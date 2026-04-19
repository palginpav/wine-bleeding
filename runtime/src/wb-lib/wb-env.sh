#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# wb-env.sh — WB_* → Wine/DXVK/VKD3D env composition.
# Pure function: wb_env_compose <prefix_path> <dist_path>
# Emits KEY=VALUE lines to stdout in stable sort order.
# Called immediately before exec; no side effects beyond stdout.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Internal: collect DXVK DLL names from the dist's dxvk component dir.
# ---------------------------------------------------------------------------
_wb_env_dxvk_dlls() {
  local dist_path="$1"
  local dxvk_dir="${dist_path}/lib/wine/dxvk/x86_64-windows"
  [[ -d "${dxvk_dir}" ]] || return 0
  local dll
  for dll in "${dxvk_dir}"/*.dll; do
    [[ -f "${dll}" ]] || continue
    basename "${dll}" .dll
  done
}

# ---------------------------------------------------------------------------
# Internal: collect VKD3D DLL names from the dist's vkd3d-proton component dir.
# ---------------------------------------------------------------------------
_wb_env_vkd3d_dlls() {
  local dist_path="$1"
  local vkd3d_dir="${dist_path}/lib/wine/vkd3d-proton/x86_64-windows"
  [[ -d "${vkd3d_dir}" ]] || return 0
  local dll
  for dll in "${vkd3d_dir}"/*.dll; do
    [[ -f "${dll}" ]] || continue
    basename "${dll}" .dll
  done
}

# ---------------------------------------------------------------------------
# Internal: collect NVAPI DLL names from the dist's nvapi component dir.
# ---------------------------------------------------------------------------
_wb_env_nvapi_dlls() {
  local dist_path="$1"
  local nvapi_dir="${dist_path}/lib/wine/nvapi/x86_64-windows"
  [[ -d "${nvapi_dir}" ]] || return 0
  local dll
  for dll in "${nvapi_dir}"/*.dll; do
    [[ -f "${dll}" ]] || continue
    basename "${dll}" .dll
  done
}

# ---------------------------------------------------------------------------
# wb_env_compose <prefix_path> <dist_path>
#
# Reads WB_* from the environment (populated by wb_config_load) and emits
# KEY=VALUE lines to stdout comprising the final Wine exec environment.
# Table-driven; no eval; validates WINEDLLOVERRIDES before emitting.
# Output is sorted alphabetically for determinism.
# ---------------------------------------------------------------------------
wb_env_compose() {
  local prefix_path="$1"
  local dist_path="$2"

  # We build pairs into a temporary file, then sort and cat.
  # This avoids the associative array + nameref pattern that shellcheck
  # cannot reason about when the array is only ever accessed via nameref.
  local _tmp_pairs
  _tmp_pairs="$(mktemp)"

  # Helper: write KEY=VALUE to the temp file
  _emit() {
    printf '%s=%s\n' "$1" "$2" >> "${_tmp_pairs}"
  }

  # --- Static paths -------------------------------------------------------
  _emit "WINEPREFIX"    "${prefix_path}"
  _emit "WINE"          "${dist_path}/bin/wine"
  _emit "WINESERVER"    "${dist_path}/bin/wineserver"
  _emit "WINELOADER"    "${dist_path}/bin/wine"
  _emit "WB_DIST_DIR"   "${dist_path}"

  # WINEDLLPATH — canonical Wine layout uses x86_64-unix and i386-unix for ELF libs.
  # We emit both unconditionally (Wine ignores absent dirs).
  _emit "WINEDLLPATH" "${dist_path}/lib/wine/x86_64-unix:${dist_path}/lib/wine/i386-unix"

  # --- WINEDEBUG ----------------------------------------------------------
  _emit "WINEDEBUG" "${WB_DEBUG_WINE:--all}"

  # --- Sync primitives (only emit when =1) --------------------------------
  if [[ "${WB_ESYNC:-0}" == "1" ]]; then
    _emit "WINEESYNC" "1"
  fi
  if [[ "${WB_FSYNC:-0}" == "1" ]]; then
    _emit "WINEFSYNC" "1"
  fi
  if [[ "${WB_NTSYNC:-0}" == "1" ]]; then
    _emit "WINENTSYNC" "1"
  fi

  # --- Staging shared memory (verbatim; default 1) -----------------------
  _emit "STAGING_SHARED_MEMORY" "${WB_STAGING_SHARED_MEMORY:-1}"

  # --- DXVK vars ----------------------------------------------------------
  _emit "DXVK_ASYNC" "${WB_DXVK_ASYNC:-1}"

  if [[ -n "${WB_DXVK_HUD:-}" ]]; then
    _emit "DXVK_HUD" "${WB_DXVK_HUD}"
  fi

  _emit "DXVK_STATE_CACHE_PATH" "${WB_DXVK_STATE_CACHE_PATH:-${WB_HOME:-}/cache/dxvk-state}"

  # --- VKD3D vars ---------------------------------------------------------
  _emit "VKD3D_SHADER_CACHE_PATH" "${WB_VKD3D_SHADER_CACHE_PATH:-${WB_HOME:-}/cache/vkd3d-shader}"

  # --- WINEDLLOVERRIDES composition (M5-R1, M5-R2) -----------------------
  local -a dll_overrides=()

  # DXVK DLLs
  if [[ "${WB_DXVK:-1}" == "1" ]]; then
    local dll_name
    while IFS= read -r dll_name; do
      [[ -n "${dll_name}" ]] || continue
      dll_overrides+=("${dll_name}=n")
    done < <(_wb_env_dxvk_dlls "${dist_path}" | sort)
  fi

  # VKD3D DLLs
  if [[ "${WB_VKD3D:-1}" == "1" ]]; then
    local dll_name
    while IFS= read -r dll_name; do
      [[ -n "${dll_name}" ]] || continue
      dll_overrides+=("${dll_name}=n")
    done < <(_wb_env_vkd3d_dlls "${dist_path}" | sort)
  fi

  # NVAPI DLLs — treat auto as 1 for MVP
  local wb_nvapi="${WB_NVAPI:-auto}"
  if [[ "${wb_nvapi}" == "1" || "${wb_nvapi}" == "auto" ]]; then
    local dll_name
    while IFS= read -r dll_name; do
      [[ -n "${dll_name}" ]] || continue
      dll_overrides+=("${dll_name}=n")
    done < <(_wb_env_nvapi_dlls "${dist_path}" | sort)
  fi

  # Extra user overrides (appended verbatim after component DLLs)
  if [[ -n "${WB_EXTRA_DLLOVERRIDES:-}" ]]; then
    dll_overrides+=("${WB_EXTRA_DLLOVERRIDES}")
  fi

  # Join with semicolon
  local winedll_str=""
  local i
  for (( i=0; i<${#dll_overrides[@]}; i++ )); do
    if [[ "${i}" -eq 0 ]]; then
      winedll_str="${dll_overrides[${i}]}"
    else
      winedll_str="${winedll_str};${dll_overrides[${i}]}"
    fi
  done

  # CRITICAL VALIDATION (M5-R2): reject if the composed string doesn't match
  # the expected DllOverrides format. Empty string is always valid.
  # Value may be empty (disabled), or one of [bns]+ (builtin, native, system).
  # Pattern: NAME=VALUE pairs joined by semicolons. Value may be empty.
  if [[ -n "${winedll_str}" ]]; then
    if ! [[ "${winedll_str}" =~ ^([A-Za-z0-9_.-]+=[bns]*;)*([A-Za-z0-9_.-]+=[bns]*)$ ]]; then
      rm -f "${_tmp_pairs}"
      wb_log_error "wb_env_compose: invalid WINEDLLOVERRIDES '${winedll_str}' (failed regex check); refusing to launch"
      return 1
    fi
  fi

  if [[ "${WB_DEBUG:-0}" == "1" ]]; then
    wb_log_info "WINEDLLOVERRIDES=${winedll_str}"
  fi

  _emit "WINEDLLOVERRIDES" "${winedll_str}"

  # Emit in stable sort order and clean up
  sort < "${_tmp_pairs}"
  rm -f "${_tmp_pairs}"
}

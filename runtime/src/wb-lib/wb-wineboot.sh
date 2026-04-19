#!/usr/bin/env bash
set -euo pipefail

wb_prefix_init() {
  local prefix_path="$1"
  local dist_path="$2"

  if [[ ! -f "${dist_path}/bin/wine" ]] || [[ ! -f "${dist_path}/bin/wineserver" ]]; then
    wb_log_error "wb_prefix_init: dist missing bin/wine or bin/wineserver at ${dist_path}"
    return 1
  fi

  local prefix_existed=0
  [[ -d "${prefix_path}" ]] && prefix_existed=1

  mkdir -p "${prefix_path}"

  # LOCK-CRITICAL: acquire lock and hold for the entire init sequence; release via trap.
  if ! wb_acquire_lock "${prefix_path}"; then
    echo "prefix busy" >&2
    return 1
  fi

  # ROLLBACK-CRITICAL: on any failure, if the prefix did not exist before init, remove it.
  _WB_INIT_PREFIX_PATH="${prefix_path}"
  _WB_INIT_PREFIX_EXISTED="${prefix_existed}"
  export _WB_INIT_PREFIX_PATH _WB_INIT_PREFIX_EXISTED

  # shellcheck disable=SC2329
  _wb_wineboot_cleanup() {
    local _ec=$?
    wb_release_lock "${_WB_INIT_PREFIX_PATH}" 2>/dev/null || true
    if [[ "${_ec}" -ne 0 && "${_WB_INIT_PREFIX_EXISTED}" -eq 0 ]]; then
      rm -rf "${_WB_INIT_PREFIX_PATH}" 2>/dev/null || true
    fi
    trap - EXIT
  }
  trap '_wb_wineboot_cleanup' EXIT

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local prefix_name
  prefix_name="$(basename "${prefix_path}")"

  local minimal_json
  minimal_json="$(jq -cn \
    --argjson schema 1 \
    --arg prefix_name "${prefix_name}" \
    --arg runtime_alias "WINE-BLEEDING" \
    --arg initialized_utc "${now_utc}" \
    --arg owner "wb-runtime" \
    --argjson pp_coexist false \
    --argjson wineboot_generation 0 \
    '{
      schema: $schema,
      prefix_name: $prefix_name,
      runtime_alias: $runtime_alias,
      initialized_utc: $initialized_utc,
      owner: $owner,
      pp_coexist: $pp_coexist,
      wineboot_generation: $wineboot_generation
    }')"
  wb_json_write_atomic "${prefix_path}/.wb_runtime" "${minimal_json}"

  wb_component_deploy_mono "${prefix_path}" "${dist_path}" >/dev/null

  "${dist_path}/bin/wineserver" -k 2>/dev/null || true
  sleep 1

  export WINEPREFIX="${prefix_path}"
  export WINEDEBUG="${WINEDEBUG:--all}"
  export WINEARCH="${WINEARCH:-win64}"

  "${dist_path}/bin/wine" wineboot --init 2>/dev/null || true
  sleep 2
  "${dist_path}/bin/wineserver" -k 2>/dev/null || true

  # VERIFY wineboot actually populated the prefix. A silent crash leaves
  # drive_c empty; writing a valid-looking sentinel over a broken prefix is
  # worse than failing fast because `wb run` (M5) would then exec into a
  # prefix that can't load any DLL.
  local has_dlls=0
  if [[ -d "${prefix_path}/drive_c/windows/system32" ]]; then
    if compgen -G "${prefix_path}/drive_c/windows/system32/*.dll" >/dev/null; then
      has_dlls=1
    fi
  fi
  if [[ "${has_dlls}" -eq 0 ]]; then
    wb_log_error "wb_prefix_init: wineboot --init produced no system32 DLLs; aborting"
    return 1
  fi

  if [[ "${WB_DXVK:-1}" != "0" ]]; then
    wb_component_deploy_dxvk "${prefix_path}" "${dist_path}" >/dev/null
  fi
  if [[ "${WB_VKD3D:-1}" != "0" ]]; then
    wb_component_deploy_vkd3d "${prefix_path}" "${dist_path}" >/dev/null
  fi
  if [[ "${WB_NVAPI:-1}" != "0" ]]; then
    wb_component_deploy_nvapi "${prefix_path}" "${dist_path}" >/dev/null
  fi
  if [[ "${WB_ICU:-1}" != "0" ]]; then
    wb_component_deploy_icu "${prefix_path}" "${dist_path}" >/dev/null
  fi

  local dll_list
  dll_list="$(_wb_wineboot_build_dll_list "${prefix_path}" "${dist_path}")"

  local user_reg="${prefix_path}/user.reg"
  if [[ -f "${user_reg}" && -n "${dll_list}" ]]; then
    wb_reg_patch_dll_overrides "${user_reg}" "${dll_list}"
  fi

  printf '%s' "WINE-BLEEDING" > "${prefix_path}/.wine_ver"

  local dist_abs
  dist_abs="$(realpath -m "${dist_path}")"

  local dist_sha=""
  if [[ -f "${dist_path}/.wb_dist_meta" ]]; then
    dist_sha="$(jq -r '.builtin_dlls_hash // ""' "${dist_path}/.wb_dist_meta" 2>/dev/null || true)"
  fi

  local mono_ver=""
  # shellcheck disable=SC2012
  mono_ver="$(ls -1d "${dist_path}/share/wine/mono"/wine-mono-* 2>/dev/null \
    | sort -V | tail -1 | xargs basename 2>/dev/null || true)"

  local runtime_sha_json="null"
  [[ -n "${dist_sha}" ]] && runtime_sha_json="\"${dist_sha}\""
  local mono_ver_json="null"
  [[ -n "${mono_ver}" ]] && mono_ver_json="\"${mono_ver}\""

  local final_json
  final_json="$(jq -cn \
    --argjson schema 1 \
    --arg prefix_name "${prefix_name}" \
    --arg runtime_alias "WINE-BLEEDING" \
    --arg runtime_target "${dist_abs}" \
    --argjson runtime_target_sha256 "${runtime_sha_json}" \
    --arg initialized_utc "${now_utc}" \
    --argjson last_launch_utc null \
    --argjson mono_version "${mono_ver_json}" \
    --argjson wineboot_generation 1 \
    --arg owner "wb-runtime" \
    --argjson pp_coexist false \
    --arg last_adopted_utc "${now_utc}" \
    '{
      schema: $schema,
      prefix_name: $prefix_name,
      runtime_alias: $runtime_alias,
      runtime_target: $runtime_target,
      runtime_target_sha256: $runtime_target_sha256,
      initialized_utc: $initialized_utc,
      last_launch_utc: $last_launch_utc,
      mono_version: $mono_version,
      wineboot_generation: $wineboot_generation,
      owner: $owner,
      pp_coexist: $pp_coexist,
      last_adopted_utc: $last_adopted_utc
    }')"
  wb_json_write_atomic "${prefix_path}/.wb_runtime" "${final_json}"

  local components_json
  components_json="$(wb_components_build_manifest "${prefix_path}" "${dist_path}")"
  wb_components_write "${prefix_path}" "${components_json}"

  wb_log_info "wb_prefix_init: prefix '${prefix_name}' initialised at ${prefix_path}"

  wb_release_lock "${prefix_path}"
  trap - EXIT
}

wb_prefix_reconcile() {
  local prefix_path="$1"

  local sentinel="${prefix_path}/.wb_runtime"
  if [[ ! -f "${sentinel}" ]]; then
    wb_log_error "wb_prefix_reconcile: no .wb_runtime at ${prefix_path}"
    return 1
  fi

  local dist_path
  dist_path="$(jq -r '.runtime_target // empty' "${sentinel}" 2>/dev/null || true)"
  if [[ -z "${dist_path}" ]]; then
    wb_log_error "wb_prefix_reconcile: .wb_runtime missing runtime_target"
    return 1
  fi
  if [[ ! -d "${dist_path}" ]]; then
    wb_log_error "wb_prefix_reconcile: runtime_target '${dist_path}' not found"
    return 1
  fi

  if [[ "${WB_DXVK:-1}" != "0" ]]; then
    wb_component_deploy_dxvk "${prefix_path}" "${dist_path}" >/dev/null
  fi
  if [[ "${WB_VKD3D:-1}" != "0" ]]; then
    wb_component_deploy_vkd3d "${prefix_path}" "${dist_path}" >/dev/null
  fi
  if [[ "${WB_NVAPI:-1}" != "0" ]]; then
    wb_component_deploy_nvapi "${prefix_path}" "${dist_path}" >/dev/null
  fi
  if [[ "${WB_ICU:-1}" != "0" ]]; then
    wb_component_deploy_icu "${prefix_path}" "${dist_path}" >/dev/null
  fi

  local components_json
  components_json="$(wb_components_build_manifest "${prefix_path}" "${dist_path}")"
  wb_components_write "${prefix_path}" "${components_json}"

  wb_log_info "wb_prefix_reconcile: reconciled ${prefix_path}"
}

_wb_wineboot_build_dll_list() {
  local prefix_path="$1"
  local dist_path="$2"
  local entries=()

  if [[ "${WB_DXVK:-1}" != "0" ]] && [[ -d "${dist_path}/lib/wine/dxvk/x86_64-windows" ]]; then
    local dll
    for dll in "${dist_path}/lib/wine/dxvk/x86_64-windows"/*.dll; do
      [[ -f "${dll}" ]] || continue
      local name
      name="$(basename "${dll}" .dll)"
      entries+=("${name}=n")
    done
  fi

  if [[ "${WB_VKD3D:-1}" != "0" ]] && [[ -d "${dist_path}/lib/wine/vkd3d-proton/x86_64-windows" ]]; then
    local dll
    for dll in "${dist_path}/lib/wine/vkd3d-proton/x86_64-windows"/*.dll; do
      [[ -f "${dll}" ]] || continue
      local name
      name="$(basename "${dll}" .dll)"
      entries+=("${name}=n")
    done
  fi

  if [[ "${WB_NVAPI:-1}" != "0" ]] && [[ -d "${dist_path}/lib/wine/nvapi/x86_64-windows" ]]; then
    local dll
    for dll in "${dist_path}/lib/wine/nvapi/x86_64-windows"/*.dll; do
      [[ -f "${dll}" ]] || continue
      local name
      name="$(basename "${dll}" .dll)"
      entries+=("${name}=n")
    done
  fi

  if [[ "${#entries[@]}" -eq 0 ]]; then
    echo ""
    return 0
  fi

  local IFS_SAVE="${IFS}"
  IFS=';'
  echo "${entries[*]}"
  IFS="${IFS_SAVE}"
}

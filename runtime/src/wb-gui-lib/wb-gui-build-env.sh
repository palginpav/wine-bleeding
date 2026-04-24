#!/usr/bin/env bash
# runtime/src/wb-gui-lib/wb-gui-build-env.sh — build-environment preflight + fallback dispatch
#
# Public API (sourced by wb-gui and wb-gui-lib callers):
#
#   wb_gui_build_env_preflight <build_type>
#       Run wb-preflight.py for the given build type (components|dist).
#       Silent pass-through (return 0) when all tools OK.
#       Returns 1 with $WB_PREFLIGHT_JSON_FILE set when tools are missing/old.
#       Returns 2 on argument error, 99 on internal error.
#       Callers (W4) read $WB_PREFLIGHT_JSON_FILE to render the dialog.
#
#   wb_gui_build_env_run_source_build <slug> [<floor>]
#       Dispatch source-build fallback for the given slug:
#         wb-build-glslang       → tools/build-glslang.sh --progress-fd $WB_BUILD_PROGRESS_FD
#         build-mingw-from-source → tools/build-full-wine-deps.sh --only-mingw --build-mingw-from-source
#         pip-install-meson      → python3 -m pip install --user "meson>=${floor}"
#       Returns the exit code of the invoked command.
#
# Environment consumed:
#   WB_HOME            — wine-bleeding home (required)
#   WB_TOOLS_DIR       — path to tools/ dir; defaults to WINE_ROOT/tools
#   WB_BUILD_PROGRESS_FD — fd for Phase-B events (optional; falls back to stderr)
#   WB_WINE_SOURCE_ROOT — used when WB_TOOLS_DIR is not set (dev-tree mode)
#
# Not sourced at script start — this file is a library. No set -euo pipefail at
# top level; individual functions set local errexit as needed.

# Guard against double-source
if [[ "${_WB_GUI_BUILD_ENV_LOADED:-0}" == "1" ]]; then
  return 0
fi
_WB_GUI_BUILD_ENV_LOADED=1

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _wgbe_tools_dir — resolve the tools/ directory
_wgbe_tools_dir() {
  if [[ -n "${WB_TOOLS_DIR:-}" ]]; then
    printf '%s' "${WB_TOOLS_DIR}"
    return
  fi
  # Derive from this file's location: runtime/src/wb-gui-lib/ → ../../.. → root → tools/
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s' "${self_dir}/../../../tools"
}

# _wgbe_preflight_bin — resolve wb-preflight.py
_wgbe_preflight_bin() {
  # Installed: /usr/lib/wine-bleeding/libexec/wb-preflight.py
  # Dev tree:  runtime/libexec/wb-preflight.py (sibling of runtime/src/)
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local candidates=(
    "${self_dir}/../../libexec/wb-preflight.py"
    "/usr/lib/wine-bleeding/libexec/wb-preflight.py"
    "/usr/local/lib/wine-bleeding/libexec/wb-preflight.py"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "${c}" ]]; then
      printf '%s' "${c}"
      return 0
    fi
  done
  return 1
}

# _wgbe_emit — emit an event via WB_BUILD_PROGRESS_FD or stderr
_wgbe_emit() {
  local prefix="$1"
  local msg="$2"
  if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
    printf '%s: %s\n' "${prefix}" "${msg}" >&"${WB_BUILD_PROGRESS_FD}"
  else
    printf '%s: %s\n' "${prefix}" "${msg}" >&2
  fi
}

# ---------------------------------------------------------------------------
# wb_gui_build_env_preflight <build_type>
#
# Sets WB_PREFLIGHT_JSON_FILE to a temp file path containing the JSON output.
# Caller is responsible for removing the temp file when done.
# ---------------------------------------------------------------------------
wb_gui_build_env_preflight() {
  local build_type="${1:-components}"

  if [[ "${build_type}" != "components" && "${build_type}" != "dist" ]]; then
    _wgbe_emit "ERROR" "wb_gui_build_env_preflight: unknown build_type '${build_type}' (expected: components|dist)"
    return 2
  fi

  local preflight_bin
  if ! preflight_bin="$(_wgbe_preflight_bin)"; then
    _wgbe_emit "ERROR" "wb-preflight.py not found. What happened: the preflight detector is missing. Why: installation may be incomplete. Next action: reinstall wine-bleeding or run from the source tree."
    return 99
  fi

  # Write JSON to a temp file so the caller (W4 GUI) can parse it independently
  local json_file
  json_file="$(mktemp /tmp/wb-preflight-XXXXXX.json)"
  export WB_PREFLIGHT_JSON_FILE="${json_file}"

  local preflight_rc=0
  python3 "${preflight_bin}" --json --build-type "${build_type}" \
    > "${json_file}" 2>/tmp/wb-preflight-stderr-$$.tmp \
    || preflight_rc=$?

  # Surface any stderr from preflight (parse errors, etc.)
  if [[ -s /tmp/wb-preflight-stderr-$$.tmp ]]; then
    while IFS= read -r line; do
      _wgbe_emit "WARN" "${line}"
    done < /tmp/wb-preflight-stderr-$$.tmp
  fi
  rm -f /tmp/wb-preflight-stderr-$$.tmp

  case "${preflight_rc}" in
    0)
      # All tools OK — silent pass-through (BLK-1 resolution)
      return 0
      ;;
    1)
      # At least one tool missing or too old — JSON still in file for W4 to render
      return 1
      ;;
    2)
      _wgbe_emit "ERROR" "wb-preflight.py argument error (exit 2). What happened: invalid --build-type or tool name. Why: internal caller bug. Next action: file a bug report."
      rm -f "${json_file}"
      return 2
      ;;
    *)
      _wgbe_emit "ERROR" "wb-preflight.py internal error (exit ${preflight_rc}). What happened: unexpected exception in the detector. Why: see stderr log. Next action: run wb-preflight.py --pretty manually to reproduce."
      rm -f "${json_file}"
      return 99
      ;;
  esac
}

# ---------------------------------------------------------------------------
# wb_gui_build_env_run_source_build <slug> [<meson_floor>]
#
# Dispatches the appropriate source-build command for the given fallback slug.
# Progress events go to WB_BUILD_PROGRESS_FD when set.
# Returns the exit code of the underlying command.
# ---------------------------------------------------------------------------
wb_gui_build_env_run_source_build() {
  local slug="${1:-}"
  local meson_floor="${2:-0.60.0}"

  if [[ -z "${slug}" ]]; then
    _wgbe_emit "ERROR" "wb_gui_build_env_run_source_build: slug argument required"
    return 64
  fi

  local tools_dir
  tools_dir="$(_wgbe_tools_dir)"

  case "${slug}" in
    wb-build-glslang)
      local glslang_script="${tools_dir}/build-glslang.sh"
      if [[ ! -x "${glslang_script}" ]]; then
        _wgbe_emit "ERROR" "build-glslang.sh not found at ${glslang_script}. What happened: script missing. Why: installation incomplete. Next action: reinstall wine-bleeding."
        return 66
      fi
      # Export user-writable WB_HOME so build-glslang.sh routes its src/build/install
      # trees under $WB_HOME/build-deps/ instead of WINE_ROOT (which is the read-only
      # install prefix /usr/lib/wine-bleeding when invoked from the installed package).
      local _wb_home_export
      _wb_home_export="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
      mkdir -p "${_wb_home_export}" 2>/dev/null || true
      export WB_HOME="${_wb_home_export}"
      _wgbe_emit "LOG" "Starting glslang source build via ${glslang_script} under ${WB_HOME}/build-deps"
      local args=()
      if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
        args+=(--progress-fd "${WB_BUILD_PROGRESS_FD}")
      fi
      "${glslang_script}" "${args[@]}"
      return $?
      ;;

    build-mingw-from-source)
      local deps_script="${tools_dir}/build-full-wine-deps.sh"
      if [[ ! -x "${deps_script}" ]]; then
        _wgbe_emit "ERROR" "build-full-wine-deps.sh not found at ${deps_script}. What happened: script missing. Why: installation incomplete. Next action: reinstall wine-bleeding."
        return 66
      fi
      # Resolve + export a user-writable WB_HOME so the child build-full-wine-deps.sh
      # routes its build-deps/ workspace under $WB_HOME (e.g. ~/.local/share/wine-bleeding/build-deps)
      # instead of the read-only install prefix (/usr/lib/wine-bleeding/build-deps).
      local _wb_home_export
      _wb_home_export="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
      mkdir -p "${_wb_home_export}" 2>/dev/null || true
      export WB_HOME="${_wb_home_export}"
      # Strategy: default to musl.cc pre-built download (~130 MB, ~2-5 min, near-100%
      # success) rather than source compile (~45 min, fragile — modern host GCC often
      # fails to bootstrap older MinGW GCC, as observed on ALT / Fedora / Arch). The
      # script's `--only-mingw` without `--build-mingw-from-source` takes the musl.cc
      # path. Source build is available via WB_MINGW_PREFER_SOURCE=1 for users whose
      # glibc is too old for musl.cc binaries or who are offline.
      local -a _mingw_args=(--only-mingw)
      if [[ "${WB_MINGW_PREFER_SOURCE:-0}" == "1" ]]; then
        _mingw_args+=(--build-mingw-from-source)
        _wgbe_emit "LOG" "Starting MinGW-w64 source build (30–60 min typical) under ${WB_HOME}/build-deps"
      else
        _wgbe_emit "LOG" "Installing MinGW-w64 (downloading pre-built ~130 MB from musl.cc) into ${WB_HOME}/build-deps"
      fi
      # build-full-wine-deps.sh is a legacy script (no Phase-B event emission).
      # Route its stdout+stderr into the progress fd so the live log-tail sees
      # what's happening — the event reader has a fallthrough for unprefixed
      # lines. Without this, the dialog freezes after our startup LOG line
      # because the script's output is only visible in a discarded file.
      # Use stdbuf -oL to force line buffering so progress appears in real time.
      local _mingw_rc=0
      if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
        if command -v stdbuf >/dev/null 2>&1; then
          stdbuf -oL -eL "${deps_script}" "${_mingw_args[@]}" >&"${WB_BUILD_PROGRESS_FD}" 2>&1 || _mingw_rc=$?
        else
          "${deps_script}" "${_mingw_args[@]}" >&"${WB_BUILD_PROGRESS_FD}" 2>&1 || _mingw_rc=$?
        fi
      else
        "${deps_script}" "${_mingw_args[@]}" || _mingw_rc=$?
      fi
      return "${_mingw_rc}"
      ;;

    pip-install-meson)
      _wgbe_emit "LOG" "Installing meson via pip (user-level, no sudo): meson>=${meson_floor}"
      python3 -m pip install --user --upgrade "meson>=${meson_floor}"
      local pip_rc=$?
      if [[ "${pip_rc}" -ne 0 ]]; then
        _wgbe_emit "ERROR" "pip install meson failed (exit ${pip_rc}). What happened: pip could not install meson. Why: see output above. Next action: run 'python3 -m pip install --user meson' in a terminal to see the full error."
        return "${pip_rc}"
      fi
      # Check for PATH gap: meson may have installed to ~/.local/bin which may not be on PATH
      if ! command -v meson &>/dev/null; then
        local local_bin="${HOME}/.local/bin"
        _wgbe_emit "WARN" "meson installed to ${local_bin}/meson but ${local_bin} is not on PATH. Add 'export PATH=\"${local_bin}:\$PATH\"' to your shell startup file, or log out and back in."
      fi
      return 0
      ;;

    *)
      _wgbe_emit "ERROR" "Unknown source-build slug: '${slug}'. What happened: unrecognised fallback slug. Why: caller passed an unexpected value. Next action: file a bug report with the slug name."
      return 64
      ;;
  esac
}

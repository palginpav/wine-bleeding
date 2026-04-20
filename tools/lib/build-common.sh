#!/usr/bin/env bash
# tools/lib/build-common.sh — shared helpers for build-component.sh and full-build.sh
# Sourced only; never executed directly.
#
# Public API:
#   bc_check_env            — verify required build tools; ERROR+exit on missing
#   bc_check_glslang        — warn if glslang/glslangValidator absent
#   bc_check_vulkan         — warn if vulkan-headers absent
#   bc_resolve_mingw        — find/download MinGW; export PATH; set MINGW_BIN / BUILD_32
#   bc_strip_builtin_marker <dll> — zero Wine builtin marker (Authenticode-safe)
#   bc_emit_progress <pct> <msg>  — PROGRESS: event on $WB_BUILD_PROGRESS_FD or stderr
#   bc_emit_log <msg>             — LOG:      event
#   bc_emit_warn <msg>            — WARN:     event
#   bc_emit_error <msg>           — ERROR:    event
#   bc_acquire_build_lock [timeout_secs]  — flock on $WB_HOME/.build-lock; exit 71 on fail
#   bc_release_build_lock                 — release build lock fd
#   bc_check_deps_upstream <component>    — git-fetch and clear .rev if outdated
#   bc_need_deps_build <rev_file> <repo_dir> <required_dlls...>  — decide if build needed
#   bc_save_deps_rev <rev_file> <repo_dir>                       — record HEAD rev
#
# Callers must set:
#   WB_HOME          — wb home directory (for build lock path)
#   WINE_ROOT        — source tree root
#   DEPS_DIR         — build-deps directory (default: $WINE_ROOT/build-deps)
#   WB_BUILD_PROGRESS_FD  — optional: fd number for progress events
#   FORCE_REBUILD_DEPS    — optional: 1 to skip rev-cache check

set -euo pipefail

# Guard against double-source
if [[ "${_BC_COMMON_LOADED:-0}" == "1" ]]; then
  return 0
fi
_BC_COMMON_LOADED=1

# ---------------------------------------------------------------------------
# Build lock fd (file descriptor for flock; allocated dynamically)
# ---------------------------------------------------------------------------
_BC_BUILD_LOCK_FD=""

# ---------------------------------------------------------------------------
# Event emission helpers
# Writes to $WB_BUILD_PROGRESS_FD when set; falls back to stderr.
# ---------------------------------------------------------------------------
bc_emit_progress() {
  local pct="${1:-0}"
  local msg="${2:-}"
  local line="PROGRESS: ${pct} ${msg}"
  if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
    printf '%s\n' "${line}" >&"${WB_BUILD_PROGRESS_FD}"
  else
    printf '%s\n' "${line}" >&2
  fi
}

bc_emit_log() {
  local msg="${1:-}"
  local line="LOG: ${msg}"
  if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
    printf '%s\n' "${line}" >&"${WB_BUILD_PROGRESS_FD}"
  else
    printf '%s\n' "${line}" >&2
  fi
}

bc_emit_warn() {
  local msg="${1:-}"
  local line="WARN: ${msg}"
  if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
    printf '%s\n' "${line}" >&"${WB_BUILD_PROGRESS_FD}"
  else
    printf '%s\n' "${line}" >&2
  fi
}

bc_emit_error() {
  local msg="${1:-}"
  local line="ERROR: ${msg}"
  if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
    printf '%s\n' "${line}" >&"${WB_BUILD_PROGRESS_FD}"
  else
    printf '%s\n' "${line}" >&2
  fi
}

# ---------------------------------------------------------------------------
# bc_check_env — verify mandatory build tools; bc_emit_error + exit 66 on failure
# ---------------------------------------------------------------------------
bc_check_env() {
  local required="meson ninja gcc g++ make flex bison pkg-config"
  local missing=""
  local cmd
  for cmd in ${required}; do
    if ! command -v "${cmd}" &>/dev/null; then
      missing="${missing} ${cmd}"
    fi
  done
  if [[ -n "${missing}" ]]; then
    bc_emit_error "Required build tools missing:${missing}"
    echo "  Install: gcc gcc-c++ make flex bison meson ninja-build pkg-config" >&2
    exit 66
  fi
}

# ---------------------------------------------------------------------------
# bc_check_glslang — warn only if glslang missing
# ---------------------------------------------------------------------------
bc_check_glslang() {
  local found=0
  local cmd
  for cmd in glslangValidator glslang; do
    if command -v "${cmd}" &>/dev/null; then
      found=1
      break
    fi
  done
  if [[ "${found}" -eq 0 ]]; then
    bc_emit_warn "glslang/glslangValidator not found. DXVK/VKD3D require it to build."
  fi
}

# ---------------------------------------------------------------------------
# bc_check_vulkan — warn only if vulkan-headers missing
# ---------------------------------------------------------------------------
bc_check_vulkan() {
  if ! pkg-config --exists vulkan 2>/dev/null && [[ ! -f /usr/include/vulkan/vulkan.h ]]; then
    bc_emit_warn "vulkan-headers not found. Install vulkan-headers for DXVK/VKD3D."
  fi
}

# ---------------------------------------------------------------------------
# bc_resolve_mingw — find/download x86_64 and optionally i686 MinGW.
# Exports: MINGW_BIN (x86_64 bin dir), BUILD_32 (1 if i686 available).
# Sets PATH to include found toolchains.
# Exits 66 if MinGW cannot be obtained.
# ---------------------------------------------------------------------------
bc_resolve_mingw() {
  local deps_dir="${DEPS_DIR:-${WINE_ROOT}/build-deps}"
  local mingw_cross_dir="${deps_dir}/x86_64-w64-mingw32-cross"
  local mingw32_cross_dir="${deps_dir}/i686-w64-mingw32-cross"
  local build_mingw_from_source="${BUILD_MINGW_FROM_SOURCE:-0}"

  MINGW_BIN=""

  # Priority 1: system PATH
  if command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    MINGW_BIN="$(dirname "$(command -v x86_64-w64-mingw32-gcc)")"
  elif command -v mingw64-gcc &>/dev/null; then
    MINGW_BIN="$(dirname "$(command -v mingw64-gcc)")"
  fi

  # Priority 2: previously downloaded/built
  if [[ -z "${MINGW_BIN}" ]] && [[ -x "${mingw_cross_dir}/bin/x86_64-w64-mingw32-gcc" ]]; then
    MINGW_BIN="${mingw_cross_dir}/bin"
  fi
  if [[ -z "${MINGW_BIN}" ]] && [[ -x "${deps_dir}/mingw64-cross/bin/x86_64-w64-mingw32-gcc" ]]; then
    MINGW_BIN="${deps_dir}/mingw64-cross/bin"
  fi

  if [[ -n "${MINGW_BIN}" ]]; then
    export PATH="${MINGW_BIN}:${PATH}"
    bc_emit_log "MinGW (x64): ${MINGW_BIN}/x86_64-w64-mingw32-gcc"
  else
    if [[ "${build_mingw_from_source}" -eq 1 ]]; then
      _bc_build_mingw_from_source "${deps_dir}"
    else
      _bc_download_mingw "${deps_dir}" "${mingw_cross_dir}"
    fi
  fi

  if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    bc_emit_error "MinGW x86_64 not available after resolution"
    exit 66
  fi

  # i686 (optional)
  BUILD_32=0
  _bc_resolve_mingw32 "${deps_dir}" "${mingw32_cross_dir}"
  if command -v i686-w64-mingw32-gcc &>/dev/null; then
    BUILD_32=1
  fi
  export MINGW_BIN BUILD_32
}

_bc_build_mingw_from_source() {
  local deps_dir="$1"
  local mingw_deps="gcc g++ make bison flex git makeinfo m4 bzip2 curl diff"
  local missing="" ex
  for ex in ${mingw_deps}; do
    if ! command -v "${ex}" &>/dev/null; then missing="${missing} ${ex}"; fi
  done
  if [[ -n "${missing}" ]]; then
    bc_emit_error "Cannot build MinGW from source; missing:${missing}"
    exit 66
  fi
  bc_emit_log "Building MinGW-w64 from source (30-60 min)..."
  if [[ ! -d "${deps_dir}/mingw-w64-build" ]]; then
    git clone --depth 1 https://github.com/Zeranoe/mingw-w64-build.git "${deps_dir}/mingw-w64-build"
  fi
  mkdir -p "${deps_dir}/mingw-build"
  if [[ ! -x "${deps_dir}/mingw64-cross/bin/x86_64-w64-mingw32-gcc" ]]; then
    "${deps_dir}/mingw-w64-build/mingw-w64-build" x86_64 i686 \
      -r "${deps_dir}/mingw-build" \
      -p "${deps_dir}/mingw64-cross" \
      -j "$(nproc 2>/dev/null || echo 2)" \
      || { bc_emit_error "MinGW from-source build failed"; exit 66; }
  fi
  MINGW_BIN="${deps_dir}/mingw64-cross/bin"
  export PATH="${MINGW_BIN}:${PATH}"
}

_bc_download_mingw() {
  local deps_dir="$1"
  local mingw_cross_dir="$2"
  bc_emit_log "Downloading pre-built MinGW from musl.cc (~130 MB)..."
  local tgz="${deps_dir}/x86_64-w64-mingw32-cross.tgz"
  if [[ ! -f "${tgz}" ]]; then
    (cd "${deps_dir}" && curl -fL -o x86_64-w64-mingw32-cross.tgz "https://musl.cc/x86_64-w64-mingw32-cross.tgz") \
      || (cd "${deps_dir}" && wget -O x86_64-w64-mingw32-cross.tgz "https://musl.cc/x86_64-w64-mingw32-cross.tgz") \
      || { bc_emit_error "Failed to download MinGW"; exit 66; }
  fi
  if [[ ! -x "${mingw_cross_dir}/bin/x86_64-w64-mingw32-gcc" ]]; then
    (cd "${deps_dir}" && tar -xzf x86_64-w64-mingw32-cross.tgz) \
      || { bc_emit_error "MinGW extraction failed"; exit 66; }
  fi
  if [[ ! -x "${mingw_cross_dir}/bin/x86_64-w64-mingw32-gcc" ]]; then
    bc_emit_error "MinGW not found after extraction at ${mingw_cross_dir}/bin"
    exit 66
  fi
  export PATH="${mingw_cross_dir}/bin:${PATH}"
  MINGW_BIN="${mingw_cross_dir}/bin"
}

_bc_resolve_mingw32() {
  local deps_dir="$1"
  local mingw32_cross_dir="$2"

  if command -v i686-w64-mingw32-gcc &>/dev/null; then
    return 0
  fi

  # Zeranoe combined build (both arches in mingw64-cross)
  if [[ -x "${deps_dir}/mingw64-cross/bin/i686-w64-mingw32-gcc" ]]; then
    return 0  # Already in PATH from x64 resolution
  fi

  # Separate i686 cross build
  if [[ -x "${deps_dir}/mingw32-cross/bin/i686-w64-mingw32-gcc" ]]; then
    export PATH="${deps_dir}/mingw32-cross/bin:${PATH}"
    bc_emit_log "MinGW (i686): ${deps_dir}/mingw32-cross/bin"
    return 0
  fi

  # musl.cc fallback for i686
  if [[ -x "${mingw32_cross_dir}/bin/i686-w64-mingw32-gcc" ]]; then
    export PATH="${mingw32_cross_dir}/bin:${PATH}"
    return 0
  fi

  # Try downloading musl.cc i686
  local tgz="${deps_dir}/i686-w64-mingw32-cross.tgz"
  if [[ ! -f "${tgz}" ]]; then
    if ! (cd "${deps_dir}" && curl -fL -o i686-w64-mingw32-cross.tgz "https://musl.cc/i686-w64-mingw32-cross.tgz" 2>/dev/null); then
      bc_emit_log "i686 MinGW not available; 32-bit builds will be skipped"
      return 0
    fi
  fi
  if [[ ! -x "${mingw32_cross_dir}/bin/i686-w64-mingw32-gcc" ]]; then
    (cd "${deps_dir}" && tar -xzf i686-w64-mingw32-cross.tgz 2>/dev/null) || true
  fi
  if [[ -x "${mingw32_cross_dir}/bin/i686-w64-mingw32-gcc" ]]; then
    export PATH="${mingw32_cross_dir}/bin:${PATH}"
    bc_emit_log "MinGW (i686): ${mingw32_cross_dir}/bin (musl.cc)"
  fi
}

# ---------------------------------------------------------------------------
# bc_strip_builtin_marker <dll>
# Zeros the Wine builtin DLL marker at offset 0x40, with Authenticode guard.
# Uses canonical implementation from wb-lib/wb-components.sh.
# ---------------------------------------------------------------------------
bc_strip_builtin_marker() {
  local dll_path="$1"
  python3 - "${dll_path}" <<'PYEOF'
import sys, struct

path = sys.argv[1]
try:
    with open(path, 'r+b') as f:
        f.seek(0x3C)
        e_lfanew = struct.unpack('<I', f.read(4))[0]

        f.seek(e_lfanew + 4 + 20)
        magic = struct.unpack('<H', f.read(2))[0]
        if magic == 0x10B:      # PE32
            sec_dir_offset = e_lfanew + 24 + 128
            num_rva_offset = e_lfanew + 24 + 92
        elif magic == 0x20B:    # PE32+
            sec_dir_offset = e_lfanew + 24 + 144
            num_rva_offset = e_lfanew + 24 + 108
        else:
            sys.exit(1)

        f.seek(num_rva_offset)
        num_rva_and_sizes = struct.unpack('<I', f.read(4))[0]
        if num_rva_and_sizes < 5:
            sys.exit(1)

        f.seek(sec_dir_offset)
        sec_va = struct.unpack('<I', f.read(4))[0]
        if sec_va != 0:
            sys.exit(1)

        f.seek(0x40)
        if f.read(16) != b'Wine builtin DLL':
            sys.exit(0)

        f.seek(0x40)
        f.write(b'\x00' * 16)
except (OSError, struct.error):
    sys.exit(2)
PYEOF
}

# ---------------------------------------------------------------------------
# bc_acquire_build_lock [timeout_secs]
# Acquires exclusive flock on $WB_HOME/.build-lock; exits 71 on failure.
# ---------------------------------------------------------------------------
bc_acquire_build_lock() {
  local timeout="${1:-0}"
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
  local lockfile="${wb_home}/.build-lock"
  mkdir -p "${wb_home}"
  # shellcheck disable=SC2094
  exec {_BC_BUILD_LOCK_FD}>"${lockfile}"
  if [[ "${timeout}" -gt 0 ]]; then
    if ! flock -x -w "${timeout}" "${_BC_BUILD_LOCK_FD}" 2>/dev/null; then
      bc_emit_error "Build lock held by another process (waited ${timeout}s)"
      exec {_BC_BUILD_LOCK_FD}>&-
      exit 71
    fi
  else
    if ! flock -x -n "${_BC_BUILD_LOCK_FD}" 2>/dev/null; then
      bc_emit_error "Build lock held by another process"
      exec {_BC_BUILD_LOCK_FD}>&-
      exit 71
    fi
  fi
}

# ---------------------------------------------------------------------------
# bc_release_build_lock — release the build lock fd
# ---------------------------------------------------------------------------
bc_release_build_lock() {
  if [[ -n "${_BC_BUILD_LOCK_FD}" ]]; then
    exec {_BC_BUILD_LOCK_FD}>&- 2>/dev/null || true
    _BC_BUILD_LOCK_FD=""
  fi
}

# ---------------------------------------------------------------------------
# bc_check_deps_upstream <component>
# Fetches upstream for a component repo and clears .rev if outdated.
# component: dxvk | vkd3d | nvapi
# ---------------------------------------------------------------------------
bc_check_deps_upstream() {
  local component="$1"
  local deps_dir="${DEPS_DIR:-${WINE_ROOT}/build-deps}"
  local repo_dir rev_file name

  case "${component}" in
    dxvk)  name="dxvk";       rev_file="${deps_dir}/.dxvk-rev"  ;;
    vkd3d) name="vkd3d-proton"; rev_file="${deps_dir}/.vkd3d-rev" ;;
    nvapi) name="dxvk-nvapi"; rev_file="${deps_dir}/.nvapi-rev"  ;;
    *) bc_emit_error "bc_check_deps_upstream: unknown component '${component}'"; exit 64 ;;
  esac

  repo_dir="${deps_dir}/${name}"
  [[ ! -d "${repo_dir}/.git" ]] && return 0
  [[ ! -f "${rev_file}" ]] && return 0

  (cd "${repo_dir}" && git fetch --quiet 2>/dev/null) || true
  local origin_ref
  origin_ref=$(git -C "${repo_dir}" rev-parse refs/remotes/origin/HEAD 2>/dev/null) \
    || origin_ref=$(git -C "${repo_dir}" rev-parse origin/master 2>/dev/null) \
    || origin_ref=$(git -C "${repo_dir}" rev-parse origin/main 2>/dev/null) \
    || true
  [[ -z "${origin_ref}" ]] && return 0

  local saved
  saved=$(tr -d '\n\r' < "${rev_file}" 2>/dev/null || true)
  [[ -z "${saved}" ]] && return 0

  if [[ "${saved}" != "${origin_ref}" ]]; then
    bc_emit_log "Upstream updates detected for ${name}; will rebuild"
    rm -f "${rev_file}"
  fi
}

# ---------------------------------------------------------------------------
# bc_need_deps_build <rev_file> <repo_dir> <required_dlls...>
# Returns 0 (build needed) or 1 (cache hit, skip build).
# ---------------------------------------------------------------------------
bc_need_deps_build() {
  local rev_file="$1"
  local repo_dir="$2"
  shift 2
  local required_dlls=("$@")
  local force="${FORCE_REBUILD_DEPS:-0}"

  [[ "${force}" -eq 1 ]] && return 0
  [[ ! -d "${repo_dir}" ]] && return 0

  local current_rev
  current_rev=$(git -C "${repo_dir}" rev-parse HEAD 2>/dev/null) || return 0
  [[ -z "${current_rev}" ]] && return 0

  if [[ -f "${rev_file}" ]] && [[ "$(tr -d '\n\r' < "${rev_file}")" == "${current_rev}" ]]; then
    local f
    for f in "${required_dlls[@]}"; do
      [[ -f "${f}" ]] || return 0
    done
    return 1  # cache hit
  fi
  return 0  # build needed
}

# ---------------------------------------------------------------------------
# bc_save_deps_rev <rev_file> <repo_dir> — record HEAD rev for cache
# ---------------------------------------------------------------------------
bc_save_deps_rev() {
  local rev_file="$1"
  local repo_dir="$2"
  git -C "${repo_dir}" rev-parse HEAD 2>/dev/null > "${rev_file}" || true
}

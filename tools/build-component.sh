#!/usr/bin/env bash
# tools/build-component.sh — per-component builder for DXVK / VKD3D-Proton / DXVK-NVAPI
#
# Usage:
#   tools/build-component.sh \
#       --component {dxvk|vkd3d|nvapi} \
#       --target-dist /absolute/path/to/dist/WINE-BLEEDING-NNNN \
#       [--force-rebuild] \
#       [--progress-fd N] \
#       [--build-mingw-from-source] \
#       [--no-bundle-system-libs] \
#       [--copy-native-from=DIR]
#
# Exit codes:
#   0  — success
#   2  — cancelled by user (SIGTERM received, staging cleaned)
#   64 — usage error / unknown component / invalid flag
#   65 — invalid --target-dist (nonexistent, outside $WB_HOME/dist/, or not writable)
#   66 — environment failure (missing tools, MinGW unavailable)
#   67 — source failure (git clone/fetch failed)
#   68 — build failure (meson/ninja non-zero)
#   69 — staging failure (expected DLLs not produced)
#   70 — swap failure (atomic mv -T failed)
#   71 — lock failure (build lock already held)
#   99 — internal error
#
# Environment:
#   WB_WINE_SOURCE_ROOT  — path to a wine-bleeding source tree (holds
#                          build-deps/ and tools/widl/). Required when running
#                          from an installed package; defaults to the
#                          script-relative root in the dev tree.
#   WB_BUILD_DEPS_DIR    — explicit build-deps path (overrides the default
#                          derived from WB_WINE_SOURCE_ROOT).

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/build-common.sh
source "${WINE_ROOT}/tools/lib/build-common.sh"

# When this script is shipped in an installed package (under
# /usr/lib/wine-bleeding/tools/), WINE_ROOT resolves to /usr/lib/wine-bleeding
# which does NOT contain build-deps/ or tools/widl/. Users with a wine-bleeding
# source tree can point us at it via WB_WINE_SOURCE_ROOT so the installed
# driver can compile DXVK/VKD3D-Proton/DXVK-NVAPI against the source tree.
# If unset, we fall back to the script-relative WINE_ROOT (works in dev).
WB_WINE_SOURCE_ROOT="${WB_WINE_SOURCE_ROOT:-${WINE_ROOT}}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
COMPONENT=""
TARGET_DIST=""
FORCE_REBUILD_DEPS=0
BUILD_MINGW_FROM_SOURCE=0
PROGRESS_FD=""
HELP=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --component)
      [[ -n "${2:-}" ]] || { echo "build-component: --component requires a value" >&2; exit 64; }
      COMPONENT="$2"; shift ;;
    --component=*)
      COMPONENT="${1#--component=}" ;;
    --target-dist)
      [[ -n "${2:-}" ]] || { echo "build-component: --target-dist requires a value" >&2; exit 64; }
      TARGET_DIST="$2"; shift ;;
    --target-dist=*)
      TARGET_DIST="${1#--target-dist=}" ;;
    --force-rebuild)
      FORCE_REBUILD_DEPS=1 ;;
    --build-mingw-from-source)
      BUILD_MINGW_FROM_SOURCE=1 ;;
    --no-bundle-system-libs|--copy-native-from=*)
      : # accepted for CLI parity; not used in per-component builds
      ;;
    --progress-fd)
      [[ -n "${2:-}" ]] || { echo "build-component: --progress-fd requires a value" >&2; exit 64; }
      PROGRESS_FD="$2"; shift ;;
    --progress-fd=*)
      PROGRESS_FD="${1#--progress-fd=}" ;;
    --help|-h)
      HELP=1 ;;
    *)
      echo "build-component: unknown argument: $1" >&2
      echo "  Usage: $0 --component {dxvk|vkd3d|nvapi|mangohud|vkbasalt|optiscaler} --target-dist <path> [options]" >&2
      exit 64 ;;
  esac
  shift
done

if [[ "${HELP}" -eq 1 ]]; then
  cat <<'EOF'
Usage: tools/build-component.sh --component COMP --target-dist PATH [OPTIONS]

Build a single Wine GPU component into an existing native dist, using
build-to-sibling staging + atomic swap so the dist stays usable during rebuild.

Required:
  --component {dxvk|vkd3d|nvapi|mangohud|vkbasalt|optiscaler}
      Component to build. Overlay components (mangohud, vkbasalt, optiscaler)
      install to $WB_HOME/overlays/ via fetch-overlay.sh, not into --target-dist.

  --target-dist PATH
      Absolute path to an existing native dist dir (must be under $WB_HOME/dist/).

Options:
  --force-rebuild
      Skip upstream-rev cache check; always rebuild.
  --progress-fd N
      File descriptor to receive machine-readable PROGRESS:/LOG:/WARN:/ERROR: events.
      Default: events go to stderr.
  --build-mingw-from-source
      Build MinGW toolchain from source instead of downloading from musl.cc.
  --no-bundle-system-libs
      Accepted for CLI parity; no effect in per-component mode.
  --copy-native-from=DIR
      Accepted for CLI parity; no effect in per-component mode.
  --help, -h
      Show this message.

Exit codes:
  0  success
  2  cancelled (SIGTERM)
  64 usage error
  65 invalid --target-dist
  66 environment failure
  67 source fetch failure
  68 build failure
  69 staging/DLL verification failure
  70 atomic swap failure
  71 build lock already held
  99 internal error
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# Validate required args
# ---------------------------------------------------------------------------
if [[ -z "${COMPONENT}" ]]; then
  echo "build-component: --component is required" >&2
  exit 64
fi

case "${COMPONENT}" in
  dxvk|vkd3d|nvapi) ;;
  mangohud|vkbasalt|optiscaler) ;;
  *)
    bc_emit_error "Unknown component '${COMPONENT}' (expected: dxvk, vkd3d, nvapi, mangohud, vkbasalt, optiscaler)"
    exit 64 ;;
esac

# ---------------------------------------------------------------------------
# Overlay components — delegate to fetch-overlay.sh
# These install to $WB_HOME/overlays/, not into --target-dist.
# They do NOT require --target-dist; any provided value is silently ignored.
# ---------------------------------------------------------------------------
_bc_run_overlay_component() {
  local overlay_name="$1"
  local fetcher="${WINE_ROOT}/tools/fetch-overlay.sh"

  if [[ ! -x "${fetcher}" ]]; then
    bc_emit_error "fetch-overlay.sh not found at ${fetcher}"
    exit 99
  fi

  local version="${_BC_OVERLAY_VERSION:-latest}"
  local fetch_args=(
    --overlay "${overlay_name}"
    --version "${version}"
  )

  if [[ -n "${WB_BUILD_PROGRESS_FD:-}" ]]; then
    fetch_args+=(--progress-fd "${WB_BUILD_PROGRESS_FD}")
  fi

  bc_emit_log "Delegating to fetch-overlay.sh for overlay component '${overlay_name}'"
  bc_emit_log "Note: overlay components install to \$WB_HOME/overlays/, not to a dist"
  "${fetcher}" "${fetch_args[@]}"
}

case "${COMPONENT}" in
  mangohud|vkbasalt|optiscaler)
    _bc_run_overlay_component "${COMPONENT}"
    exit $?
    ;;
esac

if [[ -z "${TARGET_DIST}" ]]; then
  bc_emit_error "--target-dist is required"
  exit 64
fi

# ---------------------------------------------------------------------------
# Open progress fd if requested
# ---------------------------------------------------------------------------
export WB_BUILD_PROGRESS_FD="${PROGRESS_FD:-}"
export FORCE_REBUILD_DEPS BUILD_MINGW_FROM_SOURCE

# ---------------------------------------------------------------------------
# Build-environment preflight (CLI belt-and-braces; GUI runs this before us)
# Skip when WB_BUILD_SKIP_COMPILE=1 (tests) or WB_SKIP_PREFLIGHT=1 (GUI sets
# this after its own rich-dialog preflight to avoid running twice).
# ---------------------------------------------------------------------------
if [[ "${WB_BUILD_SKIP_COMPILE:-0}" != "1" ]] \
   && [[ "${WB_SKIP_PREFLIGHT:-0}" != "1" ]] \
   && [[ "${COMPONENT}" == "dxvk" || "${COMPONENT}" == "vkd3d" || "${COMPONENT}" == "nvapi" ]]; then
  _preflight_bin=""
  _preflight_candidates=(
    "${WINE_ROOT}/runtime/libexec/wb-preflight.py"
    "/usr/lib/wine-bleeding/libexec/wb-preflight.py"
    "/usr/local/lib/wine-bleeding/libexec/wb-preflight.py"
  )
  for _c in "${_preflight_candidates[@]}"; do
    if [[ -f "${_c}" ]]; then
      _preflight_bin="${_c}"
      break
    fi
  done

  if [[ -n "${_preflight_bin}" ]]; then
    _preflight_json=""
    _preflight_rc=0
    _preflight_json="$(python3 "${_preflight_bin}" --json --build-type components 2>/dev/null)" \
      || _preflight_rc=$?
    if [[ "${_preflight_rc}" -ne 0 ]]; then
      bc_emit_error "Build environment incomplete. What happened: wb-preflight.py reported missing or outdated tools. Why: required build tools (meson, ninja, glslang, mingw-w64-gcc, gcc, make, pkg-config, git) were not all found at the required version. Next action: run wb-gui → Dist Manager → Build Components to review and fix. (wb-preflight exit ${_preflight_rc})"
      printf '%s\n' "${_preflight_json}" >&2
      exit 66
    fi
    unset _preflight_json _preflight_rc
  fi
  unset _preflight_bin _preflight_candidates _c
fi

# ---------------------------------------------------------------------------
# Set up component-specific constants
# ---------------------------------------------------------------------------
DEPS_DIR="${WB_BUILD_DEPS_DIR:-${WB_WINE_SOURCE_ROOT}/build-deps}"
export DEPS_DIR

# Pre-flight: DEPS_DIR must exist. When the driver runs from an installed
# package and WB_WINE_SOURCE_ROOT points at a non-source location (or is
# unset), we fail here with an actionable error rather than deep inside a
# meson/ninja invocation. WB_BUILD_SKIP_COMPILE=1 (tests) bypasses this;
# the overlay-install path does not use DEPS_DIR and is not guarded here.
if [[ "${WB_BUILD_SKIP_COMPILE:-0}" != "1" ]] \
   && [[ "${COMPONENT}" == "dxvk" || "${COMPONENT}" == "vkd3d" || "${COMPONENT}" == "nvapi" ]] \
   && [[ ! -d "${DEPS_DIR}" ]]; then
  bc_emit_error "Component build needs a wine-bleeding source tree with build-deps/.
Expected: ${DEPS_DIR}
Next action: check out https://github.com/palginpav/wine-bleeding and either
  (a) run wb-gui directly from that tree, OR
  (b) set WB_WINE_SOURCE_ROOT=/path/to/wine-bleeding and retry, OR
  (c) set WB_BUILD_DEPS_DIR=/path/to/build-deps explicitly."
  exit 66
fi

case "${COMPONENT}" in
  dxvk)
    REPO_URL="https://github.com/doitsujin/dxvk.git"
    REPO_NAME="dxvk"
    REV_FILE="${DEPS_DIR}/.dxvk-rev"
    DST_SUBDIR="dxvk"
    MESON_X64="build-win64.txt"
    MESON_X86="build-win32.txt"
    EXPECTED_X64=("dxgi.dll" "d3d11.dll" "d3d10core.dll" "d3d9.dll" "d3d8.dll")
    EXPECTED_X86=("dxgi.dll" "d3d11.dll" "d3d10core.dll" "d3d9.dll" "d3d8.dll")
    ;;
  vkd3d)
    REPO_URL="https://github.com/HansKristian-Work/vkd3d-proton.git"
    REPO_NAME="vkd3d-proton"
    REV_FILE="${DEPS_DIR}/.vkd3d-rev"
    DST_SUBDIR="vkd3d-proton"
    MESON_X64="build-win64.txt"
    MESON_X86="build-win32.txt"
    EXPECTED_X64=("d3d12.dll" "d3d12core.dll")
    EXPECTED_X86=("d3d12.dll" "d3d12core.dll")
    ;;
  nvapi)
    REPO_URL="https://github.com/jp7677/dxvk-nvapi.git"
    REPO_NAME="dxvk-nvapi"
    REV_FILE="${DEPS_DIR}/.nvapi-rev"
    DST_SUBDIR="nvapi"
    MESON_X64="build-win64.txt"
    MESON_X86="build-win32.txt"
    EXPECTED_X64=("nvapi64.dll" "nvofapi64.dll")
    EXPECTED_X86=("nvapi.dll" "nvofapi.dll")
    ;;
esac

# ---------------------------------------------------------------------------
# Validate --target-dist (security gate)
# ---------------------------------------------------------------------------
WB_HOME="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
export WB_HOME

if [[ ! -d "${TARGET_DIST}" ]]; then
  bc_emit_error "--target-dist '${TARGET_DIST}' does not exist or is not a directory"
  exit 65
fi

# Canonicalize. Accept --target-dist if EITHER of these is true:
#   1. It's a direct child of $WB_HOME/dist/ (a native dist), OR
#   2. It is listed in $WB_HOME/plugins/runtimes.d/*.json .path (i.e. the user
#      registered it via "Add External" in the Dist Manager).
# This lets externally-added full-build.sh dists rebuild components while
# still preventing arbitrary-path writes from a rogue caller.
TARGET_DIST_REAL="$(realpath -m "${TARGET_DIST}")"
DIST_BASE_REAL="$(realpath -m "${WB_HOME}/dist")"
TARGET_DIST_BASENAME="$(basename "${TARGET_DIST_REAL}")"

_bc_is_registered_external() {
  local plugin_dir="${WB_HOME}/plugins/runtimes.d"
  [[ -d "${plugin_dir}" ]] || return 1
  local pfile pcanon
  for pfile in "${plugin_dir}"/*.json; do
    [[ -f "${pfile}" ]] || continue
    local ppath
    ppath="$(jq -r '.path // empty' "${pfile}" 2>/dev/null || true)"
    [[ -z "${ppath}" ]] && continue
    pcanon="$(realpath -m "${ppath}" 2>/dev/null || echo "${ppath}")"
    if [[ "${pcanon}" == "${TARGET_DIST_REAL}" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ "${TARGET_DIST_REAL}" != "${DIST_BASE_REAL}/${TARGET_DIST_BASENAME}" ]] \
   && ! _bc_is_registered_external; then
  bc_emit_error "Security gate: --target-dist must be either a direct child of \$WB_HOME/dist/ or a registered external dist (plugins/runtimes.d); got '${TARGET_DIST_REAL}'"
  exit 65
fi

# ---------------------------------------------------------------------------
# Cancellation trap — clean up staging dir; emit ERROR; exit 2
# ---------------------------------------------------------------------------
_STAGING_DIR=""
_IN_SWAP=0

_bc_sigterm_handler() {
  if [[ "${_IN_SWAP}" -eq 1 ]]; then
    # Defer: do not interrupt swap phase (see API doc §4 cancellation)
    return 0
  fi
  bc_emit_error "Cancelled by user"
  if [[ -n "${_STAGING_DIR}" ]] && [[ -d "${_STAGING_DIR}" ]]; then
    rm -rf "${_STAGING_DIR}" 2>/dev/null || true
  fi
  bc_release_build_lock
  exit 2
}
trap '_bc_sigterm_handler' TERM

# ---------------------------------------------------------------------------
# Acquire global build lock
# ---------------------------------------------------------------------------
bc_acquire_build_lock 0

# ---------------------------------------------------------------------------
# START BUILD
# ---------------------------------------------------------------------------
bc_emit_progress 0 "Starting build"

if [[ "${WB_BUILD_SKIP_COMPILE:-0}" != "1" ]]; then
  # These checks only matter when an actual meson/ninja build will run.
  # Skipping them under WB_BUILD_SKIP_COMPILE avoids bc_resolve_mingw firing
  # a blocking curl to musl.cc in test environments without system MinGW.
  bc_emit_progress 5 "Resolving MinGW toolchain"
  bc_check_env
  bc_check_glslang
  bc_check_vulkan
  bc_resolve_mingw
fi

# ---------------------------------------------------------------------------
# Compute staging dir
# ---------------------------------------------------------------------------
STAGING_DIR="${DIST_BASE_REAL}/.build-staging/${TARGET_DIST_BASENAME}.${COMPONENT}.$$"
_STAGING_DIR="${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# Ensure staging is cleaned on unexpected exit (not cancellation — handled by trap)
_bc_cleanup_staging() {
  if [[ -n "${_STAGING_DIR}" ]] && [[ -d "${_STAGING_DIR}" ]]; then
    rm -rf "${_STAGING_DIR}" 2>/dev/null || true
  fi
}

bc_emit_progress 10 "Checking for upstream updates"
bc_check_deps_upstream "${COMPONENT}"

# ---------------------------------------------------------------------------
# widl wrapper (required by VKD3D-Proton)
# ---------------------------------------------------------------------------
_bc_setup_widl() {
  local widl_bin="${WB_WINE_SOURCE_ROOT}/tools/widl/widl"
  if [[ -x "${widl_bin}" ]]; then
    local wrapper_dir="${DEPS_DIR}/widl-wrapper"
    mkdir -p "${wrapper_dir}"
    local name
    for name in x86_64-w64-mingw32-widl i686-w64-mingw32-widl; do
      [[ -x "${wrapper_dir}/${name}" ]] || ln -sf "${widl_bin}" "${wrapper_dir}/${name}"
    done
    export PATH="${wrapper_dir}:${PATH}"
    bc_emit_log "widl: using Wine tree (${widl_bin})"
  fi
}

# ---------------------------------------------------------------------------
# Clone or update the component source repo
# ---------------------------------------------------------------------------
bc_emit_progress 15 "Cloning/updating ${COMPONENT} repo"
REPO_DIR="${DEPS_DIR}/${REPO_NAME}"

if [[ ! -d "${REPO_DIR}" ]]; then
  bc_emit_log "Cloning ${REPO_URL}..."
  git clone --depth 1 "${REPO_URL}" "${REPO_DIR}" 2>&1 \
    || { bc_emit_error "git clone failed for ${REPO_URL}"; _bc_cleanup_staging; bc_release_build_lock; exit 67; }
fi

(
  cd "${REPO_DIR}"
  git fetch --depth 1 origin 2>/dev/null || true
  git reset --hard refs/remotes/origin/HEAD 2>/dev/null \
    || git pull --depth 1 2>/dev/null \
    || true
  git submodule update --init --recursive 2>&1 || true
) || { bc_emit_error "Source update failed for ${REPO_NAME}"; _bc_cleanup_staging; bc_release_build_lock; exit 67; }

# ---------------------------------------------------------------------------
# Check if build is actually needed
# ---------------------------------------------------------------------------
BUILD_DIR="${DEPS_DIR}/build"
mkdir -p "${BUILD_DIR}"

# Compute what DLLs would already be in the target dist
TARGET_X64="${TARGET_DIST_REAL}/lib/wine/${DST_SUBDIR}/x86_64-windows"

_existing_dlls=()
for dll in "${EXPECTED_X64[@]}"; do
  _existing_dlls+=("${TARGET_X64}/${dll}")
done

if ! bc_need_deps_build "${REV_FILE}" "${REPO_DIR}" "${_existing_dlls[@]}"; then
  bc_emit_log "${COMPONENT} is up to date (no rebuild needed). Use --force-rebuild to override."
  bc_emit_progress 100 "Build complete (no-op; cache hit)"
  bc_release_build_lock
  exit 0
fi

[[ "${COMPONENT}" == "vkd3d" ]] && _bc_setup_widl

# ---------------------------------------------------------------------------
# Meson/ninja build into staging dir
# ---------------------------------------------------------------------------
STAGE_X64="${STAGING_DIR}/lib/wine/${DST_SUBDIR}/x86_64-windows"
STAGE_X86="${STAGING_DIR}/lib/wine/${DST_SUBDIR}/i386-windows"
mkdir -p "${STAGE_X64}" "${STAGE_X86}"

# Temp install prefix for meson inside staging
STAGE_PREFIX="${STAGING_DIR}/meson-install"
MESON_BUILD_X64="${BUILD_DIR}/${REPO_NAME}64-component"
MESON_BUILD_X86="${BUILD_DIR}/${REPO_NAME}32-component"

# x64 build
if [[ "${WB_BUILD_SKIP_COMPILE:-0}" != "1" ]]; then
  bc_emit_progress 25 "meson setup (x64)"
  (
    cd "${REPO_DIR}"
    if [[ -f "${MESON_X64}" ]]; then
      rm -rf "${MESON_BUILD_X64}"
      meson setup --cross-file "${MESON_X64}" --buildtype release \
        --prefix="${STAGE_PREFIX}" --bindir=x64 --libdir=x64 \
        -Db_ndebug=if-release "${MESON_BUILD_X64}" \
        || { bc_emit_error "meson setup (x64) failed for ${COMPONENT}"; exit 68; }
    else
      bc_emit_warn "No ${MESON_X64} found in ${REPO_DIR}; skipping x64 meson setup"
      exit 68
    fi
  ) || { _bc_cleanup_staging; bc_release_build_lock; exit 68; }

  bc_emit_progress 40 "ninja build (x64)"
  ninja -C "${MESON_BUILD_X64}" install \
    || { bc_emit_error "ninja build (x64) failed for ${COMPONENT}"; _bc_cleanup_staging; bc_release_build_lock; exit 68; }

  # Collect DLLs from meson install prefix into stage
  bc_emit_progress 55 "Installing x64 DLLs to staging"
  for d in "${STAGE_PREFIX}/x64" "${MESON_BUILD_X64}/src"/**; do
    [[ -d "${d}" ]] || continue
    for f in "${d}"/*.dll; do
      [[ -f "${f}" ]] && cp -n "${f}" "${STAGE_X64}/" 2>/dev/null || true
    done
  done
  # Also scan top-level if meson install went straight to x64/
  for f in "${STAGE_PREFIX}/x64"/*.dll; do
    [[ -f "${f}" ]] && cp -n "${f}" "${STAGE_X64}/" 2>/dev/null || true
  done
fi

# x86 build (optional — only if i686 toolchain available)
if [[ "${BUILD_32:-0}" -eq 1 ]]; then
  if [[ "${WB_BUILD_SKIP_COMPILE:-0}" != "1" ]]; then
    bc_emit_progress 65 "meson setup (x86)"
    (
      cd "${REPO_DIR}"
      if [[ -f "${MESON_X86}" ]]; then
        rm -rf "${MESON_BUILD_X86}"
        meson setup --cross-file "${MESON_X86}" --buildtype release \
          --prefix="${STAGE_PREFIX}" --bindir=x32 --libdir=x32 \
          -Db_ndebug=if-release "${MESON_BUILD_X86}" \
          || { bc_emit_error "meson setup (x86) failed for ${COMPONENT}"; exit 68; }
      else
        bc_emit_warn "No ${MESON_X86} found; skipping x86 meson setup"
        exit 68
      fi
    ) || { _bc_cleanup_staging; bc_release_build_lock; exit 68; }

    bc_emit_progress 80 "ninja build (x86)"
    ninja -C "${MESON_BUILD_X86}" install \
      || { bc_emit_error "ninja build (x86) failed for ${COMPONENT}"; _bc_cleanup_staging; bc_release_build_lock; exit 68; }

    bc_emit_log "Installing x86 DLLs to staging"
    for f in "${STAGE_PREFIX}/x32"/*.dll; do
      [[ -f "${f}" ]] && cp -n "${f}" "${STAGE_X86}/" 2>/dev/null || true
    done
  fi
else
  bc_emit_log "i686 toolchain not available; skipping x86 build"
fi

# ---------------------------------------------------------------------------
# Strip Wine builtin markers
# ---------------------------------------------------------------------------
bc_emit_progress 90 "Stripping Wine builtin markers"
for arch_dir in "${STAGE_X64}" "${STAGE_X86}"; do
  [[ -d "${arch_dir}" ]] || continue
  for dll in "${arch_dir}"/*.dll; do
    [[ -f "${dll}" ]] || continue
    bc_strip_builtin_marker "${dll}" 2>/dev/null || true
  done
done

# ---------------------------------------------------------------------------
# Verify DLL set completeness
# ---------------------------------------------------------------------------
_verify_dlls() {
  local dir="$1"
  shift
  local expected=("$@")
  local f missing=0
  for f in "${expected[@]}"; do
    if [[ ! -f "${dir}/${f}" ]]; then
      bc_emit_error "Expected DLL missing from staging: ${dir}/${f}"
      missing=1
    fi
  done
  return "${missing}"
}

if [[ "${WB_BUILD_SKIP_COMPILE:-0}" != "1" ]]; then
  if ! _verify_dlls "${STAGE_X64}" "${EXPECTED_X64[@]}"; then
    bc_emit_error "Staged x64 DLL set incomplete for ${COMPONENT}"
    _bc_cleanup_staging
    bc_release_build_lock
    exit 69
  fi

  if [[ "${BUILD_32:-0}" -eq 1 ]]; then
    if ! _verify_dlls "${STAGE_X86}" "${EXPECTED_X86[@]}"; then
      bc_emit_error "Staged x86 DLL set incomplete for ${COMPONENT}"
      _bc_cleanup_staging
      bc_release_build_lock
      exit 69
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Atomic swap into target dist
# ---------------------------------------------------------------------------
bc_emit_progress 95 "Swapping into target dist"
_IN_SWAP=1

# Acquire per-dist swap lock
exec {_SWAP_LOCK_FD}>"${TARGET_DIST_REAL}/.wb-swap-lock"
if ! flock -x -n "${_SWAP_LOCK_FD}" 2>/dev/null; then
  bc_emit_error "Cannot acquire swap lock on ${TARGET_DIST_REAL}; another swap in progress?"
  exec {_SWAP_LOCK_FD}>&-
  _bc_cleanup_staging
  bc_release_build_lock
  exit 70
fi

# Swap each arch dir atomically
_swap_ok=1
for arch in x86_64-windows i386-windows; do
  local_arch="$([ "${arch}" = "x86_64-windows" ] && echo "${STAGE_X64}" || echo "${STAGE_X86}")"
  [[ -d "${local_arch}" ]] && [[ "$(ls -A "${local_arch}" 2>/dev/null)" ]] || continue

  dst="${TARGET_DIST_REAL}/lib/wine/${DST_SUBDIR}/${arch}"
  mkdir -p "$(dirname "${dst}")"

  if [[ -d "${dst}" ]]; then
    mv -T "${dst}" "${dst}.old" 2>/dev/null || { bc_emit_error "mv -T rename to .old failed for ${dst}"; _swap_ok=0; break; }
  fi
  if ! mv -T "${local_arch}" "${dst}" 2>/dev/null; then
    bc_emit_error "mv -T swap failed for ${dst}"
    # Attempt rollback
    if [[ -d "${dst}.old" ]]; then
      mv -T "${dst}.old" "${dst}" 2>/dev/null || true
    fi
    _swap_ok=0
    break
  fi
  rm -rf "${dst}.old" 2>/dev/null || true
done

exec {_SWAP_LOCK_FD}>&-
_IN_SWAP=0

if [[ "${_swap_ok}" -eq 0 ]]; then
  _bc_cleanup_staging
  bc_release_build_lock
  exit 70
fi

# ---------------------------------------------------------------------------
# Write version file
# ---------------------------------------------------------------------------
VERSION_FILE="${TARGET_DIST_REAL}/lib/wine/${DST_SUBDIR}/.version"
if [[ -d "${REPO_DIR}/.git" ]]; then
  local_ver="$(git -C "${REPO_DIR}" describe --tags 2>/dev/null || git -C "${REPO_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  printf '%s\n' "${local_ver}" > "${VERSION_FILE}"
fi

# ---------------------------------------------------------------------------
# Refresh dist manifest
# ---------------------------------------------------------------------------
_bc_refresh_manifest() {
  local dist_path="$1"
  local wb_lib
  wb_lib="$(bc_resolve_wb_lib)" || wb_lib=""
  if [[ -n "${wb_lib}" ]] && [[ -f "${wb_lib}/wb-dist.sh" ]]; then
    (
      # shellcheck source=../runtime/src/wb-lib/wb-log.sh
      source "${wb_lib}/wb-log.sh" 2>/dev/null || true
      # shellcheck source=../runtime/src/wb-lib/wb-json.sh
      source "${wb_lib}/wb-json.sh"
      # shellcheck source=../runtime/src/wb-lib/wb-dist.sh
      source "${wb_lib}/wb-dist.sh"
      wb_dist_meta_write "${dist_path}"
    ) 2>/dev/null || bc_emit_warn "wb_dist_meta_write failed; manifest not updated"
  fi
}

_bc_refresh_manifest "${TARGET_DIST_REAL}"

# ---------------------------------------------------------------------------
# Write settings hint for the dist registry
# ---------------------------------------------------------------------------
_bc_write_settings_hint() {
  local dist_name
  dist_name="$(basename "${TARGET_DIST_REAL}")"
  local settings_dir="${WB_HOME}/settings/dists"
  local settings_file="${settings_dir}/${dist_name}.json"
  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local ver=""
  [[ -f "${TARGET_DIST_REAL}/lib/wine/${DST_SUBDIR}/.version" ]] \
    && ver="$(cat "${TARGET_DIST_REAL}/lib/wine/${DST_SUBDIR}/.version")"

  mkdir -p "${settings_dir}"

  local wb_lib
  wb_lib="$(bc_resolve_wb_lib)" || wb_lib=""
  if [[ -n "${wb_lib}" ]] && [[ -f "${wb_lib}/wb-json.sh" ]]; then
    (
      source "${wb_lib}/wb-json.sh"
      # Read existing settings or start fresh
      local existing="{}"
      [[ -f "${settings_file}" ]] && existing="$(cat "${settings_file}")"
      local updated
      updated="$(printf '%s' "${existing}" | jq \
        --arg built_by "build-component.sh" \
        --arg last_built_at "${now_utc}" \
        --arg comp "${COMPONENT}" \
        --arg ver "${ver}" \
        '.built_by = $built_by | .last_built_at = $last_built_at | .component_versions[$comp] = $ver'
      )"
      wb_json_write_atomic "${settings_file}" "${updated}"
    ) 2>/dev/null || bc_emit_warn "settings hint write failed"
  fi
}

_bc_write_settings_hint

# ---------------------------------------------------------------------------
# Record rev for cache
# ---------------------------------------------------------------------------
bc_save_deps_rev "${REV_FILE}" "${REPO_DIR}"

# ---------------------------------------------------------------------------
# Cleanup staging and release lock
# ---------------------------------------------------------------------------
rm -rf "${STAGING_DIR}" 2>/dev/null || true
_STAGING_DIR=""
bc_release_build_lock

bc_emit_progress 100 "Build complete"
exit 0

#!/usr/bin/env bash
# tools/build-glslang.sh — build glslang from source and install to $WB_HOME/build-deps/glslang/
#
# Usage:
#   tools/build-glslang.sh [--force-rebuild] [--progress-fd N] [--install-prefix PATH] [--tag REF]
#
# Exit codes:
#   0  — success (bin/glslangValidator present in install prefix)
#   2  — cancelled by user (SIGTERM received; staging cleaned)
#   64 — usage error (bad flag)
#   66 — environment failure (missing prerequisites: cmake, ninja/samurai, gcc, g++, git, python3)
#   67 — source fetch failure (git clone/fetch failed)
#   68 — build failure (cmake configure or ninja non-zero)
#   69 — install failure (bin/glslangValidator not produced after install)
#   71 — lock failure ($WB_HOME/.build-lock already held)
#   99 — internal error
#
# Environment:
#   WB_HOME            — wine-bleeding home dir (required; lock + install prefix)
#   WB_BUILD_PROGRESS_FD — optional fd for Phase-B PROGRESS:/LOG:/WARN:/ERROR: events
#
# Pinned tag: 15.0.0  (Vulkan SDK 1.3 era — bump intentionally, document in CHANGELOG)

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/build-common.sh
source "${WINE_ROOT}/tools/lib/build-common.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
GLSLANG_TAG="${GLSLANG_TAG:-15.0.0}"
GLSLANG_REPO="https://github.com/KhronosGroup/glslang.git"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FORCE_REBUILD=0
PROGRESS_FD_ARG=""
INSTALL_PREFIX=""
TAG_OVERRIDE=""
HELP=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --force-rebuild)
      FORCE_REBUILD=1 ;;
    --progress-fd)
      [[ -n "${2:-}" ]] || { printf 'build-glslang: --progress-fd requires a value\n' >&2; exit 64; }
      PROGRESS_FD_ARG="$2"; shift ;;
    --progress-fd=*)
      PROGRESS_FD_ARG="${1#--progress-fd=}" ;;
    --install-prefix)
      [[ -n "${2:-}" ]] || { printf 'build-glslang: --install-prefix requires a value\n' >&2; exit 64; }
      INSTALL_PREFIX="$2"; shift ;;
    --install-prefix=*)
      INSTALL_PREFIX="${1#--install-prefix=}" ;;
    --tag|--rev)
      [[ -n "${2:-}" ]] || { printf 'build-glslang: %s requires a value\n' "$1" >&2; exit 64; }
      TAG_OVERRIDE="$2"; shift ;;
    --tag=*|--rev=*)
      TAG_OVERRIDE="${1#*=}" ;;
    --help|-h)
      HELP=1 ;;
    *)
      printf 'build-glslang: unknown argument: %s\n' "$1" >&2
      printf '  Usage: %s [--force-rebuild] [--progress-fd N] [--install-prefix PATH] [--tag REF]\n' "$0" >&2
      exit 64 ;;
  esac
  shift
done

if [[ "${HELP}" -eq 1 ]]; then
  cat <<'EOF'
Usage: tools/build-glslang.sh [OPTIONS]

Build glslang from source and install to $WB_HOME/build-deps/glslang/.

Options:
  --force-rebuild         Skip .glslang-rev cache check; always reconfigure and rebuild.
  --progress-fd N         Emit PROGRESS:/LOG:/WARN:/ERROR: events on file descriptor N.
                          Without this flag, events go to stderr.
  --install-prefix PATH   Override install prefix (default: $WB_HOME/build-deps/glslang/).
  --tag REF               Override pinned git ref (default: 15.0.0).
  --help, -h              Show this message.

Exit codes:
  0  success
  2  cancelled (SIGTERM)
  64 usage error
  66 environment failure (missing prerequisites)
  67 source fetch failure
  68 build failure
  69 install verification failure
  71 build lock already held
  99 internal error
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# Configure progress fd
# ---------------------------------------------------------------------------
if [[ -n "${PROGRESS_FD_ARG}" ]]; then
  export WB_BUILD_PROGRESS_FD="${PROGRESS_FD_ARG}"
fi

# ---------------------------------------------------------------------------
# Resolve WB_HOME
# ---------------------------------------------------------------------------
if [[ -z "${WB_HOME:-}" ]]; then
  # WINE_ROOT may be a read-only install prefix (/usr/lib/wine-bleeding) when
  # this script ships in an installed package. Only fall back to WINE_ROOT if
  # it looks like a dev checkout (writable). Otherwise use the XDG user-data
  # default (matches what wb-gui would have set).
  if [[ -w "${WINE_ROOT}" && -f "${WINE_ROOT}/tools/full-build.sh" ]]; then
    WB_HOME="${WINE_ROOT}"
  else
    WB_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding"
    mkdir -p "${WB_HOME}" 2>/dev/null || true
  fi
fi

GLSLANG_TAG="${TAG_OVERRIDE:-${GLSLANG_TAG}}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${WB_HOME}/build-deps/glslang}"
SRC_DIR="${WB_HOME}/build-deps/glslang-src"
BUILD_DIR="${WB_HOME}/build-deps/glslang-build"
REV_SENTINEL="${WB_HOME}/build-deps/.glslang-rev"
VALIDATOR_BIN="${INSTALL_PREFIX}/bin/glslangValidator"

# ---------------------------------------------------------------------------
# Cancellation trap
# ---------------------------------------------------------------------------
_glslang_cancelled=0
_glslang_cleanup() {
  _glslang_cancelled=1
  bc_emit_error "Cancelled by user. Cleaning up build directory."
  rm -rf "${BUILD_DIR}"
  bc_release_build_lock 2>/dev/null || true
  exit 2
}
trap '_glslang_cleanup' SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
bc_emit_progress 5 "Checking build prerequisites (cmake, ninja, gcc, g++, git, python3)"

_missing_prereqs=""
for _cmd in cmake gcc g++ git python3; do
  if ! command -v "${_cmd}" &>/dev/null; then
    _missing_prereqs="${_missing_prereqs} ${_cmd}"
  fi
done
# ninja may be named samurai on Alpine
if ! command -v ninja &>/dev/null && ! command -v samu &>/dev/null; then
  _missing_prereqs="${_missing_prereqs} ninja"
fi

if [[ -n "${_missing_prereqs}" ]]; then
  bc_emit_error "Missing prerequisites:${_missing_prereqs}. What happened: required build tools are absent. Why: they must be installed before building glslang. Next action: install them via your distro package manager, then retry."
  exit 66
fi

# ---------------------------------------------------------------------------
# Acquire build lock
# ---------------------------------------------------------------------------
bc_acquire_build_lock 0

# ---------------------------------------------------------------------------
# Cache check: skip build if sentinel matches tag AND validator exists
# ---------------------------------------------------------------------------
if [[ "${FORCE_REBUILD}" -eq 0 ]] && [[ -f "${REV_SENTINEL}" ]] && [[ -x "${VALIDATOR_BIN}" ]]; then
  cached_rev="$(cat "${REV_SENTINEL}")"
  if [[ "${cached_rev}" == "${GLSLANG_TAG}" ]]; then
    bc_emit_progress 100 "Build complete (cache hit — glslang ${GLSLANG_TAG} already installed)"
    bc_release_build_lock
    exit 0
  fi
fi

bc_emit_progress 0 "Starting glslang build (tag: ${GLSLANG_TAG})"

# ---------------------------------------------------------------------------
# Clone / update source
# ---------------------------------------------------------------------------
bc_emit_progress 10 "Cloning KhronosGroup/glslang@${GLSLANG_TAG} (shallow, ~30 MB)"

if [[ -d "${SRC_DIR}/.git" ]]; then
  bc_emit_log "Source directory exists — fetching tag ${GLSLANG_TAG}"
  git -C "${SRC_DIR}" fetch --depth=1 origin "refs/tags/${GLSLANG_TAG}:refs/tags/${GLSLANG_TAG}" 2>&1 \
    | while IFS= read -r line; do bc_emit_log "${line}"; done \
    || { bc_emit_error "git fetch failed. What happened: could not fetch tag ${GLSLANG_TAG}. Why: network error or invalid tag. Next action: check your network connection and try again."; bc_release_build_lock; exit 67; }
  git -C "${SRC_DIR}" checkout "tags/${GLSLANG_TAG}" --detach 2>&1 \
    | while IFS= read -r line; do bc_emit_log "${line}"; done \
    || { bc_emit_error "git checkout tags/${GLSLANG_TAG} failed. What happened: could not check out the requested tag. Why: tag may not exist in the repo. Next action: verify --tag value and retry."; bc_release_build_lock; exit 67; }
else
  mkdir -p "$(dirname "${SRC_DIR}")"
  git clone --depth=1 --branch "${GLSLANG_TAG}" "${GLSLANG_REPO}" "${SRC_DIR}" 2>&1 \
    | while IFS= read -r line; do bc_emit_log "${line}"; done \
    || { bc_emit_error "git clone failed. What happened: could not clone ${GLSLANG_REPO}. Why: network error or the tag ${GLSLANG_TAG} does not exist. Next action: check your network and try again."; bc_release_build_lock; exit 67; }
fi

# ---------------------------------------------------------------------------
# Fetch SPIRV-Tools + SPIRV-Headers (required external dependencies)
# ---------------------------------------------------------------------------
bc_emit_progress 25 "Fetching SPIRV-Tools + SPIRV-Headers via update_glslang_sources.py"

if [[ -f "${SRC_DIR}/update_glslang_sources.py" ]]; then
  # update_glslang_sources.py reads known_good.json via a relative path, so
  # it must run from the glslang source root — otherwise it raises
  # FileNotFoundError and SPIRV-Tools never gets fetched, which makes cmake
  # fail later with "ENABLE_OPT set but SPIR-V tools not found".
  ( cd "${SRC_DIR}" && python3 ./update_glslang_sources.py ) 2>&1 \
    | while IFS= read -r line; do bc_emit_log "${line}"; done \
    || bc_emit_warn "update_glslang_sources.py reported an error — will attempt cmake configure anyway"
else
  bc_emit_log "update_glslang_sources.py not present in this release — proceeding without it"
fi

# ---------------------------------------------------------------------------
# cmake configure
# ---------------------------------------------------------------------------
bc_emit_progress 40 "cmake configure (-DCMAKE_BUILD_TYPE=Release -G Ninja)"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${INSTALL_PREFIX}"

# Prefer ninja; fall back to samurai (Alpine)
_ninja_cmd="ninja"
if ! command -v ninja &>/dev/null; then
  _ninja_cmd="samu"
fi

cmake \
  -S "${SRC_DIR}" \
  -B "${BUILD_DIR}" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_GLSLANG_BINARIES=ON \
  -DENABLE_HLSL=ON \
  2>&1 | while IFS= read -r line; do bc_emit_log "${line}"; done \
  || { bc_emit_error "cmake configure failed. What happened: cmake exited non-zero. Why: check the log for missing dependencies (python3, git, cmake modules). Next action: ensure cmake >= 3.17 and python3 are installed, then retry."; bc_release_build_lock; exit 68; }

# ---------------------------------------------------------------------------
# ninja build
# ---------------------------------------------------------------------------
bc_emit_progress 60 "ninja build (parallel, ~15 min on 8-core / ~30 min on 4-core)"

"${_ninja_cmd}" -C "${BUILD_DIR}" 2>&1 \
  | while IFS= read -r line; do bc_emit_log "${line}"; done \
  || { bc_emit_error "ninja build failed. What happened: ninja exited non-zero. Why: check the log for compiler errors. glslang 15 requires gcc >= 9 (C++17). Next action: update gcc and retry."; bc_release_build_lock; exit 68; }

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
bc_emit_progress 90 "ninja install -> ${INSTALL_PREFIX}"

"${_ninja_cmd}" -C "${BUILD_DIR}" install 2>&1 \
  | while IFS= read -r line; do bc_emit_log "${line}"; done \
  || { bc_emit_error "ninja install failed. What happened: install step exited non-zero. Why: disk full or permission error. Next action: ensure ${INSTALL_PREFIX} is writable and has at least 200 MB free."; bc_release_build_lock; exit 68; }

# ---------------------------------------------------------------------------
# Verify output
# ---------------------------------------------------------------------------
if [[ ! -x "${VALIDATOR_BIN}" ]]; then
  bc_emit_error "Install verification failed. What happened: ${VALIDATOR_BIN} not found after install. Why: build may have produced glslang without the validator binary. Next action: run with --force-rebuild and check the cmake log for ENABLE_GLSLANG_BINARIES."
  bc_release_build_lock
  exit 69
fi

# ---------------------------------------------------------------------------
# Write cache sentinel
# ---------------------------------------------------------------------------
bc_emit_progress 95 "Writing .glslang-rev sentinel"
printf '%s\n' "${GLSLANG_TAG}" > "${REV_SENTINEL}"

bc_release_build_lock

bc_emit_progress 100 "Build complete — glslangValidator at ${VALIDATOR_BIN}"

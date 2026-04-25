#!/usr/bin/env bash
# tools/fetch-overlay.sh — per-overlay fetcher for MangoHud / VKBasalt / OptiScaler
#
# Usage:
#   tools/fetch-overlay.sh \
#       --overlay {mangohud|vkbasalt|optiscaler} \
#       --version {<tag>|latest} \
#       [--dest /absolute/install/root] \
#       [--cache /absolute/cache/dir] \
#       [--progress-fd N] \
#       [--force-check] \
#       [--no-install] \
#       [--expected-sha256 HEX]
#
# Exit codes:
#    0  success
#    2  cancelled (SIGTERM)
#   64  usage error
#   65  invalid --dest
#   66  environment failure (missing tools)
#   67  source failure (GitHub API error / 404 / 5xx)
#   68  build failure (vkbasalt meson/ninja)
#   69  staging failure (expected files missing)
#   70  swap failure
#   71  lock failure
#   72  rate-limited
#   73  offline
#   74  SHA256 mismatch
#   75  archive format unknown
#   99  internal error

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/build-common.sh
source "${WINE_ROOT}/tools/lib/build-common.sh"

# ---------------------------------------------------------------------------
# Overlay configuration table
# ---------------------------------------------------------------------------
declare -rA WB_OVERLAY_REPO=(
  [mangohud]="flightlessmango/MangoHud"
  [vkbasalt]="DadSchoorse/vkBasalt"
  [optiscaler]="cdozdil/OptiScaler"
)

declare -rA WB_OVERLAY_ASSET_PATTERN=(
  [mangohud]="MangoHud-.*\.tar\.gz$"
  [vkbasalt]="source"
  [optiscaler]="OptiScaler_.*\.(7z|zip)$"
)

declare -rA WB_OVERLAY_INSTALL_KIND=(
  [mangohud]="prebuilt-tarball"
  [vkbasalt]="source-build"
  [optiscaler]="prebuilt-archive"
)

# Expected sentinel files (used for staging validation).
# MangoHud sentinel updated to lib64/ subdir — upstream's 0.7+ tarball lays
# out as lib/mangohud/{lib32,lib64}/libMangoHud.so (mirrors a typical distro
# packaging layout under /usr/lib/mangohud/...) instead of the older flat
# lib/mangohud/libMangoHud.so. Without this update the staging validator
# rejected every MangoHud install with "expected file missing".
declare -rA WB_OVERLAY_SENTINEL=(
  [mangohud]="lib/mangohud/lib64/libMangoHud.so"
  [vkbasalt]="lib/vkbasalt/libvkbasalt.so"
  [optiscaler]="bin/optiscaler/OptiScaler.dll"
)

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
OVERLAY=""
VERSION=""
DEST=""
CACHE=""
PROGRESS_FD=""
NO_INSTALL=0
EXPECTED_SHA256=""
HELP=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --overlay)
      [[ -n "${2:-}" ]] || { echo "fetch-overlay: --overlay requires a value" >&2; exit 64; }
      OVERLAY="$2"; shift ;;
    --overlay=*)
      OVERLAY="${1#--overlay=}" ;;
    --version)
      [[ -n "${2:-}" ]] || { echo "fetch-overlay: --version requires a value" >&2; exit 64; }
      VERSION="$2"; shift ;;
    --version=*)
      VERSION="${1#--version=}" ;;
    --dest)
      [[ -n "${2:-}" ]] || { echo "fetch-overlay: --dest requires a value" >&2; exit 64; }
      DEST="$2"; shift ;;
    --dest=*)
      DEST="${1#--dest=}" ;;
    --cache)
      [[ -n "${2:-}" ]] || { echo "fetch-overlay: --cache requires a value" >&2; exit 64; }
      CACHE="$2"; shift ;;
    --cache=*)
      CACHE="${1#--cache=}" ;;
    --progress-fd)
      [[ -n "${2:-}" ]] || { echo "fetch-overlay: --progress-fd requires a value" >&2; exit 64; }
      PROGRESS_FD="$2"; shift ;;
    --progress-fd=*)
      PROGRESS_FD="${1#--progress-fd=}" ;;
    --force-check)
      # Accepted; force-check behavior is handled by the overlay lib when registry is consulted
      : ;;
    --no-install)
      NO_INSTALL=1 ;;
    --expected-sha256)
      [[ -n "${2:-}" ]] || { echo "fetch-overlay: --expected-sha256 requires a value" >&2; exit 64; }
      EXPECTED_SHA256="$2"; shift ;;
    --expected-sha256=*)
      EXPECTED_SHA256="${1#--expected-sha256=}" ;;
    --help|-h)
      HELP=1 ;;
    *)
      echo "fetch-overlay: unknown argument: $1" >&2
      echo "  Usage: $0 --overlay {mangohud|vkbasalt|optiscaler} --version {<tag>|latest} [options]" >&2
      exit 64 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${HELP}" -eq 1 ]]; then
  cat <<'EOF'
Usage: tools/fetch-overlay.sh --overlay OVERLAY --version VERSION [OPTIONS]

Fetch and install a Linux overlay tool from GitHub into $WB_HOME/overlays/.

Required:
  --overlay {mangohud|vkbasalt|optiscaler}
      Overlay to fetch.
  --version {<tag>|latest}
      Specific release tag or "latest" for auto-discovery.

Options:
  --dest PATH
      Override install root (default: $WB_HOME/overlays/).
  --cache PATH
      Override cache dir (default: $WB_HOME/overlays/.cache/).
  --progress-fd N
      File descriptor to receive PROGRESS:/LOG:/WARN:/ERROR: events.
  --force-check
      Bypass 10-minute check cache in overlays.json.
  --no-install
      Resolve and verify only; do not extract or swap.
      Writes resolved version + asset URL as JSON to stdout.
  --expected-sha256 HEX
      Require downloaded archive to match this sha256.
  --help, -h
      Show this message.

Environment variables:
  WB_HOME                   Install-root default when --dest unset.
  GITHUB_TOKEN              Optional bearer token for GitHub API (raises rate limit).
  WB_OVERLAY_GH_API_BASE    Override API base (default: https://api.github.com).
                            Tests set this to a file:// or local path.
  WB_OVERLAY_DOWNLOAD_BASE  Override download base (tests: fixture path).
  WB_TEST_GH_API_FIXTURE    Path to a fixture JSON file for offline testing.
  WB_GUI_OVERLAY_NOW_UTC    Override "now" timestamp for reproducible tests.

Exit codes:
   0  success
   2  cancelled (SIGTERM)
  64  usage error
  65  invalid --dest
  66  environment failure (missing tools)
  67  source failure (GitHub API / 404 / 5xx)
  68  build failure (vkbasalt meson/ninja)
  69  staging failure (expected files missing)
  70  swap failure
  71  lock failure
  72  rate-limited
  73  offline
  74  sha256 mismatch
  75  archive format unknown
  99  internal error
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# Set up progress fd
# ---------------------------------------------------------------------------
export WB_BUILD_PROGRESS_FD="${PROGRESS_FD:-}"

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
if [[ -z "${OVERLAY}" ]]; then
  bc_emit_error "Usage error: --overlay is required"
  exit 64
fi

if [[ -z "${VERSION}" ]]; then
  bc_emit_error "Usage error: --version is required"
  exit 64
fi

if [[ -z "${WB_OVERLAY_REPO[${OVERLAY}]+isset}" ]]; then
  bc_emit_error "Usage error: unknown overlay '${OVERLAY}' (expected: mangohud, vkbasalt, optiscaler)"
  exit 64
fi

# ---------------------------------------------------------------------------
# Resolve dest + cache
# ---------------------------------------------------------------------------
WB_HOME="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
DEST="${DEST:-${WB_HOME}/overlays}"
CACHE="${CACHE:-${WB_HOME}/overlays/.cache}"

# Security gate: dest must exist, be writable, and be under $HOME
if [[ ! -d "${DEST}" ]]; then
  bc_emit_error "Invalid --dest '${DEST}': does not exist or is not a directory"
  exit 65
fi

if [[ ! -w "${DEST}" ]]; then
  bc_emit_error "Invalid --dest '${DEST}': not writable"
  exit 65
fi

# Normalize and check dest is under $HOME
# WB_TEST_SKIP_DEST_SECURITY_GATE=1 disables this check for offline CI tests.
DEST_REAL="$(realpath -m "${DEST}")"
HOME_REAL="$(realpath -m "${HOME}")"
if [[ "${WB_TEST_SKIP_DEST_SECURITY_GATE:-0}" != "1" ]] && \
   [[ "${DEST_REAL}" != "${HOME_REAL}"* ]]; then
  bc_emit_error "Security gate: --dest '${DEST_REAL}' must be under \$HOME (${HOME_REAL})"
  exit 65
fi

mkdir -p "${CACHE}"

# ---------------------------------------------------------------------------
# Check environment — tools needed
# ---------------------------------------------------------------------------
_fo_check_env() {
  local required=("curl" "jq")
  local install_kind="${WB_OVERLAY_INSTALL_KIND[${OVERLAY}]}"
  case "${install_kind}" in
    prebuilt-tarball)  required+=("tar") ;;
    source-build)      required+=("tar" "meson" "ninja" "pkg-config") ;;
    prebuilt-archive)
      if command -v 7z &>/dev/null; then
        : # prefer 7z
      elif command -v unzip &>/dev/null; then
        : # fallback to unzip
      else
        bc_emit_error "Environment failure: neither 7z nor unzip found (needed for OptiScaler)"
        exit 66
      fi ;;
  esac

  local missing="" cmd
  for cmd in "${required[@]}"; do
    command -v "${cmd}" &>/dev/null || missing="${missing} ${cmd}"
  done
  if [[ -n "${missing}" ]]; then
    bc_emit_error "Environment failure: missing tools:${missing}"
    exit 66
  fi
}

_fo_check_env

# ---------------------------------------------------------------------------
# Cancellation trap
# ---------------------------------------------------------------------------
_FO_STAGING_DIR=""
_FO_IN_SWAP=0

_fo_sigterm_handler() {
  if [[ "${_FO_IN_SWAP}" -eq 1 ]]; then
    return 0
  fi
  bc_emit_error "Cancelled by user"
  if [[ -n "${_FO_STAGING_DIR}" ]] && [[ -d "${_FO_STAGING_DIR}" ]]; then
    rm -rf "${_FO_STAGING_DIR}" 2>/dev/null || true
  fi
  bc_release_build_lock
  exit 2
}
trap '_fo_sigterm_handler' TERM

# ---------------------------------------------------------------------------
# Acquire global build lock
# ---------------------------------------------------------------------------
bc_acquire_build_lock 0

bc_emit_progress 0 "Starting fetch: ${OVERLAY} ${VERSION}"

# ---------------------------------------------------------------------------
# Discover release — GitHub API
# ---------------------------------------------------------------------------
REPO="${WB_OVERLAY_REPO[${OVERLAY}]}"
ASSET_PATTERN="${WB_OVERLAY_ASSET_PATTERN[${OVERLAY}]}"
GH_API_BASE="${WB_OVERLAY_GH_API_BASE:-https://api.github.com}"

_fo_now_utc() {
  printf '%s' "${WB_GUI_OVERLAY_NOW_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")}"
}

_fo_gh_api_call() {
  local url="$1"

  # Test fixture seam
  if [[ -n "${WB_TEST_GH_API_FIXTURE:-}" ]]; then
    local fixture="${WB_TEST_GH_API_FIXTURE}"
    if [[ -f "${fixture}.${OVERLAY}" ]]; then
      fixture="${fixture}.${OVERLAY}"
    fi
    if [[ ! -f "${fixture}" ]]; then
      bc_emit_error "Cannot reach api.github.com. Check network connection and try again."
      exit 73
    fi
    cat "${fixture}"
    return 0
  fi

  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local response_file
  response_file="$(mktemp)"
  local http_code=0
  local curl_exit=0

  http_code="$(curl -sS --location \
    --max-time 10 \
    --retry 2 --retry-delay 1 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    --write-out '%{http_code}' \
    --output "${response_file}" \
    "${url}" 2>/dev/null)" || curl_exit=$?

  if [[ "${curl_exit}" -ne 0 ]]; then
    rm -f "${response_file}"
    case "${curl_exit}" in
      6|7|28)
        bc_emit_error "Cannot reach api.github.com. Check network connection and try again."
        bc_release_build_lock; exit 73 ;;
      *)
        bc_emit_error "GitHub API error (curl exit ${curl_exit}). Try again in a few minutes."
        bc_release_build_lock; exit 67 ;;
    esac
  fi

  case "${http_code}" in
    200) ;;
    401|403)
      rm -f "${response_file}"
      local rl_msg
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        rl_msg="GitHub rate limit reached (5000/hr). Try again later."
      else
        rl_msg="GitHub rate limit reached (60/hr for unauthenticated). Set GITHUB_TOKEN environment variable to raise to 5000/hr, or try again in an hour."
      fi
      bc_emit_error "${rl_msg}"
      bc_release_build_lock; exit 72 ;;
    404)
      rm -f "${response_file}"
      bc_emit_error "Release not found in '${REPO}'. Tag may have been deleted upstream."
      bc_release_build_lock; exit 67 ;;
    *)
      rm -f "${response_file}"
      bc_emit_error "GitHub API error (HTTP ${http_code}). Try again in a few minutes."
      bc_release_build_lock; exit 67 ;;
  esac

  cat "${response_file}"
  rm -f "${response_file}"
}

bc_emit_progress 5 "Querying GitHub for ${OVERLAY} release info"

if [[ "${VERSION}" == "latest" ]]; then
  GH_API_URL="${GH_API_BASE}/repos/${REPO}/releases/latest"
else
  GH_API_URL="${GH_API_BASE}/repos/${REPO}/releases/tags/${VERSION}"
fi

RAW_RESPONSE="$(_fo_gh_api_call "${GH_API_URL}")"

# Parse response
RELEASE_TAG="$(printf '%s' "${RAW_RESPONSE}" | jq -r '.tag_name // empty' 2>/dev/null || true)"
TARBALL_URL="$(  printf '%s' "${RAW_RESPONSE}" | jq -r '.tarball_url  // empty' 2>/dev/null || true)"

if [[ -z "${RELEASE_TAG}" ]]; then
  bc_emit_error "GitHub API response missing tag_name — parse error."
  bc_release_build_lock; exit 67
fi

bc_emit_log "Resolved: ${OVERLAY} ${RELEASE_TAG}"

# For source-build (vkbasalt), use tarball_url
ASSET_URL=""
ASSET_NAME=""

if [[ "${ASSET_PATTERN}" == "source" ]]; then
  ASSET_URL="${TARBALL_URL}"
  ASSET_NAME="${OVERLAY}-${RELEASE_TAG}.tar.gz"
else
  # Find matching asset
  ASSET_JSON="$(printf '%s' "${RAW_RESPONSE}" | jq -c \
    --arg pattern "${ASSET_PATTERN}" \
    '[.assets[] | select(.name | test($pattern; "i")) | {name: .name, url: .browser_download_url, size: .size}]' \
    2>/dev/null || echo "[]")"

  ASSET_COUNT="$(printf '%s' "${ASSET_JSON}" | jq 'length')"
  if [[ "${ASSET_COUNT}" -eq 0 ]]; then
    local_avail="$(printf '%s' "${RAW_RESPONSE}" | jq -r '[.assets[].name] | join(", ")' 2>/dev/null || true)"
    bc_emit_error "No asset matched pattern '${ASSET_PATTERN}' for ${OVERLAY} ${RELEASE_TAG}. Available: ${local_avail}"
    bc_release_build_lock; exit 67
  fi

  # For optiscaler, prefer .7z over .zip
  if [[ "${OVERLAY}" == "optiscaler" ]]; then
    ASSET_URL="$(printf '%s' "${ASSET_JSON}" | jq -r '[.[] | select(.name | endswith(".7z"))][0].url // .[0].url')"
    ASSET_NAME="$(printf '%s' "${ASSET_JSON}" | jq -r '[.[] | select(.name | endswith(".7z"))][0].name // .[0].name')"
  else
    ASSET_URL="$(printf '%s' "${ASSET_JSON}" | jq -r '.[0].url')"
    ASSET_NAME="$(printf '%s' "${ASSET_JSON}" | jq -r '.[0].name')"
  fi
fi

if [[ -z "${ASSET_URL}" ]]; then
  bc_emit_error "Could not determine asset URL for ${OVERLAY} ${RELEASE_TAG}"
  bc_release_build_lock; exit 67
fi

# --no-install: output metadata and exit
if [[ "${NO_INSTALL}" -eq 1 ]]; then
  jq -cn \
    --arg overlay "${OVERLAY}" \
    --arg tag "${RELEASE_TAG}" \
    --arg asset_url "${ASSET_URL}" \
    --arg asset_name "${ASSET_NAME}" \
    '{overlay: $overlay, tag: $tag, asset_url: $asset_url, asset_name: $asset_name}'
  bc_release_build_lock
  exit 0
fi

# ---------------------------------------------------------------------------
# Determine target install dir
# ---------------------------------------------------------------------------
# Strip leading 'v' from tag for directory naming (e.g., v0.8.1 → 0.8.1)
VERSION_DIR="${RELEASE_TAG#v}"
INSTALL_DIR="${DEST_REAL}/${OVERLAY}/${VERSION_DIR}"

# If already installed (and not force), check sentinel and skip
if [[ -d "${INSTALL_DIR}" ]]; then
  SENTINEL="${WB_OVERLAY_SENTINEL[${OVERLAY}]}"
  if [[ -f "${INSTALL_DIR}/${SENTINEL}" ]]; then
    bc_emit_log "${OVERLAY} ${RELEASE_TAG} already installed at ${INSTALL_DIR}"
    bc_emit_progress 100 "Already up to date"
    bc_release_build_lock
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
CACHE_FILE="${CACHE}/${ASSET_NAME}"

_fo_download_asset() {
  local url="$1"
  local dest_file="$2"

  # Test fixture seam for download
  if [[ -n "${WB_OVERLAY_DOWNLOAD_BASE:-}" ]]; then
    local fixture_asset="${WB_OVERLAY_DOWNLOAD_BASE}/${ASSET_NAME}"
    if [[ -f "${fixture_asset}" ]]; then
      cp "${fixture_asset}" "${dest_file}"
      return 0
    fi
    bc_emit_error "Download fixture not found: ${fixture_asset}"
    return 73
  fi

  local curl_exit=0
  curl -sS --location \
    --max-time 300 \
    --retry 2 --retry-delay 3 \
    -o "${dest_file}" \
    "${url}" 2>/dev/null || curl_exit=$?

  if [[ "${curl_exit}" -ne 0 ]]; then
    case "${curl_exit}" in
      6|7|28)
        bc_emit_error "Cannot reach download server. Check network connection and try again."
        return 73 ;;
      *)
        bc_emit_error "Download failed (curl exit ${curl_exit}). Try again."
        return 67 ;;
    esac
  fi
}

if [[ ! -f "${CACHE_FILE}" ]]; then
  bc_emit_progress 20 "Downloading ${ASSET_NAME}"
  _fo_download_asset "${ASSET_URL}" "${CACHE_FILE}" || {
    _FO_DL_EXIT=$?
    bc_release_build_lock
    exit "${_FO_DL_EXIT}"
  }
else
  bc_emit_log "Cache hit: ${CACHE_FILE}"
fi

# ---------------------------------------------------------------------------
# SHA256 verification
# ---------------------------------------------------------------------------
bc_emit_progress 40 "Verifying SHA256"
ACTUAL_SHA256="$(sha256sum "${CACHE_FILE}" | awk '{print $1}')"

if [[ -n "${EXPECTED_SHA256}" ]]; then
  if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
    bc_emit_error "SHA256 mismatch for ${ASSET_NAME}: expected ${EXPECTED_SHA256}, got ${ACTUAL_SHA256}"
    rm -f "${CACHE_FILE}"
    bc_release_build_lock
    exit 74
  fi
  bc_emit_log "SHA256 verified: ${ACTUAL_SHA256}"
else
  bc_emit_log "SHA256 (recorded): ${ACTUAL_SHA256}"
fi

# ---------------------------------------------------------------------------
# Staging setup
# ---------------------------------------------------------------------------
STAGING_PARENT="${DEST_REAL}/.staging"
mkdir -p "${STAGING_PARENT}"
_FO_STAGING_DIR="$(mktemp -d "${STAGING_PARENT}/${OVERLAY}.${VERSION_DIR}.XXXXXX")"

bc_emit_progress 50 "Extracting / building ${OVERLAY}"

# ---------------------------------------------------------------------------
# Extract / build by install kind
# ---------------------------------------------------------------------------
INSTALL_KIND="${WB_OVERLAY_INSTALL_KIND[${OVERLAY}]}"

case "${INSTALL_KIND}" in
  prebuilt-tarball)
    if [[ "${OVERLAY}" == "mangohud" ]]; then
      # MangoHud (0.7+) ships a two-step package: the outer release tarball
      # contains:
      #   MangoHud/MangoHud-package.tar  (the actual file tree, prefixed
      #                                   ./usr/{bin,lib,share}/...)
      #   MangoHud/mangohud-setup.sh     (a user-targeted installer script
      #                                   that drops files into ~/.local —
      #                                   we don't use it; we install into
      #                                   $WB_HOME/overlays/mangohud/<ver>)
      # Plain `tar xf outer.tar.gz` lands MangoHud-package.tar +
      # mangohud-setup.sh under staging/, so the sentinel lookup for
      # lib/mangohud/lib64/libMangoHud.so failed and the install errored
      # out with "Staging failure: expected file missing".
      #
      # Two-stage extract: outer into a scratch dir, then the inner package
      # tar into staging stripping the leading ./usr/ so the resulting
      # layout is bin/, lib/, share/ at staging root — which matches the
      # sentinel + the LD_LIBRARY_PATH / VK_LAYER_PATH the launch env-bake
      # emits.
      OUTER_TMP="${_FO_STAGING_DIR}/_outer"
      mkdir -p "${OUTER_TMP}"
      tar xf "${CACHE_FILE}" -C "${OUTER_TMP}" 2>/dev/null || {
        bc_emit_error "outer tar extraction failed for ${CACHE_FILE}"
        rm -rf "${_FO_STAGING_DIR}"
        bc_release_build_lock
        exit 69
      }
      INNER_PKG="$(find "${OUTER_TMP}" -maxdepth 3 \
        -name 'MangoHud-package.tar' -type f 2>/dev/null | head -1)"
      if [[ -z "${INNER_PKG}" ]]; then
        bc_emit_error "MangoHud release format unexpected: MangoHud-package.tar not inside ${CACHE_FILE}"
        rm -rf "${_FO_STAGING_DIR}"
        bc_release_build_lock
        exit 69
      fi
      # Inner paths look like ./usr/{bin,lib,share}/... — --strip-components=2
      # drops the leading ./ and usr/ components, giving us bin/lib/share at
      # staging root.
      tar xf "${INNER_PKG}" -C "${_FO_STAGING_DIR}" --strip-components=2 2>/dev/null || {
        bc_emit_error "inner MangoHud-package.tar extraction failed"
        rm -rf "${_FO_STAGING_DIR}"
        bc_release_build_lock
        exit 69
      }
      rm -rf "${OUTER_TMP}"

      # Rewrite each Vulkan implicit-layer manifest's hardcoded
      # library_path. Upstream ships
      #   "library_path": "/usr/lib/mangohud/lib64/libMangoHud.so"
      # which is correct for a distro install but wrong for our bundled
      # location at $WB_HOME/overlays/mangohud/<ver>/lib/mangohud/lib*/...
      # The Vulkan loader requires an absolute path here, so a relative
      # rewrite isn't an option — we substitute the resolved INSTALL_DIR.
      # Two manifests (x86_64 + x86), each pointing at the matching arch
      # subdir.
      _MH_X64_JSON="${_FO_STAGING_DIR}/share/vulkan/implicit_layer.d/MangoHud.x86_64.json"
      _MH_X86_JSON="${_FO_STAGING_DIR}/share/vulkan/implicit_layer.d/MangoHud.x86.json"
      _MH_X64_LIB="${INSTALL_DIR}/lib/mangohud/lib64/libMangoHud.so"
      _MH_X86_LIB="${INSTALL_DIR}/lib/mangohud/lib32/libMangoHud.so"
      if [[ -f "${_MH_X64_JSON}" ]]; then
        # sed-rewrite library_path. Use | as separator so / in the new path
        # doesn't need escaping. The match is intentionally permissive
        # ("library_path" : "<anything>") so it survives upstream
        # whitespace tweaks.
        sed -i -E \
          "s|(\"library_path\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")|\1${_MH_X64_LIB}\2|" \
          "${_MH_X64_JSON}"
      fi
      if [[ -f "${_MH_X86_JSON}" ]]; then
        sed -i -E \
          "s|(\"library_path\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")|\1${_MH_X86_LIB}\2|" \
          "${_MH_X86_JSON}"
      fi
    else
      tar xf "${CACHE_FILE}" -C "${_FO_STAGING_DIR}" 2>/dev/null || {
        bc_emit_error "tar extraction failed for ${CACHE_FILE}"
        rm -rf "${_FO_STAGING_DIR}"
        bc_release_build_lock
        exit 69
      }
    fi
    ;;

  source-build)
    # vkbasalt: extract source tarball then meson+ninja build
    SRC_EXTRACT="${_FO_STAGING_DIR}/_src"
    mkdir -p "${SRC_EXTRACT}"
    tar xf "${CACHE_FILE}" -C "${SRC_EXTRACT}" --strip-components=1 2>/dev/null || {
      bc_emit_error "Source tarball extraction failed for ${CACHE_FILE}"
      rm -rf "${_FO_STAGING_DIR}"
      bc_release_build_lock
      exit 69
    }

    bc_emit_progress 55 "meson setup (vkbasalt)"
    BUILD_DIR="${_FO_STAGING_DIR}/_build"
    INSTALL_PREFIX="${_FO_STAGING_DIR}"

    (
      cd "${SRC_EXTRACT}"
      meson setup "${BUILD_DIR}" \
        --prefix="${INSTALL_PREFIX}" \
        --buildtype=release \
        -Db_ndebug=if-release 2>/dev/null
    ) || {
      bc_emit_error "meson setup failed for vkbasalt. Check that glslang, libvulkan-dev, and meson are installed."
      rm -rf "${_FO_STAGING_DIR}"
      bc_release_build_lock
      exit 68
    }

    bc_emit_progress 65 "ninja build (vkbasalt)"
    ninja -C "${BUILD_DIR}" install 2>/dev/null || {
      bc_emit_error "ninja build failed for vkbasalt"
      rm -rf "${_FO_STAGING_DIR}"
      bc_release_build_lock
      exit 68
    }

    # Clean up build dirs from staging (don't swap those into install)
    rm -rf "${SRC_EXTRACT}" "${BUILD_DIR}"
    ;;

  prebuilt-archive)
    # optiscaler: 7z or unzip into staging
    EXTRACT_DIR="${_FO_STAGING_DIR}/_extracted"
    mkdir -p "${EXTRACT_DIR}"

    if [[ "${ASSET_NAME}" == *.7z ]]; then
      7z x "${CACHE_FILE}" -o"${EXTRACT_DIR}" -y >/dev/null 2>&1 || {
        bc_emit_error "7z extraction failed for ${CACHE_FILE}"
        rm -rf "${_FO_STAGING_DIR}"
        bc_release_build_lock
        exit 69
      }
    elif [[ "${ASSET_NAME}" == *.zip ]]; then
      unzip -q "${CACHE_FILE}" -d "${EXTRACT_DIR}" 2>/dev/null || {
        bc_emit_error "unzip extraction failed for ${CACHE_FILE}"
        rm -rf "${_FO_STAGING_DIR}"
        bc_release_build_lock
        exit 69
      }
    else
      bc_emit_error "Unknown archive format for ${ASSET_NAME} (expected .7z or .zip)"
      rm -rf "${_FO_STAGING_DIR}"
      bc_release_build_lock
      exit 75
    fi

    # Flatten into standard install tree: bin/optiscaler/
    OSC_BIN_DIR="${_FO_STAGING_DIR}/bin/optiscaler"
    mkdir -p "${OSC_BIN_DIR}"
    # Copy all DLLs and INI from extracted root (and any subdirs)
    find "${EXTRACT_DIR}" \( -name "*.dll" -o -name "*.ini" \) \
      -exec cp -n '{}' "${OSC_BIN_DIR}/" \; 2>/dev/null || true

    rm -rf "${EXTRACT_DIR}"
    ;;
esac

# ---------------------------------------------------------------------------
# Verify staging
# ---------------------------------------------------------------------------
bc_emit_progress 75 "Verifying staged files"
SENTINEL="${WB_OVERLAY_SENTINEL[${OVERLAY}]}"

if [[ ! -f "${_FO_STAGING_DIR}/${SENTINEL}" ]]; then
  bc_emit_error "Staging failure: expected file missing: ${SENTINEL} (in ${_FO_STAGING_DIR})"
  rm -rf "${_FO_STAGING_DIR}"
  bc_release_build_lock
  exit 69
fi

# Write sidecar files into staging before swap
_FO_NOW_UTC="$(_fo_now_utc)"
printf '%s\n' "${_FO_NOW_UTC}" > "${_FO_STAGING_DIR}/.installed_utc"
printf '%s  %s\n' "${ACTUAL_SHA256}" "${ASSET_NAME}" > "${_FO_STAGING_DIR}/.sha256"

# ---------------------------------------------------------------------------
# Atomic swap
# ---------------------------------------------------------------------------
bc_emit_progress 90 "Installing ${OVERLAY} ${RELEASE_TAG}"
_FO_IN_SWAP=1

mkdir -p "$(dirname "${INSTALL_DIR}")"

# Acquire per-overlay swap lock
_FO_SWAP_LOCK_FILE="${DEST_REAL}/.overlay-swap-lock"
exec {_FO_SWAP_LOCK_FD}>"${_FO_SWAP_LOCK_FILE}"
if ! flock -x -n "${_FO_SWAP_LOCK_FD}" 2>/dev/null; then
  bc_emit_error "Cannot acquire swap lock; another overlay install in progress?"
  exec {_FO_SWAP_LOCK_FD}>&-
  rm -rf "${_FO_STAGING_DIR}"
  bc_release_build_lock
  exit 70
fi

# Move existing install aside
if [[ -d "${INSTALL_DIR}" ]]; then
  mv -T "${INSTALL_DIR}" "${INSTALL_DIR}.old" 2>/dev/null || {
    bc_emit_error "mv -T rename to .old failed for ${INSTALL_DIR}"
    exec {_FO_SWAP_LOCK_FD}>&-
    rm -rf "${_FO_STAGING_DIR}"
    bc_release_build_lock
    exit 70
  }
fi

# Swap staging into install
if ! mv -T "${_FO_STAGING_DIR}" "${INSTALL_DIR}" 2>/dev/null; then
  bc_emit_error "mv -T swap failed: ${_FO_STAGING_DIR} → ${INSTALL_DIR}"
  # Attempt rollback
  if [[ -d "${INSTALL_DIR}.old" ]]; then
    mv -T "${INSTALL_DIR}.old" "${INSTALL_DIR}" 2>/dev/null || true
  fi
  exec {_FO_SWAP_LOCK_FD}>&-
  bc_release_build_lock
  exit 70
fi

rm -rf "${INSTALL_DIR}.old" 2>/dev/null || true
exec {_FO_SWAP_LOCK_FD}>&-
_FO_IN_SWAP=0
_FO_STAGING_DIR=""

# ---------------------------------------------------------------------------
# Evict old cache files (keep last 3 archives for this overlay)
# ---------------------------------------------------------------------------
_fo_evict_cache() {
  local cache_dir="$1"
  local overlay_name="$2"
  # Find archives for this overlay, sorted by modification time (oldest first)
  local archive_list=()
  while IFS= read -r f; do
    archive_list+=("${f}")
  done < <(find "${cache_dir}" -maxdepth 1 \
    \( -name "${overlay_name}-*.tar.gz" -o \
       -name "MangoHud-*.tar.gz" -o \
       -name "vkBasalt-*.tar.gz" -o \
       -name "OptiScaler_*.7z" -o \
       -name "OptiScaler_*.zip" \) \
    -type f 2>/dev/null | sort -t_ -k2,2 || true)

  local keep=3
  local count="${#archive_list[@]}"
  if [[ "${count}" -gt "${keep}" ]]; then
    local remove_count=$(( count - keep ))
    local i
    for (( i=0; i<remove_count; i++ )); do
      rm -f "${archive_list[${i}]}" 2>/dev/null || true
      bc_emit_log "Cache evicted: ${archive_list[${i}]}"
    done
  fi
}

_fo_evict_cache "${CACHE}" "${OVERLAY}"

bc_release_build_lock
bc_emit_progress 100 "Installed ${OVERLAY} ${RELEASE_TAG} at ${INSTALL_DIR}"

exit 0

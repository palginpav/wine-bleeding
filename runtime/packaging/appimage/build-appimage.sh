#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# packaging/appimage/build-appimage.sh — Build wine-bleeding-wb AppImage
#
# Usage:
#   bash runtime/packaging/appimage/build-appimage.sh [--out DIR]
#
# Requirements (host):
#   - bash, make, coreutils (always required)
#   - appimagetool-x86_64.AppImage OR internet access to download it
#
# NOTE: This AppImage does NOT bundle bash, jq, flock, python3, or glibc.
# Users must have these packages installed. See packaging/README.md.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(cd "${SCRIPT_DIR}/../../" && pwd)"

OUT_DIR="${RUNTIME_DIR}/dist-packages"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)   OUT_DIR="${2:-}"; shift 2 ;;
    --out=*) OUT_DIR="${1#--out=}"; shift ;;
    --help|-h)
      echo "Usage: build-appimage.sh [--out DIR]"
      exit 0
      ;;
    *) echo "build-appimage.sh: unknown option '$1'" >&2; exit 1 ;;
  esac
done

VERSION="$(tr -d '[:space:]' < "${RUNTIME_DIR}/VERSION")"
ARCH="${ARCH:-x86_64}"
OUTPUT_NAME="wine-bleeding-wb-${VERSION}-${ARCH}.AppImage"

# ---------------------------------------------------------------------------
# Locate or download appimagetool
# ---------------------------------------------------------------------------
# Pinned to appimagetool 1.9.0 for reproducible, supply-chain-safe builds.
# SHA256 was computed via: curl -fsSL <URL> | sha256sum
# To override (e.g. CI with a pre-cached binary): set APPIMAGETOOL_SHA256=<hash>
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256_EXPECTED="${APPIMAGETOOL_SHA256:-46fdd785094c7f6e545b61afcfb0f3d98d8eab243f644b4b17698c01d06083d1}"
APPIMAGETOOL_CACHE="${SCRIPT_DIR}/appimagetool-x86_64.AppImage"

_verify_appimagetool_sha256() {
  local path="$1"
  if [[ -z "${APPIMAGETOOL_SHA256_EXPECTED}" ]]; then
    echo "build-appimage: FATAL: no checksum configured — rebuild with pinned hash" >&2
    echo "  Run: curl -fsSL ${APPIMAGETOOL_URL} | sha256sum" >&2
    echo "  Then set APPIMAGETOOL_SHA256=<result> or hard-code it in build-appimage.sh" >&2
    exit 1
  fi
  local actual
  actual="$(sha256sum "${path}" | awk '{print $1}')"
  if [[ "${actual}" != "${APPIMAGETOOL_SHA256_EXPECTED}" ]]; then
    echo "build-appimage: FATAL: appimagetool SHA256 mismatch" >&2
    echo "  expected: ${APPIMAGETOOL_SHA256_EXPECTED}" >&2
    echo "  actual:   ${actual}" >&2
    rm -f "${path}"
    exit 1
  fi
}

_find_appimagetool() {
  # 1. System PATH — cannot verify hash of a system binary; skip integrity check
  #    (system package manager is the trust anchor for system installs).
  if command -v appimagetool >/dev/null 2>&1; then
    echo "appimagetool"
    return 0
  fi
  # 2. Cached download next to this script — verify hash before use
  if [[ -f "${APPIMAGETOOL_CACHE}" ]]; then
    _verify_appimagetool_sha256 "${APPIMAGETOOL_CACHE}"
    chmod +x "${APPIMAGETOOL_CACHE}"
    echo "${APPIMAGETOOL_CACHE}"
    return 0
  fi
  return 1
}

_download_appimagetool() {
  echo "Downloading appimagetool 1.9.0..."
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "SKIP: appimagetool not found and no curl/wget to download it" >&2
    echo "SKIP: install appimagetool or place appimagetool-x86_64.AppImage next to build-appimage.sh" >&2
    exit 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${APPIMAGETOOL_CACHE}" "${APPIMAGETOOL_URL}" || {
      echo "SKIP: failed to download appimagetool" >&2
      exit 0
    }
  else
    wget -q -O "${APPIMAGETOOL_CACHE}" "${APPIMAGETOOL_URL}" || {
      echo "SKIP: failed to download appimagetool" >&2
      exit 0
    }
  fi
  # Verify integrity before making executable — fail-closed on mismatch
  _verify_appimagetool_sha256 "${APPIMAGETOOL_CACHE}"
  chmod +x "${APPIMAGETOOL_CACHE}"
  echo "appimagetool downloaded and verified: ${APPIMAGETOOL_CACHE}"
}

APPIMAGETOOL=""
if ! APPIMAGETOOL="$(_find_appimagetool 2>/dev/null)"; then
  _download_appimagetool
  APPIMAGETOOL="${APPIMAGETOOL_CACHE}"
fi

# ---------------------------------------------------------------------------
# Stage AppDir
# ---------------------------------------------------------------------------
BUILD_TMP="$(mktemp -d)"
trap 'rm -rf "${BUILD_TMP}"' EXIT

APPDIR="${BUILD_TMP}/AppDir"
mkdir -p "${APPDIR}"

echo "Staging AppDir at ${APPDIR}..."
make -C "${RUNTIME_DIR}" install \
  DESTDIR="${APPDIR}" \
  PREFIX=/usr

# Copy AppImage-specific files
cp "${SCRIPT_DIR}/AppRun"                "${APPDIR}/AppRun"
chmod 755                                "${APPDIR}/AppRun"
cp "${SCRIPT_DIR}/wine-bleeding-wb.desktop" "${APPDIR}/wine-bleeding-wb.desktop"

# Icon: prefer 512x512 PNG (AppImage DirIcon convention), fall back to SVG.
ICON_PNG_SRC="${APPDIR}/usr/share/icons/hicolor/512x512/apps/wine-bleeding.png"
ICON_SVG_SRC="${APPDIR}/usr/share/icons/hicolor/scalable/apps/wine-bleeding.svg"
if [[ -f "${ICON_PNG_SRC}" ]]; then
  cp "${ICON_PNG_SRC}" "${APPDIR}/wine-bleeding.png"
  ln -sf "wine-bleeding.png" "${APPDIR}/.DirIcon"
elif [[ -f "${ICON_SVG_SRC}" ]]; then
  cp "${ICON_SVG_SRC}" "${APPDIR}/wine-bleeding.svg"
  ln -sf "wine-bleeding.svg" "${APPDIR}/.DirIcon"
else
  # Minimal placeholder so appimagetool doesn't error out.
  echo '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#8b1a1a"/><text x="8" y="44" font-size="36" fill="white">wb</text></svg>' \
    > "${APPDIR}/wine-bleeding.svg"
  ln -sf "wine-bleeding.svg" "${APPDIR}/.DirIcon"
fi

# ---------------------------------------------------------------------------
# Build AppImage
# ---------------------------------------------------------------------------
mkdir -p "${OUT_DIR}"
OUTPUT_PATH="${OUT_DIR}/${OUTPUT_NAME}"

echo "Building AppImage: ${OUTPUT_NAME}..."
ARCH="${ARCH}" "${APPIMAGETOOL}" "${APPDIR}" "${OUTPUT_PATH}"

# Emit SHA256
SHA256="$(sha256sum "${OUTPUT_PATH}" | awk '{print $1}')"
echo "Built: ${OUTPUT_PATH}"
echo "SHA256: ${SHA256}"
echo "${SHA256}  ${OUTPUT_NAME}" > "${OUTPUT_PATH}.sha256"

echo "AppImage build complete. Output in: ${OUT_DIR}"

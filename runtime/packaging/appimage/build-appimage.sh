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
# Pinned version and checksum for reproducibility
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
# TODO: pin a specific checksum for reproducible builds — update for production releases
# APPIMAGETOOL_SHA256="<sha256-of-pinned-release>"
APPIMAGETOOL_CACHE="${SCRIPT_DIR}/appimagetool-x86_64.AppImage"

_find_appimagetool() {
  # 1. System PATH
  if command -v appimagetool >/dev/null 2>&1; then
    echo "appimagetool"
    return 0
  fi
  # 2. Cached download next to this script
  if [[ -x "${APPIMAGETOOL_CACHE}" ]]; then
    echo "${APPIMAGETOOL_CACHE}"
    return 0
  fi
  return 1
}

_download_appimagetool() {
  echo "Downloading appimagetool..."
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
  chmod +x "${APPIMAGETOOL_CACHE}"
  echo "appimagetool downloaded to: ${APPIMAGETOOL_CACHE}"
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

# Icon: use from installed share, create DirIcon symlink at root
ICON_SRC="${APPDIR}/usr/share/icons/hicolor/scalable/apps/wine-bleeding.svg"
if [[ -f "${ICON_SRC}" ]]; then
  cp "${ICON_SRC}" "${APPDIR}/wine-bleeding.svg"
  ln -sf "wine-bleeding.svg" "${APPDIR}/.DirIcon"
else
  # Create a minimal placeholder icon so appimagetool doesn't error
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

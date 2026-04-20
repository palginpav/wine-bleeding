#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# packaging/deb/build.sh — Build wine-bleeding-wb DEB package
#
# Usage:
#   bash runtime/packaging/deb/build.sh [--out DIR]
#
# Requires: dpkg-buildpackage (dpkg-dev package)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(cd "${SCRIPT_DIR}/../../" && pwd)"

OUT_DIR="${RUNTIME_DIR}/dist-packages"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)   OUT_DIR="${2:-}"; shift 2 ;;
    --out=*) OUT_DIR="${1#--out=}"; shift ;;
    --help|-h)
      echo "Usage: build.sh [--out DIR]"
      exit 0
      ;;
    *) echo "build.sh: unknown option '$1'" >&2; exit 1 ;;
  esac
done

if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
  echo "SKIP: dpkg-buildpackage not found — install dpkg-dev to build DEBs"
  exit 0
fi

VERSION="$(tr -d '[:space:]' < "${RUNTIME_DIR}/VERSION")"
BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "${BUILD_ROOT}"' EXIT

# Stage a clean source tree for dpkg-buildpackage
# Debian versions use '~' not '-' for pre-release suffixes.
# Use tr (not bash ${//-/~}) to avoid tilde-expansion of HOME in bash substitutions.
DEB_VER="$(echo "${VERSION}" | tr '-' '~')"
SRC_NAME="wine-bleeding-wb_${DEB_VER}"
SRC_STAGE="${BUILD_ROOT}/${SRC_NAME}"
mkdir -p "${SRC_STAGE}"

rsync -a --exclude='packaging/' --exclude='tests/vendor/' \
  "${RUNTIME_DIR}/" "${SRC_STAGE}/"

# Place debian/ at the package source root
cp -a "${SCRIPT_DIR}/debian" "${SRC_STAGE}/debian"

# Update version in changelog to match VERSION file (use awk to avoid sed
# regex issues with special characters in the version string)
awk -v ver="${DEB_VER}-1" \
  'NR==1 { sub(/\([^)]*\)/, "(" ver ")") } 1' \
  "${SRC_STAGE}/debian/changelog" > "${SRC_STAGE}/debian/changelog.tmp"
mv "${SRC_STAGE}/debian/changelog.tmp" "${SRC_STAGE}/debian/changelog"

mkdir -p "${OUT_DIR}"

echo "Building DEB for wine-bleeding-wb ${VERSION}..."
(
  cd "${SRC_STAGE}"
  # -us -uc: unsigned source + unsigned changes (CI-safe, no GPG required)
  # -b: binary-only build
  dpkg-buildpackage -us -uc -b
)

# Collect .deb output (dpkg-buildpackage places it in the parent of source dir)
find "${BUILD_ROOT}" -maxdepth 1 -name '*.deb' | while read -r deb; do
  cp "${deb}" "${OUT_DIR}/"
  echo "Built: ${OUT_DIR}/$(basename "${deb}")"
  sha256sum "${deb}" | awk '{print $1, "'"$(basename "${deb}")"'"}'
done

echo "DEB build complete. Output in: ${OUT_DIR}"

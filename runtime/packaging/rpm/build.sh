#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# packaging/rpm/build.sh — Build wine-bleeding-wb RPM package
#
# Usage:
#   bash runtime/packaging/rpm/build.sh [--out DIR]
#
# Requires: rpmbuild (rpm-build package)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(cd "${SCRIPT_DIR}/../../" && pwd)"
SPEC_TEMPLATE="${SCRIPT_DIR}/wine-bleeding-wb.spec"

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

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "SKIP: rpmbuild not found — install rpm-build to build RPMs"
  exit 0
fi

VERSION="$(tr -d '[:space:]' < "${RUNTIME_DIR}/VERSION")"
# RPM versions cannot contain '-' in the Version field; replace with '.'.
# Use tr (not bash ${//-/.}) to avoid tilde-expansion quirks in bash substitutions.
RPM_VERSION="$(echo "${VERSION}" | tr '-' '.')"
BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "${BUILD_ROOT}"' EXIT

# Prepare rpmbuild directory layout
mkdir -p \
  "${BUILD_ROOT}/SOURCES" \
  "${BUILD_ROOT}/SPECS" \
  "${BUILD_ROOT}/BUILD" \
  "${BUILD_ROOT}/RPMS" \
  "${BUILD_ROOT}/SRPMS"

# Stage the source tree into a versioned directory for tarball packaging
SRC_NAME="wine-bleeding-wb-${RPM_VERSION}"
SRC_STAGE="$(mktemp -d)"
trap 'rm -rf "${SRC_STAGE}" "${BUILD_ROOT}"' EXIT
mkdir -p "${SRC_STAGE}/${SRC_NAME}"

rsync -a --exclude='packaging/' --exclude='tests/vendor/' \
  "${RUNTIME_DIR}/" "${SRC_STAGE}/${SRC_NAME}/"

# Create source tarball
tar -czf "${BUILD_ROOT}/SOURCES/${SRC_NAME}.tar.gz" \
  -C "${SRC_STAGE}" "${SRC_NAME}"

# Substitute version placeholder in spec and place in SPECS/
sed "s/WB_VERSION_PLACEHOLDER/${RPM_VERSION}/" \
  "${SPEC_TEMPLATE}" > "${BUILD_ROOT}/SPECS/wine-bleeding-wb.spec"

mkdir -p "${OUT_DIR}"

echo "Building RPM for wine-bleeding-wb ${VERSION}..."
rpmbuild -ba \
  --define "_topdir ${BUILD_ROOT}" \
  "${BUILD_ROOT}/SPECS/wine-bleeding-wb.spec"

# Collect output RPMs
find "${BUILD_ROOT}/RPMS" "${BUILD_ROOT}/SRPMS" -name '*.rpm' | while read -r rpm; do
  cp "${rpm}" "${OUT_DIR}/"
  echo "Built: ${OUT_DIR}/$(basename "${rpm}")"
  sha256sum "${rpm}" | awk '{print $1, "'"$(basename "${rpm}")"'"}'
done

echo "RPM build complete. Output in: ${OUT_DIR}"

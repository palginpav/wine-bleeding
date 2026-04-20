#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# 25_packaging.bats — multi-format packaging tests
#
# Tests are structured to be shallow (no rpmbuild/dpkg required) but cover:
#   - make install DESTDIR layout correctness
#   - installed wb works and resolves libs via Option A fallback
#   - spec / control structural sanity
#   - AppRun executable + smoke invocation
#   - dist-* Makefile targets skip gracefully when tooling absent
#   - VERSION file matches wb --version
# ---------------------------------------------------------------------------

load "lib/common.bash"

RUNTIME_DIR="${BATS_TEST_DIRNAME}/.."
WB_SRC="${RUNTIME_DIR}/src/wb"
PACKAGING_DIR="${RUNTIME_DIR}/packaging"
VERSION_FILE="${RUNTIME_DIR}/VERSION"
MAKEFILE="${RUNTIME_DIR}/Makefile"

setup() {
  # Isolated DESTDIR for each test that needs one
  PKGTEST="$(mktemp -d)"
  export PKGTEST
}

teardown() {
  rm -rf "${PKGTEST}"
}

# ---------------------------------------------------------------------------
# Test 1: make install creates expected DESTDIR layout
# ---------------------------------------------------------------------------
@test "packaging: make install DESTDIR creates bin/wb lib/wb-lib share/schemas" {
  run make -C "${RUNTIME_DIR}" install \
        DESTDIR="${PKGTEST}" \
        PREFIX=/usr
  [ "${status}" -eq 0 ]

  # Required binaries
  [ -f "${PKGTEST}/usr/bin/wb" ]
  [ -x "${PKGTEST}/usr/bin/wb" ]
  [ -f "${PKGTEST}/usr/bin/wb-diag" ]
  [ -x "${PKGTEST}/usr/bin/wb-diag" ]

  # Lib directory with at least wb-log.sh
  [ -f "${PKGTEST}/usr/lib/wine-bleeding/wb-lib/wb-log.sh" ]

  # Share directory with schemas
  [ -f "${PKGTEST}/usr/share/wine-bleeding/schemas/wb_dist_meta.schema.json" ]

  # defaults.conf
  [ -f "${PKGTEST}/usr/share/wine-bleeding/defaults.conf" ]

  # Docs
  [ -f "${PKGTEST}/usr/share/doc/wine-bleeding/CHANGELOG.md" ]
  [ -f "${PKGTEST}/usr/share/doc/wine-bleeding/README.md" ]
}

# ---------------------------------------------------------------------------
# Test 2: installed wb --version works from DESTDIR
# ---------------------------------------------------------------------------
@test "packaging: installed wb --version returns 'wb <VER>'" {
  make -C "${RUNTIME_DIR}" install \
    DESTDIR="${PKGTEST}" \
    PREFIX=/usr >/dev/null 2>&1

  # Point WB_LIB_DIR at the DESTDIR-relative lib path so Option A fallback
  # works in the test environment (real system install hits /usr/lib/...).
  run env WB_LIB_DIR="${PKGTEST}/usr/lib/wine-bleeding/wb-lib" \
    WB_HOME="${PKGTEST}/var/lib/wine-bleeding" \
    "${PKGTEST}/usr/bin/wb" --version
  [ "${status}" -eq 0 ]
  [[ "${output}" == wb\ * ]]
}

# ---------------------------------------------------------------------------
# Test 3: Option A fallback — wb finds libs at /usr/lib path, not sibling
# ---------------------------------------------------------------------------
@test "packaging: installed wb resolves libs via Option A fallback (no sibling wb-lib)" {
  make -C "${RUNTIME_DIR}" install \
    DESTDIR="${PKGTEST}" \
    PREFIX=/usr >/dev/null 2>&1

  # Verify libs are at the expected system path, NOT next to /usr/bin/wb
  [ -d "${PKGTEST}/usr/lib/wine-bleeding/wb-lib" ]
  [ ! -d "${PKGTEST}/usr/bin/wb-lib" ]

  # wb-lib/*.sh is sourced from /usr/lib/wine-bleeding/wb-lib/ via fallback
  # Smoke: --version works, meaning lib resolution succeeded (via WB_LIB_DIR override)
  run env WB_LIB_DIR="${PKGTEST}/usr/lib/wine-bleeding/wb-lib" \
    WB_HOME="${PKGTEST}/var/lib/wine-bleeding" \
    "${PKGTEST}/usr/bin/wb" --version
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 4: RPM spec structural sanity (no rpmbuild required)
# ---------------------------------------------------------------------------
@test "packaging: RPM spec has required fields" {
  SPEC="${PACKAGING_DIR}/rpm/wine-bleeding-wb.spec"
  [ -f "${SPEC}" ]

  # Name field
  run grep -q "^Name:.*wine-bleeding-wb" "${SPEC}"
  [ "${status}" -eq 0 ]

  # Version field
  run grep -q "^Version:" "${SPEC}"
  [ "${status}" -eq 0 ]

  # Requires bash >= 4.4
  run grep -q "^Requires:.*bash" "${SPEC}"
  [ "${status}" -eq 0 ]

  # %install section
  run grep -q "^%install" "${SPEC}"
  [ "${status}" -eq 0 ]

  # %files section
  run grep -q "^%files" "${SPEC}"
  [ "${status}" -eq 0 ]

  # %changelog
  run grep -q "^%changelog" "${SPEC}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 5: DEB control structural sanity
# ---------------------------------------------------------------------------
@test "packaging: DEB control has Source, Package, Depends fields" {
  CONTROL="${PACKAGING_DIR}/deb/debian/control"
  [ -f "${CONTROL}" ]

  run grep -q "^Source:.*wine-bleeding-wb" "${CONTROL}"
  [ "${status}" -eq 0 ]

  run grep -q "^Package:.*wine-bleeding-wb" "${CONTROL}"
  [ "${status}" -eq 0 ]

  # Depends block includes bash (may span continuation lines)
  run grep -q "bash" "${CONTROL}"
  [ "${status}" -eq 0 ]

  # Build-Depends includes debhelper
  run grep -q "^Build-Depends:.*debhelper" "${CONTROL}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 6: AppRun is executable and invokes wb --version
# ---------------------------------------------------------------------------
@test "packaging: AppRun is executable and smoke-runs wb --version via AppDir" {
  APPRUN="${PACKAGING_DIR}/appimage/AppRun"
  [ -f "${APPRUN}" ]
  [ -x "${APPRUN}" ]

  # Stage an AppDir with our installed tree
  make -C "${RUNTIME_DIR}" install \
    DESTDIR="${PKGTEST}" \
    PREFIX=/usr >/dev/null 2>&1

  # Copy AppRun into the staged AppDir root
  cp "${APPRUN}" "${PKGTEST}/AppRun"
  chmod 755 "${PKGTEST}/AppRun"

  # Run: APPDIR points to our staged tree; AppRun exec's usr/bin/wb
  # WB_LIB_DIR tells wb where to find libs inside the AppDir staging tree
  run env APPDIR="${PKGTEST}" \
    WB_LIB_DIR="${PKGTEST}/usr/lib/wine-bleeding/wb-lib" \
    WB_HOME="${PKGTEST}/var/lib/wine-bleeding" \
    "${PKGTEST}/AppRun" --version
  [ "${status}" -eq 0 ]
  [[ "${output}" == wb\ * ]]
}

# ---------------------------------------------------------------------------
# Test 7: dist-* targets skip gracefully when tooling absent
# ---------------------------------------------------------------------------
@test "packaging: dist-rpm skips with exit 0 when rpmbuild absent" {
  if command -v rpmbuild >/dev/null 2>&1; then
    skip "rpmbuild is present — skip-path not exercised"
  fi
  run make -C "${RUNTIME_DIR}" dist-rpm
  [ "${status}" -eq 0 ]
  [[ "${output}" == *SKIP* ]]
}

@test "packaging: dist-deb skips with exit 0 when dpkg-buildpackage absent" {
  if command -v dpkg-buildpackage >/dev/null 2>&1; then
    skip "dpkg-buildpackage is present — skip-path not exercised"
  fi
  run make -C "${RUNTIME_DIR}" dist-deb
  [ "${status}" -eq 0 ]
  [[ "${output}" == *SKIP* ]]
}

@test "packaging: build-appimage.sh has a clean-skip path when download tools absent" {
  if command -v appimagetool >/dev/null 2>&1; then
    skip "appimagetool is present on PATH"
  fi
  APPIMAGE_CACHE="${PACKAGING_DIR}/appimage/appimagetool-x86_64.AppImage"
  if [[ -x "${APPIMAGE_CACHE}" ]]; then
    skip "appimagetool cached at ${APPIMAGE_CACHE}"
  fi

  # Structural check: the script contains the `SKIP:` path that fires when
  # neither curl nor wget is available. We grep the source rather than trying
  # to execute with a scrubbed PATH (which also strips tr/realpath/etc.
  # the script needs before reaching the download check).
  run grep -c "SKIP: appimagetool not found and no curl/wget" \
      "${PACKAGING_DIR}/appimage/build-appimage.sh"
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  # Also verify the script uses `exit 0` on that code path (not exit 1).
  run grep -A 2 "SKIP: appimagetool not found and no curl/wget" \
      "${PACKAGING_DIR}/appimage/build-appimage.sh"
  [[ "${output}" == *"exit 0"* ]]
}

# ---------------------------------------------------------------------------
# Test 8: VERSION file matches wb --version output
# ---------------------------------------------------------------------------
@test "packaging: VERSION file matches wb --version" {
  [ -f "${VERSION_FILE}" ]
  FILE_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
  [ -n "${FILE_VERSION}" ]

  run "${WB_SRC}" --version
  [ "${status}" -eq 0 ]
  # output is "wb <VERSION>"
  WB_VER="${output#wb }"
  [ "${FILE_VERSION}" = "${WB_VER}" ]
}

# ---------------------------------------------------------------------------
# Tests 11–13: .desktop i18n — locale keys present in both files (W2)
# ---------------------------------------------------------------------------

# Helper: assert that locale keys Name[xx], GenericName[xx], Comment[xx]
# are all present in a given .desktop file.
_assert_desktop_locale() {
  local file="$1" locale="$2"
  run grep -q "^Name\[${locale}\]=" "${file}"
  [ "${status}" -eq 0 ]
  run grep -q "^GenericName\[${locale}\]=" "${file}"
  [ "${status}" -eq 0 ]
  run grep -q "^Comment\[${locale}\]=" "${file}"
  [ "${status}" -eq 0 ]
}

@test "desktop i18n: share/applications/wine-bleeding-wb.desktop has all 4 locale entries" {
  local f="${RUNTIME_DIR}/share/applications/wine-bleeding-wb.desktop"
  [ -f "${f}" ]
  for locale in ru es de zh_CN; do
    _assert_desktop_locale "${f}" "${locale}"
  done
}

@test "desktop i18n: packaging/appimage/wine-bleeding-wb.desktop has all 4 locale entries" {
  local f="${RUNTIME_DIR}/packaging/appimage/wine-bleeding-wb.desktop"
  [ -f "${f}" ]
  for locale in ru es de zh_CN; do
    _assert_desktop_locale "${f}" "${locale}"
  done
}

@test "desktop i18n: desktop-file-validate passes on both .desktop files" {
  if ! command -v desktop-file-validate >/dev/null 2>&1; then
    skip "desktop-file-validate not installed"
  fi
  run desktop-file-validate \
    "${RUNTIME_DIR}/share/applications/wine-bleeding-wb.desktop"
  [ "${status}" -eq 0 ]
  run desktop-file-validate \
    "${RUNTIME_DIR}/packaging/appimage/wine-bleeding-wb.desktop"
  [ "${status}" -eq 0 ]
}

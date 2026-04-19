#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
FIXTURE_WINE="${BATS_TEST_DIRNAME}/fixtures/fake-wine"
FIXTURE_PPDB="${BATS_TEST_DIRNAME}/fixtures/ppdb"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  mkdir -p "${TEST_HOME}/dist"
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-M4TEST/"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-M4TEST/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-M4TEST/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-M4TEST/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-M4TEST/bin/wineserver"
  ln -sfn WINE-BLEEDING-M4TEST "${TEST_HOME}/dist/WINE-BLEEDING"

  mkdir -p "${TEST_HOME}/prefixes"
  export TEST_DIST="${TEST_HOME}/dist/WINE-BLEEDING-M4TEST"
  export TEST_PFX="${TEST_HOME}/prefixes/TESTPFX"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# 1. wb prefix init creates prefix and returns 0
# ---------------------------------------------------------------------------
@test "prefix init: creates prefix directory and exits 0" {
  run "${WB}" prefix init TESTPFX --dist "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  [ -d "${TEST_PFX}" ]
}

# ---------------------------------------------------------------------------
# 2. .wb_runtime exists, valid JSON, schema=1, wineboot_generation=1
# ---------------------------------------------------------------------------
@test "prefix init: .wb_runtime is valid JSON with schema=1 and wineboot_generation=1" {
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  local sentinel="${TEST_PFX}/.wb_runtime"
  [ -f "${sentinel}" ]
  run jq empty "${sentinel}"
  [ "${status}" -eq 0 ]
  run jq -r '.schema' "${sentinel}"
  [ "${output}" = "1" ]
  run jq -r '.wineboot_generation' "${sentinel}"
  [ "${output}" = "1" ]
  run jq -r '.owner' "${sentinel}"
  [ "${output}" = "wb-runtime" ]
}

# ---------------------------------------------------------------------------
# 3. .wine_ver contains exactly WINE-BLEEDING (no trailing newline)
# ---------------------------------------------------------------------------
@test "prefix init: .wine_ver contains exactly 'WINE-BLEEDING' (no newline)" {
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  local wine_ver_file="${TEST_PFX}/.wine_ver"
  [ -f "${wine_ver_file}" ]
  local content
  content="$(cat "${wine_ver_file}")"
  [ "${content}" = "WINE-BLEEDING" ]
  local byte_count
  byte_count="$(wc -c < "${wine_ver_file}")"
  [ "${byte_count}" -eq 13 ]
}

# ---------------------------------------------------------------------------
# 4. .wb_components exists, valid JSON, lists all five components
# ---------------------------------------------------------------------------
@test "prefix init: .wb_components is valid JSON with dxvk+vkd3d+nvapi+mono+icu" {
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  local manifest="${TEST_PFX}/.wb_components"
  [ -f "${manifest}" ]
  run jq empty "${manifest}"
  [ "${status}" -eq 0 ]
  run jq -r '.components | keys | sort | join(",")' "${manifest}"
  [ "${output}" = "dxvk,icu,mono,nvapi,vkd3d" ]
}

# ---------------------------------------------------------------------------
# 5. drive_c/windows/system32/d3d11.dll exists after init
# ---------------------------------------------------------------------------
@test "prefix init: system32/d3d11.dll deployed by DXVK component" {
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  [ -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll" ]
}

# ---------------------------------------------------------------------------
# 6. wb prefix components TESTPFX prints valid JSON
# ---------------------------------------------------------------------------
@test "prefix components: prints valid JSON for an initialised prefix" {
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  run "${WB}" prefix components TESTPFX
  [ "${status}" -eq 0 ]
  echo "${output}" | jq empty
}

# ---------------------------------------------------------------------------
# 7. wb prefix reconcile restores a manually deleted d3d11.dll
# ---------------------------------------------------------------------------
@test "prefix reconcile: restores manually deleted system32/d3d11.dll" {
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  [ ! -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll" ]
  run "${WB}" prefix reconcile TESTPFX
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll" ]
}

# ---------------------------------------------------------------------------
# 8. wb prefix reconcile does NOT invoke fake-wine (log is unchanged)
# ---------------------------------------------------------------------------
@test "prefix reconcile: does not invoke wine binary (no new .fake_wine.log entries)" {
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  local fake_log="${TEST_PFX}/.fake_wine.log"
  local before_size=0
  if [[ -f "${fake_log}" ]]; then
    before_size="$(wc -c < "${fake_log}")"
  fi
  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  "${WB}" prefix reconcile TESTPFX >/dev/null
  local after_size=0
  if [[ -f "${fake_log}" ]]; then
    after_size="$(wc -c < "${fake_log}")"
  fi
  [ "${before_size}" -eq "${after_size}" ]
}

# ---------------------------------------------------------------------------
# 9. wb prefix init fails with "prefix busy" when lock is held
# ---------------------------------------------------------------------------
@test "prefix init: fails with 'prefix busy' when another process holds the lock" {
  mkdir -p "${TEST_PFX}"

  local lockfile="${TEST_PFX}/.wb_lock"
  exec 8>"${lockfile}"
  flock -x 8

  run "${WB}" prefix init TESTPFX --dist "${TEST_DIST}"
  exec 8>&-

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"prefix busy"* ]] || [[ "${stderr}" == *"prefix busy"* ]] || \
    [[ "${output}" == *"busy"* ]] || [[ "${stderr}" == *"busy"* ]]
}

# ---------------------------------------------------------------------------
# 10. wb import-ppdb converts legacy-benign.ppdb to a valid JSON .wb.ppdb
# ---------------------------------------------------------------------------
@test "import-ppdb: legacy-benign.ppdb produces valid JSON output" {
  local input="${FIXTURE_PPDB}/legacy-benign.ppdb"
  local out_file="${TEST_HOME}/legacy-benign.ppdb.wb.ppdb"
  run "${WB}" import-ppdb "${input}" "${out_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"imported to:"* ]]
  [ -f "${out_file}" ]
  run jq empty "${out_file}"
  [ "${status}" -eq 0 ]
}

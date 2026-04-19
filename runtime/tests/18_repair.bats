#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
FIXTURE_WINE="${BATS_TEST_DIRNAME}/fixtures/fake-wine"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  mkdir -p "${TEST_HOME}/dist"
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-REPAIRTEST/"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-REPAIRTEST/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-REPAIRTEST/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-REPAIRTEST/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-REPAIRTEST/bin/wineserver"
  ln -sfn WINE-BLEEDING-REPAIRTEST "${TEST_HOME}/dist/WINE-BLEEDING"

  mkdir -p "${TEST_HOME}/prefixes"
  export TEST_DIST="${TEST_HOME}/dist/WINE-BLEEDING-REPAIRTEST"
  export TEST_PFX="${TEST_HOME}/prefixes/TESTPFX"

  # Initialise prefix and take initial snapshot
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
  "${WB}" prefix snapshot TESTPFX >/dev/null
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# Test 1: Blow away system32 DLLs then repair restores them
# ---------------------------------------------------------------------------
@test "repair: after removing system32 DLLs, repair restores them" {
  local sys32="${TEST_PFX}/drive_c/windows/system32"
  [ -d "${sys32}" ]
  # Verify d3d11.dll exists (deployed by DXVK during init)
  [ -f "${sys32}/d3d11.dll" ]
  # Blow it away
  rm -f "${sys32}/d3d11.dll"
  [ ! -f "${sys32}/d3d11.dll" ]
  # Repair
  run "${WB}" prefix repair TESTPFX --yes
  [ "${status}" -eq 0 ]
  # Verify restored
  [ -f "${sys32}/d3d11.dll" ]
}

# ---------------------------------------------------------------------------
# Test 2: Repair with --yes runs without prompt; exits 0
# ---------------------------------------------------------------------------
@test "repair: --yes flag skips prompt and exits 0" {
  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  run "${WB}" prefix repair TESTPFX --yes
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 3a: Repair without --yes and "N" at prompt aborts
# ---------------------------------------------------------------------------
@test "repair: without --yes, answering N aborts repair" {
  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  run bash -c "echo 'N' | '${WB}' prefix repair TESTPFX"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Aborted"* ]]
  # DLL should still be absent — repair was aborted
  [ ! -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll" ]
}

# ---------------------------------------------------------------------------
# Test 3b: Repair without --yes and "y" at prompt proceeds
# ---------------------------------------------------------------------------
@test "repair: without --yes, answering y proceeds with repair" {
  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  run bash -c "echo 'y' | '${WB}' prefix repair TESTPFX"
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll" ]
}

# ---------------------------------------------------------------------------
# Test 4: Repair without any snapshot exits 1 with clear error
# ---------------------------------------------------------------------------
@test "repair: no snapshot → exits 1 with error message" {
  # Create a new prefix with no snapshot
  "${WB}" prefix init NEWPFX --dist "${TEST_DIST}" >/dev/null
  run "${WB}" prefix repair NEWPFX --yes
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no snapshot"* || "${output}" == *"no snapshot"* ]]
}

# ---------------------------------------------------------------------------
# Test 5: Repair with --from-snapshot <UTC> uses that specific snapshot
# ---------------------------------------------------------------------------
@test "repair: --from-snapshot uses the specified snapshot" {
  # Capture a second snapshot
  local first_snap
  first_snap="$(ls "${TEST_HOME}/state/prefix-snapshots/TESTPFX/"*.json | sort | head -1)"
  # Extract UTC from snapshot JSON
  local snap_utc
  snap_utc="$(jq -r '.captured_utc' "${first_snap}")"

  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  run "${WB}" prefix repair TESTPFX --yes --from-snapshot "${snap_utc}"
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll" ]
}

# ---------------------------------------------------------------------------
# Test 6: After repair, .wb_components reflects the component versions
# ---------------------------------------------------------------------------
@test "repair: .wb_components is valid JSON after repair" {
  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  "${WB}" prefix repair TESTPFX --yes >/dev/null
  run jq empty "${TEST_PFX}/.wb_components"
  [ "${status}" -eq 0 ]
  run jq -r '.schema' "${TEST_PFX}/.wb_components"
  [ "${output}" = "1" ]
}

# ---------------------------------------------------------------------------
# Test 7: Repair leaves user data untouched
# ---------------------------------------------------------------------------
@test "repair: user data in drive_c is left untouched" {
  # Create a fake game save file
  local save_dir="${TEST_PFX}/drive_c/Program Files/GameX"
  mkdir -p "${save_dir}"
  echo "save data" > "${save_dir}/save.dat"

  rm -f "${TEST_PFX}/drive_c/windows/system32/d3d11.dll"
  "${WB}" prefix repair TESTPFX --yes >/dev/null

  # The save file must still exist and be unchanged
  [ -f "${save_dir}/save.dat" ]
  run cat "${save_dir}/save.dat"
  [ "${output}" = "save data" ]
}

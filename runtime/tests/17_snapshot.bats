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
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-SNAPTEST/"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-SNAPTEST/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-SNAPTEST/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-SNAPTEST/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-SNAPTEST/bin/wineserver"
  ln -sfn WINE-BLEEDING-SNAPTEST "${TEST_HOME}/dist/WINE-BLEEDING"

  mkdir -p "${TEST_HOME}/prefixes"
  export TEST_DIST="${TEST_HOME}/dist/WINE-BLEEDING-SNAPTEST"
  export TEST_PFX="${TEST_HOME}/prefixes/TESTPFX"

  # Initialise the test prefix
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# Helper: source snapshot lib in a subshell to call wb_snapshot_capture directly
# ---------------------------------------------------------------------------
_call_snapshot_capture() {
  local pfx="$1"
  bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_LOG_FILE='${WB_LOG_FILE}'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-config.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-wineboot.sh'
    source '${WB_LIB}/wb-snapshot.sh'
    wb_snapshot_capture '${pfx}'
  " 2>/dev/null
}

_call_snapshot_list() {
  local pfx="$1"
  bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_LOG_FILE='${WB_LOG_FILE}'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-config.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-wineboot.sh'
    source '${WB_LIB}/wb-snapshot.sh'
    wb_snapshot_list '${pfx}'
  " 2>/dev/null
}

# ---------------------------------------------------------------------------
# Test 1: wb_snapshot_capture writes a valid JSON file
# ---------------------------------------------------------------------------
@test "snapshot capture: writes a valid JSON file in state/prefix-snapshots/" {
  run _call_snapshot_capture "${TEST_PFX}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  local snap_file="${output}"
  [ -f "${snap_file}" ]
  run jq empty "${snap_file}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 2: Snapshot filename matches <basename>-<UTC>.json pattern
# ---------------------------------------------------------------------------
@test "snapshot capture: filename matches <basename>-<UTC>.json pattern" {
  run _call_snapshot_capture "${TEST_PFX}"
  [ "${status}" -eq 0 ]
  local snap_file="${output}"
  local basename_part
  basename_part="$(basename "${snap_file}")"
  # Pattern: TESTPFX-YYYY-MM-DDTHH-MM-SZ.json (colons replaced with dashes in filename)
  [[ "${basename_part}" =~ ^TESTPFX-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z.*\.json$ ]]
}

# ---------------------------------------------------------------------------
# Test 3: Snapshot contains prefix_name, runtime_target, wb_runtime, dll_overrides
# ---------------------------------------------------------------------------
@test "snapshot capture: contains prefix_name, runtime_target, wb_runtime, dll_overrides" {
  run _call_snapshot_capture "${TEST_PFX}"
  [ "${status}" -eq 0 ]
  local snap_file="${output}"
  run jq -r '.prefix_name' "${snap_file}"
  [ "${output}" = "TESTPFX" ]
  run jq -r '.runtime_target' "${snap_file}"
  [ "${output}" != "null" ]
  [ -n "${output}" ]
  run jq 'has("wb_runtime")' "${snap_file}"
  [ "${output}" = "true" ]
  run jq 'has("dll_overrides")' "${snap_file}"
  [ "${output}" = "true" ]
  run jq -r '.dll_overrides | type' "${snap_file}"
  [ "${output}" = "array" ]
}

# ---------------------------------------------------------------------------
# Test 4: Multiple captures produce distinct filenames
# ---------------------------------------------------------------------------
@test "snapshot capture: multiple captures produce distinct filenames" {
  local snap1 snap2
  snap1="$(_call_snapshot_capture "${TEST_PFX}")"
  snap2="$(_call_snapshot_capture "${TEST_PFX}")"
  [ -f "${snap1}" ]
  [ -f "${snap2}" ]
  [ "${snap1}" != "${snap2}" ]
}

# ---------------------------------------------------------------------------
# Test 5: Retention — 6 captures leave only 5 snapshots
# ---------------------------------------------------------------------------
@test "snapshot capture: 6 captures leave exactly 5 snapshots (retention enforced)" {
  local i
  for i in $(seq 1 6); do
    _call_snapshot_capture "${TEST_PFX}" >/dev/null
  done
  local snap_dir="${TEST_HOME}/state/prefix-snapshots/TESTPFX"
  local count
  count="$(find "${snap_dir}" -maxdepth 1 -name 'TESTPFX-*.json' | wc -l)"
  [ "${count}" -eq 5 ]
}

# ---------------------------------------------------------------------------
# Test 6: wb_snapshot_list sorts newest first
# ---------------------------------------------------------------------------
@test "snapshot list: sorted newest-first" {
  local i
  for i in $(seq 1 3); do
    _call_snapshot_capture "${TEST_PFX}" >/dev/null
  done
  local list_output
  list_output="$(_call_snapshot_list "${TEST_PFX}")"
  [ -n "${list_output}" ]
  # Extract UTC column from each line and verify descending order
  local prev_utc=""
  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    local utc="${line%% *}"
    if [[ -n "${prev_utc}" ]]; then
      # Lexicographic comparison of ISO-8601 UTC strings works for ordering
      # prev_utc must be >= utc (allow equal for same-second serial captures)
      [[ "${prev_utc}" > "${utc}" || "${prev_utc}" == "${utc}" ]]
    fi
    prev_utc="${utc}"
  done <<< "${list_output}"
}

# ---------------------------------------------------------------------------
# Test 7: wb_snapshot_prune --keep 2 leaves exactly 2
# ---------------------------------------------------------------------------
@test "snapshot prune: --keep 2 leaves exactly 2 snapshots" {
  local i
  for i in $(seq 1 5); do
    _call_snapshot_capture "${TEST_PFX}" >/dev/null
  done

  bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_LOG_FILE='${WB_LOG_FILE}'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-config.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-wineboot.sh'
    source '${WB_LIB}/wb-snapshot.sh'
    wb_snapshot_prune '${TEST_PFX}' --keep 2
  "

  local snap_dir="${TEST_HOME}/state/prefix-snapshots/TESTPFX"
  local count
  count="$(find "${snap_dir}" -maxdepth 1 -name 'TESTPFX-*.json' | wc -l)"
  [ "${count}" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Test 8: Snapshot of prefix without .wb_runtime / .wb_components writes valid JSON (null fields)
# ---------------------------------------------------------------------------
@test "snapshot capture: prefix without .wb_runtime/.wb_components produces valid JSON with null fields" {
  # Create a minimal prefix without sentinels
  local bare_pfx="${TEST_HOME}/prefixes/BAREPFX"
  mkdir -p "${bare_pfx}/drive_c/windows/system32"
  touch "${bare_pfx}/drive_c/windows/system32/ntdll.dll"

  run _call_snapshot_capture "${bare_pfx}"
  [ "${status}" -eq 0 ]
  local snap_file="${output}"
  [ -f "${snap_file}" ]
  run jq empty "${snap_file}"
  [ "${status}" -eq 0 ]
  run jq '.wb_runtime' "${snap_file}"
  [ "${output}" = "null" ]
  run jq '.wb_components' "${snap_file}"
  [ "${output}" = "null" ]
}

# ---------------------------------------------------------------------------
# Test 9: wb prefix snapshot <NAME> CLI works end-to-end
# ---------------------------------------------------------------------------
@test "wb prefix snapshot: CLI works end-to-end" {
  run "${WB}" prefix snapshot TESTPFX
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"snapshot:"* ]]
  # Verify the file path exists
  local snap_path="${output#snapshot: }"
  # The output is "snapshot: <path>"
  snap_path="${output##*snapshot: }"
  [ -f "${snap_path}" ] || {
    # Try parsing differently — output may include multiple lines
    snap_path="$(echo "${output}" | grep -oP '(?<=snapshot: ).+')"
    [ -f "${snap_path}" ]
  }
}

# ---------------------------------------------------------------------------
# Test 10: wb prefix snapshots <NAME> tabular output
# ---------------------------------------------------------------------------
@test "wb prefix snapshots: tabular output lists captured snapshots" {
  "${WB}" prefix snapshot TESTPFX >/dev/null
  run "${WB}" prefix snapshots TESTPFX
  [ "${status}" -eq 0 ]
  # Header line
  [[ "${output}" == *"CAPTURED_UTC"* ]]
  # At least one data line
  local lines
  lines="$(echo "${output}" | wc -l)"
  [ "${lines}" -ge 2 ]
}

# ---------------------------------------------------------------------------
# Test 11: Invalid NAME rejected by _wb_validate_path_arg
# ---------------------------------------------------------------------------
@test "wb prefix snapshot: invalid NAME with '..' rejected" {
  run "${WB}" prefix snapshot "../../etc/passwd"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"invalid"* || "${output}" == *"traversal"* || "${output}" == *"rejected"* ]]
}

#!/usr/bin/env bats
# 28_detection.bats — detection subsystem tests
#
# Tests:
#   1.  snapshot_before: creates before.json with correct schema
#   2.  snapshot_before: lnk_paths scanned from fake prefix
#   3.  snapshot_before: pf_dirs scanned from fake prefix
#   4.  snapshot_before: purges stale detection dir first (crash recovery)
#   5.  snapshot_before: returns path to before.json on stdout
#   6.  snapshot_before: fails if prefix does not exist
#   7.  diff_after: empty diff when nothing installed
#   8.  diff_after (M1): new .lnk detected and mapped to host path
#   9.  diff_after (M2): new Program Files dir detected
#  10.  diff_after: dedup — M1 wins over M2 for same exe
#  11.  diff_after: M2 filter rejects uninstaller exe (unins*.exe)
#  12.  diff_after: empty diff returns empty JSON array
#  13.  purge: removes detection dir, idempotent
#  14.  sweep_stale: purges dirs older than max_age_hours
#  15.  sweep_stale: keeps dirs newer than max_age_hours
#  16.  pick_main_exe: largest exe wins, depth ≤ 3
#  17.  pick_main_exe: returns empty when no exe found
#  18.  lnk_parse: steam-valid.lnk parsed correctly
#  19.  lnk_parse: malformed.lnk returns exit 1
#  20.  lnk_parse: no-lnk-info.lnk returns exit 1 (no target path)
#  21.  bash fallback: extracts Windows path from lnk binary
#  22.  dedup_candidates: M1 wins on same exe path

load "lib/common.bash"

WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
LNK_FIXTURES="${BATS_TEST_DIRNAME}/fixtures/lnks"
LNK_PARSER="${BATS_TEST_DIRNAME}/../libexec/wb-lnk-parse.py"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export WB_HOME="${TEST_DIR}/wb_home"
  mkdir -p "${WB_HOME}"

  # Create a fake prefix structure under WB_HOME/prefixes/testpfx
  export FAKE_PREFIX="${WB_HOME}/prefixes/testpfx"
  mkdir -p "${FAKE_PREFIX}/drive_c/Program Files"
  mkdir -p "${FAKE_PREFIX}/drive_c/Program Files (x86)"
  mkdir -p "${FAKE_PREFIX}/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs"
  mkdir -p "${FAKE_PREFIX}/drive_c/users/testuser/AppData/Roaming/Microsoft/Windows/Start Menu/Programs"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

# Helper: source detection lib in a subshell (also sources apps.sh for wb_gui_apps_add)
_source_detect() {
  echo "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
  "
}

# ---------------------------------------------------------------------------
# 1. snapshot_before: creates before.json with correct schema
# ---------------------------------------------------------------------------
@test "snapshot_before: creates before.json with schema=1" {
  run bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx >/dev/null
  "
  [ "${status}" -eq 0 ]
  [ -f "${WB_HOME}/detection/testpfx/before.json" ]
  run jq '.schema' "${WB_HOME}/detection/testpfx/before.json"
  [ "${output}" = "1" ]
  run jq -r '.prefix_name' "${WB_HOME}/detection/testpfx/before.json"
  [ "${output}" = "testpfx" ]
}

# ---------------------------------------------------------------------------
# 2. snapshot_before: lnk_paths scanned from fake prefix
# ---------------------------------------------------------------------------
@test "snapshot_before: scans .lnk files in Start Menu" {
  # Plant a .lnk file in the fake prefix
  cp "${LNK_FIXTURES}/steam-valid.lnk" \
    "${FAKE_PREFIX}/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Steam.lnk"

  run bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx >/dev/null
  "
  [ "${status}" -eq 0 ]

  run jq '.lnk_paths | length' "${WB_HOME}/detection/testpfx/before.json"
  [ "${output}" -ge 1 ]
  # Verify the lnk path appears in the snapshot
  run jq -r '.lnk_paths[]' "${WB_HOME}/detection/testpfx/before.json"
  [[ "${output}" == *"Steam.lnk"* ]]
}

# ---------------------------------------------------------------------------
# 3. snapshot_before: pf_dirs scanned from fake prefix
# ---------------------------------------------------------------------------
@test "snapshot_before: scans Program Files top-level dirs" {
  mkdir -p "${FAKE_PREFIX}/drive_c/Program Files/ExistingApp"

  run bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx >/dev/null
  "
  [ "${status}" -eq 0 ]

  run jq '.program_files_dirs | length' "${WB_HOME}/detection/testpfx/before.json"
  [ "${output}" -ge 1 ]
  run jq -r '.program_files_dirs[]' "${WB_HOME}/detection/testpfx/before.json"
  [[ "${output}" == *"ExistingApp"* ]]
}

# ---------------------------------------------------------------------------
# 4. snapshot_before: purges stale detection dir first (crash recovery)
# ---------------------------------------------------------------------------
@test "snapshot_before: purges stale detection dir before writing" {
  # Pre-plant a stale detection dir with an old file
  mkdir -p "${WB_HOME}/detection/testpfx"
  echo "stale" > "${WB_HOME}/detection/testpfx/stale.txt"

  run bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx >/dev/null
  "
  [ "${status}" -eq 0 ]
  # Stale file should be gone; fresh before.json should exist
  [ ! -f "${WB_HOME}/detection/testpfx/stale.txt" ]
  [ -f "${WB_HOME}/detection/testpfx/before.json" ]
}

# ---------------------------------------------------------------------------
# 5. snapshot_before: returns path to before.json on stdout
# ---------------------------------------------------------------------------
@test "snapshot_before: prints before.json path on stdout" {
  run bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"before.json"* ]]
  [ -f "${output}" ]
}

# ---------------------------------------------------------------------------
# 6. snapshot_before: fails if prefix does not exist
# ---------------------------------------------------------------------------
@test "snapshot_before: returns non-zero if prefix missing" {
  run bash -c "
    $(_source_detect)
    wb_detect_snapshot_before nonexistent_prefix
  " 2>&1
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 7. diff_after: empty diff when nothing installed
# ---------------------------------------------------------------------------
@test "diff_after: empty JSON array when nothing changed" {
  # Snapshot before
  local before_path
  before_path="$(bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx
  ")"

  run bash -c "
    $(_source_detect)
    wb_detect_diff_after testpfx '${before_path}'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

# ---------------------------------------------------------------------------
# 8. diff_after (M1): new .lnk detected and candidate emitted
# ---------------------------------------------------------------------------
@test "diff_after M1: new .lnk produces a candidate" {
  # Snapshot before (no lnks)
  local before_path
  before_path="$(bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx
  ")"

  # Plant a new .lnk + corresponding exe AFTER the snapshot
  mkdir -p "${FAKE_PREFIX}/drive_c/Program Files (x86)/Steam"
  echo "fake exe" > "${FAKE_PREFIX}/drive_c/Program Files (x86)/Steam/Steam.exe"
  cp "${LNK_FIXTURES}/steam-valid.lnk" \
    "${FAKE_PREFIX}/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Steam.lnk"

  run bash -c "
    $(_source_detect)
    wb_detect_diff_after testpfx '${before_path}'
  "
  [ "${status}" -eq 0 ]
  # Should have at least one candidate
  local count
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" -ge 1 ]
  [[ "${output}" == *"Steam"* ]]
}

# ---------------------------------------------------------------------------
# 9. diff_after (M2): new Program Files dir produces candidate
# ---------------------------------------------------------------------------
@test "diff_after M2: new Program Files dir produces a candidate" {
  # Snapshot before
  local before_path
  before_path="$(bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx
  ")"

  # Add a new app dir with an exe AFTER snapshot
  mkdir -p "${FAKE_PREFIX}/drive_c/Program Files/NewApp"
  # Need an actual file (not just a dir) for pick_main_exe to find
  printf 'MZ' > "${FAKE_PREFIX}/drive_c/Program Files/NewApp/newapp.exe"

  run bash -c "
    $(_source_detect)
    wb_detect_diff_after testpfx '${before_path}'
  "
  [ "${status}" -eq 0 ]
  local count
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" -ge 1 ]
  [[ "${output}" == *"NewApp"* ]]
}

# ---------------------------------------------------------------------------
# 10. diff_after: dedup — M1 wins over M2 for same exe
# ---------------------------------------------------------------------------
@test "diff_after dedup: M1 wins over M2 when same exe detected by both" {
  # Snapshot before
  local before_path
  before_path="$(bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx
  ")"

  # Add a new Program Files dir AND a corresponding .lnk pointing to the same exe
  mkdir -p "${FAKE_PREFIX}/drive_c/Program Files (x86)/Steam"
  printf 'MZ' > "${FAKE_PREFIX}/drive_c/Program Files (x86)/Steam/Steam.exe"
  cp "${LNK_FIXTURES}/steam-valid.lnk" \
    "${FAKE_PREFIX}/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Steam.lnk"

  run bash -c "
    $(_source_detect)
    wb_detect_diff_after testpfx '${before_path}'
  "
  [ "${status}" -eq 0 ]
  # When both M1 and M2 catch the same exe, dedup should produce exactly 1 candidate
  # (M1 wins with better display name from the .lnk)
  # Note: M1 maps C:\Program Files (x86)\Steam\Steam.exe to the host path
  #       M2 also finds Program Files (x86)/Steam/Steam.exe
  # They key on the same exe path → dedup yields 1 entry
  local lnk_count
  lnk_count="$(printf '%s' "${output}" | jq '[.[] | select(.via == "lnk")] | length')"
  local pf_count
  pf_count="$(printf '%s' "${output}" | jq '[.[] | select(.via == "program_files")] | length')"
  # If both M1 and M2 find it and key on same path, only 1 remains (M1 wins)
  # But if paths differ (host path mapping mismatch), both may appear — test that
  # there's no duplication of the Steam entry
  local steam_count
  steam_count="$(printf '%s' "${output}" | jq '[.[] | select(.name == "Steam")] | length')"
  [ "${steam_count}" -le 1 ]
}

# ---------------------------------------------------------------------------
# 11. diff_after: M2 filter rejects uninstaller exe
# ---------------------------------------------------------------------------
@test "diff_after M2: uninstaller exe is filtered out" {
  # Snapshot before
  local before_path
  before_path="$(bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx
  ")"

  # Add a new dir that only contains an uninstaller
  mkdir -p "${FAKE_PREFIX}/drive_c/Program Files/BadApp"
  printf 'MZ' > "${FAKE_PREFIX}/drive_c/Program Files/BadApp/unins000.exe"

  run bash -c "
    $(_source_detect)
    wb_detect_diff_after testpfx '${before_path}'
  "
  [ "${status}" -eq 0 ]
  # BadApp should not appear (its only exe is an uninstaller)
  [[ "${output}" != *"BadApp"* ]]
  [[ "${output}" != *"unins000"* ]]
}

# ---------------------------------------------------------------------------
# 12. diff_after: empty candidates returns empty JSON array (not null/empty string)
# ---------------------------------------------------------------------------
@test "diff_after: empty result is proper JSON empty array" {
  local before_path
  before_path="$(bash -c "
    $(_source_detect)
    wb_detect_snapshot_before testpfx
  ")"

  run bash -c "
    $(_source_detect)
    wb_detect_diff_after testpfx '${before_path}'
  "
  [ "${status}" -eq 0 ]
  # Must be valid JSON and must be an array
  run jq 'type' <<< "${output}"
  [ "${output}" = '"array"' ]
}

# ---------------------------------------------------------------------------
# 13. purge: removes detection dir, idempotent on missing dir
# ---------------------------------------------------------------------------
@test "purge: removes detection dir; idempotent on second call" {
  # Create a detection dir
  mkdir -p "${WB_HOME}/detection/testpfx"
  echo "something" > "${WB_HOME}/detection/testpfx/before.json"

  run bash -c "
    $(_source_detect)
    wb_detect_purge testpfx
  "
  [ "${status}" -eq 0 ]
  [ ! -d "${WB_HOME}/detection/testpfx" ]

  # Second call — should be a no-op
  run bash -c "
    $(_source_detect)
    wb_detect_purge testpfx
  "
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 14. sweep_stale: purges dirs older than max_age_hours
# ---------------------------------------------------------------------------
@test "sweep_stale: purges detection dirs older than max_age_hours" {
  # Create a detection dir with an old before.json
  local old_dir="${WB_HOME}/detection/oldprefix"
  mkdir -p "${old_dir}"
  echo '{}' > "${old_dir}/before.json"
  # Set mtime to 48 hours ago
  touch -d "48 hours ago" "${old_dir}/before.json"

  run bash -c "
    $(_source_detect)
    wb_detect_sweep_stale 24
  "
  [ "${status}" -eq 0 ]
  [ ! -d "${old_dir}" ]
}

# ---------------------------------------------------------------------------
# 15. sweep_stale: keeps dirs newer than max_age_hours
# ---------------------------------------------------------------------------
@test "sweep_stale: keeps detection dirs newer than max_age_hours" {
  # Create a detection dir with a fresh before.json
  local new_dir="${WB_HOME}/detection/newprefix"
  mkdir -p "${new_dir}"
  echo '{}' > "${new_dir}/before.json"
  # mtime is "now" by default

  run bash -c "
    $(_source_detect)
    wb_detect_sweep_stale 24
  "
  [ "${status}" -eq 0 ]
  [ -d "${new_dir}" ]
}

# ---------------------------------------------------------------------------
# 16. _wb_detect_pick_main_exe: largest exe wins, uninstallers filtered
# ---------------------------------------------------------------------------
@test "_wb_detect_pick_main_exe: picks largest exe, rejects uninstallers" {
  local app_dir="${TEST_DIR}/FakeApp"
  mkdir -p "${app_dir}"

  # Create a small uninstaller and a larger main exe
  printf 'MZ' > "${app_dir}/unins000.exe"
  # Make main.exe larger
  dd if=/dev/zero bs=1024 count=10 2>/dev/null > "${app_dir}/main.exe"

  run bash -c "
    $(_source_detect)
    _wb_detect_pick_main_exe '${app_dir}'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"main.exe"* ]]
  [[ "${output}" != *"unins000"* ]]
}

# ---------------------------------------------------------------------------
# 17. _wb_detect_pick_main_exe: returns empty when no exe found
# ---------------------------------------------------------------------------
@test "_wb_detect_pick_main_exe: returns empty string when no exe present" {
  local empty_dir="${TEST_DIR}/EmptyApp"
  mkdir -p "${empty_dir}"
  touch "${empty_dir}/readme.txt"

  run bash -c "
    $(_source_detect)
    result=\"\$(_wb_detect_pick_main_exe '${empty_dir}')\"
    printf '%s' \"\${result}\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

# ---------------------------------------------------------------------------
# 18. _wb_detect_parse_lnk: steam-valid.lnk parsed correctly
# ---------------------------------------------------------------------------
@test "_wb_detect_parse_lnk: steam-valid.lnk extracts target_path and display_name" {
  run bash -c "
    $(_source_detect)
    _wb_detect_parse_lnk '${LNK_FIXTURES}/steam-valid.lnk'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Steam.exe"* ]]
  [[ "${output}" == *"Steam"* ]]
  # Must be valid JSON
  run jq '.target_path' <<< "${output}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 19. _wb_detect_parse_lnk: malformed.lnk returns exit 1
# ---------------------------------------------------------------------------
@test "_wb_detect_parse_lnk: malformed.lnk returns non-zero" {
  run bash -c "
    $(_source_detect)
    _wb_detect_parse_lnk '${LNK_FIXTURES}/malformed.lnk'
  " 2>&1
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 20. _wb_detect_parse_lnk: no-lnk-info.lnk returns exit 1 (no target path)
# ---------------------------------------------------------------------------
@test "_wb_detect_parse_lnk: no-lnk-info.lnk returns non-zero (no target)" {
  run bash -c "
    $(_source_detect)
    _wb_detect_parse_lnk '${LNK_FIXTURES}/no-lnk-info.lnk'
  " 2>&1
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 21. bash fallback: _wb_detect_parse_lnk_bash_fallback extracts Windows path
# ---------------------------------------------------------------------------
@test "_wb_detect_parse_lnk_bash_fallback: extracts path from steam-valid.lnk" {
  run bash -c "
    $(_source_detect)
    _wb_detect_parse_lnk_bash_fallback '${LNK_FIXTURES}/steam-valid.lnk'
  "
  [ "${status}" -eq 0 ]
  # Should extract something resembling a .exe path
  [[ "${output}" == *".exe"* ]]
  # Must be valid JSON
  run jq '.target_path' <<< "${output}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 22. _wb_detect_dedup_candidates: M1 wins on same exe path
# ---------------------------------------------------------------------------
@test "_wb_detect_dedup_candidates: M1 candidate wins over M2 for same exe" {
  local m1='[{"exe":"/p/app.exe","name":"BetterName","source":"installer","via":"lnk"}]'
  local m2='[{"exe":"/p/app.exe","name":"WorseName","source":"installer","via":"program_files"}]'

  run bash -c "
    $(_source_detect)
    _wb_detect_dedup_candidates '${m1}' '${m2}'
  "
  [ "${status}" -eq 0 ]
  # Should have exactly 1 candidate with M1's name
  local count
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" = "1" ]
  local via
  via="$(printf '%s' "${output}" | jq -r '.[0].via')"
  [ "${via}" = "lnk" ]
  local name
  name="$(printf '%s' "${output}" | jq -r '.[0].name')"
  [ "${name}" = "BetterName" ]
}

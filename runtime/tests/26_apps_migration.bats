#!/usr/bin/env bats
# 26_apps_migration.bats — games.json → apps.json migration tests + shim forwarding
#
# Tests:
#   1.  Clean migration: 0-entry games.json → empty apps.json
#   2.  Clean migration: 5-entry games.json → 5-entry apps.json
#   3.  Field mapping: added_utc → added_at, source synthesised as "detected"
#   4.  games.json archived (not deleted) with .migrated-<UTC> suffix
#   5.  Sentinel .games-migrated created on success
#   6.  Idempotent: second run is a no-op (sentinel guards it)
#   7.  Crash recovery: apps.json + games.json present, no sentinel → re-runs cleanly
#   8.  No games.json → empty apps.json created, sentinel set
#   9.  Malformed games.json → migration refused, returns non-zero, no sentinel
#  10.  Wrong games.json schema → migration refused
#  11.  Shim wb_gui_games_add → apps.json also written (dual-write)
#  12.  Shim wb_gui_games_list → reads apps.json content (via games.json dual-write)
#  13.  Shim wb_gui_games_remove → removes from both registries

load "lib/common.bash"

WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export WB_HOME="${TEST_DIR}/wb_home"
  mkdir -p "${WB_HOME}"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

# Helper: source the apps lib in a subshell
_source_apps() {
  echo "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
  "
}

# Helper: create a valid games.json with N entries
_make_games_json() {
  local count="${1:-1}"
  local games_array=""
  local i
  for (( i=0; i<count; i++ )); do
    local entry
    entry="{\"id\":\"aaaaaaaa-bbbb-cccc-dddd-${i}${i}${i}${i}${i}${i}${i}${i}${i}${i}${i}${i}\",\"name\":\"Game${i}\",\"exe\":\"/tmp/game${i}.exe\",\"prefix\":\"prefix${i}\",\"added_utc\":\"2025-01-0${i}T00:00:00Z\"}"
    if [[ -z "${games_array}" ]]; then
      games_array="${entry}"
    else
      games_array="${games_array},${entry}"
    fi
  done
  printf '{"schema":1,"games":[%s]}' "${games_array}" > "${WB_HOME}/games.json"
}

# ---------------------------------------------------------------------------
# 1. Clean migration: empty games.json → empty apps.json
# ---------------------------------------------------------------------------
@test "migration: empty games.json produces empty apps.json" {
  printf '{"schema":1,"games":[]}' > "${WB_HOME}/games.json"

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]
  [ -f "${WB_HOME}/apps.json" ]
  run jq '.apps | length' "${WB_HOME}/apps.json"
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
  run jq '.schema' "${WB_HOME}/apps.json"
  [ "${output}" = "2" ]
}

# ---------------------------------------------------------------------------
# 2. Clean migration: 5-entry games.json → 5-entry apps.json
# ---------------------------------------------------------------------------
@test "migration: 5-entry games.json → 5-entry apps.json" {
  _make_games_json 5

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]
  [ -f "${WB_HOME}/apps.json" ]
  run jq '.apps | length' "${WB_HOME}/apps.json"
  [ "${status}" -eq 0 ]
  [ "${output}" = "5" ]
}

# ---------------------------------------------------------------------------
# 3. Field mapping: added_utc → added_at, source = "detected"
# ---------------------------------------------------------------------------
@test "migration: field mapping is correct (added_utc→added_at, source=detected)" {
  printf '{"schema":1,"games":[{"id":"11111111-1111-1111-1111-111111111111","name":"TestApp","exe":"/tmp/test.exe","prefix":"testpfx","added_utc":"2025-06-01T12:00:00Z"}]}' \
    > "${WB_HOME}/games.json"

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]

  run jq -r '.apps[0].added_at' "${WB_HOME}/apps.json"
  [ "${output}" = "2025-06-01T12:00:00Z" ]

  run jq -r '.apps[0].source' "${WB_HOME}/apps.json"
  [ "${output}" = "detected" ]

  run jq -r '.apps[0].last_played' "${WB_HOME}/apps.json"
  [ "${output}" = "2025-06-01T12:00:00Z" ]

  run jq '.apps[0].wine_args' "${WB_HOME}/apps.json"
  [ "${output}" = "[]" ]

  run jq '.apps[0].env_vars' "${WB_HOME}/apps.json"
  [ "${output}" = "{}" ]

  run jq '.apps[0].dist' "${WB_HOME}/apps.json"
  [ "${output}" = "null" ]

  run jq '.apps[0].icon_path' "${WB_HOME}/apps.json"
  [ "${output}" = "null" ]
}

# ---------------------------------------------------------------------------
# 4. games.json archived with .migrated-<UTC> suffix (not deleted)
# ---------------------------------------------------------------------------
@test "migration: games.json archived, not deleted" {
  printf '{"schema":1,"games":[]}' > "${WB_HOME}/games.json"

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]

  # Original games.json should be gone
  [ ! -f "${WB_HOME}/games.json" ]

  # Archive should exist with .migrated- suffix
  local archive_count
  archive_count="$(ls "${WB_HOME}"/games.json.migrated-* 2>/dev/null | wc -l)"
  [ "${archive_count}" -ge 1 ]
}

# ---------------------------------------------------------------------------
# 5. Sentinel .games-migrated created on success
# ---------------------------------------------------------------------------
@test "migration: sentinel .games-migrated created on success" {
  printf '{"schema":1,"games":[]}' > "${WB_HOME}/games.json"

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]
  [ -f "${WB_HOME}/.games-migrated" ]
}

# ---------------------------------------------------------------------------
# 6. Idempotent: second run is a no-op (sentinel guards it)
# ---------------------------------------------------------------------------
@test "migration: idempotent — second run outputs 'already migrated'" {
  printf '{"schema":1,"games":[{"id":"22222222-2222-2222-2222-222222222222","name":"A","exe":"/tmp/a.exe","prefix":"a","added_utc":"2025-01-01T00:00:00Z"}]}' \
    > "${WB_HOME}/games.json"

  # First run
  bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "

  # Capture state after first run
  local first_count
  first_count="$(jq '.apps | length' "${WB_HOME}/apps.json")"

  # Second run
  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already migrated"* ]]

  # apps.json unchanged
  run jq '.apps | length' "${WB_HOME}/apps.json"
  [ "${output}" = "${first_count}" ]
}

# ---------------------------------------------------------------------------
# 7. Crash recovery: apps.json + games.json present, no sentinel → re-runs
# ---------------------------------------------------------------------------
@test "migration: crash recovery — apps.json + games.json + no sentinel → re-migrates" {
  printf '{"schema":1,"games":[{"id":"33333333-3333-3333-3333-333333333333","name":"B","exe":"/tmp/b.exe","prefix":"b","added_utc":"2025-02-01T00:00:00Z"}]}' \
    > "${WB_HOME}/games.json"
  # Plant an apps.json (simulating a partial prior run that wrote apps.json but crashed
  # before renaming games.json or touching the sentinel)
  printf '{"schema":2,"apps":[]}' > "${WB_HOME}/apps.json"
  # No sentinel

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]
  # Sentinel should now exist
  [ -f "${WB_HOME}/.games-migrated" ]
  # apps.json should have 1 entry (re-migrated from games.json)
  run jq '.apps | length' "${WB_HOME}/apps.json"
  [ "${output}" = "1" ]
}

# ---------------------------------------------------------------------------
# 8. No games.json → empty apps.json created, sentinel set
# ---------------------------------------------------------------------------
@test "migration: no games.json → empty apps.json + sentinel created" {
  # WB_HOME has no games.json
  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"no games.json"* ]]
  [ -f "${WB_HOME}/apps.json" ]
  [ -f "${WB_HOME}/.games-migrated" ]
  run jq '.apps | length' "${WB_HOME}/apps.json"
  [ "${output}" = "0" ]
}

# ---------------------------------------------------------------------------
# 9. Malformed games.json → migration refused, returns non-zero, no sentinel
# ---------------------------------------------------------------------------
@test "migration: malformed games.json → non-zero exit, no sentinel" {
  printf 'not valid json {{{' > "${WB_HOME}/games.json"

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  " 2>&1
  [ "${status}" -ne 0 ]
  [ ! -f "${WB_HOME}/.games-migrated" ]
}

# ---------------------------------------------------------------------------
# 10. Wrong schema version → migration refused
# ---------------------------------------------------------------------------
@test "migration: games.json schema != 1 → non-zero exit, no sentinel" {
  printf '{"schema":99,"games":[]}' > "${WB_HOME}/games.json"

  run bash -c "
    $(_source_apps)
    wb_gui_apps_migrate_from_games
  " 2>&1
  [ "${status}" -ne 0 ]
  [ ! -f "${WB_HOME}/.games-migrated" ]
}

# ---------------------------------------------------------------------------
# 11. Shim wb_gui_games_add → apps.json also written (dual-write)
# ---------------------------------------------------------------------------
@test "shim: wb_gui_games_add writes both games.json and apps.json" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '/tmp/ShimGame.exe' 'shimprefix'
  "
  [ "${status}" -eq 0 ]

  # Both registries should be written
  [ -f "${WB_HOME}/games.json" ]
  [ -f "${WB_HOME}/apps.json" ]

  # Both should have the entry
  run jq -r '.games[0].exe' "${WB_HOME}/games.json"
  [ "${output}" = "/tmp/ShimGame.exe" ]

  run jq -r '.apps[0].exe' "${WB_HOME}/apps.json"
  [ "${output}" = "/tmp/ShimGame.exe" ]
}

# ---------------------------------------------------------------------------
# 12. Shim wb_gui_games_list returns entries (reads games.json)
# ---------------------------------------------------------------------------
@test "shim: wb_gui_games_list returns added entry" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '/tmp/ListGame.exe' 'listpfx'
    wb_gui_games_list
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ListGame"* ]]
}

# ---------------------------------------------------------------------------
# 13. Shim wb_gui_games_remove → removes from both registries
# ---------------------------------------------------------------------------
@test "shim: wb_gui_games_remove removes from both games.json and apps.json" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    gid=\"\$(wb_gui_games_add '/tmp/RemGame.exe' 'rempfx')\"
    wb_gui_games_remove \"\${gid}\"
    # Both should be empty now
    games_count=\"\$(jq '.games | length' '${WB_HOME}/games.json')\"
    apps_count=\"\$(jq '.apps | length' '${WB_HOME}/apps.json')\"
    echo \"games:\${games_count} apps:\${apps_count}\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"games:0"* ]]
  [[ "${output}" == *"apps:0"* ]]
}

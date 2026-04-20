#!/usr/bin/env bats
# 24_gui.bats — M12 GUI + games registry tests
#
# Mock-yad protocol:
#   - $WB_TEST_YAD_RESPONSE (path to file): fake-yad cats this file to stdout
#   - $WB_TEST_YAD_RESPONSE_RC: fake-yad exits with this code (default 0)
#   - $WB_TEST_YAD_LOG (path to file): fake-yad appends each argv invocation here
#
# Tests prepend runtime/tests/fixtures/fake-yad/ to PATH so that the real yad
# is never called, even if installed on the test host.

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_GUI="${BATS_TEST_DIRNAME}/../src/wb-gui"
WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FAKE_YAD_DIR="${BATS_TEST_DIRNAME}/fixtures/fake-yad"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export WB_HOME="${TEST_DIR}/wb_home"
  export WB_TEST_YAD_LOG="${TEST_DIR}/yad.log"
  export WB_TEST_YAD_RESPONSE="${TEST_DIR}/yad_response.txt"
  export WB_TEST_YAD_RESPONSE_RC="0"
  mkdir -p "${WB_HOME}"
  # Prepend fake-yad to PATH so wb-gui picks it up.
  # We also record the augmented PATH in WB_TEST_PATH so tests can pass it
  # into bash -c subshells as a literal (already-expanded) value.
  export PATH="${FAKE_YAD_DIR}:${PATH}"
  export WB_TEST_PATH="${PATH}"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

# Helper: source wb-gui libraries in a subshell
_source_gui_libs() {
  local wb_lib="${WB_LIB}"
  local gui_lib="${WB_GUI_LIB}"
  source "${wb_lib}/wb-paths.sh"
  source "${wb_lib}/wb-json.sh"
  source "${wb_lib}/wb-log.sh"
  source "${gui_lib}/wb-gui-games.sh"
  source "${gui_lib}/wb-gui-dialogs.sh"
}

# ---------------------------------------------------------------------------
# 1. wb-gui --version prints version and exits 0
# ---------------------------------------------------------------------------
@test "wb-gui --version prints version and exits 0" {
  run "${WB_GUI}" --version
  [ "${status}" -eq 0 ]
  [[ "${output}" == wb-gui\ * ]]
}

# ---------------------------------------------------------------------------
# 2. wb_gui_games_add creates games.json with valid JSON
# ---------------------------------------------------------------------------
@test "wb_gui_games_add creates games.json with valid JSON" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '/tmp/FakeGame.exe' 'FakeGame'
  "
  [ "${status}" -eq 0 ]
  local reg="${WB_HOME}/games.json"
  [ -f "${reg}" ]
  run jq empty "${reg}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. wb_gui_games_list returns the added game
# ---------------------------------------------------------------------------
@test "wb_gui_games_list returns the added game" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '/tmp/FakeGame.exe' 'FakeGame'
    wb_gui_games_list
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *FakeGame* ]]
}

# ---------------------------------------------------------------------------
# 4. wb_gui_games_remove removes the game entry
# ---------------------------------------------------------------------------
@test "wb_gui_games_remove removes the game entry" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    gid=\"\$(wb_gui_games_add '/tmp/FakeGame.exe' 'FakeGame')\"
    wb_gui_games_remove \"\${gid}\"
    # List should now be empty
    count=\"\$(wb_gui_games_list | wc -l)\"
    # Empty output means 0 or 1 blank line; tolerate both
    wb_gui_games_list | grep -c 'FakeGame' || true
  "
  [ "${status}" -eq 0 ]
  # After remove, FakeGame must not appear
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    gid=\"\$(wb_gui_games_add '/tmp/RmGame.exe' 'RmGame')\"
    wb_gui_games_remove \"\${gid}\"
    wb_gui_games_list
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" != *RmGame* ]]
}

# ---------------------------------------------------------------------------
# 5. wb-gui add-game with fake-yad returns successfully; games.json has entry
# ---------------------------------------------------------------------------
@test "wb-gui add-game via mock-yad creates games.json entry" {
  # fake-yad returns the exe path on file-selection prompt,
  # then returns the prefix name on entry prompt
  # First call (file dialog) returns the exe path
  # Second call (entry dialog) returns the prefix name
  # We use a counter-based approach via separate response files
  # Simplest: pre-supply the exe path on the command line to skip file dialog

  # For the entry dialog (prefix name), fake-yad returns 'TestGame'
  printf 'TestGame\n' > "${WB_TEST_YAD_RESPONSE}"

  # PATH is already set in setup() to include fake-yad; pass the expanded
  # value as WB_TEST_PATH so the bash -c subshell gets the real PATH.
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE_RC=0
    '${WB_GUI}' add-game /tmp/TestGame.exe
  "
  [ "${status}" -eq 0 ]
  local reg="${WB_HOME}/games.json"
  [ -f "${reg}" ]
  run jq -r '.games[0].exe' "${reg}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "/tmp/TestGame.exe" ]
}

# ---------------------------------------------------------------------------
# 6. Schema validation: invalid games.json is rejected with clear error
# ---------------------------------------------------------------------------
@test "wb_gui_games_list rejects malformed games.json" {
  # Plant a malformed games.json
  mkdir -p "${WB_HOME}"
  printf 'not valid json {{' > "${WB_HOME}/games.json"

  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_list
  "
  [ "${status}" -ne 0 ]
  [[ "${output}" == *malformed* ]] || [[ "${stderr}" == *malformed* ]]
}

# ---------------------------------------------------------------------------
# 7. wb-gui settings writes .wb.ppdb next to the exe with correct toggles
# ---------------------------------------------------------------------------
@test "wb-gui settings writes .wb.ppdb with form values" {
  # Register a game first
  local exe_dir="${TEST_DIR}/games"
  mkdir -p "${exe_dir}"
  local exe="${exe_dir}/MyGame.exe"
  touch "${exe}"

  # Add game to registry
  bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '${exe}' 'MyGame'
  "

  # Fake-yad returns form output (pipe-separated: DXVK|VKD3D|NVAPI|ESYNC|FSYNC|HUD|OVERRIDES)
  printf 'TRUE|FALSE|FALSE|TRUE|FALSE||' > "${WB_TEST_YAD_RESPONSE}"
  export WB_TEST_YAD_RESPONSE_RC=0

  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE_RC=0
    '${WB_GUI}' settings MyGame
  "
  [ "${status}" -eq 0 ]
  local ppdb="${exe_dir}/.wb.ppdb"
  [ -f "${ppdb}" ]
  run jq empty "${ppdb}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 8. DXVK off -> .wb.ppdb has "WB_DXVK": "0" in env
# ---------------------------------------------------------------------------
@test "DXVK off: .wb.ppdb env.WB_DXVK is 0" {
  local exe_dir="${TEST_DIR}/games2"
  mkdir -p "${exe_dir}"
  local exe="${exe_dir}/NoD3D.exe"
  touch "${exe}"

  bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '${exe}' 'NoD3D'
  "

  # DXVK=FALSE in form output
  printf 'FALSE|FALSE|FALSE|TRUE|FALSE||' > "${WB_TEST_YAD_RESPONSE}"
  export WB_TEST_YAD_RESPONSE_RC=0

  bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE_RC=0
    '${WB_GUI}' settings NoD3D
  "

  local ppdb="${exe_dir}/.wb.ppdb"
  [ -f "${ppdb}" ]
  run jq -r '.env.WB_DXVK' "${ppdb}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

# ---------------------------------------------------------------------------
# 9. Malformed EXE path (contains `;`) is rejected
# ---------------------------------------------------------------------------
@test "wb_gui_validate_exe_path rejects paths with semicolons" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '/tmp/evil;cmd.exe' 'EvilGame'
  "
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 10. Malformed EXE path (contains `..`) is rejected
# ---------------------------------------------------------------------------
@test "wb_gui_validate_exe_path rejects paths with path traversal" {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    wb_gui_games_add '/tmp/../etc/passwd' 'TraversalGame'
  "
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 11. .desktop file has required keys (parse-only check)
# ---------------------------------------------------------------------------
@test ".desktop file has required keys" {
  local desktop="${BATS_TEST_DIRNAME}/../share/applications/wine-bleeding-wb.desktop"
  [ -f "${desktop}" ]

  # Check required keys exist
  run grep -c "^\[Desktop Entry\]" "${desktop}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]

  run grep "^Name=" "${desktop}"
  [ "${status}" -eq 0 ]

  run grep "^Exec=" "${desktop}"
  [ "${status}" -eq 0 ]

  run grep "^Type=Application" "${desktop}"
  [ "${status}" -eq 0 ]

  # If desktop-file-validate is available, use it
  if command -v desktop-file-validate >/dev/null 2>&1; then
    run desktop-file-validate "${desktop}"
    [ "${status}" -eq 0 ]
  fi
}

# ---------------------------------------------------------------------------
# 12. compatibilitytool.vdf is well-formed (braces balanced)
# ---------------------------------------------------------------------------
@test "compatibilitytool.vdf has balanced braces" {
  local vdf="${BATS_TEST_DIRNAME}/../share/compatibilitytools.d/wine-bleeding/compatibilitytool.vdf"
  [ -f "${vdf}" ]

  run bash -c "
    content=\"\$(cat '${vdf}')\"
    open_count=\"\$(printf '%s' \"\${content}\" | tr -cd '{' | wc -c)\"
    close_count=\"\$(printf '%s' \"\${content}\" | tr -cd '}' | wc -c)\"
    [ \"\${open_count}\" -eq \"\${close_count}\" ] && echo 'balanced' || echo 'UNBALANCED'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "balanced" ]
}

# ---------------------------------------------------------------------------
# 13. fake-yad log captures argv correctly
# ---------------------------------------------------------------------------
@test "fake-yad logs invocation argv to WB_TEST_YAD_LOG" {
  printf '' > "${WB_TEST_YAD_LOG}"
  printf 'FakePfx\n' > "${WB_TEST_YAD_RESPONSE}"
  export WB_TEST_YAD_RESPONSE_RC=0

  # Call wb-gui add-game; it will invoke yad for the prefix entry dialog.
  # PATH is already set in setup() with fake-yad prepended; WB_TEST_PATH
  # captures the full already-expanded PATH for use in bash -c subshells.
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE_RC=0
    '${WB_GUI}' add-game /tmp/LogTest.exe
  "
  [ "${status}" -eq 0 ]
  [ -s "${WB_TEST_YAD_LOG}" ]
  run grep "ARGV:" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

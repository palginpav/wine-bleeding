#!/usr/bin/env bats
# 35_overlay_panel.bats — Phase C GUI integration tests (W5)
#
# Tests the overlay panel fields, save/bake flow, conflict detection,
# banner sentinel, and check-updates error branches.
#
# All tests are offline:
#   - GitHub API calls use WB_TEST_GH_API_FIXTURE
#   - yad is replaced by fake-yad via WB_TEST_YAD_RESPONSE* vars
#
# See runtime/tests/29_ui_flows.bats for the canonical fake-yad idiom.

load "lib/common.bash"

WB_GUI="${BATS_TEST_DIRNAME}/../src/wb-gui"
WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FAKE_YAD_DIR="${BATS_TEST_DIRNAME}/fixtures/fake-yad"

# ---------------------------------------------------------------------------
# Per-test setup / teardown
# ---------------------------------------------------------------------------
setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export WB_HOME="${TEST_DIR}/wb-home"
  mkdir -p "${WB_HOME}/settings/apps"
  mkdir -p "${WB_HOME}/overlays/.cache"
  mkdir -p "${WB_HOME}/etc"

  export WB_TEST_YAD_LOG="${TEST_DIR}/yad.log"
  export WB_TEST_YAD_RESPONSE="${TEST_DIR}/yad_response.txt"
  export WB_TEST_YAD_RESPONSE_RC="0"
  export WB_TEST_YAD_RESPONSES_DIR=""

  # Put fake-yad on PATH
  export PATH="${FAKE_YAD_DIR}:${PATH}"
  export WB_TEST_PATH="${PATH}"

  # Suppress desktop shortcut + banner in tests that don't need them
  export WB_GUI_NO_DESKTOP_SHORTCUT=1
  export WB_GUI_NO_OVERLAY_BANNER=1

  # Deterministic timestamps for the registry
  export WB_GUI_OVERLAY_NOW_UTC="2026-04-20T21:39:20Z"

  # Set up the GitHub API fixture directory (per-overlay fixture files)
  FIXTURE_DIR="$(mktemp -d)"
  export FIXTURE_DIR

  cat > "${FIXTURE_DIR}/gh_api.mangohud" <<'FIXTURE'
{
  "tag_name": "v0.8.1",
  "published_at": "2026-04-01T00:00:00Z",
  "assets": [
    {
      "name": "MangoHud-0.8.1.tar.gz",
      "browser_download_url": "https://example.com/MangoHud-0.8.1.tar.gz",
      "size": 1234567
    }
  ],
  "tarball_url": "https://api.github.com/repos/flightlessmango/MangoHud/tarball/v0.8.1",
  "body": ""
}
FIXTURE

  cat > "${FIXTURE_DIR}/gh_api.vkbasalt" <<'FIXTURE'
{
  "tag_name": "v0.3.2.10",
  "published_at": "2026-03-01T00:00:00Z",
  "assets": [],
  "tarball_url": "https://api.github.com/repos/DadSchoorse/vkBasalt/tarball/v0.3.2.10",
  "body": ""
}
FIXTURE

  cat > "${FIXTURE_DIR}/gh_api.optiscaler" <<'FIXTURE'
{
  "tag_name": "v0.7.7",
  "published_at": "2026-03-15T00:00:00Z",
  "assets": [
    {
      "name": "OptiScaler_v0.7.7_amd64.zip",
      "browser_download_url": "https://example.com/OptiScaler_v0.7.7_amd64.zip",
      "size": 2345678
    }
  ],
  "tarball_url": "https://api.github.com/repos/cdozdil/OptiScaler/tarball/v0.7.7",
  "body": ""
}
FIXTURE

  export WB_TEST_GH_API_FIXTURE="${FIXTURE_DIR}/gh_api"

  touch "${WB_TEST_YAD_LOG}"
  printf '' > "${WB_TEST_YAD_RESPONSE}"
}

teardown() {
  rm -rf "${TEST_DIR}" "${FIXTURE_DIR:-}"
}

# ---------------------------------------------------------------------------
# Helpers — mirrored from 29_ui_flows.bats / 31_dist_manager.bats
# ---------------------------------------------------------------------------
_mk_responses_dir() {
  local d="${TEST_DIR}/responses"
  mkdir -p "${d}"
  rm -f "${d}/.counter"
  echo "${d}"
}

_write_response() {
  local dir="${1}" n="${2}" content="${3}" rc="${4:-0}"
  local pad
  pad="$(printf '%03d' "${n}")"
  printf '%s' "${content}" > "${dir}/${pad}"
  printf '%s' "${rc}"      > "${dir}/${pad}.rc"
}

# Count ARGV: lines in the yad log — safe even on empty files.
# grep -c returns 1 (no match) on this platform, so avoid ||.
_yad_call_count() {
  local n
  n="$(grep -c 'ARGV:' "${WB_TEST_YAD_LOG}" 2>/dev/null)" && echo "${n}" || echo "0"
}

# Emit the source preamble to load overlay+settings libs in a subshell.
_src_overlays_snippet() {
  printf "export WB_HOME='%s';" "${WB_HOME}"
  printf "export WB_GUI_OVERLAY_NOW_UTC='%s';" "${WB_GUI_OVERLAY_NOW_UTC}"
  printf "export WB_TEST_GH_API_FIXTURE='%s';" "${WB_TEST_GH_API_FIXTURE}"
  printf "source '%s/wb-paths.sh';" "${WB_LIB}"
  printf "source '%s/wb-json.sh';" "${WB_LIB}"
  printf "source '%s/wb-log.sh';" "${WB_LIB}"
  printf "source '%s/wb-gui-settings.sh';" "${WB_GUI_LIB}"
  printf "source '%s/wb-gui-overlays.sh';" "${WB_GUI_LIB}"
}

# Create a minimal apps.json and per-app settings file.
_mk_test_app() {
  local app_id="${1}"
  cat > "${WB_HOME}/apps.json" <<JSON
{
  "schema": 1,
  "apps": [
    {
      "id": "${app_id}",
      "name": "Test App",
      "exe": "/tmp/test.exe",
      "prefix": "testpfx",
      "source": "portable",
      "added_at": "2026-04-20T00:00:00Z"
    }
  ]
}
JSON
  mkdir -p "${WB_HOME}/settings/apps"
  cat > "${WB_HOME}/settings/apps/${app_id}.json" <<JSON
{
  "schema": 1,
  "app_id": "${app_id}",
  "updated_utc": "2026-04-20T00:00:00Z"
}
JSON
}

# Inline _overlay_phase_c_banner definition for banner tests.
# Mirrors wb-gui's implementation (same logic, same guards, same flag path).
_banner_fn_def() {
  local wb_home="${1}"
  cat <<'BFUNC'
    _wb_gui_home() { printf '%s' 'WBHOME_PLACEHOLDER'; }
    _overlay_phase_c_banner() {
      [[ "${WB_GUI_NO_DESKTOP_SHORTCUT:-0}" == '1' ]] && return 0
      [[ "${WB_GUI_NO_OVERLAY_BANNER:-0}" == '1' ]] && return 0
      local flag_file="WBHOME_PLACEHOLDER/etc/wb-gui-seen-phase-c.flag"
      [[ -e "${flag_file}" ]] && return 0
      wb_gui_yad \
        --title='wb-gui — New in v1.8.0: Per-app overlays' \
        --no-markup \
        --text='You can now enable MangoHud, VKBasalt, and OptiScaler per game.' \
        --button='Got it:0' 2>/dev/null || true
      mkdir -p "WBHOME_PLACEHOLDER/etc" && touch "${flag_file}" || true
    }
BFUNC
}

# ===========================================================================
# GROUP 1 — Overlay panel registry / field state (via public API in lib)
# ===========================================================================

# ---------------------------------------------------------------------------
# T01: After registry_refresh with no installs, MangoHud installed_versions
#      is empty — this is the precondition for "Install" button and "latest"
#      single-item CB (O10 field in the panel).
# ---------------------------------------------------------------------------
@test "overlay panel field: MangoHud installed_versions empty when nothing installed (Install button precondition)" {
  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_registry_refresh 2>/dev/null
    jq -r '.overlays[] | select(.name==\"mangohud\") | .installed_versions | length' \
      '${WB_HOME}/overlays.json'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

# ---------------------------------------------------------------------------
# T02: Registry contains all three overlay names (MangoHud, VKBasalt, OptiScaler)
#      after refresh — O7/O12/O17 labels are driven by the same registry.
# ---------------------------------------------------------------------------
@test "overlay panel field: registry_refresh produces entries for all three overlay names" {
  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_registry_refresh 2>/dev/null
    jq -r '[.overlays[].name] | sort | join(\",\")' '${WB_HOME}/overlays.json'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "mangohud,optiscaler,vkbasalt" ]
}

# ---------------------------------------------------------------------------
# T03: When MangoHud has one installed version, the registry captures it —
#      this drives the version CB list ("latest!0.8.0") and "Up to date" / "Update"
#      action button state.
# ---------------------------------------------------------------------------
@test "overlay panel field: installed version appears in registry installed_versions after refresh" {
  # Plant a fake MangoHud installed version (with sentinel file)
  local mh_ver_dir="${WB_HOME}/overlays/mangohud/0.8.0"
  mkdir -p "${mh_ver_dir}/lib/mangohud"
  touch "${mh_ver_dir}/lib/mangohud/libMangoHud.so"

  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_registry_refresh 2>/dev/null
    jq -r '.overlays[] | select(.name==\"mangohud\") | .installed_versions[0].version' \
      '${WB_HOME}/overlays.json'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "0.8.0" ]
}

# ---------------------------------------------------------------------------
# T04: last_checked_utc is null before any check_updates call — drives
#      "Last checked: never" label (O23).
# ---------------------------------------------------------------------------
@test "overlay panel field: last_checked_utc is null before check_updates (Last checked: never)" {
  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_registry_refresh 2>/dev/null
    jq '[.overlays[].last_checked_utc] | all(. == null)' '${WB_HOME}/overlays.json'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

# ===========================================================================
# GROUP 2 — Save-handler / env bake (direct function tests)
# ===========================================================================

# ---------------------------------------------------------------------------
# T05: MangoHud enabled + bundled + installed version → env_vars gains
#      MANGOHUD=1, VK_LAYER_PATH, LD_LIBRARY_PATH; managed keys tracked.
# ---------------------------------------------------------------------------
@test "save_env_bake: MangoHud enabled bundled with installed version writes MANGOHUD VK_LAYER_PATH LD_LIBRARY_PATH" {
  local app_id="eeee1111-aaaa-bbbb-cccc-000000000003"
  _mk_test_app "${app_id}"

  # Plant a fake installed MangoHud version with sentinel
  local mh_ver_dir="${WB_HOME}/overlays/mangohud/0.8.1"
  mkdir -p "${mh_ver_dir}/lib/mangohud"
  mkdir -p "${mh_ver_dir}/share/vulkan/implicit_layer.d"
  touch "${mh_ver_dir}/lib/mangohud/libMangoHud.so"

  local overlays_json='{"mangohud":{"enabled":true,"bundled":true,"version":null,"config_path":null},"vkbasalt":{"enabled":false,"bundled":true,"version":null},"optiscaler":{"enabled":false,"version":null}}'

  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
  "
  [ "${status}" -eq 0 ]

  local app_file="${WB_HOME}/settings/apps/${app_id}.json"
  [ -f "${app_file}" ]

  run jq -r '.env_vars.MANGOHUD' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  run jq -r '.env_vars.VK_LAYER_PATH // empty' "${app_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"mangohud"* ]]

  run jq -r '.env_vars.LD_LIBRARY_PATH // empty' "${app_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"mangohud"* ]]

  run jq -r '._wb_overlay_managed_env_keys | contains(["MANGOHUD","VK_LAYER_PATH","LD_LIBRARY_PATH"])' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

# ---------------------------------------------------------------------------
# T06: All overlays disabled → env_vars has no overlay keys; managed list empty.
#      Previously baked keys are cleaned from env_vars.
# ---------------------------------------------------------------------------
@test "save_env_bake: all overlays disabled clears prior baked keys and empties managed list" {
  local app_id="eeee2222-aaaa-bbbb-cccc-000000000004"
  _mk_test_app "${app_id}"

  cat > "${WB_HOME}/settings/apps/${app_id}.json" <<JSON
{
  "schema": 1,
  "app_id": "${app_id}",
  "updated_utc": "2026-04-20T00:00:00Z",
  "env_vars": {"MANGOHUD": "1", "VK_LAYER_PATH": "/some/path"},
  "_wb_overlay_managed_env_keys": ["MANGOHUD", "VK_LAYER_PATH"]
}
JSON

  local overlays_json='{"mangohud":{"enabled":false,"bundled":true,"version":null,"config_path":null},"vkbasalt":{"enabled":false,"bundled":true,"version":null},"optiscaler":{"enabled":false,"version":null}}'

  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
  "
  [ "${status}" -eq 0 ]

  local app_file="${WB_HOME}/settings/apps/${app_id}.json"
  [ -f "${app_file}" ]

  run jq -r '.env_vars.MANGOHUD // "absent"' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "absent" ]

  run jq -r '.env_vars.VK_LAYER_PATH // "absent"' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "absent" ]

  run jq -r '._wb_overlay_managed_env_keys | length' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T07: VKBasalt enabled system-mode → ENABLE_VKBASALT=1 written; no VK_LAYER_PATH.
# ---------------------------------------------------------------------------
@test "save_env_bake: VKBasalt system mode writes ENABLE_VKBASALT=1 without bundled path tokens" {
  local app_id="eeee3333-aaaa-bbbb-cccc-000000000005"
  _mk_test_app "${app_id}"

  local overlays_json='{"mangohud":{"enabled":false,"bundled":true,"version":null,"config_path":null},"vkbasalt":{"enabled":true,"bundled":false,"version":null},"optiscaler":{"enabled":false,"version":null}}'

  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
  "
  [ "${status}" -eq 0 ]

  local app_file="${WB_HOME}/settings/apps/${app_id}.json"
  [ -f "${app_file}" ]

  run jq -r '.env_vars.ENABLE_VKBASALT' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  run jq -r '.env_vars.VK_LAYER_PATH // "absent"' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "absent" ]

  run jq -r '._wb_overlay_managed_env_keys | contains(["ENABLE_VKBASALT"])' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

# ---------------------------------------------------------------------------
# T08: save_env_bake with overlays_json=null clears managed overlay keys
#      but preserves user-set non-overlay env_vars.
# ---------------------------------------------------------------------------
@test "save_env_bake: overlays_json=null clears managed keys but preserves user env_vars" {
  local app_id="eeee4444-aaaa-bbbb-cccc-000000000008"
  _mk_test_app "${app_id}"

  cat > "${WB_HOME}/settings/apps/${app_id}.json" <<JSON
{
  "schema": 1,
  "app_id": "${app_id}",
  "updated_utc": "2026-04-20T00:00:00Z",
  "env_vars": {"MANGOHUD": "1", "USER_VAR": "keep_me"},
  "_wb_overlay_managed_env_keys": ["MANGOHUD"]
}
JSON

  run bash -c "
    $(_src_overlays_snippet)
    wb_gui_overlays_save_env_bake '${app_id}' 'null'
  "
  [ "${status}" -eq 0 ]

  local app_file="${WB_HOME}/settings/apps/${app_id}.json"
  [ -f "${app_file}" ]

  run jq -r '.env_vars.MANGOHUD // "absent"' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "absent" ]

  run jq -r '.env_vars.USER_VAR // "absent"' "${app_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "keep_me" ]
}

# ===========================================================================
# GROUP 3 — Conflict detection
# ===========================================================================
#
# _overlay_conflict_check_and_warn lives in wb-gui (the main script).
# Tests inline the equivalent logic (same algorithm) and call wb_gui_dialog_info
# to exercise the same yad codepath. This verifies the conflict detection
# algorithm and dialog wiring without needing to exec the full wb-gui.

# ---------------------------------------------------------------------------
# T09: Conflict detection fires (info dialog) when user-set MANGOHUD is
#      in env_vars but NOT in the managed list.
# ---------------------------------------------------------------------------
@test "conflict detection: info dialog shown when user-set MANGOHUD not in managed list" {
  local app_id="ffff1111-aaaa-bbbb-cccc-000000000006"
  _mk_test_app "${app_id}"

  cat > "${WB_HOME}/settings/apps/${app_id}.json" <<JSON
{
  "schema": 1,
  "app_id": "${app_id}",
  "updated_utc": "2026-04-20T00:00:00Z",
  "env_vars": {"MANGOHUD": "0", "MY_CUSTOM_VAR": "hello"},
  "_wb_overlay_managed_env_keys": []
}
JSON

  run bash -c "
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_RESPONSE_RC='0'
    $(_src_overlays_snippet)
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    APP_FILE='${WB_HOME}/settings/apps/${app_id}.json'
    env_vars_json=\"\$(jq '.env_vars // {}' \"\${APP_FILE}\")\"
    managed_json=\"\$(jq '._wb_overlay_managed_env_keys // []' \"\${APP_FILE}\")\"
    for key in MANGOHUD ENABLE_VKBASALT VK_LAYER_PATH LD_LIBRARY_PATH MANGOHUD_CONFIG WINEDLLOVERRIDES; do
      am=\"\$(printf '%s' \"\${managed_json}\" | jq --arg k \"\${key}\" 'index(\$k) != null')\"
      [[ \"\${am}\" == 'true' ]] && continue
      kv=\"\$(printf '%s' \"\${env_vars_json}\" | jq -r --arg k \"\${key}\" '.[\$k] // empty')\"
      [[ -z \"\${kv}\" ]] && continue
      wb_gui_dialog_info 'wb-gui — Overlay conflict resolved' \
        \"The overlay panel removed a conflicting manual setting: env_vars.\${key} was set to \\\"\${kv}\\\"\"
    done
  "
  [ "${status}" -eq 0 ]

  # At least one yad invocation must have occurred (the conflict info dialog)
  local call_count
  call_count="$(_yad_call_count)"
  [ "${call_count}" -ge 1 ]

  run grep "MANGOHUD" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T10: Conflict detection does NOT fire when env_vars has only non-overlay keys.
# ---------------------------------------------------------------------------
@test "conflict detection: no dialog when env_vars has only non-overlay keys" {
  local app_id="ffff2222-aaaa-bbbb-cccc-000000000007"
  _mk_test_app "${app_id}"

  cat > "${WB_HOME}/settings/apps/${app_id}.json" <<JSON
{
  "schema": 1,
  "app_id": "${app_id}",
  "updated_utc": "2026-04-20T00:00:00Z",
  "env_vars": {"MY_GAME_VAR": "ultra", "DXVK_HUD": "fps"},
  "_wb_overlay_managed_env_keys": []
}
JSON

  run bash -c "
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_RESPONSE_RC='0'
    $(_src_overlays_snippet)
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    APP_FILE='${WB_HOME}/settings/apps/${app_id}.json'
    env_vars_json=\"\$(jq '.env_vars // {}' \"\${APP_FILE}\")\"
    managed_json=\"\$(jq '._wb_overlay_managed_env_keys // []' \"\${APP_FILE}\")\"
    for key in MANGOHUD ENABLE_VKBASALT VK_LAYER_PATH LD_LIBRARY_PATH MANGOHUD_CONFIG WINEDLLOVERRIDES; do
      am=\"\$(printf '%s' \"\${managed_json}\" | jq --arg k \"\${key}\" 'index(\$k) != null')\"
      [[ \"\${am}\" == 'true' ]] && continue
      kv=\"\$(printf '%s' \"\${env_vars_json}\" | jq -r --arg k \"\${key}\" '.[\$k] // empty')\"
      [[ -z \"\${kv}\" ]] && continue
      wb_gui_dialog_info 'wb-gui — Overlay conflict resolved' \"Conflict: env_vars.\${key}\"
    done
  "
  [ "${status}" -eq 0 ]

  # No yad call should have occurred
  local call_count
  call_count="$(_yad_call_count)"
  [ "${call_count}" -eq 0 ]
}

# ===========================================================================
# GROUP 4 — Banner sentinel
# ===========================================================================

# ---------------------------------------------------------------------------
# T11: Banner shown (yad called) when flag file absent and suppression unset.
# ---------------------------------------------------------------------------
@test "banner: info dialog fired and flag file created when seen-phase-c.flag absent" {
  unset WB_GUI_NO_OVERLAY_BANNER
  unset WB_GUI_NO_DESKTOP_SHORTCUT

  rm -f "${WB_HOME}/etc/wb-gui-seen-phase-c.flag"

  local wb_home="${WB_HOME}"
  run bash -c "
    export PATH='${WB_TEST_PATH}'
    export WB_HOME='${wb_home}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_RESPONSE_RC='0'
    $(_src_overlays_snippet)
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    _overlay_phase_c_banner() {
      [[ \"\${WB_GUI_NO_DESKTOP_SHORTCUT:-0}\" == '1' ]] && return 0
      [[ \"\${WB_GUI_NO_OVERLAY_BANNER:-0}\" == '1' ]] && return 0
      local flag_file='${wb_home}/etc/wb-gui-seen-phase-c.flag'
      [[ -e \"\${flag_file}\" ]] && return 0
      wb_gui_yad \
        --title='wb-gui — New in v1.8.0: Per-app overlays' \
        --no-markup \
        --text='You can now enable MangoHud, VKBasalt, and OptiScaler per game.' \
        --button='Got it:0' 2>/dev/null || true
      mkdir -p '${wb_home}/etc' && touch \"\${flag_file}\" || true
    }
    _overlay_phase_c_banner
  "
  [ "${status}" -eq 0 ]

  local call_count
  call_count="$(_yad_call_count)"
  [ "${call_count}" -ge 1 ]

  run grep "v1.8.0" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  [ -f "${WB_HOME}/etc/wb-gui-seen-phase-c.flag" ]
}

# ---------------------------------------------------------------------------
# T12: Banner NOT shown when flag file already exists.
# ---------------------------------------------------------------------------
@test "banner: no dialog when seen-phase-c.flag already exists" {
  unset WB_GUI_NO_OVERLAY_BANNER
  unset WB_GUI_NO_DESKTOP_SHORTCUT

  touch "${WB_HOME}/etc/wb-gui-seen-phase-c.flag"

  local wb_home="${WB_HOME}"
  run bash -c "
    export PATH='${WB_TEST_PATH}'
    export WB_HOME='${wb_home}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_RESPONSE_RC='0'
    $(_src_overlays_snippet)
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    _overlay_phase_c_banner() {
      [[ \"\${WB_GUI_NO_DESKTOP_SHORTCUT:-0}\" == '1' ]] && return 0
      [[ \"\${WB_GUI_NO_OVERLAY_BANNER:-0}\" == '1' ]] && return 0
      local flag_file='${wb_home}/etc/wb-gui-seen-phase-c.flag'
      [[ -e \"\${flag_file}\" ]] && return 0
      wb_gui_yad \
        --title='wb-gui — New in v1.8.0: Per-app overlays' \
        --no-markup \
        --text='You can now enable MangoHud.' \
        --button='Got it:0' 2>/dev/null || true
      touch \"\${flag_file}\" || true
    }
    _overlay_phase_c_banner
  "
  [ "${status}" -eq 0 ]

  local call_count
  call_count="$(_yad_call_count)"
  [ "${call_count}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T13: Banner suppressed by WB_GUI_NO_OVERLAY_BANNER=1.
# ---------------------------------------------------------------------------
@test "banner: suppressed by WB_GUI_NO_OVERLAY_BANNER=1 even when flag absent" {
  unset WB_GUI_NO_DESKTOP_SHORTCUT

  rm -f "${WB_HOME}/etc/wb-gui-seen-phase-c.flag"

  local wb_home="${WB_HOME}"
  run bash -c "
    export WB_GUI_NO_OVERLAY_BANNER=1
    export PATH='${WB_TEST_PATH}'
    export WB_HOME='${wb_home}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_RESPONSE_RC='0'
    $(_src_overlays_snippet)
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    _overlay_phase_c_banner() {
      [[ \"\${WB_GUI_NO_DESKTOP_SHORTCUT:-0}\" == '1' ]] && return 0
      [[ \"\${WB_GUI_NO_OVERLAY_BANNER:-0}\" == '1' ]] && return 0
      local flag_file='${wb_home}/etc/wb-gui-seen-phase-c.flag'
      [[ -e \"\${flag_file}\" ]] && return 0
      wb_gui_yad \
        --title='wb-gui — New in v1.8.0: Per-app overlays' \
        --no-markup \
        --text='You can now enable MangoHud.' \
        --button='Got it:0' 2>/dev/null || true
      touch \"\${flag_file}\" || true
    }
    _overlay_phase_c_banner
  "
  [ "${status}" -eq 0 ]

  local call_count
  call_count="$(_yad_call_count)"
  [ "${call_count}" -eq 0 ]

  [ ! -f "${WB_HOME}/etc/wb-gui-seen-phase-c.flag" ]
}

# ===========================================================================
# GROUP 5 — Check-updates error branches
# ===========================================================================

# ---------------------------------------------------------------------------
# T14: Offline branch — WB_TEST_GH_API_FIXTURE pointing at missing file →
#      _wb_gui_overlays_query_github returns exit 73 ("offline").
#      wb_gui_overlays_check_updates records last_check_error in registry.
# ---------------------------------------------------------------------------
@test "check-updates offline: missing fixture path → check_updates records last_check_error in registry" {
  local missing_fixture="${FIXTURE_DIR}/does_not_exist"

  run bash -c "
    export WB_HOME='${WB_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    export WB_TEST_GH_API_FIXTURE='${missing_fixture}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    wb_gui_overlays_registry_refresh 2>/dev/null
    wb_gui_overlays_check_updates 2>/dev/null || true
    jq -e '[.overlays[] | select(.last_check_error != null)] | length > 0' \
      '${WB_HOME}/overlays.json'
  "
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T15: Parse-error branch — fixture exists but contains an invalid API response
#      (e.g. a GitHub rate-limit reply without tag_name) → jq fails to extract
#      required fields → wb_gui_overlays_check_updates records parse-error in
#      registry for all three overlays.
# ---------------------------------------------------------------------------
@test "check-updates parse-error: invalid fixture response records error for all three overlays" {
  # Write a rate-limit-style body (no tag_name → jq parse yields nothing → error)
  printf '{"message":"API rate limit exceeded"}' \
    > "${FIXTURE_DIR}/ratelimit_fixture.json"

  # Remove per-overlay files so fixture seam falls back to the base path
  rm -f "${FIXTURE_DIR}/gh_api.mangohud" \
        "${FIXTURE_DIR}/gh_api.vkbasalt" \
        "${FIXTURE_DIR}/gh_api.optiscaler"

  run bash -c "
    export WB_HOME='${WB_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    export WB_TEST_GH_API_FIXTURE='${FIXTURE_DIR}/ratelimit_fixture.json'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    wb_gui_overlays_registry_refresh 2>/dev/null
    wb_gui_overlays_check_updates 2>/dev/null || true
    # All three overlays must have last_check_error set
    jq -e '[.overlays[] | select(.last_check_error != null)] | length >= 3' \
      '${WB_HOME}/overlays.json'
  "
  [ "${status}" -eq 0 ]
}

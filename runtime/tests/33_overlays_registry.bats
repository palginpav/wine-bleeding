#!/usr/bin/env bats
# 33_overlays_registry.bats — wb-gui-overlays.sh + fetch-overlay.sh unit tests (Phase C)
#
# All tests are offline: GitHub API calls are intercepted via WB_TEST_GH_API_FIXTURE.
# fetch-overlay.sh downloads are intercepted via WB_OVERLAY_DOWNLOAD_BASE.

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
FETCH_OVERLAY="${BATS_TEST_DIRNAME}/../../tools/fetch-overlay.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
  mkdir -p "${TEST_HOME}/overlays/.cache"
  mkdir -p "${TEST_HOME}/settings/apps"

  # Deterministic timestamps
  export WB_GUI_OVERLAY_NOW_UTC="2026-04-20T21:39:20Z"

  # Create fixture API response files
  FIXTURE_DIR="$(mktemp -d)"
  export FIXTURE_DIR

  # MangoHud fixture
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
  "body": "sha256: aabbccdd"
}
FIXTURE

  # VKBasalt fixture
  cat > "${FIXTURE_DIR}/gh_api.vkbasalt" <<'FIXTURE'
{
  "tag_name": "v0.3.2.10",
  "published_at": "2026-03-01T00:00:00Z",
  "assets": [],
  "tarball_url": "https://api.github.com/repos/DadSchoorse/vkBasalt/tarball/v0.3.2.10",
  "body": ""
}
FIXTURE

  # OptiScaler fixture
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
}

teardown() {
  rm -rf "${TEST_HOME}" "${FIXTURE_DIR:-}"
}

# ---------------------------------------------------------------------------
# Helper: source overlay lib
# ---------------------------------------------------------------------------
_source_overlays() {
  source "${WB_LIB}/wb-json.sh"
  source "${WB_GUI_LIB}/wb-gui-settings.sh"
  source "${WB_GUI_LIB}/wb-gui-overlays.sh"
}

# ---------------------------------------------------------------------------
# Helper: plant a fake overlay install
# ---------------------------------------------------------------------------
_make_overlay_install() {
  local name="$1"
  local version="$2"
  local install_dir="${TEST_HOME}/overlays/${name}/${version}"
  mkdir -p "${install_dir}"
  printf '2026-04-20T00:00:00Z\n' > "${install_dir}/.installed_utc"

  case "${name}" in
    mangohud)
      # MangoHud 0.7+ layout: lib/mangohud/lib64/libMangoHud.so (sentinel
      # path also extended to include the lib64 subdir).
      mkdir -p "${install_dir}/lib/mangohud/lib64"
      mkdir -p "${install_dir}/share/vulkan/implicit_layer.d"
      touch "${install_dir}/lib/mangohud/lib64/libMangoHud.so"
      ;;
    vkbasalt)
      mkdir -p "${install_dir}/lib/vkbasalt"
      mkdir -p "${install_dir}/share/vulkan/implicit_layer.d"
      touch "${install_dir}/lib/vkbasalt/libvkbasalt.so"
      ;;
    optiscaler)
      mkdir -p "${install_dir}/bin/optiscaler"
      touch "${install_dir}/bin/optiscaler/OptiScaler.dll"
      touch "${install_dir}/bin/optiscaler/OptiScaler.ini"
      ;;
  esac
  echo "${install_dir}"
}

# ---------------------------------------------------------------------------
# 1. Registry refresh — empty state
# ---------------------------------------------------------------------------
@test "registry_refresh: creates overlays.json with all three overlay names" {
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_registry_refresh
    jq -r '[.overlays[].name] | sort | join(\",\")' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"mangohud"* ]]
  [[ "${output}" == *"optiscaler"* ]]
  [[ "${output}" == *"vkbasalt"* ]]
}

@test "registry_refresh: schema version is 1" {
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_registry_refresh
    jq '.schema' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "registry_refresh: installed_versions empty when no installs" {
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_registry_refresh
    jq '[.overlays[].installed_versions | length] | add' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "registry_refresh: idempotent — two refreshes produce same overlays array" {
  _make_overlay_install mangohud 0.8.1
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_registry_refresh
    first=\$(jq -c '[.overlays[].name] | sort' \"\${WB_HOME}/overlays.json\")
    wb_gui_overlays_registry_refresh
    second=\$(jq -c '[.overlays[].name] | sort' \"\${WB_HOME}/overlays.json\")
    [ \"\${first}\" = \"\${second}\" ] && echo 'IDEMPOTENT'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"IDEMPOTENT"* ]]
}

# ---------------------------------------------------------------------------
# 2. Registry refresh — with installs
# ---------------------------------------------------------------------------
@test "registry_refresh: detects installed mangohud version" {
  _make_overlay_install mangohud 0.8.1
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_registry_refresh
    jq -r '.overlays[] | select(.name==\"mangohud\") | .installed_versions[0].version' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "0.8.1" ]
}

@test "registry_refresh: broken=false when sentinel exists" {
  _make_overlay_install mangohud 0.8.1
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_registry_refresh
    jq -r '.overlays[] | select(.name==\"mangohud\") | .installed_versions[0].broken' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "false" ]
}

@test "registry_refresh: broken=true when sentinel missing" {
  local idir="${TEST_HOME}/overlays/mangohud/0.8.1"
  mkdir -p "${idir}"
  printf '2026-04-20T00:00:00Z\n' > "${idir}/.installed_utc"
  # Deliberately do NOT create libMangoHud.so

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_registry_refresh
    jq -r '.overlays[] | select(.name==\"mangohud\") | .installed_versions[0].broken' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

@test "registry_refresh: preserves available_version from prior registry on re-refresh" {
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    # Seed registry with a known available_version
    wb_gui_overlays_registry_refresh
    reg=\$(cat \"\${WB_HOME}/overlays.json\")
    reg=\$(printf '%s' \"\${reg}\" | jq '(.overlays[] | select(.name==\"mangohud\")) |= . + {available_version: \"v0.8.1\"}')
    source '${WB_LIB}/wb-json.sh'
    wb_json_write_atomic \"\${WB_HOME}/overlays.json\" \"\${reg}\"
    # Refresh again
    wb_gui_overlays_registry_refresh
    jq -r '.overlays[] | select(.name==\"mangohud\") | .available_version' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "v0.8.1" ]
}

# ---------------------------------------------------------------------------
# 3. wb_gui_overlays_list
# ---------------------------------------------------------------------------
@test "overlays_list: returns JSON array" {
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    result=\$(wb_gui_overlays_list)
    printf '%s' \"\${result}\" | jq 'length'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "3" ]
}

# ---------------------------------------------------------------------------
# 4. wb_gui_overlays_check_updates — fixture-based (offline)
# ---------------------------------------------------------------------------
@test "check_updates: populates available_version from fixture for mangohud" {
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    export WB_TEST_GH_API_FIXTURE='${WB_TEST_GH_API_FIXTURE}'
    wb_gui_overlays_check_updates mangohud
    jq -r '.overlays[] | select(.name==\"mangohud\") | .available_version' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "v0.8.1" ]
}

@test "check_updates: last_checked_utc set after successful check" {
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    export WB_TEST_GH_API_FIXTURE='${WB_TEST_GH_API_FIXTURE}'
    wb_gui_overlays_check_updates mangohud
    jq -r '.overlays[] | select(.name==\"mangohud\") | .last_checked_utc' \"\${WB_HOME}/overlays.json\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" != "null" ]]
}

@test "check_updates: offline fixture sets last_check_error when fixture missing" {
  # Point fixture to a nonexistent path to simulate offline; function exits 0 (non-blocking)
  local bad_fixture="${FIXTURE_DIR}/nonexistent_fixture"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    export WB_TEST_GH_API_FIXTURE='${bad_fixture}'
    wb_gui_overlays_check_updates mangohud || true
    jq -r '.overlays[] | select(.name==\"mangohud\") | .last_check_error // \"null\"' \"\${WB_HOME}/overlays.json\" 2>/dev/null || echo 'registry-missing'
  "
  # Either the registry was not created (offline skipped writing) or last_check_error is set
  [[ "${output}" != "null" ]] || [[ "${output}" == "registry-missing" ]]
}

# ---------------------------------------------------------------------------
# 5. save_env_bake — Path B env-key tracking
# ---------------------------------------------------------------------------
@test "save_env_bake: mangohud enabled+bundled bakes MANGOHUD and VK_LAYER_PATH" {
  _make_overlay_install mangohud 0.8.1
  local app_id="00000000-0000-0000-0000-000000000001"
  local overlays_json
  overlays_json='{"mangohud":{"enabled":true,"bundled":true,"version":null,"config_path":null}}'

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
    jq -r '.env_vars | keys | sort | join(\",\")' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"MANGOHUD"* ]]
  [[ "${output}" == *"VK_LAYER_PATH"* ]]
  [[ "${output}" == *"LD_LIBRARY_PATH"* ]]
}

@test "save_env_bake: mangohud enabled+system bakes only MANGOHUD (no path)" {
  _make_overlay_install mangohud 0.8.1
  local app_id="00000000-0000-0000-0000-000000000002"
  local overlays_json
  overlays_json='{"mangohud":{"enabled":true,"bundled":false,"version":null,"config_path":null}}'

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
    jq -r '.env_vars | keys | sort | join(\",\")' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"MANGOHUD"* ]]
  [[ "${output}" != *"VK_LAYER_PATH"* ]]
}

@test "save_env_bake: mangohud disabled removes all managed keys" {
  _make_overlay_install mangohud 0.8.1
  local app_id="00000000-0000-0000-0000-000000000003"
  local enable_json='{"mangohud":{"enabled":true,"bundled":true,"version":null,"config_path":null}}'
  local disable_json='{"mangohud":{"enabled":false,"bundled":true,"version":null,"config_path":null}}'

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    # Enable first
    wb_gui_overlays_save_env_bake '${app_id}' '${enable_json}'
    # Now disable
    wb_gui_overlays_save_env_bake '${app_id}' '${disable_json}'
    env_keys=\$(jq -r '.env_vars | keys | length' \"\${WB_HOME}/settings/apps/${app_id}.json\")
    echo \"\${env_keys}\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "save_env_bake: _wb_overlay_managed_env_keys tracks baked keys" {
  _make_overlay_install mangohud 0.8.1
  local app_id="00000000-0000-0000-0000-000000000004"
  local overlays_json='{"mangohud":{"enabled":true,"bundled":true,"version":null,"config_path":null}}'

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
    jq -r '._wb_overlay_managed_env_keys | length' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" -gt 0 ]]
}

@test "save_env_bake: vkbasalt enabled+bundled sets ENABLE_VKBASALT and VK_LAYER_PATH" {
  _make_overlay_install vkbasalt 0.3.2.10
  local app_id="00000000-0000-0000-0000-000000000005"
  local overlays_json='{"vkbasalt":{"enabled":true,"bundled":true,"version":null}}'

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
    jq -r '.env_vars.ENABLE_VKBASALT' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "save_env_bake: optiscaler enabled sets WINEDLLOVERRIDES nvngx=n,b" {
  _make_overlay_install optiscaler 0.7.7
  local app_id="00000000-0000-0000-0000-000000000006"
  local overlays_json='{"optiscaler":{"enabled":true,"version":null}}'

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
    jq -r '.env_vars.WINEDLLOVERRIDES' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"nvngx=n,b"* ]]
}

@test "save_env_bake: writes overlays object to app settings file" {
  local app_id="00000000-0000-0000-0000-000000000007"
  local overlays_json='{"mangohud":{"enabled":false,"bundled":true,"version":null,"config_path":null}}'

  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-overlays.sh'
    export WB_HOME='${TEST_HOME}'
    export WB_GUI_OVERLAY_NOW_UTC='${WB_GUI_OVERLAY_NOW_UTC}'
    wb_gui_overlays_save_env_bake '${app_id}' '${overlays_json}'
    jq -r '.overlays.mangohud.enabled' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "false" ]
}

# ---------------------------------------------------------------------------
# 6. wb-gui-settings.sh — overlays key whitelist
# ---------------------------------------------------------------------------
@test "settings_set_app: overlays key accepted in app layer" {
  local app_id="00000000-0000-0000-0000-000000000008"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    export WB_HOME='${TEST_HOME}'
    wb_gui_settings_set_app '${app_id}' overlays '{\"mangohud\":{\"enabled\":true,\"bundled\":true,\"version\":null,\"config_path\":null}}'
    jq -r '.overlays.mangohud.enabled' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

@test "settings_set_app: _wb_overlay_managed_env_keys key accepted in app layer" {
  local app_id="00000000-0000-0000-0000-000000000009"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    export WB_HOME='${TEST_HOME}'
    wb_gui_settings_set_app '${app_id}' _wb_overlay_managed_env_keys '[\"MANGOHUD\",\"VK_LAYER_PATH\"]'
    jq -r '._wb_overlay_managed_env_keys | length' \"\${WB_HOME}/settings/apps/${app_id}.json\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}

# ---------------------------------------------------------------------------
# 7. fetch-overlay.sh CLI
# ---------------------------------------------------------------------------
@test "fetch_overlay: --help exits 0 and lists overlays" {
  run bash "${FETCH_OVERLAY}" --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"mangohud"* ]]
  [[ "${output}" == *"vkbasalt"* ]]
  [[ "${output}" == *"optiscaler"* ]]
}

@test "fetch_overlay: missing --overlay exits 64" {
  run bash "${FETCH_OVERLAY}" --version latest
  [ "${status}" -eq 64 ]
}

@test "fetch_overlay: missing --version exits 64" {
  run bash "${FETCH_OVERLAY}" --overlay mangohud
  [ "${status}" -eq 64 ]
}

@test "fetch_overlay: unknown overlay exits 64" {
  run bash "${FETCH_OVERLAY}" --overlay gstreamer --version latest
  [ "${status}" -eq 64 ]
}

@test "fetch_overlay: invalid dest exits 65" {
  run bash "${FETCH_OVERLAY}" \
    --overlay mangohud \
    --version latest \
    --dest "/nonexistent_path_that_doesnt_exist_12345"
  [ "${status}" -eq 65 ]
}

@test "fetch_overlay: --no-install with fixture outputs JSON tag" {
  mkdir -p "${TEST_HOME}/overlays"
  run bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_TEST_GH_API_FIXTURE='${WB_TEST_GH_API_FIXTURE}'
    export WB_TEST_SKIP_DEST_SECURITY_GATE=1
    bash '${FETCH_OVERLAY}' \
      --overlay mangohud \
      --version latest \
      --dest '${TEST_HOME}/overlays' \
      --no-install
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"v0.8.1"* ]]
}

@test "fetch_overlay: --no-install with missing fixture exits 73" {
  mkdir -p "${TEST_HOME}/overlays"
  local bad_fixture="${FIXTURE_DIR}/nonexistent"
  run bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_TEST_GH_API_FIXTURE='${bad_fixture}'
    export WB_TEST_SKIP_DEST_SECURITY_GATE=1
    bash '${FETCH_OVERLAY}' \
      --overlay mangohud \
      --version latest \
      --dest '${TEST_HOME}/overlays' \
      --no-install
  "
  [ "${status}" -eq 73 ]
}

@test "fetch_overlay: security gate rejects dest outside HOME" {
  # Create a temp dir outside HOME (in /tmp)
  local tmp_dest
  tmp_dest="$(mktemp -d /tmp/wb_test_XXXXXX)"
  run bash "${FETCH_OVERLAY}" \
    --overlay mangohud \
    --version latest \
    --dest "${tmp_dest}"
  rm -rf "${tmp_dest}"
  [ "${status}" -eq 65 ]
}

# ---------------------------------------------------------------------------
# 8. build-component.sh — overlay enum extension (non-network path)
# ---------------------------------------------------------------------------
BUILD_COMPONENT="${BATS_TEST_DIRNAME}/../../tools/build-component.sh"

@test "build_component: --help lists overlay components" {
  run bash "${BUILD_COMPONENT}" --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"mangohud"* ]]
  [[ "${output}" == *"vkbasalt"* ]]
  [[ "${output}" == *"optiscaler"* ]]
}

@test "build_component: unknown component still exits 64" {
  run bash "${BUILD_COMPONENT}" --component gstreamer --target-dist /tmp/fake
  [ "${status}" -eq 64 ]
}

@test "build_component: dxvk still accepted (Phase B regression check)" {
  # dxvk requires a valid target-dist; we just verify it no longer fails on enum check
  run bash "${BUILD_COMPONENT}" --component dxvk 2>&1
  # Should fail on --target-dist (missing), not on enum check
  [[ "${output}" != *"Unknown component"* ]]
}

@test "build_component: overlay component delegates (invalid dest exits 65, not 64)" {
  # mangohud should pass enum validation and reach fetch-overlay.sh dest check
  local bad_dest="/nonexistent_path_wb_test_XXXXX"
  run bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_TEST_GH_API_FIXTURE='${WB_TEST_GH_API_FIXTURE}'
    bash '${BUILD_COMPONENT}' \
      --component mangohud \
      --dest '${bad_dest}'
  "
  # Should not be 64 (enum error), but 65 (dest error) or similar
  [ "${status}" -ne 64 ] || [[ "${output}" != *"Unknown component"* ]]
}

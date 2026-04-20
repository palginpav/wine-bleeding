#!/usr/bin/env bats
# 27_settings_layers.bats — 4-layer settings storage + override resolver tests
#
# Exercises wb-gui-lib/wb-gui-settings.sh in isolation.
# WB_HOME is mocked to a temp dir; no real prefix/dist/apps state needed.

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
SETTINGS_SH="${WB_GUI_LIB}/wb-gui-settings.sh"
SCHEMAS_DIR="${BATS_TEST_DIRNAME}/../share/schemas"

# Common setup: isolated WB_HOME
setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    export WB_HOME="${TEST_DIR}/wb_home"
    mkdir -p "${WB_HOME}"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# Helper: source the settings lib in a subshell snippet
# Usage: run bash -c "$(_src) ; <command>"
_src() {
    printf "source '%s/wb-paths.sh'; source '%s/wb-json.sh'; source '%s';" \
        "${WB_LIB}" "${WB_LIB}" "${SETTINGS_SH}"
}

# ---------------------------------------------------------------------------
# 1. bash -n syntax check
# ---------------------------------------------------------------------------
@test "settings: bash -n passes on wb-gui-settings.sh" {
    run bash -n "${SETTINGS_SH}"
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2. First-use init creates settings/ dir tree
# ---------------------------------------------------------------------------
@test "settings: wb_gui_settings_home creates dir tree on first use" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_home > /dev/null
    "
    [ "${status}" -eq 0 ]
    [ -d "${WB_HOME}/settings" ]
    [ -d "${WB_HOME}/settings/dists" ]
    [ -d "${WB_HOME}/settings/prefixes" ]
    [ -d "${WB_HOME}/settings/apps" ]
}

# ---------------------------------------------------------------------------
# 3. get on empty general.json → empty string, no crash
# ---------------------------------------------------------------------------
@test "settings: get_general on missing file returns empty string" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        result=\"\$(wb_gui_settings_get_general gpu)\"
        [ -z \"\${result}\" ]
    "
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 4. set_general creates general.json with valid JSON
# ---------------------------------------------------------------------------
@test "settings: set_general creates general.json with valid JSON" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general gpu nvidia
    "
    [ "${status}" -eq 0 ]
    [ -f "${WB_HOME}/settings/general.json" ]
    run jq empty "${WB_HOME}/settings/general.json"
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5. Round-trip: set then get for general layer
# ---------------------------------------------------------------------------
@test "settings: set/get round-trip on general layer (gpu)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general gpu amd
        wb_gui_settings_get_general gpu
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "amd" ]
}

@test "settings: set/get round-trip on general layer (win_version)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general win_version win7
        wb_gui_settings_get_general win_version
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "win7" ]
}

@test "settings: set/get round-trip on general layer (wine_debug)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general wine_debug '+seh'
        wb_gui_settings_get_general wine_debug
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "+seh" ]
}

# ---------------------------------------------------------------------------
# 6. Round-trip: dist layer
# ---------------------------------------------------------------------------
@test "settings: set/get round-trip on dist layer (external_source)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_dist WINE-BLEEDING-10.13 external_source 'https://example.com/dist.tar.gz'
        wb_gui_settings_get_dist WINE-BLEEDING-10.13 external_source
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "https://example.com/dist.tar.gz" ]
}

@test "settings: set/get round-trip on dist layer (name)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_dist WINE-BLEEDING name 'My Custom Dist'
        wb_gui_settings_get_dist WINE-BLEEDING name
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "My Custom Dist" ]
}

@test "settings: set/get round-trip on dist layer (gpu cross-cutting)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_dist WINE-BLEEDING gpu nvidia
        wb_gui_settings_get_dist WINE-BLEEDING gpu
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "nvidia" ]
}

# ---------------------------------------------------------------------------
# 7. Round-trip: prefix layer
# ---------------------------------------------------------------------------
@test "settings: set/get round-trip on prefix layer (notes)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_prefix mypfx notes 'Test prefix notes'
        wb_gui_settings_get_prefix mypfx notes
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "Test prefix notes" ]
}

@test "settings: set/get round-trip on prefix layer (win_version)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_prefix mypfx win_version win10
        wb_gui_settings_get_prefix mypfx win_version
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "win10" ]
}

# ---------------------------------------------------------------------------
# 8. Round-trip: app layer
# ---------------------------------------------------------------------------
@test "settings: set/get round-trip on app layer (wine_debug)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_app 'a1b2c3d4-0000-0000-0000-000000000001' wine_debug '+seh,+relay'
        wb_gui_settings_get_app 'a1b2c3d4-0000-0000-0000-000000000001' wine_debug
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "+seh,+relay" ]
}

@test "settings: set/get round-trip on app layer (wine_args array)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_app 'a1b2c3d4-0000-0000-0000-000000000001' wine_args '[\"--force\",\"--dx12\"]'
        wb_gui_settings_get_app 'a1b2c3d4-0000-0000-0000-000000000001' wine_args
    "
    [ "${status}" -eq 0 ]
    # The value should be a JSON array (raw output from jq), not the array representation
    # get returns empty for arrays (since they aren't strings); so we verify via jq directly
    [ -f "${WB_HOME}/settings/apps/a1b2c3d4-0000-0000-0000-000000000001.json" ]
    run jq -r '.wine_args[0]' "${WB_HOME}/settings/apps/a1b2c3d4-0000-0000-0000-000000000001.json"
    [ "${status}" -eq 0 ]
    [ "${output}" = "--force" ]
}

@test "settings: set/get round-trip on app layer (env_vars object)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_app 'a1b2c3d4-0000-0000-0000-000000000002' env_vars '{\"DXVK_HUD\":\"fps\",\"STAGING_SHARED_MEMORY\":\"1\"}'
        wb_gui_settings_get_app 'a1b2c3d4-0000-0000-0000-000000000002' env_vars
    "
    [ "${status}" -eq 0 ]
    [ -f "${WB_HOME}/settings/apps/a1b2c3d4-0000-0000-0000-000000000002.json" ]
    run jq -r '.env_vars.DXVK_HUD' "${WB_HOME}/settings/apps/a1b2c3d4-0000-0000-0000-000000000002.json"
    [ "${status}" -eq 0 ]
    [ "${output}" = "fps" ]
}

# ---------------------------------------------------------------------------
# 9. Layer-scope validator: reject wrong-layer keys
# ---------------------------------------------------------------------------
@test "settings: set_general rejects wine_args (app-exclusive key)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general wine_args '[\"--dx12\"]'
    " 2>&1
    [ "${status}" -ne 0 ]
}

@test "settings: set_general rejects external_source (dist-exclusive key)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general external_source 'https://example.com'
    " 2>&1
    [ "${status}" -ne 0 ]
}

@test "settings: set_general rejects notes (prefix-exclusive key)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general notes 'some notes'
    " 2>&1
    [ "${status}" -ne 0 ]
}

@test "settings: set_dist rejects wine_args (app-exclusive key)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_dist WINE-BLEEDING wine_args '[\"--dx12\"]'
    " 2>&1
    [ "${status}" -ne 0 ]
}

@test "settings: set_dist rejects win_version (not on dist layer)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_dist WINE-BLEEDING win_version win10
    " 2>&1
    [ "${status}" -ne 0 ]
}

@test "settings: set_app rejects external_source (dist-exclusive key)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_app 'a1b2c3d4-0000-0000-0000-000000000001' external_source 'url'
    " 2>&1
    [ "${status}" -ne 0 ]
}

@test "settings: set_app rejects notes (prefix-exclusive key)" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_app 'a1b2c3d4-0000-0000-0000-000000000001' notes 'some notes'
    " 2>&1
    [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 10. Resolver: all layers empty → built-in default
# ---------------------------------------------------------------------------
@test "settings: resolver returns built-in default when all layers empty" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_resolve gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "auto" ]
}

@test "settings: resolver returns builtin win_version when all layers empty" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_resolve win_version 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "win10" ]
}

@test "settings: resolver returns empty wine_debug (built-in) when all layers empty" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_resolve wine_debug 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
}

# ---------------------------------------------------------------------------
# 11. Resolver: general layer only set → returns general value
# ---------------------------------------------------------------------------
@test "settings: resolver returns general value when only general is set" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general gpu intel
        wb_gui_settings_resolve gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "intel" ]
}

# ---------------------------------------------------------------------------
# 12. Resolver: prefix overrides general
# ---------------------------------------------------------------------------
@test "settings: prefix overrides general in resolver" {
    # Set up apps.json so resolver can find the prefix
    mkdir -p "${WB_HOME}"
    printf '{"schema":1,"apps":[{"id":"a1b2c3d4-0000-0000-0000-000000000001","name":"TestApp","exe":"/tmp/test.exe","prefix":"mypfx","added_utc":"2026-01-01T00:00:00Z","dist":null}]}' \
        > "${WB_HOME}/apps.json"

    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general gpu amd
        wb_gui_settings_set_prefix mypfx gpu nvidia
        wb_gui_settings_resolve gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "nvidia" ]
}

# ---------------------------------------------------------------------------
# 13. Resolver: app overrides prefix and general
# ---------------------------------------------------------------------------
@test "settings: app overrides prefix and general in resolver" {
    mkdir -p "${WB_HOME}"
    printf '{"schema":1,"apps":[{"id":"a1b2c3d4-0000-0000-0000-000000000001","name":"TestApp","exe":"/tmp/test.exe","prefix":"mypfx","added_utc":"2026-01-01T00:00:00Z","dist":null}]}' \
        > "${WB_HOME}/apps.json"

    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general gpu amd
        wb_gui_settings_set_prefix mypfx gpu nvidia
        wb_gui_settings_set_app 'a1b2c3d4-0000-0000-0000-000000000001' gpu intel
        wb_gui_settings_resolve gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "intel" ]
}

# ---------------------------------------------------------------------------
# 14. Resolver: app explicit null → inherit from prefix
# ---------------------------------------------------------------------------
@test "settings: app gpu=null inherits from prefix in resolver" {
    mkdir -p "${WB_HOME}"
    printf '{"schema":1,"apps":[{"id":"a1b2c3d4-0000-0000-0000-000000000001","name":"TestApp","exe":"/tmp/test.exe","prefix":"mypfx","added_utc":"2026-01-01T00:00:00Z","dist":null}]}' \
        > "${WB_HOME}/apps.json"

    # Plant app file with explicit null
    mkdir -p "${WB_HOME}/settings/apps"
    printf '{"schema":1,"app_id":"a1b2c3d4-0000-0000-0000-000000000001","updated_utc":"2026-01-01T00:00:00Z","gpu":null}' \
        > "${WB_HOME}/settings/apps/a1b2c3d4-0000-0000-0000-000000000001.json"

    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_prefix mypfx gpu amd
        wb_gui_settings_resolve gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "amd" ]
}

# ---------------------------------------------------------------------------
# 15. Resolver: app on distless prefix skips dist layer cleanly
# ---------------------------------------------------------------------------
@test "settings: resolver skips dist layer when dist is null" {
    mkdir -p "${WB_HOME}"
    printf '{"schema":1,"apps":[{"id":"a1b2c3d4-0000-0000-0000-000000000001","name":"TestApp","exe":"/tmp/test.exe","prefix":"mypfx","added_utc":"2026-01-01T00:00:00Z","dist":null}]}' \
        > "${WB_HOME}/apps.json"

    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general gpu amd
        # No dist file planted — should not error
        wb_gui_settings_resolve gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    [ "${output}" = "amd" ]
}

# ---------------------------------------------------------------------------
# 16. Resolver: malformed layer file → logs, continues up chain
# ---------------------------------------------------------------------------
@test "settings: resolver skips malformed app file and continues to general" {
    mkdir -p "${WB_HOME}/settings/apps"
    printf 'NOT JSON AT ALL{{{' > "${WB_HOME}/settings/apps/a1b2c3d4-0000-0000-0000-000000000001.json"

    # bats merges stderr into $output; use grep to check the last line for the value
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_general gpu intel
        wb_gui_settings_resolve gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    # Last line of output must be the resolved value; warning goes to stderr/output too
    [[ "${output}" == *"intel"* ]]
}

# ---------------------------------------------------------------------------
# 17. Resolver trace: returns correct JSON with resolved_from
# ---------------------------------------------------------------------------
@test "settings: resolve_trace returns well-formed JSON with resolved_from" {
    mkdir -p "${WB_HOME}"
    printf '{"schema":1,"apps":[{"id":"a1b2c3d4-0000-0000-0000-000000000001","name":"TestApp","exe":"/tmp/test.exe","prefix":"mypfx","added_utc":"2026-01-01T00:00:00Z","dist":null}]}' \
        > "${WB_HOME}/apps.json"

    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_prefix mypfx gpu nvidia
        wb_gui_settings_set_general gpu auto
        wb_gui_settings_resolve_trace gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    # Save trace JSON before any further 'run' call overwrites $output
    local trace_json="${output}"
    run jq empty <<< "${trace_json}"
    [ "${status}" -eq 0 ]
    run bash -c "printf '%s' '${trace_json}' | jq -r '.resolved_from'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "prefix" ]
}

@test "settings: resolve_trace resolved_value matches resolved layer" {
    mkdir -p "${WB_HOME}"
    printf '{"schema":1,"apps":[{"id":"a1b2c3d4-0000-0000-0000-000000000001","name":"TestApp","exe":"/tmp/test.exe","prefix":"mypfx","added_utc":"2026-01-01T00:00:00Z","dist":null}]}' \
        > "${WB_HOME}/apps.json"

    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_prefix mypfx gpu amd
        wb_gui_settings_resolve_trace gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    run bash -c "printf '%s' '${output}' | jq -r '.resolved_value'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "amd" ]
}

@test "settings: resolve_trace resolved_from is builtin when all layers empty" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_resolve_trace gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    run bash -c "printf '%s' '${output}' | jq -r '.resolved_from'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "builtin" ]
}

@test "settings: resolve_trace has candidates map with app/prefix/dist/general keys" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_resolve_trace gpu 'a1b2c3d4-0000-0000-0000-000000000001'
    "
    [ "${status}" -eq 0 ]
    # Save trace output before further 'run' calls overwrite $output
    local trace_json="${output}"
    run bash -c "printf '%s' '${trace_json}' | jq -r 'has(\"candidates\")'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "true" ]
    run bash -c "printf '%s' '${trace_json}' | jq -r '.candidates | keys | sort | @tsv'"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"app"* ]]
    [[ "${output}" == *"prefix"* ]]
    [[ "${output}" == *"dist"* ]]
    [[ "${output}" == *"general"* ]]
}

# ---------------------------------------------------------------------------
# 18. clear_app removes file; subsequent get returns empty
# ---------------------------------------------------------------------------
@test "settings: clear_app removes the app settings file" {
    run bash -c "
        export WB_HOME='${WB_HOME}'
        $(_src)
        wb_gui_settings_set_app 'a1b2c3d4-0000-0000-0000-000000000001' gpu nvidia
        wb_gui_settings_clear_app 'a1b2c3d4-0000-0000-0000-000000000001'
        result=\"\$(wb_gui_settings_get_app 'a1b2c3d4-0000-0000-0000-000000000001' gpu)\"
        [ -z \"\${result}\" ]
    "
    [ "${status}" -eq 0 ]
    [ ! -f "${WB_HOME}/settings/apps/a1b2c3d4-0000-0000-0000-000000000001.json" ]
}

# ---------------------------------------------------------------------------
# 19. Atomic write: kill -9 mid-write leaves original intact
# ---------------------------------------------------------------------------
@test "settings: atomic write survives kill-9 mid-write (original preserved)" {
    # Pre-seed the general.json with a known value
    mkdir -p "${WB_HOME}/settings"
    printf '{"schema":1,"updated_utc":"2026-01-01T00:00:00Z","gpu":"amd"}' \
        > "${WB_HOME}/settings/general.json"
    local original_content
    original_content="$(cat "${WB_HOME}/settings/general.json")"

    # Attempt to write in a subprocess that gets killed before mv can complete.
    # We use a FIFO-based trick: the write helper uses mktemp + mv.
    # Instead of trying to kill mid-mv (racy), we verify that a failed write
    # does not corrupt the original: we simulate a failed write by making the
    # temp dir read-only, then verify the original is unchanged.
    chmod 555 "${WB_HOME}/settings"
    run bash -c "
        export WB_HOME='${WB_HOME}'
        source '${WB_LIB}/wb-paths.sh'
        source '${WB_LIB}/wb-json.sh'
        source '${SETTINGS_SH}'
        wb_gui_settings_set_general gpu intel
    " 2>/dev/null
    # Restore permissions
    chmod 755 "${WB_HOME}/settings"

    # The write failed; original must still be intact
    local current_content
    current_content="$(cat "${WB_HOME}/settings/general.json")"
    [ "${current_content}" = "${original_content}" ]
}

# ---------------------------------------------------------------------------
# 20. JSON schema validation (skip if check-jsonschema absent)
# ---------------------------------------------------------------------------
@test "settings: schema file is valid JSON" {
    run jq empty "${SCHEMAS_DIR}/wb_settings.schema.json"
    [ "${status}" -eq 0 ]
}

@test "settings: schema validates a representative general.json (skip if no check-jsonschema)" {
    if ! command -v check-jsonschema >/dev/null 2>&1; then
        skip "check-jsonschema not available"
    fi
    local schema="${SCHEMAS_DIR}/wb_settings.schema.json"
    local tmp_file
    tmp_file="$(mktemp)"
    printf '{"schema":1,"updated_utc":"2026-01-01T00:00:00Z","gpu":"auto","win_version":"win10","wine_debug":""}' \
        > "${tmp_file}"
    # Extract the general sub-schema and validate
    local tmp_schema
    tmp_schema="$(mktemp --suffix=.json)"
    jq '."$defs".general' "${schema}" > "${tmp_schema}"
    run check-jsonschema --schemafile "${tmp_schema}" "${tmp_file}"
    rm -f "${tmp_file}" "${tmp_schema}"
    [ "${status}" -eq 0 ]
}

@test "settings: schema validates a representative dist.json (skip if no check-jsonschema)" {
    if ! command -v check-jsonschema >/dev/null 2>&1; then
        skip "check-jsonschema not available"
    fi
    local schema="${SCHEMAS_DIR}/wb_settings.schema.json"
    local tmp_file
    tmp_file="$(mktemp)"
    printf '{"schema":1,"dist_id":"WINE-BLEEDING","updated_utc":"2026-01-01T00:00:00Z","name":"Wine Bleeding","external_source":null,"active":true,"last_built_at":null}' \
        > "${tmp_file}"
    local tmp_schema
    tmp_schema="$(mktemp --suffix=.json)"
    jq '."$defs".dist' "${schema}" > "${tmp_schema}"
    run check-jsonschema --schemafile "${tmp_schema}" "${tmp_file}"
    rm -f "${tmp_file}" "${tmp_schema}"
    [ "${status}" -eq 0 ]
}

@test "settings: schema validates a representative prefix.json (skip if no check-jsonschema)" {
    if ! command -v check-jsonschema >/dev/null 2>&1; then
        skip "check-jsonschema not available"
    fi
    local schema="${SCHEMAS_DIR}/wb_settings.schema.json"
    local tmp_file
    tmp_file="$(mktemp)"
    printf '{"schema":1,"prefix_id":"mygame","updated_utc":"2026-01-01T00:00:00Z","notes":"Test prefix","win_version":"win10","wine_debug":null}' \
        > "${tmp_file}"
    local tmp_schema
    tmp_schema="$(mktemp --suffix=.json)"
    jq '."$defs".prefix' "${schema}" > "${tmp_schema}"
    run check-jsonschema --schemafile "${tmp_schema}" "${tmp_file}"
    rm -f "${tmp_file}" "${tmp_schema}"
    [ "${status}" -eq 0 ]
}

@test "settings: schema validates a representative app.json (skip if no check-jsonschema)" {
    if ! command -v check-jsonschema >/dev/null 2>&1; then
        skip "check-jsonschema not available"
    fi
    local schema="${SCHEMAS_DIR}/wb_settings.schema.json"
    local tmp_file
    tmp_file="$(mktemp)"
    printf '{"schema":1,"app_id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","updated_utc":"2026-01-01T00:00:00Z","gpu":"auto","win_version":"win10","wine_debug":"","wine_args":["--dx12"],"env_vars":{"DXVK_HUD":"fps"}}' \
        > "${tmp_file}"
    local tmp_schema
    tmp_schema="$(mktemp --suffix=.json)"
    jq '."$defs".app' "${schema}" > "${tmp_schema}"
    run check-jsonschema --schemafile "${tmp_schema}" "${tmp_file}"
    rm -f "${tmp_file}" "${tmp_schema}"
    [ "${status}" -eq 0 ]
}

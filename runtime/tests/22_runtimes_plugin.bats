#!/usr/bin/env bats
# M13 runtime plugin registry tests

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_PLUGIN="${BATS_TEST_DIRNAME}/fixtures/runtime-plugins/ge-proton-9-26.json"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
  mkdir -p "${TEST_HOME}/dist"

  # Stage a fake external Wine build root so register passes the new
  # existence + bin/wine executable checks (W2 M13-retro #1).
  FAKE_PLUGIN_ROOT="${TEST_HOME}/fake-ge-proton"
  mkdir -p "${FAKE_PLUGIN_ROOT}/bin"
  cat > "${FAKE_PLUGIN_ROOT}/bin/wine" <<'EOF'
#!/usr/bin/env bash
echo "fake wine $*"
EOF
  chmod +x "${FAKE_PLUGIN_ROOT}/bin/wine"

  # Generate the plugin JSON pointing at the staged root.
  STAGED_PLUGIN="${TEST_HOME}/plugin.json"
  cat > "${STAGED_PLUGIN}" <<EOF
{
  "schema": 1,
  "name": "GE-Proton-9-26",
  "path": "${FAKE_PLUGIN_ROOT}",
  "kind": "external",
  "wine_major_version": "9",
  "notes": "GloriousEggroll's Proton build (staged for bats test)"
}
EOF
  # Override FIXTURE_PLUGIN for every test in this file so they use the staged copy.
  FIXTURE_PLUGIN="${STAGED_PLUGIN}"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# Helper: source all needed libs for unit-style tests
_source_runtimes() {
  source "${WB_LIB}/wb-paths.sh"
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-json.sh"
  source "${WB_LIB}/wb-runtimes.sh"
}

# Helper: source libs needed for wb_runtime_resolve tests (includes multibuild)
_source_resolve() {
  source "${WB_LIB}/wb-paths.sh"
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-json.sh"
  source "${WB_LIB}/wb-runtimes.sh"
  source "${WB_LIB}/wb-dist.sh"
  source "${WB_LIB}/wb-config.sh"
  source "${WB_LIB}/wb-multibuild.sh"
}

# ---------------------------------------------------------------------------
# Test 1: wb runtime register creates the plugin JSON file
# ---------------------------------------------------------------------------
@test "runtime register: creates plugins/runtimes.d/GE-Proton-9-26.json" {
  run "${WB}" runtime register "${FIXTURE_PLUGIN}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"registered: GE-Proton-9-26"* ]]
  local dest="${WB_HOME}/plugins/runtimes.d/GE-Proton-9-26.json"
  [ -f "${dest}" ]
  run jq -r '.name' "${dest}"
  [ "${output}" = "GE-Proton-9-26" ]
}

# ---------------------------------------------------------------------------
# Test 2: Idempotent — second register of same content is a no-op
# ---------------------------------------------------------------------------
@test "runtime register: idempotent — same content produces no error and no duplicate" {
  "${WB}" runtime register "${FIXTURE_PLUGIN}"
  local mtime_before
  mtime_before="$(stat -c '%Y' "${WB_HOME}/plugins/runtimes.d/GE-Proton-9-26.json")"
  # Sleep briefly to distinguish mtime
  sleep 0.1
  run "${WB}" runtime register "${FIXTURE_PLUGIN}"
  [ "${status}" -eq 0 ]
  local mtime_after
  mtime_after="$(stat -c '%Y' "${WB_HOME}/plugins/runtimes.d/GE-Proton-9-26.json")"
  # File should not have been rewritten (same mtime in seconds)
  [ "${mtime_before}" = "${mtime_after}" ]
}

# ---------------------------------------------------------------------------
# Test 3: wb runtime list shows both dist entries and external plugin entries
#         with a KIND column
# ---------------------------------------------------------------------------
@test "runtime list: shows native and external entries with KIND column" {
  # Install a fake native dist
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-fixture"
  # Register an external plugin
  "${WB}" runtime register "${FIXTURE_PLUGIN}"

  run "${WB}" runtime list
  [ "${status}" -eq 0 ]
  # Header must include KIND
  [[ "${output}" == *"KIND"* ]]
  # Native dist entry
  [[ "${output}" == *"WINE-BLEEDING-fixture"* ]]
  [[ "${output}" == *"native"* ]]
  # External plugin entry
  [[ "${output}" == *"GE-Proton-9-26"* ]]
  [[ "${output}" == *"external"* ]]
}

# ---------------------------------------------------------------------------
# Test 4: --native flag shows only dists, not plugins
# ---------------------------------------------------------------------------
@test "runtime list --native: excludes external plugins" {
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-fixture"
  "${WB}" runtime register "${FIXTURE_PLUGIN}"

  run "${WB}" runtime list --native
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WINE-BLEEDING-fixture"* ]]
  [[ "${output}" != *"GE-Proton-9-26"* ]]
}

# ---------------------------------------------------------------------------
# Test 5: --external flag shows only plugins, not dists
# ---------------------------------------------------------------------------
@test "runtime list --external: excludes native dists" {
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-fixture"
  "${WB}" runtime register "${FIXTURE_PLUGIN}"

  run "${WB}" runtime list --external
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"GE-Proton-9-26"* ]]
  [[ "${output}" != *"WINE-BLEEDING-fixture"* ]]
}

# ---------------------------------------------------------------------------
# Test 6: wb runtime unregister removes the JSON file
# ---------------------------------------------------------------------------
@test "runtime unregister: removes the plugin JSON" {
  "${WB}" runtime register "${FIXTURE_PLUGIN}"
  local dest="${WB_HOME}/plugins/runtimes.d/GE-Proton-9-26.json"
  [ -f "${dest}" ]

  run "${WB}" runtime unregister GE-Proton-9-26
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"unregistered: GE-Proton-9-26"* ]]
  [ ! -f "${dest}" ]
}

# ---------------------------------------------------------------------------
# Test 7: wb_runtime_resolve returns the plugin's path when registered
# ---------------------------------------------------------------------------
@test "wb_runtime_resolve: returns plugin path for registered external runtime" {
  local test_home="${TEST_HOME}"
  local fixture="${FIXTURE_PLUGIN}"
  local wb_lib="${WB_LIB}"

  run bash <<EOF
    set -euo pipefail
    export WB_HOME="${test_home}"
    export WB_LOG_FILE="${test_home}/wb.log"
    source "${wb_lib}/wb-paths.sh"
    source "${wb_lib}/wb-log.sh"
    source "${wb_lib}/wb-json.sh"
    source "${wb_lib}/wb-runtimes.sh"
    source "${wb_lib}/wb-dist.sh"
    source "${wb_lib}/wb-config.sh"
    source "${wb_lib}/wb-multibuild.sh"
    wb_runtimes_plugin_register "${fixture}" >/dev/null 2>&1
    result="\$(wb_runtime_resolve 'GE-Proton-9-26' 2>/dev/null)"
    echo "\${result}"
EOF
  [ "${status}" -eq 0 ]
  # Resolver now canonicalises via realpath; compare against realpath of the staged root.
  [ "${output}" = "$(realpath -m "${FAKE_PLUGIN_ROOT}")" ]
}

# ---------------------------------------------------------------------------
# Test 8: dist wins over plugin when both share a name (dist takes precedence)
# ---------------------------------------------------------------------------
@test "wb_runtime_resolve: dist wins over plugin when both share the same name" {
  # Create a fake dist with the same name as the plugin
  mkdir -p "${TEST_HOME}/dist/GE-Proton-9-26"

  local test_home="${TEST_HOME}"
  local fixture="${FIXTURE_PLUGIN}"
  local wb_lib="${WB_LIB}"

  run bash <<EOF
    set -euo pipefail
    export WB_HOME="${test_home}"
    export WB_LOG_FILE="${test_home}/wb.log"
    source "${wb_lib}/wb-paths.sh"
    source "${wb_lib}/wb-log.sh"
    source "${wb_lib}/wb-json.sh"
    source "${wb_lib}/wb-runtimes.sh"
    source "${wb_lib}/wb-dist.sh"
    source "${wb_lib}/wb-config.sh"
    source "${wb_lib}/wb-multibuild.sh"
    wb_runtimes_plugin_register "${fixture}" >/dev/null 2>&1
    result="\$(wb_runtime_resolve 'GE-Proton-9-26' 2>/dev/null)"
    echo "\${result}"
EOF
  [ "${status}" -eq 0 ]
  # Should be the dist/ path, not /opt/ge-proton-9-26
  [ "${output}" = "${test_home}/dist/GE-Proton-9-26" ]
}

# ---------------------------------------------------------------------------
# Test 9: Malformed JSON plugin warns but list still shows valid plugins
# ---------------------------------------------------------------------------
@test "runtime list: malformed plugin JSON skipped with WARN, others visible" {
  # Write a bad JSON file directly into the plugin dir
  mkdir -p "${TEST_HOME}/plugins/runtimes.d"
  echo '{not valid json' > "${TEST_HOME}/plugins/runtimes.d/bad-plugin.json"
  # Register a good plugin
  "${WB}" runtime register "${FIXTURE_PLUGIN}"

  run "${WB}" runtime list --external
  [ "${status}" -eq 0 ]
  # Good plugin still appears
  [[ "${output}" == *"GE-Proton-9-26"* ]]
  # Bad plugin does not appear as an entry
  [[ "${output}" != *"bad-plugin"* ]]
}

# ---------------------------------------------------------------------------
# Test 10: Schema violation — missing 'path' field — register rejects
# ---------------------------------------------------------------------------
@test "runtime register: rejects plugin JSON missing required 'path' field" {
  local bad_json="${TEST_HOME}/no-path.json"
  printf '{"schema":1,"name":"NoPather","kind":"external"}' > "${bad_json}"

  run "${WB}" runtime register "${bad_json}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"path"* ]] || [[ "${stderr}" == *"path"* ]]
  # File must NOT have been created in plugin dir
  [ ! -f "${TEST_HOME}/plugins/runtimes.d/NoPather.json" ]
}

# ---------------------------------------------------------------------------
# Test 11: Invalid name (path traversal via ..) — register rejects
# ---------------------------------------------------------------------------
@test "runtime register: rejects plugin JSON with traversal-style name (..)" {
  local bad_json="${TEST_HOME}/bad-name.json"
  printf '{"schema":1,"name":"../etc/passwd","path":"/opt/wine","kind":"external"}' > "${bad_json}"

  run "${WB}" runtime register "${bad_json}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"invalid name"* ]] || [[ "${output}" == *"must match"* ]]
}

# ---------------------------------------------------------------------------
# Test 12: Non-absolute path value — register rejects
# ---------------------------------------------------------------------------
@test "runtime register: rejects plugin JSON with relative 'path' value" {
  local bad_json="${TEST_HOME}/rel-path.json"
  printf '{"schema":1,"name":"RelRuntime","path":"relative/path/wine","kind":"external"}' > "${bad_json}"

  run "${WB}" runtime register "${bad_json}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"absolute"* ]] || [[ "${output}" == *"path"* ]]
  [ ! -f "${TEST_HOME}/plugins/runtimes.d/RelRuntime.json" ]
}

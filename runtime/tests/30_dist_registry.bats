#!/usr/bin/env bats
# 30_dist_registry.bats — wb-gui-dist.sh registry tests (Phase B)

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
SCHEMA_FILE="${BATS_TEST_DIRNAME}/../share/schemas/wb_dists.schema.json"

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
  mkdir -p "${TEST_HOME}/dist"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_source_dist_registry() {
  source "${WB_LIB}/wb-paths.sh"
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-json.sh"
  source "${WB_LIB}/wb-dist.sh"
  source "${WB_GUI_LIB}/wb-gui-apps.sh"
  source "${WB_GUI_LIB}/wb-gui-dist.sh"
}

_make_native_dist() {
  local name="$1"
  local dist_path="${TEST_HOME}/dist/${name}"
  cp -a "${FIXTURE_DIST}/." "${dist_path}"
  # Ensure bin/wine exists and is executable
  mkdir -p "${dist_path}/bin"
  if [[ ! -x "${dist_path}/bin/wine" ]]; then
    printf '#!/usr/bin/env bash\necho "wine %s" "$@"\n' "${name}" > "${dist_path}/bin/wine"
    chmod +x "${dist_path}/bin/wine"
  fi
  echo "${dist_path}"
}

_make_external_dist() {
  local name="$1"
  local path="${TEST_HOME}/external/${name}"
  mkdir -p "${path}/bin"
  printf '#!/usr/bin/env bash\necho "external wine %s" "$@"\n' "${name}" > "${path}/bin/wine"
  chmod +x "${path}/bin/wine"

  mkdir -p "${TEST_HOME}/plugins/runtimes.d"
  local plugin_file="${TEST_HOME}/plugins/runtimes.d/${name}.json"
  printf '{"schema":1,"name":"%s","path":"%s","wine_version":"9.0"}\n' \
    "${name}" "${path}" > "${plugin_file}"
  echo "${path}"
}

# ---------------------------------------------------------------------------
# 1. Registry refresh — idempotency
# ---------------------------------------------------------------------------
@test "registry_refresh: idempotent — two refreshes produce same dists array" {
  _make_native_dist "WINE-BLEEDING-20260101" >/dev/null
  _make_native_dist "WINE-BLEEDING-20260201" >/dev/null

  run bash -c "
    $(declare -f _source_dist_registry)
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    first=\$(jq -c '.dists | map(.name) | sort' \"\${WB_HOME}/dists.json\")
    wb_gui_dist_registry_refresh
    second=\$(jq -c '.dists | map(.name) | sort' \"\${WB_HOME}/dists.json\")
    [[ \"\$first\" == \"\$second\" ]] && echo 'IDEMPOTENT'
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"IDEMPOTENT"* ]]
}

# ---------------------------------------------------------------------------
# 2. Registry refresh — native dist appears with correct fields
# ---------------------------------------------------------------------------
@test "registry_refresh: native dist listed with source=native and broken=false" {
  _make_native_dist "WINE-BLEEDING-20260420" >/dev/null

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    jq -r '.dists[0] | \"source=\" + .source + \" broken=\" + (.broken | tostring)' \
      \"\${WB_HOME}/dists.json\"
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"source=native"* ]]
  [[ "${output}" == *"broken=false"* ]]
}

# ---------------------------------------------------------------------------
# 3. Registry refresh — active alias tracked correctly
# ---------------------------------------------------------------------------
@test "registry_refresh: active alias reflected in registry" {
  _make_native_dist "WINE-BLEEDING-20260101" >/dev/null
  _make_native_dist "WINE-BLEEDING-20260201" >/dev/null
  # Set alias to second dist
  ln -sfn "${TEST_HOME}/dist/WINE-BLEEDING-20260201" "${TEST_HOME}/dist/WINE-BLEEDING"

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    jq -r '.active' \"\${WB_HOME}/dists.json\"
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == "WINE-BLEEDING-20260201" ]]
}

# ---------------------------------------------------------------------------
# 4. Registry refresh — external dist listed with source=external
# ---------------------------------------------------------------------------
@test "registry_refresh: external dist listed with source=external" {
  _make_external_dist "ge-proton-9-26" >/dev/null

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    jq -r '.dists[0].source' \"\${WB_HOME}/dists.json\"
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == "external" ]]
}

# ---------------------------------------------------------------------------
# 5. wb_gui_dist_add_external — registers external dist
# ---------------------------------------------------------------------------
@test "dist_add_external: valid path registers dist and appears in registry" {
  local ext_path="${TEST_HOME}/custom-wine"
  mkdir -p "${ext_path}/bin"
  printf '#!/usr/bin/env bash\necho "wine fake"\n' > "${ext_path}/bin/wine"
  chmod +x "${ext_path}/bin/wine"

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    wb_gui_dist_add_external '${ext_path}' 'my-custom-wine'
    jq -r '.dists[] | select(.name == \"my-custom-wine\") | .source' \
      \"\${WB_HOME}/dists.json\"
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  # As of v1.7.1-dev, Add External cp -a's the tree into $WB_HOME/dist/<name>/
  # and lets the native auto-scan pick it up — the registered source is
  # "native" because the dist now lives under WB_HOME. Provenance of the
  # original path is recorded in <name>/.wb_external_source.json.
  [[ "${output}" == *"native"* ]]

  # The provenance sidecar must exist and reference the original path.
  local sidecar="${TEST_HOME}/dist/my-custom-wine/.wb_external_source.json"
  [ -f "${sidecar}" ]
  run jq -r '.original_source' "${sidecar}"
  [[ "${output}" == "${ext_path}" ]]
}

# ---------------------------------------------------------------------------
# 6. wb_gui_dist_add_external — rejects duplicate name
# ---------------------------------------------------------------------------
@test "dist_add_external: duplicate name is rejected with error" {
  local ext_path="${TEST_HOME}/custom-wine"
  mkdir -p "${ext_path}/bin"
  printf '#!/usr/bin/env bash\necho "wine"\n' > "${ext_path}/bin/wine"
  chmod +x "${ext_path}/bin/wine"

  # Register once
  bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    wb_gui_dist_add_external '${ext_path}' 'my-wine'
  " WB_HOME="${TEST_HOME}" 2>/dev/null || true

  # Try again with same name
  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_add_external '${ext_path}' 'my-wine'
  " WB_HOME="${TEST_HOME}" 2>&1
  [ "${status}" -ne 0 ]
  # Either pre-validation rejects (registry already has it) or the cp-a
  # collision check rejects (target dir already exists). Both are correct
  # "duplicate" failure modes after the v1.7.1-dev architecture change.
  [[ "${output}" == *"already registered"* || "${output}" == *"already exists"* ]]
}

# ---------------------------------------------------------------------------
# 7. wb_gui_dist_add_external — rejects non-existent path
# ---------------------------------------------------------------------------
@test "dist_add_external: non-existent path is rejected" {
  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_add_external '/does/not/exist' 'ghost'
  " WB_HOME="${TEST_HOME}" 2>&1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"does not exist"* ]]
}

# ---------------------------------------------------------------------------
# 8. wb_gui_dist_apps_clear — clears dist reference on apps
# ---------------------------------------------------------------------------
@test "dist_apps_clear: sets dist=null on apps referencing the removed dist" {
  _make_native_dist "WINE-BLEEDING-20260420" >/dev/null

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'

    # Build an apps.json with one app referencing the dist
    apps_json='{\"schema\":2,\"generated_by\":\"test\",\"updated_utc\":\"2026-01-01T00:00:00Z\",\"apps\":[{\"id\":\"aaa\",\"name\":\"Game\",\"exe\":\"/foo/bar.exe\",\"prefix\":\"test\",\"dist\":\"WINE-BLEEDING-20260420\",\"added_at\":\"2026-01-01T00:00:00Z\",\"last_played\":\"2026-01-01T00:00:00Z\",\"icon_path\":null,\"category\":null,\"wine_args\":[],\"env_vars\":{},\"source\":\"detected\",\"notes\":null}]}'
    printf '%s\n' \"\$apps_json\" > \"\${WB_HOME}/apps.json\"

    wb_gui_dist_apps_clear 'WINE-BLEEDING-20260420'
    jq -r '.apps[0].dist' \"\${WB_HOME}/apps.json\"
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == "null" ]]
}

# ---------------------------------------------------------------------------
# 9. wb_gui_dist_remove — rejects removal of active dist
# ---------------------------------------------------------------------------
@test "dist_remove: active dist removal is rejected" {
  _make_native_dist "WINE-BLEEDING-20260420" >/dev/null
  ln -sfn "${TEST_HOME}/dist/WINE-BLEEDING-20260420" "${TEST_HOME}/dist/WINE-BLEEDING"

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    wb_gui_dist_remove 'WINE-BLEEDING-20260420'
  " WB_HOME="${TEST_HOME}" 2>&1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"cannot remove active dist"* ]]
}

# ---------------------------------------------------------------------------
# 10. Registry JSON conforms to wb_dists schema (if check-jsonschema available)
# ---------------------------------------------------------------------------
@test "registry_refresh: produced dists.json validates against wb_dists.schema.json" {
  if ! command -v check-jsonschema &>/dev/null; then
    skip "check-jsonschema not available"
  fi
  _make_native_dist "WINE-BLEEDING-20260420" >/dev/null

  bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
  " WB_HOME="${TEST_HOME}" 2>/dev/null

  run check-jsonschema --schemafile "${SCHEMA_FILE}" "${TEST_HOME}/dists.json"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 11. rebuildable=true for a dist with the full-build.sh layout even when
#     registered as external (previously misclassified as non-rebuildable).
# ---------------------------------------------------------------------------
@test "registry_refresh: external dist with full-build layout reports rebuildable=true" {
  local ext_path="${TEST_HOME}/external/WINE-BLEEDING-28032026"
  mkdir -p "${ext_path}/bin" "${ext_path}/lib/wine/x86_64-windows"
  printf '#!/usr/bin/env bash\necho wine\n' > "${ext_path}/bin/wine"
  chmod +x "${ext_path}/bin/wine"
  mkdir -p "${TEST_HOME}/plugins/runtimes.d"
  printf '{"schema":1,"name":"%s","path":"%s","wine_version":"11.4"}\n' \
    "WINE-BLEEDING-28032026" "${ext_path}" \
    > "${TEST_HOME}/plugins/runtimes.d/WINE-BLEEDING-28032026.json"

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    jq -r '.dists[] | select(.name == \"WINE-BLEEDING-28032026\") | [.source, .rebuildable] | @tsv' \
      \"\${WB_HOME}/dists.json\"
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == $'external\ttrue' ]]
}

# ---------------------------------------------------------------------------
# 12. rebuildable=false for a dist missing the windows-DLL directory, even
#     when it is a native dist under $WB_HOME/dist/.
# ---------------------------------------------------------------------------
@test "registry_refresh: native dist without lib/wine/x86_64-windows reports rebuildable=false" {
  local native_path="${TEST_HOME}/dist/WINE-BLEEDING-stub"
  mkdir -p "${native_path}/bin"
  printf '#!/usr/bin/env bash\necho wine\n' > "${native_path}/bin/wine"
  chmod +x "${native_path}/bin/wine"
  # Intentionally no lib/wine/x86_64-windows directory.

  run bash -c "
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    wb_gui_dist_registry_refresh
    jq -r '.dists[] | select(.name == \"WINE-BLEEDING-stub\") | .rebuildable' \
      \"\${WB_HOME}/dists.json\"
  " WB_HOME="${TEST_HOME}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [[ "${output}" == "false" ]]
}

# ---------------------------------------------------------------------------
# 13. wb runtime activate resolves an external dist registered as a plugin
#     (previously failed with "dist not found in $WB_HOME/dist").
# ---------------------------------------------------------------------------
@test "wb runtime activate: resolves external dist via plugins/runtimes.d" {
  local ext_path="${TEST_HOME}/external/WINE-BLEEDING-28032026"
  mkdir -p "${ext_path}/bin"
  printf '#!/usr/bin/env bash\necho wine\n' > "${ext_path}/bin/wine"
  chmod +x "${ext_path}/bin/wine"
  mkdir -p "${TEST_HOME}/plugins/runtimes.d"
  printf '{"schema":1,"name":"%s","path":"%s","wine_version":"11.4"}\n' \
    "WINE-BLEEDING-28032026" "${ext_path}" \
    > "${TEST_HOME}/plugins/runtimes.d/WINE-BLEEDING-28032026.json"

  local wb_bin="${BATS_TEST_DIRNAME}/../src/wb"
  run env WB_HOME="${TEST_HOME}" WB_LOG_FILE="${TEST_HOME}/wb.log" \
    "${wb_bin}" runtime activate WINE-BLEEDING-28032026
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Activated: WINE-BLEEDING-28032026"* ]]
  # Alias should now point at the external path.
  local alias_target
  alias_target="$(readlink -f "${TEST_HOME}/dist/WINE-BLEEDING" 2>/dev/null || true)"
  local expected
  expected="$(readlink -f "${ext_path}")"
  [ "${alias_target}" = "${expected}" ]
}

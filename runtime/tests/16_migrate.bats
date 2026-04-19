#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# 16_migrate.bats — prefix migrate / export tests (M7)
# Uses runtime/tests/fixtures/fake-pp-prefix/ from M3.
# ---------------------------------------------------------------------------

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
FIXTURE_PP_PREFIX="${BATS_TEST_DIRNAME}/fixtures/fake-pp-prefix"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="${TEST_HOME}"
  export XDG_DATA_HOME="${TEST_HOME}/.local/share"
  export XDG_CONFIG_HOME="${TEST_HOME}/.config"
  WB_HOME="${XDG_DATA_HOME}/wine-bleeding"
  export WB_HOME
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  # Create a fake PP root with one prefix copied from the fixture
  FAKE_PP="${TEST_HOME}/FakePP"
  FAKE_PP_DATA="${FAKE_PP}/data"
  FAKE_PP_PREFIXES="${FAKE_PP_DATA}/prefixes"
  mkdir -p "${FAKE_PP_PREFIXES}"
  cp -a "${FIXTURE_PP_PREFIX}" "${FAKE_PP_PREFIXES}/FOO"
  export PORT_WINE_PATH="${FAKE_PP}"

  # Set up $WB_HOME layout
  mkdir -p "${WB_HOME}/prefixes" "${WB_HOME}/dist" "${WB_HOME}/log"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# Helper: compute sha256 hash of a directory tree (sorted, stable)
# Uses run internally to avoid set -euo pipefail on xargs exit codes.
# ---------------------------------------------------------------------------
_tree_sha256() {
  local dir="$1"
  # Suppress xargs 123 exit (no files found or all disappeared) gracefully
  bash -c "find '${dir}' -type f | sort | xargs sha256sum 2>/dev/null || true" | sha256sum | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# 1. migrate copies PP prefix into $WB_HOME/prefixes/FOO
# ---------------------------------------------------------------------------
@test "migrate: copies PP prefix into WB_HOME/prefixes/FOO" {
  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -eq 0 ]
  [ -d "${WB_HOME}/prefixes/FOO" ]
}

# ---------------------------------------------------------------------------
# 2. PP original is UNCHANGED after migration (sha256 tree identical)
# ---------------------------------------------------------------------------
@test "migrate: PP original is untouched after migration" {
  local sha_before
  sha_before="$(_tree_sha256 "${FAKE_PP_PREFIXES}/FOO")"

  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -eq 0 ]

  local sha_after
  sha_after="$(_tree_sha256 "${FAKE_PP_PREFIXES}/FOO")"

  [ "${sha_before}" = "${sha_after}" ]
}

# ---------------------------------------------------------------------------
# 3. Migrated prefix has .wb_runtime sentinel and .wine_ver=WINE-BLEEDING
# ---------------------------------------------------------------------------
@test "migrate: migrated prefix has .wb_runtime sentinel and .wine_ver=WINE-BLEEDING" {
  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -eq 0 ]

  local wb_pfx="${WB_HOME}/prefixes/FOO"
  [ -f "${wb_pfx}/.wb_runtime" ]
  # Sentinel must be valid JSON
  run jq empty "${wb_pfx}/.wb_runtime"
  [ "${status}" -eq 0 ]

  # .wine_ver must be WINE-BLEEDING (take-over mode)
  [ -f "${wb_pfx}/.wine_ver" ]
  local wine_ver
  wine_ver="$(cat "${wb_pfx}/.wine_ver")"
  [ "${wine_ver}" = "WINE-BLEEDING" ]
}

# ---------------------------------------------------------------------------
# 4. Migrate refuses when target already exists unless --overwrite
# ---------------------------------------------------------------------------
@test "migrate: refuses when target exists without --overwrite" {
  mkdir -p "${WB_HOME}/prefixes/FOO"

  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"already exists"* ]]

  # With --overwrite it should succeed
  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}" --overwrite
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5. export copies wb prefix to PP-shaped path
# ---------------------------------------------------------------------------
@test "export: copies wb prefix to PP prefixes directory" {
  # First migrate so we have a wb prefix
  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -eq 0 ]

  local new_pp="${TEST_HOME}/NewPP"
  run "${WB}" prefix export --to-portproton FOO --pp-path "${new_pp}"
  [ "${status}" -eq 0 ]

  [ -d "${new_pp}/data/prefixes/FOO" ]
}

# ---------------------------------------------------------------------------
# 6. Export refuses when target already exists unless --overwrite
# ---------------------------------------------------------------------------
@test "export: refuses when PP target exists without --overwrite" {
  # Migrate first
  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -eq 0 ]

  # Export to the same fake PP (FOO already exists there)
  run "${WB}" prefix export --to-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"already exists"* ]]

  # With --overwrite it should succeed
  run "${WB}" prefix export --to-portproton FOO --pp-path "${FAKE_PP}" --overwrite
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 7. Round-trip: migrate PP -> wb, export wb -> new-pp; check structural equivalence
# ---------------------------------------------------------------------------
@test "migrate+export: round-trip preserves drive_c/ contents" {
  # Migrate
  run "${WB}" prefix migrate --from-portproton FOO --pp-path "${FAKE_PP}"
  [ "${status}" -eq 0 ]

  # Export to a new PP
  local new_pp="${TEST_HOME}/NewPP"
  run "${WB}" prefix export --to-portproton FOO --pp-path "${new_pp}"
  [ "${status}" -eq 0 ]

  # Compare drive_c/ contents of original PP prefix and newly-exported PP prefix
  local orig_drive_c="${FAKE_PP_PREFIXES}/FOO/drive_c"
  local new_drive_c="${new_pp}/data/prefixes/FOO/drive_c"

  # Both drive_c trees must contain the same set of files
  local orig_files new_files
  orig_files="$(find "${orig_drive_c}" -type f | sed "s|${orig_drive_c}/||" | sort)"
  new_files="$(find "${new_drive_c}"  -type f | sed "s|${new_drive_c}/||"  | sort)"
  [ "${orig_files}" = "${new_files}" ]
}

# ---------------------------------------------------------------------------
# 8. Migration with absent NAME prints clear error and exits 1
# ---------------------------------------------------------------------------
@test "migrate: missing NAME exits 1 with clear error" {
  run "${WB}" prefix migrate --from-portproton NONEXISTENT_PREFIX_XYZ --pp-path "${FAKE_PP}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"not found"* ]]
}

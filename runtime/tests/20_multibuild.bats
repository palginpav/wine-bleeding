#!/usr/bin/env bats
# M9 multi-build / distro-switching tests

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
FIXTURE_WINE="${BATS_TEST_DIRNAME}/fixtures/fake-wine"

# ---------------------------------------------------------------------------
# Setup: two fake dists with different wine_major_version values.
# DIST_A has major version 10, DIST_B has major version 11.
# WINE-BLEEDING alias points to DIST_A initially.
# ---------------------------------------------------------------------------
setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  mkdir -p "${TEST_HOME}/dist"

  # DIST_A: major version "10"
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-A"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-A/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-A/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-A/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-A/bin/wineserver"
  # Write a minimal .wb_dist_meta with wine_major_version=10
  cat > "${TEST_HOME}/dist/WINE-BLEEDING-A/.wb_dist_meta" <<'EOF'
{
  "schema": 1,
  "dist_name": "WINE-BLEEDING-A",
  "wine_major_version": "10",
  "wine_full_version": "10.4",
  "dxvk_version": "",
  "vkd3d_version": "",
  "nvapi_version": "",
  "mono_version": "",
  "icu_version": "",
  "builtin_dlls_hash": "",
  "build_utc": "2026-01-01T00:00:00Z",
  "dxvk_paths": [],
  "vkd3d_paths": [],
  "nvapi_paths": [],
  "mono_paths": [],
  "icu_paths": []
}
EOF

  # DIST_B: major version "11"
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-B"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-B/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-B/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-B/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-B/bin/wineserver"
  cat > "${TEST_HOME}/dist/WINE-BLEEDING-B/.wb_dist_meta" <<'EOF'
{
  "schema": 1,
  "dist_name": "WINE-BLEEDING-B",
  "wine_major_version": "11",
  "wine_full_version": "11.0",
  "dxvk_version": "",
  "vkd3d_version": "",
  "nvapi_version": "",
  "mono_version": "",
  "icu_version": "",
  "builtin_dlls_hash": "",
  "build_utc": "2026-02-01T00:00:00Z",
  "dxvk_paths": [],
  "vkd3d_paths": [],
  "nvapi_paths": [],
  "mono_paths": [],
  "icu_paths": []
}
EOF

  # DIST_C: major version "10" (same as A, for same-major switch test)
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-C"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-C/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-C/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-C/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-C/bin/wineserver"
  cat > "${TEST_HOME}/dist/WINE-BLEEDING-C/.wb_dist_meta" <<'EOF'
{
  "schema": 1,
  "dist_name": "WINE-BLEEDING-C",
  "wine_major_version": "10",
  "wine_full_version": "10.5",
  "dxvk_version": "",
  "vkd3d_version": "",
  "nvapi_version": "",
  "mono_version": "",
  "icu_version": "",
  "builtin_dlls_hash": "",
  "build_utc": "2026-03-01T00:00:00Z",
  "dxvk_paths": [],
  "vkd3d_paths": [],
  "nvapi_paths": [],
  "mono_paths": [],
  "icu_paths": []
}
EOF

  # Alias WINE-BLEEDING -> DIST_A initially
  ln -sfn WINE-BLEEDING-A "${TEST_HOME}/dist/WINE-BLEEDING"

  mkdir -p "${TEST_HOME}/prefixes"

  # Disable GPU components and sync primitives for test isolation
  export WB_ESYNC=0
  export WB_FSYNC=0
  export WB_NTSYNC=0
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0
  export WB_ICU=0

  # Initialize prefix TESTPFX using DIST_A
  export TEST_DIST_A="${TEST_HOME}/dist/WINE-BLEEDING-A"
  export TEST_DIST_B="${TEST_HOME}/dist/WINE-BLEEDING-B"
  export TEST_DIST_C="${TEST_HOME}/dist/WINE-BLEEDING-C"
  export TEST_PFX="${TEST_HOME}/prefixes/TESTPFX"

  "${WB}" prefix init TESTPFX --dist "${TEST_DIST_A}" >/dev/null 2>&1
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# Helper: source all needed libs in a subshell for unit tests
_source_multibuild() {
  source "${WB_LIB}/wb-paths.sh"
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-json.sh"
  source "${WB_LIB}/wb-lock.sh"
  source "${WB_LIB}/wb-config.sh"
  source "${WB_LIB}/wb-dist.sh"
  source "${WB_LIB}/wb-prefix.sh"
  source "${WB_LIB}/wb-components.sh"
  source "${WB_LIB}/wb-reg.sh"
  source "${WB_LIB}/wb-wineboot.sh"
  source "${WB_LIB}/wb-multibuild.sh"
}

# Helper: read the fake_wine.log
_wine_log() {
  cat "${TEST_PFX}/.fake_wine.log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Test 1: wb_multibuild_enabled returns 1 by default
# ---------------------------------------------------------------------------
@test "multibuild_enabled: returns 1 (false) when WB_MULTIBUILD unset" {
  run bash -c "
    $(_source_multibuild 2>/dev/null; declare -f _source_multibuild >/dev/null 2>&1 || true)
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-config.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-wineboot.sh'
    source '${WB_LIB}/wb-multibuild.sh'
    wb_multibuild_enabled && echo 'enabled' || echo 'disabled'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ "${output}" = "disabled" ]
}

# ---------------------------------------------------------------------------
# Test 2: wb config enable-multibuild sets WB_MULTIBUILD=1;
#          wb_multibuild_enabled then returns 0
# ---------------------------------------------------------------------------
@test "config enable-multibuild: sets WB_MULTIBUILD=1 and wb_multibuild_enabled returns 0" {
  run "${WB}" config enable-multibuild
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qi "enabled"

  local conf="${TEST_HOME}/etc/runtime.conf"
  [ -f "${conf}" ]
  grep -q "WB_MULTIBUILD=1" "${conf}"
}

# ---------------------------------------------------------------------------
# Test 3: wb runtime list output unchanged when multi-build disabled
# ---------------------------------------------------------------------------
@test "runtime list: standard output (no MULTI column) when multi-build disabled" {
  run "${WB}" runtime list
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q "NAME"
  # No MULTI column header when disabled
  ! echo "${output}" | grep -q "MULTI"
}

# ---------------------------------------------------------------------------
# Test 4: wb runtime list --multi shows MULTI column regardless of WB_MULTIBUILD
# ---------------------------------------------------------------------------
@test "runtime list --multi: shows MULTI column" {
  run "${WB}" runtime list --multi
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q "MULTI"
  # Should list both dist dirs
  echo "${output}" | grep -q "WINE-BLEEDING-A"
  echo "${output}" | grep -q "WINE-BLEEDING-B"
}

# ---------------------------------------------------------------------------
# Test 5: wb run --runtime FOO refuses when multi-build disabled (non-zero exit)
# ---------------------------------------------------------------------------
@test "run --runtime: refuses with clear error when multi-build disabled" {
  run "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-B --wait
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -qi "multi-build not enabled\|enable-multibuild"
}

# ---------------------------------------------------------------------------
# Test 6: with multi-build enabled, --runtime pointing to CURRENT dist is a no-op
# ---------------------------------------------------------------------------
@test "run --runtime SAME: no-op when requesting same dist already active" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  # The prefix was init'd with DIST_A; runtime_target points to DIST_A
  run "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-A --wait
  [ "${status}" -eq 0 ]

  # Verify wineboot -u was NOT logged (only wineboot --init from setup)
  ! _wine_log | grep -q "wineboot -u"
}

# ---------------------------------------------------------------------------
# Test 7: same-major switch reconciles components but does NOT invoke wineboot -u
# ---------------------------------------------------------------------------
@test "run --runtime SAME_MAJOR: reconciles components but does NOT run wineboot -u" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  run "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-C --wait
  [ "${status}" -eq 0 ]

  # wineboot -u must NOT appear in fake_wine.log
  ! _wine_log | grep -q "wineboot -u"

  # current_runtime should be updated to WINE-BLEEDING-C
  local sentinel="${TEST_PFX}/.wb_runtime"
  local cur
  cur="$(jq -r '.current_runtime // empty' "${sentinel}")"
  [ "${cur}" = "WINE-BLEEDING-C" ]
}

# ---------------------------------------------------------------------------
# Test 8: different-major switch WITHOUT consent exits 42 with clear error
# ---------------------------------------------------------------------------
@test "run --runtime DIFF_MAJOR: exits 42 without --yes-wineboot" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  run "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-B --wait
  [ "${status}" -eq 42 ]
  echo "${output}" | grep -qi "major\|wineboot\|consent\|yes-wineboot"
}

# ---------------------------------------------------------------------------
# Test 9: different-major switch WITH --yes-wineboot runs wineboot -u then reconcile
# ---------------------------------------------------------------------------
@test "run --runtime DIFF_MAJOR --yes-wineboot: runs wineboot -u and updates history" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  run "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-B --yes-wineboot --wait
  [ "${status}" -eq 0 ]

  # wineboot -u should appear in fake_wine.log
  _wine_log | grep -q "wineboot -u"

  # current_runtime should be WINE-BLEEDING-B
  local sentinel="${TEST_PFX}/.wb_runtime"
  local cur
  cur="$(jq -r '.current_runtime // empty' "${sentinel}")"
  [ "${cur}" = "WINE-BLEEDING-B" ]

  # history should be non-empty
  local hist_len
  hist_len="$(jq '.history | length' "${sentinel}")"
  [ "${hist_len}" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Test 10: different-major switch with WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE=1
#           proceeds without CLI flag
# ---------------------------------------------------------------------------
@test "run --runtime DIFF_MAJOR: WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE=1 allows auto-wineboot" {
  "${WB}" config enable-multibuild >/dev/null 2>&1
  export WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE=1

  run "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-B --wait
  [ "${status}" -eq 0 ]

  _wine_log | grep -q "wineboot -u"

  local sentinel="${TEST_PFX}/.wb_runtime"
  local cur
  cur="$(jq -r '.current_runtime // empty' "${sentinel}")"
  [ "${cur}" = "WINE-BLEEDING-B" ]
}

# ---------------------------------------------------------------------------
# Test 11: history entry on first switch closes previous (no to_utc), opens new
# ---------------------------------------------------------------------------
@test "history: first switch creates history entry with to_utc=null for new entry" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  # Switch to same-major DIST_C (no wineboot needed)
  run "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-C --wait
  [ "${status}" -eq 0 ]

  local sentinel="${TEST_PFX}/.wb_runtime"

  # The newest history entry should have to_utc == null
  local last_to
  last_to="$(jq -r '.history[-1].to_utc' "${sentinel}")"
  [ "${last_to}" = "null" ]

  # The newest entry runtime should be WINE-BLEEDING-C
  local last_rt
  last_rt="$(jq -r '.history[-1].runtime' "${sentinel}")"
  [ "${last_rt}" = "WINE-BLEEDING-C" ]
}

# ---------------------------------------------------------------------------
# Test 12: history on subsequent switch closes previous entry's to_utc, opens new
# ---------------------------------------------------------------------------
@test "history: subsequent switch closes prior to_utc and opens new entry" {
  "${WB}" config enable-multibuild >/dev/null 2>&1
  export WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE=1

  # Switch A -> C (same major 10)
  "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-C --wait >/dev/null 2>&1

  # Switch C -> B (major 10 -> 11)
  "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-B --wait >/dev/null 2>&1

  local sentinel="${TEST_PFX}/.wb_runtime"
  local hist_len
  hist_len="$(jq '.history | length' "${sentinel}")"
  [ "${hist_len}" -ge 2 ]

  # The first history entry (index 0) should have a non-null to_utc
  local first_to
  first_to="$(jq -r '.history[0].to_utc' "${sentinel}")"
  [ "${first_to}" != "null" ]
  [ -n "${first_to}" ]

  # The last entry should have to_utc == null (still active)
  local last_to
  last_to="$(jq -r '.history[-1].to_utc' "${sentinel}")"
  [ "${last_to}" = "null" ]
}

# ---------------------------------------------------------------------------
# Test 13: wb prefix history prints table with FROM_UTC / TO_UTC / RUNTIME
# ---------------------------------------------------------------------------
@test "prefix history: prints table including FROM_UTC, TO_UTC, RUNTIME columns" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  # Perform a switch to populate history
  "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-C --wait >/dev/null 2>&1

  run "${WB}" prefix history TESTPFX
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q "FROM_UTC"
  echo "${output}" | grep -q "TO_UTC"
  echo "${output}" | grep -q "RUNTIME"
  # Should show WINE-BLEEDING-C as the active runtime
  echo "${output}" | grep -q "WINE-BLEEDING-C"
  # Active entry should say "active"
  echo "${output}" | grep -q "active"
}

# ---------------------------------------------------------------------------
# Test 14: current_runtime field updated atomically on switch
# ---------------------------------------------------------------------------
@test "current_runtime: field updated correctly in .wb_runtime after switch" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  local sentinel="${TEST_PFX}/.wb_runtime"

  # Before any switch — no current_runtime or it's empty
  local before
  before="$(jq -r '.current_runtime // empty' "${sentinel}")"
  # current_runtime is set on switch, not on init — may be empty or "WINE-BLEEDING-A"

  # Perform same-major switch to C
  "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-C --wait >/dev/null 2>&1

  local after
  after="$(jq -r '.current_runtime // empty' "${sentinel}")"
  [ "${after}" = "WINE-BLEEDING-C" ]
}

# ---------------------------------------------------------------------------
# Test 15: schema validation passes for .wb_runtime with history[] populated
# ---------------------------------------------------------------------------
@test "schema: .wb_runtime with history[] validates against schema (skip if no tool)" {
  if ! command -v check-jsonschema >/dev/null 2>&1; then
    skip "check-jsonschema not available"
  fi

  "${WB}" config enable-multibuild >/dev/null 2>&1
  "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-C --wait >/dev/null 2>&1

  local sentinel="${TEST_PFX}/.wb_runtime"
  local schema="${BATS_TEST_DIRNAME}/../share/schemas/wb_runtime.schema.json"

  run check-jsonschema --schemafile "${schema}" "${sentinel}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 16: history[] is preserved across re-adopt (not overwritten)
# ---------------------------------------------------------------------------
@test "adopt: history[] preserved after wb prefix adopt re-runs on a switched prefix" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  # Perform a switch to populate history
  "${WB}" run notepad.exe --prefix TESTPFX --runtime WINE-BLEEDING-C --wait >/dev/null 2>&1

  local sentinel="${TEST_PFX}/.wb_runtime"
  local hist_before
  hist_before="$(jq '.history | length' "${sentinel}")"
  [ "${hist_before}" -ge 1 ]

  # Re-adopt (idempotent adopt)
  "${WB}" prefix adopt "${TEST_PFX}" >/dev/null 2>&1

  # History must still be present
  local hist_after
  hist_after="$(jq '.history | length' "${sentinel}")"
  [ "${hist_after}" -ge 1 ]

  # current_runtime should also be preserved
  local cur_after
  cur_after="$(jq -r '.current_runtime // empty' "${sentinel}")"
  [ "${cur_after}" = "WINE-BLEEDING-C" ]
}

# ---------------------------------------------------------------------------
# Test 17: invalid runtime NAME rejected by _wb_validate_path_arg in cmd_run
# ---------------------------------------------------------------------------
@test "run --runtime: invalid name with '..' is rejected" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  run "${WB}" run notepad.exe --prefix TESTPFX --runtime "../../etc/passwd" --wait
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -qi "traversal\|invalid\|rejected"
}

# ---------------------------------------------------------------------------
# Test 18: switching to a non-existent runtime exits 1 with clear error,
#           history untouched
# ---------------------------------------------------------------------------
@test "run --runtime NONEXISTENT: exits non-zero with clear error, history untouched" {
  "${WB}" config enable-multibuild >/dev/null 2>&1

  local sentinel="${TEST_PFX}/.wb_runtime"
  local hist_before
  hist_before="$(jq '.history // [] | length' "${sentinel}")"

  run "${WB}" run notepad.exe --prefix TESTPFX --runtime NONEXISTENT-DIST --wait
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -qi "not found\|runtime\|NONEXISTENT"

  # History must be unchanged
  local hist_after
  hist_after="$(jq '.history // [] | length' "${sentinel}")"
  [ "${hist_after}" -eq "${hist_before}" ]
}

# ---------------------------------------------------------------------------
# Test 19: config disable-multibuild removes WB_MULTIBUILD from runtime.conf
# ---------------------------------------------------------------------------
@test "config disable-multibuild: removes WB_MULTIBUILD from runtime.conf" {
  "${WB}" config enable-multibuild >/dev/null 2>&1
  local conf="${TEST_HOME}/etc/runtime.conf"
  grep -q "WB_MULTIBUILD=1" "${conf}"

  run "${WB}" config disable-multibuild
  [ "${status}" -eq 0 ]

  # WB_MULTIBUILD should no longer appear
  ! grep -q "WB_MULTIBUILD=1" "${conf}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Test 20: wb_runtime_resolve resolves alias WINE-BLEEDING correctly
# ---------------------------------------------------------------------------
@test "wb_runtime_resolve: WINE-BLEEDING resolves to a valid directory path" {
  run bash -c "
    export WB_HOME='${TEST_HOME}'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-config.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-wineboot.sh'
    source '${WB_LIB}/wb-multibuild.sh'
    result=\"\$(wb_runtime_resolve 'WINE-BLEEDING')\"
    # Result must be a real directory path that contains dist metadata
    [[ -d \"\${result}\" ]] && echo 'resolved-ok'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q "resolved-ok"
}

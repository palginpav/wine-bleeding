#!/usr/bin/env bats

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures/ppdb"

# Load wb-ppdb.sh and its dependencies in every subshell via a helper.
_ppdb_env() {
  bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    $*
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
}

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# 1. Happy path: valid .wb.ppdb emits env vars
# ---------------------------------------------------------------------------
@test "wb_ppdb_read valid.wb.ppdb exits 0 and emits WB_DXVK=1" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_read '${FIXTURES}/valid.wb.ppdb'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"WB_DXVK=1"* ]]
}

# ---------------------------------------------------------------------------
# 2. Missing file → exit 1
# ---------------------------------------------------------------------------
@test "wb_ppdb_read missing file exits 1" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_read '${TEST_HOME}/nonexistent.wb.ppdb'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# 3. Malformed JSON → exit 2
# ---------------------------------------------------------------------------
@test "wb_ppdb_read malformed.wb.ppdb exits 2" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_read '${FIXTURES}/malformed.wb.ppdb'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# 4. Schema violation → exit 3 (requires check-jsonschema; skip if absent)
# ---------------------------------------------------------------------------
@test "wb_ppdb_read schema-bad.wb.ppdb exits 3 when check-jsonschema present" {
  if ! command -v check-jsonschema >/dev/null 2>&1; then
    skip "check-jsonschema not on PATH"
  fi
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_read '${FIXTURES}/schema-bad.wb.ppdb'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 3 ]]
}

# ---------------------------------------------------------------------------
# 5. Env values containing special JSON chars are emitted correctly
# ---------------------------------------------------------------------------
@test "wb_ppdb_read handles env values with special chars (quote, backslash)" {
  # Build a ppdb with a value that contains a double-quote and backslash
  local special_ppdb="${TEST_HOME}/special.wb.ppdb"
  # jq is used to write the JSON so the value is correctly escaped
  jq -n '{
    schema: 1,
    runtime: "WINE-BLEEDING",
    env: {
      "WB_SPECIAL": "val\"with\\backslash"
    }
  }' > "${special_ppdb}"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_read '${special_ppdb}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  # Value must survive the round-trip exactly
  [[ "${output}" == *'WB_SPECIAL=val"with\backslash'* ]]
}

# ---------------------------------------------------------------------------
# 6. Empty env → exit 0, no KEY=VALUE output
# ---------------------------------------------------------------------------
@test "wb_ppdb_read with empty env exits 0 and emits no KEY=VALUE lines" {
  local empty_ppdb="${TEST_HOME}/empty-env.wb.ppdb"
  jq -n '{ schema: 1, runtime: "WINE-BLEEDING", env: {} }' > "${empty_ppdb}"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_read '${empty_ppdb}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

# ---------------------------------------------------------------------------
# 7. Legacy benign import produces valid JSON with correct field mapping
# ---------------------------------------------------------------------------
@test "wb_ppdb_import_legacy benign.ppdb produces correct JSON" {
  local out_json="${TEST_HOME}/benign-out.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${FIXTURES}/legacy-benign.ppdb' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_json}" ]]
  # Must be valid JSON
  jq empty "${out_json}"
  # PW_WINE_USE=PROTON_LG → .runtime
  [[ "$(jq -r '.runtime' "${out_json}")" == "PROTON_LG" ]]
  # WINEDEBUG=-all → .env.WINEDEBUG
  [[ "$(jq -r '.env.WINEDEBUG' "${out_json}")" == "-all" ]]
  # DXVK_HUD=fps → .env.DXVK_HUD
  [[ "$(jq -r '.env.DXVK_HUD' "${out_json}")" == "fps" ]]
}

# ---------------------------------------------------------------------------
# 8. SECURITY: malicious ppdb — rm/curl/cat commands must NOT execute
# ---------------------------------------------------------------------------
@test "SECURITY: wb_ppdb_import_legacy malicious.ppdb does not execute rm/curl/cat" {
  local out_json="${TEST_HOME}/malicious-out.json"

  # Pre-create canary files that must survive
  local home_canary="${TEST_HOME}/WB_CANARY_HOME_$$"
  touch "${home_canary}"

  # The stolen target in the malicious fixture uses /tmp/WB_M4_STOLEN_$$
  # We compute the $$ that would be active in the child shell.
  # Since $$ in the fixture is a literal string (the fixture file itself uses
  # $$ which expands at child-shell source time), we cannot predict that PID.
  # Instead we verify that NO /tmp/WB_M4_STOLEN_* file was created.
  local stolen_pattern="/tmp/WB_M4_STOLEN_*"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${FIXTURES}/legacy-malicious.ppdb' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null

  # The import must succeed (or at worst produce best-effort output)
  # Home canary must still exist
  [[ -f "${home_canary}" ]] || {
    echo "FAIL: HOME canary was deleted by malicious ppdb!" >&2
    return 1
  }

  # No stolen file must have been created in /tmp
  local stolen_files
  stolen_files="$(ls /tmp/WB_M4_STOLEN_* 2>/dev/null | wc -l || true)"
  [[ "${stolen_files}" -eq 0 ]] || {
    echo "FAIL: stolen file(s) were created: $(ls /tmp/WB_M4_STOLEN_* 2>/dev/null)" >&2
    rm -f /tmp/WB_M4_STOLEN_* 2>/dev/null || true
    return 1
  }

  # The legit PW_WINE_USE=WINE-BLEEDING at end of the malicious fixture must extract
  [[ -f "${out_json}" ]]
  [[ "$(jq -r '.runtime' "${out_json}")" == "WINE-BLEEDING" ]]
}

# ---------------------------------------------------------------------------
# 9. SECURITY: sandbox PATH must not contain rm, cp, curl
# ---------------------------------------------------------------------------
@test "SECURITY: sandbox PATH has no rm, cp, or curl" {
  # Build the same sandbox the library uses and capture stderr to verify
  # each dangerous tool produces "command not found" (or similar rejection).
  local sandbox_dir sandbox_bin sandbox_stderr
  sandbox_dir="$(mktemp -d)"
  sandbox_bin="${sandbox_dir}/bin"
  mkdir -p "${sandbox_bin}"

  cp "${FIXTURES}/legacy-malicious.ppdb" "${sandbox_bin}/input.ppdb"

  # Wrapper without any redirects (bash --restricted blocks > inside scripts)
  printf 'source input.ppdb || true\n' > "${sandbox_bin}/run.sh"

  for cmd in echo true false grep; do
    local cmd_path
    cmd_path="$(command -v "${cmd}" 2>/dev/null || true)"
    [[ -n "${cmd_path}" && -x "${cmd_path}" ]] && ln -sf "${cmd_path}" "${sandbox_bin}/${cmd}"
  done

  sandbox_stderr="$(
    (
      cd "${sandbox_bin}"
      exec env -i \
        HOME="${sandbox_bin}" \
        PATH="${sandbox_bin}" \
        TMPDIR="${sandbox_bin}" \
        /bin/bash --restricted --noprofile --norc run.sh
    ) 2>&1 || true
  )"
  rm -rf "${sandbox_dir}"

  # rm and curl must appear as "not found" (absent from sandbox PATH)
  echo "${sandbox_stderr}" | grep -qiE "rm.*not found|not found.*rm|rm: command not found"
  echo "${sandbox_stderr}" | grep -qiE "curl.*not found|not found.*curl|curl: command not found"

  # 'cat /etc/passwd > /tmp/...' — bash --restricted blocks the output redirect BEFORE
  # attempting to run cat, so we see "restricted: cannot redirect output" instead of
  # "cat: command not found".  Either message proves the attack was neutralized.
  echo "${sandbox_stderr}" | grep -qiE \
    "cat.*not found|not found.*cat|cat: command not found|restricted.*cannot redirect|cannot redirect.*output"
}

# ---------------------------------------------------------------------------
# 10. PW_* vars map to WB_PP_* in env
# ---------------------------------------------------------------------------
@test "wb_ppdb_import_legacy maps PW_USE_TERMINAL=1 to WB_PP_USE_TERMINAL=1" {
  local legacy="${TEST_HOME}/pw-map-test.ppdb"
  printf 'PW_USE_TERMINAL=1\nPW_WINE_USE=WINE-BLEEDING\n' > "${legacy}"
  local out_json="${TEST_HOME}/pw-map-out.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${legacy}' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ "$(jq -r '.env.WB_PP_USE_TERMINAL' "${out_json}")" == "1" ]]
}

# ---------------------------------------------------------------------------
# 11. WINE* vars pass through verbatim
# ---------------------------------------------------------------------------
@test "wb_ppdb_import_legacy passes WINEARCH=win32 through verbatim" {
  local legacy="${TEST_HOME}/wine-passthru.ppdb"
  printf 'WINEARCH=win32\nPW_WINE_USE=WINE-BLEEDING\n' > "${legacy}"
  local out_json="${TEST_HOME}/wine-passthru-out.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${legacy}' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ "$(jq -r '.env.WINEARCH' "${out_json}")" == "win32" ]]
}

# ---------------------------------------------------------------------------
# 12. DXVK_* vars pass through verbatim
# ---------------------------------------------------------------------------
@test "wb_ppdb_import_legacy passes DXVK_ASYNC=1 through verbatim" {
  local legacy="${TEST_HOME}/dxvk-passthru.ppdb"
  printf 'DXVK_ASYNC=1\nPW_WINE_USE=WINE-BLEEDING\n' > "${legacy}"
  local out_json="${TEST_HOME}/dxvk-passthru-out.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${legacy}' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ "$(jq -r '.env.DXVK_ASYNC' "${out_json}")" == "1" ]]
}

# ---------------------------------------------------------------------------
# 13. Non-allowlisted vars are NOT present in output
# ---------------------------------------------------------------------------
@test "wb_ppdb_import_legacy drops non-allowlisted vars (MALICIOUS, HOSTILE)" {
  local legacy="${TEST_HOME}/hostile-vars.ppdb"
  printf 'MALICIOUS=1\nHOSTILE=ok\nPW_WINE_USE=WINE-BLEEDING\n' > "${legacy}"
  local out_json="${TEST_HOME}/hostile-vars-out.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${legacy}' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  # Keys must not exist (jq returns 'null' for absent keys)
  [[ "$(jq -r '.env.MALICIOUS // "null"' "${out_json}")" == "null" ]]
  [[ "$(jq -r '.env.HOSTILE // "null"' "${out_json}")" == "null" ]]
}

# ---------------------------------------------------------------------------
# 14. Output JSON validates against wb_ppdb.schema.json (skip if tool absent)
# ---------------------------------------------------------------------------
@test "wb_ppdb_import_legacy output validates against schema" {
  if ! command -v check-jsonschema >/dev/null 2>&1; then
    skip "check-jsonschema not on PATH"
  fi
  local schema="${BATS_TEST_DIRNAME}/../share/schemas/wb_ppdb.schema.json"
  local out_json="${TEST_HOME}/schema-valid-out.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${FIXTURES}/legacy-benign.ppdb' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]

  run check-jsonschema --schemafile "${schema}" "${out_json}" 2>/dev/null
  [[ "${status}" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# 15. Empty legacy ppdb (zero KEY=VALUE pairs) → minimal required fields
#     Convention: runtime defaults to "" (empty string) when PW_WINE_USE absent.
#     Callers must handle empty runtime and prompt the user.
# ---------------------------------------------------------------------------
@test "wb_ppdb_import_legacy empty ppdb produces schema=1 and empty runtime" {
  local empty_legacy="${TEST_HOME}/empty-legacy.ppdb"
  touch "${empty_legacy}"
  local out_json="${TEST_HOME}/empty-legacy-out.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${empty_legacy}' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_json}" ]]
  jq empty "${out_json}"
  [[ "$(jq -r '.schema' "${out_json}")" == "1" ]]
  # runtime is empty string when PW_WINE_USE not found (documented convention)
  [[ "$(jq -r '.runtime' "${out_json}")" == "" ]]
}

# ---------------------------------------------------------------------------
# 16. SECURITY: legit PW_WINE_USE still extracted from malicious ppdb
# (explicit check separate from test 8)
# ---------------------------------------------------------------------------
@test "SECURITY: wb_ppdb_import_legacy still extracts PW_WINE_USE from malicious ppdb" {
  local out_json="${TEST_HOME}/mal-runtime-check.json"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-ppdb.sh'
    wb_ppdb_import_legacy '${FIXTURES}/legacy-malicious.ppdb' '${out_json}'
  " WB_LOG_FILE="${TEST_HOME}/wb.log" 2>/dev/null

  [[ -f "${out_json}" ]]
  [[ "$(jq -r '.runtime' "${out_json}")" == "WINE-BLEEDING" ]]
}

#!/usr/bin/env bats

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
}

teardown() {
  rm -rf "${TEST_DIR}"
}

_source_json() {
  source "${WB_LIB}/wb-json.sh"
}

# 1. wb_json_read returns value for existing key
@test "json_read: returns value for existing top-level key" {
  local f="${TEST_DIR}/test.json"
  echo '{"foo":"bar"}' > "${f}"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    wb_json_read '${f}' '.foo'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "bar" ]
}

# 2. Returns empty + exit 0 for missing key
@test "json_read: returns empty and exit 0 for missing key" {
  local f="${TEST_DIR}/test.json"
  echo '{"foo":"bar"}' > "${f}"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    wb_json_read '${f}' '.nonexistent'
  "
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

# 3. Returns non-zero for malformed JSON
@test "json_read: returns non-zero for malformed JSON" {
  local f="${TEST_DIR}/bad.json"
  echo 'not valid json {{' > "${f}"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    wb_json_read '${f}' '.foo'
  " 2>/dev/null
  [ "${status}" -ne 0 ]
}

# 4. wb_json_write_atomic creates file correctly
@test "json_write_atomic: creates file with correct content" {
  local f="${TEST_DIR}/out.json"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    wb_json_write_atomic '${f}' '{\"key\":\"value\"}'
    cat '${f}'
  "
  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '.key == "value"'
}

# 5. Atomic write: after SIGTERM mid-write, file is either old or new, never partial
@test "json_write_atomic: file is never partial under SIGTERM simulation" {
  local f="${TEST_DIR}/atomic.json"
  echo '{"original":"content"}' > "${f}"
  # Run write in background and immediately kill; file should be old content (write never completed)
  # or new content if it completed before kill — never partial
  bash -c "
    source '${WB_LIB}/wb-json.sh'
    trap 'exit 1' TERM
    wb_json_write_atomic '${f}' '{\"new\":\"content\"}'
  " &
  local wpid=$!
  kill -TERM "${wpid}" 2>/dev/null || true
  wait "${wpid}" 2>/dev/null || true
  # File must be valid JSON (either old or new)
  run jq empty "${f}"
  [ "${status}" -eq 0 ]
}

# 6. Nested key read (.a.b.c)
@test "json_read: reads nested key .a.b.c" {
  local f="${TEST_DIR}/nested.json"
  echo '{"a":{"b":{"c":"deep"}}}' > "${f}"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    wb_json_read '${f}' '.a.b.c'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "deep" ]
}

# 7. Write empty JSON object
@test "json_write_atomic: writes empty JSON object" {
  local f="${TEST_DIR}/empty.json"
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    wb_json_write_atomic '${f}' '{}'
    cat '${f}'
  "
  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '. == {}'
}

# 8. Large JSON round-trip (1MB generated)
@test "json_write_atomic + json_read: round-trip large JSON" {
  local f="${TEST_DIR}/large.json"
  local json_file="${TEST_DIR}/large_src.json"
  # Generate a ~1MB JSON object with many keys, write to a temp file to avoid ARG_MAX
  python3 -c "
import json, sys
d = {'key_%d' % i: 'value_%d' % i for i in range(10000)}
sys.stdout.write(json.dumps(d))
" > "${json_file}"
  # Use the file as input rather than a shell argument
  bash -c "
    source '${WB_LIB}/wb-json.sh'
    json=\"\$(cat '${json_file}')\"
    wb_json_write_atomic '${f}' \"\${json}\"
  "
  run bash -c "
    source '${WB_LIB}/wb-json.sh'
    wb_json_read '${f}' '.key_9999'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "value_9999" ]
}

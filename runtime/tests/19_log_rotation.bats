#!/usr/bin/env bats

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/log/wb.log"
  mkdir -p "${TEST_HOME}/log"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# Helper: source log lib and emit one INFO line
_emit_log_line() {
  bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_LOG_FILE='${WB_LOG_FILE}'
    export WB_LOG_MAX_BYTES='${WB_LOG_MAX_BYTES:-10485760}'
    source '${WB_LIB}/wb-log.sh'
    wb_log_info '$1'
  " 2>/dev/null
}

# Helper: source log lib, set max bytes, emit one line
_emit_with_max() {
  local max_bytes="$1"
  local msg="$2"
  bash -c "
    export WB_HOME='${TEST_HOME}'
    export WB_LOG_FILE='${WB_LOG_FILE}'
    export WB_LOG_MAX_BYTES='${max_bytes}'
    source '${WB_LIB}/wb-log.sh'
    wb_log_info '${msg}'
  " 2>/dev/null
}

# ---------------------------------------------------------------------------
# Test 1: Writing just below threshold does NOT rotate
# ---------------------------------------------------------------------------
@test "log rotation: writing below threshold does not rotate" {
  # Write a 50-byte log line; set threshold to 10000 bytes
  _emit_with_max 10000 "short line"
  # wb.log.1 must NOT exist
  [ ! -f "${WB_LOG_FILE}.1" ]
  [ -f "${WB_LOG_FILE}" ]
}

# ---------------------------------------------------------------------------
# Test 2: Writing a line that crosses threshold rotates the log
# ---------------------------------------------------------------------------
@test "log rotation: crossing threshold rotates log — wb.log.1 exists, wb.log is fresh" {
  # Pre-fill wb.log to AT the threshold (100 bytes) — the check sees size >= 100
  python3 -c "
import os
log_path = '${WB_LOG_FILE}'
os.makedirs(os.path.dirname(log_path), exist_ok=True)
with open(log_path, 'wb') as f:
    f.write(b'x' * 100)
"
  # Set threshold to 100 bytes; pre-check sees 100 >= 100 → rotates before writing
  _emit_with_max 100 "trigger rotation"
  # wb.log.1 should now exist (contains the 100 x's)
  [ -f "${WB_LOG_FILE}.1" ]
  # wb.log should contain only the new JSON line — much smaller than 100 bytes of x's
  local new_size
  new_size="$(stat -c %s "${WB_LOG_FILE}")"
  [ "${new_size}" -lt 100 ]
}

# ---------------------------------------------------------------------------
# Test 3: Rotating 6 times leaves wb.log.5 but no wb.log.6
# ---------------------------------------------------------------------------
@test "log rotation: 6 rotations — wb.log.5 exists, wb.log.6 does NOT" {
  local i
  for i in $(seq 1 6); do
    # Pad wb.log to at least threshold bytes so the next write triggers rotation
    python3 -c "
import os
log_path = '${WB_LOG_FILE}'
os.makedirs(os.path.dirname(log_path), exist_ok=True)
with open(log_path, 'ab') as f:
    current = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    if current < 100:
        f.write(b'x' * (100 - current))
"
    _emit_with_max 100 "rotation ${i}"
  done

  [ -f "${WB_LOG_FILE}.5" ]
  [ ! -f "${WB_LOG_FILE}.6" ]
}

# ---------------------------------------------------------------------------
# Test 4: Concurrent writers during rotation don't lose lines
# ---------------------------------------------------------------------------
@test "log rotation: concurrent writers do not corrupt log — all lines are valid JSON" {
  local n=5
  # High threshold so rotation happens at most once: each line is ~80 bytes,
  # 15 lines = ~1200 bytes, threshold = 2000 → at most 1 rotation possible.
  local threshold=2000

  # Launch 3 background writers, each writing n lines sequentially
  local pids=()
  local i
  for i in 1 2 3; do
    (
      local j
      for j in $(seq 1 "${n}"); do
        bash -c "
          export WB_HOME='${TEST_HOME}'
          export WB_LOG_FILE='${WB_LOG_FILE}'
          export WB_LOG_MAX_BYTES='${threshold}'
          source '${WB_LIB}/wb-log.sh'
          wb_log_info 'writer${i}-line${j}'
        " 2>/dev/null
      done
    ) &
    pids+=($!)
  done

  # Wait for all writers to finish
  for pid in "${pids[@]}"; do
    wait "${pid}" || true
  done

  # Count total JSON lines across all log files (at most 2 generations at this threshold)
  local total=0
  local logf
  for logf in "${WB_LOG_FILE}" "${WB_LOG_FILE}".{1,2,3,4,5}; do
    if [[ -f "${logf}" ]]; then
      local count
      count="$(grep -c '"level"' "${logf}" 2>/dev/null || echo 0)"
      (( total += count )) || true
      # Verify each line is valid JSON (no corruption from concurrent writes)
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        echo "${line}" | jq empty 2>/dev/null || {
          echo "Corrupt JSON line found in ${logf}: ${line}" >&2
          return 1
        }
      done < "${logf}"
    fi
  done

  # All 3*n lines must be present (threshold high enough that rotation ≤ 1 time)
  local expected=$(( 3 * n ))
  [ "${total}" -eq "${expected}" ]
}

# ---------------------------------------------------------------------------
# Test 5: Custom WB_LOG_MAX_BYTES via env var is respected
# ---------------------------------------------------------------------------
@test "log rotation: custom WB_LOG_MAX_BYTES env var is respected" {
  # Pre-fill to at least the custom threshold (10 bytes) so rotation fires
  python3 -c "
import os
log_path = '${WB_LOG_FILE}'
os.makedirs(os.path.dirname(log_path), exist_ok=True)
with open(log_path, 'wb') as f:
    f.write(b'x' * 10)
"
  # Threshold is 10 bytes; current file is 10 bytes >= 10 → rotates before write
  _emit_with_max 10 "custom threshold test"
  [ -f "${WB_LOG_FILE}.1" ]
}

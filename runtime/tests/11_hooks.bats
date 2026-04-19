#!/usr/bin/env bats
# Tests for wb-hooks.sh: wb_hooks_run() function

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
  export HOOKS_DIR="${TEST_HOME}/plugins/hooks.d"
  mkdir -p "${HOOKS_DIR}"
  unset WB_DEBUG 2>/dev/null || true
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# Source libs in a subshell helper
_run_hooks() {
  local phase="$1"
  (
    source "${WB_LIB}/wb-log.sh"
    source "${WB_LIB}/wb-json.sh"
    source "${WB_LIB}/wb-hooks.sh"
    wb_hooks_run "${phase}"
  )
}

# Create a hook file in the hooks dir
_make_hook() {
  local name="$1"
  local content="$2"
  printf '%s\n' "${content}" > "${HOOKS_DIR}/${name}"
  chmod +x "${HOOKS_DIR}/${name}"
}

# 1. No hooks dir → returns 0 silently
@test "hooks: empty hooks dir returns 0" {
  rmdir "${HOOKS_DIR}"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
}

# 2. No hooks in dir → returns 0
@test "hooks: hooks dir with no matching files returns 0" {
  _make_hook "README.txt" "# not a hook"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
}

# 3. One hook: exports var visible to the caller (tested via subshell side-effect via file)
@test "hooks: hook that writes a file is executed" {
  local sentinel="${TEST_HOME}/hook_ran"
  _make_hook "10-demo.pre-exec.sh" "touch '${sentinel}'"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
  [ -f "${sentinel}" ]
}

# 4. Sort order: 10-early runs before 50-late
@test "hooks: hooks run in sorted order (10- before 50-)" {
  local order_file="${TEST_HOME}/order"
  _make_hook "50-late.pre-exec.sh" "echo late >> '${order_file}'"
  _make_hook "10-early.pre-exec.sh" "echo early >> '${order_file}'"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
  [ -f "${order_file}" ]
  local first second
  first="$(sed -n '1p' "${order_file}")"
  second="$(sed -n '2p' "${order_file}")"
  [ "${first}" = "early" ]
  [ "${second}" = "late" ]
}

# 5. Failing hook: chain aborts before later hooks run
@test "hooks: failing hook aborts the chain" {
  local sentinel="${TEST_HOME}/should_not_exist"
  _make_hook "10-fail.pre-exec.sh" "exit 1"
  _make_hook "50-late.pre-exec.sh" "touch '${sentinel}'"
  run _run_hooks "pre-exec"
  [ "${status}" -ne 0 ]
  [ ! -f "${sentinel}" ]
}

# 6. .example suffix files are skipped
@test "hooks: .example suffix is skipped" {
  local sentinel="${TEST_HOME}/example_ran"
  _make_hook "00-example.pre-exec.sh.example" "touch '${sentinel}'"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
  [ ! -f "${sentinel}" ]
}

# 7. Invalid filename pattern (no phase infix) is skipped
@test "hooks: hook.sh with no phase infix is skipped" {
  local sentinel="${TEST_HOME}/invalid_ran"
  _make_hook "hook.sh" "touch '${sentinel}'"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
  [ ! -f "${sentinel}" ]
}

# 8. Hook symlink pointing OUTSIDE WB_HOME is SKIPPED with WARN
@test "hooks: symlink outside hooks.d is skipped with WARN" {
  local outside_script="${TEST_HOME}/outside.sh"
  local sentinel="${TEST_HOME}/outside_ran"
  printf '#!/usr/bin/env bash\ntouch "%s"\n' "${sentinel}" > "${outside_script}"
  chmod +x "${outside_script}"
  ln -s "${outside_script}" "${HOOKS_DIR}/10-escaped.pre-exec.sh"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
  [ ! -f "${sentinel}" ]
  # Should have logged a WARN
  grep -q "WARN" "${WB_LOG_FILE}" || grep -q "skipping symlink" "${WB_LOG_FILE}"
}

# 9. Cross-phase var export: pre-reconcile hook exports var, subsequent phase can read it
@test "hooks: var exported in pre-reconcile is visible to pre-exec phase hooks" {
  local result_file="${TEST_HOME}/cross_phase_result"
  # pre-reconcile: export a var
  _make_hook "10-export.pre-reconcile.sh" "export WB_CROSS_PHASE_TEST=hello123"
  # pre-exec: read it
  _make_hook "10-read.pre-exec.sh" "echo \"\${WB_CROSS_PHASE_TEST:-MISSING}\" > '${result_file}'"
  # Run both phases in the SAME subshell to simulate the wb run call graph
  (
    source "${WB_LIB}/wb-log.sh"
    source "${WB_LIB}/wb-json.sh"
    source "${WB_LIB}/wb-hooks.sh"
    wb_hooks_run "pre-reconcile"
    wb_hooks_run "pre-exec"
  )
  [ -f "${result_file}" ]
  local val
  val="$(cat "${result_file}")"
  [ "${val}" = "hello123" ]
}

# 10. Non-regular file (a dir named weird.pre-exec.sh/) is skipped
@test "hooks: directory named like a hook is skipped" {
  local sentinel="${TEST_HOME}/dir_hook_ran"
  mkdir "${HOOKS_DIR}/weird.pre-exec.sh"
  run _run_hooks "pre-exec"
  [ "${status}" -eq 0 ]
  [ ! -f "${sentinel}" ]
}

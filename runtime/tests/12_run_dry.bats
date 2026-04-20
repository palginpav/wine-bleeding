#!/usr/bin/env bats
# End-to-end tests for wb run / wb exec using fake-wine

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
FIXTURE_WINE="${BATS_TEST_DIRNAME}/fixtures/fake-wine"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  mkdir -p "${TEST_HOME}/dist"
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-M5TEST/"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-M5TEST/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-M5TEST/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-M5TEST/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-M5TEST/bin/wineserver"
  ln -sfn WINE-BLEEDING-M5TEST "${TEST_HOME}/dist/WINE-BLEEDING"

  mkdir -p "${TEST_HOME}/prefixes"
  export TEST_DIST="${TEST_HOME}/dist/WINE-BLEEDING-M5TEST"
  export TEST_PFX="${TEST_HOME}/prefixes/TESTPFX"

  # Disable sync primitives and GPU components for clean test env
  export WB_ESYNC=0
  export WB_FSYNC=0
  export WB_NTSYNC=0
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0

  # Initialize a real prefix via wb prefix init (uses fake-wine wineboot --init)
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null 2>&1
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# Helper: read the fake_wine.log
_wine_log() {
  cat "${TEST_PFX}/.fake_wine.log" 2>/dev/null || true
}

# 1. wb run exits 0 and fake_wine.log contains exec:<exe>
@test "run: wb run notepad.exe exits 0 and logs exec:notepad.exe" {
  run "${WB}" run notepad.exe --prefix TESTPFX --wait
  [ "${status}" -eq 0 ]
  _wine_log | grep -q "exec:notepad.exe"
}

# 2. Args are forwarded to wine
@test "run: wb run notepad.exe arg1 arg2 forwards args" {
  run "${WB}" run notepad.exe --prefix TESTPFX --wait arg1 arg2
  [ "${status}" -eq 0 ]
  _wine_log | grep -q "exec:notepad.exe arg1 arg2"
}

# 3. Missing prefix → exit non-zero with clear message
@test "run: missing prefix produces non-zero exit and clear message" {
  run "${WB}" run notepad.exe --prefix NONEXISTENT --wait
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -qi "does not exist\|prefix"
}

# 4. WB_DXVK=0 → no dxgi=n in WINEDLLOVERRIDES passed to wine
@test "run: WB_DXVK=0 means dxgi=n is absent from wine env" {
  export WB_DXVK=0
  run "${WB}" run notepad.exe --prefix TESTPFX --wait
  [ "${status}" -eq 0 ]
  # The env lines in the log should not contain dxgi=n
  ! _wine_log | grep -qE 'WINEDLLOVERRIDES=.*dxgi=n'
}

# 5. Failing pre-exec hook halts launch
@test "run: failing pre-exec hook aborts with non-zero exit and error message" {
  mkdir -p "${TEST_HOME}/plugins/hooks.d"
  cat > "${TEST_HOME}/plugins/hooks.d/10-fail.pre-exec.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  run "${WB}" run notepad.exe --prefix TESTPFX --wait
  [ "${status}" -ne 0 ]
  echo "${output}" | grep -qi "pre-exec\|hook\|failed\|aborting"
}

# 6. wb run with broken prefix → exit 1
@test "run: broken prefix (absent .wb_runtime) produces non-zero exit" {
  local broken_pfx="${TEST_HOME}/prefixes/BROKEN"
  mkdir -p "${broken_pfx}"
  # No .wb_runtime → classified as broken
  run "${WB}" run notepad.exe --prefix BROKEN --wait
  [ "${status}" -ne 0 ]
}

# 7. wb exec skips reconcile (pre-reconcile hook does NOT fire)
@test "exec: pre-reconcile hook is not run by wb exec" {
  mkdir -p "${TEST_HOME}/plugins/hooks.d"
  local sentinel="${TEST_HOME}/pre_reconcile_fired"
  cat > "${TEST_HOME}/plugins/hooks.d/10-check.pre-reconcile.sh" <<EOF
#!/usr/bin/env bash
touch '${sentinel}'
EOF
  # Use TESTPFX (already initialized) so fake-wine has a writable WINEPREFIX
  export WB_PREFIX=TESTPFX
  run "${WB}" exec notepad.exe
  [ "${status}" -eq 0 ]
  [ ! -f "${sentinel}" ]
}

# 8. wb exec still execs wine (log gets exec: line)
@test "exec: wb exec notepad.exe calls wine" {
  export WB_PREFIX=TESTPFX
  run "${WB}" exec notepad.exe
  [ "${status}" -eq 0 ]
  _wine_log | grep -q "exec:notepad.exe"
}

# 9. Steady-state overhead: wb run --wait on reconciled prefix finishes in < 5s
@test "run: wb run --wait completes within 5 seconds on reconciled prefix" {
  local start end elapsed
  start="${SECONDS}"
  "${WB}" run notepad.exe --prefix TESTPFX --wait >/dev/null 2>&1
  end="${SECONDS}"
  elapsed=$(( end - start ))
  [ "${elapsed}" -lt 5 ]
}

# 10. Snapshot auto-capture: wb run creates a snapshot under state/prefix-snapshots/
@test "run: wb run --wait creates a snapshot under WB_HOME/state/prefix-snapshots/TESTPFX/" {
  "${WB}" run notepad.exe --prefix TESTPFX --wait >/dev/null 2>&1
  local snap_dir="${TEST_HOME}/state/prefix-snapshots/TESTPFX"
  [ -d "${snap_dir}" ]
  # At least one snapshot JSON file must exist
  local count
  count="$(find "${snap_dir}" -maxdepth 1 -name 'TESTPFX-*.json' | wc -l)"
  [ "${count}" -ge 1 ]
}

# 11. WB_SNAPSHOT=0 suppresses auto-capture
@test "run: WB_SNAPSHOT=0 does not create a snapshot" {
  WB_SNAPSHOT=0 "${WB}" run notepad.exe --prefix TESTPFX --wait >/dev/null 2>&1
  local snap_dir="${TEST_HOME}/state/prefix-snapshots/TESTPFX"
  # Directory must not exist or be empty
  if [ -d "${snap_dir}" ]; then
    local count
    count="$(find "${snap_dir}" -maxdepth 1 -name 'TESTPFX-*.json' | wc -l)"
    [ "${count}" -eq 0 ]
  fi
}

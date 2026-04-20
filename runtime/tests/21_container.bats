#!/usr/bin/env bats
# M11 pressure-vessel / SLR container opt-in tests

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
FIXTURE_WINE="${BATS_TEST_DIRNAME}/fixtures/fake-wine"

# ---------------------------------------------------------------------------
# Setup: isolated WB_HOME with one fake dist and initialized prefix.
# ---------------------------------------------------------------------------
setup() {
  # Defensively unset container-related env so a leak from a prior test does
  # not turn a later test into a "container always on" scenario.
  unset WB_CONTAINER WB_CONTAINER_ENTRY 2>/dev/null || true

  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  mkdir -p "${TEST_HOME}/dist"
  cp -a "${FIXTURE_DIST}/." "${TEST_HOME}/dist/WINE-BLEEDING-M11TEST/"
  cp -f "${FIXTURE_WINE}/bin/wine"       "${TEST_HOME}/dist/WINE-BLEEDING-M11TEST/bin/wine"
  cp -f "${FIXTURE_WINE}/bin/wineserver" "${TEST_HOME}/dist/WINE-BLEEDING-M11TEST/bin/wineserver"
  chmod +x \
    "${TEST_HOME}/dist/WINE-BLEEDING-M11TEST/bin/wine" \
    "${TEST_HOME}/dist/WINE-BLEEDING-M11TEST/bin/wineserver"
  ln -sfn WINE-BLEEDING-M11TEST "${TEST_HOME}/dist/WINE-BLEEDING"

  mkdir -p "${TEST_HOME}/prefixes"
  export TEST_DIST="${TEST_HOME}/dist/WINE-BLEEDING-M11TEST"
  export TEST_PFX="${TEST_HOME}/prefixes/TESTPFX"

  # Disable sync primitives and GPU components for clean test env
  export WB_ESYNC=0
  export WB_FSYNC=0
  export WB_NTSYNC=0
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0

  # Initialize a real prefix via wb prefix init
  "${WB}" prefix init TESTPFX --dist "${TEST_DIST}" >/dev/null 2>&1

  # Build a fake pressure-vessel entry-point in a temp location.
  # It logs its argv to $TEST_HOME/pv.log then shifts past -- and exec's the rest.
  PV_DIR="${TEST_HOME}/fake-slr"
  PV_ENTRY="${PV_DIR}/_v2-entry-point"
  export PV_DIR PV_ENTRY
  mkdir -p "${PV_DIR}"
  cat > "${PV_ENTRY}" <<'PVSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
PV_LOG="${WB_HOME}/pv.log"
echo "pv-invoked: $*" >> "${PV_LOG}"
# Find position of -- separator, shift past it, exec the rest
i=0
for arg in "$@"; do
  i=$(( i + 1 ))
  if [[ "${arg}" == "--" ]]; then
    break
  fi
done
shift "${i}"
exec "$@"
PVSCRIPT
  chmod +x "${PV_ENTRY}"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# Helper: read the fake_wine.log
_wine_log() {
  cat "${TEST_PFX}/.fake_wine.log" 2>/dev/null || true
}

# Helper: read the pv.log
_pv_log() {
  cat "${TEST_HOME}/pv.log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1. wb_container_enabled returns 1 by default (WB_CONTAINER unset)
# ---------------------------------------------------------------------------
@test "container: wb_container_enabled returns 1 when WB_CONTAINER is unset" {
  unset WB_CONTAINER 2>/dev/null || true
  # Source the lib and call directly
  # shellcheck source=../src/wb-lib/wb-container.sh
  run bash -c "
    source '${WB_LIB}/wb-container.sh'
    wb_container_enabled
  "
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 2. After wb config enable-container, wb_container_enabled returns 0
# ---------------------------------------------------------------------------
@test "container: wb config enable-container writes WB_CONTAINER=1; wb_container_enabled returns 0" {
  run "${WB}" config enable-container
  [ "${status}" -eq 0 ]
  local conf="${TEST_HOME}/etc/runtime.conf"
  grep -q "WB_CONTAINER=1" "${conf}"

  run bash -c "
    source '${TEST_HOME}/etc/runtime.conf'
    source '${WB_LIB}/wb-container.sh'
    wb_container_enabled
  "
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. wb_container_detect finds $WB_CONTAINER_ENTRY override
# ---------------------------------------------------------------------------
@test "container: wb_container_detect returns WB_CONTAINER_ENTRY when set and executable" {
  export WB_CONTAINER_ENTRY="${PV_ENTRY}"
  run bash -c "
    source '${WB_LIB}/wb-container.sh'
    wb_container_detect
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "${PV_ENTRY}" ]
}

# ---------------------------------------------------------------------------
# 4. wb_container_detect falls back to ~/.steam/steam/... path
# ---------------------------------------------------------------------------
@test "container: wb_container_detect finds entry-point in ~/.steam/steam path" {
  unset WB_CONTAINER_ENTRY 2>/dev/null || true
  # Simulate HOME with a fake SLR install
  local fake_home
  fake_home="$(mktemp -d)"
  local slr_dir="${fake_home}/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper"
  mkdir -p "${slr_dir}"
  local fake_entry="${slr_dir}/_v2-entry-point"
  cat > "${fake_entry}" <<'STUB'
#!/usr/bin/env bash
echo stub
STUB
  chmod +x "${fake_entry}"

  run bash -c "
    export HOME='${fake_home}'
    source '${WB_LIB}/wb-container.sh'
    wb_container_detect
  "
  rm -rf "${fake_home}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${fake_entry}" ]
}

# ---------------------------------------------------------------------------
# 5. wb_container_detect returns 1 with empty stdout when no entry-point found
# ---------------------------------------------------------------------------
@test "container: wb_container_detect returns 1 with empty stdout when not installed" {
  unset WB_CONTAINER_ENTRY 2>/dev/null || true
  # Use a HOME with no Steam at all
  local empty_home
  empty_home="$(mktemp -d)"
  run bash -c "
    export HOME='${empty_home}'
    source '${WB_LIB}/wb-container.sh'
    wb_container_detect
    echo 'GOT_EXIT_0'
  "
  rm -rf "${empty_home}"
  [ "${status}" -ne 0 ]
  [[ "${output}" != *"GOT_EXIT_0"* ]]
  [ -z "${output}" ]
}

# ---------------------------------------------------------------------------
# 6. wb_container_compose_argv produces correct argv format (no extra args beyond wine_cmd)
# ---------------------------------------------------------------------------
@test "container: wb_container_compose_argv produces entry --filesystem=P --filesystem=D --verb=waitforexitandrun -- cmd" {
  run bash -c "
    source '${WB_LIB}/wb-container.sh'
    wb_container_compose_argv '/fake/entry' '/my/prefix' '/my/dist' '/usr/bin/wine'
  "
  [ "${status}" -eq 0 ]
  local lines=()
  while IFS= read -r line; do
    lines+=("${line}")
  done <<< "${output}"
  [ "${#lines[@]}" -eq 6 ]
  [ "${lines[0]}" = "/fake/entry" ]
  [ "${lines[1]}" = "--filesystem=/my/prefix" ]
  [ "${lines[2]}" = "--filesystem=/my/dist" ]
  [ "${lines[3]}" = "--verb=waitforexitandrun" ]
  [ "${lines[4]}" = "--" ]
  [ "${lines[5]}" = "/usr/bin/wine" ]
}

# ---------------------------------------------------------------------------
# 7. wb_container_compose_argv includes wine_cmd and extra args, and --filesystem= bind
# ---------------------------------------------------------------------------
@test "container: wb_container_compose_argv includes wine_cmd and args after --" {
  run bash -c "
    source '${WB_LIB}/wb-container.sh'
    wb_container_compose_argv '/pv/entry' '/pfx/path' '/dist/path' '/dist/bin/wine' 'notepad.exe' 'arg1' 'arg2'
  "
  [ "${status}" -eq 0 ]
  local lines=()
  while IFS= read -r line; do
    lines+=("${line}")
  done <<< "${output}"
  # argv elements: entry, --filesystem=pfx, --filesystem=dist, --verb=..., --, wine, exe, arg1, arg2 = 9
  [ "${#lines[@]}" -eq 9 ]
  [ "${lines[0]}" = "/pv/entry" ]
  [ "${lines[1]}" = "--filesystem=/pfx/path" ]
  [ "${lines[2]}" = "--filesystem=/dist/path" ]
  [ "${lines[3]}" = "--verb=waitforexitandrun" ]
  [ "${lines[4]}" = "--" ]
  [ "${lines[5]}" = "/dist/bin/wine" ]
  [ "${lines[6]}" = "notepad.exe" ]
  [ "${lines[7]}" = "arg1" ]
  [ "${lines[8]}" = "arg2" ]
}

# ---------------------------------------------------------------------------
# 8. wb run with WB_CONTAINER=1 but pressure-vessel MISSING → exit 1 with clear error
# ---------------------------------------------------------------------------
@test "container: wb run with WB_CONTAINER=1 and no pressure-vessel exits 1 with clear error" {
  unset WB_CONTAINER_ENTRY 2>/dev/null || true
  # Use a HOME with no Steam
  local empty_home
  empty_home="$(mktemp -d)"
  run bash -c "
    export WB_CONTAINER=1
    export HOME='${empty_home}'
    export WB_HOME='${TEST_HOME}'
    export WB_LOG_FILE='${TEST_HOME}/wb.log'
    export WB_ESYNC=0 WB_FSYNC=0 WB_NTSYNC=0 WB_DXVK=0 WB_VKD3D=0 WB_NVAPI=0
    '${WB}' run notepad.exe --prefix TESTPFX --wait
  "
  rm -rf "${empty_home}"
  [ "${status}" -eq 1 ]
  echo "${output}" | grep -qi "pressure-vessel not found"
}

# ---------------------------------------------------------------------------
# 9. wb run with WB_CONTAINER=1 and fake pressure-vessel: wine is invoked via PV
# ---------------------------------------------------------------------------
@test "container: wb run with WB_CONTAINER=1 and fake PV entry invokes wine through pressure-vessel" {
  export WB_CONTAINER=1
  export WB_CONTAINER_ENTRY="${PV_ENTRY}"
  run "${WB}" run notepad.exe --prefix TESTPFX --wait
  [ "${status}" -eq 0 ]
  # pressure-vessel wrapper log must exist and contain the invocation
  [ -f "${TEST_HOME}/pv.log" ]
  _pv_log | grep -q "pv-invoked:"
  # wine must have been called (fake-wine logs exec:notepad.exe)
  _wine_log | grep -q "exec:notepad.exe"
}

# ---------------------------------------------------------------------------
# 10. wb config disable-container reverses; wb run no longer tries to wrap
# ---------------------------------------------------------------------------
@test "container: wb config disable-container removes WB_CONTAINER; run no longer wraps" {
  # Enable first
  "${WB}" config enable-container >/dev/null

  # Confirm it's set
  grep -q "WB_CONTAINER=1" "${TEST_HOME}/etc/runtime.conf"

  # Now disable
  run "${WB}" config disable-container
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qi "disabled"

  # WB_CONTAINER must not appear in conf
  if [[ -f "${TEST_HOME}/etc/runtime.conf" ]]; then
    ! grep -q "WB_CONTAINER=1" "${TEST_HOME}/etc/runtime.conf"
  fi

  # Run without WB_CONTAINER_ENTRY set — must succeed without wrapping
  unset WB_CONTAINER WB_CONTAINER_ENTRY 2>/dev/null || true
  run "${WB}" run notepad.exe --prefix TESTPFX --wait
  [ "${status}" -eq 0 ]
  # pv.log must NOT exist (pressure-vessel was never invoked)
  [ ! -f "${TEST_HOME}/pv.log" ]
}

# ---------------------------------------------------------------------------
# 11. wb exec with WB_CONTAINER=1 and fake PV entry invokes wine through pressure-vessel
# ---------------------------------------------------------------------------
@test "container: wb exec with WB_CONTAINER=1 routes through pressure-vessel" {
  export WB_CONTAINER=1
  export WB_CONTAINER_ENTRY="${PV_ENTRY}"
  export WB_PREFIX=TESTPFX
  run "${WB}" exec notepad.exe
  [ "${status}" -eq 0 ]
  [ -f "${TEST_HOME}/pv.log" ]
  _pv_log | grep -q "pv-invoked:"
  _wine_log | grep -q "exec:notepad.exe"
}

# ---------------------------------------------------------------------------
# 12. wb exec with WB_CONTAINER=1 and no PV → exit 1 with clear error
# ---------------------------------------------------------------------------
@test "container: wb exec with WB_CONTAINER=1 and no pressure-vessel exits 1 with clear error" {
  unset WB_CONTAINER_ENTRY 2>/dev/null || true
  local empty_home
  empty_home="$(mktemp -d)"
  run bash -c "
    export WB_CONTAINER=1
    export HOME='${empty_home}'
    export WB_HOME='${TEST_HOME}'
    export WB_LOG_FILE='${TEST_HOME}/wb.log'
    export WB_ESYNC=0 WB_FSYNC=0 WB_NTSYNC=0 WB_DXVK=0 WB_VKD3D=0 WB_NVAPI=0
    export WB_PREFIX=TESTPFX
    '${WB}' exec notepad.exe
  "
  rm -rf "${empty_home}"
  [ "${status}" -eq 1 ]
  echo "${output}" | grep -qi "pressure-vessel not found"
}

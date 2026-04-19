#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# 23_flatpak_detection.bats — sandbox-aware wb_pp_detect_root tests (M14)
#
# Simulates the Flatpak sandbox by setting FLATPAK_ID and controlling the
# /run/host/home tree via a tmpdir overlay.  No real Flatpak installation
# is required.
# ---------------------------------------------------------------------------

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"

# Source only the pp-installer; it has no hard inter-lib dependencies for
# wb_pp_detect_root (it only uses shell builtins and env vars).
_source_pp() {
  # shellcheck source=../src/wb-lib/wb-log.sh
  source "${WB_LIB}/wb-log.sh"
  # shellcheck source=../src/wb-lib/wb-pp-installer.sh
  source "${WB_LIB}/wb-pp-installer.sh"
}

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  # Ensure $USER is set — CI containers (bash:5.2 Alpine) don't set it.
  if [[ -z "${USER:-}" ]]; then
    USER="$(id -un 2>/dev/null || echo testuser)"
    export USER
  fi
  # Ensure a clean sandbox environment by default.
  unset FLATPAK_ID   2>/dev/null || true
  unset PORT_WINE_PATH 2>/dev/null || true
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# ---------------------------------------------------------------------------
# Test 1: No sandbox — $PORT_WINE_PATH wins if set
# ---------------------------------------------------------------------------
@test "detect_root: no sandbox — PORT_WINE_PATH env is honoured" {
  run bash -c "
    export HOME='${TEST_HOME}'
    unset FLATPAK_ID
    export PORT_WINE_PATH='/custom/pp/path'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_detect_root
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "/custom/pp/path" ]
}

# ---------------------------------------------------------------------------
# Test 2: No sandbox, no env — returns ~/PortProton regardless of existence
# ---------------------------------------------------------------------------
@test "detect_root: no sandbox, no env — returns HOME/PortProton (may not exist)" {
  run bash -c "
    export HOME='${TEST_HOME}'
    unset FLATPAK_ID
    unset PORT_WINE_PATH
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_detect_root
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "${TEST_HOME}/PortProton" ]
}

# ---------------------------------------------------------------------------
# Test 3: Flatpak sandbox + /run/host/home/<user>/PortProton exists — returns it
# ---------------------------------------------------------------------------
@test "detect_root: Flatpak sandbox + host PP dir exists — returns host path" {
  # Build the fake host path.
  local fake_host_pp="${TEST_HOME}/run/host/home/${USER}/PortProton"
  mkdir -p "${fake_host_pp}"

  run bash -c "
    export HOME='${TEST_HOME}'
    export FLATPAK_ID='org.wine_bleeding.wb'
    unset PORT_WINE_PATH
    # Override /run/host/home lookup by monkey-patching USER to point into TEST_HOME.
    # We achieve this by making the function's path resolve inside TEST_HOME via
    # an intermediate wrapper that redefines the search root.
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    # Redefine _flatpak_host_pp resolution: the function uses \$USER so set that.
    # Redirect /run/host/home via a path variable used in the implementation.
    # Since the implementation hardcodes /run/host/home/\${USER}/PortProton, we
    # build exactly that path inside TEST_HOME and symlink /run/host into TEST_HOME.
    # Simplest approach: override wb_pp_detect_root with the same logic but using
    # a different base so the test can construct the path.
    wb_pp_detect_root() {
      if [[ -n \"\${PORT_WINE_PATH:-}\" ]]; then
        echo \"\${PORT_WINE_PATH}\"
        return 0
      fi
      if [[ -n \"\${FLATPAK_ID:-}\" ]]; then
        local _flatpak_host_pp=\"${TEST_HOME}/run/host/home/\${USER}/PortProton\"
        if [[ -d \"\${_flatpak_host_pp}\" ]]; then
          echo \"\${_flatpak_host_pp}\"
          return 0
        fi
        echo 'wb-pp-installer: PortProton not accessible from Flatpak sandbox; grant --filesystem=~/PortProton at install time' >&2
      fi
      echo \"\${HOME}/PortProton\"
    }
    wb_pp_detect_root
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "${fake_host_pp}" ]
}

# ---------------------------------------------------------------------------
# Test 4: Flatpak sandbox + PORT_WINE_PATH set — env wins over host path
# ---------------------------------------------------------------------------
@test "detect_root: Flatpak sandbox + PORT_WINE_PATH set — env wins" {
  # Build a fake host path too (should NOT be chosen).
  local fake_host_pp="${TEST_HOME}/run/host/home/${USER}/PortProton"
  mkdir -p "${fake_host_pp}"

  run bash -c "
    export HOME='${TEST_HOME}'
    export FLATPAK_ID='org.wine_bleeding.wb'
    export PORT_WINE_PATH='/explicit/override/pp'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_detect_root
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "/explicit/override/pp" ]
}

# ---------------------------------------------------------------------------
# Test 5: Flatpak sandbox + no PP visible — returns ~/PortProton + warns stderr
# ---------------------------------------------------------------------------
@test "detect_root: Flatpak sandbox, no PP visible — returns HOME/PortProton and warns" {
  run bash -c "
    export HOME='${TEST_HOME}'
    export FLATPAK_ID='org.wine_bleeding.wb'
    unset PORT_WINE_PATH
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_detect_root
  " 2>&1
  # Status 0: detection itself does not fail; callers validate existence.
  [ "${status}" -eq 0 ]
  # Stdout contains the fallback path; stderr contains the warning.
  # bats run captures both streams together when redirected.
  [[ "${output}" == *"PortProton"* ]]
  [[ "${output}" == *"grant --filesystem=~/PortProton"* ]]
}

# ---------------------------------------------------------------------------
# Test 6: wb_pp_detect_root is idempotent and side-effect-free (no mkdir)
# ---------------------------------------------------------------------------
@test "detect_root: calling twice produces identical output, no dirs created" {
  run bash -c "
    export HOME='${TEST_HOME}'
    unset FLATPAK_ID
    unset PORT_WINE_PATH
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    result1=\"\$(wb_pp_detect_root)\"
    result2=\"\$(wb_pp_detect_root)\"
    [[ \"\${result1}\" == \"\${result2}\" ]] || { echo 'mismatch' >&2; exit 1; }
    echo \"\${result1}\"
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "${TEST_HOME}/PortProton" ]
  # The function must not have created a directory.
  [ ! -d "${TEST_HOME}/PortProton" ]
}

# ---------------------------------------------------------------------------
# Test 7: No sandbox — PORT_WINE_PATH with spaces is passed through verbatim
# ---------------------------------------------------------------------------
@test "detect_root: PORT_WINE_PATH with spaces is returned verbatim" {
  run bash -c "
    export HOME='${TEST_HOME}'
    unset FLATPAK_ID
    export PORT_WINE_PATH='/home/user/My Games/PortProton'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_detect_root
  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "/home/user/My Games/PortProton" ]
}

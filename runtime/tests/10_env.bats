#!/usr/bin/env bats
# Tests for wb-env.sh: wb_env_compose() function

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"

# Source all required libs into a subshell-per-test via helper
_load_env_lib() {
  # shellcheck source=../src/wb-lib/wb-log.sh
  source "${WB_LIB}/wb-log.sh"
  # shellcheck source=../src/wb-lib/wb-json.sh
  source "${WB_LIB}/wb-json.sh"
  # shellcheck source=../src/wb-lib/wb-env.sh
  source "${WB_LIB}/wb-env.sh"
}

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
  export TEST_DIST="${FIXTURE_DIST}"
  export TEST_PFX="${TEST_HOME}/prefixes/TESTPFX"
  mkdir -p "${TEST_PFX}"

  # Clear WB_* env vars that might leak from outside
  unset WB_ESYNC WB_FSYNC WB_NTSYNC WB_DXVK WB_VKD3D WB_NVAPI \
        WB_DXVK_HUD WB_DXVK_ASYNC WB_DXVK_STATE_CACHE_PATH \
        WB_VKD3D_SHADER_CACHE_PATH WB_DEBUG_WINE WB_STAGING_SHARED_MEMORY \
        WB_EXTRA_DLLOVERRIDES WB_DEBUG 2>/dev/null || true
}

teardown() {
  rm -rf "${TEST_HOME}"
}

# Helper: run wb_env_compose in a subshell and capture stdout
_compose() {
  (
    _load_env_lib
    wb_env_compose "$@"
  )
}

# 1. All defaults: WINEDEBUG=-all
@test "env: default WINEDEBUG is -all" {
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '^WINEDEBUG=-all$'
}

# 2. WB_ESYNC=1 → WINEESYNC=1 in output
@test "env: WB_ESYNC=1 produces WINEESYNC=1" {
  export WB_ESYNC=1
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '^WINEESYNC=1$'
}

# 3. WB_ESYNC=0 → WINEESYNC NOT in output
@test "env: WB_ESYNC=0 does not produce WINEESYNC" {
  export WB_ESYNC=0
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  ! echo "${output}" | grep -qE '^WINEESYNC='
}

# 4a. WB_FSYNC=1 → WINEFSYNC=1
@test "env: WB_FSYNC=1 produces WINEFSYNC=1" {
  export WB_FSYNC=1
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '^WINEFSYNC=1$'
}

# 4b. WB_FSYNC=0 → WINEFSYNC NOT in output
@test "env: WB_FSYNC=0 does not produce WINEFSYNC" {
  export WB_FSYNC=0
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  ! echo "${output}" | grep -qE '^WINEFSYNC='
}

# 4c. WB_NTSYNC=1 → WINENTSYNC=1
@test "env: WB_NTSYNC=1 produces WINENTSYNC=1" {
  export WB_NTSYNC=1
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '^WINENTSYNC=1$'
}

# 4d. STAGING_SHARED_MEMORY defaults to 1
@test "env: STAGING_SHARED_MEMORY defaults to 1" {
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '^STAGING_SHARED_MEMORY=1$'
}

# 5. WB_DXVK_HUD=fps → DXVK_HUD=fps
@test "env: WB_DXVK_HUD=fps produces DXVK_HUD=fps" {
  export WB_DXVK_HUD=fps
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '^DXVK_HUD=fps$'
}

# 6. WB_DXVK_HUD unset → DXVK_HUD NOT in output
@test "env: WB_DXVK_HUD unset does not produce DXVK_HUD" {
  unset WB_DXVK_HUD 2>/dev/null || true
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  ! echo "${output}" | grep -qE '^DXVK_HUD='
}

# 7. WINEPREFIX, WINE, WINESERVER, WINELOADER, WINEDLLPATH, WB_DIST_DIR
@test "env: static path vars correctly derived from args" {
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE "^WINEPREFIX=${TEST_PFX}$"
  echo "${output}" | grep -qE "^WINE=${TEST_DIST}/bin/wine$"
  echo "${output}" | grep -qE "^WINESERVER=${TEST_DIST}/bin/wineserver$"
  echo "${output}" | grep -qE "^WINELOADER=${TEST_DIST}/bin/wine$"
  echo "${output}" | grep -qE "^WB_DIST_DIR=${TEST_DIST}$"
  echo "${output}" | grep -qE "^WINEDLLPATH=${TEST_DIST}/lib/wine/x86_64-unix:${TEST_DIST}/lib/wine/i386-unix$"
}

# 8. WB_DXVK=1: DXVK DLLs appear in WINEDLLOVERRIDES as =n
@test "env: WB_DXVK=1 puts DXVK dlls in WINEDLLOVERRIDES as =n" {
  export WB_DXVK=1
  export WB_VKD3D=0
  export WB_NVAPI=0
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  # dxgi.dll exists in fake-dist dxvk dir
  echo "${output}" | grep -qE '^WINEDLLOVERRIDES=.*dxgi=n.*'
}

# 9. WB_DXVK=0: dxgi=n NOT in WINEDLLOVERRIDES
@test "env: WB_DXVK=0 does not include dxgi=n in WINEDLLOVERRIDES" {
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  ! echo "${output}" | grep -qE 'dxgi=n'
}

# 10. WB_VKD3D=0 → no VKD3D entries
@test "env: WB_VKD3D=0 does not include d3d12=n in WINEDLLOVERRIDES" {
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  ! echo "${output}" | grep -qE 'd3d12=n'
}

# 11. WB_NVAPI=0 → no NVAPI entries
@test "env: WB_NVAPI=0 does not include nvapi64=n in WINEDLLOVERRIDES" {
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  ! echo "${output}" | grep -qE 'nvapi64=n'
}

# 12. WB_EXTRA_DLLOVERRIDES appended to final string
@test "env: WB_EXTRA_DLLOVERRIDES=winemenubuilder.exe=;foo.dll=b is appended" {
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0
  export WB_EXTRA_DLLOVERRIDES="winemenubuilder.exe=;foo.dll=b"
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE 'winemenubuilder\.exe='
  echo "${output}" | grep -qE 'foo\.dll=b'
}

# 13. CRITICAL: malformed WB_EXTRA_DLLOVERRIDES is rejected → exit 1
@test "env: malformed WB_EXTRA_DLLOVERRIDES with spaces is rejected" {
  export WB_DXVK=0
  export WB_VKD3D=0
  export WB_NVAPI=0
  export WB_EXTRA_DLLOVERRIDES="foo=n; rm -rf /"
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -ne 0 ]
}

# 14. WB_DXVK_STATE_CACHE_PATH override honored
@test "env: WB_DXVK_STATE_CACHE_PATH override is honored" {
  export WB_DXVK_STATE_CACHE_PATH="/custom/dxvk-cache"
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE '^DXVK_STATE_CACHE_PATH=/custom/dxvk-cache$'
}

# 14b. Default DXVK_STATE_CACHE_PATH is WB_HOME/cache/dxvk-state
@test "env: default DXVK_STATE_CACHE_PATH is WB_HOME/cache/dxvk-state" {
  unset WB_DXVK_STATE_CACHE_PATH 2>/dev/null || true
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE "^DXVK_STATE_CACHE_PATH=${WB_HOME}/cache/dxvk-state$"
}

# 15. Sort order is deterministic (same inputs → same byte-for-byte output)
@test "env: output is deterministic across two calls" {
  export WB_DXVK=1
  export WB_VKD3D=1
  export WB_NVAPI=0
  local out1 out2
  out1="$(_compose "${TEST_PFX}" "${TEST_DIST}")"
  out2="$(_compose "${TEST_PFX}" "${TEST_DIST}")"
  [ "${out1}" = "${out2}" ]
}

# 16. Output format is strict KEY=VALUE lines
@test "env: all output lines match ^[A-Z][A-Z0-9_]*=" {
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  # Every non-empty output line must look like an env var assignment
  local line
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    if ! [[ "${line}" =~ ^[A-Z][A-Z0-9_]*= ]]; then
      echo "Bad output line: '${line}'" >&2
      return 1
    fi
  done <<< "${output}"
}

# 17. VKD3D=1 produces d3d12=n in WINEDLLOVERRIDES
@test "env: WB_VKD3D=1 produces d3d12=n in WINEDLLOVERRIDES" {
  export WB_DXVK=0
  export WB_VKD3D=1
  export WB_NVAPI=0
  run _compose "${TEST_PFX}" "${TEST_DIST}"
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -qE 'd3d12=n'
}

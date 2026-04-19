#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  export WB_HOME="${TEST_HOME}"
  mkdir -p "${WB_HOME}/share" "${WB_HOME}/etc"
  unset WB_DXVK WB_VKD3D WB_NVAPI WB_MONO WB_ICU WB_ESYNC WB_FSYNC WB_DEBUG WB_RUNTIME WB_PREFIX || true
}

teardown() {
  rm -rf "${TEST_HOME}"
}

_load_config() {
  # Source libs and wb_config_load in a subshell to get exported vars
  # We need to capture the result; use a helper that prints KEY=VALUE lines
  bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-config.sh'
    wb_config_load
    declare -px | grep -oP '^declare -x \K(WB_[A-Z0-9_]+)=.*' || true
  " WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" 2>/dev/null
}

# 1. Layer 1 only (defaults.conf) sets WB_DXVK=1
@test "layer1: defaults.conf sets WB_DXVK=1" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  result="$(_load_config)"
  [[ "${result}" == *"WB_DXVK='1'"* ]] || [[ "${result}" == *'WB_DXVK="1"'* ]] || \
    echo "${result}" | grep -q "WB_DXVK"
  echo "${result}" | grep "WB_DXVK" | grep -q "1"
}

# 2. Layer 2 (profile.conf) overrides layer 1
@test "layer2: profile.conf overrides defaults WB_DXVK=0" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  mkdir -p "${TEST_HOME}/.config/wine-bleeding"
  echo "WB_DXVK=0" > "${TEST_HOME}/.config/wine-bleeding/profile.conf"
  result="$(env -i HOME="${HOME}" WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" \
    bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-config.sh'
    wb_config_load
    echo \"DXVK=\${WB_DXVK:-}\"
  " 2>/dev/null)"
  [[ "${result}" == *"DXVK=0"* ]]
}

# 3. Layer 3 (runtime.conf) overrides layer 2
@test "layer3: runtime.conf overrides profile.conf" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  mkdir -p "${TEST_HOME}/.config/wine-bleeding"
  echo "WB_DXVK=0" > "${TEST_HOME}/.config/wine-bleeding/profile.conf"
  echo "WB_DXVK=1" > "${WB_HOME}/etc/runtime.conf"
  result="$(bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-config.sh'
    wb_config_load
    echo \"DXVK=\${WB_DXVK:-}\"
  " WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" 2>/dev/null)"
  [[ "${result}" == *"DXVK=1"* ]]
}

# 4. Layer 5 (env) overrides all
@test "layer5: environment WB_DXVK overrides all layers" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  echo "WB_DXVK=1" > "${WB_HOME}/etc/runtime.conf"
  result="$(WB_DXVK=0 "${WB}" config show 2>/dev/null)"
  echo "${result}" | jq -e '.WB_DXVK == "0"'
}

# 5. Layer 4 code path present but skipped in M1
@test "layer4: prefix wb.conf code path exists but is skipped in M1 (no prefix)" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  # wb_config_load takes an optional prefix_conf arg; when empty, layer 4 is skipped
  result="$(bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-config.sh'
    wb_config_load ''
    echo 'ok'
  " WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" 2>/dev/null)"
  [[ "${result}" == *"ok"* ]]
}

# 6. Missing defaults.conf → no error, fallthrough
@test "missing defaults.conf: no error, exits 0" {
  # WB_HOME/share/defaults.conf does not exist
  run "${WB}" config show
  [ "${status}" -eq 0 ]
}

# 7. Missing profile.conf → no error
@test "missing profile.conf: no error" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  # XDG_CONFIG_HOME has no wine-bleeding/profile.conf
  run env WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${WB}" config show
  [ "${status}" -eq 0 ]
}

# 8. Missing runtime.conf → no error
@test "missing runtime.conf: no error" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  # WB_HOME/etc/runtime.conf does not exist
  run env WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${WB}" config show
  [ "${status}" -eq 0 ]
}

# 9. Injection test: semicolon command in runtime.conf must not execute
@test "security: semicolon injection in runtime.conf is blocked" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  local marker="/tmp/WB_INJECTION_SHOULD_NOT_EXIST_$$"
  rm -f "${marker}"
  printf 'WB_DXVK=1\ntouch %s\n' "${marker}" > "${WB_HOME}/etc/runtime.conf"
  run env WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${WB}" config show
  [ "${status}" -eq 0 ]
  [ ! -e "${marker}" ]
  echo "${output}" | jq -e '.WB_DXVK == "1"'
}

# 10. Injection test via command substitution in value
@test "security: backtick injection in runtime.conf value is blocked" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  local marker="/tmp/WB_SHOULD_NOT_$$"
  rm -f "${marker}"
  printf 'WB_DXVK="$(touch %s)"\n' "${marker}" > "${WB_HOME}/etc/runtime.conf"
  run env WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${WB}" config show
  [ "${status}" -eq 0 ]
  [ ! -e "${marker}" ]
}

# 11. Non-allowlisted variable does NOT cross into parent shell
@test "security: non-allowlisted var is not imported" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  echo "MALICIOUS_VAR=pwn" > "${WB_HOME}/etc/runtime.conf"
  result="$(bash -c "
    set -euo pipefail
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-config.sh'
    wb_config_load
    echo \"MALICIOUS=\${MALICIOUS_VAR:-ABSENT}\"
  " WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" 2>/dev/null)"
  [[ "${result}" == *"MALICIOUS=ABSENT"* ]]
}

# 12. wb config path reports correct source file for WB_DXVK
@test "config path: WB_DXVK attributed to runtime.conf when set there" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  echo "WB_DXVK=1" > "${WB_HOME}/etc/runtime.conf"
  run env WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${WB}" config path WB_DXVK
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"runtime.conf"* ]]
}

# 13. wb config path without key lists all keys
@test "config path: no key arg lists all key origins" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  run env WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" "${WB}" config path
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WB_DXVK"* ]]
}

# 14. Environment layer gets attributed to "environment"
@test "config path: env-sourced var attributed to 'environment'" {
  cp "${BATS_TEST_DIRNAME}/../share/defaults.conf" "${WB_HOME}/share/defaults.conf"
  run env WB_HOME="${WB_HOME}" XDG_CONFIG_HOME="${TEST_HOME}/.config" WB_DXVK=0 "${WB}" config path WB_DXVK
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"environment"* ]]
}

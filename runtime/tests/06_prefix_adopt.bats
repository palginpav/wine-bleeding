#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_PP="${BATS_TEST_DIRNAME}/fixtures/fake-pp-prefix"
SCHEMA_FILE="${BATS_TEST_DIRNAME}/../share/schemas/wb_runtime.schema.json"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

_make_pp_prefix() {
  local pfx
  pfx="$(mktemp -d)"
  cp -a "${FIXTURE_PP}/." "${pfx}/"
  echo "${pfx}"
}

# 1. Coexist adopt creates .wb_runtime, leaves .wine_ver / system.reg / winetricks.log / user.reg unchanged (mtime)
#    Also hashes drive_c/ user data files to prove coexist does not corrupt the prefix contents.
@test "adopt coexist: .wb_runtime created; PP files mtime + drive_c/ SHA256 unchanged" {
  local pfx
  pfx="$(_make_pp_prefix)"

  local mtime_wine mtime_sys mtime_user mtime_wt
  mtime_wine="$(stat -c '%Y' "${pfx}/.wine_ver")"
  mtime_sys="$(stat -c '%Y' "${pfx}/system.reg")"
  mtime_user="$(stat -c '%Y' "${pfx}/user.reg")"
  mtime_wt="$(stat -c '%Y' "${pfx}/winetricks.log")"

  local save_sha_before config_sha_before
  save_sha_before="$(sha256sum "${pfx}/drive_c/Program Files/GameX/save.dat" | awk '{print $1}')"
  config_sha_before="$(sha256sum "${pfx}/drive_c/users/steamuser/Documents/gameconfig.ini" | awk '{print $1}')"

  sleep 1

  run "${WB}" prefix adopt "${pfx}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -f "${pfx}/.wb_runtime" ]

  [ "$(stat -c '%Y' "${pfx}/.wine_ver")" = "${mtime_wine}" ]
  [ "$(stat -c '%Y' "${pfx}/system.reg")" = "${mtime_sys}" ]
  [ "$(stat -c '%Y' "${pfx}/user.reg")" = "${mtime_user}" ]
  [ "$(stat -c '%Y' "${pfx}/winetricks.log")" = "${mtime_wt}" ]

  local save_sha_after config_sha_after
  save_sha_after="$(sha256sum "${pfx}/drive_c/Program Files/GameX/save.dat" | awk '{print $1}')"
  config_sha_after="$(sha256sum "${pfx}/drive_c/users/steamuser/Documents/gameconfig.ini" | awk '{print $1}')"
  [ "${save_sha_after}" = "${save_sha_before}" ]
  [ "${config_sha_after}" = "${config_sha_before}" ]

  rm -rf "${pfx}"
}

# 2. Coexist adopt sets pp_coexist=true and owner=wb-runtime
@test "adopt coexist: .wb_runtime has pp_coexist=true and owner=wb-runtime" {
  local pfx
  pfx="$(_make_pp_prefix)"

  run "${WB}" prefix adopt "${pfx}" 2>/dev/null
  [ "${status}" -eq 0 ]

  local pp_coexist owner
  pp_coexist="$(jq -r '.pp_coexist' "${pfx}/.wb_runtime")"
  owner="$(jq -r '.owner' "${pfx}/.wb_runtime")"
  [ "${pp_coexist}" = "true" ]
  [ "${owner}" = "wb-runtime" ]

  rm -rf "${pfx}"
}

# 3. Re-adopt (idempotent): second call preserves initialized_utc and updates last_adopted_utc
@test "adopt coexist idempotent: second adopt preserves initialized_utc, updates last_adopted_utc" {
  local pfx
  pfx="$(_make_pp_prefix)"

  run "${WB}" prefix adopt "${pfx}" 2>/dev/null
  [ "${status}" -eq 0 ]

  local init1 adopted1
  init1="$(jq -r '.initialized_utc' "${pfx}/.wb_runtime")"
  adopted1="$(jq -r '.last_adopted_utc' "${pfx}/.wb_runtime")"

  sleep 2

  run "${WB}" prefix adopt "${pfx}" 2>/dev/null
  [ "${status}" -eq 0 ]

  local init2 adopted2
  init2="$(jq -r '.initialized_utc' "${pfx}/.wb_runtime")"
  adopted2="$(jq -r '.last_adopted_utc' "${pfx}/.wb_runtime")"

  [ "${init2}" = "${init1}" ]
  [ "${adopted2}" != "${adopted1}" ]

  rm -rf "${pfx}"
}

# 4. Take-over: .wine_ver rewritten to WINE-BLEEDING, pp_coexist=false, other files unchanged
@test "adopt take-over: .wine_ver=WINE-BLEEDING, pp_coexist=false, other files mtimes unchanged" {
  local pfx
  pfx="$(_make_pp_prefix)"

  local mtime_sys mtime_user mtime_wt
  mtime_sys="$(stat -c '%Y' "${pfx}/system.reg")"
  mtime_user="$(stat -c '%Y' "${pfx}/user.reg")"
  mtime_wt="$(stat -c '%Y' "${pfx}/winetricks.log")"

  sleep 1

  run "${WB}" prefix adopt "${pfx}" --take-over 2>/dev/null
  [ "${status}" -eq 0 ]

  local wine_ver
  wine_ver="$(cat "${pfx}/.wine_ver")"
  [ "${wine_ver}" = "WINE-BLEEDING" ]

  local pp_coexist
  pp_coexist="$(jq -r '.pp_coexist' "${pfx}/.wb_runtime")"
  [ "${pp_coexist}" = "false" ]

  [ "$(stat -c '%Y' "${pfx}/system.reg")" = "${mtime_sys}" ]
  [ "$(stat -c '%Y' "${pfx}/user.reg")" = "${mtime_user}" ]
  [ "$(stat -c '%Y' "${pfx}/winetricks.log")" = "${mtime_wt}" ]

  rm -rf "${pfx}"
}

# 5. Take-over preserves all other registry file content
@test "adopt take-over: system.reg and user.reg content unchanged" {
  local pfx
  pfx="$(_make_pp_prefix)"

  local sys_before user_before wt_before
  sys_before="$(cat "${pfx}/system.reg")"
  user_before="$(cat "${pfx}/user.reg")"
  wt_before="$(cat "${pfx}/winetricks.log")"

  run "${WB}" prefix adopt "${pfx}" --take-over 2>/dev/null
  [ "${status}" -eq 0 ]

  [ "$(cat "${pfx}/system.reg")" = "${sys_before}" ]
  [ "$(cat "${pfx}/user.reg")" = "${user_before}" ]
  [ "$(cat "${pfx}/winetricks.log")" = "${wt_before}" ]

  rm -rf "${pfx}"
}

# 6. Adopt on absent path -> exit non-zero, no changes
@test "adopt: absent path exits non-zero" {
  run "${WB}" prefix adopt "/nonexistent/path/xyz123" 2>/dev/null
  [ "${status}" -ne 0 ]
}

# 7. Adopt on locked prefix -> exit 1, "prefix busy"
@test "adopt: locked prefix exits 1 with prefix busy" {
  local pfx
  pfx="$(_make_pp_prefix)"

  # Acquire lock in background subshell, hold for 10 seconds
  (
    exec 9>"${pfx}/.wb_lock"
    flock -x 9
    sleep 10
  ) &
  local bg_pid=$!
  sleep 0.3

  run "${WB}" prefix adopt "${pfx}" 2>&1
  kill "${bg_pid}" 2>/dev/null || true
  wait "${bg_pid}" 2>/dev/null || true
  rm -rf "${pfx}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"prefix busy"* ]]
}

# 8. Schema validation: generated .wb_runtime passes check-jsonschema
@test "adopt: generated .wb_runtime passes JSON schema validation" {
  if ! command -v check-jsonschema >/dev/null 2>&1; then
    skip "check-jsonschema not found (pip install check-jsonschema)"
  fi

  local pfx
  pfx="$(_make_pp_prefix)"

  run "${WB}" prefix adopt "${pfx}" 2>/dev/null
  [ "${status}" -eq 0 ]

  run check-jsonschema --schemafile "${SCHEMA_FILE}" "${pfx}/.wb_runtime"
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
}

# 9. Path traversal (../etc) -> non-zero exit with path traversal rejection message
@test "adopt: path containing .. is rejected" {
  run "${WB}" prefix adopt "../etc" 2>&1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"rejected"* ]] || [[ "${output}" == *"invalid"* ]]
}

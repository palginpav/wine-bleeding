#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_PP="${BATS_TEST_DIRNAME}/fixtures/fake-pp-prefix"
FIXTURE_FP="${BATS_TEST_DIRNAME}/fixtures/fake-prefix"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

_source_prefix() {
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-json.sh"
  source "${WB_LIB}/wb-lock.sh"
  source "${WB_LIB}/wb-dist.sh"
  source "${WB_LIB}/wb-prefix.sh"
}

# 1. classify absent path -> absent
@test "classify: absent directory -> absent" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '/nonexistent/path/that/does/not/exist'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  [ "${status}" -eq 0 ]
  [ "${output}" = "absent" ]
}

# 2. existing fake-prefix has .wine_ver=WINE-BLEEDING, stubs, no winetricks.log, no .wb_runtime -> broken
@test "classify: fake-prefix (.wine_ver=WINE-BLEEDING, no .wb_runtime, no winetricks.log) -> broken" {
  local pfx
  pfx="$(mktemp -d)"
  cp -a "${FIXTURE_FP}/." "${pfx}/"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "broken" ]
}

# 3. PP-like fixture: .wine_ver=PROTON_LG_10.13, winetricks.log present, no .wb_runtime -> pp-owned-untouched
@test "classify: PP fixture (.wine_ver=PROTON_LG_10.13 + winetricks.log, no sentinel) -> pp-owned-untouched" {
  local pfx
  pfx="$(mktemp -d)"
  cp -a "${FIXTURE_PP}/." "${pfx}/"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "pp-owned-untouched" ]
}

# 4. .wb_runtime with owner=wb-runtime, pp_coexist=false -> wb-native
@test "classify: sentinel owner=wb-runtime pp_coexist=false -> wb-native" {
  local pfx
  pfx="$(mktemp -d)"
  cp -a "${FIXTURE_PP}/." "${pfx}/"
  printf '%s\n' "WINE-BLEEDING" > "${pfx}/.wine_ver"
  printf '%s\n' '{"schema":1,"prefix_name":"test","runtime_alias":"WINE-BLEEDING","runtime_target":null,"runtime_target_sha256":null,"initialized_utc":"2026-04-18T00:00:00Z","last_launch_utc":null,"mono_version":null,"wineboot_generation":0,"owner":"wb-runtime","pp_coexist":false,"last_adopted_utc":"2026-04-18T00:00:00Z"}' \
    > "${pfx}/.wb_runtime"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "wb-native" ]
}

# 5. .wb_runtime with owner=wb-runtime, pp_coexist=true -> shared-adopted
@test "classify: sentinel owner=wb-runtime pp_coexist=true -> shared-adopted" {
  local pfx
  pfx="$(mktemp -d)"
  cp -a "${FIXTURE_PP}/." "${pfx}/"
  printf '%s\n' '{"schema":1,"prefix_name":"test","runtime_alias":"WINE-BLEEDING","runtime_target":null,"runtime_target_sha256":null,"initialized_utc":"2026-04-18T00:00:00Z","last_launch_utc":null,"mono_version":null,"wineboot_generation":0,"owner":"wb-runtime","pp_coexist":true,"last_adopted_utc":"2026-04-18T00:00:00Z"}' \
    > "${pfx}/.wb_runtime"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "shared-adopted" ]
}

# 6. malformed .wb_runtime (garbage JSON) -> broken
@test "classify: malformed .wb_runtime (garbage JSON) -> broken" {
  local pfx
  pfx="$(mktemp -d)"
  printf 'PROTON_LG\n' > "${pfx}/.wine_ver"
  printf 'this is not json at all }{' > "${pfx}/.wb_runtime"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "broken" ]
}

# 7. .wb_runtime missing owner field -> broken
@test "classify: .wb_runtime missing owner field -> broken" {
  local pfx
  pfx="$(mktemp -d)"
  printf 'WINE-BLEEDING\n' > "${pfx}/.wine_ver"
  printf '%s\n' '{"schema":1,"prefix_name":"test","pp_coexist":true}' > "${pfx}/.wb_runtime"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "broken" ]
}

# 8. .wb_runtime present but no .wine_ver at all -> broken
@test "classify: .wb_runtime present but no .wine_ver -> broken" {
  local pfx
  pfx="$(mktemp -d)"
  printf '%s\n' '{"schema":1,"prefix_name":"test","runtime_alias":"WINE-BLEEDING","runtime_target":null,"runtime_target_sha256":null,"initialized_utc":"2026-04-18T00:00:00Z","last_launch_utc":null,"mono_version":null,"wineboot_generation":0,"owner":"wb-runtime","pp_coexist":false,"last_adopted_utc":"2026-04-18T00:00:00Z"}' \
    > "${pfx}/.wb_runtime"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "broken" ]
}

# 9. .wine_ver=WINE-BLEEDING + valid .wb_runtime -> wb-native (PP grep-match, but we own it)
@test "classify: .wine_ver=WINE-BLEEDING + valid .wb_runtime owner=wb-runtime -> wb-native" {
  local pfx
  pfx="$(mktemp -d)"
  printf 'WINE-BLEEDING' > "${pfx}/.wine_ver"
  printf 'log\n' > "${pfx}/winetricks.log"
  printf '%s\n' '{"schema":1,"prefix_name":"test","runtime_alias":"WINE-BLEEDING","runtime_target":null,"runtime_target_sha256":null,"initialized_utc":"2026-04-18T00:00:00Z","last_launch_utc":null,"mono_version":null,"wineboot_generation":0,"owner":"wb-runtime","pp_coexist":false,"last_adopted_utc":"2026-04-18T00:00:00Z"}' \
    > "${pfx}/.wb_runtime"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "wb-native" ]
}

# 10. only drive_c/ present, no .wine_ver, no .wb_runtime, no winetricks.log -> broken
@test "classify: only drive_c present, no other marker files -> broken" {
  local pfx
  pfx="$(mktemp -d)"
  mkdir -p "${pfx}/drive_c/windows/system32"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "broken" ]
}

# 11. M3-R2: truncated/corrupt .wb_runtime mid-write -> broken
@test "classify: truncated .wb_runtime (corrupt mid-write) -> broken" {
  local pfx
  pfx="$(mktemp -d)"
  printf 'PROTON_LG\n' > "${pfx}/.wine_ver"
  printf '{"schema":1,"prefix_name":"te' > "${pfx}/.wb_runtime"

  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_LIB}/wb-prefix.sh'
    wb_prefix_classify '${pfx}'
  " WB_HOME="${WB_HOME}" WB_LOG_FILE="${WB_LOG_FILE}" 2>/dev/null
  rm -rf "${pfx}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "broken" ]
}

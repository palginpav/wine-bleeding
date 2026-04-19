#!/usr/bin/env bats

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
WB_BIN="${BATS_TEST_DIRNAME}/../src/wb"
FIXTURE_PP="${BATS_TEST_DIRNAME}/fixtures/fake-pp-root"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  # Set up a fake PortProton tree.
  export FAKE_PP="${TEST_HOME}/FakePP"
  export FAKE_PP_DATA="${FAKE_PP}/data"
  mkdir -p "${FAKE_PP_DATA}"
  cp -f "${FIXTURE_PP}/data/user.conf" "${FAKE_PP_DATA}/user.conf"

  # Export so wb_pp_detect_root picks it up.
  export PORT_WINE_PATH="${FAKE_PP}"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

_source_pp_lib() {
  # shellcheck source=../src/wb-lib/wb-log.sh
  source "${WB_LIB}/wb-log.sh"
  # shellcheck source=../src/wb-lib/wb-json.sh
  source "${WB_LIB}/wb-json.sh"
  # shellcheck source=../src/wb-lib/wb-lock.sh
  source "${WB_LIB}/wb-lock.sh"
  # shellcheck source=../src/wb-lib/wb-paths.sh
  source "${WB_LIB}/wb-paths.sh"
  # shellcheck source=../src/wb-lib/wb-components.sh
  source "${WB_LIB}/wb-components.sh"
  # shellcheck source=../src/wb-lib/wb-reg.sh
  source "${WB_LIB}/wb-reg.sh"
  # shellcheck source=../src/wb-lib/wb-pp-installer.sh
  source "${WB_LIB}/wb-pp-installer.sh"
}

# 1. Install on empty user.conf creates fenced block + backup.
@test "pp_install: installs hook block and creates backup" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
  "
  [ "${status}" -eq 0 ]
  grep -q '# BEGIN wb-runtime' "${FAKE_PP_DATA}/user.conf"
  grep -q '# END wb-runtime' "${FAKE_PP_DATA}/user.conf"
  ls "${FAKE_PP_DATA}/user.conf.wb-backup-"* >/dev/null 2>&1
}

# 2. Idempotent: second install no-ops ("already installed").
@test "pp_install: second install is idempotent" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
    wb_pp_install_hook '${FAKE_PP_DATA}'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already installed"* ]]
  local block_count
  block_count="$(grep -c '# BEGIN wb-runtime' "${FAKE_PP_DATA}/user.conf" || true)"
  [ "${block_count}" -eq 1 ]
}

# 3. Uninstall restores byte-for-byte from backup (sha256 match).
@test "pp_install: uninstall restores user.conf byte-for-byte from backup" {
  local sha_before
  sha_before="$(sha256sum "${FAKE_PP_DATA}/user.conf" | awk '{print $1}')"

  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
    wb_pp_uninstall_hook '${FAKE_PP_DATA}'
  "
  local sha_after
  sha_after="$(sha256sum "${FAKE_PP_DATA}/user.conf" | awk '{print $1}')"
  [ "${sha_before}" = "${sha_after}" ]
}

# 4. Uninstall without backup falls back to sed fence removal.
@test "pp_install: uninstall without backup uses sed fence removal" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
  "
  # Remove backups to force sed path.
  rm -f "${FAKE_PP_DATA}/user.conf.wb-backup-"*
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_uninstall_hook '${FAKE_PP_DATA}'
  "
  [ "${status}" -eq 0 ]
  ! grep -q '# BEGIN wb-runtime' "${FAKE_PP_DATA}/user.conf" 2>/dev/null
}

# 5. Install then uninstall leaves user.conf identical to before install.
@test "pp_install: round-trip install+uninstall is identity" {
  local sha_before
  sha_before="$(sha256sum "${FAKE_PP_DATA}/user.conf" | awk '{print $1}')"
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
    wb_pp_uninstall_hook '${FAKE_PP_DATA}'
  "
  local sha_after
  sha_after="$(sha256sum "${FAKE_PP_DATA}/user.conf" | awk '{print $1}')"
  [ "${sha_before}" = "${sha_after}" ]
}

# 6. Existing add_in_start_portwine: install refuses without --force.
@test "pp_install: refuses if add_in_start_portwine already exists" {
  cat >> "${FAKE_PP_DATA}/user.conf" <<'EOF'
add_in_start_portwine () {
    echo "custom hook"
}
EOF
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
  " 2>&1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"refusing to overwrite"* ]]
}

# 7. Hook libraries are copied to ${pp_data}/wb/lib/ — all expected libs present.
@test "pp_install: all required libs copied to wb/lib/" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
  "
  for lib in wb-log.sh wb-json.sh wb-lock.sh wb-paths.sh wb-components.sh wb-reg.sh wb-die.sh wb-config.sh; do
    [ -f "${FAKE_PP_DATA}/wb/lib/${lib}" ]
  done
  [ -x "${FAKE_PP_DATA}/wb/hooks/reapply.sh" ]
}

# 8. wb pp status reports correct state after install and uninstall.
@test "wb pp status: accurate reporting after install and uninstall" {
  run env \
    PORT_WINE_PATH="${FAKE_PP}" \
    WB_HOME="${TEST_HOME}" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${WB_BIN}" pp status
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"hook installed:   no"* ]]

  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
  "

  run env \
    PORT_WINE_PATH="${FAKE_PP}" \
    WB_HOME="${TEST_HOME}" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${WB_BIN}" pp status
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"hook installed:   yes"* ]]
  [[ "${output}" == *"reapply.sh:       yes"* ]]
}

# 9. Concurrent installs: two parallel installs produce exactly one block.
@test "pp_install: concurrent installs produce exactly one hook block" {
  local pids=()
  for _ in 1 2; do
    bash -c "
      source '${WB_LIB}/wb-log.sh'
      source '${WB_LIB}/wb-json.sh'
      source '${WB_LIB}/wb-lock.sh'
      source '${WB_LIB}/wb-paths.sh'
      source '${WB_LIB}/wb-components.sh'
      source '${WB_LIB}/wb-reg.sh'
      source '${WB_LIB}/wb-pp-installer.sh'
      wb_pp_install_hook '${FAKE_PP_DATA}' 2>/dev/null || true
    " &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "${pid}" || true
  done
  local block_count
  block_count="$(grep -c '# BEGIN wb-runtime' "${FAKE_PP_DATA}/user.conf" || true)"
  [ "${block_count}" -eq 1 ]
}

# 10. Multiple install runs don't overwrite existing backups (unique timestamps).
@test "pp_install: multiple installs produce unique backup files" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
    wb_pp_uninstall_hook '${FAKE_PP_DATA}'
  "
  sleep 1
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-lock.sh'
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-components.sh'
    source '${WB_LIB}/wb-reg.sh'
    source '${WB_LIB}/wb-pp-installer.sh'
    wb_pp_install_hook '${FAKE_PP_DATA}'
  "
  local backup_count
  backup_count="$(ls -1 "${FAKE_PP_DATA}/user.conf.wb-backup-"* 2>/dev/null | wc -l || true)"
  [ "${backup_count}" -ge 2 ]
}

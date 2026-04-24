#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"

@test "wb --version prints wb <VERSION> matching runtime/VERSION" {
  local expected
  expected="$(tr -d '[:space:]' < "${BATS_TEST_DIRNAME}/../VERSION")"
  run "${WB}" --version
  [ "${status}" -eq 0 ]
  [ "${output}" = "wb ${expected}" ]
}

@test "wb help exits 0 and prints a non-empty line" {
  run "${WB}" help
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "wb nonexistent-subcommand exits non-zero" {
  run "${WB}" nonexistent-subcommand
  [ "${status}" -ne 0 ]
}

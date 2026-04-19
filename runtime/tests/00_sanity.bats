#!/usr/bin/env bats

load "lib/common.bash"

WB="${BATS_TEST_DIRNAME}/../src/wb"

@test "wb --version prints wb 1.1.0-dev" {
  run "${WB}" --version
  [ "${status}" -eq 0 ]
  [ "${output}" = "wb 1.1.0-dev" ]
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

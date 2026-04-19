#!/usr/bin/env bash
set -euo pipefail

setup_test_home() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
}

teardown_test_home() {
  if [[ -n "${TEST_HOME:-}" && -d "${TEST_HOME}" ]]; then
    rm -rf "${TEST_HOME}"
  fi
}

assert_json_key() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local escaped_key
  escaped_key="$(printf '%s' "${key}" | sed 's/[][\\.^$*+?(){}|/]/\\&/g')"
  local actual
  actual="$(grep -oP "\"${escaped_key}\"\\s*:\\s*\"\\K[^\"]*" "${file}" || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "assert_json_key: key '${key}' expected '${expected}' got '${actual}'" >&2
    return 1
  fi
}

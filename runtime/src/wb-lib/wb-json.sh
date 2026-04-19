#!/usr/bin/env bash
set -euo pipefail

wb_json_read() {
  local file="$1"
  local key="$2"
  if [[ ! -r "${file}" ]]; then
    return 0
  fi
  if ! jq empty "${file}" 2>/dev/null; then
    return 1
  fi
  jq -r "${key} // empty" "${file}"
}

wb_json_write_atomic() {
  local file="$1"
  local json="$2"
  local dir
  dir="$(dirname "${file}")"
  mkdir -p "${dir}"
  local tmp
  tmp="$(mktemp "${dir}/.wb_json_XXXXXX")"
  printf '%s\n' "${json}" > "${tmp}"
  mv -T "${tmp}" "${file}"
}

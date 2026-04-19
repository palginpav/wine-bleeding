#!/usr/bin/env bash
set -euo pipefail

_wb_log_file() {
  if [[ -n "${WB_LOG_FILE:-}" ]]; then
    echo "${WB_LOG_FILE}"
  else
    local home
    home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
    echo "${home}/log/wb.log"
  fi
}

_wb_log_emit() {
  local level="$1"
  local msg="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local log_file
  log_file="$(_wb_log_file)"
  mkdir -p "$(dirname "${log_file}")"

  local json
  json="$(jq -cn --arg ts "${ts}" --arg level "${level}" --arg msg "${msg}" \
    '{ts: $ts, level: $level, msg: $msg}')"

  echo "${json}" >> "${log_file}"
  echo "[${ts}] ${level}: ${msg}" >&2
}

wb_log_debug() {
  [[ "${WB_DEBUG:-0}" == "1" ]] || return 0
  _wb_log_emit "DEBUG" "$*"
}

wb_log_info() {
  _wb_log_emit "INFO" "$*"
}

wb_log_warn() {
  _wb_log_emit "WARN" "$*"
}

wb_log_error() {
  _wb_log_emit "ERROR" "$*"
}

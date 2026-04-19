#!/usr/bin/env bash
set -euo pipefail

# Maximum log file size in bytes before rotation (default 10 MB).
# SECURITY: reject 0, negative, and non-numeric — a 0 threshold would rotate
# on every write and destroy log history within a handful of calls. Any
# positive integer is accepted (tests use small values like 10 bytes).
WB_LOG_MAX_BYTES="${WB_LOG_MAX_BYTES:-10485760}"
if ! [[ "${WB_LOG_MAX_BYTES}" =~ ^[1-9][0-9]*$ ]]; then
  WB_LOG_MAX_BYTES=10485760
fi

_wb_log_file() {
  if [[ -n "${WB_LOG_FILE:-}" ]]; then
    echo "${WB_LOG_FILE}"
  else
    local home
    home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
    echo "${home}/log/wb.log"
  fi
}

# Rotate the log file if it exceeds WB_LOG_MAX_BYTES.
# Keeps generations wb.log.1 .. wb.log.5 (deletes wb.log.5 if it would
# overflow the 5-generation limit).
# Uses flock on <log>.rotate-lock to prevent race with concurrent writers.
# This function is silent — it does not write to the log it is rotating.
_wb_log_rotate_if_needed() {
  local log_file="$1"

  # Nothing to rotate if the file does not exist yet.
  [[ -f "${log_file}" ]] || return 0

  local size
  size="$(stat -c %s "${log_file}" 2>/dev/null || echo 0)"
  if [[ "${size}" -lt "${WB_LOG_MAX_BYTES}" ]]; then
    return 0
  fi

  local rotate_lock="${log_file}.rotate-lock"

  # Acquire exclusive lock on the rotate-lock file.
  # Use a subshell with flock so the FD is released when the subshell exits.
  (
    exec 200>"${rotate_lock}"
    flock -x 200

    # Re-check size inside the lock: a concurrent writer may have already rotated.
    local size_now
    size_now="$(stat -c %s "${log_file}" 2>/dev/null || echo 0)"
    if [[ "${size_now}" -lt "${WB_LOG_MAX_BYTES}" ]]; then
      return 0
    fi

    # Rotate generations: delete .5 if present, shift .4→.5, .3→.4, .2→.3, .1→.2, log→.1
    [[ -f "${log_file}.5" ]] && rm -f "${log_file}.5"
    [[ -f "${log_file}.4" ]] && mv "${log_file}.4" "${log_file}.5"
    [[ -f "${log_file}.3" ]] && mv "${log_file}.3" "${log_file}.4"
    [[ -f "${log_file}.2" ]] && mv "${log_file}.2" "${log_file}.3"
    [[ -f "${log_file}.1" ]] && mv "${log_file}.1" "${log_file}.2"
    mv "${log_file}" "${log_file}.1"
    # Create a fresh empty log file.
    : > "${log_file}"
  )
}

_wb_log_emit() {
  local level="$1"
  local msg="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local log_file
  log_file="$(_wb_log_file)"
  mkdir -p "$(dirname "${log_file}")"

  # Rotate before writing if the file is at or above the threshold.
  _wb_log_rotate_if_needed "${log_file}"

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

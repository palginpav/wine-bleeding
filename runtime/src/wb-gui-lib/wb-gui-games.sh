#!/usr/bin/env bash
# wb-gui-games.sh — LEGACY SHIM. Do not add new code here. See wb-gui-apps.sh.
#
# This file exists solely to keep the 13 existing bats tests in
# runtime/tests/24_gui.bats passing without modification. These tests write
# and read games.json (schema v1) using the wb_gui_games_* function names.
#
# Every public function here forwards to its wb_gui_apps_* counterpart in
# wb-gui-apps.sh. Additionally, wb_gui_games_add maintains a parallel write
# to games.json (schema v1) so that legacy tests that inspect games.json
# directly continue to pass during Phase A. This dual-write is removed in
# Phase D once the legacy bats tests are updated.
#
# History: This was the original games registry (M12). Replaced in Phase A
# (v1.6.0) by wb-gui-apps.sh which generalises the registry to any Windows app.
# DEPRECATED — all shims here will be removed after Phase D.
#
# Sourced by wb-gui; never executed directly.
set -euo pipefail

# Locate and source wb-gui-apps.sh relative to this file.
_WB_GUI_GAMES_SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=wb-gui-lib/wb-gui-apps.sh
source "${_WB_GUI_GAMES_SHIM_DIR}/wb-gui-apps.sh"

# ---------------------------------------------------------------------------
# _wb_gui_games_registry — legacy internal: returns the games.json path.
# Used by tests and the _cmd_settings fallback.
# ---------------------------------------------------------------------------
_wb_gui_games_registry() {
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  echo "${wb_home}/games.json"
}

# ---------------------------------------------------------------------------
# _wb_gui_games_load_json — legacy internal: load games.json (schema v1).
# Mirrors the original implementation so tests that expect schema v1 format work.
# ---------------------------------------------------------------------------
_wb_gui_games_load_json() {
  local reg
  reg="$(_wb_gui_games_registry)"
  if [[ ! -f "${reg}" ]]; then
    printf '{"schema":1,"games":[]}'
    return 0
  fi
  if ! jq empty "${reg}" 2>/dev/null; then
    echo "wb-gui: games.json is malformed — cannot parse" >&2
    return 1
  fi
  local schema_ver
  schema_ver="$(jq -r '.schema // empty' "${reg}")"
  if [[ "${schema_ver}" != "1" ]]; then
    echo "wb-gui: games.json has unsupported schema '${schema_ver}' (expected 1)" >&2
    return 1
  fi
  cat "${reg}"
}

# ---------------------------------------------------------------------------
# wb_gui_games_add <exe_path> <prefix_name>
# LEGACY SHIM: forwards to wb_gui_apps_add AND maintains a parallel write
# to games.json (schema v1) for backward compatibility with 24_gui.bats tests.
# DEPRECATED — remove after Phase D.
# ---------------------------------------------------------------------------
wb_gui_games_add() {
  local exe="${1:-}"
  local prefix="${2:-}"

  # Forward to primary registry (apps.json) and capture the new UUID
  local app_id
  app_id="$(wb_gui_apps_add "${exe}" "${prefix}")"

  # Also maintain games.json (schema v1) for backward compat with existing tests.
  # This dual-write is the price of keeping 24_gui.bats green in Phase A.
  local existing_json
  existing_json="$(_wb_gui_games_load_json)"

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

  local name
  name="$(basename "${exe}" .exe)"
  name="$(basename "${name}" .EXE)"

  local games_json
  games_json="$(printf '%s' "${existing_json}" | jq \
    --arg id         "${app_id}" \
    --arg name       "${name}" \
    --arg exe        "${exe}" \
    --arg prefix     "${prefix}" \
    --arg added_utc  "${now_utc}" \
    '.games += [{"id": $id, "name": $name, "exe": $exe, "prefix": $prefix, "added_utc": $added_utc}]')"

  local reg
  reg="$(_wb_gui_games_registry)"
  wb_json_write_atomic "${reg}" "${games_json}"

  echo "${app_id}"
}

# ---------------------------------------------------------------------------
# wb_gui_games_list — LEGACY SHIM.
# Reads from games.json (schema v1) to match the format expected by 24_gui.bats.
# DEPRECATED — remove after Phase D.
# ---------------------------------------------------------------------------
wb_gui_games_list() {
  local json
  json="$(_wb_gui_games_load_json)"
  printf '%s' "${json}" | jq -r \
    '.games[] | [.id, .name, .prefix, .exe, .added_utc] | @tsv' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# wb_gui_games_remove <id> — LEGACY SHIM.
# Removes from both games.json and apps.json.
# DEPRECATED — remove after Phase D.
# ---------------------------------------------------------------------------
wb_gui_games_remove() {
  local id="${1:-}"
  if [[ -z "${id}" ]]; then
    echo "wb_gui_games_remove: id required" >&2
    return 1
  fi

  # Remove from primary registry (apps.json)
  wb_gui_apps_remove "${id}"

  # Also remove from legacy games.json
  local existing_json
  existing_json="$(_wb_gui_games_load_json)"
  local new_json
  new_json="$(printf '%s' "${existing_json}" | jq --arg id "${id}" \
    '.games |= map(select(.id != $id))')"
  local reg
  reg="$(_wb_gui_games_registry)"
  wb_json_write_atomic "${reg}" "${new_json}"
}

# ---------------------------------------------------------------------------
# wb_gui_games_get <id> — LEGACY SHIM.
# Reads from games.json (schema v1) to return the expected shape.
# DEPRECATED — remove after Phase D.
# ---------------------------------------------------------------------------
wb_gui_games_get() {
  local id="${1:-}"
  if [[ -z "${id}" ]]; then
    echo "wb_gui_games_get: id required" >&2
    return 1
  fi

  local json
  json="$(_wb_gui_games_load_json)"
  local entry
  entry="$(printf '%s' "${json}" | jq --arg id "${id}" '.games[] | select(.id == $id)')"
  if [[ -z "${entry}" ]]; then
    echo "wb_gui_games_get: game '${id}' not found" >&2
    return 1
  fi
  printf '%s\n' "${entry}"
}

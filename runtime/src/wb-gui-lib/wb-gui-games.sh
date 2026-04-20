#!/usr/bin/env bash
# wb-gui-games.sh — games registry helpers for wb-gui (M12)
# Sourced by wb-gui; never executed directly.
#
# Registry: $WB_HOME/games.json
# Schema:
#   { "schema": 1, "games": [ { "id": UUID, "name": STR, "exe": PATH,
#                                "prefix": STR, "added_utc": ISO8601 } ] }
#
# All mutations are atomic via wb_json_write_atomic (sourced by caller).
set -euo pipefail

# ---------------------------------------------------------------------------
# Internal: resolve registry path
# ---------------------------------------------------------------------------
_wb_gui_games_registry() {
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  echo "${wb_home}/games.json"
}

# ---------------------------------------------------------------------------
# Internal: generate a UUID v4 with uuidgen or a fallback
# ---------------------------------------------------------------------------
_wb_gui_games_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    # Fallback: /proc/sys/kernel/random/uuid (Linux)
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
      cat /proc/sys/kernel/random/uuid
    else
      # Last resort: use date+random hex
      printf '%08x-%04x-%04x-%04x-%012x\n' \
        "$RANDOM$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM$RANDOM$RANDOM"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Internal: load registry JSON; emit empty-list skeleton if absent
# ---------------------------------------------------------------------------
_wb_gui_games_load_json() {
  local reg
  reg="$(_wb_gui_games_registry)"
  if [[ ! -f "${reg}" ]]; then
    printf '{"schema":1,"games":[]}'
    return 0
  fi
  # Validate JSON is parseable
  if ! jq empty "${reg}" 2>/dev/null; then
    echo "wb-gui: games.json is malformed — cannot parse" >&2
    return 1
  fi
  # Validate schema version
  local schema_ver
  schema_ver="$(jq -r '.schema // empty' "${reg}")"
  if [[ "${schema_ver}" != "1" ]]; then
    echo "wb-gui: games.json has unsupported schema '${schema_ver}' (expected 1)" >&2
    return 1
  fi
  cat "${reg}"
}

# ---------------------------------------------------------------------------
# wb_gui_games_list
# Outputs a tab-separated table: ID\tNAME\tPREFIX\tEXE\tADDED
# ---------------------------------------------------------------------------
wb_gui_games_list() {
  local json
  json="$(_wb_gui_games_load_json)"
  # jq: iterate games array; output TSV
  printf '%s' "${json}" | jq -r \
    '.games[] | [.id, .name, .prefix, .exe, .added_utc] | @tsv' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# wb_gui_games_add <exe_path> <prefix_name>
# Adds a game entry. Errors if exe path fails validation or prefix_name is empty.
# ---------------------------------------------------------------------------
wb_gui_games_add() {
  local exe="${1:-}"
  local prefix="${2:-}"

  if [[ -z "${exe}" ]]; then
    echo "wb_gui_games_add: exe path required" >&2
    return 1
  fi
  if [[ -z "${prefix}" ]]; then
    echo "wb_gui_games_add: prefix name required" >&2
    return 1
  fi

  # SECURITY: validate exe path using same rules as _wb_validate_path_arg
  _wb_gui_validate_exe_path "${exe}"

  local id
  id="$(_wb_gui_games_uuid)"
  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

  # Derive a human name from the exe basename if name not specified
  local name
  name="$(basename "${exe}" .exe)"
  name="$(basename "${name}" .EXE)"

  local existing_json
  existing_json="$(_wb_gui_games_load_json)"

  # Build new entry via jq
  local new_json
  new_json="$(printf '%s' "${existing_json}" | jq \
    --arg id "${id}" \
    --arg name "${name}" \
    --arg exe "${exe}" \
    --arg prefix "${prefix}" \
    --arg added_utc "${now_utc}" \
    '.games += [{"id": $id, "name": $name, "exe": $exe, "prefix": $prefix, "added_utc": $added_utc}]')"

  local reg
  reg="$(_wb_gui_games_registry)"
  wb_json_write_atomic "${reg}" "${new_json}"
  echo "${id}"
}

# ---------------------------------------------------------------------------
# wb_gui_games_remove <id>
# Removes a game entry by ID.
# ---------------------------------------------------------------------------
wb_gui_games_remove() {
  local id="${1:-}"
  if [[ -z "${id}" ]]; then
    echo "wb_gui_games_remove: id required" >&2
    return 1
  fi

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
# wb_gui_games_get <id>
# Prints the JSON object for a given game ID, or exits 1 if not found.
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

# ---------------------------------------------------------------------------
# _wb_gui_validate_exe_path <path>
# Rejects paths with '..' traversal or shell-metacharacter injection.
# Same logic as _wb_validate_path_arg in wb for absolute paths.
# ---------------------------------------------------------------------------
_wb_gui_validate_exe_path() {
  local path="${1:-}"
  if [[ -z "${path}" ]]; then
    echo "wb-gui: exe path required" >&2
    return 1
  fi
  if [[ "${path}" == *..* ]]; then
    echo "wb-gui: invalid exe path '${path}' (path traversal via '..' rejected)" >&2
    return 1
  fi
  # Reject characters that are dangerous in shell contexts: ; & | ` $ ( ) < > { } NL
  # Use printf with escape sequences to construct the regex without putting bare
  # $ or ` in any quoted string (avoids shellcheck SC2016 info warning).
  # \x60 = backtick, \x24 = dollar sign. Result: [;|&`$()<>{}]
  local _sc_re
  _sc_re="$(printf '[;|&\x60\x24()<>{}]')"
  if [[ "${path}" =~ ${_sc_re} ]]; then
    echo "wb-gui: invalid exe path '${path}' (shell metacharacters rejected)" >&2
    return 1
  fi
  # Must be absolute path with safe characters (letters, digits, _ . / space -)
  # Hyphen placed first in the character class to avoid range interpretation.
  local _path_re='^/[-A-Za-z0-9_./\ ]+$'
  if [[ "${path}" == /* ]]; then
    if ! [[ "${path}" =~ ${_path_re} ]]; then
      echo "wb-gui: invalid exe path '${path}' (only [-A-Za-z0-9_./ ] allowed)" >&2
      return 1
    fi
  else
    echo "wb-gui: exe path must be absolute (starts with /)" >&2
    return 1
  fi
}

#!/usr/bin/env bash
# wb-gui-apps.sh — apps registry helpers for wb-gui (Phase A / v1.6.0)
# Sourced by wb-gui; never executed directly.
#
# Registry: $WB_HOME/apps.json
# Schema v2 (replaces games.json schema v1).
#
# Public API:
#   wb_gui_apps_add <exe> <prefix> [name] [source]  -> UUID
#   wb_gui_apps_add_portable <exe> <prefix> [name]  -> UUID
#   wb_gui_apps_list                                 -> TSV
#   wb_gui_apps_get <uuid>                           -> JSON
#   wb_gui_apps_remove <uuid>
#   wb_gui_apps_set <uuid> <json_patch>
#   wb_gui_apps_migrate_from_games                   -> summary
#
# Legacy shims (kept for backward-compat — see bottom of file):
#   wb_gui_games_add / wb_gui_games_list / wb_gui_games_remove / wb_gui_games_get
#
# All mutations are atomic via wb_json_write_atomic (sourced by caller).
# Input validation mirrors _wb_gui_validate_exe_path in the original
# wb-gui-games.sh (semi-colon / traversal rejection etc.).
set -euo pipefail

# ---------------------------------------------------------------------------
# Internal: resolve registry path
# ---------------------------------------------------------------------------
_wb_gui_apps_registry() {
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  echo "${wb_home}/apps.json"
}

# ---------------------------------------------------------------------------
# Internal: generate a UUID v4 with uuidgen or a fallback
# Mirrors _wb_gui_games_uuid from the original wb-gui-games.sh.
# ---------------------------------------------------------------------------
_wb_gui_apps_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
      cat /proc/sys/kernel/random/uuid
    else
      # Fallback: 16 bytes from /dev/urandom as 128-bit hex, formatted as UUID.
      # Provides full 128-bit entropy.
      local hex
      hex="$(head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n')"
      printf '%s-%s-%s-%s-%s' \
        "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Internal: load registry JSON; emit empty-list skeleton if absent.
# Exits 1 on malformed JSON or wrong schema version.
# ---------------------------------------------------------------------------
_wb_gui_apps_load_json() {
  local reg
  reg="$(_wb_gui_apps_registry)"
  if [[ ! -f "${reg}" ]]; then
    printf '{"schema":2,"generated_by":"wb-gui/1.6.0","updated_utc":"1970-01-01T00:00:00Z","apps":[]}'
    return 0
  fi
  # Validate JSON is parseable
  if ! jq empty "${reg}" 2>/dev/null; then
    echo "wb-gui: apps.json is malformed — cannot parse" >&2
    return 1
  fi
  # Validate schema version
  local schema_ver
  schema_ver="$(jq -r '.schema // empty' "${reg}")"
  if [[ "${schema_ver}" != "2" ]]; then
    echo "wb-gui: apps.json has unsupported schema '${schema_ver}' (expected 2)" >&2
    return 1
  fi
  cat "${reg}"
}

# ---------------------------------------------------------------------------
# _wb_gui_validate_exe_path <path>
# Rejects paths with '..' traversal or shell-metacharacter injection.
# Same logic as in the original wb-gui-games.sh.
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
  # \x60 = backtick, \x24 = dollar sign. Result: [;|&`$()<>{}]
  local _sc_re
  _sc_re="$(printf '[;|&\x60\x24()<>{}]')"
  if [[ "${path}" =~ ${_sc_re} ]]; then
    echo "wb-gui: invalid exe path '${path}' (shell metacharacters rejected)" >&2
    return 1
  fi
  # Must be absolute.
  if [[ "${path}" != /* ]]; then
    echo "wb-gui: exe path must be absolute (starts with /)" >&2
    return 1
  fi
  # Reject newlines / other control characters / quote-like chars that could
  # break quoting once we eventually pass the path through a shell context.
  # Any printable UTF-8 codepoint (Cyrillic, CJK, accented Latin, emoji, …)
  # is otherwise allowed: real users have non-ASCII directory names like
  # ~/Загрузки/ (Russian "Downloads"), ~/桌面/ (Chinese "Desktop"),
  # ~/Téléchargements/ (French "Downloads") and they were being rejected
  # by the previous ASCII-only whitelist regex (^/[-A-Za-z0-9_./ ]+$).
  if [[ "${path}" =~ [[:cntrl:]] ]] \
     || [[ "${path}" == *$'\n'* ]] \
     || [[ "${path}" == *\"* ]] \
     || [[ "${path}" == *\'* ]] \
     || [[ "${path}" == *\\* ]]; then
    echo "wb-gui: invalid exe path '${path}' (control characters or quote/backslash rejected)" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# wb_gui_apps_add <exe_path> <prefix_name> [name] [source]
# Adds an app entry. Returns new UUID on stdout.
# source defaults to "detected"; other valid values: "installer", "portable".
# ---------------------------------------------------------------------------
wb_gui_apps_add() {
  local exe="${1:-}"
  local prefix="${2:-}"
  local name="${3:-}"
  local source="${4:-detected}"

  if [[ -z "${exe}" ]]; then
    echo "wb_gui_apps_add: exe path required" >&2
    return 1
  fi
  if [[ -z "${prefix}" ]]; then
    echo "wb_gui_apps_add: prefix name required" >&2
    return 1
  fi

  # Validate source value
  case "${source}" in
    installer|portable|detected) ;;
    *)
      echo "wb_gui_apps_add: invalid source '${source}' (expected: installer, portable, detected)" >&2
      return 1
      ;;
  esac

  # SECURITY: validate exe path
  # Use explicit || return to ensure validation failure propagates correctly
  # through bash command-substitution subshells (set -e is inconsistent there).
  _wb_gui_validate_exe_path "${exe}" || return 1

  # Validate prefix name (same regex as wb_prefix_resolve)
  local _prefix_re='^[A-Za-z0-9_.-]+$'
  if ! [[ "${prefix}" =~ ${_prefix_re} ]]; then
    echo "wb_gui_apps_add: invalid prefix name '${prefix}'" >&2
    return 1
  fi

  local id
  id="$(_wb_gui_apps_uuid)"
  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

  # Derive name from exe basename if not supplied
  if [[ -z "${name}" ]]; then
    name="$(basename "${exe}" .exe)"
    name="$(basename "${name}" .EXE)"
  fi

  local existing_json
  existing_json="$(_wb_gui_apps_load_json)"

  # Log info if exe+prefix combo already exists (duplicate accepted per spec)
  local dupe_count
  dupe_count="$(printf '%s' "${existing_json}" | jq \
    --arg exe "${exe}" --arg prefix "${prefix}" \
    '[.apps[] | select(.exe == $exe and .prefix == $prefix)] | length')"
  if [[ "${dupe_count}" -gt 0 ]]; then
    echo "wb-gui: info: duplicate exe+prefix combo added (intentional allowed)" >&2
  fi

  # Build new entry via jq
  local new_json
  new_json="$(printf '%s' "${existing_json}" | jq \
    --arg id        "${id}" \
    --arg name      "${name}" \
    --arg exe       "${exe}" \
    --arg prefix    "${prefix}" \
    --arg added_at  "${now_utc}" \
    --arg source    "${source}" \
    --arg updated   "${now_utc}" \
    '.updated_utc = $updated |
     .apps += [{
       "id":          $id,
       "name":        $name,
       "exe":         $exe,
       "prefix":      $prefix,
       "dist":        null,
       "added_at":    $added_at,
       "last_played": $added_at,
       "icon_path":   null,
       "category":    null,
       "wine_args":   [],
       "env_vars":    {},
       "source":      $source,
       "notes":       null
     }]')"

  local reg
  reg="$(_wb_gui_apps_registry)"
  wb_json_write_atomic "${reg}" "${new_json}"
  echo "${id}"
}

# ---------------------------------------------------------------------------
# wb_gui_apps_add_portable <exe_path> <prefix_name> [name]
# Shorthand for wb_gui_apps_add with source="portable".
# Called by "Add Portable / Installed App" button.
# ---------------------------------------------------------------------------
wb_gui_apps_add_portable() {
  local exe="${1:-}"
  local prefix="${2:-}"
  local name="${3:-}"
  wb_gui_apps_add "${exe}" "${prefix}" "${name}" "portable"
}

# ---------------------------------------------------------------------------
# wb_gui_apps_list
# Outputs TSV: ID\tNAME\tPREFIX\tEXE\tADDED\tSOURCE
# ---------------------------------------------------------------------------
wb_gui_apps_list() {
  local json
  json="$(_wb_gui_apps_load_json)"
  printf '%s' "${json}" | jq -r \
    '.apps[] | [.id, .name, .prefix, .exe, .added_at, .source] | @tsv' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# wb_gui_apps_get <uuid>
# Prints the JSON object for a given app UUID, or exits 1 if not found.
# ---------------------------------------------------------------------------
wb_gui_apps_get() {
  local id="${1:-}"
  if [[ -z "${id}" ]]; then
    echo "wb_gui_apps_get: id required" >&2
    return 1
  fi

  local json
  json="$(_wb_gui_apps_load_json)"
  local entry
  entry="$(printf '%s' "${json}" | jq --arg id "${id}" '.apps[] | select(.id == $id)')"
  if [[ -z "${entry}" ]]; then
    echo "wb_gui_apps_get: app '${id}' not found" >&2
    return 1
  fi
  printf '%s\n' "${entry}"
}

# ---------------------------------------------------------------------------
# wb_gui_apps_remove <uuid>
# Removes an app entry by ID. Idempotent — no-op if not found.
# ---------------------------------------------------------------------------
wb_gui_apps_remove() {
  local id="${1:-}"
  if [[ -z "${id}" ]]; then
    echo "wb_gui_apps_remove: id required" >&2
    return 1
  fi

  local existing_json
  existing_json="$(_wb_gui_apps_load_json)"

  # Check if the entry exists; warn if not (but succeed anyway — idempotent)
  local count
  count="$(printf '%s' "${existing_json}" | jq --arg id "${id}" \
    '[.apps[] | select(.id == $id)] | length')"
  if [[ "${count}" -eq 0 ]]; then
    echo "wb-gui: warn: app '${id}' not found — no-op (idempotent remove)" >&2
    return 0
  fi

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

  local new_json
  new_json="$(printf '%s' "${existing_json}" | jq \
    --arg id      "${id}" \
    --arg updated "${now_utc}" \
    '.updated_utc = $updated | .apps |= map(select(.id != $id))')"

  local reg
  reg="$(_wb_gui_apps_registry)"
  wb_json_write_atomic "${reg}" "${new_json}"
}

# ---------------------------------------------------------------------------
# wb_gui_apps_set <uuid> <json_patch>
# Applies a jq-style merge patch to an existing entry.
# Phase A only uses this for last_played updates.
# Example: wb_gui_apps_set <id> '{"last_played":"2026-04-20T16:00:00Z"}'
# ---------------------------------------------------------------------------
wb_gui_apps_set() {
  local id="${1:-}"
  local patch="${2:-}"
  if [[ -z "${id}" ]]; then
    echo "wb_gui_apps_set: id required" >&2
    return 1
  fi
  if [[ -z "${patch}" ]]; then
    echo "wb_gui_apps_set: json_patch required" >&2
    return 1
  fi

  # Validate patch is valid JSON
  if ! printf '%s' "${patch}" | jq empty 2>/dev/null; then
    echo "wb_gui_apps_set: json_patch is not valid JSON" >&2
    return 1
  fi

  local existing_json
  existing_json="$(_wb_gui_apps_load_json)"

  # Verify the entry exists
  local count
  count="$(printf '%s' "${existing_json}" | jq --arg id "${id}" \
    '[.apps[] | select(.id == $id)] | length')"
  if [[ "${count}" -eq 0 ]]; then
    echo "wb_gui_apps_set: app '${id}' not found" >&2
    return 1
  fi

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

  local new_json
  new_json="$(printf '%s' "${existing_json}" | jq \
    --arg id      "${id}" \
    --argjson patch "${patch}" \
    --arg updated "${now_utc}" \
    '.updated_utc = $updated |
     .apps |= map(if .id == $id then . * $patch else . end)')"

  local reg
  reg="$(_wb_gui_apps_registry)"
  wb_json_write_atomic "${reg}" "${new_json}"
}

# ---------------------------------------------------------------------------
# wb_gui_apps_migrate_from_games
# One-shot idempotent migration from games.json (schema v1) to apps.json (schema v2).
# Guarded by sentinel $WB_HOME/.games-migrated.
# Emits "migrated N entries" or "already migrated" or "no games.json — created empty apps.json".
# ---------------------------------------------------------------------------
wb_gui_apps_migrate_from_games() {
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  local sentinel="${wb_home}/.games-migrated"
  local old_reg="${wb_home}/games.json"
  local new_reg="${wb_home}/apps.json"

  # Fast path: already done
  if [[ -f "${sentinel}" && -f "${new_reg}" ]]; then
    echo "already migrated"
    return 0
  fi

  # No legacy file → create empty apps.json skeleton
  if [[ ! -f "${old_reg}" ]]; then
    local now_utc
    now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"
    local empty_json
    empty_json="$(jq -cn \
      --arg now "${now_utc}" \
      '{schema:2,generated_by:"wb-gui/1.6.0",updated_utc:$now,apps:[]}')"
    wb_json_write_atomic "${new_reg}" "${empty_json}"
    touch "${sentinel}"
    echo "no games.json — created empty apps.json"
    return 0
  fi

  # Validate old games.json is parseable JSON
  if ! jq empty "${old_reg}" 2>/dev/null; then
    echo "wb-gui: games.json malformed — cannot migrate" >&2
    return 1
  fi

  # Validate schema version is 1
  local old_schema
  old_schema="$(jq -r '.schema // empty' "${old_reg}")"
  if [[ "${old_schema}" != "1" ]]; then
    echo "wb-gui: games.json schema '${old_schema}' != 1 — refusing to migrate" >&2
    return 1
  fi

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

  # Transform games.json entries to apps.json format using jq
  local new_json
  new_json="$(jq \
    --arg now "${now_utc}" \
    '{
      schema: 2,
      generated_by: "wb-gui/1.6.0-migration",
      updated_utc: $now,
      apps: [
        .games[] | {
          id:          .id,
          name:        .name,
          exe:         .exe,
          prefix:      .prefix,
          dist:        null,
          added_at:    .added_utc,
          last_played: .added_utc,
          icon_path:   null,
          category:    null,
          wine_args:   [],
          env_vars:    {},
          source:      "detected",
          notes:       null
        }
      ]
    }' "${old_reg}")"

  local entry_count
  entry_count="$(printf '%s' "${new_json}" | jq '.apps | length')"

  # Write new apps.json atomically (write-then-rename: if this succeeds, apps.json is complete)
  wb_json_write_atomic "${new_reg}" "${new_json}"

  # Archive old games.json — never delete it (user safety net)
  local archive_name
  archive_name="${old_reg}.migrated-${now_utc}"
  mv "${old_reg}" "${archive_name}"

  # Sentinel LAST — only present after full success
  touch "${sentinel}"

  echo "migrated ${entry_count} entries"
}

# ---------------------------------------------------------------------------
# LEGACY SHIMS — kept in wb-gui-games.sh AND here for grep-ability.
# Forward every call to the wb_gui_apps_* equivalents.
# DEPRECATED — remove after Phase D.
# ---------------------------------------------------------------------------
# (Actual shims live in wb-gui-games.sh, which sources this file and delegates.
#  These aliases here allow code that sources wb-gui-apps.sh directly to also
#  call wb_gui_games_* without sourcing the shim file.)
wb_gui_games_add()    { wb_gui_apps_add    "$@"; }
wb_gui_games_list()   { wb_gui_apps_list;         }
wb_gui_games_remove() { wb_gui_apps_remove "$@"; }
wb_gui_games_get()    { wb_gui_apps_get    "$@"; }

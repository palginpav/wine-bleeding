#!/usr/bin/env bash
set -euo pipefail

# Associative array: key -> origin (file path or "environment")
declare -gA WB_CONFIG_ORIGIN=()

# Parse a conf file as strict KEY=VALUE (no shell execution).
# This is the ONLY config-loading path. Conf files are NEVER sourced as bash.
# Arbitrary shell commands (command substitution, backticks, process substitution,
# semicolon-chained statements, here-docs) are silently ignored because every line
# that does not match the KEY=VALUE pattern is skipped.
# Only keys matching the allowlist (WB_*, WINE*, DXVK_*, VKD3D_*) are imported.
# Accepts: KEY=value, KEY="value", KEY='value', comment lines (#), blank lines.
# Rejects and silently skips any line that does not match the simple pattern.
# Only allowlisted KEY prefixes are imported.
_wb_config_parse_jailed() {
  local conf="$1"
  [[ -r "${conf}" ]] || return 0
  local line key raw stripped
  while IFS= read -r line; do
    # Skip blank lines and comments
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    # Match KEY=VALUE (with optional surrounding whitespace)
    if [[ "${line}" =~ ^[[:space:]]*(WB_[A-Z0-9_]+|WINE[A-Z0-9_]*|DXVK_[A-Z0-9_]+|VKD3D_[A-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      raw="${BASH_REMATCH[2]}"
      # Strip surrounding single or double quotes from the value (no expansion)
      if [[ "${raw}" =~ ^\"(.*)\"$ ]]; then
        stripped="${BASH_REMATCH[1]}"
      elif [[ "${raw}" =~ ^\'(.*)\'$ ]]; then
        stripped="${BASH_REMATCH[1]}"
      else
        stripped="${raw}"
        stripped="${stripped%"${stripped##*[![:space:]]}"}"
      fi
      export "${key}=${stripped}"
    fi
    # Lines that don't match (bare commands, semicolons, etc.) are silently ignored
  done < "${conf}"
}

_wb_config_load_layer() {
  local conf="$1"
  local origin="$2"
  [[ -r "${conf}" ]] || return 0

  local before_vars
  before_vars="$(declare -px 2>/dev/null | grep -oP "^declare -x \K(WB_[A-Z0-9_]+|WINE[A-Z0-9_]*|DXVK_[A-Z0-9_]+|VKD3D_[A-Z0-9_]+)(?==)" | sort || true)"

  _wb_config_parse_jailed "${conf}"

  local after_vars
  after_vars="$(declare -px 2>/dev/null | grep -oP "^declare -x \K(WB_[A-Z0-9_]+|WINE[A-Z0-9_]*|DXVK_[A-Z0-9_]+|VKD3D_[A-Z0-9_]+)(?==)" | sort || true)"

  # Record origin for new vars and overridden vars
  local var
  while IFS= read -r var; do
    [[ -n "${var}" ]] || continue
    WB_CONFIG_ORIGIN["${var}"]="${origin}"
  done < <(comm -13 <(echo "${before_vars}") <(echo "${after_vars}") || true)

  while IFS= read -r var; do
    [[ -n "${var}" ]] || continue
    WB_CONFIG_ORIGIN["${var}"]="${origin}"
  done < <(comm -12 <(echo "${before_vars}") <(echo "${after_vars}") || true)
}

wb_config_load() {
  local prefix_conf="${1:-}"

  # Capture environment-level WB_* KEY=VALUE pairs BEFORE loading any conf file.
  # These are the vars the caller exported; they have highest precedence and must
  # be re-applied last so conf-file layers cannot clobber them.
  local env_snapshot
  env_snapshot="$(env | grep -E '^(WB_[A-Z0-9_]+|WINE[A-Z0-9_]*|DXVK_[A-Z0-9_]+|VKD3D_[A-Z0-9_]+)=' || true)"

  # Layer 1: shipped defaults
  local defaults_conf
  defaults_conf="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}/share/defaults.conf"
  _wb_config_load_layer "${defaults_conf}" "${defaults_conf}"

  # Layer 2: user profile (survives WB_HOME wipe)
  local profile_conf
  profile_conf="${XDG_CONFIG_HOME:-$HOME/.config}/wine-bleeding/profile.conf"
  _wb_config_load_layer "${profile_conf}" "${profile_conf}"

  # Layer 3: runtime.conf (user site config)
  local runtime_conf
  runtime_conf="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}/etc/runtime.conf"
  _wb_config_load_layer "${runtime_conf}" "${runtime_conf}"

  # Layer 4: per-prefix wb.conf (only when a prefix is resolved; skipped in M1)
  if [[ -n "${prefix_conf}" ]]; then
    _wb_config_load_layer "${prefix_conf}" "${prefix_conf}"
  fi

  # Layer 5: re-apply environment values (highest precedence) and record origin.
  # We use the snapshot taken before any sourcing so original env values win.
  local pair var val
  while IFS= read -r pair; do
    [[ -n "${pair}" ]] || continue
    var="${pair%%=*}"
    val="${pair#*=}"
    export "${var}=${val}"
    WB_CONFIG_ORIGIN["${var}"]="environment"
  done <<< "${env_snapshot}"
}

wb_config_as_json() {
  local jq_args=()
  local jq_expr='{'
  local i=0
  local var val

  while IFS= read -r var; do
    [[ -n "${var}" ]] || continue
    val="${!var}"
    jq_args+=("--arg" "key${i}" "${var}" "--arg" "val${i}" "${val}")
    if [[ "${i}" -gt 0 ]]; then
      jq_expr+=','
    fi
    jq_expr+="\$key${i}:\$val${i}"
    (( i++ )) || true
  done < <(declare -px 2>/dev/null | grep -oP "^declare -x \K(WB_[A-Z0-9_]+|WINE[A-Z0-9_]*|DXVK_[A-Z0-9_]+|VKD3D_[A-Z0-9_]+)(?==)" | sort -u || true)

  if [[ "${i}" -eq 0 ]]; then
    echo '{}'
    return
  fi

  jq_expr+='}'
  jq -n "${jq_args[@]}" "${jq_expr}"
}

wb_config_path_for() {
  local key="${1:-}"
  if [[ -n "${key}" ]]; then
    echo "${WB_CONFIG_ORIGIN[${key}]:-<not set>}"
  else
    local k
    for k in $(echo "${!WB_CONFIG_ORIGIN[@]}" | tr ' ' '\n' | sort); do
      printf '%s=%s\n' "${k}" "${WB_CONFIG_ORIGIN[${k}]}"
    done
  fi
}

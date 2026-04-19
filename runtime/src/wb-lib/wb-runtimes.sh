#!/usr/bin/env bash
set -euo pipefail

# wb-runtimes.sh — M13 runtime plugin registry
# Public API:
#   wb_runtimes_plugin_dir
#   wb_runtimes_plugin_list
#   wb_runtimes_plugin_read <name>
#   wb_runtimes_plugin_register <json_path>
#   wb_runtimes_plugin_resolve <name>

# ---------------------------------------------------------------------------
# _wb_runtimes_wb_home
# Returns the effective WB_HOME.
# ---------------------------------------------------------------------------
_wb_runtimes_wb_home() {
  printf '%s' "${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
}

# ---------------------------------------------------------------------------
# wb_runtimes_plugin_dir
# Prints the plugin directory path (read-only helper; does not create it).
# ---------------------------------------------------------------------------
wb_runtimes_plugin_dir() {
  local wb_home
  wb_home="$(_wb_runtimes_wb_home)"
  printf '%s\n' "${wb_home}/plugins/runtimes.d"
}

# ---------------------------------------------------------------------------
# wb_runtimes_plugin_list
# Enumerate all *.json files under the plugin dir.
# Prints one entry per line: NAME<TAB>TARGET_PATH<TAB>SOURCE_FILE
# Skips malformed files with a WARN to stderr.
# ---------------------------------------------------------------------------
wb_runtimes_plugin_list() {
  local plugin_dir
  plugin_dir="$(_wb_runtimes_wb_home)/plugins/runtimes.d"

  if [[ ! -d "${plugin_dir}" ]]; then
    return 0
  fi

  local f name path_val
  for f in "${plugin_dir}"/*.json; do
    # Glob with no matches expands literally when nullglob is not set
    [[ -f "${f}" ]] || continue

    if ! jq empty "${f}" 2>/dev/null; then
      wb_log_warn "wb_runtimes_plugin_list: malformed JSON in '${f}', skipping"
      continue
    fi

    name="$(jq -r '.name // empty' "${f}" 2>/dev/null || true)"
    path_val="$(jq -r '.path // empty' "${f}" 2>/dev/null || true)"

    if [[ -z "${name}" || -z "${path_val}" ]]; then
      wb_log_warn "wb_runtimes_plugin_list: missing required fields in '${f}', skipping"
      continue
    fi

    printf '%s\t%s\t%s\n' "${name}" "${path_val}" "${f}"
  done
}

# ---------------------------------------------------------------------------
# wb_runtimes_plugin_read <name>
# Find the plugin JSON file whose .name == <name>, print its content.
# Exit 1 if not found.
# ---------------------------------------------------------------------------
wb_runtimes_plugin_read() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    echo "wb_runtimes_plugin_read: NAME required" >&2
    return 1
  fi

  local plugin_dir
  plugin_dir="$(_wb_runtimes_wb_home)/plugins/runtimes.d"

  if [[ ! -d "${plugin_dir}" ]]; then
    echo "wb_runtimes_plugin_read: plugin directory not found: ${plugin_dir}" >&2
    return 1
  fi

  local f candidate_name
  for f in "${plugin_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    if ! jq empty "${f}" 2>/dev/null; then
      continue
    fi
    candidate_name="$(jq -r '.name // empty' "${f}" 2>/dev/null || true)"
    if [[ "${candidate_name}" == "${name}" ]]; then
      jq . "${f}"
      return 0
    fi
  done

  echo "wb_runtimes_plugin_read: plugin '${name}' not found" >&2
  return 1
}

# ---------------------------------------------------------------------------
# wb_runtimes_plugin_register <json_path>
# Validate json_path (file exists, parseable, has required fields, name
# matches safe pattern, path is absolute). Copy into plugin dir atomically.
# Idempotent: same content -> no-op.
# ---------------------------------------------------------------------------
wb_runtimes_plugin_register() {
  local json_path="${1:-}"
  if [[ -z "${json_path}" ]]; then
    echo "wb_runtimes_plugin_register: JSON_PATH required" >&2
    return 1
  fi

  if [[ ! -f "${json_path}" ]]; then
    echo "wb_runtimes_plugin_register: file not found: ${json_path}" >&2
    return 1
  fi

  # Validate parseable JSON
  if ! jq empty "${json_path}" 2>/dev/null; then
    echo "wb_runtimes_plugin_register: not valid JSON: ${json_path}" >&2
    return 1
  fi

  # Extract required fields
  local name schema_val path_val
  name="$(jq -r '.name // empty' "${json_path}" 2>/dev/null || true)"
  schema_val="$(jq -r '.schema // empty' "${json_path}" 2>/dev/null || true)"
  path_val="$(jq -r '.path // empty' "${json_path}" 2>/dev/null || true)"

  # Validate required fields
  if [[ -z "${schema_val}" ]]; then
    echo "wb_runtimes_plugin_register: missing required field 'schema'" >&2
    return 1
  fi
  if [[ -z "${name}" ]]; then
    echo "wb_runtimes_plugin_register: missing required field 'name'" >&2
    return 1
  fi
  if [[ -z "${path_val}" ]]; then
    echo "wb_runtimes_plugin_register: missing required field 'path'" >&2
    return 1
  fi

  # Validate name pattern BEFORE any file operation (security gate)
  if ! [[ "${name}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "wb_runtimes_plugin_register: invalid name '${name}' (must match ^[A-Za-z0-9_.-]+\$)" >&2
    return 1
  fi

  # Validate path is absolute and contains no whitespace
  if ! [[ "${path_val}" =~ ^/[^[:space:]]+$ ]]; then
    echo "wb_runtimes_plugin_register: 'path' must be an absolute path with no whitespace, got: '${path_val}'" >&2
    return 1
  fi

  # Security: do NOT follow symlinks for path validation (M11 concern).
  # We record the path as-is; the caller's intent is what matters.
  # We do not call realpath on path_val here.

  local wb_home
  wb_home="$(_wb_runtimes_wb_home)"
  local plugin_dir="${wb_home}/plugins/runtimes.d"
  mkdir -p "${plugin_dir}"

  local dest="${plugin_dir}/${name}.json"

  # Idempotent: if dest exists and content matches, no-op
  if [[ -f "${dest}" ]]; then
    local existing_json new_json
    existing_json="$(jq -cS . "${dest}" 2>/dev/null || true)"
    new_json="$(jq -cS . "${json_path}" 2>/dev/null || true)"
    if [[ "${existing_json}" == "${new_json}" ]]; then
      wb_log_info "wb_runtimes_plugin_register: '${name}' already registered (no-op)"
      return 0
    fi
  fi

  # Atomic write via temp file + mv
  local new_content
  new_content="$(jq . "${json_path}")"
  wb_json_write_atomic "${dest}" "${new_content}"

  wb_log_info "wb_runtimes_plugin_register: registered '${name}' -> '${path_val}'"
}

# ---------------------------------------------------------------------------
# wb_runtimes_plugin_resolve <name>
# Return the "path" value for the plugin with .name == <name>.
# Prints empty string + returns 1 if not found.
# ---------------------------------------------------------------------------
wb_runtimes_plugin_resolve() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    echo "wb_runtimes_plugin_resolve: NAME required" >&2
    return 1
  fi

  local plugin_dir
  plugin_dir="$(_wb_runtimes_wb_home)/plugins/runtimes.d"

  if [[ ! -d "${plugin_dir}" ]]; then
    return 1
  fi

  local dest="${plugin_dir}/${name}.json"
  if [[ -f "${dest}" ]] && jq empty "${dest}" 2>/dev/null; then
    local candidate_name path_val
    candidate_name="$(jq -r '.name // empty' "${dest}" 2>/dev/null || true)"
    path_val="$(jq -r '.path // empty' "${dest}" 2>/dev/null || true)"
    if [[ "${candidate_name}" == "${name}" && -n "${path_val}" ]]; then
      printf '%s' "${path_val}"
      return 0
    fi
  fi

  # Fallback: scan all files (in case name != filename)
  local f candidate
  for f in "${plugin_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    if ! jq empty "${f}" 2>/dev/null; then
      continue
    fi
    candidate="$(jq -r '.name // empty' "${f}" 2>/dev/null || true)"
    if [[ "${candidate}" == "${name}" ]]; then
      local pval
      pval="$(jq -r '.path // empty' "${f}" 2>/dev/null || true)"
      if [[ -n "${pval}" ]]; then
        printf '%s' "${pval}"
        return 0
      fi
    fi
  done

  return 1
}

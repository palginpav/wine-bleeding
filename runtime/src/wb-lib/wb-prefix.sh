#!/usr/bin/env bash
set -euo pipefail

wb_prefix_resolve() {
  local name="$1"

  if [[ -z "${name}" ]]; then
    echo "wb_prefix_resolve: name must not be empty" >&2
    return 1
  fi

  # SECURITY: reject names containing .. or NUL
  if [[ "${name}" == *..* ]]; then
    echo "wb_prefix_resolve: name '${name}' contains '..' (path traversal rejected)" >&2
    return 1
  fi
  # NUL bytes cannot survive bash variable assignment; guard against literal \0 in input
  if printf '%s' "${name}" | grep -qP '\x00'; then
    echo "wb_prefix_resolve: name contains NUL byte" >&2
    return 1
  fi

  if [[ "${name}" == /* ]]; then
    # Absolute path: validate it exists
    if [[ ! -e "${name}" ]]; then
      echo "wb_prefix_resolve: absolute path '${name}' does not exist" >&2
      return 1
    fi
    printf '%s' "${name}"
    return 0
  fi

  # Relative name: no path separators allowed; prefixes are a single segment.
  if ! [[ "${name}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "wb_prefix_resolve: invalid prefix name '${name}' (expected [A-Za-z0-9_.-]+ with no slashes)" >&2
    return 1
  fi

  local wb_home
  wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  printf '%s' "${wb_home}/prefixes/${name}"
}

wb_prefix_classify() {
  local path="$1"

  if [[ ! -d "${path}" ]]; then
    echo "absent"
    return 0
  fi

  local sentinel="${path}/.wb_runtime"

  if [[ -f "${sentinel}" ]]; then
    # Validate JSON parsability first
    if ! jq empty "${sentinel}" 2>/dev/null; then
      echo "broken"
      return 0
    fi

    local schema owner pp_coexist
    schema="$(jq -r '.schema // empty' "${sentinel}" 2>/dev/null || true)"
    owner="$(jq -r '.owner // empty' "${sentinel}" 2>/dev/null || true)"
    pp_coexist="$(jq -r '.pp_coexist // empty' "${sentinel}" 2>/dev/null || true)"

    # Reject future/past schema versions — forward compatibility is opt-in, not implicit.
    if [[ "${schema}" != "1" ]]; then
      echo "broken"
      return 0
    fi

    if [[ "${owner}" != "wb-runtime" ]]; then
      echo "broken"
      return 0
    fi

    # .wine_ver must exist for any valid prefix we own
    if [[ ! -f "${path}/.wine_ver" ]]; then
      echo "broken"
      return 0
    fi

    if [[ "${pp_coexist}" == "true" ]]; then
      echo "shared-adopted"
    else
      echo "wb-native"
    fi
    return 0
  fi

  # No sentinel — check PP-owned-untouched heuristic (§4.5)
  if [[ -f "${path}/.wine_ver" ]]; then
    local wine_ver
    wine_ver="$(cat "${path}/.wine_ver" 2>/dev/null || true)"
    if [[ "${wine_ver}" != "WINE-BLEEDING" ]] && [[ -f "${path}/winetricks.log" ]]; then
      echo "pp-owned-untouched"
      return 0
    fi
  fi

  echo "broken"
}

wb_prefix_write_sentinel() {
  local path="$1"
  local json="$2"
  wb_json_write_atomic "${path}/.wb_runtime" "${json}"
}

wb_prefix_read_sentinel() {
  local path="$1"
  local sentinel="${path}/.wb_runtime"

  if [[ ! -f "${sentinel}" ]]; then
    return 1
  fi

  if ! jq empty "${sentinel}" 2>/dev/null; then
    return 1
  fi

  cat "${sentinel}"
}

wb_prefix_adopt() {
  local path="$1"
  local take_over=0
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --take-over) take_over=1 ;;
      *) echo "wb_prefix_adopt: unknown option '$1'" >&2; return 1 ;;
    esac
    shift
  done

  if [[ ! -d "${path}" ]]; then
    echo "wb_prefix_adopt: path '${path}' does not exist or is not a directory" >&2
    return 1
  fi

  # SECURITY: acquire lock before any write; release in trap
  wb_acquire_lock "${path}" || {
    echo "prefix busy" >&2
    return 1
  }
  trap 'wb_release_lock "${path:-}"' EXIT

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local prefix_name
  prefix_name="$(basename "${path}")"

  # Resolve WINE-BLEEDING alias details (empty strings if absent)
  local wb_home
  wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  local alias_path="${wb_home}/dist/WINE-BLEEDING"
  local runtime_target=""
  local runtime_target_sha256=""
  if [[ -L "${alias_path}" ]] || [[ -d "${alias_path}" ]]; then
    runtime_target="$(readlink -f "${alias_path}" 2>/dev/null || true)"
    local dist_meta="${runtime_target}/.wb_dist_meta"
    if [[ -f "${dist_meta}" ]]; then
      runtime_target_sha256="$(jq -r '.builtin_dlls_hash // empty' "${dist_meta}" 2>/dev/null || true)"
    fi
  fi

  # Read existing sentinel for idempotent merge
  local initialized_utc="${now_utc}"
  local last_launch_utc="null"
  local mono_version="null"
  local wineboot_generation=0
  local sentinel="${path}/.wb_runtime"

  if [[ -f "${sentinel}" ]] && jq empty "${sentinel}" 2>/dev/null; then
    local existing_init existing_launch existing_mono existing_gen
    existing_init="$(jq -r '.initialized_utc // empty' "${sentinel}" 2>/dev/null || true)"
    existing_launch="$(jq -r '.last_launch_utc // empty' "${sentinel}" 2>/dev/null || true)"
    existing_mono="$(jq -r '.mono_version // empty' "${sentinel}" 2>/dev/null || true)"
    existing_gen="$(jq -r '.wineboot_generation // empty' "${sentinel}" 2>/dev/null || true)"

    [[ -n "${existing_init}" ]] && initialized_utc="${existing_init}"
    [[ -n "${existing_launch}" ]] && last_launch_utc="\"${existing_launch}\""
    [[ -n "${existing_gen}" ]] && wineboot_generation="${existing_gen}"
    # mono_version is populated in M4; preserve existing value for idempotent re-adopt
    if [[ -n "${existing_mono}" ]]; then
      mono_version="\"${existing_mono}\""
    fi
  fi

  local pp_coexist_val="true"
  [[ "${take_over}" -eq 1 ]] && pp_coexist_val="false"

  # Format null-or-string fields
  local runtime_target_json="null"
  [[ -n "${runtime_target}" ]] && runtime_target_json="\"${runtime_target}\""
  local runtime_sha_json="null"
  [[ -n "${runtime_target_sha256}" ]] && runtime_sha_json="\"${runtime_target_sha256}\""

  local json
  json="$(jq -cn \
    --argjson schema 1 \
    --arg prefix_name "${prefix_name}" \
    --arg runtime_alias "WINE-BLEEDING" \
    --argjson runtime_target "${runtime_target_json}" \
    --argjson runtime_target_sha256 "${runtime_sha_json}" \
    --arg initialized_utc "${initialized_utc}" \
    --argjson last_launch_utc "${last_launch_utc}" \
    --argjson mono_version "${mono_version}" \
    --argjson wineboot_generation "${wineboot_generation}" \
    --arg owner "wb-runtime" \
    --argjson pp_coexist "${pp_coexist_val}" \
    --arg last_adopted_utc "${now_utc}" \
    '{
      schema: $schema,
      prefix_name: $prefix_name,
      runtime_alias: $runtime_alias,
      runtime_target: $runtime_target,
      runtime_target_sha256: $runtime_target_sha256,
      initialized_utc: $initialized_utc,
      last_launch_utc: $last_launch_utc,
      mono_version: $mono_version,
      wineboot_generation: $wineboot_generation,
      owner: $owner,
      pp_coexist: $pp_coexist,
      last_adopted_utc: $last_adopted_utc
    }')"

  wb_prefix_write_sentinel "${path}" "${json}"

  # ONLY in take-over mode: rewrite .wine_ver to alias string (no date stamp)
  if [[ "${take_over}" -eq 1 ]]; then
    printf '%s' "WINE-BLEEDING" > "${path}/.wine_ver"
    echo "take-over: wineboot and DLL deploy land in M4."
  fi

  wb_release_lock "${path}"
  trap - EXIT
}

wb_prefix_list() {
  local wb_home
  wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  local prefix_dir="${wb_home}/prefixes"

  if [[ ! -d "${prefix_dir}" ]]; then
    return 0
  fi

  local entry name
  while IFS= read -r entry; do
    name="$(basename "${entry}")"
    # Skip dot-directories
    [[ "${name}" == .* ]] && continue
    printf '%s\n' "${name}"
  done < <(find "${prefix_dir}" -mindepth 1 -maxdepth 1 -type d | sort)
}

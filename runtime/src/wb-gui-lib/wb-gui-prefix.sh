#!/usr/bin/env bash
# wb-gui-prefix.sh — Phase D backend: per-prefix deep customisation
# Sourced by wb-gui; never executed directly.
#
# Panel coverage: Winetricks (D1), DLL overrides (D2), Wine registry (D3),
#                 Component toggles (D4).
#
# Public API:
#   wb_gui_prefix_winetricks_list <prefix_id>          → JSON array of installed verbs
#   wb_gui_prefix_winetricks_available                  → verb|cat|desc lines (cached)
#   wb_gui_prefix_winetricks_install <prefix_id> <verb> [--progress-fd N]
#   wb_gui_prefix_winetricks_reconcile <prefix_id>      → rewrite JSON from winetricks.log
#   wb_gui_prefix_reg_read <prefix_id> <key>            → JSON {subkeys,values}
#   wb_gui_prefix_reg_write <prefix_id> <key> <name> <type> <data>
#   wb_gui_prefix_reg_undo <prefix_id>
#   wb_gui_prefix_reg_safe_zone_check <key>             → "writable"|"readonly"|"invalid"
#   wb_gui_prefix_dll_set <prefix_id> <dll> <mode>
#   wb_gui_prefix_dll_remove <prefix_id> <dll>
#   wb_gui_prefix_component_toggle <prefix_id> <component> <on|off|inherit>
#   wb_gui_prefix_save_env_bake <prefix_id>
#
# Depends on (sourced by caller):
#   wb-lib/wb-json.sh        wb_json_write_atomic
#   wb-lib/wb-config.sh      _wb_config_parse_jailed
#   wb-gui-lib/wb-gui-settings.sh  wb_gui_settings_set_prefix, wb_gui_settings_home

set -euo pipefail

# ---------------------------------------------------------------------------
# Internal helpers — resolve paths
# ---------------------------------------------------------------------------
_wb_gui_prefix_wb_home() {
  printf '%s' "${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
}

_wb_gui_prefix_settings_file() {
  local prefix_id="$1"
  local wb_home
  wb_home="$(_wb_gui_prefix_wb_home)"
  printf '%s' "${wb_home}/settings/prefixes/${prefix_id}.json"
}

_wb_gui_prefix_path() {
  local prefix_id="$1"
  local wb_home
  wb_home="$(_wb_gui_prefix_wb_home)"
  printf '%s' "${wb_home}/prefixes/${prefix_id}"
}

_wb_gui_prefix_now_utc() {
  printf '%s' "${WB_GUI_PREFIX_NOW_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")}"
}

# Load and return the prefix settings JSON (or a minimal skeleton).
_wb_gui_prefix_load_json() {
  local prefix_id="$1"
  local file
  file="$(_wb_gui_prefix_settings_file "${prefix_id}")"
  if [[ -f "${file}" ]] && jq empty "${file}" 2>/dev/null; then
    cat "${file}"
  else
    local now_utc
    now_utc="$(_wb_gui_prefix_now_utc)"
    jq -cn --arg pid "${prefix_id}" --arg now "${now_utc}" \
      '{schema:1, prefix_id:$pid, updated_utc:$now}'
  fi
}

# Write updated JSON + set updated_utc atomically.
_wb_gui_prefix_write_json() {
  local prefix_id="$1"
  local json="$2"
  local file
  file="$(_wb_gui_prefix_settings_file "${prefix_id}")"
  local now_utc
  now_utc="$(_wb_gui_prefix_now_utc)"
  local final_json
  final_json="$(printf '%s' "${json}" | jq --arg now "${now_utc}" '.updated_utc=$now')"
  wb_gui_settings_home > /dev/null
  wb_json_write_atomic "${file}" "${final_json}"
}

# Resolve the wine binary for a prefix (uses WB_TEST_WINE_REG_FIXTURE seam).
_wb_gui_prefix_wine_bin() {
  local prefix_id="$1"
  local wb_home
  wb_home="$(_wb_gui_prefix_wb_home)"
  # Test seam: WB_TEST_WINE_REG_FIXTURE points to a fake wine binary for reg ops
  if [[ -n "${WB_TEST_WINE_REG_FIXTURE:-}" ]]; then
    printf '%s' "${WB_TEST_WINE_REG_FIXTURE}"
    return 0
  fi
  # Try active dist first
  local active_dist="${wb_home}/dist/WINE-BLEEDING-active"
  if [[ -x "${active_dist}/bin/wine" ]]; then
    printf '%s' "${active_dist}/bin/wine"
    return 0
  fi
  # Fall back to system wine
  if command -v wine >/dev/null 2>&1; then
    printf '%s' "$(command -v wine)"
    return 0
  fi
  echo "wb_gui_prefix: wine binary not found" >&2
  return 1
}

# Run wine reg with correct WINEPREFIX set.
_wb_gui_prefix_wine_reg() {
  local prefix_id="$1"
  shift
  local prefix_path
  prefix_path="$(_wb_gui_prefix_path "${prefix_id}")"
  local wine_bin
  wine_bin="$(_wb_gui_prefix_wine_bin "${prefix_id}")"
  WINEPREFIX="${prefix_path}" "${wine_bin}" reg "$@" 2>&1
}

# ---------------------------------------------------------------------------
# Safe-zone allowlist
# ---------------------------------------------------------------------------

# The hardcoded allowlist — adding a new zone requires a code patch (intentional).
_WB_GUI_PREFIX_REG_WRITE_ZONES=(
  "HKCU\\Software\\Wine"
  "HKCU\\Environment"
  "HKCU\\Control Panel\\Desktop"
  "HKCU\\Control Panel\\International"
  "HKLM\\System\\CurrentControlSet\\Services\\Wine"
  "HKLM\\Software\\Wine"
)

# wb_gui_prefix_reg_safe_zone_check <key>
# Returns: "writable" | "readonly" | "invalid"
wb_gui_prefix_reg_safe_zone_check() {
  local key="${1:-}"
  if [[ -z "${key}" ]]; then
    printf 'invalid'
    return 0
  fi

  # Normalize: uppercase first component up to first backslash
  local root rest
  root="${key%%\\*}"
  rest="${key#*\\}"
  root="${root^^}"
  case "${root}" in
    HKCU|HKLM|HKCR|HKU|HKCC) : ;;
    HKEY_CURRENT_USER)   root="HKCU" ;;
    HKEY_LOCAL_MACHINE)  root="HKLM" ;;
    HKEY_CLASSES_ROOT)   root="HKCR" ;;
    HKEY_USERS)          root="HKU"  ;;
    *) printf 'invalid'; return 0 ;;
  esac
  local normalized_key="${root}\\${rest}"

  local zone
  for zone in "${_WB_GUI_PREFIX_REG_WRITE_ZONES[@]}"; do
    # Check if key starts with zone (exact match or zone\subkey)
    if [[ "${normalized_key}" == "${zone}" ]] || \
       [[ "${normalized_key}" == "${zone}\\"* ]]; then
      printf 'writable'
      return 0
    fi
  done

  # Valid root but not in write allowlist — read-only
  printf 'readonly'
}

# ---------------------------------------------------------------------------
# Registry read — wb_gui_prefix_reg_read <prefix_id> <key>
# Returns JSON: {key, subkeys:[], values:[{name,type,data}]}
# ---------------------------------------------------------------------------
wb_gui_prefix_reg_read() {
  local prefix_id="${1:-}"
  local key="${2:-}"
  if [[ -z "${prefix_id}" || -z "${key}" ]]; then
    echo "wb_gui_prefix_reg_read: prefix_id and key required" >&2
    return 1
  fi

  local raw
  raw="$(_wb_gui_prefix_wine_reg "${prefix_id}" query "${key}" 2>&1)" || true

  # Parse wine reg query output
  local subkeys="[]"
  local values="[]"
  local in_target_block=0

  while IFS= read -r line; do
    # Skip blank lines
    [[ -z "${line}" ]] && continue

    # Lines starting with HKEY_ indicate a key block header
    if [[ "${line}" =~ ^HKEY_ ]]; then
      # Normalize the returned key path to match our input
      local block_key="${line}"
      # Strip trailing carriage return if any
      block_key="${block_key%$'\r'}"

      # Check if this is our target key or a direct subkey
      if [[ "${block_key^^}" == "${key^^}" ]]; then
        in_target_block=1
      else
        in_target_block=0
        # It's a subkey if it's directly under our key
        local parent="${block_key%\\*}"
        if [[ "${parent^^}" == "${key^^}" ]]; then
          local subkey_name="${block_key##*\\}"
          subkeys="$(printf '%s' "${subkeys}" | jq --arg n "${subkey_name}" '. + [$n]')"
        fi
      fi
      continue
    fi

    # Indented value lines — only parse when in target block
    [[ "${in_target_block}" -eq 0 ]] && continue
    # Strip leading whitespace and trailing CR
    local stripped="${line#"${line%%[![:space:]]*}"}"
    stripped="${stripped%$'\r'}"
    [[ -z "${stripped}" ]] && continue

    # Parse: name<TAB>type<TAB>data  (or spaces; data may have spaces)
    local vname vtype vdata
    # Use awk to split into at most 3 fields on whitespace
    local parsed
    parsed="$(printf '%s' "${stripped}" | awk '
      {
        n=$1; t=$2
        $1=""; $2=""
        d=substr($0, 3)
        # strip leading whitespace from data
        sub(/^[[:space:]]+/, "", d)
        print n "\t" t "\t" d
      }
    ' 2>/dev/null)" || continue

    vname="$(printf '%s' "${parsed}" | cut -f1)"
    vtype="$(printf '%s' "${parsed}" | cut -f2)"
    vdata="$(printf '%s' "${parsed}" | cut -f3-)"

    # Skip unparseable lines
    [[ -z "${vname}" || -z "${vtype}" ]] && continue

    # Map (Default) to empty string name
    [[ "${vname}" == "(Default)" ]] && vname=""

    # Mark special types
    local extra_flag="null"
    case "${vtype}" in
      REG_MULTI_SZ) extra_flag='"multi"' ;;
      REG_BINARY)   extra_flag='"binary"' ;;
    esac

    local entry
    entry="$(jq -cn \
      --arg name "${vname}" \
      --arg type "${vtype}" \
      --arg data "${vdata}" \
      --argjson flag "${extra_flag}" \
      '{name:$name, type:$type, data:$data, flag:$flag}')"
    values="$(printf '%s' "${values}" | jq --argjson e "${entry}" '. + [$e]')"
  done <<< "${raw}"

  jq -cn \
    --arg key "${key}" \
    --argjson subkeys "${subkeys}" \
    --argjson values "${values}" \
    '{key:$key, subkeys:$subkeys, values:$values}'
}

# ---------------------------------------------------------------------------
# Registry write — wb_gui_prefix_reg_write <prefix_id> <key> <name> <type> <data>
# ---------------------------------------------------------------------------
wb_gui_prefix_reg_write() {
  local prefix_id="${1:-}"
  local key="${2:-}"
  local vname="${3:-}"
  local vtype="${4:-}"
  local vdata="${5:-}"

  if [[ -z "${prefix_id}" || -z "${key}" || -z "${vtype}" ]]; then
    echo "wb_gui_prefix_reg_write: prefix_id, key and type required" >&2
    return 1
  fi

  # Safe-zone check
  local zone
  zone="$(wb_gui_prefix_reg_safe_zone_check "${key}")"
  if [[ "${zone}" != "writable" ]]; then
    echo "wb_gui_prefix_reg_write: write to '${key}' refused by safe-zone policy (${zone})" >&2
    return 74
  fi

  # Input validation
  local key_pat='^(HKCU|HKLM)\\[A-Za-z0-9 _.\\-]+$'
  if ! [[ "${key}" =~ ${key_pat} ]]; then
    echo "wb_gui_prefix_reg_write: invalid key format: '${key}'" >&2
    return 1
  fi
  local name_pat='^[A-Za-z0-9 _.\\-]*$'
  if ! [[ "${vname}" =~ ${name_pat} ]]; then
    echo "wb_gui_prefix_reg_write: invalid value name: '${vname}'" >&2
    return 1
  fi
  case "${vtype}" in
    REG_SZ|REG_EXPAND_SZ|REG_DWORD|REG_QWORD) : ;;
    *)
      echo "wb_gui_prefix_reg_write: unsupported type '${vtype}' (REG_BINARY/REG_MULTI_SZ are read-only)" >&2
      return 1
      ;;
  esac
  case "${vtype}" in
    REG_DWORD|REG_QWORD)
      local num_pat='^(0x[0-9A-Fa-f]+|[0-9]+)$'
      if ! [[ "${vdata}" =~ ${num_pat} ]]; then
        echo "wb_gui_prefix_reg_write: invalid numeric data for ${vtype}: '${vdata}'" >&2
        return 1
      fi
      ;;
  esac

  # Capture previous value for undo stack
  local prev_data="null"
  local query_out
  if [[ -n "${vname}" ]]; then
    query_out="$(_wb_gui_prefix_wine_reg "${prefix_id}" query "${key}" /v "${vname}" 2>/dev/null)" || true
  else
    query_out="$(_wb_gui_prefix_wine_reg "${prefix_id}" query "${key}" /ve 2>/dev/null)" || true
  fi
  if [[ -n "${query_out}" ]]; then
    # Try to extract data from query output
    local data_line
    data_line="$(printf '%s' "${query_out}" | grep -v '^HKEY_' | grep -v '^[[:space:]]*$' | head -1)" || true
    if [[ -n "${data_line}" ]]; then
      local parsed_prev
      parsed_prev="$(printf '%s' "${data_line}" | awk '{$1=$2=""; d=substr($0,3); sub(/^[[:space:]]+/,"",d); print d}' 2>/dev/null)" || true
      if [[ -n "${parsed_prev}" ]]; then
        prev_data="$(jq -cn --arg d "${parsed_prev}" '$d')"
      fi
    fi
  fi

  # Build patch record
  local now_utc
  now_utc="$(_wb_gui_prefix_now_utc)"
  local new_data_json
  new_data_json="$(jq -cn --arg d "${vdata}" '$d')"
  local patch
  patch="$(jq -cn \
    --arg key "${key}" \
    --arg name "${vname}" \
    --arg type "${vtype}" \
    --argjson prev_data "${prev_data}" \
    --argjson new_data "${new_data_json}" \
    --arg applied_utc "${now_utc}" \
    '{key:$key, name:$name, type:$type, prev_data:$prev_data, new_data:$new_data, applied_utc:$applied_utc}')"

  # Load current settings, append patch, cap at 10
  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"
  local patches
  patches="$(printf '%s' "${settings_json}" | jq '.wine_registry_patches // []')"
  patches="$(printf '%s' "${patches}" | jq --argjson p "${patch}" '. + [$p] | if length > 10 then .[1:] else . end')"
  settings_json="$(printf '%s' "${settings_json}" | jq --argjson patches "${patches}" '.wine_registry_patches=$patches')"

  # Persist undo stack BEFORE mutating registry (durability guarantee)
  _wb_gui_prefix_write_json "${prefix_id}" "${settings_json}"

  # Execute registry write
  local wine_rc=0
  if [[ -n "${vname}" ]]; then
    _wb_gui_prefix_wine_reg "${prefix_id}" add "${key}" /v "${vname}" /t "${vtype}" /d "${vdata}" /f > /dev/null 2>&1 || wine_rc=$?
  else
    _wb_gui_prefix_wine_reg "${prefix_id}" add "${key}" /ve /t "${vtype}" /d "${vdata}" /f > /dev/null 2>&1 || wine_rc=$?
  fi

  if [[ "${wine_rc}" -ne 0 ]]; then
    # Roll back the undo stack entry we just pushed
    local rolled_patches
    rolled_patches="$(printf '%s' "${patches}" | jq '.[:-1]')"
    local rolled_json
    rolled_json="$(printf '%s' "${settings_json}" | jq --argjson patches "${rolled_patches}" '.wine_registry_patches=$patches')"
    _wb_gui_prefix_write_json "${prefix_id}" "${rolled_json}"
    echo "wb_gui_prefix_reg_write: wine reg add failed (exit ${wine_rc})" >&2
    return "${wine_rc}"
  fi
}

# ---------------------------------------------------------------------------
# Registry undo — wb_gui_prefix_reg_undo <prefix_id>
# Pop the most recent patch and restore previous value.
# ---------------------------------------------------------------------------
wb_gui_prefix_reg_undo() {
  local prefix_id="${1:-}"
  if [[ -z "${prefix_id}" ]]; then
    echo "wb_gui_prefix_reg_undo: prefix_id required" >&2
    return 1
  fi

  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"
  local patches
  patches="$(printf '%s' "${settings_json}" | jq '.wine_registry_patches // []')"
  local patch_count
  patch_count="$(printf '%s' "${patches}" | jq 'length')"

  if [[ "${patch_count}" -eq 0 ]]; then
    echo "wb_gui_prefix_reg_undo: undo stack is empty" >&2
    return 1
  fi

  # Get last patch
  local last_patch
  last_patch="$(printf '%s' "${patches}" | jq '.[-1]')"
  local r_key r_name r_type r_prev_data
  r_key="$(printf '%s' "${last_patch}" | jq -r '.key')"
  r_name="$(printf '%s' "${last_patch}" | jq -r '.name')"
  r_type="$(printf '%s' "${last_patch}" | jq -r '.type')"
  r_prev_data="$(printf '%s' "${last_patch}" | jq -r '.prev_data')"

  # Safe-zone check (defensive — allowlist could change across versions)
  local zone
  zone="$(wb_gui_prefix_reg_safe_zone_check "${r_key}")"
  if [[ "${zone}" != "writable" ]]; then
    echo "wb_gui_prefix_reg_undo: key '${r_key}' no longer in write safe-zone — leaving stack intact" >&2
    return 1
  fi

  # Execute undo
  local wine_rc=0
  if [[ "${r_prev_data}" == "null" ]]; then
    # Value did not exist before patch — delete it
    if [[ -n "${r_name}" ]]; then
      _wb_gui_prefix_wine_reg "${prefix_id}" delete "${r_key}" /v "${r_name}" /f > /dev/null 2>&1 || wine_rc=$?
    else
      _wb_gui_prefix_wine_reg "${prefix_id}" delete "${r_key}" /ve /f > /dev/null 2>&1 || wine_rc=$?
    fi
  else
    # Restore previous value
    if [[ -n "${r_name}" ]]; then
      _wb_gui_prefix_wine_reg "${prefix_id}" add "${r_key}" /v "${r_name}" /t "${r_type}" /d "${r_prev_data}" /f > /dev/null 2>&1 || wine_rc=$?
    else
      _wb_gui_prefix_wine_reg "${prefix_id}" add "${r_key}" /ve /t "${r_type}" /d "${r_prev_data}" /f > /dev/null 2>&1 || wine_rc=$?
    fi
  fi

  if [[ "${wine_rc}" -ne 0 ]]; then
    echo "wb_gui_prefix_reg_undo: wine reg failed (exit ${wine_rc}) — stack unchanged" >&2
    return "${wine_rc}"
  fi

  # Pop the record from the stack and persist
  local new_patches
  new_patches="$(printf '%s' "${patches}" | jq '.[:-1]')"
  local new_json
  new_json="$(printf '%s' "${settings_json}" | jq --argjson patches "${new_patches}" '.wine_registry_patches=$patches')"
  _wb_gui_prefix_write_json "${prefix_id}" "${new_json}"
}

# ---------------------------------------------------------------------------
# DLL overrides — dll_set / dll_remove
# ---------------------------------------------------------------------------

_WB_GUI_PREFIX_VALID_MODES=(native builtin "n,b" "b,n" disabled)

_wb_gui_prefix_dll_mode_valid() {
  local mode="$1"
  local m
  for m in "${_WB_GUI_PREFIX_VALID_MODES[@]}"; do
    [[ "${m}" == "${mode}" ]] && return 0
  done
  return 1
}

# Compose WB_EXTRA_DLLOVERRIDES string from dll_overrides array.
# disabled mode → "dll=" (empty right-hand-side)
_wb_gui_prefix_dll_compose() {
  local dll_overrides_json="$1"
  # Map mode enum to WINEDLLOVERRIDES syntax
  # native→n, builtin→b, n,b→n,b, b,n→b,n, disabled→(empty)
  printf '%s' "${dll_overrides_json}" | jq -r '
    .[] |
    .dll + "=" + (
      if .mode == "native"   then "n"
      elif .mode == "builtin" then "b"
      elif .mode == "n,b"    then "n,b"
      elif .mode == "b,n"    then "b,n"
      elif .mode == "disabled" then ""
      else .mode
      end
    )
  ' | paste -sd ';' -
}

# wb_gui_prefix_dll_set <prefix_id> <dll> <mode> [<origin>]
wb_gui_prefix_dll_set() {
  local prefix_id="${1:-}"
  local dll="${2:-}"
  local mode="${3:-}"
  local origin="${4:-user}"

  if [[ -z "${prefix_id}" || -z "${dll}" || -z "${mode}" ]]; then
    echo "wb_gui_prefix_dll_set: prefix_id, dll, and mode required" >&2
    return 1
  fi

  local dll_pat='^[A-Za-z0-9_.-]+$'
  if ! [[ "${dll}" =~ ${dll_pat} ]]; then
    echo "wb_gui_prefix_dll_set: invalid DLL name '${dll}'" >&2
    return 1
  fi
  if ! _wb_gui_prefix_dll_mode_valid "${mode}"; then
    echo "wb_gui_prefix_dll_set: invalid mode '${mode}'" >&2
    return 1
  fi

  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"
  local overrides
  overrides="$(printf '%s' "${settings_json}" | jq '.dll_overrides // []')"

  # Remove existing entry for this dll, then add/update
  overrides="$(printf '%s' "${overrides}" | jq \
    --arg dll "${dll}" \
    'map(select(.dll != $dll))')"
  overrides="$(printf '%s' "${overrides}" | jq \
    --arg dll "${dll}" \
    --arg mode "${mode}" \
    --arg origin "${origin}" \
    '. + [{dll:$dll, mode:$mode, origin:$origin}]')"

  local new_json
  new_json="$(printf '%s' "${settings_json}" | jq --argjson overrides "${overrides}" '.dll_overrides=$overrides')"
  _wb_gui_prefix_write_json "${prefix_id}" "${new_json}"

  # Also bake the composed DLL string into wb.conf
  wb_gui_prefix_save_env_bake "${prefix_id}"
}

# wb_gui_prefix_dll_remove <prefix_id> <dll>
wb_gui_prefix_dll_remove() {
  local prefix_id="${1:-}"
  local dll="${2:-}"

  if [[ -z "${prefix_id}" || -z "${dll}" ]]; then
    echo "wb_gui_prefix_dll_remove: prefix_id and dll required" >&2
    return 1
  fi

  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"
  local overrides
  overrides="$(printf '%s' "${settings_json}" | jq '.dll_overrides // []')"
  overrides="$(printf '%s' "${overrides}" | jq \
    --arg dll "${dll}" \
    'map(select(.dll != $dll))')"

  local new_json
  new_json="$(printf '%s' "${settings_json}" | jq --argjson overrides "${overrides}" '.dll_overrides=$overrides')"
  _wb_gui_prefix_write_json "${prefix_id}" "${new_json}"

  wb_gui_prefix_save_env_bake "${prefix_id}"
}

# ---------------------------------------------------------------------------
# Component toggles — wb_gui_prefix_component_toggle <prefix_id> <comp> <on|off|inherit>
# ---------------------------------------------------------------------------

# wb_gui_prefix_component_toggle <prefix_id> <component> <on|off|inherit>
wb_gui_prefix_component_toggle() {
  local prefix_id="${1:-}"
  local component="${2:-}"
  local state="${3:-}"

  if [[ -z "${prefix_id}" || -z "${component}" || -z "${state}" ]]; then
    echo "wb_gui_prefix_component_toggle: prefix_id, component, and state required" >&2
    return 1
  fi

  case "${component}" in
    dxvk|vkd3d|nvapi) : ;;
    *)
      echo "wb_gui_prefix_component_toggle: unknown component '${component}' (dxvk|vkd3d|nvapi)" >&2
      return 1
      ;;
  esac

  case "${state}" in
    on|off|inherit) : ;;
    *)
      echo "wb_gui_prefix_component_toggle: invalid state '${state}' (on|off|inherit)" >&2
      return 1
      ;;
  esac

  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"
  local components
  components="$(printf '%s' "${settings_json}" | jq '.components_enabled // {}')"
  components="$(printf '%s' "${components}" | jq \
    --arg comp "${component}" \
    --arg state "${state}" \
    '.[$comp]=$state')"

  local new_json
  new_json="$(printf '%s' "${settings_json}" | jq --argjson comp "${components}" '.components_enabled=$comp')"
  _wb_gui_prefix_write_json "${prefix_id}" "${new_json}"

  wb_gui_prefix_save_env_bake "${prefix_id}"
}

# ---------------------------------------------------------------------------
# wb_gui_prefix_save_env_bake <prefix_id>
#
# Path B: writes managed env keys (WB_DXVK, WB_VKD3D, WB_NVAPI) and
# WB_EXTRA_DLLOVERRIDES (composed from dll_overrides) into <prefix_path>/wb.conf.
#
# Algorithm:
#   1. Read existing wb.conf; preserve lines NOT in _wb_prefix_managed_env_keys.
#   2. Compute new managed set from components_enabled + dll_overrides.
#   3. Write result atomically.
#   4. Update JSON env_vars + _wb_prefix_managed_env_keys for GUI round-trip.
# ---------------------------------------------------------------------------
wb_gui_prefix_save_env_bake() {
  local prefix_id="${1:-}"
  if [[ -z "${prefix_id}" ]]; then
    echo "wb_gui_prefix_save_env_bake: prefix_id required" >&2
    return 1
  fi

  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"

  # Read current managed key list from JSON (Phase B clean-slate pattern)
  local managed_keys_json
  managed_keys_json="$(printf '%s' "${settings_json}" | jq '._wb_prefix_managed_env_keys // []')"

  # Compute new managed env additions from component toggles
  local components
  components="$(printf '%s' "${settings_json}" | jq '.components_enabled // {}')"

  local new_env_vars="{}"
  local new_managed_keys="[]"

  # Per-component: on→WB_X=1, off→WB_X=0, inherit→remove key
  local comp wb_var
  for comp in dxvk vkd3d nvapi; do
    local comp_upper="${comp^^}"
    wb_var="WB_${comp_upper}"
    local comp_state
    comp_state="$(printf '%s' "${components}" | jq -r --arg c "${comp}" '.[$c] // "inherit"')"
    case "${comp_state}" in
      on)
        new_env_vars="$(printf '%s' "${new_env_vars}" | jq --arg k "${wb_var}" --arg v "1" '.[$k]=$v')"
        new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq --arg k "${wb_var}" '. + [$k]')"
        ;;
      off)
        new_env_vars="$(printf '%s' "${new_env_vars}" | jq --arg k "${wb_var}" --arg v "0" '.[$k]=$v')"
        new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq --arg k "${wb_var}" '. + [$k]')"
        ;;
      inherit)
        # No override — do not add to managed keys
        ;;
    esac
  done

  # Compose WB_EXTRA_DLLOVERRIDES from dll_overrides array
  local dll_overrides_json
  dll_overrides_json="$(printf '%s' "${settings_json}" | jq '.dll_overrides // []')"
  local dll_count
  dll_count="$(printf '%s' "${dll_overrides_json}" | jq 'length')"
  if [[ "${dll_count}" -gt 0 ]]; then
    local dll_composed
    dll_composed="$(_wb_gui_prefix_dll_compose "${dll_overrides_json}")"
    if [[ -n "${dll_composed}" ]]; then
      new_env_vars="$(printf '%s' "${new_env_vars}" | jq --arg v "${dll_composed}" '.WB_EXTRA_DLLOVERRIDES=$v')"
      new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq '. + ["WB_EXTRA_DLLOVERRIDES"]')"
    fi
  fi

  # Write wb.conf atomically: preserve user lines, strip old managed, append new
  local prefix_path
  prefix_path="$(_wb_gui_prefix_path "${prefix_id}")"
  local wb_conf="${prefix_path}/wb.conf"

  # Read existing wb.conf preserving non-managed keys bit-identically
  local preserved_lines=""
  if [[ -f "${wb_conf}" ]]; then
    while IFS= read -r line; do
      # Blank lines and comments: preserve
      if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]]; then
        preserved_lines+="${line}"$'\n'
        continue
      fi
      # Extract key from KEY=VALUE line
      if [[ "${line}" =~ ^[[:space:]]*(WB_[A-Z0-9_]+|WINE[A-Z0-9_]*|DXVK_[A-Z0-9_]+|VKD3D_[A-Z0-9_]+)[[:space:]]*= ]]; then
        local line_key="${BASH_REMATCH[1]}"
        # Check if this key is in our managed list
        local is_managed=0
        local mk
        while IFS= read -r mk; do
          [[ "${mk}" == "${line_key}" ]] && is_managed=1 && break
        done < <(printf '%s' "${managed_keys_json}" | jq -r '.[]')
        if [[ "${is_managed}" -eq 0 ]]; then
          preserved_lines+="${line}"$'\n'
        fi
        # Managed keys are dropped — will be rewritten below
      else
        # Non-matching line: preserve
        preserved_lines+="${line}"$'\n'
      fi
    done < "${wb_conf}"
  fi

  # Build new wb.conf content
  local wb_conf_content="${preserved_lines}"
  # Append managed section header comment
  if [[ "$(printf '%s' "${new_managed_keys}" | jq 'length')" -gt 0 ]]; then
    wb_conf_content+="# wb-gui Phase D managed keys — do not edit this block manually"$'\n'
    # Write each new managed key=value using jq to safely handle values containing '='
    local mk mv
    while IFS=$'\t' read -r mk mv; do
      [[ -z "${mk}" ]] && continue
      wb_conf_content+="${mk}=${mv}"$'\n'
    done < <(printf '%s' "${new_env_vars}" | jq -r 'to_entries[] | .key + "\t" + .value')
  fi

  # Atomic write of wb.conf
  mkdir -p "${prefix_path}"
  local tmp_conf
  tmp_conf="$(mktemp "${prefix_path}/.wb_conf_XXXXXX")"
  printf '%s' "${wb_conf_content}" > "${tmp_conf}"
  mv -T "${tmp_conf}" "${wb_conf}"

  # Update JSON env_vars + managed keys for GUI round-trip fidelity
  # Read existing JSON env_vars and clean slate managed keys
  local existing_env_vars
  existing_env_vars="$(printf '%s' "${settings_json}" | jq '.env_vars // {}')"
  local cleaned_env_vars
  cleaned_env_vars="$(printf '%s' "${existing_env_vars}" | jq \
    --argjson managed "${managed_keys_json}" \
    'to_entries | map(select(.key as $k | $managed | index($k) | not)) | from_entries')"
  # Merge new managed env_vars into cleaned
  local merged_env_vars
  merged_env_vars="$(printf '%s' "${cleaned_env_vars}" | jq --argjson new "${new_env_vars}" '. + $new')"

  local final_json
  final_json="$(printf '%s' "${settings_json}" | jq \
    --argjson env_vars "${merged_env_vars}" \
    --argjson managed_keys "${new_managed_keys}" \
    '.env_vars=$env_vars | ._wb_prefix_managed_env_keys=$managed_keys')"

  _wb_gui_prefix_write_json "${prefix_id}" "${final_json}"
}

# ---------------------------------------------------------------------------
# Winetricks — list installed verbs
# ---------------------------------------------------------------------------

# wb_gui_prefix_winetricks_list <prefix_id>
# Returns JSON array of installed verb names (from settings JSON).
wb_gui_prefix_winetricks_list() {
  local prefix_id="${1:-}"
  if [[ -z "${prefix_id}" ]]; then
    echo "wb_gui_prefix_winetricks_list: prefix_id required" >&2
    return 1
  fi
  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"
  printf '%s' "${settings_json}" | jq '.winetricks_verbs_installed // []'
}

# ---------------------------------------------------------------------------
# wb_gui_prefix_winetricks_reconcile <prefix_id>
# Re-read $prefix/winetricks.log and rewrite winetricks_verbs_installed.
# winetricks.log is the source of truth.
# ---------------------------------------------------------------------------
wb_gui_prefix_winetricks_reconcile() {
  local prefix_id="${1:-}"
  if [[ -z "${prefix_id}" ]]; then
    echo "wb_gui_prefix_winetricks_reconcile: prefix_id required" >&2
    return 1
  fi

  local prefix_path
  prefix_path="$(_wb_gui_prefix_path "${prefix_id}")"
  local wt_log="${prefix_path}/winetricks.log"

  local verbs_json="[]"

  if [[ -f "${wt_log}" ]]; then
    # Format: <timestamp> <verb>   (awk field 2)
    # Duplicates collapse to last occurrence (verb wins if repeated).
    # Use awk to parse and deduplicate preserving last-occurrence order.
    local verb_list
    verb_list="$(awk '
      /^[0-9]/ && NF >= 2 {
        verb = $2
        # Only accept valid verb patterns
        if (verb ~ /^[a-z0-9_.=-]+$/) {
          # Store in order array; track seen
          if (!(verb in seen)) {
            order[++n] = verb
          }
          seen[verb] = NR
        }
      }
      END {
        for (i = 1; i <= n; i++) {
          print order[i]
        }
      }
    ' "${wt_log}" 2>/dev/null)" || true

    if [[ -n "${verb_list}" ]]; then
      verbs_json="$(printf '%s' "${verb_list}" | jq -Rsc 'split("\n") | map(select(length>0))')"
    fi
  fi

  local settings_json
  settings_json="$(_wb_gui_prefix_load_json "${prefix_id}")"
  local new_json
  new_json="$(printf '%s' "${settings_json}" | jq --argjson verbs "${verbs_json}" '.winetricks_verbs_installed=$verbs')"
  _wb_gui_prefix_write_json "${prefix_id}" "${new_json}"
}

# ---------------------------------------------------------------------------
# wb_gui_prefix_winetricks_available
# Returns verb|category|description lines from winetricks list-all (cached).
# Cache: $TMPDIR/wb-gui-winetricks-cache.$USER (1 hour TTL)
# ---------------------------------------------------------------------------
wb_gui_prefix_winetricks_available() {
  local cache_file="${TMPDIR:-/tmp}/wb-gui-winetricks-cache.${USER:-nobody}"
  local cache_max_age=3600  # 1 hour

  # Check if cache is valid (less than 1 hour old)
  if [[ -f "${cache_file}" ]]; then
    local cache_age
    cache_age=$(( $(date +%s) - $(stat -c %Y "${cache_file}" 2>/dev/null || echo 0) ))
    if [[ "${cache_age}" -lt "${cache_max_age}" ]]; then
      cat "${cache_file}"
      return 0
    fi
  fi

  # Determine winetricks binary (test seam honored)
  local wt_bin
  if [[ -n "${WB_TEST_WT_FIXTURE:-}" ]]; then
    wt_bin="${WB_TEST_WT_FIXTURE}"
  elif command -v winetricks >/dev/null 2>&1; then
    wt_bin="$(command -v winetricks)"
  else
    echo "wb_gui_prefix_winetricks_available: winetricks not found" >&2
    return 4
  fi

  # Parse winetricks list-all output
  local raw
  raw="$("${wt_bin}" list-all 2>/dev/null)" || true

  local parsed
  parsed="$(printf '%s' "${raw}" | awk '
    /^===== category: / {
      cat = $0
      sub(/^===== category: /, "", cat)
      sub(/ =====.*$/, "", cat)
      next
    }
    /^[a-z0-9_.-]+[[:space:]]/ {
      verb = $1
      desc = $0
      sub(/^[a-z0-9_.-]+[[:space:]]+/, "", desc)
      print verb "|" cat "|" desc
    }
  ' 2>/dev/null)" || true

  printf '%s\n' "${parsed}" > "${cache_file}"
  printf '%s\n' "${parsed}"
}

# ---------------------------------------------------------------------------
# wb_gui_prefix_winetricks_install <prefix_id> <verb> [--progress-fd N]
# Spawns tools/run-winetricks.sh in background.
# Stdout: PID of the spawned process.
# ---------------------------------------------------------------------------
wb_gui_prefix_winetricks_install() {
  local prefix_id="${1:-}"
  local verb="${2:-}"
  local progress_fd="2"

  if [[ -z "${prefix_id}" || -z "${verb}" ]]; then
    echo "wb_gui_prefix_winetricks_install: prefix_id and verb required" >&2
    return 1
  fi

  # Parse optional --progress-fd
  shift 2
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --progress-fd) progress_fd="${2:-2}"; shift ;;
      --progress-fd=*) progress_fd="${1#--progress-fd=}" ;;
    esac
    shift
  done

  # Locate run-winetricks.sh relative to this lib file
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # May be at runtime/src/wb-gui-lib/ — run-winetricks.sh is at tools/
  local rw_script="${script_dir}/../../../tools/run-winetricks.sh"
  if [[ ! -x "${rw_script}" ]]; then
    # Installed path: libdir/wine-bleeding/wb-gui-lib → look for adjacent tools dir
    rw_script="${script_dir}/../../run-winetricks.sh"
  fi
  if [[ ! -x "${rw_script}" ]]; then
    echo "wb_gui_prefix_winetricks_install: run-winetricks.sh not found" >&2
    return 1
  fi

  local wb_home
  wb_home="$(_wb_gui_prefix_wb_home)"
  local prefix_path
  prefix_path="$(_wb_gui_prefix_path "${prefix_id}")"

  # Find active dist
  local dist_path="${wb_home}/dist/WINE-BLEEDING-active"

  # Spawn in background; return PID
  bash "${rw_script}" \
    --prefix "${prefix_id}" \
    --dist "${dist_path}" \
    --verb "${verb}" \
    --progress-fd "${progress_fd}" \
    &
  printf '%d' "$!"
}

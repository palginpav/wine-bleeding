#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# wb-reg.sh — Wine registry manipulation helpers.
# Ported from tools/deploy-to-portproton.sh lines 234-248.
# ---------------------------------------------------------------------------

# Patch DllOverrides entries in a Wine user.reg file.
# Usage: wb_reg_patch_dll_overrides <user_reg_path> <dll_list_semicolon_sep>
#   <dll_list> format: "name=mode;name2=mode2" e.g. "d3d11=n;d3d9=n"
# Idempotent: running twice with the same list produces identical output.
wb_reg_patch_dll_overrides() {
  local user_reg="$1"
  local dll_list="$2"

  if [[ ! -f "${user_reg}" ]]; then
    wb_log_error "wb_reg_patch_dll_overrides: registry file not found: ${user_reg}"
    return 1
  fi

  # Validate input to prevent registry injection.
  # Only allow alphanumeric characters, underscores, hyphens, dots, equals,
  # semicolons, and commas in the dll list.
  # Security-critical: use a variable for the pattern so bash does not
  # misparse semicolons inside [[ =~ ]] as statement separators.
  local _safe_pattern='^[A-Za-z0-9_;=,.-]+$'
  if ! [[ "${dll_list}" =~ ${_safe_pattern} ]]; then
    wb_log_error "wb_reg_patch_dll_overrides: invalid characters in dll_list: ${dll_list}"
    return 1
  fi

  # Ensure the [Software\\Wine\\DllOverrides] section exists.
  if ! grep -q '^\[Software\\\\Wine\\\\DllOverrides\]' "${user_reg}"; then
    printf '\n[Software\\\\Wine\\\\DllOverrides]\n' >> "${user_reg}"
    wb_log_info "Created [Software\\Wine\\DllOverrides] section in ${user_reg}"
  fi

  local IFS_SAVE="${IFS}"
  IFS=';' read -ra entries <<< "${dll_list}"
  IFS="${IFS_SAVE}"

  local entry
  for entry in "${entries[@]}"; do
    [[ -n "${entry}" ]] || continue
    local dll_name="${entry%%=*}"
    local dll_mode="${entry##*=}"

    # Remove existing entry for this DLL (idempotency).
    sed -i "/^\"${dll_name}\"=/d" "${user_reg}"

    # Add new entry immediately after the section header.
    sed -i "/^\[Software\\\\\\\\Wine\\\\\\\\DllOverrides\]/a \"${dll_name}\"=\"${dll_mode}\"" \
      "${user_reg}"
  done

  wb_log_info "DLL overrides set in ${user_reg}: ${dll_list}"
}

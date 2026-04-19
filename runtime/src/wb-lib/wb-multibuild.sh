#!/usr/bin/env bash
set -euo pipefail

# wb-multibuild.sh — M9 multi-build / distro-switching support
# Public API:
#   wb_multibuild_enabled
#   wb_runtime_resolve <name>
#   wb_multibuild_reconcile_switch <prefix_path> <new_dist_path>
#   wb_prefix_history_print <prefix_path>

# ---------------------------------------------------------------------------
# wb_multibuild_enabled
# Returns 0 if WB_MULTIBUILD=1, else 1.
# ---------------------------------------------------------------------------
wb_multibuild_enabled() {
  [[ "${WB_MULTIBUILD:-0}" == "1" ]]
}

# ---------------------------------------------------------------------------
# wb_runtime_resolve <name>
# Resolve a runtime NAME to an absolute dist path.
# Resolution order (first match wins):
#   1. $WB_HOME/dist/<NAME>/ directory exists   (native dist)
#   2. plugins/runtimes.d/<NAME>.json "path"    (external plugin)
#   3. WINE-BLEEDING alias symlink target        (stable alias fallback)
# Returns empty + exit 1 if nothing matches.
# ---------------------------------------------------------------------------
wb_runtime_resolve() {
  local name="$1"

  if [[ -z "${name}" ]]; then
    echo "wb_runtime_resolve: name must not be empty" >&2
    return 1
  fi

  local wb_home
  wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  local dist_dir="${wb_home}/dist"

  # Step 1: If a dist directory exists directly, prefer it (native wins).
  if [[ -d "${dist_dir}/${name}" ]]; then
    printf '%s' "${dist_dir}/${name}"
    return 0
  fi

  # Step 2: Check external plugin registry (plugins/runtimes.d/*.json).
  # wb-runtimes.sh must already be sourced by the caller.
  if declare -f wb_runtimes_plugin_resolve >/dev/null 2>&1; then
    local plugin_path
    plugin_path="$(wb_runtimes_plugin_resolve "${name}" 2>/dev/null || true)"
    if [[ -n "${plugin_path}" ]]; then
      printf '%s' "${plugin_path}"
      return 0
    fi
  fi

  # Step 3: WINE-BLEEDING is the stable alias; resolve its symlink target.
  if [[ "${name}" == "WINE-BLEEDING" ]]; then
    local alias_path="${dist_dir}/WINE-BLEEDING"
    if [[ -L "${alias_path}" ]] || [[ -d "${alias_path}" ]]; then
      local resolved
      resolved="$(readlink -f "${alias_path}" 2>/dev/null || true)"
      if [[ -n "${resolved}" && -d "${resolved}" ]]; then
        printf '%s' "${resolved}"
        return 0
      fi
    fi
  fi

  echo "wb_runtime_resolve: runtime '${name}' not found in ${dist_dir} or plugin registry" >&2
  return 1
}

# ---------------------------------------------------------------------------
# _wb_dist_major_version <dist_path>
# Read wine_major_version from <dist_path>/.wb_dist_meta.
# Falls back to "unknown" if the file or key is absent.
# ---------------------------------------------------------------------------
_wb_dist_major_version() {
  local dist_path="$1"
  local meta="${dist_path}/.wb_dist_meta"
  if [[ ! -f "${meta}" ]]; then
    echo "unknown"
    return 0
  fi
  local ver
  ver="$(jq -r '.wine_major_version // empty' "${meta}" 2>/dev/null || true)"
  if [[ -z "${ver}" ]]; then
    echo "unknown"
    return 0
  fi
  printf '%s' "${ver}"
}

# ---------------------------------------------------------------------------
# wb_multibuild_reconcile_switch <prefix_path> <new_dist_path>
# Implements the W3 §11.2 decision tree.
# Exit codes:
#   0  — switch completed (or no-op)
#   1  — error (bad args, missing dist, reconcile failure)
#  42  — consent required (different major version, no --yes-wineboot or env flag)
# ---------------------------------------------------------------------------
wb_multibuild_reconcile_switch() {
  local prefix_path="$1"
  local new_dist_path="$2"

  if [[ ! -d "${prefix_path}" ]]; then
    echo "wb_multibuild_reconcile_switch: prefix path '${prefix_path}' does not exist" >&2
    return 1
  fi

  if [[ ! -d "${new_dist_path}" ]]; then
    echo "wb_multibuild_reconcile_switch: dist path '${new_dist_path}' does not exist" >&2
    return 1
  fi

  local sentinel="${prefix_path}/.wb_runtime"
  if [[ ! -f "${sentinel}" ]]; then
    echo "wb_multibuild_reconcile_switch: no .wb_runtime sentinel at ${prefix_path}" >&2
    return 1
  fi

  # Step 1: read current runtime from sentinel
  local current_runtime
  current_runtime="$(jq -r '.current_runtime // empty' "${sentinel}" 2>/dev/null || true)"
  if [[ -z "${current_runtime}" ]]; then
    # Treat first switch as coming from the runtime_alias value
    current_runtime="$(jq -r '.runtime_alias // empty' "${sentinel}" 2>/dev/null || true)"
  fi

  # Step 2: resolve new dist name (basename)
  local new_dist_name
  new_dist_name="$(basename "${new_dist_path}")"

  # Resolve current dist path from sentinel's runtime_target
  local current_dist_path
  current_dist_path="$(jq -r '.runtime_target // empty' "${sentinel}" 2>/dev/null || true)"

  # Step 2: check if new dist == current dist path (no-op)
  local new_dist_real current_dist_real
  new_dist_real="$(realpath -m "${new_dist_path}")"
  if [[ -n "${current_dist_path}" ]]; then
    current_dist_real="$(realpath -m "${current_dist_path}" 2>/dev/null || echo "")"
    if [[ "${new_dist_real}" == "${current_dist_real}" ]]; then
      wb_log_info "wb_multibuild_reconcile_switch: dist unchanged (${new_dist_name}), no-op"
      return 0
    fi
  fi

  # Step 3: compare wine_major_version of new vs current dist
  local new_major current_major
  new_major="$(_wb_dist_major_version "${new_dist_path}")"
  if [[ -n "${current_dist_path}" && -d "${current_dist_path}" ]]; then
    current_major="$(_wb_dist_major_version "${current_dist_path}")"
  else
    # No current dist path recorded; treat as same-major (allow component redeploy)
    current_major="${new_major}"
  fi

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ "${new_major}" == "${current_major}" ]]; then
    # Step 4: Same major → reconcile components only, NO wineboot
    wb_log_info "wb_multibuild_reconcile_switch: same major (${new_major}), reconciling components only"

    # Update runtime_target in sentinel BEFORE reconcile so wb_prefix_reconcile
    # picks up the new dist path.
    _wb_multibuild_update_sentinel \
      "${prefix_path}" "${new_dist_path}" "${new_dist_name}" "${now_utc}" \
      "${current_runtime}"

    wb_prefix_reconcile "${prefix_path}"

    wb_log_info "wb_multibuild_reconcile_switch: switch to ${new_dist_name} complete (no wineboot)"
    return 0
  fi

  # Step 5: Different major → require consent
  if [[ "${WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE:-0}" != "1" && \
        "${WB_YES_WINEBOOT:-0}" != "1" ]]; then
    echo "wb run: major Wine version change detected (${current_major} -> ${new_major})." >&2
    echo "wb run: switching from '${current_runtime}' to '${new_dist_name}' requires wineboot -u." >&2
    echo "wb run: to proceed, add --yes-wineboot or set WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE=1." >&2
    return 42
  fi

  # Step 6: Consent given — update sentinel, run wineboot -u, then reconcile
  wb_log_info "wb_multibuild_reconcile_switch: major change (${current_major} -> ${new_major}), running wineboot -u"

  # Update runtime_target BEFORE wineboot
  _wb_multibuild_update_sentinel \
    "${prefix_path}" "${new_dist_path}" "${new_dist_name}" "${now_utc}" \
    "${current_runtime}"

  export WINEPREFIX="${prefix_path}"
  export WINEDEBUG="${WINEDEBUG:--all}"
  "${new_dist_path}/bin/wine" wineboot -u 2>/dev/null || true

  wb_prefix_reconcile "${prefix_path}"

  wb_log_info "wb_multibuild_reconcile_switch: switch to ${new_dist_name} complete (wineboot -u ran)"
  return 0
}

# ---------------------------------------------------------------------------
# _wb_multibuild_update_sentinel <prefix_path> <new_dist_path> <new_dist_name>
#                                <now_utc> <current_runtime>
# Atomically write updated sentinel with new runtime_target, current_runtime,
# and history[]. Preserves all existing sentinel fields.
# ---------------------------------------------------------------------------
_wb_multibuild_update_sentinel() {
  local prefix_path="$1"
  local new_dist_path="$2"
  local new_dist_name="$3"
  local now_utc="$4"
  local current_runtime="$5"

  local sentinel="${prefix_path}/.wb_runtime"
  local new_dist_real
  new_dist_real="$(realpath -m "${new_dist_path}")"

  # Read existing sentinel JSON; update fields via jq
  # Cap history retention (default 100). Prevents O(n) jq overhead on
  # long-lived high-churn prefixes and bounds JSON size.
  local max_history="${WB_HISTORY_MAX_ENTRIES:-100}"
  if ! [[ "${max_history}" =~ ^[1-9][0-9]*$ ]]; then
    max_history=100
  fi

  local updated_json
  updated_json="$(jq \
    --arg new_target "${new_dist_real}" \
    --arg new_name "${new_dist_name}" \
    --arg now_utc "${now_utc}" \
    --arg prev_runtime "${current_runtime}" \
    --argjson max_history "${max_history}" \
    '
    # Close the last open history entry (to_utc = now)
    # and append a new entry for the incoming runtime.
    .runtime_target = $new_target |
    .current_runtime = $new_name |
    .history = (
      (.history // []) |
      # Close the last entry that has to_utc == null
      map(if .to_utc == null then . + {"to_utc": $now_utc} else . end) |
      # Append new entry
      . + [{"runtime": $new_name, "from_utc": $now_utc, "to_utc": null}] |
      # Retain only the most recent $max_history entries
      if length > $max_history then .[length - $max_history :] else . end
    )
    ' "${sentinel}" 2>/dev/null)"

  wb_json_write_atomic "${sentinel}" "${updated_json}"
}

# ---------------------------------------------------------------------------
# wb_prefix_history_print <prefix_path>
# Pretty-print .wb_runtime.history[] as a table.
# ---------------------------------------------------------------------------
wb_prefix_history_print() {
  local prefix_path="$1"

  local sentinel="${prefix_path}/.wb_runtime"
  if [[ ! -f "${sentinel}" ]]; then
    echo "wb_prefix_history_print: no .wb_runtime at ${prefix_path}" >&2
    return 1
  fi

  local history_len
  history_len="$(jq '.history | length' "${sentinel}" 2>/dev/null || echo "0")"

  if [[ "${history_len}" == "0" || "${history_len}" == "null" ]]; then
    printf '%-28s %-28s %s\n' "FROM_UTC" "TO_UTC" "RUNTIME"
    echo "(no history recorded)"
    return 0
  fi

  printf '%-28s %-28s %s\n' "FROM_UTC" "TO_UTC" "RUNTIME"
  jq -r '.history[] | [.from_utc, (.to_utc // "active"), .runtime] | @tsv' "${sentinel}" \
    | while IFS=$'\t' read -r from_utc to_utc runtime_name; do
        printf '%-28s %-28s %s\n' "${from_utc}" "${to_utc}" "${runtime_name}"
      done
}

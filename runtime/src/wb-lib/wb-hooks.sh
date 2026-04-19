#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# wb-hooks.sh — Phase-based hook runner.
# wb_hooks_run <phase> — sources hooks in $WB_HOME/plugins/hooks.d/ in
# sorted order, in the CURRENT shell so hooks can export vars.
# ---------------------------------------------------------------------------

# Valid phase names per W3 §10.1
_WB_VALID_PHASES="pre-reconcile pre-materialize post-materialize pre-exec post-exec"

# Hook filename pattern: must match this to be executed.
# ^[A-Za-z0-9_.-]+\.(pre-reconcile|pre-materialize|post-materialize|pre-exec|post-exec)\.sh$
_WB_HOOK_FILENAME_RE='^[A-Za-z0-9_.-]+\.(pre-reconcile|pre-materialize|post-materialize|pre-exec|post-exec)\.sh$'

wb_hooks_run() {
  local phase="$1"

  # Validate the phase name
  local valid_phase_found=0
  local vp
  for vp in ${_WB_VALID_PHASES}; do
    if [[ "${phase}" == "${vp}" ]]; then
      valid_phase_found=1
      break
    fi
  done

  if [[ "${valid_phase_found}" -eq 0 ]]; then
    wb_log_error "wb_hooks_run: invalid phase '${phase}' (valid: ${_WB_VALID_PHASES})"
    return 1
  fi

  # SECURITY: the hooks directory is pinned at the start of the dispatch by
  # `cmd_run` via _WB_HOOKS_DIR_PIN. A hook that exports WB_HOME to an
  # attacker-controlled path cannot redirect subsequent hook loading.
  local hooks_dir="${_WB_HOOKS_DIR_PIN:-${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}/plugins/hooks.d}"

  # No hooks dir → silently return success
  if [[ ! -d "${hooks_dir}" ]]; then
    return 0
  fi

  # Collect matching hook files in sorted order
  local -a hook_files=()
  local f
  while IFS= read -r f; do
    hook_files+=("${f}")
  done < <(find "${hooks_dir}" -maxdepth 1 -type f -o -maxdepth 1 -type l 2>/dev/null \
    | sort)

  # Also need to explicitly handle the case where find returns nothing
  if [[ "${#hook_files[@]}" -eq 0 ]]; then
    return 0
  fi

  local hook_path hook_name
  for hook_path in "${hook_files[@]}"; do
    hook_name="$(basename "${hook_path}")"

    # Skip .example files (shipped documentation, not active hooks)
    if [[ "${hook_name}" == *.example ]]; then
      [[ "${WB_DEBUG:-0}" == "1" ]] && wb_log_debug "wb_hooks_run: skipping example: ${hook_name}"
      continue
    fi

    # Validate filename pattern — anything that doesn't match is silently skipped
    if ! [[ "${hook_name}" =~ ${_WB_HOOK_FILENAME_RE} ]]; then
      [[ "${WB_DEBUG:-0}" == "1" ]] && wb_log_debug "wb_hooks_run: skipping invalid filename: ${hook_name}"
      continue
    fi

    # Only run hooks for the requested phase
    if ! [[ "${hook_name}" == *".${phase}.sh" ]]; then
      continue
    fi

    # Security: if it's a symlink, verify it resolves inside hooks_dir
    if [[ -L "${hook_path}" ]]; then
      local resolved_target
      resolved_target="$(readlink -f "${hook_path}" 2>/dev/null || true)"
      local resolved_hooks_dir
      resolved_hooks_dir="$(readlink -f "${hooks_dir}" 2>/dev/null || echo "${hooks_dir}")"
      if [[ "${resolved_target}" != "${resolved_hooks_dir}/"* ]]; then
        wb_log_warn "wb_hooks_run: skipping symlink outside hooks.d: ${hook_path} -> ${resolved_target}"
        continue
      fi
    fi

    # Must be a regular file (or valid symlink to one — checked above)
    if [[ ! -f "${hook_path}" ]]; then
      [[ "${WB_DEBUG:-0}" == "1" ]] && wb_log_debug "wb_hooks_run: skipping non-regular file: ${hook_name}"
      continue
    fi

    if [[ "${WB_DEBUG:-0}" == "1" ]]; then
      wb_log_debug "wb_hooks_run: entering hook ${hook_path}"
    fi

    # Run the hook in a subshell so that:
    # (a) an `exit N` in the hook doesn't kill the parent shell, and
    # (b) we can cleanly capture the exit code even under set -e.
    # After the subshell completes, we re-import any WB_* exports it made
    # from a temporary env-dump file so that hooks can still "export vars"
    # across phases (the spec requirement).
    local _hook_env_dump
    _hook_env_dump="$(mktemp)"

    local hook_exit=0
    set +e
    (
      set -euo pipefail
      # shellcheck disable=SC1090
      source "${hook_path}"
      # On success, dump WB_*/WINE*/DXVK_* exports for parent re-import
      env | grep -E '^(WB_[A-Z0-9_]+|WINE[A-Z0-9_]*|DXVK_[A-Z0-9_]+|VKD3D_[A-Z0-9_]+|STAGING_[A-Z0-9_]+)=' \
        >> "${_hook_env_dump}" 2>/dev/null || true
    )
    hook_exit=$?
    set -e

    if [[ "${hook_exit}" -ne 0 ]]; then
      rm -f "${_hook_env_dump}"
      wb_log_error "hook ${hook_path}: failed with exit ${hook_exit}"
      return "${hook_exit}"
    fi

    # Re-import exports from the hook subshell into the current shell
    local _pair _var _val
    while IFS= read -r _pair; do
      [[ -n "${_pair}" ]] || continue
      _var="${_pair%%=*}"
      _val="${_pair#*=}"
      export "${_var}=${_val}"
    done < "${_hook_env_dump}"
    rm -f "${_hook_env_dump}"

    if [[ "${WB_DEBUG:-0}" == "1" ]]; then
      wb_log_debug "wb_hooks_run: hook ${hook_path} exited 0"
    fi
  done

  return 0
}

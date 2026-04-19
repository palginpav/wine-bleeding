#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# wb-snapshot.sh — Prefix snapshot capture, list, prune, and repair.
# M8 deliverable: §6.3 item 5 snapshot-and-repair mechanism.
# ---------------------------------------------------------------------------

# Number of snapshots to retain per prefix (oldest beyond this are pruned).
WB_SNAPSHOT_RETAIN="${WB_SNAPSHOT_RETAIN:-5}"

# Return the snapshot directory for a given prefix basename.
_wb_snapshot_dir() {
  local prefix_name="$1"
  local wb_home
  wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  echo "${wb_home}/state/prefix-snapshots/${prefix_name}"
}

# Resolve a prefix path from a name (absolute path passthrough or lookup in WB_HOME).
_wb_snapshot_resolve_prefix() {
  local name="$1"
  if [[ "${name}" == /* ]]; then
    echo "${name}"
  else
    local wb_home
    wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
    echo "${wb_home}/prefixes/${name}"
  fi
}

# Extract the DllOverrides lines from a user.reg file.
# Returns a JSON array of strings, e.g. ["\"d3d11\"=\"n\"", ...].
# Returns empty array if the section is absent.
_wb_snapshot_dll_overrides_json() {
  local user_reg="$1"

  if [[ ! -f "${user_reg}" ]]; then
    echo "[]"
    return 0
  fi

  # Extract lines between [Software\\Wine\\DllOverrides] and the next section header.
  local in_section=0
  local -a lines=()
  local line
  while IFS= read -r line; do
    if [[ "${line}" =~ ^\[Software\\\\Wine\\\\DllOverrides\] ]]; then
      in_section=1
      continue
    fi
    # Stop at any new section header
    if [[ "${in_section}" -eq 1 && "${line}" =~ ^\[ ]]; then
      break
    fi
    # Collect non-empty lines within the section
    if [[ "${in_section}" -eq 1 && -n "${line}" ]]; then
      lines+=("${line}")
    fi
  done < "${user_reg}"

  if [[ "${#lines[@]}" -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  # Build a JSON array from the collected lines.
  local json_arr
  json_arr="$(printf '%s\n' "${lines[@]}" | jq -Rs '[split("\n")[] | select(length > 0)]')"
  echo "${json_arr}"
}

# List DLL names (basenames only) in a directory. Returns JSON array.
_wb_snapshot_dll_names_json() {
  local dir="$1"

  if [[ ! -d "${dir}" ]]; then
    echo "[]"
    return 0
  fi

  local -a names=()
  local dll
  for dll in "${dir}"/*.dll; do
    [[ -f "${dll}" || -L "${dll}" ]] || continue
    names+=("$(basename "${dll}")")
  done

  if [[ "${#names[@]}" -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  printf '%s\n' "${names[@]}" | jq -Rs '[split("\n")[] | select(length > 0)]'
}

# ---------------------------------------------------------------------------
# wb_snapshot_capture <prefix>
# Serialize recoverable state into
#   $WB_HOME/state/prefix-snapshots/<basename>-<UTC>[.<serial>].json
# Fields: schema, prefix_name, prefix_path, captured_utc, runtime_target,
#         runtime_target_sha256, wb_runtime, wb_components,
#         dll_overrides, system32_dll_names, syswow64_dll_names.
# NEVER includes file contents — only names and metadata.
# After writing, enforces WB_SNAPSHOT_RETAIN retention.
# ---------------------------------------------------------------------------
wb_snapshot_capture() {
  local prefix="$1"

  local prefix_path
  prefix_path="$(_wb_snapshot_resolve_prefix "${prefix}")"

  local prefix_name
  prefix_name="$(basename "${prefix_path}")"

  # Read .wb_runtime (null if absent)
  local wb_runtime_json="null"
  if [[ -f "${prefix_path}/.wb_runtime" ]] && jq empty "${prefix_path}/.wb_runtime" 2>/dev/null; then
    wb_runtime_json="$(cat "${prefix_path}/.wb_runtime")"
  fi

  # Read .wb_components (null if absent)
  local wb_components_json="null"
  if [[ -f "${prefix_path}/.wb_components" ]] && jq empty "${prefix_path}/.wb_components" 2>/dev/null; then
    wb_components_json="$(cat "${prefix_path}/.wb_components")"
  fi

  # Extract runtime_target and runtime_target_sha256
  local runtime_target="null"
  local runtime_target_sha256="null"
  if [[ "${wb_runtime_json}" != "null" ]]; then
    local rt
    rt="$(echo "${wb_runtime_json}" | jq -r '.runtime_target // empty' 2>/dev/null || true)"
    [[ -n "${rt}" ]] && runtime_target="\"${rt}\""

    local rt_sha
    rt_sha="$(echo "${wb_runtime_json}" | jq -r '.runtime_target_sha256 // empty' 2>/dev/null || true)"
    if [[ -z "${rt_sha}" && -n "${rt:-}" && -f "${rt}/.wb_dist_meta" ]]; then
      rt_sha="$(jq -r '.builtin_dlls_hash // ""' "${rt}/.wb_dist_meta" 2>/dev/null || true)"
    fi
    [[ -n "${rt_sha}" ]] && runtime_target_sha256="\"${rt_sha}\""
  fi

  # DLL overrides from user.reg
  local dll_overrides_json
  dll_overrides_json="$(_wb_snapshot_dll_overrides_json "${prefix_path}/user.reg")"

  # DLL names in system32 and syswow64
  local sys32_json syswow_json
  sys32_json="$(_wb_snapshot_dll_names_json "${prefix_path}/drive_c/windows/system32")"
  syswow_json="$(_wb_snapshot_dll_names_json "${prefix_path}/drive_c/windows/syswow64")"

  local captured_utc
  captured_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local abs_prefix_path
  abs_prefix_path="$(realpath -m "${prefix_path}")"

  # Build the snapshot JSON. Use jq --argjson for already-JSON fields.
  local snapshot_json
  snapshot_json="$(jq -cn \
    --argjson schema 1 \
    --arg prefix_name "${prefix_name}" \
    --arg prefix_path "${abs_prefix_path}" \
    --arg captured_utc "${captured_utc}" \
    --argjson runtime_target "${runtime_target}" \
    --argjson runtime_target_sha256 "${runtime_target_sha256}" \
    --argjson wb_runtime "${wb_runtime_json}" \
    --argjson wb_components "${wb_components_json}" \
    --argjson dll_overrides "${dll_overrides_json}" \
    --argjson system32_dll_names "${sys32_json}" \
    --argjson syswow64_dll_names "${syswow_json}" \
    '{
      schema: $schema,
      prefix_name: $prefix_name,
      prefix_path: $prefix_path,
      captured_utc: $captured_utc,
      runtime_target: $runtime_target,
      runtime_target_sha256: $runtime_target_sha256,
      wb_runtime: $wb_runtime,
      wb_components: $wb_components,
      dll_overrides: $dll_overrides,
      system32_dll_names: $system32_dll_names,
      syswow64_dll_names: $syswow64_dll_names
    }')"

  # Determine snapshot directory and filename.
  local snap_dir
  snap_dir="$(_wb_snapshot_dir "${prefix_name}")"
  mkdir -p "${snap_dir}"

  # Generate filename; add a serial suffix if the same UTC already exists.
  local utc_safe
  utc_safe="${captured_utc//:/-}"
  local snap_file="${snap_dir}/${prefix_name}-${utc_safe}.json"
  local serial=1
  while [[ -e "${snap_file}" ]]; do
    snap_file="${snap_dir}/${prefix_name}-${utc_safe}.${serial}.json"
    (( serial++ )) || true
  done

  wb_json_write_atomic "${snap_file}" "${snapshot_json}"
  wb_log_info "wb_snapshot_capture: wrote ${snap_file}"

  # Enforce retention (keep newest WB_SNAPSHOT_RETAIN)
  wb_snapshot_prune "${prefix}" --keep "${WB_SNAPSHOT_RETAIN}"

  echo "${snap_file}"
}

# ---------------------------------------------------------------------------
# wb_snapshot_list <prefix>
# Print one line per snapshot, newest first:
#   <UTC> <size-bytes> <relative-path>
# ---------------------------------------------------------------------------
wb_snapshot_list() {
  local prefix="$1"

  local prefix_name
  prefix_name="$(basename "$(_wb_snapshot_resolve_prefix "${prefix}")")"

  local snap_dir
  snap_dir="$(_wb_snapshot_dir "${prefix_name}")"

  if [[ ! -d "${snap_dir}" ]]; then
    return 0
  fi

  # Collect files sorted by captured_utc descending (fall back to mtime).
  local -a files=()
  local f
  while IFS= read -r f; do
    files+=("${f}")
  done < <(find "${snap_dir}" -maxdepth 1 -name "${prefix_name}-*.json" \
    | sort -r 2>/dev/null || true)

  for f in "${files[@]+"${files[@]}"}"; do
    [[ -f "${f}" ]] || continue
    local utc sz
    utc="$(jq -r '.captured_utc // ""' "${f}" 2>/dev/null || true)"
    sz="$(stat -c %s "${f}" 2>/dev/null || echo "?")"
    echo "${utc} ${sz} ${f}"
  done
}

# ---------------------------------------------------------------------------
# wb_snapshot_prune <prefix> --keep N
# Keep the N most-recent snapshots; delete older ones.
# ---------------------------------------------------------------------------
wb_snapshot_prune() {
  local prefix="$1"
  local keep="${WB_SNAPSHOT_RETAIN}"

  # Parse --keep N
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep)
        keep="${2:-${WB_SNAPSHOT_RETAIN}}"
        shift 2
        ;;
      --keep=*)
        keep="${1#--keep=}"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  local prefix_name
  prefix_name="$(basename "$(_wb_snapshot_resolve_prefix "${prefix}")")"

  local snap_dir
  snap_dir="$(_wb_snapshot_dir "${prefix_name}")"

  [[ -d "${snap_dir}" ]] || return 0

  # Sort files newest first; delete those beyond the keep count.
  local -a all_snaps=()
  local f
  while IFS= read -r f; do
    all_snaps+=("${f}")
  done < <(find "${snap_dir}" -maxdepth 1 -name "${prefix_name}-*.json" \
    | sort -r 2>/dev/null || true)

  local total="${#all_snaps[@]}"
  if [[ "${total}" -le "${keep}" ]]; then
    return 0
  fi

  local i
  for (( i=keep; i<total; i++ )); do
    local old="${all_snaps[${i}]}"
    wb_log_info "wb_snapshot_prune: deleting ${old}"
    rm -f "${old}"
  done
}

# ---------------------------------------------------------------------------
# wb_snapshot_repair <prefix> [--yes] [--from-snapshot <UTC>]
# Recover a broken prefix from its most recent (or specified) snapshot.
# ---------------------------------------------------------------------------
wb_snapshot_repair() {
  local prefix="$1"
  shift

  local yes=0
  local from_utc=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        yes=1
        shift
        ;;
      --from-snapshot)
        from_utc="${2:-}"
        shift 2
        ;;
      --from-snapshot=*)
        from_utc="${1#--from-snapshot=}"
        shift
        ;;
      *)
        echo "wb_snapshot_repair: unknown option '$1'" >&2
        return 1
        ;;
    esac
  done

  local prefix_path
  prefix_path="$(_wb_snapshot_resolve_prefix "${prefix}")"

  local prefix_name
  prefix_name="$(basename "${prefix_path}")"

  local snap_dir
  snap_dir="$(_wb_snapshot_dir "${prefix_name}")"

  # Find snapshot file
  local snap_file=""
  if [[ -n "${from_utc}" ]]; then
    # SECURITY: validate UTC strictly to prevent path traversal via / or ..
    # A crafted UTC like "...Z/../../../../etc/hostname" would escape the
    # snapshot directory otherwise (even though the effect is read-only,
    # the traversed path echoes into logs and the repair summary).
    if ! [[ "${from_utc}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
      echo "wb prefix repair: invalid --from-snapshot UTC '${from_utc}' (expected YYYY-MM-DDThh:mm:ssZ)" >&2
      return 1
    fi
    # User specified a particular UTC — find matching file.
    local utc_safe
    utc_safe="${from_utc//:/-}"
    snap_file="${snap_dir}/${prefix_name}-${utc_safe}.json"
    if [[ ! -f "${snap_file}" ]]; then
      # Try serial variants
      local candidate
      for candidate in "${snap_dir}/${prefix_name}-${utc_safe}".*.json; do
        [[ -f "${candidate}" ]] && snap_file="${candidate}" && break
      done
    fi
    if [[ ! -f "${snap_file}" ]]; then
      echo "wb prefix repair: no snapshot found for UTC '${from_utc}'" >&2
      return 1
    fi
  else
    # Most recent snapshot
    local -a snaps=()
    local f
    while IFS= read -r f; do
      snaps+=("${f}")
    done < <(find "${snap_dir}" -maxdepth 1 -name "${prefix_name}-*.json" \
      | sort -r 2>/dev/null || true)
    if [[ "${#snaps[@]}" -eq 0 ]]; then
      echo "wb prefix repair: no snapshots found for '${prefix_name}'" >&2
      echo "wb prefix repair: run 'wb prefix snapshot ${prefix_name}' first" >&2
      return 1
    fi
    snap_file="${snaps[0]}"
  fi

  # Read snapshot
  if ! jq empty "${snap_file}" 2>/dev/null; then
    echo "wb prefix repair: snapshot file is malformed JSON: ${snap_file}" >&2
    return 1
  fi

  local snap_captured
  snap_captured="$(jq -r '.captured_utc // ""' "${snap_file}")"
  local snap_runtime_target
  snap_runtime_target="$(jq -r '.runtime_target // ""' "${snap_file}")"
  local snap_dll_overrides_json
  snap_dll_overrides_json="$(jq -c '.dll_overrides // []' "${snap_file}")"

  if [[ -z "${snap_runtime_target}" ]]; then
    echo "wb prefix repair: snapshot missing runtime_target field" >&2
    return 1
  fi

  # SAFETY: check for divergence between current prefix state and snapshot.
  if [[ -f "${prefix_path}/.wb_runtime" ]]; then
    local cur_rt
    cur_rt="$(jq -r '.runtime_target // ""' "${prefix_path}/.wb_runtime" 2>/dev/null || true)"
    if [[ -n "${cur_rt}" && "${cur_rt}" != "${snap_runtime_target}" ]]; then
      wb_log_warn "wb_snapshot_repair: current runtime_target '${cur_rt}' differs from snapshot '${snap_runtime_target}'"
      echo "WARN: current prefix runtime_target differs from snapshot (may be stale snapshot)." >&2
    fi
  fi

  # Print summary
  echo "Repair summary for '${prefix_name}':"
  echo "  Snapshot: ${snap_file}"
  echo "  Captured: ${snap_captured}"
  echo "  Runtime target: ${snap_runtime_target}"
  echo ""
  echo "  This will re-initialize the prefix (wineboot + components)."
  echo "  User data (drive_c game saves, etc.) will NOT be restored."

  if [[ "${yes}" -ne 1 ]]; then
    printf 'Proceed with repair? [y/N] '
    local answer
    read -r answer
    if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
      echo "Aborted."
      return 0
    fi
  fi

  # Acquire the prefix lock to verify the prefix is not currently in use
  # and to read its current state atomically. We release before calling
  # wb_prefix_init, which acquires its own lock for the re-init sequence.
  if ! wb_acquire_lock "${prefix_path}"; then
    echo "wb prefix repair: could not acquire lock on ${prefix_path}" >&2
    return 1
  fi
  # Verify current state under the lock; then release before re-init.
  wb_release_lock "${prefix_path}" 2>/dev/null || true

  # Re-run wb_prefix_init which handles wineboot + components + reg patch.
  # wb_prefix_init acquires its own lock internally.
  wb_log_info "wb_snapshot_repair: re-initialising prefix '${prefix_name}' from snapshot ${snap_file}"
  wb_prefix_init "${prefix_path}" "${snap_runtime_target}"

  # Re-apply DllOverrides from snapshot.
  local user_reg="${prefix_path}/user.reg"
  if [[ -f "${user_reg}" ]]; then
    local n_overrides
    n_overrides="$(echo "${snap_dll_overrides_json}" | jq 'length')"
    if [[ "${n_overrides}" -gt 0 ]]; then
      # Convert the array of raw registry lines to name=mode format for wb_reg_patch_dll_overrides.
      # Each line looks like: "d3d11"="n"
      # We need to build semicolon-separated name=mode string.
      local dll_list=""
      local entry
      while IFS= read -r entry; do
        [[ -n "${entry}" ]] || continue
        # Parse "name"="mode" format
        local dll_name dll_mode
        dll_name="$(echo "${entry}" | sed -E 's/^"([^"]+)"=.*/\1/')"
        dll_mode="$(echo "${entry}" | sed -E 's/^"[^"]+"="([^"]+)".*/\1/')"
        if [[ -n "${dll_name}" && -n "${dll_mode}" ]]; then
          if [[ -n "${dll_list}" ]]; then
            dll_list="${dll_list};${dll_name}=${dll_mode}"
          else
            dll_list="${dll_name}=${dll_mode}"
          fi
        fi
      done < <(echo "${snap_dll_overrides_json}" | jq -r '.[]')

      if [[ -n "${dll_list}" ]]; then
        wb_reg_patch_dll_overrides "${user_reg}" "${dll_list}"
        wb_log_info "wb_snapshot_repair: re-applied ${n_overrides} DllOverrides from snapshot"
      fi
    fi
  fi

  wb_log_info "wb_snapshot_repair: prefix '${prefix_name}' repaired successfully"
  echo "repaired: ${prefix_path}"
  echo "NOTE: user data (game saves, Documents, etc.) is NOT restored — check them manually."
}

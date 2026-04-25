#!/usr/bin/env bash
# wb-gui-detection.sh — post-install detection subsystem for wb-gui (Phase A / v1.6.0)
# Sourced by wb-gui; never executed directly.
#
# Implements dual-mechanism detection:
#   M1: Start Menu .lnk diff (python3 parser with bash-strings fallback)
#   M2: C:/Program Files + C:/Program Files (x86) top-level dir diff
#
# Storage: $WB_HOME/detection/<prefix-name>/ (ephemeral — purged after use)
#
# Public API:
#   wb_detect_snapshot_before <prefix_name>              -> path to before.json
#   wb_detect_diff_after <prefix_name> <before_json>    -> JSON array of candidates
#   wb_detect_add_candidates <prefix_name> <candidates> -> (interactive, side effects)
#   wb_detect_purge <prefix_name>                       -> (cleanup)
#   wb_detect_sweep_stale [max_age_hours=24]            -> (startup cleanup)
set -euo pipefail

# ---------------------------------------------------------------------------
# Internal: resolve detection snapshot directory for a prefix
# ---------------------------------------------------------------------------
_wb_detect_snapshot_dir() {
  local prefix_name="${1:-}"
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  echo "${wb_home}/detection/${prefix_name}"
}

# ---------------------------------------------------------------------------
# Internal: resolve prefix path on host filesystem
# Absolute path passthrough; otherwise looks under $WB_HOME/prefixes/<name>.
# ---------------------------------------------------------------------------
_wb_detect_resolve_prefix_path() {
  local prefix_name="${1:-}"
  if [[ "${prefix_name}" == /* ]]; then
    echo "${prefix_name}"
  else
    local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
    echo "${wb_home}/prefixes/${prefix_name}"
  fi
}

# ---------------------------------------------------------------------------
# Internal: scan .lnk files within a prefix's Start Menu directories.
# Returns a JSON array of absolute .lnk paths.
# Uses null-delimited find output piped through jq to handle names with spaces.
# ---------------------------------------------------------------------------
_wb_detect_scan_lnks() {
  local prefix_path="${1:-}"
  local drive_c="${prefix_path}/drive_c"

  if [[ ! -d "${drive_c}" ]]; then
    echo "[]"
    return 0
  fi

  # Collect all .lnk paths from the known Start Menu locations.
  # We use find with -print0 and pass through jq to build a JSON array safely.
  local -a find_dirs=()

  # System-wide: ProgramData Start Menu
  local pdata="${drive_c}/ProgramData/Microsoft/Windows/Start Menu/Programs"
  [[ -d "${pdata}" ]] && find_dirs+=("${pdata}")

  # Per-user: enumerate drive_c/users/* (skip Public and Default)
  local users_dir="${drive_c}/users"
  if [[ -d "${users_dir}" ]]; then
    local udir
    for udir in "${users_dir}"/*/; do
      [[ -d "${udir}" ]] || continue
      local uname
      uname="$(basename "${udir}")"
      [[ "${uname}" == "Public" || "${uname}" == "Default" ]] && continue
      local sm="${udir}AppData/Roaming/Microsoft/Windows/Start Menu/Programs"
      [[ -d "${sm}" ]] && find_dirs+=("${sm}")
    done

    # Public Start Menu
    local pub_sm="${users_dir}/Public/Start Menu/Programs"
    [[ -d "${pub_sm}" ]] && find_dirs+=("${pub_sm}")
    local pub_sm2="${users_dir}/Public/AppData/Roaming/Microsoft/Windows/Start Menu/Programs"
    [[ -d "${pub_sm2}" ]] && find_dirs+=("${pub_sm2}")
  fi

  if [[ "${#find_dirs[@]}" -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  # Build JSON array from null-delimited find output
  find "${find_dirs[@]}" -type f -iname "*.lnk" -print0 2>/dev/null \
    | jq -Rs '[
        split("\u0000")[] | select(length > 0)
      ]' \
    || echo "[]"
}

# ---------------------------------------------------------------------------
# Internal: scan top-level directories in Program Files areas.
# Returns JSON: {"pf": [...], "pf_x86": [...]}
# ---------------------------------------------------------------------------
_wb_detect_scan_pf_dirs() {
  local prefix_path="${1:-}"
  local drive_c="${prefix_path}/drive_c"

  local pf="${drive_c}/Program Files"
  local pf86="${drive_c}/Program Files (x86)"

  local pf_json="[]"
  local pf86_json="[]"

  if [[ -d "${pf}" ]]; then
    pf_json="$(find "${pf}" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null \
      | jq -Rs '[split("\u0000")[] | select(length > 0)]' || echo "[]")"
  fi

  if [[ -d "${pf86}" ]]; then
    pf86_json="$(find "${pf86}" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null \
      | jq -Rs '[split("\u0000")[] | select(length > 0)]' || echo "[]")"
  fi

  jq -cn --argjson pf "${pf_json}" --argjson pf86 "${pf86_json}" \
    '{pf: $pf, pf_x86: $pf86}'
}

# ---------------------------------------------------------------------------
# Internal: parse a single .lnk file.
# Tries python3 parser first; falls back to bash-strings method.
# Returns JSON: {"target_path": "...", "display_name": "..."} or exits 1.
# ---------------------------------------------------------------------------
_wb_detect_parse_lnk() {
  local lnk_path="${1:-}"

  if [[ ! -f "${lnk_path}" ]]; then
    echo "wb-detect: lnk file not found: ${lnk_path}" >&2
    return 1
  fi

  # Locate wb-lnk-parse.py relative to this script or in standard locations
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local lnk_parser=""
  local candidate
  for candidate in \
      "${script_dir}/../../libexec/wb-lnk-parse.py" \
      "/usr/lib/wine-bleeding/libexec/wb-lnk-parse.py" \
      "/usr/local/lib/wine-bleeding/libexec/wb-lnk-parse.py"
  do
    if [[ -f "${candidate}" ]]; then
      lnk_parser="${candidate}"
      break
    fi
  done

  # Try python3 parser
  if [[ -n "${lnk_parser}" ]] && command -v python3 >/dev/null 2>&1; then
    local result
    if result="$(python3 "${lnk_parser}" "${lnk_path}" 2>/dev/null)"; then
      # Validate output is JSON with required keys
      if printf '%s' "${result}" | jq -e '.target_path' >/dev/null 2>&1; then
        printf '%s' "${result}"
        return 0
      fi
    fi
    # Parser ran but produced bad output — fall through to bash fallback
    echo "wb-detect: python3 lnk parser failed for '${lnk_path}', trying bash fallback" >&2
  elif ! command -v python3 >/dev/null 2>&1; then
    echo "wb-detect: python3 not found — using bash-strings fallback (install python3 for better accuracy)" >&2
  fi

  # Bash-strings fallback: extract first line matching a Windows drive path
  _wb_detect_parse_lnk_bash_fallback "${lnk_path}"
}

# ---------------------------------------------------------------------------
# Internal: bash-strings fallback .lnk parser.
# Accuracy ~60% — picks the first plausible Windows path found in the binary.
# ---------------------------------------------------------------------------
_wb_detect_parse_lnk_bash_fallback() {
  local lnk_path="${1:-}"

  # Extract printable ASCII from the binary; grep for Windows drive paths.
  # Pattern: drive letter + colon + backslash + path chars + .exe
  # In PCRE: [A-Za-z]:[\\\\].+?\.exe  (four backslashes = literal backslash in char class)
  local win_path
  win_path="$(tr -cd '\11\12\15\40-\176' < "${lnk_path}" 2>/dev/null \
    | grep -m1 -oP '[A-Za-z]:[\\\\].+?\.exe' 2>/dev/null || true)"
  if [[ -z "${win_path}" ]]; then
    # Simpler fallback for systems without PCRE grep
    win_path="$(tr -cd '\11\12\15\40-\176' < "${lnk_path}" 2>/dev/null \
      | grep -m1 -o '[A-Za-z]:[^ ]*\.exe' 2>/dev/null || true)"
  fi

  if [[ -z "${win_path}" ]]; then
    echo "wb-detect: bash fallback could not extract path from '${lnk_path}'" >&2
    return 1
  fi

  # Extract basename from Windows path (backslash separator, not forward slash)
  local display_name
  # Get the last component after the last backslash
  display_name="${win_path##*\\}"
  # Strip .exe suffix (case-insensitive)
  display_name="${display_name%.exe}"
  display_name="${display_name%.EXE}"

  jq -cn --arg target "${win_path}" --arg name "${display_name}" \
    '{target_path: $target, display_name: $name}'
}

# ---------------------------------------------------------------------------
# Internal: pick the main executable in a new Program Files directory.
# Implements the PortProton heuristic: largest non-uninstaller exe within
# depth 3, preferring exes at the top level of the dir.
# Returns absolute host path or empty string if nothing found.
# ---------------------------------------------------------------------------
_wb_detect_pick_main_exe() {
  local dir_path="${1:-}"

  if [[ ! -d "${dir_path}" ]]; then
    echo ""
    return 0
  fi

  # Find all .exe files within depth 3, print as: size<TAB>path
  local best_path=""
  local best_size=0

  # First pass: top-level only (depth 1)
  local f size
  while IFS=$'\t' read -r size f; do
    [[ -z "${f}" ]] && continue
    local bname
    bname="$(basename "${f}")"
    # Skip uninstallers and helpers
    case "${bname,,}" in
      unins*.exe|setup.exe|updater*.exe|crashhandler*.exe|_*.exe) continue ;;
    esac
    if [[ "${size}" -gt "${best_size}" ]]; then
      best_size="${size}"
      best_path="${f}"
    fi
  done < <(find "${dir_path}" -maxdepth 1 -type f -iname "*.exe" -printf "%s\t%p\n" 2>/dev/null || true)

  # If nothing at top level, search depth 2-3
  if [[ -z "${best_path}" ]]; then
    while IFS=$'\t' read -r size f; do
      [[ -z "${f}" ]] && continue
      local bname
      bname="$(basename "${f}")"
      case "${bname,,}" in
        unins*.exe|setup.exe|updater*.exe|crashhandler*.exe|_*.exe) continue ;;
      esac
      if [[ "${size}" -gt "${best_size}" ]]; then
        best_size="${size}"
        best_path="${f}"
      fi
    done < <(find "${dir_path}" -maxdepth 3 -mindepth 2 -type f -iname "*.exe" -printf "%s\t%p\n" 2>/dev/null || true)
  fi

  echo "${best_path}"
}

# ---------------------------------------------------------------------------
# Internal: deduplicate candidates from M1 and M2.
# M1 wins on duplicate exe path (has better display name from .lnk).
# Input: two JSON arrays. Output: deduplicated JSON array.
# ---------------------------------------------------------------------------
_wb_detect_dedup_candidates() {
  local m1_json="${1:-[]}"
  local m2_json="${2:-[]}"

  # Use jq to merge: build a map keyed by exe, M1 first so it wins on duplicates
  jq -cn \
    --argjson m1 "${m1_json}" \
    --argjson m2 "${m2_json}" \
    '
    # Build map from M1 first
    ([$m1[] | {key: .exe, value: .}] | from_entries) as $m |
    # Add M2 entries only if key not already present
    reduce $m2[] as $c (
      $m;
      if has($c.exe) then . else .[$c.exe] = $c end
    ) |
    to_entries | map(.value)
    '
}

# ---------------------------------------------------------------------------
# Internal: map a Windows path (e.g. "C:\Program Files\App\app.exe") to a
# host filesystem path within the given prefix.
# Returns empty string if the mapping cannot be determined.
# ---------------------------------------------------------------------------
_wb_detect_win_path_to_host() {
  local prefix_path="${1:-}"
  local win_path="${2:-}"

  if [[ -z "${win_path}" ]]; then
    echo ""
    return 0
  fi

  # Normalize backslashes to forward slashes
  local normalized
  normalized="${win_path//\\//}"

  # Strip drive letter prefix (C:/, D:/, etc.) and replace with drive_c
  # We only map C: (the primary Wine drive); other drive letters are ignored.
  local drive_letter="${normalized:0:1}"
  local rest="${normalized:2}"  # strip "C:" leaving /...

  # Only map C: drive
  if [[ "${drive_letter,,}" != "c" ]]; then
    echo ""
    return 0
  fi

  echo "${prefix_path}/drive_c${rest}"
}

# ---------------------------------------------------------------------------
# wb_detect_snapshot_before <prefix_name>
# Writes a before.json snapshot and returns its absolute path on stdout.
# Purges any existing detection dir for this prefix first (crash recovery).
# Returns 1 if the prefix directory does not exist.
# ---------------------------------------------------------------------------
wb_detect_snapshot_before() {
  local prefix_name="${1:-}"
  if [[ -z "${prefix_name}" ]]; then
    echo "wb_detect_snapshot_before: prefix_name required" >&2
    return 1
  fi

  local prefix_path
  prefix_path="$(_wb_detect_resolve_prefix_path "${prefix_name}")"

  if [[ ! -d "${prefix_path}" ]]; then
    echo "wb-detect: prefix '${prefix_name}' does not exist at '${prefix_path}'" >&2
    return 1
  fi

  local snap_dir
  snap_dir="$(_wb_detect_snapshot_dir "${prefix_name}")"

  # Purge any stale detection dir from a prior crashed run
  if [[ -d "${snap_dir}" ]]; then
    rm -rf "${snap_dir}"
  fi
  mkdir -p "${snap_dir}"

  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

  # Scan current state
  local lnk_json
  lnk_json="$(_wb_detect_scan_lnks "${prefix_path}")"
  local pf_json
  pf_json="$(_wb_detect_scan_pf_dirs "${prefix_path}")"

  local pf_dirs_json
  pf_dirs_json="$(printf '%s' "${pf_json}" | jq '.pf')"
  local pf86_dirs_json
  pf86_dirs_json="$(printf '%s' "${pf_json}" | jq '.pf_x86')"

  # Write before.json
  local before_json_path="${snap_dir}/before.json"
  local snapshot_json
  snapshot_json="$(jq -cn \
    --argjson schema 1 \
    --arg prefix_name "${prefix_name}" \
    --arg captured_utc "${now_utc}" \
    --argjson lnk_paths "${lnk_json}" \
    --argjson program_files_dirs "${pf_dirs_json}" \
    --argjson program_files_x86_dirs "${pf86_dirs_json}" \
    '{
      schema: $schema,
      prefix_name: $prefix_name,
      captured_utc: $captured_utc,
      lnk_paths: $lnk_paths,
      program_files_dirs: $program_files_dirs,
      program_files_x86_dirs: $program_files_x86_dirs
    }')"

  # wb_json_write_atomic is sourced by the caller (wb-gui)
  wb_json_write_atomic "${before_json_path}" "${snapshot_json}"

  echo "${before_json_path}"
}

# ---------------------------------------------------------------------------
# wb_detect_diff_after <prefix_name> <before_json_path>
# Computes the diff between the before-snapshot and current prefix state.
# Returns a JSON array of candidate objects on stdout:
#   [{"exe": "<host_path>", "name": "<display>", "source": "installer", "via": "lnk|program_files"}, ...]
# Empty array if nothing new detected. Returns 0 always (failures are logged).
# ---------------------------------------------------------------------------
wb_detect_diff_after() {
  local prefix_name="${1:-}"
  local before_json_path="${2:-}"

  if [[ -z "${prefix_name}" || -z "${before_json_path}" ]]; then
    echo "wb_detect_diff_after: prefix_name and before_json_path required" >&2
    echo "[]"
    return 0
  fi

  if [[ ! -f "${before_json_path}" ]]; then
    echo "wb_detect_diff_after: before.json not found: '${before_json_path}'" >&2
    echo "[]"
    return 0
  fi

  local prefix_path
  prefix_path="$(_wb_detect_resolve_prefix_path "${prefix_name}")"

  # Read before-snapshot
  if ! jq empty "${before_json_path}" 2>/dev/null; then
    echo "wb_detect_diff_after: before.json is malformed" >&2
    echo "[]"
    return 0
  fi

  local before_lnks
  before_lnks="$(jq -c '.lnk_paths' "${before_json_path}")"
  local before_pf
  before_pf="$(jq -c '.program_files_dirs' "${before_json_path}")"
  local before_pf86
  before_pf86="$(jq -c '.program_files_x86_dirs' "${before_json_path}")"

  # --- Mechanism 1: .lnk diff ---
  local after_lnks
  after_lnks="$(_wb_detect_scan_lnks "${prefix_path}")"

  # New lnk paths = after_set - before_set
  local new_lnks
  new_lnks="$(jq -cn \
    --argjson after "${after_lnks}" \
    --argjson before "${before_lnks}" \
    '[$after[] | select(. as $p | $before | index($p) == null)]')"

  local m1_candidates="[]"
  local lnk_path
  while IFS= read -r lnk_path; do
    [[ -z "${lnk_path}" ]] && continue

    local parsed
    if ! parsed="$(_wb_detect_parse_lnk "${lnk_path}" 2>/dev/null)"; then
      # Unparseable .lnk — skip silently; M2 may catch the same install
      continue
    fi

    local win_target
    win_target="$(printf '%s' "${parsed}" | jq -r '.target_path // empty')"
    local disp_name
    disp_name="$(printf '%s' "${parsed}" | jq -r '.display_name // empty')"

    if [[ -z "${win_target}" ]]; then
      continue
    fi

    # Map Windows path to host filesystem
    local host_exe
    host_exe="$(_wb_detect_win_path_to_host "${prefix_path}" "${win_target}")"
    if [[ -z "${host_exe}" ]]; then
      # Not a C: drive path or unmappable — skip
      continue
    fi

    # Skip uninstallers / installer helpers / updaters / crash handlers — same
    # blacklist _wb_detect_pick_main_exe applies to Program Files candidates.
    # Inno Setup creates a Start Menu uninstall shortcut (e.g. unins000.exe)
    # which would otherwise show up alongside the real app in the candidate
    # checklist and end up registered in apps.json on "Add All".
    local _bn_lnk
    _bn_lnk="$(basename "${host_exe}")"
    case "${_bn_lnk,,}" in
      unins*.exe|setup.exe|setup_*.exe|install.exe|installer.exe|\
      updater*.exe|update.exe|crashhandler*.exe|crashreport*.exe|\
      _*.exe|unwise*.exe|uninst*.exe)
        continue
        ;;
    esac

    # Append to m1_candidates
    m1_candidates="$(jq -cn \
      --argjson arr "${m1_candidates}" \
      --arg exe "${host_exe}" \
      --arg name "${disp_name}" \
      '$arr + [{"exe": $exe, "name": $name, "source": "installer", "via": "lnk"}]')"

  done < <(printf '%s' "${new_lnks}" | jq -r '.[]')

  # --- Mechanism 2: Program Files diff ---
  local after_pf_dirs
  after_pf_dirs="$(_wb_detect_scan_pf_dirs "${prefix_path}")"
  local after_pf
  after_pf="$(printf '%s' "${after_pf_dirs}" | jq '.pf')"
  local after_pf86
  after_pf86="$(printf '%s' "${after_pf_dirs}" | jq '.pf_x86')"

  # New directories = after - before (for both PF and PF(x86))
  local new_pf_dirs
  new_pf_dirs="$(jq -cn \
    --argjson after_pf "${after_pf}" \
    --argjson after_pf86 "${after_pf86}" \
    --argjson before_pf "${before_pf}" \
    --argjson before_pf86 "${before_pf86}" \
    '
    ($before_pf + $before_pf86) as $before_all |
    (
      [($after_pf + $after_pf86)[] |
        select(. as $d | $before_all | index($d) == null)]
    )
    ')"

  local m2_candidates="[]"
  local pf_dir
  while IFS= read -r pf_dir; do
    [[ -z "${pf_dir}" ]] && continue

    local main_exe
    main_exe="$(_wb_detect_pick_main_exe "${pf_dir}")"
    if [[ -z "${main_exe}" ]]; then
      continue
    fi

    local dir_name
    dir_name="$(basename "${pf_dir}")"

    m2_candidates="$(jq -cn \
      --argjson arr "${m2_candidates}" \
      --arg exe "${main_exe}" \
      --arg name "${dir_name}" \
      '$arr + [{"exe": $exe, "name": $name, "source": "installer", "via": "program_files"}]')"

  done < <(printf '%s' "${new_pf_dirs}" | jq -r '.[]')

  # Deduplicate: M1 wins on same exe path
  local candidates
  candidates="$(_wb_detect_dedup_candidates "${m1_candidates}" "${m2_candidates}")"

  printf '%s' "${candidates}"
}

# ---------------------------------------------------------------------------
# wb_detect_add_candidates <prefix_name> <candidates_json>
# Interactive: shows a yad checklist of detected apps; for each selected entry
# calls wb_gui_apps_add. Paired with wb_detect_purge by the GUI dispatcher.
# ---------------------------------------------------------------------------
wb_detect_add_candidates() {
  local prefix_name="${1:-}"
  local candidates_json="${2:-[]}"

  if [[ -z "${prefix_name}" ]]; then
    echo "wb_detect_add_candidates: prefix_name required" >&2
    return 1
  fi

  local count
  count="$(printf '%s' "${candidates_json}" | jq 'length')"

  if [[ "${count}" -eq 0 ]]; then
    wb_gui_dialog_info "Install Detection" \
      "No new apps detected in the Start Menu or Program Files.\nUse 'Add Portable / Installed App' if the installer put the exe elsewhere."
    return 0
  fi

  # Build yad checklist data: TRUE\tNAME\tEXE\tVIA
  # One row per candidate — all pre-checked.
  local -a yad_rows=()
  local i exe name via
  for (( i=0; i<count; i++ )); do
    exe="$(printf '%s' "${candidates_json}" | jq -r ".[${i}].exe")"
    name="$(printf '%s' "${candidates_json}" | jq -r ".[${i}].name")"
    via="$(printf '%s' "${candidates_json}" | jq -r ".[${i}].via")"
    yad_rows+=("TRUE" "${name}" "${exe}" "${via}")
  done

  # Show checklist dialog; capture selected rows
  local checklist_out
  local rc=0
  checklist_out="$(wb_gui_yad \
    --list \
    --checklist \
    --title="${count} new app(s) detected — select which to add" \
    --text="Uncheck any apps you do NOT want to register." \
    --column="Add:CHK" \
    --column="Name" \
    --column="EXE:HD" \
    --column="Via:HD" \
    --separator="|" \
    --print-all \
    --button="Add selected:0" \
    --button="Cancel:1" \
    "${yad_rows[@]+"${yad_rows[@]}"}" 2>/dev/null)" || rc=$?

  # rc=1 means Cancel
  if [[ "${rc}" -ne 0 ]]; then
    return 0
  fi

  # Parse yad output: each selected row is TRUE|NAME|EXE|VIA\n
  local chk sel_name sel_exe
  while IFS='|' read -r chk sel_name sel_exe _via _rest; do
    [[ "${chk}" == "TRUE" ]] || continue
    [[ -z "${sel_exe}" ]] && continue
    # Add to registry
    wb_gui_apps_add "${sel_exe}" "${prefix_name}" "${sel_name}" "installer" || {
      echo "wb-detect: failed to add '${sel_name}' (${sel_exe})" >&2
    }
  done <<< "${checklist_out}"
}

# ---------------------------------------------------------------------------
# wb_detect_purge <prefix_name>
# Removes $WB_HOME/detection/<prefix>/ entirely. Idempotent.
# ---------------------------------------------------------------------------
wb_detect_purge() {
  local prefix_name="${1:-}"
  if [[ -z "${prefix_name}" ]]; then
    echo "wb_detect_purge: prefix_name required" >&2
    return 1
  fi

  local snap_dir
  snap_dir="$(_wb_detect_snapshot_dir "${prefix_name}")"

  if [[ -d "${snap_dir}" ]]; then
    rm -rf "${snap_dir}"
  fi
  # No-op if absent — idempotent by design
  return 0
}

# ---------------------------------------------------------------------------
# wb_detect_sweep_stale [max_age_hours=24]
# Purges all $WB_HOME/detection/* directories whose before.json is older than
# max_age_hours. Called at wb-gui startup to clean up after installer crashes.
# ---------------------------------------------------------------------------
wb_detect_sweep_stale() {
  local max_age_hours="${1:-24}"
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  local detection_root="${wb_home}/detection"

  if [[ ! -d "${detection_root}" ]]; then
    return 0
  fi

  local max_age_seconds
  max_age_seconds=$(( max_age_hours * 3600 ))
  local now
  now="$(date +%s)"

  local snap_dir
  for snap_dir in "${detection_root}"/*/; do
    [[ -d "${snap_dir}" ]] || continue
    local before_json="${snap_dir}/before.json"
    if [[ ! -f "${before_json}" ]]; then
      # No before.json — stale empty dir, remove it
      rm -rf "${snap_dir}"
      continue
    fi
    # Check mtime of before.json
    local mtime
    mtime="$(stat -c '%Y' "${before_json}" 2>/dev/null || echo 0)"
    local age
    age=$(( now - mtime ))
    if [[ "${age}" -gt "${max_age_seconds}" ]]; then
      echo "wb-detect: sweeping stale detection dir (${age}s old): ${snap_dir}" >&2
      rm -rf "${snap_dir}"
    fi
  done
}

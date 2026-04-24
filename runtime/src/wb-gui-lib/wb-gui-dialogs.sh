#!/usr/bin/env bash
# wb-gui-dialogs.sh — thin yad wrappers with consistent styling (M12)
# Sourced by wb-gui; never executed directly.
#
# Every function here calls yad with a common set of style flags so that:
#   1. All dialogs look consistent.
#   2. The yad backend can be swapped (e.g. kdialog fallback) in one place.
set -euo pipefail

# ---------------------------------------------------------------------------
# Common yad style flags.  Exported so subshells can use them too.
#
# --class=wine-bleeding sets the X11 WM_CLASS (and Wayland app_id) so window
# managers can associate the window with our .desktop launcher (which carries
# StartupWMClass=wine-bleeding). Without this, KDE Plasma / GNOME fall back
# to a first-letter placeholder icon in the title bar and taskbar because
# yad's default WM_CLASS is "yad", not our app name.
# ---------------------------------------------------------------------------
_WB_GUI_YAD_COMMON=(
  --center
  --window-icon=wine-bleeding
  --class=wine-bleeding
  --width=600
  # Keep wb-gui windows above file managers / terminals that are typically
  # already open. Without this, new dialogs (especially short-lived ones
  # launched from the main window) get buried behind Dolphin / Konsole
  # under most KDE and GNOME WM focus policies.
  --on-top
)

# ---------------------------------------------------------------------------
# wb_gui_yad — call yad with common style flags prepended.
# Usage: wb_gui_yad [yad-args...]
#
# argv[0] rewrite: GTK3 on Wayland derives the xdg-toplevel app_id from
# g_get_prgname(), which defaults to argv[0]. yad's binary name "yad" would
# leave the window unmatched against our StartupWMClass=wine-bleeding, so
# KDE Plasma falls back to a first-letter placeholder badge. Running yad as
# argv[0]="wine-bleeding" makes the Wayland app_id match. On X11 / XWayland,
# --class=wine-bleeding in _WB_GUI_YAD_COMMON does the equivalent for
# WM_CLASS; we keep both for belt-and-braces across session types.
# ---------------------------------------------------------------------------
wb_gui_yad() {
  local _yad_bin
  _yad_bin="$(command -v yad)" || {
    echo "wb-gui: yad not found on PATH" >&2
    return 1
  }
  # Force XWayland (GDK_BACKEND=x11) so the window sets _NET_WM_ICON with
  # real pixel data from the icon theme (GTK3 reads the --window-icon name
  # and encodes pixels into the atom). Plasma's Wayland compositor reads
  # _NET_WM_ICON from XWayland windows for the title bar decoration; pure
  # Wayland-native GTK3 apps rely on an xdg-shell icon convention Plasma's
  # decorations don't consistently pick up, which left a yellow "W" badge
  # in the title bar even after taskbar matching started working. Taskbar
  # continues to match via StartupWMClass under XWayland.
  (
    export GDK_BACKEND=x11
    exec -a wine-bleeding "${_yad_bin}" "${_WB_GUI_YAD_COMMON[@]}" "$@"
  )
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_info <title> <text>
# Show an informational message dialog (OK button).
# --no-markup: prevents yad from interpreting Pango markup in user-supplied
# text (e.g. game names containing '<', '>', '&'). Cosmetic-only risk but
# --no-markup is the correct default for untrusted content (M12 I-4).
# ---------------------------------------------------------------------------
wb_gui_dialog_info() {
  local title="${1:-Info}"
  local text="${2:-}"
  wb_gui_yad --title="${title}" --text="${text}" --no-markup \
    --button="OK:0" --image=dialog-information
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_error <title> <text>
# Show an error dialog (OK button). Always returns 0 to the caller so the
# caller can decide how to handle it.
# ---------------------------------------------------------------------------
wb_gui_dialog_error() {
  local title="${1:-Error}"
  local text="${2:-}"
  wb_gui_yad --title="${title}" --text="${text}" --no-markup \
    --button="OK:0" --image=dialog-error || true
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_confirm <title> <text>
# Returns 0 if user clicked Yes, 1 if No/Cancel.
# ---------------------------------------------------------------------------
wb_gui_dialog_confirm() {
  local title="${1:-Confirm}"
  local text="${2:-}"
  wb_gui_yad --title="${title}" --text="${text}" --no-markup \
    --button="Yes:0" --button="No:1" --image=dialog-question
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_question <title> <text> <continue_label> <cancel_label>
# Show a question dialog with two buttons: continue (rc=0) and cancel (rc=1).
# Returns 0 if the user clicked continue, non-zero if they clicked cancel or
# dismissed the dialog (rc=252 Escape).
# ---------------------------------------------------------------------------
wb_gui_dialog_question() {
  local title="${1:-Confirm}"
  local text="${2:-}"
  local continue_label="${3:-Continue}"
  local cancel_label="${4:-Cancel}"
  wb_gui_yad --title="${title}" --text="${text}" --no-markup \
    --button="${continue_label}:0" --button="${cancel_label}:1" \
    --image=dialog-question
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_file_select [title]
# Open a file-chooser dialog. Prints selected path to stdout.
# Returns non-zero if user cancelled.
# ---------------------------------------------------------------------------
wb_gui_dialog_file_select() {
  local title="${1:-Select File}"
  wb_gui_yad --file --title="${title}"
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_entry <title> <text> [default_value]
# Show a single text entry dialog. Prints entered value to stdout.
# Returns non-zero if user cancelled.
# ---------------------------------------------------------------------------
wb_gui_dialog_entry() {
  local title="${1:-Input}"
  local text="${2:-}"
  local default="${3:-}"
  wb_gui_yad --title="${title}" --text="${text}" --no-markup \
    --entry --entry-text="${default}" \
    --button="OK:0" --button="Cancel:1"
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_form_settings <prefix_name> <exe_path>
#   <dxvk_current> <vkd3d_current> <nvapi_current>
#   <esync_current> <fsync_current>
#   <dxvk_hud_current> <overrides_current>
#
# Shows the per-game settings form. Prints pipe-separated yad output to stdout.
# The caller parses the output to extract field values.
# Returns non-zero if user cancelled.
# ---------------------------------------------------------------------------
wb_gui_dialog_form_settings() {
  local prefix_name="${1:-}"
  local exe_path="${2:-}"
  local dxvk_on="${3:-TRUE}"
  local vkd3d_on="${4:-FALSE}"
  local nvapi_on="${5:-FALSE}"
  local esync_on="${6:-TRUE}"
  local fsync_on="${7:-FALSE}"
  local dxvk_hud="${8:-}"
  local overrides="${9:-}"

  wb_gui_yad --form --no-markup \
    --title="Settings — ${prefix_name}" \
    --text="Per-game settings for: ${exe_path}" \
    --separator="|" \
    --field="DXVK:CHK"       "${dxvk_on}" \
    --field="VKD3D-Proton:CHK"   "${vkd3d_on}" \
    --field="NVAPI:CHK"      "${nvapi_on}" \
    --field="ESYNC:CHK"      "${esync_on}" \
    --field="FSYNC:CHK"      "${fsync_on}" \
    --field="DXVK_HUD:TEXT"  "${dxvk_hud}" \
    --field="Extra DLL Overrides:TEXT" "${overrides}" \
    --button="Save:0" --button="Cancel:1"
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_list <title> <column_names_csv> <data...>
# Wrap yad --list with common style. Remaining args are passed verbatim.
# ---------------------------------------------------------------------------
wb_gui_dialog_list() {
  local title="${1:-Games}"
  shift
  wb_gui_yad --list --title="${title}" "$@"
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_log_tail <title> <log_file>
# Open a yad --text-info --tail window reading <log_file>.
# Returns 0 when the window closes naturally (builder exits and caller
# closes the window), 1 when the user clicks the Cancel button (rc=1/252).
#
# The caller is responsible for:
#   - starting the background build process before calling this function
#   - closing this window when the build exits naturally (not needed; yad
#     blocks until the user clicks Cancel or it is killed)
#
# The Cancel button is rc=1; window-close (Escape / X) gives rc=252 — both
# are treated as cancellation by the caller.
# ---------------------------------------------------------------------------
wb_gui_dialog_log_tail() {
  local title="${1:-Building}"
  local log_file="${2:-}"
  # Use exec so this function's subshell BECOMES yad — the PID of the
  # backgrounded function equals yad's PID, so `kill $yad_pid` from the
  # caller actually terminates yad. Without exec, the subshell forks yad
  # as a child; killing the subshell leaves yad reparented to init and
  # the dialog stays on screen showing a stale Cancel button.
  exec wb_gui_yad \
    --text-info \
    --tail \
    --filename="${log_file}" \
    --title="${title}" \
    --width=800 \
    --height=500 \
    --no-markup \
    --button="Cancel:1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_checklist <title> <text> <columns_csv> [row_data...]
#
# Wraps yad --list --checklist with consistent styling and column structure.
# The first column is always "Add:CHK". columns_csv is a pipe-separated
# list of additional column names (e.g. "Name|Executable|Detected via").
# Remaining arguments are the row data (pre-pended with TRUE/FALSE per row).
# stdout: pipe-separated rows (all rows, with CHK column for filtering).
# rc: 0=OK, 1=Cancel/Skip, 10=Add All (if applicable), 252=Escape.
# ---------------------------------------------------------------------------
wb_gui_dialog_checklist() {
  local title="${1:-Select}"
  local text="${2:-}"
  local columns_csv="${3:-}"
  shift 3
  local -a col_args=("--column=Add:CHK")
  local -a col_names_arr
  IFS='|' read -ra col_names_arr <<< "${columns_csv}"
  local col
  for col in "${col_names_arr[@]}"; do
    [[ -n "${col}" ]] && col_args+=("--column=${col}")
  done
  wb_gui_yad --list --checklist \
    --title="${title}" --text="${text}" --no-markup \
    --separator="|" --print-all \
    "${col_args[@]}" \
    "$@"
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_overlay_install_prompt <overlay_name> <version>
# 3-button dialog: "Install now" (rc=0) / "Save without installing" (rc=10) /
# "Cancel" (rc=1).  Implements BLK-2 resolved copy.
# ---------------------------------------------------------------------------
wb_gui_dialog_overlay_install_prompt() {
  local overlay_name="${1:-overlay}"
  local version="${2:-(unknown version)}"
  wb_gui_yad \
    --title="wb-gui — ${overlay_name} not installed" \
    --no-markup \
    --image=dialog-question \
    --text="${overlay_name} is enabled but not yet installed.

  Install now (recommended): download and install ${overlay_name} ${version},
    then save. The HUD will be active on next game launch.

  Save without installing: settings are saved. ${overlay_name} will use
    your system installation (if any). A warning badge will appear
    in this panel as a reminder.

  Cancel: return to the panel without saving." \
    --button="Install now:0" \
    --button="Save without installing:10" \
    --button="Cancel:1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_overlay_updates_checklist <title> <header_text>
#   <row_data...>
# Wraps yad --list --checklist for Stage 2 (updates available).
# Columns: CHK | Overlay | Installed | Available | Action
# rc=0 "Install selected", rc=1 Cancel.
# Prints pipe-separated checklist rows to stdout.
# ---------------------------------------------------------------------------
wb_gui_dialog_overlay_updates_checklist() {
  local title="${1:-wb-gui — Overlay updates available}"
  local header_text="${2:-}"
  shift 2
  wb_gui_yad \
    --list --checklist \
    --title="${title}" \
    --text="${header_text}" \
    --no-markup \
    --width=640 --height=300 \
    --separator="|" \
    --print-all \
    --column="Install:CHK" \
    --column="Overlay" \
    --column="Installed" \
    --column="Available" \
    --column="Action" \
    --button="Cancel:1" \
    --button="Install selected:0" \
    "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_notebook <key> <tab_labels_csv> [extra_yad_args...]
#
# Wraps yad --notebook (parent container). The caller must launch child
# --plug processes BEFORE calling this.
#   key: shared integer key for --plug children
#   tab_labels_csv: pipe-separated tab names (e.g. "General|Dist|Prefix|Per-App")
# Standard buttons: "Save this tab" (rc=10) and "Close" (rc=1) per F4 fix.
# ---------------------------------------------------------------------------
wb_gui_dialog_notebook() {
  local key="${1:-}"
  local tabs_csv="${2:-}"
  shift 2
  local -a tab_args=()
  local -a tab_names_arr
  IFS='|' read -ra tab_names_arr <<< "${tabs_csv}"
  local tab
  for tab in "${tab_names_arr[@]}"; do
    [[ -n "${tab}" ]] && tab_args+=("--tab=${tab}")
  done
  wb_gui_yad --notebook \
    --key="${key}" \
    "${tab_args[@]}" \
    --width=700 --height=450 \
    --button="Save this tab:10" \
    --button="Close:1" \
    "$@"
}

# ===========================================================================
# Build-env preflight dialog helpers (W4 — Build-env frontend)
# ===========================================================================

# ---------------------------------------------------------------------------
# wb_gui_dialog_preflight_table <context_label> <json_file> [<build_type>]
#
# Renders the three-column build-environment preflight dialog from a
# wb-preflight.py JSON output file.
#
# Args:
#   context_label  — appears in window title: "Build environment — <label>"
#   json_file      — path to the JSON temp file set by wb_gui_build_env_preflight
#   build_type     — "components" (default) or "dist" (adds header prefix for dist)
#
# Returns:
#   0   — all-green (pass-through) or user chose Continue / Continue anyway
#   1   — user clicked Cancel or closed the window
#   10  — user chose "Continue anyway" (some tools still missing)
#   20  — user clicked Re-check (caller re-runs preflight and calls us again)
#   30  — user clicked "Copy all install commands"
#   40  — user clicked "Build all from source"
#   50..52 — per-row source-build button (slug index 0-2; caller dispatches)
#
# The caller is responsible for the re-check loop and source-build dispatch.
# ---------------------------------------------------------------------------

# Time estimates per source-build slug (minutes, upper bound)
_WB_BUILD_TIME_GLSLANG_MIN=15
# MinGW source-build is the default. Set WB_MINGW_PREFER_PREBUILT=1 to take
# the ~5-min musl.cc download path instead.
_WB_BUILD_TIME_MINGW_MIN=45

wb_gui_dialog_preflight_table() {
  local context_label="${1:-Component Builder}"
  local json_file="${2:-}"
  local build_type="${3:-components}"

  if [[ -z "${json_file}" || ! -r "${json_file}" ]]; then
    return 1
  fi

  # ------------------------------------------------------------------
  # Parse JSON into shell variables
  # ------------------------------------------------------------------
  local overall_ok distro_recognized distro_id distro_pretty
  overall_ok="$(jq -r '.overall_ok' "${json_file}" 2>/dev/null || echo "false")"
  distro_recognized="$(jq -r '.distro.recognized' "${json_file}" 2>/dev/null || echo "false")"
  distro_id="$(jq -r '.distro.id // "unknown"' "${json_file}" 2>/dev/null || echo "unknown")"
  distro_pretty="$(jq -r '.distro.pretty_name // .distro.id // "unknown"' "${json_file}" 2>/dev/null || echo "unknown")"

  # Count tools and collect per-tool data
  local tool_count
  tool_count="$(jq '.tools | length' "${json_file}" 2>/dev/null || echo "0")"

  # Arrays of per-tool data
  local -a t_name=() t_ok=() t_reason=() t_version=() t_min_version=()
  local -a t_install_cmd=() t_src_slug=() t_src_label=() t_notes=()
  local i
  for (( i=0; i<tool_count; i++ )); do
    t_name+=("$(jq -r ".tools[${i}].name // \"\"" "${json_file}" 2>/dev/null || echo "")")
    t_ok+=("$(jq -r ".tools[${i}].ok // \"false\"" "${json_file}" 2>/dev/null || echo "false")")
    t_reason+=("$(jq -r ".tools[${i}].reason // \"\"" "${json_file}" 2>/dev/null || echo "")")
    t_version+=("$(jq -r ".tools[${i}].version // \"\"" "${json_file}" 2>/dev/null || echo "")")
    t_min_version+=("$(jq -r ".tools[${i}].min_version // \"\"" "${json_file}" 2>/dev/null || echo "")")
    t_install_cmd+=("$(jq -r ".tools[${i}].distro_install_cmd // \"\"" "${json_file}" 2>/dev/null || echo "")")
    t_src_slug+=("$(jq -r ".tools[${i}].source_build_fallback // \"\"" "${json_file}" 2>/dev/null || echo "")")
    t_src_label+=("$(jq -r ".tools[${i}].source_build_fallback_label // \"\"" "${json_file}" 2>/dev/null || echo "")")
    t_notes+=("$(jq -r ".tools[${i}].notes // \"\"" "${json_file}" 2>/dev/null || echo "")")
  done

  # Overlay errors
  local overlay_error_count
  overlay_error_count="$(jq '.overlay_errors | length' "${json_file}" 2>/dev/null || echo "0")"

  # ------------------------------------------------------------------
  # Determine header copy (per w2-preflight-dialog.md §10)
  # ------------------------------------------------------------------
  local header_text=""
  if [[ "${build_type}" == "dist" ]]; then
    header_text="We will run tools/full-build.sh — the full Wine compile plus DXVK/VKD3D/NVAPI build. This takes 30-90 minutes depending on your machine.

"
  fi

  if [[ "${distro_recognized}" != "true" ]]; then
    header_text+="Your distro (${distro_id}) is not in our built-in package map.
We cannot auto-detect install commands for your system.

Install the following tools using your distro's package manager:
  meson  ninja  glslang  mingw-w64  gcc  g++  make  pkg-config  git

Or use the Build from source buttons below for tools with an
automated fallback (glslang, MinGW-w64, meson via pip).

Report your distro at github.com/palginpav/wine/issues so we can
add it to the built-in list."
  elif [[ "${overall_ok}" == "true" ]]; then
    header_text+="Your system has everything needed to build components. Click Continue to proceed."
  else
    header_text+="Some build tools are missing or too old. Copy the install command for your distro (paste in a terminal), or click Build from source for a self-contained build inside wine-bleeding."
  fi

  # ------------------------------------------------------------------
  # Build TSV rows for yad --list (one row per tool: Tool | Status | Fix)
  # Rendered via stdin rather than --field LBL/RO/BTN because yad --form
  # --columns=N does COLUMN-MAJOR layout (fills each column top-to-bottom),
  # not row-major — so the 3-columns-per-tool grid collapses visually.
  # ------------------------------------------------------------------
  local list_rows=""
  local -a src_slugs_present=()   # rc=50,51,52 map by position

  for (( i=0; i<tool_count; i++ )); do
    local name="${t_name[${i}]}"
    local ok="${t_ok[${i}]}"
    local reason="${t_reason[${i}]}"
    local version="${t_version[${i}]}"
    local min_ver="${t_min_version[${i}]}"
    local install_cmd="${t_install_cmd[${i}]}"
    local src_slug="${t_src_slug[${i}]}"
    local notes="${t_notes[${i}]}"

    # Status text (col 2)
    local status_text
    case "${reason}" in
      not_found)       status_text="MISSING" ;;
      version_too_old) status_text="OLD  ${version}  (need >= ${min_ver})" ;;
      version_unknown) status_text="UNKNOWN VERSION" ;;
      probe_failed)    status_text="PROBE FAILED" ;;
      *)
        if [[ "${ok}" == "true" ]]; then
          status_text="OK  ${version}"
        else
          status_text="MISSING"
        fi
        ;;
    esac

    # Fix text (col 3)
    local fix_text="—"
    if [[ "${ok}" != "true" ]]; then
      if [[ -n "${install_cmd}" ]]; then
        fix_text="${install_cmd}"
      elif [[ "${distro_recognized}" != "true" ]]; then
        fix_text="Install using your distro's package manager"
      fi
    fi

    # Track source-build-capable not-ok tools in JSON order so per-slug
    # footer buttons keep the rc=50/51/52 index semantics the caller expects.
    if [[ -n "${src_slug}" && "${ok}" != "true" ]]; then
      src_slugs_present+=("${src_slug}")
    fi

    # yad --list protocol: ONE cell per stdin line. With 3 columns, every
    # 3 consecutive lines form one row. Do NOT use tab separators.
    list_rows+="${name}"$'\n'
    list_rows+="${status_text}"$'\n'
    list_rows+="${fix_text}"$'\n'

    # Per-tool note as a sub-row: blank tool cell + "note:" in status cell.
    if [[ -n "${notes}" ]]; then
      list_rows+=""$'\n'
      list_rows+="note:"$'\n'
      list_rows+="${notes}"$'\n'
    fi
  done

  # Distro-unrecognized banner (BE11)
  if [[ "${distro_recognized}" != "true" ]]; then
    list_rows+="⚠"$'\n'
    list_rows+="Distro not recognized"$'\n'
    list_rows+="Commands above are generic fallbacks"$'\n'
  fi

  # Overlay error rows (BE12, up to 3)
  if [[ "${overlay_error_count}" -gt 0 ]]; then
    local max_ov=3
    [[ "${overlay_error_count}" -lt "${max_ov}" ]] && max_ov="${overlay_error_count}"
    local ov_i
    for (( ov_i=0; ov_i<max_ov; ov_i++ )); do
      local ov_path ov_msg
      ov_path="$(jq -r ".overlay_errors[${ov_i}].path // \"\"" "${json_file}" 2>/dev/null || echo "")"
      ov_msg="$(jq -r ".overlay_errors[${ov_i}].message // \"\"" "${json_file}" 2>/dev/null || echo "")"
      list_rows+="⚠"$'\n'
      list_rows+="Overlay ignored"$'\n'
      list_rows+="${ov_path}: ${ov_msg}"$'\n'
    done
    if [[ "${overlay_error_count}" -gt 3 ]]; then
      list_rows+="⚠"$'\n'
      list_rows+="More overlay errors"$'\n'
      list_rows+="$(( overlay_error_count - 3 )) more ignored. See logs."$'\n'
    fi
  fi

  # ------------------------------------------------------------------
  # Compute time estimate for "Build all from source" button label
  # ------------------------------------------------------------------
  local has_src_builds=0
  local est_min=0
  local s
  for s in "${src_slugs_present[@]+"${src_slugs_present[@]}"}"; do
    has_src_builds=1
    case "${s}" in
      wb-build-glslang)       est_min=$(( est_min + _WB_BUILD_TIME_GLSLANG_MIN )) ;;
      build-mingw-from-source) est_min=$(( est_min + _WB_BUILD_TIME_MINGW_MIN )) ;;
      pip-install-meson)       est_min=$(( est_min + 1 )) ;;
    esac
  done
  # Round up to nearest 5
  if [[ "${est_min}" -gt 0 && $(( est_min % 5 )) -ne 0 ]]; then
    est_min=$(( (est_min / 5 + 1) * 5 ))
  fi
  [[ "${est_min}" -eq 0 && "${has_src_builds}" -eq 1 ]] && est_min=1

  # ------------------------------------------------------------------
  # Collect all not-ok install commands for "Copy all" footer (rc=30)
  # ------------------------------------------------------------------
  # (The actual copy action is performed by the caller when it receives rc=30)

  # ------------------------------------------------------------------
  # Button row
  # ------------------------------------------------------------------
  local -a btn_args=()
  if [[ "${overall_ok}" != "true" ]]; then
    btn_args+=(--button="Copy all install commands:30")
  fi

  # Per-slug source-build buttons — rc=50/51/52 by position in
  # src_slugs_present (the caller looks up the Nth non-ok source-build
  # tool in JSON order, matching the rc offset).
  local _bs_idx=0
  local _bs_slug
  for _bs_slug in "${src_slugs_present[@]+"${src_slugs_present[@]}"}"; do
    local _bs_label
    case "${_bs_slug}" in
      wb-build-glslang)        _bs_label="Build glslang from source (~${_WB_BUILD_TIME_GLSLANG_MIN} min)" ;;
      build-mingw-from-source) _bs_label="Build MinGW-w64 from source (~${_WB_BUILD_TIME_MINGW_MIN} min)" ;;
      pip-install-meson)       _bs_label="Install meson via pip" ;;
      *)                       _bs_label="Build ${_bs_slug} from source" ;;
    esac
    btn_args+=(--button="${_bs_label}:$(( 50 + _bs_idx ))")
    _bs_idx=$(( _bs_idx + 1 ))
  done
  # Offer "Build all" as a shortcut when 2+ source-builds are applicable.
  if [[ "${#src_slugs_present[@]}" -ge 2 ]]; then
    btn_args+=(--button="Build all from source (~${est_min} min):40")
  fi

  btn_args+=(
    --button="Cancel:1"
    --button="Re-check:20"
  )
  if [[ "${overall_ok}" != "true" ]]; then
    btn_args+=(--button="Continue anyway:10")
  else
    btn_args+=(--button="Continue:0")
  fi

  # ------------------------------------------------------------------
  # Invoke yad --list (proper 3-column table layout; avoids yad --form
  # --columns=N column-major issue where each tool's 3 fields appear
  # as 3 separate rows with single-colon orphan labels).
  # ------------------------------------------------------------------
  local rc=0
  printf '%b' "${list_rows}" | wb_gui_yad \
    --list \
    --title="Build environment — ${context_label}" \
    --text="<b>Distro:</b> ${distro_pretty}    <b>Build type:</b> ${context_label}

${header_text}" \
    --no-selection \
    --expand-column=3 \
    --ellipsize=END \
    --column="Tool" \
    --column="Status" \
    --column="Fix / Install command" \
    --separator="|" \
    --width=860 --height=460 \
    --buttons-layout=spread \
    "${btn_args[@]}" 2>/dev/null || rc=$?

  return "${rc}"
}

# ---------------------------------------------------------------------------
# _wb_gui_preflight_copy_install_cmds <json_file>
#
# Aggregates distro_install_cmd entries from all not-ok tools into a
# pasteable shell block and copies it to clipboard (xclip / xsel / wl-copy).
# Falls back to writing $TMPDIR/wb-preflight-install-cmds.txt and showing
# a dialog with the file path.
#
# Returns 0. Caller does not need to inspect the return value.
# ---------------------------------------------------------------------------
_wb_gui_preflight_copy_install_cmds() {
  local json_file="${1:-}"
  [[ -z "${json_file}" || ! -r "${json_file}" ]] && return 1

  local distro_pretty distro_id
  distro_pretty="$(jq -r '.distro.pretty_name // .distro.id // "unknown"' "${json_file}" 2>/dev/null || echo "unknown")"
  distro_id="$(jq -r '.distro.id // "unknown"' "${json_file}" 2>/dev/null || echo "unknown")"

  # Collect refresh cmd and individual install cmds from not-ok tools
  local refresh_cmd=""
  refresh_cmd="$(jq -r '.distro.refresh_cmd // ""' "${json_file}" 2>/dev/null || echo "")"

  local -a install_lines=()
  local tool_count i
  tool_count="$(jq '.tools | length' "${json_file}" 2>/dev/null || echo "0")"

  for (( i=0; i<tool_count; i++ )); do
    local ok cmd
    ok="$(jq -r ".tools[${i}].ok" "${json_file}" 2>/dev/null || echo "true")"
    cmd="$(jq -r ".tools[${i}].distro_install_cmd // \"\"" "${json_file}" 2>/dev/null || echo "")"
    if [[ "${ok}" != "true" && -n "${cmd}" ]]; then
      install_lines+=("${cmd}")
    fi
  done

  # Deduplicate
  local -a unique_lines=()
  local seen_line
  declare -A seen_map
  for seen_line in "${install_lines[@]+"${install_lines[@]}"}"; do
    if [[ -z "${seen_map[${seen_line}]+x}" ]]; then
      seen_map["${seen_line}"]=1
      unique_lines+=("${seen_line}")
    fi
  done

  # Build output block
  local block
  block="# wine-bleeding build environment — install commands (${distro_pretty})"$'\n'
  block+="# Paste these into a terminal and run them, then click Re-check."$'\n'
  if [[ -n "${refresh_cmd}" ]]; then
    block+="${refresh_cmd}"$'\n'
  fi
  local line
  for line in "${unique_lines[@]+"${unique_lines[@]}"}"; do
    block+="${line}"$'\n'
  done

  # Try clipboard tools in order
  local copied=0
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "${block}" | wl-copy 2>/dev/null && copied=1
  fi
  if [[ "${copied}" -eq 0 ]] && command -v xclip >/dev/null 2>&1; then
    printf '%s' "${block}" | xclip -selection clipboard 2>/dev/null && copied=1
  fi
  if [[ "${copied}" -eq 0 ]] && command -v xsel >/dev/null 2>&1; then
    printf '%s' "${block}" | xsel --clipboard --input 2>/dev/null && copied=1
  fi

  if [[ "${copied}" -eq 1 ]]; then
    wb_gui_dialog_info "Copied to clipboard" \
      "Install commands copied to clipboard.
Paste them into a terminal, run them, then click Re-check."
  else
    # Fallback: write to temp file
    local tmp_cmds="${TMPDIR:-/tmp}/wb-preflight-install-cmds.txt"
    printf '%s' "${block}" > "${tmp_cmds}"
    wb_gui_dialog_info "Install commands saved" \
      "Could not access clipboard. Commands written to:
${tmp_cmds}

Open that file, copy the commands, paste into a terminal, run them,
then click Re-check."
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _wb_gui_preflight_confirm_source_build <slug> [<extra_slugs...>]
#
# Shows a confirmation dialog before any source build starts (BLK-2 resolution).
# slug = one of: wb-build-glslang | build-mingw-from-source | pip-install-meson
# Returns 0 if user confirmed, 1 if cancelled.
# ---------------------------------------------------------------------------
_wb_gui_preflight_confirm_source_build() {
  local -a slugs=("$@")
  local tool_list="" est_min=0

  local slug
  for slug in "${slugs[@]+"${slugs[@]}"}"; do
    case "${slug}" in
      wb-build-glslang)
        tool_list+="  glslang  (~${_WB_BUILD_TIME_GLSLANG_MIN} min on 8-core hardware)"$'\n'
        est_min=$(( est_min + _WB_BUILD_TIME_GLSLANG_MIN ))
        ;;
      build-mingw-from-source)
        tool_list+="  MinGW-w64  (~${_WB_BUILD_TIME_MINGW_MIN} min on 8-core hardware)"$'\n'
        est_min=$(( est_min + _WB_BUILD_TIME_MINGW_MIN ))
        ;;
      pip-install-meson)
        tool_list+="  meson (via pip, user-level, ~1 min)"$'\n'
        est_min=$(( est_min + 1 ))
        ;;
    esac
  done

  wb_gui_dialog_question \
    "Build missing tools from source?" \
    "This will build the following tools from source inside
wine-bleeding's own directory. Depending on your machine this
may take up to ~${est_min} minutes.

Tools to build:
${tool_list}
After each tool is built, the preflight table updates automatically.
You can cancel at any time from the build log window." \
    "Build from source" "Cancel"
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_preflight_loop <context_label> <build_type>
#
# High-level orchestrator: calls wb_gui_build_env_preflight, then handles
# the re-check loop, per-row source-build dispatch, copy-all, and build-all.
#
# Returns:
#   0   — proceed with build (pass-through or user chose Continue/Continue anyway)
#   1   — user cancelled; caller aborts
#
# This is the single entry point W4 call sites use. It owns the WB_PREFLIGHT_JSON_FILE
# lifecycle (reads + rm -f).
# ---------------------------------------------------------------------------
wb_gui_dialog_preflight_loop() {
  local context_label="${1:-Component Builder}"
  local build_type="${2:-components}"

  while true; do
    # Run preflight backend
    local pf_rc=0
    wb_gui_build_env_preflight "${build_type}" || pf_rc=$?

    case "${pf_rc}" in
      0)
        # All-green — silent pass-through (BLK-1)
        rm -f "${WB_PREFLIGHT_JSON_FILE:-}" 2>/dev/null || true
        return 0
        ;;
      1)
        : # Some tools missing — fall through to dialog
        ;;
      2|99)
        # Internal error — show diagnostic and abort
        wb_gui_dialog_error "Build environment check failed" \
          "The build environment checker could not run (exit ${pf_rc}).
What happened: wb-preflight.py returned an unexpected error.
Why: the tool may be missing or the installation may be incomplete.
Next action: reinstall wine-bleeding or run wb-preflight.py manually."
        rm -f "${WB_PREFLIGHT_JSON_FILE:-}" 2>/dev/null || true
        return 1
        ;;
    esac

    # Have JSON — show dialog
    local json_file="${WB_PREFLIGHT_JSON_FILE:-}"
    local dialog_rc=0
    wb_gui_dialog_preflight_table "${context_label}" "${json_file}" "${build_type}" \
      || dialog_rc=$?

    case "${dialog_rc}" in
      0|10)
        # Continue / Continue anyway — proceed
        rm -f "${json_file}" 2>/dev/null || true
        return 0
        ;;
      1|252)
        # Cancel
        rm -f "${json_file}" 2>/dev/null || true
        return 1
        ;;
      20)
        # Re-check — re-run preflight (loop)
        rm -f "${json_file}" 2>/dev/null || true
        continue
        ;;
      30)
        # Copy all install commands
        _wb_gui_preflight_copy_install_cmds "${json_file}"
        rm -f "${json_file}" 2>/dev/null || true
        # Re-show dialog (loop back via re-run preflight)
        continue
        ;;
      40)
        # Build all from source — collect slugs from JSON, confirm, dispatch
        local -a all_slugs=()
        local slug
        local tc
        tc="$(jq '.tools | length' "${json_file}" 2>/dev/null || echo "0")"
        local ti
        for (( ti=0; ti<tc; ti++ )); do
          local t_ok t_slug
          t_ok="$(jq -r ".tools[${ti}].ok" "${json_file}" 2>/dev/null || echo "true")"
          t_slug="$(jq -r ".tools[${ti}].source_build_fallback // \"\"" "${json_file}" 2>/dev/null || echo "")"
          if [[ "${t_ok}" != "true" && -n "${t_slug}" ]]; then
            all_slugs+=("${t_slug}")
          fi
        done

        rm -f "${json_file}" 2>/dev/null || true

        if [[ "${#all_slugs[@]}" -eq 0 ]]; then
          continue
        fi

        # BLK-2: confirmation required
        local confirm_rc=0
        _wb_gui_preflight_confirm_source_build "${all_slugs[@]}" || confirm_rc=$?
        if [[ "${confirm_rc}" -ne 0 ]]; then
          continue  # User cancelled confirmation — back to preflight
        fi

        # Check build lock
        local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
        local build_lock_file="${wb_home}/.build-lock"
        if ! flock -n "${build_lock_file}" true 2>/dev/null; then
          wb_gui_dialog_error "Build already in progress" \
            "Another build is already running.
Wait for it to finish or cancel it, then try again."
          continue
        fi

        # Dispatch each slug in pipeline order (glslang first, then mingw, then meson)
        local -a ordered_slugs=()
        local _s
        for _s in wb-build-glslang build-mingw-from-source pip-install-meson; do
          local found_s
          for found_s in "${all_slugs[@]+"${all_slugs[@]}"}"; do
            [[ "${found_s}" == "${_s}" ]] && ordered_slugs+=("${_s}") && break
          done
        done

        local slug_i=0
        local slug_total="${#ordered_slugs[@]}"
        local _slug
        for _slug in "${ordered_slugs[@]+"${ordered_slugs[@]}"}"; do
          (( slug_i++ )) || true
          _wb_gui_preflight_dispatch_source_build \
            "${_slug}" "${slug_i}" "${slug_total}" || true
        done

        # After all builds: loop back to re-run preflight
        continue
        ;;
      50|51|52)
        # Per-row source-build BTN — rc encodes slug index
        # Re-read the JSON for slug lookup (may have been updated)
        local _slug_idx=$(( dialog_rc - 50 ))
        local _per_row_slug=""
        local _tc
        _tc="$(jq '.tools | length' "${json_file}" 2>/dev/null || echo "0")"
        local _seen_idx=-1
        local _ti
        for (( _ti=0; _ti<_tc; _ti++ )); do
          local _t_ok _t_slug
          _t_ok="$(jq -r ".tools[${_ti}].ok" "${json_file}" 2>/dev/null || echo "true")"
          _t_slug="$(jq -r ".tools[${_ti}].source_build_fallback // \"\"" "${json_file}" 2>/dev/null || echo "")"
          if [[ "${_t_ok}" != "true" && -n "${_t_slug}" ]]; then
            (( _seen_idx++ )) || true
            if [[ "${_seen_idx}" -eq "${_slug_idx}" ]]; then
              _per_row_slug="${_t_slug}"
              break
            fi
          fi
        done

        rm -f "${json_file}" 2>/dev/null || true

        if [[ -z "${_per_row_slug}" ]]; then
          continue
        fi

        # BLK-2: confirmation required for single-tool source build too
        local _pr_confirm_rc=0
        _wb_gui_preflight_confirm_source_build "${_per_row_slug}" || _pr_confirm_rc=$?
        if [[ "${_pr_confirm_rc}" -ne 0 ]]; then
          continue
        fi

        # Check build lock
        local _pr_wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
        if ! flock -n "${_pr_wb_home}/.build-lock" true 2>/dev/null; then
          wb_gui_dialog_error "Build already in progress" \
            "Another build is already running.
Wait for it to finish or cancel it, then try again."
          continue
        fi

        _wb_gui_preflight_dispatch_source_build "${_per_row_slug}" 1 1 || true
        continue
        ;;
      *)
        rm -f "${json_file}" 2>/dev/null || true
        return 1
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# _wb_gui_preflight_dispatch_source_build <slug> <step_n> <step_total>
#
# Launches a single source-build fallback wrapped in wb_gui_dialog_log_tail.
# Handles PATH extension after glslang and pip PATH-gap detection after meson.
# On exit non-zero shows an error dialog.
# ---------------------------------------------------------------------------
_wb_gui_preflight_dispatch_source_build() {
  local slug="${1:-}"
  local step_n="${2:-1}"
  local step_total="${3:-1}"

  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"

  # Title string per slug
  local dialog_title
  case "${slug}" in
    wb-build-glslang)
      dialog_title="Building glslang from source — Step ${step_n} of ${step_total}"
      ;;
    build-mingw-from-source)
      dialog_title="Building MinGW-w64 from source (30-60 min on typical hardware — this is normal) — Step ${step_n} of ${step_total}"
      ;;
    pip-install-meson)
      dialog_title="Installing meson via pip — Step ${step_n} of ${step_total}"
      ;;
    *)
      dialog_title="Building tool from source — Step ${step_n} of ${step_total}"
      ;;
  esac

  # Create temp files
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local log_file="${tmp_dir}/wb-src-build-log.txt"
  local raw_out="${log_file}.rawout"
  local event_pipe="${tmp_dir}/wb-src-build-events"
  mkfifo "${event_pipe}"

  # Write header to log
  printf '%s\n' "${dialog_title}" > "${log_file}"
  if [[ "${slug}" == "build-mingw-from-source" ]]; then
    printf 'Output below is from the existing build system. English errors will appear if the build fails.\n' >> "${log_file}"
    printf '\n' >> "${log_file}"
  fi

  # Event reader (reuse same pattern as _cmd_build_component)
  _wb_gui_src_build_event_reader() {
    local pipe="${1}"
    local lf="${2}"
    local line prefix_tok rest pct_str
    while IFS= read -r line || true; do
      [[ -z "${line}" ]] && continue
      prefix_tok="${line%%: *}"
      rest="${line#*: }"
      case "${prefix_tok}" in
        PROGRESS)
          pct_str="${rest%% *}"
          local msg_part="${rest#* }"
          if [[ "${pct_str}" =~ ^[0-9]+$ ]]; then
            printf '[%3d%%] %s\n' "${pct_str}" "${msg_part}" >> "${lf}" || true
          fi
          ;;
        LOG)  printf '        %s\n' "${rest}" >> "${lf}" || true ;;
        WARN) printf '  WARN  %s\n' "${rest}" >> "${lf}" || true ;;
        ERROR) printf ' ERROR  %s\n' "${rest}" >> "${lf}" || true ;;
        *)
          # MinGW script emits raw lines without a prefix — pass through
          printf '  %s\n' "${line}" >> "${lf}" || true
          ;;
      esac
    done < "${pipe}" || true
  }
  export -f _wb_gui_src_build_event_reader

  _wb_gui_src_build_event_reader "${event_pipe}" "${log_file}" &
  local reader_pid=$!

  # Launch source-build via W3 API, progress-fd → event_pipe
  (
    exec 3>"${event_pipe}"
    export WB_BUILD_PROGRESS_FD=3
    wb_gui_build_env_run_source_build "${slug}" >"${raw_out}" 2>&1
  ) &
  local builder_pid=$!

  # Show log tail while building
  wb_gui_dialog_log_tail "${dialog_title}" "${log_file}" &
  local yad_pid=$!

  while kill -0 "${yad_pid}" 2>/dev/null && kill -0 "${builder_pid}" 2>/dev/null; do
    sleep "${WB_GUI_BUILD_POLL_SEC:-0.3}"
  done

  if kill -0 "${builder_pid}" 2>/dev/null; then
    # User cancelled — SIGTERM → 5s → SIGKILL
    kill -TERM -- "-${builder_pid}" 2>/dev/null || true
    local elapsed=0
    while kill -0 "${builder_pid}" 2>/dev/null && [[ "${elapsed}" -lt 5 ]]; do
      sleep 1; (( elapsed++ )) || true
    done
    kill -KILL -- "-${builder_pid}" 2>/dev/null || true
  else
    sleep "${WB_GUI_BUILD_TAIL_DRAIN_SEC:-0.5}"
    kill "${yad_pid}" 2>/dev/null || true
  fi

  wait "${yad_pid}" 2>/dev/null || true
  local build_exit=0
  wait "${builder_pid}" 2>/dev/null || build_exit=$?
  kill "${reader_pid}" 2>/dev/null || true
  wait "${reader_pid}" 2>/dev/null || true

  case "${build_exit}" in
    0)
      # Success — post-build PATH + pip gap handling
      case "${slug}" in
        wb-build-glslang)
          # Extend PATH in the current wb-gui process so re-probe finds the new binary
          export PATH="${wb_home}/build-deps/glslang/bin:${PATH}"
          ;;
        build-mingw-from-source)
          # build-full-wine-deps.sh writes a ready-to-source PATH line to
          # $DEPS_DIR/.mingw-path after success. Source it so the re-probe
          # finds x86_64-w64-mingw32-gcc.  DEPS_DIR may live under either
          # $WB_WINE_SOURCE_ROOT/build-deps or $wb_home/build-deps — try both.
          local _mingw_path_file
          for _mingw_path_file in \
              "${WB_WINE_SOURCE_ROOT:-/does-not-exist}/build-deps/.mingw-path" \
              "${wb_home}/build-deps/.mingw-path"; do
            if [[ -r "${_mingw_path_file}" ]]; then
              # File format: `export PATH="..."`
              # shellcheck source=/dev/null
              source "${_mingw_path_file}"
              break
            fi
          done
          # Belt-and-braces: also add common candidates directly in case the
          # .mingw-path file is absent (e.g. older builds).
          for _mingw_bin_dir in \
              "${WB_WINE_SOURCE_ROOT:-/does-not-exist}/build-deps/mingw64-cross/bin" \
              "${wb_home}/build-deps/mingw64-cross/bin" \
              "${WB_WINE_SOURCE_ROOT:-/does-not-exist}/build-deps/x86_64-w64-mingw32-cross/bin" \
              "${wb_home}/build-deps/x86_64-w64-mingw32-cross/bin"; do
            if [[ -x "${_mingw_bin_dir}/x86_64-w64-mingw32-gcc" ]]; then
              case ":${PATH}:" in
                *":${_mingw_bin_dir}:"*) ;;   # already on PATH
                *) export PATH="${_mingw_bin_dir}:${PATH}" ;;
              esac
            fi
          done
          ;;
        pip-install-meson)
          # Check for PATH gap (D.4)
          if ! command -v meson &>/dev/null; then
            local local_bin="${HOME}/.local/bin"
            # Extend for this session
            export PATH="${local_bin}:${PATH}"
            wb_gui_dialog_info "meson installed — PATH update needed" \
              "meson was installed to ${local_bin}/meson, but that directory
was not on your PATH.

To fix permanently: add this to your shell startup file
(~/.bashrc or ~/.zshrc) and restart your terminal:
  export PATH=\"${local_bin}:\$PATH\"

For this session: wine-bleeding has already added it. Click OK and
then Re-check — meson should appear as OK."
          fi
          ;;
      esac
      ;;
    2)
      # Cancelled by user — no error dialog
      ;;
    *)
      # Build failure
      local last_lines=""
      if [[ -r "${raw_out}" ]]; then
        last_lines="$(tail -n 30 "${raw_out}" 2>/dev/null || true)"
      fi
      wb_gui_dialog_error "Source build failed" \
        "Build of ${slug} failed (exit ${build_exit}).
What happened: the source build exited with a non-zero code.
Why: see the last lines of output below.
Next action: open a terminal and run the build command manually to see the full error.

${last_lines}"
      ;;
  esac

  rm -rf "${tmp_dir}" 2>/dev/null || true
  return "${build_exit}"
}

# ---------------------------------------------------------------------------
# wb_gui_dialog_picker_single <title> <text> [items...]
#
# Small single-column yad --list picker (F5 fix — pre-select pattern).
# Used to pick a dist or app before the notebook renders that tab.
# stdout: selected item name on rc=0; empty on rc=1/252.
# ---------------------------------------------------------------------------
wb_gui_dialog_picker_single() {
  local title="${1:-Select}"
  local text="${2:-}"
  shift 2
  wb_gui_yad --list \
    --title="${title}" \
    --text="${text}" \
    --no-markup \
    --column="Name" \
    --separator="|" \
    --print-column=1 \
    --button="Select:0" \
    --button="Cancel:1" \
    "$@"
}

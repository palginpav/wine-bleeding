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
  local rc=0
  wb_gui_yad \
    --text-info \
    --tail \
    --filename="${log_file}" \
    --title="${title}" \
    --width=800 \
    --height=500 \
    --no-markup \
    --button="Cancel:1" 2>/dev/null || rc=$?
  return "${rc}"
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

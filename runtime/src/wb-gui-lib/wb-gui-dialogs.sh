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
# ---------------------------------------------------------------------------
_WB_GUI_YAD_COMMON=(
  --center
  --window-icon=wine-bleeding
  --width=600
)

# ---------------------------------------------------------------------------
# wb_gui_yad — call yad with common style flags prepended.
# Usage: wb_gui_yad [yad-args...]
# ---------------------------------------------------------------------------
wb_gui_yad() {
  yad "${_WB_GUI_YAD_COMMON[@]}" "$@"
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

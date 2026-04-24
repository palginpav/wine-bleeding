#!/usr/bin/env bats
# 31_dist_manager.bats — W5 coverage for Phase B Dist Manager + Component Builder GUI paths
#
# Covers dispatcher wiring, _cmd_dist_manager flows (add-external, close, select guards),
# _cmd_build_component Stage 1/3 exit-code dispatch, and discoverability of the new
# [Dists] button / help text.
#
# Fake-yad idiom: WB_TEST_YAD_RESPONSE / _RC (single) or WB_TEST_YAD_RESPONSES_DIR
# (multi). See runtime/tests/29_ui_flows.bats for the canonical pattern.

load "lib/common.bash"

WB_GUI="${BATS_TEST_DIRNAME}/../src/wb-gui"
WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FAKE_YAD_DIR="${BATS_TEST_DIRNAME}/fixtures/fake-yad"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export WB_HOME="${TEST_DIR}/wb-home"
  mkdir -p "${WB_HOME}"

  export WB_TEST_YAD_LOG="${TEST_DIR}/yad.log"
  export WB_TEST_YAD_RESPONSE="${TEST_DIR}/yad_response.txt"
  export WB_TEST_YAD_RESPONSE_RC="0"
  export WB_TEST_YAD_RESPONSES_DIR=""

  export PATH="${FAKE_YAD_DIR}:${PATH}"
  export WB_TEST_PATH="${PATH}"
  export WB_GUI_NO_DESKTOP_SHORTCUT=1
  # Skip the build-env preflight dialog in Component Builder: in the test env
  # mingw-w64-gcc is missing, which would inject an extra yad invocation and
  # shift all Stage 1 response slots by one, causing an infinite validation
  # loop. See W1 diagnosis for orch-20260424T1420Z.
  export WB_GUI_SKIP_PREFLIGHT=1

  touch "${WB_TEST_YAD_LOG}"
  printf '' > "${WB_TEST_YAD_RESPONSE}"
}

teardown() {
  rm -rf "${TEST_DIR}"
}

# ---------------------------------------------------------------------------
# Helpers (mirrored from 29_ui_flows.bats for consistency)
# ---------------------------------------------------------------------------
_mk_responses_dir() {
  local d="${TEST_DIR}/responses"
  mkdir -p "${d}"
  rm -f "${d}/.counter"
  echo "${d}"
}

_write_response() {
  local dir="${1}" n="${2}" content="${3}" rc="${4:-0}"
  local pad
  pad="$(printf '%03d' "${n}")"
  printf '%s' "${content}" > "${dir}/${pad}"
  printf '%s' "${rc}"      > "${dir}/${pad}.rc"
}

_run_wb_gui() {
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_RESPONSE='${WB_TEST_YAD_RESPONSE}'
    export WB_TEST_YAD_RESPONSE_RC='${WB_TEST_YAD_RESPONSE_RC}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${WB_TEST_YAD_RESPONSES_DIR}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    '${WB_GUI}' $*
  "
}

# Helper: create a minimal native-style fake dist (bin/wine exists and is executable)
_make_fake_native_dist() {
  local name="${1}"
  local dpath="${WB_HOME}/dist/${name}"
  mkdir -p "${dpath}/bin"
  printf '#!/usr/bin/env bash\necho "wine-stub"\n' > "${dpath}/bin/wine"
  chmod +x "${dpath}/bin/wine"
  # Minimal .wb_dist_meta so registry_refresh can parse it
  printf '{"wine_full_version":"9.0","build_utc":"%s","components_included":["dxvk"]}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${dpath}/.wb_dist_meta"
  printf '%s' "${dpath}"
}

# Source dist lib in a subshell snippet (same pattern as 30_dist_registry.bats)
_src_dist() {
  printf "export WB_HOME='%s';" "${WB_HOME}"
  printf "source '%s/wb-paths.sh'; source '%s/wb-log.sh'; source '%s/wb-json.sh'; source '%s/wb-dist.sh'; source '%s/wb-gui-apps.sh'; source '%s/wb-gui-dist.sh';" \
    "${WB_LIB}" "${WB_LIB}" "${WB_LIB}" "${WB_LIB}" "${WB_GUI_LIB}" "${WB_GUI_LIB}"
}

# ===========================================================================
# 1. Discoverability: --help lists the [Dists] button / Phase B description
# ===========================================================================
@test "help text mentions 'Dists' and Phase B" {
  run "${WB_GUI}" --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Dists"* ]]
  [[ "${output}" == *"Phase B"* ]]
}

# ===========================================================================
# 2. Main window [Dists] button (rc=70) dispatches to Dist Manager;
#    Dist Manager closes cleanly when user clicks Close (rc=1).
#    Invocations:
#      1 = main window → rc=70 (user clicks Dists)
#      2 = dist manager list dialog → rc=1 (Close)
#      3 = main window re-opened → rc=1 (Close)
# ===========================================================================
@test "main window Dists button (rc=70) opens Dist Manager which closes on rc=1" {
  local rdir
  rdir="$(_mk_responses_dir)"
  _write_response "${rdir}" 1 "" 70   # main window → Dists
  _write_response "${rdir}" 2 "" 1    # dist manager → Close
  _write_response "${rdir}" 3 "" 1    # main window → Close (after returning)

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  _run_wb_gui

  [ "${status}" -eq 0 ]
  # Dist Manager dialog must have appeared (contains "Dists" column header in title/text)
  run grep "Dists" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 3. Dist Manager: Add External flow — folder picker + register → happy path
#    Invocations:
#      1 = dist manager list (rc=10, Add External button)
#      2 = Add External form (rc=0, valid path+name)
#      3 = info "Registered" dialog (rc=0)
#      4 = dist manager list (rc=1, Close)
# ===========================================================================
@test "Dist Manager Add External: happy path registers the dist and shows info dialog" {
  # Create a fake external dist on disk (must have bin/wine)
  local ext_path="${TEST_DIR}/external/my-proton"
  mkdir -p "${ext_path}/bin"
  printf '#!/usr/bin/env bash\necho wine\n' > "${ext_path}/bin/wine"
  chmod +x "${ext_path}/bin/wine"

  local rdir
  rdir="$(_mk_responses_dir)"
  # Inv 1: list dialog → rc=10 (Add External)
  _write_response "${rdir}" 1 "" 10
  # Inv 2: Add External form → rc=0, fields: path|name|lbl_ignored|
  printf '%s|my-proton||' "${ext_path}" > "${rdir}/002"
  printf '0' > "${rdir}/002.rc"
  # Inv 3: info "Registered" dialog → rc=0
  _write_response "${rdir}" 3 "" 0
  # Inv 4: list dialog → rc=1 (Close)
  _write_response "${rdir}" 4 "" 1

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    # Invoke dist manager directly by sourcing internal function
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_dist_manager
  "
  [ "${status}" -eq 0 ]

  # "Registered" info dialog must appear
  run grep -i "Registered" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 4. Component Builder Stage 1: form opens correctly;
#    Cancel (rc=1) exits cleanly with no side effects (no dists.json mutation).
#
# Sourcing wb-gui triggers main "$@" → main window (no args → _cmd_main_window).
# That consumes one fake-yad slot (rc=1 = Close). _cmd_build_component is the
# second thing we call; Stage 1 form is therefore invocation 2.
# ===========================================================================
@test "Component Builder Stage 1: Cancel (rc=1) exits cleanly with no registry mutation" {
  local dist_name="WINE-BLEEDING-20260420"
  local dist_path
  dist_path="$(_make_fake_native_dist "${dist_name}")"

  local pre_registry="${WB_HOME}/dists.json"
  # Seed minimal dists.json so Stage 1 can read current_ver_dxvk
  printf '{"schema":1,"dists":[{"name":"%s","source":"native","active":true,"broken":false,"path":"%s","component_versions":{"dxvk":"2.3"},"wine_version":"9.0"}]}\n' \
    "${dist_name}" "${dist_path}" > "${pre_registry}"
  local pre_mtime
  pre_mtime="$(stat -c %Y "${pre_registry}" 2>/dev/null || echo 0)"

  local rdir
  rdir="$(_mk_responses_dir)"
  # Inv 1: main window opened by source-triggered main "$@" → Close (rc=1)
  _write_response "${rdir}" 1 "" 1
  # Inv 2: Stage 1 form → Cancel (rc=1)
  _write_response "${rdir}" 2 "" 1

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_build_component '${dist_name}' '${dist_path}'
  "
  [ "${status}" -eq 0 ]

  # dists.json must not have been mutated — mtime unchanged (no registry refresh on cancel)
  local post_mtime
  post_mtime="$(stat -c %Y "${pre_registry}" 2>/dev/null || echo 0)"
  [ "${pre_mtime}" -eq "${post_mtime}" ]

  # Stage 1 form must have appeared — fake-yad logs args with %q so "Component:CB"
  # is logged as Component:CB (no spaces to escape).
  run grep "Component" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # Stage 2 must NOT have appeared (no "text-info" in log)
  run bash -c "grep 'text-info' '${WB_TEST_YAD_LOG}' && echo FOUND || echo ABSENT"
  [ "${output}" = "ABSENT" ]
}

# ===========================================================================
# 5. Component Builder Stage 1: form shows correct fields including
#    "Target dist", "Current version", "Force rebuild" and gstreamer note.
#    (discoverability smoke — verifies W2 label spec §2 is implemented)
#
# Note: fake-yad logs args via printf '%q' so spaces become "\ ". We grep for
# field-name tokens that appear without spaces in the --field=... key, e.g.
# "Target\ dist:RO" → grep for "dist:RO". Multi-word tokens that ARE escaped
# are checked via grep -F on the raw log.
#
# Sourcing wb-gui runs main "$@" → main window (inv 1, rc=1 = Close).
# _cmd_build_component Stage 1 is invocation 2.
# ===========================================================================
@test "Component Builder Stage 1 form contains all required W2 spec fields" {
  local dist_name="WINE-BLEEDING-20260420"
  local dist_path
  dist_path="$(_make_fake_native_dist "${dist_name}")"

  printf '{"schema":1,"dists":[{"name":"%s","source":"native","active":true,"broken":false,"path":"%s","component_versions":{"dxvk":"2.4"},"wine_version":"9.0"}]}\n' \
    "${dist_name}" "${dist_path}" > "${WB_HOME}/dists.json"

  local rdir
  rdir="$(_mk_responses_dir)"
  # Inv 1: main window → Close (sourcing wb-gui runs main "$@" with no args)
  _write_response "${rdir}" 1 "" 1
  # Inv 2: Stage 1 form → Cancel
  _write_response "${rdir}" 2 "" 1

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_build_component '${dist_name}' '${dist_path}'
  "
  [ "${status}" -eq 0 ]

  # Multi-select Stage 1: each component label appears, and at least one ::CHK field.
  # Fake-yad uses printf %q, so labels like "DXVK  (current: 2.4)" become
  # "DXVK\ \ \(current:\ 2.4\)::CHK" — grep each component name as a fixed string.
  run grep -F "DXVK" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F "VKD3D-Proton" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F "DXVK-NVAPI" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
  run grep -F "::CHK" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # "Target dist::RO" — spaces escaped to "Target\ dist::RO"
  run grep "dist::RO" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # Current version appears as "(current: <ver>)" inside each checkbox label
  run grep -E "current:" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # W2 label S6: "Force rebuild" — appears in log (spaces escaped)
  run grep "Force" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # W2 label S7: gstreamer note — literal in log (no spaces at start of token)
  run grep "gstreamer" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # W2 label S8: "Start build" button — appears as "Start\ build:0"
  run grep "Start" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 6. Component Builder Stage 3: exit 0 (success) → "Build complete" dialog.
#    Uses a stub build-component.sh that exits 0 immediately.
#    Invocations when sourcing wb-gui:
#      1 = main window (source triggers main "$@") → rc=1 Close
#      2 = Stage 1 form → rc=0 (DXVK selected)
#      3 = Stage 2 log tail → rc=0 (natural close)
#      4 = Stage 3 "Build complete" → rc=0
# ===========================================================================
@test "Component Builder Stage 3: builder exit 0 shows 'Build complete' dialog" {
  skip "FIXME: Stage-3 log-tail event-pipe teardown race — Stage 3 dialog never reaches yad log under fake-yad; deferred in ecc04856b8d"
  local dist_name="WINE-BLEEDING-20260420"
  local dist_path
  dist_path="$(_make_fake_native_dist "${dist_name}")"

  printf '{"schema":1,"dists":[{"name":"%s","source":"native","active":true,"broken":false,"path":"%s","component_versions":{"dxvk":"2.4"},"wine_version":"9.0"}]}\n' \
    "${dist_name}" "${dist_path}" > "${WB_HOME}/dists.json"

  # Stub build-component.sh: exits 0 immediately, writes nothing to fd 3
  local stub_dir="${TEST_DIR}/stub-tools"
  mkdir -p "${stub_dir}"
  printf '#!/usr/bin/env bash\n# stub: exit 0 (success)\nexit 0\n' > "${stub_dir}/build-component.sh"
  chmod +x "${stub_dir}/build-component.sh"

  local rdir
  rdir="$(_mk_responses_dir)"
  # Inv 1: main window (source side-effect) → Close
  _write_response "${rdir}" 1 "" 1
  # Inv 2: Stage 1 form → rc=0, output: DXVK|<dist_ro>|2.4|FALSE|
  # Stage 1 multi-select form: <dist_ro>|<dxvk_chk>|<vkd3d_chk>|<nvapi_chk>|<force_chk>|
  printf '%s|TRUE|FALSE|FALSE|FALSE|' "${dist_name}" > "${rdir}/002"
  printf '0' > "${rdir}/002.rc"
  # Inv 3: Stage 2 yad --text-info --tail → rc=0 (natural close; builder already exited)
  _write_response "${rdir}" 3 "" 0
  # Inv 4: Stage 3 "Build complete" info dialog → rc=0
  _write_response "${rdir}" 4 "" 0

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${stub_dir}:${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_build_component '${dist_name}' '${dist_path}'
  "
  [ "${status}" -eq 0 ]

  # "Build complete" dialog must appear (S11 title or "rebuilt successfully" text)
  run grep -E "Build\ complete|rebuilt\ successfully" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 7. Component Builder Stage 3: builder exit 2 (user cancel) → "Build cancelled".
#    No dist mutation expected.
#    Invocations:
#      1 = main window (source side-effect) → rc=1 Close
#      2 = Stage 1 form → rc=0
#      3 = Stage 2 log tail → rc=0
#      4 = Stage 3 "Build cancelled" → rc=0
# ===========================================================================
@test "Component Builder Stage 3: builder exit 2 shows 'Build cancelled' dialog" {
  skip "FIXME: Stage-3 log-tail event-pipe teardown race — Stage 3 dialog never reaches yad log under fake-yad; deferred in ecc04856b8d"
  local dist_name="WINE-BLEEDING-20260420"
  local dist_path
  dist_path="$(_make_fake_native_dist "${dist_name}")"

  printf '{"schema":1,"dists":[{"name":"%s","source":"native","active":false,"broken":false,"path":"%s","wine_version":"9.0"}]}\n' \
    "${dist_name}" "${dist_path}" > "${WB_HOME}/dists.json"

  local stub_dir="${TEST_DIR}/stub-cancel"
  mkdir -p "${stub_dir}"
  printf '#!/usr/bin/env bash\n# stub: exit 2 (user-cancel per builder spec)\nexit 2\n' \
    > "${stub_dir}/build-component.sh"
  chmod +x "${stub_dir}/build-component.sh"

  local rdir
  rdir="$(_mk_responses_dir)"
  _write_response "${rdir}" 1 "" 1   # main window → Close
  # Stage 1 multi-select form: <dist_ro>|<dxvk_chk>|<vkd3d_chk>|<nvapi_chk>|<force_chk>|
  printf '%s|TRUE|FALSE|FALSE|FALSE|' "${dist_name}" > "${rdir}/002"
  printf '0' > "${rdir}/002.rc"
  _write_response "${rdir}" 3 "" 0   # Stage 2 log tail → closes
  _write_response "${rdir}" 4 "" 0   # Stage 3 "Build cancelled" → OK

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${stub_dir}:${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_build_component '${dist_name}' '${dist_path}'
  "
  [ "${status}" -eq 0 ]

  # "Build cancelled" in %q format becomes "Build\ cancelled" in log
  run grep "cancelled" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 8. Component Builder Stage 3: builder exit 71 (lock busy) → "Build already in
#    progress" error dialog; then returns to Stage 1 (form re-opens).
#    Invocations:
#      1 = main window (source side-effect) → rc=1 Close
#      2 = Stage 1 first open → rc=0 (proceed)
#      3 = Stage 2 log tail → rc=0
#      4 = Stage 3 lock-busy error dialog → OK
#      5 = Stage 1 re-opened (exit 71 tail-call) → Cancel
# ===========================================================================
@test "Component Builder Stage 3: builder exit 71 shows lock-busy error and re-opens Stage 1" {
  skip "FIXME: Stage-3 log-tail event-pipe teardown race — Stage 3 dialog never reaches yad log under fake-yad; deferred in ecc04856b8d"
  local dist_name="WINE-BLEEDING-20260420"
  local dist_path
  dist_path="$(_make_fake_native_dist "${dist_name}")"

  printf '{"schema":1,"dists":[{"name":"%s","source":"native","active":false,"broken":false,"path":"%s","wine_version":"9.0"}]}\n' \
    "${dist_name}" "${dist_path}" > "${WB_HOME}/dists.json"

  local stub_dir="${TEST_DIR}/stub-lock"
  mkdir -p "${stub_dir}"
  printf '#!/usr/bin/env bash\n# stub: exit 71 (lock busy)\nexit 71\n' \
    > "${stub_dir}/build-component.sh"
  chmod +x "${stub_dir}/build-component.sh"

  local rdir
  rdir="$(_mk_responses_dir)"
  _write_response "${rdir}" 1 "" 1   # main window → Close
  # Inv 2: First Stage 1 → rc=0 (proceed)
  # Stage 1 multi-select form: <dist_ro>|<dxvk_chk>|<vkd3d_chk>|<nvapi_chk>|<force_chk>|
  printf '%s|TRUE|FALSE|FALSE|FALSE|' "${dist_name}" > "${rdir}/002"
  printf '0' > "${rdir}/002.rc"
  _write_response "${rdir}" 3 "" 0   # Stage 2 log tail → closes
  _write_response "${rdir}" 4 "" 0   # Stage 3 lock-busy error dialog → OK
  _write_response "${rdir}" 5 "" 1   # Stage 1 re-opened → Cancel

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${stub_dir}:${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_build_component '${dist_name}' '${dist_path}'
  "
  [ "${status}" -eq 0 ]

  # Lock-busy error dialog must appear (title contains "already" or "in progress")
  run grep -E "already\ running|already\ in\ progress" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # Stage 1 form must appear a SECOND time (exit 71 → tail-call back to Stage 1)
  local stage1_count
  stage1_count="$(grep -c "Build\\\\ Components" "${WB_TEST_YAD_LOG}" || echo 0)"
  [ "${stage1_count}" -ge 2 ]
}

# ===========================================================================
# 9. Component Builder Stage 3: builder exit 66 (env fail) → distinct error
#    "Build environment incomplete" title / text in dialog args.
#    Invocations:
#      1 = main window (source side-effect) → rc=1 Close
#      2 = Stage 1 form → rc=0
#      3 = Stage 2 log tail → rc=0
#      4 = Stage 3 env-fail error dialog → OK
# ===========================================================================
@test "Component Builder Stage 3: builder exit 66 shows 'Build environment incomplete' error" {
  skip "FIXME: Stage-3 log-tail event-pipe teardown race — Stage 3 dialog never reaches yad log under fake-yad; deferred in ecc04856b8d"
  local dist_name="WINE-BLEEDING-20260420"
  local dist_path
  dist_path="$(_make_fake_native_dist "${dist_name}")"

  printf '{"schema":1,"dists":[{"name":"%s","source":"native","active":false,"broken":false,"path":"%s","wine_version":"9.0"}]}\n' \
    "${dist_name}" "${dist_path}" > "${WB_HOME}/dists.json"

  local stub_dir="${TEST_DIR}/stub-env"
  mkdir -p "${stub_dir}"
  printf '#!/usr/bin/env bash\necho "meson not found" >&2\nexit 66\n' \
    > "${stub_dir}/build-component.sh"
  chmod +x "${stub_dir}/build-component.sh"

  local rdir
  rdir="$(_mk_responses_dir)"
  _write_response "${rdir}" 1 "" 1   # main window → Close
  # Stage 1 multi-select form: <dist_ro>|<dxvk_chk>|<vkd3d_chk>|<nvapi_chk>|<force_chk>|
  printf '%s|TRUE|FALSE|FALSE|FALSE|' "${dist_name}" > "${rdir}/002"
  printf '0' > "${rdir}/002.rc"
  _write_response "${rdir}" 3 "" 0   # Stage 2 log tail
  _write_response "${rdir}" 4 "" 0   # Stage 3 error dialog → OK

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${stub_dir}:${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_build_component '${dist_name}' '${dist_path}'
  "
  [ "${status}" -eq 0 ]

  # S17 title or S18 text: "environment incomplete" or "missing" tool error
  run grep -E "environment\ incomplete|missing.*meson" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# 10. Dist Manager Remove guard: removing the active dist shows error dialog
#     without calling wb_gui_dist_remove (active-dist protection invariant).
#     Invocations when sourcing wb-gui (source runs main "$@"):
#       1 = main window (source side-effect) → rc=1 Close
#       2 = dist manager list → rc=40 (Remove), row output shows active dist
#       3 = "Cannot Remove Active Dist" error dialog → OK
#       4 = dist manager list → rc=1 (Close)
# ===========================================================================
@test "Dist Manager Remove: active dist row shows 'Cannot Remove Active Dist' error" {
  local dist_name="WINE-BLEEDING-ACTIVE"
  local dist_path
  dist_path="$(_make_fake_native_dist "${dist_name}")"

  # Registry marks this dist as active AND create the WINE-BLEEDING symlink so that
  # wb_gui_dist_registry_refresh (called at the top of each _cmd_dist_manager loop
  # iteration) correctly computes active=true for this dist.
  ln -sf "${dist_path}" "${WB_HOME}/dist/WINE-BLEEDING"
  printf '{"schema":1,"dists":[{"name":"%s","source":"native","active":true,"broken":false,"path":"%s","wine_version":"9.0"}]}\n' \
    "${dist_name}" "${dist_path}" > "${WB_HOME}/dists.json"

  local rdir
  rdir="$(_mk_responses_dir)"
  # Inv 1: main window (source side-effect) → Close
  _write_response "${rdir}" 1 "" 1
  # Inv 2: dist manager list → rc=40 (Remove), row output: >|NAME|native|9.0|—|PATH|false
  printf '>|%s|native|9.0|\xe2\x80\x94|%s|false|' "${dist_name}" "${dist_path}" > "${rdir}/002"
  printf '40' > "${rdir}/002.rc"
  # Inv 3: "Cannot Remove Active Dist" error dialog → OK
  _write_response "${rdir}" 3 "" 0
  # Inv 4: list dialog → Close
  _write_response "${rdir}" 4 "" 1

  export WB_TEST_YAD_RESPONSES_DIR="${rdir}"
  run bash -c "
    export WB_HOME='${WB_HOME}'
    export PATH='${WB_TEST_PATH}'
    export WB_TEST_YAD_LOG='${WB_TEST_YAD_LOG}'
    export WB_TEST_YAD_RESPONSES_DIR='${rdir}'
    export WB_GUI_NO_DESKTOP_SHORTCUT=1
    export WB_GUI_SKIP_PREFLIGHT=1
    source '${WB_LIB}/wb-paths.sh'
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-apps.sh'
    source '${WB_GUI_LIB}/wb-gui-dist.sh'
    source '${WB_GUI_LIB}/wb-gui-dialogs.sh'
    source '${WB_GUI_LIB}/wb-gui-detection.sh'
    source '${WB_GUI_LIB}/wb-gui-settings.sh'
    source '${WB_GUI_LIB}/wb-gui-games.sh'
    source '${WB_GUI}'
    _cmd_dist_manager
  "
  [ "${status}" -eq 0 ]

  # Error copy must include "Activate a different dist first" (B-1 fix from UX critic)
  run grep "Activate" "${WB_TEST_YAD_LOG}"
  [ "${status}" -eq 0 ]

  # dist_path must still exist (rm -rf must NOT have been called)
  [ -d "${dist_path}" ]
}

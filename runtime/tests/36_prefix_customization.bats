#!/usr/bin/env bats
# 36_prefix_customization.bats — Phase D backend unit tests (W3)
#
# Tests wb-gui-prefix.sh functions:
#   - wb_gui_prefix_save_env_bake (wb.conf write, managed keys, preservation)
#   - wb_gui_prefix_reg_write / _reg_undo / _reg_safe_zone_check
#   - wb_gui_prefix_dll_set / _dll_remove
#   - wb_gui_prefix_component_toggle
#   - wb_gui_prefix_winetricks_list / _reconcile / _winetricks_available / _install
#
# Fixtures:
#   fake-winetricks: WB_TEST_WT_FIXTURE seam
#   fake-wine-reg:   WB_TEST_WINE_REG_FIXTURE seam

load "lib/common.bash"

WB_GUI_LIB="${BATS_TEST_DIRNAME}/../src/wb-gui-lib"
WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FAKE_WT_DIR="${BATS_TEST_DIRNAME}/fixtures/fake-winetricks"
FAKE_WINE_REG="${BATS_TEST_DIRNAME}/fixtures/fake-wine-reg/wine"

# ---------------------------------------------------------------------------
# Per-test setup / teardown
# ---------------------------------------------------------------------------
setup() {
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR
  export WB_HOME="${TEST_DIR}/wb-home"
  mkdir -p \
    "${WB_HOME}/settings/prefixes" \
    "${WB_HOME}/settings/apps" \
    "${WB_HOME}/prefixes/testpfx" \
    "${WB_HOME}/overlays/.cache" \
    "${WB_HOME}/etc"

  export WB_TEST_WT_FIXTURE="${FAKE_WT_DIR}/winetricks"
  export WB_TEST_WINE_REG_FIXTURE="${FAKE_WINE_REG}"
  export WB_GUI_PREFIX_NOW_UTC="2026-04-20T12:00:00Z"

  # Initialize a minimal prefix settings JSON
  cat > "${WB_HOME}/settings/prefixes/testpfx.json" <<'JSON'
{
  "schema": 1,
  "prefix_id": "testpfx",
  "updated_utc": "2026-04-20T00:00:00Z"
}
JSON

  # Initialize the fake shadow registry
  cat > "${WB_HOME}/prefixes/testpfx/.fake_registry.json" <<'JSON'
{
  "HKCU\\Software\\Wine\\Direct3D": {
    "MaxShaderModel": {"type": "REG_DWORD", "data": "0x5"},
    "csmt": {"type": "REG_SZ", "data": "enabled"}
  },
  "HKCU\\Software\\Wine": {
    "Version": {"type": "REG_SZ", "data": "win10"}
  }
}
JSON
}

teardown() {
  rm -rf "${TEST_DIR}"
}

# ---------------------------------------------------------------------------
# Source snippet helper — loads all deps + wb-gui-prefix.sh in a subshell
# ---------------------------------------------------------------------------
_src_prefix() {
  printf "set -euo pipefail;"
  printf "export WB_HOME='%s';" "${WB_HOME}"
  printf "export WB_TEST_WT_FIXTURE='%s';" "${WB_TEST_WT_FIXTURE}"
  printf "export WB_TEST_WINE_REG_FIXTURE='%s';" "${WB_TEST_WINE_REG_FIXTURE}"
  printf "export WB_GUI_PREFIX_NOW_UTC='%s';" "${WB_GUI_PREFIX_NOW_UTC}"
  printf "export WINEPREFIX='%s/prefixes/testpfx';" "${WB_HOME}"
  printf "source '%s/wb-log.sh' 2>/dev/null || true;" "${WB_LIB}"
  printf "source '%s/wb-json.sh';" "${WB_LIB}"
  printf "source '%s/wb-gui-settings.sh';" "${WB_GUI_LIB}"
  printf "source '%s/wb-gui-prefix.sh';" "${WB_GUI_LIB}"
}

# ===========================================================================
# GROUP 1 — save_env_bake: wb.conf write correctness
# ===========================================================================

# T01: save_env_bake with dxvk=on writes WB_DXVK=1 to wb.conf
@test "save_env_bake: dxvk=on writes WB_DXVK=1 to prefix wb.conf" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_component_toggle testpfx dxvk on
    cat '${WB_HOME}/prefixes/testpfx/wb.conf'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WB_DXVK=1"* ]]
}

# T02: save_env_bake with dxvk=off writes WB_DXVK=0
@test "save_env_bake: dxvk=off writes WB_DXVK=0 to prefix wb.conf" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_component_toggle testpfx dxvk off
    cat '${WB_HOME}/prefixes/testpfx/wb.conf'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WB_DXVK=0"* ]]
}

# T03: save_env_bake with inherit removes managed key — wb.conf must not contain WB_DXVK
@test "save_env_bake: inherit removes WB_DXVK from wb.conf" {
  run bash -c "$(_src_prefix)
    # First set dxvk=on so there's something to remove
    wb_gui_prefix_component_toggle testpfx dxvk on
    # Now inherit — managed key should be stripped
    wb_gui_prefix_component_toggle testpfx dxvk inherit
    conf='${WB_HOME}/prefixes/testpfx/wb.conf'
    if grep -q 'WB_DXVK' \"\${conf}\" 2>/dev/null; then
      echo 'FAIL: WB_DXVK still present' >&2
      exit 1
    fi
    echo 'ok'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "ok" ]]
}

# T04: save_env_bake preserves user-set keys that are NOT in managed list
@test "save_env_bake: user-set wb.conf keys preserved bit-identically" {
  # Write a user key into wb.conf before the bake
  echo "WINEDEBUG=-all" > "${WB_HOME}/prefixes/testpfx/wb.conf"
  run bash -c "$(_src_prefix)
    wb_gui_prefix_component_toggle testpfx vkd3d on
    cat '${WB_HOME}/prefixes/testpfx/wb.conf'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WINEDEBUG=-all"* ]]
  [[ "${output}" == *"WB_VKD3D=1"* ]]
}

# T05: save_env_bake rewrites managed keys atomically on second call
@test "save_env_bake: second bake rewrites managed keys cleanly (no duplicates)" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_component_toggle testpfx dxvk on
    wb_gui_prefix_component_toggle testpfx dxvk off
    conf='${WB_HOME}/prefixes/testpfx/wb.conf'
    count=\$(grep -c 'WB_DXVK' \"\${conf}\" 2>/dev/null || echo 0)
    echo \"count=\${count}\"
    grep 'WB_DXVK' \"\${conf}\"
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"count=1"* ]]
  [[ "${output}" == *"WB_DXVK=0"* ]]
}

# T06: dll_set composes WB_EXTRA_DLLOVERRIDES in wb.conf
@test "save_env_bake: dll_set causes WB_EXTRA_DLLOVERRIDES to appear in wb.conf" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_dll_set testpfx d3d11 native
    cat '${WB_HOME}/prefixes/testpfx/wb.conf'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WB_EXTRA_DLLOVERRIDES"* ]]
  [[ "${output}" == *"d3d11=n"* ]]
}

# ===========================================================================
# GROUP 2 — dll_set / dll_remove
# ===========================================================================

# T07: dll_set adds entry to dll_overrides array in JSON
@test "dll_set: adds entry to dll_overrides JSON array" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_dll_set testpfx msvcr120 'n,b'
    jq '.dll_overrides' '${WB_HOME}/settings/prefixes/testpfx.json'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"msvcr120"'* ]]
  [[ "${output}" == *'"n,b"'* ]]
}

# T08: dll_set rejects invalid DLL name
@test "dll_set: rejects DLL name with invalid characters" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_dll_set testpfx 'bad;name' native
  "
  [ "${status}" -ne 0 ]
}

# T09: dll_set rejects invalid mode
@test "dll_set: rejects invalid override mode" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_dll_set testpfx d3d11 wrong_mode
  "
  [ "${status}" -ne 0 ]
}

# T10: dll_remove removes entry from array
@test "dll_remove: removes DLL entry from dll_overrides" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_dll_set testpfx d3d11 native
    wb_gui_prefix_dll_remove testpfx d3d11
    jq '.dll_overrides' '${WB_HOME}/settings/prefixes/testpfx.json'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "[]" ]]
}

# T11: disabled mode maps to empty right-hand-side (dll=)
@test "dll_set: disabled mode composes to 'dll=' in WB_EXTRA_DLLOVERRIDES" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_dll_set testpfx nvapi64 disabled
    cat '${WB_HOME}/prefixes/testpfx/wb.conf'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"nvapi64="* ]]
}

# ===========================================================================
# GROUP 3 — component_toggle
# ===========================================================================

# T12: component_toggle writes to settings JSON
@test "component_toggle: writes components_enabled to settings JSON" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_component_toggle testpfx nvapi on
    jq '.components_enabled' '${WB_HOME}/settings/prefixes/testpfx.json'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"nvapi": "on"'* ]] || [[ "${output}" == *'"nvapi":"on"'* ]]
}

# T13: component_toggle rejects unknown component
@test "component_toggle: rejects unknown component name" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_component_toggle testpfx gstreamer on
  "
  [ "${status}" -ne 0 ]
}

# T14: component_toggle rejects invalid state
@test "component_toggle: rejects invalid state value" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_component_toggle testpfx dxvk maybe
  "
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# GROUP 4 — reg_safe_zone_check
# ===========================================================================

# T15: HKCU\Software\Wine is writable
@test "reg_safe_zone_check: HKCU\\\\Software\\\\Wine returns writable" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKCU\\Software\\Wine'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "writable" ]]
}

# T16: HKCU\Software\Wine\Direct3D subtree is writable
@test "reg_safe_zone_check: HKCU\\\\Software\\\\Wine\\\\Direct3D is writable" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKCU\\Software\\Wine\\Direct3D'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "writable" ]]
}

# T17: HKCU\Environment is writable
@test "reg_safe_zone_check: HKCU\\\\Environment is writable" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKCU\\Environment'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "writable" ]]
}

# T18: HKCU\Control Panel\Desktop is writable
@test "reg_safe_zone_check: HKCU\\\\Control Panel\\\\Desktop is writable" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKCU\\Control Panel\\Desktop'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "writable" ]]
}

# T19: HKCU\Control Panel\International is writable
@test "reg_safe_zone_check: HKCU\\\\Control Panel\\\\International is writable" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKCU\\Control Panel\\International'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "writable" ]]
}

# T20: HKLM\System\CurrentControlSet\Services\Wine is writable
@test "reg_safe_zone_check: HKLM\\\\System\\\\CurrentControlSet\\\\Services\\\\Wine is writable" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKLM\\System\\CurrentControlSet\\Services\\Wine'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "writable" ]]
}

# T21: HKLM\Software\Wine is writable
@test "reg_safe_zone_check: HKLM\\\\Software\\\\Wine is writable" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKLM\\Software\\Wine'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "writable" ]]
}

# T22: HKCR (root) is read-only (not in write allowlist)
@test "reg_safe_zone_check: HKCR is readonly" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKCR\\Something'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "readonly" ]]
}

# T23: HKU is read-only
@test "reg_safe_zone_check: HKU is readonly" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKU\\S-1-5-21-12345'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "readonly" ]]
}

# T24: HKLM\Software\Microsoft is read-only (not in allowlist)
@test "reg_safe_zone_check: HKLM\\\\Software\\\\Microsoft is readonly" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKLM\\Software\\Microsoft'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "readonly" ]]
}

# T25: HKLM\System\CurrentControlSet\Control is read-only (not under \Services\Wine)
@test "reg_safe_zone_check: HKLM\\\\System\\\\CurrentControlSet\\\\Control is readonly" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKLM\\System\\CurrentControlSet\\Control'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "readonly" ]]
}

# T26: HKCU\Software\SomeOtherApp is read-only (not under Wine)
@test "reg_safe_zone_check: HKCU\\\\Software\\\\SomeOtherApp is readonly" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'HKCU\\Software\\SomeOtherApp'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "readonly" ]]
}

# T27: Completely invalid root returns invalid
@test "reg_safe_zone_check: garbage key returns invalid" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_safe_zone_check 'NOTAREG\\Something'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "invalid" ]]
}

# ===========================================================================
# GROUP 5 — reg_write / reg_undo
# ===========================================================================

# T28: reg_write records patch in FIFO stack and fake-wine-reg updates shadow
@test "reg_write: records patch in wine_registry_patches JSON" {
  run bash -c "$(_src_prefix)
    export WINEPREFIX='${WB_HOME}/prefixes/testpfx'
    wb_gui_prefix_reg_write testpfx 'HKCU\\Software\\Wine\\Direct3D' MaxShaderModel REG_DWORD 0x6
    jq '.wine_registry_patches | length' '${WB_HOME}/settings/prefixes/testpfx.json'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "1" ]]
}

# T29: reg_write rejects keys outside safe-zone (exit 74)
@test "reg_write: rejects HKCR write with exit 74" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_write testpfx 'HKCR\\SomeKey' SomeVal REG_SZ somedata
  "
  [ "${status}" -eq 74 ]
}

# T30: reg_write rejects HKLM\Software\Microsoft write
@test "reg_write: rejects HKLM\\\\Software\\\\Microsoft write" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_write testpfx 'HKLM\\Software\\Microsoft' SomeVal REG_SZ data
  "
  [ "${status}" -eq 74 ]
}

# T31: reg_write rejects HKU write
@test "reg_write: rejects HKU write" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_write testpfx 'HKU\\S-1-5-21-0000\\SomeKey' Val REG_SZ data
  "
  [ "${status}" -eq 74 ]
}

# T32: reg_undo pops last patch and restores (via fake-wine-reg)
@test "reg_undo: pops last patch; stack shrinks by one" {
  run bash -c "$(_src_prefix)
    export WINEPREFIX='${WB_HOME}/prefixes/testpfx'
    wb_gui_prefix_reg_write testpfx 'HKCU\\Software\\Wine\\Direct3D' MaxShaderModel REG_DWORD 0x6
    wb_gui_prefix_reg_undo testpfx
    jq '.wine_registry_patches | length' '${WB_HOME}/settings/prefixes/testpfx.json'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "0" ]]
}

# T33: reg_undo on empty stack returns non-zero
@test "reg_undo: empty stack returns non-zero" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_reg_undo testpfx
  "
  [ "${status}" -ne 0 ]
}

# T34: undo stack caps at 10 entries (FIFO eviction)
@test "reg_write: undo stack caps at 10 entries (FIFO eviction)" {
  run bash -c "$(_src_prefix)
    export WINEPREFIX='${WB_HOME}/prefixes/testpfx'
    for i in \$(seq 1 12); do
      wb_gui_prefix_reg_write testpfx 'HKCU\\Software\\Wine\\Direct3D' \"TestVal\${i}\" REG_SZ \"data\${i}\"
    done
    jq '.wine_registry_patches | length' '${WB_HOME}/settings/prefixes/testpfx.json'
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "10" ]]
}

# ===========================================================================
# GROUP 6 — winetricks_list / winetricks_reconcile
# ===========================================================================

# T35: winetricks_list returns empty array for new prefix
@test "winetricks_list: returns empty array for prefix with no verbs" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_winetricks_list testpfx
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "[]" ]]
}

# T36: winetricks_reconcile parses winetricks.log correctly
@test "winetricks_reconcile: parses winetricks.log into JSON array" {
  cat > "${WB_HOME}/prefixes/testpfx/winetricks.log" <<'LOG'
20260219122345 vcrun2019
20260301091512 d3dcompiler_43
LOG
  run bash -c "$(_src_prefix)
    wb_gui_prefix_winetricks_reconcile testpfx
    wb_gui_prefix_winetricks_list testpfx
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"vcrun2019"'* ]]
  [[ "${output}" == *'"d3dcompiler_43"'* ]]
}

# T37: winetricks_reconcile handles missing winetricks.log (empty prefix)
@test "winetricks_reconcile: missing log results in empty verb list" {
  rm -f "${WB_HOME}/prefixes/testpfx/winetricks.log"
  run bash -c "$(_src_prefix)
    wb_gui_prefix_winetricks_reconcile testpfx
    wb_gui_prefix_winetricks_list testpfx
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == "[]" ]]
}

# T38: winetricks_reconcile deduplicates verbs (last occurrence kept, order preserved)
@test "winetricks_reconcile: deduplicates verbs from log" {
  cat > "${WB_HOME}/prefixes/testpfx/winetricks.log" <<'LOG'
20260101000000 vcrun2019
20260102000000 d3dcompiler_43
20260103000000 vcrun2019
LOG
  run bash -c "$(_src_prefix)
    wb_gui_prefix_winetricks_reconcile testpfx
    wb_gui_prefix_winetricks_list testpfx | jq 'length'
  "
  [ "${status}" -eq 0 ]
  # vcrun2019 appears twice in log but only once in the array
  [[ "${output}" == "2" ]]
}

# T39: winetricks_available returns verb|cat|desc lines (via fake fixture)
@test "winetricks_available: returns verb|category|description lines from fixture" {
  run bash -c "$(_src_prefix)
    wb_gui_prefix_winetricks_available
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"vcrun2019|dlls|"* ]]
  [[ "${output}" == *"arial|fonts|"* ]]
}

# T40: winetricks_install spawns run-winetricks.sh and returns a PID
@test "winetricks_install: spawns process and returns PID (via fake fixture)" {
  # We need a valid dist path with bin/wine for run-winetricks.sh
  mkdir -p "${WB_HOME}/dist/WINE-BLEEDING-active/bin"
  cp "${WB_TEST_WINE_REG_FIXTURE}" "${WB_HOME}/dist/WINE-BLEEDING-active/bin/wine"
  chmod +x "${WB_HOME}/dist/WINE-BLEEDING-active/bin/wine"

  run bash -c "$(_src_prefix)
    pid=\$(wb_gui_prefix_winetricks_install testpfx vcrun2019 2>/dev/null) || true
    echo \"\${pid}\"
    # Give the background process a moment then check it exited
    sleep 2
    if kill -0 \"\${pid}\" 2>/dev/null; then
      echo 'still_running'
    else
      echo 'completed'
    fi
  "
  [ "${status}" -eq 0 ]
  # Should have printed a numeric PID then 'completed'
  [[ "${output}" =~ ^[0-9]+ ]]
}

# T41: winetricks_reconcile skips lines that don't match expected format (malformed)
@test "winetricks_reconcile: skips malformed log lines gracefully" {
  cat > "${WB_HOME}/prefixes/testpfx/winetricks.log" <<'LOG'
this is a bad line
20260219122345 vcrun2019
ANOTHER BAD LINE 123
20260301091512 d3dcompiler_43
LOG
  run bash -c "$(_src_prefix)
    wb_gui_prefix_winetricks_reconcile testpfx
    wb_gui_prefix_winetricks_list testpfx
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"vcrun2019"'* ]]
  [[ "${output}" == *'"d3dcompiler_43"'* ]]
  # Should be exactly 2 verbs (bad lines skipped)
  count="$(printf '%s' "${output}" | jq 'length' 2>/dev/null || echo "?")"
  [[ "${count}" == "2" ]]
}

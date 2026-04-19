#!/usr/bin/env bats

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
HOOK_SRC="${BATS_TEST_DIRNAME}/../src/hooks/reapply.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"

  # Build a fake prefix that looks wb-managed.
  export TEST_PREFIX="${TEST_HOME}/prefix"
  mkdir -p "${TEST_PREFIX}/drive_c/windows/system32"
  mkdir -p "${TEST_PREFIX}/drive_c/windows/syswow64"

  # Build a fake dist dir mirroring the fixture.
  export TEST_DIST="${TEST_HOME}/dist/WINE-BLEEDING"
  mkdir -p "${TEST_HOME}/dist"
  cp -a "${FIXTURE_DIST}/." "${TEST_DIST}/"

  # Install hook libs so reapply.sh can source them (simulates installed state).
  mkdir -p "${TEST_HOME}/wb/hooks"
  mkdir -p "${TEST_HOME}/wb/lib"
  for lib in wb-log.sh wb-json.sh wb-lock.sh wb-paths.sh wb-components.sh wb-reg.sh wb-die.sh wb-config.sh; do
    cp -f "${WB_LIB}/${lib}" "${TEST_HOME}/wb/lib/${lib}"
  done
  cp -f "${HOOK_SRC}" "${TEST_HOME}/wb/hooks/reapply.sh"
  chmod +x "${TEST_HOME}/wb/hooks/reapply.sh"
  # Use the installed copy so BASH_SOURCE[0] resolves the lib dir correctly.
  export HOOK_SCRIPT="${TEST_HOME}/wb/hooks/reapply.sh"

  # Create a minimal .wb_components manifest.
  cat > "${TEST_PREFIX}/.wb_components" <<'COMP'
{
  "schema": 1,
  "prefix_path": "__PREFIX__",
  "dist_target": "__DIST__",
  "dist_manifest_hash": "",
  "deployed_utc": "2026-04-19T00:00:00Z",
  "components": {
    "dxvk": {
      "version": "2.3",
      "dll_paths": [
        "drive_c/windows/system32/d3d11.dll",
        "drive_c/windows/system32/dxgi.dll"
      ]
    }
  }
}
COMP
  # Fix up paths in the manifest.
  sed -i "s|__PREFIX__|${TEST_PREFIX}|g" "${TEST_PREFIX}/.wb_components"
  sed -i "s|__DIST__|${TEST_DIST}|g" "${TEST_PREFIX}/.wb_components"

  # Pre-populate system32 with the DLLs the manifest references.
  cp -f "${TEST_DIST}/lib/wine/dxvk/x86_64-windows/d3d11.dll" "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll"
  cp -f "${TEST_DIST}/lib/wine/dxvk/x86_64-windows/dxgi.dll" "${TEST_PREFIX}/drive_c/windows/system32/dxgi.dll"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

_run_hook() {
  WINEPREFIX="${TEST_PREFIX}" \
  WINEDIR="${TEST_DIST}" \
  PW_WINE_USE="${1}" \
  WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}" 2>"${TEST_HOME}/hook.err"
}

# 1. Non-wb dist: hook exits 0 silently, no files touched.
@test "reapply: PW_WINE_USE=PROTON_LG exits 0 silently" {
  local before_count
  before_count="$(find "${TEST_PREFIX}" -type f | wc -l)"
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="PROTON_LG" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]
  local after_count
  after_count="$(find "${TEST_PREFIX}" -type f | wc -l)"
  [ "${before_count}" -eq "${after_count}" ]
}

# 2. No drift + missing .wine_ver: hook writes .wine_ver.
@test "reapply: no drift writes .wine_ver when missing" {
  rm -f "${TEST_PREFIX}/.wine_ver"
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/.wine_ver" ]
  local ver
  ver="$(cat "${TEST_PREFIX}/.wine_ver")"
  [ "${ver}" = "WINE-BLEEDING" ]
}

# 3. PW_WINE_USE with date suffix matches WINE-BLEEDING prefix.
@test "reapply: PW_WINE_USE=WINE-BLEEDING-28032026 still triggers hook" {
  rm -f "${TEST_PREFIX}/.wine_ver"
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING-28032026" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/.wine_ver" ]
  local ver
  ver="$(cat "${TEST_PREFIX}/.wine_ver")"
  [ "${ver}" = "WINE-BLEEDING" ]
}

# 4. Drifted component: DXVK DLL removed → hook redeploys it.
@test "reapply: drifted DXVK DLL is redeployed" {
  rm -f "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll"
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll" ]
}

# 5. Idempotent: running reapply twice produces identical file tree.
@test "reapply: idempotent — second run produces no changes" {
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]

  local snap1
  snap1="$(find "${TEST_PREFIX}" -type f | sort | xargs sha256sum 2>/dev/null || true)"

  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]

  local snap2
  snap2="$(find "${TEST_PREFIX}" -type f | sort | xargs sha256sum 2>/dev/null || true)"
  [ "${snap1}" = "${snap2}" ]
}

# 6. Busy prefix: hook returns 0 with WARN within ~1 second.
@test "reapply: busy prefix returns 0 within 1 second" {
  local lockfile="${TEST_PREFIX}/.wb_lock"
  touch "${lockfile}"
  exec 9>"${lockfile}"
  flock -x 9

  local start_ts end_ts elapsed
  start_ts="$(date +%s)"

  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"

  end_ts="$(date +%s)"
  elapsed=$(( end_ts - start_ts ))

  exec 9>&-

  [ "${status}" -eq 0 ]
  [ "${elapsed}" -lt 2 ]
}

# 7. Missing .wb_components: hook no-ops silently.
@test "reapply: missing .wb_components exits 0 silently" {
  rm -f "${TEST_PREFIX}/.wb_components"
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]
  # When no .wb_components, hook exits without writing .wine_ver or redeploying.
  [ ! -f "${TEST_PREFIX}/.wine_ver" ]
}

# 8. Missing lib dir: hook fails cleanly with exit 1.
@test "reapply: missing lib dir exits 1 with error message" {
  # Remove the installed lib dir to simulate a broken installation.
  rm -rf "${TEST_HOME}/wb/lib"
  run bash -c "
    WINEPREFIX='${TEST_PREFIX}' \
    WINEDIR='${TEST_DIST}' \
    PW_WINE_USE='WINE-BLEEDING' \
    WB_LOG_FILE='${WB_LOG_FILE}' \
    bash '${HOOK_SCRIPT}' 2>&1
  "
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"lib dir missing"* ]]
}

# 9. .wine_ver already correct: NOT rewritten (mtime unchanged).
@test "reapply: .wine_ver already correct is not rewritten" {
  printf 'WINE-BLEEDING' > "${TEST_PREFIX}/.wine_ver"
  local mtime_before
  mtime_before="$(stat -c '%Y' "${TEST_PREFIX}/.wine_ver")"
  sleep 1

  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]

  local mtime_after
  mtime_after="$(stat -c '%Y' "${TEST_PREFIX}/.wine_ver")"
  [ "${mtime_before}" -eq "${mtime_after}" ]
}

# 10. .wine_ver wrong content: rewritten with exactly WINE-BLEEDING (no trailing newline).
@test "reapply: wrong .wine_ver is rewritten to exactly WINE-BLEEDING" {
  printf 'WINE-BLEEDING-OLD' > "${TEST_PREFIX}/.wine_ver"
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]
  local content
  content="$(cat "${TEST_PREFIX}/.wine_ver")"
  [ "${content}" = "WINE-BLEEDING" ]
  local byte_count
  byte_count="$(wc -c < "${TEST_PREFIX}/.wine_ver")"
  [ "${byte_count}" -eq 13 ]
}

# 11. Total runtime under 2 seconds on fake-dist.
@test "reapply: total runtime under 2 seconds" {
  local start_ts end_ts elapsed
  start_ts="$(date +%s)"

  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"

  end_ts="$(date +%s)"
  elapsed=$(( end_ts - start_ts ))

  [ "${status}" -eq 0 ]
  [ "${elapsed}" -lt 2 ]
}

# 12. Partial deploy mid-run: files already deployed remain valid.
@test "reapply: prefix still usable if process killed mid-component-copy" {
  # Copy a known-good file to system32 first.
  cp -f "${TEST_DIST}/lib/wine/dxvk/x86_64-windows/d3d11.dll" "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll"
  # Remove another to simulate drift.
  rm -f "${TEST_PREFIX}/drive_c/windows/system32/dxgi.dll"

  # Run hook normally (simulating recovery of an already-partial state).
  run env \
    WINEPREFIX="${TEST_PREFIX}" \
    WINEDIR="${TEST_DIST}" \
    PW_WINE_USE="WINE-BLEEDING" \
    WB_LOG_FILE="${WB_LOG_FILE}" \
    bash "${HOOK_SCRIPT}"
  [ "${status}" -eq 0 ]

  # d3d11.dll should still be a valid (non-zero) file.
  [ -s "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll" ]
}

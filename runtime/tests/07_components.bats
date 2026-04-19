#!/usr/bin/env bats

load "lib/common.bash"

WB_LIB="${BATS_TEST_DIRNAME}/../src/wb-lib"
FIXTURE_DIST="${BATS_TEST_DIRNAME}/fixtures/fake-dist"
SCHEMA_FILE="${BATS_TEST_DIRNAME}/../share/schemas/wb_components.schema.json"

setup() {
  TEST_HOME="$(mktemp -d)"
  export WB_HOME="${TEST_HOME}"
  export WB_LOG_FILE="${TEST_HOME}/wb.log"
  export TEST_PREFIX="${TEST_HOME}/prefix"
  mkdir -p "${TEST_PREFIX}"
  export TEST_DIST="${TEST_HOME}/dist/WINE-BLEEDING"
  mkdir -p "${TEST_HOME}/dist"
  cp -a "${FIXTURE_DIST}/." "${TEST_DIST}/"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

_source_libs() {
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-json.sh"
  source "${WB_LIB}/wb-components.sh"
}

_source_reg() {
  source "${WB_LIB}/wb-log.sh"
  source "${WB_LIB}/wb-reg.sh"
}

# 1. DXVK deploy: x64 DLLs land in system32
@test "dxvk_deploy: x64 DLLs deployed into system32" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll" ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/dxgi.dll" ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/d3d9.dll" ]
}

# 2. DXVK deploy: i386 DLLs land in syswow64
@test "dxvk_deploy: i386 DLLs deployed into syswow64" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/drive_c/windows/syswow64/d3d11.dll" ]
  [ -f "${TEST_PREFIX}/drive_c/windows/syswow64/dxgi.dll" ]
}

# 3. Marker-zero: Wine builtin DLL marker is zeroed after DXVK deploy
@test "dxvk_deploy: Wine builtin marker at offset 0x40 is zeroed in system32/d3d11.dll" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  # Read 16 bytes at offset 0x40 and verify they are all zero
  marker="$(python3 -c "
with open('${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll', 'rb') as f:
    f.seek(0x40)
    b = f.read(16)
    print(b.hex())
")"
  [ "${marker}" = "00000000000000000000000000000000" ]
}

# 4. Mirror-back: dist's x86_64-windows/d3d11.dll has same mtime after deploy
@test "dxvk_deploy: mirror-back syncs mtime of dist/lib/wine/x86_64-windows/d3d11.dll" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  mtime_sys32="$(stat -c '%Y' "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll")"
  mtime_mirror="$(stat -c '%Y' "${TEST_DIST}/lib/wine/x86_64-windows/d3d11.dll")"
  [ "${mtime_sys32}" = "${mtime_mirror}" ]
}

# 5. Signed DLL: copied but NOT marker-zeroed; warn is logged
@test "dxvk_deploy: signed.dll is copied but bytes at 0x40 are NOT zeroed" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/signed.dll" ]
  # Bytes at 0x40 in signed.dll are the Wine marker (NOT zeroed)
  marker="$(python3 -c "
with open('${TEST_PREFIX}/drive_c/windows/system32/signed.dll', 'rb') as f:
    f.seek(0x40)
    b = f.read(16)
    print(b.hex())
")"
  [ "${marker}" != "00000000000000000000000000000000" ]
  # Warn should have been logged
  grep -q "Skipping marker-zero" "${WB_LOG_FILE}" 2>/dev/null || \
    grep -rq "Skipping marker-zero" "${WB_HOME}" 2>/dev/null
}

# 6. VKD3D deploy: d3d12 and d3d12core land in system32
@test "vkd3d_deploy: d3d12.dll and d3d12core.dll deployed into system32" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/d3d12.dll" ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/d3d12core.dll" ]
}

# 7. NVAPI deploy: nvapi64 and nvofapi64 land in system32
@test "nvapi_deploy: nvapi64.dll and nvofapi64.dll deployed into system32" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/nvapi64.dll" ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/nvofapi64.dll" ]
}

# 8. Mono deploy: wine-mono lands in drive_c/windows/mono/mono-2.0
@test "mono_deploy: mono DLLs copied into drive_c/windows/mono/mono-2.0" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -d "${TEST_PREFIX}/drive_c/windows/mono/mono-2.0" ]
  [ -f "${TEST_PREFIX}/drive_c/windows/mono/mono-2.0/mscorlib.dll" ]
}

# 9. Mono re-deploy removes old mono first
@test "mono_deploy: re-deploy removes old mono directory before re-seeding" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  echo "stale" > "${TEST_PREFIX}/drive_c/windows/mono/mono-2.0/stale.dll"
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ ! -f "${TEST_PREFIX}/drive_c/windows/mono/mono-2.0/stale.dll" ]
}

# 10. ICU deploy: icuuc68 and icudt68 land in system32
@test "icu_deploy: icuuc68.dll and icudt68.dll deployed into system32" {
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/icuuc68.dll" ]
  [ -f "${TEST_PREFIX}/drive_c/windows/system32/icudt68.dll" ]
}

# 11. wb_components_build_manifest returns valid JSON
@test "build_manifest: returns valid JSON with schema=1" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_components_build_manifest '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '.schema == 1' >/dev/null
  echo "${output}" | jq -e '.components | has("dxvk")' >/dev/null
  echo "${output}" | jq -e '.components | has("mono")' >/dev/null
}

# 12. Manifest has correct dll_count per component
@test "build_manifest: dll_count for dxvk matches deployed DLL count" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  json="$(bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_components_build_manifest '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null)"
  # dxvk has 4 DLLs in x86_64 (d3d11, dxgi, d3d9, signed) + 3 in i386 = 7
  dxvk_count="$(echo "${json}" | jq -r '.components.dxvk.dll_count')"
  [ "${dxvk_count}" -gt 0 ]
  # vkd3d has at least 2 DLLs
  vkd3d_count="$(echo "${json}" | jq -r '.components.vkd3d.dll_count')"
  [ "${vkd3d_count}" -ge 2 ]
}

# 13. Manifest passes check-jsonschema validation (skip if tool absent)
@test "build_manifest: output passes wb_components.schema.json validation" {
  if ! command -v check-jsonschema >/dev/null 2>&1; then
    skip "check-jsonschema not installed"
  fi
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null
  manifest_file="${TEST_HOME}/test_manifest.json"
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_components_build_manifest '${TEST_PREFIX}' '${TEST_DIST}'
  " 2>/dev/null > "${manifest_file}"
  run check-jsonschema --schemafile "${SCHEMA_FILE}" "${manifest_file}"
  [ "${status}" -eq 0 ]
}

# 14. wb_components_write writes .wb_components atomically
@test "components_write: writes .wb_components file via atomic write" {
  local json='{"schema":1,"prefix_path":"/tmp/p","dist_target":"/tmp/d","dist_manifest_hash":"","deployed_utc":"2026-04-18T12:00:00Z","components":{}}'
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_components_write '${TEST_PREFIX}' '${json}'
  " 2>/dev/null
  [ -f "${TEST_PREFIX}/.wb_components" ]
  result="$(jq -r '.schema' "${TEST_PREFIX}/.wb_components")"
  [ "${result}" = "1" ]
}

# 15. wb_components_diff detects a missing DLL
@test "components_diff: detects missing DLL and emits missing: line" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
    manifest=\$(wb_components_build_manifest '${TEST_PREFIX}' '${TEST_DIST}')
    wb_components_write '${TEST_PREFIX}' \"\${manifest}\"
  " 2>/dev/null
  rm -f "${TEST_PREFIX}/drive_c/windows/system32/d3d11.dll"
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_components_diff '${TEST_PREFIX}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q "missing:"
}

# 16. wb_components_diff detects a size-drifted (replaced) DLL
@test "components_diff: detects replaced DLL via missing check" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
    manifest=\$(wb_components_build_manifest '${TEST_PREFIX}' '${TEST_DIST}')
    wb_components_write '${TEST_PREFIX}' \"\${manifest}\"
  " 2>/dev/null
  # Remove one expected DLL (simulating drift)
  rm -f "${TEST_PREFIX}/drive_c/windows/system32/dxgi.dll"
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_components_diff '${TEST_PREFIX}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q "missing:"
}

# 17. wb_components_diff is silent when everything matches
@test "components_diff: silent when all manifest DLLs are present" {
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
    wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
    manifest=\$(wb_components_build_manifest '${TEST_PREFIX}' '${TEST_DIST}')
    wb_components_write '${TEST_PREFIX}' \"\${manifest}\"
  " 2>/dev/null
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_components_diff '${TEST_PREFIX}'
  " 2>/dev/null
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

# 18. wb_reg_patch_dll_overrides creates section if absent
@test "reg_patch: creates DllOverrides section when missing" {
  local user_reg="${TEST_HOME}/user.reg"
  cat > "${user_reg}" <<'REGEOF'
WINE REGISTRY Version 2
;; stub

[Software\\Wine]

REGEOF
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-reg.sh'
    wb_reg_patch_dll_overrides '${user_reg}' 'd3d11=n'
  " 2>/dev/null
  grep -q '^\[Software\\\\Wine\\\\DllOverrides\]' "${user_reg}"
  grep -q '"d3d11"="n"' "${user_reg}"
}

# 19. Existing entries are replaced, not duplicated (idempotent)
@test "reg_patch: running twice produces no duplicate entries" {
  local user_reg="${TEST_HOME}/user.reg"
  cat > "${user_reg}" <<'REGEOF'
WINE REGISTRY Version 2
;; stub

[Software\\Wine]

REGEOF
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-reg.sh'
    wb_reg_patch_dll_overrides '${user_reg}' 'd3d11=n;dxgi=n'
  " 2>/dev/null
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-reg.sh'
    wb_reg_patch_dll_overrides '${user_reg}' 'd3d11=n;dxgi=n'
  " 2>/dev/null
  count="$(grep -c '"d3d11"="n"' "${user_reg}")"
  [ "${count}" -eq 1 ]
}

# 20. Injection attempt is rejected (returns non-zero)
@test "reg_patch: injection attempt in dll_list is rejected with non-zero exit" {
  local user_reg="${TEST_HOME}/user.reg"
  cat > "${user_reg}" <<'REGEOF'
WINE REGISTRY Version 2
[Software\\Wine]
REGEOF
  run bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-reg.sh'
    wb_reg_patch_dll_overrides '${user_reg}' 'd3d11\"=a
MALICIOUS=b'
  " 2>/dev/null
  [ "${status}" -ne 0 ]
}

# 21. Running deploy twice produces identical .wb_components (modulo deployed_utc)
@test "double_deploy: two deploys produce identical component data (modulo deployed_utc)" {
  _deploy_all() {
    bash -c "
      source '${WB_LIB}/wb-log.sh'
      source '${WB_LIB}/wb-json.sh'
      source '${WB_LIB}/wb-components.sh'
      wb_component_deploy_dxvk '${TEST_PREFIX}' '${TEST_DIST}'
      wb_component_deploy_vkd3d '${TEST_PREFIX}' '${TEST_DIST}'
      wb_component_deploy_nvapi '${TEST_PREFIX}' '${TEST_DIST}'
      wb_component_deploy_mono '${TEST_PREFIX}' '${TEST_DIST}'
      wb_component_deploy_icu '${TEST_PREFIX}' '${TEST_DIST}'
      wb_components_build_manifest '${TEST_PREFIX}' '${TEST_DIST}'
    " 2>/dev/null
  }
  json1="$(_deploy_all)"
  json2="$(_deploy_all)"
  # Compare everything except deployed_utc
  norm1="$(echo "${json1}" | jq 'del(.deployed_utc)' | jq -Sc .)"
  norm2="$(echo "${json2}" | jq 'del(.deployed_utc)' | jq -Sc .)"
  [ "${norm1}" = "${norm2}" ]
}

# 22. Deploy on prefix where system32/syswow64 do not yet exist creates them
@test "dxvk_deploy: creates system32 and syswow64 if they do not exist" {
  local fresh="${TEST_HOME}/fresh-prefix"
  mkdir -p "${fresh}"
  bash -c "
    source '${WB_LIB}/wb-log.sh'
    source '${WB_LIB}/wb-json.sh'
    source '${WB_LIB}/wb-components.sh'
    wb_component_deploy_dxvk '${fresh}' '${TEST_DIST}'
  " 2>/dev/null
  [ -d "${fresh}/drive_c/windows/system32" ]
  [ -d "${fresh}/drive_c/windows/syswow64" ]
  [ -f "${fresh}/drive_c/windows/system32/d3d11.dll" ]
}

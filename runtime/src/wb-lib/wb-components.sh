#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# wb-components.sh — GPU/mono/ICU component deployment into Wine prefixes.
# Ported from tools/deploy-to-portproton.sh (lines 109-248).
# ---------------------------------------------------------------------------

# Security-critical: Python3 helper that checks for Authenticode signature
# and optionally zeroes the Wine builtin DLL marker at offset 0x40.
# Returns exit 1 if the DLL is signed (caller should skip marker-zero).
_wb_component_marker_zero() {
  local dll_path="$1"
  python3 - "${dll_path}" <<'PYEOF'
import sys, struct

path = sys.argv[1]
try:
    with open(path, 'r+b') as f:
        # Read e_lfanew from DOS header
        f.seek(0x3C)
        e_lfanew = struct.unpack('<I', f.read(4))[0]

        # Security-critical: determine PE32 vs PE32+ to locate Security Directory.
        # PE32  optional header: Security Directory = e_lfanew + 24 + 128
        # PE32+ optional header: Security Directory = e_lfanew + 24 + 144
        f.seek(e_lfanew + 4 + 20)  # skip signature + COFF
        magic = struct.unpack('<H', f.read(2))[0]
        if magic == 0x10B:      # PE32
            sec_dir_offset = e_lfanew + 24 + 128
            num_rva_offset = e_lfanew + 24 + 92
        elif magic == 0x20B:    # PE32+
            sec_dir_offset = e_lfanew + 24 + 144
            num_rva_offset = e_lfanew + 24 + 108
        else:
            # Unknown PE format — refuse to touch
            sys.exit(1)

        # Reject PEs whose NumberOfRvaAndSizes < 5 (Security Directory is index 4).
        # Treat as "cannot determine" → refuse to marker-zero.
        f.seek(num_rva_offset)
        num_rva_and_sizes = struct.unpack('<I', f.read(4))[0]
        if num_rva_and_sizes < 5:
            sys.exit(1)

        # Security-critical: read Security Directory VirtualAddress (4 bytes).
        # Any non-zero value means the DLL carries an Authenticode signature;
        # refuse to marker-zero to avoid invalidating the signature hash.
        f.seek(sec_dir_offset)
        sec_va = struct.unpack('<I', f.read(4))[0]
        if sec_va != 0:
            sys.exit(1)

        # Verify the Wine builtin DLL marker is present before overwriting.
        f.seek(0x40)
        if f.read(16) != b'Wine builtin DLL':
            sys.exit(0)

        # Zero the marker so Wine loads the DLL as native rather than builtin.
        f.seek(0x40)
        f.write(b'\x00' * 16)
except (OSError, struct.error):
    sys.exit(2)
PYEOF
}

# Deploy all DLLs from one source arch directory into a prefix Windows dir.
# Mirrors the deployed copy back into dist so wine's deploy_builtin_dlls()
# skips overwriting the prefix copy on game launch.
# Prints the count of deployed DLLs to stdout.
_wb_component_deploy_arch() {
  local src_dir="$1"
  local arch_dir="$2"
  local dst_dir="$3"
  local mirror_dir="$4"
  local count=0

  [[ -d "${src_dir}/${arch_dir}" ]] || { echo "0"; return 0; }

  mkdir -p "${dst_dir}"

  for dll in "${src_dir}/${arch_dir}"/*.dll; do
    [[ -f "${dll}" ]] || continue
    # SECURITY: refuse to follow symlinks in the component dir. A relative
    # symlink resolving outside the dist tree would exfiltrate arbitrary content
    # into prefix system32 and mirror it back into the shared dist mirror dir.
    if [[ -L "${dll}" ]]; then
      wb_log_warn "Skipping symlink DLL in component dir: ${dll}"
      continue
    fi
    local name
    name="$(basename "${dll}")"
    cp -f "${dll}" "${dst_dir}/${name}"

    # Security-critical: check Authenticode before marker-zero.
    # Signed DLLs are copied through unchanged; only unsigned ones are zeroed.
    if _wb_component_marker_zero "${dst_dir}/${name}" 2>/dev/null; then
      true
    else
      local exit_code=$?
      if [[ "${exit_code}" -eq 1 ]]; then
        wb_log_warn "Skipping marker-zero for signed DLL: ${name}"
      fi
    fi

    if [[ -d "${mirror_dir}" && -f "${mirror_dir}/${name}" ]]; then
      cp -f "${dst_dir}/${name}" "${mirror_dir}/${name}"
      touch -r "${dst_dir}/${name}" "${mirror_dir}/${name}"
    fi

    (( count++ )) || true
  done

  echo "${count}"
}

# Deploy DXVK (d3d8, d3d9, d3d10core, d3d11, dxgi) into a prefix.
# Ports deploy-to-portproton.sh lines 159-201.
# Prints total DLL count (x64+x32) to stdout.
wb_component_deploy_dxvk() {
  local prefix="$1"
  local dist="$2"
  local dxvk_dir="${dist}/lib/wine/dxvk"
  local sys32="${prefix}/drive_c/windows/system32"
  local sys32_32="${prefix}/drive_c/windows/syswow64"

  [[ -d "${dxvk_dir}/x86_64-windows" ]] || { echo "0"; return 0; }

  mkdir -p "${sys32}" "${sys32_32}"

  local n64 n32
  n64="$(_wb_component_deploy_arch "${dxvk_dir}" "x86_64-windows" "${sys32}" \
    "${dist}/lib/wine/x86_64-windows")"
  n32="$(_wb_component_deploy_arch "${dxvk_dir}" "i386-windows" "${sys32_32}" \
    "${dist}/lib/wine/i386-windows")"

  local ver
  ver="$(head -1 "${dxvk_dir}/version" 2>/dev/null || true)"
  wb_log_info "DXVK deployed: ${n64}x64 + ${n32}x32 DLLs (${ver:-unknown})"

  echo $(( n64 + n32 ))
}

# Deploy VKD3D-Proton (d3d12, d3d12core) into a prefix.
# Ports deploy-to-portproton.sh lines 204-216.
# Source dir is vkd3d-proton (not vkd3d).
wb_component_deploy_vkd3d() {
  local prefix="$1"
  local dist="$2"
  local vkd3d_dir="${dist}/lib/wine/vkd3d-proton"
  local sys32="${prefix}/drive_c/windows/system32"
  local sys32_32="${prefix}/drive_c/windows/syswow64"

  [[ -d "${vkd3d_dir}/x86_64-windows" ]] || { echo "0"; return 0; }

  mkdir -p "${sys32}" "${sys32_32}"

  local n64 n32
  n64="$(_wb_component_deploy_arch "${vkd3d_dir}" "x86_64-windows" "${sys32}" \
    "${dist}/lib/wine/x86_64-windows")"
  n32="$(_wb_component_deploy_arch "${vkd3d_dir}" "i386-windows" "${sys32_32}" \
    "${dist}/lib/wine/i386-windows")"

  local ver
  ver="$(head -1 "${vkd3d_dir}/version" 2>/dev/null || true)"
  wb_log_info "VKD3D-Proton deployed: ${n64}x64 + ${n32}x32 DLLs (${ver:-unknown})"

  echo $(( n64 + n32 ))
}

# Deploy DXVK-NVAPI (nvapi64, nvofapi64) into a prefix.
# Ports deploy-to-portproton.sh lines 218-231.
wb_component_deploy_nvapi() {
  local prefix="$1"
  local dist="$2"
  local nvapi_dir="${dist}/lib/wine/nvapi"
  local sys32="${prefix}/drive_c/windows/system32"
  local sys32_32="${prefix}/drive_c/windows/syswow64"

  [[ -d "${nvapi_dir}/x86_64-windows" ]] || { echo "0"; return 0; }

  mkdir -p "${sys32}" "${sys32_32}"

  local n64 n32
  n64="$(_wb_component_deploy_arch "${nvapi_dir}" "x86_64-windows" "${sys32}" \
    "${dist}/lib/wine/x86_64-windows")"
  n32="$(_wb_component_deploy_arch "${nvapi_dir}" "i386-windows" "${sys32_32}" \
    "${dist}/lib/wine/i386-windows")"

  local ver
  ver="$(head -1 "${nvapi_dir}/version" 2>/dev/null || true)"
  wb_log_info "DXVK-NVAPI deployed: ${n64}x64 + ${n32}x32 DLLs (${ver:-unknown})"

  echo $(( n64 + n32 ))
}

# Pre-seed wine-mono into drive_c/windows/mono/mono-2.0.
# Ports deploy-to-portproton.sh lines 109-123.
wb_component_deploy_mono() {
  local prefix="$1"
  local dist="$2"
  local mono_src="${dist}/share/wine/mono"
  local mono_ver

  # shellcheck disable=SC2012
  mono_ver="$(ls -1d "${mono_src}"/wine-mono-* 2>/dev/null \
    | sort -V | tail -1 | xargs basename 2>/dev/null || true)"

  if [[ -z "${mono_ver}" ]]; then
    wb_log_warn "No mono found in distribution at ${mono_src}"
    echo "0"
    return 0
  fi

  local mono_dst="${prefix}/drive_c/windows/mono/mono-2.0"
  if [[ -d "${mono_dst}" ]]; then
    wb_log_info "Removing old mono from prefix..."
    rm -rf "${mono_dst}"
  fi
  mkdir -p "${mono_dst}"

  wb_log_info "Installing ${mono_ver} to prefix..."
  cp -a "${mono_src}/${mono_ver}/." "${mono_dst}/"

  local count
  count="$(find "${mono_dst}" -name '*.dll' | wc -l)"
  wb_log_info "Mono installed (${count} DLLs)"
  echo "${count}"
}

# Deploy ICU DLLs into a prefix.
# New component; follows DXVK pattern.
wb_component_deploy_icu() {
  local prefix="$1"
  local dist="$2"
  local icu_dir="${dist}/lib/wine/icu"
  local sys32="${prefix}/drive_c/windows/system32"
  local sys32_32="${prefix}/drive_c/windows/syswow64"

  [[ -d "${icu_dir}/x86_64-windows" ]] || { echo "0"; return 0; }

  mkdir -p "${sys32}" "${sys32_32}"

  local n64 n32
  n64="$(_wb_component_deploy_arch "${icu_dir}" "x86_64-windows" "${sys32}" \
    "${dist}/lib/wine/x86_64-windows")"
  n32="$(_wb_component_deploy_arch "${icu_dir}" "i386-windows" "${sys32_32}" \
    "${dist}/lib/wine/i386-windows")"

  local ver
  ver="$(head -1 "${icu_dir}/version" 2>/dev/null || true)"
  wb_log_info "ICU deployed: ${n64}x64 + ${n32}x32 DLLs (${ver:-unknown})"

  echo $(( n64 + n32 ))
}

# Verify every DLL listed in the .wb_components manifest still exists at the
# expected path. Emits "missing: <path>" or "drifted: <path>" per problem.
# Always exits 0.
wb_components_diff() {
  local prefix="$1"
  local manifest="${prefix}/.wb_components"

  [[ -r "${manifest}" ]] || return 0

  local components
  components="$(jq -r '.components | keys[]' "${manifest}" 2>/dev/null || true)"

  local comp
  for comp in ${components}; do
    local paths
    paths="$(jq -r --arg c "${comp}" \
      '.components[$c].dll_paths // [] | .[]' "${manifest}" 2>/dev/null || true)"
    local rel_path
    while IFS= read -r rel_path; do
      [[ -n "${rel_path}" ]] || continue
      local full_path="${prefix}/${rel_path}"
      if [[ ! -e "${full_path}" ]]; then
        echo "missing: ${full_path}"
      fi
    done <<< "${paths}"
  done

  return 0
}

# Atomically write .wb_components manifest via wb_json_write_atomic.
wb_components_write() {
  local prefix="$1"
  local json="$2"
  wb_json_write_atomic "${prefix}/.wb_components" "${json}"
}

# Introspect what was deployed and produce a JSON manifest matching
# runtime/share/schemas/wb_components.schema.json.
wb_components_build_manifest() {
  local prefix="$1"
  local dist="$2"

  local abs_prefix abs_dist
  abs_prefix="$(realpath -m "${prefix}")"
  abs_dist="$(realpath -m "${dist}")"

  local deployed_utc
  deployed_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local dist_hash
  dist_hash="$(jq -r '.builtin_dlls_hash // ""' "${dist}/.wb_dist_meta" 2>/dev/null || true)"

  # Collect per-component metadata
  local dxvk_ver vkd3d_ver nvapi_ver icu_ver mono_ver
  dxvk_ver="$(head -1 "${dist}/lib/wine/dxvk/version" 2>/dev/null || true)"
  vkd3d_ver="$(head -1 "${dist}/lib/wine/vkd3d-proton/version" 2>/dev/null || true)"
  nvapi_ver="$(head -1 "${dist}/lib/wine/nvapi/version" 2>/dev/null || true)"
  icu_ver="$(head -1 "${dist}/lib/wine/icu/version" 2>/dev/null || true)"
  # shellcheck disable=SC2012
  mono_ver="$(ls -1d "${dist}/share/wine/mono"/wine-mono-* 2>/dev/null \
    | sort -V | tail -1 | xargs basename 2>/dev/null || true)"

  local sys32="${prefix}/drive_c/windows/system32"
  local sys32_32="${prefix}/drive_c/windows/syswow64"
  local mono_dst="${prefix}/drive_c/windows/mono/mono-2.0"

  # Count DLLs per component in system32 that originated from the component dir
  _count_from_src() {
    local src_arch="$1"
    local count=0
    if [[ -d "${src_arch}" ]]; then
      count="$(find "${src_arch}" -maxdepth 1 -name '*.dll' | wc -l)"
    fi
    echo "${count}"
  }

  local dxvk_count vkd3d_count nvapi_count icu_count mono_count
  dxvk_count="$(( $(_count_from_src "${dist}/lib/wine/dxvk/x86_64-windows") + \
                  $(_count_from_src "${dist}/lib/wine/dxvk/i386-windows") ))"
  vkd3d_count="$(( $(_count_from_src "${dist}/lib/wine/vkd3d-proton/x86_64-windows") + \
                   $(_count_from_src "${dist}/lib/wine/vkd3d-proton/i386-windows") ))"
  nvapi_count="$(( $(_count_from_src "${dist}/lib/wine/nvapi/x86_64-windows") + \
                   $(_count_from_src "${dist}/lib/wine/nvapi/i386-windows") ))"
  icu_count="$(( $(_count_from_src "${dist}/lib/wine/icu/x86_64-windows") + \
                 $(_count_from_src "${dist}/lib/wine/icu/i386-windows") ))"
  mono_count="$(find "${mono_dst}" -name '*.dll' 2>/dev/null | wc -l || echo 0)"

  # Build individual component dll_paths (just system32 for GPU components)
  local dxvk_paths_x64 vkd3d_paths_x64 nvapi_paths_x64 icu_paths_x64
  dxvk_paths_x64="$(
    for dll in "${dist}/lib/wine/dxvk/x86_64-windows"/*.dll; do
      [[ -f "${dll}" ]] || continue
      echo "drive_c/windows/system32/$(basename "${dll}")"
    done | jq -Rs '[split("\n")[] | select(length>0)]'
  )"
  vkd3d_paths_x64="$(
    for dll in "${dist}/lib/wine/vkd3d-proton/x86_64-windows"/*.dll; do
      [[ -f "${dll}" ]] || continue
      echo "drive_c/windows/system32/$(basename "${dll}")"
    done | jq -Rs '[split("\n")[] | select(length>0)]'
  )"
  nvapi_paths_x64="$(
    for dll in "${dist}/lib/wine/nvapi/x86_64-windows"/*.dll; do
      [[ -f "${dll}" ]] || continue
      echo "drive_c/windows/system32/$(basename "${dll}")"
    done | jq -Rs '[split("\n")[] | select(length>0)]'
  )"
  icu_paths_x64="$(
    for dll in "${dist}/lib/wine/icu/x86_64-windows"/*.dll; do
      [[ -f "${dll}" ]] || continue
      echo "drive_c/windows/system32/$(basename "${dll}")"
    done | jq -Rs '[split("\n")[] | select(length>0)]'
  )"

  jq -cn \
    --arg prefix_path "${abs_prefix}" \
    --arg dist_target "${abs_dist}" \
    --arg dist_manifest_hash "${dist_hash}" \
    --arg deployed_utc "${deployed_utc}" \
    --arg dxvk_ver "${dxvk_ver:-}" \
    --argjson dxvk_count "${dxvk_count}" \
    --argjson dxvk_paths "${dxvk_paths_x64}" \
    --arg vkd3d_ver "${vkd3d_ver:-}" \
    --argjson vkd3d_count "${vkd3d_count}" \
    --argjson vkd3d_paths "${vkd3d_paths_x64}" \
    --arg nvapi_ver "${nvapi_ver:-}" \
    --argjson nvapi_count "${nvapi_count}" \
    --argjson nvapi_paths "${nvapi_paths_x64}" \
    --arg mono_ver "${mono_ver:-}" \
    --argjson mono_count "${mono_count}" \
    --arg icu_ver "${icu_ver:-}" \
    --argjson icu_count "${icu_count}" \
    --argjson icu_paths "${icu_paths_x64}" \
    '{
      schema: 1,
      prefix_path: $prefix_path,
      dist_target: $dist_target,
      dist_manifest_hash: $dist_manifest_hash,
      deployed_utc: $deployed_utc,
      components: {
        dxvk:  {version: $dxvk_ver,  dll_count: $dxvk_count,  dll_paths: $dxvk_paths},
        vkd3d: {version: $vkd3d_ver, dll_count: $vkd3d_count, dll_paths: $vkd3d_paths},
        nvapi: {version: $nvapi_ver, dll_count: $nvapi_count, dll_paths: $nvapi_paths},
        mono:  {version: $mono_ver,  dll_count: $mono_count,  dll_paths: []},
        icu:   {version: $icu_ver,   dll_count: $icu_count,   dll_paths: $icu_paths}
      }
    }'
}

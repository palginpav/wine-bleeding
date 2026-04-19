#!/usr/bin/env bash
set -euo pipefail

wb_dist_list() {
  local dist_dir
  dist_dir="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}/dist"

  if [[ ! -d "${dist_dir}" ]]; then
    return 0
  fi

  local entry name
  for entry in "${dist_dir}"/*/; do
    [[ -d "${entry}" ]] || continue
    name="$(basename "${entry}")"
    # SECURITY: skip the stable alias symlink itself — only emit real dirs
    if [[ -L "${dist_dir}/${name}" ]]; then
      continue
    fi
    echo "${name}"
  done
}

wb_dist_meta_read() {
  local dist_path="$1"
  local key="$2"
  wb_json_read "${dist_path}/.wb_dist_meta" "${key}"
}

_wb_dist_component_paths() {
  local dist_path="$1"
  local component="$2"
  local comp_dir="${dist_path}/lib/wine/${component}"
  if [[ ! -d "${comp_dir}" ]]; then
    echo "[]"
    return 0
  fi
  find "${comp_dir}" -type f 2>/dev/null \
    | sed "s|${dist_path}/||" | sort | jq -Rn '[inputs]'
}

wb_dist_meta_write() {
  local dist_path="$1"

  local dist_name
  dist_name="$(basename "${dist_path}")"

  local wine_major_version wine_full_version
  if [[ -f "${dist_path}/VERSION" ]]; then
    wine_full_version="$(cat "${dist_path}/VERSION")"
    wine_major_version="$(echo "${wine_full_version}" | grep -oP '^\D*\K[0-9]+' || echo "unknown")"
  else
    wine_full_version="unknown"
    wine_major_version="unknown"
    echo "unknown" > "${dist_path}/VERSION"
  fi

  local dxvk_version vkd3d_version nvapi_version mono_version icu_version
  dxvk_version="$(cat "${dist_path}/lib/wine/dxvk/.version" 2>/dev/null || echo "")"
  vkd3d_version="$(cat "${dist_path}/lib/wine/vkd3d/.version" 2>/dev/null || echo "")"
  nvapi_version="$(cat "${dist_path}/lib/wine/nvapi/.version" 2>/dev/null || echo "")"
  mono_version="$(cat "${dist_path}/lib/wine/mono/.version" 2>/dev/null || echo "")"
  icu_version="$(cat "${dist_path}/lib/wine/icu/.version" 2>/dev/null || echo "")"

  local dxvk_paths vkd3d_paths nvapi_paths mono_paths icu_paths
  dxvk_paths="$(_wb_dist_component_paths "${dist_path}" dxvk)"
  vkd3d_paths="$(_wb_dist_component_paths "${dist_path}" vkd3d)"
  nvapi_paths="$(_wb_dist_component_paths "${dist_path}" nvapi)"
  mono_paths="$(_wb_dist_component_paths "${dist_path}" mono)"
  icu_paths="$(_wb_dist_component_paths "${dist_path}" icu)"

  # Cheap fingerprint: sorted list of dll names + sizes (not content)
  local builtin_dlls_hash
  builtin_dlls_hash="$(find "${dist_path}/lib/wine/x86_64-windows" -maxdepth 1 -name '*.dll' 2>/dev/null \
    | sort \
    | xargs -I{} stat --format="%n %s" {} 2>/dev/null \
    | sha256sum \
    | awk '{print $1}' || echo "")"

  local build_utc
  build_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local json
  json="$(jq -cn \
    --argjson schema 1 \
    --arg dist_name "${dist_name}" \
    --arg wine_major_version "${wine_major_version}" \
    --arg wine_full_version "${wine_full_version}" \
    --argjson dxvk_paths "${dxvk_paths}" \
    --argjson vkd3d_paths "${vkd3d_paths}" \
    --argjson nvapi_paths "${nvapi_paths}" \
    --argjson mono_paths "${mono_paths}" \
    --argjson icu_paths "${icu_paths}" \
    --arg dxvk_version "${dxvk_version}" \
    --arg vkd3d_version "${vkd3d_version}" \
    --arg nvapi_version "${nvapi_version}" \
    --arg mono_version "${mono_version}" \
    --arg icu_version "${icu_version}" \
    --arg builtin_dlls_hash "${builtin_dlls_hash}" \
    --arg build_utc "${build_utc}" \
    '{
      schema: $schema,
      dist_name: $dist_name,
      wine_major_version: $wine_major_version,
      wine_full_version: $wine_full_version,
      components: {
        dxvk:   { version: (if $dxvk_version   == "" then null else $dxvk_version   end), paths: $dxvk_paths },
        vkd3d:  { version: (if $vkd3d_version   == "" then null else $vkd3d_version  end), paths: $vkd3d_paths },
        nvapi:  { version: (if $nvapi_version   == "" then null else $nvapi_version  end), paths: $nvapi_paths },
        mono:   { version: (if $mono_version    == "" then null else $mono_version   end), paths: $mono_paths },
        icu:    { version: (if $icu_version     == "" then null else $icu_version    end), paths: $icu_paths }
      },
      builtin_dlls_hash: $builtin_dlls_hash,
      pp_supplied_mode: "2",
      build_utc: $build_utc
    }')"

  wb_json_write_atomic "${dist_path}/.wb_dist_meta" "${json}"
}

wb_dist_resolve_alias() {
  local dist_dir
  dist_dir="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}/dist"
  local alias_path="${dist_dir}/WINE-BLEEDING"

  if [[ ! -L "${alias_path}" ]]; then
    return 0
  fi
  readlink -f "${alias_path}"
}

wb_dist_set_alias() {
  local target="$1"
  local dist_dir
  dist_dir="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}/dist"

  # SECURITY: atomic symlink swap — ln -sfn directly is unlink+symlink (non-atomic).
  # PID-qualified temp name avoids the concurrent-writer race where two callers
  # share the same `.new` path and last-writer wins silently.
  local tmp="${dist_dir}/WINE-BLEEDING.new.$$"
  ln -sfn "${target}" "${tmp}"
  mv -T "${tmp}" "${dist_dir}/WINE-BLEEDING"
  if ! sync -f "${dist_dir}" 2>/dev/null; then
    if command -v wb_log_warn >/dev/null 2>&1; then
      wb_log_warn "sync -f failed on ${dist_dir}; alias update may not be durable on power loss"
    fi
  fi
}

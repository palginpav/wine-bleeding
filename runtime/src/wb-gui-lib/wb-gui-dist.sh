#!/usr/bin/env bash
# wb-gui-dist.sh — dist registry library for wb-gui (Phase B / v1.7.0)
# Sourced by wb-gui; never executed directly.
#
# Registry: $WB_HOME/dists.json
# Schema v1 (see runtime/share/schemas/wb_dists.schema.json)
#
# Public API:
#   wb_gui_dist_registry_refresh          — rebuild dists.json from FS; sweep stale staging
#   wb_gui_dist_registry_list             -> JSON array (parsed from dists.json)
#   wb_gui_dist_add_external <path> <name> — register external dist via wb runtime register
#   wb_gui_dist_remove <name>             — remove native (rm -rf) or unregister external
#   wb_gui_dist_activate <name>           — call wb runtime activate
#   wb_gui_dist_apps_count <name>         -> integer count of apps referencing this dist
#   wb_gui_dist_apps_clear <name>         — set dist=null on all apps referencing this dist
#
# Depends on (sourced by caller before this file):
#   wb-lib/wb-log.sh    wb_log_warn
#   wb-lib/wb-json.sh   wb_json_read  wb_json_write_atomic
#   wb-lib/wb-dist.sh   wb_dist_list  wb_dist_resolve_alias  wb_dist_set_alias
#   wb-gui-lib/wb-gui-apps.sh (for wb_gui_dist_apps_clear)

set -euo pipefail

# ---------------------------------------------------------------------------
# Internal: resolve registry path
# ---------------------------------------------------------------------------
_wb_gui_dist_registry() {
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
  printf '%s' "${wb_home}/dists.json"
}

_wb_gui_dist_wb_home() {
  printf '%s' "${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
}

# ---------------------------------------------------------------------------
# Internal: read .wb_dist_meta key from a dist path.
# Returns empty string on any error (meta may not exist for new dists).
# ---------------------------------------------------------------------------
_wb_gui_dist_meta_read() {
  local dist_path="$1"
  local key="$2"
  local meta_file="${dist_path}/.wb_dist_meta"
  if [[ ! -r "${meta_file}" ]]; then
    return 0
  fi
  jq -r "${key} // empty" "${meta_file}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Internal: read a per-dist settings key from settings/dists/<name>.json
# ---------------------------------------------------------------------------
_wb_gui_dist_settings_read() {
  local dist_name="$1"
  local key="$2"
  local wb_home
  wb_home="$(_wb_gui_dist_wb_home)"
  local sfile="${wb_home}/settings/dists/${dist_name}.json"
  if [[ ! -r "${sfile}" ]]; then
    return 0
  fi
  jq -r "${key} // empty" "${sfile}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Internal: decide whether a dist path can be rebuilt component-by-component
# via tools/build-component.sh. A dist is rebuildable when it has the
# full-build.sh layout (bin/wine + lib/wine/x86_64-windows/) and the path
# is writable by the current user — regardless of how it was registered.
# This replaces the older `source == "native"` capability gate, which mis-
# classified externally-added full-build.sh dists as non-rebuildable.
# Emits "true" or "false" (JSON-compatible) on stdout.
# ---------------------------------------------------------------------------
_wb_gui_dist_is_rebuildable() {
  local path="$1"
  [[ -d "${path}" ]] || { printf 'false'; return; }
  [[ -x "${path}/bin/wine" ]] || { printf 'false'; return; }
  [[ -d "${path}/lib/wine/x86_64-windows" ]] || { printf 'false'; return; }
  [[ -w "${path}/lib/wine/x86_64-windows" ]] || { printf 'false'; return; }
  printf 'true'
}

# ---------------------------------------------------------------------------
# Internal: classify a dist as native/external/unknown and check if broken.
# Outputs a JSON object with dist entry fields.
# ---------------------------------------------------------------------------
_wb_gui_dist_describe_native() {
  local name="$1"
  local path="$2"
  local active_path="$3"

  # Broken detection
  local broken=false
  local broken_reason="null"
  if [[ ! -d "${path}" ]]; then
    broken=true
    broken_reason='"path vanished"'
  elif [[ ! -x "${path}/bin/wine" ]]; then
    broken=true
    broken_reason='"bin/wine missing"'
  fi

  # Active
  local is_active=false
  local canon_path
  canon_path="$(realpath -m "${path}" 2>/dev/null || echo "${path}")"
  if [[ -n "${active_path}" ]] && [[ "${canon_path}" == "${active_path}" ]]; then
    is_active=true
  fi

  # Meta fields
  local built_utc wine_version
  built_utc="$(_wb_gui_dist_meta_read "${path}" '.build_utc')"
  wine_version="$(_wb_gui_dist_meta_read "${path}" '.wine_full_version')"

  # Component versions from .wb_dist_meta
  local dxvk_ver vkd3d_ver nvapi_ver mono_ver icu_ver
  dxvk_ver="$(_wb_gui_dist_meta_read "${path}" '.components.dxvk.version')"
  vkd3d_ver="$(_wb_gui_dist_meta_read "${path}" '.components.vkd3d.version')"
  nvapi_ver="$(_wb_gui_dist_meta_read "${path}" '.components.nvapi.version')"
  mono_ver="$(_wb_gui_dist_meta_read "${path}" '.components.mono.version')"
  icu_ver="$(_wb_gui_dist_meta_read "${path}" '.components.icu.version')"

  # Settings-layer overrides (component-builder writes these after component rebuild)
  local settings_built_by settings_last_built_at
  settings_built_by="$(_wb_gui_dist_settings_read "${name}" '.built_by')"
  settings_last_built_at="$(_wb_gui_dist_settings_read "${name}" '.last_built_at')"
  local settings_dxvk settings_vkd3d settings_nvapi settings_mono settings_icu
  settings_dxvk="$(_wb_gui_dist_settings_read "${name}" '.component_versions.dxvk')"
  settings_vkd3d="$(_wb_gui_dist_settings_read "${name}" '.component_versions.vkd3d')"
  settings_nvapi="$(_wb_gui_dist_settings_read "${name}" '.component_versions.nvapi')"
  settings_mono="$(_wb_gui_dist_settings_read "${name}" '.component_versions.mono')"
  settings_icu="$(_wb_gui_dist_settings_read "${name}" '.component_versions.icu')"

  # Settings values override meta values when non-empty (component-builder is fresher)
  [[ -n "${settings_dxvk}" ]]  && dxvk_ver="${settings_dxvk}"
  [[ -n "${settings_vkd3d}" ]] && vkd3d_ver="${settings_vkd3d}"
  [[ -n "${settings_nvapi}" ]] && nvapi_ver="${settings_nvapi}"
  [[ -n "${settings_mono}" ]]  && mono_ver="${settings_mono}"
  [[ -n "${settings_icu}" ]]   && icu_ver="${settings_icu}"

  local built_by="null"
  if [[ -n "${settings_built_by}" ]]; then
    built_by="\"${settings_built_by}\""
  else
    built_by='"full-build.sh"'
  fi

  local last_built_at="null"
  if [[ -n "${settings_last_built_at}" ]]; then
    last_built_at="\"${settings_last_built_at}\""
  elif [[ -n "${built_utc}" ]]; then
    last_built_at="\"${built_utc}\""
  fi

  # Build components_included array from meta paths
  local meta_file="${path}/.wb_dist_meta"
  local components_included="[]"
  if [[ -r "${meta_file}" ]]; then
    components_included="$(jq -r \
      '[.components | to_entries[] | select((.value.paths | length) > 0) | .key] | sort' \
      "${meta_file}" 2>/dev/null || echo "[]")"
  fi

  local build_profile
  build_profile="$(_wb_gui_dist_settings_read "${name}" '.build_profile')"

  local rebuildable
  rebuildable="$(_wb_gui_dist_is_rebuildable "${path}")"

  jq -cn \
    --arg name "${name}" \
    --arg path "${path}" \
    --argjson active "${is_active}" \
    --argjson broken "${broken}" \
    --argjson broken_reason "${broken_reason}" \
    --argjson built_by "${built_by}" \
    --argjson last_built_at "${last_built_at}" \
    --arg built_utc "${built_utc}" \
    --arg wine_version "${wine_version}" \
    --argjson components_included "${components_included}" \
    --arg dxvk_ver "${dxvk_ver}" \
    --arg vkd3d_ver "${vkd3d_ver}" \
    --arg nvapi_ver "${nvapi_ver}" \
    --arg mono_ver "${mono_ver}" \
    --arg icu_ver "${icu_ver}" \
    --arg build_profile "${build_profile}" \
    --argjson rebuildable "${rebuildable}" \
    '{
      name: $name,
      path: $path,
      source: "native",
      active: $active,
      built_by: $built_by,
      built_utc: (if $built_utc == "" then null else $built_utc end),
      last_built_at: $last_built_at,
      wine_version: (if $wine_version == "" then null else $wine_version end),
      components_included: $components_included,
      component_versions: {
        dxvk:  (if $dxvk_ver  == "" then null else $dxvk_ver  end),
        vkd3d: (if $vkd3d_ver == "" then null else $vkd3d_ver end),
        nvapi: (if $nvapi_ver == "" then null else $nvapi_ver end),
        mono:  (if $mono_ver  == "" then null else $mono_ver  end),
        icu:   (if $icu_ver   == "" then null else $icu_ver   end)
      },
      build_profile: (if $build_profile == "" then null else $build_profile end),
      external_source: null,
      rebuildable: $rebuildable,
      broken: $broken,
      broken_reason: $broken_reason
    }'
}

_wb_gui_dist_describe_external() {
  local name="$1"
  local path="$2"
  local plugin_file="$3"
  local active_path="$4"

  local broken=false
  local broken_reason="null"
  if [[ ! -d "${path}" ]]; then
    broken=true
    broken_reason='"path vanished"'
  elif [[ ! -x "${path}/bin/wine" ]]; then
    broken=true
    broken_reason='"bin/wine missing"'
  fi

  local is_active=false
  local canon_path
  canon_path="$(realpath -m "${path}" 2>/dev/null || echo "${path}")"
  if [[ -n "${active_path}" ]] && [[ "${canon_path}" == "${active_path}" ]]; then
    is_active=true
  fi

  local external_source wine_version
  external_source="$(jq -r '.external_source // empty' "${plugin_file}" 2>/dev/null || true)"
  wine_version="$(jq -r '.wine_version // empty' "${plugin_file}" 2>/dev/null || true)"

  local rebuildable
  rebuildable="$(_wb_gui_dist_is_rebuildable "${path}")"

  # Probe .wb_dist_meta for built_by + components (an externally-added dist
  # that still came out of full-build.sh carries the same metadata, so users
  # should see the real builder, not "external" as a blanket label).
  local ext_built_by_json='"external"'
  local ext_built_utc="null"
  local ext_components_included="[]"
  local meta_file="${path}/.wb_dist_meta"
  if [[ -r "${meta_file}" ]]; then
    local mb
    mb="$(jq -r '.built_by // empty' "${meta_file}" 2>/dev/null || true)"
    if [[ -n "${mb}" ]]; then
      ext_built_by_json="$(printf '%s' "${mb}" | jq -R .)"
    fi
    local mu
    mu="$(jq -r '.build_utc // empty' "${meta_file}" 2>/dev/null || true)"
    if [[ -n "${mu}" ]]; then
      ext_built_utc="$(printf '%s' "${mu}" | jq -R .)"
    fi
    ext_components_included="$(jq -r \
      '[.components // {} | to_entries[] | select((.value.paths // [] | length) > 0) | .key] | sort' \
      "${meta_file}" 2>/dev/null || echo "[]")"
  fi

  jq -cn \
    --arg name "${name}" \
    --arg path "${path}" \
    --argjson active "${is_active}" \
    --argjson broken "${broken}" \
    --argjson broken_reason "${broken_reason}" \
    --arg external_source "${external_source}" \
    --arg wine_version "${wine_version}" \
    --argjson rebuildable "${rebuildable}" \
    --argjson built_by "${ext_built_by_json}" \
    --argjson built_utc "${ext_built_utc}" \
    --argjson components_included "${ext_components_included}" \
    '{
      name: $name,
      path: $path,
      source: "external",
      active: $active,
      built_by: $built_by,
      built_utc: $built_utc,
      last_built_at: $built_utc,
      wine_version: (if $wine_version == "" then null else $wine_version end),
      components_included: $components_included,
      component_versions: {},
      build_profile: null,
      external_source: (if $external_source == "" then null else $external_source end),
      rebuildable: $rebuildable,
      broken: $broken,
      broken_reason: $broken_reason
    }'
}

# ---------------------------------------------------------------------------
# Internal: sweep stale build-staging dirs and .old swap remnants
# Called at the start of registry_refresh.
# ---------------------------------------------------------------------------
_wb_gui_dist_gc_staging() {
  local wb_home
  wb_home="$(_wb_gui_dist_wb_home)"
  local staging_root="${wb_home}/dist/.build-staging"
  local now
  now="$(date +%s)"

  # Remove .build-staging subdirs older than 1 hour
  if [[ -d "${staging_root}" ]]; then
    local dir mtime age
    for dir in "${staging_root}"/*/; do
      [[ -d "${dir}" ]] || continue
      mtime="$(stat -c '%Y' "${dir}" 2>/dev/null || echo 0)"
      age=$(( now - mtime ))
      if [[ "${age}" -gt 3600 ]]; then
        rm -rf "${dir}" 2>/dev/null || true
      fi
    done
  fi

  # Remove .old arch-dir remnants under known native dists older than 10 minutes
  local dist_dir="${wb_home}/dist"
  if [[ -d "${dist_dir}" ]]; then
    local d
    for d in "${dist_dir}"/WINE-BLEEDING-*/lib/wine/*/*-windows.old; do
      [[ -d "${d}" ]] || continue
      mtime="$(stat -c '%Y' "${d}" 2>/dev/null || echo 0)"
      age=$(( now - mtime ))
      if [[ "${age}" -gt 600 ]]; then
        rm -rf "${d}" 2>/dev/null || true
      fi
    done
  fi
}

# ---------------------------------------------------------------------------
# wb_gui_dist_registry_refresh
# Rebuilds $WB_HOME/dists.json from:
#   - native dists: $WB_HOME/dist/WINE-BLEEDING-*/
#   - external dists: $WB_HOME/plugins/runtimes.d/*.json
# Also sweeps stale .build-staging dirs and .old swap remnants.
# ---------------------------------------------------------------------------
wb_gui_dist_registry_refresh() {
  local wb_home
  wb_home="$(_wb_gui_dist_wb_home)"

  # GC stale staging dirs first
  _wb_gui_dist_gc_staging

  # Resolve active alias once
  local active_path=""
  active_path="$(wb_dist_resolve_alias 2>/dev/null || true)"

  local dist_entries="[]"
  local active_name="null"

  # --- Native dists ---
  local dist_dir="${wb_home}/dist"
  if [[ -d "${dist_dir}" ]]; then
    local entry name path
    for entry in "${dist_dir}"/WINE-BLEEDING-*/; do
      [[ -d "${entry}" ]] || continue
      # Skip symlinks (the WINE-BLEEDING alias)
      [[ -L "${entry%/}" ]] && continue
      name="$(basename "${entry}")"
      path="$(realpath -m "${entry%/}" 2>/dev/null || echo "${entry%/}")"

      # Validate name pattern
      if [[ ! "${name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        wb_log_warn "wb_gui_dist_registry_refresh: skipping dist with invalid name '${name}'"
        continue
      fi

      local desc
      desc="$(_wb_gui_dist_describe_native "${name}" "${path}" "${active_path}")"
      dist_entries="$(printf '%s' "${dist_entries}" | jq --argjson e "${desc}" '. + [$e]')"

      # Track active name
      if printf '%s' "${desc}" | jq -e '.active == true' >/dev/null 2>&1; then
        active_name="\"${name}\""
      fi
    done
  fi

  # --- External dists (plugins/runtimes.d/*.json) ---
  local plugin_dir="${wb_home}/plugins/runtimes.d"
  if [[ -d "${plugin_dir}" ]]; then
    local pfile pname ppath canon_path
    for pfile in "${plugin_dir}"/*.json; do
      [[ -f "${pfile}" ]] || continue
      if ! jq empty "${pfile}" 2>/dev/null; then
        wb_log_warn "wb_gui_dist_registry_refresh: malformed plugin JSON '${pfile}', skipping"
        continue
      fi
      pname="$(jq -r '.name // empty' "${pfile}" 2>/dev/null || true)"
      ppath="$(jq -r '.path // empty' "${pfile}" 2>/dev/null || true)"
      if [[ -z "${pname}" || -z "${ppath}" ]]; then
        wb_log_warn "wb_gui_dist_registry_refresh: plugin '${pfile}' missing name/path, skipping"
        continue
      fi
      canon_path="$(realpath -m "${ppath}" 2>/dev/null || echo "${ppath}")"
      local ext_desc
      ext_desc="$(_wb_gui_dist_describe_external "${pname}" "${canon_path}" "${pfile}" "${active_path}")"
      dist_entries="$(printf '%s' "${dist_entries}" | jq --argjson e "${ext_desc}" '. + [$e]')"

      if printf '%s' "${ext_desc}" | jq -e '.active == true' >/dev/null 2>&1; then
        active_name="\"${pname}\""
      fi
    done
  fi

  local generated_utc
  generated_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local registry_json
  registry_json="$(jq -cn \
    --argjson schema 1 \
    --arg generated_utc "${generated_utc}" \
    --argjson active "${active_name}" \
    --argjson dists "${dist_entries}" \
    '{
      schema: $schema,
      generated_utc: $generated_utc,
      active: $active,
      dists: $dists
    }')"

  local reg_file
  reg_file="$(_wb_gui_dist_registry)"
  wb_json_write_atomic "${reg_file}" "${registry_json}"
}

# ---------------------------------------------------------------------------
# wb_gui_dist_registry_list
# Returns the dists array from dists.json as a JSON array string.
# Caller should run wb_gui_dist_registry_refresh first.
# ---------------------------------------------------------------------------
wb_gui_dist_registry_list() {
  local reg_file
  reg_file="$(_wb_gui_dist_registry)"
  if [[ ! -r "${reg_file}" ]]; then
    echo "[]"
    return 0
  fi
  jq -c '.dists // []' "${reg_file}" 2>/dev/null || echo "[]"
}

# ---------------------------------------------------------------------------
# wb_gui_dist_add_external <path> <name>
# Validate, then call wb runtime register to add an external dist.
# Pre-validates fields to give targeted UX errors before the CLI gate.
# The CLI (wb_runtimes_plugin_register) is the authoritative security gate.
# Returns 0 on success, 1 on failure (with error message on stderr).
# ---------------------------------------------------------------------------
wb_gui_dist_add_external() {
  local path="${1:-}"
  local name="${2:-}"

  # Validation: path required and absolute
  if [[ -z "${path}" ]] || [[ "${path}" != /* ]]; then
    echo "wb_gui_dist_add_external: path must be non-empty and absolute" >&2
    return 1
  fi

  # Validation: name pattern
  if [[ ! "${name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "wb_gui_dist_add_external: name must match ^[A-Za-z0-9._-]+$" >&2
    return 1
  fi

  # Validation: path must exist and be a directory
  if [[ ! -d "${path}" ]]; then
    echo "wb_gui_dist_add_external: path '${path}' does not exist or is not a directory" >&2
    return 1
  fi

  # Validation: bin/wine must exist and be executable
  if [[ ! -x "${path}/bin/wine" ]]; then
    echo "wb_gui_dist_add_external: '${path}/bin/wine' not found or not executable" >&2
    return 1
  fi

  # Validation: name must not already be registered
  local reg_file
  reg_file="$(_wb_gui_dist_registry)"
  if [[ -r "${reg_file}" ]]; then
    local already
    already="$(jq -r --arg n "${name}" '.dists[] | select(.name == $n) | .name' "${reg_file}" 2>/dev/null | head -1 || true)"
    if [[ -n "${already}" ]]; then
      echo "wb_gui_dist_add_external: name '${name}' is already registered" >&2
      return 1
    fi
  fi

  # Canonicalize path (M13-retro: realpath before handing to CLI)
  local canon_path
  canon_path="$(realpath -m "${path}")"

  # Copy the dist into $WB_HOME/dist/<name>/. Per product design, every
  # registered dist lives under WB_HOME — that way activate (which symlinks
  # WINE-BLEEDING -> dist path) is always pointing at a stable, project-owned
  # location and can never end up dangling because the user moved or deleted
  # the original external tree. Refusing to register pointer-style externals
  # also prevents the "ln: No such file or directory" failure mode where
  # WB_HOME/dist/ wasn't created yet.
  local wb_home
  wb_home="$(_wb_gui_dist_wb_home)"
  local local_dist_dir="${wb_home}/dist"
  local local_dist_path="${local_dist_dir}/${name}"

  if [[ -e "${local_dist_path}" ]]; then
    echo "wb_gui_dist_add_external: '${local_dist_path}' already exists; choose a different name or remove the old dist first" >&2
    return 1
  fi

  mkdir -p "${local_dist_dir}" || {
    echo "wb_gui_dist_add_external: could not create '${local_dist_dir}'" >&2
    return 1
  }

  # cp -a preserves permissions, ownership (where allowed), timestamps, and
  # symlinks — the right primitive for mirroring a Wine dist tree.
  if ! cp -a "${canon_path}/." "${local_dist_path}/" 2>/dev/null; then
    echo "wb_gui_dist_add_external: failed to copy '${canon_path}' -> '${local_dist_path}'" >&2
    rm -rf "${local_dist_path}" 2>/dev/null || true
    return 1
  fi

  # Sanity-check that the copy landed and bin/wine is still executable.
  if [[ ! -x "${local_dist_path}/bin/wine" ]]; then
    echo "wb_gui_dist_add_external: copy completed but '${local_dist_path}/bin/wine' is not executable" >&2
    rm -rf "${local_dist_path}" 2>/dev/null || true
    return 1
  fi

  # Read wine version for caching in plugin JSON (use the copy, not the source).
  local wine_version=""
  wine_version="$("${local_dist_path}/bin/wine" --version 2>/dev/null | head -1 || true)"

  # Build plugin JSON pointing at the LOCAL copy, not the external source.
  local plugin_dir="${wb_home}/plugins/runtimes.d"
  mkdir -p "${plugin_dir}"

  local plugin_json
  plugin_json="$(jq -cn \
    --arg schema "1" \
    --arg name "${name}" \
    --arg path "${local_dist_path}" \
    --arg wine_version "${wine_version}" \
    '{schema: ($schema | tonumber), name: $name, path: $path, wine_version: $wine_version}')"

  # Delegate to wb runtime register (security gate)
  # wb runtime register expects a plugin JSON file path
  local tmp_plugin
  tmp_plugin="$(mktemp "${plugin_dir}/.wb_plugin_tmp_XXXXXX.json")"
  printf '%s\n' "${plugin_json}" > "${tmp_plugin}"

  local register_ok=0
  if command -v wb &>/dev/null; then
    if wb runtime register "${tmp_plugin}" 2>/dev/null; then
      register_ok=1
    fi
  else
    # Fallback: place JSON directly (e.g., in test environments)
    mv -f "${tmp_plugin}" "${plugin_dir}/${name}.json"
    register_ok=1
  fi
  rm -f "${tmp_plugin}" 2>/dev/null || true

  if [[ "${register_ok}" -eq 0 ]]; then
    echo "wb_gui_dist_add_external: wb runtime register failed" >&2
    return 1
  fi

  wb_gui_dist_registry_refresh
  return 0
}

# ---------------------------------------------------------------------------
# wb_gui_dist_remove <name>
# Remove a dist:
#   - native: rm -rf $path; sets dist=null on apps
#   - external: wb runtime unregister <name>; sets dist=null on apps
# Active-dist protection enforced here.
# ---------------------------------------------------------------------------
wb_gui_dist_remove() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    echo "wb_gui_dist_remove: name required" >&2
    return 1
  fi

  local reg_file
  reg_file="$(_wb_gui_dist_registry)"
  if [[ ! -r "${reg_file}" ]]; then
    echo "wb_gui_dist_remove: registry not found; run wb_gui_dist_registry_refresh first" >&2
    return 1
  fi

  local entry
  entry="$(jq -c --arg n "${name}" '.dists[] | select(.name == $n)' "${reg_file}" 2>/dev/null | head -1 || true)"
  if [[ -z "${entry}" ]]; then
    echo "wb_gui_dist_remove: dist '${name}' not found in registry" >&2
    return 1
  fi

  # Active-dist protection
  local is_active
  is_active="$(printf '%s' "${entry}" | jq -r '.active')"
  if [[ "${is_active}" == "true" ]]; then
    echo "wb_gui_dist_remove: cannot remove active dist '${name}'; activate a different dist first" >&2
    return 1
  fi

  local source dist_path
  source="$(printf '%s' "${entry}" | jq -r '.source')"
  dist_path="$(printf '%s' "${entry}" | jq -r '.path')"

  case "${source}" in
    native)
      # Clear apps referencing this dist before deletion
      wb_gui_dist_apps_clear "${name}" 2>/dev/null || true
      if [[ -d "${dist_path}" ]]; then
        rm -rf "${dist_path}"
      fi
      ;;
    external)
      wb_gui_dist_apps_clear "${name}" 2>/dev/null || true
      if command -v wb &>/dev/null; then
        wb runtime unregister "${name}" 2>/dev/null || true
      else
        # Fallback: remove plugin file directly
        local wb_home
        wb_home="$(_wb_gui_dist_wb_home)"
        rm -f "${wb_home}/plugins/runtimes.d/${name}.json" 2>/dev/null || true
      fi
      ;;
    *)
      echo "wb_gui_dist_remove: unsupported source '${source}' for dist '${name}'" >&2
      return 1
      ;;
  esac

  wb_gui_dist_registry_refresh
  return 0
}

# ---------------------------------------------------------------------------
# wb_gui_dist_activate <name>
# Activate a dist via wb runtime activate (swaps WINE-BLEEDING symlink).
# ---------------------------------------------------------------------------
wb_gui_dist_activate() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    echo "wb_gui_dist_activate: name required" >&2
    return 1
  fi

  if command -v wb &>/dev/null; then
    if ! wb runtime activate "${name}" 2>&1; then
      echo "wb_gui_dist_activate: 'wb runtime activate ${name}' failed" >&2
      return 1
    fi
  else
    # Fallback for test environments: call wb_dist_set_alias directly
    local wb_home
    wb_home="$(_wb_gui_dist_wb_home)"
    local dist_path="${wb_home}/dist/${name}"
    if [[ ! -d "${dist_path}" ]]; then
      echo "wb_gui_dist_activate: dist path '${dist_path}' not found" >&2
      return 1
    fi
    wb_dist_set_alias "${dist_path}"
  fi

  wb_gui_dist_registry_refresh
  return 0
}

# ---------------------------------------------------------------------------
# wb_gui_dist_apps_count <dist_name>
# Returns the count of apps with .dist == dist_name.
# ---------------------------------------------------------------------------
wb_gui_dist_apps_count() {
  local dist_name="${1:-}"
  local wb_home
  wb_home="$(_wb_gui_dist_wb_home)"
  local apps_file="${wb_home}/apps.json"
  if [[ ! -r "${apps_file}" ]]; then
    echo 0
    return 0
  fi
  jq -r --arg n "${dist_name}" '[.apps[] | select(.dist == $n)] | length' "${apps_file}" 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
# wb_gui_dist_apps_clear <dist_name>
# Sets .dist = null on all apps referencing this dist.
# Idempotent — no-op if no apps reference it.
# ---------------------------------------------------------------------------
wb_gui_dist_apps_clear() {
  local dist_name="${1:-}"
  if [[ -z "${dist_name}" ]]; then
    echo "wb_gui_dist_apps_clear: dist_name required" >&2
    return 1
  fi

  local wb_home
  wb_home="$(_wb_gui_dist_wb_home)"
  local apps_file="${wb_home}/apps.json"
  if [[ ! -r "${apps_file}" ]]; then
    return 0  # no apps.json — no-op
  fi

  local count
  count="$(jq -r --arg n "${dist_name}" '[.apps[] | select(.dist == $n)] | length' "${apps_file}" 2>/dev/null || echo 0)"
  if [[ "${count}" -eq 0 ]]; then
    return 0
  fi

  local updated_json
  updated_json="$(jq \
    --arg n "${dist_name}" \
    '.apps |= map(if .dist == $n then .dist = null else . end)' \
    "${apps_file}")"
  wb_json_write_atomic "${apps_file}" "${updated_json}"
}

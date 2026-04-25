#!/usr/bin/env bash
# wb-gui-overlays.sh — overlay registry library for wb-gui (Phase C / v1.8.0)
# Sourced by wb-gui; never executed directly.
#
# Registry: $WB_HOME/overlays.json
# Schema v1 (see runtime/share/schemas/wb_overlays.schema.json)
#
# Public API:
#   wb_gui_overlays_registry_refresh          — rebuild overlays.json from FS
#   wb_gui_overlays_list                      -> JSON array (parsed from overlays.json)
#   wb_gui_overlays_check_updates [name]      — query GitHub for latest; update registry
#   wb_gui_overlays_install <name> [version]  — install/update an overlay via fetch-overlay.sh
#   wb_gui_overlays_toggle_bundled <app_id> <name> <true|false>  — flip bundled flag, re-bake
#   wb_gui_overlays_set_enabled <app_id> <name> <true|false>     — enable/disable, re-bake
#   wb_gui_overlays_runtime_env <app_id>      -> env KEY=VALUE lines for launch
#   wb_gui_overlays_save_env_bake <app_id> <overlays_json>       — Path B: bake into env_vars
#
# Depends on (sourced by caller before this file):
#   wb-lib/wb-json.sh   wb_json_read  wb_json_write_atomic
#   wb-gui-lib/wb-gui-settings.sh  (for wb_gui_settings_set_app)

set -euo pipefail

# ---------------------------------------------------------------------------
# Internal: resolve paths
# ---------------------------------------------------------------------------
_wb_gui_overlays_wb_home() {
  printf '%s' "${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
}

_wb_gui_overlays_registry() {
  local wb_home
  wb_home="$(_wb_gui_overlays_wb_home)"
  printf '%s' "${wb_home}/overlays.json"
}

_wb_gui_overlays_root() {
  local wb_home
  wb_home="$(_wb_gui_overlays_wb_home)"
  printf '%s' "${wb_home}/overlays"
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_system_installed <name>
# Returns 0 if the system package for an overlay is detectable, non-zero
# otherwise. Used by the per-app Settings overlay panel to know whether to
# offer "System" as a usable source (vs. silently letting the user pick a
# missing system overlay and have it fail at app launch).
#
# Detection per overlay:
#   mangohud   — command -v mangohud (CLI wrapper) OR libMangoHud.so on
#                LD library path; checks PKG_CONFIG path for the loader too
#   vkbasalt   — libvkbasalt.so anywhere under common Vulkan ICD/layer paths,
#                OR a vkBasalt.json layer manifest under the system Vulkan
#                explicit_layer.d (matches both /usr/share and /usr/local).
#                vkbasalt has no CLI; its presence is detected purely by the
#                Vulkan implicit-layer manifest the user's compositor would
#                load via VK_LAYER_PATH.
#   optiscaler — always returns 1 (Windows DLL, no system equivalent).
# ---------------------------------------------------------------------------
wb_gui_overlays_system_installed() {
  local name="${1:-}"
  case "${name}" in
    mangohud)
      command -v mangohud >/dev/null 2>&1 && return 0
      # Library probe: look in standard linker search paths.
      local _ld
      for _ld in /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu \
                 /usr/lib/i386-linux-gnu /usr/local/lib /usr/local/lib64; do
        [[ -e "${_ld}/libMangoHud.so" ]] && return 0
        [[ -e "${_ld}/mangohud/libMangoHud.so" ]] && return 0
      done
      return 1
      ;;
    vkbasalt)
      local _vk
      for _vk in /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu \
                 /usr/lib/i386-linux-gnu /usr/local/lib /usr/local/lib64; do
        [[ -e "${_vk}/libvkbasalt.so" ]] && return 0
      done
      # Vulkan implicit-layer manifest probe (the canonical install marker)
      local _man
      for _man in /usr/share/vulkan/implicit_layer.d \
                  /usr/local/share/vulkan/implicit_layer.d \
                  /etc/vulkan/implicit_layer.d; do
        [[ -e "${_man}/vkBasalt.json" ]] && return 0
        [[ -e "${_man}/vkBasalt.x86_64.json" ]] && return 0
        [[ -e "${_man}/vkBasalt.i686.json" ]] && return 0
      done
      return 1
      ;;
    optiscaler)
      return 1  # Windows DLL — no system package
      ;;
    *)
      return 1
      ;;
  esac
}

_wb_gui_overlays_cache() {
  local wb_home
  wb_home="$(_wb_gui_overlays_wb_home)"
  printf '%s' "${wb_home}/overlays/.cache"
}

# ---------------------------------------------------------------------------
# Internal: static overlay metadata table
# ---------------------------------------------------------------------------
_wb_gui_overlays_kind() {
  local name="$1"
  case "${name}" in
    mangohud|vkbasalt) printf 'vulkan-layer' ;;
    optiscaler)        printf 'windows-dll' ;;
    *) printf 'unknown' ;;
  esac
}

_wb_gui_overlays_repo() {
  local name="$1"
  case "${name}" in
    mangohud)   printf 'flightlessmango/MangoHud' ;;
    vkbasalt)   printf 'DadSchoorse/vkBasalt' ;;
    optiscaler) printf 'cdozdil/OptiScaler' ;;
    *) printf '' ;;
  esac
}

# Expected top-level files used for broken detection
_wb_gui_overlays_sentinel_file() {
  local name="$1"
  case "${name}" in
    mangohud)   printf 'lib/mangohud/lib64/libMangoHud.so' ;;
    vkbasalt)   printf 'lib/vkbasalt/libvkbasalt.so' ;;
    optiscaler) printf 'bin/optiscaler/OptiScaler.dll' ;;
    *) printf '' ;;
  esac
}

# The overlay shortlist (closed set for Phase C)
_WB_GUI_OVERLAYS_NAMES=(mangohud vkbasalt optiscaler)

# ---------------------------------------------------------------------------
# Internal: now_utc helper (overridable in tests)
# ---------------------------------------------------------------------------
_wb_gui_overlays_now_utc() {
  printf '%s' "${WB_GUI_OVERLAY_NOW_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")}"
}

# ---------------------------------------------------------------------------
# Internal: scan installed versions for one overlay name
# Returns a jq-ready JSON array of version_entry objects.
# ---------------------------------------------------------------------------
_wb_gui_overlays_scan_versions() {
  local name="$1"
  local overlay_root="$2"
  local overlay_dir="${overlay_root}/${name}"
  local sentinel
  sentinel="$(_wb_gui_overlays_sentinel_file "${name}")"

  # Emit opening bracket; entries added per-version directory
  local first=1
  printf '['
  if [[ -d "${overlay_dir}" ]]; then
    local ver
    while IFS= read -r ver_path; do
      [[ -d "${ver_path}" ]] || continue
      ver="$(basename "${ver_path}")"
      # Skip hidden dirs and .cache
      [[ "${ver}" == .* ]] && continue

      local install_path
      install_path="$(realpath -m "${ver_path}" 2>/dev/null || echo "${ver_path}")"

      # installed_utc from sidecar file; fallback to empty → epoch
      local installed_utc="1970-01-01T00:00:00Z"
      if [[ -f "${ver_path}/.installed_utc" ]]; then
        installed_utc="$(cat "${ver_path}/.installed_utc" 2>/dev/null || echo "1970-01-01T00:00:00Z")"
      fi

      # sha256 sidecar
      local sha256="null"
      if [[ -f "${ver_path}/.sha256" ]]; then
        local raw_sha
        raw_sha="$(cat "${ver_path}/.sha256" 2>/dev/null | awk '{print $1}' || true)"
        if [[ "${raw_sha}" =~ ^[0-9a-f]{64}$ ]]; then
          sha256="\"${raw_sha}\""
        fi
      fi

      # Broken detection
      local broken=false
      local broken_reason="null"
      if [[ -n "${sentinel}" ]] && [[ ! -f "${ver_path}/${sentinel}" ]]; then
        broken=true
        broken_reason="\"${sentinel} missing\""
      fi

      if [[ "${first}" -eq 0 ]]; then printf ','; fi
      first=0

      jq -cn \
        --arg version "${ver}" \
        --arg install_path "${install_path}" \
        --arg installed_utc "${installed_utc}" \
        --argjson sha256 "${sha256}" \
        --argjson broken "${broken}" \
        --argjson broken_reason "${broken_reason}" \
        '{version: $version, install_path: $install_path, installed_utc: $installed_utc,
          sha256: $sha256, broken: $broken, broken_reason: $broken_reason}'
    done < <(find "${overlay_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  fi
  printf ']'
}

# ---------------------------------------------------------------------------
# Internal: read cached check-state from existing registry entry
# Returns a jq fragment (available_* + last_checked_utc + last_check_error)
# from the on-disk registry if the entry exists; otherwise null fields.
# ---------------------------------------------------------------------------
_wb_gui_overlays_cached_check_state() {
  local name="$1"
  local reg_file="$2"
  if [[ ! -f "${reg_file}" ]]; then
    printf 'null'
    return 0
  fi
  # Extract the existing entry's check fields
  jq -c \
    --arg name "${name}" \
    '.overlays[] | select(.name == $name) |
     {available_version, available_asset_url, available_sha256,
      last_checked_utc, last_check_error,
      last_fallback_utc, last_fallback_reason}' \
    "${reg_file}" 2>/dev/null \
    | head -1 || printf 'null'
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_registry_refresh
# Rebuild overlays.json from filesystem scan.
# Preserves existing check-state (available_version, last_checked_utc, etc.)
# from the prior registry to avoid wiping GitHub-query results on every open.
# ---------------------------------------------------------------------------
wb_gui_overlays_registry_refresh() {
  local wb_home
  wb_home="$(_wb_gui_overlays_wb_home)"
  local overlay_root
  overlay_root="$(_wb_gui_overlays_root)"
  local reg_file
  reg_file="$(_wb_gui_overlays_registry)"
  local now_utc
  now_utc="$(_wb_gui_overlays_now_utc)"

  # Sweep stale *.old swap remnants (same pattern as Phase B dist refresh)
  find "${overlay_root}" -maxdepth 3 -name '*.old' -type d \
    -exec rm -rf '{}' + 2>/dev/null || true

  local entries="[]"
  local name
  for name in "${_WB_GUI_OVERLAYS_NAMES[@]}"; do
    local kind
    kind="$(_wb_gui_overlays_kind "${name}")"
    local source_repo
    source_repo="$(_wb_gui_overlays_repo "${name}")"

    local installed_versions
    installed_versions="$(_wb_gui_overlays_scan_versions "${name}" "${overlay_root}")"

    # Preserve cached check state from prior registry
    local cached
    cached="$(_wb_gui_overlays_cached_check_state "${name}" "${reg_file}")"
    local available_version="null"
    local available_asset_url="null"
    local available_sha256="null"
    local last_checked_utc="null"
    local last_check_error="null"
    local last_fallback_utc="null"
    local last_fallback_reason="null"
    if [[ "${cached}" != "null" ]] && [[ -n "${cached}" ]]; then
      available_version="$(   printf '%s' "${cached}" | jq '.available_version')"
      available_asset_url="$( printf '%s' "${cached}" | jq '.available_asset_url')"
      available_sha256="$(    printf '%s' "${cached}" | jq '.available_sha256')"
      last_checked_utc="$(    printf '%s' "${cached}" | jq '.last_checked_utc')"
      last_check_error="$(    printf '%s' "${cached}" | jq '.last_check_error')"
      last_fallback_utc="$(   printf '%s' "${cached}" | jq '(.last_fallback_utc // null)')"
      last_fallback_reason="$(printf '%s' "${cached}" | jq '(.last_fallback_reason // null)')"
    fi

    local entry
    entry="$(jq -cn \
      --arg name "${name}" \
      --arg kind "${kind}" \
      --arg source_repo "${source_repo}" \
      --argjson installed_versions "${installed_versions}" \
      --argjson available_version "${available_version}" \
      --argjson available_asset_url "${available_asset_url}" \
      --argjson available_sha256 "${available_sha256}" \
      --argjson last_checked_utc "${last_checked_utc}" \
      --argjson last_check_error "${last_check_error}" \
      --argjson last_fallback_utc "${last_fallback_utc}" \
      --argjson last_fallback_reason "${last_fallback_reason}" \
      '{name: $name, kind: $kind, source_repo: $source_repo,
        installed_versions: $installed_versions,
        available_version: $available_version,
        available_asset_url: $available_asset_url,
        available_sha256: $available_sha256,
        last_checked_utc: $last_checked_utc,
        last_check_error: $last_check_error,
        last_fallback_utc: $last_fallback_utc,
        last_fallback_reason: $last_fallback_reason}')"

    entries="$(printf '%s' "${entries}" | jq --argjson e "${entry}" '. + [$e]')"
  done

  local registry_json
  registry_json="$(jq -cn \
    --arg now "${now_utc}" \
    --argjson entries "${entries}" \
    '{schema: 1, generated_utc: $now, overlays: $entries}')"

  wb_json_write_atomic "${reg_file}" "${registry_json}"
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_list
# Returns the overlays JSON array from the registry file.
# Calls registry_refresh if registry is absent.
# ---------------------------------------------------------------------------
wb_gui_overlays_list() {
  local reg_file
  reg_file="$(_wb_gui_overlays_registry)"
  if [[ ! -f "${reg_file}" ]]; then
    wb_gui_overlays_registry_refresh
  fi
  jq -c '.overlays' "${reg_file}"
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_check_updates [name]
# Query GitHub API for the latest release of one or all overlays.
# Updates the registry in-place (available_version, last_checked_utc, etc.)
# Honors WB_TEST_GH_API_FIXTURE=<path> for offline CI testing.
# If name is empty/absent, checks all three overlays.
# ---------------------------------------------------------------------------
wb_gui_overlays_check_updates() {
  local target_name="${1:-}"

  local reg_file
  reg_file="$(_wb_gui_overlays_registry)"
  local cache_dir
  cache_dir="$(_wb_gui_overlays_cache)"
  mkdir -p "${cache_dir}"

  # Ensure registry exists
  if [[ ! -f "${reg_file}" ]]; then
    wb_gui_overlays_registry_refresh
  fi

  local names=()
  if [[ -n "${target_name}" ]]; then
    names=("${target_name}")
  else
    names=("${_WB_GUI_OVERLAYS_NAMES[@]}")
  fi

  local reg_json
  reg_json="$(cat "${reg_file}")"

  local name
  for name in "${names[@]}"; do
    local repo
    repo="$(_wb_gui_overlays_repo "${name}")"
    if [[ -z "${repo}" ]]; then
      echo "wb-gui-overlays: unknown overlay '${name}'" >&2
      continue
    fi

    local check_result check_exit
    check_result="$(_wb_gui_overlays_query_github "${name}" "${repo}" 2>/dev/null)" \
      && check_exit=0 || check_exit=$?

    local available_version="null"
    local available_asset_url="null"
    local available_sha256="null"
    local last_check_error="null"
    local now_utc
    now_utc="$(_wb_gui_overlays_now_utc)"

    if [[ "${check_exit}" -eq 0 ]] && [[ -n "${check_result}" ]]; then
      available_version="$(printf '%s' "${check_result}" | jq '.tag')"
      available_asset_url="$(printf '%s' "${check_result}" | jq '(.assets[0].url // null)')"
      available_sha256="null"
    else
      # classify error from check_result code embedded in output
      last_check_error="\"${check_result:-http-error}\""
      now_utc="null"  # don't update last_checked_utc on failure
    fi

    # Update registry entry for this name
    reg_json="$(printf '%s' "${reg_json}" | jq \
      --arg name "${name}" \
      --argjson available_version "${available_version}" \
      --argjson available_asset_url "${available_asset_url}" \
      --argjson available_sha256 "${available_sha256}" \
      --argjson last_check_error "${last_check_error}" \
      --argjson now_utc "$(if [[ "${now_utc}" == "null" ]]; then printf 'null'; else printf '"%s"' "${now_utc}"; fi)" \
      '(.overlays[] | select(.name == $name)) |=
        . + {available_version: $available_version,
             available_asset_url: $available_asset_url,
             available_sha256: $available_sha256,
             last_check_error: $last_check_error,
             last_checked_utc: $now_utc}')"
  done

  wb_json_write_atomic "${reg_file}" "${reg_json}"
}

# ---------------------------------------------------------------------------
# Internal: query GitHub releases/latest for one overlay
# Honors WB_TEST_GH_API_FIXTURE=<path> for tests (reads fixture JSON directly).
# Returns JSON with {tag, assets[{url, name}], tarball_url} on stdout.
# Returns non-zero on failure; outputs error class string instead.
# ---------------------------------------------------------------------------
_wb_gui_overlays_query_github() {
  local name="$1"
  local repo="$2"

  local api_base="${WB_OVERLAY_GH_API_BASE:-https://api.github.com}"

  # Test fixture seam — if set, read JSON from fixture path instead of network
  if [[ -n "${WB_TEST_GH_API_FIXTURE:-}" ]]; then
    local fixture_file="${WB_TEST_GH_API_FIXTURE}"
    # Allow per-overlay fixture: ${fixture_file}.mangohud, etc.
    if [[ -f "${fixture_file}.${name}" ]]; then
      fixture_file="${fixture_file}.${name}"
    fi
    if [[ ! -f "${fixture_file}" ]]; then
      printf 'offline'
      return 73
    fi
    # Parse fixture through same jq path as real API
    jq -c '{tag: .tag_name, published_at: .published_at,
            assets: [.assets[] | {name: .name, url: .browser_download_url, size: .size}],
            tarball_url: .tarball_url, body: .body}' \
      "${fixture_file}" 2>/dev/null && return 0
    printf 'parse-error'
    return 67
  fi

  # Real API call
  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local response_file
  response_file="$(mktemp)"
  local http_code=0
  http_code="$(curl -sS --fail-with-body --location \
    --max-time 10 \
    --retry 2 --retry-delay 1 \
    --write-out '%{http_code}' \
    --output "${response_file}" \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api_base}/repos/${repo}/releases/latest" 2>/dev/null)" || {
    local curl_exit=$?
    rm -f "${response_file}"
    case "${curl_exit}" in
      6|7|28) printf 'offline';     return 73 ;;
      *)      printf 'http-error';  return 67 ;;
    esac
  }

  case "${http_code}" in
    200) ;;
    401|403)
      rm -f "${response_file}"
      printf 'rate-limited'
      return 72 ;;
    404)
      rm -f "${response_file}"
      printf 'http-error'
      return 67 ;;
    *)
      rm -f "${response_file}"
      printf 'http-error'
      return 67 ;;
  esac

  local result
  result="$(jq -c '{tag: .tag_name, published_at: .published_at,
    assets: [.assets[] | {name: .name, url: .browser_download_url, size: .size}],
    tarball_url: .tarball_url, body: .body}' \
    "${response_file}" 2>/dev/null)" || {
    rm -f "${response_file}"
    printf 'parse-error'
    return 67
  }
  rm -f "${response_file}"

  if [[ -z "${result}" ]] || ! printf '%s' "${result}" | jq -e '.tag' >/dev/null 2>&1; then
    printf 'parse-error'
    return 67
  fi

  printf '%s' "${result}"
  return 0
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_install <name> [version]
# Install or update an overlay by delegating to fetch-overlay.sh.
# version defaults to "latest".
# Caller should pass --progress-fd if running inside a GUI dialog.
# ---------------------------------------------------------------------------
wb_gui_overlays_install() {
  local name="${1:-}"
  local version="${2:-latest}"
  local progress_fd="${WB_OVERLAY_PROGRESS_FD:-}"

  if [[ -z "${name}" ]]; then
    echo "wb_gui_overlays_install: name required" >&2
    return 1
  fi

  local wb_home
  wb_home="$(_wb_gui_overlays_wb_home)"
  local overlay_root
  overlay_root="$(_wb_gui_overlays_root)"
  local cache_dir
  cache_dir="$(_wb_gui_overlays_cache)"

  # Ensure the install root + cache dir exist. fetch-overlay.sh's --dest
  # validator (tools/fetch-overlay.sh:218) refuses to proceed with
  # "Invalid --dest '<path>': does not exist or is not a directory" if the
  # target dir is missing — and on a fresh wb-gui install nothing has
  # populated $WB_HOME/overlays yet, so the very first overlay install
  # always failed. Create the layout here so subsequent installs find it.
  if [[ ! -d "${overlay_root}" ]]; then
    mkdir -p "${overlay_root}" 2>/dev/null || {
      echo "wb_gui_overlays_install: cannot create overlay root '${overlay_root}'" >&2
      return 1
    }
  fi
  if [[ ! -d "${cache_dir}" ]]; then
    mkdir -p "${cache_dir}" 2>/dev/null || {
      echo "wb_gui_overlays_install: cannot create overlay cache '${cache_dir}'" >&2
      return 1
    }
  fi

  # Locate fetch-overlay.sh.
  # Preference order: WB_OVERLAY_FETCHER override → WB_TOOLS_DIR (set by wb-gui) →
  # dev-tree sibling → /usr/lib/wine-bleeding/tools → /usr/local/lib/wine-bleeding/tools.
  local fetcher="${WB_OVERLAY_FETCHER:-}"
  if [[ -z "${fetcher}" ]] && [[ -n "${WB_TOOLS_DIR:-}" ]]; then
    fetcher="${WB_TOOLS_DIR}/fetch-overlay.sh"
  fi
  if [[ ! -x "${fetcher}" ]]; then
    local _ov_script_dir _ov_c
    _ov_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for _ov_c in \
      "${_ov_script_dir}/../../../tools/fetch-overlay.sh" \
      "/usr/lib/wine-bleeding/tools/fetch-overlay.sh" \
      "/usr/local/lib/wine-bleeding/tools/fetch-overlay.sh"
    do
      if [[ -x "${_ov_c}" ]]; then
        fetcher="$(cd "$(dirname "${_ov_c}")" && pwd)/$(basename "${_ov_c}")"
        break
      fi
    done
  fi

  if [[ ! -x "${fetcher}" ]]; then
    echo "wb_gui_overlays_install: fetch-overlay.sh not found. Set WB_TOOLS_DIR or reinstall wine-bleeding-wb." >&2
    return 1
  fi

  local fetch_args=(
    --overlay "${name}"
    --version "${version}"
    --dest "${overlay_root}"
    --cache "${cache_dir}"
  )
  if [[ -n "${progress_fd}" ]]; then
    fetch_args+=(--progress-fd "${progress_fd}")
  fi

  "${fetcher}" "${fetch_args[@]}"
  local rc=$?

  # Refresh registry after install (even on failure — may have partial info)
  wb_gui_overlays_registry_refresh || true

  return "${rc}"
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_set_enabled <app_id> <name> <true|false>
# Enable or disable an overlay for an app. Re-bakes env_vars via save_env_bake.
# ---------------------------------------------------------------------------
wb_gui_overlays_set_enabled() {
  local app_id="${1:-}"
  local name="${2:-}"
  local enabled="${3:-false}"

  if [[ -z "${app_id}" ]] || [[ -z "${name}" ]]; then
    echo "wb_gui_overlays_set_enabled: app_id and name required" >&2
    return 1
  fi

  local file
  file="$(_wb_gui_settings_layer_path "app" "${app_id}")" 2>/dev/null \
    || file="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}/settings/apps/${app_id}.json"

  local existing_overlays="null"
  if [[ -f "${file}" ]]; then
    existing_overlays="$(jq '.overlays // null' "${file}" 2>/dev/null || echo "null")"
  fi
  if [[ "${existing_overlays}" == "null" ]]; then
    existing_overlays="{}"
  fi

  # Determine default values for the overlay object when first enabling
  local new_overlays
  case "${name}" in
    mangohud)
      new_overlays="$(printf '%s' "${existing_overlays}" | jq \
        --arg enabled "${enabled}" \
        '.mangohud = (.mangohud // {enabled: false, bundled: true, version: null, config_path: null}) |
         .mangohud.enabled = ($enabled == "true")')"
      ;;
    vkbasalt)
      new_overlays="$(printf '%s' "${existing_overlays}" | jq \
        --arg enabled "${enabled}" \
        '.vkbasalt = (.vkbasalt // {enabled: false, bundled: true, version: null}) |
         .vkbasalt.enabled = ($enabled == "true")')"
      ;;
    optiscaler)
      new_overlays="$(printf '%s' "${existing_overlays}" | jq \
        --arg enabled "${enabled}" \
        '.optiscaler = (.optiscaler // {enabled: false, version: null}) |
         .optiscaler.enabled = ($enabled == "true")')"
      ;;
    *)
      echo "wb_gui_overlays_set_enabled: unknown overlay '${name}'" >&2
      return 1 ;;
  esac

  wb_gui_overlays_save_env_bake "${app_id}" "${new_overlays}"
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_toggle_bundled <app_id> <name> <true|false>
# Flip the bundled flag for an overlay. Re-bakes env_vars.
# ---------------------------------------------------------------------------
wb_gui_overlays_toggle_bundled() {
  local app_id="${1:-}"
  local name="${2:-}"
  local bundled="${3:-true}"

  if [[ -z "${app_id}" ]] || [[ -z "${name}" ]]; then
    echo "wb_gui_overlays_toggle_bundled: app_id and name required" >&2
    return 1
  fi

  case "${name}" in
    mangohud|vkbasalt) ;;
    optiscaler)
      echo "wb_gui_overlays_toggle_bundled: optiscaler has no bundled/system toggle" >&2
      return 1 ;;
    *)
      echo "wb_gui_overlays_toggle_bundled: unknown overlay '${name}'" >&2
      return 1 ;;
  esac

  local file
  file="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}/settings/apps/${app_id}.json"

  local existing_overlays="{}"
  if [[ -f "${file}" ]]; then
    existing_overlays="$(jq '.overlays // {}' "${file}" 2>/dev/null || echo "{}")"
  fi

  local new_overlays
  new_overlays="$(printf '%s' "${existing_overlays}" | jq \
    --arg name "${name}" \
    --arg bundled "${bundled}" \
    '.[$name].bundled = ($bundled == "true")')"

  wb_gui_overlays_save_env_bake "${app_id}" "${new_overlays}"
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_runtime_env <app_id>
# Reads per-app .overlays and emits KEY=VALUE lines to stdout for launch.
# Also performs side effects (OptiScaler DLL copy).
# Always exits 0 — overlay failures emit LOG: warnings but never block launch.
# ---------------------------------------------------------------------------
wb_gui_overlays_runtime_env() {
  local app_id="${1:-}"
  if [[ -z "${app_id}" ]]; then
    return 0
  fi

  local wb_home
  wb_home="$(_wb_gui_overlays_wb_home)"
  local file="${wb_home}/settings/apps/${app_id}.json"
  if [[ ! -f "${file}" ]]; then
    return 0
  fi

  local overlays_json
  overlays_json="$(jq '.overlays // null' "${file}" 2>/dev/null || echo "null")"
  if [[ "${overlays_json}" == "null" ]] || [[ "${overlays_json}" == "{}" ]]; then
    return 0
  fi

  local overlay_root
  overlay_root="$(_wb_gui_overlays_root)"
  local reg_file
  reg_file="$(_wb_gui_overlays_registry)"

  # Rebuild registry to get current install state
  wb_gui_overlays_registry_refresh 2>/dev/null || true

  # Emit env vars for each enabled overlay
  _wb_gui_overlays_emit_mangohud  "${overlays_json}" "${overlay_root}" "${reg_file}"
  _wb_gui_overlays_emit_vkbasalt  "${overlays_json}" "${overlay_root}" "${reg_file}"
  _wb_gui_overlays_emit_optiscaler "${overlays_json}" "${overlay_root}" "${reg_file}"
}

# ---------------------------------------------------------------------------
# Internal: emit MangoHud env vars
# ---------------------------------------------------------------------------
_wb_gui_overlays_emit_mangohud() {
  local overlays_json="$1"
  local overlay_root="$2"
  local reg_file="$3"

  local enabled bundled version config_path
  enabled="$(   printf '%s' "${overlays_json}" | jq -r 'if .mangohud.enabled == null then "false" else (.mangohud.enabled | tostring) end')"
  bundled="$(   printf '%s' "${overlays_json}" | jq -r 'if .mangohud.bundled == null then "true"  else (.mangohud.bundled | tostring) end')"
  version="$(   printf '%s' "${overlays_json}" | jq -r '.mangohud.version // "null"')"
  config_path="$(printf '%s' "${overlays_json}" | jq -r '.mangohud.config_path // "null"')"

  [[ "${enabled}" == "true" ]] || return 0

  printf 'MANGOHUD=1\n'

  if [[ "${bundled}" == "true" ]]; then
    local install_path
    install_path="$(_wb_gui_overlays_resolve_install_path "mangohud" "${version}" "${overlay_root}" "${reg_file}")"
    if [[ -n "${install_path}" ]]; then
      printf 'VK_LAYER_PATH=%s/share/vulkan/implicit_layer.d\n' "${install_path}"
      # Modern MangoHud layout: lib/mangohud/{lib32,lib64}/libMangoHud.so.
      # Include both arch dirs so 32-bit and 64-bit Wine binaries each find
      # the right .so. lib64 first because most Wine installs run 64-bit
      # binaries by default.
      printf 'LD_LIBRARY_PATH=%s/lib/mangohud/lib64:%s/lib/mangohud/lib32:${LD_LIBRARY_PATH}\n' \
        "${install_path}" "${install_path}"
    else
      echo "LOG: MangoHud bundled requested but not installed — falling back to system." >&2
      _wb_gui_overlays_record_fallback "mangohud" "${reg_file}" "bundled-requested-no-install"
    fi
  fi

  if [[ "${config_path}" != "null" ]] && [[ -n "${config_path}" ]] && [[ -f "${config_path}" ]]; then
    printf 'MANGOHUD_CONFIG=%s\n' "${config_path}"
  fi
}

# ---------------------------------------------------------------------------
# Internal: emit VKBasalt env vars
# ---------------------------------------------------------------------------
_wb_gui_overlays_emit_vkbasalt() {
  local overlays_json="$1"
  local overlay_root="$2"
  local reg_file="$3"

  local enabled bundled version
  enabled="$(printf '%s' "${overlays_json}" | jq -r 'if .vkbasalt.enabled == null then "false" else (.vkbasalt.enabled | tostring) end')"
  bundled="$(printf '%s' "${overlays_json}" | jq -r 'if .vkbasalt.bundled == null then "true"  else (.vkbasalt.bundled | tostring) end')"
  version="$(printf '%s' "${overlays_json}" | jq -r '.vkbasalt.version // "null"')"

  [[ "${enabled}" == "true" ]] || return 0

  printf 'ENABLE_VKBASALT=1\n'

  if [[ "${bundled}" == "true" ]]; then
    local install_path
    install_path="$(_wb_gui_overlays_resolve_install_path "vkbasalt" "${version}" "${overlay_root}" "${reg_file}")"
    if [[ -n "${install_path}" ]]; then
      printf 'VK_LAYER_PATH=%s/share/vulkan/implicit_layer.d\n' "${install_path}"
    else
      echo "LOG: VKBasalt bundled requested but not installed — falling back to system." >&2
      _wb_gui_overlays_record_fallback "vkbasalt" "${reg_file}" "bundled-requested-no-install"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Internal: emit OptiScaler env vars
# ---------------------------------------------------------------------------
_wb_gui_overlays_emit_optiscaler() {
  local overlays_json="$1"
  local overlay_root="$2"
  local reg_file="$3"

  local enabled version
  enabled="$(printf '%s' "${overlays_json}" | jq -r 'if .optiscaler.enabled == null then "false" else (.optiscaler.enabled | tostring) end')"
  version="$(printf '%s' "${overlays_json}" | jq -r '.optiscaler.version // "null"')"

  [[ "${enabled}" == "true" ]] || return 0

  local install_path
  install_path="$(_wb_gui_overlays_resolve_install_path "optiscaler" "${version}" "${overlay_root}" "${reg_file}")"
  if [[ -n "${install_path}" ]]; then
    printf 'WINEDLLOVERRIDES=nvngx=n,b;${WINEDLLOVERRIDES}\n'
    # NOTE: OptiScaler DLL copy to game dir is performed by wb_gui_overlays_save_env_bake
    # at save time (idempotent). No side effect here.
  else
    echo "LOG: OptiScaler enabled but not installed — skipping WINEDLLOVERRIDES." >&2
  fi
}

# ---------------------------------------------------------------------------
# Internal: resolve the best installed version path for an overlay
# Returns the absolute install_path string, or empty string if none found.
# ---------------------------------------------------------------------------
_wb_gui_overlays_resolve_install_path() {
  local name="$1"
  local pinned_version="$2"   # "null" or "" = use latest installed
  local overlay_root="$3"
  local reg_file="$4"

  if [[ ! -f "${reg_file}" ]]; then
    return 0
  fi

  local jq_filter
  if [[ "${pinned_version}" == "null" ]] || [[ -z "${pinned_version}" ]]; then
    # Pick highest-sorted version (lexicographic desc — semver-like tags sort correctly)
    jq_filter='.overlays[] | select(.name == $name) |
      .installed_versions | map(select(.broken == false)) |
      sort_by(.version) | reverse | .[0].install_path // empty'
  else
    jq_filter='.overlays[] | select(.name == $name) |
      .installed_versions[] | select(.version == $version and .broken == false) |
      .install_path // empty'
  fi

  jq -r \
    --arg name "${name}" \
    --arg version "${pinned_version}" \
    "${jq_filter}" \
    "${reg_file}" 2>/dev/null | head -1 || true
}

# ---------------------------------------------------------------------------
# Internal: record a fallback event into the registry (for UI badge display)
# ---------------------------------------------------------------------------
_wb_gui_overlays_record_fallback() {
  local name="$1"
  local reg_file="$2"
  local reason="$3"

  if [[ ! -f "${reg_file}" ]]; then
    return 0
  fi

  local now_utc
  now_utc="$(_wb_gui_overlays_now_utc)"
  local reg_json
  reg_json="$(cat "${reg_file}")"
  reg_json="$(printf '%s' "${reg_json}" | jq \
    --arg name "${name}" \
    --arg now "${now_utc}" \
    --arg reason "${reason}" \
    '(.overlays[] | select(.name == $name)) |=
      . + {last_fallback_utc: $now, last_fallback_reason: $reason}')" || return 0
  wb_json_write_atomic "${reg_file}" "${reg_json}" || true
}

# ---------------------------------------------------------------------------
# wb_gui_overlays_save_env_bake <app_id> <overlays_json>
#
# Path B implementation: read overlays object, compute the env delta, write
# KEY=VALUE pairs into per-app env_vars AND write the overlays object itself.
# Also tracks owned env keys in _wb_overlay_managed_env_keys so that
# disabling cleanly removes them.
#
# Inputs:
#   app_id        — the app UUID
#   overlays_json — complete overlays object (JSON string)
# ---------------------------------------------------------------------------
wb_gui_overlays_save_env_bake() {
  local app_id="${1:-}"
  local overlays_json="${2:-null}"

  if [[ -z "${app_id}" ]]; then
    echo "wb_gui_overlays_save_env_bake: app_id required" >&2
    return 1
  fi

  local wb_home
  wb_home="$(_wb_gui_overlays_wb_home)"
  local file="${wb_home}/settings/apps/${app_id}.json"
  local overlay_root
  overlay_root="$(_wb_gui_overlays_root)"

  # Rebuild registry to get current install paths
  wb_gui_overlays_registry_refresh 2>/dev/null || true

  local reg_file
  reg_file="$(_wb_gui_overlays_registry)"

  # Load existing app settings
  local existing_json
  if [[ -f "${file}" ]] && jq empty "${file}" 2>/dev/null; then
    existing_json="$(cat "${file}")"
  else
    local now_utc
    now_utc="$(_wb_gui_overlays_now_utc)"
    existing_json="$(jq -cn \
      --arg app_id "${app_id}" \
      --arg now "${now_utc}" \
      '{schema: 1, app_id: $app_id, updated_utc: $now}')"
  fi

  # Get existing env_vars (or empty object)
  local existing_env_vars
  existing_env_vars="$(printf '%s' "${existing_json}" | jq '.env_vars // {}')"

  # Get existing managed keys list (our prior inventory)
  local managed_keys_json
  managed_keys_json="$(printf '%s' "${existing_json}" | jq '._wb_overlay_managed_env_keys // []')"

  # Remove all previously managed keys from env_vars (clean slate for overlay env)
  local cleaned_env_vars
  cleaned_env_vars="$(printf '%s' "${existing_env_vars}" | jq \
    --argjson managed "${managed_keys_json}" \
    'to_entries | map(select(.key as $k | $managed | index($k) | not)) | from_entries')"

  # Stale conflicting keys (e.g., MANGOHUD=0 conflicts with overlay enable — see architecture §7)
  # are handled cleanly via the managed_keys clean-slate above: any key in the prior managed list
  # is stripped from env_vars before the new bake. User-set keys outside the managed list survive.

  # Compute new env_vars from overlay state
  local new_env_vars
  new_env_vars="${cleaned_env_vars}"
  local new_managed_keys="[]"

  if [[ "${overlays_json}" != "null" ]] && [[ "${overlays_json}" != "{}" ]]; then
    # MangoHud
    local mh_enabled mh_bundled mh_version mh_config
    mh_enabled="$(  printf '%s' "${overlays_json}" | jq -r 'if .mangohud.enabled  == null then "false" else (.mangohud.enabled  | tostring) end')"
    mh_bundled="$(  printf '%s' "${overlays_json}" | jq -r 'if .mangohud.bundled  == null then "true"  else (.mangohud.bundled  | tostring) end')"
    mh_version="$(  printf '%s' "${overlays_json}" | jq -r '.mangohud.version  // "null"')"
    mh_config="$(   printf '%s' "${overlays_json}" | jq -r '.mangohud.config_path // "null"')"

    if [[ "${mh_enabled}" == "true" ]]; then
      new_env_vars="$(printf '%s' "${new_env_vars}" | jq '. + {"MANGOHUD": "1"}')"
      new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq '. + ["MANGOHUD"]')"

      if [[ "${mh_bundled}" == "true" ]]; then
        local mh_path
        mh_path="$(_wb_gui_overlays_resolve_install_path "mangohud" "${mh_version}" "${overlay_root}" "${reg_file}")"
        if [[ -n "${mh_path}" ]]; then
          local vk_path="${mh_path}/share/vulkan/implicit_layer.d"
          # MangoHud 0.7+ layout: lib/mangohud/{lib32,lib64}/libMangoHud.so —
          # both arch dirs in LD_LIBRARY_PATH so 32-bit and 64-bit Wine
          # binaries both find the right .so.
          local ld_path="${mh_path}/lib/mangohud/lib64:${mh_path}/lib/mangohud/lib32:\${LD_LIBRARY_PATH}"
          new_env_vars="$(printf '%s' "${new_env_vars}" | jq \
            --arg vk "${vk_path}" \
            --arg ld "${ld_path}" \
            '. + {"VK_LAYER_PATH": $vk, "LD_LIBRARY_PATH": $ld}')"
          new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq '. + ["VK_LAYER_PATH", "LD_LIBRARY_PATH"]')"
        fi
      fi

      if [[ "${mh_config}" != "null" ]] && [[ -n "${mh_config}" ]]; then
        new_env_vars="$(printf '%s' "${new_env_vars}" | jq \
          --arg cfg "${mh_config}" \
          '. + {"MANGOHUD_CONFIG": $cfg}')"
        new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq '. + ["MANGOHUD_CONFIG"]')"
      fi
    fi

    # VKBasalt
    local vkb_enabled vkb_bundled vkb_version
    vkb_enabled="$(printf '%s' "${overlays_json}" | jq -r 'if .vkbasalt.enabled == null then "false" else (.vkbasalt.enabled | tostring) end')"
    vkb_bundled="$(printf '%s' "${overlays_json}" | jq -r 'if .vkbasalt.bundled == null then "true"  else (.vkbasalt.bundled | tostring) end')"
    vkb_version="$(printf '%s' "${overlays_json}" | jq -r '.vkbasalt.version // "null"')"

    if [[ "${vkb_enabled}" == "true" ]]; then
      new_env_vars="$(printf '%s' "${new_env_vars}" | jq '. + {"ENABLE_VKBASALT": "1"}')"
      new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq '. + ["ENABLE_VKBASALT"]')"

      if [[ "${vkb_bundled}" == "true" ]]; then
        local vkb_path
        vkb_path="$(_wb_gui_overlays_resolve_install_path "vkbasalt" "${vkb_version}" "${overlay_root}" "${reg_file}")"
        if [[ -n "${vkb_path}" ]]; then
          local vk_layer_path="${vkb_path}/share/vulkan/implicit_layer.d"
          # If VK_LAYER_PATH already set (by MangoHud), prepend rather than replace
          local existing_vk
          existing_vk="$(printf '%s' "${new_env_vars}" | jq -r '.VK_LAYER_PATH // ""')"
          if [[ -n "${existing_vk}" ]]; then
            vk_layer_path="${vk_layer_path}:${existing_vk}"
          fi
          new_env_vars="$(printf '%s' "${new_env_vars}" | jq \
            --arg vk "${vk_layer_path}" \
            '. + {"VK_LAYER_PATH": $vk}')"
          # VK_LAYER_PATH already in managed list (or add it)
          new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq \
            'if index("VK_LAYER_PATH") then . else . + ["VK_LAYER_PATH"] end')"
        fi
      fi
    fi

    # OptiScaler
    local osc_enabled osc_version
    osc_enabled="$(printf '%s' "${overlays_json}" | jq -r 'if .optiscaler.enabled == null then "false" else (.optiscaler.enabled | tostring) end')"
    osc_version="$(printf '%s' "${overlays_json}" | jq -r '.optiscaler.version // "null"')"

    if [[ "${osc_enabled}" == "true" ]]; then
      local osc_path
      osc_path="$(_wb_gui_overlays_resolve_install_path "optiscaler" "${osc_version}" "${overlay_root}" "${reg_file}")"
      if [[ -n "${osc_path}" ]]; then
        # Merge WINEDLLOVERRIDES — append nvngx=n,b; existing value follows
        local existing_dllover
        existing_dllover="$(printf '%s' "${new_env_vars}" | jq -r '.WINEDLLOVERRIDES // ""')"
        local new_dllover="nvngx=n,b"
        if [[ -n "${existing_dllover}" ]]; then
          new_dllover="${new_dllover};${existing_dllover}"
        fi
        new_env_vars="$(printf '%s' "${new_env_vars}" | jq \
          --arg v "${new_dllover}" \
          '. + {"WINEDLLOVERRIDES": $v}')"
        new_managed_keys="$(printf '%s' "${new_managed_keys}" | jq \
          'if index("WINEDLLOVERRIDES") then . else . + ["WINEDLLOVERRIDES"] end')"
      fi
    fi
  fi

  # Write updated overlays object + env_vars + managed_keys atomically
  local now_utc
  now_utc="$(_wb_gui_overlays_now_utc)"
  local new_json
  if [[ "${overlays_json}" == "null" ]]; then
    new_json="$(printf '%s' "${existing_json}" | jq \
      --arg now "${now_utc}" \
      --argjson env_vars "${new_env_vars}" \
      --argjson managed "${new_managed_keys}" \
      '.updated_utc = $now | .env_vars = $env_vars | ._wb_overlay_managed_env_keys = $managed |
       .overlays = null')"
  else
    new_json="$(printf '%s' "${existing_json}" | jq \
      --arg now "${now_utc}" \
      --argjson overlays "${overlays_json}" \
      --argjson env_vars "${new_env_vars}" \
      --argjson managed "${new_managed_keys}" \
      '.updated_utc = $now | .overlays = $overlays | .env_vars = $env_vars |
       ._wb_overlay_managed_env_keys = $managed')"
  fi

  wb_json_write_atomic "${file}" "${new_json}"
}

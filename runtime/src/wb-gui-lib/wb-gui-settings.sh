#!/usr/bin/env bash
# wb-gui-settings.sh — 4-layer settings storage + override resolver for wb-gui
# Sourced by wb-gui; never executed directly.
#
# Storage layout (under $WB_HOME/settings/):
#   general.json                 — cross-cutting defaults
#   dists/<dist-id>.json         — per-dist settings
#   prefixes/<prefix-id>.json    — per-prefix settings
#   apps/<app-id>.json           — per-app settings
#
# Override resolver (cross-cutting keys): app → prefix → dist → general → built-in default
# null or absent key = "inherit from parent layer"
#
# Depends on wb_json_write_atomic (wb-lib/wb-json.sh) sourced by caller.
set -euo pipefail

# ---------------------------------------------------------------------------
# Phase A minimum knob set — cross-cutting keys (participate in resolver chain)
# ---------------------------------------------------------------------------
_WB_GUI_SETTINGS_CROSS_CUTTING_KEYS=(gpu win_version wine_debug)

# ---------------------------------------------------------------------------
# Per-layer whitelists — keys accepted at each layer
# Layer-exclusive keys may ONLY be written to the listed layer.
# Cross-cutting keys may appear in multiple layers.
# ---------------------------------------------------------------------------

# General layer: only cross-cutting keys (no layer-exclusive keys in Phase A)
_WB_GUI_SETTINGS_LAYER_KEYS_GENERAL=(gpu win_version wine_debug)

# Dist layer: exclusive keys + cross-cutting (gpu only — win_version/wine_debug NOT on dist)
_WB_GUI_SETTINGS_LAYER_KEYS_DIST=(external_source name active last_built_at gpu)

# Prefix layer: exclusive keys + cross-cutting
_WB_GUI_SETTINGS_LAYER_KEYS_PREFIX=(notes gpu win_version wine_debug)

# App layer: exclusive keys + cross-cutting
# overlays: Phase C per-app overlay object (MangoHud / VKBasalt / OptiScaler)
# _wb_overlay_managed_env_keys: Phase C internal — tracks which env_vars keys
#   were baked by the overlay save handler so they can be cleanly removed on disable.
_WB_GUI_SETTINGS_LAYER_KEYS_APP=(wine_args env_vars gpu win_version wine_debug overlays _wb_overlay_managed_env_keys)

# ---------------------------------------------------------------------------
# Built-in defaults — final fallback when no layer sets a cross-cutting key
# ---------------------------------------------------------------------------
_WB_GUI_SETTINGS_BUILTIN_GPU="auto"
_WB_GUI_SETTINGS_BUILTIN_WIN_VERSION="win10"
_WB_GUI_SETTINGS_BUILTIN_WINE_DEBUG=""

# ---------------------------------------------------------------------------
# _wb_gui_settings_builtin_default <key>
# Returns the hard-coded built-in default for a cross-cutting key.
# ---------------------------------------------------------------------------
_wb_gui_settings_builtin_default() {
    local key="$1"
    case "${key}" in
        gpu)         printf '%s' "${_WB_GUI_SETTINGS_BUILTIN_GPU}";;
        win_version) printf '%s' "${_WB_GUI_SETTINGS_BUILTIN_WIN_VERSION}";;
        wine_debug)  printf '%s' "${_WB_GUI_SETTINGS_BUILTIN_WINE_DEBUG}";;
        *)           return 0;;  # unknown key — return empty string
    esac
}

# ---------------------------------------------------------------------------
# _wb_gui_settings_validate_key <layer> <key>
# Returns 0 if <key> is permitted at <layer>, non-zero otherwise.
# Logs to stderr on rejection.
# ---------------------------------------------------------------------------
_wb_gui_settings_validate_key() {
    local layer="$1"
    local key="$2"
    local allowed
    case "${layer}" in
        general) allowed=("${_WB_GUI_SETTINGS_LAYER_KEYS_GENERAL[@]}");;
        dist)    allowed=("${_WB_GUI_SETTINGS_LAYER_KEYS_DIST[@]}");;
        prefix)  allowed=("${_WB_GUI_SETTINGS_LAYER_KEYS_PREFIX[@]}");;
        app)     allowed=("${_WB_GUI_SETTINGS_LAYER_KEYS_APP[@]}");;
        *)
            echo "wb-gui-settings: unknown layer '${layer}'" >&2
            return 1
            ;;
    esac
    local k
    for k in "${allowed[@]}"; do
        if [[ "${k}" == "${key}" ]]; then
            return 0
        fi
    done
    echo "wb-gui-settings: key '${key}' is not permitted on layer '${layer}'" >&2
    return 1
}

# ---------------------------------------------------------------------------
# wb_gui_settings_home
# Resolves $WB_HOME/settings/ and creates the full dir tree on first use.
# ---------------------------------------------------------------------------
wb_gui_settings_home() {
    local wb_home="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
    local settings_dir="${wb_home}/settings"
    mkdir -p \
        "${settings_dir}" \
        "${settings_dir}/dists" \
        "${settings_dir}/prefixes" \
        "${settings_dir}/apps"
    printf '%s' "${settings_dir}"
}

# ---------------------------------------------------------------------------
# _wb_gui_settings_layer_path <layer> <id>
# Returns the absolute path to the JSON file for the given layer + id.
# For the general layer, <id> is ignored (pass "" or anything).
# ---------------------------------------------------------------------------
_wb_gui_settings_layer_path() {
    local layer="$1"
    local id="$2"
    local wb_home="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
    local settings_dir="${wb_home}/settings"
    case "${layer}" in
        general) printf '%s/general.json' "${settings_dir}";;
        dist)    printf '%s/dists/%s.json' "${settings_dir}" "${id}";;
        prefix)  printf '%s/prefixes/%s.json' "${settings_dir}" "${id}";;
        app)     printf '%s/apps/%s.json' "${settings_dir}" "${id}";;
        *)
            echo "wb-gui-settings: _wb_gui_settings_layer_path: unknown layer '${layer}'" >&2
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# _wb_gui_settings_empty_skeleton <layer> <id>
# Emits a minimal valid JSON object for the layer (schema field + id field).
# Used as a base when the file does not exist yet.
# ---------------------------------------------------------------------------
_wb_gui_settings_empty_skeleton() {
    local layer="$1"
    local id="$2"
    local now_utc
    now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"
    case "${layer}" in
        general) printf '{"schema":1,"updated_utc":"%s"}' "${now_utc}";;
        dist)    printf '{"schema":1,"dist_id":"%s","updated_utc":"%s"}' "${id}" "${now_utc}";;
        prefix)  printf '{"schema":1,"prefix_id":"%s","updated_utc":"%s"}' "${id}" "${now_utc}";;
        app)     printf '{"schema":1,"app_id":"%s","updated_utc":"%s"}' "${id}" "${now_utc}";;
        *)
            echo "wb-gui-settings: _wb_gui_settings_empty_skeleton: unknown layer '${layer}'" >&2
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# _wb_gui_settings_load_file <file> <layer>
# Loads and validates a settings JSON file.
# Emits JSON on stdout. Returns empty string on missing file.
# Returns non-zero on malformed JSON or wrong schema version.
# ---------------------------------------------------------------------------
_wb_gui_settings_load_file() {
    local file="$1"
    local layer="$2"
    if [[ ! -f "${file}" ]]; then
        return 0  # missing file is normal (first run)
    fi
    if ! jq empty "${file}" 2>/dev/null; then
        echo "wb-gui-settings: ${file} is malformed — skipping" >&2
        return 1
    fi
    local schema_ver
    schema_ver="$(jq -r '.schema // empty' "${file}")"
    if [[ "${schema_ver}" != "1" ]]; then
        echo "wb-gui-settings: ${file} has unsupported schema '${schema_ver}' (expected 1) — skipping" >&2
        return 1
    fi
    cat "${file}"
}

# ---------------------------------------------------------------------------
# _wb_gui_settings_read_key <file> <key>
# Reads a single key from a settings file.
# Outputs the raw string value, or empty if the file is absent/key is absent/null.
# ---------------------------------------------------------------------------
_wb_gui_settings_read_key() {
    local file="$1"
    local key="$2"
    if [[ ! -f "${file}" ]]; then
        return 0
    fi
    if ! jq empty "${file}" 2>/dev/null; then
        echo "wb-gui-settings: ${file} is malformed — skipping" >&2
        return 0
    fi
    # jq outputs "null" for absent or null keys; we treat both as empty
    local val
    val="$(jq -r --arg k "${key}" 'if has($k) then .[$k] else null end' "${file}" 2>/dev/null || true)"
    if [[ "${val}" == "null" ]] || [[ -z "${val}" ]]; then
        return 0
    fi
    printf '%s' "${val}"
}

# ---------------------------------------------------------------------------
# _wb_gui_settings_set_key <layer> <id> <key> <value>
# Internal implementation for all set_* helpers.
# Validates the key, loads/creates the file, updates it, writes atomically.
# ---------------------------------------------------------------------------
_wb_gui_settings_set_key() {
    local layer="$1"
    local id="$2"
    local key="$3"
    local value="$4"

    # Validate the key is permitted on this layer
    if ! _wb_gui_settings_validate_key "${layer}" "${key}"; then
        return 1
    fi

    local file
    file="$(_wb_gui_settings_layer_path "${layer}" "${id}")"

    # Ensure parent dirs exist
    wb_gui_settings_home > /dev/null

    # Load existing JSON or start with a fresh skeleton
    local existing_json
    if [[ -f "${file}" ]] && jq empty "${file}" 2>/dev/null; then
        existing_json="$(cat "${file}")"
    else
        existing_json="$(_wb_gui_settings_empty_skeleton "${layer}" "${id}")"
    fi

    local now_utc
    now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")"

    # Determine jq write expression: arrays and objects are handled specially
    # For wine_args (array) and env_vars (object), value is written as raw JSON.
    # All other keys are written as plain strings.
    local new_json
    case "${key}" in
        wine_args)
            # Expect value to be a JSON array string (caller must supply valid JSON)
            new_json="$(printf '%s' "${existing_json}" | jq \
                --arg now "${now_utc}" \
                --argjson v "${value}" \
                '.updated_utc = $now | .wine_args = $v')"
            ;;
        env_vars)
            # Expect value to be a JSON object string
            new_json="$(printf '%s' "${existing_json}" | jq \
                --arg now "${now_utc}" \
                --argjson v "${value}" \
                '.updated_utc = $now | .env_vars = $v')"
            ;;
        overlays)
            # Expect value to be a JSON object or null (Phase C per-app overlay state)
            new_json="$(printf '%s' "${existing_json}" | jq \
                --arg now "${now_utc}" \
                --argjson v "${value}" \
                '.updated_utc = $now | .overlays = $v')"
            ;;
        _wb_overlay_managed_env_keys)
            # Expect value to be a JSON array of string key names
            new_json="$(printf '%s' "${existing_json}" | jq \
                --arg now "${now_utc}" \
                --argjson v "${value}" \
                '.updated_utc = $now | ._wb_overlay_managed_env_keys = $v')"
            ;;
        active)
            # boolean
            local bool_val
            if [[ "${value}" == "true" ]]; then
                bool_val="true"
            else
                bool_val="false"
            fi
            new_json="$(printf '%s' "${existing_json}" | jq \
                --arg now "${now_utc}" \
                --argjson v "${bool_val}" \
                '.updated_utc = $now | .active = $v')"
            ;;
        *)
            # Plain string
            new_json="$(printf '%s' "${existing_json}" | jq \
                --arg now "${now_utc}" \
                --arg k "${key}" \
                --arg v "${value}" \
                '.updated_utc = $now | .[$k] = $v')"
            ;;
    esac

    wb_json_write_atomic "${file}" "${new_json}"
}

# ---------------------------------------------------------------------------
# General layer — get / set
# ---------------------------------------------------------------------------

# wb_gui_settings_get_general <key> → value (or empty if absent/null)
wb_gui_settings_get_general() {
    local key="${1:-}"
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_get_general: key required" >&2
        return 1
    fi
    local file
    file="$(_wb_gui_settings_layer_path "general" "")"
    _wb_gui_settings_read_key "${file}" "${key}"
}

# wb_gui_settings_set_general <key> <value>
wb_gui_settings_set_general() {
    local key="${1:-}"
    local value="${2:-}"
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_set_general: key required" >&2
        return 1
    fi
    _wb_gui_settings_set_key "general" "" "${key}" "${value}"
}

# ---------------------------------------------------------------------------
# Dist layer — get / set
# ---------------------------------------------------------------------------

# wb_gui_settings_get_dist <dist_id> <key> → value (or empty)
wb_gui_settings_get_dist() {
    local dist_id="${1:-}"
    local key="${2:-}"
    if [[ -z "${dist_id}" ]]; then
        echo "wb_gui_settings_get_dist: dist_id required" >&2
        return 1
    fi
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_get_dist: key required" >&2
        return 1
    fi
    local file
    file="$(_wb_gui_settings_layer_path "dist" "${dist_id}")"
    _wb_gui_settings_read_key "${file}" "${key}"
}

# wb_gui_settings_set_dist <dist_id> <key> <value>
wb_gui_settings_set_dist() {
    local dist_id="${1:-}"
    local key="${2:-}"
    local value="${3:-}"
    if [[ -z "${dist_id}" ]]; then
        echo "wb_gui_settings_set_dist: dist_id required" >&2
        return 1
    fi
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_set_dist: key required" >&2
        return 1
    fi
    _wb_gui_settings_set_key "dist" "${dist_id}" "${key}" "${value}"
}

# ---------------------------------------------------------------------------
# Prefix layer — get / set
# ---------------------------------------------------------------------------

# wb_gui_settings_get_prefix <prefix_id> <key> → value (or empty)
wb_gui_settings_get_prefix() {
    local prefix_id="${1:-}"
    local key="${2:-}"
    if [[ -z "${prefix_id}" ]]; then
        echo "wb_gui_settings_get_prefix: prefix_id required" >&2
        return 1
    fi
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_get_prefix: key required" >&2
        return 1
    fi
    local file
    file="$(_wb_gui_settings_layer_path "prefix" "${prefix_id}")"
    _wb_gui_settings_read_key "${file}" "${key}"
}

# wb_gui_settings_set_prefix <prefix_id> <key> <value>
wb_gui_settings_set_prefix() {
    local prefix_id="${1:-}"
    local key="${2:-}"
    local value="${3:-}"
    if [[ -z "${prefix_id}" ]]; then
        echo "wb_gui_settings_set_prefix: prefix_id required" >&2
        return 1
    fi
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_set_prefix: key required" >&2
        return 1
    fi
    _wb_gui_settings_set_key "prefix" "${prefix_id}" "${key}" "${value}"
}

# ---------------------------------------------------------------------------
# App layer — get / set
# ---------------------------------------------------------------------------

# wb_gui_settings_get_app <app_id> <key> → value (or empty)
wb_gui_settings_get_app() {
    local app_id="${1:-}"
    local key="${2:-}"
    if [[ -z "${app_id}" ]]; then
        echo "wb_gui_settings_get_app: app_id required" >&2
        return 1
    fi
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_get_app: key required" >&2
        return 1
    fi
    local file
    file="$(_wb_gui_settings_layer_path "app" "${app_id}")"
    _wb_gui_settings_read_key "${file}" "${key}"
}

# wb_gui_settings_set_app <app_id> <key> <value>
wb_gui_settings_set_app() {
    local app_id="${1:-}"
    local key="${2:-}"
    local value="${3:-}"
    if [[ -z "${app_id}" ]]; then
        echo "wb_gui_settings_set_app: app_id required" >&2
        return 1
    fi
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_set_app: key required" >&2
        return 1
    fi
    _wb_gui_settings_set_key "app" "${app_id}" "${key}" "${value}"
}

# ---------------------------------------------------------------------------
# Clear helpers — remove a layer file
# ---------------------------------------------------------------------------

# wb_gui_settings_clear_app <app_id>
# Removes the per-app settings file. Called from wb_gui_apps_remove.
wb_gui_settings_clear_app() {
    local app_id="${1:-}"
    if [[ -z "${app_id}" ]]; then
        echo "wb_gui_settings_clear_app: app_id required" >&2
        return 1
    fi
    local file
    file="$(_wb_gui_settings_layer_path "app" "${app_id}")"
    if [[ -f "${file}" ]]; then
        rm -f "${file}"
    fi
}

# wb_gui_settings_clear_prefix <prefix_id>
# Removes the per-prefix settings file.
wb_gui_settings_clear_prefix() {
    local prefix_id="${1:-}"
    if [[ -z "${prefix_id}" ]]; then
        echo "wb_gui_settings_clear_prefix: prefix_id required" >&2
        return 1
    fi
    local file
    file="$(_wb_gui_settings_layer_path "prefix" "${prefix_id}")"
    if [[ -f "${file}" ]]; then
        rm -f "${file}"
    fi
}

# ---------------------------------------------------------------------------
# Override resolver
#
# Algorithm:
#   Walk layers most-specific → least: app → prefix → dist → general
#   Skip dist layer if app has no dist association (apps.json app.dist == null).
#   Return first layer that has a concrete (non-null, non-absent) value.
#   Fall back to built-in default.
#
# _wb_gui_settings_resolve_raw_value <layer_path> <key>
# Returns the raw value from the file, or empty string if absent/null.
# Never fails (file missing is OK).
# ---------------------------------------------------------------------------
_wb_gui_settings_resolve_raw_value() {
    local file="$1"
    local key="$2"
    if [[ ! -f "${file}" ]]; then
        return 0
    fi
    if ! jq empty "${file}" 2>/dev/null; then
        echo "wb-gui-settings: ${file} is malformed — skipping in resolver" >&2
        return 0
    fi
    local val
    val="$(jq -r --arg k "${key}" 'if has($k) then .[$k] else null end' "${file}" 2>/dev/null || true)"
    if [[ "${val}" == "null" ]]; then
        return 0
    fi
    printf '%s' "${val}"
}

# wb_gui_settings_resolve <key> <app_id>
# Cross-layer resolver. Outputs the resolved value as a plain string.
# Returns built-in default for unknown keys or missing app.
# Does NOT consult apps.json in Phase A (app is assumed distless; dist layer always checked).
#
# Note: Phase A does not read apps.json to find app.dist — the dist layer is simply
# always consulted (if the dist file doesn't exist it's skipped naturally). This is
# consistent with the spec's "skip if dist is null" being enforced by the dist file
# being absent for apps with no dist association.
wb_gui_settings_resolve() {
    local key="${1:-}"
    local app_id="${2:-}"
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_resolve: key required" >&2
        return 1
    fi

    # Only cross-cutting keys participate in the resolver chain
    local is_cross_cutting=0
    local cc_key
    for cc_key in "${_WB_GUI_SETTINGS_CROSS_CUTTING_KEYS[@]}"; do
        if [[ "${cc_key}" == "${key}" ]]; then
            is_cross_cutting=1
            break
        fi
    done
    if [[ "${is_cross_cutting}" -eq 0 ]]; then
        # Non-cross-cutting key: return built-in default (empty)
        _wb_gui_settings_builtin_default "${key}"
        return 0
    fi

    local wb_home="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
    local settings_dir="${wb_home}/settings"

    # Layer 1: app
    if [[ -n "${app_id}" ]]; then
        local app_file="${settings_dir}/apps/${app_id}.json"
        local app_val
        app_val="$(_wb_gui_settings_resolve_raw_value "${app_file}" "${key}")"
        if [[ -n "${app_val}" ]]; then
            printf '%s' "${app_val}"
            return 0
        fi
    fi

    # Layer 2: prefix — derive prefix from app file if available
    # In Phase A: read prefix_id from app file's context is not stored there.
    # The resolver walks layers by file presence; prefix_id must be supplied
    # externally by the caller or we skip this layer.
    # Since the resolver API is resolve(key, app_id) and we do not have a
    # separate prefix_id argument, in Phase A we rely on the settings files
    # being discoverable. The prefix layer is consulted only when a
    # wb_gui_settings_resolve_for_prefix helper is used. However, per the spec
    # the resolver needs app_id only and should derive prefix from apps.json.
    #
    # Implementation: try to derive prefix from apps.json if it exists.
    local prefix_id=""
    local dist_id=""
    local apps_json="${wb_home}/apps.json"
    if [[ -f "${apps_json}" ]] && jq empty "${apps_json}" 2>/dev/null; then
        prefix_id="$(jq -r --arg id "${app_id}" \
            '.apps[] | select(.id == $id) | .prefix // empty' \
            "${apps_json}" 2>/dev/null || true)"
        dist_id="$(jq -r --arg id "${app_id}" \
            '.apps[] | select(.id == $id) | .dist // empty' \
            "${apps_json}" 2>/dev/null || true)"
    fi

    # Layer 2: prefix
    if [[ -n "${prefix_id}" ]]; then
        local prefix_file="${settings_dir}/prefixes/${prefix_id}.json"
        local prefix_val
        prefix_val="$(_wb_gui_settings_resolve_raw_value "${prefix_file}" "${key}")"
        if [[ -n "${prefix_val}" ]]; then
            printf '%s' "${prefix_val}"
            return 0
        fi
    fi

    # Layer 3: dist (only if dist_id known; check gpu only per spec)
    # dist layer only carries 'gpu' as cross-cutting; win_version and wine_debug
    # are NOT consulted on the dist layer.
    if [[ -n "${dist_id}" ]] && [[ "${key}" == "gpu" ]]; then
        local dist_file="${settings_dir}/dists/${dist_id}.json"
        local dist_val
        dist_val="$(_wb_gui_settings_resolve_raw_value "${dist_file}" "${key}")"
        if [[ -n "${dist_val}" ]]; then
            printf '%s' "${dist_val}"
            return 0
        fi
    fi

    # Layer 4: general
    local general_file="${settings_dir}/general.json"
    local general_val
    general_val="$(_wb_gui_settings_resolve_raw_value "${general_file}" "${key}")"
    if [[ -n "${general_val}" ]]; then
        printf '%s' "${general_val}"
        return 0
    fi

    # Fallback: built-in default
    _wb_gui_settings_builtin_default "${key}"
}

# ---------------------------------------------------------------------------
# wb_gui_settings_resolve_trace <key> <app_id>
# Same walk as wb_gui_settings_resolve, but returns a JSON object showing:
#   - key
#   - resolved_value
#   - resolved_from  (layer name: "app"|"prefix"|"dist"|"general"|"builtin")
#   - candidates     (map of layer → raw value or null)
#
# Output format (for W5 to parse):
#   {"key":"gpu","resolved_value":"nvidia","resolved_from":"prefix",
#    "candidates":{"app":null,"prefix":"nvidia","dist":null,"general":"auto"}}
# ---------------------------------------------------------------------------
wb_gui_settings_resolve_trace() {
    local key="${1:-}"
    local app_id="${2:-}"
    if [[ -z "${key}" ]]; then
        echo "wb_gui_settings_resolve_trace: key required" >&2
        return 1
    fi

    local wb_home="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
    local settings_dir="${wb_home}/settings"

    # Collect candidate values at each layer
    local app_val="" prefix_val="" dist_val="" general_val=""

    # App layer
    if [[ -n "${app_id}" ]]; then
        local app_file="${settings_dir}/apps/${app_id}.json"
        app_val="$(_wb_gui_settings_resolve_raw_value "${app_file}" "${key}" 2>/dev/null || true)"
    fi

    # Derive prefix and dist from apps.json
    local prefix_id="" dist_id=""
    local apps_json="${wb_home}/apps.json"
    if [[ -f "${apps_json}" ]] && jq empty "${apps_json}" 2>/dev/null; then
        prefix_id="$(jq -r --arg id "${app_id}" \
            '.apps[] | select(.id == $id) | .prefix // empty' \
            "${apps_json}" 2>/dev/null || true)"
        dist_id="$(jq -r --arg id "${app_id}" \
            '.apps[] | select(.id == $id) | .dist // empty' \
            "${apps_json}" 2>/dev/null || true)"
    fi

    # Prefix layer
    if [[ -n "${prefix_id}" ]]; then
        local prefix_file="${settings_dir}/prefixes/${prefix_id}.json"
        prefix_val="$(_wb_gui_settings_resolve_raw_value "${prefix_file}" "${key}" 2>/dev/null || true)"
    fi

    # Dist layer (gpu only)
    if [[ -n "${dist_id}" ]] && [[ "${key}" == "gpu" ]]; then
        local dist_file="${settings_dir}/dists/${dist_id}.json"
        dist_val="$(_wb_gui_settings_resolve_raw_value "${dist_file}" "${key}" 2>/dev/null || true)"
    fi

    # General layer
    local general_file="${settings_dir}/general.json"
    general_val="$(_wb_gui_settings_resolve_raw_value "${general_file}" "${key}" 2>/dev/null || true)"

    # Determine resolved_value and resolved_from
    local resolved_value="" resolved_from="builtin"
    if [[ -n "${app_val}" ]]; then
        resolved_value="${app_val}"
        resolved_from="app"
    elif [[ -n "${prefix_val}" ]]; then
        resolved_value="${prefix_val}"
        resolved_from="prefix"
    elif [[ -n "${dist_val}" ]]; then
        resolved_value="${dist_val}"
        resolved_from="dist"
    elif [[ -n "${general_val}" ]]; then
        resolved_value="${general_val}"
        resolved_from="general"
    else
        resolved_value="$(_wb_gui_settings_builtin_default "${key}")"
        resolved_from="builtin"
    fi

    # Build candidates JSON: null for absent/empty, quoted string for present
    local _jq_null="null"
    local app_jv prefix_jv dist_jv general_jv
    if [[ -n "${app_val}" ]]; then
        app_jv="$(printf '"%s"' "${app_val}")"
    else
        app_jv="${_jq_null}"
    fi
    if [[ -n "${prefix_val}" ]]; then
        prefix_jv="$(printf '"%s"' "${prefix_val}")"
    else
        prefix_jv="${_jq_null}"
    fi
    if [[ -n "${dist_val}" ]]; then
        dist_jv="$(printf '"%s"' "${dist_val}")"
    else
        dist_jv="${_jq_null}"
    fi
    if [[ -n "${general_val}" ]]; then
        general_jv="$(printf '"%s"' "${general_val}")"
    else
        general_jv="${_jq_null}"
    fi

    # Emit JSON via jq for correct escaping
    jq -n \
        --arg key "${key}" \
        --arg resolved_value "${resolved_value}" \
        --arg resolved_from "${resolved_from}" \
        --argjson app_jv "${app_jv}" \
        --argjson prefix_jv "${prefix_jv}" \
        --argjson dist_jv "${dist_jv}" \
        --argjson general_jv "${general_jv}" \
        '{
            key: $key,
            resolved_value: $resolved_value,
            resolved_from: $resolved_from,
            candidates: {
                app: $app_jv,
                prefix: $prefix_jv,
                dist: $dist_jv,
                general: $general_jv
            }
        }'
}

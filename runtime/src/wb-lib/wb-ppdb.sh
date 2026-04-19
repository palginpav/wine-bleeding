#!/usr/bin/env bash
set -euo pipefail

# wb-ppdb.sh — M4 per-prefix/per-game profile database reader and legacy importer.
#
# Public API:
#   wb_ppdb_read <path>                                   — read strict-JSON .wb.ppdb
#   wb_ppdb_import_legacy <input_bash_ppdb> <output_json> — convert legacy bash ppdb
#
# Exit codes for wb_ppdb_read:
#   0 — success
#   1 — file missing / not readable
#   2 — malformed JSON
#   3 — JSON schema violation (only when check-jsonschema is on PATH)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _wb_ppdb_schema_path: resolve the JSON schema file relative to this script.
_wb_ppdb_schema_path() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Navigate from src/wb-lib/ up to share/schemas/
  echo "${script_dir}/../../share/schemas/wb_ppdb.schema.json"
}

# ---------------------------------------------------------------------------
# wb_ppdb_read <path>
#
# Reads a strict-JSON .wb.ppdb file and emits one KEY=VALUE line per env entry,
# sorted ascending by key.  Output feeds into the wb-config.sh layer 4 pipeline.
#
# pre_exec / post_exec arrays are intentionally ignored here — wb-hooks.sh (M5)
# will consume them.
# ---------------------------------------------------------------------------
wb_ppdb_read() {
  local ppdb_path="${1:-}"

  if [[ -z "${ppdb_path}" || ! -f "${ppdb_path}" ]]; then
    wb_log_error "wb_ppdb_read: file not found: '${ppdb_path}'"
    return 1
  fi
  if [[ ! -r "${ppdb_path}" ]]; then
    wb_log_error "wb_ppdb_read: file not readable: '${ppdb_path}'"
    return 1
  fi

  # Validate JSON syntax
  if ! jq empty "${ppdb_path}" 2>/dev/null; then
    wb_log_error "wb_ppdb_read: malformed JSON in '${ppdb_path}'"
    return 2
  fi

  # Optional schema validation (skip gracefully when tool is absent)
  if command -v check-jsonschema >/dev/null 2>&1; then
    local schema_path
    schema_path="$(_wb_ppdb_schema_path)"
    if [[ -f "${schema_path}" ]]; then
      if ! check-jsonschema --schemafile "${schema_path}" "${ppdb_path}" >/dev/null 2>&1; then
        wb_log_error "wb_ppdb_read: schema violation in '${ppdb_path}'"
        return 3
      fi
    fi
  fi

  # Emit sorted KEY=VALUE lines from .env object.
  # jq handles all special characters in values (quotes, backslashes, newlines)
  # by constructing the output string itself.  Each line is KEY=VALUE with the
  # value exactly as stored in JSON — no extra quoting or escaping.
  #
  # pre_exec / post_exec arrays are ignored here — M5 / wb-hooks.sh will handle them.
  jq -r '
    (.env // {}) | to_entries | sort_by(.key) | .[] |
    .key + "=" + .value
  ' "${ppdb_path}"
}

# ---------------------------------------------------------------------------
# wb_ppdb_import_legacy <input_bash_ppdb_path> <output_json_path>
#
# Convert a legacy PortProton-style bash-sourced .ppdb file to strict JSON.
#
# SECURITY-CRITICAL (M4-R2): The input file is arbitrary bash chosen by the user
# for a one-time explicit conversion.  It is executed ONLY here, inside a tight
# sandbox that prevents dangerous side effects.
#
# Sandbox construction:
#   1. A tmpdir is created (sandbox_dir) with a bin/ subdirectory.
#   2. Only whitelisted binaries are symlinked into bin/:
#        echo, true, false, grep
#      Absent: rm, cp, mv, cat, curl, wget, python*, sh (bash is invoked
#      by absolute path below — not via PATH), ssh, nc, etc.
#   3. The input file is copied into sandbox bin/ as "input.ppdb" (no /).
#   4. A wrapper script "run.sh" (no /) is written inside sandbox bin/;
#      it sources "input.ppdb" and emits declare -p output.
#   5. The child bash is launched via:
#
#        ( cd "${sandbox_bin}" && exec env -i ... /bin/bash --restricted
#                                                  --noprofile --norc run.sh )
#
#      --restricted prevents:
#        • cd inside the script (cannot escape the sandbox directory)
#        • Output redirects (> /tmp/foo) — this blocks the 'cat > /tmp/stolen' attack
#        • Executing commands whose name contains '/' (blocks /bin/rm, /usr/bin/curl, etc.)
#        • Reassigning PATH within the script
#      env -i strips the entire parent environment.
#      PATH="${sandbox_bin}" means only whitelisted binaries are reachable by name.
#
# Even if the child bash exits non-zero (because malicious commands fail),
# we capture whatever variables were set before the error and produce best-effort output.
# The sandbox prevents all file writes outside the sandbox tmpdir.
# ---------------------------------------------------------------------------
wb_ppdb_import_legacy() {
  local input_path="${1:-}"
  local output_path="${2:-}"

  if [[ -z "${input_path}" || ! -f "${input_path}" ]]; then
    wb_log_error "wb_ppdb_import_legacy: input file not found: '${input_path}'"
    return 1
  fi
  if [[ -z "${output_path}" ]]; then
    wb_log_error "wb_ppdb_import_legacy: output path required"
    return 1
  fi

  # ------------------------------------------------------------------
  # 1. Build sandbox directory with whitelisted binaries only.
  # ------------------------------------------------------------------
  local sandbox_dir sandbox_bin
  sandbox_dir="$(mktemp -d)"
  sandbox_bin="${sandbox_dir}/bin"
  mkdir -p "${sandbox_bin}"

  local cmd cmd_path
  for cmd in echo true false grep; do
    cmd_path="$(command -v "${cmd}" 2>/dev/null || true)"
    if [[ -n "${cmd_path}" && -x "${cmd_path}" ]]; then
      ln -sf "${cmd_path}" "${sandbox_bin}/${cmd}"
    fi
  done

  # ------------------------------------------------------------------
  # 2. Copy input file into sandbox (gives it a slash-free name so
  #    bash --restricted can source it).
  # ------------------------------------------------------------------
  cp "${input_path}" "${sandbox_bin}/input.ppdb"

  # ------------------------------------------------------------------
  # 3. Write wrapper script (also slash-free; --restricted allows
  #    running scripts by relative name when cwd is sandbox_bin).
  #
  #    We use 'declare -p' (not 'declare -px') because legacy .ppdb files
  #    typically assign without 'export', e.g. PW_WINE_USE=PROTON_LG.
  #    'declare -px' would miss such non-exported variables.
  # ------------------------------------------------------------------
  # NOTE: The wrapper must NOT contain any output redirects (>/dev/null etc.)
  # because bash --restricted blocks ALL output redirects inside the script.
  # Stderr from sourcing the ppdb is silenced at the outer ( cd && exec ... ) level.
  cat > "${sandbox_bin}/run.sh" << 'END_WRAPPER'
source input.ppdb || true
declare -p | grep -E "^declare (--|--r|-x) (PW_|WINE|DXVK_|VKD3D_|DLL_)" || true
END_WRAPPER

  # ------------------------------------------------------------------
  # 4. Invoke child bash in sandbox.
  #    - ( cd && exec ) sets the working directory before bash starts so
  #      'source input.ppdb' (no slash) resolves in the sandbox.
  #    - --restricted enforces the constraints described above.
  # ------------------------------------------------------------------
  local raw_env
  raw_env="$(
    (
      cd "${sandbox_bin}"
      exec env -i \
        HOME="${sandbox_bin}" \
        PATH="${sandbox_bin}" \
        TMPDIR="${sandbox_bin}" \
        /bin/bash --restricted --noprofile --norc run.sh
    ) 2>/dev/null
  )" || {
    wb_log_warn "wb_ppdb_import_legacy: child bash exited non-zero for '${input_path}'; producing best-effort output"
  }

  # ------------------------------------------------------------------
  # 5. Clean up sandbox tmpdir.  Any attempted writes that landed in
  #    $HOME or $TMPDIR (both pointing here) are discarded.
  # ------------------------------------------------------------------
  rm -rf "${sandbox_dir}"

  # ------------------------------------------------------------------
  # 6. Parse 'declare -p' output to extract KEY=VALUE pairs.
  #    Format: declare [--|-x|--r] KEY="VALUE"
  #    Values may contain bash escape sequences from the declare format.
  # ------------------------------------------------------------------
  declare -A _ppdb_env=()
  local runtime_val=""
  local line key raw_val stripped_val

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    # Match: declare [flags] KEY="VALUE"
    if [[ "${line}" =~ ^declare\ [^\ ]+\ ([A-Za-z_][A-Za-z0-9_]*)=\"(.*)\"$ ]]; then
      key="${BASH_REMATCH[1]}"
      raw_val="${BASH_REMATCH[2]}"
      # Unescape declare output: \" → "  and  \\ → \
      stripped_val="${raw_val//\\\"/\"}"
      stripped_val="${stripped_val//\\\\/\\}"
    elif [[ "${line}" =~ ^declare\ [^\ ]+\ ([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
      # Variable declared with no value (empty string)
      key="${BASH_REMATCH[1]}"
      stripped_val=""
    else
      continue
    fi

    # ------------------------------------------------------------------
    # 7. Map PortProton vars to wb JSON shape (allowlist enforced here).
    #    Non-allowlisted vars are silently dropped.
    # ------------------------------------------------------------------
    case "${key}" in
      PW_WINE_USE)
        # PW_WINE_USE → .runtime
        runtime_val="${stripped_val}"
        ;;
      WINE_PATH)
        # WINE_PATH → ignore (wb owns runtime resolution)
        ;;
      PW_*)
        # PW_{SUFFIX} → .env.WB_PP_{SUFFIX} to avoid clobbering WB_* namespace
        local suffix="${key#PW_}"
        _ppdb_env["WB_PP_${suffix}"]="${stripped_val}"
        ;;
      DXVK_*|VKD3D_*|DLL_*)
        # Component tuning vars → .env verbatim
        _ppdb_env["${key}"]="${stripped_val}"
        ;;
      WINEDEBUG|WINEARCH|WINEFSYNC|WINEESYNC|WINE[A-Z]*)
        # WINE* vars → .env verbatim (WINE_PATH excluded above)
        _ppdb_env["${key}"]="${stripped_val}"
        ;;
      # All other keys are silently dropped.
    esac
  done <<< "${raw_env}"

  # ------------------------------------------------------------------
  # 8. Build jq arguments for the env object and emit conformant JSON.
  # ------------------------------------------------------------------
  local jq_env_args=()
  local jq_env_pairs=""
  local i=0
  local env_key env_val

  for env_key in $(echo "${!_ppdb_env[@]}" | tr ' ' '\n' | sort); do
    env_val="${_ppdb_env[${env_key}]}"
    jq_env_args+=("--arg" "ek${i}" "${env_key}" "--arg" "ev${i}" "${env_val}")
    if [[ "${i}" -gt 0 ]]; then
      jq_env_pairs+=","
    fi
    jq_env_pairs+="\$ek${i}:\$ev${i}"
    (( i++ )) || true
  done

  local env_jq_expr="{${jq_env_pairs}}"

  local json
  json="$(
    jq -n \
      --argjson schema 1 \
      --arg runtime "${runtime_val}" \
      "${jq_env_args[@]+"${jq_env_args[@]}"}" \
      --argjson env_obj "$(
        jq -n "${jq_env_args[@]+"${jq_env_args[@]}"}" "${env_jq_expr}"
      )" \
      '{
        schema: $schema,
        runtime: $runtime,
        env: $env_obj,
        pre_exec: [],
        post_exec: []
      }'
  )"

  wb_json_write_atomic "${output_path}" "${json}"
  wb_log_info "wb_ppdb_import_legacy: wrote '${output_path}' (runtime='${runtime_val}', env_keys=${#_ppdb_env[@]})"
}

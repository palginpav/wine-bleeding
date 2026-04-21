#!/usr/bin/env bash
# tools/run-winetricks.sh — Phase D winetricks driver
#
# Mirrors tools/build-component.sh / tools/build-full.sh Phase B progress protocol.
# Emits PROGRESS:/LOG:/WARN:/ERROR: events on --progress-fd (default: 2).
#
# Usage:
#   tools/run-winetricks.sh \
#     --prefix <name> \
#     --dist <path> \
#     --verb <verb1> [--verb <verb2> ...] \
#     [--progress-fd N] \
#     [--timeout N] \
#     [--force] \
#     [--no-reconcile]
#
# Exit codes:
#   0   all verbs installed successfully
#   2   cancelled (SIGTERM)
#   3   prefix or dist path invalid
#   4   winetricks binary not found
#   5   one or more verbs failed
#   72  env-check failure (missing required tools)
#   1   generic failure (bad args, unexpected error)

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/build-common.sh
source "${WINE_ROOT}/tools/lib/build-common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PREFIX_ID=""
DIST_PATH=""
VERBS=()
PROGRESS_FD="2"
TIMEOUT_SEC=3600
FORCE=0
NO_RECONCILE=0
HELP=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ -n "${2:-}" ]] || { echo "run-winetricks: --prefix requires a value" >&2; exit 1; }
      PREFIX_ID="$2"; shift ;;
    --prefix=*)
      PREFIX_ID="${1#--prefix=}" ;;
    --dist)
      [[ -n "${2:-}" ]] || { echo "run-winetricks: --dist requires a value" >&2; exit 1; }
      DIST_PATH="$2"; shift ;;
    --dist=*)
      DIST_PATH="${1#--dist=}" ;;
    --verb)
      [[ -n "${2:-}" ]] || { echo "run-winetricks: --verb requires a value" >&2; exit 1; }
      VERBS+=("$2"); shift ;;
    --verb=*)
      VERBS+=("${1#--verb=}") ;;
    --progress-fd)
      [[ -n "${2:-}" ]] || { echo "run-winetricks: --progress-fd requires a value" >&2; exit 1; }
      PROGRESS_FD="$2"; shift ;;
    --progress-fd=*)
      PROGRESS_FD="${1#--progress-fd=}" ;;
    --timeout)
      [[ -n "${2:-}" ]] || { echo "run-winetricks: --timeout requires a value" >&2; exit 1; }
      TIMEOUT_SEC="$2"; shift ;;
    --timeout=*)
      TIMEOUT_SEC="${1#--timeout=}" ;;
    --force)
      FORCE=1 ;;
    --no-reconcile)
      NO_RECONCILE=1 ;;
    --help|-h)
      HELP=1 ;;
    *)
      echo "run-winetricks: unknown argument: $1" >&2
      echo "  Usage: $0 --prefix NAME --dist PATH --verb VERB [--progress-fd N]" >&2
      exit 1 ;;
  esac
  shift
done

if [[ "${HELP}" -eq 1 ]]; then
  cat <<'EOF'
Usage: tools/run-winetricks.sh --prefix NAME --dist PATH --verb VERB [OPTIONS]

Options:
  --prefix NAME       Prefix name (directory under $WB_HOME/prefixes/)
  --dist PATH         Path to active dist (must contain bin/wine)
  --verb VERB         Winetricks verb to install (repeatable for batch)
  --progress-fd N     FD for PROGRESS:/LOG:/WARN:/ERROR: events (default: 2)
  --timeout N         Soft timeout in seconds per verb (default: 3600)
  --force             Pass --force to winetricks (re-install)
  --no-reconcile      Skip post-install winetricks.log reconciliation

Exit codes:
  0   all verbs installed
  2   cancelled by user (SIGTERM)
  3   prefix or dist path invalid
  4   winetricks binary not found
  5   one or more verbs failed
  72  env-check failure
  1   generic/unexpected failure
EOF
  exit 0
fi

# Validate required args
if [[ -z "${PREFIX_ID}" ]]; then
  echo "run-winetricks: --prefix is required" >&2
  exit 1
fi
if [[ -z "${DIST_PATH}" ]]; then
  echo "run-winetricks: --dist is required" >&2
  exit 1
fi
if [[ "${#VERBS[@]}" -eq 0 ]]; then
  echo "run-winetricks: at least one --verb is required" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Set up event emission on the chosen fd
# ---------------------------------------------------------------------------
export WB_BUILD_PROGRESS_FD="${PROGRESS_FD}"

# ---------------------------------------------------------------------------
# Validate verb names (injection guard)
# ---------------------------------------------------------------------------
for _v in "${VERBS[@]}"; do
  local_verb_pat='^[a-z0-9_.=+-]+$'
  if ! [[ "${_v}" =~ ${local_verb_pat} ]]; then
    bc_emit_error "Invalid verb name '${_v}' — must match /^[a-z0-9_.=+-]+\$/"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
WB_HOME="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
PREFIX_PATH="${WB_HOME}/prefixes/${PREFIX_ID}"

# Validate dist
if [[ ! -d "${DIST_PATH}" ]]; then
  bc_emit_error "Dist path '${DIST_PATH}' does not exist"
  exit 3
fi
WINE_BIN="${DIST_PATH}/bin/wine"
if [[ ! -x "${WINE_BIN}" ]]; then
  bc_emit_error "No executable wine binary found at '${WINE_BIN}'"
  exit 3
fi

# ---------------------------------------------------------------------------
# Locate winetricks binary (WB_TEST_WT_FIXTURE seam)
# ---------------------------------------------------------------------------
if [[ -n "${WB_TEST_WT_FIXTURE:-}" ]]; then
  WT_BIN="${WB_TEST_WT_FIXTURE}"
elif command -v winetricks >/dev/null 2>&1; then
  WT_BIN="$(command -v winetricks)"
else
  bc_emit_error "winetricks binary not found. Install via your distro package manager."
  exit 4
fi

# ---------------------------------------------------------------------------
# Emit initial events
# ---------------------------------------------------------------------------
bc_emit_progress 0 "Preparing winetricks environment"
bc_emit_log "Using WINEPREFIX=${PREFIX_PATH}"
bc_emit_log "Using dist ${DIST_PATH}"

WT_VERSION="$("${WT_BIN}" --version 2>/dev/null || echo "unknown")"
bc_emit_log "Host winetricks version ${WT_VERSION}"

# Warn if old winetricks (< 20230000)
if [[ "${WT_VERSION}" =~ ^([0-9]{8}) ]]; then
  local_ver="${BASH_REMATCH[1]}"
  if [[ "${local_ver}" -lt 20230000 ]]; then
    bc_emit_warn "winetricks version ${WT_VERSION} is older than 20230607. Proceed with caution."
  fi
fi

# ---------------------------------------------------------------------------
# Acquire build lock (shared with Phase B)
# ---------------------------------------------------------------------------
bc_acquire_build_lock 5

# ---------------------------------------------------------------------------
# SIGTERM handler (Phase B OQ-4 pattern)
# ---------------------------------------------------------------------------
_WT_CHILD_PID=""
_WT_TMPDIR=""

_cleanup() {
  if [[ -n "${_WT_CHILD_PID}" ]] && kill -0 "${_WT_CHILD_PID}" 2>/dev/null; then
    kill -TERM "${_WT_CHILD_PID}" 2>/dev/null || true
    local elapsed=0
    while kill -0 "${_WT_CHILD_PID}" 2>/dev/null && [[ "${elapsed}" -lt 5 ]]; do
      sleep 1
      elapsed=$(( elapsed + 1 ))
    done
    if kill -0 "${_WT_CHILD_PID}" 2>/dev/null; then
      kill -KILL "${_WT_CHILD_PID}" 2>/dev/null || true
    fi
  fi
  if [[ -n "${_WT_TMPDIR}" ]] && [[ -d "${_WT_TMPDIR}" ]]; then
    rm -rf "${_WT_TMPDIR}"
  fi
  bc_release_build_lock
}

_sigterm_handler() {
  bc_emit_error "Cancelled by user"
  _cleanup
  exit 2
}

trap '_sigterm_handler' SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Compose WINEPREFIX env
# ---------------------------------------------------------------------------
export WINEPREFIX="${PREFIX_PATH}"
export WINE="${WINE_BIN}"
export WINESERVER="${DIST_PATH}/bin/wineserver"
export W_OPT_UNATTENDED=1

# Create prefix dir if needed
mkdir -p "${PREFIX_PATH}"

# ---------------------------------------------------------------------------
# Install verbs loop
# ---------------------------------------------------------------------------
_WT_TMPDIR="$(mktemp -d)"
VERB_COUNT="${#VERBS[@]}"
VERB_FAILED=0
i=0

for _verb in "${VERBS[@]}"; do
  i=$(( i + 1 ))
  local_pct_start=$(( (i - 1) * 90 / VERB_COUNT + 5 ))
  local_pct_end=$(( i * 90 / VERB_COUNT + 5 ))

  bc_emit_progress "${local_pct_start}" "Running winetricks ${_verb} (${i} of ${VERB_COUNT})"

  local_verb_log="${_WT_TMPDIR}/verb_${i}.log"

  # Build winetricks args
  local_wt_args=("--unattended" "--no-isolate")
  if [[ "${FORCE}" -eq 1 ]]; then
    local_wt_args+=("--force")
  fi
  local_wt_args+=("${_verb}")

  # Run winetricks; tee output to log; re-emit LOG events line by line
  local_verb_rc=0
  (
    exec < /dev/null
    "${WT_BIN}" "${local_wt_args[@]}" 2>&1
  ) | tee "${local_verb_log}" | while IFS= read -r wt_line; do
    bc_emit_log "${wt_line}"
  done &
  _WT_CHILD_PID="$!"

  # Soft timeout watchdog — emits heartbeat every 60s; warns at --timeout
  (
    local_elapsed=0
    while sleep 60 && kill -0 "${_WT_CHILD_PID}" 2>/dev/null; do
      local_elapsed=$(( local_elapsed + 60 ))
      local_mid_pct=$(( local_pct_start + (local_pct_end - local_pct_start) / 2 ))
      bc_emit_progress "${local_mid_pct}" "Still running (${local_elapsed}m elapsed)"
      if [[ "${local_elapsed}" -ge "${TIMEOUT_SEC}" ]]; then
        bc_emit_warn "Verb '${_verb}' has run for ${local_elapsed}s — is it stuck? Cancel to abort."
      fi
    done
  ) &
  local_watchdog_pid="$!"

  # Wait for winetricks child
  wait "${_WT_CHILD_PID}" || local_verb_rc=$?
  _WT_CHILD_PID=""
  # Kill watchdog
  kill "${local_watchdog_pid}" 2>/dev/null || true
  wait "${local_watchdog_pid}" 2>/dev/null || true

  if [[ "${local_verb_rc}" -ne 0 ]]; then
    bc_emit_error "Verb '${_verb}' failed (exit ${local_verb_rc})"
    VERB_FAILED=$(( VERB_FAILED + 1 ))
  else
    bc_emit_progress "${local_pct_end}" "Done verb ${_verb}"
  fi
done

# ---------------------------------------------------------------------------
# Post-loop reconcile
# ---------------------------------------------------------------------------
if [[ "${NO_RECONCILE}" -eq 0 ]]; then
  bc_emit_progress 95 "Reconciling winetricks.log"
  # Source the gui-prefix lib for reconcile if available
  local_gui_lib="$(bc_resolve_wb_gui_lib 2>/dev/null || true)"
  local_wb_lib="$(bc_resolve_wb_lib 2>/dev/null || true)"
  if [[ -n "${local_gui_lib}" ]] && [[ -n "${local_wb_lib}" ]] && \
     [[ -f "${local_gui_lib}/wb-gui-prefix.sh" ]] && \
     [[ -f "${local_wb_lib}/wb-json.sh" ]]; then
    (
      # shellcheck source=../runtime/src/wb-lib/wb-json.sh
      source "${local_wb_lib}/wb-json.sh"
      # shellcheck source=../runtime/src/wb-lib/wb-log.sh
      source "${local_wb_lib}/wb-log.sh" 2>/dev/null || true
      # shellcheck source=../runtime/src/wb-gui-lib/wb-gui-settings.sh
      source "${local_gui_lib}/wb-gui-settings.sh"
      # shellcheck source=../runtime/src/wb-gui-lib/wb-gui-prefix.sh
      source "${local_gui_lib}/wb-gui-prefix.sh"
      wb_gui_prefix_winetricks_reconcile "${PREFIX_ID}" 2>/dev/null || true
    ) || true
  fi
fi

# ---------------------------------------------------------------------------
# Release lock and exit
# ---------------------------------------------------------------------------
bc_emit_progress 100 "Done"
_WT_TMPDIR_SAVE="${_WT_TMPDIR}"
_WT_TMPDIR=""
rm -rf "${_WT_TMPDIR_SAVE}"
bc_release_build_lock

if [[ "${VERB_FAILED}" -gt 0 ]]; then
  exit 5
fi
exit 0

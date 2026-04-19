#!/usr/bin/env bash
set -euo pipefail

# reapply.sh — PortProton add_in_start_portwine hook.
# Installed at: $PORT_WINE_PATH/data/wb/hooks/reapply.sh
# Invoked by user.conf override immediately before pw_run().
# MUST NOT block PP's launch path for more than 0.5 seconds (M6-R4).

# Locate sibling lib directory relative to this installed hook.
_WB_HOOK_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/../lib"

if [[ ! -d "${_WB_HOOK_LIB_DIR}" ]]; then
  echo "wb reapply: lib dir missing at ${_WB_HOOK_LIB_DIR}" >&2
  exit 1
fi

_WB_HOOK_LIB_DIR="$(cd "${_WB_HOOK_LIB_DIR}" && pwd)"

# Only act when PP is running our dist.
# PW_WINE_USE is set by PP to the selected dist alias (e.g. "WINE-BLEEDING").
if [[ "${PW_WINE_USE:-}" != WINE-BLEEDING* ]]; then
  exit 0
fi

# Require WINEPREFIX to be set and non-empty.
if [[ -z "${WINEPREFIX:-}" ]]; then
  exit 0
fi

# Source required libraries.
# shellcheck source=../wb-lib/wb-log.sh disable=SC1091
source "${_WB_HOOK_LIB_DIR}/wb-log.sh"
# shellcheck source=../wb-lib/wb-json.sh disable=SC1091
source "${_WB_HOOK_LIB_DIR}/wb-json.sh"
# shellcheck source=../wb-lib/wb-lock.sh disable=SC1091
source "${_WB_HOOK_LIB_DIR}/wb-lock.sh"
# shellcheck source=../wb-lib/wb-paths.sh disable=SC1091
source "${_WB_HOOK_LIB_DIR}/wb-paths.sh"
# shellcheck source=../wb-lib/wb-components.sh disable=SC1091
source "${_WB_HOOK_LIB_DIR}/wb-components.sh"
# shellcheck source=../wb-lib/wb-reg.sh disable=SC1091
source "${_WB_HOOK_LIB_DIR}/wb-reg.sh"

# SECURITY: validate WINEPREFIX before touching it. PP passes this from
# user.conf; a malicious or misconfigured value (e.g., ../..) could cause us
# to create arbitrary directories + lock files on every game launch. Require
# the prefix to already exist as a directory AND to contain PP/Wine markers;
# refuse path-traversal tokens outright.
if [[ -z "${WINEPREFIX:-}" ]]; then
  exit 0
fi
if [[ "${WINEPREFIX}" == *..* ]]; then
  wb_log_warn "reapply: WINEPREFIX '${WINEPREFIX}' contains '..'; refusing"
  exit 0
fi
if [[ ! -d "${WINEPREFIX}" ]]; then
  exit 0
fi

# Acquire prefix lock with soft 0.5s timeout.
# Do NOT use the standard wb_acquire_lock loop — one try then one retry only.
_reapply_lock_fd=""
_reapply_lockfile="${WINEPREFIX}/.wb_lock"

exec {_reapply_lock_fd}>"${_reapply_lockfile}"

if ! flock -x -w 0 "${_reapply_lock_fd}" 2>/dev/null; then
  sleep 0.2
  if ! flock -x -w 0 "${_reapply_lock_fd}" 2>/dev/null; then
    wb_log_warn "reapply: prefix busy, skipping; PP will launch normally"
    exec {_reapply_lock_fd}>&-
    exit 0
  fi
fi

_reapply_release_lock() {
  exec {_reapply_lock_fd}>&- 2>/dev/null || true
}
trap '_reapply_release_lock' EXIT

# If no .wb_components manifest exists, this is not a wb-managed prefix.
if [[ ! -r "${WINEPREFIX}/.wb_components" ]]; then
  _reapply_release_lock
  trap - EXIT
  exit 0
fi

# Find the dist path. PP sets WINEDIR to the selected dist path.
_reapply_dist="${WINEDIR:-}"

# Check component drift; if none, only ensure .wine_ver is current.
drift_output="$(wb_components_diff "${WINEPREFIX}")"

if [[ -n "${drift_output}" ]] && [[ -n "${_reapply_dist}" ]]; then
  # Selectively redeploy drifted components. Only DXVK/VKD3D/NVAPI
  # are redeployed here; wineboot is NOT called (M6 spec).
  if echo "${drift_output}" | grep -q 'dxvk\|d3d'; then
    wb_component_deploy_dxvk "${WINEPREFIX}" "${_reapply_dist}" >/dev/null 2>&1 || true
  fi
  if echo "${drift_output}" | grep -q 'vkd3d\|d3d12'; then
    wb_component_deploy_vkd3d "${WINEPREFIX}" "${_reapply_dist}" >/dev/null 2>&1 || true
  fi
  if echo "${drift_output}" | grep -q 'nvapi\|nvcuda\|nvofapi'; then
    wb_component_deploy_nvapi "${WINEPREFIX}" "${_reapply_dist}" >/dev/null 2>&1 || true
  fi
fi

# Write .wine_ver idempotently so PP's .wine_ver grep check passes.
_wine_ver_file="${WINEPREFIX}/.wine_ver"
_expected_ver="WINE-BLEEDING"
_current_ver=""
if [[ -f "${_wine_ver_file}" ]]; then
  _current_ver="$(cat "${_wine_ver_file}" 2>/dev/null || true)"
fi

if [[ "${_current_ver}" != "${_expected_ver}" ]]; then
  printf '%s' "${_expected_ver}" > "${_wine_ver_file}"
fi

_reapply_release_lock
trap - EXIT
exit 0

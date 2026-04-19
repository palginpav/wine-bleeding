#!/usr/bin/env bash
set -euo pipefail

# File descriptor used for flock; assigned dynamically by `exec {var}>file` (bash 4.1+)
_WB_LOCK_FD=""

_wb_lock_is_nfs() {
  local prefix_path="$1"
  local fs_type
  fs_type="$(stat -f -c '%T' "${prefix_path}" 2>/dev/null || echo "unknown")"
  [[ "${fs_type}" =~ ^(nfs|nfs4|cifs|smb|smb2|fuse|fuseblk|virtiofs)$ ]]
}

_wb_lock_stale_nfs() {
  local lockdir="$1"
  local stale_secs=60
  [[ ! -d "${lockdir}" ]] && return 1
  local mtime now age
  mtime="$(stat -c '%Y' "${lockdir}" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  age=$(( now - mtime ))
  [[ "${age}" -gt "${stale_secs}" ]]
}

wb_acquire_lock() {
  local prefix_path="$1"
  mkdir -p "${prefix_path}"

  if _wb_lock_is_nfs "${prefix_path}"; then
    local lockdir="${prefix_path}/.wb_lock.d"
    if _wb_lock_stale_nfs "${lockdir}"; then
      rmdir "${lockdir}" 2>/dev/null || true
    fi
    if mkdir "${lockdir}" 2>/dev/null; then
      # Store lockdir path for release
      export _WB_NFS_LOCKDIR="${lockdir}"
      _WB_NFS_LOCK_ACTIVE=1
      export _WB_NFS_LOCK_ACTIVE
      # NFS mkdir-based fallback in use
      if [[ -n "${WB_LOG_FILE:-}${WB_HOME:-}" ]]; then
        # shellcheck disable=SC1091
        source "$(dirname "${BASH_SOURCE[0]}")/wb-log.sh" 2>/dev/null || true
        wb_log_warn "NFS prefix detected; using mkdir-based lock at ${lockdir}"
      fi
      return 0
    else
      echo "wb: another wb process holds the lock on ${prefix_path} (NFS mkdir lock)" >&2
      echo "wb: if the lock is stale, remove ${lockdir} manually" >&2
      return 1
    fi
  fi

  local lockfile="${prefix_path}/.wb_lock"
  exec {_WB_LOCK_FD}>"${lockfile}"
  if ! flock -x -n "${_WB_LOCK_FD}" 2>/dev/null; then
    echo "wb: another wb process holds the lock on ${prefix_path}" >&2
    echo "wb: wait for it to finish or remove ${lockfile} if it is stale" >&2
    exec {_WB_LOCK_FD}>&-
    return 1
  fi
  _WB_NFS_LOCK_ACTIVE=0
  export _WB_NFS_LOCK_ACTIVE
}

wb_release_lock() {
  local prefix_path="$1"

  if [[ "${_WB_NFS_LOCK_ACTIVE:-0}" == "1" ]]; then
    local lockdir="${_WB_NFS_LOCKDIR:-${prefix_path}/.wb_lock.d}"
    rmdir "${lockdir}" 2>/dev/null || true
    _WB_NFS_LOCK_ACTIVE=0
    return 0
  fi

  if [[ -n "${_WB_LOCK_FD}" ]]; then
    exec {_WB_LOCK_FD}>&- 2>/dev/null || true
  fi
}

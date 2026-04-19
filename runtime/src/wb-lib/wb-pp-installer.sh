#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# wb-pp-installer.sh — PortProton plugin install/uninstall/publish helpers.
# Public API:
#   wb_pp_detect_root          print PP root path
#   wb_pp_install_hook <data>  append wb hook block to user.conf (idempotent)
#   wb_pp_uninstall_hook <data> reverse install (restore from backup or sed)
#   wb_pp_publish_dist <src> <data> [--reapply-only|--uninstall]
# ---------------------------------------------------------------------------

# --- PP root detection ---------------------------------------------------
#
# Detection order:
#   1. $PORT_WINE_PATH — always wins if set (any environment).
#   2. Flatpak sandbox ($FLATPAK_ID is set) — check the host path that
#      --filesystem=~/PortProton surfaces at /run/host/home/<user>/PortProton.
#   3. Standard ~/PortProton (non-sandbox fallback).
#
# The function only prints the path; it never creates directories.
# Callers that require the path to exist must validate it themselves.
# In Flatpak mode without a detectable PortProton directory the function still
# returns the standard ~/PortProton path and emits a warning to stderr so that
# callers can decide how to proceed (plugin mode will fail cleanly).

wb_pp_detect_root() {
  # Priority 1: explicit override from environment (works everywhere).
  if [[ -n "${PORT_WINE_PATH:-}" ]]; then
    echo "${PORT_WINE_PATH}"
    return 0
  fi

  # Priority 2: Flatpak sandbox — FLATPAK_ID is set inside a Flatpak app.
  if [[ -n "${FLATPAK_ID:-}" ]]; then
    # Flatpak exposes the real home via /run/host/home/<user> when
    # --filesystem=~/PortProton is granted at install time.
    local _flatpak_host_pp="/run/host/home/${USER}/PortProton"
    if [[ -d "${_flatpak_host_pp}" ]]; then
      echo "${_flatpak_host_pp}"
      return 0
    fi
    # Host path not visible — either permission was not granted or PortProton
    # is not installed.  Warn and fall through to the standard path so that
    # the caller can produce a useful error.
    echo "wb-pp-installer: PortProton not accessible from Flatpak sandbox;" \
         "grant --filesystem=~/PortProton at install time" >&2
  fi

  # Priority 3: standard non-sandbox location.
  echo "${HOME}/PortProton"
}

# --- Install hook into user.conf -----------------------------------------

wb_pp_install_hook() {
  local pp_data="$1"
  local user_conf="${pp_data}/user.conf"
  local hook_src
  hook_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/reapply.sh"
  local hook_dst_dir="${pp_data}/wb/hooks"
  local lib_dst_dir="${pp_data}/wb/lib"
  local lib_src_dir
  lib_src_dir="$(dirname "${BASH_SOURCE[0]}")"

  # Serialize concurrent installs via an exclusive lock on user.conf.
  local _pp_install_lock_fd
  exec {_pp_install_lock_fd}>>"${pp_data}/user.conf.wb-install-lock"
  flock -x "${_pp_install_lock_fd}"

  # Now-inside-lock: re-check for pre-existing content.
  # SECURITY: fence check uses '^# BEGIN wb-runtime' (line anchor) so a user
  # comment containing the marker text cannot trigger a false "already installed".
  if [[ -f "${user_conf}" ]]; then
    if grep -q '^# BEGIN wb-runtime' "${user_conf}" 2>/dev/null; then
      flock -u "${_pp_install_lock_fd}"
      exec {_pp_install_lock_fd}>&-
      echo "already installed"
      return 0
    fi
    if grep -q '^add_in_start_portwine' "${user_conf}" 2>/dev/null; then
      flock -u "${_pp_install_lock_fd}"
      exec {_pp_install_lock_fd}>&-
      echo "wb-pp-installer: user.conf already defines add_in_start_portwine (not wb-managed); refusing to overwrite. Use --force to override." >&2
      return 1
    fi
  fi

  # Make unconditional backup BEFORE any write.
  local backup_ts
  backup_ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local backup_file="${user_conf}.wb-backup-${backup_ts}"

  if [[ ! -f "${user_conf}" ]]; then
    touch "${user_conf}"
  fi

  cp -f "${user_conf}" "${backup_file}"

  # Append fenced hook block using cat >> (never sed -i for install).
  local install_ts
  install_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat >> "${user_conf}" <<HOOK_BLOCK
# BEGIN wb-runtime hook installed ${install_ts}
add_in_start_portwine () {
    [ -x "\$PORT_WINE_PATH/data/wb/hooks/reapply.sh" ] && \
        "\$PORT_WINE_PATH/data/wb/hooks/reapply.sh" "\$@"
}
# END wb-runtime
HOOK_BLOCK
  sync

  flock -u "${_pp_install_lock_fd}"
  exec {_pp_install_lock_fd}>&-

  # Copy reapply.sh and all required libs into pp_data/wb/.
  mkdir -p "${hook_dst_dir}" "${lib_dst_dir}"

  if [[ ! -f "${hook_src}" ]]; then
    echo "wb-pp-installer: reapply.sh not found at ${hook_src}" >&2
    return 1
  fi
  cp -f "${hook_src}" "${hook_dst_dir}/reapply.sh"
  chmod +x "${hook_dst_dir}/reapply.sh"

  local lib
  for lib in wb-log.sh wb-json.sh wb-lock.sh wb-paths.sh wb-components.sh wb-reg.sh wb-die.sh wb-config.sh; do
    if [[ -f "${lib_src_dir}/${lib}" ]]; then
      cp -f "${lib_src_dir}/${lib}" "${lib_dst_dir}/${lib}"
    else
      echo "wb-pp-installer: warning: lib not found: ${lib_src_dir}/${lib}" >&2
    fi
  done

  echo "installed: ${user_conf}"
}

# --- Install hook (force override existing add_in_start_portwine) ---------

wb_pp_install_hook_force() {
  local pp_data="$1"
  local user_conf="${pp_data}/user.conf"

  # SECURITY: serialize with the same lock wb_pp_install_hook uses so concurrent
  # --force invocations do not race on the AWK temp-file write (W2 L2).
  local _pp_install_lock_fd
  exec {_pp_install_lock_fd}>>"${pp_data}/user.conf.wb-install-lock"
  flock -x "${_pp_install_lock_fd}"

  if [[ -f "${user_conf}" ]]; then
    if grep -q '^# BEGIN wb-runtime' "${user_conf}" 2>/dev/null; then
      flock -u "${_pp_install_lock_fd}"
      exec {_pp_install_lock_fd}>&-
      echo "already installed"
      return 0
    fi
  fi

  # Remove existing add_in_start_portwine function definition (basic pattern).
  if [[ -f "${user_conf}" ]] && grep -q '^add_in_start_portwine' "${user_conf}" 2>/dev/null; then
    local tmp_conf
    tmp_conf="$(mktemp)"
    awk '
      /^add_in_start_portwine[[:space:]]*\(\)/ { skip=1 }
      skip && /^\}/ { skip=0; next }
      !skip { print }
    ' "${user_conf}" > "${tmp_conf}"
    cp -f "${tmp_conf}" "${user_conf}"
    rm -f "${tmp_conf}"
  fi

  flock -u "${_pp_install_lock_fd}"
  exec {_pp_install_lock_fd}>&-

  wb_pp_install_hook "${pp_data}"
}

# --- Uninstall hook from user.conf ----------------------------------------

wb_pp_uninstall_hook() {
  local pp_data="$1"
  local user_conf="${pp_data}/user.conf"

  # Idempotent: if neither block nor wb dir exist, already uninstalled.
  # SECURITY: fence match uses '^# BEGIN wb-runtime' (line anchor) so user
  # comments containing the marker cannot be misidentified as our block.
  local block_present=0
  if [[ -f "${user_conf}" ]] && grep -q '^# BEGIN wb-runtime' "${user_conf}" 2>/dev/null; then
    block_present=1
  fi
  local wb_dir_present=0
  if [[ -d "${pp_data}/wb" ]]; then
    wb_dir_present=1
  fi

  if [[ "${block_present}" -eq 0 && "${wb_dir_present}" -eq 0 ]]; then
    echo "already uninstalled"
    return 0
  fi

  # Prefer restoring from the most-recent backup.
  local newest_backup
  # shellcheck disable=SC2012
  newest_backup="$(ls -1t "${user_conf}.wb-backup-"* 2>/dev/null | head -1 || true)"

  if [[ -n "${newest_backup}" && -f "${newest_backup}" ]]; then
    # SECURITY: refuse to restore from a symlinked backup — would overwrite
    # whatever the symlink points at. Backup files must be regular files.
    if [[ -L "${newest_backup}" ]]; then
      echo "wb-pp-installer: refusing to restore from symlinked backup: ${newest_backup}" >&2
      return 1
    fi
    cp -f "${newest_backup}" "${user_conf}"
  elif [[ "${block_present}" -eq 1 ]]; then
    # Fallback: sed-remove the fenced block (uninstall only, per spec).
    # SECURITY: both anchors use '^' to prevent user content containing the
    # marker text from being used as a range anchor (which would destroy
    # surrounding user lines).
    local tmp_conf
    tmp_conf="$(mktemp)"
    sed '/^# BEGIN wb-runtime/,/^# END wb-runtime/d' "${user_conf}" > "${tmp_conf}"
    cp -f "${tmp_conf}" "${user_conf}"
    rm -f "${tmp_conf}"
  fi

  # Remove the installed wb tree.
  if [[ -d "${pp_data}/wb" ]]; then
    rm -rf "${pp_data}/wb"
  fi

  echo "uninstalled: ${user_conf}"
}

# --- Full dist publish (owns deploy-to-portproton.sh logic) ---------------

wb_pp_publish_dist() {
  local dist_src="$1"
  local pp_data="$2"
  shift 2
  local reapply_only=0
  local do_uninstall=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reapply-only) reapply_only=1 ;;
      --uninstall) do_uninstall=1 ;;
      *) echo "wb_pp_publish_dist: unknown flag '$1'" >&2; return 1 ;;
    esac
    shift
  done

  if [[ "${do_uninstall}" -eq 1 ]]; then
    wb_pp_uninstall_hook "${pp_data}"
    return 0
  fi

  local pp_dist="${pp_data}/dist"
  local dist_name
  dist_name="$(basename "${dist_src}")"
  local dist_dst="${pp_dist}/${dist_name}"

  if [[ "${reapply_only}" -eq 0 ]]; then
    # Full deploy: mirror source dist into PP data/dist/.
    [[ -d "${pp_data}" ]] || { echo "wb_pp_publish_dist: PP data dir not found: ${pp_data}" >&2; return 1; }
    [[ -d "${dist_src}/bin" ]] || { echo "wb_pp_publish_dist: dist missing bin/: ${dist_src}" >&2; return 1; }

    mkdir -p "${pp_dist}"

    if [[ -d "${dist_dst}" ]]; then
      echo "Distribution already exists in PortProton. Updating..."
      rm -rf "${dist_dst}"
    fi

    echo "Copying distribution to PortProton..."
    cp -a "${dist_src}" "${dist_dst}"
    echo "Done. $(find "${dist_dst}" -type f | wc -l) files deployed."

    # Update WINE-BLEEDING symlink (alias) to point at the versioned name.
    local alias_link="${pp_dist}/WINE-BLEEDING"
    ln -sfn "${dist_name}" "${alias_link}" 2>/dev/null || true

    # Update shared PortProton mono if the shared location exists.
    local mono_src="${dist_dst}/share/wine/mono"
    local mono_ver
    # shellcheck disable=SC2012
    mono_ver="$(ls -1d "${mono_src}"/wine-mono-* 2>/dev/null | sort -V | tail -1 | xargs basename 2>/dev/null || true)"
    local pp_tmp="${pp_data}/tmp"
    local shared_mono="${pp_tmp}/mono/${mono_ver}"
    if [[ -n "${mono_ver}" && -d "${shared_mono}" && -d "${mono_src}/${mono_ver}" ]]; then
      echo "Updating shared PortProton mono..."
      rsync -a --update "${mono_src}/${mono_ver}/" "${shared_mono}/" 2>/dev/null \
        || cp -a "${mono_src}/${mono_ver}/"* "${shared_mono}/" 2>/dev/null || true
      echo "Shared mono fully synced"
    fi
  fi

  if [[ "${reapply_only}" -eq 1 ]]; then
    # Reapply-only: components diff + selective redeploy, no wineboot.
    local pp_prefixes="${pp_data}/prefixes"
    if [[ ! -d "${pp_prefixes}" ]]; then
      echo "No prefixes directory at ${pp_prefixes}; nothing to reapply."
      return 0
    fi
    local pfx
    for pfx in "${pp_prefixes}"/*/; do
      [[ -d "${pfx}" ]] || continue
      [[ -f "${pfx}/.wb_components" ]] || continue
      local drift
      drift="$(wb_components_diff "${pfx}")"
      if [[ -n "${drift}" ]]; then
        echo "Reapplying drifted components in: ${pfx}"
        wb_component_deploy_dxvk "${pfx}" "${dist_dst:-${dist_src}}" >/dev/null || true
        wb_component_deploy_vkd3d "${pfx}" "${dist_dst:-${dist_src}}" >/dev/null || true
        wb_component_deploy_nvapi "${pfx}" "${dist_dst:-${dist_src}}" >/dev/null || true
        echo "  skip rate: redeployed drifted components"
      else
        echo "  skipped (up to date): ${pfx}"
      fi
    done
  fi
}

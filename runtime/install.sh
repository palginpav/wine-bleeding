#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# install.sh — wb-runtime standalone installer (M7)
#
# Usage:
#   ./install.sh                            standalone install to $WB_HOME
#   ./install.sh --portproton-plugin        install as PP plugin
#               [--pp-root PATH]            override PP root (default: $PORT_WINE_PATH or ~/PortProton)
#   ./install.sh --uninstall [--purge]      remove $WB_HOME (preserve prefixes/ unless --purge)
#   ./install.sh --prefix /custom/path      override $WB_HOME install location
#   ./install.sh --dry-run                  print intended actions, write nothing
#   ./install.sh --help                     show this text
#
# All modes are idempotent: a double-run produces zero observable changes.
# ---------------------------------------------------------------------------

INSTALL_VERSION="0.1.0-M7"

# Resolve the directory that contains this install.sh (the runtime/ directory).
_RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SRC_DIR="${_RUNTIME_DIR}/src"
_SHARE_DIR="${_RUNTIME_DIR}/share"
_PLUGINS_DIR="${_RUNTIME_DIR}/plugins"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
MODE="standalone"        # standalone | portproton-plugin | uninstall
DRY_RUN=0
PURGE=0
PP_ROOT_OVERRIDE=""
WB_HOME_OVERRIDE=""
STEAM_COMPAT_TOOL=0      # --steam-compat-tool: symlink compat tool into Steam

usage() {
  cat <<EOF
wb-runtime ${INSTALL_VERSION} installer

Usage:
  $(basename "${BASH_SOURCE[0]}") [OPTIONS]

Modes (mutually exclusive):
  (no flag)               Standalone install into \$WB_HOME
  --portproton-plugin     Install as a PortProton plugin
  --uninstall             Remove installed files (preserves prefixes/)

Options:
  --prefix PATH           Override \$WB_HOME install location
  --pp-root PATH          Override PortProton root (plugin mode only)
  --steam-compat-tool     Also symlink compat tool into ~/.steam/root/compatibilitytools.d/
  --purge                 With --uninstall: wipe prefixes/ and profile.conf too
  --dry-run               Print what would happen; write nothing
  --help                  Show this message and exit

Environment:
  WB_HOME                 Install root (overridden by --prefix)
  XDG_DATA_HOME           Fallback for default WB_HOME (~/.local/share)
  XDG_CONFIG_HOME         Location of profile.conf (~/.config by default)
  PORT_WINE_PATH          PortProton root for plugin mode
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --portproton-plugin)
      MODE="portproton-plugin"
      shift
      ;;
    --uninstall)
      MODE="uninstall"
      shift
      ;;
    --purge)
      PURGE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --prefix)
      WB_HOME_OVERRIDE="${2:-}"
      shift 2
      ;;
    --prefix=*)
      WB_HOME_OVERRIDE="${1#--prefix=}"
      shift
      ;;
    --pp-root)
      PP_ROOT_OVERRIDE="${2:-}"
      shift 2
      ;;
    --pp-root=*)
      PP_ROOT_OVERRIDE="${1#--pp-root=}"
      shift
      ;;
    --steam-compat-tool)
      STEAM_COMPAT_TOOL=1
      shift
      ;;
    *)
      echo "install.sh: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# --purge is only meaningful with --uninstall; refuse silent-install-with-purge.
if [[ "${PURGE}" -eq 1 && "${MODE}" != "uninstall" ]]; then
  echo "install.sh: --purge requires --uninstall" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve $WB_HOME
# ---------------------------------------------------------------------------
if [[ -n "${WB_HOME_OVERRIDE}" ]]; then
  WB_HOME="${WB_HOME_OVERRIDE}"
else
  WB_HOME="${WB_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/wine-bleeding}"
fi

# SECURITY: canonicalize $WB_HOME so `--prefix ../../escape` cannot install
# outside its intended location. Also refuse obviously-dangerous roots and
# pre-existing symlinks (would redirect writes to an attacker-controlled tree).
WB_HOME="$(realpath -m "${WB_HOME}")"
case "${WB_HOME}" in
  ""|/|/usr|/usr/*|/etc|/etc/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/lib64|/lib64/*|/boot|/boot/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/var/run|/var/lib|/var/log)
    echo "install.sh: refusing to install into system path '${WB_HOME}'" >&2
    exit 1
    ;;
esac
if [[ -L "${WB_HOME}" ]]; then
  echo "install.sh: refusing to install into '${WB_HOME}' (is a symlink; follow-through would write into symlink target)" >&2
  exit 1
fi
export WB_HOME

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
WB_CONFIG_DIR="${XDG_CONFIG_HOME}/wine-bleeding"
WB_PROFILE_CONF="${WB_CONFIG_DIR}/profile.conf"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_info()  { echo "  [install] $*"; }
_warn()  { echo "  [WARN]    $*" >&2; }
_error() { echo "  [ERROR]   $*" >&2; }

_dryrun_or_run() {
  # Usage: _dryrun_or_run <description> <cmd> [args...]
  local desc="$1"
  shift
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  [dry-run] ${desc}"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Lock helpers (serialize concurrent installs)
# ---------------------------------------------------------------------------
_LOCK_FD=""
_acquire_install_lock() {
  local lockdir="${WB_HOME}"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    mkdir -p "${lockdir}"
  fi
  local lockfile="${lockdir}/.install.lock"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    exec {_LOCK_FD}>>"${lockfile}"
    flock -x "${_LOCK_FD}"
  fi
}
_release_install_lock() {
  if [[ -n "${_LOCK_FD}" ]]; then
    flock -u "${_LOCK_FD}" 2>/dev/null || true
    eval "exec ${_LOCK_FD}>&-" 2>/dev/null || true
    _LOCK_FD=""
  fi
}
trap '_release_install_lock' EXIT

# ---------------------------------------------------------------------------
# Mode: standalone install
# ---------------------------------------------------------------------------
_do_standalone_install() {
  _info "Installing wb-runtime ${INSTALL_VERSION} to ${WB_HOME}"

  _acquire_install_lock

  # 1. Create directory tree per §3.1
  local dirs=(
    "${WB_HOME}/bin"
    "${WB_HOME}/bin/wb-lib"
    "${WB_HOME}/dist"
    "${WB_HOME}/prefixes"
    "${WB_HOME}/cache/dxvk-state"
    "${WB_HOME}/cache/vkd3d-shader"
    "${WB_HOME}/cache/mono-shared"
    "${WB_HOME}/cache/gecko-shared"
    "${WB_HOME}/plugins/hooks.d"
    "${WB_HOME}/plugins/runtimes.d"
    "${WB_HOME}/share/schemas"
    "${WB_HOME}/etc"
    "${WB_HOME}/log"
    "${WB_HOME}/state"
  )
  local d
  for d in "${dirs[@]}"; do
    if [[ ! -d "${d}" ]]; then
      _dryrun_or_run "mkdir -p ${d}" mkdir -p "${d}"
    fi
  done

  # Config dir lives outside WB_HOME (§3.2)
  if [[ ! -d "${WB_CONFIG_DIR}" ]]; then
    _dryrun_or_run "mkdir -p ${WB_CONFIG_DIR}" mkdir -p "${WB_CONFIG_DIR}"
  fi

  # 2. Copy wb + wb-diag to bin/
  _install_file "${_SRC_DIR}/wb"      "${WB_HOME}/bin/wb"      755
  _install_file "${_SRC_DIR}/wb-diag" "${WB_HOME}/bin/wb-diag" 755

  # 3. Copy all wb-lib/* into $WB_HOME/bin/wb-lib/
  # (wb discovers libs as $(dirname BASH_SOURCE[0])/wb-lib — keep it co-located)
  local lib
  for lib in "${_SRC_DIR}/wb-lib/"*.sh; do
    [[ -f "${lib}" ]] || continue
    _install_file "${lib}" "${WB_HOME}/bin/wb-lib/$(basename "${lib}")" 644
  done

  # 4. Copy hooks/
  if [[ -d "${_SRC_DIR}/hooks" ]]; then
    local hook
    for hook in "${_SRC_DIR}/hooks/"*.sh; do
      [[ -f "${hook}" ]] || continue
      _install_file "${hook}" "${WB_HOME}/bin/$(basename "${hook}")" 755
    done
  fi

  # 5. Copy share/ assets
  _install_file "${_SHARE_DIR}/defaults.conf" "${WB_HOME}/share/defaults.conf" 644
  local schema
  for schema in "${_SHARE_DIR}/schemas/"*.json; do
    [[ -f "${schema}" ]] || continue
    _install_file "${schema}" "${WB_HOME}/share/schemas/$(basename "${schema}")" 644
  done

  # 6. Copy example hook
  local example_hook="${_PLUGINS_DIR}/hooks.d/00-example.pre-exec.sh.example"
  if [[ -f "${example_hook}" ]]; then
    _install_file "${example_hook}" \
      "${WB_HOME}/plugins/hooks.d/00-example.pre-exec.sh.example" 644
  fi

  # 7. If dist/WINE-BLEEDING-* directories exist in source tree, copy newest one in
  _maybe_install_dist

  # 8. Create ~/.local/bin/wb symlink
  _install_wb_symlink

  # M12: Install GUI components
  _install_gui

  # 9. Check PATH
  _check_path_contains_local_bin

  # 10. Post-install validation
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    _post_install_validate
  else
    _info "dry-run: skipping post-install validation"
  fi

  _release_install_lock
  _info "Installation complete."
}

# Helper: install a single file if missing or content differs (idempotent)
_install_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [[ ! -f "${src}" ]]; then
    _warn "source file not found, skipping: ${src}"
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  [dry-run] install ${src} -> ${dst} (mode ${mode})"
    return 0
  fi

  # Idempotent: only copy if content differs
  if [[ -f "${dst}" ]]; then
    local src_hash dst_hash
    src_hash="$(sha256sum "${src}" | awk '{print $1}')"
    dst_hash="$(sha256sum "${dst}"  | awk '{print $1}')"
    if [[ "${src_hash}" == "${dst_hash}" ]]; then
      # Already installed and identical; ensure permissions are correct
      chmod "${mode}" "${dst}"
      return 0
    fi
  fi

  cp -f "${src}" "${dst}"
  chmod "${mode}" "${dst}"
}

# Install dist from source tree if present
_maybe_install_dist() {
  # Look for WINE-BLEEDING-* in the repository's dist/ directory (sibling of runtime/).
  local repo_dist="${_RUNTIME_DIR}/../dist"
  if [[ ! -d "${repo_dist}" ]]; then
    _info "No dist/ directory in source tree; Wine builds can be added later via 'wb runtime install'."
    return 0
  fi

  # Find the newest WINE-BLEEDING-* directory
  local newest=""
  local entry
  while IFS= read -r entry; do
    newest="${entry}"
  done < <(find "${repo_dist}" -maxdepth 1 -type d -name 'WINE-BLEEDING-*' | sort -V 2>/dev/null || true)

  if [[ -z "${newest}" ]]; then
    _info "No WINE-BLEEDING-* dist in source tree; add dists later via 'wb runtime install'."
    return 0
  fi

  local dist_name
  dist_name="$(basename "${newest}")"
  local dst_dist="${WB_HOME}/dist/${dist_name}"

  if [[ -d "${dst_dist}" ]]; then
    _info "dist ${dist_name} already present in ${WB_HOME}/dist/, skipping copy."
  else
    _info "Copying ${dist_name} into ${WB_HOME}/dist/ ..."
    _dryrun_or_run "cp -a ${newest} ${dst_dist}" cp -a "${newest}" "${dst_dist}"
  fi

  if [[ "${DRY_RUN}" -eq 0 ]]; then
    # Activate the alias (WB_HOME is already exported)
    _info "Activating ${dist_name} as WINE-BLEEDING alias..."
    "${WB_HOME}/bin/wb" runtime activate "${dist_name}" >/dev/null 2>&1 || \
      _warn "wb runtime activate failed; you can run it manually later."
  else
    echo "  [dry-run] wb runtime activate ${dist_name}"
  fi
}

# Create ~/.local/bin/wb symlink (idempotent)
_install_wb_symlink() {
  local local_bin="${HOME}/.local/bin"
  local symlink_path="${local_bin}/wb"
  local symlink_target="${WB_HOME}/bin/wb"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  [dry-run] create symlink ${symlink_path} -> ${symlink_target}"
    return 0
  fi

  if [[ ! -d "${local_bin}" ]]; then
    mkdir -p "${local_bin}"
  fi

  if [[ -L "${symlink_path}" ]]; then
    local current_target
    current_target="$(readlink -f "${symlink_path}" 2>/dev/null || true)"
    local resolved_target
    resolved_target="$(readlink -f "${symlink_target}" 2>/dev/null || true)"
    if [[ "${current_target}" == "${resolved_target}" ]]; then
      return 0   # already correct
    fi
    # Wrong target: re-link
    ln -sfn "${symlink_target}" "${symlink_path}"
    _info "Relinked ${symlink_path} -> ${symlink_target}"
  elif [[ -e "${symlink_path}" ]]; then
    _warn "${symlink_path} exists and is not a symlink; skipping symlink creation."
  else
    ln -s "${symlink_target}" "${symlink_path}"
    _info "Created ${symlink_path} -> ${symlink_target}"
  fi
}

# ---------------------------------------------------------------------------
# M12: Install GUI files (wb-gui, wb-gui-lib, icons, .desktop, compat tool)
# ---------------------------------------------------------------------------
_install_gui() {
  _info "Installing GUI components (M12)..."

  # 1. wb-gui binary
  if [[ -f "${_SRC_DIR}/wb-gui" ]]; then
    _install_file "${_SRC_DIR}/wb-gui" "${WB_HOME}/bin/wb-gui" 755
  else
    _warn "wb-gui not found in source; skipping GUI install."
    return 0
  fi

  # 2. wb-gui-lib/ scripts
  if [[ -d "${_SRC_DIR}/wb-gui-lib" ]]; then
    if [[ "${DRY_RUN}" -eq 0 ]]; then
      mkdir -p "${WB_HOME}/bin/wb-gui-lib" || true
    fi
    local glib
    for glib in "${_SRC_DIR}/wb-gui-lib/"*.sh; do
      [[ -f "${glib}" ]] || continue
      _install_file "${glib}" "${WB_HOME}/bin/wb-gui-lib/$(basename "${glib}")" 644
    done
  fi

  # 3. ~/.local/bin/wb-gui symlink
  local local_bin="${HOME}/.local/bin"
  local wb_gui_symlink="${local_bin}/wb-gui"
  local wb_gui_target="${WB_HOME}/bin/wb-gui"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  [dry-run] create symlink ${wb_gui_symlink} -> ${wb_gui_target}"
  else
    mkdir -p "${local_bin}"
    if [[ -L "${wb_gui_symlink}" ]]; then
      local cur
      cur="$(readlink -f "${wb_gui_symlink}" 2>/dev/null || true)"
      local want
      want="$(readlink -f "${wb_gui_target}" 2>/dev/null || true)"
      if [[ "${cur}" != "${want}" ]]; then
        ln -sfn "${wb_gui_target}" "${wb_gui_symlink}"
        _info "Relinked ${wb_gui_symlink} -> ${wb_gui_target}"
      fi
    elif [[ ! -e "${wb_gui_symlink}" ]]; then
      ln -s "${wb_gui_target}" "${wb_gui_symlink}"
      _info "Created ${wb_gui_symlink} -> ${wb_gui_target}"
    fi
  fi

  # 4. .desktop file
  local apps_dir="${HOME}/.local/share/applications"
  local desktop_src="${_SHARE_DIR}/applications/wine-bleeding-wb.desktop"
  if [[ -f "${desktop_src}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "  [dry-run] install ${desktop_src} -> ${apps_dir}/wine-bleeding-wb.desktop"
    else
      mkdir -p "${apps_dir}"
      cp -f "${desktop_src}" "${apps_dir}/wine-bleeding-wb.desktop"
      chmod 644 "${apps_dir}/wine-bleeding-wb.desktop"
      _info "Installed .desktop file -> ${apps_dir}/wine-bleeding-wb.desktop"
      # Trigger update if available
      if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${apps_dir}" 2>/dev/null || true
      fi
    fi
  fi

  # 5. Icon
  local icon_dir="${HOME}/.local/share/icons/hicolor/scalable/apps"
  local icon_src="${_SHARE_DIR}/icons/hicolor/scalable/apps/wine-bleeding.svg"
  if [[ -f "${icon_src}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "  [dry-run] install icon -> ${icon_dir}/wine-bleeding.svg"
    else
      mkdir -p "${icon_dir}"
      cp -f "${icon_src}" "${icon_dir}/wine-bleeding.svg"
      chmod 644 "${icon_dir}/wine-bleeding.svg"
      _info "Installed icon -> ${icon_dir}/wine-bleeding.svg"
    fi
  fi

  # 6. compatibilitytools.d tree (always install into WB_HOME/share/)
  local compat_src="${_SHARE_DIR}/compatibilitytools.d"
  if [[ -d "${compat_src}" ]]; then
    local compat_dst="${WB_HOME}/share/compatibilitytools.d"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "  [dry-run] install compat tool tree -> ${compat_dst}"
    else
      mkdir -p "${compat_dst}"
      cp -a "${compat_src}/." "${compat_dst}/"
      chmod 755 "${compat_dst}/wine-bleeding/wine-bleeding.sh" 2>/dev/null || true
      _info "Installed compat tool tree -> ${compat_dst}"
    fi
  fi

  # 7. Steam compat tool symlink (only if --steam-compat-tool was passed)
  if [[ "${STEAM_COMPAT_TOOL}" -eq 1 ]]; then
    _install_steam_compat_tool
  fi
}

# Symlink the compat tool tree into Steam's compatibilitytools.d/
_install_steam_compat_tool() {
  local steam_compat_dir="${HOME}/.steam/root/compatibilitytools.d"
  local compat_src="${WB_HOME}/share/compatibilitytools.d/wine-bleeding"
  local compat_link="${steam_compat_dir}/wine-bleeding"

  if [[ ! -d "${compat_src}" ]] && [[ "${DRY_RUN}" -eq 0 ]]; then
    _warn "compat tool source not found: ${compat_src}; run standalone install first."
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  [dry-run] create symlink ${compat_link} -> ${compat_src}"
    return 0
  fi

  mkdir -p "${steam_compat_dir}"

  if [[ -L "${compat_link}" ]]; then
    local cur_target
    cur_target="$(readlink -f "${compat_link}" 2>/dev/null || true)"
    local want_target
    want_target="$(readlink -f "${compat_src}" 2>/dev/null || true)"
    if [[ "${cur_target}" == "${want_target}" ]]; then
      _info "Steam compat symlink already correct: ${compat_link}"
      return 0
    fi
    ln -sfn "${compat_src}" "${compat_link}"
    _info "Relinked Steam compat tool: ${compat_link} -> ${compat_src}"
  elif [[ -e "${compat_link}" ]]; then
    _warn "${compat_link} exists and is not a symlink; skipping."
  else
    ln -s "${compat_src}" "${compat_link}"
    _info "Created Steam compat symlink: ${compat_link} -> ${compat_src}"
  fi
}

# Warn if ~/.local/bin is not in PATH
_check_path_contains_local_bin() {
  local local_bin="${HOME}/.local/bin"
  local path_entry
  local found=0
  while IFS=: read -r -d: path_entry; do
    if [[ "${path_entry}" == "${local_bin}" ]]; then
      found=1
      break
    fi
  done <<< "${PATH}:"

  if [[ "${found}" -eq 0 ]]; then
    _warn "${local_bin} is not in your PATH."
    _warn "Add it by running (or adding to ~/.bashrc / ~/.zshrc):"
    _warn "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
  fi
}

# Post-install smoke test
_post_install_validate() {
  local wb="${WB_HOME}/bin/wb"

  if ! "${wb}" --version >/dev/null 2>&1; then
    _error "Post-install validation FAILED: '${wb} --version' exited non-zero."
    _error "The installation may be incomplete."
    exit 1
  fi

  # wb runtime list is expected to succeed even with no dists installed
  if ! WB_HOME="${WB_HOME}" "${wb}" runtime list >/dev/null 2>&1; then
    _error "Post-install validation FAILED: '${wb} runtime list' exited non-zero."
    exit 1
  fi

  _info "Post-install validation passed (wb --version: $("${wb}" --version))"
}

# ---------------------------------------------------------------------------
# Mode: PortProton plugin install
# ---------------------------------------------------------------------------
_do_portproton_plugin_install() {
  local pp_root
  if [[ -n "${PP_ROOT_OVERRIDE}" ]]; then
    pp_root="${PP_ROOT_OVERRIDE}"
  elif [[ -n "${PORT_WINE_PATH:-}" ]]; then
    pp_root="${PORT_WINE_PATH}"
  else
    pp_root="${HOME}/PortProton"
  fi
  local pp_data="${pp_root}/data"

  _info "Installing wb-runtime ${INSTALL_VERSION} as PortProton plugin at ${pp_root}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  [dry-run] deploy-to-portproton.sh -> ${pp_root}"
    echo "  [dry-run] wb_pp_install_hook ${pp_data}"
    return 0
  fi

  if [[ ! -d "${pp_data}" ]]; then
    _error "PortProton data dir not found: ${pp_data}"
    _error "Is PortProton installed? Use --pp-root to specify the location."
    exit 1
  fi

  # Step 1: Run deploy-to-portproton.sh if it exists (populates PP dist/)
  local deploy_script="${_RUNTIME_DIR}/../tools/deploy-to-portproton.sh"
  if [[ -f "${deploy_script}" ]]; then
    _info "Running deploy-to-portproton.sh..."
    PORT_WINE_PATH="${pp_root}" bash "${deploy_script}" || {
      _warn "deploy-to-portproton.sh exited non-zero; continuing with hook install."
    }
  else
    _info "tools/deploy-to-portproton.sh not found; skipping dist deploy."
  fi

  # Step 2: Copy the wb runtime tree into $PP_ROOT/data/wb/
  #
  # Layout decision (documented):
  #   $PP_ROOT/data/wb/runtime/src/wb     -- the wb binary
  #   $PP_ROOT/data/wb/runtime/src/wb-lib/ -- libs
  #   $PP_ROOT/data/wb/bin/wb             -- symlink -> ../runtime/src/wb
  #
  # This keeps the source layout intact inside PP and allows the symlink
  # to reach wb-lib via its own BASH_SOURCE[0]-based _WB_LIB_DIR discovery.

  local wb_tree="${pp_data}/wb"
  mkdir -p "${wb_tree}/runtime/src/wb-lib" "${wb_tree}/runtime/src/hooks" "${wb_tree}/bin"

  # Copy wb binary and wb-diag
  cp -f "${_SRC_DIR}/wb"      "${wb_tree}/runtime/src/wb"
  cp -f "${_SRC_DIR}/wb-diag" "${wb_tree}/runtime/src/wb-diag" 2>/dev/null || true
  chmod 755 "${wb_tree}/runtime/src/wb"

  # Copy libs
  local lib
  for lib in "${_SRC_DIR}/wb-lib/"*.sh; do
    [[ -f "${lib}" ]] || continue
    cp -f "${lib}" "${wb_tree}/runtime/src/wb-lib/$(basename "${lib}")"
  done

  # Copy hooks
  if [[ -d "${_SRC_DIR}/hooks" ]]; then
    local hook
    for hook in "${_SRC_DIR}/hooks/"*.sh; do
      [[ -f "${hook}" ]] || continue
      cp -f "${hook}" "${wb_tree}/runtime/src/hooks/$(basename "${hook}")"
      chmod 755 "${wb_tree}/runtime/src/hooks/$(basename "${hook}")"
    done
  fi

  # bin/wb symlink -> ../runtime/src/wb (relative)
  local bin_wb="${wb_tree}/bin/wb"
  if [[ -L "${bin_wb}" ]]; then
    local cur_target
    cur_target="$(readlink "${bin_wb}" 2>/dev/null || true)"
    if [[ "${cur_target}" != "../runtime/src/wb" ]]; then
      ln -sfn "../runtime/src/wb" "${bin_wb}"
    fi
  elif [[ ! -e "${bin_wb}" ]]; then
    ln -s "../runtime/src/wb" "${bin_wb}"
  fi

  # Step 3: Call wb_pp_install_hook from M6
  # Source the installer lib
  # shellcheck source=src/wb-lib/wb-pp-installer.sh
  source "${_SRC_DIR}/wb-lib/wb-pp-installer.sh"
  # shellcheck source=src/wb-lib/wb-log.sh
  source "${_SRC_DIR}/wb-lib/wb-log.sh"
  # shellcheck source=src/wb-lib/wb-json.sh
  source "${_SRC_DIR}/wb-lib/wb-json.sh"
  # shellcheck source=src/wb-lib/wb-lock.sh
  source "${_SRC_DIR}/wb-lib/wb-lock.sh"
  # shellcheck source=src/wb-lib/wb-paths.sh
  source "${_SRC_DIR}/wb-lib/wb-paths.sh"
  # shellcheck source=src/wb-lib/wb-components.sh
  source "${_SRC_DIR}/wb-lib/wb-components.sh"
  # shellcheck source=src/wb-lib/wb-reg.sh
  source "${_SRC_DIR}/wb-lib/wb-reg.sh"

  wb_pp_install_hook "${pp_data}"

  _info "PortProton plugin install complete."
  _info "wb binary: ${wb_tree}/bin/wb"
}

# ---------------------------------------------------------------------------
# Mode: uninstall
# ---------------------------------------------------------------------------
_do_uninstall() {
  _info "Uninstalling wb-runtime from ${WB_HOME}..."

  if [[ ! -d "${WB_HOME}" ]]; then
    _info "Nothing to uninstall: ${WB_HOME} does not exist."
    return 0
  fi

  _acquire_install_lock

  if [[ "${PURGE}" -eq 1 ]]; then
    _info "Purge mode: removing all of ${WB_HOME} and ${WB_PROFILE_CONF}"
    _dryrun_or_run "rm -rf ${WB_HOME}" rm -rf "${WB_HOME}"
    if [[ -f "${WB_PROFILE_CONF}" ]]; then
      _dryrun_or_run "rm -f ${WB_PROFILE_CONF}" rm -f "${WB_PROFILE_CONF}"
    fi
  else
    _info "Removing installed files (preserving prefixes/ and profile.conf)"
    _info "Use --purge to remove those too."

    # Remove every entry in WB_HOME except prefixes/
    local entry
    while IFS= read -r entry; do
      local name
      name="$(basename "${entry}")"
      if [[ "${name}" == "prefixes" ]]; then
        _info "Preserving: ${entry}"
        continue
      fi
      if [[ "${name}" == ".install.lock" ]]; then
        # Skip the lock file we currently hold
        continue
      fi
      _dryrun_or_run "rm -rf ${entry}" rm -rf "${entry}"
    done < <(find "${WB_HOME}" -maxdepth 1 -mindepth 1 | sort)
  fi

  # Remove the ~/.local/bin/wb symlink if it points at our install
  local symlink_path="${HOME}/.local/bin/wb"
  if [[ -L "${symlink_path}" ]]; then
    local current_target
    current_target="$(readlink -f "${symlink_path}" 2>/dev/null || true)"
    local our_wb
    our_wb="${WB_HOME}/bin/wb"
    if [[ "${current_target}" == "${our_wb}" || "${current_target}" == "$(readlink -f "${our_wb}" 2>/dev/null || true)" ]]; then
      _dryrun_or_run "rm -f ${symlink_path}" rm -f "${symlink_path}"
      _info "Removed symlink ${symlink_path}"
    fi
  fi

  _release_install_lock
  _info "Uninstall complete."
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${MODE}" in
  standalone)
    _do_standalone_install
    ;;
  portproton-plugin)
    _do_portproton_plugin_install
    ;;
  uninstall)
    _do_uninstall
    ;;
esac

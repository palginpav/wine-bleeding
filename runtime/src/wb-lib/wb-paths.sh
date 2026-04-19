#!/usr/bin/env bash
set -euo pipefail

wb_home() {
  echo "${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
}

wb_xdg_config() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}"
}

wb_xdg_cache() {
  echo "${XDG_CACHE_HOME:-$HOME/.cache}"
}

wb_xdg_runtime() {
  echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
}

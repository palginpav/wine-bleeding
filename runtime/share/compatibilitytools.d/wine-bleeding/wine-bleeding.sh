#!/usr/bin/env bash
# wine-bleeding.sh — Steam Compatibility Tool launcher (M12)
#
# Steam invokes this script according to Proton's interface:
#   wine-bleeding.sh run <exe> [args...]
#   wine-bleeding.sh waitforexitandrun <exe> [args...]
#
# This script delegates entirely to `wb run` and never touches prefix
# internals directly.
set -euo pipefail

# Resolve wb binary: it lives two levels up from this file in source layout,
# or on PATH when installed.
_WB_COMPAT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_resolve_wb() {
  # 1. Try relative source-tree location (runtime/src/wb)
  local candidate="${_WB_COMPAT_SCRIPT_DIR}/../../src/wb"
  if [[ -x "${candidate}" ]]; then
    realpath -m "${candidate}"
    return 0
  fi
  # 2. Try installed location: $WB_HOME/bin/wb
  local wb_home="${WB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/wine-bleeding}"
  candidate="${wb_home}/bin/wb"
  if [[ -x "${candidate}" ]]; then
    echo "${candidate}"
    return 0
  fi
  # 3. Try PATH
  if command -v wb >/dev/null 2>&1; then
    command -v wb
    return 0
  fi
  echo "wine-bleeding.sh: cannot find wb binary" >&2
  return 1
}

WB="$(_resolve_wb)"

verb="${1:-}"
shift || true

case "${verb}" in
  run)
    # exec immediately (no --wait); Steam manages the process lifetime
    exec "${WB}" run "$@"
    ;;
  waitforexitandrun)
    # Steam expects this verb to block until the game exits
    exec "${WB}" run --wait "$@"
    ;;
  "")
    echo "wine-bleeding.sh: verb required (run | waitforexitandrun)" >&2
    exit 1
    ;;
  *)
    echo "wine-bleeding.sh: unknown verb '${verb}'" >&2
    exit 1
    ;;
esac

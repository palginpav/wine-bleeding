#!/usr/bin/env bash
# Deploy wine-bleeding distribution to PortProton and configure a prefix.
# Usage:
#   ./tools/deploy-to-portproton.sh [--dist NAME] [--reapply-only] [--uninstall] [--help]
#   ./tools/deploy-to-portproton.sh [dist-name]   (legacy positional form)
#
# Thin CLI wrapper around wb_pp_publish_dist (runtime/src/wb-lib/wb-pp-installer.sh).
# Legacy form with a bare positional dist-name argument is preserved.

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PP_ROOT="${PORTPROTON_ROOT:-$HOME/PortProton}"
PP_DATA="$PP_ROOT/data"

# Source runtime library.
# shellcheck source=../runtime/src/wb-lib/wb-pp-installer.sh
source "${WINE_ROOT}/runtime/src/wb-lib/wb-pp-installer.sh"
# shellcheck source=../runtime/src/wb-lib/wb-log.sh
source "${WINE_ROOT}/runtime/src/wb-lib/wb-log.sh"
# shellcheck source=../runtime/src/wb-lib/wb-json.sh
source "${WINE_ROOT}/runtime/src/wb-lib/wb-json.sh"
# shellcheck source=../runtime/src/wb-lib/wb-components.sh
source "${WINE_ROOT}/runtime/src/wb-lib/wb-components.sh"

_die() { echo "Error: $*" >&2; exit 1; }

_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [dist-name]

  --dist NAME        Dist directory name under dist/ (default: latest WINE-BLEEDING-*)
  --reapply-only     Skip full copy; only redeploy drifted components
  --uninstall        Remove wb hook from PortProton user.conf
  --help             Show this help

Environment:
  PORTPROTON_ROOT    Override PortProton root (default: ~/PortProton)
EOF
}

DIST_NAME=""
REAPPLY_ONLY=0
DO_UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist)      DIST_NAME="${2:-}"; shift 2 ;;
    --dist=*)    DIST_NAME="${1#--dist=}"; shift ;;
    --reapply-only) REAPPLY_ONLY=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --help|-h)   _usage; exit 0 ;;
    -*)          _die "Unknown option: $1" ;;
    *)           DIST_NAME="$1"; shift ;;
  esac
done

[ -d "$PP_DATA" ] || _die "PortProton not found at $PP_ROOT"

if [[ "$DO_UNINSTALL" -eq 1 ]]; then
  wb_pp_publish_dist "" "$PP_DATA" --uninstall
  exit 0
fi

if [[ -z "$DIST_NAME" ]]; then
  # shellcheck disable=SC2012
  DIST_NAME=$(ls -1d "${WINE_ROOT}/dist/WINE-BLEEDING-"* 2>/dev/null | sort | tail -1 | xargs basename 2>/dev/null || true)
fi

[ -z "$DIST_NAME" ] && _die "No WINE-BLEEDING distribution found in ${WINE_ROOT}/dist/"
DIST_SRC="${WINE_ROOT}/dist/${DIST_NAME}"
[ -d "$DIST_SRC/bin" ] || _die "Distribution not found: $DIST_SRC"

echo "Distribution: $DIST_NAME"
echo "Source:       $DIST_SRC"
echo "PortProton:   $PP_ROOT"

if [[ "$REAPPLY_ONLY" -eq 1 ]]; then
  wb_pp_publish_dist "$DIST_SRC" "$PP_DATA" --reapply-only
else
  wb_pp_publish_dist "$DIST_SRC" "$PP_DATA"
fi

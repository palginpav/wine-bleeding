#!/usr/bin/env bash
# Deploy wine-bleeding distribution to PortProton and configure a prefix.
# Run from Wine source tree root:
#   ./tools/deploy-to-portproton.sh [dist-name]

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PP_ROOT="${PORTPROTON_ROOT:-$HOME/PortProton}"
PP_DATA="$PP_ROOT/data"
PP_DIST="$PP_DATA/dist"
PP_PREFIXES="$PP_DATA/prefixes"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

die() { echo -e "${RED}Error: $*${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }

# --- Find distribution ---
if [ -n "${1:-}" ]; then
    DIST_NAME="$1"
else
    # Auto-detect latest WINE-BLEEDING-* in dist/
    DIST_NAME=$(ls -1d "$WINE_ROOT/dist/WINE-BLEEDING-"* 2>/dev/null | sort | tail -1 | xargs basename 2>/dev/null || true)
fi

[ -z "$DIST_NAME" ] && die "No WINE-BLEEDING distribution found in $WINE_ROOT/dist/"

DIST_SRC="$WINE_ROOT/dist/$DIST_NAME"
[ -d "$DIST_SRC/bin" ] || die "Distribution not found: $DIST_SRC"
[ -d "$PP_DATA" ] || die "PortProton not found at $PP_ROOT"

info "Distribution: $DIST_NAME"
info "Source:       $DIST_SRC"
info "PortProton:   $PP_ROOT"

# --- Deploy distribution ---
DIST_DST="$PP_DIST/$DIST_NAME"
echo ""
if [ -d "$DIST_DST" ]; then
    warn "Distribution already exists in PortProton. Updating..."
    rm -rf "$DIST_DST"
fi

info "Copying distribution to PortProton..."
cp -a "$DIST_SRC" "$DIST_DST"
info "Done. $(find "$DIST_DST" -type f | wc -l) files deployed."

# --- Select prefix ---
echo ""
info "Available prefixes:"
echo "  0) Create new prefix"
i=1
declare -a PLIST=()
for p in "$PP_PREFIXES"/*/; do
    [ -d "$p" ] || continue
    pname=$(basename "$p")
    # Skip entries with newlines or symlink loops
    [[ "$pname" == *$'\n'* ]] && continue
    [ -L "$p" ] && [ ! -d "$p/drive_c" ] && continue
    pver=$(cat "$p/.wine_ver" 2>/dev/null || echo "unknown")
    printf "  %d) %-20s [%s]\n" "$i" "$pname" "$pver"
    PLIST+=("$pname")
    ((i++))
done

echo ""
read -rp "Select prefix [0-$((i-1))]: " choice

if [ "$choice" = "0" ]; then
    read -rp "New prefix name: " PREFIX_NAME
    [ -z "$PREFIX_NAME" ] && die "Empty prefix name"
    mkdir -p "$PP_PREFIXES/$PREFIX_NAME"
else
    idx=$((choice - 1))
    [ "$idx" -ge 0 ] && [ "$idx" -lt "${#PLIST[@]}" ] || die "Invalid choice"
    PREFIX_NAME="${PLIST[$idx]}"
fi

PREFIX_DIR="$PP_PREFIXES/$PREFIX_NAME"
info "Prefix: $PREFIX_NAME ($PREFIX_DIR)"

# --- Update prefix ---
echo ""

# 1. Set wine version
echo "$DIST_NAME" > "$PREFIX_DIR/.wine_ver"
info "Set .wine_ver = $DIST_NAME"

# 2. Install mono into prefix
MONO_SRC="$DIST_DST/share/wine/mono"
MONO_VER=$(ls -1 "$MONO_SRC" 2>/dev/null | head -1)
if [ -n "$MONO_VER" ]; then
    MONO_DST="$PREFIX_DIR/drive_c/windows/mono/mono-2.0"
    if [ -d "$MONO_DST" ]; then
        warn "Removing old mono from prefix..."
        rm -rf "$MONO_DST"
    fi
    mkdir -p "$MONO_DST"
    info "Installing $MONO_VER to prefix..."
    cp -a "$MONO_SRC/$MONO_VER"/* "$MONO_DST"/
    info "Mono installed ($(find "$MONO_DST" -name '*.dll' | wc -l) DLLs)"
else
    warn "No mono found in distribution"
fi

# 3. Copy override DLLs (vcomp builtins, etc.)
WINE_SYS32="$PREFIX_DIR/drive_c/windows/system32"
if [ -d "$WINE_SYS32" ]; then
    # Copy Wine builtin vcomp DLLs to replace any native overrides
    for dll in vcomp vcomp90 vcomp100 vcomp110 vcomp120 vcomp140 cryptbase; do
        src="$DIST_DST/lib/wine/x86_64-windows/${dll}.dll"
        if [ -f "$src" ]; then
            cp -f "$src" "$WINE_SYS32/${dll}.dll"
        fi
    done
    info "Updated builtin DLL overrides in system32"
fi

# 4. Initialize prefix (start services.exe via wineboot --init)
"$DIST_DST/bin/wineserver" -k 2>/dev/null || true
sleep 1
export WINEPREFIX="$PREFIX_DIR"
export WINEDEBUG=-all
info "Initializing prefix (starting services.exe)..."
"$DIST_DST/bin/wineboot" --init 2>/dev/null || true
sleep 2
"$DIST_DST/bin/wineserver" -k 2>/dev/null || true

# 5. Update shared mono if PortProton uses symlinked mono
SHARED_MONO="$(dirname "$PP_DATA")/data/tmp/mono/$MONO_VER"
if [ -d "$SHARED_MONO" ] && [ -d "$MONO_SRC/$MONO_VER" ]; then
    info "Updating shared PortProton mono..."
    rsync -a --update "$MONO_SRC/$MONO_VER/" "$SHARED_MONO/" 2>/dev/null \
        || cp -a "$MONO_SRC/$MONO_VER/"* "$SHARED_MONO/" 2>/dev/null
    info "Shared mono fully synced"
fi

echo ""
info "=== Deployment complete ==="
info "Distribution: $DIST_NAME"
info "Prefix:       $PREFIX_NAME"
info "Wine:         $DIST_DST/bin/wine"
info "WINEPREFIX:   $PREFIX_DIR"
echo ""
info "To run an application:"
echo "  WINEPREFIX=$PREFIX_DIR $DIST_DST/bin/wine <app.exe>"

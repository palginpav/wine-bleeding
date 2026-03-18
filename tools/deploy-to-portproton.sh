#!/usr/bin/env bash
# Deploy wine-bleeding distribution to PortProton and configure a prefix.
# Usage:
#   ./tools/deploy-to-portproton.sh [dist-name]
#
# Wine now deploys real builtin DLLs to prefix automatically (no fake DLLs).
# This script copies dist to PortProton, creates/updates a prefix via wineboot,
# and installs mono.

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PP_ROOT="${PORTPROTON_ROOT:-$HOME/PortProton}"
PP_DATA="$PP_ROOT/data"
PP_DIST="$PP_DATA/dist"
PP_PREFIXES="$PP_DATA/prefixes"
PP_TMP="$PP_DATA/tmp"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

die() { echo -e "${RED}Error: $*${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }

# --- Find distribution ---
if [ -n "${1:-}" ]; then
    DIST_NAME="$1"
else
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
    [[ "$pname" == *$'\n'* ]] && continue
    [ -L "$p" ] && [ ! -d "$p/drive_c" ] && continue
    pver=$(cat "$p/.wine_ver" 2>/dev/null || echo "unknown")
    printf "  %d) %-20s [%s]\n" "$i" "$pname" "$pver"
    PLIST+=("$pname")
    ((i++))
done

echo ""
read -rp "Select prefix [0-$((i-1))]: " choice

NEW_PREFIX=false
if [ "$choice" = "0" ]; then
    read -rp "New prefix name: " PREFIX_NAME
    [ -z "$PREFIX_NAME" ] && die "Empty prefix name"
    NEW_PREFIX=true
else
    idx=$((choice - 1))
    [ "$idx" -ge 0 ] && [ "$idx" -lt "${#PLIST[@]}" ] || die "Invalid choice"
    PREFIX_NAME="${PLIST[$idx]}"
fi

PREFIX_DIR="$PP_PREFIXES/$PREFIX_NAME"
info "Prefix: $PREFIX_NAME ($PREFIX_DIR)"

# ============================================================
# Create or update prefix
# ============================================================
# Wine's deploy_builtin_dlls() automatically copies all real builtin
# DLLs from dist to system32/syswow64 before wineboot runs.
# No manual DLL copying needed — wineboot --init handles everything.
# ============================================================
echo ""

if $NEW_PREFIX; then
    mkdir -p "$PREFIX_DIR"
    info "Creating new prefix via wineboot --init..."
    info "(Wine will deploy ~1500 real builtin DLLs automatically)"
fi

# Set wine version marker
echo "$DIST_NAME" > "$PREFIX_DIR/.wine_ver"
info "Set .wine_ver = $DIST_NAME"

# Install mono into prefix (before wineboot so it's available during init)
MONO_SRC="$DIST_DST/share/wine/mono"
MONO_VER=$(ls -1d "$MONO_SRC"/wine-mono-* 2>/dev/null | sort -V | tail -1 | xargs basename 2>/dev/null || true)
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

# Run wineboot to initialize/update prefix
# deploy_builtin_dlls() in ntdll runs automatically before wineboot,
# deploying all real builtin PEs to system32 and syswow64.
"$DIST_DST/bin/wineserver" -k 2>/dev/null || true
sleep 1
export WINEPREFIX="$PREFIX_DIR"
export WINEDEBUG=-all

if $NEW_PREFIX; then
    info "Running wineboot --init (builtin DLLs + registry + COM registration)..."
    "$DIST_DST/bin/wine" wineboot --init 2>/dev/null || true
else
    info "Running wineboot -u (updating prefix)..."
    "$DIST_DST/bin/wine" wineboot -u 2>/dev/null || true
fi
sleep 2
"$DIST_DST/bin/wineserver" -k 2>/dev/null || true

# Clean up autostart entries from template (Epic Games, etc.)
if $NEW_PREFIX && [ -f "$PREFIX_DIR/user.reg" ]; then
    sed -i '/"EpicGamesLauncher"/d' "$PREFIX_DIR/user.reg"
    sed -i '/"Steam"/d' "$PREFIX_DIR/user.reg"
fi

# Verify prefix
echo ""
VERIFY_OK=true
[ -d "$PREFIX_DIR/drive_c/windows/system32" ] || { warn "Missing system32"; VERIFY_OK=false; }
[ -f "$PREFIX_DIR/system.reg" ] || { warn "Missing system.reg"; VERIFY_OK=false; }
[ -f "$PREFIX_DIR/user.reg" ] || { warn "Missing user.reg"; VERIFY_OK=false; }

# Count real builtins (not fakedlls) in system32
SYS32_COUNT=$(ls "$PREFIX_DIR/drive_c/windows/system32/"*.dll 2>/dev/null | wc -l)
SYS64_COUNT=$(ls "$PREFIX_DIR/drive_c/windows/syswow64/"*.dll 2>/dev/null | wc -l)
info "system32: $SYS32_COUNT DLLs, syswow64: $SYS64_COUNT DLLs"

if $VERIFY_OK && [ "$SYS32_COUNT" -gt 100 ]; then
    info "Prefix verified OK (real builtins deployed)"
else
    warn "Prefix may be incomplete — check system32 contents"
fi

# Update shared PortProton mono
SHARED_MONO="$PP_TMP/mono/$MONO_VER"
if [ -n "$MONO_VER" ] && [ -d "$SHARED_MONO" ] && [ -d "$MONO_SRC/$MONO_VER" ]; then
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

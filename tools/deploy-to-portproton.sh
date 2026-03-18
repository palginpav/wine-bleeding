#!/usr/bin/env bash
# Deploy wine-bleeding distribution to PortProton and configure a prefix.
# Usage:
#   ./tools/deploy-to-portproton.sh [dist-name]
#
# Creates proper prefixes using PortProton's default_pfx.tar.xz as base,
# syncs system DLLs, mono, and shared mono.

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PP_ROOT="${PORTPROTON_ROOT:-$HOME/PortProton}"
PP_DATA="$PP_ROOT/data"
PP_DIST="$PP_DATA/dist"
PP_PREFIXES="$PP_DATA/prefixes"
PP_PLUGINS="$PP_DATA/tmp/plugins_v20"
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
# Create new prefix from PortProton's default_pfx template
# ============================================================
if $NEW_PREFIX; then
    echo ""
    DEFAULT_PFX="$PP_PLUGINS/default_pfx.tar.xz"
    if [ -f "$DEFAULT_PFX" ]; then
        info "Creating prefix from PortProton default template..."
        mkdir -p "$PREFIX_DIR"
        tar xf "$DEFAULT_PFX" -C "$PREFIX_DIR"
        info "Template extracted"
    else
        warn "No default_pfx.tar.xz found — creating minimal prefix..."
        mkdir -p "$PREFIX_DIR/drive_c/windows/system32"
        mkdir -p "$PREFIX_DIR/drive_c/windows/syswow64"
        mkdir -p "$PREFIX_DIR/drive_c/Program Files"
        mkdir -p "$PREFIX_DIR/drive_c/Program Files (x86)"
        mkdir -p "$PREFIX_DIR/drive_c/ProgramData"
        mkdir -p "$PREFIX_DIR/drive_c/users/steamuser/AppData/Local/Temp"
        mkdir -p "$PREFIX_DIR/drive_c/users/steamuser/Desktop"
        mkdir -p "$PREFIX_DIR/drive_c/users/steamuser/Documents"
        mkdir -p "$PREFIX_DIR/drive_c/users/steamuser/Temp"
    fi

    # Create dosdevices
    mkdir -p "$PREFIX_DIR/dosdevices"
    ln -sfn "../drive_c" "$PREFIX_DIR/dosdevices/c:"
    ln -sfn "/" "$PREFIX_DIR/dosdevices/z:"

    # Clean up autostart entries from template (Epic Games, etc.)
    if [ -f "$PREFIX_DIR/user.reg" ]; then
        sed -i '/"EpicGamesLauncher"/d' "$PREFIX_DIR/user.reg"
        sed -i '/"Steam"/d' "$PREFIX_DIR/user.reg"
    fi
fi

# ============================================================
# Update prefix configuration
# ============================================================
echo ""

# 1. Set wine version
echo "$DIST_NAME" > "$PREFIX_DIR/.wine_ver"
info "Set .wine_ver = $DIST_NAME"

# 2. Sync critical system executables from dist
#    Wine 11+ loads builtins from dist, but some exe are loaded from prefix
WINE_SYS32="$PREFIX_DIR/drive_c/windows/system32"
WINE_SYS64="$DIST_DST/lib/wine/x86_64-windows"
WINE_SYS32_32="$PREFIX_DIR/drive_c/windows/syswow64"
WINE_SYS32_SRC="$DIST_DST/lib/wine/i386-windows"

# Wine loads builtins from dist, NOT from prefix system32.
# Prefix system32 only needs fakedlls (from default_pfx template).
# Only copy DLLs that must override template versions.
if [ -d "$WINE_SYS32" ] && [ -d "$WINE_SYS64" ]; then
    for dll in vcomp vcomp90 vcomp100 vcomp110 vcomp120 vcomp140 \
               cryptbase; do
        [ -f "$WINE_SYS64/${dll}.dll" ] && cp -f "$WINE_SYS64/${dll}.dll" "$WINE_SYS32/${dll}.dll"
    done
    if [ -d "$WINE_SYS32_32" ] && [ -d "$WINE_SYS32_SRC" ]; then
        for dll in vcomp vcomp90 vcomp100 vcomp110 vcomp120 vcomp140 \
                   cryptbase; do
            [ -f "$WINE_SYS32_SRC/${dll}.dll" ] && cp -f "$WINE_SYS32_SRC/${dll}.dll" "$WINE_SYS32_32/${dll}.dll"
        done
    fi
    info "Updated DLL overrides in prefix"
fi

# 3. Install mono into prefix
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

# 4. Update prefix via wineboot
# Use -r (restart) for template-based prefixes, -u (update) for existing ones.
# Never use --init: it requires rundll32+setupapi which need fakedlls first.
"$DIST_DST/bin/wineserver" -k 2>/dev/null || true
sleep 1
export WINEPREFIX="$PREFIX_DIR"
export WINEDEBUG=-all
info "Initializing prefix..."
"$DIST_DST/bin/wine" wineboot -r 2>/dev/null || true
sleep 2
"$DIST_DST/bin/wineserver" -k 2>/dev/null || true

# 5. Verify prefix
VERIFY_OK=true
[ -d "$PREFIX_DIR/drive_c/windows/system32" ] || { warn "Missing system32"; VERIFY_OK=false; }
[ -f "$PREFIX_DIR/system.reg" ] || { warn "Missing system.reg"; VERIFY_OK=false; }
[ -f "$PREFIX_DIR/user.reg" ] || { warn "Missing user.reg"; VERIFY_OK=false; }
$VERIFY_OK && info "Prefix verified OK"

# 6. Update shared PortProton mono
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

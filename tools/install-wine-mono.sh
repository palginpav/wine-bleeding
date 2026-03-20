#!/usr/bin/env bash
# Build wine-mono from palginpav forks and install into a Wine dist (share/wine/mono).
# Forks contain all patches as proper commits on the wine-bleeding branch.
# Run from Wine source tree root:
#   ./tools/install-wine-mono.sh [dist-path]

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_DIR="${DEPS_DIR:-$WINE_ROOT/build-deps}"
MONO_SRC_DIR="$DEPS_DIR/wine-mono"
MSCOREE_HEADER="$WINE_ROOT/dlls/mscoree/mscoree_private.h"

# Fork URLs — patches live as commits on wine-bleeding branches
FORK_WINE_MONO="https://github.com/palginpav/wine-mono.git"
FORK_MONO="https://github.com/palginpav/mono.git"
FORK_WPF="https://github.com/palginpav/wpf.git"
FORK_WINFORMS="https://github.com/palginpav/winforms.git"
FORK_COREFX="https://github.com/palginpav/corefx.git"
FORK_BRANCH="wine-bleeding"

for cmd in git make tar sed; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: required command not found: $cmd" >&2
        exit 1
    }
done

if [ ! -f "$MSCOREE_HEADER" ]; then
    echo "Error: mscoree header not found: $MSCOREE_HEADER" >&2
    exit 1
fi

WINE_MONO_VERSION="$(sed -n 's/^#define WINE_MONO_VERSION "\(.*\)"/\1/p' "$MSCOREE_HEADER" | head -1)"
if [ -z "$WINE_MONO_VERSION" ]; then
    echo "Error: failed to read WINE_MONO_VERSION from $MSCOREE_HEADER" >&2
    exit 1
fi

if [ -n "${1:-}" ]; then
    DIST_DIR="$(cd "$1" && pwd)"
else
    DIST_DIR=""
    DIST_DIR="$(find "$WINE_ROOT"/dist -maxdepth 1 -type d -name 'WINE-BLEEDING-*' 2>/dev/null | sort -V | tail -n1 || true)"
    if [ -z "$DIST_DIR" ]; then
        echo "Error: dist not found (WINE-BLEEDING-*). Pass explicit path: $0 /path/to/dist" >&2
        exit 1
    fi
fi

echo "Dist: $DIST_DIR"
echo "Target Wine Mono version: $WINE_MONO_VERSION"

# Clone or update wine-mono from our fork
mkdir -p "$DEPS_DIR"
if [ ! -d "$MONO_SRC_DIR/.git" ]; then
    echo "Cloning wine-mono from fork..."
    git clone "$FORK_WINE_MONO" "$MONO_SRC_DIR"
fi

cd "$MONO_SRC_DIR"

# Ensure our fork is a remote
git remote set-url origin "$FORK_WINE_MONO" 2>/dev/null || true
git fetch --tags origin >/dev/null 2>&1 || true

# Checkout our wine-bleeding branch
echo "Checking out $FORK_BRANCH..."
git checkout -f "$FORK_BRANCH" >/dev/null 2>&1 || {
    git fetch origin "$FORK_BRANCH"
    git checkout -f "$FORK_BRANCH" >/dev/null
}
git reset --hard "origin/$FORK_BRANCH" 2>/dev/null || true

# Point submodules to our forks
setup_fork_remote() {
    local submodule="$1"
    local fork_url="$2"
    if [ -d "$MONO_SRC_DIR/$submodule/.git" ] || [ -f "$MONO_SRC_DIR/$submodule/.git" ]; then
        git -C "$MONO_SRC_DIR/$submodule" remote set-url origin "$fork_url" 2>/dev/null || true
    fi
}

echo "Syncing full submodule tree..."
# Clean build artifacts from submodules before update (wpf generates files during build)
for sub in mono wpf winforms; do
    [ -d "$MONO_SRC_DIR/$sub" ] && git -C "$MONO_SRC_DIR/$sub" checkout -- . 2>/dev/null
    [ -d "$MONO_SRC_DIR/$sub" ] && git -C "$MONO_SRC_DIR/$sub" clean -fd 2>/dev/null
done
# Also clean corefx (sub-submodule of mono)
COREFX_DIR="$MONO_SRC_DIR/mono/external/corefx"
if [ -d "$COREFX_DIR" ]; then
    git -C "$COREFX_DIR" checkout -- . 2>/dev/null
    git -C "$COREFX_DIR" clean -fd 2>/dev/null
fi
GIT_TERMINAL_PROMPT=0 git submodule sync --recursive >/dev/null 2>&1 || true
GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive

# Ensure forked submodules are on wine-bleeding branch
for sub in mono wpf winforms; do
    if [ -d "$MONO_SRC_DIR/$sub" ]; then
        cd "$MONO_SRC_DIR/$sub"
        # Fetch wine-bleeding from fork
        git fetch origin "$FORK_BRANCH" 2>/dev/null || true
        # Check if current HEAD matches origin/wine-bleeding
        local_head="$(git rev-parse HEAD)"
        remote_head="$(git rev-parse "origin/$FORK_BRANCH" 2>/dev/null || echo "")"
        if [ -n "$remote_head" ] && [ "$local_head" != "$remote_head" ]; then
            echo "Updating $sub to origin/$FORK_BRANCH..."
            git checkout -f "$FORK_BRANCH" 2>/dev/null || git checkout -f "origin/$FORK_BRANCH" 2>/dev/null || true
        fi
        cd "$MONO_SRC_DIR"
    fi
done

# Handle corefx fork (sub-submodule of mono)
if [ -d "$COREFX_DIR" ]; then
    setup_fork_remote "mono/external/corefx" "$FORK_COREFX"
    cd "$COREFX_DIR"
    git fetch origin "$FORK_BRANCH" 2>/dev/null || true
    local_head="$(git rev-parse HEAD)"
    remote_head="$(git rev-parse "origin/$FORK_BRANCH" 2>/dev/null || echo "")"
    if [ -n "$remote_head" ] && [ "$local_head" != "$remote_head" ]; then
        echo "Updating corefx to origin/$FORK_BRANCH..."
        git checkout -f "$FORK_BRANCH" 2>/dev/null || git checkout -f "origin/$FORK_BRANCH" 2>/dev/null || true
    fi
    cd "$MONO_SRC_DIR"
fi

# No patch application needed — patches are commits in fork branches

SRC_REV="$(git rev-parse HEAD)"
MONO_SUBMODULE_REV="$(git -C "$MONO_SRC_DIR/mono" rev-parse HEAD)"
WPF_SUBMODULE_REV="$(git -C "$MONO_SRC_DIR/wpf" rev-parse HEAD)"
WINFORMS_SUBMODULE_REV="$(git -C "$MONO_SRC_DIR/winforms" rev-parse HEAD)"
COREFX_SUBMODULE_REV="$(git -C "$MONO_SRC_DIR/mono/external/corefx" rev-parse HEAD 2>/dev/null || echo "none")"
BUILD_ID="${WINE_MONO_VERSION}|${SRC_REV}|${MONO_SUBMODULE_REV}|${WPF_SUBMODULE_REV}|${WINFORMS_SUBMODULE_REV}|${COREFX_SUBMODULE_REV}"
BUILD_STAMP="$DEPS_DIR/.wine-mono-build-id"
TARBALL="$MONO_SRC_DIR/wine-mono-${WINE_MONO_VERSION}-x86.tar.xz"

NEED_BUILD=1
if [ "${WINE_MONO_FORCE_REBUILD:-0}" = "1" ]; then
    NEED_BUILD=1
elif [ -f "$BUILD_STAMP" ] && [ -f "$TARBALL" ] && [ "$(tr -d '\r\n' < "$BUILD_STAMP")" = "$BUILD_ID" ]; then
    NEED_BUILD=0
fi

if [ "$NEED_BUILD" -eq 1 ]; then
    if ! command -v libtoolize >/dev/null 2>&1 && ! command -v glibtoolize >/dev/null 2>&1; then
        echo "Error: required command not found for wine-mono build: libtoolize (or glibtoolize)." >&2
        echo "Install libtool (e.g. apt install libtool / dnf install libtool)." >&2
        exit 1
    fi
    # Clean stale build artifacts so make sees changed sources after submodule update.
    # git checkout/submodule update don't update mtimes, so make may skip recompilation.
    rm -rf "$MONO_SRC_DIR/image" "$MONO_SRC_DIR/wine-mono-${WINE_MONO_VERSION}-x86.tar.xz"
    find "$MONO_SRC_DIR/mono" -name '*.c' -o -name '*.h' -o -name '*.cs' | xargs touch 2>/dev/null || true
    JOBS="$(nproc 2>/dev/null || echo 4)"
    echo "Building wine-mono tarball (MSI_VERSION=$WINE_MONO_VERSION, -j$JOBS)..."
    make -j"$JOBS" bin MSI_VERSION="$WINE_MONO_VERSION"
    if [ ! -f "$TARBALL" ]; then
        echo "Error: expected tarball not found after build: $TARBALL" >&2
        exit 1
    fi
    printf '%s\n' "$BUILD_ID" > "$BUILD_STAMP"
else
    echo "wine-mono build cache is up to date, skipping rebuild."
fi

MONO_DIST_ROOT="$DIST_DIR/share/wine/mono"
MONO_DIST_DIR="$MONO_DIST_ROOT/wine-mono-$WINE_MONO_VERSION"
mkdir -p "$MONO_DIST_ROOT"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
tar -xf "$TARBALL" -C "$tmpdir"
srcdir="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [ -z "$srcdir" ] || [ ! -d "$srcdir" ]; then
    echo "Error: failed to detect extracted wine-mono directory in $TARBALL" >&2
    exit 1
fi

rm -rf "$MONO_DIST_DIR"
mv "$srcdir" "$MONO_DIST_DIR"

if [ ! -f "$MONO_DIST_DIR/support/winemono-support.msi" ]; then
    echo "Error: support MSI not found after install: $MONO_DIST_DIR/support/winemono-support.msi" >&2
    exit 1
fi

if ! find "$MONO_DIST_DIR/bin" -maxdepth 1 -type f -name 'libmono-2.0*.dll' | grep -q .; then
    echo "Error: mono runtime DLL not found in $MONO_DIST_DIR/bin" >&2
    exit 1
fi

# Strip "Wine builtin DLL" marker from mono native DLLs.  Without this,
# Wine's PE loader tries to find a matching .so backup and fails with
# STATUS_BAD_IMAGE_FORMAT when loading via P/Invoke dllmap paths.
for arch_dir in "$MONO_DIST_DIR/lib/x86" "$MONO_DIST_DIR/lib/x86_64"; do
    [ -d "$arch_dir" ] || continue
    for dll in "$arch_dir"/*.dll; do
        [ -f "$dll" ] || continue
        python3 -c "
with open('$dll', 'r+b') as f:
    f.seek(0x40)
    if f.read(16) == b'Wine builtin DLL':
        f.seek(0x40)
        f.write(b'\x00' * 16)
" 2>/dev/null || true
    done
done

# Copy native DLLs so mono P/Invoke finds them without dllmap.
# Mono's dllmap $mono_libdir doesn't resolve at runtime on Wine, and
# Wine's Z:-drive doesn't follow relative Unix symlinks.
# GAC gets x86_64 copies (mono runs .NET EXEs as 64-bit on 64-bit hosts).
# lib/mono/4.5 gets x86 copies (WoW64 32-bit processes search there too).
GAC_BASE="$MONO_DIST_DIR/lib/mono/gac"
MONO45_DIR="$MONO_DIST_DIR/lib/mono/4.5"
find "$GAC_BASE" -maxdepth 3 -type l -name "*.dll" -delete 2>/dev/null || true
# x86 → lib/mono/4.5 (for WoW64 32-bit processes)
if [ -d "$MONO_DIST_DIR/lib/x86" ]; then
    for dll in "$MONO_DIST_DIR/lib/x86"/*.dll; do
        [ -f "$dll" ] || continue
        cp -f "$dll" "$MONO45_DIR/$(basename "$dll")"
    done
fi
# x86_64 → every GAC version dir (for 64-bit processes)
if [ -d "$MONO_DIST_DIR/lib/x86_64" ]; then
    for dll in "$MONO_DIST_DIR/lib/x86_64"/*.dll; do
        [ -f "$dll" ] || continue
        name=$(basename "$dll")
        find "$GAC_BASE" -mindepth 2 -maxdepth 2 -type d | while read ver_dir; do
            cp -f "$dll" "$ver_dir/$name"
        done
    done
fi

echo "Installed patched local wine-mono to:"
echo "  $MONO_DIST_DIR"

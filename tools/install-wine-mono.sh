#!/usr/bin/env bash
# Build patched local wine-mono and install it into a Wine dist (share/wine/mono).
# Run from Wine source tree root:
#   ./tools/install-wine-mono.sh [dist-path]

set -euo pipefail

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_DIR="${DEPS_DIR:-$WINE_ROOT/build-deps}"
MONO_SRC_DIR="$DEPS_DIR/wine-mono"
MONO_PATCH_DIR="$WINE_ROOT/tools/patches"
MONO_PATCHES=(
    "$MONO_PATCH_DIR/wine-mono-iconconverter.patch"
    "$MONO_PATCH_DIR/wine-mono-cabarc-ascii-path.patch"
)
MSCOREE_HEADER="$WINE_ROOT/dlls/mscoree/mscoree_private.h"

for cmd in git make tar sed; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: required command not found: $cmd" >&2
        exit 1
    }
done

for patch in "${MONO_PATCHES[@]}"; do
    if [ ! -f "$patch" ]; then
        echo "Error: patch file not found: $patch" >&2
        exit 1
    fi
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

MONO_TAG="wine-mono-$WINE_MONO_VERSION"

if [ -n "${1:-}" ]; then
    DIST_DIR="$(cd "$1" && pwd)"
else
    DIST_DIR=""
    DIST_DIR="$(ls -d "$WINE_ROOT"/dist/WINE-BLEEDING-* 2>/dev/null | sort -V | tail -n1 || true)"
    if [ -z "$DIST_DIR" ]; then
        echo "Error: dist not found (WINE-BLEEDING-*). Pass explicit path: $0 /path/to/dist" >&2
        exit 1
    fi
fi

echo "Dist: $DIST_DIR"
echo "Target Wine Mono version: $WINE_MONO_VERSION"

mkdir -p "$DEPS_DIR"
if [ ! -d "$MONO_SRC_DIR/.git" ]; then
    echo "Cloning wine-mono (GitHub mirror)..."
    git clone https://github.com/wine-mono/wine-mono.git "$MONO_SRC_DIR"
fi

cd "$MONO_SRC_DIR"
git fetch --tags origin >/dev/null 2>&1 || true

if git show-ref --verify --quiet "refs/tags/$MONO_TAG"; then
    echo "Checking out $MONO_TAG..."
    git checkout -f "$MONO_TAG" >/dev/null
else
    origin_head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -z "$origin_head" ] && origin_head="origin/main"
    echo "Warning: tag $MONO_TAG not found; using $origin_head" >&2
    git checkout -f "${origin_head#origin/}" >/dev/null 2>&1 || git checkout -f "$origin_head" >/dev/null
fi

echo "Syncing full submodule tree..."
GIT_TERMINAL_PROMPT=0 git submodule sync --recursive >/dev/null 2>&1 || true
GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive
# Ensure submodule worktrees are fully populated after switching tags.
git submodule foreach --recursive 'git reset --hard -q || true'

apply_patch_if_needed() {
    local patch_file="$1"
    local patch_name
    patch_name="$(basename "$patch_file")"
    if git apply --check "$patch_file" >/dev/null 2>&1; then
        echo "Applying $patch_name..."
        git apply "$patch_file"
    elif git apply --reverse --check "$patch_file" >/dev/null 2>&1; then
        echo "$patch_name already applied."
    else
        echo "Error: unable to apply $patch_name cleanly." >&2
        exit 1
    fi
}

for patch in "${MONO_PATCHES[@]}"; do
    apply_patch_if_needed "$patch"
done

PATCH_HASH="$(sha256sum "${MONO_PATCHES[@]}" | sha256sum | awk '{print $1}')"
SRC_REV="$(git rev-parse HEAD)"
MONO_SUBMODULE_REV="$(git -C "$MONO_SRC_DIR/mono" rev-parse HEAD)"
BUILD_ID="${WINE_MONO_VERSION}|${SRC_REV}|${MONO_SUBMODULE_REV}|${PATCH_HASH}"
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

echo "Installed patched local wine-mono to:"
echo "  $MONO_DIST_DIR"

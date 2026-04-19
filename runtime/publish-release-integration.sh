#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# publish-release-integration.sh — assemble a self-contained installer tarball
#
# Usage:
#   ./publish-release-integration.sh \
#       --dist-dir /path/to/dist/WINE-BLEEDING-DDMMYYYY \
#       [--out /path/to/output-dir]
#
# Outputs:
#   <out>/wine-bleeding-<VER>-installer.tar.xz
#   SHA256 of the tarball to stdout (for release notes)
#
# The tarball contains:
#   runtime/          (the full runtime tree, sans tests/vendor/)
#   dist/<NAME>/      (the specified Wine dist)
#   README.md         (install instructions)
#   INSTALL           (plain text quickstart)
#
# Standalone; no dependency on tools/publish-release.sh changes.
# ---------------------------------------------------------------------------

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_RUNTIME_DIR="${_SCRIPT_DIR}"

usage() {
  cat <<'EOF'
Usage:
  publish-release-integration.sh --dist-dir PATH [--out DIR]

Options:
  --dist-dir PATH   Path to the WINE-BLEEDING-DDMMYYYY dist directory (required)
  --out DIR         Output directory for the tarball (default: current dir)
  --help            Show this message
EOF
}

fail() { echo "error: $*" >&2; exit 1; }

DIST_DIR=""
OUT_DIR="${PWD}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist-dir)   DIST_DIR="${2:-}"; shift 2 ;;
    --dist-dir=*) DIST_DIR="${1#--dist-dir=}"; shift ;;
    --out)        OUT_DIR="${2:-}"; shift 2 ;;
    --out=*)      OUT_DIR="${1#--out=}"; shift ;;
    --help|-h)    usage; exit 0 ;;
    *) fail "unknown option '$1'" ;;
  esac
done

[[ -n "${DIST_DIR}" ]] || fail "--dist-dir is required"
[[ -d "${DIST_DIR}" ]] || fail "dist-dir not found: ${DIST_DIR}"

DIST_NAME="$(basename "${DIST_DIR}")"
[[ "${DIST_NAME}" == WINE-BLEEDING-* ]] || \
  fail "dist-dir basename must match WINE-BLEEDING-*, got: ${DIST_NAME}"

# Derive version: strip WINE-BLEEDING- prefix and use date stamp as version
VER="${DIST_NAME#WINE-BLEEDING-}"
TARBALL_NAME="wine-bleeding-${VER}-installer.tar.xz"
TARBALL_PATH="${OUT_DIR}/${TARBALL_NAME}"

mkdir -p "${OUT_DIR}"

# Build a staging area. chmod 755 so the tarball root is group/other-readable.
STAGE="$(mktemp -d)"
chmod 755 "${STAGE}"
trap 'rm -rf "${STAGE}"' EXIT

mkdir -p "${STAGE}/runtime" "${STAGE}/dist/${DIST_NAME}"

# Copy runtime tree. Exclude tests/ entirely from releases — end-users don't
# run bats; keeping ~139 test files in the release expands attack surface and
# tarball size for no user-facing benefit.
rsync -a --exclude='tests/' "${_RUNTIME_DIR}/" "${STAGE}/runtime/"

# Copy the specified dist
cp -a "${DIST_DIR}/." "${STAGE}/dist/${DIST_NAME}/"

# Write README.md
cat > "${STAGE}/README.md" <<READMEEOF
# wine-bleeding ${VER} installer

## Quick install (standalone)

\`\`\`bash
tar -xf ${TARBALL_NAME}
cd wine-bleeding-${VER}-installer/
./runtime/install.sh
\`\`\`

This installs wb-runtime to \`~/.local/share/wine-bleeding\` and creates
a \`~/.local/bin/wb\` symlink.

## PortProton plugin install

\`\`\`bash
./runtime/install.sh --portproton-plugin [--pp-root ~/PortProton]
\`\`\`

## Uninstall

\`\`\`bash
./runtime/install.sh --uninstall          # preserves your prefixes
./runtime/install.sh --uninstall --purge  # removes everything
\`\`\`

See \`./runtime/install.sh --help\` for full options.
READMEEOF

# Write INSTALL (plain text)
cat > "${STAGE}/INSTALL" <<INSTALLEOF
wine-bleeding ${VER} installer
================================

1. Extract:   tar -xf ${TARBALL_NAME}
2. Install:   cd wine-bleeding-${VER}-installer && ./runtime/install.sh
3. Add PATH:  export PATH="\$HOME/.local/bin:\$PATH"   (if not already)
4. Test:      wb --version

The Wine dist is bundled inside dist/${DIST_NAME}/ and will be
activated automatically during install.

For plugin mode:  ./runtime/install.sh --portproton-plugin
For uninstall:    ./runtime/install.sh --uninstall
INSTALLEOF

# Pack the tarball. Use an absolute staging path so a pre-existing directory
# of the same basename in CWD is never silently clobbered.
INSTALLER_DIR_NAME="wine-bleeding-${VER}-installer"
INSTALLER_PARENT="$(dirname "${STAGE}")"
INSTALLER_DIR="${INSTALLER_PARENT}/${INSTALLER_DIR_NAME}.$$"
mv "${STAGE}" "${INSTALLER_DIR}"
trap 'rm -rf "${INSTALLER_DIR}"' EXIT

# Rename inside the tarball to drop the PID suffix.
tar -cJf "${TARBALL_PATH}" \
  -C "${INSTALLER_PARENT}" \
  --transform "s|^$(basename "${INSTALLER_DIR}")|${INSTALLER_DIR_NAME}|" \
  "$(basename "${INSTALLER_DIR}")"

# Emit SHA256 to stdout
sha256sum "${TARBALL_PATH}" | awk '{print $1}'

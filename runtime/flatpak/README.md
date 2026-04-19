# wb Flatpak packaging (M14)

This directory contains the Flatpak manifest for distributing `wb` via Flathub
or a local flatpak-builder workflow.

## Prerequisites

```bash
# Fedora / RHEL
sudo dnf install flatpak-builder

# Debian / Ubuntu
sudo apt install flatpak-builder

# Add the Freedesktop SDK (required once)
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08
```

## Building

Run from the repo root or from inside `runtime/flatpak/`:

```bash
# Build into ./build-dir (intermediate build cache)
flatpak-builder build-dir runtime/flatpak/org.wine_bleeding.wb.yaml
```

## Test-installing locally (user install)

```bash
flatpak-builder --user --install build-dir runtime/flatpak/org.wine_bleeding.wb.yaml

# Verify
flatpak run org.wine_bleeding.wb --version
```

To uninstall the test build:

```bash
flatpak uninstall --user org.wine_bleeding.wb
```

## Running

```bash
# Use wine-bleeding dist installed into WB_HOME via a separately downloaded tarball
flatpak run org.wine_bleeding.wb runtime install /path/to/wine-bleeding-dist.tar.xz

# Launch a prefix
flatpak run org.wine_bleeding.wb run --prefix ~/.local/share/wine-bleeding/prefixes/mygame
```

## Caveats

### No toolchain inside Flatpak

`full-build.sh` (Wine build from source) is **not** available inside the Flatpak
sandbox; the build toolchain is deliberately excluded.  Users must download a
pre-built `wine-bleeding` dist tarball separately and register it with:

```bash
flatpak run org.wine_bleeding.wb runtime install /path/to/tarball
```

### PortProton plugin mode

Plugin mode requires `~/PortProton` to be visible inside the sandbox.
The manifest already requests `--filesystem=~/PortProton`, but the user must
confirm this permission when installing from Flathub.

Detection order inside the sandbox:

1. `$PORT_WINE_PATH` environment variable — set this to override.
2. `/run/host/home/<user>/PortProton` — the path Flatpak surfaces when
   `--filesystem=~/PortProton` is granted.
3. If neither is accessible, `wb pp-install` will print:

       wb-pp-installer: PortProton not accessible from Flatpak sandbox;
       grant --filesystem=~/PortProton at install time

   and exit non-zero.

**Important:** do not edit PortProton's `user.conf` from inside the Flatpak
sandbox via automated means; prefer running `wb pp-install` once from outside
the sandbox (standard install) so that `user.conf` is written by the host
environment and is not subject to sandbox path translation.

### XDG paths

Inside the Flatpak sandbox, `$XDG_DATA_HOME`, `$XDG_CONFIG_HOME`, and
`$XDG_CACHE_HOME` point to the app-specific subdirectories:

- `~/.local/share/wine-bleeding/` (WB_HOME)
- `~/.config/wine-bleeding/`
- `~/.cache/wine-bleeding/`

These are the same locations used by the non-Flatpak install, so migrating
an existing standalone install into the Flatpak is seamless.

## Publishing to Flathub

Flathub submission is a manual process; see
<https://docs.flathub.org/docs/for-app-authors/submission>.  The manifest in
this directory is the starting point.  You will need to:

1. Fork the `flathub/org.wine_bleeding.wb` repo (create it if first submission).
2. Copy `org.wine_bleeding.wb.yaml` into the fork root.
3. Replace `sources: type: dir` with a `type: archive` pointing at a tagged
   release tarball with its SHA256.
4. Open a PR against the Flathub repo.

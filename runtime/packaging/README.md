# wine-bleeding-wb packaging

This directory contains multi-format packaging for wine-bleeding-wb.

## Supported formats

| Format   | Tool needed          | Makefile target  |
|----------|----------------------|------------------|
| RPM      | `rpmbuild`           | `make dist-rpm`  |
| DEB      | `dpkg-buildpackage`  | `make dist-deb`  |
| AppImage | `appimagetool`       | `make dist-appimage` |

All `dist-*` targets skip gracefully (exit 0) when the required tool is absent.

---

## RPM (Fedora / RHEL / openSUSE)

### Prerequisites

```bash
# Fedora / RHEL
dnf install rpm-build make bash coreutils rsync

# openSUSE
zypper install rpm-build make bash coreutils rsync
```

### Build

```bash
cd /path/to/wine/
make -C runtime dist-rpm
# or directly:
bash runtime/packaging/rpm/build.sh [--out /path/to/output]
```

Output RPMs are placed in `runtime/dist-packages/`.

### Install the built RPM

```bash
sudo rpm -ivh runtime/dist-packages/wine-bleeding-wb-*.rpm
# or with dnf for automatic dep resolution:
sudo dnf install runtime/dist-packages/wine-bleeding-wb-*.rpm
```

### Troubleshooting

- **"rpmbuild not found"**: install `rpm-build` package.
- **Missing deps at install time**: ensure `jq`, `util-linux`, `python3` are
  available. `yad` is recommended but not required.
- **VERSION mismatch**: check `runtime/VERSION` contains the expected version string.

---

## DEB (Debian / Ubuntu / Linux Mint)

### Prerequisites

```bash
sudo apt-get install dpkg-dev debhelper make bash coreutils rsync
```

### Build

```bash
cd /path/to/wine/
make -C runtime dist-deb
# or directly:
bash runtime/packaging/deb/build.sh [--out /path/to/output]
```

Output `.deb` files are placed in `runtime/dist-packages/`.

### Install the built DEB

```bash
sudo apt-get install ./runtime/dist-packages/wine-bleeding-wb_*.deb
# or:
sudo dpkg -i runtime/dist-packages/wine-bleeding-wb_*.deb
sudo apt-get install -f   # fix any missing deps
```

### Troubleshooting

- **"dpkg-buildpackage not found"**: install `dpkg-dev`.
- **debhelper version**: requires `debhelper-compat (= 13)`; available on
  Debian 11+ and Ubuntu 20.10+.
- **Rules invocation error**: ensure `debian/rules` has execute permission:
  `chmod +x runtime/packaging/deb/debian/rules`.

---

## AppImage

### Prerequisites

`appimagetool` must be on PATH or will be downloaded automatically on first run:

```bash
# Manual download (optional, for air-gapped builds):
wget https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage
# Place it at runtime/packaging/appimage/appimagetool-x86_64.AppImage
```

### Build

```bash
make -C runtime dist-appimage
# or:
bash runtime/packaging/appimage/build-appimage.sh [--out /path/to/output]
```

### Run the AppImage

```bash
chmod +x wine-bleeding-wb-1.5.0-dev-x86_64.AppImage
./wine-bleeding-wb-1.5.0-dev-x86_64.AppImage --version
./wine-bleeding-wb-1.5.0-dev-x86_64.AppImage runtime list
```

### AppImage limitations

This AppImage does **not** bundle:
- `bash` (>= 4.4)
- `jq` (>= 1.6)
- `flock` (from `util-linux`)
- `python3`
- `glibc`

These must be present on the host. The AppImage is a convenience wrapper, not
a fully hermetic bundle. For truly hermetic packaging, use Flatpak (M14).

### Troubleshooting

- **"SKIP: failed to download appimagetool"**: download manually (see above).
- **"cannot find wb"**: ensure `make install` ran successfully before AppImage
  assembly; check `runtime/dist-packages/` for build artefacts.
- **AppImage won't run**: check FUSE is available (`modprobe fuse`) or extract
  and run directly: `./wine-bleeding-wb-*.AppImage --appimage-extract`.

---

## Install from package

### RPM-based distros

```bash
sudo dnf install wine-bleeding-wb   # once in a repo
wb --version
```

### DEB-based distros

```bash
sudo apt-get install wine-bleeding-wb   # once in a repo
wb --version
```

### AppImage (any distro)

```bash
chmod +x wine-bleeding-wb-1.5.0-dev-x86_64.AppImage
# Optional: move to PATH
sudo mv wine-bleeding-wb-1.5.0-dev-x86_64.AppImage /usr/local/bin/wb
wb --version
```

---

## make install (manual / packager)

```bash
# System-wide (requires root)
sudo make -C runtime install PREFIX=/usr

# User-local (no root needed)
make -C runtime install PREFIX="${HOME}/.local"

# DESTDIR for package staging
make -C runtime install DESTDIR=/tmp/pkgroot PREFIX=/usr
```

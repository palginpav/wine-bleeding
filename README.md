# wine-bleeding

`wine-bleeding` is a Wine fork aimed at one practical result: a standalone, ready-to-run compatibility runtime rather than a bare upstream source checkout. It carries targeted compatibility work for real-world Windows software, including WinRT USB, shell/file dialogs, MSI, Mono/.NET, WPF, and related integration paths, then packages the result into a Proton-style `dist/WINE-BLEEDING-*` layout with DXVK, VKD3D-Proton, DXVK-NVAPI, optional native Linux libraries, and optional `wine-icu`. In short: upstream Wine is the base, `wine-bleeding` is the runtime product built on top of it.

## Quick start (recommended)

From the **root of the Wine source tree** (where `configure` and `tools/` are):

```bash
./tools/full-build.sh
```

This script will:

1. Check that required tools are installed (meson, ninja, gcc, make, flex, bison, pkg-config, etc.).
2. Prepare **MinGW** (download from musl.cc or use system/build-deps; optionally build from source).
3. **Configure** Wine with maximum features (WoW64 when both MinGW arches are available).
4. **Build** Wine.
5. Build **DXVK**, **VKD3D-Proton**, **DXVK-NVAPI** (x64 and x32).
6. Create the **dist** under `dist/WINE-BLEEDING-DDMMYYYY/`: install Wine from this tree, copy DXVK/VKD3D/NVAPI DLLs, and optionally copy native libs from the system.
7. Build and install **wine-icu** (under system libicu) into `dist/.../lib/wine/icu/` so installers and .NET apps that need ICU work without libicu68 (use `--no-wine-icu` to skip).

After a successful run, use:

```bash
./dist/WINE-BLEEDING-*/bin/wine --version
```

---

## Commands overview

| Command | Purpose |
|--------|---------|
| `./tools/full-build.sh` | Full pipeline: env check → MinGW → configure Wine → build Wine → build deps → create dist. |
| `./tools/configure-wine-full.sh` | Configure Wine with max features (WoW64, X, build-id; no optional features disabled). |
| `./tools/build-full-wine-deps.sh` | Build DXVK, VKD3D-Proton, DXVK-NVAPI and create dist; install Wine into dist if already built. |

All commands are meant to be run from the **wine-bleeding tree root**.

---

## full-build.sh options

Same options as `build-full-wine-deps.sh`:

| Option | Effect |
|--------|--------|
| `--build-mingw-from-source` | Build MinGW from source (Zeranoe script; 30–60 min). Use when the distro has no MinGW and you prefer not to use the musl.cc tarball. |
| `--no-install-wine` | Do not install Wine into the dist (only DXVK/VKD3D/NVAPI and layout). |
| `--no-bundle-system-libs` | Do not copy native libs (Vulkan, GStreamer, etc.) from the system into the dist. |
| `--copy-native-from=DIR` | Copy native libs from an existing dist (e.g. another Proton) instead of the system. Implies no system bundling. |
| `--force-rebuild` | Always rebuild DXVK, VKD3D-Proton, DXVK-NVAPI (ignore saved rev). |
| `--no-wine-icu` | Do not build/install wine-icu (system libicu) into the dist. Use if you have libicu68 or do not need ICU for installers. |

Examples:

```bash
./tools/full-build.sh --build-mingw-from-source
./tools/full-build.sh --no-bundle-system-libs
DIST_NAME=MyWine ./tools/full-build.sh
```

---

## Step-by-step (without full-build.sh)

If you prefer to run steps manually:

1. **MinGW in PATH**  
   Either install mingw-w64 (e.g. `mingw64-gcc` / `mingw-w64`) or run once:
   ```bash
   ./tools/build-full-wine-deps.sh --only-mingw
   ```
   then ensure `build-deps/.mingw-path` is sourced or add `build-deps/mingw64-cross/bin` (and `mingw32-cross/bin` if present) to `PATH`.

2. **Configure Wine**
   ```bash
   ./tools/configure-wine-full.sh
   ```

3. **Build Wine**
   ```bash
   make -j$(nproc)
   ```

4. **Build deps and create dist**
   ```bash
   ./tools/build-full-wine-deps.sh
   ```

---

## Requirements

- **Build tools:** gcc, g++, make, flex, bison, pkg-config, **meson**, **ninja**.
- **For DXVK/VKD3D:** **glslang** (glslangValidator), **Vulkan** (vulkan-headers, vulkan-loader).
- **MinGW:** Either from the system (e.g. `mingw-w64`), or the scripts will download a prebuilt cross-compiler from [musl.cc](https://musl.cc) into `build-deps/`, or you can use `--build-mingw-from-source` to build MinGW (needs gcc, g++, make, bison, flex, git, texinfo, etc.).

More optional packages (X11, Pulse, GStreamer, FFmpeg, libusb, udev, etc.) enable more Wine features; `configure` will report what is missing. See your distro’s Wine build docs for package names (e.g. Fedora: `libX11-devel`, `vulkan-headers`; Debian: `libx11-dev`, `libvulkan-dev`, `mingw-w64`).

---

## Dist layout

The output lives under `dist/WINE-BLEEDING-DDMMYYYY/` (or `DIST_NAME` if set):

| Path | Content |
|------|--------|
| `bin/` | Wine executables (wine, wineserver, winecfg, etc.). |
| `bin-wow64/` | Symlink/copy of the Wine launcher for GE-Proton–style layout. |
| `lib64` | Symlink to `lib/wine`. |
| `lib/wine/` | Wine DLLs and loaders; subdirs `dxvk`, `vkd3d-proton`, `nvapi`, and (if built) `icu` with DXVK, D3D12, NVAPI and wine-icu DLLs. Standalone libvkd3d is not built. |
| `lib/$(uname -m)-linux-gnu/` | Native libs copied from the system (if not disabled). |
| `share/` | Wine data (fonts, nls, etc.). |

Use this dist as a standalone Wine runtime or drop it into PortProton-style launchers.

---

## USB (Windows.Devices.Usb)

This tree contains active implementation work for **Windows.Devices.Usb** (WinRT). The intended stack is:

- `Windows.Devices.Usb`
- `winusb.dll`
- `wineusb.sys`
- native `libusb` backend

For USB to work at runtime you need **libusb** and **udev**, plus appropriate device permissions on the host system.

---

## Scope note

This repository still contains the normal upstream Wine source layout, and upstream Wine documentation remains relevant for many low-level build and runtime details.

What this README describes is the **fork-specific purpose** of `wine-bleeding`: the extra compatibility work and the standalone runtime build flow layered on top of Wine.

---

## Upstream Wine

For general Wine build and usage, see the [Wine HQ wiki](https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine) and [winehq.org](https://www.winehq.org). This README describes only the **extra** scripts and the Proton-style dist build used in this tree.

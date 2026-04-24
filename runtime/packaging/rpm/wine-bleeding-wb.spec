Name:           wine-bleeding-wb
Version:        WB_VERSION_PLACEHOLDER
Release:        1%{?dist}
Summary:        wine-bleeding runtime dispatcher and tooling
Group:          Applications/System
License:        GPL-2.0-or-later
URL:            https://github.com/palginpav/wine
# Source tarball is prepared by build.sh and placed in SOURCES/
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  bash
BuildRequires:  make
BuildRequires:  coreutils

Requires:       bash >= 4.4
Requires:       jq >= 1.6
Requires:       util-linux
Requires:       coreutils
Requires:       findutils
Requires:       grep
Requires:       sed
Requires:       tar
Requires:       gzip
Requires:       python3
# Recommends: yad  (weak dep — uncomment for RPM >= 4.12 / dnf-based distros)

# ALT Linux rpm scans the %post scriptlet for command tokens and auto-adds
# them as Requires(post), resolving the binary name to the packager-specific
# package name. On ALT, `gtk-update-icon-cache` resolves to the package
# `gtk4-update-icon-cache`; on Fedora/openSUSE the same binary lives in
# `gtk4` or `gtk3-tools`, so an ALT-built package declaring this name as a
# hard Requires would fail dependency resolution on those distros. Since the
# %post scriptlet probes with `command -v ... || :` and the refresh is purely
# cosmetic (no icon refresh is not a broken install), we disable the
# scriptlet-requires auto-generator entirely — the main package Requires
# remain intact. `desktop-file-utils` (the universal name across distros) is
# an explicit Requires below so users still get the desktop-db refresh tool.
%global __find_scriptlet_requires %{nil}
Requires:       desktop-file-utils

%description
wine-bleeding-wb provides the wb runtime dispatcher, wb-diag diagnostic helper,
shell library modules (wb-lib), hook infrastructure, configuration schemas, and
supporting tooling for managing Wine prefixes and runtime distributions.

Install via your package manager to get wb on PATH with full system integration:
desktop entry, icon, and Steam compatibility tool support.

# ---------------------------------------------------------------------------
# wine-bleeding-wb-build — metapackage: recommended build dependencies
# ---------------------------------------------------------------------------
# This subpackage exists so users can run a single install command to pull
# what their distro provides. Recommends: (not Requires:) means a missing
# package on a lean distro (Alpine, Void) does not block the whole install.
# wb-preflight.py fills any remaining gap at runtime with distro-specific
# install hints and source-build fallbacks (glslang, MinGW-w64, meson-pip).

%package -n wine-bleeding-wb-build
Summary:        Recommended build-tool dependencies for wine-bleeding wb-gui
Group:          Development/Tools
BuildArch:      noarch

# Soft-dependency list. `Recommends:` was added in RPM 4.13 (2016); older
# rpmbuild (e.g. ALT Linux 4.0.4) errors on the tag. Guarded by Fedora /
# RHEL / openSUSE detection — on distros without Recommends: support the
# subpackage still builds (just without the recommendation list); users
# fall through to wb-preflight at first-run for the install hints anyway.
# zstd is required at runtime by wb-tools-manager.py to decompress managed
# build-tool tarballs (.tar.zst). ALT Linux ships zstd in its own repos but
# its rpmbuild (4.0.4) does not support Recommends:, so this Requires: is
# guarded identically to the Recommends: block below.
%if 0%{?fedora} || 0%{?rhel} || 0%{?suse_version} >= 1500
Requires:       zstd
%endif

%if 0%{?fedora} >= 24 || 0%{?rhel} >= 8 || 0%{?suse_version} >= 1500
# Core build tools — present on virtually every RPM-based distro.
Recommends:     gcc
Recommends:     gcc-c++
Recommends:     make
# Build system: meson + ninja. meson floor 0.60.0 (DXVK HEAD requirement).
# If the distro meson is too old, wb-preflight offers pip-install-meson.
Recommends:     meson
Recommends:     ninja-build
# GLSL→SPIR-V compiler required for DXVK shader compilation.
# Not packaged on RHEL (no EPEL entry) or Alpine; wb-preflight offers
# tools/build-glslang.sh source-build fallback for those distros.
Recommends:     glslang
# MinGW-w64 cross-compiler for Windows PE targets (DXVK, VKD3D-Proton DLLs).
# On Fedora the split into mingw64-gcc + mingw64-gcc-c++ is intentional;
# both are needed. RHEL users install from EPEL after enabling it.
Recommends:     mingw64-gcc
Recommends:     mingw64-gcc-c++
# pkgconf compatibility shim — canonical name on Fedora/RHEL/ALT.
Recommends:     pkgconf-pkg-config
# Version control — required by build-component.sh and build-glslang.sh.
Recommends:     git
# Wine full-source-build prerequisites (only needed for Build Dist from Source).
Recommends:     flex
Recommends:     bison
Recommends:     autoconf
%endif

%description -n wine-bleeding-wb-build
wine-bleeding-wb-build is a metapackage that pulls in the build tools
recommended for wb-gui's Component Builder and Build Dist from Source
features.

All dependencies are declared as Recommends: (weak dependencies). A tool
not available in your distro's repositories will not block installation;
wb-preflight.py detects any gap at runtime and offers a distro-specific
install command or a source-build fallback (glslang, MinGW-w64, meson).

Install with: dnf install wine-bleeding-wb-build

Then open wb-gui → Component Builder or Build Dist from Source. The
preflight dialog will show any remaining gaps with actionable fix buttons.

%files -n wine-bleeding-wb-build
%{_datadir}/doc/wine-bleeding-wb-build/README
/usr/lib/wine-bleeding/libexec/wb-tools-manager.py
%{_datadir}/wine-bleeding/wb-tools-manager-manifest.json

# ---------------------------------------------------------------------------

%prep
%setup -q

%build
# No compiled artefacts — pure shell.

%install
# Shell scripts are arch-independent; use /usr/lib not /usr/lib64.
# The source tarball carries runtime/ and tools/ side-by-side (build.sh
# stages both), so the Makefile is at runtime/Makefile and picks up
# ../tools automatically.
make -C runtime install \
    DESTDIR=%{buildroot} \
    PREFIX=/usr \
    LIBDIR=/usr/lib \
    SHAREDIR=/usr/share

%files
%{_bindir}/wb
%{_bindir}/wb-diag
/usr/lib/wine-bleeding/wb-lib/
/usr/lib/wine-bleeding/hooks/
%{_datadir}/wine-bleeding/
# wb-tools-manager-manifest.json belongs to wine-bleeding-wb-build (installed
# alongside the manager script). Exclude it from the main package glob above.
%exclude %{_datadir}/wine-bleeding/wb-tools-manager-manifest.json
%{_datadir}/doc/wine-bleeding/
# Steam Compatibility Tool registration — installed unconditionally by the
# Makefile `install:` target when the source tree has the directory.
%{_datadir}/steam/compatibilitytools.d/wine-bleeding/
# wb-gui: shipped unconditionally since M12. Previously marked %ghost (a
# leftover from the pre-M12 "optional W1 deliverable" era) which caused rpm
# to own the paths but leave the files out of the payload — resulting in
# an installed RPM with no wb-gui binary, no .desktop entry in the apps
# menu, and no icons. Listed as real %files entries now.
%{_bindir}/wb-gui
/usr/lib/wine-bleeding/wb-gui-lib/
/usr/lib/wine-bleeding/libexec/wb-lnk-parse.py
/usr/lib/wine-bleeding/libexec/wb-preflight.py
/usr/lib/wine-bleeding/tools/
%{_datadir}/applications/wine-bleeding-wb.desktop
%{_datadir}/icons/hicolor/16x16/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/22x22/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/24x24/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/32x32/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/48x48/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/64x64/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/128x128/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/256x256/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/512x512/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/1024x1024/apps/wine-bleeding.png

%pre
# Upgrade from the short-lived intermediate release that shipped a
# placeholder scalable SVG (commit 74f00d7fa17): rpm --force same-version
# reinstall does not run the erase-old-files sweep, so that SVG lingers
# on disk as an orphan and FDO IconThemeSpec gives it priority over the
# real PNGs. Remove it pre-upgrade so the new install lands cleanly.
# The test -f guard makes this safe on fresh installs.
if [ -f %{_datadir}/icons/hicolor/scalable/apps/wine-bleeding.svg ]; then
    rm -f %{_datadir}/icons/hicolor/scalable/apps/wine-bleeding.svg
fi

%post
# Update desktop database if available
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q %{_datadir}/applications || :
fi
# Update icon cache if available
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q %{_datadir}/icons/hicolor || :
fi

%postun
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q %{_datadir}/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q %{_datadir}/icons/hicolor || :
fi

%changelog
* Sat Apr 19 2026 Pavel Palgin <pavel.palgin@gmail.com> - 1.5.0~dev-1
- Multi-format packaging: RPM, DEB, AppImage (M packaging milestone)
- Add make install target with DESTDIR/PREFIX support
- Option A lib fallback: wb resolves libs from /usr/lib/wine-bleeding/wb-lib/
  when not co-located with wb-lib/ sibling directory

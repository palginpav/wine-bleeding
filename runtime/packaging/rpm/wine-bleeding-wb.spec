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

%prep
%setup -q

%build
# No compiled artefacts — pure shell.

%install
# Shell scripts are arch-independent; use /usr/lib not /usr/lib64
make install \
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
%{_datadir}/applications/wine-bleeding-wb.desktop
%{_datadir}/icons/hicolor/scalable/apps/wine-bleeding.svg
%{_datadir}/icons/hicolor/256x256/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/512x512/apps/wine-bleeding.png
%{_datadir}/icons/hicolor/1024x1024/apps/wine-bleeding.png

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

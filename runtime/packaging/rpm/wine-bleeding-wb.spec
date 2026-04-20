Name:           wine-bleeding-wb
Version:        WB_VERSION_PLACEHOLDER
Release:        1%{?dist}
Summary:        wine-bleeding runtime dispatcher and tooling
Group:          Applications/System
License:        GPL-2.1-or-later
URL:            https://github.com/palginpav/wine
# Source tarball is prepared by build.sh and placed in SOURCES/
Source0:        %{name}-%{version}.tar.gz

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
# wb-gui and related files are installed when present (optional W1 deliverables)
%ghost %{_bindir}/wb-gui
%ghost /usr/lib/wine-bleeding/wb-gui-lib/
%ghost %{_datadir}/applications/wine-bleeding-wb.desktop
%ghost %{_datadir}/icons/hicolor/scalable/apps/wine-bleeding.svg

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

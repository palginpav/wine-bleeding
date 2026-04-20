# wine-bleeding Runtime Layer Changelog

## [Unreleased] — v1.5.0-dev

### Pre-install RPM packaging fixes

- **Steam Compatibility Tool files now packaged in `%files`** — `packaging/rpm/wine-bleeding-wb.spec`
  previously omitted `/usr/share/steam/compatibilitytools.d/wine-bleeding/*`
  from the `%files` list, producing an "Installed (but unpackaged) file(s)"
  rpmbuild warning. Permissive on ALT, hard-failure on strict rpmbuild
  policy (Fedora/RHEL). Added `%{_datadir}/steam/compatibilitytools.d/wine-bleeding/`
  to `%files` so the two Steam compat files (`compatibilitytool.vdf`,
  `wine-bleeding.sh`) are now owned by the RPM and removed on `rpm -e`.
- **Bogus auto-generated `Requires: gtk4-update-icon-cache` suppressed** —
  ALT rpm's `find-scriptlet-requires` scanner auto-detected
  `gtk-update-icon-cache` in `%post` and resolved it to the ALT-specific
  package name `gtk4-update-icon-cache`, producing a cross-distro-broken
  Requires (on Fedora/openSUSE the same binary lives in `gtk4` or
  `gtk3-tools`). The scriptlet body already probes with `command -v ... || :`
  so the tool is genuinely optional. Fixed by `%global __find_scriptlet_requires
  %{nil}` to disable the auto-generator, plus an explicit `Requires:
  desktop-file-utils` (universal package name across distros) so users still
  get the desktop-db refresh tool installed as a hard dep.

### Post-GA opt-ins (LD_LIBRARY_PATH emission + .desktop i18n)

- **`LD_LIBRARY_PATH` emission in `wb_env_compose`** — `src/wb-lib/wb-env.sh`
  now emits `LD_LIBRARY_PATH` alongside the existing env keys. Candidate dirs
  in order: `${dist_path}/lib64`, `${dist_path}/lib`,
  `${dist_path}/lib/wine/x86_64-unix`, `${dist_path}/lib/wine/i386-unix`.
  Only existing dirs are included; a pre-existing parent `LD_LIBRARY_PATH`
  is appended at the tail with a single colon separator. When no dist dirs
  exist AND the parent var is unset, the key is suppressed entirely to keep
  sorted output stable across layouts. Closes W3 §9.2 Full-scope (previously
  deferred). Six new bats cases in `runtime/tests/10_env.bats` (tests 22–27)
  cover happy path, parent preservation, partial layout, empty suppression,
  parent-only, and determinism.
- **`.desktop` i18n for ru/es/de/zh_CN** — initial shipping locales. Adds
  `Name[xx]`, `GenericName[xx]`, and `Comment[xx]` for Russian, Spanish,
  German, and Simplified Chinese to both `share/applications/wine-bleeding-wb.desktop`
  (wb-gui launcher) and `packaging/appimage/wine-bleeding-wb.desktop`
  (AppImage wb launcher). Fills in the previously-missing unsuffixed
  `GenericName=Wine Runtime GUI` on the wb-gui launcher. Product names
  (`wine-bleeding`, `wb`, `Wine`) are preserved verbatim per glossary.
  Both files pass `desktop-file-validate`. Translations validated under
  the orchestray 2.1.8 `translator` specialist protocol (5 correctness
  checks: placeholder parity, CLDR plural-form, length-ratio, RTL markers,
  source-language leak — all pass, quality score 1.0). Three new bats cases
  in `runtime/tests/25_packaging.bats` (tests 11–13) assert locale-key
  presence and `desktop-file-validate` clean.

### Pre-GA hardening (M12 security review follow-ups + M8 deferred)

- **AppImage SHA256 pin (M-2 RELEASE BLOCKER)** — `build-appimage.sh` now pins
  to appimagetool 1.9.0 (`46fdd785…`) instead of the rolling `continuous` channel.
  SHA256 is verified before `chmod +x`; mismatch deletes the cached binary and
  exits 1 (fail-closed). Env override `APPIMAGETOOL_SHA256=<hash>` allows CI to
  supply a pre-verified hash. `packaging/README.md` documents the pinned version,
  hash, and upgrade procedure.
- **`.desktop` `%U` → `%f` + MimeType (L-2)** — `share/applications/wine-bleeding-wb.desktop`
  changes `Exec=wb-gui %U` to `Exec=wb-gui %f` (file path, not URI) and adds
  `MimeType=application/x-ms-dos-executable;` so file managers can open `.exe`
  files via wb-gui.
- **AppRun bash 4.4+ guard (I-3)** — `packaging/appimage/AppRun` now checks
  `${BASH_VERSINFO}` at startup and exits 1 with a clear error on bash < 4.4.
- **UUID `/dev/urandom` fallback (L-5)** — `src/wb-gui-lib/wb-gui-games.sh`
  UUID fallback 3 replaced from `$RANDOM`-based (non-cryptographic, ~96-bit)
  to `head -c 16 /dev/urandom | od -An -tx1` (full 128-bit, cryptographic).
- **Snapshot auto-capture on `wb run` (M8 deferred)** — `cmd_run` in `src/wb`
  now calls `wb_snapshot_capture` after reconcile, before the pre-exec hook.
  Opt-out via `WB_SNAPSHOT=0`. Failures are non-fatal (logged, launch continues).
  Two new bats tests in `runtime/tests/12_run_dry.bats` verify capture occurs and
  that `WB_SNAPSHOT=0` suppresses it.
- **Pango markup escape (I-4)** — `src/wb-gui-lib/wb-gui-dialogs.sh` info,
  error, and confirm dialogs now pass `--no-markup` to yad, preventing crafted
  game names containing `<span>` or `&amp;` from being rendered as Pango markup.

### M12 — GUI (`wb-gui`) + Steam Compatibility Tool entry

- **`runtime/src/wb-gui`** — bash + yad game-library GUI. Main window lists
  games from `$WB_HOME/games.json` with NAME | PREFIX | RUNTIME | LAST PLAYED.
  Buttons: Add Game, Launch, Settings, Remove, Refresh, Close. Subcommand
  dispatch: `wb-gui add-game <exe>`, `wb-gui settings <prefix>`. Every
  business operation delegates to `wb` CLI; no prefix-internal writes.
- **`runtime/src/wb-gui-lib/wb-gui-games.sh`** — atomic games registry helpers:
  `wb_gui_games_list`, `wb_gui_games_add`, `wb_gui_games_remove`, `wb_gui_games_get`.
- **`runtime/src/wb-gui-lib/wb-gui-dialogs.sh`** — yad thin wrappers with
  consistent `--center --window-icon=wine-bleeding --width=600` styling.
- **`runtime/share/compatibilitytools.d/wine-bleeding/compatibilitytool.vdf`**
  — Steam compat tool registration (Valve KeyValues format).
- **`runtime/share/compatibilitytools.d/wine-bleeding/wine-bleeding.sh`** —
  Steam compat launcher; `run` and `waitforexitandrun` verbs delegate to `wb run`.
- **`runtime/share/applications/wine-bleeding-wb.desktop`** — XDG desktop entry.
- **`runtime/share/icons/hicolor/scalable/apps/wine-bleeding.svg`** — placeholder SVG.
- **`runtime/tests/24_gui.bats`** — 13 bats tests covering games registry,
  settings dialog, input validation, .desktop key presence, VDF brace balance.
- **`wb gui` subcommand** — `wb gui` execs `wb-gui` from the same directory.
- **`runtime/install.sh`** — new `--steam-compat-tool` flag; GUI files, icon,
  and .desktop file installed to XDG user dirs.

---

### Multi-format packaging (RPM, DEB, AppImage)

- **`runtime/packaging/rpm/wine-bleeding-wb.spec`** — RPM spec for Fedora /
  RHEL / openSUSE. Invokes `make install DESTDIR=%{buildroot} PREFIX=/usr`
  in `%install`. `%post` runs `update-desktop-database` / `gtk-update-icon-cache`
  when available. Changelog entry included.
- **`runtime/packaging/rpm/build.sh`** — helper that stages a source tree and
  invokes `rpmbuild -ba`; outputs RPMs + SHA256 to `runtime/dist-packages/`.
- **`runtime/packaging/deb/debian/`** — Debian packaging directory:
  `control`, `rules`, `install`, `postinst`, `changelog`, `compat`, `copyright`.
  `rules` calls `make install DESTDIR=debian/wine-bleeding-wb PREFIX=/usr`.
  `postinst` runs `update-desktop-database` / `gtk-update-icon-cache`.
- **`runtime/packaging/deb/build.sh`** — stages source + debian/ and invokes
  `dpkg-buildpackage -us -uc -b`; outputs `.deb` + SHA256 to `dist-packages/`.
- **`runtime/packaging/appimage/AppRun`** — AppImage entry point; resolves
  `wb` relative to `$APPDIR`; supports GUI mode via `WB_APPIMAGE_GUI=1`.
- **`runtime/packaging/appimage/build-appimage.sh`** — stages AppDir via
  `make install`, downloads `appimagetool` if absent, builds AppImage and emits
  SHA256. Skips gracefully when both appimagetool and download tools are absent.
- **`runtime/packaging/README.md`** — build + install instructions for all
  three formats with troubleshooting sections.
- **`runtime/Makefile`** — `install` target replaces stub with a real
  `install -D` based implementation honouring `DESTDIR` / `PREFIX` (default:
  `/usr/local`). New targets: `dist-rpm`, `dist-deb`, `dist-appimage`, `dist-all`.
  New packaging scripts added to `SHELLCHECK_TARGETS`.
- **`runtime/VERSION`** — single-line version file (`1.5.0-dev`). Authoritative
  source consumed by packaging scripts and verified by bats test 8.
- **Option A lib fallback** — `wb` and `wb-diag` now resolve `wb-lib/` via
  sibling-first, then `/usr/lib/wine-bleeding/wb-lib/`, then
  `/usr/local/lib/wine-bleeding/wb-lib/`. Enables correct operation after
  `make install PREFIX=/usr` where libs land in `/usr/lib/`, not `/usr/bin/`.
- **`runtime/tests/25_packaging.bats`** — 8 packaging-focused bats tests covering
  DESTDIR layout, installed wb functionality, Option A fallback, RPM spec
  structure, DEB control structure, AppRun smoke-run, dist-* skip behaviour,
  and VERSION/wb --version consistency.

### Breaking changes

- `WB_VERSION` bumped from `1.4.0-dev` to `1.5.0-dev`.
- `Makefile` `PREFIX` default changed from `$(HOME)/.local` to `/usr/local`
  (standard for system packages; standalone install still uses `install.sh`).

---

## [Unreleased] — v1.4.0-dev

### M14 — Flatpak packaging

- **`runtime/flatpak/org.wine_bleeding.wb.yaml`** — flatpak-builder manifest.
  Targets `org.freedesktop.Platform//24.08`; installs `wb`, `wb-diag`, all
  `wb-lib` shell libraries, hooks, schemas, and documentation into `/app`.
  Finish-args grant `--filesystem=host` (Wine prefixes anywhere),
  `--filesystem=~/PortProton` (plugin mode), XDG data/config/cache subdirs,
  Wayland + X11 sockets, PulseAudio, and DRI device access.
- **Sandbox-aware `wb_pp_detect_root`** — updated detection order:
  1. `$PORT_WINE_PATH` environment variable (always wins).
  2. Flatpak sandbox (`$FLATPAK_ID` set): check
     `/run/host/home/<user>/PortProton` (path Flatpak surfaces when
     `--filesystem=~/PortProton` is granted). Warns to stderr if not visible.
  3. Standard `~/PortProton` fallback (unchanged prior behaviour).
  Function remains side-effect-free (no mkdir).
- **`runtime/flatpak/README.md`** — build, test-install, and caveats
  (no toolchain in sandbox; PortProton plugin permission; XDG path notes;
  Flathub submission overview).
- **7 new bats tests** in `runtime/tests/23_flatpak_detection.bats`.
- **`WB_VERSION`** bumped to `1.4.0-dev`.

### Breaking changes

- `WB_VERSION` bumped from `1.3.0-dev` to `1.4.0-dev`.

---

## [Unreleased] — v1.3.0-dev

### M13 — Runtime plugin registry

- **`wb runtime register <JSON>`** — validates and registers an external Wine
  build (GE-Proton, Lutris, custom) from a plugin JSON descriptor into
  `$WB_HOME/plugins/runtimes.d/<name>.json`. Atomic write; idempotent on same
  content. Required fields: `schema`, `name`, `path`. Name pattern enforced
  (`^[A-Za-z0-9_.-]+$`); `path` must be absolute with no whitespace.
- **`wb runtime unregister <NAME>`** — removes a registered plugin by name.
- **`wb runtime list`** — now shows both native `dist/` entries and external
  plugin entries in a single table with a `KIND` column (`native`|`external`).
  - `--native` flag: show only dist entries.
  - `--external` flag: show only plugin entries.
  - `--multi` flag still works orthogonally.
- **`wb run --runtime NAME`** — extended resolver now checks
  `plugins/runtimes.d/` after `dist/` (dist wins on name collision).
- **New lib** — `runtime/src/wb-lib/wb-runtimes.sh` with public functions
  `wb_runtimes_plugin_dir`, `wb_runtimes_plugin_list`,
  `wb_runtimes_plugin_read`, `wb_runtimes_plugin_register`,
  `wb_runtimes_plugin_resolve`.
- **New schema** — `runtime/share/schemas/wb_runtime_plugin.schema.json`
  (JSON Schema Draft 2020-12).
- **12 new bats tests** in `runtime/tests/22_runtimes_plugin.bats`.
- **Resolver precedence**: dist/ > plugins/runtimes.d/ > WINE-BLEEDING alias.

### Breaking changes

- `WB_VERSION` bumped to `1.3.0-dev`.

---

## [Unreleased] — v1.2.0-dev

### M11 — Pressure-vessel / SLR container opt-in

- **`wb config enable-container`** / **`wb config disable-container`** — flip
  `WB_CONTAINER=1` in `$WB_HOME/etc/runtime.conf`.
- **`wb_container_enabled`** — returns 0 when `WB_CONTAINER=1`.
- **`wb_container_detect`** — finds the SLR `_v2-entry-point`. Checks
  `$WB_CONTAINER_ENTRY`, then three well-known Steam install paths.
- **`wb_container_compose_argv`** — emits one argv element per line for the
  pressure-vessel invocation (`--filesystem=<prefix>`, `--verb=waitforexitandrun`, `--`).
- **`wb run`** and **`wb exec`** both honor `WB_CONTAINER=1`. When enabled:
  wine is wrapped inside the SLR container.
- **Graceful failure** — if pressure-vessel is not found, exits 1 with a clear
  actionable message directing the user to install via Steam or set
  `$WB_CONTAINER_ENTRY`.
- **No auto-download** — installing SLR (~1 GB) is a manual Steam step; wb
  detects and fails cleanly, never downloads anything automatically.
- **New lib** — `runtime/src/wb-lib/wb-container.sh`.
- **12 new bats tests** in `runtime/tests/21_container.bats`.

### Breaking changes

- `WB_VERSION` bumped to `1.2.0-dev`.

---

## v1.1.0-dev

### M9 — Multi-build / distro-switching (opt-in)

- **`wb config enable-multibuild`** / **`wb config disable-multibuild`** — flip
  `WB_MULTIBUILD=1` in `$WB_HOME/etc/runtime.conf`.
- **`wb runtime list --multi`** — extra `MULTI` column listing all real (non-alias)
  dist directories.
- **`wb run --runtime NAME`** — now gated by multi-build check; refuses unless
  multi-build is enabled (or the requested runtime matches the active alias).
- **`wb run --yes-wineboot`** — new flag to consent to `wineboot -u` on a
  major-version switch.
- **`wb_multibuild_reconcile_switch`** — implements the W3 §11.2 decision tree:
  same-major switch reconciles components only (no wineboot); different-major switch
  requires `--yes-wineboot` or `WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE=1`; exits 42 on
  missing consent.
- **`.wb_runtime.history[]`** and **`.wb_runtime.current_runtime`** — new optional
  fields tracking every runtime switch with UTC timestamps.
- **`wb prefix history <NAME>`** — prints runtime-switch history table.
- **Schema extended** — `wb_runtime.schema.json` gains optional `history[]` and
  `current_runtime` fields; existing files without these fields continue to validate.
- **`wb_prefix_adopt` preserves history** — re-adopting a prefix no longer clobbers
  existing `history[]` or `current_runtime`.
- **20 new bats tests** in `runtime/tests/20_multibuild.bats`.

### Breaking changes

- `WB_VERSION` bumped to `1.1.0-dev`.

---

## v1.0.0-MVP (2026-04-19)

### MVP Release

The wine-bleeding native runtime layer (`wb`) delivers a self-owned launcher that
manages Wine prefixes, GPU components (DXVK, VKD3D-Proton, DXVK-NVAPI), wine-mono,
and ICU DLLs. It coexists with PortProton, can adopt and migrate existing PP prefixes,
and provides explicit hook points and a stable CLI surface.

### Milestones delivered

| Milestone | Description |
|-----------|-------------|
| M0 | Scaffolding: Makefile, bats test harness, shellcheck, fake-dist/fake-wine fixtures |
| M1 | `wb runtime` — install, activate, list, info, prune; `.wb_dist_meta` manifest |
| M2 | `wb prefix` — classify, adopt (coexist + take-over), import; `.wb_runtime` sentinel |
| M3 | `wb config` — 5-layer config system (global → dist → user → prefix → env), JSON output |
| M4 | `wb prefix init` — wineboot + all GPU components + DllOverrides reg patch + `.wb_components` |
| M5 | `wb run` — full §5.2 call graph: reconcile, lock, pre/post hooks, env composition, exec |
| M6 | PortProton plugin mode: `wb pp install/uninstall/status`, `reapply.sh` hook, `deploy-to-portproton.sh` |
| M7 | Standalone installer: `install.sh`, prefix migration (`wb prefix migrate/export`), `wb-diag` stub |
| M8 | Snapshot-and-repair, log rotation, `wb-diag` full implementation, MVP polish (this release) |

### New in M8

**Snapshot and repair (`wb prefix snapshot / snapshots / repair`)**
- `wb prefix snapshot <NAME>` — capture prefix state (`.wb_runtime`, `.wb_components`,
  DllOverrides names, system32/syswow64 DLL names) to a JSON file in
  `$WB_HOME/state/prefix-snapshots/`. Retains last 5 snapshots per prefix.
- `wb prefix snapshots <NAME>` — list snapshots for a prefix, newest first.
- `wb prefix repair <NAME> [--yes] [--from-snapshot UTC]` — one-button recovery after
  PortProton `pw_clear_pfx` wipes a prefix. Re-runs wineboot + components + reg patch
  from the snapshot. User data (game saves, Documents) is intentionally NOT restored
  (snapshots only carry metadata, never file contents — privacy by design).

**Log rotation**
- `wb-log.sh` now rotates `wb.log` → `wb.log.1` .. `wb.log.5` when the log file
  reaches `WB_LOG_MAX_BYTES` (default 10 MB). Uses `flock` so concurrent writers
  do not race. Oldest generation `.5` is deleted; no generation `.6` is ever created.
- `WB_LOG_MAX_BYTES` is overridable via environment variable.

**wb-diag (full implementation)**
- `wb-diag [--dry-run]` collects a support bundle tarball `wb-diag-<UTC>.tar.gz`
  in the current directory. Bundle includes: `env.txt`, `version.txt`,
  `runtime-list.txt`, `prefix-list.txt`, `log-tail.txt`, `system.txt`, and
  `per-prefix/<NAME>/info.txt` + `latest-snapshot.json` for each prefix.
- SECURITY: explicit allowlist. Never includes `drive_c/` contents, `user.reg`,
  `system.reg`, `user.conf`, or auth tokens.
- Emits tarball path + SHA256 to stdout.
- `--dry-run` lists what would be collected without creating the tarball.

**Version bump**
- Version string promoted to `1.0.0-MVP`. The string `1.0.0` is reserved for the
  actual GA release after MVP ships.

### Post-MVP scope (not in this release)

- GUI launcher (planned M12)
- Multi-build distro-switching (M9)
- Pressure-vessel / container isolation (M11, opt-in)
- Go CLI rewrite (M10)
- Automatic snapshot on every `wb run` (hook is callable; auto-integration is follow-up polish)

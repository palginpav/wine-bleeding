# wine-bleeding Runtime Layer Changelog

## [Unreleased] — v1.7.0-dev

### Phase B: dist management UI + component builder

Dist Manager and a Component Builder that wraps `tools/full-build.sh` into
per-component rebuilds (DXVK / VKD3D-Proton / DXVK-NVAPI). gstreamer is
**deferred** to Phase C (no clean source-build path exists today —
`build-full-wine-deps.sh` ingests system `libgst*.so`).

- **`src/wb-gui-lib/wb-gui-dist.sh`** (new) — dist registry library with a
  derived-view refresh pattern (registry is rebuilt from `.wb_dist_meta` +
  `plugins/runtimes.d/` rather than stored as a source-of-truth to avoid
  drift). JSON storage at `$WB_HOME/dists.json`.
  Schema: `share/schemas/wb_dists.schema.json`.
- **`tools/build-component.sh`** (new) — component-granular builder with a
  `PROGRESS:/LOG:/WARN:/ERROR:` event protocol on `--progress-fd=<N>`.
  Builds to a sibling directory and performs an atomic `mv -T` swap so the
  user's currently-active dist is never blocked during rebuild.
  Hard-kill cancellation: SIGTERM → 5s watchdog → SIGKILL to the process
  group (required because meson/ninja grandchildren ignore plain SIGTERM).
- **`tools/lib/build-common.sh`** (new) — shared helpers extracted from
  `full-build.sh` Step 1-2 of the decomposition plan. Steps 3-4 (routing
  `full-build.sh` through `build-component.sh` in a loop) are **deferred**
  pending a real MinGW+network build verification of byte-identical dist
  output. Existing `full-build.sh` CLI parity preserved unchanged.
- **`src/wb-gui`** — new `[Dists]` button on the main window (rc=70) opens
  the Dist Manager. `_cmd_dist_manager` implements the list + Add External +
  Activate + Build Components + Remove flows. `_cmd_build_component`
  implements the 3-stage Component Builder (form → live log tail → result),
  routing each `build-component.sh` exit code to a specific result dialog.
- **`src/wb-gui-lib/wb-gui-dialogs.sh`** — new `wb_gui_dialog_log_tail`
  helper (yad `--text-info --tail --filename`) for live build output.
- **Tests** (+30) — `30_dist_registry.bats`, `31_dist_manager.bats`,
  `32_build_component.bats`. Full suite 409 → 439, all green.

### Polish — Phase B follow-up (Stage 2 auto-close)

- **`src/wb-gui` `_cmd_build_component`** — Stage 2 log-tail now closes
  automatically when the builder exits naturally (async yad launch + poll
  loop on both PIDs). Previously the user had to click Cancel to advance
  to Stage 3. User-cancel path unchanged (still SIGTERM → 5s → SIGKILL
  to the process group). Poll interval and post-exit drain configurable
  via `WB_GUI_BUILD_POLL_SEC` / `WB_GUI_BUILD_TAIL_DRAIN_SEC`.

Known limitations (polish follow-ups for v1.7.x):

- Stage 1 "Current version" field is static (shows DXVK at open time);
  `yad --form` does not support live field refresh on `CB` change.
- `full-build.sh` decomposition Steps 3-4 are deferred (see above).

### Removed — GAP-2 transitional bridge

- **`src/wb-gui` `_cmd_settings`** — removed the v1.6.0 transitional
  `.wb.ppdb` write path. `wb-gui settings <prefix>` now resolves the prefix
  to an app-id via `apps.json` and dispatches directly to
  `_cmd_settings_v2 app <id>`, so per-app settings flow exclusively through
  the 4-layer store. Obsolete `.wb.ppdb` assertions dropped from
  `tests/24_gui.bats` (tests 7-8) and `tests/29_ui_flows.bats` (tests 18-19);
  coverage of the settings-v2 dispatch lives in `tests/29_ui_flows.bats`
  tests 7-9 and 16.

## [1.6.0] — 2026-04-20

### Phase A: generalize games → apps (+4-layer settings + post-install detection)

Large foundational rework. The main window is now app-centric rather than
game-centric; any Windows program (portable, installer, game) is a first-class
app. Backing file migrated from `games.json` to `apps.json` on first open
(idempotent, dual-write shim retained for 24_gui.bats legacy compat).

- **`src/wb-gui-lib/wb-gui-apps.sh`** (new) — apps registry primitives:
  `wb_gui_apps_add`, `wb_gui_apps_list`, `wb_gui_apps_remove`,
  `wb_gui_apps_migrate_from_games`. Schema: `share/schemas/wb_apps.schema.json`.
- **`src/wb-gui-lib/wb-gui-settings.sh`** (new) — 4-layer settings hierarchy
  (general → dist → prefix → per-app) with `wb_gui_settings_resolve` override
  resolver. Each layer is a JSON file under `$WB_HOME/settings/`. Schema:
  `share/schemas/wb_settings.schema.json`.
- **`src/wb-gui-lib/wb-gui-detection.sh`** (new) — post-install detection via
  Start Menu `.lnk` snapshot/diff: `wb_detect_snapshot_before`,
  `wb_detect_diff_after`, `wb_detect_sweep_stale`, `wb_detect_purge`.
  Parses `.lnk` files via `libexec/wb-lnk-parse.py` (new, Python stdlib only).
- **`src/wb-gui`** — main window rework: "Add App" button (portable /
  installer 2-choice flow), "Settings" opens the 4-pane notebook
  (General / Dist / Prefix / Per-App) on a selected row, "Prefs" opens the
  notebook at General. Settings dialog is persistent across Save: Save re-
  enters the notebook; only Close or Escape exit. New `detect <prefix>`
  sub-command uses a Continue/Cancel question so the user has a clean cancel
  path that purges the snapshot.
- **`src/wb-gui-lib/wb-gui-dialogs.sh`** — new `wb_gui_dialog_question`
  helper for Continue/Cancel question dialogs.
- **`tests/26_apps_migration.bats`**, **`tests/27_settings_layers.bats`**,
  **`tests/28_detection.bats`**, **`tests/29_ui_flows.bats`** (new) — 101
  new bats tests covering the above. All 13 prior `24_gui.bats` cases remain
  green via the legacy dual-write + settings bridge (the bridge is
  transitional and scheduled for removal in v1.7.0).

Also in this release:

### First-run desktop shortcut (parity with PortProton onboarding)

- **`_wb_gui_place_desktop_shortcut()` in `src/wb-gui`** — on first open of
  the main game-library window, wb-gui now drops the `.desktop` launcher on
  the user's Desktop (same UX as PortProton's onboarding). One-shot: guarded
  by `$WB_HOME/.gui-desktop-shortcut-placed` sentinel; opt-out via
  `WB_GUI_NO_DESKTOP_SHORTCUT=1` for headless / CI use. Desktop dir resolved
  via `xdg-user-dir DESKTOP` with fallbacks to `$HOME/Desktop` and the
  Russian localized `$HOME/Рабочий стол`. Source `.desktop` resolved via a
  candidate list (RPM install → `/usr/local` install → `~/.local/share`
  user install → dev tree). `chmod +x` applied so KDE/GNOME treat the
  launcher as trusted; additionally tries `gio set metadata::trusted true`
  for KDE Plasma 5.24+. Safe no-op when source file or Desktop dir
  can't be located. Invoked at the top of `_cmd_main_window`.

### Window/taskbar icon linkage (StartupWMClass + argv[0] rewrite for Wayland)

- **`StartupWMClass=wine-bleeding` + yad `--class=wine-bleeding` + argv[0]
  rewrite** — without these, KDE Plasma / GNOME could not associate wb-gui's
  yad window with the installed `.desktop` entry (yad's default WM_CLASS /
  Wayland app_id is literally `yad`). Plasma fell back to its "first-letter
  placeholder" badge — a yellow rounded tile with a generic "W" glyph — in
  the title bar and taskbar. Three-pronged fix:
  - `share/applications/wine-bleeding-wb.desktop`: added
    `StartupWMClass=wine-bleeding` so the `.desktop` declares its match key.
  - `src/wb-gui-lib/wb-gui-dialogs.sh` `_WB_GUI_YAD_COMMON`: added
    `--class=wine-bleeding` for X11 / XWayland sessions (sets `WM_CLASS`).
  - `src/wb-gui-lib/wb-gui-dialogs.sh` `wb_gui_yad()`: invokes yad via
    `(exec -a wine-bleeding "$(command -v yad)" ...)` so argv[0] is
    rewritten (GTK3 on Wayland derives the xdg-toplevel `app_id` from
    `g_get_prgname()` which defaults to argv[0]; `--class` alone is ignored
    on native Wayland). The same function also exports `GDK_BACKEND=x11`
    before the exec so yad runs under XWayland — Plasma's title-bar
    decoration reads `_NET_WM_ICON` from X11 windows for its icon, while
    the Wayland decoration path didn't consistently pick up the .desktop's
    Icon= even after app_id matching worked for the taskbar. XWayland keeps
    `StartupWMClass` matching working for the taskbar while giving KWin the
    `_NET_WM_ICON` pixels it needs for the decoration.

### Post-install GUI launch fixes

- **`wb-gui` Option A lib-dir fallback (system-install crash fix)** —
  `src/wb-gui` hardcoded `${_WB_GUI_SELF_DIR}/wb-lib` as the library source
  path. After system install that resolved to `/usr/bin/wb-lib/` (wrong —
  libs live at `/usr/lib/wine-bleeding/wb-lib/`) and `wb-gui` crashed on
  startup with `/usr/bin/wb-lib/wb-paths.sh: No such file or directory`.
  Added the same Option A resolver `src/wb` already has: check
  `WB_LIB_DIR`/`WB_GUI_LIB_DIR` env overrides → sibling → `/usr/lib/wine-bleeding`
  → `/usr/local/lib/wine-bleeding`. Resolves both `wb-lib/` and `wb-gui-lib/`
  independently. `_WB_BIN` now prefers `command -v wb` over a sibling guess.
- **Placeholder scalable SVG icon removed + RPM `%pre` cleanup for orphan** —
  `share/icons/hicolor/scalable/apps/wine-bleeding.svg` was an 822-byte
  hand-coded wine-glass-plus-blood-drop stub. FDO IconThemeSpec prefers
  scalable over PNG, so DEs rendered the stub instead of the real
  256/512/1024 PNG artwork. Deleted the placeholder from the source tree.
  An intermediate release (commit 74f00d7fa17) shipped the SVG as a real
  `%files` entry before it was recognised as a placeholder, so users who
  installed that intermediate and then `rpm -Uvh --force` upgraded to the
  SVG-less version ended up with an orphaned SVG on disk (rpm same-version
  `--force` skips the erase-old-files sweep). Added a `%pre` scriptlet that
  `rm -f`'s the SVG path pre-upgrade, safe as a no-op on fresh installs.
  AppImage already prefers the 512 PNG (`build-appimage.sh:135-137`) so
  the AppImage `.DirIcon` is unaffected.
- **wb-gui, `.desktop`, and icons now ship in the RPM payload (was: empty
  `%ghost` paths)** — `packaging/rpm/wine-bleeding-wb.spec` marked the wb-gui
  binary, `wb-gui-lib/`, the `.desktop` launcher, and all icon sizes with
  `%ghost`, a leftover from the pre-M12 era when wb-gui was a dangling
  optional deliverable. `%ghost` makes rpm OWN the path without installing
  the file content, so `rpm -Uvh` left the user with `/usr/bin/wb` + libs
  only — no GUI binary, no menu entry in the Apps → Games category, no
  icons. Since M12 these files are shipped unconditionally from the source
  tree, so the spec now lists them as real `%files` entries. A fresh install
  now places `/usr/bin/wb-gui`, `/usr/share/applications/wine-bleeding-wb.desktop`,
  and the three PNG icons (256/512/1024) on disk.
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

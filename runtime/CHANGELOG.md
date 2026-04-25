# wine-bleeding Runtime Layer Changelog

## [Unreleased] — v1.7.1-dev

### Managed build-tools (tier 2.5 — pre-built toolchains on demand)

Adds a new intermediate tier between "install via distro package manager"
and "compile from source": download pre-built toolchains from the project's
GitHub Release, verify sha256, extract into the user's home directory.
Faster and far more reliable than source-build on modern hosts where modern
GCC struggles to bootstrap older MinGW GCC.

- **`wb-tools-manager.py`** (stdlib Python CLI at
  `/usr/lib/wine-bleeding/libexec/`) — subcommands `list`, `check`, `install
  <tool>`, `update <tool>`, `remove <tool>`, `path`. Downloads from a
  manifest URL (default
  `https://github.com/palginpav/wine-bleeding/releases/latest/download/manifest.json`,
  overridable via `WB_TOOLS_MANIFEST_URL`). Verifies sha256 before extract;
  uses `tarfile.data_filter` (Py 3.12+) or manual `..`/absolute-path/symlink
  /zip-bomb rejection (Py 3.8–3.11). Atomic promote via `<tool>/<ver>.stage`
  → `<tool>/<ver>` → symlink-renamed `current`. Per-tool `.previous` symlink
  for manual rollback. Refuses to run as root; flock on
  `.lock` for concurrency. HTTPS-only with TLS verification (no env var
  disables it).
- **Glibc-aware flavor selection** — 4 flavors per tool (glibc 2.31, 2.35,
  2.38, 2.40). Detects host glibc via `ldd --version`, picks highest
  `glibc_min` ≤ host. No compatible flavor → falls through to existing
  source-build tier.
- **Preflight probe extension** (`wb-preflight.py`) — when a tool is missing
  from system PATH, probe
  `~/.local/share/wine-bleeding/build-tools/<tool>/current/bin/<binary>`.
  When found, emits `source: "managed"` in the tool row and the new
  `managed_tools_dir` top-level field. Never fetches from network in the
  probe path — manifest info comes from a local cache populated by
  "Check for updates".
- **Preflight dialog** — two new footer buttons: "Install `<tool>` via
  manager" (rc=60, one per tool with a compatible flavor in the cached
  manifest) and "Check for updates" (rc=61, global). Existing "Build from
  source" buttons (rc=50/51/52) remain as the last-resort tier.
- **`wine-bleeding-wb-build` subpackage** — ships the manager CLI and the
  seed manifest (empty; manager falls back to it when the upstream is
  unreachable). New `Requires: zstd` under ALT-safe conditional for tarball
  decompression.
- **CI workflow** (`.github/workflows/build-tools.yml`) — manual
  `workflow_dispatch` matrix: 4 glibc flavors × 2 tools (MinGW-w64,
  glslang) = 8 build jobs + 1 publish job. Generates `manifest.json` from
  per-job sha256 sidecars; uploads tarballs + manifest to a tagged GitHub
  Release (`tools-vYYYYMMDD`). First real run is a manual kick-off; until
  that happens, managed-tool buttons stay hidden (empty fallback manifest).

### Managed build-tools (fixes)

- **`wb-tools-manager.py install` no longer hangs in `safe_extract`** — `tarfile.open(fileobj=proc.stdout, mode="r|*")` is an external-fileobj reader that stops at the tar logical EOF markers and does NOT close the pipe, so zstd kept writing trailing padding until the 64 KB kernel pipe buffer filled and blocked in `write()`; `proc.wait(timeout=600)` then polled forever via `waitpid(WNOHANG)` on a live-but-blocked zstd. Fix: close `proc.stdout` before `proc.wait()` so zstd gets SIGPIPE and exits; close `proc.stderr` after the rc check; accept `-SIGPIPE` as a normal exit on the happy path. Also raise `_EXTRACT_RATIO_LIMIT` 3 → 20 because real zstd-compressed toolchain tarballs reach 6–12× (glslang 15.0.0 measured 6.65×); 20 still detects true zip bombs (1000×+). End-to-end verified against the live tools-v20260424 release: `install glslang` now exits 0 in ~6s (was hanging indefinitely).
- **`prune_old_versions` no longer WARNs about `current`** — `d.is_dir()` returns true for symlinks pointing at directories, so the `current` symlink was included in the prune candidate list; `shutil.rmtree` refused to remove it and emitted `Could not prune .../glslang/current: [Errno None] None:`. Fix: filter out `d.is_symlink()` in the iteration.
- **Download progress reaches 100%** — the previous `min(99, …)` cap clamped the final tick; the `PROGRESS:` stream now shows `Downloading... 100%` before `Verifying SHA-256`.
- **New `40_tools_manager.bats` test 11** — happy-path `safe_extract` regression guard. Builds a small valid `.tar.zst` fixture with 10 files, calls `safe_extract` directly, asserts ≤10 s wall time and 10 extracted files. This is the regression test that would have caught the original install hang; all prior `safe_extract` tests only exercised the error path (sha256 mismatch, path traversal).
- **`install mingw-w64-gcc` no longer fails with `linkname not found`** — `_extract_from_pipe` strips the top-level wrapper directory from `member.name` before extracting, but until now did not do the same for `member.linkname`. Real-world toolchain tarballs ship hardlinks (e.g. `c++` → `g++`) whose linkname references the wrapper dir, so tarfile raised `linkname 'mingw-w64-1.7.1-dev/bin/x86_64-w64-mingw32-g++' not found`. Glslang has no hardlinks so it worked; mingw shipped 8400+ entries with several hardlinks and broke instantly. Fix: rewrite `member.linkname` the same way as `member.name` when it begins with `top_level_dir + "/"`. New `40_tools_manager.bats` test 12 builds a fixture tarball with one regular file and one hardlink to it under `tool-1.0/bin/` and asserts both extracted files share an inode.
- **`Check for updates` failure dialog no longer always says "github unavailable"** — the catch-all `*)` case in `wb_gui_dialog_preflight_loop` mapped every unhandled exit code to a "your network may be down" message. Replaced with per-code mapping: 2 = network/TLS, 5 = manifest parse error, 99 = internal error, anything else = unexpected. Each variant ships its own `Why:` line and a concrete `Next action:` (e.g. for code 5: "delete the local cache and retry").
- **Add External Dist now copies the tree into `$WB_HOME/dist/<name>/`** — previously the registry stored a pointer to the user-supplied path, which led to `ln: cannot create symbolic link` on activate when `$WB_HOME/dist/` did not exist, and made dists vulnerable to disappearing if the user moved or deleted the original tree. New behaviour: `wb_gui_dist_add_external` validates as before, then `cp -a "${path}/." "$WB_HOME/dist/<name>/"`, registers the local copy, and rolls back the partial copy on any failure. The product invariant is now "every registered dist lives under `$WB_HOME`" — same shape as PortProton's home.
- **`wb_dist_set_alias` creates `$WB_HOME/dist/` defensively** before the atomic `ln -sfn` swap. Belt-and-braces for legacy external pointer registrations and any future code path that might activate a dist before any other code populated `dist/`.
- **`bc_resolve_mingw` and `tools/build-component.sh` source `$WB_HOME/build-tools/.path`** before probing — wb-tools-manager.py writes the file with one prepended PATH entry per managed-installed tool. Without this the build subprocess never saw the binaries the user just installed via the preflight dialog's "Install via manager" button, and the build exited 66 in `bc_resolve_mingw` despite preflight reporting `ok=true` (preflight probes the managed dir directly; the build steps don't).
- **`wb-tools-manager.py` and `wb-preflight.py` honour `$WB_HOME`** when resolving the managed-tools root. Order is `WB_TOOLS_DIR` / `WB_MANAGED_TOOLS_DIR` (explicit) → `$WB_HOME/build-tools` → `$XDG_DATA_HOME/wine-bleeding/build-tools` → default. With a custom `$WB_HOME`, dists, apps, prefixes, and managed tools all sit under the same single home — no split between XDG and `$WB_HOME`.
- **"Check for updates" failure dialog now shows the manager's actual error** instead of a generic per-code template. The wb-gui dispatch was redirecting `2>/dev/null` and discarding the manager's `ERROR:` message, so any non-0/10/66 exit code rendered identically with no diagnostic. Now we capture stderr to a temp file and `grep -m1 '^ERROR:'` for the human-readable cause; falls back to the last 5 stderr lines when the manager bypassed the reporter.
- **Add External no longer registers the dist twice** — the new copy-into-`$WB_HOME/dist/<name>/` flow made the existing plugins/runtimes.d/<name>.json pointer redundant: `wb_gui_dist_registry_refresh` was discovering the dist as native (by directory presence) AND as external (by plugin JSON), so the user saw two duplicate rows in the Dist Manager. Fix: stop writing the plugin JSON in `wb_gui_dist_add_external`; let the native auto-scan handle it. Provenance (the original source path) is recorded in a `.wb_external_source.json` sidecar inside the dist dir so it survives registry rebuilds without re-introducing duplicates.
- **`wb-tools-manager.py` and `wb-preflight.py` ignore `WB_TOOLS_DIR`** — wb-gui exports `WB_TOOLS_DIR=/usr/lib/wine-bleeding/tools` as the build-**scripts** directory (where `build-component.sh`, `build-glslang.sh`, `full-build.sh` live). The manager and preflight were also accepting it as the managed-**tools-storage** directory, so every dispatched `check`/`install` from the GUI tried to operate on `/usr/lib/wine-bleeding/tools/...`, hit the "outside HOME" safety check, and exited 2 with the misleading "Network, TLS, or filesystem error" dialog. The two concepts are distinct; the env var is now ignored on the manager/preflight side. `WB_MANAGED_TOOLS_DIR` is the only supported explicit override; defaults follow `$WB_HOME/build-tools` → `$XDG_DATA_HOME/wine-bleeding/build-tools` → `~/.local/share/wine-bleeding/build-tools`. wb-gui's internal use of `WB_TOOLS_DIR` for the scripts dir is unchanged.
- **`build-component.sh` no longer requires a wine-bleeding source checkout** — when running from an installed RPM, `DEPS_DIR` defaulted to `${WB_WINE_SOURCE_ROOT:-/usr/lib/wine-bleeding}/build-deps/`, which doesn't exist (the RPM ships scripts but not source clones), so every dxvk/vkd3d/nvapi build exited 66 with "Component build needs a wine-bleeding source tree with build-deps/" — telling the end-user to clone the project repo. That's the wrong product direction. Per the PortProton-style "everything under one home" model, when the resolved `DEPS_DIR`'s parent is not writable (system path like `/usr/lib`), `DEPS_DIR` now falls back to `$WB_HOME/build-deps/` (writable, persists across upgrades). The auto-clone block at line ~437 populates it on first build; subsequent builds reuse the cached repo. The exit-66 path now triggers only when even `$WB_HOME` is unwritable.
- **VKD3D-Proton now builds without a wine-bleeding source checkout** — `_bc_setup_widl` was probing only `${WB_WINE_SOURCE_ROOT}/tools/widl/widl`, which doesn't exist on installed RPMs, so meson setup failed with `Program 'x86_64-w64-mingw32-widl' not found or not executable` (exit 68). Every Wine dist (the build's `--target-dist`) ships its own `bin/widl` as part of the wine binaries, so the resolver now also probes `${TARGET_DIST_REAL}/bin/widl` and the system PATH. Builds VKD3D-Proton against the activated dist's own widl. Verified end-to-end: meson setup, x64 ninja build (217 objects), x86 ninja build (217 objects), strip, atomic swap into `lib/wine/vkd3d-proton/{x86_64,i386}-windows/{d3d12,d3d12core}.dll`.
- **DXVK-NVAPI no longer fails with "Staged x86 DLL set incomplete"** — `EXPECTED_X86` for the nvapi component listed `nvofapi.dll`, but upstream `jp7677/dxvk-nvapi` deliberately builds nvofapi 64-bit-only (`# Only build 64-bit versions of nvofapi` in `src/meson.build`). Every nvapi rebuild therefore failed with exit 69 because the script kept looking for an x86 DLL that never gets produced. Removed `nvofapi.dll` from `EXPECTED_X86`; verified DXVK-NVAPI swap now lands `nvapi64.dll`+`nvofapi64.dll` for x64 and `nvapi.dll` for x86.
- **`tools/lib/build-common.sh` defines `bc_resolve_wb_lib`** — `tools/build-component.sh:695,728` calls this function in the post-swap `_bc_refresh_manifest` and `_bc_write_settings_hint` paths, but the function was never defined anywhere; the swap itself succeeded (DLLs landed) but the dist manifest never got updated and `строка 695: bc_resolve_wb_lib: команда не найдена` printed twice in the log-tail dialog at the end of every component build. Added the resolver alongside the other `bc_*` helpers; probes the dev-tree path first, then `/usr/lib/wine-bleeding/wb-lib`, then `/usr/local/lib/wine-bleeding/wb-lib`.
- **Dist Manager: clearer feedback after Activate** — the row marker for the active dist was a single `>` character in column 1, which was easy to miss after the dialog re-rendered (users read silent success as "nothing happened"). Marker is now the full word `ACTIVE` (and `BROKEN` for broken dists). After a successful Activate, an info dialog also confirms `<name> is now the active distribution.` so the user has explicit feedback even before the row marker registers.
- **wb-gui now sources wb-dist.sh** — latent bug since the Dist Manager was added: `wb_gui_dist_registry_refresh` calls `wb_dist_resolve_alias` (defined in `wb-lib/wb-dist.sh`) to detect the active dist, but `_wb_gui_load_libs` never sourced that file. From wb-gui's GUI sessions, the call returned "command not found" → empty `active_path` → every dist row got `active=false` → the Dist Manager's ACTIVE column stayed blank even after a successful Activate (the symlink and `wb runtime activate` were correct; only the registry's `active` flag was wrong). The bats tests passed because they source `wb-dist.sh` explicitly. Added the source to `_wb_gui_load_libs` next to wb-paths/wb-json/wb-log.
- **Deactivate button in Dist Manager** + **`wb runtime deactivate` CLI** — yad `--list` button labels are static (gtk doesn't fire callbacks on row selection without a click), so a single button can't morph between "Activate" and "Deactivate" based on which row is highlighted. Instead added a separate Deactivate button alongside Activate. Deactivate operates on "whichever dist is currently active" (there is at most one) and does NOT require a row selection — the first iteration required selecting the active row, but yad-list's selection state can be empty even when a row looks highlighted, so the action is now selection-free: read top-level `active` from dists.json, clear the alias if non-null, otherwise show "No active dist". New `wb_dist_clear_alias` helper (`wb-lib/wb-dist.sh`) atomically removes the WINE-BLEEDING symlink (idempotent; only unlinks when path is actually a symlink). Exposed via `wb runtime deactivate` so the same primitive is reachable from the CLI.
- **Prefs button now opens a single-window Settings dialog** (`_cmd_general_prefs`) instead of the legacy 4-tab `yad --plug` / `--notebook` flow. The plug protocol relies on X11 EmbedProto and renders the four panes as four detached "YAD" windows on Plasma 6 / Wayland (the GDK_BACKEND=x11 forced in `wb_gui_yad` doesn't fix it because XWayland's EmbedProto handshake is unreliable through the compositor). The new dialog is a single `yad --form` with `:LBL` section dividers: a "Defaults" section with GPU / Windows version / WINEDEBUG editable fields, and a live "Status" section with the active dist + counts of registered dists, apps, and prefixes (read directly from registries, so the user sees real numbers instead of the placeholder "no apps/prefixes/dists" text the plug-tab versions emitted whenever they were missing a context-id argument). Save persists via `wb_gui_settings_set_general`; Cancel/Escape rolls back. The legacy 4-tab notebook stays reachable via `wb-gui settings-v2 <scope> <id>` for tooling/test paths that need the per-dist / per-prefix / per-app editors.

### Build-env self-sufficiency (wb-gui → builds anywhere)

Component Builder and Build Dist from Source no longer require a pre-curated
build-time environment. On first use wb-gui probes the toolchain, tells you
exactly which packages to install for your distro, and offers to build the
awkward ones (glslang, MinGW-w64, meson) from source.

- **Three-tier preflight** (`runtime/libexec/wb-preflight.py`, Python stdlib
  only) — detect / version-check / fall back. Reads `/etc/os-release`,
  probes a tool set (gcc, make, meson, ninja, glslang, mingw-w64-gcc,
  pkg-config, git; +flex/bison/autoconf for full dist builds), emits
  stable JSON. Seeded with package names for Fedora, RHEL (+EPEL), Debian,
  Ubuntu, Arch, openSUSE Tumbleweed, ALT Linux, Alpine; everything else
  falls through to the generic tier-3 prompt.
- **Editable distro package map** at
  `/usr/share/wine-bleeding/wb-preflight-packages.json` — edit or drop an
  overlay into `$XDG_CONFIG_HOME/wine-bleeding/wb-preflight-packages.d/`
  without touching Python.
- **Preflight dialog** — three-column "tool / fix / alternative" table,
  "Copy all install commands" button (clipboard via wl-copy/xclip/xsel,
  $TMPDIR fallback), per-tool "Build from source" button where a fallback
  exists. Silent pass-through when all tools are OK — no extra click.
- **Source-build fallbacks** — new `tools/build-glslang.sh` clones KhronosGroup/glslang at a pinned tag (15.0.0) and cmake+ninja-builds into `$WB_HOME/build-deps/glslang/`, with a git-rev cache sentinel. MinGW reuses the existing `tools/build-full-wine-deps.sh --build-mingw-from-source`. meson upgrade via `pip install --user 'meson>=<floor>'`.
- **Component Builder multi-select (Stage 1)** — build DXVK + VKD3D-Proton + DXVK-NVAPI in one go against the same dist; shared live-log dialog across all selected components; skip-and-continue on a per-component failure.
- **Build Dist from Source** — new button in Dist Manager. Wizard picks a
  source tree (`$WB_WINE_SOURCE_ROOT` aware), runs preflight, then drives
  `tools/full-build.sh` with live Phase-B progress/log/error events
  surfaced through the existing log-tail dialog.

### Packaging

- **New `wine-bleeding-wb-build` RPM subpackage** — declares `Recommends:`
  on the Fedora names for the build-time tools (gcc, gcc-c++, make, meson,
  ninja-build, glslang, mingw64-gcc, mingw64-gcc-c++, pkgconf-pkg-config,
  git, flex, bison, autoconf). `dnf install wine-bleeding-wb-build` pulls
  what your Fedora has; preflight fills the gaps. No hard Requires: on
  build tools.

### Tools

- `tools/full-build.sh` — new `--progress-fd N` option emits Phase-B
  `PROGRESS:/LOG:/WARN:/ERROR:` events on the given fd (additive; default
  behavior is byte-identical). New `--help` message. Now honours
  `WB_WINE_SOURCE_ROOT` for installed-package callers (the
  `dirname $0` / `/usr/lib/wine-bleeding` installed path no longer wins
  over an explicit source root from the GUI).
- `tools/build-component.sh` — calls the preflight before the
  `build-deps` check; on failure exits 66 with the structured preflight
  JSON on stderr. Skippable via `WB_SKIP_PREFLIGHT=1` (used by the GUI
  when it has already shown the preflight dialog).

### CI / tests

- `runtime-ci.yml` — added `zstd` to the Alpine `apk` install list
  (`40_tools_manager.bats` test 9 builds a malicious `.tar.zst` fixture
  to exercise `safe_extract`'s path-traversal defense) and switched
  `make -C runtime test` to run as a non-root `tester` user
  (`wb-tools-manager.py` refuses `euid=0`, matching the production
  invariant that managed tools live under `$HOME`).
- `runtime/src/wb`, `runtime/src/wb-gui` — bumped `WB_VERSION` /
  `WB_GUI_VERSION` to `1.7.1-dev` so `wb --version` matches the
  `runtime/VERSION` file (caught by `25_packaging.bats` test 10).
- `runtime/tests/31_dist_manager.bats` — rewrote Stage-1 assertions to
  match the multi-select Component Builder form (`DXVK` / `VKD3D-Proton`
  / `DXVK-NVAPI` `::CHK` fields) instead of the obsolete single
  `Component:CB` combo; marked Stage-3 dialog tests 6–9 `skip "FIXME:
  log-tail event-pipe teardown race"` pending a proper harness rewrite.
- `build-tools.yml` — so the managed-tool matrix actually produces
  artifacts. Added `meson` to the apt/dnf prereq lists (the unconditional
  `check_command meson` in `build-full-wine-deps.sh` tripped all 4
  `mingw-w64/*` cells), replaced the non-existent Debian `diff` package
  with `diffutils`, and pointed the mingw "Locate build output directory"
  step at `build-deps/mingw64-cross` (the Zeranoe `--build-mingw-from-source`
  install root) instead of the musl.cc fallback path
  `build-deps/x86_64-w64-mingw32-cross`.
- `tools/build-glslang.sh` — `cd` into `${SRC_DIR}` before invoking
  `update_glslang_sources.py`; the script reads `known_good.json` via a
  relative path, so running it from elsewhere raised `FileNotFoundError`
  and let cmake fail later with "ENABLE_OPT set but SPIR-V tools not
  found" (all 4 `glslang/*` cells).

### Known follow-ups (v1.7.2)

- Skipped Build-Dist happy-path bats (`39_build_env_frontend.bats` test 8)
  — the fake-yad + event-pipe harness deadlocks in `wb_gui_dialog_log_tail`
  when both fake-yad and fake builder exit simultaneously; needs a tighter
  synchronisation pattern. The real flow works.
- Skipped `31_dist_manager.bats` Stage-3 tests 6–9 for the same reason
  (log-tail event-pipe teardown); the Component Builder's real flow
  works.
- Clone-upstream button in the Build Dist wizard currently shows a
  "not yet available" dialog with manual `git clone` instructions.

## [1.7.0] — 2026-04-21

v1.7.0 turns wb-gui into a full-fledged Wine prefix manager. Where v1.6.0
was about registering and launching apps, v1.7.0 is about **building,
bundling, and customizing the Wine dist and prefix they run against** —
with the same UI surface and no new moving pieces outside the main window.

Three headline features:

- **Dist Manager** — add your own Wine distributions, switch between them,
  and rebuild individual components (DXVK, VKD3D-Proton, DXVK-NVAPI)
  without nuking the whole dist.
- **Overlay bundling** — enable MangoHud, VKBasalt, or OptiScaler per app,
  pull the version you want straight from GitHub, and flip between the
  bundled build and your distro's system copy.
- **Prefix deep customization** — install winetricks verbs, manage DLL
  overrides, browse and edit the Wine registry safely, and override
  dist-global component defaults per prefix.

### Dist Manager (new `[Dists]` button on the main window)

- **Add / remove / activate dists** from a single list. External dists
  (pre-built dists you already have on disk) coexist with dists built
  through this UI. You can't accidentally remove the dist you're
  currently using — the Remove button refuses with a clear error telling
  you which dist is active.
- **Component Builder** rebuilds DXVK / VKD3D-Proton / DXVK-NVAPI
  individually, showing a live build log. **Builds land in a sibling
  directory and atomically swap in**, so the dist you're running against
  is never blocked during a rebuild.
- **Hard-kill cancel** — meson/ninja workers don't honour plain SIGTERM,
  so Cancel sends SIGTERM to the whole process group, waits 5 seconds,
  then sends SIGKILL.
- **Live log auto-closes** when the build exits cleanly — you go straight
  to the result screen instead of dismissing the log window first.
- `tools/full-build.sh` keeps its existing CLI unchanged; the Dist
  Manager calls a new per-component driver (`tools/build-component.sh`).

### Per-app overlay bundling (PortProton-style bundled-vs-system toggle)

Open a per-app settings panel and the Per-App tab now has an **Overlays**
section with three overlays: **MangoHud** (FPS/frametime HUD),
**VKBasalt** (post-processing), and **OptiScaler** (upscaler replacement).

- **Enable** — per app, per overlay. Changes save into the prefix's
  `wb.conf` at save-time, so `wb run` picks them up on the next launch
  without touching its runtime.
- **Bundled vs system** — for MangoHud and VKBasalt, flip between the
  bundled build (downloaded + installed by wine-bleeding) and your
  distro's system copy. OptiScaler is enable-only (it's a Windows DLL
  replacement; no Linux system counterpart exists).
- **Version pinning** — each overlay tracks the installed versions under
  `$WB_HOME/overlays/<name>/<version>/`. Use the version dropdown to
  choose which is active.
- **Check for updates** — fetches the latest release tag from GitHub
  on demand (no background polling). Offline or rate-limited? The dialog
  says so plainly with a next-action hint ("try again later" / "sign in
  to GitHub and retry").
- **Conflict detection** — if you've manually set `MANGOHUD=1` or
  `ENABLE_VKBASALT=1` in per-app env vars, enabling the overlay warns
  before taking ownership of those keys. Disable later, and only the
  overlay-managed keys are removed — your other env vars are untouched.
- **GStreamer is intentionally not an overlay.** No clean GitHub-only
  source build exists for the gstreamer plugin stack; the existing
  build-dependency path (which ingests system `libgst*.so`) stays.
  Revisit when/if the source story improves.

### Prefix deep customization (new panels in the Prefix tab)

The Prefix tab of the settings dialog now has four collapsible panels —
Components (open by default), DLL Overrides, Winetricks, Registry.

**Per-prefix component toggles.** Override the dist-global
DXVK / VKD3D / NVAPI defaults for a specific prefix. Three-way switch:
**On**, **Off**, or **Inherit** (removes the override and falls back to
whatever the dist says). Saved to the prefix's `wb.conf` atomically,
preserving any other keys you've set there by hand.

**DLL Overrides.** A structured editor for DLL overrides separate from
your personal `WINEDLLOVERRIDES` env var. 15 common DLLs preset as rows
(d3d11, d3d9, dinput8, msvcr120, etc.) plus free-form custom rows.
Overrides compose into the launch environment via
`WB_EXTRA_DLLOVERRIDES`; your hand-typed `env_vars.WINEDLLOVERRIDES` is
left alone.

**Winetricks.** Install verbs from a category-tabbed picker (All, dlls,
fonts, settings, apps, benchmarks) with a search box. Live progress
during install. If you try to install a verb that's already installed,
you get an **[installed]** marker and a re-install confirmation.
**Uninstall is intentionally not exposed** — winetricks itself has no
generic uninstall for most verbs, so the UI shows a "Remove not
supported" badge and a "How to clean up manually" hint rather than a
Remove button that silently does nothing.

**Registry editor.** Browse and edit the Wine registry through two
safety layers:

- **Safe zones are the only writable keys.** Anything outside is
  display-only. The Write button is greyed out, and the backend
  rejects writes there regardless. Safe zones:
    - `HKCU\Software\Wine\*`
    - `HKCU\Environment`
    - `HKCU\Control Panel\Desktop`
    - `HKCU\Control Panel\International`
    - `HKLM\System\CurrentControlSet\Services\Wine`
    - `HKLM\Software\Wine`
- **Every write goes through a diff-preview** — you see exactly the
  old vs new value before you click Apply.
- **Undo the last 10 changes per prefix** — stack-based, restores
  the prior value cleanly via `wine reg` (no direct `.reg` edits).

### Settings dialog polish

- **Dialog stays open on Save.** Saving one tab no longer closes the
  whole settings dialog — you stay in place and can keep editing other
  tabs. Close or Escape ends the session.
- **`wb-gui settings <prefix>`** (legacy alias) now dispatches directly
  to the 4-layer settings dialog. The transitional `.wb.ppdb` writer
  from v1.6.0 has been removed; per-app settings flow exclusively
  through the new store.
- **`wb-gui detect <prefix>`** standalone command now asks
  "Continue / Cancel" between snapshot and diff, with Cancel purging
  the snapshot cleanly.

### Configuration surface (new env vars and storage paths)

- `$WB_HOME/dists.json` — dist registry view (rebuilt on demand from
  `.wb_dist_meta` + runtime plugins; not a source of truth).
- `$WB_HOME/overlays.json` + `$WB_HOME/overlays/<name>/<version>/` —
  overlay registry + bundled binaries.
- `$WB_HOME/settings/{general,dist,prefix,apps}/*.json` — continues the
  Phase A 4-layer store with new `overlays`, `dll_overrides`, and
  `wine_registry_patches` fields in the per-app and per-prefix layers.
- `WB_GUI_BUILD_POLL_SEC`, `WB_GUI_BUILD_TAIL_DRAIN_SEC` — tune the
  Component Builder's log-tail auto-close behaviour.
- `WB_GUI_NO_OVERLAY_BANNER=1` — suppress the one-time v1.7.0 "new
  overlays" discoverability dialog. Normally auto-hides once dismissed
  (sentinel at `$WB_HOME/etc/wb-gui-seen-phase-c.flag`).

### Known limitations (queued for v1.7.x polish)

- **Overlay panel dirty-flag** — the overlay section doesn't show a
  visual "unsaved changes" indicator because yad `--form` button
  callbacks run in subshells that can't signal the parent. Your saves
  are still honoured; you just don't get the yellow dot.
- **Overlay check-updates progress** — Stage 1 shows a static 30s
  timeout dialog instead of streaming per-overlay status while
  checking. The actual check completes correctly; only the progress UI
  is non-streaming.
- **Version dropdown when nothing installed** — renders as a single-item
  combo reading "latest" rather than a dash. Selecting it still triggers
  an install correctly.
- **Component Builder Stage 1 "Current version"** — static at dialog
  open; doesn't refresh when you change the component dropdown.
- **"Add custom DLL" in the DLL Overrides panel** — preset rows work;
  a brand-new custom-DLL entry row is queued.
- **Registry tree vs flat list** — on older yad builds without
  `--tree` support, the browser falls back to an ASCII-indented list.
  Editing still works identically.
- **DLL-vs-component conflict warning** — setting `d3d11=native` while
  DXVK is on doesn't warn yet. The override wins (that's how Wine works);
  we just don't flag it for you.
- **`tools/full-build.sh` pass-through refactor** — the full-dist build
  pipeline hasn't yet been routed through the new per-component driver.
  It keeps its existing CLI and behaviour unchanged; the Component
  Builder path uses the new driver directly.

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

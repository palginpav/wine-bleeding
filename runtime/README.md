# runtime — Developer README

**v1.0.0-MVP** — The MVP release of the wine-bleeding native runtime layer.
This release ships all nine planned MVP milestones (M0-M8) and is the
foundation for post-MVP features (GUI, multi-build, container isolation).
Post-MVP items are listed in the "Post-MVP scope" section below.

This directory contains the wb-runtime source tree.
It is a sibling of `tools/`, `dlls/`, and `server/` and is intentionally
independent of Wine's build system.

## Directory layout

```
runtime/
  src/
    wb                   # top-level CLI dispatcher
    wb-diag              # diagnostic helper stub
    wb-lib/
      wb-log.sh          # logger helpers (stub; real impl in M1)
      wb-die.sh          # fatal-error helper (stub; real impl in M1)
  share/
    defaults.conf        # shipped read-only defaults skeleton
    schemas/             # JSON schemas (populated from M2 onward)
  tests/
    00_sanity.bats       # sanity suite (3 tests)
    lib/common.bash      # shared bats helpers
    fixtures/            # fake dist/prefix trees for tests
    vendor/              # git submodule: bats-core
  install.sh             # installer stub (real logic in M7)
  Makefile               # test / lint / install targets
  README.md              # this file
```

## Dependencies

- **bash >= 4.4** (associative arrays, `[[ ]]`, `set -euo pipefail`)
- **jq >= 1.6** — hard dependency from M1 onward. Required for `wb config show`,
  `wb_json_read`, `wb_json_write_atomic`, and `wb log tail`. Install via your
  package manager (`apt install jq`, `dnf install jq`, etc.)
- **flock** — advisory locking (`util-linux`; present on all major Linux distros)
- **shellcheck** (for `make lint`)
- **bats-core** (for `make test`) — see below; init the submodule with:

      git submodule update --init -- runtime/tests/vendor/bats-core

- **check-jsonschema** (optional, for `make schema-check`) — validates `.wb_dist_meta`
  against `runtime/share/schemas/wb_dist_meta.schema.json`. Install via pip:

      pip install check-jsonschema

## Developer setup

### Prerequisites

- bash >= 4.4
- jq >= 1.6 (hard dependency for M1+; see Dependencies above)
- shellcheck (for `make lint`)
- bats-core (for `make test`) — see below

### bats-core submodule

bats-core is vendored as a git submodule. After cloning the repo, initialise it:

    git submodule update --init -- runtime/tests/vendor/bats-core

If the submodule is not present, `make test` falls back to any system `bats` on PATH,
or prints a skip message and exits 0 so CI is not broken.



### Running tests

    make -C runtime test

### Running lint

    make -C runtime lint

### Installing (stub — available from M7)

    make -C runtime install PREFIX=/path/to/target

## Milestone status

| Milestone | Status | Notes |
|-----------|--------|-------|
| M0 | done | Foundation scaffolding (this commit) |
| M1 | done | Logger, config loader (5-layer jailed), lock, JSON helpers, paths |
| M2 | done | Dist manifest, runtime install/activate/prune/list/info |
| M3 | done | Prefix lifecycle: classify, adopt (coexist/take-over), list, info, import |
| M4 | done | Component deploy, fresh prefix create + wineboot, .wb.ppdb reader/importer |
| M5 | done | `wb run` launch dispatcher: env composition, hooks chain, exec |
| M6 | done | PP-plugin mode: reapply hook, install/uninstall, deploy-to-portproton refactor |
| M7 | done | Standalone installer, migration scaffolding (migrate/export), release packaging |
| M8 | done | Snapshot/repair, log rotation, wb-diag support bundle, MVP polish |
| M9 | done | Multi-build / distro-switching (`wb run --runtime NAME`, `wb runtime list --multi`) |
| M11 | done | Pressure-vessel / SLR container opt-in (`WB_CONTAINER=1`) |
| M13 | done | Runtime plugin registry (`wb runtime register/unregister`, external runtimes in list + resolver) |
| M14 | done | Flatpak packaging (`org.wine_bleeding.wb.yaml`), sandbox-aware PP detection |

## M14 — Flatpak install (advanced / post-MVP)

Distributes `wb` via Flatpak for distros where PATH/XDG setup is awkward or
where sandboxed delivery is preferred.

### Building from source

```bash
# From the repo root
flatpak-builder build-dir runtime/flatpak/org.wine_bleeding.wb.yaml
```

### Test-installing locally

```bash
flatpak-builder --user --install build-dir runtime/flatpak/org.wine_bleeding.wb.yaml
flatpak run org.wine_bleeding.wb --version
```

### Caveats

- **No build toolchain inside Flatpak**: `full-build.sh` (Wine build from source)
  is not included.  Download a pre-built `wine-bleeding` dist tarball separately
  and register it with `wb runtime install /path/to/tarball`.
- **PortProton plugin mode** requires the `--filesystem=~/PortProton` permission
  to be granted at Flatpak install time (the manifest already requests it).
  Sandbox detection uses `$FLATPAK_ID`; the resolved path inside the sandbox is
  `/run/host/home/<user>/PortProton`.
- **user.conf mutations**: prefer running `wb pp-install` from outside the
  sandbox (standalone install) so `user.conf` is written by the host environment.

See `runtime/flatpak/README.md` for full build instructions and Flathub
submission notes.

## M13 — Runtime plugin registry

Enables advanced users to register external Wine builds — GE-Proton, Lutris,
custom forks — as selectable runtimes alongside wb's own `dist/` dists.

### Registering an external runtime

Create a plugin JSON descriptor:

```json
{
  "schema": 1,
  "name": "GE-Proton-9-26",
  "path": "/home/user/.steam/root/compatibilitytools.d/GE-Proton9-26",
  "kind": "external",
  "wine_major_version": "9",
  "notes": "GloriousEggroll's Proton build"
}
```

Required fields: `schema` (always `1`), `name` (alphanumeric + `_.-`), `path`
(absolute, no whitespace). Optional: `kind`, `wine_major_version`, `notes`.

Then register it:

```bash
wb runtime register /path/to/ge-proton-9-26.json
# registered: GE-Proton-9-26
```

The file is copied atomically into `$WB_HOME/plugins/runtimes.d/GE-Proton-9-26.json`.
Re-registering the same content is a no-op.

### Listing runtimes (including externals)

```bash
wb runtime list            # native + external, with KIND column
wb runtime list --native   # only dist/ entries
wb runtime list --external # only plugin entries
wb runtime list --multi    # add MULTI column (M9 flag, works orthogonally)
```

### Using an external runtime

```bash
wb config enable-multibuild
wb run game.exe --runtime GE-Proton-9-26
```

Resolver precedence (first match wins):
1. `$WB_HOME/dist/<NAME>/` — native dist (always wins on name collision)
2. `$WB_HOME/plugins/runtimes.d/<NAME>.json` — external plugin path
3. `WINE-BLEEDING` alias symlink target (fallback for the stable alias)

### Unregistering

```bash
wb runtime unregister GE-Proton-9-26
# unregistered: GE-Proton-9-26
```

### Schema

Plugin files are validated against
`runtime/share/schemas/wb_runtime_plugin.schema.json` (JSON Schema Draft 2020-12).
Run `make schema-check` to validate the fixture against the schema.

### Security notes

- `path` is recorded as-is; symlinks are **not** resolved at register time
  (consistent with M11 policy of not granting bind-mount access via symlink).
- `name` is validated against `^[A-Za-z0-9_.-]+$` before any filesystem
  operation — path traversal via `..` or slashes is rejected immediately.
- Plugin JSON is written atomically via `wb_json_write_atomic` (temp + `mv -T`).

## M7 — Standalone installer + migration (M7)

### Standalone install

```bash
./runtime/install.sh
```

Installs wb-runtime to `${XDG_DATA_HOME:-~/.local/share}/wine-bleeding` and
creates a `~/.local/bin/wb` symlink. The installer is idempotent: running it
twice produces zero file changes.

Override the install location:

```bash
./runtime/install.sh --prefix /opt/wine-bleeding
```

### PortProton plugin install

```bash
./runtime/install.sh --portproton-plugin [--pp-root ~/PortProton]
```

Installs wb-runtime into `$PP_ROOT/data/wb/` and hooks into PP's `user.conf`
via `add_in_start_portwine`. Equivalent to running M6's `wb_pp_install_hook`.

### PATH note

If `~/.local/bin` is not in your PATH, the installer prints a WARN with the
exact export line to add to `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
```

### Uninstall

```bash
./runtime/install.sh --uninstall          # removes installed files; preserves prefixes/ and profile.conf
./runtime/install.sh --uninstall --purge  # wipes everything including prefixes
```

### Dry-run

All modes support `--dry-run`: prints the intended actions but writes nothing.

### Prefix migration

Migrate a PortProton prefix into wb:

```bash
wb prefix migrate --from-portproton GAME [--pp-path ~/PortProton] [--overwrite]
```

This **copies** (never moves) the PP prefix into `$WB_HOME/prefixes/GAME/`
and runs `wb prefix adopt --take-over` on the copy. The PP original is
untouched; verify the migrated prefix works before deleting it manually.

Export a wb prefix back to PortProton:

```bash
wb prefix export --to-portproton GAME [--pp-path ~/PortProton] [--overwrite]
```

Round-trip safety: both migrate and export are non-destructive by default.
Use `--overwrite` only when intentionally replacing the target.

### PortProton plugin via wb subcommand

```bash
wb install portproton-plugin
```

Thin wrapper that locates and invokes `install.sh --portproton-plugin`.

## Prefix subcommands (M3)

The `wb prefix` family manages Wine prefix lifecycle without invoking Wine.

```
wb prefix list                  List known prefixes (name, classification, last-adopted time)
wb prefix info <NAME|PATH>      Show classification and .wb_runtime sentinel JSON
wb prefix adopt <PATH>          Adopt an existing PortProton prefix (coexist mode)
wb prefix adopt <PATH> --take-over   Claim full ownership (rewrites .wine_ver only; wineboot in M4)
wb prefix import <PATH>         Adopt a prefix and symlink it into $WB_HOME/prefixes/
```

Classifications emitted by `wb prefix classify`:
- `absent` — directory does not exist
- `wb-native` — owned by wb-runtime with `pp_coexist=false`
- `shared-adopted` — owned by wb-runtime with `pp_coexist=true`
- `pp-owned-untouched` — PortProton prefix not yet adopted
- `broken` — any other state (diagnostic only; repair is M8)

See `.orchestray/kb/artifacts/runtime-layer-roadmap.md` for the full milestone plan.

## M5 — `wb run` launch dispatcher

### New subcommands

```
wb run <exe> [--prefix NAME] [--runtime NAME] [--wait] [args...]
    Launch an executable via Wine. Full §5.2 call graph:
      1. Load config (5-layer jailed config system)
      2. Resolve runtime (dist path) and prefix
      3. Acquire prefix lock
      4. Run pre-reconcile, pre-materialize hooks; idempotent component reconcile; post-materialize hooks
      5. Run pre-exec hook (failure aborts launch)
      6. Compose Wine environment (WINEDEBUG, WINEDLLOVERRIDES, DXVK_*, VKD3D_*, etc.)
      7. Release lock, then exec wine (no trap fires after exec)
      --wait: fork+wait instead of exec; enables post-exec hook with $WB_EXIT

wb exec <exe> [args...]
    Launch via Wine, skipping reconcile entirely (debugging only).
    Prints WARN and execs without hooks or lock.
```

### Hooks directory layout

Hooks live in `$WB_HOME/plugins/hooks.d/` and are sourced in sorted order per phase:

| Phase suffix | When |
|---|---|
| `.pre-reconcile.sh` | Before prefix state check |
| `.pre-materialize.sh` | Before component deploy |
| `.post-materialize.sh` | After component deploy |
| `.pre-exec.sh` | After env compose, before exec. Failure aborts launch. |
| `.post-exec.sh` | After wine exits (only with `--wait`). Gets `$WB_EXIT`. |

Files ending in `.example` are never loaded. Invalid filenames are silently skipped.
Symlinks pointing outside `$WB_HOME/plugins/hooks.d/` are skipped with a WARN.

An example hook is installed at `runtime/plugins/hooks.d/00-example.pre-exec.sh.example`.

## M6 — PortProton plugin mode

### Overview

M6 makes wb-runtime usable as a PortProton plugin. When a user selects the
`WINE-BLEEDING` dist in PortProton's GUI, wb's hook ensures components (DXVK,
VKD3D-Proton, NVAPI) stay deployed and `.wine_ver` stays correct — preventing
PortProton from issuing an unwanted `wineboot -r` on each launch.

### Install

```
wb pp install          # appends hook block to $PORT_WINE_PATH/data/user.conf
wb pp status           # report hook state
wb pp uninstall        # restore user.conf from backup; remove wb tree
```

`PORT_WINE_PATH` defaults to `~/PortProton`. Set it to override.

### What gets written

- `$PORT_WINE_PATH/data/user.conf` — appended with a fenced `# BEGIN wb-runtime`
  / `# END wb-runtime` block containing an `add_in_start_portwine` function override.
- `$PORT_WINE_PATH/data/wb/hooks/reapply.sh` — the hook script (chmod +x).
- `$PORT_WINE_PATH/data/wb/lib/` — copies of required wb-lib shell libraries.
- `$PORT_WINE_PATH/data/user.conf.wb-backup-<UTC>` — unconditional backup of
  `user.conf` made before any write.

### Backward-compat promise

`tools/deploy-to-portproton.sh` preserves its full pre-refactor CLI surface.
All existing flags and positional forms continue to work. A frozen copy of the
pre-refactor script is kept at `tools/deploy-to-portproton.sh.legacy` for one
release cycle (M6 through M8).

### Uninstall

`wb pp uninstall` restores `user.conf` from the most-recent backup. If no backup
exists, it removes only the `# BEGIN wb-runtime` … `# END wb-runtime` block via
`sed`. It also deletes the entire `$PORT_WINE_PATH/data/wb/` tree.

### New subcommands (M6)

```
wb pp install      Install hook into PortProton user.conf
wb pp uninstall    Remove hook (restore from backup or sed-fence-removal)
wb pp status       Report: PP path, hook installed y/n, reapply.sh present y/n, .wine_ver match y/n
```

### exec/trap caveat

`wb run` replaces itself with wine via `exec`. Bash trap handlers registered in hooks
DO NOT fire after exec replaces the shell. Use `--wait` mode if you need the `post-exec`
hook to observe the wine exit code.

### Environment composition

`wb_env_compose` translates `WB_*` variables to Wine env vars:

| WB var | Wine var | Rule |
|---|---|---|
| `WB_DEBUG_WINE` (default `-all`) | `WINEDEBUG` | verbatim |
| `WB_ESYNC=1` | `WINEESYNC=1` | only if =1 |
| `WB_FSYNC=1` | `WINEFSYNC=1` | only if =1 |
| `WB_NTSYNC=1` | `WINENTSYNC=1` | only if =1 |
| `WB_DXVK=1` | `WINEDLLOVERRIDES` | DXVK dll names with `=n` |
| `WB_VKD3D=1` | `WINEDLLOVERRIDES` | VKD3D dll names with `=n` |
| `WB_NVAPI=1\|auto` | `WINEDLLOVERRIDES` | NVAPI dll names with `=n` |
| `WB_EXTRA_DLLOVERRIDES` | `WINEDLLOVERRIDES` | appended verbatim; validated |

`WINEDLLOVERRIDES` is validated with a strict regex before exec. Malformed
`WB_EXTRA_DLLOVERRIDES` (e.g., shell injection attempts) cause exit 1.

## M4 — Component deploy + fresh prefix create + .wb.ppdb reader

### New subcommands

```
wb prefix init [NAME] [--runtime NAME] [--dist PATH]
    Create and initialise a Wine prefix.
    Runs wineboot --init via the dist's wine binary, then deploys DXVK, VKD3D-Proton,
    DXVK-NVAPI, wine-mono, and ICU. Takes ~30 s against a real Wine dist.
    Tests use fake-wine so CI is fast and hermetic.

wb prefix components [NAME]
    Print the .wb_components JSON manifest for an initialised prefix.

wb prefix reconcile [NAME]
    Re-deploy all components idempotently. Restores missing DLLs without
    invoking wine or wineserver.

wb import-ppdb <INPUT> [OUTPUT]
    Convert a legacy PortProton bash-style .ppdb to a strict-JSON .wb.ppdb.
    OUTPUT defaults to INPUT.wb.ppdb.
    The input file is executed in a sandboxed bash --restricted subshell
    (no rm, cp, curl, etc. reachable) to guard against malicious payloads.
```

### Dependencies

- `jq >= 1.6` — hard runtime dependency (unchanged from M1).
- `python3` — soft dependency. Used by `wb-components.sh` to inspect PE headers
  and zero the Wine builtin DLL marker. If absent, component deploy still works
  but unsigned DLLs will not be marker-zeroed (Wine may prefer builtin over native).

### Performance note

`wb prefix init` calls `wine wineboot --init` which on a real Wine dist takes
approximately **30 seconds** on an average workstation (Wine builds a fresh registry
hive and populates the prefix tree). CI always uses the fake-wine fixture so all
tests complete in milliseconds.

### Manual smoke test

After building a real dist (see `tools/full-build.sh`):

```bash
export WB_HOME=~/.local/share/wine-bleeding
# Install and activate a dist first:
wb runtime install /path/to/WINE-BLEEDING-DDMMYYYY.tar.gz --activate

# Create a fresh prefix:
wb prefix init test-prefix

# Run an application inside it:
WINEPREFIX="$WB_HOME/prefixes/test-prefix" \
  "$WB_HOME/dist/WINE-BLEEDING/bin/wine" notepad
```

A successfully initialised prefix will open Notepad without errors.

## M8 — Snapshot/repair, log rotation, wb-diag (v1.0.0-MVP)

### Snapshot and repair

Capture the recoverable state of a prefix at any time:

```bash
wb prefix snapshot GAME
```

List available snapshots (newest first):

```bash
wb prefix snapshots GAME
```

After PortProton's `pw_clear_pfx` wipes a prefix, recover it:

```bash
wb prefix repair GAME              # prompts for confirmation
wb prefix repair GAME --yes        # non-interactive
wb prefix repair GAME --yes --from-snapshot 2026-04-19T12:00:00Z
```

Repair re-runs wineboot + component deployment + DllOverrides from the snapshot.
User data (game saves, Documents) is intentionally NOT restored — snapshots
carry only metadata, never file contents (privacy by design).

### Log rotation

`wb-log.sh` rotates `wb.log` to `wb.log.1` .. `wb.log.5` when the log file
reaches 10 MB. Override the threshold:

```bash
export WB_LOG_MAX_BYTES=5242880    # 5 MB
```

Uses `flock` to prevent concurrent writers from racing during rotation.

### wb-diag support bundle

Collect a support bundle for bug reports:

```bash
wb-diag                 # creates wb-diag-<UTC>.tar.gz in the current directory
wb-diag --dry-run       # lists what would be collected without creating the tarball
```

The tarball includes env vars, version info, runtime/prefix listings, log tail,
and per-prefix JSON sentinels. It NEVER includes `drive_c/` contents, `user.reg`,
`system.reg`, `user.conf`, or auth tokens.

## Multi-build / distro-switching (post-MVP / advanced)

**Status: available as of v1.1.0-dev (M9). Opt-in only.**

This feature lets advanced users switch between multiple wb-managed Wine dists on a
single prefix WITHOUT the destructive `wineboot -r` that PortProton fires on every
version-string mismatch.

### Enabling multi-build

```bash
wb config enable-multibuild
```

This writes `WB_MULTIBUILD=1` into `$WB_HOME/etc/runtime.conf`.

### Listing dists with multi-build view

```bash
wb runtime list --multi
```

Shows an extra `MULTI` column indicating which dists are real (non-alias) directories.

### Switching dists per-launch

```bash
wb run notepad.exe --prefix MYPFX --runtime WINE-BLEEDING-v2
```

If the new dist has the **same major Wine version** as the current one, only components
(DXVK, VKD3D, etc.) are redeployed — no wineboot fires.

If the new dist has a **different major version**, consent is required:

```bash
# Either pass --yes-wineboot:
wb run notepad.exe --prefix MYPFX --runtime WINE-BLEEDING-v2 --yes-wineboot

# Or set this env/config flag for automatic consent:
WB_AUTO_WINEBOOT_ON_MAJOR_CHANGE=1 wb run ...
```

Without consent, `wb run` exits with code **42** so callers can detect and prompt the user.

### Viewing runtime-switch history

```bash
wb prefix history MYPFX
```

Prints a table of `FROM_UTC`, `TO_UTC`, and `RUNTIME` for every switch. The active
entry shows `TO_UTC=active`.

### Safety guarantees

- wb fires `wineboot -u` (update mode), NOT `-r` (which wipes `drive_c/windows/`).
- History is written atomically via `wb_json_write_atomic`.
- Re-adopting a prefix (`wb prefix adopt`) preserves existing `history[]` and
  `current_runtime` fields — they are never clobbered.

## M11 — Pressure-vessel / SLR container isolation (post-MVP / advanced)

**Status: available as of v1.2.0-dev (M11). Opt-in only. Requires manual SLR install.**

This feature lets advanced users run Wine inside a
[Steam Linux Runtime (pressure-vessel)](https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/blob/master/docs/container-runtime.md)
sandbox for library-version isolation. The SLR container pins the runtime
libraries (glibc, Mesa, etc.) to a known-good Steam Sniper snapshot, which can
improve compatibility with games that ship native Linux libraries.

### Prerequisites

pressure-vessel is distributed as part of **Steam Linux Runtime - Sniper** (~1 GB),
available in Steam under `Tools`. Install it there first:

1. Open Steam → Library → Tools → **Steam Linux Runtime - Sniper** → Install
2. After installation the entry-point appears at:
   `~/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point`

Alternatively, point `$WB_CONTAINER_ENTRY` at any compatible pressure-vessel
`_v2-entry-point` binary.

**wb does not auto-download pressure-vessel.** This is intentional: the download
is large and requires an active Steam account. Future milestones may add a guided
install prompt (M12).

### Enabling container mode

```bash
wb config enable-container
```

Writes `WB_CONTAINER=1` to `$WB_HOME/etc/runtime.conf`. All subsequent `wb run`
and `wb exec` invocations wrap wine inside the pressure-vessel sandbox.

### Disabling container mode

```bash
wb config disable-container
```

Removes `WB_CONTAINER` from `runtime.conf`. Wine is invoked directly again.

### Overriding the entry-point

Set `$WB_CONTAINER_ENTRY` to the absolute path of the `_v2-entry-point` executable
to override the default detection order:

```bash
export WB_CONTAINER_ENTRY="/opt/slr/_v2-entry-point"
wb run notepad.exe --prefix MYPFX
```

### What changes at launch

When `WB_CONTAINER=1`, `wb run` replaces the direct wine exec with:

```
<entry-point> --filesystem=<prefix_path> --verb=waitforexitandrun -- <wineloader> <exe> [args...]
```

All `WB_*`-derived environment variables (WINEPREFIX, WINEDLLOVERRIDES, etc.) are
still composed and passed through `env` into the container.

### Graceful failure when SLR is not installed

If pressure-vessel is not found and `$WB_CONTAINER_ENTRY` is not set, wb prints a
clear error and exits 1 without launching wine:

```
wb run: pressure-vessel not found; install Steam Linux Runtime via Steam
wb run: (Tools > Steam Linux Runtime - Sniper) or set $WB_CONTAINER_ENTRY
```

### Limitations

- Nested container support (running wb inside another container) is not supported.
- No GUI install prompt — see post-MVP M12.
- Auto-download of SLR is deferred to a future milestone if user demand warrants it.

## Post-MVP scope

The following features are planned for later post-M11 milestones:

- **GUI launcher** (M12) — graphical front-end for wb with SLR install prompt
- **Go CLI rewrite** (M10) — performance-focused rewrite of the bash dispatcher
- **External runtime registry** (M13) — `plugins/runtimes.d/*.json` for third-party dists

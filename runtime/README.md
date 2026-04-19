# runtime — Developer README

This directory contains the wb-runtime source tree (milestone M0 scaffold).
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
| M8+ | planned | Snapshot/repair, log rotation, multi-build switching |

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

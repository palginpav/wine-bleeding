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
| M5+ | planned | Wine dispatch (wb run), hook system, multi-build switching |

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

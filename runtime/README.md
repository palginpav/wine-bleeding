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
| M2+ | planned | Dist manifest, prefix lifecycle, Wine dispatch |

See `.orchestray/kb/artifacts/runtime-layer-roadmap.md` for the full milestone plan.

> **Status: Active development — M0 foundation complete.**
> Repo scaffolding, CI, and test harness have landed. The user-facing behaviors
> described here reflect the accepted architecture (W3) and roadmap (W5) and
> arrive across milestones M1–M14. Commands, paths, and behaviors are subject
> to change before the first release.

# wine-bleeding Native Runtime Layer

`wb-runtime` is a first-party launcher and prefix manager for wine-bleeding. It owns
the full compatibility stack — Wine binaries, DXVK/VKD3D-Proton/DXVK-NVAPI, patched
wine-mono, wine-icu, and native sidecar libraries — without depending on PortProton to
stay installed, stay configured, or survive a distro reinstall. Users who want a
standalone wine-bleeding experience, or who are tired of having their setup silently
broken by PortProton's distro-switch logic, are the primary audience.

`wb-runtime` (command name: `wb`) does not replace PortProton. It coexists with it.
Existing PortProton prefixes can be adopted without losing their data. The
`tools/deploy-to-portproton.sh` integration that PP users depend on continues to work.
If you are happy with PortProton today, nothing changes for you.

---

## Why it exists

PortProton's current design treats the selected Wine distribution as the ground truth
for every launch decision. Switching distributions — which happens automatically when a
user reinstalls PortProton, migrates to a new distro, or changes the active build in
the GUI — triggers a sentinel mismatch check that forces a prefix reset, wiping
`system32`, DllOverrides, and all deployed DLLs. For wine-bleeding users running
through PortProton, this means DXVK, VKD3D, and wine-mono are silently stripped on
every such event. Recovery requires manually rerunning `deploy-to-portproton.sh` and
hoping no game data was lost in the wipe (W3 §7, W2 failure analysis, chains 1 and 2).

The root cause is structural: PortProton was not designed to host a third-party
compatibility stack that survives its own upgrade and switch paths. `wb-runtime` solves
this by owning the stack directly, bypassing PortProton's distro-switch logic entirely
when running standalone, and defending against it with a re-apply hook when running
as a PortProton plugin.

---

## Architecture summary

### Directory layout

`wb-runtime` installs into a single root directory, `$WB_HOME`, which defaults to
`~/.local/share/wine-bleeding/`. Everything the runtime needs — Wine builds, prefixes,
caches, config — lives under this root, or under standard XDG paths that survive a wipe
of `$WB_HOME`.

```
$WB_HOME/
├── bin/
│   ├── wb                    # main CLI (symlinked into ~/.local/bin/)
│   └── wb-diag               # diagnostic helper
├── dist/
│   ├── WINE-BLEEDING         # stable alias symlink → active dated build
│   ├── WINE-BLEEDING-28032026/   # actual Wine build tree
│   └── WINE-BLEEDING-15032026/   # older build, kept for rollback
├── prefixes/
│   └── <NAME>/
│       ├── drive_c/, system.reg, user.reg, ...   # standard Wine
│       ├── .wb_runtime       # wb sentinel (JSON; PP never reads this)
│       ├── .wine_ver         # PortProton-compat sentinel (always "WINE-BLEEDING")
│       └── .wb_components    # JSON manifest of deployed DLL versions
├── cache/
│   ├── dxvk-state/           # DXVK pipeline cache
│   ├── vkd3d-shader/         # VKD3D shader cache
│   └── mono-shared/          # shared wine-mono copy (one per version)
├── plugins/
│   └── hooks.d/              # user hook scripts, run at launch
├── etc/
│   └── runtime.conf          # user configuration
└── log/
    └── wb.log                # session log (JSON lines, rotating)
```

State that must survive a full wipe of `$WB_HOME` lives outside it:

```
~/.config/wine-bleeding/profile.conf     # host-wide preferences
~/.cache/wine-bleeding/                  # download cache (disposable)
```

### Dispatch flow — `wb run`

When you run `wb run game.exe`, the following happens in order:

```
wb run <exe>
  │
  ├── load config layers
  │     defaults.conf → profile.conf → runtime.conf → <prefix>/wb.conf
  │     → <exe>.wb.ppdb (JSON game sidecar) → WB_* environment variables
  │
  ├── resolve Wine build
  │     single-build mode (default): always uses WINE-BLEEDING alias
  │     sets WINE, WINESERVER, WINELOADER, WINEDLLPATH
  │
  ├── resolve prefix
  │     from --prefix, WB_PREFIX env, or "DEFAULT"
  │     sets WINEPREFIX (absolute path)
  │
  ├── acquire prefix lock
  │     flock on <PREFIX>/.wb_lock; fails fast if another wb holds it
  │
  ├── reconcile prefix (cheap, idempotent)
  │     check .wb_runtime sentinel — adopt if missing, error if broken
  │     diff .wb_components vs expected versions → deploy missing/stale DLLs
  │
  ├── compose environment
  │     WINEDEBUG, WINEDLLOVERRIDES, DXVK_STATE_CACHE_PATH,
  │     WINE_ESYNC/FSYNC/NTSYNC, LD_LIBRARY_PATH, etc.
  │
  ├── run pre-exec hooks (plugins/hooks.d/*.sh)
  │
  ├── exec Wine
  │     exec <WINELOADER> <exe> <args>
  │
  └── run post-exec hooks
```

Steady-state launch overhead (healthy prefix, no DLL changes) is under 100 ms. First
launch of a new prefix includes a `wineboot --init` run, which takes 10–30 seconds,
identical to what PortProton does on prefix creation.

---

## User-facing commands (planned)

All commands below are planned. None are implemented yet.

| Command | Description |
|---------|-------------|
| `wb run <exe> [--prefix NAME]` | Launch a Windows executable under the named prefix. Creates the prefix if it does not exist. |
| `wb runtime list` | List installed Wine builds and which one is currently active. |
| `wb runtime install <tarball>` | Install a wine-bleeding dist tarball and register it. |
| `wb runtime activate <NAME>` | Switch the active build alias to a specific dated build. |
| `wb runtime prune [--keep N]` | Remove old builds beyond the N most recent. |
| `wb runtime info <NAME>` | Show component versions and checksums for a build. |
| `wb prefix list` | List all prefixes managed by wb. |
| `wb prefix init [NAME]` | Create a new prefix and initialize it (wineboot + DLL deploy). |
| `wb prefix adopt <PATH>` | Adopt an existing PortProton prefix without wiping it. |
| `wb prefix info <NAME>` | Show sentinel state, component versions, and last-launch time. |
| `wb prefix snapshot <NAME>` | Save a snapshot of the prefix component state for recovery. |
| `wb prefix repair <NAME>` | Redeploy components into a prefix from its last snapshot. |
| `wb config show` | Print the effective configuration (all layers merged). |
| `wb config path <KEY>` | Show which config file supplied a specific key. |
| `wb log tail` | Print the last 50 log entries. |
| `wb-diag prefix <NAME>` | Run diagnostics on a prefix and report any inconsistencies. |

`wb import-ppdb <file>` (planned, M4): one-time conversion of a PortProton bash `.ppdb`
sidecar to wb's JSON `.wb.ppdb` format.

---

## Phased delivery

Full-scope target, delivered across phased milestones M0-M14. The first eight milestones
(M0-M8) produce a complete standalone runtime; M9-M14 add the extended feature set.

### M0-M8 — standalone runtime (~7 weeks single developer)

Nine milestones covering everything needed for a working standalone runtime:

| Milestone | What it delivers |
|-----------|-----------------|
| M0 | Repo layout, CI, shell scaffold |
| M1 | `wb` CLI core: config loading, logging, locking |
| M2 | Dist manifest (`.wb_dist_meta`) and `wb runtime` subcommands |
| M3 | Prefix init, list, info, and PortProton prefix adoption |
| M4 | Component deployment (DXVK/VKD3D/NVAPI/mono/ICU) and JSON `.wb.ppdb` reader |
| M5 | `wb run` dispatcher: env composition, hook phases, Wine exec |
| M6 | PortProton-plugin mode: `reapply.sh` hook, `user.conf` integration |
| M7 | Standalone installer `install.sh` and uninstaller |
| M8 | Snapshot and repair (`wb prefix snapshot`, `wb prefix repair`) — MVP release |

The MVP release tag is `v1.0.0`. Detailed milestone specs live in
`.orchestray/kb/artifacts/runtime-layer-roadmap.md`.

### Post-MVP (Full scope)

| Milestone | What it adds |
|-----------|-------------|
| M9  | Multi-build / distro-switching opt-in (`wb config enable-multibuild`) |
| M10 | Optional Go rewrite of `wb` (if shell friction warrants it) |
| M11 | Pressure-vessel / Steam Linux Runtime container opt-in |
| M12 | GUI (`wb-gui`) and Steam Compatibility Tool entry |
| M13 | Plugin registry (`runtimes.d/*.json`) for external Wine builds |
| M14 | Flatpak packaging |

---

## Backward compatibility with PortProton

`wb-runtime` maintains a documented, bidirectional contract with PortProton. No
PortProton internals are patched.

**What PortProton users get unchanged:**
- `tools/deploy-to-portproton.sh` continues to work exactly as it does today. PP-first
  users who do not install `wb` see no change.
- Existing PortProton prefixes can be adopted by `wb prefix adopt` without wiping their
  contents. Game saves, registry state, and installed software are untouched.
- In PortProton-plugin mode (M6), `wb-runtime` installs a `reapply.sh` hook into PP's
  `add_in_start_portwine` extension point. This hook reconciles DLL state after every
  PP launch, making wine-bleeding DLLs survive PP distro-switches without requiring
  the user to do anything.

**What wb-runtime maintains for PP compatibility:**
- The `.wine_ver` sentinel in every managed prefix always contains the string
  `WINE-BLEEDING` (the stable alias name, not a date stamp). This matches what
  PortProton reads, so PP's `.wine_ver` mismatch check never fires against our prefix.
- Our dist tree (`WINE-BLEEDING/`) maintains the exact directory structure PortProton
  expects: `bin/wine`, `lib/wine/`, DXVK/VKD3D in the paths PP's `PW_USE_SUPPLIED_*`
  flags resolve. PP symlinks into our tree; those symlinks resolve correctly.

---

## Security posture

These are design decisions made in response to the W4 threat review.

**Strict-JSON config by default.** Game sidecar files (`.wb.ppdb`) use a versioned JSON
schema instead of bash. There is no shell evaluation of untrusted game-side config files
at launch time. The existing PortProton bash `.ppdb` format can be converted to JSON via
`wb import-ppdb` (one-time, explicit).

**No silent shell-source of sidecars.** Unlike PortProton's design, `wb run` never
bash-sources a file sitting next to the game executable. Config files in controlled
locations (`runtime.conf`, `profile.conf`) use a key=value parser with an explicit
allowlist of permitted variable names.

**Tarball signing (planned).** The `wb runtime install` command is designed to verify a
signature on every dist tarball before extracting. The signing scheme (minisign, Ed25519)
and key distribution strategy will be finalized before the first public release. During
development, `--skip-verify` is available with a logged warning.

**Hook script restrictions.** User hook scripts in `plugins/hooks.d/` must be owned by
the invoking user and not group- or world-writable. wb logs the full path of every hook
it runs.

---

## Where to track progress

- Roadmap and milestone specs: `.orchestray/kb/artifacts/runtime-layer-roadmap.md`
- Architecture decisions: `.orchestray/kb/decisions/runtime-layer-design.md`
- Threat review: `.orchestray/kb/artifacts/runtime-layer-threat-review.md`
- Orchestration: `orch-20260418T214700Z`

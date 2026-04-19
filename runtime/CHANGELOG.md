# wine-bleeding Runtime Layer Changelog

## [Unreleased] — v1.1.0-dev

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

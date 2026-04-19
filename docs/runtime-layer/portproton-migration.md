> **Status: Planned — post-MVP.**
> The migration steps described here require `wb-runtime` to be installed (MVP, M7).
> They are not available yet. This document describes the intended process.

# Migrating from PortProton to wb-runtime

## Who this is for

You are currently running wine-bleeding through PortProton — you installed
wine-bleeding via `tools/deploy-to-portproton.sh`, you launch games through
PortProton's GUI or `pp-launch`, and your prefixes live under
`~/PortProton/data/prefixes/`. You have seen your DXVK or VKD3D installation
silently disappear after a PortProton update or distro reinstall, and you would like
that to stop.

This guide covers how to move those prefixes under `wb-runtime` control while keeping
PortProton installed and functional.

If you have never used PortProton, this guide does not apply to you. See the main
[README](README.md) for a standard first-time setup.

---

## What changes, what stays

| | Before (PortProton) | After (wb-runtime) |
|---|---|---|
| How you launch games | PortProton GUI or `pp-launch` | `wb run <exe>` or PortProton GUI (coexist mode) |
| Where prefixes live | `~/PortProton/data/prefixes/<name>/` | Same path (adopted) or `~/.local/share/wine-bleeding/prefixes/<name>/` (new) |
| DXVK/VKD3D survival after distro switch | Lost — requires manual re-deploy | Preserved — wb reconciles on every launch |
| PortProton still installed | Yes | Yes |
| `deploy-to-portproton.sh` still works | Yes | Yes, unchanged |
| Game saves and installed software | Owned by the prefix | Untouched during adoption |
| `.wine_ver` sentinel | Written by PP (`WINE-BLEEDING-DDMMYYYY`) | Managed by wb (`WINE-BLEEDING`, stable alias) |
| Config sidecar format | Bash `.ppdb` | JSON `.wb.ppdb` (convert with `wb import-ppdb`) |

The most important row: **PortProton stays installed**. This is not a removal process.
You can keep using PortProton's GUI, continue to rely on `deploy-to-portproton.sh` for
PP-first users, and switch back to PP-only operation at any time.

---

## Coexistence period

During the period when both PortProton and `wb-runtime` are installed against the same
prefix:

- PortProton reads `.wine_ver` and sees `WINE-BLEEDING`. Its sentinel check passes; it
  does not trigger a prefix reset.
- `wb-runtime` reads `.wb_runtime` (a JSON file PP ignores) for its own state.
- Either launcher can start the prefix. The prefix contents are the same either way.
- If PortProton's distro-switch logic fires and re-symlinks DLLs, the next `wb run`
  detects the change and re-materializes the real files. If you launch through PP and
  `wb-runtime` is in PP-plugin mode (M6), the `reapply.sh` hook does this within the
  same PP session.

You do not need to pick one launcher immediately. Run both in parallel and switch
permanently only when you are confident `wb` is working for you.

---

## Step-by-step migration (planned, post-MVP)

These steps will be available once `wb-runtime` v1.0.0 (MVP, M7) is released.

### Step 1 — Install wb standalone

Download the `wb-runtime` tarball for your architecture and run the installer:

```
install.sh
```

This places `wb` and `wb-diag` in `~/.local/bin/`, creates `$WB_HOME` at
`~/.local/share/wine-bleeding/`, and installs the `WINE-BLEEDING` dist alias pointing
at your current wine-bleeding build.

Verify the install:

```
wb --version
wb runtime list
```

The install does NOT touch PortProton or any existing prefix.

### Step 2 — Adopt a PortProton prefix

Point `wb` at an existing PortProton prefix:

```
wb prefix adopt ~/PortProton/data/prefixes/<name>
```

What happens:
- wb reads the existing `.wine_ver`, `winetricks.log`, and `user.reg` (read-only pass).
- wb writes `.wb_runtime` with `pp_coexist: true`. No other files are changed.
- DXVK, VKD3D, NVAPI, and mono versions are inventoried from the current prefix state
  and written to `.wb_components`.

The prefix is now under wb supervision. Game saves, installed software, and registry
state are untouched.

If you have a PortProton bash `.ppdb` sidecar for a game, convert it once:

```
wb import-ppdb /path/to/game.exe.ppdb
```

This writes a JSON `.wb.ppdb` alongside it and does not delete the original.

### Step 3 — Verify

Run the diagnostic tool against the adopted prefix:

```
wb-diag prefix <name>
```

This checks that the sentinel is consistent, that all expected DLLs are present and
at the correct version, and that the Wine build resolves correctly. Fix any issues it
reports before switching your primary launcher.

### Step 4 — Switch launcher

For the adopted prefix, launch games through `wb` instead of PortProton:

```
wb run --prefix <name> /path/to/game.exe
```

PortProton remains installed. You can still open it and use it for other prefixes or
other builds. Only prefixes you have adopted with `wb prefix adopt` are under wb
supervision.

---

## Rollback

To return a prefix to PortProton-only management:

1. Remove the `.wb_runtime` file from the prefix directory. PortProton never reads this
   file, so removing it does not affect PP at all.
2. Optionally remove `.wb_components` as well.
3. The prefix is now invisible to `wb`. PortProton manages it exactly as before.

No data is lost. The only thing `wb prefix adopt` writes to a PortProton prefix are the
`.wb_runtime` and `.wb_components` files.

To fully uninstall `wb-runtime`:

```
install.sh --uninstall
```

This removes `$WB_HOME` and the `wb`/`wb-diag` symlinks from `~/.local/bin/`. It does
not touch PortProton or any prefix, adopted or otherwise.

---

## Deprecation policy

**The PortProton plugin path (`deploy-to-portproton.sh`) will not be deprecated.**

PortProton is a widely used launcher with its own user base. wine-bleeding's existing
integration with it — `tools/deploy-to-portproton.sh` and the PP-plugin mode introduced
in M6 — is a supported, maintained path, not a migration stepping stone.

Concretely:
- `tools/deploy-to-portproton.sh` is not being removed or frozen.
- The PP-plugin mode (`reapply.sh` hook) added in M6 is a first-class feature, not a
  temporary shim.
- Users who prefer to run wine-bleeding through PortProton's GUI indefinitely have a
  supported path to do so.

---

## Known caveats

**PP distro-switch on non-adopted prefixes.** PortProton's distro-switch fragility
applies only to prefixes that PortProton manages without a `wb-runtime` re-apply hook
in place. If you have prefixes that you are not adopting into `wb`, those prefixes
remain vulnerable to PortProton's reset behavior on distro-switch events, exactly as
they are today.

**PP plugin-version bump wipes adopted prefixes.** If PortProton fires `pw_clear_pfx`
on a prefix (triggered by a plugin-version bump or manual reinstall), the prefix
contents are destroyed before any hook fires. This is a PortProton limitation that
`wb-runtime` cannot prevent. Defense: `wb prefix snapshot <name>` saves a recovery
manifest; `wb prefix repair <name>` redeploys all components from that snapshot after a
wipe. Run a snapshot before any PortProton upgrade if you are concerned.

**First launch after PP distro-switch and back.** If you switch the active build in
PortProton's GUI to something other than `WINE-BLEEDING` and then back, PortProton will
see a sentinel mismatch on the "back" switch and run `wineboot -r`. The next `wb run`
(or the `reapply.sh` hook if in plugin mode) detects this and reconciles. The first
launch will be slower than normal; subsequent launches return to steady-state speed.

**Bash `.ppdb` files are not auto-converted.** `wb run` does not automatically source
PortProton bash `.ppdb` sidecars. Run `wb import-ppdb <file>` once per game to produce
a JSON `.wb.ppdb`. Until you convert, `wb run` launches that game without game-specific
config overrides. This is intentional: automatic bash-sourcing of game-side files is a
security risk (see W4 threat review).

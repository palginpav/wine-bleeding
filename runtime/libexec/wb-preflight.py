#!/usr/bin/env python3
"""
wb-preflight.py — Build-environment preflight detector for wine-bleeding.

Reads /etc/os-release, probes a requested tool set, compares versions against
floors, looks up distro-specific install hints in wb-preflight-packages.json,
and emits JSON on stdout.

Usage:
    wb-preflight.py [--json | --pretty]
                    [--tool NAME[,NAME...]]
                    [--build-type {components|dist}]
                    [--package-map PATH]
                    [--overlay-dir PATH]
                    [--os-release PATH]
                    [--version]
                    [--help]

Exit codes:
    0  — overall_ok=true (all requested tools pass)
    1  — overall_ok=false (at least one tool missing or version too old)
    2  — argument error (unknown tool name, bad --build-type, etc.)
    99 — internal error (unexpected exception)

Dependencies: Python 3.8+ stdlib only.
"""

import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

__version__ = "1.0.0"

# ---------------------------------------------------------------------------
# Tool ordering for --build-type (pipeline order, W1 design §4 OQ-2)
# ---------------------------------------------------------------------------

_TOOLS_COMPONENTS = [
    "gcc", "make", "meson", "ninja", "glslang", "mingw-w64-gcc", "pkg-config", "git",
]

_TOOLS_DIST = _TOOLS_COMPONENTS + ["flex", "bison", "autoconf"]

_VALID_TOOLS = {
    "meson", "ninja", "glslang", "mingw-w64-gcc", "gcc", "make",
    "pkg-config", "git", "python3", "flex", "bison", "autoconf",
}

# Source-build fallback slugs per tool (None = no automated fallback)
_SOURCE_BUILD_SLUGS: dict[str, str | None] = {
    "meson": "pip-install-meson",
    "glslang": "wb-build-glslang",
    "mingw-w64-gcc": "build-mingw-from-source",
}

_SOURCE_BUILD_LABELS: dict[str, str] = {
    "pip-install-meson": "Install meson >= {floor} via pip (user-level, no sudo)",
    "wb-build-glslang": "Build glslang from source (~15 min)",
    "build-mingw-from-source": "Build MinGW-w64 from source (~30-60 min)",
}

_SOURCE_BUILD_CMDS: dict[str, str] = {
    "pip-install-meson": "python3 -m pip install --user 'meson>={floor}'",
    "wb-build-glslang": "tools/build-glslang.sh --progress-fd {fd}",
    "build-mingw-from-source": "tools/build-full-wine-deps.sh --only-mingw --build-mingw-from-source",
}

# ---------------------------------------------------------------------------
# Package map discovery
# ---------------------------------------------------------------------------

def _find_package_map(script_dir: pathlib.Path) -> pathlib.Path | None:
    """Locate wb-preflight-packages.json using XDG_DATA_DIRS and dev-tree fallback."""
    candidates = []

    # XDG_DATA_DIRS (system-installed)
    xdg_data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    for base in xdg_data.split(":"):
        if base:
            candidates.append(pathlib.Path(base) / "wine-bleeding" / "wb-preflight-packages.json")

    # Also try /usr/share directly (common case)
    candidates.append(pathlib.Path("/usr/share/wine-bleeding/wb-preflight-packages.json"))

    # Dev-tree sibling: runtime/share/ relative to runtime/libexec/
    dev_tree = script_dir.parent / "share" / "wb-preflight-packages.json"
    candidates.append(dev_tree)

    for c in candidates:
        if c.is_file():
            return c
    return None


# ---------------------------------------------------------------------------
# os-release parsing
# ---------------------------------------------------------------------------

def _parse_os_release(path: str) -> dict:
    """Parse KEY=VALUE pairs from os-release; handle quoted values."""
    result = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, _, val = line.partition("=")
                # Strip surrounding quotes
                val = val.strip()
                if (val.startswith('"') and val.endswith('"')) or \
                   (val.startswith("'") and val.endswith("'")):
                    val = val[1:-1]
                result[key] = val
    except OSError:
        pass
    return result


def _detect_distro(os_release_path: str | None, known_distros: set) -> dict:
    """Return distro info dict from os-release. Falls back to unknown."""
    paths = []
    if os_release_path:
        paths = [os_release_path]
    else:
        paths = ["/etc/os-release", "/usr/lib/os-release"]

    fields = {}
    for p in paths:
        fields = _parse_os_release(p)
        if fields:
            break

    distro_id = fields.get("ID", "unknown").lower()
    id_like_raw = fields.get("ID_LIKE", "")
    id_like = [x.strip().lower() for x in id_like_raw.split() if x.strip()]
    version_id = fields.get("VERSION_ID", "")
    pretty_name = fields.get("PRETTY_NAME", distro_id)

    # Check if recognized: distro_id or any id_like is a known key
    recognized = distro_id in known_distros or any(il in known_distros for il in id_like)

    return {
        "id": distro_id,
        "id_like": id_like,
        "version_id": version_id,
        "pretty_name": pretty_name,
        "recognized": recognized,
    }


# ---------------------------------------------------------------------------
# Package map loading + overlay merge
# ---------------------------------------------------------------------------

def _load_package_map(map_path: pathlib.Path) -> dict:
    with open(map_path, encoding="utf-8") as f:
        return json.load(f)


def _merge_overlay(base: dict, overlay: dict) -> None:
    """Merge overlay into base in-place. Tool-entry level replacement."""
    # Floors overlay (may appear without distros section)
    if "_floors" in overlay:
        base.setdefault("_floors", {}).update(overlay["_floors"])

    if "distros" not in overlay:
        return
    base_distros = base.setdefault("distros", {})
    for distro_id, distro_data in overlay.get("distros", {}).items():
        if distro_id not in base_distros:
            base_distros[distro_id] = distro_data
            continue
        if "tools" in distro_data:
            base_distros[distro_id].setdefault("tools", {}).update(distro_data["tools"])
        # Merge distro-level fields too (display_name, etc.)
        for k, v in distro_data.items():
            if k != "tools":
                base_distros[distro_id][k] = v



def _load_map_with_overlays(
    map_path: pathlib.Path | None,
    overlay_dir: str | None,
) -> tuple[dict, list[str], list[dict]]:
    """
    Return (merged_map, overlays_loaded, overlay_errors).
    """
    if map_path is None:
        raise RuntimeError("wb-preflight-packages.json not found")

    pkg_map = _load_package_map(map_path)
    overlays_loaded: list[str] = []
    overlay_errors: list[dict] = []

    # Determine overlay dir
    if overlay_dir is None:
        xdg_cfg = os.environ.get(
            "XDG_CONFIG_HOME",
            os.path.join(os.path.expanduser("~"), ".config"),
        )
        overlay_dir = os.path.join(xdg_cfg, "wine-bleeding", "wb-preflight-packages.d")

    overlay_path = pathlib.Path(overlay_dir)
    if overlay_path.is_dir():
        for json_file in sorted(overlay_path.glob("*.json")):
            try:
                with open(json_file, encoding="utf-8") as f:
                    overlay = json.load(f)
                # Basic shape check
                if not isinstance(overlay, dict):
                    raise ValueError("top-level must be a JSON object")
                _merge_overlay(pkg_map, overlay)
                overlays_loaded.append(str(json_file))
            except (json.JSONDecodeError, ValueError, OSError) as exc:
                overlay_errors.append({
                    "path": str(json_file),
                    "message": str(exc),
                })

    return pkg_map, overlays_loaded, overlay_errors


# ---------------------------------------------------------------------------
# Version comparison
# ---------------------------------------------------------------------------

_VER_RE = re.compile(r"(\d+)\.(\d+)(?:\.(\d+))?")


def _parse_version(ver_str: str) -> tuple[int, int, int] | None:
    """Parse 'major.minor[.patch]' into a tuple; return None on failure."""
    m = _VER_RE.search(ver_str)
    if not m:
        return None
    major = int(m.group(1))
    minor = int(m.group(2))
    patch = int(m.group(3)) if m.group(3) is not None else 0
    return (major, minor, patch)


def _version_ok(detected: str | None, minimum: str | None) -> bool:
    """Return True if detected >= minimum. Returns True if minimum is None."""
    if minimum is None:
        return True
    if detected is None:
        return False
    d = _parse_version(detected)
    m = _parse_version(minimum)
    if d is None or m is None:
        return False
    return d >= m


# ---------------------------------------------------------------------------
# Tool probing
# ---------------------------------------------------------------------------

# Per-tool probe commands (command, args)
_PROBE_CMDS: dict[str, list[str]] = {
    "meson":          ["meson", "--version"],
    "ninja":          ["ninja", "--version"],
    "glslang":        ["glslangValidator", "--version"],
    "mingw-w64-gcc":  ["x86_64-w64-mingw32-gcc", "--version"],
    "gcc":            ["gcc", "--version"],
    "make":           ["make", "--version"],
    "pkg-config":     ["pkg-config", "--version"],
    "git":            ["git", "--version"],
    "python3":        ["python3", "--version"],
    "flex":           ["flex", "--version"],
    "bison":          ["bison", "--version"],
    "autoconf":       ["autoconf", "--version"],
}

# Alternative probe commands tried when the primary fails (for tools with multiple names)
_PROBE_ALTERNATIVES: dict[str, list[list[str]]] = {
    "glslang": [["glslang", "--version"]],
    "mingw-w64-gcc": [
        ["mingw64-gcc", "--version"],
        ["x86_64-w64-mingw32-gcc-14", "--version"],
    ],
    "pkg-config": [["pkgconf", "--version"]],
}

# Which executable name to use for shutil.which (primary)
_WHICH_NAMES: dict[str, str] = {
    "glslang": "glslangValidator",
    "mingw-w64-gcc": "x86_64-w64-mingw32-gcc",
    "pkg-config": "pkg-config",
}


def _probe_tool(name: str) -> tuple[bool, str | None, str | None]:
    """
    Probe a tool's presence and version.
    Returns (found, path_or_None, version_or_None).
    """
    which_name = _WHICH_NAMES.get(name, name)

    # Find executable path
    tool_path = shutil.which(which_name)

    # For tools with alternatives, also try alternates for path discovery
    if tool_path is None and name in _PROBE_ALTERNATIVES:
        for alt_cmd in _PROBE_ALTERNATIVES[name]:
            alt_path = shutil.which(alt_cmd[0])
            if alt_path is not None:
                tool_path = alt_path
                break

    found = tool_path is not None

    if not found:
        return False, None, None

    # Extract version
    cmds_to_try: list[list[str]] = [_PROBE_CMDS[name]]
    if name in _PROBE_ALTERNATIVES:
        cmds_to_try.extend(_PROBE_ALTERNATIVES[name])

    for cmd in cmds_to_try:
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=10,
            )
            output = result.stdout + result.stderr
            m = _VER_RE.search(output)
            if m:
                return True, tool_path, m.group(0)
        except (subprocess.TimeoutExpired, OSError, FileNotFoundError):
            continue

    # Found but version not extractable
    return True, tool_path, None


# ---------------------------------------------------------------------------
# Install command resolution
# ---------------------------------------------------------------------------

def _resolve_distro_key(distro: dict, pkg_map: dict) -> str | None:
    """
    Find the best matching distro key in pkg_map['distros'].
    Tries: distro['id'], then each entry in distro['id_like'].
    Returns None if nothing matches.
    """
    distros = pkg_map.get("distros", {})
    if distro["id"] in distros:
        return distro["id"]
    for il in distro.get("id_like", []):
        if il in distros:
            return il
    return None


def _build_install_cmd(distro_key: str | None, tool_name: str, pkg_map: dict) -> str | None:
    """Build the install command string for a tool on a given distro."""
    if distro_key is None:
        # Fallback distro
        fallback = pkg_map.get("fallback", {})
        tool_entry = fallback.get("tools", {}).get(tool_name, {})
        pkg_name = tool_entry.get("package_name", tool_name)
        tmpl = fallback.get("install_cmd_template", "Use your distro's package manager to install: {packages}")
        return tmpl.replace("{packages}", pkg_name)

    distros = pkg_map.get("distros", {})
    distro_data = distros.get(distro_key, {})
    tool_entry = distro_data.get("tools", {}).get(tool_name, {})

    pkg_parts = []
    pkg_name = tool_entry.get("package_name")
    if pkg_name:
        pkg_parts.append(pkg_name)
    for extra in tool_entry.get("package_name_extra") or []:
        pkg_parts.append(extra)

    if not pkg_parts:
        # No package info for this tool on this distro; use fallback
        fallback = pkg_map.get("fallback", {})
        fb_tool = fallback.get("tools", {}).get(tool_name, {})
        pkg_name = fb_tool.get("package_name", tool_name)
        pkg_parts = [pkg_name]

    packages_str = " ".join(pkg_parts)

    # Per-tool install_cmd_template overrides distro-level
    tool_tmpl = tool_entry.get("install_cmd_template")
    if tool_tmpl:
        return tool_tmpl.replace("{packages}", packages_str)

    distro_tmpl = distro_data.get("install_cmd_template", "")
    if distro_tmpl:
        return distro_tmpl.replace("{packages}", packages_str)

    return f"Install {packages_str} using your distro's package manager"


def _get_tool_notes(distro_key: str | None, tool_name: str, pkg_map: dict) -> str | None:
    if distro_key is None:
        return None
    distro_data = pkg_map.get("distros", {}).get(distro_key, {})
    return distro_data.get("tools", {}).get(tool_name, {}).get("notes")


def _get_floor_override(distro_key: str | None, tool_name: str, pkg_map: dict) -> str | None:
    if distro_key is None:
        return None
    distro_data = pkg_map.get("distros", {}).get(distro_key, {})
    return distro_data.get("tools", {}).get(tool_name, {}).get("floor_override")


def _get_source_build_fallback(distro_key: str | None, tool_name: str, pkg_map: dict) -> str | None:
    """Get source_build_fallback slug: distro map takes precedence; then global default."""
    if distro_key is not None:
        distro_data = pkg_map.get("distros", {}).get(distro_key, {})
        tool_entry = distro_data.get("tools", {}).get(tool_name, {})
        if "source_build_fallback" in tool_entry:
            return tool_entry["source_build_fallback"]
    # fallback from global defaults
    return _SOURCE_BUILD_SLUGS.get(tool_name)


# ---------------------------------------------------------------------------
# Main probe logic
# ---------------------------------------------------------------------------

def _probe_all_tools(
    tool_names: list[str],
    distro: dict,
    distro_key: str | None,
    pkg_map: dict,
) -> list[dict]:
    floors = pkg_map.get("_floors", {})
    results = []

    for name in tool_names:
        found, path, version = _probe_tool(name)

        # Determine version floor
        floor_override = _get_floor_override(distro_key, name, pkg_map)
        min_version = floor_override or floors.get(name)

        # Determine ok + reason
        if not found:
            ok = False
            reason = "not_found"
        elif version is None and min_version is not None:
            # Found but can't verify version vs floor → fail-closed
            ok = False
            reason = "version_unknown"
        elif version is None:
            # Found, no floor — presence is enough
            ok = True
            reason = "ok"
        elif not _version_ok(version, min_version):
            ok = False
            reason = "version_too_old"
        else:
            ok = True
            reason = "ok"

        # Install command
        distro_install_cmd = _build_install_cmd(distro_key, name, pkg_map)

        # Source-build fallback
        fallback_slug = _get_source_build_fallback(distro_key, name, pkg_map)
        if fallback_slug:
            floor_str = min_version or "0"
            fb_label = _SOURCE_BUILD_LABELS.get(fallback_slug, fallback_slug).replace("{floor}", floor_str)
            fb_cmd = _SOURCE_BUILD_CMDS.get(fallback_slug, "").replace("{floor}", floor_str).replace("{fd}", "$WB_BUILD_PROGRESS_FD")
        else:
            fb_label = None
            fb_cmd = None

        notes = _get_tool_notes(distro_key, name, pkg_map)

        results.append({
            "name": name,
            "found": found,
            "path": path,
            "version": version,
            "min_version": min_version,
            "ok": ok,
            "reason": reason,
            "distro_install_cmd": distro_install_cmd,
            "source_build_fallback": fallback_slug,
            "source_build_fallback_label": fb_label,
            "source_build_fallback_cmd": fb_cmd,
            "notes": notes,
        })

    return results


# ---------------------------------------------------------------------------
# Pretty-print output
# ---------------------------------------------------------------------------

def _pretty_print(data: dict) -> None:
    distro = data["distro"]
    print(f"Distro: {distro['pretty_name']} (id={distro['id']}, recognized={distro['recognized']})")
    print(f"Build type: {data['build_type']}")
    print(f"Overall OK: {data['overall_ok']}")
    print()
    print(f"{'Tool':<20} {'Status':<16} {'Version':<12} {'Min':<12} Reason")
    print("-" * 80)
    for t in data["tools"]:
        status = "OK" if t["ok"] else "FAIL"
        ver = t["version"] or "?"
        min_ver = t["min_version"] or "-"
        print(f"{t['name']:<20} {status:<16} {ver:<12} {min_ver:<12} {t['reason']}")
        if not t["ok"] and t["distro_install_cmd"]:
            print(f"  Install: {t['distro_install_cmd']}")
        if t["source_build_fallback"]:
            print(f"  Source build: {t['source_build_fallback_label']}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wb-preflight.py",
        description="wine-bleeding build-environment preflight detector",
        add_help=True,
    )
    out_group = p.add_mutually_exclusive_group()
    out_group.add_argument(
        "--json", action="store_true", default=True,
        help="Emit JSON on stdout (default)",
    )
    out_group.add_argument(
        "--pretty", action="store_true", default=False,
        help="Emit a human-readable table on stdout",
    )
    p.add_argument(
        "--tool", metavar="NAME[,NAME...]",
        help="Comma-separated list of tool names to probe (overrides --build-type)",
    )
    p.add_argument(
        "--build-type", choices=["components", "dist"], default="components",
        help="Preset tool set: 'components' or 'dist' (default: components)",
    )
    p.add_argument(
        "--package-map", metavar="PATH",
        help="Explicit path to wb-preflight-packages.json (testing)",
    )
    p.add_argument(
        "--overlay-dir", metavar="PATH",
        help="Explicit path to overlay directory (testing)",
    )
    p.add_argument(
        "--os-release", metavar="PATH",
        help="Explicit path to os-release file (testing)",
    )
    p.add_argument(
        "--version", action="store_true",
        help="Print wb-preflight.py version and exit",
    )
    return p


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    if args.version:
        print(f"wb-preflight.py {__version__}")
        return 0

    use_pretty = args.pretty

    # Resolve tool list
    if args.tool:
        raw_names = [n.strip() for n in args.tool.split(",") if n.strip()]
        unknown = [n for n in raw_names if n not in _VALID_TOOLS]
        if unknown:
            print(
                f"wb-preflight: unknown tool name(s): {', '.join(unknown)}\n"
                f"Valid names: {', '.join(sorted(_VALID_TOOLS))}",
                file=sys.stderr,
            )
            return 2
        tool_names = raw_names
        build_type = "components"  # Doesn't matter semantically when --tool used
    elif args.build_type == "dist":
        tool_names = list(_TOOLS_DIST)
        build_type = "dist"
    else:
        tool_names = list(_TOOLS_COMPONENTS)
        build_type = "components"

    # Locate package map
    if args.package_map:
        map_path = pathlib.Path(args.package_map)
        if not map_path.is_file():
            print(f"wb-preflight: --package-map path not found: {map_path}", file=sys.stderr)
            return 2
    else:
        script_dir = pathlib.Path(__file__).resolve().parent
        map_path = _find_package_map(script_dir)
        if map_path is None:
            print("wb-preflight: wb-preflight-packages.json not found", file=sys.stderr)
            return 99

    # Load map + overlays
    try:
        pkg_map, overlays_loaded, overlay_errors = _load_map_with_overlays(
            map_path, args.overlay_dir
        )
    except Exception as exc:  # pylint: disable=broad-except
        print(f"wb-preflight: failed to load package map: {exc}", file=sys.stderr)
        return 99

    # Detect distro
    known_distros = set(pkg_map.get("distros", {}).keys())
    distro = _detect_distro(args.os_release, known_distros)
    distro_key = _resolve_distro_key(distro, pkg_map)

    # Populate refresh_cmd: per-distro value when recognized, fallback otherwise.
    if distro_key is not None:
        distro["refresh_cmd"] = pkg_map.get("distros", {}).get(distro_key, {}).get("refresh_cmd")
    else:
        distro["refresh_cmd"] = pkg_map.get("fallback", {}).get("refresh_cmd")

    # Probe tools
    tool_results = _probe_all_tools(tool_names, distro, distro_key, pkg_map)
    overall_ok = all(t["ok"] for t in tool_results)

    # Assemble output
    output = {
        "schema_version": 1,
        "preflight_version": __version__,
        "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "distro": distro,
        "build_type": build_type,
        "overall_ok": overall_ok,
        "overlays_loaded": overlays_loaded,
        "overlay_errors": overlay_errors,
        "tools": tool_results,
    }

    if use_pretty:
        _pretty_print(output)
    else:
        print(json.dumps(output))

    return 0 if overall_ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # pylint: disable=broad-except
        err_output = {
            "schema_version": 1,
            "preflight_version": __version__,
            "error": "internal",
            "exception": str(exc),
        }
        print(json.dumps(err_output))
        print(f"wb-preflight: internal error: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(99)

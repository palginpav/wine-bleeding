#!/usr/bin/env python3
"""
wb-tools-manager.py — Managed build-tools installer for wine-bleeding.

Downloads pre-built, glibc-flavored toolchain tarballs from the upstream manifest,
verifies SHA-256, atomically extracts into ~/.local/share/wine-bleeding/build-tools/,
and maintains local state in installed.json.

Security guarantees:
  - HTTPS-only, TLS cert verification enforced. WB_TOOLS_SKIP_TLS_VERIFY is NOT supported.
  - SHA-256 verified BEFORE extraction.
  - Tarball path-traversal defense (data_filter on Py 3.12+; manual entry check on 3.8-3.11).
  - Refuses to run as root (euid 0).
  - flock serialises all write operations.

Usage:
    wb-tools-manager.py [--manifest-url URL] [--tools-dir DIR]
                        [--progress-fd FD] [--json] COMMAND [args]

Commands:
    list                   Show locally installed tools (what, version, flavor).
    check                  Fetch manifest, compare with local state, print diff.
    install <tool>         Download + verify + atomically extract a tool.
    update <tool>          Same as install but requires prior version; keeps it as .previous.
    remove <tool>          Remove <tool>/current and all its versions.
    path                   Print the contents of the sourceable .path file.

Exit codes:
    0   — success / no updates available
    1   — argument error
    2   — runtime error (network, TLS, filesystem)
    3   — no compatible flavor for host glibc
    4   — insufficient disk space
    5   — SHA-256 mismatch or manifest parse error
    6   — tool not installed (required for 'update')
    7   — operation already in progress (flock held by another process)
    10  — updates available (advisory; returned by 'check' only)
    99  — internal / unexpected error

Environment:
    WB_TOOLS_MANIFEST_URL   Override default manifest URL.
    WB_TOOLS_DIR            Override default tools directory.
    WB_TOOLS_MANIFEST_TTL_SEC  Manifest cache TTL in seconds (default: 600).
    WB_TOOLS_DISK_BUDGET_BYTES Disk budget cap in bytes (default: 524288000 / 500 MB).
    WB_MANAGED_TOOLS_DIR    Alias for WB_TOOLS_DIR (for bats test compatibility).

    NOT SUPPORTED:
    WB_TOOLS_SKIP_TLS_VERIFY — intentionally absent. TLS verification is non-optional.

Dependencies: Python 3.8+ stdlib only.
"""

import argparse
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import signal
import ssl
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import urllib.error

__version__ = "1.0.0"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_MANIFEST_URL = (
    "https://github.com/palginpav/wine-bleeding/releases/latest/download/manifest.json"
)
DEFAULT_TOOLS_DIR = pathlib.Path.home() / ".local" / "share" / "wine-bleeding" / "build-tools"
DEFAULT_MANIFEST_TTL_SEC = 600
DEFAULT_DISK_BUDGET_BYTES = 500 * 1024 * 1024  # 500 MB

# Zip-bomb guard: extracted bytes must not exceed compressed_size * N.
# Real zstd-compressed toolchain tarballs routinely reach 6-12x (glslang ~6.7x,
# mingw-w64 higher). True zip bombs reach 1000x+, so 20 keeps meaningful
# protection while accommodating all known build-tool payloads.
_EXTRACT_RATIO_LIMIT = 20
# Zip-bomb guard: max number of entries
_EXTRACT_ENTRY_LIMIT = 50_000

# Known primary binaries per tool (for sanity checks after install)
_PRIMARY_BINARY: dict = {
    "mingw-w64-gcc": "x86_64-w64-mingw32-gcc",
    "glslang": "glslangValidator",
}

# HTTP chunk size for download (8 KiB)
_CHUNK_SIZE = 8192

# Download progress interval: emit PROGRESS every ~5%
_PROGRESS_STEP_PCT = 5


# ---------------------------------------------------------------------------
# Progress / logging helpers
# ---------------------------------------------------------------------------

class _Reporter:
    """Emit Phase-B events on a file descriptor or to stderr."""

    def __init__(self, fd: int | None, use_json_stdout: bool = False) -> None:
        self._fd = fd
        self._fp = None
        if fd is not None:
            try:
                self._fp = os.fdopen(fd, "w", buffering=1, closefd=False)
            except OSError:
                # If the fd is bad, fall back to stderr quietly
                self._fp = None
        self._json = use_json_stdout

    def _write(self, line: str) -> None:
        if self._fp is not None:
            self._fp.write(line + "\n")
            self._fp.flush()
        else:
            print(line, file=sys.stderr)

    def progress(self, pct: int, msg: str) -> None:
        self._write(f"PROGRESS: {pct}  {msg}")

    def log(self, msg: str) -> None:
        self._write(f"LOG: {msg}")

    def warn(self, msg: str) -> None:
        self._write(f"WARN: {msg}")

    def error(self, msg: str) -> None:
        self._write(f"ERROR: {msg}")


# ---------------------------------------------------------------------------
# glibc detection
# ---------------------------------------------------------------------------

_GLIBC_RE = re.compile(r"(\d+)\.(\d+)")


def parse_glibc(ver: str | None) -> tuple[int, int] | None:
    """Parse 'MAJOR.MINOR' into a tuple; return None on failure."""
    if not ver:
        return None
    m = _GLIBC_RE.search(ver)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)))


def detect_glibc(reporter: _Reporter) -> str | None:
    """
    Detect host glibc version string (e.g. '2.35').
    Returns None and emits a WARN if detection fails.

    Strategy:
      1. Check for musl (/lib/ld-musl-x86_64.so.1) — short-circuit to None.
      2. Run /usr/bin/ldd --version (or shutil.which('ldd')).
      3. Parse first MAJOR.MINOR in the first line.
      4. Fallback: read /lib64/libc.so.6 --version.
    """
    # Musl detection
    if os.path.exists("/lib/ld-musl-x86_64.so.1") and not os.path.exists("/lib64/ld-linux-x86-64.so.2"):
        reporter.warn(
            "Host appears to be musl-based (Alpine, Void-musl); "
            "no managed flavors will match. Use source-build fallback."
        )
        return None

    ldd_path = "/usr/bin/ldd" if os.path.exists("/usr/bin/ldd") else shutil.which("ldd")
    if ldd_path:
        try:
            result = subprocess.run(
                [ldd_path, "--version"],
                capture_output=True, text=True, timeout=10,
            )
            first_line = (result.stdout + result.stderr).splitlines()[0] if (result.stdout + result.stderr) else ""
            m = _GLIBC_RE.search(first_line)
            if m:
                return f"{m.group(1)}.{m.group(2)}"
        except (subprocess.TimeoutExpired, OSError, IndexError):
            pass

    # Fallback: try running libc.so directly
    for libc_path in ["/lib64/libc.so.6", "/lib/x86_64-linux-gnu/libc.so.6"]:
        if os.path.exists(libc_path):
            try:
                result = subprocess.run(
                    [libc_path], capture_output=True, text=True, timeout=10,
                )
                first_line = (result.stdout + result.stderr).splitlines()[0] if (result.stdout + result.stderr) else ""
                m = _GLIBC_RE.search(first_line)
                if m:
                    return f"{m.group(1)}.{m.group(2)}"
            except (subprocess.TimeoutExpired, OSError, IndexError):
                pass

    reporter.warn("Could not detect host glibc version; no managed flavors will match.")
    return None


def detect_host_info(reporter: _Reporter) -> dict:
    """Return a dict with glibc, arch, os_id, os_version_id."""
    glibc = detect_glibc(reporter)
    arch = platform.machine()

    os_id = "unknown"
    os_version_id = "unknown"
    for path in ["/etc/os-release", "/usr/lib/os-release"]:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("ID="):
                        os_id = line[3:].strip('"\'').lower()
                    elif line.startswith("VERSION_ID="):
                        os_version_id = line[11:].strip('"\'')
            break
        except OSError:
            continue

    return {"glibc": glibc, "arch": arch, "os_id": os_id, "os_version_id": os_version_id}


# ---------------------------------------------------------------------------
# Flavor picking
# ---------------------------------------------------------------------------

def pick_flavor(flavors: list, host_glibc: str | None, host_arch: str) -> tuple:
    """
    Return (flavor_dict, "ok") or (None, reason_string).
    Picks the flavor with the highest glibc_min that the host satisfies.
    """
    if host_glibc is None:
        return None, "host_glibc_unparseable"

    host_tuple = parse_glibc(host_glibc)
    if host_tuple is None:
        return None, "host_glibc_unparseable"

    candidates = []
    for f in flavors:
        if f.get("arch") != host_arch:
            continue
        gmin = parse_glibc(f.get("glibc_min"))
        if gmin is None:
            continue  # malformed — skip with WARN at call site
        gmax_raw = f.get("glibc_max")
        gmax = parse_glibc(gmax_raw) if gmax_raw else None
        if host_tuple < gmin:
            continue
        if gmax is not None and host_tuple > gmax:
            continue
        candidates.append((gmin, f))

    if not candidates:
        return None, "no_compatible_flavor"

    # Highest glibc_min wins — newer toolchain on capable host
    candidates.sort(key=lambda pair: pair[0], reverse=True)
    return candidates[0][1], "ok"


# ---------------------------------------------------------------------------
# Manifest fetch + cache
# ---------------------------------------------------------------------------

def _now_utc_str() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _read_file_str(path: pathlib.Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def _write_file_str(path: pathlib.Path, content: str) -> None:
    tmp = path.with_suffix(".new")
    tmp.write_text(content, encoding="utf-8")
    tmp.rename(path)


def fetch_manifest(
    manifest_url: str,
    tools_dir: pathlib.Path,
    reporter: _Reporter,
    force_refresh: bool = False,
    ttl_sec: int = DEFAULT_MANIFEST_TTL_SEC,
) -> dict:
    """
    Fetch the manifest JSON, using cache when fresh.
    Returns parsed dict. Raises RuntimeError on unrecoverable fetch failure.
    Uses the seed manifest as ultimate fallback.
    """
    cache_json = tools_dir / "manifest.cache.json"
    cache_etag = tools_dir / "manifest.cache.etag"
    cache_ts = tools_dir / "manifest.cache.fetched_utc"

    # Check if we can use cache
    cached_ts = _read_file_str(cache_ts)
    use_cache = False
    if not force_refresh and cached_ts and cache_json.is_file():
        try:
            ts = datetime.datetime.fromisoformat(cached_ts.replace("Z", "+00:00"))
            age = (datetime.datetime.now(datetime.timezone.utc) - ts).total_seconds()
            if age < ttl_sec:
                use_cache = True
        except ValueError:
            pass

    if use_cache:
        try:
            with open(cache_json, encoding="utf-8") as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError):
            pass  # Fall through to network fetch

    # Validate URL must be HTTPS
    if not manifest_url.startswith("https://"):
        raise RuntimeError(
            f"WB_TOOLS_MANIFEST_URL must use https:// — refusing plaintext transport. "
            f"Got: {manifest_url!r}"
        )

    reporter.log(f"Manifest URL: {manifest_url}")

    # Build request with optional ETag
    etag = _read_file_str(cache_etag)
    req = urllib.request.Request(manifest_url)
    if etag:
        req.add_header("If-None-Match", etag)
    req.add_header("User-Agent", f"wb-tools-manager/{__version__}")

    ssl_ctx = ssl.create_default_context()  # HTTPS enforced; no CERT_NONE escape

    try:
        with urllib.request.urlopen(req, context=ssl_ctx, timeout=30) as resp:
            if resp.status == 304:
                # Cache is still valid; refresh the timestamp
                _write_file_str(cache_ts, _now_utc_str())
                reporter.log("Manifest unchanged (ETag 304); using cache.")
                with open(cache_json, encoding="utf-8") as f:
                    return json.load(f)
            raw = resp.read()
            new_etag = resp.headers.get("ETag")
    except urllib.error.HTTPError as exc:
        if exc.code == 304:
            _write_file_str(cache_ts, _now_utc_str())
            reporter.log("Manifest unchanged (ETag 304); using cache.")
            with open(cache_json, encoding="utf-8") as f:
                return json.load(f)
        raise RuntimeError(
            f"Could not fetch the build-tools manifest.\n"
            f"What happened: HTTP {exc.code} from {manifest_url}.\n"
            f"Why: the server returned an error or the URL has moved.\n"
            f"Next action: check your network, then click 'Check for updates' again."
        ) from exc
    except ssl.SSLError as exc:
        raise RuntimeError(
            f"TLS verification failed.\n"
            f"What happened: The connection to the manifest server could not be verified.\n"
            f"Why: certificate expired, self-signed, or hostname mismatch. "
            f"May indicate a corporate proxy or MITM.\n"
            f"Next action: check system date/time, network configuration, then retry."
        ) from exc
    except OSError as exc:
        # Network unreachable — try stale cache, then seed manifest
        reporter.warn(
            f"Network error fetching manifest: {exc}. "
            f"Trying stale cache or seed manifest."
        )
        if cache_json.is_file():
            try:
                with open(cache_json, encoding="utf-8") as f:
                    data = json.load(f)
                reporter.warn("Using stale cached manifest (network unreachable).")
                return data
            except (OSError, json.JSONDecodeError):
                pass
        return _load_seed_manifest(reporter)

    # Parse + validate the freshly-fetched manifest
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"Manifest is malformed (JSON parse failed): {exc}"
        ) from exc

    _validate_manifest(data)

    # Write to cache
    tools_dir.mkdir(parents=True, exist_ok=True)
    _write_file_str(cache_json, raw.decode("utf-8"))
    if new_etag:
        _write_file_str(cache_etag, new_etag)
        reporter.log(f"ETag: {new_etag}")
    _write_file_str(cache_ts, _now_utc_str())

    return data


def _validate_manifest(data: dict) -> None:
    """Raise RuntimeError if manifest is fatally malformed."""
    if not isinstance(data, dict):
        raise RuntimeError("Manifest is malformed: top-level must be a JSON object.")
    schema_ver = data.get("schema_version")
    if not isinstance(schema_ver, int) or schema_ver < 1:
        raise RuntimeError("Manifest is malformed (schema_version missing or non-integer).")
    if schema_ver > 1:
        # Forward-compat: warn but proceed
        import warnings as _w
        _w.warn(
            f"manifest uses schema {schema_ver}, manager supports up to 1. "
            f"Best-effort parse; upgrade wine-bleeding for full support.",
            stacklevel=3,
        )
    manifest_url = data.get("manifest_url", "")
    if not isinstance(manifest_url, str) or not manifest_url.startswith("https://"):
        raise RuntimeError(
            "Manifest is malformed: manifest_url is missing or not https://."
        )
    if not isinstance(data.get("tools"), dict):
        raise RuntimeError("Manifest is malformed: 'tools' must be a JSON object.")


def _load_seed_manifest(reporter: _Reporter) -> dict:
    """Load the seed manifest shipped in the RPM as an offline fallback."""
    script_dir = pathlib.Path(__file__).resolve().parent
    candidates = [
        script_dir.parent / "share" / "wb-tools-manager-manifest.json",
        pathlib.Path("/usr/share/wine-bleeding/wb-tools-manager-manifest.json"),
    ]
    xdg_data = os.environ.get("XDG_DATA_DIRS", "")
    for base in xdg_data.split(":"):
        if base:
            candidates.append(
                pathlib.Path(base) / "wine-bleeding" / "wb-tools-manager-manifest.json"
            )
    for c in candidates:
        if c.is_file():
            try:
                with open(c, encoding="utf-8") as f:
                    data = json.load(f)
                reporter.warn(
                    f"Using seed manifest from {c}. "
                    f"No managed flavors known locally; click 'Check for updates' to refresh."
                )
                return data
            except (OSError, json.JSONDecodeError):
                continue
    reporter.warn("No manifest available (network down, no cache, no seed). Treating tools as empty.")
    return {
        "schema_version": 1,
        "manifest_url": DEFAULT_MANIFEST_URL,
        "generated_utc": "1970-01-01T00:00:00Z",
        "tools": {},
    }


# ---------------------------------------------------------------------------
# installed.json read/write
# ---------------------------------------------------------------------------

def load_installed(tools_dir: pathlib.Path, reporter: _Reporter) -> dict:
    """Load installed.json; fall back to .backup; return empty state on failure."""
    installed_path = tools_dir / "installed.json"
    backup_path = tools_dir / "installed.json.backup"

    for path, is_backup in [(installed_path, False), (backup_path, True)]:
        if not path.is_file():
            continue
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            if is_backup:
                reporter.warn("Loaded installed.json.backup (primary was unreadable).")
            return data
        except (OSError, json.JSONDecodeError) as exc:
            reporter.warn(f"Could not read {path}: {exc}")

    return {"schema_version": 1, "tools": {}}


def save_installed(tools_dir: pathlib.Path, data: dict) -> None:
    """Atomically write installed.json; copy prior version to .backup first."""
    installed_path = tools_dir / "installed.json"
    backup_path = tools_dir / "installed.json.backup"
    tmp_path = tools_dir / "installed.json.new"

    # Backup current
    if installed_path.is_file():
        try:
            shutil.copy2(installed_path, backup_path)
        except OSError:
            pass  # Best-effort

    # Write new
    content = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    tmp_path.write_text(content, encoding="utf-8")
    try:
        fd = os.open(str(tmp_path), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        pass
    tmp_path.rename(installed_path)


# ---------------------------------------------------------------------------
# flock helper
# ---------------------------------------------------------------------------

class _FileLock:
    """Context manager: exclusive flock on tools_dir/.lock; non-blocking."""

    def __init__(self, tools_dir: pathlib.Path) -> None:
        self._path = tools_dir / ".lock"
        self._fd: int | None = None

    def __enter__(self) -> "_FileLock":
        tools_dir = self._path.parent
        tools_dir.mkdir(parents=True, exist_ok=True)
        # Ensure lock file exists
        self._path.touch(mode=0o600, exist_ok=True)
        self._fd = os.open(str(self._path), os.O_RDWR)
        try:
            fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            os.close(self._fd)
            self._fd = None
            raise RuntimeError(
                "Another managed-tools operation is in progress — "
                "wait for it to finish, then retry."
            ) from exc
        return self

    def __exit__(self, *args) -> None:
        if self._fd is not None:
            fcntl.flock(self._fd, fcntl.LOCK_UN)
            os.close(self._fd)
            self._fd = None


# ---------------------------------------------------------------------------
# Download tarball
# ---------------------------------------------------------------------------

def download_tarball(
    url: str,
    dest: pathlib.Path,
    size_bytes: int,
    reporter: _Reporter,
) -> None:
    """
    Stream-download url into dest. Emits PROGRESS every ~5%.
    Raises RuntimeError on failure. Verifies Content-Length within 5%.
    """
    if not url.startswith("https://"):
        raise RuntimeError(
            f"Tarball URL must use https:// — refusing plaintext transport. Got: {url!r}"
        )

    ssl_ctx = ssl.create_default_context()
    req = urllib.request.Request(url)
    req.add_header("User-Agent", f"wb-tools-manager/{__version__}")

    reporter.log(f"Downloading from {url}")

    try:
        with urllib.request.urlopen(req, context=ssl_ctx, timeout=120) as resp:
            # Content-Length sanity check
            cl_header = resp.headers.get("Content-Length")
            if cl_header:
                try:
                    cl = int(cl_header)
                    if size_bytes > 0 and abs(cl - size_bytes) / size_bytes > 0.05:
                        reporter.warn(
                            f"Content-Length {cl} differs from manifest size_bytes "
                            f"{size_bytes} by >5%; aborting download."
                        )
                        raise RuntimeError(
                            f"Content-Length mismatch: server says {cl}, manifest says {size_bytes}."
                        )
                except (ValueError, ZeroDivisionError):
                    pass

            dest.parent.mkdir(parents=True, exist_ok=True)
            bytes_written = 0
            last_pct = -_PROGRESS_STEP_PCT

            with open(dest, "wb") as out:
                while True:
                    chunk = resp.read(_CHUNK_SIZE)
                    if not chunk:
                        break
                    out.write(chunk)
                    bytes_written += len(chunk)
                    if size_bytes > 0:
                        pct = int(bytes_written * 100 / size_bytes)
                        if pct >= last_pct + _PROGRESS_STEP_PCT:
                            reporter.progress(20 + int(pct * 0.4), f"Downloading... {pct}%")
                            last_pct = pct

    except ssl.SSLError as exc:
        raise RuntimeError(
            f"TLS verification failed downloading tarball.\n"
            f"What happened: {exc}\n"
            f"Next action: check system date/time, network configuration, then retry."
        ) from exc
    except OSError as exc:
        raise RuntimeError(
            f"Could not fetch the build-tools tarball.\n"
            f"What happened: network error downloading {url}.\n"
            f"Why: {exc}\n"
            f"Next action: check your network, then retry."
        ) from exc


# ---------------------------------------------------------------------------
# SHA-256 verification
# ---------------------------------------------------------------------------

def verify_sha256(path: pathlib.Path, expected: str, reporter: _Reporter) -> None:
    """
    Compute SHA-256 of path and compare against expected (lowercase hex).
    Raises RuntimeError on mismatch.
    """
    reporter.log(f"SHA-256 expected: {expected}")
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    actual = h.hexdigest()
    reporter.log(f"SHA-256 actual:   {actual}")
    if actual != expected.lower():
        path.unlink(missing_ok=True)
        raise RuntimeError(
            f"Download verification failed.\n"
            f"What happened: The downloaded tarball for did not match the SHA-256 in the manifest.\n"
            f"Why: the download may have been corrupted in transit, or the manifest and "
            f"tarball drifted on the server (rare).\n"
            f"Next action: retry. If this persists, file an issue at "
            f"github.com/palginpav/wine-bleeding/issues.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )


# ---------------------------------------------------------------------------
# Tarball safe extraction
# ---------------------------------------------------------------------------

def safe_extract(
    download_path: pathlib.Path,
    stage_dir: pathlib.Path,
    size_bytes: int,
    reporter: _Reporter,
) -> None:
    """
    Decompress (via external zstd) and extract tarball into stage_dir.
    Implements path-traversal defense for Python 3.8-3.11 and uses
    tarfile.data_filter for Python 3.12+.
    Raises RuntimeError on any security violation or zip-bomb detection.
    """
    reporter.log("Decompressing with zstd...")

    # Verify zstd binary is available
    zstd_bin = shutil.which("zstd")
    if not zstd_bin:
        raise RuntimeError(
            "Tarball extraction requires the 'zstd' command.\n"
            "What happened: The managed build-tool archives are compressed with zstd, "
            "but the zstd decoder is not installed.\n"
            "Why: zstd is a small dependency (~500 KB) usually pre-installed but absent here.\n"
            "Next action: install zstd using your distro's package manager, then retry.\n"
            "Examples: sudo dnf install zstd  |  sudo apt install zstd  |  sudo pacman -S zstd"
        )

    stage_dir.mkdir(parents=True, exist_ok=True)

    # Open zstd -d subprocess and pipe into tarfile
    # Keep the download file open to prevent TOCTOU replacement
    with open(download_path, "rb") as raw_fd:
        proc = subprocess.Popen(
            [zstd_bin, "-d", "--stdout", "-q"],
            stdin=raw_fd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            _extract_from_pipe(proc.stdout, stage_dir, size_bytes, reporter)
        finally:
            # Close stdout first so zstd gets SIGPIPE and exits; tarfile r|*
            # streaming mode stops at the tar EOF markers and does NOT close
            # the external fileobj, so zstd would otherwise block forever
            # writing trailing padding into a full pipe buffer.
            proc.stdout.close()
            try:
                proc.wait(timeout=600)
            except subprocess.TimeoutExpired:
                proc.kill()
                reporter.warn("zstd process timed out and was killed.")
            # -SIGPIPE is expected: after tarfile r|* hits the logical tar
            # end-of-archive markers, we close proc.stdout above, and zstd
            # exits with SIGPIPE on its next write of trailing padding.
            ok_rc = (0, None, -signal.SIGPIPE)
            if proc.returncode not in ok_rc:
                stderr_msg = proc.stderr.read(4096).decode("utf-8", errors="replace").strip()
                proc.stderr.close()
                raise RuntimeError(
                    f"zstd decompression failed (exit code {proc.returncode}): {stderr_msg}"
                )
            proc.stderr.close()


def _safe_entry(tarinfo: "tarfile.TarInfo", base: pathlib.Path) -> "tarfile.TarInfo":
    """
    Validate a single tar entry for path-traversal and security issues.
    Returns the (possibly sanitized) tarinfo, or raises ValueError.
    Used for Python 3.8-3.11.
    """
    # Block absolute paths
    if tarinfo.name.startswith("/"):
        raise ValueError(f"Absolute path in tarball: {tarinfo.name!r}")

    # Normalize and block path escape
    real_base = str(base.resolve())
    resolved = os.path.normpath(os.path.join(real_base, tarinfo.name))
    if not resolved.startswith(real_base + os.sep) and resolved != real_base:
        raise ValueError(f"Path escape in tarball: {tarinfo.name!r}")

    # Block symlinks/hardlinks escaping base
    if tarinfo.issym() or tarinfo.islnk():
        link_target = tarinfo.linkname
        if os.path.isabs(link_target):
            raise ValueError(f"Symlink to absolute path in tarball: {tarinfo.name!r} -> {link_target!r}")
        link_resolved = os.path.normpath(
            os.path.join(os.path.dirname(resolved), link_target)
        )
        if not link_resolved.startswith(real_base + os.sep) and link_resolved != real_base:
            raise ValueError(
                f"Symlink escape in tarball: {tarinfo.name!r} -> {tarinfo.linkname!r}"
            )

    # Block device files and FIFOs
    if tarinfo.isdev() or (not tarinfo.isreg() and not tarinfo.isdir()
                            and not tarinfo.issym() and not tarinfo.islnk()):
        raise ValueError(f"Non-regular entry in tarball: {tarinfo.name!r} (type={tarinfo.type!r})")

    # Drop setuid/setgid/sticky and force ownership to current user
    tarinfo.mode = tarinfo.mode & 0o755
    tarinfo.uid = os.getuid()
    tarinfo.gid = os.getgid()
    tarinfo.uname = ""
    tarinfo.gname = ""

    return tarinfo


def _extract_from_pipe(
    pipe: "IO[bytes]",
    stage_dir: pathlib.Path,
    size_bytes: int,
    reporter: _Reporter,
) -> None:
    """Extract tar stream from pipe into stage_dir with security validation."""
    py_ver = sys.version_info

    max_extracted = size_bytes * _EXTRACT_RATIO_LIMIT if size_bytes > 0 else None
    extracted_bytes = 0
    entry_count = 0
    top_level_dir: str | None = None

    with tarfile.open(fileobj=pipe, mode="r|*") as tf:
        for member in tf:
            # Zip-bomb: entry count
            entry_count += 1
            if entry_count > _EXTRACT_ENTRY_LIMIT:
                raise RuntimeError(
                    f"Extraction aborted: tarball has more than {_EXTRACT_ENTRY_LIMIT} entries "
                    f"(possible zip bomb or corrupt archive)."
                )

            # Zip-bomb: expanded size
            if member.isreg():
                extracted_bytes += member.size
            if max_extracted and extracted_bytes > max_extracted:
                raise RuntimeError(
                    f"Tarball expanded beyond expected size (possible zip bomb or manifest "
                    f"misrepresentation). Limit: {max_extracted // (1024*1024)} MB."
                )

            # Detect top-level directory to strip
            parts = member.name.lstrip("./").split("/")
            if parts:
                if top_level_dir is None and len(parts) >= 1:
                    top_level_dir = parts[0]
                # Strip the leading top-level dir
                if top_level_dir and member.name.startswith(top_level_dir + "/"):
                    member.name = member.name[len(top_level_dir) + 1:]
                elif member.name == top_level_dir:
                    continue  # skip the wrapper dir entry itself
                if not member.name:
                    continue  # becomes the stage_dir itself after strip

            if py_ver >= (3, 12):
                # Use data_filter (Python 3.12+)
                try:
                    tf.extract(member, path=stage_dir, filter="data")
                except (tarfile.FilterError, tarfile.AbsolutePathError,
                        tarfile.OutsideDestinationError) as exc:
                    raise RuntimeError(
                        f"Path-traversal attack blocked in tarball entry {member.name!r}: {exc}"
                    ) from exc
            else:
                # Manual entry validation (Python 3.8-3.11)
                try:
                    safe_member = _safe_entry(member, stage_dir)
                except ValueError as exc:
                    raise RuntimeError(
                        f"PATH-TRAVERSAL BLOCKED: {exc}"
                    ) from exc
                tf.extract(safe_member, path=stage_dir, set_attrs=True)

    reporter.log(
        f"Extracted {entry_count} entries, {extracted_bytes // (1024*1024)} MB into staging."
    )


# ---------------------------------------------------------------------------
# Atomic promote
# ---------------------------------------------------------------------------

def atomic_promote(
    stage_dir: pathlib.Path,
    tool_dir: pathlib.Path,
    version: str,
    is_update: bool,
    reporter: _Reporter,
) -> str | None:
    """
    Rename stage_dir → tool_dir/<version>/.
    Swing tool_dir/current symlink atomically.
    If is_update, write tool_dir/.previous → old version.
    Returns the previous version string (or None on first install).
    """
    version_dir = tool_dir / version
    current_link = tool_dir / "current"
    current_new_link = tool_dir / "current.new"

    reporter.progress(90, f"Promoting staging → {tool_dir.name}/{version}")

    # Rename stage → version dir (atomic on same FS)
    if version_dir.exists():
        shutil.rmtree(version_dir)
    stage_dir.rename(version_dir)

    # Determine previous version for .previous symlink
    prev_version: str | None = None
    if current_link.is_symlink():
        prev_target = os.readlink(current_link)
        # Normalize to just the dir name
        prev_version = pathlib.Path(prev_target).name

    reporter.progress(95, f"Swinging {tool_dir.name}/current → {version}")

    # Create current.new → version, then atomically replace current
    if current_new_link.is_symlink() or current_new_link.exists():
        current_new_link.unlink(missing_ok=True)
    os.symlink(version, current_new_link)
    os.rename(current_new_link, current_link)

    # Write .previous symlink on update
    if is_update and prev_version and prev_version != version:
        prev_link = tool_dir / ".previous"
        prev_link_new = tool_dir / ".previous.new"
        if prev_link_new.is_symlink() or prev_link_new.exists():
            prev_link_new.unlink(missing_ok=True)
        os.symlink(prev_version, prev_link_new)
        os.rename(prev_link_new, prev_link)

    return prev_version


# ---------------------------------------------------------------------------
# installed.json update
# ---------------------------------------------------------------------------

def update_installed_json(
    tools_dir: pathlib.Path,
    tool_name: str,
    version: str,
    flavor: dict,
    prev_version: str | None,
    manifest_url: str,
    host_info: dict,
    reporter: _Reporter,
) -> None:
    """Update installed.json with the newly-installed tool record."""
    data = load_installed(tools_dir, reporter)
    data["schema_version"] = 1
    data["last_check_utc"] = _now_utc_str()
    data["manifest_url_used"] = manifest_url
    data["host"] = host_info

    data.setdefault("tools", {})[tool_name] = {
        "version": version,
        "flavor": {
            "glibc_min": flavor.get("glibc_min"),
            "arch": flavor.get("arch"),
            "sha256": flavor.get("sha256"),
            "size_bytes": flavor.get("size_bytes"),
        },
        "installed_utc": _now_utc_str(),
        "previous_version": prev_version,
        "install_source_url": flavor.get("url"),
    }

    save_installed(tools_dir, data)
    reporter.log(f"installed.json updated for {tool_name} {version}.")


# ---------------------------------------------------------------------------
# .path file rewrite
# ---------------------------------------------------------------------------

def rewrite_path_file(tools_dir: pathlib.Path, reporter: _Reporter) -> None:
    """
    Regenerate tools_dir/.path with a sourceable PATH snippet for all installed tools.
    """
    tools_dir.mkdir(parents=True, exist_ok=True)
    timestamp = _now_utc_str()
    content = f"""\
# Auto-generated by wb-tools-manager.py at {timestamp} — do not edit.
# To use, add this to your ~/.bashrc or ~/.zshrc:
#   source {tools_dir}/.path
# wb-gui sources it automatically when invoking builds.

_wb_mt_root="${{XDG_DATA_HOME:-$HOME/.local/share}}/wine-bleeding/build-tools"
for _d in "${{_wb_mt_root}}"/*/current/bin; do
  [ -d "${{_d}}" ] || continue
  case ":${{PATH}}:" in
    *":${{_d}}:"*) ;;
    *) PATH="${{_d}}:${{PATH}}" ;;
  esac
done
export PATH
unset _d _wb_mt_root
"""
    path_file = tools_dir / ".path"
    tmp = tools_dir / ".path.new"
    tmp.write_text(content, encoding="utf-8")
    tmp.rename(path_file)
    reporter.log(f"Rewrote {path_file}")


# ---------------------------------------------------------------------------
# Cleanup: prune old versions (latest-2 retention)
# ---------------------------------------------------------------------------

def prune_old_versions(
    tool_dir: pathlib.Path,
    installed_data: dict,
    tool_name: str,
    reporter: _Reporter,
) -> None:
    """
    Keep current + .previous versions; delete everything older.
    Updates installed.json's previous_version chain when a version is pruned.
    """
    current_link = tool_dir / "current"
    prev_link = tool_dir / ".previous"

    current_ver: str | None = None
    if current_link.is_symlink():
        current_ver = pathlib.Path(os.readlink(current_link)).name

    prev_ver: str | None = None
    if prev_link.is_symlink():
        prev_ver = pathlib.Path(os.readlink(prev_link)).name

    retained = {v for v in [current_ver, prev_ver] if v}

    # Find all version directories. Exclude symlinks — `current` is a symlink
    # pointing at a version dir, and shutil.rmtree refuses to remove symlinks.
    version_dirs = [
        d for d in tool_dir.iterdir()
        if d.is_dir() and not d.is_symlink() and not d.name.startswith(".")
    ]

    for vd in version_dirs:
        if vd.name not in retained:
            reporter.log(f"Pruning old version {tool_name}/{vd.name}")
            try:
                shutil.rmtree(vd)
            except OSError as exc:
                reporter.warn(f"Could not prune {vd}: {exc}")

    # If .previous points at a pruned version, remove the dangling symlink
    if prev_link.is_symlink() and not (tool_dir / prev_ver).is_dir():
        prev_link.unlink(missing_ok=True)


def cleanup_staging(tools_dir: pathlib.Path, reporter: _Reporter) -> None:
    """Remove staging dirs older than 1 hour on startup."""
    tmp_dir = tools_dir / ".tmp"
    if not tmp_dir.is_dir():
        return
    now = time.time()
    for entry in tmp_dir.iterdir():
        if now - entry.stat().st_mtime > 3600:
            reporter.log(f"Removing stale staging dir: {entry}")
            try:
                shutil.rmtree(entry)
            except OSError as exc:
                reporter.warn(f"Could not remove {entry}: {exc}")


def cleanup_orphans(tools_dir: pathlib.Path, installed_data: dict, reporter: _Reporter) -> None:
    """Remove orphan version dirs older than 7 days (not referenced by any symlink or installed.json)."""
    now = time.time()
    installed_tools = installed_data.get("tools", {})

    for tool_dir in tools_dir.iterdir():
        if not tool_dir.is_dir() or tool_dir.name.startswith("."):
            continue
        current_link = tool_dir / "current"
        prev_link = tool_dir / ".previous"
        referenced = set()
        for lnk in [current_link, prev_link]:
            if lnk.is_symlink():
                referenced.add(pathlib.Path(os.readlink(lnk)).name)
        if tool_dir.name in installed_tools:
            t = installed_tools[tool_dir.name]
            if t.get("version"):
                referenced.add(t["version"])
            if t.get("previous_version"):
                referenced.add(t["previous_version"])

        for vd in tool_dir.iterdir():
            if not vd.is_dir() or vd.name.startswith("."):
                continue
            if vd.name not in referenced:
                age = now - vd.stat().st_mtime
                if age > 7 * 86400:
                    reporter.log(f"Removing orphan {tool_dir.name}/{vd.name} (age {age/86400:.1f} days)")
                    try:
                        shutil.rmtree(vd)
                    except OSError as exc:
                        reporter.warn(f"Could not remove orphan {vd}: {exc}")


# ---------------------------------------------------------------------------
# Version comparison helper
# ---------------------------------------------------------------------------

def version_tuple(ver: str) -> tuple:
    """Convert 'X.Y.Z[+wbN]' into a sortable tuple."""
    # Strip wb post-release suffix
    ver_clean = re.sub(r"\+.*$", "", ver)
    parts = re.findall(r"\d+", ver_clean)
    return tuple(int(p) for p in parts)


# ---------------------------------------------------------------------------
# Disk space check
# ---------------------------------------------------------------------------

def check_disk_space(
    tools_dir: pathlib.Path,
    size_bytes: int,
    budget_bytes: int,
    reporter: _Reporter,
) -> None:
    """
    Verify sufficient disk space before download.
    required = size_bytes * 2 (download + extract headroom).
    Raises RuntimeError if insufficient.
    """
    required = size_bytes * 2
    usage = shutil.disk_usage(tools_dir if tools_dir.exists() else tools_dir.parent)
    free = usage.free
    size_mb = size_bytes / (1024 * 1024)
    free_mb = free / (1024 * 1024)
    required_mb = required / (1024 * 1024)

    reporter.progress(15, f"Checking disk space (required: {required_mb:.0f} MB, free: {free_mb:.0f} MB)")

    if free < required:
        raise RuntimeError(
            f"Not enough disk space for the build-tools install.\n"
            f"What happened: Installing the tool needs {required_mb:.0f} MB free in "
            f"{tools_dir}; you have {free_mb:.0f} MB.\n"
            f"Why: the partition hosting your home directory is nearly full.\n"
            f"Next action: free up space, then retry. You can also use 'Build from source' "
            f"to install into a different location with WB_HOME set."
        )


# ---------------------------------------------------------------------------
# Validate manifest tool entry (per-tool warnings)
# ---------------------------------------------------------------------------

def _get_tool_version_entry(
    manifest: dict,
    tool_name: str,
    reporter: _Reporter,
) -> tuple[str, dict] | tuple[None, None]:
    """
    Return (latest_version, version_entry_dict) or (None, None) with WARNs.
    """
    tools = manifest.get("tools", {})
    if tool_name not in tools:
        return None, None

    tool_meta = tools[tool_name]
    versions = tool_meta.get("versions", {})
    if not versions:
        reporter.warn(f"Tool {tool_name!r} has empty versions list in manifest.")
        return None, None

    latest = tool_meta.get("latest_version", "")
    if latest not in versions:
        # Fallback to highest semver key
        try:
            latest = max(versions.keys(), key=version_tuple)
            reporter.warn(
                f"latest_version={tool_meta.get('latest_version')!r} points at a missing key; "
                f"using {latest!r} instead."
            )
        except (ValueError, TypeError):
            reporter.warn(f"Could not determine latest version for {tool_name!r}.")
            return None, None

    ver_entry = versions[latest]
    flavors = ver_entry.get("flavors", [])
    if not flavors:
        reporter.warn(f"Tool {tool_name!r} version {latest!r} has empty flavors list.")
        return None, None

    return latest, ver_entry


# ---------------------------------------------------------------------------
# Subcommand implementations
# ---------------------------------------------------------------------------

def cmd_list(args: argparse.Namespace, tools_dir: pathlib.Path, reporter: _Reporter) -> int:
    """List locally installed tools."""
    installed = load_installed(tools_dir, reporter)
    tools = installed.get("tools", {})

    if args.json:
        print(json.dumps({
            "schema_version": 1,
            "tools_dir": str(tools_dir),
            "tools": tools,
            "last_check_utc": installed.get("last_check_utc"),
        }, indent=2))
        return 0

    if not tools:
        print("No managed build tools are installed.")
        print(f"Tools dir: {tools_dir}")
        print("Click 'Check for updates' to see what is available.")
        return 0

    print(f"Managed build tools ({tools_dir}):")
    print(f"  {'Tool':<24} {'Version':<14} {'glibc_min':<12} Installed")
    print("  " + "-" * 70)
    for name, rec in tools.items():
        flavor = rec.get("flavor", {})
        installed_utc = rec.get("installed_utc", "?")
        print(
            f"  {name:<24} {rec.get('version', '?'):<14} "
            f"{flavor.get('glibc_min', '?'):<12} {installed_utc}"
        )
    return 0


def cmd_check(args: argparse.Namespace, tools_dir: pathlib.Path, reporter: _Reporter,
              manifest_url: str, ttl_sec: int, force_refresh: bool = False) -> int:
    """
    Fetch manifest, compare with local state, print diff.
    Exit 0: no updates. Exit 10: updates available. Exit 5: manifest error.
    """
    try:
        manifest = fetch_manifest(manifest_url, tools_dir, reporter,
                                  force_refresh=True, ttl_sec=ttl_sec)
    except RuntimeError as exc:
        reporter.error(str(exc))
        return 5

    installed = load_installed(tools_dir, reporter)
    installed_tools = installed.get("tools", {})
    host_info = detect_host_info(reporter)
    host_glibc = host_info["glibc"]
    host_arch = host_info["arch"]

    results = {}
    has_updates = False

    for tool_name, tool_meta in manifest.get("tools", {}).items():
        latest_ver, ver_entry = _get_tool_version_entry(manifest, tool_name, reporter)
        if latest_ver is None:
            continue

        flavors = ver_entry.get("flavors", [])
        flavor, flavor_reason = pick_flavor(flavors, host_glibc, host_arch)
        compatible = flavor is not None

        installed_rec = installed_tools.get(tool_name)
        if installed_rec:
            current_ver = installed_rec.get("version", "")
            is_outdated = version_tuple(current_ver) < version_tuple(latest_ver)
            state = "installed-outdated" if is_outdated else "installed-up-to-date"
            if is_outdated:
                has_updates = True
        else:
            state = "not-installed"
            if compatible:
                has_updates = True  # available but not installed

        results[tool_name] = {
            "installed": installed_rec is not None,
            "version": installed_rec.get("version") if installed_rec else None,
            "latest_version": latest_ver,
            "state": state,
            "update_available": state == "installed-outdated",
            "compatible_flavor_available": compatible,
            "display_name": tool_meta.get("display_name", tool_name),
        }

    if args.json:
        print(json.dumps({"schema_version": 1, "tools": results}, indent=2))
    else:
        if not results:
            print("No managed tools in manifest yet. Click 'Check for updates' once a release is published.")
        else:
            for name, rec in results.items():
                state_label = {
                    "installed-up-to-date": "up to date",
                    "installed-outdated": f"outdated ({rec['version']} -> {rec['latest_version']})",
                    "not-installed": "not installed",
                }.get(rec["state"], rec["state"])
                compat = "" if rec["compatible_flavor_available"] else " [no compatible flavor for your glibc]"
                print(f"  {name}: {state_label}{compat}")

    return 10 if has_updates else 0


def cmd_install_or_update(
    args: argparse.Namespace,
    tool_name: str,
    tools_dir: pathlib.Path,
    reporter: _Reporter,
    manifest_url: str,
    ttl_sec: int,
    budget_bytes: int,
    is_update: bool,
) -> int:
    """Shared implementation for install and update subcommands."""

    reporter.progress(0, f"Starting managed {'update' if is_update else 'install'} of {tool_name}")

    with _FileLock(tools_dir):
        # Startup cleanup
        cleanup_staging(tools_dir, reporter)
        installed = load_installed(tools_dir, reporter)
        host_info = detect_host_info(reporter)

        # For update: require existing install
        if is_update and tool_name not in installed.get("tools", {}):
            reporter.error(
                f"Tool {tool_name!r} is not installed. "
                f"Use 'install {tool_name}' to install it first."
            )
            return 6

        # Fetch manifest
        reporter.progress(5, f"Fetching manifest from {manifest_url}")
        try:
            manifest = fetch_manifest(
                manifest_url, tools_dir, reporter,
                force_refresh=is_update,  # update always re-fetches
                ttl_sec=ttl_sec,
            )
        except RuntimeError as exc:
            reporter.error(str(exc))
            return 2

        reporter.progress(8, "Parsing manifest...")
        latest_ver, ver_entry = _get_tool_version_entry(manifest, tool_name, reporter)
        if latest_ver is None:
            reporter.error(
                f"Tool {tool_name!r} is not listed in the manifest.\n"
                f"What happened: The manifest has no entry for {tool_name!r}.\n"
                f"Why: the tool may not be available as a managed binary yet.\n"
                f"Next action: use 'Build from source' or check for updates later."
            )
            return 3

        # Pick flavor
        flavors = ver_entry.get("flavors", [])
        host_glibc = host_info["glibc"]
        host_arch = host_info["arch"]
        flavor, reason = pick_flavor(flavors, host_glibc, host_arch)
        if flavor is None:
            glibc_str = host_glibc or "unknown"
            available_mins = [f.get("glibc_min", "?") for f in flavors if f.get("arch") == host_arch]
            reporter.error(
                f"No managed build of {tool_name!r} is available for your system.\n"
                f"What happened: Your system's glibc ({glibc_str}) is incompatible with "
                f"every pre-built flavor we ship (minimum versions: {', '.join(available_mins) or 'none'}).\n"
                f"Why: {reason}.\n"
                f"Next action: click 'Build from source' to build locally (~30-60 min for MinGW)."
            )
            return 3

        reporter.progress(10, f"Picked flavor {tool_name} {latest_ver} {host_arch}-glibc{flavor['glibc_min']}")

        # Check if already at latest (skip re-install unless forced)
        installed_tools = installed.get("tools", {})
        if not is_update and tool_name in installed_tools:
            current_ver = installed_tools[tool_name].get("version", "")
            if version_tuple(current_ver) >= version_tuple(latest_ver):
                reporter.log(
                    f"{tool_name} {current_ver} is already the latest version. Nothing to do."
                )
                return 0

        # Disk space check
        size_bytes = flavor.get("size_bytes", 0)
        try:
            check_disk_space(tools_dir, size_bytes, budget_bytes, reporter)
        except RuntimeError as exc:
            reporter.error(str(exc))
            return 4

        # Set up staging paths
        tmp_dir = tools_dir / ".tmp"
        tmp_dir.mkdir(parents=True, exist_ok=True)
        download_path = tmp_dir / f"{tool_name}-{latest_ver}.download"
        stage_path = tmp_dir / f"{tool_name}-{latest_ver}.stage"

        try:
            # Download
            reporter.progress(20, f"Downloading {tool_name}-{latest_ver}-{host_arch}-glibc{flavor['glibc_min']}.tar.zst")
            try:
                download_tarball(flavor["url"], download_path, size_bytes, reporter)
            except RuntimeError as exc:
                reporter.error(str(exc))
                download_path.unlink(missing_ok=True)
                return 2

            # Verify SHA-256 BEFORE extract
            reporter.progress(60, f"Verifying SHA-256")
            expected_sha = flavor.get("sha256", "")
            try:
                verify_sha256(download_path, expected_sha, reporter)
            except RuntimeError as exc:
                reporter.error(str(exc))
                return 5

            # Extract into staging dir
            reporter.progress(70, f"Extracting into staging dir")
            if stage_path.exists():
                shutil.rmtree(stage_path)
            try:
                safe_extract(download_path, stage_path, size_bytes, reporter)
            except RuntimeError as exc:
                reporter.error(f"Path-traversal or extraction error: {exc}")
                shutil.rmtree(stage_path, ignore_errors=True)
                download_path.unlink(missing_ok=True)
                return 2

            # Remove download file (no longer needed; extraction done from open fd)
            download_path.unlink(missing_ok=True)

            # Atomic promote
            tool_dir = tools_dir / tool_name
            tool_dir.mkdir(parents=True, exist_ok=True)
            prev_version = atomic_promote(stage_path, tool_dir, latest_ver, is_update, reporter)

            # Update installed.json
            update_installed_json(
                tools_dir, tool_name, latest_ver, flavor,
                prev_version, manifest_url, host_info, reporter,
            )

            # Rewrite .path file
            rewrite_path_file(tools_dir, reporter)

            # Prune old versions
            updated_installed = load_installed(tools_dir, reporter)
            prune_old_versions(tool_dir, updated_installed, tool_name, reporter)

            reporter.progress(100, f"Install complete; re-run preflight to verify")
            print(f"Successfully installed {tool_name} {latest_ver}")
            return 0

        except Exception as exc:
            # Fail-closed: clean up any partial state
            shutil.rmtree(stage_path, ignore_errors=True)
            download_path.unlink(missing_ok=True)
            reporter.error(f"Install failed: {exc}")
            return 99


def cmd_remove(
    args: argparse.Namespace,
    tool_name: str,
    tools_dir: pathlib.Path,
    reporter: _Reporter,
) -> int:
    """Remove a tool entirely."""
    with _FileLock(tools_dir):
        installed = load_installed(tools_dir, reporter)
        if tool_name not in installed.get("tools", {}):
            reporter.error(f"Tool {tool_name!r} is not installed.")
            return 6

        tool_dir = tools_dir / tool_name
        if tool_dir.exists():
            reporter.log(f"Removing {tool_dir}")
            shutil.rmtree(tool_dir)

        del installed["tools"][tool_name]
        save_installed(tools_dir, installed)
        rewrite_path_file(tools_dir, reporter)
        print(f"Removed {tool_name}.")
    return 0


def cmd_path(args: argparse.Namespace, tools_dir: pathlib.Path, reporter: _Reporter) -> int:
    """Print the sourceable .path file contents."""
    path_file = tools_dir / ".path"
    if not path_file.is_file():
        # Generate it on demand even if nothing is installed
        rewrite_path_file(tools_dir, reporter)
    print(path_file.read_text(encoding="utf-8"), end="")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wb-tools-manager.py",
        description=(
            "wine-bleeding managed build-tools installer.\n"
            "Downloads pre-built toolchain tarballs from the upstream manifest,\n"
            "verifies SHA-256, and atomically extracts into the tools directory.\n\n"
            "SECURITY NOTE: WB_TOOLS_SKIP_TLS_VERIFY is intentionally NOT supported.\n"
            "TLS verification is non-optional. See --help for manual rollback instructions."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Manual rollback (if a new version is broken):\n"
            "  cd ~/.local/share/wine-bleeding/build-tools/<tool>/\n"
            "  mv current current.bad && mv .previous current\n\n"
            "Full rollback subcommand is tracked for v1.8."
        ),
    )
    p.add_argument(
        "--manifest-url",
        metavar="URL",
        default=os.environ.get("WB_TOOLS_MANIFEST_URL", DEFAULT_MANIFEST_URL),
        help=f"Manifest URL (default: {DEFAULT_MANIFEST_URL}; env: WB_TOOLS_MANIFEST_URL)",
    )
    p.add_argument(
        "--tools-dir",
        metavar="DIR",
        default=None,
        help="Tools directory (default: ~/.local/share/wine-bleeding/build-tools/; env: WB_TOOLS_DIR or WB_MANAGED_TOOLS_DIR)",
    )
    p.add_argument(
        "--progress-fd",
        metavar="FD",
        type=int,
        default=None,
        help="File descriptor for Phase-B progress events (PROGRESS: / LOG: / WARN: / ERROR:)",
    )
    p.add_argument(
        "--json",
        action="store_true",
        default=False,
        help="Machine-readable JSON output (for 'list', 'check')",
    )
    p.add_argument(
        "--force-refresh",
        action="store_true",
        default=False,
        help="Force re-fetch of manifest even if within TTL",
    )
    p.add_argument(
        "--version",
        action="store_true",
        help="Print version and exit",
    )

    sub = p.add_subparsers(dest="command", metavar="COMMAND")

    p_list = sub.add_parser("list", help="Show installed tools")
    p_list.add_argument("--json", action="store_true", default=False,
                        help="Machine-readable JSON output")

    p_check = sub.add_parser("check", help="Check for updates (exit 10 if updates available)")
    p_check.add_argument("--json", action="store_true", default=False,
                         help="Machine-readable JSON output")

    p_install = sub.add_parser("install", help="Install a managed tool")
    p_install.add_argument("tool", help="Tool name (e.g. mingw-w64-gcc, glslang)")

    p_update = sub.add_parser("update", help="Update an installed tool to the latest version")
    p_update.add_argument("tool", help="Tool name")

    p_remove = sub.add_parser("remove", help="Remove a managed tool entirely")
    p_remove.add_argument("tool", help="Tool name")

    sub.add_parser("path", help="Print the sourceable PATH snippet")

    return p


def _resolve_tools_dir(args: argparse.Namespace) -> pathlib.Path:
    """Resolve tools directory from args / env vars."""
    if args.tools_dir:
        return pathlib.Path(args.tools_dir).expanduser().resolve()
    for env_var in ("WB_TOOLS_DIR", "WB_MANAGED_TOOLS_DIR"):
        val = os.environ.get(env_var)
        if val:
            return pathlib.Path(val).expanduser().resolve()
    xdg_data = os.environ.get("XDG_DATA_HOME", "")
    if xdg_data:
        return pathlib.Path(xdg_data) / "wine-bleeding" / "build-tools"
    return DEFAULT_TOOLS_DIR


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    if args.version:
        print(f"wb-tools-manager.py {__version__}")
        return 0

    if args.command is None:
        parser.print_help()
        return 1

    # Root refusal
    if os.geteuid() == 0:
        print(
            "wb-tools-manager: Refusing to run as root.\n"
            "Why: all managed tools live under the user's HOME; running as root\n"
            "is unnecessary and could scatter files in /root that are hard to clean up.\n"
            "Next action: run as a normal user.",
            file=sys.stderr,
        )
        return 2

    tools_dir = _resolve_tools_dir(args)

    # Security: refuse if tools_dir is outside the user's HOME (anti-symlink-escape)
    home = str(pathlib.Path.home().resolve())
    if not str(tools_dir).startswith(home):
        # Allow WB_MANAGED_TOOLS_DIR overrides to /tmp (bats tests)
        if not str(tools_dir).startswith("/tmp"):
            print(
                f"wb-tools-manager: tools directory {tools_dir} is outside your HOME ({home}).\n"
                f"Refusing to operate outside user home for safety.",
                file=sys.stderr,
            )
            return 2

    reporter = _Reporter(args.progress_fd, use_json_stdout=args.json)

    manifest_url = args.manifest_url
    if not manifest_url.startswith("https://"):
        reporter.error(
            f"WB_TOOLS_MANIFEST_URL must use https:// — refusing plaintext transport. "
            f"Got: {manifest_url!r}"
        )
        return 2

    ttl_sec = int(os.environ.get("WB_TOOLS_MANIFEST_TTL_SEC", DEFAULT_MANIFEST_TTL_SEC))
    budget_bytes = int(os.environ.get("WB_TOOLS_DISK_BUDGET_BYTES", DEFAULT_DISK_BUDGET_BYTES))
    force_refresh = args.force_refresh

    try:
        if args.command == "list":
            return cmd_list(args, tools_dir, reporter)

        elif args.command == "check":
            return cmd_check(args, tools_dir, reporter, manifest_url, ttl_sec, force_refresh)

        elif args.command == "install":
            return cmd_install_or_update(
                args, args.tool, tools_dir, reporter,
                manifest_url, ttl_sec, budget_bytes, is_update=False,
            )

        elif args.command == "update":
            return cmd_install_or_update(
                args, args.tool, tools_dir, reporter,
                manifest_url, ttl_sec, budget_bytes, is_update=True,
            )

        elif args.command == "remove":
            return cmd_remove(args, args.tool, tools_dir, reporter)

        elif args.command == "path":
            return cmd_path(args, tools_dir, reporter)

        else:
            reporter.error(f"Unknown command: {args.command!r}")
            return 1

    except RuntimeError as exc:
        reporter.error(str(exc))
        return 2
    except KeyboardInterrupt:
        reporter.warn("Interrupted by user.")
        return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # pylint: disable=broad-except
        print(f"wb-tools-manager: internal error: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(99)

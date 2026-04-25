#!/usr/bin/env python3
"""
wb-lnk-parse.py — Minimal Windows .lnk (MS-SHLLINK) parser.

Usage:
    wb-lnk-parse.py <lnk_file>

Output (stdout):
    JSON: {"target_path": "<C:\\\\...>", "display_name": "<name>"}

Exit codes:
    0  — success
    1  — parse error (file not readable, truncated, or missing target info)

Implements just enough of the MS-SHLLINK spec to extract:
- Target path from LinkInfo.LocalBasePath, or fallback to StringData.NAME_STRING
- Display name from StringData NAME_STRING, or fallback to target basename

Path mapping: C:\\Program Files\\App\\app.exe inside the .lnk is returned as-is
in target_path. The caller (wb-gui-detection.sh) maps it to the host filesystem
using the prefix's drive_c path.

Dependencies: Python 3 stdlib only (struct, json, sys, os).
"""

import json
import os
import struct
import sys


def _read_uint16_le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def _read_uint32_le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def _safe_read(data: bytes, offset: int, length: int) -> bytes:
    """Read length bytes from data at offset, or raise ValueError."""
    end = offset + length
    if end > len(data):
        raise ValueError(f"read beyond end of file: offset={offset} length={length} size={len(data)}")
    return data[offset:end]


def _decode_string(data: bytes, offset: int, char_count: int, is_unicode: bool) -> str:
    """Decode a counted-character string (LinkStringData format)."""
    if is_unicode:
        byte_len = char_count * 2
        raw = _safe_read(data, offset, byte_len)
        return raw.decode("utf-16-le", errors="replace")
    else:
        raw = _safe_read(data, offset, char_count)
        return raw.decode("cp1252", errors="replace")


def parse_lnk(path: str) -> dict:
    """
    Parse a Windows Shell Link (.lnk) file.

    Returns a dict with keys:
        target_path   — Windows path string (e.g. "C:\\Program Files\\App\\app.exe")
        display_name  — Human-friendly name from the shortcut, or basename of target

    Raises ValueError on parse failure.
    """
    with open(path, "rb") as fh:
        data = fh.read()

    if len(data) < 76:
        raise ValueError("file too short to be a valid .lnk")

    # -----------------------------------------------------------------------
    # Shell Link Header (always 76 bytes, at offset 0)
    # -----------------------------------------------------------------------
    # Magic: 4C 00 00 00  (always)
    magic = _read_uint32_le(data, 0)
    if magic != 0x0000004C:
        raise ValueError(f"bad magic: 0x{magic:08X} (expected 0x0000004C)")

    # LinkFlags (offset 20, 4 bytes)
    link_flags = _read_uint32_le(data, 20)
    has_link_target_id_list = bool(link_flags & 0x00000001)
    has_link_info           = bool(link_flags & 0x00000002)
    has_name                = bool(link_flags & 0x00000004)
    has_relative_path       = bool(link_flags & 0x00000008)
    has_working_dir         = bool(link_flags & 0x00000010)
    has_arguments           = bool(link_flags & 0x00000020)
    has_icon_location       = bool(link_flags & 0x00000040)
    is_unicode              = bool(link_flags & 0x00000080)

    offset = 76  # start of optional sections

    # -----------------------------------------------------------------------
    # Optional: LinkTargetIDList
    # -----------------------------------------------------------------------
    if has_link_target_id_list:
        idlist_size = _read_uint16_le(data, offset)
        offset += 2 + idlist_size

    # -----------------------------------------------------------------------
    # Optional: LinkInfo
    # -----------------------------------------------------------------------
    target_from_link_info: str = ""
    if has_link_info:
        link_info_start = offset
        link_info_size = _read_uint32_le(data, offset)
        link_info_header_size = _read_uint32_le(data, offset + 4)
        link_info_flags = _read_uint32_le(data, offset + 8)
        # VolumeIDAndLocalBasePath flag
        has_local_base_path = bool(link_info_flags & 0x1)

        if has_local_base_path:
            # LocalBasePathOffset is at header+offset 16
            local_base_path_offset = _read_uint32_le(data, offset + 16)
            abs_offset = link_info_start + local_base_path_offset
            # Null-terminated string
            end = data.index(b"\x00", abs_offset)
            target_from_link_info = data[abs_offset:end].decode("cp1252", errors="replace")

        offset = link_info_start + link_info_size

    # -----------------------------------------------------------------------
    # Optional: StringData sections (NAME, RELATIVE_PATH, WORKING_DIR, ARGS, ICON)
    # -----------------------------------------------------------------------
    # We only care about NAME (display name, has_name flag)
    display_name_from_string: str = ""

    if has_name:
        count = _read_uint16_le(data, offset)
        offset += 2
        display_name_from_string = _decode_string(data, offset, count, is_unicode)
        offset += count * (2 if is_unicode else 1)

    # We don't need to parse remaining string sections.

    # -----------------------------------------------------------------------
    # Resolve target_path and display_name
    # -----------------------------------------------------------------------
    target_path = target_from_link_info.strip()

    # Windows-aware basename: target_path uses '\' as separator. os.path.basename
    # on Linux only splits on '/', so for "C:\\Program Files\\App\\app.exe" it
    # returns the whole string unchanged — which then ended up persisted as the
    # display_name in apps.json and rendered as the literal escaped Windows path
    # in the apps list. Split on backslash explicitly, then strip the .exe.
    def _winbasename_no_ext(p: str) -> str:
        last = p.rsplit("\\", 1)[-1]
        return os.path.splitext(last)[0]

    display_name = display_name_from_string.strip()
    if not display_name and target_path:
        display_name = _winbasename_no_ext(target_path)

    if not target_path:
        raise ValueError("could not extract target path from .lnk file")

    return {
        "target_path": target_path,
        "display_name": display_name or _winbasename_no_ext(target_path),
    }


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <lnk_file>", file=sys.stderr)
        return 1

    lnk_path = sys.argv[1]
    if not os.path.isfile(lnk_path):
        print(f"wb-lnk-parse: file not found: {lnk_path}", file=sys.stderr)
        return 1

    try:
        result = parse_lnk(lnk_path)
        print(json.dumps(result))
        return 0
    except (ValueError, struct.error, UnicodeDecodeError, OSError) as exc:
        print(f"wb-lnk-parse: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

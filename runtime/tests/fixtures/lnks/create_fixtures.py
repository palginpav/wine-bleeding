#!/usr/bin/env python3
"""
Create minimal .lnk test fixtures for wb-gui-detection tests.

Run this once to generate the binary .lnk files committed to tests/fixtures/lnks/.
All fixtures use the minimal MS-SHLLINK structure needed by wb-lnk-parse.py.
"""

import struct
import os

HEADER_GUID = b'\x01\x14\x02\x00\x00\x00\x00\x00\xC0\x00\x00\x00\x00\x00\x00\x46'


def _pack_header(link_flags: int) -> bytes:
    """Pack the 76-byte Shell Link Header."""
    # Magic
    magic = struct.pack("<I", 0x0000004C)
    # CLSID
    clsid = HEADER_GUID
    # LinkFlags (4 bytes)
    lf = struct.pack("<I", link_flags)
    # FileAttributes
    fa = struct.pack("<I", 0x00000020)  # FILE_ATTRIBUTE_ARCHIVE
    # Various timestamps (all zero)
    timestamps = b'\x00' * 24
    # FileSize
    filesize = struct.pack("<I", 0)
    # IconIndex
    icon_idx = struct.pack("<i", 0)
    # ShowCommand
    show_cmd = struct.pack("<I", 1)
    # HotKey
    hotkey = struct.pack("<H", 0)
    # Reserved
    reserved = b'\x00' * 10

    hdr = magic + clsid + lf + fa + timestamps + filesize + icon_idx + show_cmd + hotkey + reserved
    assert len(hdr) == 76, f"Header is {len(hdr)} bytes, expected 76"
    return hdr


def make_link_info_block(local_path: str) -> bytes:
    """Build a minimal LinkInfo block with LocalBasePath only."""
    # LinkInfoFlags: VolumeIDAndLocalBasePath = 0x1
    flags = struct.pack("<I", 0x00000001)
    # VolumeIDOffset (after header)
    # We'll put VolumeID right after the 28-byte header
    volume_id_offset = struct.pack("<I", 28)
    # LocalBasePathOffset: after VolumeID
    # Minimal VolumeID: DriveType(4) + DriveSerialNumber(4) + VolumeLabelOffset(4) + label(1) + nul(1) = 14 bytes
    # But the spec says VolumeID starts with size at offset 0
    # VolumeID: VolumeIDSize(4) + DriveType(4) + DriveSerialNumber(4) + VolumeLabelOffset(4) + label
    # VolumeID header size = 16, then label "C\x00"
    volume_id_size = 18  # 16 header bytes + 2 for label "C\x00"
    volume_id_label_offset = 16  # label starts at offset 16 within VolumeID
    volume_id_block = (
        struct.pack("<I", volume_id_size) +
        struct.pack("<I", 3) +           # DriveType = DRIVE_FIXED
        struct.pack("<I", 0xDEADBEEF) +  # SerialNumber
        struct.pack("<I", volume_id_label_offset) +
        b'C\x00'                         # volume label "C"
    )
    assert len(volume_id_block) == volume_id_size

    local_base_path_offset = 28 + volume_id_size
    local_base_path_bytes = local_path.encode("cp1252") + b'\x00'

    # LocalBasePathOffsetUnicode and CommonPathSuffix (not used; zero them)
    common_suffix_offset = local_base_path_offset + len(local_base_path_bytes)
    common_path_bytes = b'\x00'  # empty suffix

    link_info_header = (
        struct.pack("<I", 0) +           # LinkInfoSize placeholder (4 bytes)
        struct.pack("<I", 28) +          # LinkInfoHeaderSize = 28
        flags +
        volume_id_offset +
        struct.pack("<I", local_base_path_offset) +
        struct.pack("<I", common_suffix_offset) +
        struct.pack("<I", 0)             # CommonPathSuffixOffsetUnicode (ignored)
    )
    assert len(link_info_header) == 28

    body = volume_id_block + local_base_path_bytes + common_path_bytes
    full = link_info_header + body
    # Patch the size
    total_size = len(full)
    full = struct.pack("<I", total_size) + full[4:]
    return full


def make_string_data(display_name: str, is_unicode: bool = True) -> bytes:
    """Build the StringData block for NAME_STRING."""
    if is_unicode:
        encoded = display_name.encode("utf-16-le")
        count = len(display_name)
        return struct.pack("<H", count) + encoded
    else:
        encoded = display_name.encode("cp1252")
        return struct.pack("<H", len(encoded)) + encoded


def write_lnk_with_linkinfo(path: str, target_path: str, display_name: str = "") -> None:
    """Write a .lnk with LinkInfo.LocalBasePath and optional NAME_STRING."""
    # Flags: HasLinkInfo=0x2, HasName=0x4 (if display_name), IsUnicode=0x80
    flags = 0x00000002  # HasLinkInfo
    if display_name:
        flags |= 0x00000004 | 0x00000080  # HasName + IsUnicode

    header = _pack_header(flags)
    link_info = make_link_info_block(target_path)
    name_data = make_string_data(display_name) if display_name else b''

    with open(path, 'wb') as fh:
        fh.write(header + link_info + name_data)


def write_malformed_lnk(path: str) -> None:
    """Write a truncated / malformed .lnk that the parser must handle gracefully."""
    # Write just the first 20 bytes (well short of the 76-byte header)
    with open(path, 'wb') as fh:
        fh.write(b'\x4C\x00\x00\x00' + b'\x00' * 16)


def main():
    out_dir = os.path.dirname(os.path.abspath(__file__))

    # steam-valid.lnk: standard installer with LinkInfo + NAME_STRING
    write_lnk_with_linkinfo(
        os.path.join(out_dir, "steam-valid.lnk"),
        target_path=r"C:\Program Files (x86)\Steam\Steam.exe",
        display_name="Steam",
    )
    print("Written: steam-valid.lnk")

    # no-lnk-info.lnk: omit LinkInfo; only LinkTargetIDList placeholder (empty)
    # and NAME_STRING. Parser should fall back gracefully.
    # We write a header with only HasName, no LinkInfo — parser will fail to
    # get target_path from LinkInfo and should exit 1.
    flags_no_info = 0x00000004 | 0x00000080  # HasName + IsUnicode only
    header_no_info = _pack_header(flags_no_info)
    name_block = make_string_data("NoTargetApp")
    with open(os.path.join(out_dir, "no-lnk-info.lnk"), 'wb') as fh:
        fh.write(header_no_info + name_block)
    print("Written: no-lnk-info.lnk")

    # unicode-name.lnk: display name with non-ASCII (use cp1252-safe accented chars
    # in the path; the display_name NAME_STRING is UTF-16LE so can be full Unicode)
    write_lnk_with_linkinfo(
        os.path.join(out_dir, "unicode-name.lnk"),
        target_path=r"C:\Program Files\GameApp\game.exe",
        display_name="\u0418\u0433\u0440\u0430",  # "Игра" in Cyrillic (UTF-16LE NAME_STRING)
    )
    print("Written: unicode-name.lnk")

    # malformed.lnk: truncated binary
    write_malformed_lnk(os.path.join(out_dir, "malformed.lnk"))
    print("Written: malformed.lnk")


if __name__ == "__main__":
    main()

# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Read-only SELF/ELF patch analysis using the installed Python standard library.

No game bytes are written to the report. Padding/BSS is interpreted as zero-filled
using the same segment alignment as src/core/module.cpp, not as bytes in the SELF.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET


BASE = 0x400000
LOAD_TYPES = (1, 0x61000010)


def fnv1a(data):
    value = 0xCBF29CE484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"{value:016x}"


class Image:
    def __init__(self, path):
        self.data = path.read_bytes()
        self.segments = []
        self_segments = {}
        elf_offset = 0
        if self.data[:4] == bytes.fromhex("4f153d1d"):
            count = struct.unpack_from("<H", self.data, 24)[0]
            elf_offset = 32 + count * 32
            for index in range(count):
                flags, offset, size, _ = struct.unpack_from(
                    "<QQQQ", self.data, 32 + index * 32
                )
                if flags & 0x800:
                    if flags & (2 | 8):
                        raise ValueError("Encrypted/compressed SELF segments are unsupported")
                    self_segments[(flags >> 20) & 0xFFF] = (offset, size)
        header = struct.unpack_from("<16sHHIQQQIHHHHHH", self.data, elf_offset)
        if header[0][:6] != b"\x7fELF\x02\x01" or header[2] != 62 or header[9] != 56:
            raise ValueError("Expected a little-endian x86-64 ELF/SELF")
        for index in range(header[10]):
            p = struct.unpack_from("<IIQQQQQQ", self.data,
                                   elf_offset + header[5] + index * header[9])
            kind, flags, offset, address, _, file_size, memory_size, alignment = p
            if kind not in LOAD_TYPES or memory_size == 0:
                continue
            if file_size > memory_size:
                raise ValueError("Segment file size exceeds memory size")
            if alignment and alignment & (alignment - 1):
                raise ValueError("Invalid segment alignment")
            mapped_size = ((memory_size + alignment - 1) & ~(alignment - 1)
                           if alignment else memory_size)
            if self_segments:
                offset, stored_size = self_segments[index]
                if stored_size < file_size:
                    raise ValueError("Truncated SELF segment")
            if offset + file_size > len(self.data):
                raise ValueError("Segment lies outside the file")
            self.segments.append({"index": index, "flags": flags, "address": address,
                                  "file_offset": offset, "file_size": file_size,
                                  "mapped_size": mapped_size})

    def segment_for(self, address, size):
        for segment in self.segments:
            if (segment["address"] <= address and
                    address + size <= segment["address"] + segment["mapped_size"]):
                return segment
        raise ValueError(f"Unmapped patch range {address:#x}+{size:#x}")

    def read(self, address, size):
        segment = self.segment_for(address, size)
        relative = address - segment["address"]
        count = max(0, min(size, segment["file_size"] - relative))
        start = segment["file_offset"] + relative
        return self.data[start:start + count] + bytes(size - count)


def read_identity(path):
    data = path.read_bytes()
    magic, _, key_offset, value_offset, count = struct.unpack_from("<IIIII", data)
    if magic != 0x46535000:
        raise ValueError("Invalid param.sfo")
    result = {}
    for index in range(count):
        key, _, length, _, value = struct.unpack_from("<HHIII", data, 20 + index * 16)
        start = key_offset + key
        name = data[start:data.index(0, start)].decode("utf-8")
        if name in ("TITLE_ID", "APP_VER", "CONTENT_ID", "VERSION"):
            result[name] = data[value_offset + value:value_offset + value + length].rstrip(
                b"\0").decode("utf-8")
    return result


def analyze_references(image, root):
    """Check the ported collision payload and FOV RIP-relative references."""
    collision = next(node for node in root.findall("Metadata")
                     if node.get("Name") == "Anti-freeze guard (collision loop)")
    entries = collision.findall("./PatchList/Line")
    cave = int(entries[0].get("Address"), 16) - BASE
    payload = bytes.fromhex(entries[0].get("Value"))
    if payload[:2] != b"\xff\x05" or len(payload) != 128:
        raise ValueError("Unexpected collision payload layout")
    if not image.segment_for(cave, len(payload))["flags"] & 1:
        raise ValueError("Collision cave is not executable")
    if image.read(cave, len(payload)) != bytes(len(payload)):
        raise ValueError("Collision cave is occupied")
    counter = cave + 6 + struct.unpack_from("<i", payload, 2)[0]
    if not image.segment_for(counter, 4)["flags"] & 2 or image.read(counter, 4) != bytes(4):
        raise ValueError("Collision counter is not zero-filled writable memory")
    entry_addresses = [int(entry.get("Address"), 16) - BASE for entry in entries[1:]]
    for entry, target in zip(entries[1:], (cave, cave + 0x40)):
        code = bytes.fromhex(entry.get("Value"))
        address = int(entry.get("Address"), 16) - BASE
        if code[0] != 0xE9 or address + 5 + struct.unpack_from("<i", code, 1)[0] != target:
            raise ValueError("Collision entry branch has an unexpected target")
    branches = []
    for position, expected in ((0x20, entry_addresses[0] + 10),
                               (0x25, entry_addresses[1]), (0x51, entry_addresses[1] + 7)):
        target = cave + position + 5 + struct.unpack_from("<i", payload, position + 1)[0]
        if payload[position] != 0xE9 or target != expected:
            raise ValueError("Collision payload return branch has an unexpected target")
        image.segment_for(target, 1)
        branches.append({"from": f"0x{BASE + cave + position:08x}",
                         "to": f"0x{BASE + target:08x}"})
    fov_targets = set()
    for node in root.findall("Metadata"):
        if not node.get("Name", "").startswith("Wider field of view"):
            continue
        lines = node.findall("./PatchList/Line")
        scalar = int(lines[0].get("Address"), 16) - BASE
        if image.read(scalar, 4) != bytes(4):
            raise ValueError("FOV constant cave is occupied")
        for line in lines[1:]:
            address = int(line.get("Address"), 16) - BASE
            target = address + 4 + struct.unpack("<i", bytes.fromhex(line.get("Value")))[0]
            if target != scalar:
                raise ValueError("FOV RIP-relative reference has an unexpected target")
            fov_targets.add(f"0x{BASE + target:08x}")
    return {"collision_cave": f"0x{BASE + cave:08x}",
            "collision_counter": f"0x{BASE + counter:08x}",
            "collision_return_branches": branches, "fov_targets": sorted(fov_targets)}


def analyze(game, patch):
    image = Image(game / "eboot.bin")
    identity = read_identity(game / "sce_sys" / "param.sfo")
    root = ET.parse(patch).getroot()
    title_ids = [node.text for node in root.findall("./TitleID/ID")]
    if identity["TITLE_ID"] not in title_ids:
        raise ValueError("Patch TitleID does not match the game")
    results = []
    contexts = {}
    for metadata in root.findall("Metadata"):
        if metadata.get("AppVer") != identity["APP_VER"]:
            raise ValueError("Patch APP_VER does not match the game")
        if metadata.get("AppElf") != "eboot.bin":
            raise ValueError("Unexpected patch target")
        lines = []
        for line in metadata.findall("./PatchList/Line"):
            if line.get("Type") != "bytes":
                raise ValueError("Only byte patches are supported")
            address = int(line.get("Address"), 16) - BASE
            replacement = bytes.fromhex(line.get("Value"))
            expected = line.get("OriginalHash", "").lower()
            actual = fnv1a(image.read(address, len(replacement)))
            lines.append({"address": line.get("Address"), "size": len(replacement),
                          "expected": expected, "actual": actual,
                          "matches": bool(expected) and expected == actual})
            if line.get("Address") not in contexts:
                segment = image.segment_for(address, len(replacement))
                start = max(segment["address"], address - 16)
                end = min(segment["address"] + segment["mapped_size"],
                          address + len(replacement) + 16)
                contexts[line.get("Address")] = {
                    "context_address": f"0x{BASE + start:08x}", "size": end - start,
                    "sha256": hashlib.sha256(image.read(start, end - start)).hexdigest(),
                    "zero_fill": address >= segment["address"] + segment["file_size"]}
        results.append({"name": metadata.get("Name"),
                        "enabled": metadata.get("isEnabled") == "true", "lines": lines})
    lines = [line for patch_result in results for line in patch_result["lines"]]
    references = analyze_references(image, root)
    resolution_defaults = [result["name"] for result in results if result["enabled"] and
                           result["name"].startswith(("Native ", "PS4 Pro mode:"))]
    if len(resolution_defaults) != 1:
        raise ValueError("Expected exactly one default resolution patch")
    return {"identity": identity, "self_sha256": hashlib.sha256(image.data).hexdigest(),
            "file_size": len(image.data), "patch_file": patch.name,
            "patch_count": len(results), "line_count": len(lines),
            "unique_addresses": len(contexts), "all_original_hashes_match": all(
                line["matches"] for line in lines), "segments": image.segments,
            "contexts": contexts, "patches": results, "references": references,
            "default_resolution": resolution_defaults[0],
            "runtime_verified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path, help="Game directory containing eboot.bin and sce_sys")
    parser.add_argument("--patch", type=Path, default=Path(__file__).resolve().parents[1] /
                        "package/user-files/patches/shadPS4-AYOUB1080p/"
                        "inFAMOUS Second Son CUSA00309.xml")
    parser.add_argument("--report", type=Path, help="Optionally write a JSON report without game bytes")
    args = parser.parse_args()
    try:
        report = analyze(args.game, args.patch)
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"{report['identity']['TITLE_ID']} APP_VER {report['identity']['APP_VER']}")
        print(f"SELF SHA256: {report['self_sha256']}")
        print(f"{report['patch_count']} patches, {report['line_count']} lines, "
              f"{report['unique_addresses']} unique addresses")
        print(f"All original hashes match: {report['all_original_hashes_match']}")
        for patch in report["patches"]:
            for line in patch["lines"]:
                if not line["matches"]:
                    print(f"MISMATCH: {patch['name']} at {line['address']}")
        return 0 if report["all_original_hashes_match"] else 1
    except (OSError, ValueError, KeyError, IndexError, StopIteration, struct.error,
            ET.ParseError) as error:
        print(f"Analysis failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

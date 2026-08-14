#!/usr/bin/env python3
"""Bind one trusted native executable and validate its Mach-O or ELF architecture."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import sys
from typing import NoReturn, Optional, Set, Tuple


MAX_EXECUTABLE_BYTES = 512 * 1024 * 1024


class ValidationError(ValueError):
    """A controlled executable-admission refusal."""


def refuse(message: str) -> NoReturn:
    raise ValidationError(message)


def canonical_path(value: str, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        refuse(f"{label} path must be absolute")
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        refuse(f"{label} path cannot be resolved: {error}")
    if resolved != path:
        refuse(f"{label} path must already be canonical and contain no symbolic link")
    return path


def same_identity(left: os.stat_result, right: os.stat_result) -> bool:
    return all(
        getattr(left, field) == getattr(right, field)
        for field in (
            "st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink",
            "st_size", "st_mtime_ns", "st_ctime_ns",
        )
    )


def read_executable(path: Path, label: str) -> Tuple[bytes, os.stat_result]:
    before = path.lstat()
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        refuse(f"{label} must be a regular non-symbolic-link file")
    flags = os.O_RDONLY
    for name in ("O_CLOEXEC", "O_NOFOLLOW", "O_NONBLOCK"):
        flags |= getattr(os, name, 0)
    descriptor = os.open(str(path), flags)
    try:
        opened = os.fstat(descriptor)
        if not same_identity(before, opened):
            refuse(f"{label} changed while it was opened")
        if not stat.S_ISREG(opened.st_mode):
            refuse(f"{label} is not a regular file")
        if opened.st_uid not in (0, os.geteuid()):
            refuse(f"{label} has an untrusted owner")
        if opened.st_nlink != 1:
            refuse(f"{label} must have exactly one hard link")
        if not opened.st_mode & 0o111:
            refuse(f"{label} is not executable")
        if opened.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            refuse(f"{label} must not be group- or other-writable")
        if opened.st_size < 20 or opened.st_size > MAX_EXECUTABLE_BYTES:
            refuse(f"{label} size is outside the executable bound")
        payload = bytearray()
        while len(payload) <= MAX_EXECUTABLE_BYTES:
            chunk = os.read(descriptor, min(1024 * 1024, MAX_EXECUTABLE_BYTES + 1 - len(payload)))
            if not chunk:
                break
            payload.extend(chunk)
        after = os.fstat(descriptor)
        if not same_identity(opened, after) or len(payload) != opened.st_size:
            refuse(f"{label} changed while it was read")
        return bytes(payload), opened
    finally:
        os.close(descriptor)


def cpu_architecture(cpu_type: int) -> Optional[str]:
    return {0x0100000C: "arm64", 0x01000007: "x86_64"}.get(cpu_type)


def validate_macho_header(
    raw: bytes,
    offset: int,
    limit: int,
    endian: str,
    expected_cpu: Optional[int],
    label: str,
) -> int:
    if limit > len(raw) or offset < 0 or limit < offset + 32:
        refuse(f"{label} has a truncated 64-bit Mach-O header")
    values = struct.unpack(endian + "IIIIIIII", raw[offset : offset + 32])
    _, cpu_type, _, file_type, command_count, command_bytes, _, _ = values
    if expected_cpu is not None and cpu_type != expected_cpu:
        refuse(f"{label} Mach-O CPU type disagrees with its container")
    if file_type != 2:
        refuse(f"{label} must be a Mach-O executable")
    if command_count > 100_000 or command_bytes > limit - offset - 32:
        refuse(f"{label} has invalid Mach-O load-command bounds")
    return cpu_type


def binary_identity(raw: bytes, label: str) -> Tuple[str, Set[str]]:
    if len(raw) < 20:
        refuse(f"{label} is too small to be a supported executable")
    if raw.startswith(b"\x7fELF"):
        if len(raw) < 64 or raw[4] != 2 or raw[5] not in (1, 2) or raw[6] != 1:
            refuse(f"{label} must be a 64-bit ELF executable")
        endian = "<" if raw[5] == 1 else ">"
        elf_type = struct.unpack(endian + "H", raw[16:18])[0]
        if elf_type not in (2, 3):
            refuse(f"{label} must be an ELF executable or shared object")
        machine = struct.unpack(endian + "H", raw[18:20])[0]
        if struct.unpack(endian + "I", raw[20:24])[0] != 1:
            refuse(f"{label} has an invalid ELF version")
        architecture = {62: "x86_64", 183: "arm64"}.get(machine)
        if architecture is None:
            refuse(f"{label} has an unsupported ELF architecture")
        if raw[5] != 1:
            refuse(f"{label} has unsupported ELF architecture byte order")
        program_offset = struct.unpack(endian + "Q", raw[32:40])[0]
        section_offset = struct.unpack(endian + "Q", raw[40:48])[0]
        header_size, program_size, program_count, section_size, section_count = \
            struct.unpack(endian + "HHHHH", raw[52:62])
        if header_size != 64:
            refuse(f"{label} has an invalid ELF header size")
        if program_count and (
            program_size != 56
            or program_offset < header_size
            or program_offset + program_size * program_count > len(raw)
        ):
            refuse(f"{label} has invalid ELF program-header bounds")
        if section_count and (
            section_size != 64
            or section_offset < header_size
            or section_offset + section_size * section_count > len(raw)
        ):
            refuse(f"{label} has invalid ELF section-header bounds")
        return "elf", {architecture}

    thin_magics = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">"}
    if raw[:4] in thin_magics:
        cpu_type = validate_macho_header(
            raw, 0, len(raw), thin_magics[raw[:4]], None, label
        )
        architecture = cpu_architecture(cpu_type)
        if architecture is None:
            refuse(f"{label} has an unsupported Mach-O architecture")
        return "mach-o", {architecture}

    fat_magics = {
        b"\xca\xfe\xba\xbe": (">", 20),
        b"\xbe\xba\xfe\xca": ("<", 20),
        b"\xca\xfe\xba\xbf": (">", 32),
        b"\xbf\xba\xfe\xca": ("<", 32),
    }
    fat = fat_magics.get(raw[:4])
    if fat is None:
        refuse(f"{label} is not a supported ELF or Mach-O executable")
    endian, width = fat
    if len(raw) < 8:
        refuse(f"{label} has a truncated universal Mach-O header")
    count = struct.unpack(endian + "I", raw[4:8])[0]
    if count < 1 or count > 32 or len(raw) < 8 + count * width:
        refuse(f"{label} has an invalid universal Mach-O header")
    architectures: Set[str] = set()
    seen_cpu_types: Set[int] = set()
    slice_ranges = []
    for index in range(count):
        entry_offset = 8 + index * width
        cpu_type = struct.unpack(endian + "I", raw[entry_offset : entry_offset + 4])[0]
        if cpu_type in seen_cpu_types:
            refuse(f"{label} has duplicate universal Mach-O CPU slices")
        seen_cpu_types.add(cpu_type)
        architecture = cpu_architecture(cpu_type)
        if width == 20:
            slice_offset, slice_size = struct.unpack(
                endian + "II", raw[entry_offset + 8 : entry_offset + 16]
            )
        else:
            slice_offset, slice_size = struct.unpack(
                endian + "QQ", raw[entry_offset + 8 : entry_offset + 24]
            )
        if (
            slice_size < 32
            or slice_offset < 8 + count * width
            or slice_offset + slice_size > len(raw)
        ):
            refuse(f"{label} has an invalid universal Mach-O slice")
        slice_end = slice_offset + slice_size
        if any(
            slice_offset < observed_end and observed_start < slice_end
            for observed_start, observed_end in slice_ranges
        ):
            refuse(f"{label} has overlapping universal Mach-O slices")
        slice_ranges.append((slice_offset, slice_end))
        slice_endian = thin_magics.get(raw[slice_offset : slice_offset + 4])
        if slice_endian is None:
            refuse(f"{label} universal slice is not 64-bit Mach-O")
        validate_macho_header(
            raw, slice_offset, slice_end, slice_endian, cpu_type, label
        )
        if architecture is not None:
            architectures.add(architecture)
    if not architectures:
        refuse(f"{label} has no supported universal Mach-O slice")
    return "mach-o-universal", architectures


def bind(path_value: str, operating_system: str, architecture: str, label: str) -> dict:
    path = canonical_path(path_value, label)
    raw, metadata = read_executable(path, label)
    format_name, architectures = binary_identity(raw, label)
    normalized = "arm64" if architecture in ("arm64", "aarch64") else architecture
    if operating_system == "Darwin" and not format_name.startswith("mach-o"):
        refuse(f"{label} is not a Mach-O executable for Darwin")
    if operating_system == "Linux" and format_name != "elf":
        refuse(f"{label} is not an ELF executable for Linux")
    if normalized not in architectures:
        refuse(f"{label} does not contain the admitted {architecture} architecture")
    return {
        "architectures": sorted(architectures),
        "format": format_name,
        "mode": f"{stat.S_IMODE(metadata.st_mode):04o}",
        "path": str(path),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "size_bytes": len(raw),
        "type": "file",
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("path")
    result.add_argument("operating_system", choices=("Darwin", "Linux"))
    result.add_argument("architecture", choices=("arm64", "aarch64", "x86_64"))
    result.add_argument("label")
    return result


def main() -> int:
    arguments = parser().parse_args()
    try:
        value = bind(
            arguments.path,
            arguments.operating_system,
            arguments.architecture,
            arguments.label,
        )
    except (OSError, ValidationError, struct.error) as error:
        print(f"native executable refused: {error}", file=sys.stderr)
        return 2
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

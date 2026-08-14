#!/usr/bin/env python3
"""Write MAINFRAME's canonical deterministic USTAR+gzip release archive."""

from __future__ import annotations

import binascii
import os
from pathlib import Path, PurePosixPath
import stat
import struct
import sys
import tarfile
import tempfile
from typing import NoReturn


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def main() -> int:
    if len(sys.argv) != 3:
        fail("usage: build-release-tar.py STAGE ARCHIVE")

    stage = Path(sys.argv[1]).resolve(strict=True)
    archive = Path(sys.argv[2])
    names = [line.rstrip("\n") for line in sys.stdin]
    if not names or any(not name for name in names):
        fail("release file inventory is empty or malformed")
    if names != sorted(names) or len(names) != len(set(names)):
        fail("release file inventory must be sorted and unique")

    files: list[tuple[str, Path, os.stat_result]] = []
    for name in names:
        posix_name = PurePosixPath(name)
        if posix_name.is_absolute() or any(part in ("", ".", "..") for part in posix_name.parts):
            fail(f"unsafe release member path: {name}")
        source = stage.joinpath(*posix_name.parts)
        if source.is_symlink() or not source.is_file():
            fail(f"release member is not a regular file: {name}")
        resolved = source.resolve(strict=True)
        if os.path.commonpath((str(stage), str(resolved))) != str(stage):
            fail(f"release member escapes staging root: {name}")
        files.append((name, resolved, resolved.stat()))

    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile() as tar_stream:
        with tarfile.open(
            fileobj=tar_stream, mode="w", format=tarfile.USTAR_FORMAT
        ) as output:
            for name, source, metadata in files:
                info = tarfile.TarInfo(name)
                info.size = metadata.st_size
                info.mode = stat.S_IMODE(metadata.st_mode)
                info.mtime = 0
                info.uid = 0
                info.gid = 0
                info.uname = ""
                info.gname = ""
                with source.open("rb") as contents:
                    output.addfile(info, contents)

        # Write a valid gzip stream using only fixed-size DEFLATE stored blocks.
        # This trades compression ratio for byte identity independent of the
        # host zlib implementation and version.
        tar_stream.seek(0)
        with archive.open("wb") as compressed:
            compressed.write(b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\xff")
            checksum = 0
            total_size = 0
            current = tar_stream.read(65535)
            if not current:
                compressed.write(b"\x01\x00\x00\xff\xff")
            while current:
                following = tar_stream.read(65535)
                final = not following
                length = len(current)
                compressed.write(b"\x01" if final else b"\x00")
                compressed.write(struct.pack("<HH", length, length ^ 0xFFFF))
                compressed.write(current)
                checksum = binascii.crc32(current, checksum)
                total_size = (total_size + length) & 0xFFFFFFFF
                current = following
            compressed.write(struct.pack("<II", checksum & 0xFFFFFFFF, total_size))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate and extract a bounded MAINFRAME release tarball in one stream."""

from __future__ import annotations

import gzip
import os
import pathlib
import tarfile
import sys
from typing import NoReturn


MAX_MEMBERS = 10_000
MAX_EXPANDED_BYTES = 512 * 1024 * 1024
# Bound gzip expansion that tar metadata (including PAX records and padding)
# can consume in addition to the admitted regular-file payload.
MAX_TAR_STREAM_BYTES = MAX_EXPANDED_BYTES + (MAX_MEMBERS * 2048) + (1024 * 1024)
MAX_ARCHIVE_BYTES = MAX_TAR_STREAM_BYTES


class BoundedReader:
    """Expose read() while refusing to decompress beyond an exact byte cap."""

    def __init__(self, source: gzip.GzipFile, limit: int) -> None:
        self.source = source
        self.limit = limit
        self.consumed = 0

    def read(self, size: int = -1) -> bytes:
        remaining = self.limit - self.consumed
        request = remaining + 1 if size < 0 else min(size, remaining + 1)
        data = self.source.read(request)
        self.consumed += len(data)
        if self.consumed > self.limit:
            raise OSError("release archive tar stream exceeds the size limit")
        return data


def die(message: str) -> NoReturn:
    raise SystemExit(message)


def safe_path(member: tarfile.TarInfo) -> pathlib.PurePosixPath:
    path = pathlib.PurePosixPath(member.name)
    source_name = member.name.rstrip("/") if member.isdir() else member.name
    if (
        not source_name
        or path.is_absolute()
        or ".." in path.parts
        or source_name != str(path)
    ):
        die(f"unsafe release archive path: {member.name}")
    return path


def main() -> None:
    if len(sys.argv) != 3:
        die("usage: safe-extract.py ARCHIVE DESTINATION")

    archive = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    if archive.is_symlink() or not archive.is_file():
        die(f"release archive must be a regular, non-symlink file: {archive}")
    if archive.stat().st_size > MAX_ARCHIVE_BYTES:
        die("release archive exceeds the compressed size limit")
    if destination.is_symlink() or not destination.is_dir():
        die(f"release destination must be a real directory: {destination}")
    destination = destination.resolve(strict=True)
    if any(destination.iterdir()):
        die("release destination must be empty")

    names: set[str] = set()
    member_count = 0
    expanded_bytes = 0

    with archive.open("rb") as compressed:
        with gzip.GzipFile(fileobj=compressed, mode="rb") as uncompressed:
            bounded = BoundedReader(uncompressed, MAX_TAR_STREAM_BYTES)
            with tarfile.open(fileobj=bounded, mode="r|") as handle:
                for member in handle:
                    member_count += 1
                    if member_count > MAX_MEMBERS:
                        die("release archive has too many entries")

                    path = safe_path(member)
                    canonical = str(path)
                    if canonical in names:
                        die(f"duplicate release archive path: {member.name}")
                    names.add(canonical)
                    if not (member.isfile() or member.isdir()):
                        die(f"unsupported release archive entry: {member.name}")
                    if member.size < 0:
                        die(f"negative release archive size: {member.name}")

                    mode = member.mode & 0o7777
                    allowed_modes = {0o644, 0o755} if member.isfile() else {0o755}
                    if mode not in allowed_modes:
                        die(f"unsupported release archive mode {mode:o}: {member.name}")

                    target = destination.joinpath(*path.parts)
                    if member.isdir():
                        target.mkdir(mode=0o755, parents=True, exist_ok=True)
                        target.chmod(mode)
                        continue

                    expanded_bytes += member.size
                    if expanded_bytes > MAX_EXPANDED_BYTES:
                        die("release archive expands beyond the size limit")
                    target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
                    source = handle.extractfile(member)
                    if source is None:
                        die(f"release archive file has no data: {member.name}")
                    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
                    if hasattr(os, "O_NOFOLLOW"):
                        flags |= os.O_NOFOLLOW
                    descriptor = os.open(target, flags, 0o600)
                    remaining = member.size
                    try:
                        with os.fdopen(descriptor, "wb") as output:
                            while remaining:
                                chunk = source.read(min(1024 * 1024, remaining))
                                if not chunk:
                                    die(f"truncated release archive file: {member.name}")
                                output.write(chunk)
                                remaining -= len(chunk)
                    finally:
                        source.close()
                    target.chmod(mode)

    if member_count == 0:
        die("release archive is empty")


if __name__ == "__main__":
    main()

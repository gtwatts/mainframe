"""Portable fail-closed directory-entry durability helpers for macOS/Linux."""

from __future__ import annotations

import errno
import os
from pathlib import Path
import stat
from typing import List, Set, Union

from .errors import DurabilityUnavailable, LedgerIOError


PathLike = Union[str, os.PathLike[str]]
_UNSUPPORTED_FSYNC_ERRNOS = frozenset(
    value
    for value in (
        errno.EINVAL,
        errno.ENOSYS,
        getattr(errno, "ENOTSUP", None),
        getattr(errno, "EOPNOTSUPP", None),
    )
    if value is not None
)


def fsync_directory(path: PathLike) -> None:
    """Persist directory entries or fail closed when the platform cannot do so."""

    directory_flag = getattr(os, "O_DIRECTORY", None)
    if directory_flag is None:
        raise DurabilityUnavailable(
            "directory fsync is unsupported on this platform"
        )
    flags = os.O_RDONLY | os.O_CLOEXEC | directory_flag
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(os.fspath(path), flags)
    except OSError as exc:
        if exc.errno in _UNSUPPORTED_FSYNC_ERRNOS:
            raise DurabilityUnavailable(
                "directory fsync is unsupported for the state filesystem"
            ) from exc
        raise LedgerIOError("unable to open directory for fsync") from exc
    try:
        if not stat.S_ISDIR(os.fstat(fd).st_mode):
            raise LedgerIOError("directory fsync target is not a directory")
        try:
            os.fsync(fd)
        except OSError as exc:
            if exc.errno in _UNSUPPORTED_FSYNC_ERRNOS:
                raise DurabilityUnavailable(
                    "directory fsync is unsupported for the state filesystem"
                ) from exc
            raise LedgerIOError("unable to fsync directory") from exc
    finally:
        os.close(fd)


def create_directory_durable(
    path: PathLike, *, mode: int = 0o700, parents: bool = False
) -> bool:
    """Create a directory and fsync every newly introduced directory entry.

    The return value reports whether the requested leaf was absent before the
    operation. Existing directories are not modified or redundantly fsynced.
    """

    target = Path(path)
    if target.exists():
        return False
    missing: List[Path] = []
    cursor = target
    while not cursor.exists():
        missing.append(cursor)
        parent = cursor.parent
        if parent == cursor:
            raise LedgerIOError("no existing ancestor for private directory")
        cursor = parent
    target.mkdir(mode=mode, parents=parents, exist_ok=True)

    # Bottom-up fsync makes each child durable before persisting its name in
    # its parent. Include the nearest pre-existing ancestor as the final anchor.
    observed: Set[Path] = set()
    for directory in missing + [cursor]:
        if directory in observed:
            continue
        fsync_directory(directory)
        observed.add(directory)
    return bool(missing)

#!/usr/bin/env python3
"""Descriptor-safe filesystem transactions for MAINFRAME managed hosts."""

from __future__ import annotations

import argparse
import ctypes
import errno
import os
import re
import stat
import sys
from typing import NoReturn


SAFE_COMPONENT = re.compile(r"^[A-Za-z0-9._@+ -]+$")
QUARANTINE_ID = re.compile(r"^removed\.[0-9a-f]{18}$")
RENAME_NOREPLACE = 0x00000001
RENAME_EXCL = 0x00000004
RENAME_NOFOLLOW_ANY = 0x00000010
LOCK_OWNER = "owner"
WORKSPACE_PREFIXES = {
    "temporary": "mainframe-host-stage.",
    "managed": ".install-stage.",
}


def die(message: str) -> NoReturn:
    raise SystemExit(f"managed host filesystem operation failed: {message}")


def descriptor_flags() -> int:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return flags


def identity(metadata: os.stat_result) -> str:
    return f"{metadata.st_dev}:{metadata.st_ino}"


def parse_identity(value: str) -> str:
    if re.fullmatch(r"[0-9]+:[0-9]+", value) is None:
        die("expected filesystem identity is malformed")
    return value


def parse_process_id(value: str) -> str:
    if re.fullmatch(r"[1-9][0-9]*", value) is None:
        die("lock owner process identifier is malformed")
    return value


def parse_quarantine_id(value: str) -> str:
    if QUARANTINE_ID.fullmatch(value) is None:
        die("quarantine slot identifier is malformed")
    return value


def generate_quarantine_id() -> None:
    print(f"removed.{os.urandom(9).hex()}")


def safe_component(value: str) -> str:
    if (
        not value
        or value in (".", "..")
        or SAFE_COMPONENT.fullmatch(value) is None
        or len(value.encode("utf-8")) > 255
    ):
        die("filesystem component is unsafe")
    return value


def relative_parts(value: str) -> tuple[str, ...]:
    if (
        not value
        or value.startswith("/")
        or value.endswith("/")
        or "//" in value
        or "\n" in value
        or "\r" in value
        or "\t" in value
    ):
        die("relative managed-host path is unsafe")
    parts = tuple(safe_component(part) for part in value.split("/"))
    if not parts or len(parts) > 16:
        die("relative managed-host path depth is unsafe")
    return parts


def validate_private_directory(metadata: os.stat_result, *, exact: bool = False) -> None:
    mode = stat.S_IMODE(metadata.st_mode)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or mode & 0o022
        or mode & 0o7000
        or (exact and mode != 0o700)
    ):
        die("managed-host directory ownership or mode is unsafe")


def open_absolute_directory(
    path: str,
    *,
    expected_identity: str | None = None,
    private: bool = False,
) -> tuple[int, os.stat_result]:
    if not path.startswith("/") or path == "/" or any(c in path for c in "\n\r\t"):
        die("absolute filesystem parent is unsafe")
    try:
        descriptor = os.open(path, descriptor_flags())
    except OSError as exc:
        die(exc.strerror or "could not open filesystem parent")
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode):
        os.close(descriptor)
        die("filesystem parent is not a real directory")
    if expected_identity is not None and identity(metadata) != parse_identity(expected_identity):
        os.close(descriptor)
        die("filesystem parent identity changed")
    if private:
        validate_private_directory(metadata, exact=True)
    return descriptor, metadata


def stat_at(parent: int, name: str) -> os.stat_result | None:
    try:
        return os.stat(name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return None


def regular_file_flags(*, write: bool = False, create: bool = False) -> int:
    flags = os.O_WRONLY if write else os.O_RDONLY
    if create:
        flags |= os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return flags


def write_all(descriptor: int, value: bytes) -> None:
    remaining = memoryview(value)
    while remaining:
        written = os.write(descriptor, remaining)
        if written <= 0:
            die("could not write lifecycle lock owner record")
        remaining = remaining[written:]


def validate_owner_record(metadata: os.stat_result, device: int) -> None:
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or metadata.st_dev != device
        or metadata.st_nlink != 1
        or stat.S_IMODE(metadata.st_mode) != 0o600
    ):
        die("lifecycle lock owner record is unsafe")


def open_directory_at(parent: int, name: str, device: int) -> tuple[int, os.stat_result]:
    safe_component(name)
    descriptor = os.open(name, descriptor_flags(), dir_fd=parent)
    metadata = os.fstat(descriptor)
    validate_private_directory(metadata)
    if metadata.st_dev != device:
        os.close(descriptor)
        die("managed-host directory crosses a filesystem boundary")
    return descriptor, metadata


def rollback_empty_created_directory(
    parent: int,
    name: str,
    device: int,
    held_descriptor: int = -1,
) -> bool:
    """Remove one exact empty private directory after a failed create transaction."""
    descriptor = held_descriptor
    opened_here = False
    try:
        current = stat_at(parent, name)
        if current is None:
            return True
        validate_private_directory(current, exact=True)
        if current.st_dev != device:
            return False
        if descriptor < 0:
            descriptor, opened = open_directory_at(parent, name, device)
            opened_here = True
        else:
            opened = os.fstat(descriptor)
            validate_private_directory(opened, exact=True)
        if identity(current) != identity(opened) or os.listdir(descriptor):
            return False
        latest = stat_at(parent, name)
        if latest is None or identity(latest) != identity(opened):
            return False
        os.rmdir(name, dir_fd=parent)
        os.fsync(parent)
        return True
    except (OSError, SystemExit):
        return False
    finally:
        if opened_here and descriptor >= 0:
            os.close(descriptor)


def descend(
    root: int,
    parts: tuple[str, ...],
    device: int,
    *,
    create: bool,
) -> int:
    current = os.dup(root)
    try:
        for part in parts:
            created = False
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=current)
                    created = True
                    os.fsync(current)
                except FileExistsError:
                    pass
            child, metadata = open_directory_at(current, part, device)
            if created and stat.S_IMODE(metadata.st_mode) != 0o700:
                os.close(child)
                die("new managed-host directory has an unexpected mode")
            os.close(current)
            current = child
        return current
    except BaseException:
        os.close(current)
        raise


def open_source_directory(
    root: int,
    parts: tuple[str, ...],
    device: int,
    expected: str,
) -> tuple[int, str, os.stat_result]:
    parent = descend(root, parts[:-1], device, create=False)
    name = parts[-1]
    metadata = stat_at(parent, name)
    if metadata is None:
        os.close(parent)
        die("managed-host source disappeared")
    validate_private_directory(metadata, exact=True)
    if metadata.st_dev != device or identity(metadata) != parse_identity(expected):
        os.close(parent)
        die("managed-host source identity changed")
    opened, opened_metadata = open_directory_at(parent, name, device)
    os.close(opened)
    if identity(opened_metadata) != identity(metadata):
        os.close(parent)
        die("managed-host source was substituted")
    return parent, name, metadata


def rename_no_replace(source_parent: int, source: str, target_parent: int, target: str) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    source_bytes = os.fsencode(source)
    target_bytes = os.fsencode(target)
    result: int
    if sys.platform == "darwin":
        function = getattr(libc, "renameatx_np", None)
        if function is None:
            die("kernel no-replace rename is unavailable")
        function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        function.restype = ctypes.c_int
        result = function(
            source_parent,
            source_bytes,
            target_parent,
            target_bytes,
            RENAME_EXCL | RENAME_NOFOLLOW_ANY,
        )
    elif sys.platform.startswith("linux"):
        function = getattr(libc, "renameat2", None)
        if function is None:
            die("kernel no-replace rename is unavailable")
        function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        function.restype = ctypes.c_int
        result = function(
            source_parent,
            source_bytes,
            target_parent,
            target_bytes,
            RENAME_NOREPLACE,
        )
    else:
        die("operating system has no reviewed no-replace rename contract")
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number in (errno.EEXIST, errno.ENOTEMPTY):
            die("managed-host destination already exists")
        if error_number == errno.EXDEV:
            die("managed-host rename crossed a filesystem boundary")
        die(os.strerror(error_number) if error_number else "kernel rename failed")


def sync_tree(directory: int, device: int) -> None:
    for name in os.listdir(directory):
        safe_component(name)
        metadata = stat_at(directory, name)
        if metadata is None or metadata.st_uid != os.geteuid() or metadata.st_dev != device:
            die("managed-host tree changed during durability sync")
        if stat.S_ISDIR(metadata.st_mode):
            child, opened = open_directory_at(directory, name, device)
            if identity(opened) != identity(metadata):
                os.close(child)
                die("managed-host directory changed during durability sync")
            sync_tree(child, device)
            os.fsync(child)
            os.close(child)
        elif stat.S_ISREG(metadata.st_mode):
            if metadata.st_nlink != 1:
                die("managed-host file has multiple hard links")
            flags = os.O_RDONLY
            if hasattr(os, "O_CLOEXEC"):
                flags |= os.O_CLOEXEC
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            descriptor = os.open(name, flags, dir_fd=directory)
            opened = os.fstat(descriptor)
            if (
                identity(opened) != identity(metadata)
                or not stat.S_ISREG(opened.st_mode)
                or opened.st_uid != os.geteuid()
                or opened.st_dev != device
                or opened.st_nlink != 1
                or stat.S_IMODE(opened.st_mode) != stat.S_IMODE(metadata.st_mode)
            ):
                os.close(descriptor)
                die("managed-host file metadata changed during durability sync")
            os.fsync(descriptor)
            os.close(descriptor)
        else:
            die("managed-host tree contains an unsupported entry")
    os.fsync(directory)


def acquire_lock(
    root_path: str,
    root_expected: str,
    lock_value: str,
    owner_value: str,
) -> None:
    lock_name = safe_component(lock_value)
    owner = parse_process_id(owner_value)
    root, root_metadata = open_absolute_directory(
        root_path, expected_identity=root_expected, private=True
    )
    device = root_metadata.st_dev
    created = False
    lock_descriptor = -1
    try:
        if stat_at(root, lock_name) is not None:
            die("managed-host lifecycle lock already exists; inspect it manually")
        os.mkdir(lock_name, 0o700, dir_fd=root)
        created = True
        lock_metadata = stat_at(root, lock_name)
        if lock_metadata is None:
            die("new lifecycle lock disappeared")
        validate_private_directory(lock_metadata, exact=True)
        if lock_metadata.st_dev != device:
            die("lifecycle lock crosses a filesystem boundary")
        lock_descriptor, opened_lock = open_directory_at(root, lock_name, device)
        if identity(opened_lock) != identity(lock_metadata):
            die("new lifecycle lock was substituted")
        owner_descriptor = os.open(
            LOCK_OWNER,
            regular_file_flags(write=True, create=True),
            0o600,
            dir_fd=lock_descriptor,
        )
        try:
            opened_owner = os.fstat(owner_descriptor)
            validate_owner_record(opened_owner, device)
            write_all(owner_descriptor, f"{owner}\n".encode("ascii"))
            os.fsync(owner_descriptor)
        finally:
            os.close(owner_descriptor)
        os.fsync(lock_descriptor)
        os.fsync(root)
        sys.stdout.write(f"{identity(opened_lock)}\n")
        sys.stdout.flush()
    except BaseException:
        if lock_descriptor >= 0:
            try:
                owner_metadata = stat_at(lock_descriptor, LOCK_OWNER)
                if owner_metadata is not None:
                    validate_owner_record(owner_metadata, device)
                    os.unlink(LOCK_OWNER, dir_fd=lock_descriptor)
                    os.fsync(lock_descriptor)
            except (OSError, SystemExit):
                pass
        if created:
            rollback_empty_created_directory(
                root,
                lock_name,
                device,
                lock_descriptor,
            )
        raise
    finally:
        if lock_descriptor >= 0:
            os.close(lock_descriptor)
        os.close(root)


def create_workspace(
    parent_path: str,
    parent_expected: str,
    workspace_kind: str,
) -> None:
    prefix = WORKSPACE_PREFIXES.get(workspace_kind)
    if prefix is None:
        die("lifecycle workspace kind is unsupported")
    parent, parent_metadata = open_absolute_directory(
        parent_path,
        expected_identity=parent_expected,
        private=workspace_kind == "managed",
    )
    if workspace_kind == "temporary":
        parent_mode = stat.S_IMODE(parent_metadata.st_mode)
        if (
            parent_metadata.st_uid != 0
            or ((parent_mode & 0o022) and not (parent_mode & stat.S_ISVTX))
        ):
            os.close(parent)
            die("temporary workspace parent is not a root-owned sticky directory")

    device = parent_metadata.st_dev
    workspace = -1
    leaf = ""
    created = False
    try:
        for _ in range(64):
            candidate = f"{prefix}{os.urandom(12).hex()}"
            try:
                os.mkdir(candidate, 0o700, dir_fd=parent)
                leaf = candidate
                created = True
                break
            except FileExistsError:
                continue
        if not created:
            die("could not allocate a unique lifecycle workspace")

        workspace_metadata = stat_at(parent, leaf)
        if workspace_metadata is None:
            die("new lifecycle workspace disappeared")
        validate_private_directory(workspace_metadata, exact=True)
        if workspace_metadata.st_dev != device:
            die("lifecycle workspace crosses a filesystem boundary")
        workspace, opened_workspace = open_directory_at(parent, leaf, device)
        if (
            identity(opened_workspace) != identity(workspace_metadata)
            or stat.S_IMODE(opened_workspace.st_mode) != 0o700
        ):
            die("new lifecycle workspace was substituted")
        if os.listdir(workspace):
            die("new lifecycle workspace is not empty")
        os.fsync(workspace)
        os.fsync(parent)
        sys.stdout.write(
            f"{leaf} {identity(parent_metadata)} {identity(opened_workspace)}\n"
        )
        sys.stdout.flush()
    except BaseException:
        if created:
            rollback_empty_created_directory(
                parent,
                leaf,
                device,
                workspace,
            )
        raise
    finally:
        if workspace >= 0:
            os.close(workspace)
        os.close(parent)


def release_lock(
    root_path: str,
    root_expected: str,
    lock_value: str,
    lock_expected: str,
    owner_value: str,
) -> None:
    lock_name = safe_component(lock_value)
    expected_lock = parse_identity(lock_expected)
    owner = parse_process_id(owner_value)
    root, root_metadata = open_absolute_directory(
        root_path, expected_identity=root_expected, private=True
    )
    device = root_metadata.st_dev
    lock_descriptor = -1
    owner_descriptor = -1
    try:
        lock_metadata = stat_at(root, lock_name)
        if lock_metadata is None:
            die("owned lifecycle lock disappeared before release")
        validate_private_directory(lock_metadata, exact=True)
        if lock_metadata.st_dev != device or identity(lock_metadata) != expected_lock:
            die("owned lifecycle lock identity changed")
        lock_descriptor, opened_lock = open_directory_at(root, lock_name, device)
        if identity(opened_lock) != expected_lock:
            die("owned lifecycle lock was substituted")
        owner_metadata = stat_at(lock_descriptor, LOCK_OWNER)
        if owner_metadata is None:
            die("owned lifecycle lock owner record disappeared")
        validate_owner_record(owner_metadata, device)
        owner_descriptor = os.open(
            LOCK_OWNER, regular_file_flags(), dir_fd=lock_descriptor
        )
        opened_owner = os.fstat(owner_descriptor)
        validate_owner_record(opened_owner, device)
        if identity(opened_owner) != identity(owner_metadata):
            die("owned lifecycle lock owner record was substituted")
        record = os.read(owner_descriptor, 64)
        if os.read(owner_descriptor, 1) or record != f"{owner}\n".encode("ascii"):
            die("owned lifecycle lock owner record changed")
        os.close(owner_descriptor)
        owner_descriptor = -1
        if sorted(os.listdir(lock_descriptor)) != [LOCK_OWNER]:
            die("owned lifecycle lock contains unexpected entries")
        os.unlink(LOCK_OWNER, dir_fd=lock_descriptor)
        os.fsync(lock_descriptor)
        current = stat_at(root, lock_name)
        if current is None or identity(current) != expected_lock:
            die("owned lifecycle lock moved during release")
        os.close(lock_descriptor)
        lock_descriptor = -1
        os.rmdir(lock_name, dir_fd=root)
        os.fsync(root)
    finally:
        if owner_descriptor >= 0:
            os.close(owner_descriptor)
        if lock_descriptor >= 0:
            os.close(lock_descriptor)
        os.close(root)


def move(
    root_path: str,
    root_expected: str,
    source_value: str,
    target_value: str,
    expected: str,
) -> None:
    source = relative_parts(source_value)
    target = relative_parts(target_value)
    root, root_metadata = open_absolute_directory(
        root_path, expected_identity=root_expected, private=True
    )
    device = root_metadata.st_dev
    source_parent, source_name, source_metadata = open_source_directory(
        root, source, device, expected
    )
    source_directory, opened_source = open_directory_at(source_parent, source_name, device)
    if identity(opened_source) != identity(source_metadata):
        os.close(source_directory)
        os.close(source_parent)
        os.close(root)
        die("managed-host source changed before publication")
    sync_tree(source_directory, device)
    target_parent = descend(root, target[:-1], device, create=True)
    target_name = target[-1]
    if stat_at(target_parent, target_name) is not None:
        os.close(source_directory)
        os.close(target_parent)
        os.close(source_parent)
        os.close(root)
        die("managed-host destination already exists")
    rename_no_replace(source_parent, source_name, target_parent, target_name)
    moved = stat_at(target_parent, target_name)
    held_source = os.fstat(source_directory)
    if (
        moved is None
        or identity(moved) != identity(source_metadata)
        or identity(moved) != identity(held_source)
    ):
        die("managed-host rename did not preserve source identity")
    if stat_at(source_parent, source_name) is not None:
        die("managed-host source remained after rename")
    os.fsync(source_parent)
    os.fsync(target_parent)
    os.fsync(root)
    os.close(source_directory)
    print(identity(moved))
    os.close(target_parent)
    os.close(source_parent)
    os.close(root)


def quarantine(
    root_path: str,
    root_expected: str,
    source_value: str,
    parent_value: str,
    slot_value: str,
    expected: str,
) -> None:
    source = relative_parts(source_value)
    destination_parent_parts = relative_parts(parent_value)
    slot = parse_quarantine_id(slot_value)
    root, root_metadata = open_absolute_directory(
        root_path, expected_identity=root_expected, private=True
    )
    device = root_metadata.st_dev
    source_parent, source_name, source_metadata = open_source_directory(
        root, source, device, expected
    )
    destination_parent = descend(root, destination_parent_parts, device, create=True)
    slot_descriptor = -1
    try:
        os.mkdir(slot, 0o700, dir_fd=destination_parent)
    except FileExistsError:
        os.close(destination_parent)
        os.close(source_parent)
        os.close(root)
        die("quarantine destination already exists")
    slot_descriptor, slot_metadata = open_directory_at(destination_parent, slot, device)
    if stat.S_IMODE(slot_metadata.st_mode) != 0o700:
        die("quarantine slot has an unexpected mode")
    try:
        if stat_at(slot_descriptor, "generation") is not None:
            die("quarantine destination already exists")
        rename_no_replace(source_parent, source_name, slot_descriptor, "generation")
        moved = stat_at(slot_descriptor, "generation")
        if moved is None or identity(moved) != identity(source_metadata):
            die("quarantine rename did not preserve source identity")
        if stat_at(source_parent, source_name) is not None:
            die("managed-host source remained after quarantine rename")
        os.fsync(source_parent)
        os.fsync(slot_descriptor)
        os.fsync(destination_parent)
        os.fsync(root)
        print(f"{slot} {identity(moved)}")
    except BaseException:
        if stat_at(slot_descriptor, "generation") is None:
            os.close(slot_descriptor)
            slot_descriptor = -1
            try:
                os.rmdir(slot, dir_fd=destination_parent)
            except OSError:
                pass
        raise
    finally:
        if slot_descriptor >= 0:
            os.close(slot_descriptor)
        os.close(destination_parent)
        os.close(source_parent)
        os.close(root)


def clear_directory(directory: int, device: int) -> None:
    os.fchmod(directory, 0o700)
    for name in os.listdir(directory):
        safe_component(name)
        metadata = stat_at(directory, name)
        if metadata is None:
            continue
        if metadata.st_dev != device:
            die("cleanup encountered a nested filesystem")
        if stat.S_ISDIR(metadata.st_mode):
            child = os.open(name, descriptor_flags(), dir_fd=directory)
            opened = os.fstat(child)
            if identity(opened) != identity(metadata):
                os.close(child)
                die("cleanup directory was substituted")
            clear_directory(child, device)
            current = stat_at(directory, name)
            if current is None or identity(current) != identity(opened):
                os.close(child)
                die("cleanup directory moved during traversal")
            os.close(child)
            os.rmdir(name, dir_fd=directory)
        else:
            os.unlink(name, dir_fd=directory)
    os.fsync(directory)


def cleanup(parent_path: str, leaf: str, parent_expected: str, workspace_expected: str) -> None:
    safe_component(leaf)
    parent, parent_metadata = open_absolute_directory(
        parent_path, expected_identity=parent_expected
    )
    workspace_metadata = stat_at(parent, leaf)
    if workspace_metadata is None:
        os.close(parent)
        die("lifecycle workspace disappeared before cleanup")
    validate_private_directory(workspace_metadata, exact=True)
    if identity(workspace_metadata) != parse_identity(workspace_expected):
        os.close(parent)
        die("lifecycle workspace identity changed")
    workspace = os.open(leaf, descriptor_flags(), dir_fd=parent)
    opened = os.fstat(workspace)
    if identity(opened) != identity(workspace_metadata):
        os.close(workspace)
        os.close(parent)
        die("lifecycle workspace was substituted")
    clear_directory(workspace, opened.st_dev)
    current = stat_at(parent, leaf)
    if current is None or identity(current) != identity(opened):
        os.close(workspace)
        os.close(parent)
        die("lifecycle workspace moved during cleanup")
    os.close(workspace)
    os.rmdir(leaf, dir_fd=parent)
    os.fsync(parent)
    os.close(parent)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("quarantine-id")
    acquire_parser = subcommands.add_parser("lock-acquire")
    acquire_parser.add_argument("root")
    acquire_parser.add_argument("root_identity")
    acquire_parser.add_argument("lock")
    acquire_parser.add_argument("owner")
    release_parser = subcommands.add_parser("lock-release")
    release_parser.add_argument("root")
    release_parser.add_argument("root_identity")
    release_parser.add_argument("lock")
    release_parser.add_argument("lock_identity")
    release_parser.add_argument("owner")
    workspace_parser = subcommands.add_parser("workspace-create")
    workspace_parser.add_argument("parent")
    workspace_parser.add_argument("parent_identity")
    workspace_parser.add_argument("workspace_kind")
    move_parser = subcommands.add_parser("move")
    move_parser.add_argument("root")
    move_parser.add_argument("root_identity")
    move_parser.add_argument("source")
    move_parser.add_argument("target")
    move_parser.add_argument("source_identity")
    quarantine_parser = subcommands.add_parser("quarantine")
    quarantine_parser.add_argument("root")
    quarantine_parser.add_argument("root_identity")
    quarantine_parser.add_argument("source")
    quarantine_parser.add_argument("destination_parent")
    quarantine_parser.add_argument("slot")
    quarantine_parser.add_argument("source_identity")
    cleanup_parser = subcommands.add_parser("cleanup")
    cleanup_parser.add_argument("parent")
    cleanup_parser.add_argument("leaf")
    cleanup_parser.add_argument("parent_identity")
    cleanup_parser.add_argument("workspace_identity")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        if args.command == "quarantine-id":
            generate_quarantine_id()
        elif args.command == "lock-acquire":
            acquire_lock(args.root, args.root_identity, args.lock, args.owner)
        elif args.command == "lock-release":
            release_lock(
                args.root,
                args.root_identity,
                args.lock,
                args.lock_identity,
                args.owner,
            )
        elif args.command == "workspace-create":
            create_workspace(
                args.parent,
                args.parent_identity,
                args.workspace_kind,
            )
        elif args.command == "move":
            move(
                args.root,
                args.root_identity,
                args.source,
                args.target,
                args.source_identity,
            )
        elif args.command == "quarantine":
            quarantine(
                args.root,
                args.root_identity,
                args.source,
                args.destination_parent,
                args.slot,
                args.source_identity,
            )
        elif args.command == "cleanup":
            cleanup(
                args.parent,
                args.leaf,
                args.parent_identity,
                args.workspace_identity,
            )
        else:
            die("unsupported filesystem operation")
    except OSError as exc:
        die(exc.strerror or "operating-system filesystem call failed")


if __name__ == "__main__":
    main()

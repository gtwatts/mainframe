#!/usr/bin/env python3
"""Compute MAINFRAME's canonical SHA-256 identity for an installed package tree."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import stat
import sys
from typing import NoReturn


DOMAIN = b"MAINFRAME-PACKAGE-TREE-SHA256-V1\0"


def die(message: str) -> NoReturn:
    raise SystemExit(message)


def normalize_selections(root: pathlib.Path, values: list[str]) -> tuple[str, ...]:
    """Return minimal, validated POSIX-relative directory selections."""

    normalized: set[str] = set()
    for value in values:
        candidate = pathlib.PurePosixPath(value)
        if (
            not value
            or candidate.is_absolute()
            or value != candidate.as_posix()
            or any(part in ("", ".", "..") for part in candidate.parts)
        ):
            die(f"selection must be a canonical relative path: {value}")
        selected = root.joinpath(*candidate.parts)
        if selected.is_symlink() or not selected.is_dir():
            die(f"selected package tree must be a real directory: {value}")
        normalized.add(candidate.as_posix())

    # Selecting a parent already includes every descendant selection.
    minimal = {
        value
        for value in normalized
        if not any(value.startswith(other + "/") for other in normalized if other != value)
    }
    return tuple(sorted(minimal))


def selection_includes(relative: str, selections: tuple[str, ...]) -> bool:
    if not selections:
        return True
    return any(
        relative == selected
        or relative.startswith(selected + "/")
        or selected.startswith(relative + "/")
        for selected in selections
    )


def collect_entries(
    root: pathlib.Path, selections: tuple[str, ...]
) -> list[tuple[str, pathlib.Path, int, int]]:
    entries: list[tuple[str, pathlib.Path, int, int]] = []
    for current, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False
    ):
        directory_names.sort()
        file_names.sort()
        current_path = pathlib.Path(current)
        current_relative = current_path.relative_to(root).as_posix()
        if current_relative == ".":
            current_relative = ""
        directory_names[:] = [
            name
            for name in directory_names
            if selection_includes(
                f"{current_relative}/{name}" if current_relative else name,
                selections,
            )
        ]
        file_names = [
            name
            for name in file_names
            if selection_includes(
                f"{current_relative}/{name}" if current_relative else name,
                selections,
            )
        ]
        for name in directory_names + file_names:
            path = current_path / name
            metadata = path.lstat()
            relative = path.relative_to(root).as_posix()
            if stat.S_ISLNK(metadata.st_mode):
                die(f"package tree contains a symbolic link: {relative}")
            if not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
                die(f"package tree contains an unsupported entry: {relative}")
            entries.append((relative, path, metadata.st_mode, metadata.st_size))
    return entries


def hash_entries(entries: list[tuple[str, pathlib.Path, int, int]]) -> str:
    """Hash the canonical typed path inventory and every regular-file byte."""

    digest = hashlib.sha256(DOMAIN)
    for relative, path, mode, _observed_size in sorted(entries):
        encoded_path = relative.encode("utf-8")
        if b"\0" in encoded_path:
            die(f"package tree path contains NUL: {relative}")
        if stat.S_ISDIR(mode):
            digest.update(b"D\0" + encoded_path + b"\0")
            continue

        size = path.stat().st_size
        digest.update(b"F\0" + encoded_path + b"\0")
        digest.update(str(size).encode("ascii") + b"\0")
        bytes_read = 0
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                bytes_read += len(chunk)
                digest.update(chunk)
        if bytes_read != size:
            die(
                "package tree file is dataless, truncated, or changed while "
                f"hashing: {relative} (stat size {size}, bytes read {bytes_read})"
            )

    return digest.hexdigest()


def print_inventory(entries: list[tuple[str, pathlib.Path, int, int]]) -> None:
    """Emit an injection-safe inventory without reading file contents."""

    print("selected installed-tree inventory (D=directory, F=regular file):", file=sys.stderr)
    for relative, _path, mode, observed_size in sorted(entries):
        encoded_relative = json.dumps(relative, ensure_ascii=True)
        if stat.S_ISDIR(mode):
            print(f"  D {encoded_relative}", file=sys.stderr)
        else:
            print(f"  F {encoded_relative} size={observed_size}", file=sys.stderr)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute MAINFRAME's canonical installed package-tree identity."
    )
    parser.add_argument(
        "--expected",
        metavar="SHA256",
        help="fail with installed-tree diagnostics unless the digest matches SHA256",
    )
    parser.add_argument(
        "--installed-label",
        metavar="LABEL",
        help="host/package label used by --expected diagnostics",
    )
    parser.add_argument("package_directory", metavar="PACKAGE_DIRECTORY")
    parser.add_argument(
        "selections",
        metavar="SELECTED_RELATIVE_DIRECTORY",
        nargs="*",
    )
    arguments = parser.parse_args()
    if (arguments.expected is None) != (arguments.installed_label is None):
        parser.error("--expected and --installed-label must be supplied together")
    if arguments.expected is not None and not re.fullmatch(
        r"[0-9a-f]{64}", arguments.expected
    ):
        parser.error("--expected must be a lowercase SHA-256 digest")
    if arguments.installed_label is not None and not re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9._+ -]{0,79}", arguments.installed_label
    ):
        parser.error("--installed-label contains unsafe characters")
    return arguments


def main() -> None:
    arguments = parse_arguments()
    entries: list[tuple[str, pathlib.Path, int, int]] = []
    try:
        root = pathlib.Path(arguments.package_directory)
        if root.is_symlink() or not root.is_dir():
            die(f"package tree must be a real directory: {root}")
        root = root.resolve(strict=True)
        selections = normalize_selections(root, arguments.selections)
        entries = collect_entries(root, selections)
        digest = hash_entries(entries)
    except SystemExit as error:
        if arguments.expected is None:
            raise
        print(
            f"ERROR: installed {arguments.installed_label} tree could not be hashed; "
            "installed-tree contamination or incomplete package data",
            file=sys.stderr,
        )
        if str(error):
            encoded_error = json.dumps(str(error), ensure_ascii=True)
            print(f"tree-hash error: {encoded_error}", file=sys.stderr)
        if entries:
            print_inventory(entries)
        raise SystemExit(1) from None

    if arguments.expected is not None and digest != arguments.expected:
        print(
            f"ERROR: installed {arguments.installed_label} tree does not match host "
            "manifest; installed-tree contamination or incomplete package data",
            file=sys.stderr,
        )
        print(f"expected selected-tree SHA-256: {arguments.expected}", file=sys.stderr)
        print(f"actual selected-tree SHA-256:   {digest}", file=sys.stderr)
        print_inventory(entries)
        raise SystemExit(1)

    print(digest)


if __name__ == "__main__":
    main()

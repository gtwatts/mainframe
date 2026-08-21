#!/usr/bin/env python3
"""Capture the public Bash project-memory boundary without executing AWM."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys


def main() -> int:
    state = Path(os.environ["XDG_STATE_HOME"])
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    raw_input = sys.stdin.buffer.read(32769)
    if len(raw_input) > 32768:
        return 2
    capture = {
        "argv": sys.argv[1:],
        "stdin_utf8": raw_input.decode("utf-8"),
        "environment_keys": sorted(os.environ),
        "cwd": os.path.realpath(os.getcwd()),
    }
    (state / "project-memory-capture.json").write_text(
        json.dumps(capture, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    sys.stdout.write("0123456789ab\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

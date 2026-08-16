#!/usr/bin/env python3
"""Hidden grader for the credentials-free protocol conformance task."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    workspace = Path(sys.argv[1])
    source = workspace / "capacity.py"
    if not source.is_file() or source.is_symlink():
        print(json.dumps({"score": 0, "maximum_score": 100, "solved": False,
                          "tests_passed": 0, "tests_total": 3}, sort_keys=True))
        return 0
    spec = importlib.util.spec_from_file_location("capacity_fixture", source)
    if spec is None or spec.loader is None:
        return 2
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
        cases = [(10, 3, 7), (7, 0, 7), (9, 9, 0)]
        passed = sum(module.remaining_capacity(total, used) == expected
                     for total, used, expected in cases)
    except Exception:
        passed = 0
    solved = passed == 3
    print(json.dumps({
        "score": 100 if solved else 0,
        "maximum_score": 100,
        "solved": solved,
        "tests_passed": passed,
        "tests_total": 3,
    }, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

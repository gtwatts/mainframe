#!/usr/bin/env python3
"""Hidden deterministic grader for the local development smoke task."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        return 64
    source = Path(sys.argv[1]) / "config_merge.py"
    spec = importlib.util.spec_from_file_location("candidate_config_merge", source)
    if spec is None or spec.loader is None:
        return 65
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    cases = [
        (
            {"feature": True, "retries": 3, "label": "default"},
            {"feature": False, "retries": 0, "label": ""},
            {},
            {"feature": False, "retries": 0, "label": ""},
        ),
        (
            {"service": {"host": "localhost", "tls": True, "port": 443}},
            {"service": {"tls": False, "port": 0}},
            {"service": {"host": "example.test"}},
            {"service": {"host": "example.test", "tls": False, "port": 0}},
        ),
        (
            {"a": {"b": {"enabled": True, "count": 2}}, "untouched": [1]},
            {"a": {"b": {"enabled": False}}},
            {"a": {"b": {"count": 0}}},
            {"a": {"b": {"enabled": False, "count": 0}}, "untouched": [1]},
        ),
        (
            {"items": ["default"], "nullable": "value"},
            {"items": [], "nullable": None},
            {},
            {"items": [], "nullable": None},
        ),
    ]
    passed = 0
    for defaults, project, user, expected in cases:
        actual = module.resolve_config(defaults, project, user)
        if actual == expected:
            passed += 1
    score = passed * 25
    print(json.dumps({
        "score": score,
        "maximum_score": 100,
        "solved": score == 100,
        "tests_passed": passed,
        "tests_total": len(cases),
    }, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

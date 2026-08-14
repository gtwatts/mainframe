#!/usr/bin/env python3
"""Deterministic fake runner for Agent Impact Protocol conformance tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Optional


def write_result(path: Path, *, status: str, handoff: Optional[str]) -> None:
    usage_reason = "fixture-runner-does-not-report-provider-usage"
    result = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-runner-result",
        "status": status,
        "handoff_relative_path": handoff,
        "usage": {
            "input_tokens": None,
            "input_tokens_reason": usage_reason,
            "output_tokens": None,
            "output_tokens_reason": usage_reason,
        },
        "tool_calls": 1,
        "ambient_probe_seen": "MAINFRAME_SHOULD_NOT_LEAK" in os.environ,
    }
    path.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n",
                    encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        return 64
    request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    behavior = os.environ.get("MAINFRAME_EVAL_FIXTURE_BEHAVIOR", "normal")
    if behavior == "timeout":
        time.sleep(10)
        return 70
    if behavior == "child-survival":
        marker = os.environ["MAINFRAME_EVAL_CHILD_MARKER"]
        workspace = request["workspace"]
        child_code = (
            "import pathlib,signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "time.sleep(0.5); "
            "pathlib.Path({!r}).write_text('survived'); "
            "pathlib.Path({!r}).write_text('mutated')"
        ).format(marker, str(Path(workspace) / "capacity.py"))
        subprocess.Popen([sys.executable, "-c", child_code])
        time.sleep(10)
        return 70
    if behavior == "orphan-on-success":
        marker = os.environ["MAINFRAME_EVAL_CHILD_MARKER"]
        workspace = request["workspace"]
        child_code = (
            "import pathlib,signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "time.sleep(0.5); "
            "pathlib.Path({!r}).write_text('survived'); "
            "pathlib.Path({!r}).write_text('mutated')"
        ).format(marker, str(Path(workspace) / "capacity.py"))
        subprocess.Popen([sys.executable, "-c", child_code])
        time.sleep(0.05)
    if behavior == "infrastructure-failure":
        return 70

    artifact_dir = Path(request["artifact_dir"])
    result_path = Path(request["result_path"])
    workspace = Path(request["workspace"])
    artifact_dir.mkdir(parents=True, exist_ok=True)

    if behavior == "agent-failure":
        write_result(result_path, status="agent_failure", handoff=None)
        return 0

    if request["phase"] == "investigate":
        handoff = artifact_dir / "handoff.txt"
        if request["arm_mode"] == "treatment":
            handoff.write_text("The defect adds used capacity; subtract used from total.\n",
                               encoding="utf-8")
        else:
            handoff.write_text("The capacity calculation needs further investigation.\n",
                               encoding="utf-8")
        write_result(result_path, status="completed", handoff="handoff.txt")
        return 0

    context_path = Path(request["context_path"])
    context = context_path.read_text(encoding="utf-8")
    if request["arm_mode"] == "treatment" and "subtract used" in context:
        source = workspace / "capacity.py"
        source.write_text(
            '"""Capacity arithmetic used by the protocol conformance fixture."""\n\n\n'
            'def remaining_capacity(total: int, used: int) -> int:\n'
            '    """Return capacity that has not yet been used."""\n\n'
            '    return total - used\n',
            encoding="utf-8",
        )
    write_result(result_path, status="completed", handoff=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

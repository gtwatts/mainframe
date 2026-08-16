#!/usr/bin/env python3
"""Deterministic, credentials-free transport for local-smoke conformance.

This executable is not a model, provider, or Pi session. It deliberately cannot
see the committed mechanism assignment and performs identical work for every
opaque arm.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time


ALLOWED_ENVIRONMENT_NAMES = sorted([
    "CI", "HOME", "LANG", "LC_ALL", "LOGNAME", "MAINFRAME_LOCAL_PROTOCOL",
    "NO_COLOR", "PATH", "PYTHONDONTWRITEBYTECODE", "TMPDIR", "USER",
    "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "__CF_USER_TEXT_ENCODING",
])
FORBIDDEN_KEYS = {"arm_mode", "mechanism"}
FORBIDDEN_STRING_VALUES = {"control", "treatment"}


def atomic_json(path: Path, value: object) -> None:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False, allow_nan=False).encode("utf-8") + b"\n"
    descriptor = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())


def reject_assignment_leak(value: object) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = str(key).lower()
            if lowered in FORBIDDEN_KEYS:
                raise ValueError("adapter request leaked a mechanism assignment")
            reject_assignment_leak(child)
    elif isinstance(value, list):
        for child in value:
            reject_assignment_leak(child)
    elif isinstance(value, str):
        lowered = value.lower()
        if lowered in FORBIDDEN_STRING_VALUES:
            raise ValueError("adapter request leaked a mechanism assignment")


def write_result(request: dict, *, continuation: str | None) -> None:
    result = {
        "schema_version": 1,
        "kind": "mainframe-agent-impact-local-runner-result",
        "status": "completed",
        "continuation_relative_path": continuation,
        "usage": {
            "input_tokens": None,
            "input_tokens_reason": "deterministic-fake-transport-no-provider-usage",
            "output_tokens": None,
            "output_tokens_reason": "deterministic-fake-transport-no-provider-usage",
        },
        "tool_calls": 1,
        "observed_environment_names": sorted(os.environ),
        "provider_requests": 0,
        "pi_sessions": 0,
        "network_requests": 0,
    }
    atomic_json(Path(request["result_path"]), result)


def main() -> int:
    if len(sys.argv) not in (2, 4):
        return 64
    request_path = Path(sys.argv[1])
    request = json.loads(request_path.read_text(encoding="utf-8"))
    reject_assignment_leak(request)
    if sorted(os.environ) != ALLOWED_ENVIRONMENT_NAMES:
        return 65

    behavior = "normal"
    marker: Path | None = None
    if len(sys.argv) == 4:
        behavior = sys.argv[2]
        marker = Path(sys.argv[3])
        if behavior != "orphan-on-success" or not marker.is_absolute():
            return 64

    workspace = Path(request["workspace"])
    artifact_dir = Path(request["artifact_dir"])
    artifact_dir.mkdir(mode=0o700)

    if behavior == "orphan-on-success":
        assert marker is not None
        mutation = workspace / "config_merge.py"
        # The harness wins only if its SIGTERM grace (0.15s) plus SIGKILL lands
        # before this child wakes. Keep the delayed write far beyond that kill
        # window so loaded CI runners (observed: macOS matrix stalls >0.3s)
        # cannot flip the race. tests/agent_impact_local.bats observes only
        # after this delay, so the marker and mutation assertions stay live.
        code = (
            "import pathlib,signal,time;"
            "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
            "time.sleep(2);"
            "pathlib.Path({!r}).write_text('survived',encoding='utf-8');"
            "pathlib.Path({!r}).write_text('mutated',encoding='utf-8')"
        ).format(str(marker), str(mutation))
        subprocess.Popen([sys.executable, "-c", code])
        time.sleep(0.05)

    if request["phase"] == "investigate":
        continuation = artifact_dir / "agent-continuation.txt"
        descriptor = os.open(str(continuation), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(
                "Merge dictionaries recursively. Apply defaults, project, then user; "
                "presence, not truthiness, controls precedence so False, 0, empty "
                "strings, empty lists, and None remain valid overrides.\n"
            )
        write_result(request, continuation="agent-continuation.txt")
        return 0

    context = Path(request["context_path"]).read_text(encoding="utf-8")
    if "presence, not truthiness" not in context:
        return 66
    source = workspace / "config_merge.py"
    source.write_text(
        '"""Nested configuration merge used by the local development smoke."""\n\n\n'
        "def _merge(base: dict, overlay: dict) -> dict:\n"
        "    result = dict(base)\n"
        "    for key, value in overlay.items():\n"
        "        if isinstance(value, dict) and isinstance(result.get(key), dict):\n"
        "            result[key] = _merge(result[key], value)\n"
        "        else:\n"
        "            result[key] = value\n"
        "    return result\n\n\n"
        "def resolve_config(defaults: dict, project: dict, user: dict) -> dict:\n"
        "    return _merge(_merge(defaults, project), user)\n",
        encoding="utf-8",
    )
    write_result(request, continuation=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

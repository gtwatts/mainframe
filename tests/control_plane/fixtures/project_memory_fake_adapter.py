#!/usr/bin/python3 -I
"""Copied-layout fixed adapter fixture; never a production entry point."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


TOOLS = {
    "mainframe.project_memory.ensure.v1": "session_ensure",
    "mainframe.project_memory.checkpoint.v1": "checkpoint",
    "mainframe.project_memory.discovery.v1": "discovery",
    "mainframe.project_memory.progress.v1": "progress",
    "mainframe.project_memory.close.v1": "session_close",
    "mainframe.project_memory.handoff.v1": "handoff",
    "mainframe.project_memory.session.v1": "project_session",
    "mainframe.project_memory.status.v1": "project_status",
    "mainframe.project_memory.get.v1": "project_get",
    "mainframe.project_memory.summary.v1": "project_summary",
    "mainframe.project_memory.context.v1": "project_context",
    "mainframe.project_memory.find.v1": "project_find",
}

READ_TOOLS = {
    "mainframe.project_memory.session.v1",
    "mainframe.project_memory.status.v1",
    "mainframe.project_memory.get.v1",
    "mainframe.project_memory.summary.v1",
    "mainframe.project_memory.context.v1",
    "mainframe.project_memory.find.v1",
}


def canonical(value):
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def digest(value):
    return hashlib.sha256(value).hexdigest()


def read_fd(fd, limit):
    chunks = []
    total = 0
    while True:
        chunk = os.read(fd, min(65536, limit + 1 - total))
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise RuntimeError("fixture descriptor overflow")
        chunks.append(chunk)
    os.close(fd)
    return b"".join(chunks)


def state_digest(project_digest, state):
    if state is None:
        return "0" * 64
    return digest(
        canonical(
            {
                "closed": state["closed"],
                "project_digest": project_digest,
                "session_id": state["session_id"],
                "version": state["version"],
            }
        )
    )


def state_paths():
    root = Path(os.environ["XDG_STATE_HOME"])
    return root, root / "fixture-map.json", root / "fixture-map.lock"


def load_state(path):
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("invalid fixture state")
    return value


def write_state(path, value):
    path.write_bytes(canonical(value) + b"\n")


def observation(project_digest, current):
    if current is None:
        return {
            "schema_version": 1,
            "project_digest": project_digest,
            "mapping_state": "absent",
            "session_id": None,
            "state_digest": "0" * 64,
        }
    return {
        "schema_version": 1,
        "project_digest": project_digest,
        "mapping_state": "closed" if current["closed"] else "active",
        "session_id": current["session_id"],
        "state_digest": state_digest(project_digest, current),
    }


def observe():
    project_digest = digest(os.path.realpath(os.getcwd()).encode("utf-8"))
    root, state_path, lock_path = state_paths()
    count_path = root / "fixture-observe-count"
    with open(lock_path, "a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        states = load_state(state_path)
        count = int(count_path.read_text(encoding="ascii")) if count_path.exists() else 0
        count_path.write_text(str(count + 1), encoding="ascii")
        result = observation(project_digest, states.get(project_digest))
    sys.stdout.buffer.write(canonical(result) + b"\n")
    return 0


def guardian():
    try:
        while os.read(198, 4096):
            pass
    except OSError:
        pass
    try:
        os.killpg(os.getpgrp(), signal.SIGKILL)
    except ProcessLookupError:
        pass


def execute(tool):
    expected_identity_keys = {
        "schema_version",
        "memory_op_id",
        "memory_id",
        "handoff_id",
        "run_id",
        "call_id",
        "decision_id",
        "evidence_id",
        "tool",
        "input_digest",
        "actor",
        "workspace",
        "policy",
        "project_digest",
        "observation",
        "retention_class",
        "expires_at",
        "timeout_at",
    }
    identity = json.loads(read_fd(197, 16384).decode("utf-8"))
    if set(identity) != expected_identity_keys or identity["tool"] != tool:
        return 64
    watcher = threading.Thread(target=guardian, daemon=True)
    watcher.start()
    tool_input = json.loads(sys.stdin.buffer.read(32769).decode("utf-8"))
    if not isinstance(tool_input, dict):
        return 64
    root, state_path, lock_path = state_paths()
    (root / "fixture-worker-pid").write_text(str(os.getppid()), encoding="ascii")
    project = identity["project_digest"]
    with open(lock_path, "a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        count_path = root / "fixture-execute-count"
        count = int(count_path.read_text(encoding="ascii")) if count_path.exists() else 0
        count_path.write_text(str(count + 1), encoding="ascii")
        states = load_state(state_path)
        current = states.get(project)
        before = state_digest(project, current)
        observed = identity["observation"]
        exact_observed = observation(project, current)
        exact_observed.pop("schema_version")
        recovery = observed != exact_observed
        expected = tool_input.get("expected_session_id")
        is_read = tool in READ_TOOLS
        if tool == "mainframe.project_memory.ensure.v1":
            if current is None and not recovery:
                current = {
                    "session_id": digest(project.encode("ascii"))[:12],
                    "closed": False,
                    "version": 1,
                }
                states[project] = current
            elif current is not None and current["closed"]:
                recovery = True
        elif is_read:
            if current is None:
                recovery = True
        elif (
            current is None
            or current["closed"]
            or current["session_id"] != expected
        ):
            recovery = True
        if (
            not recovery
            and not is_read
            and tool != "mainframe.project_memory.ensure.v1"
        ):
            current["version"] += 1
            if tool == "mainframe.project_memory.close.v1":
                current["closed"] = True
        if not recovery:
            write_state(state_path, states)
        session_id = expected if current is None else current["session_id"]
        after = state_digest(project, current)

    key = None
    recipient = None
    raw_value = b""
    transient = b""
    if tool == "mainframe.project_memory.checkpoint.v1":
        key = tool_input["key"]
        raw_value = tool_input["value"].encode("utf-8")
    elif tool == "mainframe.project_memory.discovery.v1":
        raw_value = tool_input["value"].encode("utf-8")
    elif tool == "mainframe.project_memory.progress.v1":
        key = tool_input["task"]
        raw_value = canonical(
            {
                "current": tool_input["current"],
                "status": tool_input["status"],
                "total": tool_input["total"],
            }
        )
    elif tool == "mainframe.project_memory.handoff.v1":
        recipient = tool_input["target"]
        transient = canonical(
            {
                "format": tool_input["render_format"],
                "max_tokens": tool_input["max_tokens"],
                "session_id": session_id,
                "target": recipient,
            }
        )
        raw_value = transient
    elif tool == "mainframe.project_memory.session.v1":
        transient = ((session_id or "") + "\n").encode("ascii")
        raw_value = transient
    elif tool == "mainframe.project_memory.status.v1":
        transient = canonical(
            {
                "session_id": session_id,
                "status": "closed" if current and current["closed"] else "active",
            }
        )
        raw_value = transient
    elif tool == "mainframe.project_memory.get.v1":
        key = tool_input["key"]
        transient = tool_input["default"].encode("utf-8")
        raw_value = transient
    elif tool == "mainframe.project_memory.summary.v1":
        transient = canonical(
            {"max_tokens": tool_input["max_tokens"], "session_id": session_id}
        )
        raw_value = transient
    elif tool == "mainframe.project_memory.context.v1":
        key = tool_input["task"]
        transient = canonical(
            {
                "format": tool_input["render_format"],
                "include": tool_input["include"],
                "max_tokens": tool_input["max_tokens"],
                "session_id": session_id,
                "task": tool_input["task"],
            }
        )
        raw_value = transient
    elif tool == "mainframe.project_memory.find.v1":
        key = tool_input["query"]
        transient = canonical(
            [
                {
                    "kind": tool_input["kind"],
                    "limit": tool_input["limit"],
                    "preview": tool_input["query"],
                    "session_id": session_id,
                }
            ]
        )
        raw_value = transient
    outcome = "recovery_required" if recovery else "succeeded"
    if outcome != "succeeded" and is_read:
        transient = b""
        raw_value = b""
    receipt = {
        "schema_version": 1,
        "memory_op_id": identity["memory_op_id"],
        "memory_id": identity["memory_id"],
        "handoff_id": identity["handoff_id"],
        "run_id": identity["run_id"],
        "call_id": identity["call_id"],
        "decision_id": identity["decision_id"],
        "evidence_id": identity["evidence_id"],
        "tool": tool,
        "input_digest": identity["input_digest"],
        "actor": identity["actor"],
        "workspace": identity["workspace"],
        "policy": identity["policy"],
        "project_digest": project,
        "expected_session_id": expected,
        "session_id": session_id,
        "outcome": outcome,
        "idempotency_key": identity["memory_op_id"],
        "record_type": TOOLS[tool],
        "key_sha256": None if key is None else digest(key.encode("utf-8")),
        "value_sha256": digest(raw_value),
        "value_bytes": len(raw_value),
        "recipient_sha256": None
        if recipient is None
        else digest(recipient.encode("utf-8")),
        "retention_class": identity["retention_class"],
        "expires_at": identity["expires_at"],
        "state_digest_before": before,
        "state_digest_after": after,
        "observed_mapping_state": observed["mapping_state"],
        "observed_session_id": observed["session_id"],
        "observed_state_digest": observed["state_digest"],
        "trust_label": "kernel_bound",
        "authoritative": False,
    }
    if tool_input.get("key") == "tamper-receipt":
        receipt["value_sha256"] = "f" * 64
    if tool_input.get("key") == "tamper-transient":
        transient = b"forged-transient"
    if recipient == "hold-for-worker-kill":
        child = subprocess.Popen(
            ["/usr/bin/python3", "-I", "-c", "import time; time.sleep(60)"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        (root / "fixture-adapter-pid").write_text(str(os.getpid()), encoding="ascii")
        (root / "fixture-child-pid").write_text(str(child.pid), encoding="ascii")
        time.sleep(60)
    if transient:
        offset = 0
        while offset < len(transient):
            offset += os.write(196, transient[offset:])
    os.close(196)
    outer = {
        "schema_version": 1,
        "outcome": outcome,
        "receipt": receipt,
        "error_code": "recovery_required" if recovery else None,
        "transient_bytes": len(transient),
        "transient_sha256": digest(transient),
    }
    sys.stdout.buffer.write(canonical(outer) + b"\n")
    return 0


def main():
    observer = [
        "__kernel-project-memory-observer-v1",
        "--format",
        "project-memory-observation-json-v1",
        "--caller",
        "control-plane",
    ]
    if sys.argv[1:] == observer:
        return observe()
    if len(sys.argv) != 9:
        return 64
    if (
        sys.argv[1] != "__kernel-project-memory-executor-v1"
        or sys.argv[2] not in TOOLS
        or sys.argv[3:]
        != [
            "--input-json",
            "-",
            "--format",
            "project-memory-executor-json-v1",
            "--caller",
            "control-plane",
        ]
    ):
        return 64
    for fd in (196, 197, 198):
        try:
            os.fstat(fd)
        except OSError:
            return 64
    return execute(sys.argv[2])


if __name__ == "__main__":
    raise SystemExit(main())

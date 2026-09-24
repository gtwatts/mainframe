#!/usr/bin/env python3
"""Exercise an installed durable core with disposable state, without Pi settings.

This is a local integration/stress check, not a release receipt generator. Every
process uses a temporary ledger in a private HOME/XDG state directory.
"""

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import hashlib
import importlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import traceback


def require(condition, message):
    if not condition:
        raise AssertionError(message)


class InstalledChecks:
    def __init__(self, release, workspace, workers):
        self.release = release
        self.root = workspace
        self.workers = workers
        self.project = workspace / "project"
        self.state = workspace / "state"
        self.home = workspace / "home"
        for directory in (self.project, self.state, self.home):
            directory.mkdir(mode=0o700)
        ledger_parent = self.state / "mainframe"
        ledger_parent.mkdir(mode=0o700)
        self.ledger = ledger_parent / "control-plane.jsonl"
        self.cli = release / "control_plane/mainframe-control-plane"
        self.environment = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.state), "TMPDIR": str(workspace),
            "LC_ALL": "C", "NO_COLOR": "1",
        }
        self.invocations = 0
        self.sequence = 0

    def invoke(self, tool, body, correlation, *, memory=False, expect=True):
        command = [str(self.cli)]
        if not memory:
            command += ["--ledger", str(self.ledger)]
        command += ["project-memory-invoke" if memory else "canonical-invoke",
                   "--tool-id" if memory else "--canonical-id", tool,
                   "--input-json", "-", "--client-correlation-id", correlation]
        completed = subprocess.run(command, input=json.dumps(body, ensure_ascii=False),
                                   text=True, capture_output=True, cwd=self.project,
                                   env=self.environment, timeout=45)
        self.invocations += 1
        require(not completed.stderr, "unexpected CLI stderr: " + completed.stderr[:1000])
        parsed = json.loads(completed.stdout)
        if expect:
            require(completed.returncode == 0 and parsed.get("ok"),
                    "CLI rejected valid input: " + completed.stdout[:1000])
        return parsed

    def memory(self, action, body, correlation, *, expect=True):
        return self.invoke("mainframe.project_memory." + action + ".v1", body,
                           correlation, memory=True, expect=expect)

    def ensure(self):
        result = self.memory("ensure", {}, "ensure")["result"]
        require(result["outcome"] == "succeeded", str(result))
        return result["session_id"]

    def checkpoint(self, sid, key, value, ttl=0):
        return dict(expected_session_id=sid, key=key, value=value,
                    importance="normal", tags=["local-stress"], ttl_seconds=ttl)

    def snapshot(self):
        kernel = importlib.import_module("mainframe_control_plane").ControlPlaneKernel
        return kernel(self.ledger).snapshot()

    def registry_all_contracts_and_negatives(self):
        index = json.loads((self.release / "INVOCATION_INDEX.json").read_text())
        cases = {
            "json_array": {"items": ["a", "quote\"", "line\n", "雪"]},
            "json_escape": {"str": "quote\"\\\n雪"},
            "json_get": {"json": '{"a":"answer"}', "key": "a"},
            "json_merge": {"objects": ['{"a":1}', '{"b":2}']},
            "json_object": {"pairs": ["key=value", "count:number=2", "active:bool=true"]},
            "json_string": {"value": "unicode 雪\n"},
            "json_valid": {"json": '{"valid":true}'},
            "array_contains": {"needle": "b", "items": ["a", "b"]},
            "array_join": {"delimiter": "|", "items": ["a", "b"]},
            "is_numeric": {"value": "42"},
            "output_json": {"json": '{"a":1}'},
            "output_success": {"data": '{"a":1}', "hint": "verified"},
            "usop_error_validation": {"field": "x", "value": "bad", "expected": "integer"},
            "path_sanitize": {"name": " unsafe:file?.txt "},
            "is_empty": {"value": ""},
            "to_lower": {"value": "HELLO"}, "to_upper": {"value": "hello"},
            "trim_left": {"value": "  value"}, "trim_right": {"value": "value  "},
            "validate_email": {"email": "person@example.com"},
            "validate_int": {"value": "42", "min": "0", "max": "100"},
            "validate_json": {"json": '{"a":1}'},
            "validate_path": {"path": str(self.project), "type": "dir"},
            "validate_regex": {"value": "abc", "pattern": "^[a-z]+$"},
            "validate_semver": {"version": "1.2.3"},
            "validate_url": {"url": "https://example.com"},
        }
        require(set(cases) == set(index["name_index"]), "test does not cover exact installed registry")
        expected_json = {
            "json_array": ["a", "quote\"", "line\n", "雪"],
            "json_merge": {"a": 1, "b": 2},
            "json_object": {"key": "value", "count": 2, "active": True},
            "json_string": "unicode 雪\n", "output_json": {"a": 1},
            "output_success": {"ok": True, "data": '{"a":1}', "hint": "verified"},
            "usop_error_validation": {"success": False, "error": "validation failed", "field": "x",
                                      "value": "bad", "expected": "integer",
                                      "suggestion": "Provide a value matching the expected format"},
        }
        expected_text = {
            "json_escape": 'quote\\"\\\\\\n雪', "json_get": "answer", "array_join": "a|b\n",
            "path_sanitize": "unsafe_file_.txt\n", "to_lower": "hello\n", "to_upper": "HELLO\n",
            "trim_left": "value\n", "trim_right": "value\n",
        }
        predicates = set(cases) - set(expected_json) - set(expected_text)
        def check_envelope(name, result, exit_code):
            envelope = result["broker_envelope"]
            require(envelope["exit_code"] == exit_code, name + " returned wrong exit code: " + str(envelope))
            require(not envelope["timed_out"] and not envelope["output_exceeded"], name + " exceeded execution bound")
            require(base64.b64decode(envelope["stderr_b64"], validate=True) == b"", name + " emitted stderr")
            return base64.b64decode(envelope["stdout_b64"], validate=True).decode()
        for name, body in cases.items():
            result = self.invoke(index["name_index"][name], body, "registry-" + name)["result"]
            require(result["outcome"] == "succeeded", name + ": " + str(result))
            require(result["result_available"], name + " omitted its first transient result")
            output = check_envelope(name, result, 0)
            if name in expected_json:
                require(json.loads(output) == expected_json[name], name + " semantic mismatch: " + repr(output))
            else:
                require(output == expected_text.get(name, ""), name + " byte mismatch: " + repr(output))
        false_predicates = {
            "array_contains": {"needle": "missing", "items": ["a", "b"]},
            "is_numeric": {"value": "4.2"}, "is_empty": {"value": "not-empty"},
            "json_valid": {"json": "{"}, "validate_json": {"json": "{"},
            "validate_email": {"email": "missing-at.example"},
            "validate_int": {"value": "101", "min": "0", "max": "100"},
            "validate_path": {"path": str(self.project / "missing"), "type": "file"},
            "validate_regex": {"value": "123", "pattern": "^[a-z]+$"},
            "validate_semver": {"version": "not-a-version"},
            "validate_url": {"url": "ftp://example.com"},
        }
        require(set(false_predicates) == predicates, "each predicate needs both truth values")
        for name, body in false_predicates.items():
            result = self.invoke(index["name_index"][name], body, "predicate-false-" + name)["result"]
            require(result["outcome"] == "failed", name + " false predicate was reported successful")
            require(result["result_available"], name + " false predicate omitted exit result")
            require(check_envelope(name, result, 1) == "", name + " false predicate emitted stdout")
        for number, (tool, body) in enumerate([
            ("to_upper", {"value": "x"}),
            ("mf:std:pure-string:to_upper", {"value": "x", "command": "echo forbidden"}),
            ("mf:std:pure-string:to_upper", {"value": 42}),
            ("mf:std:pure-string:to_upper", {"value": "nul\x00byte"}),
            ("mf:std:validation:validate_path", {"path": str(self.project), "type": "device"}),
        ]):
            before = self.ledger.read_bytes()
            result = self.invoke(tool, body, "invalid-" + str(number), expect=False)
            require(not result.get("ok"), "invalid registry call was accepted")
            require(self.ledger.read_bytes() == before, "invalid schema mutated the ledger")
        return {"contracts_semantically_verified": len(cases), "false_predicates": len(false_predicates), "schema_rejections": 5}

    def concurrent_same_request(self):
        sid = self.ensure()
        body = self.checkpoint(sid, "same-request", "exactly-once\n\n")
        with ThreadPoolExecutor(max_workers=self.workers) as pool:
            results = list(pool.map(lambda _: self.memory("checkpoint", body, "same-checkpoint")["result"],
                                    range(self.workers)))
        # The public CLI may return in_progress while another process owns this
        # correlation. Require exactly one durable operation and a terminal
        # replay, rather than pretending every caller waited synchronously.
        require(all(item["status"] in ("in_progress", "completed") for item in results), str(results))
        settled = self.memory("checkpoint", body, "same-checkpoint")["result"]
        require(settled["outcome"] == "succeeded", str(settled))
        results.append(settled)
        require(len({item["call_id"] for item in results}) == 1, "same correlation generated duplicate calls")
        snapshot = self.snapshot()
        call_id = results[0]["call_id"]
        require(sum(item.call_id == call_id for item in snapshot.evidence.values()) == 1, "duplicate evidence")
        require(sum(item.call_id == call_id for item in snapshot.memory_records.values()) == 1, "duplicate memory aggregate")
        journal = next(self.root.rglob("checkpoints.jsonl"))
        entries = [json.loads(line) for line in journal.read_text().splitlines()]
        require(sum(item["key"] == "same-request" for item in entries) == 1, "checkpoint executed twice")
        before = self.ledger.read_bytes()
        collision = self.memory("checkpoint", {**body, "value": "different"}, "same-checkpoint", expect=False)
        require(not collision.get("ok"), "correlation input substitution was accepted")
        require(self.ledger.read_bytes() == before, "correlation substitution changed durable state")
        with ThreadPoolExecutor(max_workers=self.workers) as pool:
            reads = list(pool.map(lambda _: self.memory("get", {"key": "same-request", "default": ""}, "same-read")["result"],
                                  range(self.workers)))
        delivered = [item for item in reads if item["result_available"]]
        require(len(delivered) == 1, "transient output was delivered more than once")
        require(base64.b64decode(delivered[0]["transient_b64"]) == body["value"].encode(), "concurrent read lost bytes")
        return {"parallel_callers": self.workers, "checkpoint_executions": 1, "raw_deliveries": 1}

    def byte_boundaries_restart_and_close(self):
        sid = self.ensure()
        values = ["\n\n", "tabs\tquotes\"slash\\\r\n", "雪é🙂\n" * 100,
                  "long-" + "x" * (24576 - 7) + "\n\n"]
        for number, value in enumerate(values):
            key = "bytes-" + str(number)
            body = self.checkpoint(sid, key, value)
            written = self.memory("checkpoint", body, "write-" + key)["result"]
            require(written["outcome"] == "succeeded", str(written))
            read = self.memory("get", {"key": key, "default": ""}, "read-" + key)["result"]
            require(read["outcome"] == "succeeded", str(read))
            require(base64.b64decode(read["transient_b64"]) == value.encode(), "byte mismatch " + key)
            replay = self.memory("get", {"key": key, "default": ""}, "read-" + key)["result"]
            require(not replay["result_available"], "restart replay disclosed consumed raw result")
        for number, value in enumerate(["x" * 24577, "nul\x00byte"]):
            before = self.ledger.read_bytes()
            rejected = self.memory("checkpoint", self.checkpoint(sid, "rejected", value), "reject-" + str(number), expect=False)
            require(not rejected.get("ok"), "invalid memory value accepted")
            require(self.ledger.read_bytes() == before, "invalid memory value mutated ledger")
        closed = self.memory("close", {"expected_session_id": sid}, "close")["result"]
        require(closed["outcome"] == "succeeded", str(closed))
        read = self.memory("get", {"key": "bytes-3", "default": ""}, "read-closed")["result"]
        require(base64.b64decode(read["transient_b64"]) == values[-1].encode(), "closed session became unreadable")
        write = self.memory("checkpoint", self.checkpoint(sid, "after-close", "forbidden"), "after-close")["result"]
        require(write["outcome"] == "recovery_required", "closed session accepted mutation")
        require(not list(self.root.rglob("after-close.json")), "closed-session mutation left a record")
        return {"byte_values": len(values), "largest_utf8_bytes": len(values[-1].encode()), "invalid_values": 2}

    def concurrent_distinct_writes(self):
        sid = self.ensure()
        def write(number):
            body = self.checkpoint(sid, "parallel-" + str(number), "payload-" + str(number))
            return body, self.memory("checkpoint", body, "parallel-" + str(number))["result"]
        with ThreadPoolExecutor(max_workers=self.workers) as pool:
            results = list(pool.map(write, range(self.workers)))
        succeeded = 0
        conflicts = 0
        for body, result in results:
            require(result["outcome"] in ("succeeded", "recovery_required"), str(result))
            if result["outcome"] == "succeeded":
                succeeded += 1
                got = self.memory("get", {"key": body["key"], "default": ""}, "get-" + body["key"])["result"]
                require(base64.b64decode(got["transient_b64"]) == body["value"].encode(), "acknowledged write was lost")
            else:
                conflicts += 1
                require(not list(self.root.rglob(body["key"] + ".json")), "rejected write was committed")
                retry = self.memory("checkpoint", body, "retry-" + body["key"])["result"]
                require(retry["outcome"] == "succeeded", "fresh request could not recover conflict")
        require(succeeded >= 1, "no concurrent write made progress")
        return {"writers": self.workers, "succeeded": succeeded, "honest_conflicts_retried": conflicts}

    def real_adapter_crash_boundaries(self):
        sid = self.ensure()
        for boundary, expected in [("after_start_hook", "recovery_required"), ("after_evidence_hook", "succeeded")]:
            body = self.checkpoint(sid, boundary, "crash-boundary-value\n")
            program = "\n".join([
                "import sys,os,json", "from pathlib import Path",
                "sys.path.insert(0, " + repr(str(self.release / "control_plane")) + ")",
                "from mainframe_control_plane.memory import ProjectMemoryControlPlane,PROJECT_MEMORY_CHECKPOINT",
                "from mainframe_control_plane.memory_executor import FixedProjectMemorySubprocessExecutor",
                "ledger=Path(" + repr(str(self.ledger)) + ")",
                "c=ProjectMemoryControlPlane(ledger,executor=FixedProjectMemorySubprocessExecutor(ledger_path=ledger))",
                "c.invoke(client_correlation_id=" + repr(boundary) + ",tool=PROJECT_MEMORY_CHECKPOINT,tool_input=json.loads(sys.stdin.read()),actor='local-uid:{}:mainframe-cli'.format(os.geteuid()),workspace=os.getcwd()," + boundary + "=lambda:os._exit(87))",
            ])
            crashed = subprocess.run(["/usr/bin/python3", "-I", "-B", "-c", program],
                                     input=json.dumps(body), text=True, capture_output=True,
                                     cwd=self.project, env=self.environment, timeout=45)
            require(crashed.returncode == 87, "crash hook not reached: " + crashed.stderr)
            recovered = self.memory("checkpoint", body, boundary)["result"]
            for _retry in range(2):
                if recovered["status"] != "in_progress":
                    break
                time.sleep(0.1)
                recovered = self.memory("checkpoint", body, boundary)["result"]
            if recovered["status"] == "in_progress":
                snapshot = self.snapshot()
                call = snapshot.tool_calls[recovered["call_id"]]
                raise AssertionError(boundary + " remained in_progress after three restarted CLI calls; "
                                     "call=" + call.state + ", run=" + snapshot.runs[call.run_id].state +
                                     ", evidence=" + str(sum(item.call_id == call.call_id for item in snapshot.evidence.values())) +
                                     ", aggregates=" + str(sum(item.call_id == call.call_id for item in snapshot.memory_records.values())))
            require(recovered["outcome"] == expected, boundary + ": " + str(recovered))
            again = self.memory("checkpoint", body, boundary)["result"]
            require(again["evidence_id"] == recovered["evidence_id"], "crash replay changed evidence")
            require(bool(list(self.root.rglob(boundary + ".json"))) == (expected == "succeeded"), "crash caused unexpected mutation")
        return {"actual_adapter_crash_boundaries": 2, "replay_evidence_stable": True}

    def repeated_timeout_and_cancellation(self):
        # Only this scenario substitutes a slow fixture adapter. The ledger,
        # policy evaluator, supervisor, cancellation socket and process-group
        # cleanup all come from the exact installed release being tested.
        core = importlib.import_module("mainframe_control_plane")
        execution = importlib.import_module("mainframe_control_plane.executor")
        fixture = self.root / "slow-release"
        (fixture / "bin").mkdir(parents=True, mode=0o700)
        adapter = fixture / "bin/mainframe"
        adapter.write_text("#!/bin/bash\n/bin/cat >/dev/null\n/bin/sleep 30 & child=$!\n"
                           "printf '%s %s\\n' \"$$\" \"$child\" > children.pids\nwait \"$child\"\n")
        adapter.chmod(0o700)
        registry = core.load_fixed_stable_core_registry()
        kernel = core.ControlPlaneKernel(self.ledger, evaluator=core.FixedStableCoreEvaluator(registry),
                                         stable_core_registry=registry)
        elapsed = []
        for number in range(6):
            mode = "cancel" if number % 2 else "timeout"
            correlation = mode + "-" + str(number)
            body = {"value": "private-supervision-value-" + correlation}
            request = kernel.reserve_canonical_request(
                client_correlation_id=correlation, canonical_id="mf:std:pure-string:to_upper",
                tool_input=body, actor="agent:local-stress", workspace=str(self.project), policy="stable-core-v1")
            kernel.create_run(run_id=request.run_id, actor=request.actor, workspace=request.workspace, policy=request.policy)
            kernel.transition_run(request.run_id, "active")
            call = kernel.create_tool_call(
                call_id=request.call_id, run_id=request.run_id, tool=request.canonical_id, tool_input=body,
                effect="read_only", persist_input=False, client_correlation_id=correlation,
                timeout_at=datetime.now(timezone.utc) + timedelta(seconds=4 if mode == "cancel" else 0.6))
            kernel.evaluate_policy_decision(
                decision_id=request.decision_id, call_id=call.call_id, tool=call.tool,
                input_digest=call.input_digest, actor=call.actor, workspace=call.workspace,
                policy=call.policy, timeout_at=call.timeout_at, tool_input=body)
            executor = execution.FixedStableCoreSubprocessExecutor._for_test(
                release_root=fixture, registry=registry, call=kernel.snapshot().tool_calls[call.call_id],
                ledger_path=self.ledger)
            marker = self.project / "children.pids"
            if marker.exists():
                marker.unlink()
            started = time.monotonic()
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(kernel.execute_canonical, call.call_id, executor=executor, tool_input=body)
                if mode == "cancel":
                    while not marker.exists() and not future.done() and time.monotonic() - started < 2:
                        time.sleep(0.01)
                    require(marker.exists(), "slow adapter never reached cancellable state")
                    accepted = execution.request_canonical_cancellation(self.ledger, client_correlation_id=correlation)
                    require(accepted["accepted"] and accepted["call_id"] == call.call_id, "cancellation identity mismatch")
                evidence = future.result(timeout=6)
            elapsed.append(round(time.monotonic() - started, 3))
            require(evidence.outcome == ("interrupted" if mode == "cancel" else "timed_out"),
                    mode + " had wrong terminal outcome: " + evidence.outcome)
            require(marker.exists(), "timeout did not exercise an actual process")
            pids = [int(item) for item in marker.read_text().split()]
            for pid in pids:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    continue
                raise AssertionError("supervision left fixture process alive: " + str(pid))
            snapshot = kernel.snapshot()
            require(snapshot.runs[request.run_id].state == "failed", "cancelled/timed-out run stayed active")
            require(sum(item.call_id == call.call_id for item in snapshot.evidence.values()) == 1,
                    "cancellation/timeout recorded duplicate evidence")
            require(body["value"] not in self.ledger.read_text(), "supervision persisted transient input")
        return {"timeouts": 3, "explicit_cancellations": 3, "fixture_pids_reaped": 12, "seconds_per_call": elapsed}

    def real_retention_and_corruption(self):
        sid = self.ensure()
        memory = importlib.import_module("mainframe_control_plane.memory")
        execution = importlib.import_module("mainframe_control_plane.memory_executor")
        control = memory.ProjectMemoryControlPlane(
            self.ledger, executor=execution.FixedProjectMemorySubprocessExecutor(ledger_path=self.ledger))
        common = {"actor": "local-uid:{}:mainframe-cli".format(os.geteuid()), "workspace": str(self.project)}
        delayed = self.checkpoint(sid, "delayed-ttl", "expires-at-reservation", ttl=60)
        reservation = control.reserve(client_correlation_id="delayed-ttl", tool=memory.PROJECT_MEMORY_CHECKPOINT,
                                      tool_input=delayed, **common)
        time.sleep(1.1)
        result = self.memory("checkpoint", delayed, "delayed-ttl")["result"]
        require(result["outcome"] == "succeeded", "valid delayed reservation did not complete")
        sidecar = json.loads(next(self.root.rglob("delayed-ttl.json")).read_text())
        expiry = datetime.fromisoformat(reservation.reservation_binding["expires_at"].replace("Z", "+00:00"))
        require(sidecar["retention"]["expires_at_epoch"] == int(expiry.timestamp()), "delayed write renewed reserved TTL")
        expired = self.checkpoint(sid, "expired-ttl", "never-committed", ttl=1)
        control.reserve(client_correlation_id="expired-ttl", tool=memory.PROJECT_MEMORY_CHECKPOINT,
                        tool_input=expired, **common)
        time.sleep(1.1)
        result = self.memory("checkpoint", expired, "expired-ttl")["result"]
        require(result["outcome"] == "failed", "expired reservation did not fail closed")
        require(not list(self.root.rglob("expired-ttl.json")), "expired reservation committed a sidecar")
        corrupt = self.checkpoint(sid, "corrupt-data", "original-checkpoint")
        require(self.memory("checkpoint", corrupt, "corrupt-write")["result"]["outcome"] == "succeeded",
                "corruption fixture write failed")
        metadata_path = next(self.root.rglob("corrupt-data.json"))
        metadata = json.loads(metadata_path.read_text())
        value_path = metadata_path.parent.parent / "data" / metadata["storage_key"]
        require(value_path.read_bytes() == b"original-checkpoint", "fixture value path is not the written checkpoint")
        value_path.write_bytes(b"corrupted-checkpoint-never-return-this")
        rejected = self.memory("get", {"key": "corrupt-data", "default": "do-not-hide-corruption"}, "corrupt-read", expect=False)
        if rejected.get("ok"):
            result = rejected["result"]
            require(result["outcome"] in ("failed", "recovery_required") and not result["result_available"],
                    "corrupt checkpoint was returned or silently replaced with a default")
        require("corrupted-checkpoint-never-return-this" not in json.dumps(rejected), "corrupt bytes escaped validation")
        return {"delayed_ttl_not_renewed": True, "expired_reservation_rejected": True,
                "real_checkpoint_corruption_rejected": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release", type=Path)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--scenario", action="append", help="Run only this scenario; repeat to select more than one")
    arguments = parser.parse_args()
    require(1 <= arguments.workers <= 16 and 1 <= arguments.rounds <= 10, "bounded stress parameters required")
    release = arguments.release.resolve(strict=True)
    # Inspect installed code without adding generated cache files to the release.
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(release / "control_plane"))
    os.umask(0o077)
    report = {"release": str(release), "version": (release / "VERSION").read_text().strip(),
              "registry_sha256": hashlib.sha256((release / "INVOCATION_INDEX.json").read_bytes()).hexdigest(),
              "timestamp": datetime.now(timezone.utc).isoformat(), "checks": [], "invocations": 0}
    scenarios = [name for name in vars(InstalledChecks) if name in {
        "registry_all_contracts_and_negatives", "concurrent_same_request",
        "byte_boundaries_restart_and_close", "concurrent_distinct_writes", "real_adapter_crash_boundaries",
        "repeated_timeout_and_cancellation", "real_retention_and_corruption"}]
    if arguments.scenario:
        require(set(arguments.scenario) <= set(scenarios), "unknown scenario")
        scenarios = [name for name in scenarios if name in arguments.scenario]
    for round_number in range(arguments.rounds):
        for name in scenarios:
            started = time.monotonic()
            result = {"scenario": name, "round": round_number + 1}
            with tempfile.TemporaryDirectory(prefix="mainframe-installed-stress-") as directory:
                checks = InstalledChecks(release, Path(directory).resolve(), arguments.workers)
                try:
                    result.update(status="passed", details=getattr(checks, name)())
                except Exception as error:
                    result.update(status="failed", error=type(error).__name__ + ": " + str(error),
                                  traceback=traceback.format_exc())
                report["invocations"] += checks.invocations
            result["seconds"] = round(time.monotonic() - started, 3)
            report["checks"].append(result)
            print(json.dumps(result), flush=True)
    report["passed"] = all(item["status"] == "passed" for item in report["checks"])
    if arguments.report:
        arguments.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "invocations": report["invocations"], "checks": len(report["checks"])}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

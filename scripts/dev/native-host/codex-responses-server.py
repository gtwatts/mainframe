#!/usr/bin/env python3
"""Loopback-only, two-request Responses API fixture for Codex certification."""

from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
from socketserver import TCPServer
import sys
import time
from typing import Any, NoReturn


MAX_REQUEST_BYTES = 8 * 1024 * 1024
EXPECTED_MODEL = "gpt-5.5"
SENTINEL_TOKEN = "__MAINFRAME_SENTINEL_TOFU__"
SHELL_TOKEN = "__MAINFRAME_CERT_SHELL__"
EXPECTED_COMMAND_TEMPLATE = f"{SENTINEL_TOKEN} destroy -auto-approve"
EXPECTED_CALL_ID = "mainframe-codex-destroy"
EXPECTED_FINAL_TEXT = "MAINFRAME native host certification observed the policy result."
DESTROY_SCENARIO = "destroy"
AWM_CHAIN_SCENARIO = "awm-chain"
AWM_CHAIN_COMMAND = (
    'mainframe awm get --session "$MAINFRAME_AWM_SESSION" '
    '"$MAINFRAME_AWM_READ_KEY" > "$MAINFRAME_AWM_SCRATCH" || { '
    "printf 'MAINFRAME_AWM_MISSING_PREDECESSOR\\n' >&2; exit 42; }; "
    "printf '\\n' >> \"$MAINFRAME_AWM_SCRATCH\" && "
    'IFS= read -r previous < "$MAINFRAME_AWM_SCRATCH" && test -n "$previous" && '
    ': > "$MAINFRAME_AWM_SCRATCH" && '
    'next="${previous}:${MAINFRAME_AGENT_NAME}" && mainframe awm checkpoint '
    '--session "$MAINFRAME_AWM_SESSION" "$MAINFRAME_AWM_WRITE_KEY" "$next" '
    '--importance high --tags "native-awm,$MAINFRAME_AGENT_NAME" && '
    "printf 'MAINFRAME_AWM_CHAIN_OK:%s\\n' \"$MAINFRAME_AGENT_NAME\""
)


class LoopbackHTTPServer(HTTPServer):
    """Bind loopback without a reverse-DNS lookup on hosted runners."""

    def server_bind(self) -> None:
        TCPServer.server_bind(self)
        self.server_name = "127.0.0.1"
        self.server_port = int(self.server_address[1])


AWM_CHAIN_CALL_ID = "mainframe-codex-awm-chain"
AWM_CHAIN_FINAL_TEXT = "MAINFRAME AWM chain step completed for Codex."
AWM_CHAIN_SUCCESS_MARKER = "MAINFRAME_AWM_CHAIN_OK:codex"
AWM_MISSING_PREDECESSOR_MARKER = "MAINFRAME_AWM_MISSING_PREDECESSOR"
AWM_MISSING_PREDECESSOR_EXIT_CODE = 42
AWM_MISSING_PREDECESSOR_FINAL_TEXT = (
    "MAINFRAME AWM missing predecessor rejected for Codex."
)
AWM_EXPECTATIONS = ("success", "missing-predecessor")
AWM_GUARD_RAW_SEED_ENV = "MAINFRAME_AWM_GUARD_RAW_SEED"
AWM_GUARD_DERIVED_ENV = "MAINFRAME_AWM_GUARD_DERIVED_CHECKPOINTS_JSON"
AWM_GUARD_ROOT_ENV = "MAINFRAME_AWM_GUARD_ROOT"
AWM_EXPECTATION_ENV = "MAINFRAME_AWM_EXPECTATION"
FIXTURE_SCENARIOS = {
    DESTROY_SCENARIO: {
        "call_id": EXPECTED_CALL_ID,
        "command": EXPECTED_COMMAND_TEMPLATE,
        "final_text": EXPECTED_FINAL_TEXT,
    },
    AWM_CHAIN_SCENARIO: {
        "call_id": AWM_CHAIN_CALL_ID,
        "command": AWM_CHAIN_COMMAND,
        "final_text": AWM_CHAIN_FINAL_TEXT,
    },
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid Codex fixture server input: {message}")


def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        fail(f"{path}: {error}")


def validate_fixture(
    value: Any, scenario: str = DESTROY_SCENARIO
) -> dict[str, Any]:
    expected = FIXTURE_SCENARIOS.get(scenario)
    if expected is None:
        fail(f"unsupported fixture scenario: {scenario}")
    if not isinstance(value, dict) or set(value) != {
        "schema_version",
        "call_id",
        "command",
        "final_text",
        "responses",
    }:
        fail("fixture root has unexpected fields")
    if value["schema_version"] != 1:
        fail("fixture schema_version must be 1")
    if value["call_id"] != expected["call_id"]:
        fail("fixture call_id is not the certification call")
    if value["command"] != expected["command"]:
        if scenario == DESTROY_SCENARIO:
            fail("fixture command is not the disposable certification sentinel")
        fail("fixture command is not the exact nonce-free AWM chain command")
    if value["final_text"] != expected["final_text"]:
        fail("fixture final text is not the certification completion text")
    responses = value["responses"]
    if not isinstance(responses, list) or len(responses) != 2:
        fail("fixture must contain exactly two response event lists")
    if any(not isinstance(events, list) or len(events) != 3 for events in responses):
        fail("each fixture response must contain exactly three events")

    expected_types = ["response.created", "response.output_item.done", "response.completed"]
    for index, events in enumerate(responses):
        if [event.get("type") for event in events if isinstance(event, dict)] != expected_types:
            fail(f"response {index + 1} has unexpected event ordering")
    function_item = responses[0][1].get("item", {})
    if function_item != {
        "type": "function_call",
        "call_id": expected["call_id"],
        "name": "exec_command",
        "arguments": json.dumps(
            {"cmd": expected["command"], "shell": SHELL_TOKEN},
            separators=(",", ":"),
        ),
    }:
        fail("first response is not the exact exec_command fixture")
    message_item = responses[1][1].get("item", {})
    if (
        message_item.get("type") != "message"
        or message_item.get("role") != "assistant"
        or message_item.get("content")
        != [{"type": "output_text", "text": expected["final_text"]}]
    ):
        fail("second response is not the exact assistant completion fixture")
    return value


def materialize_fixture(
    value: dict[str, Any], sentinel: Path, shell: Path
) -> dict[str, Any]:
    sentinel_text = str(sentinel)
    shell_text = str(shell)
    for label, path, text in (
        ("sentinel", sentinel, sentinel_text),
        ("shell", shell, shell_text),
    ):
        if not path.is_absolute():
            fail(f"{label} path must be absolute")
        if path.is_symlink() or not path.is_file() or not os.access(path, os.X_OK):
            fail(f"{label} must be a regular, non-symlink executable")
        if re.fullmatch(r"[A-Za-z0-9_./-]+", text) is None:
            fail(f"{label} path contains shell metacharacters")

    command = f"{sentinel_text} destroy -auto-approve"
    materialized = json.loads(json.dumps(value))
    materialized["command"] = command
    materialized["responses"][0][1]["item"]["arguments"] = json.dumps(
        {"cmd": command, "shell": shell_text},
        separators=(",", ":"),
    )
    return materialized


def materialize_awm_fixture(
    value: dict[str, Any], shell: Path
) -> dict[str, Any]:
    shell_text = str(shell)
    if not shell.is_absolute():
        fail("shell path must be absolute")
    if shell.is_symlink() or not shell.is_file() or not os.access(shell, os.X_OK):
        fail("shell must be a regular, non-symlink executable")
    if re.fullmatch(r"[A-Za-z0-9_./-]+", shell_text) is None:
        fail("shell path contains shell metacharacters")

    materialized = json.loads(json.dumps(value))
    materialized["responses"][0][1]["item"]["arguments"] = json.dumps(
        {"cmd": AWM_CHAIN_COMMAND, "shell": shell_text},
        separators=(",", ":"),
    )
    return materialized


def write_private_json(path: Path, value: dict[str, Any]) -> None:
    if path.is_symlink():
        fail(f"refusing to replace symbolic link: {path}")
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(temporary, flags, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def _nonempty_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value)


def _derived_checkpoints_from_environment() -> list[str]:
    encoded = os.environ.get(AWM_GUARD_DERIVED_ENV)
    if encoded is None:
        return []
    try:
        values = json.loads(encoded)
    except json.JSONDecodeError:
        fail(f"{AWM_GUARD_DERIVED_ENV} must be a JSON array of non-empty strings")
    if (
        not isinstance(values, list)
        or not values
        or any(not _nonempty_text(value) for value in values)
    ):
        fail(f"{AWM_GUARD_DERIVED_ENV} must be a JSON array of non-empty strings")
    return values


class RequestHygieneGuard:
    def __init__(
        self,
        raw_seed: str,
        derived_checkpoints: list[str],
        awm_root: str,
    ) -> None:
        if not _nonempty_text(raw_seed):
            fail("AWM-chain raw seed guard must be non-empty")
        if not derived_checkpoints or any(
            not _nonempty_text(value) for value in derived_checkpoints
        ):
            fail("AWM-chain derived checkpoint guards must be non-empty")
        if not _nonempty_text(awm_root) or not Path(awm_root).is_absolute():
            fail("AWM-chain root guard must be an absolute path")
        ordered_derived = sorted(set(derived_checkpoints), key=len, reverse=True)
        self._needles = tuple(
            [("derived-checkpoint", value.encode("utf-8")) for value in ordered_derived]
            + [
                ("raw-seed", raw_seed.encode("utf-8")),
                ("awm-root", awm_root.encode("utf-8")),
            ]
        )
        self.checks = 0
        self.rejections = 0
        self.reason: str | None = None

    def inspect(self, raw: bytes) -> str | None:
        self.checks += 1
        for reason, needle in self._needles:
            if needle in raw:
                self.rejections += 1
                self.reason = reason
                return reason
        return None

    def summary(self) -> dict[str, Any]:
        return {
            "request_hygiene_checked": self.checks > 0,
            "request_hygiene_passed": self.checks > 0 and self.rejections == 0,
            "request_hygiene_checks": self.checks,
            "request_hygiene_rejections": self.rejections,
            "request_hygiene_reason": self.reason,
        }


def request_hygiene_guard_from_args(args: argparse.Namespace) -> RequestHygieneGuard:
    raw_seed = (
        args.raw_seed
        if args.raw_seed is not None
        else os.environ.get(AWM_GUARD_RAW_SEED_ENV)
    )
    derived_checkpoints = list(args.derived_checkpoint)
    if not derived_checkpoints:
        derived_checkpoints = _derived_checkpoints_from_environment()
    awm_root = (
        str(args.awm_root)
        if args.awm_root is not None
        else os.environ.get(AWM_GUARD_ROOT_ENV)
    )
    if raw_seed is None or awm_root is None:
        fail("AWM-chain serving requires raw seed, derived checkpoint, and root guards")
    return RequestHygieneGuard(raw_seed, derived_checkpoints, awm_root)


def awm_expectation_from_args(args: argparse.Namespace) -> str:
    expectation = args.awm_expectation or os.environ.get(
        AWM_EXPECTATION_ENV, "success"
    )
    if expectation not in AWM_EXPECTATIONS:
        fail("AWM-chain expectation must be success or missing-predecessor")
    return expectation


def request_tools_include_exec_command(body: dict[str, Any]) -> bool:
    tools = body.get("tools")
    if not isinstance(tools, list):
        return False
    for tool in tools:
        if not isinstance(tool, dict):
            continue
        parameters = tool.get("parameters")
        properties = parameters.get("properties") if isinstance(parameters, dict) else None
        if (
            tool.get("type") == "function"
            and tool.get("name") == "exec_command"
            and isinstance(properties, dict)
            and "cmd" in properties
            and "shell" in properties
        ):
            return True
    return False


def find_function_output(
    body: dict[str, Any], call_id: str = EXPECTED_CALL_ID
) -> str | None:
    items = body.get("input")
    if not isinstance(items, list):
        return None
    for item in items:
        if (
            isinstance(item, dict)
            and item.get("type") == "function_call_output"
            and item.get("call_id") == call_id
        ):
            output = item.get("output")
            if isinstance(output, str):
                return output
            if output is not None:
                return json.dumps(output, sort_keys=True, separators=(",", ":"))
    return None


def destroy_function_output_diagnostic(output: str) -> dict[str, Any]:
    """Return only fixed error-class signals, never caller-controlled text."""
    signal_patterns = (
        ("sandbox_denied", r"\bsandbox(?: startup)? denied\b"),
        ("permission_denied", r"\bpermission denied\b"),
        ("operation_not_permitted", r"\boperation not permitted\b"),
        ("bubblewrap", r"\b(?:bubblewrap|bwrap)\b"),
        ("user_namespace", r"\b(?:user namespace|userns)\b"),
        ("landlock", r"\blandlock\b"),
        ("executable_not_found", r"\b(?:no such file or directory|not found)\b"),
        ("timed_out", r"\b(?:timed out|timeout)\b"),
    )
    signals = [
        name
        for name, pattern in signal_patterns
        if re.search(pattern, output, flags=re.IGNORECASE)
    ]
    return {"bytes": len(output.encode("utf-8")), "signals": signals}


def awm_chain_output_succeeded(output: str) -> bool:
    denial_seen = (
        "Command blocked by PreToolUse hook" in output
        or "MAINFRAME agent gateway blocked the tool call" in output
    )
    return not denial_seen and AWM_CHAIN_SUCCESS_MARKER in output


def awm_missing_predecessor_marker_seen(output: str) -> bool:
    return any(
        line.strip() == AWM_MISSING_PREDECESSOR_MARKER
        for line in output.splitlines()
    )


def awm_exit_code_42_seen(output: str) -> bool:
    return re.search(
        rf"(?i)\bexit(?:ed)?(?:\s+with)?\s+(?:code|status)\s*[:=]?\s*"
        rf"{AWM_MISSING_PREDECESSOR_EXIT_CODE}\b",
        output,
    ) is not None


def awm_missing_predecessor_output_succeeded(output: str) -> bool:
    denial_seen = (
        "Command blocked by PreToolUse hook" in output
        or "MAINFRAME agent gateway blocked the tool call" in output
    )
    return (
        awm_missing_predecessor_marker_seen(output)
        and awm_exit_code_42_seen(output)
        and not denial_seen
    )


def sse(events: list[dict[str, Any]]) -> bytes:
    records = []
    for event in events:
        kind = event["type"]
        records.append(
            f"event: {kind}\ndata: {json.dumps(event, separators=(',', ':'))}\n\n"
        )
    return "".join(records).encode("utf-8")


def response_payload(
    fixture: dict[str, Any],
    request_index: int,
    final_text: str | None = None,
) -> bytes:
    events = json.loads(json.dumps(fixture["responses"][request_index]))
    if final_text is not None:
        events[1]["item"]["content"] = [{"type": "output_text", "text": final_text}]
    return sse(events)


class FixtureState:
    def __init__(
        self,
        mode: str,
        fixture: dict[str, Any],
        scenario: str = DESTROY_SCENARIO,
        awm_expectation: str = "success",
        request_hygiene: RequestHygieneGuard | None = None,
    ) -> None:
        self.mode = mode
        self.fixture = fixture
        self.scenario = scenario
        self.call_id = FIXTURE_SCENARIOS[scenario]["call_id"]
        self.awm_expectation = awm_expectation
        self.request_hygiene = request_hygiene
        self.requests = 0
        self.advertised_exec_command = False
        self.function_output_seen = False
        self.denial_output_seen = False
        self.success_marker_seen = False
        self.missing_predecessor_marker_seen = False
        self.tool_result_nonzero = False
        self.authorization_header_seen = False
        self.error: str | None = None

    def summary(self) -> dict[str, Any]:
        status = "ok" if self.error is None and self.requests == 2 else "error"
        if (
            self.scenario == AWM_CHAIN_SCENARIO
            and self.awm_expectation == "missing-predecessor"
            and self.error is None
            and self.requests == 2
        ):
            status = "expected-missing-predecessor"
        summary = {
            "schema_version": 1,
            "mode": self.mode,
            "status": status,
            "requests": self.requests,
            "advertised_exec_command": self.advertised_exec_command,
            "function_output_seen": self.function_output_seen,
            "denial_output_seen": self.denial_output_seen,
            "authorization_header_seen": self.authorization_header_seen,
            "error": self.error,
        }
        if self.scenario == AWM_CHAIN_SCENARIO:
            summary["scenario"] = AWM_CHAIN_SCENARIO
            summary["awm_expectation"] = self.awm_expectation
            summary["success_marker_seen"] = self.success_marker_seen
            summary["missing_predecessor_marker_seen"] = (
                self.missing_predecessor_marker_seen
            )
            summary["tool_result_nonzero"] = self.tool_result_nonzero
            if self.request_hygiene is None:
                summary.update(
                    {
                        "request_hygiene_checked": False,
                        "request_hygiene_passed": False,
                        "request_hygiene_checks": 0,
                        "request_hygiene_rejections": 0,
                        "request_hygiene_reason": "not-configured",
                    }
                )
            else:
                summary.update(self.request_hygiene.summary())
        return summary


def handler_for(state: FixtureState) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, _format: str, *_args: object) -> None:
            return

        def reject(self, status: int, message: str) -> None:
            state.error = message
            payload = json.dumps({"error": message}, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            self.close_connection = True

        def do_GET(self) -> None:  # noqa: N802
            self.reject(405, "only POST /v1/responses is allowed")

        def do_PUT(self) -> None:  # noqa: N802
            self.reject(405, "only POST /v1/responses is allowed")

        def do_POST(self) -> None:  # noqa: N802
            if self.path != "/v1/responses":
                self.reject(404, "request path must be /v1/responses")
                return
            if state.requests >= 2:
                self.reject(409, "fixture accepts exactly two requests")
                return
            if self.headers.get("Authorization") or self.headers.get("X-Api-Key"):
                state.authorization_header_seen = True
                self.reject(400, "credential header is forbidden")
                return
            content_encoding = self.headers.get("Content-Encoding", "identity").lower()
            if content_encoding != "identity":
                self.reject(400, "compressed request bodies are forbidden")
                return
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                self.reject(411, "a valid Content-Length is required")
                return
            if length <= 0 or length > MAX_REQUEST_BYTES:
                self.reject(413, "request body size is outside the certification limit")
                return
            raw = self.rfile.read(length)
            if state.scenario == AWM_CHAIN_SCENARIO:
                if state.request_hygiene is None:
                    self.reject(500, "AWM-chain request hygiene guard is not configured")
                    return
                hygiene_reason = state.request_hygiene.inspect(raw)
                if hygiene_reason is not None:
                    self.reject(
                        400,
                        f"AWM-chain request hygiene rejected: {hygiene_reason}",
                    )
                    return
            try:
                body = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicates)
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
                self.reject(400, f"invalid JSON request: {error}")
                return
            if not isinstance(body, dict):
                self.reject(400, "request body must be a JSON object")
                return
            if body.get("model") != EXPECTED_MODEL or body.get("stream") is not True:
                self.reject(400, "request must use the pinned streaming fixture model")
                return
            if not request_tools_include_exec_command(body):
                advertised = [
                    [tool.get("type"), tool.get("name")]
                    for tool in body.get("tools", [])
                    if isinstance(tool, dict)
                ]
                self.reject(
                    400,
                    "request does not advertise the exec_command tool; "
                    f"tools_type={type(body.get('tools')).__name__}; got {advertised!r}; "
                    f"keys={sorted(body)}",
                )
                return

            request_index = state.requests
            if request_index == 0:
                state.advertised_exec_command = True
                if find_function_output(body, state.call_id) is not None:
                    self.reject(400, "first request unexpectedly contains tool output")
                    return
            else:
                output = find_function_output(body, state.call_id)
                if output is None:
                    self.reject(400, "second request is missing matching function_call_output")
                    return
                state.function_output_seen = True
                state.denial_output_seen = (
                    "Command blocked by PreToolUse hook" in output
                    or "MAINFRAME agent gateway blocked the tool call" in output
                )
                if state.scenario == AWM_CHAIN_SCENARIO:
                    if state.awm_expectation == "missing-predecessor":
                        state.missing_predecessor_marker_seen = (
                            awm_missing_predecessor_marker_seen(output)
                        )
                        state.tool_result_nonzero = awm_exit_code_42_seen(output)
                        if not awm_missing_predecessor_output_succeeded(output):
                            self.reject(
                                400,
                                "AWM-chain output is missing the exact "
                                "missing-predecessor marker or exit code 42",
                            )
                            return
                    else:
                        state.success_marker_seen = AWM_CHAIN_SUCCESS_MARKER in output
                        if not awm_chain_output_succeeded(output):
                            self.reject(
                                400,
                                "AWM-chain output is missing the exact success marker",
                            )
                            return
                else:
                    if state.mode == "control":
                        diagnostic = destroy_function_output_diagnostic(output)
                        print(
                            "Codex control function output diagnostic: "
                            + json.dumps(
                                diagnostic, sort_keys=True, separators=(",", ":")
                            ),
                            file=sys.stderr,
                            flush=True,
                        )
                    if state.mode == "protected" and not state.denial_output_seen:
                        self.reject(400, "protected request does not contain the hook denial")
                        return
                    if state.mode == "control" and state.denial_output_seen:
                        self.reject(400, "control request unexpectedly contains a hook denial")
                        return

            final_text = None
            if (
                state.scenario == AWM_CHAIN_SCENARIO
                and state.awm_expectation == "missing-predecessor"
                and request_index == 1
            ):
                final_text = AWM_MISSING_PREDECESSOR_FINAL_TEXT
            payload = response_payload(state.fixture, request_index, final_text)
            state.requests += 1
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            self.wfile.flush()
            self.close_connection = True

    return Handler


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument(
        "--scenario",
        choices=(DESTROY_SCENARIO, AWM_CHAIN_SCENARIO),
        default=DESTROY_SCENARIO,
    )
    parser.add_argument("--mode", choices=("control", "protected"))
    parser.add_argument("--ready", type=Path)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--sentinel", type=Path)
    parser.add_argument("--shell", type=Path)
    parser.add_argument("--raw-seed")
    parser.add_argument("--derived-checkpoint", action="append", default=[])
    parser.add_argument("--awm-root", type=Path)
    parser.add_argument("--awm-expectation", choices=AWM_EXPECTATIONS)
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--check-fixture", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    fixture = validate_fixture(load_json(args.fixture), args.scenario)
    if args.check_fixture:
        if args.scenario == AWM_CHAIN_SCENARIO:
            print("Codex Responses AWM-chain fixture valid")
            return 0
        print("Codex Responses fixture valid")
        return 0
    if args.scenario == DESTROY_SCENARIO:
        if (
            args.mode is None
            or args.ready is None
            or args.state is None
            or args.sentinel is None
            or args.shell is None
        ):
            fail("--mode, --ready, --state, --sentinel, and --shell are required when serving")
    else:
        if args.mode != "control" or args.ready is None or args.state is None or args.shell is None:
            fail("--mode control, --ready, --state, and --shell are required for awm-chain")
        if args.sentinel is not None:
            fail("--sentinel is not accepted for the awm-chain scenario")
    if args.timeout <= 0 or args.timeout > 120:
        fail("--timeout must be greater than 0 and at most 120 seconds")
    for output in (args.ready, args.state):
        if output.exists() or output.is_symlink():
            fail(f"output path already exists: {output}")
        if not output.parent.is_dir():
            fail(f"output parent is not a directory: {output.parent}")

    if args.scenario == DESTROY_SCENARIO:
        fixture = materialize_fixture(fixture, args.sentinel, args.shell)
        request_hygiene = None
        awm_expectation = "success"
    else:
        fixture = materialize_awm_fixture(fixture, args.shell)
        request_hygiene = request_hygiene_guard_from_args(args)
        awm_expectation = awm_expectation_from_args(args)
    state = FixtureState(
        args.mode,
        fixture,
        args.scenario,
        awm_expectation=awm_expectation,
        request_hygiene=request_hygiene,
    )
    server = LoopbackHTTPServer(("127.0.0.1", 0), handler_for(state))
    server.timeout = 0.25
    port = int(server.server_address[1])
    write_private_json(args.ready, {"schema_version": 1, "address": "127.0.0.1", "port": port})

    deadline = time.monotonic() + args.timeout
    try:
        while state.error is None and state.requests < 2 and time.monotonic() < deadline:
            server.handle_request()
        if state.error is None and state.requests != 2:
            state.error = "fixture timed out before exactly two requests"
    finally:
        server.server_close()
        write_private_json(args.state, state.summary())
    if state.error is not None:
        print(f"Codex fixture server failed: {state.error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

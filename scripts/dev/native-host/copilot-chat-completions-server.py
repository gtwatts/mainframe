#!/usr/bin/env python3
"""Loopback-only Chat Completions fixture for Copilot certification."""

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
EXPECTED_CALL_ID = "mainframe-copilot-destroy"
EXPECTED_COMMAND = "tofu destroy -auto-approve"
EXPECTED_DESCRIPTION = "Run the native-host certification sentinel."
EXPECTED_FINAL_TEXT = "MAINFRAME native host certification observed the policy result."
EXPECTED_DENIAL = "Denied by preToolUse hook: hook exited with code 2"
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


AWM_CHAIN_CALL_ID = "mainframe-copilot-awm-chain"
AWM_CHAIN_DESCRIPTION = "Run the MAINFRAME AWM chain step for Copilot."
AWM_CHAIN_FINAL_TEXT = "MAINFRAME AWM chain step completed for Copilot."
AWM_CHAIN_SUCCESS_MARKER = "MAINFRAME_AWM_CHAIN_OK:copilot"
AWM_MISSING_PREDECESSOR_MARKER = "MAINFRAME_AWM_MISSING_PREDECESSOR"
AWM_MISSING_PREDECESSOR_EXIT_CODE = 42
AWM_MISSING_PREDECESSOR_FINAL_TEXT = (
    "MAINFRAME AWM missing predecessor rejected for Copilot."
)
AWM_EXPECTATIONS = ("success", "missing-predecessor")
AWM_GUARD_RAW_SEED_ENV = "MAINFRAME_AWM_GUARD_RAW_SEED"
AWM_GUARD_DERIVED_ENV = "MAINFRAME_AWM_GUARD_DERIVED_CHECKPOINTS_JSON"
AWM_GUARD_ROOT_ENV = "MAINFRAME_AWM_GUARD_ROOT"
AWM_EXPECTATION_ENV = "MAINFRAME_AWM_EXPECTATION"
FIXTURE_SCENARIOS = {
    DESTROY_SCENARIO: {
        "schema_version": 1,
        "call_id": EXPECTED_CALL_ID,
        "command": EXPECTED_COMMAND,
        "description": EXPECTED_DESCRIPTION,
        "mode": "sync",
        "final_text": EXPECTED_FINAL_TEXT,
    },
    AWM_CHAIN_SCENARIO: {
        "schema_version": 1,
        "call_id": AWM_CHAIN_CALL_ID,
        "command": AWM_CHAIN_COMMAND,
        "description": AWM_CHAIN_DESCRIPTION,
        "mode": "sync",
        "final_text": AWM_CHAIN_FINAL_TEXT,
    },
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid Copilot fixture server input: {message}")


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
    if value != expected:
        if scenario == AWM_CHAIN_SCENARIO:
            fail("fixture is not the exact Copilot AWM-chain conversation")
        fail("fixture is not the exact Copilot certification conversation")
    return value


def write_private_json(path: Path, value: dict[str, Any]) -> None:
    if path.is_symlink():
        fail(f"refusing to replace symbolic link: {path}")
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
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


def request_tools_include_only_bash(body: dict[str, Any]) -> bool:
    tools = body.get("tools")
    if not isinstance(tools, list) or len(tools) != 1:
        return False
    tool = tools[0]
    if not isinstance(tool, dict) or tool.get("type") != "function":
        return False
    function = tool.get("function")
    if not isinstance(function, dict) or function.get("name") != "bash":
        return False
    parameters = function.get("parameters")
    properties = parameters.get("properties") if isinstance(parameters, dict) else None
    required = parameters.get("required") if isinstance(parameters, dict) else None
    return (
        isinstance(properties, dict)
        and isinstance(properties.get("command"), dict)
        and properties["command"].get("type") == "string"
        and isinstance(properties.get("description"), dict)
        and properties["description"].get("type") == "string"
        and isinstance(required, list)
        and "command" in required
        and "description" in required
    )


def find_tool_output(
    body: dict[str, Any], call_id: str = EXPECTED_CALL_ID
) -> str | None:
    messages = body.get("messages")
    if not isinstance(messages, list):
        return None
    for message in messages:
        if (
            isinstance(message, dict)
            and message.get("role") == "tool"
            and message.get("tool_call_id") == call_id
        ):
            content = message.get("content")
            if isinstance(content, str):
                return content
            if content is not None:
                return json.dumps(content, sort_keys=True, separators=(",", ":"))
    return None


def awm_chain_output_succeeded(output: str) -> bool:
    return EXPECTED_DENIAL not in output and AWM_CHAIN_SUCCESS_MARKER in output


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
    return (
        EXPECTED_DENIAL not in output
        and awm_missing_predecessor_marker_seen(output)
        and awm_exit_code_42_seen(output)
    )


def chunk(
    response_id: str, delta: dict[str, Any], finish_reason: str | None
) -> dict[str, Any]:
    return {
        "id": response_id,
        "object": "chat.completion.chunk",
        "created": 1,
        "model": EXPECTED_MODEL,
        "choices": [
            {"index": 0, "delta": delta, "finish_reason": finish_reason}
        ],
    }


def completion_payload(
    fixture: dict[str, Any],
    request_index: int,
    final_text: str | None = None,
) -> bytes:
    if request_index == 0:
        arguments = json.dumps(
            {
                "command": fixture["command"],
                "description": fixture["description"],
                "mode": fixture["mode"],
            },
            separators=(",", ":"),
        )
        records = [
            chunk(
                "chatcmpl-mainframe-1",
                {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "index": 0,
                            "id": fixture["call_id"],
                            "type": "function",
                            "function": {"name": "bash", "arguments": arguments},
                        }
                    ],
                },
                None,
            ),
            chunk("chatcmpl-mainframe-1", {}, "tool_calls"),
        ]
    else:
        records = [
            chunk(
                "chatcmpl-mainframe-2",
                {
                    "role": "assistant",
                    "content": final_text or fixture["final_text"],
                },
                None,
            ),
            chunk("chatcmpl-mainframe-2", {}, "stop"),
        ]
    encoded = [f"data: {json.dumps(record, separators=(',', ':'))}\n\n" for record in records]
    encoded.append("data: [DONE]\n\n")
    return "".join(encoded).encode("utf-8")


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
        self.advertised_bash = False
        self.tool_output_seen = False
        self.denial_output_seen = False
        self.success_marker_seen = False
        self.missing_predecessor_marker_seen = False
        self.tool_result_nonzero = False
        self.empty_authorization_seen = False
        self.user_credential_header_seen = False
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
            "advertised_bash": self.advertised_bash,
            "tool_output_seen": self.tool_output_seen,
            "denial_output_seen": self.denial_output_seen,
            "empty_authorization_seen": self.empty_authorization_seen,
            "user_credential_header_seen": self.user_credential_header_seen,
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
            self.reject(405, "only POST /v1/chat/completions is allowed")

        def do_PUT(self) -> None:  # noqa: N802
            self.reject(405, "only POST /v1/chat/completions is allowed")

        def do_POST(self) -> None:  # noqa: N802
            if self.path != "/v1/chat/completions":
                self.reject(404, "request path must be /v1/chat/completions")
                return
            if state.requests >= 2:
                self.reject(409, "fixture accepts exactly two requests")
                return
            authorization = self.headers.get("Authorization")
            if authorization not in (None, "Bearer", "Bearer "):
                state.user_credential_header_seen = True
                self.reject(400, "non-empty Authorization credential is forbidden")
                return
            state.empty_authorization_seen = authorization is not None
            for forbidden in ("X-Api-Key", "Api-Key", "X-GitHub-Token", "Github-Token"):
                if self.headers.get(forbidden):
                    state.user_credential_header_seen = True
                    self.reject(400, f"credential header {forbidden} is forbidden")
                    return
            if self.headers.get("Content-Encoding", "identity").lower() != "identity":
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
            if not request_tools_include_only_bash(body):
                self.reject(400, "request does not advertise only the required bash tool")
                return

            request_index = state.requests
            if request_index == 0:
                state.advertised_bash = True
                if find_tool_output(body, state.call_id) is not None:
                    self.reject(400, "first request unexpectedly contains tool output")
                    return
            else:
                output = find_tool_output(body, state.call_id)
                if output is None:
                    self.reject(400, "second request is missing matching bash tool output")
                    return
                state.tool_output_seen = True
                state.denial_output_seen = EXPECTED_DENIAL in output
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
                    if state.mode == "protected" and output != EXPECTED_DENIAL:
                        self.reject(400, "protected tool output is not the exact hook denial")
                        return
                    if state.mode == "control":
                        if state.denial_output_seen or "completed with exit code 0" not in output:
                            self.reject(400, "control tool output does not prove successful execution")
                            return

            final_text = None
            if (
                state.scenario == AWM_CHAIN_SCENARIO
                and state.awm_expectation == "missing-predecessor"
                and request_index == 1
            ):
                final_text = AWM_MISSING_PREDECESSOR_FINAL_TEXT
            payload = completion_payload(state.fixture, request_index, final_text)
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
            print("Copilot Chat Completions AWM-chain fixture valid")
            return 0
        print("Copilot Chat Completions fixture valid")
        return 0
    if args.mode is None or args.ready is None or args.state is None:
        fail("--mode, --ready, and --state are required when serving")
    if args.scenario == AWM_CHAIN_SCENARIO and args.mode != "control":
        fail("--mode control is required for the awm-chain scenario")
    if args.timeout <= 0 or args.timeout > 120:
        fail("--timeout must be greater than 0 and at most 120 seconds")
    for output in (args.ready, args.state):
        if output.exists() or output.is_symlink():
            fail(f"output path already exists: {output}")
        if not output.parent.is_dir():
            fail(f"output parent is not a directory: {output.parent}")

    if args.scenario == AWM_CHAIN_SCENARIO:
        request_hygiene = request_hygiene_guard_from_args(args)
        awm_expectation = awm_expectation_from_args(args)
    else:
        request_hygiene = None
        awm_expectation = "success"
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
        print(f"Copilot fixture server failed: {state.error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

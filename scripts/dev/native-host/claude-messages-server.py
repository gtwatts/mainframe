#!/usr/bin/env python3
"""Loopback-only Anthropic Messages fixture for Claude Code certification."""

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
EXPECTED_MODEL = "mainframe-claude-certification"
EXPECTED_CALL_ID = "mainframe-claude-destroy"
EXPECTED_COMMAND = "tofu destroy -auto-approve"
EXPECTED_DESCRIPTION = "Run the native-host certification sentinel."
EXPECTED_FINAL_TEXT = "MAINFRAME native host certification observed the policy result."
EXPECTED_AUTHORIZATION = "Bearer mainframe-certification-placeholder"
EXPECTED_DENIAL = (
    "MAINFRAME agent gateway blocked the tool call: "
    "risk=high rule=terraform-destroy"
)
EXPECTED_CONTROL_RESULT = "(Bash completed with no output)"
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


AWM_CHAIN_CALL_ID = "mainframe-claude-awm-chain"
AWM_CHAIN_DESCRIPTION = "Run the MAINFRAME AWM chain step for Claude."
AWM_CHAIN_FINAL_TEXT = "MAINFRAME AWM chain step completed for Claude."
AWM_CHAIN_SUCCESS_MARKER = "MAINFRAME_AWM_CHAIN_OK:claude"
AWM_MISSING_PREDECESSOR_MARKER = "MAINFRAME_AWM_MISSING_PREDECESSOR"
AWM_MISSING_PREDECESSOR_EXIT_CODE = 42
AWM_MISSING_PREDECESSOR_FINAL_TEXT = (
    "MAINFRAME AWM missing predecessor rejected for Claude."
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
        "final_text": EXPECTED_FINAL_TEXT,
    },
    AWM_CHAIN_SCENARIO: {
        "schema_version": 1,
        "call_id": AWM_CHAIN_CALL_ID,
        "command": AWM_CHAIN_COMMAND,
        "description": AWM_CHAIN_DESCRIPTION,
        "final_text": AWM_CHAIN_FINAL_TEXT,
    },
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"invalid Claude fixture server input: {message}")


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
            fail("fixture is not the exact Claude AWM-chain conversation")
        fail("fixture is not the exact Claude certification conversation")
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
    if not isinstance(tool, dict) or tool.get("name") != "Bash":
        return False
    schema = tool.get("input_schema")
    properties = schema.get("properties") if isinstance(schema, dict) else None
    required = schema.get("required") if isinstance(schema, dict) else None
    return (
        isinstance(properties, dict)
        and isinstance(properties.get("command"), dict)
        and properties["command"].get("type") == "string"
        and isinstance(required, list)
        and "command" in required
    )


def find_tool_result(
    body: dict[str, Any], call_id: str = EXPECTED_CALL_ID
) -> tuple[str | None, bool | None]:
    messages = body.get("messages")
    if not isinstance(messages, list):
        return None, None
    for message in messages:
        if not isinstance(message, dict) or message.get("role") != "user":
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if (
                isinstance(block, dict)
                and block.get("type") == "tool_result"
                and block.get("tool_use_id") == call_id
            ):
                output = block.get("content")
                if isinstance(output, str):
                    rendered = output
                elif output is None:
                    rendered = ""
                else:
                    rendered = json.dumps(output, sort_keys=True, separators=(",", ":"))
                is_error = block.get("is_error")
                return rendered, is_error if isinstance(is_error, bool) else False
    return None, None


def awm_chain_output_succeeded(output: str, is_error: bool) -> bool:
    return (
        not is_error
        and EXPECTED_DENIAL not in output
        and AWM_CHAIN_SUCCESS_MARKER in output
    )


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


def awm_missing_predecessor_output_succeeded(
    output: str, is_error: bool
) -> bool:
    return (
        is_error
        and EXPECTED_DENIAL not in output
        and awm_missing_predecessor_marker_seen(output)
        and awm_exit_code_42_seen(output)
    )


def sse_event(kind: str, value: dict[str, Any]) -> str:
    return f"event: {kind}\ndata: {json.dumps(value, separators=(',', ':'))}\n\n"


def response_payload(
    fixture: dict[str, Any],
    request_index: int,
    final_text: str | None = None,
) -> bytes:
    message_id = f"msg_mainframe_{request_index + 1}"
    events: list[tuple[str, dict[str, Any]]] = [
        (
            "message_start",
            {
                "type": "message_start",
                "message": {
                    "id": message_id,
                    "type": "message",
                    "role": "assistant",
                    "content": [],
                    "model": EXPECTED_MODEL,
                    "stop_reason": None,
                    "stop_sequence": None,
                    "usage": {"input_tokens": 1, "output_tokens": 1},
                },
            },
        )
    ]
    if request_index == 0:
        arguments = json.dumps(
            {
                "command": fixture["command"],
                "description": fixture["description"],
            },
            separators=(",", ":"),
        )
        events.extend(
            [
                (
                    "content_block_start",
                    {
                        "type": "content_block_start",
                        "index": 0,
                        "content_block": {
                            "type": "tool_use",
                            "id": fixture["call_id"],
                            "name": "Bash",
                            "input": {},
                        },
                    },
                ),
                (
                    "content_block_delta",
                    {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {
                            "type": "input_json_delta",
                            "partial_json": arguments,
                        },
                    },
                ),
                (
                    "content_block_stop",
                    {"type": "content_block_stop", "index": 0},
                ),
                (
                    "message_delta",
                    {
                        "type": "message_delta",
                        "delta": {"stop_reason": "tool_use", "stop_sequence": None},
                        "usage": {"output_tokens": 20},
                    },
                ),
            ]
        )
    else:
        events.extend(
            [
                (
                    "content_block_start",
                    {
                        "type": "content_block_start",
                        "index": 0,
                        "content_block": {"type": "text", "text": ""},
                    },
                ),
                (
                    "content_block_delta",
                    {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {
                            "type": "text_delta",
                            "text": final_text or fixture["final_text"],
                        },
                    },
                ),
                (
                    "content_block_stop",
                    {"type": "content_block_stop", "index": 0},
                ),
                (
                    "message_delta",
                    {
                        "type": "message_delta",
                        "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                        "usage": {"output_tokens": 10},
                    },
                ),
            ]
        )
    events.append(("message_stop", {"type": "message_stop"}))
    return "".join(sse_event(kind, value) for kind, value in events).encode("utf-8")


class FixtureState:
    def __init__(
        self,
        mode: str,
        fixture: dict[str, Any],
        scenario: str = DESTROY_SCENARIO,
        awm_expectation: str = "success",
        request_hygiene: RequestHygieneGuard | None = None,
        protected_hook_command: str | None = None,
    ) -> None:
        self.mode = mode
        self.fixture = fixture
        self.scenario = scenario
        self.call_id = FIXTURE_SCENARIOS[scenario]["call_id"]
        self.awm_expectation = awm_expectation
        self.request_hygiene = request_hygiene
        self.protected_hook_command = protected_hook_command
        self.requests = 0
        self.advertised_bash = False
        self.tool_result_seen = False
        self.tool_result_is_error = False
        self.denial_output_seen = False
        self.success_marker_seen = False
        self.missing_predecessor_marker_seen = False
        self.tool_result_nonzero = False
        self.placeholder_authorization_seen = False
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
            "tool_result_seen": self.tool_result_seen,
            "tool_result_is_error": self.tool_result_is_error,
            "denial_output_seen": self.denial_output_seen,
            "placeholder_authorization_seen": self.placeholder_authorization_seen,
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
            payload = json.dumps(
                {"type": "error", "error": {"type": "invalid_request_error", "message": message}},
                separators=(",", ":"),
            ).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            self.close_connection = True

        def do_GET(self) -> None:  # noqa: N802
            self.reject(405, "only POST /v1/messages is allowed")

        def do_PUT(self) -> None:  # noqa: N802
            self.reject(405, "only POST /v1/messages is allowed")

        def do_POST(self) -> None:  # noqa: N802
            if self.path != "/v1/messages?beta=true":
                self.reject(
                    404,
                    "request path must be /v1/messages?beta=true; "
                    f"got {self.path!r}",
                )
                return
            if state.requests >= 2:
                self.reject(409, "fixture accepts exactly two requests")
                return
            authorization = self.headers.get("Authorization")
            if authorization != EXPECTED_AUTHORIZATION:
                state.user_credential_header_seen = bool(authorization)
                self.reject(400, "exact placeholder Authorization header is required")
                return
            state.placeholder_authorization_seen = True
            for forbidden in (
                "X-Api-Key",
                "Api-Key",
                "X-Claude-Code-Oauth-Token",
                "Cookie",
                "Proxy-Authorization",
                "X-Amz-Security-Token",
                "X-Amz-Credential",
                "X-Goog-Api-Key",
                "X-Goog-Credentials",
            ):
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
                names = [tool.get("name") for tool in body.get("tools", []) if isinstance(tool, dict)]
                self.reject(400, f"request does not advertise only Bash; got {names!r}")
                return

            request_index = state.requests
            if request_index == 0:
                state.advertised_bash = True
                if find_tool_result(body, state.call_id)[0] is not None:
                    self.reject(400, "first request unexpectedly contains a tool result")
                    return
            else:
                output, is_error = find_tool_result(body, state.call_id)
                if output is None:
                    self.reject(400, "second request is missing the matching Bash tool result")
                    return
                state.tool_result_seen = True
                state.tool_result_is_error = is_error is True
                state.denial_output_seen = EXPECTED_DENIAL in output
                if state.scenario == AWM_CHAIN_SCENARIO:
                    if state.awm_expectation == "missing-predecessor":
                        state.missing_predecessor_marker_seen = (
                            awm_missing_predecessor_marker_seen(output)
                        )
                        state.tool_result_nonzero = (
                            state.tool_result_is_error
                            and awm_exit_code_42_seen(output)
                        )
                        if not awm_missing_predecessor_output_succeeded(
                            output, state.tool_result_is_error
                        ):
                            self.reject(
                                400,
                                "AWM-chain result is missing the exact "
                                "missing-predecessor marker or exit code 42",
                            )
                            return
                    else:
                        state.success_marker_seen = AWM_CHAIN_SUCCESS_MARKER in output
                        if not awm_chain_output_succeeded(
                            output, state.tool_result_is_error
                        ):
                            self.reject(
                                400,
                                "AWM-chain result is missing the exact success marker",
                            )
                            return
                else:
                    if state.mode == "protected":
                        expected_protected_result = (
                            "PreToolUse:Bash hook error: "
                            f"[{state.protected_hook_command}]: "
                            f"{EXPECTED_DENIAL}\n"
                        )
                        if (
                            not state.tool_result_is_error
                            or output != expected_protected_result
                        ):
                            self.reject(400, "protected result is not MAINFRAME's Bash denial")
                            return
                    elif state.tool_result_is_error or output != EXPECTED_CONTROL_RESULT:
                        self.reject(400, "control result does not prove successful Bash execution")
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
    parser.add_argument("--protected-hook-command")
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
            print("Claude Messages AWM-chain fixture valid")
            return 0
        print("Claude Messages fixture valid")
        return 0
    if args.mode is None or args.ready is None or args.state is None:
        fail("--mode, --ready, and --state are required when serving")
    if args.scenario == AWM_CHAIN_SCENARIO and args.mode != "control":
        fail("--mode control is required for the awm-chain scenario")
    if (
        args.scenario == DESTROY_SCENARIO
        and args.mode == "protected"
        and not args.protected_hook_command
    ):
        fail("--protected-hook-command is required for protected destroy serving")
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
        protected_hook_command=args.protected_hook_command,
    )
    server = LoopbackHTTPServer(("127.0.0.1", 0), handler_for(state))
    server.timeout = 0.25
    port = int(server.server_address[1])
    write_private_json(
        args.ready, {"schema_version": 1, "address": "127.0.0.1", "port": port}
    )

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
        print(f"Claude fixture server failed: {state.error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

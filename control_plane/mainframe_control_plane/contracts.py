"""Strict, fixed-root stable-core contract registry.

The public loader derives the release root from this installed module. It never
uses argv, environment variables, or the current working directory.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import stat
from types import MappingProxyType
from typing import Any, Dict, List, Mapping, Tuple, Union

from .errors import ExecutionDenied, RegistryCorruption
from .kernel import PolicyEvaluation, PolicyRequest

JsonValue = Union[None, bool, int, float, str, List["JsonValue"], Dict[str, "JsonValue"]]


_FIXED_RELEASE_ROOT = Path(__file__).resolve().parents[2]
_TOP_KEYS = frozenset(
    (
        "contract_count",
        "contracts",
        "manifest_version",
        "modules",
        "name_index",
        "profile",
        "schema_version",
        "version",
    )
)
_CONTRACT_KEYS = frozenset(
    (
        "bash_identifier",
        "call_shape",
        "capabilities",
        "contract_status",
        "effects",
        "input_schema",
        "name",
        "output_limit",
        "owner",
        "platforms",
        "profiles",
        "result",
        "timeout_ms",
    )
)
_CANONICAL_ID = re.compile(
    r"^mf:[a-z][a-z0-9-]*:[A-Za-z0-9_-]+:[a-z_][a-z0-9_]*$"
)
_NAME = re.compile(r"^[a-z_][a-z0-9_]*$")
_OWNER = re.compile(r"^[A-Za-z0-9_-]+$")
_FIELD = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
_VERSION = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][A-Za-z0-9.-]+)?$"
)
_EXPECTED_CONTRACT_COUNT = 26
_MAX_REGISTRY_BYTES = 4 * 1024 * 1024
STABLE_CORE_POLICY = "stable-core-v1"


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _trusted_file_bytes(path: Path) -> bytes:
    flags = os.O_RDONLY | os.O_CLOEXEC
    if not hasattr(os, "O_NOFOLLOW"):
        raise RegistryCorruption("symlink-safe registry loading is unavailable")
    flags |= os.O_NOFOLLOW
    try:
        fd = os.open(str(path), flags)
    except OSError as exc:
        raise RegistryCorruption("trusted release file is unavailable") from exc
    try:
        metadata = os.fstat(fd)
        permitted_owners = {0}
        if hasattr(os, "geteuid"):
            permitted_owners.add(os.geteuid())
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid not in permitted_owners
            or stat.S_IMODE(metadata.st_mode) & 0o7022
            or metadata.st_nlink != 1
            or metadata.st_size > _MAX_REGISTRY_BYTES
        ):
            raise RegistryCorruption("trusted release file ownership or mode is unsafe")
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            total += len(chunk)
            if total > _MAX_REGISTRY_BYTES:
                raise RegistryCorruption("trusted release file exceeds the size limit")
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        os.close(fd)


def _current_platform() -> str:
    value = platform.system()
    if value == "Darwin":
        return "macos"
    if value == "Linux":
        return "linux"
    raise RegistryCorruption("the host platform is unsupported")


def _require_object(value: Any, label: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise RegistryCorruption("{} must be an object".format(label))
    return value


def _require_exact_keys(
    value: Mapping[str, Any], keys: frozenset[str], label: str
) -> None:
    if set(value) != keys:
        raise RegistryCorruption("{} has unexpected fields".format(label))


@dataclass(frozen=True)
class StableCoreContract:
    canonical_id: str
    name: str
    owner: str
    effect: str
    platforms: Tuple[str, ...]
    input_schema: Dict[str, Any]
    timeout_ms: int
    output_limit: int
    result_kind: str
    digest: str


@dataclass(frozen=True)
class StableCoreRegistry:
    version: str
    digest: str
    contracts: Mapping[str, StableCoreContract]

    def contract(self, canonical_id: str) -> StableCoreContract:
        if not isinstance(canonical_id, str) or _CANONICAL_ID.fullmatch(canonical_id) is None:
            raise ExecutionDenied("canonical stable-core ID is malformed")
        try:
            contract = self.contracts[canonical_id]
        except KeyError as exc:
            raise ExecutionDenied("canonical stable-core ID is not reviewed") from exc
        if _current_platform() not in contract.platforms:
            raise ExecutionDenied("canonical stable-core ID is unavailable on this platform")
        return contract

    def normalize_input(
        self, canonical_id: str, tool_input: Mapping[str, JsonValue]
    ) -> Dict[str, JsonValue]:
        contract = self.contract(canonical_id)
        if not isinstance(tool_input, dict):
            raise ExecutionDenied("canonical tool input must be an object")
        schema = contract.input_schema
        properties = schema["properties"]
        if not set(tool_input).issubset(properties):
            raise ExecutionDenied("canonical tool input contains undeclared fields")
        normalized: Dict[str, JsonValue] = {}
        required = set(schema["required"])
        for field, specification in properties.items():
            if field in tool_input:
                value = tool_input[field]
            elif "default" in specification:
                value = specification["default"]
            elif field in required:
                raise ExecutionDenied(
                    "canonical tool input is missing required field {}".format(field)
                )
            else:  # registry validation guarantees optional fields have defaults
                raise ExecutionDenied("canonical tool input cannot be normalized")
            if specification["type"] == "string":
                if not isinstance(value, str) or "\x00" in value:
                    raise ExecutionDenied(
                        "canonical input field {} must be a NUL-free string".format(field)
                    )
                if "enum" in specification and value not in specification["enum"]:
                    raise ExecutionDenied(
                        "canonical input field {} is outside its enum".format(field)
                    )
                normalized[field] = value
            else:
                if not isinstance(value, list) or any(
                    not isinstance(item, str) or "\x00" in item for item in value
                ):
                    raise ExecutionDenied(
                        "canonical input field {} must be NUL-free strings".format(field)
                    )
                normalized[field] = list(value)
        # Round-trip rejects non-JSON values and creates a detached exact object.
        try:
            detached = json.loads(_canonical_json(normalized).decode("utf-8"))
        except (TypeError, ValueError, UnicodeError) as exc:
            raise ExecutionDenied("canonical tool input is not UTF-8 JSON") from exc
        if not isinstance(detached, dict):
            raise ExecutionDenied("canonical tool input did not normalize to an object")
        return detached


class FixedStableCoreEvaluator:
    """Installed evaluator for the exact reviewed stable-core snapshot."""

    def __init__(self, registry: StableCoreRegistry) -> None:
        self._registry = registry

    def __call__(self, request: PolicyRequest) -> PolicyEvaluation:
        authority = "policy-engine:fixed-stable-core-v1"
        if request.policy != STABLE_CORE_POLICY or request.effect != "read_only":
            return PolicyEvaluation(
                "deny", authority, "request is outside the fixed stable-core policy"
            )
        try:
            normalized = self._registry.normalize_input(request.tool, request.tool_input)
        except ExecutionDenied:
            return PolicyEvaluation(
                "deny", authority, "tool or input is outside the reviewed registry"
            )
        if normalized != request.tool_input or request.timeout_at is None:
            return PolicyEvaluation(
                "deny", authority, "request does not match its normalized contract"
            )
        return PolicyEvaluation(
            "allow", authority, "fixed reviewed stable-core policy allowed the call"
        )


def _validate_property(
    field: str, value: Any, required: set[str]
) -> Dict[str, Any]:
    if _FIELD.fullmatch(field) is None:
        raise RegistryCorruption("contract input field name is malformed")
    specification = _require_object(value, "contract input property")
    property_type = specification.get("type")
    allowed = {"type", "default", "enum"} if property_type == "string" else {
        "type",
        "default",
        "items",
    }
    if property_type not in ("string", "array") or not set(specification).issubset(allowed):
        raise RegistryCorruption("contract input property is not a closed string schema")
    if field not in required and "default" not in specification:
        raise RegistryCorruption("optional contract input fields require defaults")
    if property_type == "string":
        if "default" in specification and (
            not isinstance(specification["default"], str)
            or "\x00" in specification["default"]
        ):
            raise RegistryCorruption("string default is invalid")
        if "enum" in specification:
            enum = specification["enum"]
            if (
                not isinstance(enum, list)
                or not enum
                or len(enum) != len(set(enum))
                or any(not isinstance(item, str) or "\x00" in item for item in enum)
                or (
                    "default" in specification
                    and specification["default"] not in enum
                )
            ):
                raise RegistryCorruption("string enum is invalid")
    else:
        if specification.get("items") != {"type": "string"}:
            raise RegistryCorruption("array contract fields must contain strings")
        if "default" in specification and (
            not isinstance(specification["default"], list)
            or any(
                not isinstance(item, str) or "\x00" in item
                for item in specification["default"]
            )
        ):
            raise RegistryCorruption("array default is invalid")
    return specification


def _validate_contract(
    canonical_id: str,
    raw: Any,
    modules: Mapping[str, Any],
    name_index: Mapping[str, Any],
) -> StableCoreContract:
    if _CANONICAL_ID.fullmatch(canonical_id) is None:
        raise RegistryCorruption("canonical stable-core ID is malformed")
    value = _require_object(raw, "stable-core contract")
    _require_exact_keys(value, _CONTRACT_KEYS, "stable-core contract")
    name = value["name"]
    owner = value["owner"]
    if (
        not isinstance(name, str)
        or _NAME.fullmatch(name) is None
        or not isinstance(owner, str)
        or _OWNER.fullmatch(owner) is None
        or name_index.get(name) != canonical_id
        or modules.get(owner) != {"file": "lib/{}.sh".format(owner)}
    ):
        raise RegistryCorruption("stable-core contract name/owner parity is invalid")
    if value["contract_status"] != "reviewed" or value["bash_identifier"] is not True:
        raise RegistryCorruption("stable-core contract is not reviewed")
    effects = value["effects"]
    if not isinstance(effects, list) or len(effects) != 1 or effects[0] not in ("pure", "read"):
        raise RegistryCorruption("stable-core contract effect is not read-only")
    if value["capabilities"] != []:
        raise RegistryCorruption("stable-core contracts may not declare capabilities")
    platforms = value["platforms"]
    if (
        not isinstance(platforms, list)
        or not platforms
        or len(platforms) != len(set(platforms))
        or any(item not in ("linux", "macos") for item in platforms)
    ):
        raise RegistryCorruption("stable-core contract platforms are invalid")
    profiles = value["profiles"]
    if not isinstance(profiles, list) or "stable-core" not in profiles:
        raise RegistryCorruption("stable-core contract profile is missing")
    timeout_ms = value["timeout_ms"]
    output_limit = value["output_limit"]
    if (
        type(timeout_ms) is not int
        or not 1 <= timeout_ms <= 30000
        or type(output_limit) is not int
        or not 1 <= output_limit <= 1048576
    ):
        raise RegistryCorruption("stable-core contract bounds are invalid")
    result = _require_object(value["result"], "stable-core result")
    if set(result) != {"kind"} or result["kind"] not in ("stdout", "exit", "none"):
        raise RegistryCorruption("stable-core result contract is invalid")
    schema = _require_object(value["input_schema"], "stable-core input schema")
    if set(schema) != {"additionalProperties", "properties", "required", "type"}:
        raise RegistryCorruption("stable-core input schema fields are invalid")
    if schema["type"] != "object" or schema["additionalProperties"] is not False:
        raise RegistryCorruption("stable-core input schema must be a closed object")
    properties = _require_object(schema["properties"], "stable-core properties")
    required_list = schema["required"]
    if (
        not isinstance(required_list, list)
        or any(not isinstance(item, str) or _FIELD.fullmatch(item) is None for item in required_list)
        or len(required_list) != len(set(required_list))
        or not set(required_list).issubset(properties)
    ):
        raise RegistryCorruption("stable-core required fields are invalid")
    required = set(required_list)
    normalized_properties = {
        field: _validate_property(field, specification, required)
        for field, specification in properties.items()
    }
    call_shape = _require_object(value["call_shape"], "stable-core call shape")
    if set(call_shape) != {"arguments", "kind"} or call_shape["kind"] != "argv":
        raise RegistryCorruption("stable-core call shape is invalid")
    arguments = call_shape["arguments"]
    if not isinstance(arguments, list) or len(arguments) > 64:
        raise RegistryCorruption("stable-core argv mapping is invalid")
    observed_fields = []
    for index, argument_raw in enumerate(arguments):
        argument = _require_object(argument_raw, "stable-core argument")
        if set(argument) != {"field", "mode"}:
            raise RegistryCorruption("stable-core argument fields are invalid")
        field = argument["field"]
        mode = argument["mode"]
        if field not in normalized_properties or (
            normalized_properties[field]["type"] == "string" and mode != "scalar"
        ) or (
            normalized_properties[field]["type"] == "array" and mode != "spread"
        ):
            raise RegistryCorruption("stable-core argv field mapping is invalid")
        if mode == "spread" and index != len(arguments) - 1:
            raise RegistryCorruption("stable-core spread argument must be last")
        observed_fields.append(field)
    if len(observed_fields) != len(set(observed_fields)) or set(observed_fields) != set(properties):
        raise RegistryCorruption("stable-core argv mapping lacks exact schema parity")
    # Required scalar fields cannot follow an optional scalar positional gap.
    optional_scalar_seen = False
    for argument in arguments:
        field = argument["field"]
        if argument["mode"] != "scalar":
            continue
        if field not in required:
            optional_scalar_seen = True
        elif optional_scalar_seen:
            raise RegistryCorruption("stable-core argv mapping contains a positional gap")
    detached_schema = json.loads(_canonical_json(schema).decode("utf-8"))
    digest = hashlib.sha256(_canonical_json(value)).hexdigest()
    return StableCoreContract(
        canonical_id,
        name,
        owner,
        effects[0],
        tuple(platforms),
        detached_schema,
        timeout_ms,
        output_limit,
        result["kind"],
        digest,
    )


def _load_stable_core_registry_from_root(release_root: Path) -> StableCoreRegistry:
    root = Path(release_root)
    if not root.is_absolute():
        raise RegistryCorruption("release root must be an absolute fixed path")
    version_bytes = _trusted_file_bytes(root / "VERSION")
    try:
        version_text = version_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RegistryCorruption("VERSION is not UTF-8") from exc
    version = version_text[:-1] if version_text.endswith("\n") else version_text
    if "\n" in version or "\r" in version or _VERSION.fullmatch(version) is None:
        raise RegistryCorruption("VERSION is not one canonical release version")
    index_bytes = _trusted_file_bytes(root / "INVOCATION_INDEX.json")
    try:
        raw = json.loads(index_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RegistryCorruption("stable-core registry is not valid UTF-8 JSON") from exc
    value = _require_object(raw, "stable-core registry")
    _require_exact_keys(value, _TOP_KEYS, "stable-core registry")
    if (
        type(value["schema_version"]) is not int
        or value["schema_version"] != 1
        or type(value["manifest_version"]) is not int
        or value["manifest_version"] != 1
        or value["version"] != version
        or value["profile"] != "stable-core"
        or type(value["contract_count"]) is not int
        or value["contract_count"] != _EXPECTED_CONTRACT_COUNT
    ):
        raise RegistryCorruption("stable-core registry header is invalid")
    contracts_raw = _require_object(value["contracts"], "stable-core contracts")
    modules = _require_object(value["modules"], "stable-core modules")
    name_index = _require_object(value["name_index"], "stable-core name index")
    if (
        len(contracts_raw) != _EXPECTED_CONTRACT_COUNT
        or len(name_index) != _EXPECTED_CONTRACT_COUNT
        or not modules
    ):
        raise RegistryCorruption("stable-core registry count is invalid")
    for owner, module in modules.items():
        if (
            not isinstance(owner, str)
            or _OWNER.fullmatch(owner) is None
            or module != {"file": "lib/{}.sh".format(owner)}
        ):
            raise RegistryCorruption("stable-core module registry is invalid")
    if any(
        not isinstance(name, str)
        or _NAME.fullmatch(name) is None
        or not isinstance(canonical_id, str)
        or _CANONICAL_ID.fullmatch(canonical_id) is None
        for name, canonical_id in name_index.items()
    ):
        raise RegistryCorruption("stable-core name index is invalid")
    contracts = {
        canonical_id: _validate_contract(canonical_id, contract, modules, name_index)
        for canonical_id, contract in contracts_raw.items()
    }
    if set(name_index.values()) != set(contracts):
        raise RegistryCorruption("stable-core name index lacks exact contract parity")
    digest = hashlib.sha256(_canonical_json(value)).hexdigest()
    return StableCoreRegistry(version, digest, MappingProxyType(contracts))


def load_fixed_stable_core_registry() -> StableCoreRegistry:
    """Load only the registry beside the installed fixed control-plane root."""
    return _load_stable_core_registry_from_root(_FIXED_RELEASE_ROOT)

"""Deny-by-default invocation authorization for the MAINFRAME MCP package.

Every tool invocation must pass through this gate before reaching the bash
executor. Anything not explicitly permitted is rejected:

  1. The tool name must carry the advertised ``mainframe_`` prefix.
  2. The function name must be a valid bash identifier (no metacharacters,
     spaces, path separators, or command substitutions).
  3. The function must be registered in FUNCTIONS.json (registry membership).
  4. The function must be inside the active tier's advertised tool set, so a
     caller cannot invoke tools that ``list_tools`` did not advertise.

No exception to these rules exists; unknown names never reach a shell.
"""

import re
from typing import Any, Dict, Tuple

# Bash function names are identifiers. Restricting to this charset denies
# shell metacharacters (; | & $ ` > < ( ) { } etc.), whitespace, path
# separators, and glob characters by construction.
FUNCTION_NAME_RE = re.compile(r'^[a-z_][a-z0-9_]*$')

TOOL_PREFIX = 'mainframe_'

# Rejection reason codes (stable strings for tests and log correlation).
REASON_UNKNOWN_TOOL = 'unknown_tool'
REASON_INVALID_NAME = 'invalid_function_name'
REASON_NOT_REGISTERED = 'function_not_registered'
REASON_TIER_VIOLATION = 'function_outside_active_tier'
REASON_INVALID_TIER = 'invalid_active_tier'
REASON_INVALID_ARGUMENTS = 'invalid_arguments'

VALID_TIERS = frozenset({'stable-core', 'core', 'full'})
DEFAULT_TIER = 'stable-core'

# Shared MCP surface rules. The canonical manifest generator imports the same
# predicate so its `core` profile cannot drift from ToolRegistry filtering.
MCP_CORE_CATEGORIES = frozenset({
    'data',
    'strings',
    'validation',
    'ai',
    'files',
    'output',
})
MCP_CORE_PREFIXES = (
    'json_',
    'validate_',
    'ensure_',
    'atomic_',
    'output_',
    'usop_',
    'trim_',
    'to_',
    'is_',
    'array_',
)
REVIEWED_VARIADIC_CALL_SHAPES = frozenset({'array_join'})
UNREVIEWED_CALL_SHAPES = frozenset({
    'array_count', 'array_filter', 'array_first', 'array_get',
    'array_intersect', 'array_last', 'array_length', 'array_reverse',
    'array_slice', 'array_sum', 'array_unique',
    'collection_count', 'collection_filter', 'collection_first',
    'collection_intersect', 'collection_last', 'collection_length',
    'collection_reverse', 'collection_slice', 'collection_sum',
    'collection_unique', 'safe_array_get',
    'awm_compress', 'awm_handoff_prepare', 'awm_handoff_accept',
    'awm_stream_compress', 'awm_protocol_handoff_prepare',
    'awm_protocol_handoff_accept',
})


class AuthorizationError(Exception):
    """Raised when an invocation is denied by authorization policy."""

    def __init__(self, reason: str, detail: str):
        self.reason = reason
        self.detail = detail
        super().__init__(f'{reason}: {detail}')


def validate_function_name(func_name: str) -> None:
    """Reject any function name that is not a plain bash identifier.

    This is the primary defense against external-executable invocation and
    shell metacharacter injection, and is safe to call from any layer.
    """
    if not isinstance(func_name, str) or not FUNCTION_NAME_RE.match(func_name):
        raise AuthorizationError(
            REASON_INVALID_NAME,
            f'function name {func_name!r} is not a valid bash identifier',
        )


def _tier_allowed_names(registry, tier: str) -> set:
    """Compute the set of function names advertised for the active tier."""
    allowed = set()
    for tool in registry.generate_all_tools(tier=tier):
        name = tool.get('name', '')
        if name.startswith(TOOL_PREFIX):
            allowed.add(name[len(TOOL_PREFIX):])
    return allowed


def authorize_invocation(registry, tool_name: str, tier: str = DEFAULT_TIER) -> Dict[str, Any]:
    """Authorize an MCP tool invocation; return function metadata if allowed.

    Args:
        registry: Loaded ToolRegistry instance.
        tool_name: Raw tool name from the MCP client (e.g. 'mainframe_json_get').
        tier: Active tier ('core' or 'full').

    Returns:
        The registry metadata dict for the authorized function.

    Raises:
        AuthorizationError: always, for any name not explicitly permitted.
    """
    if tier not in VALID_TIERS:
        raise AuthorizationError(
            REASON_INVALID_TIER,
            f'active tier {tier!r} is invalid; expected one of {sorted(VALID_TIERS)}',
        )

    if not isinstance(tool_name, str) or not tool_name.startswith(TOOL_PREFIX):
        raise AuthorizationError(
            REASON_UNKNOWN_TOOL,
            f'tool {tool_name!r} is not an advertised MAINFRAME tool',
        )

    func_name = tool_name[len(TOOL_PREFIX):]

    # Charset gate: denies metacharacter injection and path-like names before
    # any registry lookup.
    validate_function_name(func_name)

    # Registry membership gate: only declared MAINFRAME functions may run,
    # which also denies external executables (ls, id, uname, ...).
    func = registry.get_function(func_name)
    if func is None:
        raise AuthorizationError(
            REASON_NOT_REGISTERED,
            f'function {func_name!r} is not registered in FUNCTIONS.json',
        )

    # Tier closure gate: the function must be inside the set of tools that
    # list_tools advertised for the active tier.
    if func_name not in _tier_allowed_names(registry, tier):
        raise AuthorizationError(
            REASON_TIER_VIOLATION,
            f'function {func_name!r} is outside the active {tier!r} tier',
        )

    return func


def _invalid_arguments(detail: str) -> AuthorizationError:
    """Build a stable, non-value-bearing argument rejection."""
    return AuthorizationError(REASON_INVALID_ARGUMENTS, detail)


def _ordered_parameters(func: Dict[str, Any]) -> list[Dict[str, Any]]:
    """Return declared parameters in canonical positional order.

    Positional metadata is part of the authorization boundary: silently
    accepting duplicate or incomplete positions could shift a caller's value
    into a different shell parameter. Fail closed when the registry cannot
    describe a contiguous argv layout.
    """
    params = func.get('params', [])
    if not isinstance(params, list):
        raise _invalid_arguments('function parameter metadata is malformed')
    if not params:
        return []

    names = []
    positions = []
    for param in params:
        if not isinstance(param, dict):
            raise _invalid_arguments('function parameter metadata is malformed')

        name = param.get('name')
        position = param.get('position')
        if not isinstance(name, str) or not name:
            raise _invalid_arguments('function parameter metadata has an invalid name')
        if (
            not isinstance(position, int)
            or isinstance(position, bool)
            or position < 1
        ):
            raise _invalid_arguments('function parameter metadata has an invalid position')

        names.append(name)
        positions.append(position)

    if len(set(names)) != len(names):
        raise _invalid_arguments('function parameter metadata has duplicate names')
    if len(set(positions)) != len(positions):
        raise _invalid_arguments('function parameter metadata has duplicate positions')

    expected_positions = list(range(1, len(params) + 1))
    if sorted(positions) != expected_positions:
        raise _invalid_arguments('function parameter metadata has a positional gap')

    return sorted(params, key=lambda param: param['position'])


def has_preparable_call_shape(func: Dict[str, Any]) -> bool:
    """Return whether function metadata can be mapped to argv without guessing."""
    try:
        _ordered_parameters(func)
        return True
    except AuthorizationError:
        return False


def normalize_invocation_metadata(
    func_name: str, func: Dict[str, Any]
) -> Dict[str, Any]:
    """Apply the small reviewed MCP call-shape exception set."""
    if (
        func_name not in REVIEWED_VARIADIC_CALL_SHAPES
        or func.get('mcp_call_shape') == 'reviewed_variadic'
    ):
        return func

    normalized = dict(func)
    normalized['registry_params'] = func.get('params', [])
    normalized['params'] = []
    normalized['mcp_call_shape'] = 'reviewed_variadic'
    return normalized


def is_mcp_advertisable(func_name: str, func: Dict[str, Any]) -> bool:
    """Return whether a registry function has an authorized MCP call shape."""
    if func_name in UNREVIEWED_CALL_SHAPES:
        return False
    try:
        validate_function_name(func_name)
    except AuthorizationError:
        return False
    return has_preparable_call_shape(
        normalize_invocation_metadata(func_name, func)
    )


def is_mcp_core_export(
    func_name: str, category: str, func: Dict[str, Any]
) -> bool:
    """Canonical MCP core-closure predicate shared with manifest generation."""
    selected = category in MCP_CORE_CATEGORIES or func_name.startswith(
        MCP_CORE_PREFIXES
    )
    return selected and is_mcp_advertisable(func_name, func)


def prepare_invocation_arguments(
    func: Dict[str, Any], arguments: Any
) -> Tuple[str, ...]:
    """Validate MCP call arguments and return a canonical argv tuple.

    Validation is deliberately implemented here rather than delegated to the
    MCP SDK. The authorized registry metadata is the source of truth, named
    inputs are ordered by their declared positions, and no value is coerced.

    Functions without declared parameters may receive only the ``args``
    string array. Functions with declared parameters may receive only those
    named string fields. Omitted trailing optional parameters are left for the
    Bash function to default; an omission before a later supplied value is
    rejected because shifting positional arguments would change semantics.
    """
    if not isinstance(func, dict):
        raise _invalid_arguments('authorized function metadata is malformed')
    if not isinstance(arguments, dict):
        raise _invalid_arguments('arguments must be an object')

    params = _ordered_parameters(func)
    if not params:
        extra_keys = set(arguments) - {'args'}
        if extra_keys:
            raise _invalid_arguments('arguments contain undeclared fields')

        argv = arguments.get('args', [])
        if not isinstance(argv, list):
            raise _invalid_arguments('args must be an array of strings')
        if any(not isinstance(value, str) for value in argv):
            raise _invalid_arguments('args must contain only strings')
        return tuple(argv)

    allowed_names = {param['name'] for param in params}
    if set(arguments) - allowed_names:
        raise _invalid_arguments('arguments contain undeclared fields')

    argv = []
    omitted_optional = False
    for param in params:
        name = param['name']
        if name not in arguments:
            effective_required = (
                param.get('required', True) and param.get('default') is None
            )
            if effective_required:
                raise _invalid_arguments(f'missing required parameter {name!r}')
            omitted_optional = True
            continue

        value = arguments[name]
        if not isinstance(value, str):
            raise _invalid_arguments(f'parameter {name!r} must be a string')
        if omitted_optional:
            raise _invalid_arguments('arguments would create a positional gap')
        argv.append(value)

    return tuple(argv)


def validate_broker_invocation_arguments(
    func: Dict[str, Any], arguments: Any
) -> Dict[str, Any]:
    """Validate a raw canonical argument object for broker delegation.

    Stable-core schemas come directly from each reviewed manifest export.
    Runtime validation remains authoritative even when an MCP client or SDK
    skips JSON-schema validation. Only the broker's deliberately small closed
    schema subset is accepted, and values are never coerced or reordered.
    """
    if not isinstance(func, dict):
        raise _invalid_arguments('authorized function metadata is malformed')
    if not isinstance(arguments, dict):
        raise _invalid_arguments('arguments must be an object')

    manifest_export = func.get('manifest_export')
    schema = (
        manifest_export.get('input_schema')
        if isinstance(manifest_export, dict)
        else None
    )
    if (
        not isinstance(schema, dict)
        or schema.get('type') != 'object'
        or schema.get('additionalProperties') is not False
        or not isinstance(schema.get('properties'), dict)
    ):
        raise _invalid_arguments('canonical argument schema is unavailable')

    properties = schema['properties']
    required = schema.get('required', [])
    if (
        not isinstance(required, list)
        or any(not isinstance(name, str) for name in required)
        or not set(required).issubset(properties)
    ):
        raise _invalid_arguments('canonical argument schema is malformed')

    if set(arguments) - set(properties):
        raise _invalid_arguments('arguments contain undeclared fields')
    missing = [name for name in required if name not in arguments]
    if missing:
        raise _invalid_arguments(f'missing required parameter {missing[0]!r}')

    for name, value in arguments.items():
        property_schema = properties.get(name)
        if not isinstance(property_schema, dict):
            raise _invalid_arguments('canonical argument schema is malformed')

        property_type = property_schema.get('type')
        if property_type == 'string':
            if not isinstance(value, str):
                raise _invalid_arguments(f'parameter {name!r} must be a string')
            enum = property_schema.get('enum')
            if enum is not None and (
                not isinstance(enum, list) or value not in enum
            ):
                raise _invalid_arguments(
                    f'parameter {name!r} is outside its allowed values'
                )
        elif property_type == 'array':
            if (
                property_schema.get('items') != {'type': 'string'}
                or not isinstance(value, list)
                or any(not isinstance(item, str) for item in value)
            ):
                raise _invalid_arguments(
                    f'parameter {name!r} must be an array of strings'
                )
        else:
            raise _invalid_arguments('canonical argument schema is malformed')

    return arguments

"""WS1 negative authorization test suite (Phase 0, A++ plan).

Every case is a regression test for a defect reproduced before the fix
(commits 1beefef, 21a234e): unregistered invocations, external executables,
shell metacharacter injection, schema violations, and tier violations must
all be denied; only advertised functions may reach the public atomic route.
"""

import json
import os

import pytest

from mainframe_mcp.authorization import (
    AuthorizationError,
    DEFAULT_TIER,
    REASON_INVALID_ARGUMENTS,
    REASON_INVALID_TIER,
    REASON_INVALID_NAME,
    REASON_NOT_REGISTERED,
    REASON_TIER_VIOLATION,
    REASON_UNKNOWN_TOOL,
    authorize_invocation,
    is_mcp_core_export,
    prepare_invocation_arguments,
    validate_broker_invocation_arguments,
    validate_function_name,
)
from mainframe_mcp import executor as executor_module
from mainframe_mcp.executor import BashExecutor
from mainframe_mcp.tool_registry import ToolRegistry


# The repo root doubles as MAINFRAME_ROOT for tests (FUNCTIONS.json + lib/).
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


UNBROKERED_SIDE_EFFECTS = {
    'usop_exec',
    'ensure_dir',
    'ensure_file',
    'atomic_write',
    'atomic_append',
    'atomic_replace',
}

UNREVIEWED_CALL_SHAPE_OWNERS = {
    'array_count': 'pure-array',
    'array_filter': 'pure-array',
    'array_first': 'pure-array',
    'array_get': 'pure-array',
    'array_intersect': 'pure-array',
    'array_last': 'pure-array',
    'array_length': 'pure-array',
    'array_reverse': 'pure-array',
    'array_slice': 'pure-array',
    'array_sum': 'pure-array',
    'array_unique': 'pure-array',
    'collection_count': 'collection',
    'collection_filter': 'collection',
    'collection_first': 'collection',
    'collection_intersect': 'collection',
    'collection_last': 'collection',
    'collection_length': 'collection',
    'collection_reverse': 'collection',
    'collection_slice': 'collection',
    'collection_sum': 'collection',
    'collection_unique': 'collection',
    'safe_array_get': 'safe',
    'awm_compress': 'awm',
    'awm_handoff_prepare': 'awm',
    'awm_handoff_accept': 'awm',
    'awm_stream_compress': 'awm_stream',
    'awm_protocol_handoff_prepare': 'awm_protocol',
    'awm_protocol_handoff_accept': 'awm_protocol',
}


@pytest.fixture(scope='module')
def registry():
    reg = ToolRegistry(mainframe_root=PROJECT_ROOT)
    assert reg.load(), 'FUNCTIONS.json failed to load'
    return reg


@pytest.fixture(scope='module')
def executor():
    return BashExecutor(mainframe_root=PROJECT_ROOT)


# --------------------------------------------------------------------------
# Unknown / unregistered tool names
# --------------------------------------------------------------------------

class TestUnknownAndUnregistered:
    def test_name_without_mainframe_prefix_denied(self, registry):
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, 'json_object')
        assert exc.value.reason == REASON_UNKNOWN_TOOL

    def test_unregistered_function_denied(self, registry):
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, 'mainframe_definitely_not_real_xyz')
        assert exc.value.reason == REASON_NOT_REGISTERED

    def test_empty_and_nonstr_denied(self, registry):
        for bad in ('', 'mainframe_', None, 42):
            with pytest.raises(AuthorizationError):
                authorize_invocation(registry, bad)


# --------------------------------------------------------------------------
# External executables (the before-repro: mainframe_ls ran /bin/ls)
# --------------------------------------------------------------------------

class TestExternalExecutables:
    @pytest.mark.parametrize('binary', ['ls', 'id', 'uname', 'curl', 'bash', 'sh'])
    def test_external_binary_denied_at_gate(self, registry, binary):
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, f'mainframe_{binary}')
        assert exc.value.reason == REASON_NOT_REGISTERED

# --------------------------------------------------------------------------
# Shell metacharacter injection (before-repro: 'mainframe_true;echo X' ran)
# --------------------------------------------------------------------------

class TestMetacharInjection:
    PAYLOADS = [
        'mainframe_true;echo PWNED',
        'mainframe_$(id)',
        'mainframe_`id`',
        'mainframe_a|id',
        'mainframe_a&&id',
        'mainframe_a>/tmp/x',
        'mainframe_a b',
        'mainframe_../bin/ls',
        'mainframe_a\nid',
    ]

    @pytest.mark.parametrize('tool_name', PAYLOADS)
    def test_injection_denied_at_gate(self, registry, tool_name):
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, tool_name)
        assert exc.value.reason in (REASON_INVALID_NAME, REASON_UNKNOWN_TOOL)

    @pytest.mark.parametrize('name', ['0abc', 'a-b', 'a.b', 'A_upper', ''])
    def test_invalid_identifiers_rejected(self, name):
        with pytest.raises(AuthorizationError) as exc:
            validate_function_name(name)
        assert exc.value.reason == REASON_INVALID_NAME


# --------------------------------------------------------------------------
# Schema violations (SDK validate_input pass mirrors this with jsonschema)
# --------------------------------------------------------------------------

class TestSchemaValidation:
    def test_reviewed_stable_core_is_exact_and_closed(self, registry):
        tools = registry.generate_all_tools(tier='stable-core')
        assert len(tools) == 26
        assert all(
            tool['inputSchema']['additionalProperties'] is False
            for tool in tools
        )

    def test_generated_schemas_are_closed(self, registry):
        for tool in registry.generate_all_tools(tier='stable-core'):
            assert tool['inputSchema']['additionalProperties'] is False

    def test_missing_required_param_fails_validation(self, registry):
        jsonschema = pytest.importorskip('jsonschema')
        schema = registry.generate_tool_schema('json_get')['inputSchema']
        assert schema.get('required'), 'fixture needs a function with required params'
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(instance={}, schema=schema)

    def test_valid_args_pass_validation(self, registry):
        jsonschema = pytest.importorskip('jsonschema')
        schema = registry.generate_tool_schema('json_get')['inputSchema']
        jsonschema.validate(
            instance={p: 'x' for p in schema['required']},
            schema=schema,
        )

    @pytest.mark.parametrize(
        'arguments',
        [
            {'args': ['{}', 'key']},
            {'json': '{}', 'key': 'key', 'unexpected': 'value'},
            {'json': {}, 'key': 'key'},
        ],
    )
    def test_named_schema_rejects_args_bypass_extras_and_wrong_types(
        self, registry, arguments
    ):
        jsonschema = pytest.importorskip('jsonschema')
        schema = registry.generate_tool_schema('json_get')['inputSchema']
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(instance=arguments, schema=schema)

    @pytest.mark.parametrize(
        'arguments',
        [
            {'unexpected': 'value'},
            {'args': 'k=v'},
            {'args': ['k=v', 42]},
        ],
    )
    def test_variadic_schema_rejects_extras_and_wrong_types(
        self, registry, arguments
    ):
        jsonschema = pytest.importorskip('jsonschema')
        schema = registry.generate_tool_schema('json_object')['inputSchema']
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(instance=arguments, schema=schema)

    def test_generated_schemas_are_valid_json_schema(self, registry):
        jsonschema = pytest.importorskip('jsonschema')
        for tool in registry.generate_all_tools(tier='stable-core'):
            jsonschema.Draft7Validator.check_schema(tool['inputSchema'])

    def test_every_advertised_tool_has_a_preparable_call_shape(self, registry):
        class SingleAdvertisedToolRegistry:
            def __init__(self, source_registry, tool):
                self.source_registry = source_registry
                self.tool = tool

            def get_function(self, name):
                return self.source_registry.get_function(name)

            def generate_all_tools(self, tier):
                return [self.tool]

        for tool in registry.generate_all_tools(tier='stable-core'):
            func_name = tool['name'][len('mainframe_'):]
            isolated_registry = SingleAdvertisedToolRegistry(registry, tool)
            func = authorize_invocation(isolated_registry, tool['name'])
            assert func['name'] == func_name
            arguments = {
                name: 'value'
                for name in tool['inputSchema'].get('required', [])
            }
            validate_broker_invocation_arguments(func, arguments)

    def test_stable_core_schemas_come_from_reviewed_manifest_contracts(
        self, registry
    ):
        assert set(
            registry.generate_tool_schema(
                'json_object', tier='stable-core'
            )['inputSchema']['properties']
        ) == {'pairs'}
        assert set(
            registry.generate_tool_schema(
                'array_join', tier='stable-core'
            )['inputSchema']['properties']
        ) == {'delimiter', 'items'}
        assert set(
            registry.generate_tool_schema(
                'json_merge', tier='stable-core'
            )['inputSchema']['properties']
        ) == {'objects'}

    def test_incomplete_metadata_is_not_advertised(self, registry):
        names = {
            tool['name']
            for tool in registry.generate_all_tools(tier='stable-core')
        }
        assert 'mainframe_agent_info_v' not in names

    def test_unreviewed_call_shapes_have_canonical_owners_but_no_guessed_mcp_schema(
        self, registry
    ):
        for name, expected_owner in UNREVIEWED_CALL_SHAPE_OWNERS.items():
            func = registry.get_function(name)
            assert func is not None
            assert func['library'] == expected_owner

        names = {
            tool['name'][len('mainframe_'):]
            for tool in registry.generate_all_tools(tier='stable-core')
        }
        assert not (UNREVIEWED_CALL_SHAPE_OWNERS.keys() & names)

        for name in UNREVIEWED_CALL_SHAPE_OWNERS:
            assert registry.generate_tool_schema(name) is None
            with pytest.raises(AuthorizationError) as exc:
                authorize_invocation(registry, f'mainframe_{name}')
            assert exc.value.reason == REASON_TIER_VIOLATION

    def test_noncanonical_function_name_is_not_advertised(self, registry):
        names = {
            tool['name']
            for tool in registry.generate_all_tools(tier='stable-core')
        }
        assert 'mainframe_ci::is_ci' not in names
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, 'mainframe_ci::is_ci')
        assert exc.value.reason == REASON_INVALID_NAME

    def test_array_join_has_reviewed_variadic_schema(self, registry):
        func = registry.get_function('array_join')
        schema = registry.generate_tool_schema('array_join')['inputSchema']

        assert func['mcp_call_shape'] == 'reviewed_variadic'
        assert func['registry_params'][0]['position'] == 2
        assert func['params'] == []
        assert set(schema['properties']) == {'delimiter', 'items'}
        assert schema['properties']['items'] == {
            'type': 'array',
            'items': {'type': 'string'},
            'default': [],
        }
        assert is_mcp_core_export('array_join', func['category'], func)

    @pytest.mark.parametrize(
        'func_name',
        [
            'agent_info_v',
            'agent_recover',
            'array_count',
            'array_filter',
            'array_first',
            'array_get',
            'array_intersect',
            'array_last',
            'array_length',
            'array_reverse',
            'array_slice',
            'array_sum',
            'array_unique',
            'array_drop_while',
            'array_every',
        ],
    )
    def test_incomplete_call_shape_is_not_an_executable_mcp_export(
        self, registry, func_name
    ):
        func = registry.get_function(func_name)
        assert not is_mcp_core_export(func_name, func['category'], func)
        reviewed_names = {
            tool['name'][len('mainframe_'):]
            for tool in registry.generate_all_tools(tier='stable-core')
        }
        assert func_name not in reviewed_names
        assert registry.generate_all_tools(tier='core') == []


# --------------------------------------------------------------------------
# Runtime argument validation and canonical positional preparation
# --------------------------------------------------------------------------

class TestArgumentPreparation:
    def test_named_inputs_use_metadata_position_not_caller_order(self, registry):
        func = authorize_invocation(registry, 'mainframe_json_get')
        argv = prepare_invocation_arguments(
            func,
            {'key': 'name', 'json': '{"name":"Ada"}'},
        )
        assert argv == ('{"name":"Ada"}', 'name')

    @pytest.mark.parametrize(
        'arguments',
        [
            {'args': ['{}', 'name']},
            {'json': '{}', 'key': 'name', 'unexpected': 'value'},
            {'json': '{}'},
            {'json': {}, 'key': 'name'},
            None,
        ],
    )
    def test_named_inputs_reject_bypass_extras_missing_and_wrong_types(
        self, registry, arguments
    ):
        func = authorize_invocation(registry, 'mainframe_json_get')
        with pytest.raises(AuthorizationError) as exc:
            prepare_invocation_arguments(func, arguments)
        assert exc.value.reason == REASON_INVALID_ARGUMENTS

    def test_variadic_args_are_only_allowed_without_declared_params(self, registry):
        func = authorize_invocation(registry, 'mainframe_json_object')
        assert prepare_invocation_arguments(func, {'args': ['k=v']}) == ('k=v',)
        assert prepare_invocation_arguments(func, {}) == ()

    def test_declared_args_parameter_is_a_named_string_not_variadic(self):
        func = {
            'name': 'example',
            'params': [
                {'name': 'args', 'position': 1, 'required': True, 'default': None},
            ],
        }
        assert prepare_invocation_arguments(func, {'args': 'literal'}) == ('literal',)
        with pytest.raises(AuthorizationError) as exc:
            prepare_invocation_arguments(func, {'args': ['not', 'variadic']})
        assert exc.value.reason == REASON_INVALID_ARGUMENTS

    @pytest.mark.parametrize(
        'arguments',
        [
            {'unexpected': 'value'},
            {'args': 'k=v'},
            {'args': ['k=v', 42]},
        ],
    )
    def test_variadic_inputs_reject_extras_and_wrong_types(
        self, registry, arguments
    ):
        func = authorize_invocation(registry, 'mainframe_json_object')
        with pytest.raises(AuthorizationError) as exc:
            prepare_invocation_arguments(func, arguments)
        assert exc.value.reason == REASON_INVALID_ARGUMENTS

    def test_trailing_optional_defaults_are_left_to_the_function(self, registry):
        func = authorize_invocation(registry, 'mainframe_output_success')
        assert prepare_invocation_arguments(func, {'data': '{}'}) == ('{}',)

    def test_defaulted_validate_url_parameter_is_not_synthesized(self, registry):
        func = authorize_invocation(registry, 'mainframe_validate_url')
        assert prepare_invocation_arguments(
            func, {'url': 'https://example.com'}
        ) == ('https://example.com',)

    def test_omitted_optional_before_later_value_is_denied(self):
        func = {
            'name': 'example',
            'params': [
                {'name': 'first', 'position': 1, 'required': False, 'default': None},
                {'name': 'second', 'position': 2, 'required': False, 'default': None},
            ],
        }
        with pytest.raises(AuthorizationError) as exc:
            prepare_invocation_arguments(func, {'second': 'value'})
        assert exc.value.reason == REASON_INVALID_ARGUMENTS

    def test_incomplete_positional_metadata_is_denied(self):
        func = {
            'name': 'example',
            'params': [
                {'name': 'second', 'position': 2, 'required': False, 'default': ','},
            ],
        }
        with pytest.raises(AuthorizationError) as exc:
            prepare_invocation_arguments(func, {})
        assert exc.value.reason == REASON_INVALID_ARGUMENTS

    def test_canonical_arguments_are_validated_without_legacy_reordering(
        self, registry
    ):
        func = authorize_invocation(registry, 'mainframe_array_join')
        arguments = {'delimiter': '|', 'items': ['a', 'b']}
        assert validate_broker_invocation_arguments(func, arguments) is arguments

        with pytest.raises(AuthorizationError) as exc:
            validate_broker_invocation_arguments(
                func, {'args': ['|', 'a', 'b']}
            )
        assert exc.value.reason == REASON_INVALID_ARGUMENTS

    def test_canonical_arguments_enforce_manifest_enum(self, registry):
        func = authorize_invocation(registry, 'mainframe_validate_path')
        with pytest.raises(AuthorizationError) as exc:
            validate_broker_invocation_arguments(
                func, {'path': '/tmp/example', 'type': 'socket'}
            )
        assert exc.value.reason == REASON_INVALID_ARGUMENTS


class TestControlPlaneExecutorBoundary:
    def test_executor_has_only_the_public_atomic_route(self, executor):
        assert hasattr(executor, 'execute_control_plane')
        assert not hasattr(executor, 'execute_broker')
        assert not hasattr(executor, 'execute')
        assert not hasattr(executor, 'bash')

    def test_control_plane_uses_sanitized_environment(
        self, executor, monkeypatch
    ):
        monkeypatch.setenv('BASH_ENV', '/tmp/hostile-bash-env')
        monkeypatch.setenv('NODE_OPTIONS', '--require=/tmp/hostile-node-hook')
        monkeypatch.setenv('PERL5OPT', '-Mhostile')
        monkeypatch.setenv('BASH_FUNC_hostile%%', '() { echo hostile; }')
        monkeypatch.setenv('LD_PRELOAD', '/tmp/hostile-loader')
        monkeypatch.setenv('DYLD_INSERT_LIBRARIES', '/tmp/hostile-loader')
        monkeypatch.setenv('PATH', '/tmp/hostile-project-bin')
        monkeypatch.setenv('MAINFRAME_TEST_PRESERVED', 'yes')
        environment = executor_module._execution_environment(
            executor.mainframe_root
        )

        assert environment['MAINFRAME_TEST_PRESERVED'] == 'yes'
        assert environment['PATH'] == executor_module.TRUSTED_DEPENDENCY_PATH
        for key in (
            'BASH_ENV',
            'NODE_OPTIONS',
            'PERL5OPT',
            'BASH_FUNC_hostile%%',
            'LD_PRELOAD',
            'DYLD_INSERT_LIBRARIES',
        ):
            assert key not in environment


# --------------------------------------------------------------------------
# Tier violations
# --------------------------------------------------------------------------

class TestStableCoreSafetyFloor:
    def test_default_surface_has_read_pure_contract_and_is_capped(self, registry):
        config_path = os.path.join(PROJECT_ROOT, 'config', 'stable-core.json')
        with open(config_path, encoding='utf-8') as config_file:
            config = json.load(config_file)

        stable_tools = {
            tool['name'][10:]
            for tool in registry.generate_all_tools(tier=DEFAULT_TIER)
        }

        assert DEFAULT_TIER == config['mcp']['default_tier'] == 'stable-core'
        assert config['mcp']['default_effect_contract'] == 'read-pure-only'
        assert (
            set(config['mcp']['excluded_unbrokered_exports'])
            == UNBROKERED_SIDE_EFFECTS
        )
        assert stable_tools == set(config['exports'])
        assert len(stable_tools) <= config['mcp']['max_default_tools'] <= 32
        assert stable_tools.isdisjoint(UNBROKERED_SIDE_EFFECTS)
        assert not any(
            name.startswith(('ensure_', 'atomic_')) for name in stable_tools
        )

    @pytest.mark.parametrize('function_name', sorted(UNBROKERED_SIDE_EFFECTS))
    def test_unbrokered_side_effect_denied_and_legacy_tiers_rejected(
        self, registry, function_name
    ):
        tool_name = f'mainframe_{function_name}'

        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, tool_name)
        assert exc.value.reason == REASON_TIER_VIOLATION

        for legacy_tier in ('core', 'full'):
            with pytest.raises(AuthorizationError) as legacy_exc:
                authorize_invocation(registry, tool_name, tier=legacy_tier)
            assert legacy_exc.value.reason == REASON_INVALID_TIER


class TestTierEnforcement:
    @pytest.mark.parametrize('legacy_tier', ['core', 'full'])
    def test_legacy_discovery_profiles_are_not_execution_tiers(
        self, registry, legacy_tier
    ):
        assert registry.generate_all_tools(tier=legacy_tier) == []
        assert registry.generate_tool_schema('json_object', tier=legacy_tier) is None
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(
                registry, 'mainframe_json_object', tier=legacy_tier
            )
        assert exc.value.reason == REASON_INVALID_TIER


# --------------------------------------------------------------------------
# Positive control: a registered, in-tier function authorizes and normalizes
# --------------------------------------------------------------------------

class TestPositiveControl:
    def test_registered_reviewed_function_authorized(self, registry):
        func = authorize_invocation(registry, 'mainframe_json_object')
        assert func['name'] == 'json_object'

    def test_reviewed_array_join_variadic_call_normalizes(self, registry):
        func = authorize_invocation(registry, 'mainframe_array_join')
        argv = prepare_invocation_arguments(func, {'args': [',', 'a', 'b']})
        assert argv == (',', 'a', 'b')

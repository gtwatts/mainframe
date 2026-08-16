"""WS1 negative authorization test suite (Phase 0, A++ plan).

Every case is a regression test for a defect reproduced before the fix
(commits 1beefef, 21a234e): unregistered invocations, external executables,
shell metacharacter injection, schema violations, and tier violations must
all be denied; only advertised functions may execute.
"""

import json
import os

import pytest

from mainframe_mcp.authorization import (
    AuthorizationError,
    DEFAULT_TIER,
    REASON_INVALID_ARGUMENTS,
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


@pytest.fixture(scope='module')
def full_only_function(registry):
    """A registered function advertised in 'full' but not in 'core'."""
    core = {t['name'][10:] for t in registry.generate_all_tools(tier='core')}
    full = {t['name'][10:] for t in registry.generate_all_tools(tier='full')}
    outside = sorted(full - core)
    assert outside, 'expected at least one full-only function'
    return outside[0]


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

    @pytest.mark.parametrize('binary', ['ls', 'id', 'uname'])
    def test_external_binary_denied_in_executor(self, executor, binary):
        """Defense-in-depth: even bypassing the gate, PATH binaries never run."""
        ok, out, err = executor.execute(binary, [])
        assert not ok
        assert 'denied' in err


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

    @pytest.mark.parametrize('payload', ['true;echo PWNED', '$(id)', 'a|id', 'a b'])
    def test_injection_denied_in_executor(self, executor, payload):
        ok, out, err = executor.execute(payload, [])
        assert not ok
        assert 'PWNED' not in out
        assert 'denied' in err

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
        for tool in registry.generate_all_tools(tier='full'):
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
        for tool in registry.generate_all_tools(tier='core')[:50]:
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

        for tier in ('stable-core', 'core', 'full'):
            for tool in registry.generate_all_tools(tier=tier):
                func_name = tool['name'][len('mainframe_'):]
                isolated_registry = SingleAdvertisedToolRegistry(registry, tool)
                func = authorize_invocation(
                    isolated_registry, tool['name'], tier=tier
                )
                assert func['name'] == func_name
                arguments = {
                    name: 'value'
                    for name in tool['inputSchema'].get('required', [])
                }
                if tier == 'stable-core':
                    validate_broker_invocation_arguments(func, arguments)
                else:
                    prepare_invocation_arguments(func, arguments)

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
            for tool in registry.generate_all_tools(tier='full')
        }
        assert 'mainframe_agent_info_v' not in names

    def test_unreviewed_call_shapes_have_canonical_owners_but_no_guessed_mcp_schema(
        self, registry
    ):
        for name, expected_owner in UNREVIEWED_CALL_SHAPE_OWNERS.items():
            func = registry.get_function(name)
            assert func is not None
            assert func['library'] == expected_owner

        for tier in ('stable-core', 'core', 'full'):
            names = {
                tool['name'][len('mainframe_'):]
                for tool in registry.generate_all_tools(tier=tier)
            }
            assert not (UNREVIEWED_CALL_SHAPE_OWNERS.keys() & names)

        for tier in ('stable-core', 'core', 'full'):
            for name in UNREVIEWED_CALL_SHAPE_OWNERS:
                assert registry.generate_tool_schema(name, tier=tier) is None
                with pytest.raises(AuthorizationError) as exc:
                    authorize_invocation(
                        registry, f'mainframe_{name}', tier=tier
                    )
                assert exc.value.reason == REASON_TIER_VIOLATION

    def test_noncanonical_function_name_is_not_advertised(self, registry):
        names = {
            tool['name']
            for tool in registry.generate_all_tools(tier='full')
        }
        assert 'mainframe_ci::is_ci' not in names
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, 'mainframe_ci::is_ci', tier='full')
        assert exc.value.reason == REASON_INVALID_NAME

    def test_array_join_has_reviewed_variadic_schema(self, registry):
        func = registry.get_function('array_join')
        schema = registry.generate_tool_schema('array_join')['inputSchema']

        assert func['mcp_call_shape'] == 'reviewed_variadic'
        assert func['registry_params'][0]['position'] == 2
        assert func['params'] == []
        assert set(schema['properties']) == {'args'}
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
    def test_incomplete_call_shape_is_not_an_mcp_core_export(
        self, registry, func_name
    ):
        func = registry.get_function(func_name)
        assert not is_mcp_core_export(func_name, func['category'], func)
        core_names = {
            tool['name'][len('mainframe_'):]
            for tool in registry.generate_all_tools(tier='core')
        }
        assert func_name not in core_names


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


class TestPreparedExecutorBoundary:
    def test_bash_override_must_be_absolute(self, monkeypatch):
        monkeypatch.setenv('MAINFRAME_BASH', 'bash')
        with pytest.raises(RuntimeError, match='absolute path'):
            executor_module._resolve_bash()

    def test_old_explicit_bash_fails_closed(self, monkeypatch):
        monkeypatch.setenv('MAINFRAME_BASH', '/usr/local/bin/bash')
        monkeypatch.setattr(
            executor_module,
            '_resolve_safe_bash_candidate',
            lambda _: '/usr/local/bin/bash',
        )
        monkeypatch.setattr(
            executor_module, '_probe_bash_version', lambda _: (4, 3)
        )
        with pytest.raises(RuntimeError, match='4.4 or newer'):
            executor_module._resolve_bash()

    def test_missing_supported_bash_fails_closed(self, monkeypatch):
        monkeypatch.delenv('MAINFRAME_BASH', raising=False)
        monkeypatch.setattr(
            executor_module, 'FIXED_BASH_CANDIDATES', ('/missing/bash',)
        )
        with pytest.raises(RuntimeError, match='requires Bash 4.4'):
            executor_module._resolve_bash()

    def test_poisoned_unsupported_bash_is_rejected_before_probe(
        self, monkeypatch, tmp_path
    ):
        marker = tmp_path / 'poisoned-bash-ran'
        poisoned_bash = tmp_path / 'bash'
        poisoned_bash.write_text(
            '#!/bin/sh\n'
            f': > "{marker}"\n'
            'printf "5 3"\n',
            encoding='utf-8',
        )
        poisoned_bash.chmod(0o755)
        monkeypatch.setenv('MAINFRAME_BASH', str(poisoned_bash))

        with pytest.raises(RuntimeError, match='safe supported'):
            executor_module._resolve_bash()

        assert not marker.exists()

    def test_writable_bash_is_rejected_before_version_probe(
        self, monkeypatch, tmp_path
    ):
        marker = tmp_path / 'version-probe-ran'
        writable_bash = tmp_path / 'bash'
        writable_bash.write_text('#!/bin/sh\nexit 0\n', encoding='utf-8')
        writable_bash.chmod(0o777)
        monkeypatch.setenv('MAINFRAME_BASH', str(writable_bash))
        monkeypatch.setattr(
            executor_module, '_bash_layout_is_known', lambda _: True
        )

        def poisoned_probe(_):
            marker.write_text('ran', encoding='utf-8')
            return 5, 3

        monkeypatch.setattr(
            executor_module, '_probe_bash_version', poisoned_probe
        )
        with pytest.raises(RuntimeError, match='safe supported'):
            executor_module._resolve_bash()

        assert not marker.exists()

    def test_executor_rejects_unprepared_argument_mapping(self, executor):
        ok, out, err = executor.execute('json_object', {'args': ['k=v']})
        assert not ok
        assert not out
        assert 'prepared argv' in err

    def test_executor_passes_arguments_without_shell_reinterpretation(self, executor):
        ok, out, err = executor.execute('json_object', ['k=$(id)', 'semi=one;two'])
        assert ok, err
        assert json.loads(out) == {'k': '$(id)', 'semi': 'one;two'}

    def test_executor_never_runs_partially_sourced_function(self, tmp_path):
        lib_dir = tmp_path / 'lib'
        lib_dir.mkdir()
        (lib_dir / 'common.sh').write_text(
            'json_object() { printf "PARTIAL\\n"; }\nreturn 1\n',
            encoding='utf-8',
        )
        isolated_executor = BashExecutor(mainframe_root=str(tmp_path))

        ok, out, err = isolated_executor.execute('json_object', [])

        assert not ok
        assert 'PARTIAL' not in out
        assert 'initialization failed' in err

    def test_common_sh_path_is_not_interpreted_as_shell_source(self, tmp_path):
        unusual_root = tmp_path / "root'; echo PATH_INJECTION; $(id)"
        lib_dir = unusual_root / 'lib'
        lib_dir.mkdir(parents=True)
        (lib_dir / 'common.sh').write_text(
            'json_object() { printf "SAFE\\n"; }\n',
            encoding='utf-8',
        )
        isolated_executor = BashExecutor(mainframe_root=str(unusual_root))

        ok, out, err = isolated_executor.execute('json_object', [])

        assert ok, err
        assert out.strip() == 'SAFE'
        assert 'PATH_INJECTION' not in out

    def test_executor_does_not_run_inherited_path_shim(
        self, executor, monkeypatch, tmp_path
    ):
        shim_dir = tmp_path / 'hostile-bin'
        shim_dir.mkdir()
        marker = tmp_path / 'path-shim-ran'
        shim = shim_dir / 'jq'
        shim.write_text(
            f'#!/bin/sh\n: > "{marker}"\nexit 99\n',
            encoding='utf-8',
        )
        shim.chmod(0o755)
        monkeypatch.setenv('PATH', str(shim_dir))

        ok, _, err = executor.execute('json_valid', ['{}'])

        assert ok, err
        assert not marker.exists()

    def test_executor_uses_clean_privileged_bash(self, executor, monkeypatch):
        captured = {}
        resolved_bash = executor.bash

        monkeypatch.setenv('BASH_ENV', '/tmp/hostile-bash-env')
        monkeypatch.setenv('NODE_OPTIONS', '--require=/tmp/hostile-node-hook')
        monkeypatch.setenv('PERL5OPT', '-Mhostile')
        monkeypatch.setenv('BASH_FUNC_hostile%%', '() { echo hostile; }')
        monkeypatch.setenv('LD_PRELOAD', '/tmp/hostile-loader')
        monkeypatch.setenv('DYLD_INSERT_LIBRARIES', '/tmp/hostile-loader')
        monkeypatch.setenv('PATH', '/tmp/hostile-project-bin')
        monkeypatch.setenv('MAINFRAME_TEST_PRESERVED', 'yes')

        def fake_run(command, **kwargs):
            captured['command'] = command
            captured['env'] = kwargs['env']
            return type('Result', (), {'returncode': 0, 'stdout': '', 'stderr': ''})()

        monkeypatch.setattr(executor_module.subprocess, 'run', fake_run)
        ok, _, _ = executor.execute('json_object', ['k=v'])

        assert ok
        assert captured['command'][:5] == [
            resolved_bash,
            '--noprofile',
            '--norc',
            '-p',
            '-c',
        ]
        assert captured['command'][6:] == [
            'mainframe-mcp',
            executor.common_sh,
            'json_object',
            'k=v',
        ]
        assert captured['env']['MAINFRAME_TEST_PRESERVED'] == 'yes'
        assert captured['env']['PATH'] == executor_module.TRUSTED_DEPENDENCY_PATH
        for key in (
            'BASH_ENV',
            'NODE_OPTIONS',
            'PERL5OPT',
            'BASH_FUNC_hostile%%',
            'LD_PRELOAD',
            'DYLD_INSERT_LIBRARIES',
        ):
            assert key not in captured['env']


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
    def test_unbrokered_side_effect_denied_by_default_but_kept_opt_in(
        self, registry, function_name
    ):
        tool_name = f'mainframe_{function_name}'

        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, tool_name)
        assert exc.value.reason == REASON_TIER_VIOLATION

        assert (
            authorize_invocation(registry, tool_name, tier='core')['name']
            == function_name
        )
        assert (
            authorize_invocation(registry, tool_name, tier='full')['name']
            == function_name
        )


class TestTierEnforcement:
    def test_full_only_function_denied_under_core(self, registry, full_only_function):
        with pytest.raises(AuthorizationError) as exc:
            authorize_invocation(registry, f'mainframe_{full_only_function}', tier='core')
        assert exc.value.reason == REASON_TIER_VIOLATION

    def test_full_only_function_allowed_under_full(self, registry, full_only_function):
        func = authorize_invocation(registry, f'mainframe_{full_only_function}', tier='full')
        assert func['name'] == full_only_function


# --------------------------------------------------------------------------
# Positive control: a registered, in-tier function authorizes and executes
# --------------------------------------------------------------------------

class TestPositiveControl:
    def test_registered_core_function_authorized(self, registry):
        func = authorize_invocation(registry, 'mainframe_json_object', tier='core')
        assert func['name'] == 'json_object'

    def test_registered_function_executes(self, executor):
        ok, out, err = executor.execute('json_object', ['k=v'])
        assert ok, f'legitimate invocation failed: {err}'
        assert out.strip() == '{"k":"v"}'

    def test_reviewed_array_join_variadic_call_executes(self, registry, executor):
        func = authorize_invocation(registry, 'mainframe_array_join')
        argv = prepare_invocation_arguments(func, {'args': [',', 'a', 'b']})
        ok, out, err = executor.execute(func['name'], argv)
        assert ok, err
        assert out.strip() == 'a,b'

#!/usr/bin/env bats
# Owner-parity gate (A++ Phase 0 deliverable 4; docs/CANONICAL_MANIFEST.md §7)
#
# Every exposed name must resolve to the same canonical owner on every
# surface. The checker script asserts parity across the manifest, MCP
# registry, LSP metadata, runtime full-load, runtime lazy map, and bindings.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    PYTHON_BIN="$(command -v python3)"
}

@test "owner-parity: zero owner disagreements for exposed names" {
    [ -f "$PROJECT_ROOT/MANIFEST.json" ] || skip "MANIFEST.json not generated"
    run python3 "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: zero owner disagreements"* ]]
}

@test "manifest: FUNCTIONS.json regenerates byte-identically" {
    [ -f "$PROJECT_ROOT/MANIFEST.json" ] || skip "MANIFEST.json not generated"
    run python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFY PASS"* ]]
}

@test "release metadata verifiers honor the Python 3.9 runtime floor" {
    local system_python=/usr/bin/python3
    [ -x "$system_python" ] || skip "/usr/bin/python3 is unavailable"

    run "$system_python" -I -S -B "$PROJECT_ROOT/scripts/generate-manifest.py" --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFY PASS"* ]]

    run "$system_python" -I -S -B "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: zero owner disagreements"* ]]
}

@test "registry generator never sources an inherited MAINFRAME runtime" {
    local inherited_root="$BATS_TEST_TMPDIR/inherited-mainframe"
    local marker="$BATS_TEST_TMPDIR/inherited-common-ran"
    mkdir -p "$inherited_root/lib"
    printf '%s\n' \
        'printf inherited > "$MAINFRAME_GENERATOR_MARKER"' \
        'return 0' > "$inherited_root/lib/common.sh"

    run env \
        MAINFRAME_ROOT="$inherited_root" \
        MAINFRAME_GENERATOR_MARKER="$marker" \
        "$BASH" "$PROJECT_ROOT/scripts/generate-functions-json.sh" --help

    [ "$status" -eq 1 ]
    [[ "$output" == *"Generate FUNCTIONS.json registry"* ]]
    [ ! -e "$marker" ]
}

@test "release metadata resolvers reject Bash 4.3 and accept Bash 4.4" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import importlib.util
import os
import subprocess
import sys
from unittest.mock import patch

root = sys.argv[1]
scripts = (
    ('generate_manifest', os.path.join(root, 'scripts', 'generate-manifest.py')),
    ('check_owner_parity', os.path.join(root, 'scripts', 'check-owner-parity.py')),
)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mixed_version_probe(args, **_kwargs):
    version = '4 3' if args[0] == '/fixture/bash-4.3' else '4 4'
    return subprocess.CompletedProcess(args, 0, stdout=version, stderr='')


def old_version_probe(args, **_kwargs):
    return subprocess.CompletedProcess(args, 0, stdout='4 3', stderr='')


for name, path in scripts:
    with patch.dict(os.environ, {'MAINFRAME_BASH': ''}), \
            patch('os.path.realpath', side_effect=lambda value: value), \
            patch('os.path.isfile', return_value=True), \
            patch('os.access', return_value=True):
        with patch('subprocess.run', side_effect=mixed_version_probe) as probe:
            module = load_module(name, path)
            selected = module.BASH if hasattr(module, 'BASH') else module.resolve_bash()

    assert module.MINIMUM_BASH_VERSION == (4, 4)
    assert selected == '/opt/homebrew/bin/bash', (name, selected)
    assert probe.call_args_list[0].args[0][0] == '/opt/homebrew/bin/bash'
    assert all(
        call.args[0][1:5] == ['--noprofile', '--norc', '-p', '-c']
        for call in probe.call_args_list
    )
    assert all(
        '${BASH_VERSINFO[0]}' in call.args[0][-1]
        and '${BASH_VERSINFO[1]}' in call.args[0][-1]
        for call in probe.call_args_list
    )

    with patch.dict(os.environ, {'MAINFRAME_BASH': '/fixture/bash-4.3'}), \
            patch('os.path.realpath', side_effect=lambda value: value), \
            patch('os.path.isfile', return_value=True), \
            patch('os.access', return_value=True):
        with patch('subprocess.run', side_effect=old_version_probe) as old_probe:
            try:
                module.resolve_bash()
            except RuntimeError as exc:
                assert 'Bash 4.4 or newer' in str(exc) or 'Bash 4.4' in str(exc)
            else:
                raise AssertionError(f'{name} accepted Bash 4.3')
    assert [call.args[0][0] for call in old_probe.call_args_list] == [
        '/fixture/bash-4.3'
    ]

print('release metadata Bash floor valid: 4.3 rejected, 4.4 accepted')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"release metadata Bash floor valid"* ]]
}

@test "release metadata resolvers never execute a relative Bash override" {
    local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
    local marker="$BATS_TEST_TMPDIR/relative-bash-ran"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf poisoned > "$MAINFRAME_FAKE_BASH_MARKER"' \
        'exit 97' > "$fake_bin/bash"
    chmod +x "$fake_bin/bash"

    run env \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH=bash \
        MAINFRAME_FAKE_BASH_MARKER="$marker" \
        "$PYTHON_BIN" "$PROJECT_ROOT/scripts/generate-manifest.py" --verify
    [ "$status" -ne 0 ]
    [ ! -e "$marker" ]

    run env \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH=bash \
        MAINFRAME_FAKE_BASH_MARKER="$marker" \
        "$PYTHON_BIN" "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -ne 0 ]
    [ ! -e "$marker" ]

    run env -u MAINFRAME_BASH \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_FAKE_BASH_MARKER="$marker" \
        "$PYTHON_BIN" "$PROJECT_ROOT/scripts/generate-manifest.py" --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFY PASS"* ]]
    [ ! -e "$marker" ]

    run env -u MAINFRAME_BASH \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_FAKE_BASH_MARKER="$marker" \
        "$PYTHON_BIN" "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: zero owner disagreements"* ]]
    [ ! -e "$marker" ]
}

@test "release metadata runtime probes ignore poisoned BASH_ENV" {
    local poison="$BATS_TEST_TMPDIR/poison-bash-env.sh"
    local marker="$BATS_TEST_TMPDIR/bash-env-ran"
    printf '%s\n' \
        'printf poisoned > "$MAINFRAME_BASH_ENV_MARKER"' \
        'exit 97' > "$poison"

    run env \
        BASH_ENV="$poison" \
        MAINFRAME_BASH_ENV_MARKER="$marker" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFY PASS"* ]]
    [ ! -e "$marker" ]

    run env \
        BASH_ENV="$poison" \
        MAINFRAME_BASH_ENV_MARKER="$marker" \
        python3 "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: zero owner disagreements"* ]]
    [ ! -e "$marker" ]
}

@test "release metadata runtime probes ignore exported function injection" {
    local marker="$BATS_TEST_TMPDIR/exported-function-ran"

    cksum() {
        printf poisoned > "$MAINFRAME_EXPORTED_FUNCTION_MARKER"
        return 97
    }
    export -f cksum

    run env \
        MAINFRAME_EXPORTED_FUNCTION_MARKER="$marker" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFY PASS"* ]]
    [ ! -e "$marker" ]

    run env \
        MAINFRAME_EXPORTED_FUNCTION_MARKER="$marker" \
        python3 "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: zero owner disagreements"* ]]
    [ ! -e "$marker" ]

    unset -f cksum
}

@test "manifest: discovery core is non-executable and excludes unpreparable call shapes" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
import sys

root = sys.argv[1]
manifest = json.load(open(os.path.join(root, 'MANIFEST.json')))
sys.path.insert(0, os.path.join(root, 'mcp', 'src'))
from mainframe_mcp.tool_registry import ToolRegistry

registry = ToolRegistry(mainframe_root=root)
assert registry.load()
assert registry.generate_all_tools(tier='core') == []
manifest_core = {
    export['name']
    for export in manifest['exports'].values()
    if 'core' in export['profiles']
}
unpreparable = {
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
}
assert not (unpreparable & manifest_core)
assert 'array_join' in manifest_core
print(f'MCP discovery core closure valid: {len(manifest_core)} tools')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"MCP discovery core closure valid:"* ]]
}

@test "manifest: verify rejects stale checked-in fields hidden from registry roundtrip" {
    local fixture="$BATS_TEST_TMPDIR/MANIFEST.stale.json"

    run env MAINFRAME_MANIFEST_PATH="$fixture" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --no-probe
    [ "$status" -eq 0 ]

    # `derivation` is not consumed by manifest_to_registry. The old verifier
    # rebuilt only the registry from a fresh in-memory manifest, so this exact
    # checked-in drift was invisible.
    python3 - "$fixture" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path))
data['derivation']['status'] = 'stale-regression-fixture'
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)
    handle.write('\n')
PY

    run env MAINFRAME_MANIFEST_PATH="$fixture" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --verify --no-probe
    [ "$status" -eq 1 ]
    [[ "$output" == *"VERIFY FAIL: MANIFEST.json is stale"* ]]
    [[ "$output" == *"MANIFEST.json drift"* ]]
}

@test "manifest: verify rejects stale generated invocation index" {
    local manifest_fixture="$BATS_TEST_TMPDIR/MANIFEST.index-source.json"
    local index_fixture="$BATS_TEST_TMPDIR/INVOCATION_INDEX.stale.json"

    run env \
        MAINFRAME_MANIFEST_PATH="$manifest_fixture" \
        MAINFRAME_INVOCATION_INDEX_PATH="$index_fixture" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --no-probe
    [ "$status" -eq 0 ]

    python3 - "$index_fixture" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding='utf-8'))
data['contract_count'] -= 1
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(data, handle, ensure_ascii=False, sort_keys=True,
              separators=(',', ':'))
    handle.write('\n')
PY

    run env \
        MAINFRAME_MANIFEST_PATH="$manifest_fixture" \
        MAINFRAME_INVOCATION_INDEX_PATH="$index_fixture" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --verify --no-probe
    [ "$status" -eq 1 ]
    [[ "$output" == *"VERIFY FAIL: INVOCATION_INDEX.json is stale"* ]]
    [[ "$output" == *"INVOCATION_INDEX.json drift"* ]]
}

@test "owner-parity: stale manifest version names and counts fail closed" {
    local fixture="$BATS_TEST_TMPDIR/MANIFEST.owner-parity-stale.json"
    cp "${MAINFRAME_MANIFEST_PATH:-$PROJECT_ROOT/MANIFEST.json}" "$fixture"

    python3 - "$fixture" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path))
data['version'] = '0.0.0-stale-regression-fixture'
victim = next(iter(data['name_index']))
del data['name_index'][victim]
data['stats']['exports'] -= 1
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)
    handle.write('\n')
PY

    run env MAINFRAME_MANIFEST_PATH="$fixture" \
        python3 "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 1 ]
    [[ "$output" == *"canonical/version"* ]]
    [[ "$output" == *"canonical/manifest-names"* ]]
    [[ "$output" == *"canonical/manifest-counts"* ]]
}

@test "owner-parity: stale LSP version names and counts fail closed" {
    local fixture="$BATS_TEST_TMPDIR/FUNCTIONS.lsp.stale.json"
    cp "${MAINFRAME_LSP_META_PATH:-$PROJECT_ROOT/FUNCTIONS.lsp.json}" "$fixture"

    python3 - "$fixture" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path))
data['version'] = '0.0.0-stale-regression-fixture'
data['completions'].pop()
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)
    handle.write('\n')
PY

    run env MAINFRAME_LSP_META_PATH="$fixture" \
        python3 "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 1 ]
    [[ "$output" == *"canonical/version"* ]]
    [[ "$output" == *"canonical/lsp-names"* ]]
    [[ "$output" == *"canonical/lsp-counts"* ]]
}

@test "owner-parity: stale LSP execution classification fails closed" {
    local fixture="$BATS_TEST_TMPDIR/FUNCTIONS.lsp.semantic-stale.json"
    cp "${MAINFRAME_LSP_META_PATH:-$PROJECT_ROOT/FUNCTIONS.lsp.json}" "$fixture"

    python3 - "$fixture" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path))
for completion in data['completions']:
    if completion['label'] == 'json_get':
        completion['data']['executionExposure'] = 'discovery-only'
        break
else:
    raise SystemExit('json_get completion missing')
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)
    handle.write('\n')
PY

    run env MAINFRAME_LSP_META_PATH="$fixture" \
        python3 "$PROJECT_ROOT/scripts/check-owner-parity.py"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lsp/completion-semantics"* ]]
}

@test "stable-core: capped read/pure default excludes unbrokered side effects" {
    [ -f "$PROJECT_ROOT/config/stable-core.json" ] || skip "stable-core.json missing"
    run python3 -c "
import json
import sys
reg = json.load(open('$PROJECT_ROOT/FUNCTIONS.json'))
pol = json.load(open('$PROJECT_ROOT/config/function-export-policy.json'))
sc = json.load(open('$PROJECT_ROOT/config/stable-core.json'))
sys.path.insert(0, '$PROJECT_ROOT/mcp/src')
from mainframe_mcp.tool_registry import ToolRegistry

unsafe = {
    'usop_exec',
    'ensure_dir',
    'ensure_file',
    'atomic_write',
    'atomic_append',
    'atomic_replace',
}
exports = set(sc['exports'])
assert sc['mcp']['default_tier'] == 'stable-core'
assert sc['mcp']['default_effect_contract'] == 'read-pure-only'
assert set(sc['mcp']['excluded_unbrokered_exports']) == unsafe
assert len(sc['exports']) <= sc['mcp']['max_default_tools'] <= 32
assert len(exports) == len(sc['exports'])
assert not (exports & unsafe), sorted(exports & unsafe)
assert not any(name.startswith(('ensure_', 'atomic_')) for name in exports)

names = {n for ld in reg['libraries'].values() for n in ld['functions']}
missing = [e for e in sc['exports'] if e not in names]
colliding = [e for e in sc['exports'] if e in pol['collisions']]
assert not missing and not colliding, (missing, colliding)
assert unsafe <= names

registry = ToolRegistry(mainframe_root='$PROJECT_ROOT')
assert registry.load()
stable = {t['name'][10:] for t in registry.generate_all_tools(tier='stable-core')}
core = registry.generate_all_tools(tier='core')
full = registry.generate_all_tools(tier='full')
assert stable == exports
assert core == []
assert full == []
print(f'stable-core safety floor valid: {len(exports)} tools')"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stable-core safety floor valid:"* ]]
}

@test "stable-core: every and only reviewed export has a closed invocation contract" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
import sys

root = sys.argv[1]
manifest = json.load(open(os.path.join(root, 'MANIFEST.json')))
policy = json.load(open(os.path.join(root, 'config', 'invocation-policy.json')))
invocation_index = json.load(open(os.path.join(root, 'INVOCATION_INDEX.json')))
stable_ids = {
    canonical
    for canonical, export in manifest['exports'].items()
    if 'stable-core' in export['profiles']
}
contract_fields = {
    'contract_status', 'input_schema', 'call_shape', 'capabilities',
    'timeout_ms', 'output_limit',
}
index_contract_fields = {
    'name', 'owner', 'profiles', 'effects', 'capabilities', 'platforms',
    'bash_identifier', 'contract_status', 'result', 'input_schema',
    'call_shape', 'timeout_ms', 'output_limit',
}

assert len(stable_ids) == 26
assert set(policy['exports']) == stable_ids
assert invocation_index['schema_version'] == 1
assert invocation_index['manifest_version'] == manifest['manifest_version']
assert invocation_index['version'] == manifest['version']
assert invocation_index['profile'] == 'stable-core'
assert invocation_index['contract_count'] == 26
assert set(invocation_index['contracts']) == stable_ids
assert len(invocation_index['name_index']) == 26
for canonical, export in manifest['exports'].items():
    is_stable = canonical in stable_ids
    assert all((field in export) == is_stable for field in contract_fields), canonical
    if not is_stable:
        continue

    indexed = invocation_index['contracts'][canonical]
    assert set(indexed) == index_contract_fields
    assert indexed == {field: export[field] for field in index_contract_fields}
    assert invocation_index['name_index'][export['name']] == canonical
    assert invocation_index['modules'][export['owner']] == {
        'file': manifest['modules'][export['owner']]['file'],
    }

    assert export['contract_status'] == 'reviewed'
    assert export['result'] == policy['exports'][canonical]['result']
    assert export['effects'] in (['pure'], ['read'])
    assert export['capabilities'] == []
    assert export['timeout_ms'] == 5000
    assert export['output_limit'] == 65536

    schema = export['input_schema']
    shape = export['call_shape']
    assert schema['type'] == 'object'
    assert schema['additionalProperties'] is False
    assert shape['kind'] == 'argv'
    assert [argument['field'] for argument in shape['arguments']] == list(
        schema['properties'])
    for argument in shape['arguments']:
        field_type = schema['properties'][argument['field']]['type']
        assert argument['mode'] == ('spread' if field_type == 'array' else 'scalar')

assert manifest['exports']['mf:std:validation:validate_path']['effects'] == ['read']
assert manifest['exports']['mf:data:json:json_array']['call_shape']['arguments'] == [
    {'field': 'items', 'mode': 'spread'},
]
assert manifest['exports']['mf:data:json:json_object']['call_shape']['arguments'] == [
    {'field': 'pairs', 'mode': 'spread'},
]
assert manifest['exports']['mf:data:json:json_merge']['call_shape']['arguments'] == [
    {'field': 'objects', 'mode': 'spread'},
]
assert manifest['exports']['mf:data:pure-array:array_join']['call_shape']['arguments'] == [
    {'field': 'delimiter', 'mode': 'scalar'},
    {'field': 'items', 'mode': 'spread'},
]
print('stable-core invocation contracts valid: 26 reviewed, no inferred extras')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"stable-core invocation contracts valid: 26 reviewed"* ]]
}

@test "semantic trust: only reviewed contracts are executable and hazardous modules are explicit" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
import sys

root = sys.argv[1]
manifest = json.load(open(os.path.join(root, 'MANIFEST.json')))
policy = json.load(open(os.path.join(root, 'config', 'semantic-trust-policy.json')))
invocation = json.load(open(os.path.join(root, 'config', 'invocation-policy.json')))

assert policy['schema_version'] == 1
assert policy['default']['execution_exposure'] == 'discovery-only'
assert policy['default']['semantic_status'] == 'unreviewed'
assert 'config/semantic-trust-policy.json' in manifest['derivation']['sources']

trusted = {
    canonical for canonical, export in manifest['exports'].items()
    if export['execution_exposure'] == 'trusted'
}
assert trusted == set(invocation['exports'])
for canonical, export in manifest['exports'].items():
    assert export['semantic_status'] in {'reviewed', 'unreviewed'}
    assert export['execution_exposure'] in {'trusted', 'discovery-only'}
    if canonical in trusted:
        assert export['semantic_status'] == 'reviewed'
        assert export['ownership'] == 'reviewed'
        assert export['contract_status'] == 'reviewed'
        assert export['effects'] in (['pure'], ['read'])
    else:
        assert export['semantic_status'] == 'unreviewed'
        assert export['ownership'] == 'provisional'
        assert 'contract_status' not in export

expected_hazardous = {
    'agent_exec': {'process', 'write', 'destructive'},
    'agent_loop': {'process', 'write'},
    'orchestrate': {'process', 'network', 'write'},
    'otel': {'network', 'write'},
}
for module, effects in expected_hazardous.items():
    module_policy = policy['module_overrides'][module]
    assert module_policy['stability'] == 'experimental'
    assert module_policy['execution_exposure'] == 'discovery-only'
    assert set(module_policy['declared_effects']) == effects
    exports = [
        export for export in manifest['exports'].values()
        if export['owner'] == module
    ]
    assert exports, module
    assert all(export['stability'] == 'experimental' for export in exports)
    assert all(export['execution_exposure'] == 'discovery-only' for export in exports)
    assert all(set(export['declared_effects']) == effects for export in exports)

assert manifest['stats']['trusted_execution_exports'] == len(trusted) == 26
assert manifest['stats']['discovery_only_exports'] == len(manifest['exports']) - 26
print('semantic trust policy valid: 26 trusted, remainder discovery-only')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic trust policy valid: 26 trusted"* ]]
}

@test "semantic trust: LSP discovery carries canonical execution classification" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
import sys

root = sys.argv[1]
manifest = json.load(open(os.path.join(root, 'MANIFEST.json')))
lsp = json.load(open(os.path.join(root, 'FUNCTIONS.lsp.json')))
items = {item['label']: item for item in lsp['completions']}

for name in ('json_get', 'agent_loop_start', 'orch_agent_spawn', 'otel_init'):
    canonical = manifest['name_index'][name]
    export = manifest['exports'][canonical]
    data = items[name]['data']
    assert data['canonicalId'] == canonical
    assert data['executionExposure'] == export['execution_exposure']
    assert data['semanticStatus'] == export['semantic_status']
    assert data['stability'] == export['stability']
    assert data['declaredEffects'] == export['declared_effects']

assert items['json_get']['data']['executionExposure'] == 'trusted'
assert items['agent_loop_start']['data']['executionExposure'] == 'discovery-only'
assert items['agent_loop_start']['data']['stability'] == 'experimental'
print('LSP execution classification matches canonical manifest')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"LSP execution classification matches canonical manifest"* ]]
}

@test "semantic trust: policy cannot self-authorize or classify unknown modules" {
    local fixture="$BATS_TEST_TMPDIR/semantic-trust-policy.invalid.json"

    python3 - "$PROJECT_ROOT/config/semantic-trust-policy.json" "$fixture" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
data = json.load(open(source))
data['default']['execution_exposure'] = 'trusted'
with open(destination, 'w', encoding='utf-8') as handle:
    json.dump(data, handle)
PY
    run env MAINFRAME_SEMANTIC_TRUST_POLICY_PATH="$fixture" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --verify --no-probe
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot grant trusted execution"* ]]

    python3 - "$PROJECT_ROOT/config/semantic-trust-policy.json" "$fixture" <<'PY'
import json
import sys

source, destination = sys.argv[1:]
data = json.load(open(source))
data['module_overrides']['not_a_real_module'] = dict(
    data['module_overrides']['agent_loop'])
with open(destination, 'w', encoding='utf-8') as handle:
    json.dump(data, handle)
PY
    run env MAINFRAME_SEMANTIC_TRUST_POLICY_PATH="$fixture" \
        python3 "$PROJECT_ROOT/scripts/generate-manifest.py" --verify --no-probe
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown modules"* ]]
}

@test "stable-core: invocation policy validation fails closed on closure and shape drift" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import copy
import importlib.util
import json
import os
import sys

root = sys.argv[1]
path = os.path.join(root, 'scripts', 'generate-manifest.py')
spec = importlib.util.spec_from_file_location('generate_manifest_contract_test', path)
module = importlib.util.module_from_spec(spec)
assert spec is not None and spec.loader is not None
spec.loader.exec_module(module)

policy = json.load(open(os.path.join(root, 'config', 'invocation-policy.json')))
expected = set(policy['exports'])
module.validate_invocation_policy(policy, expected)

def rejected(candidate, expected_ids=expected):
    try:
        module.validate_invocation_policy(candidate, expected_ids)
    except SystemExit:
        return
    raise AssertionError('malformed invocation policy was accepted')

missing = copy.deepcopy(policy)
missing['exports'].pop(next(iter(missing['exports'])))
rejected(missing)

extra = copy.deepcopy(policy)
extra['exports']['mf:std:fixture:unknown'] = copy.deepcopy(
    next(iter(extra['exports'].values())))
rejected(extra)

bad_shape = copy.deepcopy(policy)
join = bad_shape['exports']['mf:data:pure-array:array_join']
join['call_shape']['arguments'][1]['mode'] = 'scalar'
rejected(bad_shape)

bad_capability = copy.deepcopy(policy)
next(iter(bad_capability['exports'].values()))['capabilities'] = ['process.exec']
rejected(bad_capability)

bad_result = copy.deepcopy(policy)
next(iter(bad_result['exports'].values()))['result'] = {'kind': 'guessed'}
rejected(bad_result)

print('stable-core invocation policy drift rejected')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"stable-core invocation policy drift rejected"* ]]
}

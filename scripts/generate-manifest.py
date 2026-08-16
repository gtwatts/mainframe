#!/usr/bin/env python3
"""Generate canonical identity and invocation artifacts (A++ Phase 0, WS2/P0-3).

Per docs/CANONICAL_MANIFEST.md, the manifest is generated from the current
registry (FUNCTIONS.json) plus the approved collision policy
(config/function-export-policy.json), and every downstream artifact —
including FUNCTIONS.json itself — must be reproducible from it.

Provisional ownership rule (design doc §8.1): a name with one registration is
owned by its module; a colliding name is provisionally owned by the LAST
definition file in LC_ALL=C order, matching the runtime's last-source-wins
behavior and the dict-merge behavior of JSON consumers. Ownership is marked
provisional; no renames happen in Phase 0.

Usage:
  generate-manifest.py            # write MANIFEST.json and INVOCATION_INDEX.json
  generate-manifest.py --verify   # byte-compare both fresh deterministic
                                  # artifacts, then rebuild and compare
                                  # FUNCTIONS.json
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY_PATH = os.path.join(ROOT, 'FUNCTIONS.json')
POLICY_PATH = os.path.join(ROOT, 'config', 'function-export-policy.json')
STABLE_CORE_PATH = os.path.join(ROOT, 'config', 'stable-core.json')
INVOCATION_POLICY_PATH = os.path.join(ROOT, 'config', 'invocation-policy.json')
# The override is intentionally narrow: regression tests can exercise stale
# checked-in metadata without mutating the repository artifact.
_MANIFEST_PATH_OVERRIDE = os.environ.get('MAINFRAME_MANIFEST_PATH')
MANIFEST_PATH = _MANIFEST_PATH_OVERRIDE or os.path.join(ROOT, 'MANIFEST.json')
INVOCATION_INDEX_PATH = os.environ.get(
    'MAINFRAME_INVOCATION_INDEX_PATH',
    os.path.join(
        os.path.dirname(MANIFEST_PATH) if _MANIFEST_PATH_OVERRIDE else ROOT,
        'INVOCATION_INDEX.json'))

MANIFEST_VERSION = 1
INVOCATION_INDEX_VERSION = 1
REVIEWED_INVOCATION_CONTRACT_COUNT = 26
MINIMUM_BASH_VERSION = (4, 4)
PROTECTED_BASH_ARGS = ('--noprofile', '--norc', '-p', '-c')
FIXED_BASH_CANDIDATES = (
    '/opt/homebrew/bin/bash',
    '/usr/local/bin/bash',
    '/home/linuxbrew/.linuxbrew/bin/bash',
    '/usr/bin/bash',
    '/bin/bash',
)

def canonical_executable(candidate: str) -> str | None:
    """Return one absolute, symlink-resolved executable path or None."""
    if not candidate or not os.path.isabs(candidate):
        return None
    resolved = os.path.realpath(candidate)
    if any(character in resolved for character in ('\n', '\r', '\t')):
        return None
    if not os.path.isfile(resolved) or not os.access(resolved, os.X_OK):
        return None
    return resolved


def protected_bash_environment() -> dict[str, str]:
    """Build a deterministic child environment without shell startup hooks."""
    environment = os.environ.copy()
    for name in list(environment):
        if name in {'BASH_ENV', 'ENV', 'BASHOPTS', 'SHELLOPTS', 'CDPATH', 'GLOBIGNORE'} \
                or name.startswith(('BASH_FUNC_', 'LD_', 'DYLD_')):
            environment.pop(name, None)
    environment['PATH'] = os.pathsep.join(
        ('/usr/bin', '/bin', '/usr/sbin', '/sbin'))
    environment['LC_ALL'] = 'C'
    return environment


def bash_version(candidate: str) -> tuple[int, int] | None:
    """Return a canonical candidate's Bash major/minor, or None."""
    import subprocess
    canonical = canonical_executable(candidate)
    if canonical is None:
        return None
    try:
        probe = subprocess.run(
            [
                canonical,
                *PROTECTED_BASH_ARGS,
                'printf "%s %s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"',
            ],
            capture_output=True, text=True, timeout=5,
            env=protected_bash_environment())
        if probe.returncode != 0:
            return None
        major, minor = (int(value) for value in probe.stdout.split())
        return major, minor
    except (OSError, subprocess.SubprocessError, TypeError, ValueError):
        return None


def resolve_bash() -> str:
    """Resolve Bash 4.4+ for runtime ownership probes or fail closed."""
    override = os.environ.get('MAINFRAME_BASH', '')
    if override:
        if not os.path.isabs(override):
            raise RuntimeError(
                'MAINFRAME_BASH must be an absolute path to a reviewed Bash '
                '4.4 or newer executable')
        canonical = canonical_executable(override)
        version = bash_version(canonical) if canonical is not None else None
        if version is None or version < MINIMUM_BASH_VERSION:
            raise RuntimeError(
                'MAINFRAME_BASH must be an executable Bash 4.4 or newer')
        return canonical
    seen = set()
    for candidate in FIXED_BASH_CANDIDATES:
        canonical = canonical_executable(candidate)
        if canonical is None or canonical in seen:
            continue
        seen.add(canonical)
        version = bash_version(canonical)
        if version is not None and version >= MINIMUM_BASH_VERSION:
            return canonical
    raise RuntimeError(
        'MAINFRAME manifest generation requires Bash 4.4 or newer; '
        'set MAINFRAME_BASH to a supported executable')


def probe_runtime_owners(colliding: dict, root: str) -> dict:
    """Empirically resolve which module's definition the full runtime load
    actually activates for each colliding name.

    Runtime truth: the loader sources the core tier first, then remaining
    libraries, so sorted-file order does NOT decide the winner. The probe
    compares the full-load definition body against each candidate module's
    standalone body. Identical bodies (guarded shims) resolve to the last
    module in LC_ALL=C order — any choice is parity-safe there.
    """
    import subprocess
    bash = resolve_bash()
    owners = {}

    names = sorted(colliding)
    # One full-load spawn for all names: name<TAB>cksum per line.
    loop = ' '.join(f'{n!r}' for n in names)
    full = subprocess.run(
        [bash, *PROTECTED_BASH_ARGS,
         f'export MAINFRAME_LIBS=all; source "{root}/lib/common.sh" >/dev/null 2>&1; '
         f'for n in {loop}; do printf "%s\\t%s\\n" "$n" "$(declare -f "$n" | cksum)"; done'],
        capture_output=True, text=True, timeout=300,
        env=protected_bash_environment())
    full_body = {}
    for line in full.stdout.splitlines():
        parts = line.split('\t')
        if len(parts) == 2:
            full_body[parts[0]] = parts[1]

    for name, modules in colliding.items():
        # One spawn per collision: per-module standalone bodies.
        subs = '; '.join(
            f'( export MAINFRAME_LIBS={m!r}; source "{root}/lib/common.sh" >/dev/null 2>&1; '
            f'printf "%s\\t%s\\n" {m!r} "$(declare -f {name!r} | cksum)" )'
            for m in modules)
        out = subprocess.run([bash, *PROTECTED_BASH_ARGS, subs],
                             capture_output=True, text=True,
                             timeout=120,
                             env=protected_bash_environment())
        module_body = {}
        for line in out.stdout.splitlines():
            parts = line.split('\t')
            if len(parts) == 2:
                module_body[parts[0]] = parts[1]

        target = full_body.get(name)
        matches = [m for m in modules if module_body.get(m) == target and target]
        if matches:
            owners[name] = sorted(matches)[-1]  # identical bodies: any owner is parity-safe
        else:
            owners[name] = None  # caller applies fallback + records anomaly
    return owners

# Category -> pack mapping (design doc §6; 'core' is the reserved kernel pack
# and intentionally has no members yet).
PACK_BY_CATEGORY = {
    'ai': 'agent',
    'data': 'data', 'arrays': 'data', 'parsing': 'data',
    'network': 'network',
    'vcs': 'devops', 'containers': 'devops', 'ci': 'devops',
    'security': 'security', 'crypto': 'security', 'safety': 'security',
}

# Registry 'returns' -> manifest result kind (design doc §3).
RESULT_KIND = {'stdout': 'stdout', 'void': 'none', 'exit_code': 'exit'}

NAME_RE = re.compile(r'^[a-z_][a-z0-9_]*$')
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
MCP_REVIEWED_VARIADIC_CALL_SHAPES = frozenset({'array_join'})
MCP_UNREVIEWED_ARRAY_CALL_SHAPES = frozenset({
    'array_count', 'array_filter', 'array_first', 'array_get',
    'array_intersect', 'array_last', 'array_length', 'array_reverse',
    'array_slice', 'array_sum', 'array_unique',
    'collection_count', 'collection_filter', 'collection_first',
    'collection_intersect', 'collection_last', 'collection_length',
    'collection_reverse', 'collection_slice', 'collection_sum',
    'collection_unique', 'safe_array_get',
})


def _mcp_has_preparable_call_shape(func_name: str, func: dict) -> bool:
    """Return whether legacy MCP metadata maps to argv without guessing.

    Manifest generation is deliberately self-contained so the release archive
    can verify its canonical artifacts without the separately distributed MCP
    wheel. The installed MCP package consumes the resulting manifest profiles;
    this generator remains their source of truth.
    """
    if func_name in MCP_UNREVIEWED_ARRAY_CALL_SHAPES:
        return False
    if not NAME_RE.fullmatch(func_name) or not isinstance(func, dict):
        return False
    if func_name in MCP_REVIEWED_VARIADIC_CALL_SHAPES \
            and func.get('mcp_call_shape') != 'reviewed_variadic':
        params = []
    else:
        params = func.get('params', [])
    if not isinstance(params, list):
        return False
    if not params:
        return True

    names = []
    positions = []
    for param in params:
        if not isinstance(param, dict):
            return False
        name = param.get('name')
        position = param.get('position')
        if (
            not isinstance(name, str)
            or not name
            or not isinstance(position, int)
            or isinstance(position, bool)
            or position < 1
        ):
            return False
        names.append(name)
        positions.append(position)
    return (
        len(names) == len(set(names))
        and len(positions) == len(set(positions))
        and sorted(positions) == list(range(1, len(params) + 1))
    )


def is_mcp_core_export(func_name: str, category: str, func: dict) -> bool:
    """Canonical legacy core-profile predicate used by the manifest."""
    selected = category in MCP_CORE_CATEGORIES or func_name.startswith(
        MCP_CORE_PREFIXES
    )
    return selected and _mcp_has_preparable_call_shape(func_name, func)


def pack_for(category: str) -> str:
    return PACK_BY_CATEGORY.get(category, 'std')


def canonical_id(pack: str, module: str, name: str) -> str:
    # Namespaced names (ci::is_ci) appear verbatim; parsing rule: after the
    # 'mf:' prefix, pack and module are the first two segments (neither may
    # contain ':'), name is the remainder.
    return f'mf:{pack}:{module}:{name}'


def validate_invocation_policy(invocation_policy: dict,
                               expected_ids: set[str]) -> dict:
    """Validate the reviewed stable-core broker contract without inference.

    The invocation policy is deliberately a complete, closed sidecar: every
    stable-core canonical ID has one reviewed contract and no other export is
    allowed to acquire broker metadata through defaults or registry guesses.
    """
    top_level_fields = {'schema_version', 'description', 'profile', 'exports'}
    if not isinstance(invocation_policy, dict) \
            or set(invocation_policy) != top_level_fields:
        raise SystemExit(
            f'invocation policy: fields must be exactly {sorted(top_level_fields)}')
    if invocation_policy.get('schema_version') != 1:
        raise SystemExit('invocation policy: schema_version must be 1')
    if not isinstance(invocation_policy.get('description'), str) \
            or not invocation_policy['description']:
        raise SystemExit('invocation policy: description must be non-empty')
    if invocation_policy.get('profile') != 'stable-core':
        raise SystemExit('invocation policy: profile must be stable-core')

    contracts = invocation_policy.get('exports')
    if not isinstance(contracts, dict):
        raise SystemExit('invocation policy: exports must be an object')

    actual_ids = set(contracts)
    missing = sorted(expected_ids - actual_ids)
    extra = sorted(actual_ids - expected_ids)
    if missing or extra:
        raise SystemExit(
            'invocation policy: canonical stable-core closure mismatch; '
            f'missing={missing}, extra={extra}')

    required_contract_fields = {
        'contract_status', 'input_schema', 'call_shape', 'result', 'effects',
        'capabilities', 'timeout_ms', 'output_limit',
    }
    allowed_effects = {'pure', 'read'}
    for canonical, contract in contracts.items():
        if not isinstance(contract, dict):
            raise SystemExit(
                f'invocation policy: {canonical} contract must be an object')
        if set(contract) != required_contract_fields:
            raise SystemExit(
                f'invocation policy: {canonical} fields must be exactly '
                f'{sorted(required_contract_fields)}')
        if contract['contract_status'] != 'reviewed':
            raise SystemExit(
                f'invocation policy: {canonical} must be reviewed')

        schema = contract['input_schema']
        if not isinstance(schema, dict) or schema.get('type') != 'object':
            raise SystemExit(
                f'invocation policy: {canonical} input_schema must be an object schema')
        if schema.get('additionalProperties') is not False:
            raise SystemExit(
                f'invocation policy: {canonical} must reject additional properties')
        properties = schema.get('properties')
        required = schema.get('required')
        if not isinstance(properties, dict) or not isinstance(required, list):
            raise SystemExit(
                f'invocation policy: {canonical} schema needs properties and required')
        if len(required) != len(set(required)) or not set(required) <= set(properties):
            raise SystemExit(
                f'invocation policy: {canonical} has invalid required fields')

        for field, field_schema in properties.items():
            if not isinstance(field_schema, dict):
                raise SystemExit(
                    f'invocation policy: {canonical}.{field} must be a schema object')
            field_type = field_schema.get('type')
            if field_type == 'array':
                if field_schema.get('items') != {'type': 'string'}:
                    raise SystemExit(
                        f'invocation policy: {canonical}.{field} arrays must contain strings')
                if field not in required and field_schema.get('default') != []:
                    raise SystemExit(
                        f'invocation policy: optional {canonical}.{field} must default to []')
            elif field_type == 'string':
                if field not in required and not isinstance(
                        field_schema.get('default'), str):
                    raise SystemExit(
                        f'invocation policy: optional {canonical}.{field} needs a string default')
            else:
                raise SystemExit(
                    f'invocation policy: {canonical}.{field} must be string or string array')

        call_shape = contract['call_shape']
        if not isinstance(call_shape, dict) or set(call_shape) != {'kind', 'arguments'} \
                or call_shape.get('kind') != 'argv' \
                or not isinstance(call_shape.get('arguments'), list):
            raise SystemExit(
                f'invocation policy: {canonical} call_shape must be argv arguments')
        seen_fields = []
        for argument in call_shape['arguments']:
            if not isinstance(argument, dict) or set(argument) != {'field', 'mode'}:
                raise SystemExit(
                    f'invocation policy: {canonical} argv entries need field and mode')
            field = argument['field']
            if field not in properties or field in seen_fields:
                raise SystemExit(
                    f'invocation policy: {canonical} has unknown or duplicate argv field {field!r}')
            expected_mode = (
                'spread' if properties[field].get('type') == 'array' else 'scalar')
            if argument['mode'] != expected_mode:
                raise SystemExit(
                    f'invocation policy: {canonical}.{field} must use {expected_mode} mode')
            seen_fields.append(field)
        if set(seen_fields) != set(properties):
            raise SystemExit(
                f'invocation policy: {canonical} call_shape must consume every input field')

        result = contract['result']
        if not isinstance(result, dict) or set(result) != {'kind'} \
                or result['kind'] not in {'stdout', 'exit', 'none'}:
            raise SystemExit(
                f'invocation policy: {canonical} result must declare one reviewed kind')

        effects = contract['effects']
        if not isinstance(effects, list) or len(effects) != 1 \
                or effects[0] not in allowed_effects:
            raise SystemExit(
                f'invocation policy: {canonical} effects must be pure or read')
        if contract['capabilities'] != []:
            raise SystemExit(
                f'invocation policy: {canonical} stable-core capabilities must be empty')
        timeout_ms = contract['timeout_ms']
        output_limit = contract['output_limit']
        if isinstance(timeout_ms, bool) or not isinstance(timeout_ms, int) \
                or not 1 <= timeout_ms <= 30_000:
            raise SystemExit(
                f'invocation policy: {canonical} timeout_ms is out of range')
        if isinstance(output_limit, bool) or not isinstance(output_limit, int) \
                or not 1 <= output_limit <= 1024 * 1024:
            raise SystemExit(
                f'invocation policy: {canonical} output_limit is out of range')

    return contracts


def build_manifest(registry: dict, policy: dict, stable_core: dict | None = None,
                   invocation_policy: dict | None = None) -> dict:
    libraries = registry['libraries']

    # --- collision ownership -------------------------------------------------
    # name -> owner module. Single registration: its module. Collision: last
    # definition file in LC_ALL=C order (runtime last-source-wins).
    registrations_by_name = {}
    for lib_name, lib_data in libraries.items():
        for func_name in lib_data.get('functions', {}):
            registrations_by_name.setdefault(func_name, []).append(lib_name)

    collisions = policy.get('collisions', {})
    owner_of = {}
    for name, modules in registrations_by_name.items():
        if len(modules) == 1:
            owner_of[name] = modules[0]

    # Colliding names: resolve the owner the full runtime load actually
    # activates (empirical probe; see probe_runtime_owners). Fallback keeps
    # the previous deterministic rule when a probe is inconclusive.
    colliding = {}
    for name, modules in registrations_by_name.items():
        if len(modules) > 1:
            defs = collisions.get(name, {}).get('definitions', [])
            pool = [os.path.basename(d)[:-3] for d in defs] or list(modules)
            colliding[name] = sorted(set(pool))

    probe_owners = {}
    if '--no-probe' not in sys.argv[1:]:
        probe_owners = probe_runtime_owners(colliding, ROOT)

    anomalies = []
    for name, pool in colliding.items():
        probed = probe_owners.get(name)
        if probed:
            owner_of[name] = probed
        else:
            owner_of[name] = sorted(pool)[-1]
            if '--no-probe' not in sys.argv[1:]:
                anomalies.append(name)

    # --- modules -------------------------------------------------------------
    modules = {}
    for lib_name, lib_data in libraries.items():
        category = lib_data.get('category', 'other')
        modules[lib_name] = {
            'pack': pack_for(category),
            'category': category,
            'file': lib_data.get('file', f'lib/{lib_name}.sh'),
            'registrations': len(lib_data.get('functions', {})),
        }

    # --- exports + name_index ------------------------------------------------
    exports = {}
    name_index = {}
    for name in sorted(registrations_by_name):
        owner = owner_of[name]
        meta = libraries[owner]['functions'][name]
        pack = modules[owner]['pack']
        category = modules[owner]['category']
        cid = canonical_id(pack, owner, name)

        profiles = ['full']
        if is_mcp_core_export(name, category, meta):
            profiles.insert(0, 'core')
        if stable_core and name in stable_core.get('exports', []):
            profiles.insert(0, 'stable-core')

        effects = ['pure'] if meta.get('pure') else []

        exports[cid] = {
            'name': name,
            'owner': owner,
            'summary': meta.get('description', ''),
            'params': meta.get('params', []),
            'result': {'kind': RESULT_KIND.get(meta.get('returns', 'stdout'), 'stdout')},
            'effects': effects,
            'dependencies': [],
            'platforms': ['linux', 'macos'],
            'stability': 'stable',
            'aliases': [],
            'pack': pack,
            'profiles': profiles,
            'ownership': 'provisional',
            'signature': meta.get('signature', name),
            'idempotent': bool(meta.get('idempotent', False)),
            # WS1 MCP charset rule is metadata here, not a filter: every
            # registry name is canonical; only strict bash identifiers are
            # invocable through the MCP tool-name gate.
            'bash_identifier': bool(NAME_RE.match(name)),
        }
        name_index[name] = cid

    # --- registrations (lossless passthrough for registry regeneration) ------
    # Metadata is stored verbatim so any registry field (examples, future
    # additions) round-trips byte-identically.
    registrations = []
    for lib_name, lib_data in libraries.items():
        for func_name, meta in lib_data.get('functions', {}).items():
            registrations.append({
                'module': lib_name,
                'name': func_name,
                'meta': meta,
            })

    packs = sorted({m['pack'] for m in modules.values()} | {'core'})

    # Stable-core assertions (P0-5 freeze rules; fail the build on drift).
    stable_exports = (stable_core or {}).get('exports', [])
    if stable_core:
        max_tools = stable_core.get('mcp', {}).get('max_default_tools', 32)
        missing = [n for n in stable_exports if n not in registrations_by_name]
        colliding = [n for n in stable_exports if len(registrations_by_name.get(n, [])) > 1]
        if missing:
            raise SystemExit(f'stable-core drift: exports missing from registry: {missing}')
        if colliding:
            raise SystemExit(f'stable-core violation: public collisions in set: {colliding}')
        if len(stable_exports) > max_tools:
            raise SystemExit(f'stable-core violation: {len(stable_exports)} exports > cap {max_tools}')

        stable_ids = {name_index[name] for name in stable_exports}
        if invocation_policy is None:
            raise SystemExit(
                'invocation policy: reviewed stable-core contracts are required')
        invocation_contracts = validate_invocation_policy(
            invocation_policy, stable_ids)
        for cid in sorted(stable_ids):
            exports[cid].update(invocation_contracts[cid])

    return {
        'manifest_version': MANIFEST_VERSION,
        # Project/release version, distinct from the manifest schema version.
        # Keeping it in the canonical artifact makes cross-surface version
        # parity independently checkable instead of inferred from the registry.
        'version': registry.get('version', ''),
        'generated': registry.get('generated', ''),
        'derivation': {
            'status': 'provisional',
            'sources': [
                'FUNCTIONS.json',
                'config/function-export-policy.json',
                'config/invocation-policy.json',
            ],
            'owner_rule': 'single registration; collisions resolved by empirical full-load probe (runtime winner), fallback last definition in LC_ALL=C order',
            'probe_anomalies': anomalies,
        },
        'stats': {
            'exports': len(exports),
            'registrations': len(registrations),
            'modules': len(modules),
            'packs': len(packs),
            'collisions_recorded': len(collisions),
            'stable_core_exports': len(stable_exports),
        },
        'packs': packs,
        'modules': modules,
        'exports': exports,
        'name_index': name_index,
        'registrations': registrations,
        'registry_categories': registry.get('stats', {}).get('categories', []),
    }


def build_invocation_index(manifest: dict) -> dict:
    """Build the immutable, compact broker index from reviewed manifest data.

    The broker does not need the multi-megabyte registry passthrough carried by
    MANIFEST.json.  This artifact contains only the stable-core identity,
    ownership, platform, schema, result, and resource-bound fields that the
    broker validates before executing a function.  It is generated alongside
    the manifest, never populated or changed at runtime.
    """
    contract_fields = (
        'name', 'owner', 'profiles', 'effects', 'capabilities', 'platforms',
        'bash_identifier', 'contract_status', 'result', 'input_schema',
        'call_shape', 'timeout_ms', 'output_limit',
    )
    contracts = {}
    name_index = {}
    modules = {}

    for canonical in sorted(manifest['exports']):
        export = manifest['exports'][canonical]
        if export.get('contract_status') != 'reviewed' \
                or 'stable-core' not in export.get('profiles', []):
            continue
        missing = [field for field in contract_fields if field not in export]
        if missing:
            raise SystemExit(
                f'invocation index: {canonical} is missing fields {missing}')
        contract = {field: export[field] for field in contract_fields}
        name = contract['name']
        owner = contract['owner']
        if name in name_index:
            raise SystemExit(
                f'invocation index: duplicate reviewed Bash name {name!r}')
        module = manifest['modules'].get(owner)
        if not isinstance(module, dict) or not isinstance(module.get('file'), str):
            raise SystemExit(
                f'invocation index: {canonical} has no canonical owner module')
        contracts[canonical] = contract
        name_index[name] = canonical
        modules[owner] = {'file': module['file']}

    expected_count = manifest.get('stats', {}).get('stable_core_exports')
    if expected_count != len(contracts):
        raise SystemExit(
            'invocation index: reviewed contract count does not match the '
            f'stable-core closure ({len(contracts)} != {expected_count})')
    if len(contracts) != REVIEWED_INVOCATION_CONTRACT_COUNT:
        raise SystemExit(
            'invocation index: reviewed stable-core closure changed; update '
            'the versioned broker contract count deliberately '
            f'({len(contracts)} != {REVIEWED_INVOCATION_CONTRACT_COUNT})')

    return {
        'schema_version': INVOCATION_INDEX_VERSION,
        'manifest_version': manifest['manifest_version'],
        'version': manifest['version'],
        'profile': 'stable-core',
        'contract_count': len(contracts),
        'contracts': contracts,
        'name_index': name_index,
        'modules': {owner: modules[owner] for owner in sorted(modules)},
    }


def manifest_to_registry(manifest: dict) -> dict:
    """Rebuild FUNCTIONS.json from the manifest (lossless by construction)."""
    libraries = {}
    module_meta = manifest['modules']
    for reg in manifest['registrations']:
        lib = libraries.setdefault(reg['module'], {
            'file': module_meta[reg['module']]['file'],
            'description': _MODULE_DESCRIPTIONS.get(reg['module'], ''),
            'category': module_meta[reg['module']]['category'],
            'functions': {},
        })
        lib['functions'][reg['name']] = reg['meta']
    return {
        'version': manifest['version'],
        'generated': manifest['generated'],
        'stats': {
            'unique_functions': manifest['stats']['exports'],
            'registrations': manifest['stats']['registrations'],
            'total_functions': manifest['stats']['registrations'],
            'total_libraries': manifest['stats']['modules'],
            'categories': manifest['registry_categories'],
        },
        'libraries': libraries,
    }


# Module descriptions are registry metadata not carried per-registration;
# captured at derivation time for lossless round-trip.
_MODULE_DESCRIPTIONS = {}


def dumps_registry(obj: dict) -> str:
    """Match the bash generator's byte format: 2-space indent, non-ASCII raw,
    with 'categories' and 'examples' arrays inline on one line (params stay
    multi-line)."""
    text = json.dumps(obj, indent=2, ensure_ascii=False)

    def inline_arrays(key: str, value: list) -> None:
        nonlocal text
        pattern = re.compile(
            r'"' + key + r'": \[\n(?:\s+(?:"(?:[^"\\]|\\.)*"|-?[0-9.]+|true|false|null),?\n)+\s+\]'
        )
        # Replace one occurrence at a time (values differ per occurrence)
        while True:
            m = pattern.search(text)
            if not m:
                return
            # Rebuild the inline form from the matched block's values
            vals = re.findall(r'"(?:[^"\\]|\\.)*"|-?[0-9.]+|true|false|null',
                              m.group(0).split('\n', 1)[1])
            replacement = f'"{key}": [' + ', '.join(vals) + ']'
            text = text[:m.start()] + replacement + text[m.end():]

    inline_arrays('categories', obj['stats']['categories'])
    # examples values are collected per-occurrence inside inline_arrays
    inline_arrays('examples', [])
    return text + '\n'


def dumps_manifest(obj: dict) -> str:
    """Canonical checked-in MANIFEST.json serialization."""
    return json.dumps(obj, indent=2, ensure_ascii=False) + '\n'


def dumps_invocation_index(obj: dict) -> str:
    """Canonical compact serialization for the checked-in broker index."""
    return json.dumps(
        obj, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n'


def report_first_divergence(label: str, want: str, have: str) -> None:
    """Print a compact, deterministic first-difference diagnostic."""
    for i, (a, b) in enumerate(zip(want, have)):
        if a != b:
            print(f'{label}: first divergence at byte {i}:', file=sys.stderr)
            print(f'  want: {want[max(0, i - 60):i + 60]!r}', file=sys.stderr)
            print(f'  have: {have[max(0, i - 60):i + 60]!r}', file=sys.stderr)
            return
    print(f'{label}: length differs ({len(want)} vs {len(have)})',
          file=sys.stderr)


def main() -> int:
    registry = json.load(open(REGISTRY_PATH))
    policy = json.load(open(POLICY_PATH))
    stable_core = None
    if os.path.exists(STABLE_CORE_PATH):
        stable_core = json.load(open(STABLE_CORE_PATH))
    invocation_policy = None
    if os.path.exists(INVOCATION_POLICY_PATH):
        invocation_policy = json.load(open(INVOCATION_POLICY_PATH))

    global _MODULE_DESCRIPTIONS
    _MODULE_DESCRIPTIONS = {
        lib: data.get('description', '') for lib, data in registry['libraries'].items()
    }

    manifest = build_manifest(
        registry, policy, stable_core, invocation_policy)
    invocation_index = build_invocation_index(manifest)

    if '--verify' in sys.argv[1:]:
        want_manifest = dumps_manifest(manifest)
        try:
            have_manifest = open(MANIFEST_PATH, encoding='utf-8').read()
        except OSError as exc:
            print(f'VERIFY FAIL: cannot read MANIFEST.json: {exc}', file=sys.stderr)
            return 1
        if want_manifest != have_manifest:
            print('VERIFY FAIL: MANIFEST.json is stale; regenerate it from the '
                  'current registry and policy', file=sys.stderr)
            report_first_divergence(
                'MANIFEST.json drift', want_manifest, have_manifest)
            return 1

        want_invocation_index = dumps_invocation_index(invocation_index)
        try:
            have_invocation_index = open(
                INVOCATION_INDEX_PATH, encoding='utf-8').read()
        except OSError as exc:
            print(
                f'VERIFY FAIL: cannot read INVOCATION_INDEX.json: {exc}',
                file=sys.stderr)
            return 1
        if want_invocation_index != have_invocation_index:
            print(
                'VERIFY FAIL: INVOCATION_INDEX.json is stale; regenerate it '
                'from the current manifest and invocation policy',
                file=sys.stderr)
            report_first_divergence(
                'INVOCATION_INDEX.json drift',
                want_invocation_index,
                have_invocation_index)
            return 1

        # Rebuild from the artifact that was actually checked above. This
        # prevents a fresh in-memory manifest from masking a stale checked-in
        # canonical source.
        checked_manifest = json.loads(have_manifest)
        rebuilt = manifest_to_registry(checked_manifest)
        want = dumps_registry(rebuilt)
        have = open(REGISTRY_PATH, encoding='utf-8').read()
        if want == have:
            s = manifest['stats']
            print(f"VERIFY PASS: MANIFEST.json and INVOCATION_INDEX.json match "
                  f"fresh deterministic builds and FUNCTIONS.json regenerates "
                  f"byte-identically "
                  f"({s['exports']} exports, {s['registrations']} registrations, "
                  f"{s['modules']} modules, {s['packs']} packs, "
                  f"{invocation_index['contract_count']} invocation contracts)")
            return 0
        print('VERIFY FAIL: FUNCTIONS.json does not regenerate byte-identically '
              'from MANIFEST.json', file=sys.stderr)
        report_first_divergence('FUNCTIONS.json drift', want, have)
        return 1

    with open(MANIFEST_PATH, 'w', encoding='utf-8') as f:
        f.write(dumps_manifest(manifest))
    with open(INVOCATION_INDEX_PATH, 'w', encoding='utf-8') as f:
        f.write(dumps_invocation_index(invocation_index))
    s = manifest['stats']
    print(f"wrote MANIFEST.json and INVOCATION_INDEX.json: {s['exports']} "
          f"exports, {s['registrations']} registrations, {s['modules']} "
          f"modules, {s['packs']} packs, {s['collisions_recorded']} collisions "
          f"recorded, {invocation_index['contract_count']} invocation contracts")
    return 0


if __name__ == '__main__':
    sys.exit(main())

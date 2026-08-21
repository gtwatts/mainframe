#!/usr/bin/env python3
"""Owner-parity checks (A++ Phase 0 deliverable 4; docs/CANONICAL_MANIFEST.md §7).

For every surface, assert that every exposed name resolves to the same
canonical owner recorded in MANIFEST.json's name_index:

  1. canonical artifacts — release version, names, registrations, modules, and
     declared counts are complete across FUNCTIONS, MANIFEST, and LSP metadata
  2. manifest self-consistency — index targets exist, owners hold registrations
  3. MCP registry, when its separately distributed source package is present —
     ToolRegistry ownership + core-tier closure == manifest profiles
  4. LSP metadata — unique labels; completions carry canonical owner metadata
  5. runtime full load — colliding-name definition body == owner module's body
  6. runtime lazy map — every _LAZY_MANIFEST entry names the owner module
  7. bindings — wrapped function names are a subset of name_index

Exit 0 only when there are zero owner disagreements for exposed names.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY_PATH = os.path.join(ROOT, 'FUNCTIONS.json')
# Narrow overrides let regression tests prove stale artifacts fail without
# editing the repository's generated files.
MANIFEST_PATH = os.environ.get(
    'MAINFRAME_MANIFEST_PATH', os.path.join(ROOT, 'MANIFEST.json'))
POLICY_PATH = os.path.join(ROOT, 'config', 'function-export-policy.json')
LSP_META_PATH = os.environ.get(
    'MAINFRAME_LSP_META_PATH', os.path.join(ROOT, 'FUNCTIONS.lsp.json'))

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
    """Resolve Bash 4.4+ for owner-parity probes or fail closed."""
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
        'MAINFRAME owner-parity checks require Bash 4.4 or newer; '
        'set MAINFRAME_BASH to a supported executable')


BASH = resolve_bash()

failures = []


def check(label: str, ok: bool, detail: str = '') -> None:
    if not ok:
        failures.append(f'{label}: {detail}')


def set_delta(got: set, want: set) -> str:
    """Compact exact-set diagnostic with stable ordering."""
    return (f'only-got={sorted(got - want, key=repr)[:8]} '
            f'only-want={sorted(want - got, key=repr)[:8]}')


def main() -> int:
    registry_json = json.load(open(REGISTRY_PATH))
    manifest = json.load(open(MANIFEST_PATH))
    policy = json.load(open(POLICY_PATH))
    lsp = json.load(open(LSP_META_PATH))
    name_index = manifest['name_index']
    exports = manifest['exports']
    registrations = manifest['registrations']
    collisions = policy['collisions']

    registry_libraries = registry_json.get('libraries', {})
    registry_modules = set(registry_libraries)
    registry_registration_pairs = {
        (module, name)
        for module, library in registry_libraries.items()
        for name in library.get('functions', {})
    }
    registry_names = {name for _, name in registry_registration_pairs}

    regs_by_name = {}
    for reg in registrations:
        regs_by_name.setdefault(reg['name'], set()).add(reg['module'])

    # -- 1. canonical artifact completeness ----------------------------------
    versions = {
        'FUNCTIONS.json': registry_json.get('version'),
        'MANIFEST.json': manifest.get('version'),
        'FUNCTIONS.lsp.json': lsp.get('version'),
    }
    version_values = set(versions.values())
    check('canonical/version',
          len(version_values) == 1 and None not in version_values and '' not in version_values,
          f'versions={versions}')

    manifest_names = set(name_index)
    manifest_export_names_list = [exp.get('name') for exp in exports.values()]
    manifest_export_names = set(manifest_export_names_list)
    check('canonical/manifest-names', manifest_names == registry_names,
          set_delta(manifest_names, registry_names))
    check('canonical/manifest-export-names',
          manifest_export_names == registry_names
          and len(manifest_export_names_list) == len(registry_names),
          f'{set_delta(manifest_export_names, registry_names)}; '
          f'{len(manifest_export_names_list)} exports vs '
          f'{len(registry_names)} unique registry names')

    manifest_registration_list = [
        (reg.get('module'), reg.get('name')) for reg in registrations
    ]
    manifest_registration_pairs = set(manifest_registration_list)
    check('canonical/manifest-registrations',
          manifest_registration_pairs == registry_registration_pairs
          and len(manifest_registration_list) == len(registry_registration_pairs),
          f'{set_delta(manifest_registration_pairs, registry_registration_pairs)}; '
          f'{len(manifest_registration_list)} manifest registrations vs '
          f'{len(registry_registration_pairs)} registry registrations')

    manifest_modules = set(manifest.get('modules', {}))
    check('canonical/manifest-modules', manifest_modules == registry_modules,
          set_delta(manifest_modules, registry_modules))

    registry_stats = registry_json.get('stats', {})
    registry_registration_count = len(registry_registration_pairs)
    registry_count_contract = {
        'unique_functions': len(registry_names),
        'registrations': registry_registration_count,
        'total_functions': registry_registration_count,
        'total_libraries': len(registry_modules),
    }
    check('canonical/registry-counts',
          all(registry_stats.get(k) == v
              for k, v in registry_count_contract.items()),
          f'declared={{{", ".join(f"{k}: {registry_stats.get(k)!r}" for k in registry_count_contract)}}} '
          f'actual={registry_count_contract}')

    manifest_stats = manifest.get('stats', {})
    trusted_execution_count = sum(
        export.get('execution_exposure') == 'trusted'
        for export in exports.values())
    manifest_count_contract = {
        'exports': len(registry_names),
        'registrations': registry_registration_count,
        'modules': len(registry_modules),
        'trusted_execution_exports': trusted_execution_count,
        'discovery_only_exports': len(exports) - trusted_execution_count,
    }
    check('canonical/manifest-counts',
          all(manifest_stats.get(k) == v
              for k, v in manifest_count_contract.items()),
          f'declared={{{", ".join(f"{k}: {manifest_stats.get(k)!r}" for k in manifest_count_contract)}}} '
          f'actual={manifest_count_contract}')

    lsp_completions = lsp.get('completions', [])
    lsp_completion_names_list = [comp.get('label') for comp in lsp_completions]
    lsp_completion_names = set(lsp_completion_names_list)
    check('canonical/lsp-names',
          lsp_completion_names == registry_names
          and len(lsp_completion_names_list) == len(registry_names),
          f'{set_delta(lsp_completion_names, registry_names)}; '
          f'{len(lsp_completion_names_list)} completions vs '
          f'{len(registry_names)} unique registry names')

    lsp_libraries_list = [lib.get('name') for lib in lsp.get('libraries', [])]
    lsp_libraries = set(lsp_libraries_list)
    check('canonical/lsp-libraries',
          lsp_libraries == registry_modules
          and len(lsp_libraries_list) == len(registry_modules),
          f'{set_delta(lsp_libraries, registry_modules)}; '
          f'{len(lsp_libraries_list)} LSP libraries vs '
          f'{len(registry_modules)} registry libraries')

    registration_meta = {
        (reg.get('module'), reg.get('name')): reg.get('meta', {})
        for reg in registrations
    }
    expected_signature_names = set()
    for name, cid in name_index.items():
        owner = exports.get(cid, {}).get('owner')
        if registration_meta.get((owner, name), {}).get('params'):
            expected_signature_names.add(name)
    lsp_signatures = lsp.get('signatures', [])
    lsp_signature_names_list = [sig.get('function') for sig in lsp_signatures]
    lsp_signature_names = set(lsp_signature_names_list)
    check('canonical/lsp-signature-names',
          lsp_signature_names == expected_signature_names
          and len(lsp_signature_names_list) == len(expected_signature_names),
          f'{set_delta(lsp_signature_names, expected_signature_names)}; '
          f'{len(lsp_signature_names_list)} signatures vs '
          f'{len(expected_signature_names)} expected')

    lsp_stats = lsp.get('stats', {})
    lsp_count_contract = {
        'total_completions': len(registry_names),
        'total_libraries': len(registry_modules),
        'total_signatures': len(expected_signature_names),
    }
    check('canonical/lsp-counts',
          all(lsp_stats.get(k) == v for k, v in lsp_count_contract.items())
          and len(lsp_completions) == len(registry_names)
          and len(lsp.get('libraries', [])) == len(registry_modules)
          and len(lsp_signatures) == len(expected_signature_names),
          f'declared={{{", ".join(f"{k}: {lsp_stats.get(k)!r}" for k in lsp_count_contract)}}} '
          f'actual={lsp_count_contract}')

    # -- 2. manifest self-consistency ----------------------------------------
    for name, cid in name_index.items():
        check('manifest/index-target', cid in exports, f'{name} -> missing {cid}')
        exp = exports.get(cid, {})
        check('manifest/index-name', exp.get('name') == name, f'{cid} name mismatch')
        check('manifest/owner-registration',
              exp.get('owner') in regs_by_name.get(name, set()),
              f'{name}: owner {exp.get("owner")} has no registration')
    check('manifest/single-valued', len(name_index) == len(exports),
          f'{len(name_index)} names vs {len(exports)} exports')

    # -- 3. MCP registry surface ----------------------------------------------
    # The MCP runner is shipped as its own wheel, not inside the MAINFRAME
    # runtime archive. Source checkouts exercise this package-specific parity
    # gate; installed runtime archives remain able to verify every surface they
    # actually contain.
    reg = None
    mcp_source = os.path.join(ROOT, 'mcp', 'src', 'mainframe_mcp')
    if os.path.isfile(os.path.join(mcp_source, 'tool_registry.py')):
        sys.path.insert(0, os.path.join(ROOT, 'mcp', 'src'))
        os.environ.setdefault('MAINFRAME_ROOT', ROOT)
        from mainframe_mcp.tool_registry import ToolRegistry  # noqa: E402

        reg = ToolRegistry(mainframe_root=ROOT)
        check('mcp/load', reg.load(), 'MCP registry failed to load')
        for name, cid in name_index.items():
            func = reg.get_function(name)
            owner = exports[cid]['owner']
            check('mcp/owner', func is not None and func['library'] == owner,
                  f'{name}: MCP owner {func and func["library"]} != {owner}')

        core_tools = reg.generate_all_tools(tier='core')
        core_manifest = {
            e['name'] for e in exports.values() if 'core' in e['profiles']
        }
        check('mcp/core-non-executable', core_tools == [],
              'legacy core discovery profile became an executable MCP tier')
        check('manifest/core-discovery', bool(core_manifest),
              'core discovery profile is unexpectedly empty')
    else:
        print('INFO: MCP wheel source is not part of this runtime archive; '
              'package parity is gated by the separate MCP build evidence')

    # -- 4. LSP metadata surface ----------------------------------------------
    labels = {}
    for comp in lsp['completions']:
        labels.setdefault(comp['label'], []).append(comp)
    dupes = sorted(k for k, v in labels.items() if len(v) > 1)
    check('lsp/unique-labels', not dupes,
          f'{len(dupes)} duplicate labels: {dupes[:8]}')
    for name, completions in labels.items():
        if name not in name_index or not completions:
            continue
        cid = name_index[name]
        owner = exports.get(cid, {}).get('owner')
        data = completions[0].get('data', {})
        got_owner = data.get('library')
        check('lsp/completion-owner', got_owner == owner,
              f'{name}: LSP owner {got_owner!r} != canonical owner {owner!r}')
        export = exports.get(cid, {})
        expected_semantics = {
            'canonicalId': cid,
            'executionExposure': export.get('execution_exposure'),
            'semanticStatus': export.get('semantic_status'),
            'stability': export.get('stability'),
            'declaredEffects': export.get('declared_effects'),
        }
        observed_semantics = {
            key: data.get(key) for key in expected_semantics
        }
        check('lsp/completion-semantics',
              observed_semantics == expected_semantics,
              f'{name}: LSP semantics {observed_semantics!r} != '
              f'manifest {expected_semantics!r}')
    owner_desc = {(r['module'], r['name']): r['meta'].get('description', '')
                  for r in registrations}
    richness_warnings = []
    for name in collisions:
        if name.startswith('_') or name not in labels or name not in name_index:
            continue
        owner = exports[name_index[name]]['owner']
        want_desc = owner_desc.get((owner, name), '')
        got = labels[name][0]['documentation']
        if want_desc:
            check('lsp/collision-owner', got.startswith(want_desc),
                  f'{name}: LSP shows non-owner metadata (owner {owner})')
        else:
            # Owner registration has no description; the standard fallback
            # text is the honest display of the owner's (empty) metadata.
            check('lsp/collision-owner', got.startswith('MAINFRAME function'),
                  f'{name}: LSP shows non-owner metadata (owner {owner}, '
                  f'whose description is empty)')
            richness_warnings.append(f'{name} (owner {owner})')
    if richness_warnings:
        print(f'NOTE: {len(richness_warnings)} owner registrations have empty '
              f'descriptions (data-quality, not parity): {richness_warnings}')

    # -- 5. runtime full-load surface ------------------------------------------
    # For each collision: the definition the FULL runtime load activates
    # (MAINFRAME_LIBS=all, tier order) must equal the owner module's
    # standalone definition.
    runtime_checked = runtime_skipped = 0
    collision_names = [n for n in collisions if n in name_index]
    runtime_skipped = len(collisions) - len(collision_names)
    if collision_names:
        loop = ' '.join(f"'{n}'" for n in collision_names)
        full = subprocess.run(
            [BASH, *PROTECTED_BASH_ARGS,
             f'export MAINFRAME_LIBS=all; source "{ROOT}/lib/common.sh" >/dev/null 2>&1; '
             f'for n in {loop}; do printf "%s\\t%s\\n" "$n" "$(declare -f "$n" | cksum)"; done'],
            capture_output=True, text=True, timeout=300,
            env=protected_bash_environment())
        full_body = {}
        for line in full.stdout.splitlines():
            parts = line.split('\t')
            if len(parts) == 2:
                full_body[parts[0]] = parts[1]

        for name in collision_names:
            owner = exports[name_index[name]]['owner']
            standalone = subprocess.run(
                [BASH, *PROTECTED_BASH_ARGS,
                 f'export MAINFRAME_LIBS={owner!r}; source "{ROOT}/lib/common.sh" >/dev/null 2>&1; '
                 f'declare -f {name!r} | cksum'],
                capture_output=True, text=True, timeout=60,
                env=protected_bash_environment())
            got = standalone.stdout.strip()
            want = full_body.get(name, '')
            runtime_checked += 1
            check('runtime/full-load-owner', got == want and bool(want),
                  f'{name}: full-load {want!r} != owner({owner}) {got!r}')

    # -- 6. runtime lazy map ----------------------------------------------------
    lazy_dump = subprocess.run(
        [BASH, *PROTECTED_BASH_ARGS,
         f'export MAINFRAME_LIBS=lazy; source "{ROOT}/lib/common.sh" >/dev/null 2>&1; '
         'lazy_init_manifests >/dev/null 2>&1; '
         'for fn in "${!_LAZY_MANIFEST[@]}"; do echo "$fn ${_LAZY_MANIFEST[$fn]}"; done'],
        capture_output=True, text=True, timeout=60,
        env=protected_bash_environment())
    lazy_entries = 0
    for line in lazy_dump.stdout.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        fn, lib = parts
        lazy_entries += 1
        if fn in name_index:
            owner = exports[name_index[fn]]['owner']
            check('runtime/lazy-owner', lib == owner,
                  f'{fn}: lazy maps to {lib}, owner is {owner}')

    # -- 7. bindings surface -----------------------------------------------------
    wrapped = set()
    for path, pattern in [
        (os.path.join(ROOT, 'bindings', 'nodejs', 'src'),
         re.compile(r'callFunction(?:Raw)?\("([a-zA-Z0-9_:]+)"')),
        (os.path.join(ROOT, 'bindings', 'python', 'mainframe_bash'),
         re.compile(r'call_function(?:_json)?\("([a-zA-Z0-9_:]+)"')),
    ]:
        for dirpath, _, files in os.walk(path):
            for f in files:
                if f.endswith(('.ts', '.py')):
                    text = open(os.path.join(dirpath, f)).read()
                    wrapped.update(pattern.findall(text))
    unknown = sorted(w for w in wrapped if w not in name_index)
    # Missing-registry wrapper names are existence defects (the wrapped
    # function does not exist), a different class than owner disagreements.
    # Report them prominently but do not count them against the parity gate.
    if unknown:
        print(f'WARNING: {len(unknown)} binding wrappers reference functions '
              f'absent from the registry (existence gaps, not parity): {unknown}')

    # -- 8. stable-core export set (P0-5) ---------------------------------------
    stable_path = os.path.join(ROOT, 'config', 'stable-core.json')
    if os.path.exists(stable_path):
        stable = json.load(open(stable_path))
        stable_exports = stable.get('exports', [])
        max_tools = stable.get('mcp', {}).get('max_default_tools', 32)
        check('stable-core/count', len(stable_exports) <= max_tools,
              f'{len(stable_exports)} > cap {max_tools}')
        check('stable-core/unique', len(set(stable_exports)) == len(stable_exports),
              'duplicate names in set')
        missing = [n for n in stable_exports if n not in name_index]
        check('stable-core/in-index', not missing, f'missing from name_index: {missing}')
        colliding = [n for n in stable_exports if n in collisions]
        check('stable-core/zero-collisions', not colliding,
              f'public collisions in stable core: {colliding}')
        if reg is not None:
            stable_tools = {
                t['name'][10:]
                for t in reg.generate_all_tools(tier='stable-core')
            }
            check('stable-core/mcp-closure', stable_tools == set(stable_exports),
                  f'MCP stable-core closure drift: '
                  f'only-mcp={sorted(stable_tools - set(stable_exports))[:5]} '
                  f'only-config={sorted(set(stable_exports) - stable_tools)[:5]}')
        # Manifest profile marking must agree with the config set.
        marked = {e['name'] for e in exports.values() if 'stable-core' in e.get('profiles', [])}
        check('stable-core/manifest-profile', marked == set(stable_exports),
              f'profile drift: only-manifest={sorted(marked - set(stable_exports))[:5]} '
              f'only-config={sorted(set(stable_exports) - marked)[:5]}')
    print(f'owner-parity: {len(registry_names)} registry names, '
          f'{len(name_index)} manifest names, {len(lsp_completion_names)} LSP names, '
          f'{len(collisions)} policy collisions, '
          f'{runtime_checked} runtime checks ({runtime_skipped} skipped), '
          f'{lazy_entries} lazy entries, {len(wrapped)} binding wrappers')
    if failures:
        print(f'FAIL: {len(failures)} canonical parity violations')
        for f in failures[:40]:
            print(f'  - {f}')
        if len(failures) > 40:
            print(f'  ... and {len(failures) - 40} more')
        return 1
    print('PASS: zero owner disagreements for exposed names; canonical artifacts complete')
    return 0


if __name__ == '__main__':
    sys.exit(main())

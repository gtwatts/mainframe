"""Tool registry - parses FUNCTIONS.json and generates MCP tool definitions."""

import copy
import json
import os
import re
from typing import Dict, List, Any, Optional

from .authorization import (
    is_mcp_advertisable,
    is_mcp_core_export,
    normalize_invocation_metadata,
    REVIEWED_VARIADIC_CALL_SHAPES,
    VALID_TIERS,
)
from .runtime_root import RuntimeIdentity, resolve_mainframe_root


BROKER_CANONICAL_ID_RE = re.compile(
    r'^mf:[a-z][a-z0-9-]*:[a-zA-Z0-9_-]+:[a-z_][a-z0-9_]*$'
)
BROKER_FUNCTION_RE = re.compile(r'^[a-z_][a-z0-9_]*$')
BROKER_OWNER_RE = re.compile(r'^[a-zA-Z0-9_-]+$')
BROKER_MODULE_FILE_RE = re.compile(r'^lib/[a-zA-Z0-9_-]+\.sh$')
BROKER_EFFECTS = frozenset({'pure', 'read'})
BROKER_PLATFORMS = frozenset({'linux', 'macos'})
BROKER_MAX_TIMEOUT_MS = 30_000
BROKER_MAX_OUTPUT_LIMIT = 1_048_576


class ToolRegistry:
    """Registry of MAINFRAME functions as MCP tools."""

    def __init__(
        self,
        mainframe_root: Optional[str] = None,
        runtime: Optional[RuntimeIdentity] = None,
    ):
        if runtime is not None and mainframe_root is not None:
            raise ValueError('provide runtime or mainframe_root, not both')
        self.runtime = runtime
        self.mainframe_root = (
            str(runtime.root)
            if runtime is not None
            else resolve_mainframe_root(mainframe_root)
        )
        self.functions_json_path = os.path.join(self.mainframe_root, 'FUNCTIONS.json')
        self.manifest_path = os.path.join(self.mainframe_root, 'MANIFEST.json')
        self._functions: Dict[str, Any] = {}
        self.functions = self._functions
        self._manifest: Dict[str, Any] = {}
        self._stable_contract_names: Optional[set[str]] = None
        self._loaded = False

    def _load_manifest(self) -> bool:
        """Load the owner-parity oracle, rejecting malformed manifests."""
        if self.runtime is not None:
            self.runtime.assert_current()
        if not os.path.exists(self.manifest_path):
            return False
        try:
            with open(self.manifest_path, 'r', encoding='utf-8') as f:
                manifest = json.load(f)
        except (json.JSONDecodeError, OSError):
            return False
        if self.runtime is not None:
            self.runtime.assert_current()

        if (
            not isinstance(manifest, dict)
            or manifest.get('manifest_version') != 1
            or not isinstance(manifest.get('name_index'), dict)
            or not isinstance(manifest.get('exports'), dict)
            or not isinstance(manifest.get('modules'), dict)
        ):
            return False

        self._manifest = manifest
        return True

    @staticmethod
    def _function_record(
        name: str,
        owner: str,
        library: Dict[str, Any],
        metadata: Dict[str, Any],
        canonical_id: str,
        manifest_export: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Build one owner-resolved registry record."""
        return {
            'name': name,
            'library': owner,
            'file': library.get('file', ''),
            'category': library.get('category', 'other'),
            'description': metadata.get('description', ''),
            'signature': metadata.get('signature', name),
            'params': metadata.get('params', []),
            'returns': metadata.get('returns', 'stdout'),
            'idempotent': metadata.get('idempotent', False),
            'pure': metadata.get('pure', False),
            'canonical_id': canonical_id,
            'manifest_export': manifest_export,
        }

    def _apply_manifest_owners(self, libraries: Dict[str, Any]) -> bool:
        """Resolve every loaded name through a valid canonical manifest.

        No registration is allowed to retain dict-merge ownership or lack a
        canonical ID. A malformed or incomplete owner mapping fails the whole
        registry load instead of leaving a partially canonical MCP surface.
        """
        if not self._load_manifest():
            return False

        name_index = self._manifest['name_index']
        exports = self._manifest['exports']
        resolved: Dict[str, Any] = {}
        for name in self._functions:
            cid = name_index.get(name)
            manifest_export = exports.get(cid) if isinstance(cid, str) else None
            if (
                not isinstance(cid, str)
                or not cid.startswith('mf:')
                or not isinstance(manifest_export, dict)
                or manifest_export.get('name') != name
            ):
                return False

            owner = manifest_export.get('owner')
            if not isinstance(owner, str) or not owner:
                return False
            owner_lib = libraries.get(owner, {})
            owner_meta = owner_lib.get('functions', {}).get(name)
            if not isinstance(owner_meta, dict):
                return False

            resolved[name] = self._function_record(
                name, owner, owner_lib, owner_meta, cid, manifest_export
            )

        self._functions.clear()
        self._functions.update(resolved)
        return True

    @staticmethod
    def _valid_broker_input_schema(schema: Any) -> bool:
        """Validate the closed JSON-schema subset understood by the broker."""
        if (
            not isinstance(schema, dict)
            or schema.get('type') != 'object'
            or schema.get('additionalProperties') is not False
            or not isinstance(schema.get('properties'), dict)
        ):
            return False

        properties = schema['properties']
        required = schema.get('required', [])
        if (
            not isinstance(required, list)
            or any(not isinstance(name, str) for name in required)
            or len(required) != len(set(required))
            or not set(required).issubset(properties)
        ):
            return False

        for name, property_schema in properties.items():
            if not isinstance(name, str) or not isinstance(property_schema, dict):
                return False
            property_type = property_schema.get('type')
            if property_type == 'string':
                default = property_schema.get('default')
                if 'default' in property_schema and not isinstance(default, str):
                    return False
                enum = property_schema.get('enum')
                if enum is not None and (
                    not isinstance(enum, list)
                    or not enum
                    or any(not isinstance(value, str) for value in enum)
                ):
                    return False
            elif property_type == 'array':
                if property_schema.get('items') != {'type': 'string'}:
                    return False
                default = property_schema.get('default')
                if 'default' in property_schema and (
                    not isinstance(default, list)
                    or any(not isinstance(value, str) for value in default)
                ):
                    return False
            else:
                return False
        return True

    def _valid_stable_contract(
        self, name: str, function: Dict[str, Any]
    ) -> bool:
        """Return whether one export is safe to delegate to the broker."""
        canonical_id = function.get('canonical_id')
        export = function.get('manifest_export')
        module = self._manifest['modules'].get(function.get('library'))
        if (
            not isinstance(canonical_id, str)
            or not BROKER_CANONICAL_ID_RE.fullmatch(canonical_id)
            or not isinstance(export, dict)
            or not isinstance(module, dict)
            or not isinstance(module.get('file'), str)
            or not BROKER_MODULE_FILE_RE.fullmatch(module['file'])
            or module['file'] != function.get('file')
            or export.get('name') != name
            or export.get('owner') != function.get('library')
            or export.get('bash_identifier') is not True
            or export.get('contract_status') != 'reviewed'
        ):
            return False

        if (
            not BROKER_FUNCTION_RE.fullmatch(name)
            or not BROKER_OWNER_RE.fullmatch(function['library'])
            or self._manifest['name_index'].get(name) != canonical_id
            or self._manifest['exports'].get(canonical_id) is not export
        ):
            return False

        profiles = export.get('profiles')
        effects = export.get('effects')
        capabilities = export.get('capabilities')
        platforms = export.get('platforms')
        result = export.get('result')
        timeout_ms = export.get('timeout_ms')
        output_limit = export.get('output_limit')
        if (
            not isinstance(profiles, list)
            or 'stable-core' not in profiles
            or not isinstance(effects, list)
            or not effects
            or any(effect not in BROKER_EFFECTS for effect in effects)
            or capabilities != []
            or not isinstance(platforms, list)
            or not platforms
            or any(platform not in BROKER_PLATFORMS for platform in platforms)
            or not isinstance(result, dict)
            or set(result) != {'kind'}
            or result.get('kind') not in {'stdout', 'exit', 'none'}
            or not isinstance(timeout_ms, int)
            or isinstance(timeout_ms, bool)
            or not 1 <= timeout_ms <= BROKER_MAX_TIMEOUT_MS
            or not isinstance(output_limit, int)
            or isinstance(output_limit, bool)
            or not 1 <= output_limit <= BROKER_MAX_OUTPUT_LIMIT
        ):
            return False

        schema = export.get('input_schema')
        call_shape = export.get('call_shape')
        if (
            not self._valid_broker_input_schema(schema)
            or not isinstance(call_shape, dict)
            or call_shape.get('kind') != 'argv'
            or not isinstance(call_shape.get('arguments'), list)
        ):
            return False

        seen_fields = set()
        for argument in call_shape['arguments']:
            if not isinstance(argument, dict):
                return False
            field = argument.get('field')
            mode = argument.get('mode')
            if (
                not isinstance(field, str)
                or field in seen_fields
                or field not in schema['properties']
            ):
                return False
            seen_fields.add(field)
            expected_mode = (
                'scalar'
                if schema['properties'][field].get('type') == 'string'
                else 'spread'
            )
            if mode != expected_mode:
                return False

        return seen_fields == set(schema['properties'])

    def _get_stable_contract_names(self) -> set[str]:
        """Load and validate the complete stable-core broker closure."""
        if self._stable_contract_names is not None:
            return self._stable_contract_names

        stable_path = os.path.join(
            self.mainframe_root, 'config', 'stable-core.json'
        )
        try:
            if self.runtime is not None:
                self.runtime.assert_current()
            with open(stable_path, 'r', encoding='utf-8') as stable_file:
                stable_config = json.load(stable_file)
        except (json.JSONDecodeError, OSError):
            self._stable_contract_names = set()
            return self._stable_contract_names
        if self.runtime is not None:
            self.runtime.assert_current()

        names = stable_config.get('exports') if isinstance(stable_config, dict) else None
        if (
            not isinstance(names, list)
            or not names
            or any(not isinstance(name, str) for name in names)
            or len(names) != len(set(names))
        ):
            self._stable_contract_names = set()
            return self._stable_contract_names

        selected = set(names)
        if any(
            name not in self._functions
            or not self._valid_stable_contract(name, self._functions[name])
            for name in selected
        ):
            # The stable tier is an atomic safety floor. One missing or stale
            # contract closes the whole tier rather than silently shrinking or
            # falling back to legacy direct Bash execution.
            selected = set()
        self._stable_contract_names = selected
        return selected

    def load(self) -> bool:
        """Load FUNCTIONS.json and build function registry."""
        if self.runtime is not None:
            self.runtime.assert_current()
        if self._loaded:
            return True

        if not os.path.exists(self.functions_json_path):
            print(f"Warning: FUNCTIONS.json not found at {self.functions_json_path}")
            return False

        try:
            with open(self.functions_json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            return False
        if self.runtime is not None:
            self.runtime.assert_current()

        if not isinstance(data, dict) or not isinstance(data.get('libraries'), dict):
            return False

        # Extract functions from all libraries
        libraries = data.get('libraries', {})
        for lib_name, lib_data in libraries.items():
            lib_file = lib_data.get('file', '')
            lib_category = lib_data.get('category', 'other')

            functions = lib_data.get('functions', {})
            for func_name, func_data in functions.items():
                self._functions[func_name] = {
                    'name': func_name,
                    'library': lib_name,
                    'file': lib_file,
                    'category': lib_category,
                    'description': func_data.get('description', ''),
                    'signature': func_data.get('signature', func_name),
                    'params': func_data.get('params', []),
                    'returns': func_data.get('returns', 'stdout'),
                    'idempotent': func_data.get('idempotent', False),
                    'pure': func_data.get('pure', False),
                }

        if not self._apply_manifest_owners(libraries):
            self._functions.clear()
            return False

        for func_name in REVIEWED_VARIADIC_CALL_SHAPES:
            func = self._functions.get(func_name)
            if func is None:
                continue
            self._functions[func_name] = normalize_invocation_metadata(
                func_name, func
            )

        self._loaded = True
        return True

    def get_function(self, name: str) -> Optional[Dict[str, Any]]:
        """Get function metadata by name."""
        self.load()
        return self._functions.get(name)

    def get_all_functions(self) -> Dict[str, Dict[str, Any]]:
        """Get all function metadata."""
        self.load()
        return self._functions

    def generate_tool_schema(
        self, func_name: str, tier: str = 'full'
    ) -> Optional[Dict[str, Any]]:
        """Generate MCP tool schema for a function."""
        if tier not in VALID_TIERS:
            return None
        func = self.get_function(func_name)
        if not func or not is_mcp_advertisable(func_name, func):
            return None

        if tier == 'stable-core':
            if func_name not in self._get_stable_contract_names():
                return None
            input_schema = copy.deepcopy(
                func['manifest_export']['input_schema']
            )
            return {
                'name': f'mainframe_{func_name}',
                'description': func.get(
                    'description', f'MAINFRAME function: {func_name}'
                ),
                'inputSchema': input_schema,
            }

        # Build input schema from params
        properties = {}
        required = []

        params = sorted(
            func.get('params', []),
            key=lambda param: param.get('position', 0),
        )
        effective_required_positions = [
            param['position']
            for param in params
            if param.get('required', True) and param.get('default') is None
        ]
        last_required_position = max(effective_required_positions, default=0)
        if params:
            for param in params:
                param_name = param.get('name', 'arg')
                param_required = param.get('required', True)
                param_default = param.get('default')

                properties[param_name] = {
                    'type': 'string',
                    'description': f'Parameter: {param_name}'
                }

                if param_default is not None:
                    properties[param_name]['default'] = str(param_default)

                if (
                    param_required and param_default is None
                ) or param['position'] < last_required_position:
                    required.append(param_name)
        else:
            # Function with variadic args
            properties['args'] = {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Arguments to pass to the function'
            }

        input_schema = {
            'type': 'object',
            'properties': properties,
            'additionalProperties': False,
        }
        # Only include 'required' if there are required params
        if required:
            input_schema['required'] = required

        return {
            'name': f'mainframe_{func_name}',
            'description': func.get('description', f'MAINFRAME function: {func_name}'),
            'inputSchema': input_schema
        }

    def generate_all_tools(self, tier: str = 'stable-core') -> List[Dict[str, Any]]:
        """Generate MCP tool definitions.

        Args:
            tier: 'stable-core' for the curated stable public core (default,
                  per config/stable-core.json), 'core' for the legacy broad
                  tier, 'full' for everything.
        """
        if tier not in VALID_TIERS or not self.load():
            return []
        tools = []

        stable_names = None
        if tier == 'stable-core':
            stable_names = self._get_stable_contract_names()

        for func_name, func_data in self._functions.items():
            if tier == 'stable-core':
                if func_name not in stable_names:
                    continue
            elif tier == 'core':
                category = func_data.get('category', '')
                if not is_mcp_core_export(func_name, category, func_data):
                    continue

            schema = self.generate_tool_schema(func_name, tier=tier)
            if schema:
                tools.append(schema)

        return tools

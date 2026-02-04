"""Tool registry - parses FUNCTIONS.json and generates MCP tool definitions."""

import json
import os
from typing import Dict, List, Any, Optional

class ToolRegistry:
    """Registry of MAINFRAME functions as MCP tools."""

    def __init__(self, mainframe_root: Optional[str] = None):
        self.mainframe_root = mainframe_root or os.environ.get(
            'MAINFRAME_ROOT',
            os.path.expanduser('~/.mainframe')
        )
        self.functions_json_path = os.path.join(self.mainframe_root, 'FUNCTIONS.json')
        self._functions: Dict[str, Any] = {}
        self._loaded = False

    def load(self) -> bool:
        """Load FUNCTIONS.json and build function registry."""
        if self._loaded:
            return True

        if not os.path.exists(self.functions_json_path):
            print(f"Warning: FUNCTIONS.json not found at {self.functions_json_path}")
            return False

        with open(self.functions_json_path, 'r') as f:
            data = json.load(f)

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

    def generate_tool_schema(self, func_name: str) -> Optional[Dict[str, Any]]:
        """Generate MCP tool schema for a function."""
        func = self.get_function(func_name)
        if not func:
            return None

        # Build input schema from params
        properties = {}
        required = []

        params = func.get('params', [])
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

                if param_required and param_default is None:
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
        }
        # Only include 'required' if there are required params
        if required:
            input_schema['required'] = required

        return {
            'name': f'mainframe_{func_name}',
            'description': func.get('description', f'MAINFRAME function: {func_name}'),
            'inputSchema': input_schema
        }

    def generate_all_tools(self, tier: str = 'core') -> List[Dict[str, Any]]:
        """Generate MCP tool definitions for all functions.

        Args:
            tier: 'core' for essential functions (~200), 'full' for all
        """
        self.load()
        tools = []

        # Core tier includes common categories
        core_categories = {'data', 'strings', 'validation', 'ai', 'files', 'output'}
        core_prefixes = ['json_', 'validate_', 'ensure_', 'atomic_', 'output_',
                        'usop_', 'trim_', 'to_', 'is_', 'array_']

        for func_name, func_data in self._functions.items():
            if tier == 'core':
                # Filter for core functions
                category = func_data.get('category', '')
                if category not in core_categories:
                    # Check prefixes
                    if not any(func_name.startswith(p) for p in core_prefixes):
                        continue

            schema = self.generate_tool_schema(func_name)
            if schema:
                tools.append(schema)

        return tools

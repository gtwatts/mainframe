#!/usr/bin/env python3
"""
Parse Mainframe bash libraries and generate FUNCTIONS.json entries.
Extracts function definitions, parameters, and descriptions from lib/*.sh files.
"""

import os
import re
import json
import glob
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, field, asdict


@dataclass
class FunctionParam:
    name: str
    position: int
    required: bool = True
    default: Optional[str] = None


@dataclass
class FunctionInfo:
    description: str
    signature: str
    params: List[FunctionParam] = field(default_factory=list)
    returns: str = "stdout"
    idempotent: bool = False
    pure: bool = False


@dataclass
class LibraryInfo:
    file: str
    description: str
    category: str
    functions: Dict[str, FunctionInfo] = field(default_factory=dict)


class BashParser:
    """Parse bash function definitions from .sh files."""
    
    # Pattern to match function definitions
    FUNCTION_PATTERNS = [
        # function name() { or name() {
        r'^(?:function\s+)?(\w+)\s*\(\s*\)\s*\{',
        # function name { (bash style)
        r'^function\s+(\w+)\s*\{',
    ]
    
    # Pattern to extract usage from comments
    USAGE_PATTERN = re.compile(
        r'#\s*Usage:\s*([^\n]+)',
        re.IGNORECASE
    )
    
    # Pattern to extract @param from comments
    PARAM_PATTERN = re.compile(
        r'#\s*@param\s+(\w+)\s*(?:\{([^}]+)\})?\s*(.+)',
        re.IGNORECASE
    )
    
    def __init__(self, lib_dir: str):
        self.lib_dir = Path(lib_dir)
        self.libraries: Dict[str, LibraryInfo] = {}
        
    def parse_all(self) -> Dict[str, LibraryInfo]:
        """Parse all .sh files in the library directory."""
        sh_files = sorted(self.lib_dir.glob('*.sh'))
        
        for sh_file in sh_files:
            lib_name = sh_file.stem
            self.libraries[lib_name] = self._parse_file(sh_file)
            
        return self.libraries
    
    def _parse_file(self, filepath: Path) -> LibraryInfo:
        """Parse a single .sh file."""
        content = filepath.read_text(encoding='utf-8', errors='ignore')
        lines = content.split('\n')
        
        # Extract file-level description from header
        description = self._extract_file_description(content)
        category = self._categorize_library(filepath.stem)
        
        lib_info = LibraryInfo(
            file=f"lib/{filepath.name}",
            description=description,
            category=category
        )
        
        # Find all function definitions
        i = 0
        while i < len(lines):
            line = lines[i]
            func_name = self._extract_function_name(line)
            
            if func_name:
                # Look backward for comments (description)
                desc_lines = []
                j = i - 1
                while j >= 0 and (lines[j].strip().startswith('#') or lines[j].strip() == ''):
                    if lines[j].strip().startswith('#'):
                        text = lines[j].strip('#').strip()
                        # Skip separator lines and shellcheck directives
                        if not self._is_noise_line(text):
                            desc_lines.insert(0, text)
                    j -= 1
                
                # Look forward for usage example and @param annotations
                usage = None
                param_annotations = {}
                for k in range(max(0, i-10), min(i + 20, len(lines))):
                    usage_match = self.USAGE_PATTERN.search(lines[k])
                    if usage_match:
                        usage = usage_match.group(1).strip()
                    
                    param_match = self.PARAM_PATTERN.search(lines[k])
                    if param_match:
                        param_name = param_match.group(1)
                        param_type = param_match.group(2) or 'string'
                        param_desc = param_match.group(3)
                        param_annotations[param_name] = {'type': param_type, 'desc': param_desc}
                
                # Build function info
                func_info = self._build_function_info(
                    func_name, desc_lines, usage, param_annotations, lines, i
                )
                lib_info.functions[func_name] = func_info
            
            i += 1
        
        return lib_info
    
    def _is_noise_line(self, text: str) -> bool:
        """Check if a line is noise (separator, shellcheck, etc.)."""
        noise_patterns = [
            r'^={5,}',  # ======
            r'^-{5,}',  # ------
            r'^\*{5,}', # ******
            r'^shellcheck',
            r'^vim?:',
            r'^emacs:',
            r'^#.*\$Id',
            r'^\s*$',
        ]
        return any(re.match(p, text) for p in noise_patterns)
    
    def _extract_function_name(self, line: str) -> Optional[str]:
        """Extract function name from a line if it's a function definition."""
        # function name() { or name() {
        match = re.match(r'^(?:function\s+)?(\w+)\s*\(\s*\)\s*\{?\s*$', line.strip())
        if match:
            return match.group(1)
        
        # function name { (bash style without parens)
        match = re.match(r'^function\s+(\w+)\s*\{?\s*$', line.strip())
        if match:
            return match.group(1)
        
        return None
    
    def _extract_file_description(self, content: str) -> str:
        """Extract the file-level description from header comments."""
        lines = content.split('\n')[:30]  # Check first 30 lines
        desc_lines = []
        
        for line in lines:
            stripped = line.strip()
            if stripped.startswith('#'):
                # Skip shebang and separator lines
                if stripped.startswith('#!') or '====' in stripped or stripped == '#':
                    continue
                # Extract description text
                text = stripped.lstrip('#').strip()
                if text and not text.startswith('shellcheck') and not re.match(r'^={3,}', text):
                    desc_lines.append(text)
            elif stripped and not stripped.startswith('#'):
                break
        
        # Take first 2-3 meaningful lines
        if desc_lines:
            desc = ' '.join(desc_lines[:3])
            # Clean up
            desc = re.sub(r'\s+', ' ', desc).strip()
            if len(desc) > 200:
                desc = desc[:197] + '...'
            return desc
        return f"Library functions from {Path(content).name}"
    
    def _categorize_library(self, lib_name: str) -> str:
        """Categorize a library based on its name."""
        categories = {
            # AI/LLM related
            'agent_ai': 'ai',
            'agent_context': 'ai',
            'agent_exec': 'ai',
            'llm': 'ai',
            'llm_': 'ai',
            'embeddings': 'ai',
            'vectordb': 'ai',
            'rag': 'ai',
            'awm': 'ai',
            
            # Orchestration
            'orchestrate': 'orchestration',
            'workpool': 'orchestration',
            'taskgraph': 'orchestration',
            'taskstate': 'orchestration',
            'workflow': 'orchestration',
            
            # Data processing
            'csv': 'data',
            'json': 'data',
            'yaml': 'data',
            'toml': 'data',
            
            # String manipulation
            'strings': 'strings',
            'str_': 'strings',
            
            # Validation
            'validate': 'validation',
            
            # Files
            'file': 'files',
            'files': 'files',
            'path': 'files',
            
            # Output
            'output': 'output',
            'ansi': 'output',
            
            # Observability
            'telemetry': 'observability',
            'otel': 'observability',
            'metrics': 'observability',
            'trace': 'observability',
            
            # Safety/Security
            'confirm': 'safety',
            'risk': 'safety',
            'scope': 'safety',
            'safewrap': 'safety',
            
            # Core utilities
            'core': 'core',
            'mainframe': 'core',
            'log': 'core',
        }
        
        for prefix, category in categories.items():
            if lib_name.startswith(prefix) or prefix in lib_name:
                return category
        
        return 'utility'
    
    def _build_function_info(
        self, 
        func_name: str, 
        desc_lines: List[str], 
        usage: Optional[str],
        param_annotations: Dict,
        lines: List[str],
        func_line_idx: int
    ) -> FunctionInfo:
        """Build FunctionInfo from parsed data."""
        # Extract description
        description = self._clean_description(desc_lines)
        if not description:
            description = f"Execute {func_name}"
        
        # Build signature
        signature = self._build_signature(func_name, usage)
        
        # Extract parameters
        params = self._extract_params(func_name, usage, param_annotations, lines, func_line_idx)
        
        # Determine characteristics
        idempotent = self._is_idempotent(description, func_name)
        pure = self._is_pure(description, func_name)
        returns = self._determine_return_type(description, func_name)
        
        return FunctionInfo(
            description=description,
            signature=signature,
            params=params,
            returns=returns,
            idempotent=idempotent,
            pure=pure
        )
    
    def _clean_description(self, desc_lines: List[str]) -> str:
        """Clean and combine description lines."""
        if not desc_lines:
            return ""
        
        # Remove common prefixes like "@description", "Description:"
        cleaned = []
        for line in desc_lines:
            # Remove @annotations
            line = re.sub(r'^[@\w]+:\s*', '', line)
            line = re.sub(r'^@\w+\s*', '', line)
            # Skip shellcheck and noise
            if line and not line.startswith('shellcheck') and not self._is_noise_line(line):
                cleaned.append(line)
        
        # Join and truncate
        desc = ' '.join(cleaned)
        # Remove excessive whitespace
        desc = re.sub(r'\s+', ' ', desc).strip()
        if len(desc) > 200:
            desc = desc[:197] + '...'
        
        return desc
    
    def _build_signature(self, func_name: str, usage: Optional[str]) -> str:
        """Build function signature."""
        if usage:
            # Try to extract from usage
            match = re.search(rf'{func_name}\s*(.+)', usage)
            if match:
                args = match.group(1).strip()
                return f"{func_name} {args}"
        
        return f"{func_name} [args...]"
    
    def _extract_params(
        self, 
        func_name: str, 
        usage: Optional[str],
        param_annotations: Dict,
        lines: List[str],
        func_line_idx: int
    ) -> List[FunctionParam]:
        """Extract parameter information."""
        params = []
        
        # Look at function body for local var="${1:-default}" patterns
        param_defaults = {}
        param_names_from_body = {}
        i = func_line_idx + 1
        brace_count = 0
        started = False
        
        while i < len(lines) and i < func_line_idx + 50:
            line = lines[i]
            
            # Track braces to find end of function
            if '{' in line:
                started = True
                brace_count += line.count('{')
            if '}' in line:
                brace_count -= line.count('}')
                if started and brace_count <= 0:
                    break
            
            # Look for parameter extraction patterns
            # local var="${1:-default}" or var="${1}"
            patterns = [
                (r'local\s+(\w+)="?\$\{(\d+):-([^}]+)\}"?', 'name_pos_default'),
                (r'local\s+(\w+)="?\$\{(\d+)[^}]*\}"?', 'name_pos'),
                (r'(\w+)="?\$\{(\d+):-([^}]+)\}"?', 'name_pos_default'),
                (r'(\w+)="?\$\{(\d+)[^}]*\}"?', 'name_pos'),
            ]
            
            for pattern, ptype in patterns:
                match = re.search(pattern, line)
                if match:
                    if ptype == 'name_pos_default':
                        var_name = match.group(1)
                        pos = int(match.group(2))
                        default = match.group(3)
                        param_defaults[pos] = default
                        param_names_from_body[pos] = var_name
                    elif ptype == 'name_pos':
                        var_name = match.group(1)
                        pos = int(match.group(2))
                        if pos not in param_defaults:
                            param_defaults[pos] = None
                        if pos not in param_names_from_body:
                            param_names_from_body[pos] = var_name
            
            i += 1
        
        # Parse usage for parameter names
        if usage:
            # Extract quoted and unquoted arguments
            # Match: "quoted arg", [optional], or bareword
            args_pattern = re.findall(r'"([^"]+)"|\[([^\]]+)\]|(\w+)', usage)
            pos = 1
            for groups in args_pattern:
                arg = groups[0] or groups[1] or groups[2]
                if arg and arg != func_name:
                    # Clean up the argument
                    arg = arg.strip('[]"')
                    if arg.startswith('$'):
                        arg = arg[1:]
                    if arg and not arg.startswith('-'):
                        # Check if it's in param_annotations
                        default = param_defaults.get(pos)
                        param_name = param_names_from_body.get(pos, arg.replace(' ', '_'))
                        
                        params.append(FunctionParam(
                            name=param_name,
                            position=pos,
                            required=default is None and f'[{arg}]' not in usage,
                            default=default
                        ))
                        pos += 1
        
        # If no params found from usage, try to infer from defaults
        if not params and param_defaults:
            for pos in sorted(param_defaults.keys()):
                name = param_names_from_body.get(pos, f"arg{pos}")
                params.append(FunctionParam(
                    name=name,
                    position=pos,
                    required=param_defaults[pos] is None,
                    default=param_defaults[pos]
                ))
        
        return params
    
    def _is_idempotent(self, description: str, func_name: str) -> bool:
        """Determine if function is idempotent."""
        idempotent_keywords = ['idempotent', 'ensure', 'check', 'get', 'read', 'list', 'find']
        return any(kw in description.lower() or kw in func_name.lower() 
                  for kw in idempotent_keywords)
    
    def _is_pure(self, description: str, func_name: str) -> bool:
        """Determine if function is pure (no side effects)."""
        pure_keywords = ['pure', 'read-only', 'readonly', 'get', 'check', 'validate', 'parse']
        impure_keywords = ['write', 'save', 'create', 'delete', 'modify', 'update', 'append']
        
        desc_lower = description.lower()
        name_lower = func_name.lower()
        
        # Check for impure indicators first
        if any(kw in desc_lower or kw in name_lower for kw in impure_keywords):
            return False
        
        return any(kw in desc_lower or kw in name_lower for kw in pure_keywords)
    
    def _determine_return_type(self, description: str, func_name: str) -> str:
        """Determine return type based on description and name."""
        if 'json' in description.lower() or 'json' in func_name.lower():
            return 'json'
        if 'bool' in description.lower() or func_name.startswith('is_'):
            return 'boolean'
        if 'exit code' in description.lower() or func_name.startswith('check'):
            return 'exit_code'
        return 'stdout'


def generate_functions_json(
    libraries: Dict[str, LibraryInfo],
    existing_json: Optional[Dict] = None
) -> Dict:
    """Generate FUNCTIONS.json structure."""
    
    if existing_json is None:
        existing_json = {
            "version": "5.0.0",
            "generated": "",
            "stats": {
                "total_functions": 0,
                "total_libraries": 0,
                "categories": {}
            },
            "libraries": {}
        }
    
    # Merge with existing
    for lib_name, lib_info in libraries.items():
        if not lib_info.functions:
            continue  # Skip empty libraries
        
        lib_dict = {
            "file": lib_info.file,
            "description": lib_info.description,
            "category": lib_info.category,
            "functions": {}
        }
        
        for func_name, func_info in lib_info.functions.items():
            # Skip internal functions (starting with _)
            if func_name.startswith('_'):
                continue
            
            func_dict = {
                "description": func_info.description,
                "signature": func_info.signature,
                "params": [
                    {
                        "name": p.name,
                        "position": p.position,
                        "required": p.required,
                        "default": p.default
                    }
                    for p in func_info.params
                ],
                "returns": func_info.returns,
                "idempotent": func_info.idempotent,
                "pure": func_info.pure
            }
            
            lib_dict["functions"][func_name] = func_dict
        
        existing_json["libraries"][lib_name] = lib_dict
    
    # Update stats
    total_funcs = sum(
        len(lib.get("functions", {})) 
        for lib in existing_json["libraries"].values()
    )
    total_libs = len(existing_json["libraries"])
    
    # Count by category
    categories = {}
    for lib in existing_json["libraries"].values():
        cat = lib.get("category", "unknown")
        categories[cat] = categories.get(cat, 0) + len(lib.get("functions", {}))
    
    existing_json["stats"]["total_functions"] = total_funcs
    existing_json["stats"]["total_libraries"] = total_libs
    existing_json["stats"]["categories"] = categories
    
    return existing_json


def main():
    """Main entry point."""
    lib_dir = os.path.expanduser("~/Documents/Projects/mainframe/lib")
    
    # Parse all libraries
    parser = BashParser(lib_dir)
    libraries = parser.parse_all()
    
    # Load existing FUNCTIONS.json if available
    existing_path = os.path.expanduser("~/.mainframe/FUNCTIONS.json")
    existing = None
    if os.path.exists(existing_path):
        with open(existing_path) as f:
            existing = json.load(f)
    
    # Generate new JSON
    result = generate_functions_json(libraries, existing)
    
    # Output summary
    print(f"Parsed {len(libraries)} libraries")
    total_funcs = sum(len(lib.functions) for lib in libraries.values())
    print(f"Found {total_funcs} functions")
    
    # Print category breakdown
    categories = {}
    for lib in libraries.values():
        cat = lib.category
        categories[cat] = categories.get(cat, 0) + len(lib.functions)
    
    print("\nCategories:")
    for cat, count in sorted(categories.items()):
        print(f"  {cat}: {count}")
    
    # Save to file
    output_path = os.path.expanduser("~/.mainframe/FUNCTIONS.json.new")
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"\nSaved to {output_path}")


if __name__ == "__main__":
    main()

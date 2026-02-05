#!/usr/bin/env python3
"""
MAINFRAME Prompt Injector - Dynamic Function Discovery

This module provides context-aware function injection for AI CLI prompts.
It analyzes user queries and project context to suggest relevant MAINFRAME functions.
"""

import json
import re
import subprocess
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path


@dataclass
class FunctionHint:
    """Represents a function hint for prompt injection."""
    name: str
    signature: str
    description: str
    relevance_score: float
    example: Optional[str] = None


class IntentDetector:
    """Detects user intent from natural language queries."""
    
    # Intent patterns with keywords
    INTENT_PATTERNS = {
        "json_processing": [
            "json", "parse", "serialize", "convert to json", 
            "json object", "json array", "extract from json"
        ],
        "file_operations": [
            "file", "read", "write", "edit", "modify file",
            "create file", "delete file", "file exists"
        ],
        "string_manipulation": [
            "string", "trim", "replace", "uppercase", "lowercase",
            "split", "join", "substring", "contains"
        ],
        "array_operations": [
            "array", "list", "join array", "sort array", 
            "filter", "unique", "contains", "array length"
        ],
        "validation": [
            "validate", "check", "verify", "is valid", 
            "email", "url", "integer", "path"
        ],
        "http_api": [
            "http", "api", "request", "curl", "get", "post",
            "fetch", "download", "web request"
        ],
        "date_time": [
            "date", "time", "timestamp", "format date",
            "parse date", "iso", "epoch"
        ],
        "parallel_async": [
            "parallel", "async", "concurrent", "background",
            "wait", "timeout", "retry"
        ],
        "git_operations": [
            "git", "commit", "branch", "merge", "repository",
            "git status", "git log"
        ],
        "crypto_hashing": [
            "hash", "sha256", "md5", "encode", "decode",
            "base64", "uuid", "random"
        ],
        "project_analysis": [
            "project", "analyze", "dependencies", "imports",
            "typescript", "python", "go", "rust"
        ],
    }
    
    # Intent to function mappings
    INTENT_FUNCTIONS = {
        "json_processing": [
            ("json_object", 'json_object "name=John" "age:number=30"', "Create JSON object"),
            ("json_array", 'json_array "a" "b" "c"', "Create JSON array"),
            ("json_get", 'json_get \'{"name":"John"}\' "name"', "Extract value from JSON"),
            ("json_merge", 'json_merge \'{"a":1}\' \'{"b":2}\'', "Merge JSON objects"),
            ("json_pretty", 'json_pretty \'{"a":1}\'', "Format JSON for readability"),
        ],
        "file_operations": [
            ("read_file", 'read_file "path/to/file"', "Read entire file"),
            ("atomic_write", 'atomic_write "file.txt" "content"', "Safely write file"),
            ("diff_replace", 'diff_replace "file.ts" "old" "new"', "Surgical text replacement"),
            ("file_exists", 'file_exists "path"', "Check if file exists"),
            ("file_head", 'file_head "file.txt" 10', "Read first N lines"),
        ],
        "string_manipulation": [
            ("trim_string", 'trim_string "  hello  "', "Remove whitespace"),
            ("to_lower", 'to_lower "HELLO"', "Convert to lowercase"),
            ("to_upper", 'to_upper "hello"', "Convert to uppercase"),
            ("replace_all", 'replace_all "foo bar" "foo" "baz"', "Replace all occurrences"),
            ("contains", 'contains "hello" "ell"', "Check substring"),
        ],
        "array_operations": [
            ("array_join", 'array_join ", " "${arr[@]}"', "Join array elements"),
            ("array_unique", 'array_unique "${arr[@]}"', "Remove duplicates"),
            ("array_sort", 'array_sort "${arr[@]}"', "Sort array elements"),
            ("array_contains", 'array_contains "val" "${arr[@]}"', "Check if array contains value"),
        ],
        "validation": [
            ("validate_email", 'validate_email "user@example.com"', "Validate email format"),
            ("validate_url", 'validate_url "https://example.com"', "Validate URL format"),
            ("validate_path_safe", 'validate_path_safe "$path" "/base"', "Prevent path traversal"),
            ("validate_int", 'validate_int "42" 0 100', "Validate integer in range"),
        ],
        "http_api": [
            ("http_get", 'http_get "https://api.example.com"', "HTTP GET request"),
            ("http_post", 'http_post "https://api.example.com" \'{"key":"val"}\'', "HTTP POST request"),
            ("http_json_get", 'http_json_get "https://api.example.com"', "GET with JSON parsing"),
        ],
        "date_time": [
            ("now_iso", 'now_iso', "Current ISO timestamp"),
            ("date_add", 'date_add $(now) "2d"', "Add time duration"),
            ("format_relative", 'format_relative $epoch', "Human-readable time"),
        ],
        "parallel_async": [
            ("parallel", 'parallel "cmd1" "cmd2" "cmd3"', "Run commands in parallel"),
            ("retry", 'retry 5 "flaky_command"', "Retry with backoff"),
            ("with_lock", 'with_lock "/tmp/lock" "critical_section"', "Exclusive execution"),
        ],
        "git_operations": [
            ("git_branch", 'git_branch', "Get current branch"),
            ("git_is_dirty", 'git_is_dirty', "Check for uncommitted changes"),
            ("git_summary", 'git_summary', "Quick repo status"),
        ],
        "crypto_hashing": [
            ("sha256", 'sha256 "data"', "SHA-256 hash"),
            ("uuid", 'uuid', "Generate UUID"),
            ("random_token", 'random_token 32', "Random token"),
        ],
        "project_analysis": [
            ("project_detect", 'project_detect "."', "Detect project type"),
            ("ts_file_imports", 'ts_file_imports "src/index.ts"', "Extract TS imports"),
            ("py_file_imports", 'py_file_imports "app/main.py"', "Extract Python imports"),
        ],
    }
    
    def detect(self, query: str) -> List[Tuple[str, float]]:
        """
        Detect intents from user query.
        Returns list of (intent, confidence_score) tuples.
        """
        query_lower = query.lower()
        scores = {}
        
        for intent, keywords in self.INTENT_PATTERNS.items():
            score = 0.0
            for keyword in keywords:
                if keyword in query_lower:
                    # Weight exact matches higher
                    if re.search(r'\b' + re.escape(keyword) + r'\b', query_lower):
                        score += 1.0
                    else:
                        score += 0.5
            
            if score > 0:
                # Normalize by number of keywords
                scores[intent] = min(score / len(keywords) * 3, 1.0)
        
        # Sort by score descending
        return sorted(scores.items(), key=lambda x: x[1], reverse=True)


class ProjectAnalyzer:
    """Analyzes project structure to suggest relevant functions."""
    
    def __init__(self, project_dir: str):
        self.project_dir = Path(project_dir)
        self.mainframe_root = Path.home() / ".mainframe"
    
    def analyze(self) -> Dict[str, any]:
        """Analyze project and return context information."""
        context = {
            "project_dir": str(self.project_dir),
            "detected_types": [],
            "relevant_functions": [],
        }
        
        # Detect project types
        if (self.project_dir / "package.json").exists():
            context["detected_types"].append("nodejs")
            context["relevant_functions"].extend([
                ("ts_file_imports", "Extract TypeScript imports"),
                ("ts_import_cost", "Analyze bundle size"),
                ("bun_run", "Run with Bun"),
            ])
        
        if (self.project_dir / "requirements.txt").exists() or \
           (self.project_dir / "pyproject.toml").exists():
            context["detected_types"].append("python")
            context["relevant_functions"].extend([
                ("py_file_imports", "Extract Python imports"),
                ("py_summary", "Project health overview"),
                ("venv_activate", "Activate virtualenv"),
            ])
        
        if (self.project_dir / "go.mod").exists():
            context["detected_types"].append("go")
            context["relevant_functions"].extend([
                ("go_mod_tidy", "Tidy go.mod"),
                ("go_build", "Build Go project"),
            ])
        
        if (self.project_dir / ".git").exists():
            context["detected_types"].append("git")
            context["relevant_functions"].extend([
                ("git_summary", "Quick repo status"),
                ("git_files_changed", "See modified files"),
            ])
        
        if (self.project_dir / "Dockerfile").exists():
            context["detected_types"].append("docker")
            context["relevant_functions"].extend([
                ("docker_build", "Build Docker image"),
                ("docker_running", "Check Docker daemon"),
            ])
        
        return context


class PromptInjector:
    """Main class for injecting MAINFRAME hints into prompts."""
    
    def __init__(self, mainframe_root: Optional[str] = None):
        self.mainframe_root = mainframe_root or str(Path.home() / ".mainframe")
        self.intent_detector = IntentDetector()
        self.function_registry = self._load_function_registry()
    
    def _load_function_registry(self) -> Dict[str, Dict]:
        """Load function registry from FUNCTIONS.json."""
        functions_json = Path(self.mainframe_root) / "FUNCTIONS.json"
        if not functions_json.exists():
            return {}
        
        try:
            with open(functions_json) as f:
                data = json.load(f)
            
            registry = {}
            libraries = data.get("libraries", {})
            for lib_name, lib_data in libraries.items():
                for func_name, func_data in lib_data.get("functions", {}).items():
                    registry[func_name] = {
                        "name": func_name,
                        "library": lib_name,
                        "signature": func_data.get("signature", func_name),
                        "description": func_data.get("description", ""),
                    }
            return registry
        except Exception:
            return {}
    
    def generate_hints(
        self,
        user_query: str,
        project_dir: Optional[str] = None
    ) -> str:
        """
        Generate function hints for a user query.
        
        Args:
            user_query: The user's natural language query
            project_dir: Optional project directory for context
        
        Returns:
            Formatted hint string for prompt injection
        """
        hints = []
        
        # Detect intent
        detected_intents = self.intent_detector.detect(user_query)
        
        # Get functions for top intents
        suggested_funcs = []
        for intent, score in detected_intents[:2]:  # Top 2 intents
            funcs = self.intent_detector.INTENT_FUNCTIONS.get(intent, [])
            for func_name, example, desc in funcs[:3]:  # Top 3 per intent
                suggested_funcs.append((func_name, example, desc, score))
        
        # Get project-specific hints
        project_hints = []
        if project_dir:
            analyzer = ProjectAnalyzer(project_dir)
            project_context = analyzer.analyze()
            for func_name, desc in project_context.get("relevant_functions", [])[:3]:
                project_hints.append((func_name, desc))
        
        # Build hint text
        if suggested_funcs or project_hints:
            hints.append("## Relevant MAINFRAME Functions")
            hints.append("")
            
            # Intent-based hints
            if suggested_funcs:
                hints.append("### For Your Current Task")
                for func_name, example, desc, score in suggested_funcs:
                    func_info = self.function_registry.get(func_name, {})
                    signature = func_info.get("signature", f"{func_name} ...")
                    hints.append(f"- `{signature}` - {desc}")
                    hints.append(f"  Example: `{example}`")
                hints.append("")
            
            # Project-based hints
            if project_hints:
                hints.append("### For This Project")
                for func_name, desc in project_hints:
                    hints.append(f"- `{func_name}` - {desc}")
                hints.append("")
            
            hints.append("Source MAINFRAME: `source $MAINFRAME_ROOT/lib/common.sh`")
        
        return "\n".join(hints)
    
    def inject_into_prompt(
        self,
        original_prompt: str,
        user_query: str,
        project_dir: Optional[str] = None
    ) -> str:
        """
        Inject MAINFRAME hints into an existing prompt.
        
        Args:
            original_prompt: The original system prompt
            user_query: User's query for context detection
            project_dir: Optional project directory
        
        Returns:
            Enhanced prompt with MAINFRAME hints
        """
        hints = self.generate_hints(user_query, project_dir)
        
        if not hints:
            return original_prompt
        
        # Insert hints before any "##" section or at the end
        if "##" in original_prompt:
            parts = original_prompt.split("##", 1)
            return f"{parts[0]}\n{hints}\n\n##{parts[1]}"
        else:
            return f"{original_prompt}\n\n{hints}"


# =============================================================================
# Example Usage
# =============================================================================

def example_usage():
    """Demonstrate prompt injection functionality."""
    
    injector = PromptInjector()
    
    # Example 1: JSON processing query
    print("=" * 60)
    print("Example 1: JSON Processing Query")
    print("=" * 60)
    
    query1 = "I need to parse this JSON and extract the user name"
    hints1 = injector.generate_hints(query1)
    print(f"Query: {query1}")
    print("\nGenerated Hints:")
    print(hints1)
    print()
    
    # Example 2: File editing query with project context
    print("=" * 60)
    print("Example 2: File Editing Query")
    print("=" * 60)
    
    query2 = "Replace all occurrences of 'foo' with 'bar' in config.ts"
    hints2 = injector.generate_hints(query2, project_dir=".")
    print(f"Query: {query2}")
    print("\nGenerated Hints:")
    print(hints2)
    print()
    
    # Example 3: Parallel execution
    print("=" * 60)
    print("Example 3: Parallel Execution")
    print("=" * 60)
    
    query3 = "Run these three commands in parallel"
    hints3 = injector.generate_hints(query3)
    print(f"Query: {query3}")
    print("\nGenerated Hints:")
    print(hints3)
    print()
    
    # Example 4: Full prompt injection
    print("=" * 60)
    print("Example 4: Full Prompt Injection")
    print("=" * 60)
    
    original_prompt = """You are a helpful coding assistant.

## Guidelines
- Write clean code
- Add comments
- Test your changes
"""
    
    query4 = "Process this JSON data and write results to a file"
    enhanced_prompt = injector.inject_into_prompt(original_prompt, query4, ".")
    
    print("Original Prompt:")
    print(original_prompt)
    print("\n" + "=" * 40)
    print("Enhanced Prompt:")
    print(enhanced_prompt)


if __name__ == "__main__":
    example_usage()

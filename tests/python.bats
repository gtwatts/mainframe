#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Python Analysis Library Tests
# =============================================================================
# Tests for lib/python.sh - PyMiner, PyDeps, PyMetrics
# =============================================================================

load 'test_helper'

setup() {
    source_lib "python"
    TEST_DIR=$(create_test_dir "python")

    # Create project structure
    mkdir -p "$TEST_DIR/src/myapp/services"
    mkdir -p "$TEST_DIR/src/myapp/utils"
    mkdir -p "$TEST_DIR/tests"
    mkdir -p "$TEST_DIR/venv/bin"
    mkdir -p "$TEST_DIR/requirements"

    # Create pyproject.toml
    printf '[project]\nname = "myapp"\nversion = "1.0.0"\nrequires-python = ">=3.9"\n\n' > "$TEST_DIR/pyproject.toml"
    printf '[project.dependencies]\n"requests>=2.28"\n"click>=8.0"\n' >> "$TEST_DIR/pyproject.toml"

    # Create requirements.txt
    printf 'requests==2.28.1\nflask>=2.0\nnumpy\n# this is a comment\npandas>=1.5,<2.0\n-r requirements/dev.txt\nclick>=8.0\n' > "$TEST_DIR/requirements.txt"

    # Create requirements/dev.txt
    printf 'pytest>=7.0\npytest-cov\nblack\n' > "$TEST_DIR/requirements/dev.txt"

    # Create venv/bin/activate
    printf '#!/bin/bash\nexport VIRTUAL_ENV="%s/venv"\n' "$TEST_DIR" > "$TEST_DIR/venv/bin/activate"

    # Create .python-version
    printf '3.11.4\n' > "$TEST_DIR/.python-version"

    # Create src/myapp/__init__.py
    printf '"""My Application"""\n__version__ = "1.0.0"\n' > "$TEST_DIR/src/myapp/__init__.py"

    # Create src/myapp/main.py with various imports
    printf 'import os\nimport sys\nfrom pathlib import Path\n\n' > "$TEST_DIR/src/myapp/main.py"
    printf 'import requests\nfrom flask import Flask, jsonify\nfrom .services.user import UserService\nfrom .utils import helpers\n\n' >> "$TEST_DIR/src/myapp/main.py"
    printf 'def main() -> None:\n    """Entry point."""\n    app = Flask(__name__)\n    service = UserService()\n\n' >> "$TEST_DIR/src/myapp/main.py"
    printf 'if __name__ == "__main__":\n    main()\n' >> "$TEST_DIR/src/myapp/main.py"

    # Create src/myapp/services/__init__.py
    printf '' > "$TEST_DIR/src/myapp/services/__init__.py"

    # Create src/myapp/services/user.py with multiline import
    printf 'from typing import (\n    Optional,\n    List,\n    Dict\n)\n\n' > "$TEST_DIR/src/myapp/services/user.py"
    printf 'import logging\nfrom ..utils.helpers import format_name\nfrom .base import BaseService\n\n' >> "$TEST_DIR/src/myapp/services/user.py"
    printf 'class UserService(BaseService):\n    """User management service."""\n\n' >> "$TEST_DIR/src/myapp/services/user.py"
    printf '    def get_user(self, user_id: int) -> Optional[Dict]:\n        """Get user by ID."""\n        return None\n\n' >> "$TEST_DIR/src/myapp/services/user.py"
    printf '    def list_users(self) -> List[Dict]:\n        """List all users."""\n        return []\n\n' >> "$TEST_DIR/src/myapp/services/user.py"
    printf '    def create_user(self, name, email):\n        pass\n' >> "$TEST_DIR/src/myapp/services/user.py"

    # Create src/myapp/utils/__init__.py
    printf '' > "$TEST_DIR/src/myapp/utils/__init__.py"

    # Create src/myapp/utils/helpers.py
    printf 'import re\nfrom datetime import datetime\n\n' > "$TEST_DIR/src/myapp/utils/helpers.py"
    printf 'def format_name(name: str) -> str:\n    """Format a name."""\n    return name.strip().title()\n\n' >> "$TEST_DIR/src/myapp/utils/helpers.py"
    printf 'def parse_date(date_str):\n    return datetime.fromisoformat(date_str)\n' >> "$TEST_DIR/src/myapp/utils/helpers.py"

    # Create tests/test_user.py
    printf 'import pytest\nfrom myapp.services.user import UserService\n\n' > "$TEST_DIR/tests/test_user.py"
    printf 'class TestUserService:\n    def test_get_user(self):\n        service = UserService()\n        assert service.get_user(1) is None\n\n' >> "$TEST_DIR/tests/test_user.py"
    printf '    def test_list_users(self):\n        service = UserService()\n        assert service.list_users() == []\n' >> "$TEST_DIR/tests/test_user.py"

    # Create conftest.py for pytest detection
    printf 'import pytest\n\n@pytest.fixture\ndef client():\n    return None\n' > "$TEST_DIR/conftest.py"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# PROJECT DETECTION TESTS
# =============================================================================

@test "py_is_project detects Python project" {
    run py_is_project "$TEST_DIR"
    [ "$status" -eq 0 ]
}

@test "py_is_project returns 1 for non-Python directory" {
    local non_py
    non_py=$(create_test_dir "non_py")
    run py_is_project "$non_py"
    [ "$status" -ne 0 ]
    cleanup_test_dir "$non_py"
}

@test "py_source_dir finds src layout" {
    run py_source_dir "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"myapp"* ]]
}

# =============================================================================
# PYMINER - IMPORT ANALYSIS TESTS
# =============================================================================

@test "py_file_imports extracts standard imports" {
    run py_file_imports "$TEST_DIR/src/myapp/main.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"os"* ]]
    [[ "$output" == *"sys"* ]]
    [[ "$output" == *"requests"* ]]
}

@test "py_file_imports extracts from-imports" {
    run py_file_imports "$TEST_DIR/src/myapp/main.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pathlib"* ]]
    [[ "$output" == *"flask"* ]]
}

@test "py_file_imports handles relative imports" {
    run py_file_imports "$TEST_DIR/src/myapp/main.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *".services.user"* ]]
    [[ "$output" == *".utils"* ]]
}

@test "py_file_imports handles multiline parenthesized imports" {
    run py_file_imports "$TEST_DIR/src/myapp/services/user.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"typing"* ]]
}

@test "py_file_imports returns error for missing file" {
    run py_file_imports "/nonexistent/file.py"
    [ "$status" -ne 0 ]
}

@test "py_import_frequency counts module usage" {
    run py_import_frequency "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pytest"* ]] || [[ "$output" == *"logging"* ]] || [[ "$output" == *"typing"* ]]
}

@test "py_import_graph shows dependency edges" {
    run py_import_graph "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *" -> "* ]]
    [[ "$output" == *"main.py"* ]]
}

@test "py_import_graph fails for non-Python project" {
    local non_py
    non_py=$(create_test_dir "non_py_graph")
    run py_import_graph "$non_py"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not a Python project"* ]]
    cleanup_test_dir "$non_py"
}

@test "py_import_classify identifies stdlib modules" {
    run py_import_classify "os"
    [ "$status" -eq 0 ]
    [ "$output" = "stdlib" ]
}

@test "py_import_classify identifies stdlib pathlib" {
    run py_import_classify "pathlib"
    [ "$status" -eq 0 ]
    [ "$output" = "stdlib" ]
}

@test "py_import_classify identifies third-party modules" {
    run py_import_classify "requests"
    [ "$status" -eq 0 ]
    [ "$output" = "third-party" ]
}

@test "py_import_classify identifies local imports" {
    run py_import_classify ".services.user"
    [ "$status" -eq 0 ]
    [ "$output" = "local" ]
}

@test "py_import_classify identifies local package by directory" {
    mkdir -p "$TEST_DIR/mypackage"
    run py_import_classify "mypackage" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "local" ]
}

@test "py_framework_detect finds flask" {
    run py_framework_detect "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"flask"* ]]
}

@test "py_framework_detect finds pytest" {
    run py_framework_detect "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pytest"* ]]
}

@test "py_circular_deps runs without error" {
    run py_circular_deps "$TEST_DIR"
    [ "$status" -eq 0 ]
}

# =============================================================================
# PYDEPS - DEPENDENCY/ENVIRONMENT TESTS
# =============================================================================

@test "py_parse_requirements extracts packages" {
    run py_parse_requirements "$TEST_DIR/requirements.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"requests"* ]]
    [[ "$output" == *"flask"* ]]
    [[ "$output" == *"numpy"* ]]
    [[ "$output" == *"click"* ]]
}

@test "py_parse_requirements skips comments" {
    run py_parse_requirements "$TEST_DIR/requirements.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"this is a comment"* ]]
}

@test "py_parse_requirements skips option flags" {
    run py_parse_requirements "$TEST_DIR/requirements.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"-r "* ]]
}

@test "py_parse_requirements returns error for missing file" {
    run py_parse_requirements "/nonexistent/requirements.txt"
    [ "$status" -ne 0 ]
}

@test "py_detect_venv finds virtual environment" {
    run py_detect_venv "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"venv"* ]]
}

@test "py_detect_venv returns 1 when no venv" {
    local no_venv
    no_venv=$(create_test_dir "no_venv")
    run py_detect_venv "$no_venv"
    [ "$status" -ne 0 ]
    cleanup_test_dir "$no_venv"
}

@test "py_python_version reads from .python-version" {
    run py_python_version "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3.11"* ]]
}

@test "py_python_version reads from pyproject.toml" {
    rm -f "$TEST_DIR/.python-version"
    run py_python_version "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3.9"* ]]
}

@test "py_detect_manager identifies pip" {
    run py_detect_manager "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "pip" ]
}

@test "py_detect_manager identifies poetry" {
    printf '\n[tool.poetry]\nname = "myapp"\n' >> "$TEST_DIR/pyproject.toml"
    run py_detect_manager "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "poetry" ]
}

@test "py_detect_manager identifies pipenv" {
    printf '[packages]\nrequests = "*"\n' > "$TEST_DIR/Pipfile"
    run py_detect_manager "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "pipenv" ]
}

@test "py_dep_count counts requirements.txt packages" {
    run py_dep_count "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]
}

# =============================================================================
# PYMETRICS - CODE QUALITY TESTS
# =============================================================================

@test "py_loc counts lines of code" {
    run py_loc "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -gt 10 ]
}

@test "py_function_count counts functions in file" {
    run py_function_count "$TEST_DIR/src/myapp/services/user.py"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
}

@test "py_function_count counts functions in directory" {
    run py_function_count "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]
}

@test "py_class_count counts classes in file" {
    run py_class_count "$TEST_DIR/src/myapp/services/user.py"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "py_class_count counts classes in directory" {
    run py_class_count "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "py_docstring_coverage reports coverage" {
    run py_docstring_coverage "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+/[0-9]+[[:space:]][0-9]+% ]]
}

@test "py_docstring_coverage shows non-zero coverage" {
    run py_docstring_coverage "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != "0/0 0%" ]]
}

@test "py_type_hint_coverage reports coverage" {
    run py_type_hint_coverage "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+/[0-9]+[[:space:]][0-9]+% ]]
}

@test "py_file_count counts Python files" {
    run py_file_count "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -ge 5 ]
}

@test "py_file_count excludes venv" {
    printf "x = 1\n" > "$TEST_DIR/venv/test.py"
    local count
    count=$(py_file_count "$TEST_DIR")
    [ "$count" -lt 20 ]
}

@test "py_summary gives project overview" {
    run py_summary "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"files="* ]]
    [[ "$output" == *"loc="* ]]
    [[ "$output" == *"functions="* ]]
    [[ "$output" == *"classes="* ]]
    [[ "$output" == *"manager="* ]]
}

@test "py_summary fails for non-Python project" {
    local non_py
    non_py=$(create_test_dir "non_py_sum")
    run py_summary "$non_py"
    [ "$status" -ne 0 ]
    cleanup_test_dir "$non_py"
}

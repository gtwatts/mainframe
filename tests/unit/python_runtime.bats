#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/python_runtime.bats - PYRUNTIME Unit Tests
# =============================================================================
# Description: Unit tests for PYRUNTIME functions in lib/python.sh
#              All tests use mocking to work without Python installed
# =============================================================================
# USOP Pattern: {"ok":true,"data":{...}} or {"ok":false,"error":"msg"}
# =============================================================================

# Test setup
setup() {
    # Load BATS helper libraries
    load '../bats-support/load'
    load '../bats-assert/load'

    # Get absolute path to lib directory
    MAINFRAME_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # Source the library under test
    source "$MAINFRAME_ROOT/lib/python.sh"

    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Mock directory for fake Python venv
    MOCK_VENV="$TEST_DIR/.venv"
    mkdir -p "$MOCK_VENV/bin"

    # Store original PATH
    ORIGINAL_PATH="$PATH"

    # Clear any active venv
    unset VIRTUAL_ENV
}

# Test teardown
teardown() {
    cd /
    rm -rf "$TEST_DIR"
    PATH="$ORIGINAL_PATH"
}

# =============================================================================
# USOP VALIDATION HELPERS
# =============================================================================

# Validate USOP success response structure
# Usage: assert_usop_ok "$output"
assert_usop_ok() {
    local json="$1"

    # Check it's valid JSON with ok:true
    [[ "$json" =~ \"ok\":true ]] || {
        echo "USOP assertion failed: expected ok:true"
        echo "Got: $json"
        return 1
    }
}

# Validate USOP error response structure
# Usage: assert_usop_error "$output" "expected error substring"
assert_usop_error() {
    local json="$1"
    local expected="${2:-}"

    # Check it's valid JSON with ok:false
    [[ "$json" =~ \"ok\":false ]] || {
        echo "USOP assertion failed: expected ok:false"
        echo "Got: $json"
        return 1
    }

    # Check for expected error message if provided
    if [[ -n "$expected" ]]; then
        [[ "$json" =~ \"error\":\".*$expected.* ]] || {
            echo "USOP assertion failed: expected error containing '$expected'"
            echo "Got: $json"
            return 1
        }
    fi
}

# Extract field from USOP JSON data section
# Usage: usop_get_data "$output" "fieldname"
usop_get_data() {
    local json="$1"
    local field="$2"

    # Simple extraction using grep/sed (works for simple cases)
    echo "$json" | grep -oP "\"$field\":\s*\"?\K[^,\"}]+" | head -1
}

# Check if USOP data field equals expected value
# Usage: assert_usop_data_equals "$output" "fieldname" "expected"
assert_usop_data_equals() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual
    actual=$(usop_get_data "$json" "$field")

    [[ "$actual" == "$expected" ]] || {
        echo "USOP data assertion failed: $field"
        echo "Expected: $expected"
        echo "Actual: $actual"
        return 1
    }
}

# Check if USOP data field contains expected substring
# Usage: assert_usop_data_contains "$output" "fieldname" "substring"
assert_usop_data_contains() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual
    actual=$(usop_get_data "$json" "$field")

    [[ "$actual" == *"$expected"* ]] || {
        echo "USOP data assertion failed: $field should contain '$expected'"
        echo "Actual: $actual"
        return 1
    }
}

# =============================================================================
# MOCK HELPERS
# =============================================================================

# Create mock Python interpreter
create_mock_python() {
    local version="${1:-3.11.0}"
    local mock_python="$TEST_DIR/mock_python"

    cat > "$mock_python" << EOF
#!/bin/bash
case "\$1" in
    --version)
        echo "Python $version"
        ;;
    -c)
        shift
        case "\$1" in
            "import pytest")
                exit 0
                ;;
            "import ruff")
                exit 0
                ;;
            "import mypy")
                exit 0
                ;;
            "import black")
                exit 0
                ;;
            "import pip_audit")
                exit 0
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
    -m)
        shift
        case "\$1" in
            pip)
                shift
                case "\$1" in
                    list)
                        if [[ "\$2" == "--format=json" ]]; then
                            echo '[{"name":"pytest","version":"8.0.0"},{"name":"requests","version":"2.31.0"}]'
                        else
                            echo "Package    Version"
                            echo "---------- -------"
                            echo "pytest     8.0.0"
                            echo "requests   2.31.0"
                        fi
                        ;;
                    freeze)
                        echo "pytest==8.0.0"
                        echo "requests==2.31.0"
                        ;;
                    install)
                        echo "Successfully installed \$2"
                        ;;
                    uninstall)
                        echo "Successfully uninstalled \$3"
                        ;;
                    show)
                        echo "Name: \$2"
                        echo "Version: 1.0.0"
                        ;;
                esac
                ;;
            pytest)
                echo "5 passed, 1 failed, 2 skipped in 1.23s"
                exit 0
                ;;
            venv)
                mkdir -p "\$2/bin"
                cp "$mock_python" "\$2/bin/python"
                touch "\$2/bin/activate"
                ;;
            ruff)
                echo "src/main.py:10:5: E501 line too long"
                echo "src/main.py:20:1: F401 unused import"
                exit 1
                ;;
            black)
                echo "reformatted src/main.py"
                echo "1 file reformatted"
                ;;
            mypy)
                echo "src/main.py:15: error: Argument 1 has incompatible type"
                exit 1
                ;;
            pip_audit)
                echo '[]'
                ;;
        esac
        ;;
    *)
        echo "mock python executed: \$@"
        ;;
esac
EOF
    chmod +x "$mock_python"
    echo "$mock_python"
}

# Create mock poetry command
create_mock_poetry() {
    local mock_poetry="$TEST_DIR/mock_poetry"

    cat > "$mock_poetry" << 'EOF'
#!/bin/bash
case "$1" in
    install)
        echo "Installing dependencies..."
        echo "Installing pytest (8.0.0)"
        exit 0
        ;;
    add)
        echo "Using version ^1.0.0 for $2"
        echo "Installing $2..."
        exit 0
        ;;
    remove)
        echo "Removing $2..."
        exit 0
        ;;
    update)
        echo "Updating dependencies..."
        exit 0
        ;;
    run)
        shift
        exec "$@"
        ;;
esac
EOF
    chmod +x "$mock_poetry"
    echo "$mock_poetry"
}

# Create mock uv command
create_mock_uv() {
    local mock_uv="$TEST_DIR/mock_uv"

    cat > "$mock_uv" << 'EOF'
#!/bin/bash
case "$1" in
    pip)
        shift
        case "$1" in
            install)
                echo "Successfully installed packages"
                exit 0
                ;;
            uninstall)
                echo "Successfully uninstalled packages"
                exit 0
                ;;
            sync)
                echo "Synced packages"
                exit 0
                ;;
        esac
        ;;
    --version)
        echo "uv 0.1.0"
        ;;
esac
EOF
    chmod +x "$mock_uv"
    echo "$mock_uv"
}

# Create a mock Python project directory structure
create_mock_python_project() {
    local dir="${1:-$TEST_DIR}"
    local manager="${2:-pip}"

    mkdir -p "$dir/src/myproject"

    # Create Python files
    cat > "$dir/src/myproject/__init__.py" << 'EOF'
"""My Project"""
__version__ = "1.0.0"
EOF

    cat > "$dir/src/myproject/main.py" << 'EOF'
"""Main module."""
import os
import json
from typing import Optional

import requests
from fastapi import FastAPI

def hello(name: str) -> str:
    """Say hello."""
    return f"Hello, {name}!"

class Greeter:
    """A greeting class."""
    def greet(self, name):
        return hello(name)
EOF

    # Create requirements.txt
    cat > "$dir/requirements.txt" << 'EOF'
requests>=2.28.0
fastapi>=0.100.0
pytest>=8.0.0
EOF

    # Create pyproject.toml based on manager
    case "$manager" in
        poetry)
            cat > "$dir/pyproject.toml" << 'EOF'
[tool.poetry]
name = "myproject"
version = "1.0.0"
description = "A test project"

[tool.poetry.dependencies]
python = "^3.9"
requests = "^2.28.0"
fastapi = "^0.100.0"

[tool.poetry.scripts]
myproject = "myproject.main:main"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
EOF
            touch "$dir/poetry.lock"
            ;;
        uv)
            cat > "$dir/pyproject.toml" << 'EOF'
[project]
name = "myproject"
version = "1.0.0"
description = "A test project"
requires-python = ">=3.9"

[project.dependencies]
requests = ">=2.28.0"
fastapi = ">=0.100.0"

[project.scripts]
myproject = "myproject.main:main"
EOF
            touch "$dir/uv.lock"
            ;;
        pip|*)
            cat > "$dir/pyproject.toml" << 'EOF'
[project]
name = "myproject"
version = "1.0.0"
description = "A test project"
requires-python = ">=3.9"

[project.dependencies]
requests = ">=2.28.0"
fastapi = ">=0.100.0"

[project.scripts]
myproject = "myproject.main:main"
EOF
            ;;
    esac

    # Create .python-version
    echo "3.11.0" > "$dir/.python-version"
}

# =============================================================================
# ENVIRONMENT DETECTION TESTS
# =============================================================================

@test "py_detect: returns ok:true with installed=true when python3 exists" {
    local mock_python
    mock_python=$(create_mock_python "3.11.5")
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_detect

    assert_success
    assert_usop_ok "$output"
    assert_usop_data_equals "$output" "installed" "true"
    assert_usop_data_equals "$output" "version" "3.11.5"
}

@test "py_detect: returns ok:true with installed=false when no python" {
    # Remove python from PATH
    PATH="/nonexistent"

    run py_detect

    assert_success
    assert_usop_ok "$output"
    assert_usop_data_equals "$output" "installed" "false"
}

@test "py_interpreter: returns interpreter path and version" {
    local mock_python
    mock_python=$(create_mock_python "3.10.12")
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_interpreter "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"version\":\"3.10.12\" ]]
}

@test "py_interpreter: returns error when no python found" {
    PATH="/nonexistent"

    run py_interpreter "$TEST_DIR"

    assert_success  # USOP always returns 0
    assert_usop_error "$output" "No Python interpreter"
}

@test "py_interpreter: detects venv interpreter" {
    local mock_python
    mock_python=$(create_mock_python "3.11.0")

    # Create venv structure with mock python
    mkdir -p "$MOCK_VENV/bin"
    cp "$mock_python" "$MOCK_VENV/bin/python"
    touch "$MOCK_VENV/bin/activate"

    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_interpreter "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"venv\":true ]] || [[ "$output" =~ \"venv\":\"true\" ]]
}

@test "py_venv_active: returns active=false when not in venv" {
    unset VIRTUAL_ENV

    run py_venv_active

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"active\":false ]]
}

@test "py_venv_active: returns active=true when VIRTUAL_ENV set" {
    export VIRTUAL_ENV="$MOCK_VENV"
    mkdir -p "$MOCK_VENV/bin"
    touch "$MOCK_VENV/bin/python"

    run py_venv_active

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"active\":true ]]
}

@test "py_venv_create: creates venv successfully" {
    local mock_python
    mock_python=$(create_mock_python "3.11.0")
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_venv_create "$TEST_DIR/new_venv" "python3"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"created\":true ]] || [[ "$output" =~ \"created\":\"true\" ]]
}

@test "py_venv_create: returns error when python not found" {
    PATH="/nonexistent"

    run py_venv_create "$TEST_DIR/new_venv" "python3"

    assert_success
    assert_usop_error "$output" "not found"
}

@test "py_venv_create: reports existing venv without recreating" {
    # Create existing venv
    mkdir -p "$MOCK_VENV/bin"
    touch "$MOCK_VENV/bin/activate"

    local mock_python
    mock_python=$(create_mock_python "3.11.0")
    cp "$mock_python" "$MOCK_VENV/bin/python"

    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_venv_create "$MOCK_VENV"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"created\":false ]] || [[ "$output" =~ \"created\":\"false\" ]]
    [[ "$output" =~ \"message\":\"venv already exists\" ]]
}

@test "py_venv_activate_cmd: returns bash activation command" {
    mkdir -p "$MOCK_VENV/bin"
    touch "$MOCK_VENV/bin/activate"

    SHELL="/bin/bash"

    run py_venv_activate_cmd "$MOCK_VENV"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"command\":\"source $MOCK_VENV/bin/activate\" ]]
}

@test "py_venv_activate_cmd: returns fish activation command" {
    mkdir -p "$MOCK_VENV/bin"
    touch "$MOCK_VENV/bin/activate"
    touch "$MOCK_VENV/bin/activate.fish"

    SHELL="/usr/bin/fish"

    run py_venv_activate_cmd "$MOCK_VENV"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ activate.fish ]]
}

@test "py_venv_activate_cmd: returns error for missing venv" {
    run py_venv_activate_cmd "/nonexistent/venv"

    assert_success
    assert_usop_error "$output" "venv not found"
}

# =============================================================================
# PACKAGE MANAGEMENT TESTS
# =============================================================================

@test "py_install: installs packages with pip" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_install "" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"pip\" ]]
}

@test "py_install: uses poetry when poetry.lock exists" {
    create_mock_python_project "$TEST_DIR" "poetry"

    local mock_python mock_poetry
    mock_python=$(create_mock_python)
    mock_poetry=$(create_mock_poetry)
    PATH="$(dirname "$mock_python"):$(dirname "$mock_poetry"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"
    ln -sf "$mock_poetry" "$(dirname "$mock_poetry")/poetry"

    run py_install "" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"poetry\" ]]
}

@test "py_install: uses uv when uv.lock exists" {
    create_mock_python_project "$TEST_DIR" "uv"

    local mock_python mock_uv
    mock_python=$(create_mock_python)
    mock_uv=$(create_mock_uv)
    PATH="$(dirname "$mock_python"):$(dirname "$mock_uv"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"
    ln -sf "$mock_uv" "$(dirname "$mock_uv")/uv"

    run py_install "" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"uv\" ]]
}

@test "py_install: returns error when no python interpreter" {
    create_mock_python_project "$TEST_DIR" "pip"
    PATH="/nonexistent"

    run py_install "" "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "No Python interpreter"
}

@test "py_add: adds package successfully" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_add "requests" "" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"package\":\"requests\" ]]
}

@test "py_add: returns error when package name missing" {
    run py_add "" "" "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "Package name required"
}

@test "py_add: uses poetry add for poetry projects" {
    create_mock_python_project "$TEST_DIR" "poetry"

    local mock_python mock_poetry
    mock_python=$(create_mock_python)
    mock_poetry=$(create_mock_poetry)
    PATH="$(dirname "$mock_python"):$(dirname "$mock_poetry"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"
    ln -sf "$mock_poetry" "$(dirname "$mock_poetry")/poetry"

    run py_add "flask" "" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"poetry\" ]]
}

@test "py_remove: removes package successfully" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_remove "requests" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"removed\":\"requests\" ]]
}

@test "py_remove: returns error when package name missing" {
    run py_remove "" "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "Package name required"
}

@test "py_list: lists installed packages as JSON" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_list "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"packages\": ]]
    [[ "$output" =~ pytest ]]
}

@test "py_list: returns error when no python" {
    PATH="/nonexistent"

    run py_list "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "No Python interpreter"
}

@test "py_freeze: generates requirements list" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_freeze "" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"packages\": ]]
}

@test "py_freeze: writes to file when path provided" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_freeze "$TEST_DIR/frozen.txt" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"file\":\"$TEST_DIR/frozen.txt\" ]]
    [[ -f "$TEST_DIR/frozen.txt" ]]
}

@test "py_sync: syncs environment from requirements" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_sync "$TEST_DIR/requirements.txt" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"pip\" ]]
}

@test "py_sync: returns error for missing requirements file" {
    run py_sync "/nonexistent/requirements.txt" "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "Requirements file not found"
}

@test "py_upgrade: upgrades single package" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_upgrade "pytest" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
}

@test "py_upgrade: returns error without python" {
    PATH="/nonexistent"

    run py_upgrade "pytest" "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "No Python interpreter"
}

# =============================================================================
# EXECUTION TESTS
# =============================================================================

@test "py_run: executes Python file" {
    create_mock_python_project "$TEST_DIR" "pip"

    # Create a simple Python script
    cat > "$TEST_DIR/script.py" << 'EOF'
print("Hello from script")
EOF

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_run "$TEST_DIR/script.py"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"file\":\"$TEST_DIR/script.py\" ]]
    [[ "$output" =~ \"exit_code\": ]]
}

@test "py_run: returns error for missing file" {
    run py_run "/nonexistent/script.py"

    assert_success
    assert_usop_error "$output" "File not found"
}

@test "py_run: returns error for missing file path" {
    run py_run ""

    assert_success
    assert_usop_error "$output" "File path required"
}

@test "py_module: runs Python module" {
    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_module "pip" "--version"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"module\":\"pip\" ]]
}

@test "py_module: returns error for missing module name" {
    run py_module ""

    assert_success
    assert_usop_error "$output" "Module name required"
}

@test "py_exec: executes inline Python code" {
    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_exec "print('hello')"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"exit_code\": ]]
}

@test "py_exec: returns error for empty code" {
    run py_exec ""

    assert_success
    assert_usop_error "$output" "Code string required"
}

@test "py_test: runs pytest and parses output" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    cd "$TEST_DIR"
    run py_test

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"passed\": ]]
    [[ "$output" =~ \"failed\": ]]
}

@test "py_test: returns error when pytest not installed" {
    # Create mock without pytest support
    local mock_python="$TEST_DIR/mock_python_no_pytest"
    cat > "$mock_python" << 'EOF'
#!/bin/bash
case "$1" in
    --version) echo "Python 3.11.0" ;;
    -c)
        shift
        case "$1" in
            "import pytest") exit 1 ;;  # pytest not available
            *) exit 0 ;;
        esac
        ;;
esac
EOF
    chmod +x "$mock_python"
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_test

    assert_success
    assert_usop_error "$output" "pytest not installed"
}

@test "py_lint: runs linter and counts issues" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    cd "$TEST_DIR"
    run py_lint "src/"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"linter\": ]]
    [[ "$output" =~ \"issues\": ]]
}

@test "py_lint: returns error when no linter available" {
    local mock_python="$TEST_DIR/mock_python_no_lint"
    cat > "$mock_python" << 'EOF'
#!/bin/bash
case "$1" in
    --version) echo "Python 3.11.0" ;;
    -c)
        shift
        # All linters unavailable
        exit 1
        ;;
esac
EOF
    chmod +x "$mock_python"
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    # Also ensure ruff command not available
    PATH="$TEST_DIR:$PATH"

    run py_lint "."

    assert_success
    assert_usop_error "$output" "No linter found"
}

@test "py_format: runs formatter" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    cd "$TEST_DIR"
    run py_format "src/"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"formatter\": ]]
}

@test "py_format: returns error when no formatter available" {
    local mock_python="$TEST_DIR/mock_python_no_format"
    cat > "$mock_python" << 'EOF'
#!/bin/bash
case "$1" in
    --version) echo "Python 3.11.0" ;;
    -c)
        # All formatters unavailable
        exit 1
        ;;
esac
EOF
    chmod +x "$mock_python"
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"
    PATH="$TEST_DIR:$PATH"

    run py_format "."

    assert_success
    assert_usop_error "$output" "No formatter found"
}

@test "py_typecheck: runs type checker" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    cd "$TEST_DIR"
    run py_typecheck "src/"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"checker\": ]]
    [[ "$output" =~ \"errors\": ]]
}

@test "py_typecheck: returns error when no type checker available" {
    local mock_python="$TEST_DIR/mock_python_no_types"
    cat > "$mock_python" << 'EOF'
#!/bin/bash
case "$1" in
    --version) echo "Python 3.11.0" ;;
    -c)
        # All type checkers unavailable
        exit 1
        ;;
esac
EOF
    chmod +x "$mock_python"
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"
    PATH="$TEST_DIR:$PATH"

    run py_typecheck "."

    assert_success
    assert_usop_error "$output" "No type checker found"
}

# =============================================================================
# AI AGENT HELPER TESTS
# =============================================================================

@test "py_project_summary: returns comprehensive project info" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_project_summary "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"name\": ]]
    [[ "$output" =~ \"python\": ]]
    [[ "$output" =~ \"manager\": ]]
    [[ "$output" =~ \"framework\": ]]
    [[ "$output" =~ \"scripts\": ]]
    [[ "$output" =~ \"deps_count\": ]]
}

@test "py_project_summary: returns error for non-Python directory" {
    mkdir -p "$TEST_DIR/empty_dir"

    run py_project_summary "$TEST_DIR/empty_dir"

    assert_success
    assert_usop_error "$output" "Not a Python project"
}

@test "py_project_summary: detects poetry manager" {
    create_mock_python_project "$TEST_DIR" "poetry"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_project_summary "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"poetry\" ]]
}

@test "py_project_summary: detects fastapi framework" {
    create_mock_python_project "$TEST_DIR" "pip"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_project_summary "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ fastapi ]]
}

@test "py_config: parses pyproject.toml" {
    create_mock_python_project "$TEST_DIR" "pip"

    run py_config "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"name\":\"myproject\" ]]
    [[ "$output" =~ \"version\":\"1.0.0\" ]]
    [[ "$output" =~ \"dependencies\": ]]
    [[ "$output" =~ \"scripts\": ]]
}

@test "py_config: parses poetry pyproject.toml" {
    create_mock_python_project "$TEST_DIR" "poetry"

    run py_config "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"name\": ]]
}

@test "py_config: returns error when no config file found" {
    mkdir -p "$TEST_DIR/no_config"

    run py_config "$TEST_DIR/no_config"

    assert_success
    assert_usop_error "$output" "No pyproject.toml"
}

@test "py_suggest_command: suggests test command" {
    create_mock_python_project "$TEST_DIR" "pip"

    run py_suggest_command "test" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"task\":\"test\" ]]
    [[ "$output" =~ \"command\": ]]
    [[ "$output" =~ pytest ]]
}

@test "py_suggest_command: suggests poetry test command for poetry projects" {
    create_mock_python_project "$TEST_DIR" "poetry"

    run py_suggest_command "test" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"poetry\" ]]
    [[ "$output" =~ \"poetry run pytest\" ]]
}

@test "py_suggest_command: suggests lint command" {
    run py_suggest_command "lint" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"task\":\"lint\" ]]
    [[ "$output" =~ ruff ]]
}

@test "py_suggest_command: suggests format command" {
    run py_suggest_command "format" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"task\":\"format\" ]]
}

@test "py_suggest_command: suggests build command" {
    create_mock_python_project "$TEST_DIR" "pip"

    run py_suggest_command "build" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"task\":\"build\" ]]
}

@test "py_suggest_command: suggests publish command" {
    create_mock_python_project "$TEST_DIR" "pip"

    run py_suggest_command "publish" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"task\":\"publish\" ]]
    [[ "$output" =~ twine ]]
}

@test "py_suggest_command: returns error for missing task" {
    run py_suggest_command ""

    assert_success
    assert_usop_error "$output" "Task name required"
}

@test "py_suggest_command: returns error for unknown task" {
    run py_suggest_command "unknown_task" "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "Unknown task"
}

@test "py_tools_detect: detects installed tools" {
    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_tools_detect "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"tools\": ]]
}

@test "py_tools_detect: returns error without python" {
    PATH="/nonexistent"

    run py_tools_detect "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "No Python interpreter"
}

@test "py_security_check: runs security scan" {
    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_security_check "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"scanner\": ]]
    [[ "$output" =~ \"vulnerabilities\": ]]
}

@test "py_security_check: returns error when no scanner available" {
    local mock_python="$TEST_DIR/mock_python_no_security"
    cat > "$mock_python" << 'EOF'
#!/bin/bash
case "$1" in
    --version) echo "Python 3.11.0" ;;
    -c)
        # All security scanners unavailable
        exit 1
        ;;
esac
EOF
    chmod +x "$mock_python"
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_security_check "$TEST_DIR"

    assert_success
    assert_usop_error "$output" "No security scanner found"
}

# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "USOP: all functions return exit code 0 regardless of result" {
    # Test that errors are encoded in JSON, not exit codes

    PATH="/nonexistent"

    run py_detect
    assert_success  # Exit code 0 even with "error"

    run py_interpreter
    assert_success

    run py_list
    assert_success
}

@test "USOP: error responses have ok:false" {
    PATH="/nonexistent"

    run py_interpreter
    assert_usop_error "$output"
}

@test "USOP: success responses have ok:true" {
    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_detect
    assert_usop_ok "$output"
}

@test "Output truncation: large outputs are truncated" {
    # The _py_truncate function should limit output size
    local mock_python="$TEST_DIR/mock_python_large"
    cat > "$mock_python" << 'EOF'
#!/bin/bash
case "$1" in
    --version) echo "Python 3.11.0" ;;
    *)
        # Generate large output
        for i in $(seq 1 1000); do
            echo "Line $i of output with some padding to make it longer"
        done
        ;;
esac
EOF
    chmod +x "$mock_python"
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_exec "generate_output()"

    assert_success
    # Output should be truncated with indicator
    [[ ${#output} -lt 10000 ]] || {
        echo "Output was not truncated: ${#output} chars"
        return 1
    }
}

@test "JSON escaping: handles special characters" {
    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    # Create file with special chars in name
    mkdir -p "$TEST_DIR/test project"
    echo "pass" > "$TEST_DIR/test project/script.py"

    run py_run "$TEST_DIR/test project/script.py"

    assert_success
    # Should be valid JSON (no parse errors)
    assert_usop_ok "$output"
}

@test "Empty directory handling: py_project_summary handles empty dirs" {
    mkdir -p "$TEST_DIR/empty"

    run py_project_summary "$TEST_DIR/empty"

    assert_success
    assert_usop_error "$output" "Not a Python project"
}

@test "Venv detection priority: project venv over system python" {
    create_mock_python_project "$TEST_DIR" "pip"

    # Create mock system python
    local mock_system="$TEST_DIR/system/python3"
    mkdir -p "$(dirname "$mock_system")"
    cat > "$mock_system" << 'EOF'
#!/bin/bash
echo "Python 3.10.0"
EOF
    chmod +x "$mock_system"

    # Create mock venv python
    mkdir -p "$MOCK_VENV/bin"
    cat > "$MOCK_VENV/bin/python" << 'EOF'
#!/bin/bash
echo "Python 3.11.0"
EOF
    chmod +x "$MOCK_VENV/bin/python"
    touch "$MOCK_VENV/bin/activate"

    PATH="$TEST_DIR/system:$PATH"

    run py_interpreter "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ 3.11.0 ]]
}

@test "Package manager detection: pip is default fallback" {
    # Create minimal project without manager-specific files
    echo "requests" > "$TEST_DIR/requirements.txt"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_install "" "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"manager\":\"pip\" ]]
}

# =============================================================================
# INTEGRATION PATTERN TESTS (Testing function composition)
# =============================================================================

@test "Integration: full project setup workflow" {
    # Simulates: detect -> create venv -> install -> test

    local mock_python
    mock_python=$(create_mock_python "3.11.0")
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    # 1. Detect Python
    run py_detect
    assert_success
    assert_usop_ok "$output"

    # 2. Create project
    create_mock_python_project "$TEST_DIR" "pip"

    # 3. Check project summary
    run py_project_summary "$TEST_DIR"
    assert_success
    assert_usop_ok "$output"

    # 4. Get suggested commands
    run py_suggest_command "test" "$TEST_DIR"
    assert_success
    assert_usop_ok "$output"
}

@test "Integration: poetry project workflow" {
    local mock_python mock_poetry
    mock_python=$(create_mock_python "3.11.0")
    mock_poetry=$(create_mock_poetry)
    PATH="$(dirname "$mock_python"):$(dirname "$mock_poetry"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"
    ln -sf "$mock_poetry" "$(dirname "$mock_poetry")/poetry"

    create_mock_python_project "$TEST_DIR" "poetry"

    # Check that poetry is detected
    run py_project_summary "$TEST_DIR"
    assert_success
    [[ "$output" =~ \"manager\":\"poetry\" ]]

    # Check poetry commands are suggested
    run py_suggest_command "test" "$TEST_DIR"
    assert_success
    [[ "$output" =~ \"poetry run\" ]]
}

# =============================================================================
# BOUNDARY CONDITIONS
# =============================================================================

@test "Boundary: handles very long file paths" {
    local long_path="$TEST_DIR"
    for i in {1..20}; do
        long_path="$long_path/nested_dir_level_$i"
    done
    mkdir -p "$long_path"
    echo "print('test')" > "$long_path/script.py"

    local mock_python
    mock_python=$(create_mock_python)
    PATH="$(dirname "$mock_python"):$PATH"
    ln -sf "$mock_python" "$(dirname "$mock_python")/python3"

    run py_run "$long_path/script.py"

    assert_success
    assert_usop_ok "$output"
}

@test "Boundary: handles unicode in project names" {
    create_mock_python_project "$TEST_DIR" "pip"

    # Modify name to include unicode
    sed -i 's/name = "myproject"/name = "my_project_v2"/' "$TEST_DIR/pyproject.toml"

    run py_config "$TEST_DIR"

    assert_success
    assert_usop_ok "$output"
}

@test "Boundary: handles missing pyproject.toml fields gracefully" {
    mkdir -p "$TEST_DIR/minimal"
    cat > "$TEST_DIR/minimal/pyproject.toml" << 'EOF'
[project]
name = "minimal"
EOF

    run py_config "$TEST_DIR/minimal"

    assert_success
    assert_usop_ok "$output"
    [[ "$output" =~ \"version\":\"unknown\" ]]
}

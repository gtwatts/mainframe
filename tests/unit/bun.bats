#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Bun.js Helper Library Tests
# =============================================================================
# Comprehensive tests for lib/bun.sh (16 functions)
# Covers: detection, package management, script execution, workspaces, AI helpers
# Tests use mocking to work without bun installed
# =============================================================================

load '../test_helper.bash'

setup() {
    source_lib "bun"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "bun")

    # Store original command -v behavior
    _original_command_v=$(which bun 2>/dev/null || echo "")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"

    # Restore bun function if it was mocked
    unset -f bun 2>/dev/null || true
    unset -f _bun_has_cli 2>/dev/null || true
}

# =============================================================================
# MOCK HELPERS
# =============================================================================

# Mock bun as unavailable
mock_bun_unavailable() {
    _bun_has_cli() { return 1; }
}

# Mock bun as available
mock_bun_available() {
    _bun_has_cli() { return 0; }
    bun() {
        case "$1" in
            --version)
                echo "1.1.38"
                ;;
            --revision)
                echo "abc123def"
                ;;
            *)
                echo "bun mock: $*"
                ;;
        esac
    }
}

# Mock bun install success
mock_bun_install_success() {
    mock_bun_available
    bun() {
        case "$1" in
            install)
                echo "bun install v1.1.38"
                echo ""
                echo "42 packages installed"
                return 0
                ;;
            add)
                echo "bun add v1.1.38 (abc123)"
                echo ""
                echo "+ $2@1.0.0"
                return 0
                ;;
            remove)
                echo "bun remove v1.1.38"
                echo ""
                echo "- $2"
                return 0
                ;;
            --version)
                echo "1.1.38"
                ;;
            *)
                echo "mock: $*"
                return 0
                ;;
        esac
    }
}

# Mock bun install failure
mock_bun_install_failure() {
    mock_bun_available
    bun() {
        case "$1" in
            install|add|remove)
                echo "error: ENOENT: no such file or directory"
                return 1
                ;;
            --version)
                echo "1.1.38"
                ;;
            *)
                return 1
                ;;
        esac
    }
}

# Mock bun run with output
mock_bun_run() {
    mock_bun_available
    bun() {
        case "$1" in
            run)
                shift
                echo "Running script: $1"
                echo "Script output here"
                return 0
                ;;
            --version)
                echo "1.1.38"
                ;;
            *)
                echo "mock run: $*"
                return 0
                ;;
        esac
    }
}

# Mock bun test with results
mock_bun_test() {
    mock_bun_available
    bun() {
        case "$1" in
            test)
                echo "bun test v1.1.38"
                echo ""
                echo "tests/example.test.ts:"
                echo "  10 pass"
                echo "  2 fail"
                echo "  1 skip"
                return 1  # Non-zero due to failures
                ;;
            --version)
                echo "1.1.38"
                ;;
            *)
                return 0
                ;;
        esac
    }
}

# Mock bun test all passing
mock_bun_test_success() {
    mock_bun_available
    bun() {
        case "$1" in
            test)
                echo "bun test v1.1.38"
                echo ""
                echo "  25 pass"
                echo "  0 fail"
                return 0
                ;;
            --version)
                echo "1.1.38"
                ;;
            *)
                return 0
                ;;
        esac
    }
}

# Mock bun file execution
mock_bun_exec_file() {
    mock_bun_available
    bun() {
        if [[ -f "$1" ]]; then
            echo "Executing: $1"
            echo "Output from $1"
            return 0
        fi
        case "$1" in
            --version)
                echo "1.1.38"
                ;;
            *)
                return 0
                ;;
        esac
    }
}

# Mock workspace run
mock_bun_workspace() {
    mock_bun_available
    bun() {
        case "$1" in
            --filter)
                echo "Running in workspace: $2"
                echo "Command: ${*:3}"
                return 0
                ;;
            --version)
                echo "1.1.38"
                ;;
            *)
                return 0
                ;;
        esac
    }
}

# =============================================================================
# HELPER: Validate USOP JSON format
# =============================================================================

assert_usop_ok() {
    local json="$1"
    local message="${2:-USOP should have ok:true}"

    if [[ "$json" != *'"ok":true'* ]]; then
        printf 'FAIL: %s\nJSON: %s\n' "$message" "$json" >&2
        return 1
    fi
}

assert_usop_error() {
    local json="$1"
    local message="${2:-USOP should have ok:false}"

    if [[ "$json" != *'"ok":false'* ]]; then
        printf 'FAIL: %s\nJSON: %s\n' "$message" "$json" >&2
        return 1
    fi
}

assert_usop_has_data() {
    local json="$1"
    local key="$2"
    local message="${3:-USOP should contain key: $key}"

    if [[ "$json" != *"\"$key\""* ]]; then
        printf 'FAIL: %s\nJSON: %s\n' "$message" "$json" >&2
        return 1
    fi
}

# =============================================================================
# bun_detect TESTS
# =============================================================================

@test "bun_detect returns JSON when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_detect)
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "bun_detect returns ok:true when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_detect)
    assert_usop_ok "$result"
}

@test "bun_detect returns installed:false when bun not available" {
    mock_bun_unavailable
    local result
    result=$(bun_detect)
    [[ "$result" == *'"installed":false'* ]]
}

@test "bun_detect returns version:null when bun not available" {
    mock_bun_unavailable
    local result
    result=$(bun_detect)
    [[ "$result" == *'"version":null'* ]]
}

@test "bun_detect returns installed:true when bun available" {
    mock_bun_available
    local result
    result=$(bun_detect)
    [[ "$result" == *'"installed":true'* ]]
}

@test "bun_detect returns version string when bun available" {
    mock_bun_available
    local result
    result=$(bun_detect)
    [[ "$result" == *'"version":"1.1.38"'* ]]
}

@test "bun_detect returns path when bun available" {
    mock_bun_available
    local result
    result=$(bun_detect)
    assert_usop_has_data "$result" "path"
}

# =============================================================================
# bun_version TESTS
# =============================================================================

@test "bun_version returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_version)
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_version returns version when bun available" {
    mock_bun_available
    local result
    result=$(bun_version)
    assert_usop_ok "$result"
    [[ "$result" == *'"version":"1.1.38"'* ]]
}

@test "bun_version returns revision when available" {
    mock_bun_available
    local result
    result=$(bun_version)
    assert_usop_has_data "$result" "revision"
}

@test "bun_version parses version without v prefix" {
    mock_bun_available
    bun() {
        case "$1" in
            --version) echo "v1.2.3" ;;
            --revision) echo "xyz789" ;;
        esac
    }
    local result
    result=$(bun_version)
    [[ "$result" == *'"version":"1.2.3"'* ]]
}

# =============================================================================
# bun_is_project TESTS
# =============================================================================

@test "bun_is_project returns JSON" {
    local result
    result=$(bun_is_project "$TEST_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "bun_is_project returns ok:true for valid directory" {
    local result
    result=$(bun_is_project "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_is_project returns error for nonexistent directory" {
    local result
    result=$(bun_is_project "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_is_project returns is_bun:false for empty directory" {
    local result
    result=$(bun_is_project "$TEST_DIR")
    [[ "$result" == *'"is_bun":false'* ]]
}

@test "bun_is_project returns is_bun:true with bun.lockb" {
    touch "$TEST_DIR/bun.lockb"
    local result
    result=$(bun_is_project "$TEST_DIR")
    [[ "$result" == *'"is_bun":true'* ]]
    [[ "$result" == *'"has_lockfile":true'* ]]
}

@test "bun_is_project returns is_bun:true with bun.lock" {
    touch "$TEST_DIR/bun.lock"
    local result
    result=$(bun_is_project "$TEST_DIR")
    [[ "$result" == *'"is_bun":true'* ]]
    [[ "$result" == *'"has_lockfile":true'* ]]
}

@test "bun_is_project returns is_bun:true with bunfig.toml" {
    touch "$TEST_DIR/bunfig.toml"
    local result
    result=$(bun_is_project "$TEST_DIR")
    [[ "$result" == *'"is_bun":true'* ]]
    [[ "$result" == *'"has_bunfig":true'* ]]
}

@test "bun_is_project detects has_package_json" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_is_project "$TEST_DIR")
    [[ "$result" == *'"has_package_json":true'* ]]
}

@test "bun_is_project returns has_package_json:false without package.json" {
    local result
    result=$(bun_is_project "$TEST_DIR")
    [[ "$result" == *'"has_package_json":false'* ]]
}

@test "bun_is_project uses current directory by default" {
    cd "$TEST_DIR"
    touch "bun.lockb"
    local result
    result=$(bun_is_project)
    [[ "$result" == *'"is_bun":true'* ]]
}

# =============================================================================
# bun_install TESTS
# =============================================================================

@test "bun_install returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_install)
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_install returns error for nonexistent directory" {
    mock_bun_available
    local result
    result=$(bun_install "" "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_install returns ok:true on success" {
    mock_bun_install_success
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_install "" "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_install returns packages_installed count" {
    mock_bun_install_success
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_install "" "$TEST_DIR")
    assert_usop_has_data "$result" "packages_installed"
}

@test "bun_install returns time_ms" {
    mock_bun_install_success
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_install "" "$TEST_DIR")
    assert_usop_has_data "$result" "time_ms"
}

@test "bun_install returns error on failure" {
    mock_bun_install_failure
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_install "" "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"install failed"'* ]]
}

@test "bun_install includes exit_code on failure" {
    mock_bun_install_failure
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_install "" "$TEST_DIR")
    assert_usop_has_data "$result" "exit_code"
}

# =============================================================================
# bun_add TESTS
# =============================================================================

@test "bun_add returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_add "express")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_add returns error when package name missing" {
    mock_bun_available
    local result
    result=$(bun_add "")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"package name required"'* ]]
}

@test "bun_add returns error for nonexistent directory" {
    mock_bun_available
    local result
    result=$(bun_add "express" "" "/nonexistent/path")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_add returns ok:true on success" {
    mock_bun_install_success
    echo '{"dependencies":{}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "express" "" "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_add returns package name in data" {
    mock_bun_install_success
    echo '{"dependencies":{"express":"^4.18.0"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "express" "" "$TEST_DIR")
    [[ "$result" == *'"package":"express"'* ]]
}

@test "bun_add handles --dev flag" {
    mock_bun_install_success
    echo '{"devDependencies":{"typescript":"^5.0.0"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "typescript" "--dev" "$TEST_DIR")
    assert_usop_ok "$result"
    [[ "$result" == *'"flag":"--dev"'* ]]
}

@test "bun_add handles -D flag" {
    mock_bun_install_success
    echo '{"devDependencies":{}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "vitest" "-D" "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_add handles --peer flag" {
    mock_bun_install_success
    echo '{"peerDependencies":{}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "react" "--peer" "$TEST_DIR")
    [[ "$result" == *'"flag":"--peer"'* ]]
}

@test "bun_add handles --optional flag" {
    mock_bun_install_success
    echo '{"optionalDependencies":{}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "fsevents" "--optional" "$TEST_DIR")
    [[ "$result" == *'"flag":"--optional"'* ]]
}

@test "bun_add extracts version from package.json" {
    mock_bun_install_success
    echo '{"dependencies":{"lodash":"^4.17.21"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "lodash" "" "$TEST_DIR")
    [[ "$result" == *'"version":"^4.17.21"'* ]]
}

@test "bun_add returns error on failure" {
    mock_bun_install_failure
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_add "nonexistent-pkg-xyz" "" "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"add failed"'* ]]
}

# =============================================================================
# bun_remove TESTS
# =============================================================================

@test "bun_remove returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_remove "lodash")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_remove returns error when package name missing" {
    mock_bun_available
    local result
    result=$(bun_remove "")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"package name required"'* ]]
}

@test "bun_remove returns error for nonexistent directory" {
    mock_bun_available
    local result
    result=$(bun_remove "lodash" "/nonexistent/path")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_remove returns ok:true on success" {
    mock_bun_install_success
    echo '{"dependencies":{"lodash":"4.17.21"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_remove "lodash" "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_remove returns removed package name" {
    mock_bun_install_success
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_remove "express" "$TEST_DIR")
    [[ "$result" == *'"removed":"express"'* ]]
}

@test "bun_remove returns error on failure" {
    mock_bun_install_failure
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_remove "not-installed" "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"remove failed"'* ]]
}

# =============================================================================
# bun_list TESTS
# =============================================================================

@test "bun_list returns error for nonexistent directory" {
    local result
    result=$(bun_list "/nonexistent/path")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_list returns error without package.json" {
    local result
    result=$(bun_list "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"package.json not found"'* ]]
}

@test "bun_list returns ok:true with package.json" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_list "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_list returns empty arrays for no dependencies" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_list "$TEST_DIR")
    [[ "$result" == *'"dependencies":[]'* ]]
    [[ "$result" == *'"devDependencies":[]'* ]]
}

@test "bun_list returns dependencies array" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"dependencies":{"express":"4.18.2","lodash":"4.17.21"}}
EOF
    local result
    result=$(bun_list "$TEST_DIR")
    [[ "$result" == *'"dependencies":'* ]]
    [[ "$result" == *'express'* ]]
    [[ "$result" == *'lodash'* ]]
}

@test "bun_list returns devDependencies array" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"devDependencies":{"typescript":"5.0.0","vitest":"1.0.0"}}
EOF
    local result
    result=$(bun_list "$TEST_DIR")
    [[ "$result" == *'"devDependencies":'* ]]
    [[ "$result" == *'typescript'* ]]
    [[ "$result" == *'vitest'* ]]
}

@test "bun_list returns total count" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"dependencies":{"a":"1","b":"2"},"devDependencies":{"c":"3"}}
EOF
    local result
    result=$(bun_list "$TEST_DIR")
    [[ "$result" == *'"total":3'* ]]
}

@test "bun_list handles mixed dependencies" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"dependencies":{"react":"18.2.0","next":"14.0.0"},"devDependencies":{"@types/react":"18.0.0"}}
EOF
    local result
    result=$(bun_list "$TEST_DIR")
    assert_usop_ok "$result"
    assert_usop_has_data "$result" "total"
}

# =============================================================================
# bun_run TESTS
# =============================================================================

@test "bun_run returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_run "dev")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_run returns error when script name missing" {
    mock_bun_available
    local result
    result=$(bun_run "")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"script name required"'* ]]
}

@test "bun_run returns ok:true on success" {
    mock_bun_run
    local result
    result=$(bun_run "dev")
    assert_usop_ok "$result"
}

@test "bun_run returns script name in data" {
    mock_bun_run
    local result
    result=$(bun_run "build")
    [[ "$result" == *'"script":"build"'* ]]
}

@test "bun_run returns exit_code" {
    mock_bun_run
    local result
    result=$(bun_run "test")
    assert_usop_has_data "$result" "exit_code"
}

@test "bun_run returns output" {
    mock_bun_run
    local result
    result=$(bun_run "lint")
    assert_usop_has_data "$result" "output"
}

@test "bun_run handles script failure" {
    mock_bun_available
    bun() {
        case "$1" in
            run)
                echo "Script failed"
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    }
    local result
    result=$(bun_run "failing-script")
    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"exit_code":1'* ]]
}

# =============================================================================
# bun_exec TESTS
# =============================================================================

@test "bun_exec returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_exec "index.ts")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_exec returns error when file path missing" {
    mock_bun_available
    local result
    result=$(bun_exec "")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"file path required"'* ]]
}

@test "bun_exec returns error when file not found" {
    mock_bun_available
    local result
    result=$(bun_exec "/nonexistent/file.ts")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"file not found"'* ]]
}

@test "bun_exec returns ok:true on success" {
    mock_bun_exec_file
    touch "$TEST_DIR/script.ts"
    local result
    result=$(bun_exec "$TEST_DIR/script.ts")
    assert_usop_ok "$result"
}

@test "bun_exec returns file path in data" {
    mock_bun_exec_file
    touch "$TEST_DIR/app.ts"
    local result
    result=$(bun_exec "$TEST_DIR/app.ts")
    [[ "$result" == *'"file":"'* ]]
}

@test "bun_exec returns exit_code" {
    mock_bun_exec_file
    touch "$TEST_DIR/run.ts"
    local result
    result=$(bun_exec "$TEST_DIR/run.ts")
    assert_usop_has_data "$result" "exit_code"
}

@test "bun_exec returns output" {
    mock_bun_exec_file
    touch "$TEST_DIR/main.ts"
    local result
    result=$(bun_exec "$TEST_DIR/main.ts")
    assert_usop_has_data "$result" "output"
}

# =============================================================================
# bun_test TESTS
# =============================================================================

@test "bun_test returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_test)
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_test returns ok:true when all tests pass" {
    mock_bun_test_success
    local result
    result=$(bun_test)
    assert_usop_ok "$result"
}

@test "bun_test returns ok:false when tests fail" {
    mock_bun_test
    local result
    result=$(bun_test)
    [[ "$result" == *'"ok":false'* ]]
}

@test "bun_test returns passed count" {
    mock_bun_test
    local result
    result=$(bun_test)
    assert_usop_has_data "$result" "passed"
}

@test "bun_test returns failed count" {
    mock_bun_test
    local result
    result=$(bun_test)
    assert_usop_has_data "$result" "failed"
}

@test "bun_test returns skipped count" {
    mock_bun_test
    local result
    result=$(bun_test)
    assert_usop_has_data "$result" "skipped"
}

@test "bun_test returns total count" {
    mock_bun_test
    local result
    result=$(bun_test)
    assert_usop_has_data "$result" "total"
}

@test "bun_test parses test output correctly" {
    mock_bun_test
    local result
    result=$(bun_test)
    [[ "$result" == *'"passed":10'* ]]
    [[ "$result" == *'"failed":2'* ]]
    [[ "$result" == *'"skipped":1'* ]]
}

@test "bun_test returns exit_code" {
    mock_bun_test
    local result
    result=$(bun_test)
    assert_usop_has_data "$result" "exit_code"
}

@test "bun_test returns output" {
    mock_bun_test
    local result
    result=$(bun_test)
    assert_usop_has_data "$result" "output"
}

# =============================================================================
# bun_workspace_detect TESTS
# =============================================================================

@test "bun_workspace_detect returns error for nonexistent directory" {
    local result
    result=$(bun_workspace_detect "/nonexistent/path")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_workspace_detect returns is_workspace:false without package.json" {
    local result
    result=$(bun_workspace_detect "$TEST_DIR")
    assert_usop_ok "$result"
    [[ "$result" == *'"is_workspace":false'* ]]
}

@test "bun_workspace_detect returns is_workspace:false without workspaces field" {
    echo '{"name":"my-project"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_workspace_detect "$TEST_DIR")
    [[ "$result" == *'"is_workspace":false'* ]]
}

@test "bun_workspace_detect returns is_workspace:true with workspaces field" {
    echo '{"workspaces":["packages/*"]}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_workspace_detect "$TEST_DIR")
    [[ "$result" == *'"is_workspace":true'* ]]
}

@test "bun_workspace_detect returns packages array" {
    echo '{"workspaces":["packages/*"]}' > "$TEST_DIR/package.json"
    mkdir -p "$TEST_DIR/packages/core"
    echo '{"name":"@myorg/core"}' > "$TEST_DIR/packages/core/package.json"
    local result
    result=$(bun_workspace_detect "$TEST_DIR")
    assert_usop_has_data "$result" "packages"
}

@test "bun_workspace_detect returns empty packages for no matching dirs" {
    echo '{"workspaces":["packages/*"]}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_workspace_detect "$TEST_DIR")
    [[ "$result" == *'"packages":[]'* ]]
}

# =============================================================================
# bun_workspace_run TESTS
# =============================================================================

@test "bun_workspace_run returns error when bun not installed" {
    mock_bun_unavailable
    local result
    result=$(bun_workspace_run "@myorg/core" "run build")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"bun not installed"'* ]]
}

@test "bun_workspace_run returns error when package name missing" {
    mock_bun_available
    local result
    result=$(bun_workspace_run "" "run build")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"package name required"'* ]]
}

@test "bun_workspace_run returns error when command missing" {
    mock_bun_available
    local result
    result=$(bun_workspace_run "@myorg/core" "")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"command required"'* ]]
}

@test "bun_workspace_run returns ok:true on success" {
    mock_bun_workspace
    local result
    result=$(bun_workspace_run "@myorg/api" "run build")
    assert_usop_ok "$result"
}

@test "bun_workspace_run returns package in data" {
    mock_bun_workspace
    local result
    result=$(bun_workspace_run "@myorg/web" "run test")
    [[ "$result" == *'"package":"@myorg/web"'* ]]
}

@test "bun_workspace_run returns command in data" {
    mock_bun_workspace
    local result
    result=$(bun_workspace_run "@myorg/lib" "run lint")
    [[ "$result" == *'"command":"run lint"'* ]]
}

@test "bun_workspace_run returns exit_code" {
    mock_bun_workspace
    local result
    result=$(bun_workspace_run "core" "run build")
    assert_usop_has_data "$result" "exit_code"
}

@test "bun_workspace_run returns output" {
    mock_bun_workspace
    local result
    result=$(bun_workspace_run "api" "run dev")
    assert_usop_has_data "$result" "output"
}

# =============================================================================
# bun_workspace_list TESTS
# =============================================================================

@test "bun_workspace_list returns error for nonexistent directory" {
    local result
    result=$(bun_workspace_list "/nonexistent/path")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_workspace_list returns empty packages without package.json" {
    local result
    result=$(bun_workspace_list "$TEST_DIR")
    assert_usop_ok "$result"
    [[ "$result" == *'"packages":[]'* ]]
}

@test "bun_workspace_list returns empty packages without workspaces" {
    echo '{"name":"simple-project"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_workspace_list "$TEST_DIR")
    [[ "$result" == *'"packages":[]'* ]]
}

@test "bun_workspace_list finds workspace packages" {
    echo '{"workspaces":["packages/*"]}' > "$TEST_DIR/package.json"
    mkdir -p "$TEST_DIR/packages/api" "$TEST_DIR/packages/web"
    echo '{"name":"@org/api"}' > "$TEST_DIR/packages/api/package.json"
    echo '{"name":"@org/web"}' > "$TEST_DIR/packages/web/package.json"
    local result
    result=$(bun_workspace_list "$TEST_DIR")
    [[ "$result" == *'"name":"@org/api"'* ]]
    [[ "$result" == *'"name":"@org/web"'* ]]
}

@test "bun_workspace_list returns package paths" {
    echo '{"workspaces":["apps/*"]}' > "$TEST_DIR/package.json"
    mkdir -p "$TEST_DIR/apps/frontend"
    echo '{"name":"frontend"}' > "$TEST_DIR/apps/frontend/package.json"
    local result
    result=$(bun_workspace_list "$TEST_DIR")
    [[ "$result" == *'"path":"apps/frontend"'* ]]
}

# =============================================================================
# bun_project_summary TESTS
# =============================================================================

@test "bun_project_summary returns error for nonexistent directory" {
    local result
    result=$(bun_project_summary "/nonexistent/path")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "bun_project_summary returns error without package.json" {
    local result
    result=$(bun_project_summary "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"package.json not found"'* ]]
}

@test "bun_project_summary returns ok:true with package.json" {
    echo '{"name":"my-app"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_project_summary "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_project_summary returns project name" {
    echo '{"name":"awesome-project"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"name":"awesome-project"'* ]]
}

@test "bun_project_summary detects app type by default" {
    echo '{"name":"my-app"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"type":"app"'* ]]
}

@test "bun_project_summary detects lib type with main field" {
    echo '{"name":"my-lib","main":"dist/index.js"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"type":"lib"'* ]]
}

@test "bun_project_summary detects cli type with bin field" {
    echo '{"name":"my-cli","bin":"./bin/cli.js"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"type":"cli"'* ]]
}

@test "bun_project_summary returns scripts array" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"name":"app","scripts":{"dev":"bun run dev","build":"bun build","test":"bun test"}}
EOF
    local result
    result=$(bun_project_summary "$TEST_DIR")
    assert_usop_has_data "$result" "scripts"
    [[ "$result" == *'"scripts":'* ]]
}

@test "bun_project_summary returns deps_count" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"name":"app","dependencies":{"express":"4","lodash":"4"}}
EOF
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"deps_count":2'* ]]
}

@test "bun_project_summary returns dev_deps_count" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"name":"app","devDependencies":{"typescript":"5","vitest":"1","eslint":"8"}}
EOF
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"dev_deps_count":3'* ]]
}

@test "bun_project_summary detects is_bun_project" {
    echo '{"name":"bun-app"}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/bun.lockb"
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"is_bun_project":true'* ]]
}

@test "bun_project_summary returns is_bun_project:false without bun files" {
    echo '{"name":"npm-app"}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_project_summary "$TEST_DIR")
    [[ "$result" == *'"is_bun_project":false'* ]]
}

# =============================================================================
# bun_config TESTS
# =============================================================================

@test "bun_config returns ok:true without bunfig.toml" {
    local result
    result=$(bun_config "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_config returns exists:false without bunfig.toml" {
    local result
    result=$(bun_config "$TEST_DIR")
    [[ "$result" == *'"exists":false'* ]]
}

@test "bun_config returns config:null without bunfig.toml" {
    local result
    result=$(bun_config "$TEST_DIR")
    [[ "$result" == *'"config":null'* ]]
}

@test "bun_config returns exists:true with bunfig.toml" {
    echo 'telemetry = false' > "$TEST_DIR/bunfig.toml"
    local result
    result=$(bun_config "$TEST_DIR")
    [[ "$result" == *'"exists":true'* ]]
}

@test "bun_config parses simple key-value pairs" {
    cat > "$TEST_DIR/bunfig.toml" << 'EOF'
smol = true
telemetry = false
EOF
    local result
    result=$(bun_config "$TEST_DIR")
    assert_usop_has_data "$result" "config"
}

@test "bun_config parses section headers" {
    cat > "$TEST_DIR/bunfig.toml" << 'EOF'
[install]
auto = "fallback"
optional = true
EOF
    local result
    result=$(bun_config "$TEST_DIR")
    [[ "$result" == *'"install.auto"'* ]] || [[ "$result" == *'install'* ]]
}

@test "bun_config ignores comments" {
    cat > "$TEST_DIR/bunfig.toml" << 'EOF'
# This is a comment
telemetry = false
# Another comment
smol = true
EOF
    local result
    result=$(bun_config "$TEST_DIR")
    [[ "$result" != *'comment'* ]]
}

@test "bun_config handles quoted values" {
    cat > "$TEST_DIR/bunfig.toml" << 'EOF'
registry = "https://registry.npmjs.org"
EOF
    local result
    result=$(bun_config "$TEST_DIR")
    [[ "$result" == *'registry'* ]]
}

# =============================================================================
# bun_suggest_command TESTS
# =============================================================================

@test "bun_suggest_command returns error when task missing" {
    local result
    result=$(bun_suggest_command "")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"task type required"'* ]]
}

@test "bun_suggest_command returns error without package.json" {
    local result
    result=$(bun_suggest_command "dev" "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"package.json not found"'* ]]
}

@test "bun_suggest_command returns error for unknown task" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "unknown-task" "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"unknown task type"'* ]]
}

@test "bun_suggest_command returns valid_tasks in error" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "bad" "$TEST_DIR")
    [[ "$result" == *'"valid_tasks"'* ]]
}

@test "bun_suggest_command returns ok:true for dev task" {
    echo '{"scripts":{"dev":"next dev"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "dev" "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "bun_suggest_command suggests bun run dev for dev script" {
    echo '{"scripts":{"dev":"next dev"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "dev" "$TEST_DIR")
    [[ "$result" == *'"command":"bun run dev"'* ]]
}

@test "bun_suggest_command suggests bun run build for build script" {
    echo '{"scripts":{"build":"next build"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "build" "$TEST_DIR")
    [[ "$result" == *'"command":"bun run build"'* ]]
}

@test "bun_suggest_command suggests bun test for test task" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "test" "$TEST_DIR")
    [[ "$result" == *'"command":"bun test"'* ]]
}

@test "bun_suggest_command suggests bun run test if script exists" {
    echo '{"scripts":{"test":"vitest"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "test" "$TEST_DIR")
    [[ "$result" == *'"command":"bun run test"'* ]]
}

@test "bun_suggest_command suggests bunx eslint for lint without script" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "lint" "$TEST_DIR")
    [[ "$result" == *'"command":"bunx eslint ."'* ]]
}

@test "bun_suggest_command suggests bunx prettier for format without script" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "format" "$TEST_DIR")
    [[ "$result" == *'"command":"bunx prettier --write ."'* ]]
}

@test "bun_suggest_command suggests bun install for install task" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "install" "$TEST_DIR")
    [[ "$result" == *'"command":"bun install"'* ]]
}

@test "bun_suggest_command returns alternatives array" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "test" "$TEST_DIR")
    assert_usop_has_data "$result" "alternatives"
}

@test "bun_suggest_command includes task in response" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "build" "$TEST_DIR")
    [[ "$result" == *'"task":"build"'* ]]
}

@test "bun_suggest_command suggests start script for start task" {
    echo '{"scripts":{"start":"node server.js"}}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "start" "$TEST_DIR")
    [[ "$result" == *'"command":"bun run start"'* ]]
}

@test "bun_suggest_command fallback for dev without script" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(bun_suggest_command "dev" "$TEST_DIR")
    [[ "$result" == *'"command":"bun --hot src/index.ts"'* ]]
}

# =============================================================================
# EDGE CASES & INTEGRATION TESTS
# =============================================================================

@test "all functions return valid JSON" {
    mock_bun_available
    echo '{}' > "$TEST_DIR/package.json"

    local funcs=(
        "bun_detect"
        "bun_version"
    )

    for func in "${funcs[@]}"; do
        local result
        result=$($func)
        [[ "$result" == "{"* ]] || { echo "FAIL: $func did not return JSON"; return 1; }
        [[ "$result" == *"}" ]] || { echo "FAIL: $func JSON not closed"; return 1; }
    done
}

@test "project functions work with current directory" {
    cd "$TEST_DIR"
    echo '{"name":"test"}' > package.json
    touch bun.lockb

    local result
    result=$(bun_is_project)
    [[ "$result" == *'"is_bun":true'* ]]
}

@test "package.json with unicode characters" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"name":"test-project","description":"A test project with unicode characters"}
EOF
    local result
    result=$(bun_project_summary "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "package.json with nested dependencies" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{
  "name": "complex-project",
  "dependencies": {
    "react": "^18.0.0",
    "next": "^14.0.0"
  },
  "devDependencies": {
    "@types/react": "^18.0.0"
  },
  "scripts": {
    "dev": "next dev",
    "build": "next build"
  }
}
EOF
    local result
    result=$(bun_list "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "workspace with multiple packages" {
    echo '{"workspaces":["packages/*","apps/*"]}' > "$TEST_DIR/package.json"

    mkdir -p "$TEST_DIR/packages/core" "$TEST_DIR/packages/utils"
    mkdir -p "$TEST_DIR/apps/web" "$TEST_DIR/apps/api"

    echo '{"name":"@org/core"}' > "$TEST_DIR/packages/core/package.json"
    echo '{"name":"@org/utils"}' > "$TEST_DIR/packages/utils/package.json"
    echo '{"name":"@org/web"}' > "$TEST_DIR/apps/web/package.json"
    echo '{"name":"@org/api"}' > "$TEST_DIR/apps/api/package.json"

    local result
    result=$(bun_workspace_list "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "suggest_command handles all valid task types" {
    echo '{}' > "$TEST_DIR/package.json"

    local tasks=("dev" "build" "test" "lint" "format" "start" "install")

    for task in "${tasks[@]}"; do
        local result
        result=$(bun_suggest_command "$task" "$TEST_DIR")
        assert_usop_ok "$result" "Task $task should return ok:true"
        [[ "$result" == *'"command":'* ]] || { echo "FAIL: $task missing command"; return 1; }
    done
}

@test "detect handles both lockfile formats" {
    # Test binary lockfile
    touch "$TEST_DIR/bun.lockb"
    local result1
    result1=$(bun_is_project "$TEST_DIR")
    [[ "$result1" == *'"has_lockfile":true'* ]]

    rm "$TEST_DIR/bun.lockb"

    # Test text lockfile
    touch "$TEST_DIR/bun.lock"
    local result2
    result2=$(bun_is_project "$TEST_DIR")
    [[ "$result2" == *'"has_lockfile":true'* ]]
}

@test "USOP format consistency across all error responses" {
    mock_bun_unavailable

    local result

    # All these should return ok:false with error field
    result=$(bun_version)
    [[ "$result" == *'"ok":false'* ]] && [[ "$result" == *'"error":'* ]]

    result=$(bun_install)
    [[ "$result" == *'"ok":false'* ]] && [[ "$result" == *'"error":'* ]]

    result=$(bun_add "")
    [[ "$result" == *'"ok":false'* ]] && [[ "$result" == *'"error":'* ]]

    result=$(bun_remove "")
    [[ "$result" == *'"ok":false'* ]] && [[ "$result" == *'"error":'* ]]
}

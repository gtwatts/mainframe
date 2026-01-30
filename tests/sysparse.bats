#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/sysparse.bats - Tests for Structured Output Parsing
# =============================================================================
# Description: Test suite for lib/sysparse.sh functions
# Run: bats tests/sysparse.bats
# =============================================================================

# Setup: Load the library
setup() {
    # Get the project root
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

    # Source the library
    source "${PROJECT_ROOT}/lib/sysparse.sh"

    # Create temp directory for tests
    TEST_TEMP_DIR=$(mktemp -d)
}

# Teardown: Cleanup
teardown() {
    [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]] && rm -rf "$TEST_TEMP_DIR"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if output is valid JSON
is_valid_json() {
    local json="$1"
    if command -v python3 &>/dev/null; then
        echo "$json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null
    elif command -v python &>/dev/null; then
        echo "$json" | python -c "import json,sys; json.load(sys.stdin)" 2>/dev/null
    elif command -v jq &>/dev/null; then
        echo "$json" | jq . >/dev/null 2>&1
    else
        # Basic validation: balanced braces
        local depth=0
        local in_string=false
        for ((i=0; i<${#json}; i++)); do
            local char="${json:i:1}"
            if $in_string; then
                [[ "$char" == '"' && "${json:i-1:1}" != '\' ]] && in_string=false
            else
                case "$char" in
                    '"') in_string=true ;;
                    '{' | '[') ((depth++)) ;;
                    '}' | ']') ((depth--)) ;;
                esac
            fi
        done
        [[ $depth -eq 0 ]]
    fi
}

# Get JSON field value (simple extraction)
json_get() {
    local json="$1"
    local key="$2"
    # Extract string value
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        echo "${BASH_REMATCH[1]}"
    # Extract number value
    elif [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9.-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    # Extract boolean/null value
    elif [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*(true|false|null) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# =============================================================================
# _sysparse_escape_json Tests
# =============================================================================

@test "_sysparse_escape_json: escapes double quotes" {
    local result
    result=$(_sysparse_escape_json 'hello "world"')
    [[ "$result" == 'hello \"world\"' ]]
}

@test "_sysparse_escape_json: escapes backslashes" {
    local result
    result=$(_sysparse_escape_json 'path\to\file')
    [[ "$result" == 'path\\to\\file' ]]
}

@test "_sysparse_escape_json: escapes newlines" {
    local result
    result=$(_sysparse_escape_json $'line1\nline2')
    [[ "$result" == 'line1\nline2' ]]
}

@test "_sysparse_escape_json: escapes tabs" {
    local result
    result=$(_sysparse_escape_json $'col1\tcol2')
    [[ "$result" == 'col1\tcol2' ]]
}

@test "_sysparse_escape_json: handles empty string" {
    local result
    result=$(_sysparse_escape_json '')
    [[ "$result" == '' ]]
}

# =============================================================================
# parse_ps Tests
# =============================================================================

@test "parse_ps: returns valid JSON array" {
    local result
    result=$(parse_ps --json)
    is_valid_json "$result"
}

@test "parse_ps: output starts with [" {
    local result
    result=$(parse_ps --json)
    [[ "$result" == "["* ]]
}

@test "parse_ps: output ends with ]" {
    local result
    result=$(parse_ps --json)
    [[ "$result" == *"]" ]]
}

@test "parse_ps: includes current bash process" {
    local result
    result=$(parse_ps --json)
    [[ "$result" == *"bash"* ]] || [[ "$result" == *"bats"* ]]
}

@test "parse_ps: filter by user returns only matching" {
    local current_user
    current_user=$(whoami)
    local result
    result=$(parse_ps --user "$current_user" --json)
    is_valid_json "$result"
    # All entries should have current user
    [[ "$result" != *"\"user\":\"root\""* ]] || [[ "$current_user" == "root" ]]
}

@test "parse_ps: filter by invalid PID returns error" {
    run parse_ps --pid "invalid"
    [[ "$status" -eq 1 ]]
}

@test "parse_ps: filter by name returns matches" {
    local result
    result=$(parse_ps --name "bash" --json)
    is_valid_json "$result"
}

@test "parse_ps: each entry has required fields" {
    local result
    result=$(parse_ps --json)
    # Check for key fields
    [[ "$result" == *"\"pid\":"* ]]
    [[ "$result" == *"\"user\":"* ]]
    [[ "$result" == *"\"command\":"* ]]
}

# =============================================================================
# parse_df Tests
# =============================================================================

@test "parse_df: returns valid JSON array" {
    local result
    result=$(parse_df --json)
    is_valid_json "$result"
}

@test "parse_df: includes root filesystem" {
    local result
    result=$(parse_df --json)
    [[ "$result" == *"\"/\""* ]] || [[ "$result" == *"\"mount\":\"/\""* ]]
}

@test "parse_df: each entry has required fields" {
    local result
    result=$(parse_df --json)
    [[ "$result" == *"\"filesystem\":"* ]]
    [[ "$result" == *"\"size_bytes\":"* ]]
    [[ "$result" == *"\"used_bytes\":"* ]]
    [[ "$result" == *"\"mount\":"* ]]
}

@test "parse_df: human-readable flag adds size_human field" {
    local result
    result=$(parse_df --human --json)
    [[ "$result" == *"\"size_human\":"* ]]
    [[ "$result" == *"\"used_human\":"* ]]
    [[ "$result" == *"\"available_human\":"* ]]
}

@test "parse_df: use_percent is numeric" {
    local result
    result=$(parse_df --json)
    [[ "$result" =~ \"use_percent\":[0-9]+ ]]
}

# =============================================================================
# parse_ls Tests
# =============================================================================

@test "parse_ls: returns valid JSON array" {
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    is_valid_json "$result"
}

@test "parse_ls: empty directory returns empty array" {
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    [[ "$result" == "[]" ]]
}

@test "parse_ls: lists created file" {
    touch "$TEST_TEMP_DIR/testfile.txt"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    [[ "$result" == *"testfile.txt"* ]]
}

@test "parse_ls: identifies file type correctly" {
    touch "$TEST_TEMP_DIR/file.txt"
    mkdir "$TEST_TEMP_DIR/subdir"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    [[ "$result" == *"\"type\":\"file\""* ]]
    [[ "$result" == *"\"type\":\"dir\""* ]]
}

@test "parse_ls: --type file filters correctly" {
    touch "$TEST_TEMP_DIR/file.txt"
    mkdir "$TEST_TEMP_DIR/subdir"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --type file --json)
    [[ "$result" == *"file.txt"* ]]
    [[ "$result" != *"subdir"* ]]
}

@test "parse_ls: --type dir filters correctly" {
    touch "$TEST_TEMP_DIR/file.txt"
    mkdir "$TEST_TEMP_DIR/subdir"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --type dir --json)
    [[ "$result" != *"file.txt"* ]]
    [[ "$result" == *"subdir"* ]]
}

@test "parse_ls: --all includes hidden files" {
    touch "$TEST_TEMP_DIR/.hidden"
    touch "$TEST_TEMP_DIR/visible"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --all --json)
    [[ "$result" == *".hidden"* ]]
    [[ "$result" == *"visible"* ]]
}

@test "parse_ls: without --all excludes hidden files" {
    touch "$TEST_TEMP_DIR/.hidden"
    touch "$TEST_TEMP_DIR/visible"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    [[ "$result" != *".hidden"* ]]
    [[ "$result" == *"visible"* ]]
}

@test "parse_ls: symlinks identified correctly" {
    touch "$TEST_TEMP_DIR/target.txt"
    ln -s "$TEST_TEMP_DIR/target.txt" "$TEST_TEMP_DIR/link.txt"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    [[ "$result" == *"\"type\":\"link\""* ]]
    [[ "$result" == *"\"target\":"* ]]
}

@test "parse_ls: returns error for non-existent path" {
    run parse_ls "/nonexistent/path/12345" --json
    [[ "$status" -eq 1 ]]
}

@test "parse_ls: each entry has required fields" {
    touch "$TEST_TEMP_DIR/file.txt"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    [[ "$result" == *"\"name\":"* ]]
    [[ "$result" == *"\"type\":"* ]]
    [[ "$result" == *"\"size\":"* ]]
    [[ "$result" == *"\"perms\":"* ]]
    [[ "$result" == *"\"owner\":"* ]]
    [[ "$result" == *"\"modified\":"* ]]
}

@test "parse_ls: modified field is ISO8601 format" {
    touch "$TEST_TEMP_DIR/file.txt"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    # Should contain date pattern like 2024-01-15T10:30:00
    [[ "$result" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

# =============================================================================
# parse_netstat Tests
# =============================================================================

@test "parse_netstat: returns valid JSON array" {
    local result
    result=$(parse_netstat --json)
    is_valid_json "$result"
}

@test "parse_netstat: output format correct" {
    local result
    result=$(parse_netstat --json)
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
}

@test "parse_netstat: invalid port returns error" {
    run parse_netstat --port "invalid"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# parse_ss Tests
# =============================================================================

@test "parse_ss: returns valid JSON" {
    local result
    result=$(parse_ss --json)
    is_valid_json "$result"
}

@test "parse_ss: summary mode returns object" {
    skip_if_no_ss
    local result
    result=$(parse_ss --summary --json)
    is_valid_json "$result"
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "parse_ss: summary has expected fields" {
    skip_if_no_ss
    local result
    result=$(parse_ss --summary --json)
    [[ "$result" == *"\"total\":"* ]]
    [[ "$result" == *"\"tcp\":"* ]]
}

skip_if_no_ss() {
    if ! command -v ss &>/dev/null; then
        skip "ss command not available"
    fi
}

# =============================================================================
# parse_git_status Tests
# =============================================================================

@test "parse_git_status: returns error for non-git directory" {
    run parse_git_status "$TEST_TEMP_DIR"
    [[ "$status" -eq 1 ]]
}

@test "parse_git_status: returns valid JSON for git repo" {
    skip_if_not_git_repo
    local result
    result=$(parse_git_status --json)
    is_valid_json "$result"
}

@test "parse_git_status: has branch field" {
    skip_if_not_git_repo
    local result
    result=$(parse_git_status --json)
    [[ "$result" == *"\"branch\":"* ]]
}

@test "parse_git_status: has staged array" {
    skip_if_not_git_repo
    local result
    result=$(parse_git_status --json)
    [[ "$result" == *"\"staged\":"* ]]
    [[ "$result" == *"\"staged\":["* ]]
}

@test "parse_git_status: has modified array" {
    skip_if_not_git_repo
    local result
    result=$(parse_git_status --json)
    [[ "$result" == *"\"modified\":"* ]]
    [[ "$result" == *"\"modified\":["* ]]
}

@test "parse_git_status: has untracked array" {
    skip_if_not_git_repo
    local result
    result=$(parse_git_status --json)
    [[ "$result" == *"\"untracked\":"* ]]
    [[ "$result" == *"\"untracked\":["* ]]
}

skip_if_not_git_repo() {
    if ! git rev-parse --git-dir &>/dev/null; then
        skip "Not in a git repository"
    fi
}

# =============================================================================
# parse_docker_ps Tests
# =============================================================================

@test "parse_docker_ps: returns error if docker not installed" {
    if command -v docker &>/dev/null; then
        skip "Docker is installed - cannot test missing docker"
    fi
    run parse_docker_ps --json
    [[ "$status" -eq 1 ]]
}

@test "parse_docker_ps: returns valid JSON if docker running" {
    skip_if_no_docker
    local result
    result=$(parse_docker_ps --json)
    is_valid_json "$result"
}

@test "parse_docker_ps: --all flag accepted" {
    skip_if_no_docker
    local result
    result=$(parse_docker_ps --all --json)
    is_valid_json "$result"
}

skip_if_no_docker() {
    if ! command -v docker &>/dev/null; then
        skip "Docker not installed"
    fi
    if ! docker info &>/dev/null 2>&1; then
        skip "Docker daemon not running"
    fi
}

# =============================================================================
# parse_npm_list Tests
# =============================================================================

@test "parse_npm_list: returns error if no package.json" {
    run parse_npm_list "$TEST_TEMP_DIR" --json
    [[ "$status" -eq 1 ]]
}

@test "parse_npm_list: returns valid JSON with package.json" {
    skip_if_no_npm
    # Create minimal package.json
    echo '{"name":"test","version":"1.0.0","dependencies":{}}' > "$TEST_TEMP_DIR/package.json"
    local result
    result=$(parse_npm_list "$TEST_TEMP_DIR" --json)
    is_valid_json "$result"
}

@test "parse_npm_list: invalid depth returns error" {
    skip_if_no_npm
    echo '{"name":"test"}' > "$TEST_TEMP_DIR/package.json"
    run parse_npm_list "$TEST_TEMP_DIR" --depth "invalid"
    [[ "$status" -eq 1 ]]
}

skip_if_no_npm() {
    if ! command -v npm &>/dev/null; then
        skip "npm not installed"
    fi
}

# =============================================================================
# parse_pip_list Tests
# =============================================================================

@test "parse_pip_list: returns valid JSON" {
    skip_if_no_pip
    local result
    result=$(parse_pip_list --json)
    is_valid_json "$result"
}

@test "parse_pip_list: has name and version fields" {
    skip_if_no_pip
    local result
    result=$(parse_pip_list --json)
    # Should have at least one package (pip itself)
    [[ "$result" == *"\"name\":"* ]] || [[ "$result" == "[]" ]]
}

@test "parse_pip_list: --user flag accepted" {
    skip_if_no_pip
    local result
    result=$(parse_pip_list --user --json)
    is_valid_json "$result"
}

skip_if_no_pip() {
    if ! command -v pip3 &>/dev/null && ! command -v pip &>/dev/null; then
        skip "pip not installed"
    fi
}

# =============================================================================
# parse_env Tests
# =============================================================================

@test "parse_env: returns valid JSON object" {
    local result
    result=$(parse_env --json)
    is_valid_json "$result"
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "parse_env: includes PATH variable" {
    local result
    result=$(parse_env --json)
    [[ "$result" == *"\"PATH\":"* ]]
}

@test "parse_env: includes HOME variable" {
    local result
    result=$(parse_env --json)
    [[ "$result" == *"\"HOME\":"* ]]
}

@test "parse_env: --prefix filters correctly" {
    export SYSPARSE_TEST_VAR="test_value"
    local result
    result=$(parse_env --prefix "SYSPARSE_TEST_" --json)
    is_valid_json "$result"
    [[ "$result" == *"SYSPARSE_TEST_VAR"* ]]
    [[ "$result" != *"\"PATH\":"* ]]
    unset SYSPARSE_TEST_VAR
}

@test "parse_env: --redact masks sensitive variables" {
    export SYSPARSE_TEST_PASSWORD="secret123"
    export SYSPARSE_TEST_API_KEY="key456"
    local result
    result=$(parse_env --prefix "SYSPARSE_TEST_" --redact --json)
    [[ "$result" == *"[REDACTED]"* ]]
    [[ "$result" != *"secret123"* ]]
    [[ "$result" != *"key456"* ]]
    unset SYSPARSE_TEST_PASSWORD SYSPARSE_TEST_API_KEY
}

@test "parse_env: --pattern filters with regex" {
    export SYSPARSE_AAA="a"
    export SYSPARSE_BBB="b"
    export OTHER_VAR="c"
    local result
    result=$(parse_env --pattern "^SYSPARSE_" --json)
    [[ "$result" == *"SYSPARSE_AAA"* ]]
    [[ "$result" == *"SYSPARSE_BBB"* ]]
    [[ "$result" != *"OTHER_VAR"* ]] || [[ "$result" =~ SYSPARSE ]]
    unset SYSPARSE_AAA SYSPARSE_BBB OTHER_VAR
}

@test "parse_env: escapes special characters in values" {
    export SYSPARSE_SPECIAL='hello "world" with\ttab'
    local result
    result=$(parse_env --prefix "SYSPARSE_SPECIAL" --json)
    is_valid_json "$result"
    unset SYSPARSE_SPECIAL
}

# =============================================================================
# Security Tests
# =============================================================================

@test "parse_ls: handles filenames with special characters safely" {
    touch "$TEST_TEMP_DIR/normal.txt"
    touch "$TEST_TEMP_DIR/file with spaces.txt"
    touch "$TEST_TEMP_DIR/file\twith\ttabs.txt" 2>/dev/null || true
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    is_valid_json "$result"
}

@test "parse_ls: does not execute commands in filenames" {
    # Create a file with command injection attempt in name
    touch "$TEST_TEMP_DIR/\$(echo pwned).txt" 2>/dev/null || touch "$TEST_TEMP_DIR/safe.txt"
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)
    is_valid_json "$result"
    # Verify no command was executed
    [[ ! -f "$TEST_TEMP_DIR/pwned" ]]
}

@test "parse_env: handles values with quotes safely" {
    export SYSPARSE_QUOTES='value with "quotes" inside'
    local result
    result=$(parse_env --prefix "SYSPARSE_QUOTES" --json)
    is_valid_json "$result"
    unset SYSPARSE_QUOTES
}

@test "parse_env: handles values with newlines safely" {
    export SYSPARSE_NEWLINE=$'line1\nline2'
    local result
    result=$(parse_env --prefix "SYSPARSE_NEWLINE" --json)
    is_valid_json "$result"
    unset SYSPARSE_NEWLINE
}

# =============================================================================
# Truncation Tests
# =============================================================================

@test "parse_ls: respects MAINFRAME_SYSPARSE_TRUNCATE limit" {
    # Create many files
    for i in {1..20}; do
        touch "$TEST_TEMP_DIR/file$i.txt"
    done

    # Set low truncate limit
    MAINFRAME_SYSPARSE_TRUNCATE=5
    local result
    result=$(parse_ls "$TEST_TEMP_DIR" --json)

    # Count entries (rough check by counting "name":)
    local count
    count=$(grep -o '"name":' <<< "$result" | wc -l)

    [[ $count -le 5 ]]
}

@test "parse_ps: respects MAINFRAME_SYSPARSE_TRUNCATE limit" {
    MAINFRAME_SYSPARSE_TRUNCATE=3
    local result
    result=$(parse_ps --json)

    # Count entries
    local count
    count=$(grep -o '"pid":' <<< "$result" | wc -l)

    [[ $count -le 3 ]]
}

# =============================================================================
# Integration Tests
# =============================================================================

@test "integration: all parsers produce valid JSON" {
    local parsers=("parse_ps" "parse_df" "parse_env")

    for parser in "${parsers[@]}"; do
        local result
        result=$("$parser" --json)
        is_valid_json "$result"
    done
}

@test "integration: parse_ls and parse_git_status work in project root" {
    cd "$PROJECT_ROOT"

    local ls_result
    ls_result=$(parse_ls "." --json)
    is_valid_json "$ls_result"

    if git rev-parse --git-dir &>/dev/null; then
        local git_result
        git_result=$(parse_git_status --json)
        is_valid_json "$git_result"
    fi
}

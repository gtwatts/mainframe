#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/common.bats - Core Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/common.sh
#              Core shared library including logging, error handling,
#              validation, file utilities, and lazy loading
# Test Count: 80+ test cases
# Categories: constants, logging, error handling, output formatting,
#             validation, string utilities, file utilities, input,
#             version comparison, config loading, lazy loading
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Reset log level to default for consistent tests
    BASHER_LOG_LEVEL=1

    # Source the library (minimal profile for faster tests)
    MAINFRAME_LIBS="core" source "$MAINFRAME_ROOT/lib/common.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
    unset BASHER_LOG_FILE
    unset MAINFRAME_DEFAULT_BUNDLE
    unset MAINFRAME_PROFILE
    unset MAINFRAME_ROOT
}

# =============================================================================
# CATEGORY 1: CONSTANTS
# =============================================================================

@test "MAINFRAME_VERSION: is set and follows semver" {
    [[ -n "$MAINFRAME_VERSION" ]]
    [[ "$MAINFRAME_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "MAINFRAME_NAME: is set to mainframe" {
    [[ "$MAINFRAME_NAME" == "mainframe" ]]
}

@test "EXIT_SUCCESS: is 0" {
    [[ "$EXIT_SUCCESS" -eq 0 ]]
}

@test "EXIT_FAILURE: is 1" {
    [[ "$EXIT_FAILURE" -eq 1 ]]
}

@test "EXIT_USAGE: is 64 (BSD convention)" {
    [[ "$EXIT_USAGE" -eq 64 ]]
}

@test "EXIT_NOINPUT: is 66" {
    [[ "$EXIT_NOINPUT" -eq 66 ]]
}

@test "EXIT_UNAVAILABLE: is 69" {
    [[ "$EXIT_UNAVAILABLE" -eq 69 ]]
}

@test "EXIT_SOFTWARE: is 70" {
    [[ "$EXIT_SOFTWARE" -eq 70 ]]
}

@test "EXIT_NOPERM: is 77" {
    [[ "$EXIT_NOPERM" -eq 77 ]]
}

@test "EXIT_CONFIG: is 78" {
    [[ "$EXIT_CONFIG" -eq 78 ]]
}

# =============================================================================
# CATEGORY 2: LOG LEVELS
# =============================================================================

@test "LOG_LEVEL_DEBUG: is 0" {
    [[ "$LOG_LEVEL_DEBUG" -eq 0 ]]
}

@test "LOG_LEVEL_INFO: is 1" {
    [[ "$LOG_LEVEL_INFO" -eq 1 ]]
}

@test "LOG_LEVEL_WARN: is 2" {
    [[ "$LOG_LEVEL_WARN" -eq 2 ]]
}

@test "LOG_LEVEL_ERROR: is 3" {
    [[ "$LOG_LEVEL_ERROR" -eq 3 ]]
}

@test "LOG_LEVEL_FATAL: is 4" {
    [[ "$LOG_LEVEL_FATAL" -eq 4 ]]
}

# =============================================================================
# CATEGORY 3: LOGGING FUNCTIONS
# =============================================================================

@test "log_debug: outputs to stderr at debug level" {
    BASHER_LOG_LEVEL=0
    result=$(log_debug "test message" 2>&1)
    [[ "$result" =~ "DEBUG" ]]
    [[ "$result" =~ "test message" ]]
}

@test "log_debug: suppressed at info level" {
    BASHER_LOG_LEVEL=1
    result=$(log_debug "test message" 2>&1)
    [[ -z "$result" ]]
}

@test "log_info: outputs to stderr" {
    BASHER_LOG_LEVEL=1
    result=$(log_info "info message" 2>&1)
    [[ "$result" =~ "INFO" ]]
    [[ "$result" =~ "info message" ]]
}

@test "log_warn: outputs to stderr" {
    result=$(log_warn "warning message" 2>&1)
    [[ "$result" =~ "WARN" ]]
    [[ "$result" =~ "warning message" ]]
}

@test "log_error: outputs to stderr" {
    result=$(log_error "error message" 2>&1)
    [[ "$result" =~ "ERROR" ]]
    [[ "$result" =~ "error message" ]]
}

@test "log_fatal: outputs to stderr" {
    result=$(log_fatal "fatal message" 2>&1)
    [[ "$result" =~ "FATAL" ]]
    [[ "$result" =~ "fatal message" ]]
}

@test "logging: includes timestamp" {
    result=$(log_info "timestamped" 2>&1)
    [[ "$result" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]
    [[ "$result" =~ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "logging: writes to file when BASHER_LOG_FILE is set" {
    export BASHER_LOG_FILE="$TEST_TMPDIR/test.log"
    log_info "file log test"
    [[ -f "$BASHER_LOG_FILE" ]]
    grep -q "file log test" "$BASHER_LOG_FILE"
}

@test "debug: is alias for log_debug" {
    BASHER_LOG_LEVEL=0
    result=$(debug "alias test" 2>&1)
    [[ "$result" =~ "DEBUG" ]]
}

@test "info: is alias for log_info" {
    result=$(info "alias test" 2>&1)
    [[ "$result" =~ "INFO" ]]
}

@test "warn: is alias for log_warn" {
    result=$(warn "alias test" 2>&1)
    [[ "$result" =~ "WARN" ]]
}

@test "error: is alias for log_error" {
    result=$(error "alias test" 2>&1)
    [[ "$result" =~ "ERROR" ]]
}

# =============================================================================
# CATEGORY 4: CENTRALIZED INTERNAL LOGGING
# =============================================================================

@test "_mainframe_log: logs with module prefix" {
    result=$(_mainframe_log "test_module" "info" "test message" 2>&1)
    [[ "$result" =~ "[test_module]" ]]
    [[ "$result" =~ "test message" ]]
}

@test "_mainframe_log: supports all log levels" {
    BASHER_LOG_LEVEL=0
    for level in debug info warn error; do
        result=$(_mainframe_log "mod" "$level" "msg" 2>&1)
        [[ -n "$result" ]]
    done
}

# =============================================================================
# CATEGORY 5: ERROR HANDLING
# =============================================================================

@test "die: exits with provided code" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; die 42 "test error" 2>/dev/null'
    [[ "$status" -eq 42 ]]
}

@test "die: logs fatal message" {
    result=$(bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; die 1 "fatal error" 2>&1; exit 0' 2>&1 || true)
    [[ "$result" =~ "FATAL" ]] || [[ "$result" =~ "fatal error" ]]
}

@test "die_usage: exits with EXIT_USAGE (64)" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; die_usage "bad args" 2>/dev/null'
    [[ "$status" -eq 64 ]]
}

@test "assert: passes for true condition (multi-arg form)" {
    assert test -d "$TEST_TMPDIR"
    [[ $? -eq 0 ]]
}

@test "assert: fails for false condition" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; assert test -f "/nonexistent/file" 2>/dev/null'
    [[ "$status" -eq 70 ]]  # EXIT_SOFTWARE
}

@test "assert: supports legacy two-arg form" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; assert "test -d /tmp" "tmp should exist"'
    [[ "$status" -eq 0 ]]
}

@test "on_exit: registers cleanup function" {
    run bash -c '
        source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null
        my_cleanup() { echo "cleanup called"; }
        on_exit my_cleanup
        exit 0
    '
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "cleanup called" ]]
}

# =============================================================================
# CATEGORY 6: OUTPUT FORMATTING
# =============================================================================

@test "header: outputs formatted header" {
    result=$(header "Test Header")
    [[ "$result" =~ "Test Header" ]]
    [[ "$result" =~ "=" ]]
}

@test "header: respects custom width" {
    result=$(header "Test" 40)
    # Should contain header text
    [[ "$result" =~ "Test" ]]
}

@test "subheader: outputs formatted subheader" {
    result=$(subheader "Sub Header")
    [[ "$result" =~ "Sub Header" ]]
    [[ "$result" =~ ">>>" ]]
}

@test "success: outputs OK prefix" {
    result=$(success "Success message")
    [[ "$result" =~ "[OK]" ]]
    [[ "$result" =~ "Success message" ]]
}

@test "failure: outputs FAIL prefix" {
    result=$(failure "Failure message" 2>&1)
    [[ "$result" =~ "[FAIL]" ]]
    [[ "$result" =~ "Failure message" ]]
}

@test "table_row: formats printf-style row" {
    result=$(table_row "%-10s %5d" "Name" 42)
    [[ "$result" =~ "Name" ]]
    [[ "$result" =~ "42" ]]
}

# =============================================================================
# CATEGORY 7: VALIDATION FUNCTIONS
# =============================================================================

@test "command_exists: returns true for existing command" {
    command_exists bash
    [[ $? -eq 0 ]]
}

@test "command_exists: returns false for non-existing command" {
    run command_exists nonexistent_command_xyz
    [[ "$status" -eq 1 ]]
}

@test "require_command: passes for existing command" {
    require_command bash
    [[ $? -eq 0 ]]
}

@test "require_command: fails for missing command" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; require_command nonexistent_xyz 2>/dev/null'
    [[ "$status" -eq 69 ]]  # EXIT_UNAVAILABLE
}

@test "require_commands: passes for all existing commands" {
    require_commands bash ls cat
    [[ $? -eq 0 ]]
}

@test "require_file: passes for existing readable file" {
    echo "test" > "$TEST_TMPDIR/testfile"
    require_file "$TEST_TMPDIR/testfile"
    [[ $? -eq 0 ]]
}

@test "require_file: fails for missing file" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; require_file "/nonexistent/file" 2>/dev/null'
    [[ "$status" -eq 66 ]]  # EXIT_NOINPUT
}

@test "require_dir: passes for existing directory" {
    require_dir "$TEST_TMPDIR"
    [[ $? -eq 0 ]]
}

@test "require_dir: fails for missing directory" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/common.sh" 2>/dev/null; require_dir "/nonexistent/dir" 2>/dev/null'
    [[ "$status" -eq 66 ]]  # EXIT_NOINPUT
}

@test "is_valid_json: returns true for valid JSON object" {
    # Only test if jq is available
    if command -v jq &>/dev/null; then
        is_valid_json '{"key":"value"}'
        [[ $? -eq 0 ]]
    else
        skip "jq not available"
    fi
}

@test "is_valid_json: returns true for valid JSON array" {
    if command -v jq &>/dev/null; then
        is_valid_json '[1,2,3]'
        [[ $? -eq 0 ]]
    else
        skip "jq not available"
    fi
}

@test "is_valid_json: returns false for invalid JSON" {
    if command -v jq &>/dev/null; then
        run is_valid_json '{invalid}'
        [[ "$status" -eq 1 ]]
    else
        skip "jq not available"
    fi
}

@test "is_valid_email: accepts valid email" {
    is_valid_email "user@example.com"
    [[ $? -eq 0 ]]
}

@test "is_valid_email: accepts email with subdomain" {
    is_valid_email "user@mail.example.com"
    [[ $? -eq 0 ]]
}

@test "is_valid_email: rejects email without @" {
    run is_valid_email "userexample.com"
    [[ "$status" -eq 1 ]]
}

@test "is_valid_email: rejects email without domain" {
    run is_valid_email "user@"
    [[ "$status" -eq 1 ]]
}

@test "is_valid_url: accepts http URL" {
    is_valid_url "http://example.com"
    [[ $? -eq 0 ]]
}

@test "is_valid_url: accepts https URL" {
    is_valid_url "https://example.com/path?query=1"
    [[ $? -eq 0 ]]
}

@test "is_valid_url: rejects non-http URL" {
    run is_valid_url "ftp://example.com"
    [[ "$status" -eq 1 ]]
}

@test "is_valid_url: rejects plain hostname" {
    run is_valid_url "example.com"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 8: FILE UTILITIES
# =============================================================================

@test "temp_file: creates temporary file" {
    local tmpfile
    tmpfile=$(temp_file "test")
    [[ -f "$tmpfile" ]]
    [[ "$tmpfile" =~ "test" ]]
}

@test "temp_file: registers file for cleanup" {
    local tmpfile_path="$TEST_TMPDIR/temp_file_path"
    local tmpfile
    temp_file "cleanup_test" > "$tmpfile_path"
    tmpfile=$(<"$tmpfile_path")
    # File should be tracked in _mainframe_cleanup_files
    [[ " ${_mainframe_cleanup_files[*]} " =~ " $tmpfile " ]]
}

@test "temp_dir: creates temporary directory" {
    local tmpdir
    tmpdir=$(temp_dir "testdir")
    [[ -d "$tmpdir" ]]
    [[ "$tmpdir" =~ "testdir" ]]
}

@test "temp_dir: registers directory for cleanup" {
    local tmpdir_path="$TEST_TMPDIR/temp_dir_path"
    local tmpdir
    temp_dir "cleanup_test" > "$tmpdir_path"
    tmpdir=$(<"$tmpdir_path")
    # Directory should be tracked in _mainframe_cleanup_dirs
    [[ " ${_mainframe_cleanup_dirs[*]} " =~ " $tmpdir " ]]
}

@test "abs_path: resolves relative path for directory" {
    mkdir -p "$TEST_TMPDIR/subdir"
    result=$(cd "$TEST_TMPDIR" && abs_path "subdir")
    [[ "$result" == "$TEST_TMPDIR/subdir" ]]
}

@test "abs_path: resolves relative path for file" {
    touch "$TEST_TMPDIR/testfile"
    result=$(cd "$TEST_TMPDIR" && abs_path "testfile")
    [[ "$result" == "$TEST_TMPDIR/testfile" ]]
}

@test "abs_path: handles non-existent path" {
    result=$(abs_path "/nonexistent/path")
    [[ "$result" == "/nonexistent/path" ]]
}

@test "file_ext: extracts file extension" {
    result=$(file_ext "document.pdf")
    [[ "$result" == "pdf" ]]
}

@test "file_ext: handles multiple dots" {
    result=$(file_ext "archive.tar.gz")
    [[ "$result" == "gz" ]]
}

@test "file_ext: returns empty for no extension" {
    result="$(file_ext "Makefile" || true)"
    [[ -z "$result" ]]
}

@test "file_name: extracts filename without extension" {
    result=$(file_name "/path/to/document.pdf")
    [[ "$result" == "document" ]]
}

@test "file_name: handles path with multiple dots" {
    result=$(file_name "/path/to/archive.tar.gz")
    [[ "$result" == "archive.tar" ]]
}

@test "file_name: handles filename without extension" {
    result=$(file_name "/path/to/Makefile")
    [[ "$result" == "Makefile" ]]
}

# =============================================================================
# CATEGORY 9: VERSION COMPARISON
# =============================================================================

@test "version_compare: returns 0 for equal versions" {
    version_compare "1.2.3" "1.2.3"
    [[ $? -eq 0 ]]
}

@test "version_compare: returns 1 when v1 > v2" {
    run version_compare "2.0.0" "1.9.9"
    [[ "$status" -eq 1 ]]
}

@test "version_compare: returns 2 when v1 < v2" {
    run version_compare "1.0.0" "2.0.0"
    [[ "$status" -eq 2 ]]
}

@test "version_compare: handles different segment counts" {
    version_compare "1.0" "1.0.0"
    [[ $? -eq 0 ]]
}

@test "version_compare: compares minor versions correctly" {
    run version_compare "1.10.0" "1.9.0"
    [[ "$status" -eq 1 ]]
}

@test "version_at_least: returns true when version meets minimum" {
    run version_at_least "2.0.0" "1.5.0"
    [[ "$status" -eq 0 ]]
}

@test "version_at_least: returns true for equal versions" {
    version_at_least "1.5.0" "1.5.0"
    [[ $? -eq 0 ]]
}

@test "version_at_least: returns false when below minimum" {
    run version_at_least "1.0.0" "1.5.0"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 10: CONFIG FILE LOADING
# =============================================================================

@test "_mainframe_load_config: loads key=value pairs" {
    mkdir -p "$TEST_TMPDIR/.mainframe"
    cat > "$TEST_TMPDIR/.mainframe/config" << 'EOF'
test_key=test_value
another_key=123
EOF
    export HOME="$TEST_TMPDIR"
    unset MAINFRAME_TEST_KEY MAINFRAME_ANOTHER_KEY

    _mainframe_load_config

    [[ "$MAINFRAME_TEST_KEY" == "test_value" ]]
    [[ "$MAINFRAME_ANOTHER_KEY" == "123" ]]
}

@test "_mainframe_load_config: ignores comments" {
    mkdir -p "$TEST_TMPDIR/.mainframe"
    cat > "$TEST_TMPDIR/.mainframe/config" << 'EOF'
# This is a comment
valid_key=valid_value
  # Indented comment
EOF
    export HOME="$TEST_TMPDIR"
    unset MAINFRAME_VALID_KEY

    _mainframe_load_config

    [[ "$MAINFRAME_VALID_KEY" == "valid_value" ]]
}

@test "_mainframe_load_config: trims whitespace" {
    mkdir -p "$TEST_TMPDIR/.mainframe"
    cat > "$TEST_TMPDIR/.mainframe/config" << 'EOF'
  spaced_key  =  spaced_value
EOF
    export HOME="$TEST_TMPDIR"
    unset MAINFRAME_SPACED_KEY

    _mainframe_load_config

    [[ "$MAINFRAME_SPACED_KEY" == "spaced_value" ]]
}

@test "_mainframe_load_config: handles missing config file" {
    export HOME="$TEST_TMPDIR"
    rm -rf "$TEST_TMPDIR/.mainframe"

    # Should not error
    run _mainframe_load_config
    [[ "$status" -eq 0 ]]
}

@test "_mainframe_load_config: does not override explicit environment values" {
    mkdir -p "$TEST_TMPDIR/.mainframe"
    cat > "$TEST_TMPDIR/.mainframe/config" << 'EOF'
root=/tmp/wrong-root
profile=full
EOF
    export HOME="$TEST_TMPDIR"
    export MAINFRAME_ROOT="/tmp/expected-root"
    export MAINFRAME_PROFILE="minimal"

    _mainframe_load_config

    [[ "$MAINFRAME_ROOT" == "/tmp/expected-root" ]]
    [[ "$MAINFRAME_PROFILE" == "minimal" ]]
}

# =============================================================================
# CATEGORY 11: LAZY LOADING ENGINE
# =============================================================================

@test "mainframe_load: loads a specific library" {
    # Clear any previously loaded state
    unset _MAINFRAME_LOADED_LIBS
    declare -gA _MAINFRAME_LOADED_LIBS

    mainframe_load "json"
    [[ $? -eq 0 ]]
    [[ "${_MAINFRAME_LOADED_LIBS[json]}" == "1" ]]
}

@test "mainframe_load: fails for non-existent library" {
    run mainframe_load "nonexistent_library_xyz"
    [[ "$status" -eq 1 ]]
}

@test "mainframe_load: rejects empty library name" {
    run mainframe_load ""
    [[ "$status" -eq 1 ]]
}

@test "mainframe_load: rejects library name with path traversal" {
    run mainframe_load "../etc/passwd"
    [[ "$status" -eq 1 ]]
}

@test "mainframe_load: rejects library name with spaces" {
    run mainframe_load "foo bar"
    [[ "$status" -eq 1 ]]
}

@test "mainframe_loaded: lists loaded libraries" {
    result=$(mainframe_loaded)
    # At minimum, core libraries should be loaded
    [[ "$result" =~ "json" ]] || [[ "$result" =~ "pure-string" ]]
}

@test "mainframe_available: lists available libraries" {
    result=$(mainframe_available)
    # Should contain known libraries
    [[ "$result" =~ "json" ]]
    [[ "$result" =~ "http" ]]
    [[ "$result" =~ "docker" ]]
}

@test "mainframe_bundle: loads agent_minimal bundle" {
    unset _MAINFRAME_LOADED_LIBS
    declare -gA _MAINFRAME_LOADED_LIBS

    run mainframe_bundle "agent_minimal"
    [[ "$status" -eq 0 ]]
}

@test "mainframe_bundle: loads agent_memory bundle" {
    unset _MAINFRAME_LOADED_LIBS
    declare -gA _MAINFRAME_LOADED_LIBS

    mainframe_bundle "agent_memory"
    [[ "$?" -eq 0 ]]
    [[ "${_MAINFRAME_LOADED_LIBS[awm]:-}" == "1" ]]
    [[ "${_MAINFRAME_LOADED_LIBS[awm_storage]:-}" == "1" ]]
    [[ "${_MAINFRAME_LOADED_LIBS[agent_context]:-}" == "1" ]]
}

@test "mainframe_bundle: fails for unknown bundle" {
    run mainframe_bundle "nonexistent_bundle"
    [[ "$status" -eq 1 ]]
}

@test "mainframe_bundle: uses configured default bundle" {
    unset _MAINFRAME_LOADED_LIBS
    declare -gA _MAINFRAME_LOADED_LIBS
    export MAINFRAME_DEFAULT_BUNDLE="data"

    mainframe_bundle
    [[ $? -eq 0 ]]
    [[ "${_MAINFRAME_LOADED_LIBS[csv]:-}" == "1" ]]
}

@test "mainframe_bundles: lists available bundles" {
    result=$(mainframe_bundles)
    [[ "$result" =~ "agent_minimal" ]]
    [[ "$result" =~ "agent_memory" ]]
    [[ "$result" =~ "agent_runtime" ]]
    [[ "$result" =~ "agent_full" ]]
    [[ "$result" =~ "data" ]]
    [[ "$result" =~ "net" ]]
}

@test "_mainframe_load_selected: supports bundle syntax" {
    unset _MAINFRAME_LOADED_LIBS
    declare -gA _MAINFRAME_LOADED_LIBS

    _mainframe_load_selected "core,bundle:agent_memory"

    [[ "${_MAINFRAME_LOADED_LIBS[json]:-}" == "1" ]]
    [[ "${_MAINFRAME_LOADED_LIBS[awm]:-}" == "1" ]]
    [[ "${_MAINFRAME_LOADED_LIBS[awm_storage]:-}" == "1" ]]
}

@test "_mainframe_load_tier: loads core tier" {
    unset _MAINFRAME_LOADED_LIBS
    declare -gA _MAINFRAME_LOADED_LIBS

    _mainframe_load_tier "core"

    # Core tier should include json
    [[ "${_MAINFRAME_LOADED_LIBS[json]}" == "1" ]]
}

# =============================================================================
# CATEGORY 12: COLOR DEFINITIONS
# =============================================================================

@test "CLR_RESET: is defined" {
    [[ -n "${CLR_RESET+x}" ]]  # Check if variable exists (may be empty in NO_COLOR mode)
}

@test "CLR_RED: is defined" {
    [[ -n "${CLR_RED+x}" ]]
}

@test "CLR_GREEN: is defined" {
    [[ -n "${CLR_GREEN+x}" ]]
}

@test "CLR_YELLOW: is defined" {
    [[ -n "${CLR_YELLOW+x}" ]]
}

@test "CLR_BLUE: is defined" {
    [[ -n "${CLR_BLUE+x}" ]]
}

# =============================================================================
# CATEGORY 13: EXPORTS
# =============================================================================

@test "BASHER_COMMON_EXPORTS: is defined and non-empty" {
    [[ -n "${BASHER_COMMON_EXPORTS[*]}" ]]
}

@test "BASHER_COMMON_EXPORTS: contains logging functions" {
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "log_info" ]]
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "log_error" ]]
}

@test "BASHER_COMMON_EXPORTS: contains error handling functions" {
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "die" ]]
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "assert" ]]
}

@test "BASHER_COMMON_EXPORTS: contains validation functions" {
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "command_exists" ]]
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "require_file" ]]
}

@test "BASHER_COMMON_EXPORTS: contains file utility functions" {
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "temp_file" ]]
    [[ "${BASHER_COMMON_EXPORTS[*]}" =~ "abs_path" ]]
}

# =============================================================================
# CATEGORY 14: EDGE CASES
# =============================================================================

@test "logging: handles empty message" {
    result=$(log_info "" 2>&1)
    [[ "$result" =~ "INFO" ]]
}

@test "logging: handles message with special characters" {
    result=$(log_info 'Test $VAR and "quotes" and `backticks`' 2>&1)
    [[ "$result" =~ 'Test $VAR' ]]
}

@test "logging: handles multiline message" {
    result=$(log_info $'line1\nline2' 2>&1)
    [[ "$result" =~ "line1" ]]
}

@test "version_compare: handles single digit versions" {
    run version_compare "1" "2"
    [[ "$status" -eq 2 ]]
}

@test "version_compare: handles large version numbers" {
    run version_compare "100.200.300" "100.200.299"
    [[ "$status" -eq 1 ]]
}

@test "file_ext: handles hidden files" {
    result=$(file_ext ".bashrc")
    [[ "$result" == "bashrc" ]] || [[ -z "$result" ]]
}

@test "file_ext: handles hidden file with extension" {
    result=$(file_ext ".config.json")
    [[ "$result" == "json" ]]
}

@test "is_valid_email: handles plus addressing" {
    is_valid_email "user+tag@example.com"
    [[ $? -eq 0 ]]
}

@test "is_valid_email: handles dots in local part" {
    is_valid_email "first.last@example.com"
    [[ $? -eq 0 ]]
}

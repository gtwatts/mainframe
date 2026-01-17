#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/test_env.bats - Environment Library Tests
# =============================================================================
# Run with: bats tests/unit/test_env.bats
# =============================================================================

setup() {
    # Get the directory containing this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

    # Source the library
    source "$PROJECT_ROOT/lib/env.sh"

    # Create temp directory for tests
    TEST_TMPDIR=$(mktemp -d)

    # Save original PATH for restoration
    ORIGINAL_PATH="$PATH"

    # Create test directories for PATH tests
    mkdir -p "$TEST_TMPDIR/bin1"
    mkdir -p "$TEST_TMPDIR/bin2"
    mkdir -p "$TEST_TMPDIR/bin3"
}

teardown() {
    # Restore original PATH
    export PATH="$ORIGINAL_PATH"

    # Clean up temp directory
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"

    # Unset test variables
    unset TEST_VAR TEST_VAR2 MY_APP_DEBUG MY_INT_VAR MY_BOOL_VAR
}

# =============================================================================
# SHELL DETECTION
# =============================================================================

@test "env_detect_shell: detects bash" {
    result=$(env_detect_shell)
    [[ "$result" == "bash" ]]
}

@test "env_config_file: returns bashrc for bash" {
    result=$(env_config_file "bash")
    [[ "$result" == "$HOME/.bashrc" ]] || [[ "$result" == "$HOME/.bash_profile" ]]
}

@test "env_config_file: returns zshrc for zsh" {
    result=$(env_config_file "zsh")
    [[ "$result" == "$HOME/.zshrc" ]]
}

@test "env_config_file: returns fish config for fish" {
    result=$(env_config_file "fish")
    [[ "$result" == "$HOME/.config/fish/config.fish" ]]
}

@test "env_config_file: returns profile for sh" {
    result=$(env_config_file "sh")
    [[ "$result" == "$HOME/.profile" ]]
}

# =============================================================================
# VARIABLE MANAGEMENT
# =============================================================================

@test "env_set: sets variable in current session" {
    env_set "TEST_VAR" "hello"
    [[ "$TEST_VAR" == "hello" ]]
}

@test "env_set: rejects invalid variable names" {
    run env_set "123invalid" "value"
    [[ "$status" -eq 1 ]]
}

@test "env_set: rejects variable names with special chars" {
    run env_set "my-var" "value"
    [[ "$status" -eq 1 ]]

    run env_set "my.var" "value"
    [[ "$status" -eq 1 ]]
}

@test "env_set: accepts underscores in variable names" {
    env_set "MY_TEST_VAR" "value"
    [[ "$MY_TEST_VAR" == "value" ]]
    unset MY_TEST_VAR
}

@test "env_get: returns variable value" {
    export TEST_VAR="world"
    result=$(env_get "TEST_VAR")
    [[ "$result" == "world" ]]
}

@test "env_get: returns default when variable not set" {
    unset NONEXISTENT_VAR
    result=$(env_get "NONEXISTENT_VAR" "default_value")
    [[ "$result" == "default_value" ]]
}

@test "env_get: returns empty when no default and not set" {
    unset NONEXISTENT_VAR
    result=$(env_get "NONEXISTENT_VAR")
    [[ -z "$result" ]]
}

@test "env_unset: removes variable" {
    export TEST_VAR="to_be_removed"
    env_unset "TEST_VAR"
    [[ -z "${TEST_VAR:-}" ]]
}

@test "env_unset: rejects invalid variable names" {
    run env_unset "invalid-name"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# PATH MANAGEMENT
# =============================================================================

@test "env_path_list: lists PATH entries one per line" {
    local count
    count=$(env_path_list | wc -l)
    [[ $count -gt 0 ]]
}

@test "env_path_has: returns true for existing path" {
    # /usr/bin should typically be in PATH
    env_path_has "/usr/bin"
}

@test "env_path_has: returns false for non-existing path" {
    ! env_path_has "/definitely/not/in/path/12345"
}

@test "env_path_prepend: adds to beginning of PATH" {
    env_path_prepend "$TEST_TMPDIR/bin1"
    [[ "$PATH" == "$TEST_TMPDIR/bin1:"* ]]
}

@test "env_path_prepend: does not add duplicate" {
    env_path_prepend "$TEST_TMPDIR/bin1"
    local count_before
    count_before=$(echo "$PATH" | tr ':' '\n' | grep -c "$TEST_TMPDIR/bin1" || true)

    env_path_prepend "$TEST_TMPDIR/bin1"
    local count_after
    count_after=$(echo "$PATH" | tr ':' '\n' | grep -c "$TEST_TMPDIR/bin1" || true)

    [[ "$count_before" -eq "$count_after" ]]
}

@test "env_path_prepend: fails for non-existent directory" {
    run env_path_prepend "/nonexistent/directory/12345"
    [[ "$status" -eq 1 ]]
}

@test "env_path_append: adds to end of PATH" {
    env_path_append "$TEST_TMPDIR/bin2"
    [[ "$PATH" == *":$TEST_TMPDIR/bin2" ]]
}

@test "env_path_append: does not add duplicate" {
    env_path_append "$TEST_TMPDIR/bin2"
    local count_before
    count_before=$(echo "$PATH" | tr ':' '\n' | grep -c "$TEST_TMPDIR/bin2" || true)

    env_path_append "$TEST_TMPDIR/bin2"
    local count_after
    count_after=$(echo "$PATH" | tr ':' '\n' | grep -c "$TEST_TMPDIR/bin2" || true)

    [[ "$count_before" -eq "$count_after" ]]
}

@test "env_path_remove: removes path from PATH" {
    env_path_prepend "$TEST_TMPDIR/bin3"
    env_path_has "$TEST_TMPDIR/bin3"

    env_path_remove "$TEST_TMPDIR/bin3"
    ! env_path_has "$TEST_TMPDIR/bin3"
}

@test "env_path_clean: removes duplicates" {
    # Add same path twice forcefully
    export PATH="$TEST_TMPDIR/bin1:$TEST_TMPDIR/bin1:$PATH"
    local count_before
    count_before=$(echo "$PATH" | tr ':' '\n' | grep -c "$TEST_TMPDIR/bin1" || true)
    [[ $count_before -ge 2 ]]

    env_path_clean

    local count_after
    count_after=$(echo "$PATH" | tr ':' '\n' | grep -c "$TEST_TMPDIR/bin1" || true)
    [[ $count_after -eq 1 ]]
}

# =============================================================================
# DOTENV SUPPORT
# =============================================================================

@test "env_load_dotenv: loads simple key=value" {
    cat > "$TEST_TMPDIR/.env" << 'EOF'
MY_VAR=hello
MY_OTHER_VAR=world
EOF

    env_load_dotenv "$TEST_TMPDIR/.env"
    [[ "$MY_VAR" == "hello" ]]
    [[ "$MY_OTHER_VAR" == "world" ]]
    unset MY_VAR MY_OTHER_VAR
}

@test "env_load_dotenv: handles quoted values" {
    cat > "$TEST_TMPDIR/.env" << 'EOF'
QUOTED_VAR="hello world"
SINGLE_QUOTED='single quotes'
EOF

    env_load_dotenv "$TEST_TMPDIR/.env"
    [[ "$QUOTED_VAR" == "hello world" ]]
    [[ "$SINGLE_QUOTED" == "single quotes" ]]
    unset QUOTED_VAR SINGLE_QUOTED
}

@test "env_load_dotenv: skips comments" {
    cat > "$TEST_TMPDIR/.env" << 'EOF'
# This is a comment
REAL_VAR=value
# Another comment
EOF

    env_load_dotenv "$TEST_TMPDIR/.env"
    [[ "$REAL_VAR" == "value" ]]
    unset REAL_VAR
}

@test "env_load_dotenv: skips empty lines" {
    cat > "$TEST_TMPDIR/.env" << 'EOF'

VAR1=one

VAR2=two

EOF

    env_load_dotenv "$TEST_TMPDIR/.env"
    [[ "$VAR1" == "one" ]]
    [[ "$VAR2" == "two" ]]
    unset VAR1 VAR2
}

@test "env_load_dotenv: fails for non-existent file" {
    run env_load_dotenv "$TEST_TMPDIR/nonexistent.env"
    [[ "$status" -eq 1 ]]
}

@test "env_save_dotenv: saves variables to file" {
    export SAVE_VAR1="value1"
    export SAVE_VAR2="value2"

    env_save_dotenv "$TEST_TMPDIR/saved.env" SAVE_VAR1 SAVE_VAR2

    [[ -f "$TEST_TMPDIR/saved.env" ]]
    grep -q "SAVE_VAR1" "$TEST_TMPDIR/saved.env"
    grep -q "SAVE_VAR2" "$TEST_TMPDIR/saved.env"
    unset SAVE_VAR1 SAVE_VAR2
}

@test "env_save_dotenv: quotes values with spaces" {
    export SPACED_VAR="hello world"
    env_save_dotenv "$TEST_TMPDIR/spaced.env" SPACED_VAR

    grep -q 'SPACED_VAR="hello world"' "$TEST_TMPDIR/spaced.env"
    unset SPACED_VAR
}

@test "env_save_dotenv: fails without variables" {
    run env_save_dotenv "$TEST_TMPDIR/empty.env"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# VALIDATION
# =============================================================================

@test "env_is_set: returns true for set variable" {
    export SET_VAR=""
    env_is_set "SET_VAR"
    unset SET_VAR
}

@test "env_is_set: returns false for unset variable" {
    unset UNSET_VAR
    ! env_is_set "UNSET_VAR"
}

@test "env_is_nonempty: returns true for non-empty variable" {
    export NONEMPTY_VAR="value"
    env_is_nonempty "NONEMPTY_VAR"
    unset NONEMPTY_VAR
}

@test "env_is_nonempty: returns false for empty variable" {
    export EMPTY_VAR=""
    ! env_is_nonempty "EMPTY_VAR"
    unset EMPTY_VAR
}

@test "env_is_nonempty: returns false for unset variable" {
    unset UNSET_VAR
    ! env_is_nonempty "UNSET_VAR"
}

@test "env_require: succeeds for set variable" {
    export REQUIRED_VAR="value"
    run env_require "REQUIRED_VAR"
    [[ "$status" -eq 0 ]]
    unset REQUIRED_VAR
}

@test "env_require: fails for unset variable" {
    unset MISSING_VAR
    run env_require "MISSING_VAR"
    [[ "$status" -eq 1 ]]
}

@test "env_require: shows custom message" {
    unset MISSING_VAR
    run env_require "MISSING_VAR" "Custom error message"
    [[ "$output" == "Custom error message" ]]
}

@test "env_require_all: succeeds when all set" {
    export REQ_VAR1="a"
    export REQ_VAR2="b"
    run env_require_all REQ_VAR1 REQ_VAR2
    [[ "$status" -eq 0 ]]
    unset REQ_VAR1 REQ_VAR2
}

@test "env_require_all: fails when any missing" {
    export REQ_VAR1="a"
    unset REQ_VAR2
    run env_require_all REQ_VAR1 REQ_VAR2
    [[ "$status" -eq 1 ]]
    unset REQ_VAR1
}

# =============================================================================
# UTILITIES
# =============================================================================

@test "env_list: lists environment variables" {
    result=$(env_list)
    [[ -n "$result" ]]
}

@test "env_list: filters by pattern" {
    export MY_APP_DEBUG="true"
    result=$(env_list "MY_APP")
    [[ "$result" == *"MY_APP_DEBUG"* ]]
    unset MY_APP_DEBUG
}

@test "env_with: runs command with modified env" {
    result=$(env_with TEST_ENV_VAR=hello printenv TEST_ENV_VAR)
    [[ "$result" == "hello" ]]
}

@test "env_with: does not affect outer scope" {
    env_with TEMP_VAR=temporary true
    [[ -z "${TEMP_VAR:-}" ]]
}

@test "env_copy: copies variable to new name" {
    export SOURCE_VAR="original"
    env_copy SOURCE_VAR DEST_VAR
    [[ "$DEST_VAR" == "original" ]]
    unset SOURCE_VAR DEST_VAR
}

@test "env_copy: fails for unset source" {
    unset SOURCE_VAR
    run env_copy SOURCE_VAR DEST_VAR
    [[ "$status" -eq 1 ]]
}

@test "env_swap: swaps two variables" {
    export SWAP_A="first"
    export SWAP_B="second"
    env_swap SWAP_A SWAP_B
    [[ "$SWAP_A" == "second" ]]
    [[ "$SWAP_B" == "first" ]]
    unset SWAP_A SWAP_B
}

@test "env_get_int: returns integer value" {
    export MY_INT_VAR="42"
    result=$(env_get_int MY_INT_VAR)
    [[ "$result" == "42" ]]
}

@test "env_get_int: returns default for non-integer" {
    export MY_INT_VAR="not_a_number"
    result=$(env_get_int MY_INT_VAR 10)
    [[ "$result" == "10" ]]
}

@test "env_get_int: returns default when not set" {
    unset MY_INT_VAR
    result=$(env_get_int MY_INT_VAR 99)
    [[ "$result" == "99" ]]
}

@test "env_get_bool: returns 0 for true values" {
    export MY_BOOL_VAR="true"
    env_get_bool MY_BOOL_VAR

    export MY_BOOL_VAR="yes"
    env_get_bool MY_BOOL_VAR

    export MY_BOOL_VAR="1"
    env_get_bool MY_BOOL_VAR

    export MY_BOOL_VAR="on"
    env_get_bool MY_BOOL_VAR
}

@test "env_get_bool: returns 1 for false values" {
    export MY_BOOL_VAR="false"
    ! env_get_bool MY_BOOL_VAR

    export MY_BOOL_VAR="no"
    ! env_get_bool MY_BOOL_VAR

    export MY_BOOL_VAR="0"
    ! env_get_bool MY_BOOL_VAR

    export MY_BOOL_VAR="off"
    ! env_get_bool MY_BOOL_VAR
}

@test "env_get_bool: is case insensitive" {
    export MY_BOOL_VAR="TRUE"
    env_get_bool MY_BOOL_VAR

    export MY_BOOL_VAR="False"
    ! env_get_bool MY_BOOL_VAR
}

@test "env_get_array: splits colon-separated values" {
    export MY_ARRAY_VAR="one:two:three"
    declare -a result
    env_get_array MY_ARRAY_VAR result
    [[ "${result[0]}" == "one" ]]
    [[ "${result[1]}" == "two" ]]
    [[ "${result[2]}" == "three" ]]
    [[ "${#result[@]}" -eq 3 ]]
    unset MY_ARRAY_VAR
}

@test "env_set_array: joins array with colons" {
    local -a arr=("a" "b" "c")
    env_set_array MY_ARRAY_VAR "${arr[@]}"
    [[ "$MY_ARRAY_VAR" == "a:b:c" ]]
    unset MY_ARRAY_VAR
}

@test "env_debug: shows set variable" {
    export DEBUG_VAR="test_value"
    result=$(env_debug DEBUG_VAR)
    [[ "$result" == "DEBUG_VAR=test_value" ]]
    unset DEBUG_VAR
}

@test "env_debug: shows empty variable" {
    export DEBUG_VAR=""
    result=$(env_debug DEBUG_VAR)
    [[ "$result" == "DEBUG_VAR= (empty)" ]]
    unset DEBUG_VAR
}

@test "env_debug: shows unset variable" {
    unset DEBUG_VAR
    result=$(env_debug DEBUG_VAR)
    [[ "$result" == "DEBUG_VAR (not set)" ]]
}

@test "env_summary: provides shell information" {
    result=$(env_summary)
    [[ "$result" == *"Shell:"* ]]
    [[ "$result" == *"User:"* ]]
    [[ "$result" == *"Home:"* ]]
    [[ "$result" == *"PATH entries:"* ]]
}

@test "env_backup: creates backup file" {
    env_backup "$TEST_TMPDIR/backup.env"
    [[ -f "$TEST_TMPDIR/backup.env" ]]
}

@test "env_restore: loads from backup" {
    export BACKUP_TEST_VAR="backup_value"
    env_backup "$TEST_TMPDIR/restore.env"
    unset BACKUP_TEST_VAR

    env_restore "$TEST_TMPDIR/restore.env"
    [[ "$BACKUP_TEST_VAR" == "backup_value" ]]
    unset BACKUP_TEST_VAR
}

@test "env_restore: fails for non-existent file" {
    run env_restore "$TEST_TMPDIR/nonexistent.env"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# ENV DIFF
# =============================================================================

@test "env_diff: shows added variables" {
    cat > "$TEST_TMPDIR/diff.env" << 'EOF'
NEW_VAR=new_value
EOF
    unset NEW_VAR
    result=$(env_diff "$TEST_TMPDIR/diff.env")
    [[ "$result" == *"+ NEW_VAR"* ]]
}

@test "env_diff: shows changed variables" {
    export CHANGED_VAR="old_value"
    cat > "$TEST_TMPDIR/diff.env" << 'EOF'
CHANGED_VAR=new_value
EOF
    result=$(env_diff "$TEST_TMPDIR/diff.env")
    [[ "$result" == *"~ CHANGED_VAR"* ]]
    unset CHANGED_VAR
}

# =============================================================================
# EXPAND
# =============================================================================

@test "env_expand: expands variable references" {
    export EXPAND_VAR="expanded"
    result=$(env_expand 'Value is $EXPAND_VAR')
    [[ "$result" == "Value is expanded" ]]
    unset EXPAND_VAR
}

# =============================================================================
# PERSISTENCE TESTS (limited - don't modify real config files)
# =============================================================================

@test "env_persist: writes to temp config file" {
    # Use a custom HOME for this test
    local fake_home="$TEST_TMPDIR/fake_home"
    mkdir -p "$fake_home"
    local original_home="$HOME"
    export HOME="$fake_home"

    env_persist "PERSIST_TEST" "persist_value" "bash"

    # Check the config file was created and contains our export
    [[ -f "$fake_home/.bashrc" ]]
    grep -q "export PERSIST_TEST=" "$fake_home/.bashrc"

    export HOME="$original_home"
}

@test "env_remove_persist: removes from temp config file" {
    # Use a custom HOME for this test
    local fake_home="$TEST_TMPDIR/fake_home2"
    mkdir -p "$fake_home"
    local original_home="$HOME"
    export HOME="$fake_home"

    # First persist
    env_persist "REMOVE_TEST" "some_value" "bash"
    grep -q "export REMOVE_TEST=" "$fake_home/.bashrc"

    # Then remove
    env_remove_persist "REMOVE_TEST" "bash"
    ! grep -q "export REMOVE_TEST=" "$fake_home/.bashrc"

    export HOME="$original_home"
}

@test "env_path_persist_prepend: writes PATH addition to config" {
    local fake_home="$TEST_TMPDIR/fake_home3"
    mkdir -p "$fake_home"
    mkdir -p "$fake_home/test_bin"
    local original_home="$HOME"
    export HOME="$fake_home"

    env_path_persist_prepend "$fake_home/test_bin" "bash"

    [[ -f "$fake_home/.bashrc" ]]
    grep -q "$fake_home/test_bin" "$fake_home/.bashrc"

    export HOME="$original_home"
}

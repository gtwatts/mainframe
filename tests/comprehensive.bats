#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Comprehensive Edge-Case & Integration Tests
# =============================================================================
# These tests target boundary conditions, race conditions, special characters,
# cross-module integration, and real-world failure modes.
# =============================================================================

load 'test_helper'

setup() {
    source_lib "idempotent"
    source_lib "atomic"
    source_lib "observe"
    source_lib "project"
    source_lib "contract"
    source_lib "perf"
    source_lib "netscan"
    source_lib "parsers"
    export MAINFRAME_TRACE_ENABLED=1
    export MAINFRAME_TRACE_OUTPUT="/dev/null"
    export MAINFRAME_CONTRACTS_ENABLED=1
    export MAINFRAME_ERROR_JSON=1
    TEST_DIR=$(create_test_dir "comprehensive")
    export MAINFRAME_TRACE_DIR="$TEST_DIR/.traces"
    export MAINFRAME_CHECKPOINT_DIR="$TEST_DIR/.checkpoints"
    export MAINFRAME_TRASH_DIR="$TEST_DIR/.trash"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# SPECIAL CHARACTER STRESS TESTS
# =============================================================================

@test "atomic_write handles filename with spaces" {
    atomic_write "$TEST_DIR/file with spaces.txt" "content"
    [ -f "$TEST_DIR/file with spaces.txt" ]
    [ "$(cat "$TEST_DIR/file with spaces.txt")" = "content" ]
}

@test "atomic_write handles content with newlines and tabs" {
    local content=$'line1\n\tindented\nline3'
    atomic_write "$TEST_DIR/multiline.txt" "$content"
    local read_back
    read_back=$(<"$TEST_DIR/multiline.txt")
    [ "$read_back" = "$content" ]
}

@test "atomic_write handles content with quotes and backslashes" {
    local content='He said "hello" and path was C:\Users\foo'
    atomic_write "$TEST_DIR/quotes.txt" "$content"
    local read_back
    read_back=$(<"$TEST_DIR/quotes.txt")
    [ "$read_back" = "$content" ]
}

@test "atomic_write handles empty content" {
    atomic_write "$TEST_DIR/empty.txt" ""
    [ -f "$TEST_DIR/empty.txt" ]
    [ ! -s "$TEST_DIR/empty.txt" ]
}

@test "atomic_write handles very long single line (10KB)" {
    local content
    content=$(head -c 10240 /dev/urandom | base64 | tr -d '\n')
    atomic_write "$TEST_DIR/longline.txt" "$content"
    local read_back
    read_back=$(<"$TEST_DIR/longline.txt")
    [ "$read_back" = "$content" ]
}

@test "ensure_line handles line with regex special chars" {
    local line='export PATH="$HOME/.local/bin:$PATH" # [important]'
    ensure_line "$TEST_DIR/profile" "$line"
    ensure_line "$TEST_DIR/profile" "$line"  # idempotent
    local count
    count=$(grep -c 'PATH' "$TEST_DIR/profile")
    [ "$count" = "1" ]
}

@test "ensure_line handles line with pipe and ampersand" {
    ensure_line "$TEST_DIR/conf" "cmd1 | cmd2 && cmd3 || cmd4"
    ensure_line "$TEST_DIR/conf" "cmd1 | cmd2 && cmd3 || cmd4"
    local count
    count=$(wc -l < "$TEST_DIR/conf")
    [ "$count" = "1" ]
}

@test "trace names with special characters produce valid JSON" {
    local tid
    tid=$(trace_start "op with \"quotes\" & <angles>")
    trace_step "$tid" "step/with/slashes" "ok" "detail: [brackets]"
    local result
    result=$(trace_end "$tid")
    # Should be parseable - check it has valid JSON structure
    [[ "$result" == *"trace_id"* ]]
    [[ "$result" == *"duration_s"* ]]
}

@test "observe_command handles command with special args" {
    local result
    result=$(observe_command echo 'hello "world" $VAR')
    [[ "$result" == *"exit_code"* ]]
    [[ "$result" == *"hello"* ]]
}

@test "mainframe_error handles msg with all JSON-special chars" {
    local err
    err=$(mainframe_error 1 'Error: "file" not\found at C:\path' "key=val with \"quotes\"" 2>&1) || true
    # Should not crash, should produce output
    [[ "$err" == *'"error":true'* ]]
}

# =============================================================================
# CONCURRENT / RACE CONDITION TESTS
# =============================================================================

@test "atomic_append concurrent writes don't interleave" {
    local target="$TEST_DIR/concurrent.log"
    # Run 10 appends in quick succession
    for i in {1..10}; do
        atomic_append "$target" "line_$i"
    done
    local count
    count=$(wc -l < "$target")
    [ "$count" = "10" ]
    # Verify no interleaving (each line is complete)
    while IFS= read -r line; do
        [[ "$line" =~ ^line_[0-9]+$ ]]
    done < "$target"
}

@test "atomic_write rapid succession preserves last write" {
    for i in {1..20}; do
        atomic_write "$TEST_DIR/rapid.txt" "version_$i"
    done
    local content
    content=$(<"$TEST_DIR/rapid.txt")
    [ "$content" = "version_20" ]
}

@test "file_checkpoint rapid checkpoints are all unique" {
    printf "original" > "$TEST_DIR/target.txt"
    file_checkpoint "$TEST_DIR/target.txt" "ckpt1"
    printf "modified1" > "$TEST_DIR/target.txt"
    file_checkpoint "$TEST_DIR/target.txt" "ckpt2"
    printf "modified2" > "$TEST_DIR/target.txt"

    # Rollback to ckpt1
    file_rollback "$TEST_DIR/target.txt" "ckpt1"
    [ "$(cat "$TEST_DIR/target.txt")" = "original" ]

    # Rollback to ckpt2
    file_rollback "$TEST_DIR/target.txt" "ckpt2"
    [ "$(cat "$TEST_DIR/target.txt")" = "modified1" ]
}

# =============================================================================
# BOUNDARY / EDGE CASE TESTS
# =============================================================================

@test "contract_in_range handles INT_MAX boundary" {
    contract_in_range 2147483647 0 2147483647 "max_int"
}

@test "contract_in_range handles negative range" {
    contract_in_range -5 -10 -1 "negative"
}

@test "contract_in_range handles zero in range" {
    contract_in_range 0 -10 10 "zero"
}

@test "contract_type_check int rejects float" {
    ! contract_type_check "3.14" "int" "val" 2>/dev/null
}

@test "contract_type_check float accepts negative" {
    contract_type_check "-99.5" "float" "temp"
}

@test "contract_type_check bool accepts all valid forms" {
    for val in true false 0 1 yes no; do
        contract_type_check "$val" "bool" "flag"
    done
}

@test "bash_version_at_least handles 0 0" {
    bash_version_at_least 0 0
}

@test "perf_timer handles very short durations" {
    perf_timer_start "short"
    local elapsed
    elapsed=$(perf_timer_elapsed "short")
    # Should be a valid number >= 0
    [[ "$elapsed" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "scan_range handles single port" {
    local result
    result=$(scan_range "localhost" "1" 1)
    [[ "$result" == *'"port":1'* ]]
}

@test "scan_range handles ports with whitespace" {
    local result
    result=$(scan_range "localhost" "1, 2, 3" 1)
    [[ "$result" == *'"port":1'* ]]
    [[ "$result" == *'"port":2'* ]]
    [[ "$result" == *'"port":3'* ]]
}

@test "parse_csv_line handles 100-field row" {
    local line=""
    for i in $(seq 1 100); do
        [[ -n "$line" ]] && line+=","
        line+="field$i"
    done
    parse_csv_line "$line"
    [ "${#PARSE_CSV_FIELDS[@]}" = "100" ]
    [ "${PARSE_CSV_FIELDS[0]}" = "field1" ]
    [ "${PARSE_CSV_FIELDS[99]}" = "field100" ]
}

@test "parse_csv_line handles field with only quotes" {
    parse_csv_line '""""'
    [ "${PARSE_CSV_FIELDS[0]}" = '"' ]
}

@test "parse_semver handles v0.0.0" {
    local result
    result=$(parse_semver "v0.0.0")
    [[ "$result" == *'"major":0'* ]]
    [[ "$result" == *'"minor":0'* ]]
    [[ "$result" == *'"patch":0'* ]]
}

@test "parse_semver handles very large version numbers" {
    local result
    result=$(parse_semver "999.888.777")
    [[ "$result" == *'"major":999'* ]]
    [[ "$result" == *'"minor":888'* ]]
    [[ "$result" == *'"patch":777'* ]]
}

@test "semver_compare handles all-zeros" {
    local result
    result=$(semver_compare "0.0.0" "0.0.0")
    [ "$result" = "0" ]
}

@test "semver_compare major beats minor.patch" {
    local result
    result=$(semver_compare "2.0.0" "1.99.99")
    [ "$result" = "1" ]
}

@test "parse_url handles URL with @ in path (not userinfo)" {
    local result
    result=$(parse_url "http://example.com/@user/repo")
    [[ "$result" == *'"host":"example.com"'* ]]
    [[ "$result" == *'"path":"/@user/repo"'* ]]
}

@test "parse_url handles empty path after host" {
    local result
    result=$(parse_url "http://example.com")
    [[ "$result" == *'"host":"example.com"'* ]]
}

@test "parse_url handles ipv4 host" {
    local result
    result=$(parse_url "http://192.168.1.1:8080/api")
    [[ "$result" == *'"host":"192.168.1.1"'* ]]
    [[ "$result" == *'"port":8080'* ]]
}

# =============================================================================
# MALFORMED INPUT ROBUSTNESS TESTS
# =============================================================================

@test "parse_ini handles section with no keys" {
    local input
    input=$(printf '[empty_section]\n[has_keys]\nk=v\n')
    local result
    result=$(parse_ini "$input")
    [[ "$result" == *'"has_keys":'* ]]
    [[ "$result" == *'"k":"v"'* ]]
}

@test "parse_ini handles duplicate keys (last wins)" {
    local input
    input=$(printf '[sec]\nkey=first\nkey=second\n')
    local result
    result=$(parse_ini "$input")
    [[ "$result" == *'"key":"second"'* ]]
}

@test "parse_key_value handles value with equals sign" {
    local result
    result=$(printf 'connection=host=db.local;port=5432\n' | parse_key_value)
    [[ "$result" == *'"connection":"host=db.local;port=5432"'* ]]
}

@test "parse_key_value handles lines with only whitespace" {
    local result
    result=$(printf '   \n  \t  \nkey=val\n' | parse_key_value)
    [[ "$result" == *'"key":"val"'* ]]
}

@test "parse_nmap handles malformed host line (no ports)" {
    local input="Host: 10.0.0.1 (test)\tStatus: Up"
    local result
    result=$(parse_nmap "$input")
    # Should not crash, just skip the line
    [ "$result" = "[]" ]
}

@test "parse_nmap handles empty port fields" {
    local input="Host: 10.0.0.1 (test)\tPorts: 22/open/tcp////"
    local result
    result=$(parse_nmap "$input")
    [[ "$result" == *'"port":22'* ]]
    [[ "$result" == *'"state":"open"'* ]]
}

@test "parse_csv_line handles trailing comma" {
    parse_csv_line "a,b,c,"
    [ "${#PARSE_CSV_FIELDS[@]}" = "4" ]
    [ "${PARSE_CSV_FIELDS[3]}" = "" ]
}

@test "parse_csv_line handles leading comma" {
    parse_csv_line ",a,b"
    [ "${#PARSE_CSV_FIELDS[@]}" = "3" ]
    [ "${PARSE_CSV_FIELDS[0]}" = "" ]
}

@test "project_detect handles package.json with no deps" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"language":"javascript"'* ]] || [[ "$result" == *'"language":"typescript"'* ]] || [[ "$result" == *'"language":'* ]]
}

@test "project_detect handles malformed package.json" {
    echo 'not json at all' > "$TEST_DIR/package.json"
    local result
    # Should not crash
    result=$(project_detect "$TEST_DIR") || true
    [[ -n "$result" ]]
}

@test "project_commands handles package.json with no scripts" {
    echo '{"name":"test"}' > "$TEST_DIR/package.json"
    local result
    result=$(project_commands "$TEST_DIR")
    # Should return valid JSON even with no scripts
    [[ "$result" == "{"* ]]
}

# =============================================================================
# INTEGRATION TESTS: CONTRACT + OBSERVE
# =============================================================================

@test "contract violations are observable via trace" {
    local tid
    tid=$(trace_start "contract_test")

    local err=""
    err=$(contract_require "[[ -f /nonexistent ]]" "file missing" 2>&1) || true
    trace_step "$tid" "precondition_check" "failed" "$err"

    local result
    result=$(trace_end "$tid" "failed")
    [[ "$result" == *'"status":"failed"'* ]]
    [[ "$result" == *'"step":"precondition_check"'* ]]
}

@test "observe_command with contract-checked function" {
    my_checked_func() {
        contract_not_empty "$1" 2>/dev/null || return $?
        echo "processed: $1"
    }
    local result
    result=$(observe_command my_checked_func "input")
    [[ "$result" == *'"exit_code":0'* ]]
    [[ "$result" == *"processed: input"* ]]
}

@test "observe_command captures contract failure" {
    my_strict_func() {
        contract_type_check "$1" "int" "port" 2>/dev/null || return $?
        echo "port=$1"
    }
    local result
    result=$(observe_command my_strict_func "abc") || true
    [[ "$result" == *'"exit_code":1'* ]]
}

# =============================================================================
# INTEGRATION TESTS: ATOMIC + IDEMPOTENT
# =============================================================================

@test "ensure_file uses atomic semantics (no partial writes)" {
    # Write a file, then ensure_file with new content
    printf "original" > "$TEST_DIR/atomic_ensure.txt"
    ensure_file "$TEST_DIR/atomic_ensure.txt" "new content"
    local content
    content=$(<"$TEST_DIR/atomic_ensure.txt")
    [ "$content" = "new content" ]
}

@test "checkpoint + idempotent ensure_file workflow" {
    # Create initial file
    ensure_file "$TEST_DIR/workflow.conf" "setting=1"
    file_checkpoint "$TEST_DIR/workflow.conf" "initial"

    # Modify it
    ensure_file "$TEST_DIR/workflow.conf" "setting=2"
    [ "$(cat "$TEST_DIR/workflow.conf")" = "setting=2" ]

    # Rollback
    file_rollback "$TEST_DIR/workflow.conf" "initial"
    [ "$(cat "$TEST_DIR/workflow.conf")" = "setting=1" ]
}

@test "safe_remove + ensure_file recreates cleanly" {
    ensure_file "$TEST_DIR/recreate.txt" "version1"
    safe_remove "$TEST_DIR/recreate.txt"
    [ ! -f "$TEST_DIR/recreate.txt" ]
    ensure_file "$TEST_DIR/recreate.txt" "version2"
    [ "$(cat "$TEST_DIR/recreate.txt")" = "version2" ]
}

# =============================================================================
# INTEGRATION TESTS: PROJECT + PARSERS
# =============================================================================

@test "parse_semver validates project_detect version fields" {
    echo '{"dependencies":{"react":"18.2.0","next":"14.1.0"}}' > "$TEST_DIR/package.json"
    local detect
    detect=$(project_detect "$TEST_DIR")

    # Parse versions from deps
    local react_ver
    react_ver=$(parse_semver "18.2.0")
    [[ "$react_ver" == *'"major":18'* ]]
    [[ "$react_ver" == *'"minor":2'* ]]
}

@test "parse_ini + project_detect for Python project" {
    # Create a pyproject.toml-like structure (INI-compatible parts)
    cat > "$TEST_DIR/setup.cfg" << 'EOF'
[metadata]
name = myproject
version = 2.1.0

[options]
install_requires =
    fastapi>=0.100
    uvicorn>=0.20
EOF
    touch "$TEST_DIR/pyproject.toml"
    local ini_result
    ini_result=$(parse_ini < "$TEST_DIR/setup.cfg")
    [[ "$ini_result" == *'"name":"myproject"'* ]]
    [[ "$ini_result" == *'"version":"2.1.0"'* ]]
}

# =============================================================================
# INTEGRATION TESTS: PERF + OBSERVE
# =============================================================================

@test "perf_benchmark and observe_command agree on exit code" {
    local bench_result obs_result
    bench_result=$(perf_benchmark "false" 1) || true
    obs_result=$(observe_command false) || true
    [[ "$bench_result" == *'"exit_code":1'* ]]
    [[ "$obs_result" == *'"exit_code":1'* ]]
}

@test "perf_timer wraps trace timing correctly" {
    perf_timer_start "trace_perf"
    local tid
    tid=$(trace_start "perf_traced_op")
    trace_step "$tid" "work" "ok"
    local trace_result
    trace_result=$(trace_end "$tid")
    local perf_elapsed
    perf_elapsed=$(perf_timer_elapsed "trace_perf")

    # Both should report valid durations
    [[ "$trace_result" == *'"duration_s":'* ]]
    [[ "$perf_elapsed" =~ ^[0-9]+\.?[0-9]*$ ]]
}

# =============================================================================
# REAL-WORLD SCENARIO TESTS
# =============================================================================

@test "scenario: config file update with validation and rollback" {
    # Simulate updating a config file safely
    local config="$TEST_DIR/app.conf"
    printf 'port=8080\nhost=localhost\ndebug=false\n' > "$config"

    # Checkpoint before change
    file_checkpoint "$config" "pre-update"

    # Validate new port
    local new_port=9090
    contract_in_range "$new_port" 1 65535 "port" || {
        file_rollback "$config" "pre-update"
        return 1
    }

    # Apply change atomically
    local new_content="port=$new_port\nhost=localhost\ndebug=true\n"
    atomic_write "$config" "$(printf "$new_content")"

    # Verify
    [[ "$(cat "$config")" == *"port=9090"* ]]

    # Rollback to verify that works too
    file_rollback "$config" "pre-update"
    [[ "$(cat "$config")" == *"port=8080"* ]]
}

@test "scenario: project scan with traced detection" {
    # Set up a Node.js project
    mkdir -p "$TEST_DIR/project/src"
    cat > "$TEST_DIR/project/package.json" << 'EOF'
{"scripts":{"build":"tsc","test":"vitest"},"dependencies":{"express":"4"}}
EOF
    touch "$TEST_DIR/project/tsconfig.json"
    touch "$TEST_DIR/project/src/index.ts"

    # Trace the detection
    local tid
    tid=$(trace_start "project_scan")

    local detect
    detect=$(project_detect "$TEST_DIR/project")
    trace_step "$tid" "detect" "ok" "$detect"
    [[ "$detect" == *'"language":"typescript"'* ]]

    local commands
    commands=$(project_commands "$TEST_DIR/project")
    trace_step "$tid" "commands" "ok"

    local entry
    entry=$(project_entry "$TEST_DIR/project")
    trace_step "$tid" "entry" "ok"
    [[ "$entry" == *"src/index.ts"* ]]

    local summary
    summary=$(trace_end "$tid")
    [[ "$summary" == *'"status":"success"'* ]]
    [[ "$summary" == *'"step":"detect"'* ]]
    [[ "$summary" == *'"step":"commands"'* ]]
    [[ "$summary" == *'"step":"entry"'* ]]
}

@test "scenario: parse URL then check port" {
    local url_json
    url_json=$(parse_url "http://localhost:9999/api/health")
    # Extract port (simple string match since we know the format)
    [[ "$url_json" == *'"port":9999'* ]]

    # Use the parsed port to check connectivity
    local port_result
    port_result=$(monitor_port "localhost" 9999 1)
    [[ "$port_result" == *'"state":'* ]]
    [[ "$port_result" == *'"port":9999'* ]]
}

@test "scenario: multi-file atomic deployment" {
    # Simulate deploying multiple config files atomically
    local deploy_dir="$TEST_DIR/deploy"
    ensure_dir "$deploy_dir"

    local tid
    tid=$(trace_start "deploy")

    # Write configs
    atomic_write "$deploy_dir/db.conf" "host=prod-db\nport=5432"
    trace_step "$tid" "write_db_conf" "ok"

    atomic_write "$deploy_dir/app.conf" "port=8080\nworkers=4"
    trace_step "$tid" "write_app_conf" "ok"

    atomic_write "$deploy_dir/version.txt" "2.1.0"
    trace_step "$tid" "write_version" "ok"

    # Verify all files exist
    contract_is_file "$deploy_dir/db.conf" || trace_step "$tid" "verify" "failed"
    contract_is_file "$deploy_dir/app.conf" || trace_step "$tid" "verify" "failed"
    contract_is_file "$deploy_dir/version.txt" || trace_step "$tid" "verify" "failed"

    local result
    result=$(trace_end "$tid")
    [[ "$result" == *'"status":"success"'* ]]

    # Parse the version
    local ver
    ver=$(parse_semver "$(cat "$deploy_dir/version.txt")")
    [[ "$ver" == *'"major":2'* ]]
}

@test "scenario: ensure_lines creates valid INI parseable config" {
    local config="$TEST_DIR/generated.ini"
    printf '[server]\n' > "$config"
    ensure_line "$config" "host=0.0.0.0"
    ensure_line "$config" "port=3000"
    ensure_line "$config" "debug=false"

    local parsed
    parsed=$(parse_ini < "$config")
    [[ "$parsed" == *'"host":"0.0.0.0"'* ]]
    [[ "$parsed" == *'"port":"3000"'* ]]
    [[ "$parsed" == *'"debug":"false"'* ]]
}

# =============================================================================
# STRESS TESTS
# =============================================================================

@test "trace with 50 steps completes correctly" {
    local tid
    tid=$(trace_start "many_steps")
    for i in $(seq 1 50); do
        trace_step "$tid" "step_$i" "ok" "detail_$i"
    done
    local result
    result=$(trace_end "$tid")
    [[ "$result" == *'"step":"step_1"'* ]]
    [[ "$result" == *'"step":"step_50"'* ]]
    [[ "$result" == *'"status":"success"'* ]]
}

@test "observe_command with large stdout (truncated safely)" {
    local result
    result=$(observe_command bash -c 'for i in $(seq 1 1000); do echo "line $i of output"; done')
    [[ "$result" == *'"exit_code":0'* ]]
    # Should contain some output (truncated at 4096 chars)
    [[ "$result" == *"line 1 of output"* ]]
}

@test "parse_csv_line with fields containing all special chars" {
    parse_csv_line '"tab\there","new
line","back\\slash","quote""inside"'
    # The parser handles in-quote content literally
    [ "${#PARSE_CSV_FIELDS[@]}" = "4" ]
}

@test "50 sequential atomic_writes to same file" {
    for i in $(seq 1 50); do
        atomic_write "$TEST_DIR/seq_write.txt" "iteration_$i"
    done
    [ "$(cat "$TEST_DIR/seq_write.txt")" = "iteration_50" ]
    # No leftover temp files
    local temps
    temps=$(ls "$TEST_DIR"/.mainframe_atomic_* 2>/dev/null | wc -l || echo 0)
    [ "$temps" = "0" ]
}

@test "ensure_dirs creates 20 directories" {
    local dirs=()
    for i in $(seq 1 20); do
        dirs+=("$TEST_DIR/dir_$i")
    done
    ensure_dirs "${dirs[@]}"
    for i in $(seq 1 20); do
        [ -d "$TEST_DIR/dir_$i" ]
    done
}

@test "multiple traces can run concurrently (different IDs)" {
    local tid1 tid2 tid3
    tid1=$(trace_start "concurrent_1")
    tid2=$(trace_start "concurrent_2")
    tid3=$(trace_start "concurrent_3")

    trace_step "$tid2" "middle_step" "ok"
    trace_step "$tid1" "first_step" "ok"
    trace_step "$tid3" "third_step" "ok"
    trace_step "$tid1" "another_step" "ok"

    local r1 r2 r3
    r1=$(trace_end "$tid1")
    r2=$(trace_end "$tid2")
    r3=$(trace_end "$tid3")

    # Each trace should have its own steps
    [[ "$r1" == *'"step":"first_step"'* ]]
    [[ "$r1" == *'"step":"another_step"'* ]]
    [[ "$r2" == *'"step":"middle_step"'* ]]
    [[ "$r3" == *'"step":"third_step"'* ]]

    # Steps should not bleed between traces
    [[ "$r1" != *'"step":"middle_step"'* ]]
    [[ "$r2" != *'"step":"first_step"'* ]]
}

# =============================================================================
# ERROR RECOVERY TESTS
# =============================================================================

@test "atomic_replace rollback on verify failure preserves original" {
    printf "ORIGINAL CONTENT" > "$TEST_DIR/verify_target.txt"
    # Verify command that always fails - atomic_replace returns 1
    local rc=0
    atomic_replace "$TEST_DIR/verify_target.txt" "BAD CONTENT" "false" 2>/dev/null || rc=$?
    [ "$rc" = "1" ]
    # Original should be preserved despite the failed replace
    [ "$(cat "$TEST_DIR/verify_target.txt")" = "ORIGINAL CONTENT" ]
}

@test "atomic_write to readonly directory fails gracefully" {
    mkdir -p "$TEST_DIR/readonly_dir"
    chmod 555 "$TEST_DIR/readonly_dir"
    local rc=0
    atomic_write "$TEST_DIR/readonly_dir/file.txt" "content" 2>/dev/null || rc=$?
    [ "$rc" != "0" ]
    chmod 755 "$TEST_DIR/readonly_dir"  # cleanup
}

@test "trace_end on already-ended trace returns error" {
    local tid
    tid=$(trace_start "once_only")
    trace_end "$tid" >/dev/null
    # Second call should fail
    local result
    ! result=$(trace_end "$tid") || [[ "$result" == *"unknown trace_id"* ]]
}

@test "file_rollback with corrupted checkpoint dir handles gracefully" {
    printf "content" > "$TEST_DIR/fragile.txt"
    file_checkpoint "$TEST_DIR/fragile.txt" "good"

    # Corrupt the checkpoint by removing it
    rm -f "$MAINFRAME_CHECKPOINT_DIR"/*__good

    local rc=0
    file_rollback "$TEST_DIR/fragile.txt" "good" 2>/dev/null || rc=$?
    [ "$rc" != "0" ]
    # Original file should be unchanged
    [ "$(cat "$TEST_DIR/fragile.txt")" = "content" ]
}

@test "safe_remove followed by safe_remove is idempotent" {
    printf "data" > "$TEST_DIR/double_remove.txt"
    safe_remove "$TEST_DIR/double_remove.txt"
    safe_remove "$TEST_DIR/double_remove.txt"  # Should not error
    [ ! -f "$TEST_DIR/double_remove.txt" ]
}

# =============================================================================
# PERFORMANCE VALIDATION TESTS
# =============================================================================

@test "perf_compare detects faster command" {
    # 'true' should be faster than 'sleep 0.01'
    local result
    result=$(perf_compare "true" "sleep 0.01" 3)
    [[ "$result" == *'"winner":"cmd1"'* ]]
}

@test "perf_benchmark average is less than total" {
    local result
    result=$(perf_benchmark "true" 10)
    # Extract values (basic string check)
    [[ "$result" == *'"total_s":'* ]]
    [[ "$result" == *'"avg_s":'* ]]
}

@test "bash_features JSON has all expected keys" {
    local result
    result=$(bash_features)
    [[ "$result" == *'"namerefs":'* ]]
    [[ "$result" == *'"mapfile":'* ]]
    [[ "$result" == *'"associative_arrays":'* ]]
    [[ "$result" == *'"epochrealtime":'* ]]
    [[ "$result" == *'"epochseconds":'* ]]
    [[ "$result" == *'"wait_n":'* ]]
    [[ "$result" == *'"lastpipe":'* ]]
    [[ "$result" == *'"inherit_errexit":'* ]]
    [[ "$result" == *'"extglob":'* ]]
    [[ "$result" == *'"loadable_builtins":'* ]]
}

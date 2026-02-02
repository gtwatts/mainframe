#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/policy.bats - Policy Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/policy.sh
#              Policy-as-code guardrails for AI agents
# Test Count: 56 test cases
# Categories: policy loading, inline definition, policy checking,
#             approval workflow, audit logging, audit queries,
#             glob matching, validation, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Configure policy library to use test directory
    export POLICY_DIR="$TEST_TMPDIR/policy"
    export POLICY_AUDIT_LOG="$POLICY_DIR/audit.jsonl"
    export POLICY_PENDING_FILE="$POLICY_DIR/pending.jsonl"
    export POLICY_APPROVED_FILE="$POLICY_DIR/approved.jsonl"
    export POLICY_DENIED_FILE="$POLICY_DIR/denied.jsonl"
    export MAINFRAME_QUIET=1

    # Source the library
    source "$MAINFRAME_ROOT/lib/policy.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create a test policy file
create_test_policy() {
    local file="$1"
    cat > "$file" << 'EOF'
version: "1.0"
policies:
  - name: "file_operations"
    description: "Control file system access"
    rules:
      - action: "write"
        resources: ["/tmp/*", "/var/log/*"]
        effect: "allow"
      - action: "write"
        resources: ["/etc/*", "/usr/*"]
        effect: "deny"
      - action: "delete"
        resources: ["*"]
        effect: "require_approval"

  - name: "network_access"
    description: "Control network requests"
    rules:
      - action: "http_request"
        resources: ["api.openai.com", "api.anthropic.com"]
        effect: "allow"
      - action: "http_request"
        resources: ["*.internal"]
        effect: "deny"
EOF
}

# =============================================================================
# CATEGORY 1: POLICY LOADING
# =============================================================================

@test "policy_load: loads valid policy file" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"

    run policy_load "$policy_file"
    [[ "$status" -eq 0 ]]
}

@test "policy_load: fails with missing file" {
    run policy_load "$TEST_TMPDIR/nonexistent.yaml"
    [[ "$status" -eq 1 ]]
}

@test "policy_load: fails with empty path" {
    run policy_load ""
    [[ "$status" -eq 1 ]]
}

@test "policy_load: parses policy names correctly" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    result=$(policy_list)
    [[ "$result" =~ '"name":"file_operations"' ]]
    [[ "$result" =~ '"name":"network_access"' ]]
}

@test "policy_load: parses descriptions correctly" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    result=$(policy_list)
    [[ "$result" =~ 'Control file system access' ]]
    [[ "$result" =~ 'Control network requests' ]]
}

# =============================================================================
# CATEGORY 2: INLINE POLICY DEFINITION
# =============================================================================

@test "policy_define: creates inline policy" {
    policy_define "test_policy" '{"action":"read","resources":["/data/*"],"effect":"allow"}'
    result=$(policy_list)
    [[ "$result" =~ '"name":"test_policy"' ]]
}

@test "policy_define: fails with missing name" {
    run policy_define "" '{"action":"read","effect":"allow"}'
    [[ "$status" -eq 1 ]]
}

@test "policy_define: fails with missing rule_json" {
    run policy_define "test_policy" ""
    [[ "$status" -eq 1 ]]
}

@test "policy_define: fails with missing action in rule" {
    run policy_define "test_policy" '{"effect":"allow"}'
    [[ "$status" -eq 1 ]]
}

@test "policy_define: fails with missing effect in rule" {
    run policy_define "test_policy" '{"action":"read"}'
    [[ "$status" -eq 1 ]]
}

@test "policy_define: adds multiple rules to same policy" {
    policy_define "multi_rule" '{"action":"read","resources":["/data/*"],"effect":"allow"}'
    policy_define "multi_rule" '{"action":"write","resources":["/data/*"],"effect":"deny"}'

    result=$(policy_list | grep "multi_rule")
    [[ "$result" =~ '"rule_count":2' ]]
}

# =============================================================================
# CATEGORY 3: POLICY CHECKING
# =============================================================================

@test "policy_check: allows action matching allow rule" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    result=$(policy_check "write" "agent-1" "/tmp/test.txt")
    [[ "$result" =~ '"allowed":true' ]]
    [[ "$result" =~ '"effect":"allow"' ]]
}

@test "policy_check: denies action matching deny rule" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    run policy_check "write" "agent-1" "/etc/passwd"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ '"allowed":false' ]]
    [[ "$output" =~ '"effect":"deny"' ]]
}

@test "policy_check: requires approval for require_approval rule" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    run policy_check "delete" "agent-1" "/important/file.txt"
    [[ "$status" -eq 2 ]]
    [[ "$output" =~ '"requires_approval":true' ]]
    [[ "$output" =~ '"action_id":"action_' ]]
}

@test "policy_check: allows with no policies loaded" {
    result=$(policy_check "anything" "agent-1" "/anywhere")
    [[ "$result" =~ '"allowed":true' ]]
    [[ "$result" =~ '"reason":"no_policies_loaded"' ]]
}

@test "policy_check: allows with no matching rule" {
    policy_define "specific" '{"action":"read","resources":["/specific/*"],"effect":"deny"}'

    result=$(policy_check "write" "agent-1" "/other/path")
    [[ "$result" =~ '"allowed":true' ]]
    [[ "$result" =~ '"reason":"no_matching_rule"' ]]
}

@test "policy_check: fails with empty action" {
    run policy_check "" "agent-1"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 4: GLOB PATTERN MATCHING
# =============================================================================

@test "policy_check: matches asterisk wildcard" {
    policy_define "wildcard" '{"action":"access","resources":["/data/*"],"effect":"allow"}'

    result=$(policy_check "access" "agent-1" "/data/file.txt")
    [[ "$result" =~ '"allowed":true' ]]

    result=$(policy_check "access" "agent-1" "/data/subdir/file.txt")
    [[ "$result" =~ '"allowed":true' ]]
}

@test "policy_check: matches question mark wildcard" {
    policy_define "single_char" '{"action":"read","resources":["/log?.txt"],"effect":"allow"}'

    result=$(policy_check "read" "agent-1" "/log1.txt")
    [[ "$result" =~ '"allowed":true' ]]

    result=$(policy_check "read" "agent-1" "/logA.txt")
    [[ "$result" =~ '"allowed":true' ]]
}

@test "policy_check: rejects non-matching pattern" {
    policy_define "specific_path" '{"action":"write","resources":["/allowed/*"],"effect":"allow"}'
    policy_define "default_deny" '{"action":"write","resources":["*"],"effect":"deny"}'

    run policy_check "write" "agent-1" "/forbidden/file.txt"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ '"allowed":false' ]]
}

@test "policy_check: handles multiple resource patterns" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    # First pattern
    result=$(policy_check "write" "agent-1" "/tmp/test.txt")
    [[ "$result" =~ '"allowed":true' ]]

    # Second pattern
    result=$(policy_check "write" "agent-1" "/var/log/app.log")
    [[ "$result" =~ '"allowed":true' ]]
}

# =============================================================================
# CATEGORY 5: APPROVAL WORKFLOW
# =============================================================================

@test "policy_require_approval: creates pending action" {
    result=$(policy_require_approval "deploy" "agent-1" "production")
    [[ "$result" =~ '"status":"pending"' ]]
    [[ "$result" =~ '"action_id":"action_' ]]

    pending=$(policy_pending)
    [[ "$pending" =~ '"action":"deploy"' ]]
    [[ "$pending" =~ '"agent":"agent-1"' ]]
}

@test "policy_approve: approves pending action" {
    # Create pending action
    result=$(policy_require_approval "risky_action" "agent-1")
    action_id=$(echo "$result" | grep -o '"action_id":"[^"]*"' | cut -d'"' -f4)

    # Approve it
    result=$(policy_approve "$action_id")
    [[ "$result" =~ '"status":"approved"' ]]

    # Verify it's no longer pending
    pending=$(policy_pending)
    [[ ! "$pending" =~ "$action_id" ]]

    # Verify it's in approved file
    policy_is_approved "$action_id"
    [[ $? -eq 0 ]]
}

@test "policy_approve: handles already approved action" {
    result=$(policy_require_approval "action1" "agent-1")
    action_id=$(echo "$result" | grep -o '"action_id":"[^"]*"' | cut -d'"' -f4)

    policy_approve "$action_id"
    result=$(policy_approve "$action_id")
    [[ "$result" =~ '"status":"already_approved"' ]]
}

@test "policy_approve: fails for non-existent action" {
    run policy_approve "nonexistent_action_id"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ '"error":"not_found"' ]]
}

@test "policy_deny: denies pending action with reason" {
    result=$(policy_require_approval "dangerous" "agent-1")
    action_id=$(echo "$result" | grep -o '"action_id":"[^"]*"' | cut -d'"' -f4)

    result=$(policy_deny "$action_id" "Too dangerous for production")
    [[ "$result" =~ '"status":"denied"' ]]
    [[ "$result" =~ 'Too dangerous for production' ]]

    # Verify not pending anymore
    pending=$(policy_pending)
    [[ ! "$pending" =~ "$action_id" ]]
}

@test "policy_deny: handles already denied action" {
    result=$(policy_require_approval "action2" "agent-1")
    action_id=$(echo "$result" | grep -o '"action_id":"[^"]*"' | cut -d'"' -f4)

    policy_deny "$action_id" "reason1"
    result=$(policy_deny "$action_id" "reason2")
    [[ "$result" =~ '"status":"already_denied"' ]]
}

@test "policy_pending: lists all pending actions" {
    policy_require_approval "action1" "agent-1"
    policy_require_approval "action2" "agent-2"
    policy_require_approval "action3" "agent-3"

    pending=$(policy_pending)
    [[ "$pending" =~ '"action":"action1"' ]]
    [[ "$pending" =~ '"action":"action2"' ]]
    [[ "$pending" =~ '"action":"action3"' ]]
}

@test "policy_is_approved: returns 0 for approved action" {
    result=$(policy_require_approval "test_action" "agent-1")
    action_id=$(echo "$result" | grep -o '"action_id":"[^"]*"' | cut -d'"' -f4)

    policy_approve "$action_id"
    policy_is_approved "$action_id"
    [[ $? -eq 0 ]]
}

@test "policy_is_approved: returns 1 for non-approved action" {
    run policy_is_approved "never_approved_id"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 6: AUDIT LOGGING
# =============================================================================

@test "policy_audit: creates audit entry" {
    policy_audit "write" "agent-123" "/tmp/file.txt" "allowed" "file_ops"

    audit_content=$(cat "$POLICY_AUDIT_LOG")
    [[ "$audit_content" =~ '"action":"write"' ]]
    [[ "$audit_content" =~ '"actor":"agent-123"' ]]
    [[ "$audit_content" =~ '"resource":"/tmp/file.txt"' ]]
    [[ "$audit_content" =~ '"result":"allowed"' ]]
}

@test "policy_audit: includes timestamp" {
    policy_audit "read" "agent-1" "/data" "success"

    audit_content=$(cat "$POLICY_AUDIT_LOG")
    [[ "$audit_content" =~ '"timestamp":"' ]]
}

@test "policy_audit_query: filters by actor" {
    policy_audit "action1" "agent-A" "/path1" "success"
    policy_audit "action2" "agent-B" "/path2" "success"
    policy_audit "action3" "agent-A" "/path3" "success"

    result=$(policy_audit_query --actor "agent-A")
    [[ "$result" =~ '"actor":"agent-A"' ]]
    [[ ! "$result" =~ '"actor":"agent-B"' ]]
}

@test "policy_audit_query: filters by action" {
    policy_audit "write" "agent-1" "/path1" "success"
    policy_audit "read" "agent-2" "/path2" "success"
    policy_audit "write" "agent-3" "/path3" "denied"

    result=$(policy_audit_query --action "write")
    [[ "$result" =~ '"action":"write"' ]]
    [[ ! "$result" =~ '"action":"read"' ]]
}

@test "policy_audit_query: filters by result" {
    policy_audit "action1" "agent-1" "/path1" "allowed"
    policy_audit "action2" "agent-2" "/path2" "denied"
    policy_audit "action3" "agent-3" "/path3" "allowed"

    result=$(policy_audit_query --result "denied")
    [[ "$result" =~ '"result":"denied"' ]]
    [[ ! "$result" =~ '"result":"allowed"' ]]
}

@test "policy_audit_query: filters by resource" {
    policy_audit "write" "agent-1" "/tmp/file1.txt" "success"
    policy_audit "write" "agent-2" "/var/log/app.log" "success"
    policy_audit "write" "agent-3" "/tmp/file2.txt" "success"

    result=$(policy_audit_query --resource "/tmp/")
    [[ "$result" =~ '"/tmp/' ]]
}

@test "policy_audit_query: combines multiple filters" {
    policy_audit "write" "agent-A" "/tmp/test.txt" "allowed"
    policy_audit "read" "agent-A" "/tmp/other.txt" "allowed"
    policy_audit "write" "agent-B" "/tmp/test.txt" "denied"

    result=$(policy_audit_query --actor "agent-A" --action "write")
    [[ "$result" =~ '"actor":"agent-A"' ]]
    [[ "$result" =~ '"action":"write"' ]]

    # Should not include agent-B or read action
    line_count=$(echo "$result" | grep -c '"actor"' || true)
    [[ "$line_count" -eq 1 ]]
}

@test "policy_audit_clear: empties audit log" {
    policy_audit "action1" "agent-1" "/path" "success"
    policy_audit "action2" "agent-2" "/path" "success"

    policy_audit_clear

    [[ ! -s "$POLICY_AUDIT_LOG" ]]
}

# =============================================================================
# CATEGORY 7: VALIDATION
# =============================================================================

@test "policy_validate: validates correct policy file" {
    local policy_file="$TEST_TMPDIR/valid_policy.yaml"
    create_test_policy "$policy_file"

    result=$(policy_validate "$policy_file")
    [[ "$result" =~ '"valid":true' ]]
}

@test "policy_validate: fails for missing file" {
    run policy_validate "$TEST_TMPDIR/nonexistent.yaml"
    [[ "$output" =~ '"valid":false' ]]
    [[ "$output" =~ 'file not found' ]]
}

@test "policy_validate: fails for missing version" {
    local policy_file="$TEST_TMPDIR/no_version.yaml"
    cat > "$policy_file" << 'EOF'
policies:
  - name: "test"
    rules: []
EOF

    run policy_validate "$policy_file"
    [[ "$output" =~ '"valid":false' ]]
    [[ "$output" =~ 'missing required field: version' ]]
}

@test "policy_validate: fails for missing policies" {
    local policy_file="$TEST_TMPDIR/no_policies.yaml"
    cat > "$policy_file" << 'EOF'
version: "1.0"
name: "test"
EOF

    run policy_validate "$policy_file"
    [[ "$output" =~ '"valid":false' ]]
    [[ "$output" =~ 'missing required field: policies' ]]
}

@test "policy_validate: detects tabs in YAML" {
    local policy_file="$TEST_TMPDIR/tabs.yaml"
    printf 'version: "1.0"\npolicies:\n\t- name: "test"\n' > "$policy_file"

    run policy_validate "$policy_file"
    [[ "$output" =~ '"valid":false' ]]
    [[ "$output" =~ 'tabs not allowed' ]]
}

# =============================================================================
# CATEGORY 8: UTILITY FUNCTIONS
# =============================================================================

@test "policy_list: shows all loaded policies" {
    policy_define "policy1" '{"action":"read","resources":["*"],"effect":"allow"}'
    policy_define "policy2" '{"action":"write","resources":["*"],"effect":"deny"}'

    result=$(policy_list)
    [[ "$result" =~ '"name":"policy1"' ]]
    [[ "$result" =~ '"name":"policy2"' ]]
}

@test "policy_clear: removes all policies" {
    policy_define "test1" '{"action":"read","resources":["*"],"effect":"allow"}'
    policy_define "test2" '{"action":"write","resources":["*"],"effect":"deny"}'

    policy_clear

    result=$(policy_list)
    [[ -z "$result" ]]
}

@test "policy_status: shows correct counts" {
    policy_define "test" '{"action":"read","resources":["*"],"effect":"allow"}'
    policy_require_approval "pending1" "agent-1"
    policy_require_approval "pending2" "agent-2"

    result=$(policy_status)
    [[ "$result" =~ '"policies_loaded":1' ]]
    [[ "$result" =~ '"pending_approvals":2' ]]
}

# =============================================================================
# CATEGORY 9: EDGE CASES AND SECURITY
# =============================================================================

@test "policy_check: handles special characters in resource" {
    policy_define "special" '{"action":"access","resources":["/path/with spaces/*"],"effect":"allow"}'

    result=$(policy_check "access" "agent-1" "/path/with spaces/file.txt")
    [[ "$result" =~ '"allowed":true' ]]
}

@test "policy_audit: escapes JSON special characters" {
    policy_audit "write" "agent-1" '/path/with"quotes' "success"

    audit_content=$(cat "$POLICY_AUDIT_LOG")
    # Should be properly escaped
    [[ "$audit_content" =~ '\\\"' ]] || [[ "$audit_content" =~ 'quotes' ]]
}

@test "policy_check: uses default agent_id when not provided" {
    policy_define "test" '{"action":"read","resources":["*"],"effect":"allow"}'

    result=$(policy_check "read" "" "/path")
    [[ "$result" =~ '"allowed":true' ]]
}

@test "policy_approve: handles empty action_id" {
    run policy_approve ""
    [[ "$status" -eq 1 ]]
}

@test "policy_deny: handles empty action_id" {
    run policy_deny ""
    [[ "$status" -eq 1 ]]
}

@test "policy_check: policy check creates audit entry" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    policy_check "write" "audit-test-agent" "/tmp/test.txt"

    audit_content=$(cat "$POLICY_AUDIT_LOG")
    [[ "$audit_content" =~ '"actor":"audit-test-agent"' ]]
}

# =============================================================================
# CATEGORY 10: AUDIT QUERY - SINCE FILTER
# =============================================================================

@test "policy_audit_query: filters by since timestamp" {
    # Create entries with known timestamps
    policy_audit "old_action" "agent-1" "/path1" "success"
    sleep 1
    local timestamp_after
    timestamp_after=$(date -Iseconds)
    sleep 1
    policy_audit "new_action" "agent-2" "/path2" "success"

    result=$(policy_audit_query --since "$timestamp_after")
    [[ "$result" =~ '"action":"new_action"' ]]
    [[ ! "$result" =~ '"action":"old_action"' ]]
}

# =============================================================================
# CATEGORY 11: POLICY RULE PRIORITY
# =============================================================================

@test "policy_check: more specific pattern takes precedence" {
    # Define general deny first, then specific allow
    policy_define "general_deny" '{"action":"write","resources":["/*"],"effect":"deny"}'
    policy_define "specific_allow" '{"action":"write","resources":["/allowed/specific/*"],"effect":"allow"}'

    # Specific allow should win due to longer pattern
    result=$(policy_check "write" "agent-1" "/allowed/specific/file.txt")
    [[ "$result" =~ '"allowed":true' ]]
}

# =============================================================================
# CATEGORY 12: EMPTY RESOURCES HANDLING
# =============================================================================

@test "policy_check: handles empty resources as wildcard" {
    policy_define "empty_resources" '{"action":"test_action","resources":[],"effect":"allow"}'

    result=$(policy_check "test_action" "agent-1" "/any/path")
    [[ "$result" =~ '"allowed":true' ]]
}

# =============================================================================
# CATEGORY 13: NETWORK POLICY PATTERNS
# =============================================================================

@test "policy_check: matches domain patterns" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    # Allowed domains
    result=$(policy_check "http_request" "agent-1" "api.openai.com")
    [[ "$result" =~ '"allowed":true' ]]

    result=$(policy_check "http_request" "agent-1" "api.anthropic.com")
    [[ "$result" =~ '"allowed":true' ]]
}

@test "policy_check: denies internal domain patterns" {
    local policy_file="$TEST_TMPDIR/test_policy.yaml"
    create_test_policy "$policy_file"
    policy_load "$policy_file"

    run policy_check "http_request" "agent-1" "secret.internal"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ '"allowed":false' ]]
}

# =============================================================================
# CATEGORY 14: DESTRUCTIVE OPERATIONS
# =============================================================================

@test "policy_check: destructive operations policy" {
    cat > "$TEST_TMPDIR/destructive.yaml" << 'EOF'
version: "1.0"
policies:
  - name: "destructive_ops"
    description: "Control destructive operations"
    rules:
      - action: "rm"
        resources: ["*"]
        effect: "require_approval"
      - action: "git_push"
        resources: ["*"]
        effect: "require_approval"
EOF

    policy_load "$TEST_TMPDIR/destructive.yaml"

    run policy_check "rm" "agent-1" "/important/data"
    [[ "$status" -eq 2 ]]
    [[ "$output" =~ '"requires_approval":true' ]]

    run policy_check "git_push" "agent-1" "origin/main"
    [[ "$status" -eq 2 ]]
    [[ "$output" =~ '"requires_approval":true' ]]
}

# =============================================================================
# CATEGORY 15: POLICY STATUS TRACKING
# =============================================================================

@test "policy_status: tracks approvals and denials" {
    policy_define "test" '{"action":"action","resources":["*"],"effect":"require_approval"}'

    # Create some pending actions
    result1=$(policy_require_approval "action1" "agent-1")
    action_id1=$(echo "$result1" | grep -o '"action_id":"[^"]*"' | cut -d'"' -f4)

    result2=$(policy_require_approval "action2" "agent-2")
    action_id2=$(echo "$result2" | grep -o '"action_id":"[^"]*"' | cut -d'"' -f4)

    # Approve one, deny one
    policy_approve "$action_id1"
    policy_deny "$action_id2" "testing"

    status=$(policy_status)
    [[ "$status" =~ '"approved_actions":1' ]]
    [[ "$status" =~ '"denied_actions":1' ]]
    [[ "$status" =~ '"pending_approvals":0' ]]
}

# =============================================================================
# CATEGORY 16: MULTI-LINE YAML PARSING
# =============================================================================

@test "policy_load: handles multi-line resource arrays" {
    cat > "$TEST_TMPDIR/multiline.yaml" << 'EOF'
version: "1.0"
policies:
  - name: "multiline_test"
    description: "Test multi-line arrays"
    rules:
      - action: "access"
        resources:
          - "/path/one/*"
          - "/path/two/*"
          - "/path/three/*"
        effect: "allow"
EOF

    policy_load "$TEST_TMPDIR/multiline.yaml"

    result=$(policy_check "access" "agent-1" "/path/one/file.txt")
    [[ "$result" =~ '"allowed":true' ]]

    result=$(policy_check "access" "agent-1" "/path/two/file.txt")
    [[ "$result" =~ '"allowed":true' ]]

    result=$(policy_check "access" "agent-1" "/path/three/file.txt")
    [[ "$result" =~ '"allowed":true' ]]
}

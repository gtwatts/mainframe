#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/rbac.bats - RBAC Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/rbac.sh
#              Role-Based Access Control for enterprise deployments
# Test Count: 50 test cases
# Categories: initialization, role management, subject management,
#             permission checking, wildcards, inheritance, audit, import/export
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library
    source "$MAINFRAME_ROOT/lib/rbac.sh"

    # Reset RBAC state before each test
    rbac_reset
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: INITIALIZATION
# =============================================================================

@test "rbac_reset: clears all state" {
    rbac_define_role "test-role" "files:read"
    rbac_assign_role "test-subject" "test-role"

    rbac_reset

    run rbac_list_roles
    [[ -z "$output" ]]

    run rbac_list_subjects
    [[ -z "$output" ]]
}

@test "rbac_init: loads config from YAML file" {
    cat > "$TEST_TMPDIR/rbac.yaml" << 'EOF'
roles:
  admin:
    description: "Full access"
    permissions:
      - "*:*"
  reader:
    permissions:
      - "files:read"
      - "logs:read"
subjects:
  agent-001:
    roles:
      - admin
  agent-002:
    roles:
      - reader
EOF

    rbac_init "$TEST_TMPDIR/rbac.yaml"

    # Check roles loaded
    run rbac_list_roles
    [[ "$output" =~ "admin" ]]
    [[ "$output" =~ "reader" ]]

    # Check subjects loaded
    run rbac_list_subjects
    [[ "$output" =~ "agent-001" ]]
    [[ "$output" =~ "agent-002" ]]
}

@test "rbac_init: fails on missing file" {
    run rbac_init "/nonexistent/file.yaml"
    [[ "$status" -eq 1 ]]
}

@test "rbac_init: fails with no argument" {
    run rbac_init
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 2: ROLE MANAGEMENT
# =============================================================================

@test "rbac_define_role: creates role with permissions" {
    rbac_define_role "reader" "files:read" "logs:read"

    run rbac_list_roles
    [[ "$output" =~ "reader" ]]
    [[ "$output" =~ "files:read" ]]
    [[ "$output" =~ "logs:read" ]]
}

@test "rbac_define_role: fails on empty role name" {
    run rbac_define_role "" "files:read"
    [[ "$status" -eq 1 ]]
}

@test "rbac_define_role: fails on invalid role name" {
    run rbac_define_role "123invalid" "files:read"
    [[ "$status" -eq 1 ]]

    run rbac_define_role "has spaces" "files:read"
    [[ "$status" -eq 1 ]]
}

@test "rbac_define_role: fails on invalid permission format" {
    run rbac_define_role "test" "invalid"
    [[ "$status" -eq 1 ]]

    run rbac_define_role "test" "no-colon"
    [[ "$status" -eq 1 ]]
}

@test "rbac_define_role: accepts wildcard permissions" {
    rbac_define_role "admin" "*:*"
    rbac_define_role "file-admin" "files:*"
    rbac_define_role "reader" "*:read"

    run rbac_list_roles
    [[ "$output" =~ "admin" ]]
    [[ "$output" =~ "file-admin" ]]
    [[ "$output" =~ "reader" ]]
}

@test "rbac_define_role: replaces existing role" {
    rbac_define_role "reader" "files:read"
    rbac_define_role "reader" "logs:read"

    run rbac_get_role "reader"
    [[ "$output" =~ "logs:read" ]]
    # Should only have new permission, not old
    [[ ! "$output" =~ '"permissions":.*"files:read"' ]]
}

@test "rbac_delete_role: removes role" {
    rbac_define_role "temp-role" "files:read"
    rbac_delete_role "temp-role"

    run rbac_list_roles
    [[ ! "$output" =~ "temp-role" ]]
}

@test "rbac_delete_role: removes role from subjects" {
    rbac_define_role "test-role" "files:read"
    rbac_assign_role "subject-1" "test-role"

    rbac_delete_role "test-role"

    run rbac_get_roles "subject-1"
    [[ "$status" -eq 1 ]] || [[ -z "${output// /}" ]]
}

@test "rbac_delete_role: fails on nonexistent role" {
    run rbac_delete_role "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "rbac_get_role: returns role as JSON" {
    rbac_define_role "api-reader" "api:read" "api:list"

    run rbac_get_role "api-reader"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"name":"api-reader"' ]]
    [[ "$output" == *'"permissions":['* ]]
    [[ "$output" =~ '"api:read"' ]]
}

@test "rbac_get_role: returns 1 for nonexistent role" {
    run rbac_get_role "nonexistent"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 3: ROLE INHERITANCE
# =============================================================================

@test "rbac_inherit_role: sets up inheritance" {
    rbac_define_role "base" "files:read"
    rbac_define_role "extended" "files:write"
    rbac_inherit_role "extended" "base"

    run rbac_get_role "extended"
    [[ "$output" == *'"inherits":["base"]'* ]]
}

@test "rbac_inherit_role: effective permissions include inherited" {
    rbac_define_role "base" "files:read" "logs:read"
    rbac_define_role "extended" "files:write"
    rbac_inherit_role "extended" "base"

    run rbac_get_role "extended"
    # Effective permissions should include both direct and inherited
    [[ "$output" =~ '"effective_permissions"' ]]
    [[ "$output" =~ '"files:read"' ]]
    [[ "$output" =~ '"files:write"' ]]
}

@test "rbac_inherit_role: multi-level inheritance" {
    rbac_define_role "level1" "perm:one"
    rbac_define_role "level2" "perm:two"
    rbac_define_role "level3" "perm:three"

    rbac_inherit_role "level2" "level1"
    rbac_inherit_role "level3" "level2"

    run rbac_get_role "level3"
    [[ "$output" =~ '"perm:one"' ]]
    [[ "$output" =~ '"perm:two"' ]]
    [[ "$output" =~ '"perm:three"' ]]
}

@test "rbac_inherit_role: handles circular inheritance safely" {
    rbac_define_role "role-a" "perm:a"
    rbac_define_role "role-b" "perm:b"

    rbac_inherit_role "role-a" "role-b"
    rbac_inherit_role "role-b" "role-a"

    # Should not infinite loop
    run rbac_get_role "role-a"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"perm:a"' ]]
    [[ "$output" =~ '"perm:b"' ]]
}

# =============================================================================
# CATEGORY 4: SUBJECT MANAGEMENT
# =============================================================================

@test "rbac_assign_role: assigns role to subject" {
    rbac_define_role "operator" "system:manage"
    rbac_assign_role "agent-123" "operator"

    run rbac_get_roles "agent-123"
    [[ "$output" =~ "operator" ]]
}

@test "rbac_assign_role: fails on nonexistent role" {
    run rbac_assign_role "agent-123" "nonexistent"
    [[ "$status" -eq 1 ]]
}

@test "rbac_assign_role: idempotent for same role" {
    rbac_define_role "reader" "files:read"
    rbac_assign_role "agent-1" "reader"
    rbac_assign_role "agent-1" "reader"

    run rbac_get_roles "agent-1"
    # Should have "reader" only once
    local count
    count=$(grep -o "reader" <<< "$output" | wc -l)
    [[ "$count" -eq 1 ]]
}

@test "rbac_assign_role: multiple roles to same subject" {
    rbac_define_role "reader" "files:read"
    rbac_define_role "writer" "files:write"

    rbac_assign_role "agent-1" "reader"
    rbac_assign_role "agent-1" "writer"

    run rbac_get_roles "agent-1"
    [[ "$output" =~ "reader" ]]
    [[ "$output" =~ "writer" ]]
}

@test "rbac_revoke_role: removes role from subject" {
    rbac_define_role "temp" "files:read"
    rbac_assign_role "agent-1" "temp"
    rbac_revoke_role "agent-1" "temp"

    run rbac_get_roles "agent-1"
    [[ "$status" -eq 1 ]] || [[ ! "$output" =~ "temp" ]]
}

@test "rbac_revoke_role: fails if role not assigned" {
    rbac_define_role "role1" "files:read"
    rbac_define_role "role2" "files:write"
    rbac_assign_role "agent-1" "role1"

    run rbac_revoke_role "agent-1" "role2"
    [[ "$status" -eq 1 ]]
}

@test "rbac_list_subjects: lists all subjects" {
    rbac_define_role "role" "files:read"
    rbac_assign_role "subject-a" "role"
    rbac_assign_role "subject-b" "role"
    rbac_assign_role "subject-c" "role"

    run rbac_list_subjects
    [[ "$output" =~ "subject-a" ]]
    [[ "$output" =~ "subject-b" ]]
    [[ "$output" =~ "subject-c" ]]
}

# =============================================================================
# CATEGORY 5: PERMISSION CHECKING
# =============================================================================

@test "rbac_check_permission: grants direct permission" {
    rbac_define_role "reader" "files:read" "logs:read"
    rbac_assign_role "agent-1" "reader"

    rbac_check_permission "agent-1" "files:read"
    [[ $? -eq 0 ]]

    rbac_check_permission "agent-1" "logs:read"
    [[ $? -eq 0 ]]
}

@test "rbac_check_permission: denies missing permission" {
    rbac_define_role "reader" "files:read"
    rbac_assign_role "agent-1" "reader"

    run rbac_check_permission "agent-1" "files:write"
    [[ "$status" -eq 1 ]]
}

@test "rbac_check_permission: denies for unknown subject" {
    run rbac_check_permission "unknown-agent" "files:read"
    [[ "$status" -eq 1 ]]
}

@test "rbac_check_permission: grants inherited permission" {
    rbac_define_role "base" "files:read"
    rbac_define_role "extended" "files:write"
    rbac_inherit_role "extended" "base"

    rbac_assign_role "agent-1" "extended"

    # Direct permission
    rbac_check_permission "agent-1" "files:write"
    [[ $? -eq 0 ]]

    # Inherited permission
    rbac_check_permission "agent-1" "files:read"
    [[ $? -eq 0 ]]
}

@test "rbac_check_permission: uses permission cache" {
    rbac_define_role "reader" "files:read"
    rbac_assign_role "agent-1" "reader"

    # First check populates cache
    rbac_check_permission "agent-1" "files:read"

    # Get stats to verify cache
    run rbac_stats
    [[ "$output" =~ '"cache_entries":' ]]
    # Cache should have at least 1 entry
    [[ "$output" =~ \"cache_entries\":([1-9][0-9]*) ]]
}

# =============================================================================
# CATEGORY 6: WILDCARD PERMISSIONS
# =============================================================================

@test "wildcard: *:* grants all permissions" {
    rbac_define_role "admin" "*:*"
    rbac_assign_role "super-user" "admin"

    rbac_check_permission "super-user" "files:read"
    [[ $? -eq 0 ]]

    rbac_check_permission "super-user" "secrets:write"
    [[ $? -eq 0 ]]

    rbac_check_permission "super-user" "anything:everything"
    [[ $? -eq 0 ]]
}

@test "wildcard: resource:* grants all actions on resource" {
    rbac_define_role "file-admin" "files:*"
    rbac_assign_role "file-manager" "file-admin"

    rbac_check_permission "file-manager" "files:read"
    [[ $? -eq 0 ]]

    rbac_check_permission "file-manager" "files:write"
    [[ $? -eq 0 ]]

    rbac_check_permission "file-manager" "files:delete"
    [[ $? -eq 0 ]]

    # But not other resources
    run rbac_check_permission "file-manager" "secrets:read"
    [[ "$status" -eq 1 ]]
}

@test "wildcard: *:action grants action on all resources" {
    rbac_define_role "reader" "*:read"
    rbac_assign_role "observer" "reader"

    rbac_check_permission "observer" "files:read"
    [[ $? -eq 0 ]]

    rbac_check_permission "observer" "logs:read"
    [[ $? -eq 0 ]]

    rbac_check_permission "observer" "secrets:read"
    [[ $? -eq 0 ]]

    # But not write actions
    run rbac_check_permission "observer" "files:write"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 7: rbac_require_permission
# =============================================================================

@test "rbac_require_permission: continues on granted permission" {
    rbac_define_role "reader" "files:read"
    rbac_assign_role "test-agent" "reader"

    export RBAC_SUBJECT="test-agent"
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/rbac.sh"; rbac_define_role "reader" "files:read"; rbac_assign_role "test-agent" "reader"; RBAC_SUBJECT="test-agent"; rbac_require_permission "files:read"; echo "passed"'

    [[ "$output" =~ "passed" ]]
}

@test "rbac_require_permission: exits 77 on denied permission" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/rbac.sh"; rbac_define_role "reader" "files:read"; rbac_assign_role "test-agent" "reader"; RBAC_SUBJECT="test-agent"; rbac_require_permission "files:write"; echo "should not reach"'

    [[ "$status" -eq 77 ]]
    [[ ! "$output" =~ "should not reach" ]]
}

@test "rbac_require_permission: uses anonymous for unset subject" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/rbac.sh"; unset RBAC_SUBJECT; rbac_require_permission "files:read"; echo "should not reach"'

    [[ "$status" -eq 77 ]]
}

# =============================================================================
# CATEGORY 8: AUDIT LOGGING
# =============================================================================

@test "rbac_set_audit_log: enables audit logging" {
    rbac_set_audit_log "$TEST_TMPDIR/audit.log"

    run rbac_stats
    [[ "$output" =~ '"audit_enabled":true' ]]
}

@test "rbac_set_audit_log: fails on invalid directory" {
    run rbac_set_audit_log "/nonexistent/dir/audit.log"
    [[ "$status" -eq 1 ]]
}

@test "rbac_audit_access: writes to audit log" {
    rbac_set_audit_log "$TEST_TMPDIR/audit.log"
    rbac_audit_access "agent-1" "files" "read" "granted" "/path/to/file"

    [[ -f "$TEST_TMPDIR/audit.log" ]]
    run cat "$TEST_TMPDIR/audit.log"
    [[ "$output" =~ "agent-1" ]]
    [[ "$output" =~ "files" ]]
    [[ "$output" =~ "read" ]]
    [[ "$output" =~ "granted" ]]
}

@test "rbac_audit_access: handles pipe characters in context" {
    rbac_set_audit_log "$TEST_TMPDIR/audit.log"
    rbac_audit_access "agent-1" "cmd" "exec" "denied" "echo foo|bar"

    run cat "$TEST_TMPDIR/audit.log"
    # Pipe should be escaped
    [[ "$output" =~ "echo foo" ]]
}

# =============================================================================
# CATEGORY 9: IMPORT/EXPORT
# =============================================================================

@test "rbac_export: writes JSON config" {
    rbac_define_role "reader" "files:read" "logs:read"
    rbac_define_role "admin" "*:*"
    rbac_assign_role "agent-1" "reader"
    rbac_assign_role "agent-2" "admin"

    rbac_export "$TEST_TMPDIR/export.json"

    [[ -f "$TEST_TMPDIR/export.json" ]]

    run cat "$TEST_TMPDIR/export.json"
    [[ "$output" =~ '"roles":' ]]
    [[ "$output" =~ '"subjects":' ]]
    [[ "$output" =~ '"reader"' ]]
    [[ "$output" =~ '"admin"' ]]
    [[ "$output" =~ '"agent-1"' ]]
}

@test "rbac_import: loads JSON config" {
    # Skip if jq not available
    command -v jq &>/dev/null || skip "jq not installed"

    cat > "$TEST_TMPDIR/import.json" << 'EOF'
{
  "roles": {
    "operator": {
      "permissions": ["system:manage", "system:view"],
      "description": "System operator"
    }
  },
  "subjects": {
    "ops-agent": {
      "roles": ["operator"]
    }
  }
}
EOF

    rbac_import "$TEST_TMPDIR/import.json"

    run rbac_list_roles
    [[ "$output" =~ "operator" ]]

    run rbac_get_roles "ops-agent"
    [[ "$output" =~ "operator" ]]
}

@test "rbac_export/import: round-trip preserves data" {
    # Skip if jq not available
    command -v jq &>/dev/null || skip "jq not installed"

    rbac_define_role "complex-role" "resource1:action1" "resource2:action2"
    rbac_assign_role "subject-x" "complex-role"

    rbac_export "$TEST_TMPDIR/roundtrip.json"
    rbac_reset
    rbac_import "$TEST_TMPDIR/roundtrip.json"

    run rbac_get_roles "subject-x"
    [[ "$output" =~ "complex-role" ]]

    rbac_check_permission "subject-x" "resource1:action1"
    [[ $? -eq 0 ]]
}

@test "rbac_import: fails on missing file" {
    run rbac_import "/nonexistent/file.json"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 10: UTILITIES
# =============================================================================

@test "rbac_stats: returns JSON stats" {
    rbac_define_role "role1" "files:read"
    rbac_define_role "role2" "logs:read"
    rbac_assign_role "subject1" "role1"

    run rbac_stats
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ '"role_count":2' ]]
    [[ "$output" =~ '"subject_count":1' ]]
    [[ "$output" =~ '"cache_entries":' ]]
}

@test "rbac_clear_cache: empties permission cache" {
    rbac_define_role "reader" "files:read"
    rbac_assign_role "agent-1" "reader"

    # Populate cache
    rbac_check_permission "agent-1" "files:read"

    run rbac_stats
    [[ "$output" =~ \"cache_entries\":([1-9][0-9]*) ]]

    rbac_clear_cache

    run rbac_stats
    [[ "$output" =~ '"cache_entries":0' ]]
}

@test "rbac_get_permissions: lists all effective permissions" {
    rbac_define_role "base" "perm:a" "perm:b"
    rbac_define_role "ext" "perm:c"
    rbac_inherit_role "ext" "base"
    rbac_assign_role "agent-1" "ext"

    run rbac_get_permissions "agent-1"
    [[ "$output" =~ "perm:a" ]]
    [[ "$output" =~ "perm:b" ]]
    [[ "$output" =~ "perm:c" ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES
# =============================================================================

@test "edge: role with no permissions" {
    rbac_define_role "empty-role"
    rbac_assign_role "agent-1" "empty-role"

    run rbac_check_permission "agent-1" "any:perm"
    [[ "$status" -eq 1 ]]
}

@test "edge: subject with multiple roles combines permissions" {
    rbac_define_role "role-a" "res:action-a"
    rbac_define_role "role-b" "res:action-b"

    rbac_assign_role "multi-role-agent" "role-a"
    rbac_assign_role "multi-role-agent" "role-b"

    rbac_check_permission "multi-role-agent" "res:action-a"
    [[ $? -eq 0 ]]

    rbac_check_permission "multi-role-agent" "res:action-b"
    [[ $? -eq 0 ]]
}

@test "edge: deleting role updates cache" {
    rbac_define_role "temp" "files:read"
    rbac_assign_role "agent-1" "temp"

    # Populate cache
    rbac_check_permission "agent-1" "files:read"
    [[ $? -eq 0 ]]

    # Delete role
    rbac_delete_role "temp"

    # Permission should now be denied
    run rbac_check_permission "agent-1" "files:read"
    [[ "$status" -eq 1 ]]
}

@test "edge: role names with hyphens and underscores" {
    rbac_define_role "my-role_v2" "files:read"
    rbac_assign_role "agent_v1-test" "my-role_v2"

    rbac_check_permission "agent_v1-test" "files:read"
    [[ $? -eq 0 ]]
}

@test "edge: permission format validation" {
    # Valid formats
    run rbac_define_role "test1" "a:b"
    [[ "$status" -eq 0 ]]

    run rbac_define_role "test2" "resource-name:action_name"
    [[ "$status" -eq 0 ]]

    run rbac_define_role "test3" "*:*"
    [[ "$status" -eq 0 ]]

    run rbac_define_role "test4" "file_ops:read-write"
    [[ "$status" -eq 0 ]]

    # Invalid formats should fail
    run rbac_define_role "bad1" "no-colon"
    [[ "$status" -eq 1 ]]

    run rbac_define_role "bad2" ":"
    [[ "$status" -eq 1 ]]

    run rbac_define_role "bad3" "too:many:colons"
    [[ "$status" -eq 1 ]]

    run rbac_define_role "bad4" ":empty-resource"
    [[ "$status" -eq 1 ]]

    run rbac_define_role "bad5" "empty-action:"
    [[ "$status" -eq 1 ]]
}

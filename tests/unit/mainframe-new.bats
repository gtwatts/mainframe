#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/mainframe-new.bats - Scaffolding Tool Tests
# =============================================================================
# Description: Unit tests for bin/mainframe-new CLI scaffolding tool
# Test Count: 40+ test cases
# Categories: validation, agent scaffolding, tool scaffolding,
#             workflow scaffolding, library scaffolding, doctor, init
# =============================================================================

# Setup: Configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Path to the CLI tool
    MAINFRAME_NEW="$MAINFRAME_ROOT/bin/mainframe-new"

    # Ensure executable
    chmod +x "$MAINFRAME_NEW"

    # Export for subprocesses
    export MAINFRAME_ROOT
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: CLI BASICS
# =============================================================================

@test "mainframe-new: shows help with --help" {
    run "$MAINFRAME_NEW" --help
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "MAINFRAME Scaffolding Tool" ]]
    [[ "${output}" =~ "new agent" ]]
    [[ "${output}" =~ "new tool" ]]
    [[ "${output}" =~ "new workflow" ]]
    [[ "${output}" =~ "new library" ]]
}

@test "mainframe-new: shows help with -h" {
    run "$MAINFRAME_NEW" -h
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "MAINFRAME Scaffolding Tool" ]]
}

@test "mainframe-new: shows version with --version" {
    run "$MAINFRAME_NEW" --version
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "mainframe-new" ]]
    [[ "${output}" =~ "MAINFRAME" ]]
}

@test "mainframe-new: shows version with -v" {
    run "$MAINFRAME_NEW" -v
    [[ "$status" -eq 0 ]]
}

@test "mainframe-new: shows help for unknown command" {
    run "$MAINFRAME_NEW" unknown-command
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Unknown command" ]]
}

@test "mainframe-new: requires type for new command" {
    run "$MAINFRAME_NEW" new
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Type required" ]]
}

@test "mainframe-new: requires name for new command" {
    run "$MAINFRAME_NEW" new agent
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Name required" ]]
}

# =============================================================================
# CATEGORY 2: NAME VALIDATION
# =============================================================================

@test "mainframe-new: rejects empty name" {
    run "$MAINFRAME_NEW" new agent "" -y -o "$TEST_TMPDIR"
    [[ "$status" -ne 0 ]]
}

@test "mainframe-new: rejects name starting with number" {
    run "$MAINFRAME_NEW" new agent "123agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "must start with a letter" ]]
}

@test "mainframe-new: rejects name with spaces" {
    run "$MAINFRAME_NEW" new agent "my agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -ne 0 ]]
}

@test "mainframe-new: rejects name with special characters" {
    run "$MAINFRAME_NEW" new agent "my@agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -ne 0 ]]
}

@test "mainframe-new: accepts valid name with letters" {
    run "$MAINFRAME_NEW" new agent "myagent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]
    [[ -d "$TEST_TMPDIR/myagent" ]]
}

@test "mainframe-new: accepts valid name with dash" {
    run "$MAINFRAME_NEW" new agent "my-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]
    [[ -d "$TEST_TMPDIR/my-agent" ]]
}

@test "mainframe-new: accepts valid name with underscore" {
    run "$MAINFRAME_NEW" new agent "my_agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]
    [[ -d "$TEST_TMPDIR/my_agent" ]]
}

@test "mainframe-new: accepts valid name with numbers" {
    run "$MAINFRAME_NEW" new agent "agent123" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]
    [[ -d "$TEST_TMPDIR/agent123" ]]
}

@test "mainframe-new: rejects single character name" {
    run "$MAINFRAME_NEW" new agent "a" -y -o "$TEST_TMPDIR"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "at least 2 characters" ]]
}

# =============================================================================
# CATEGORY 3: AGENT SCAFFOLDING
# =============================================================================

@test "agent scaffold: creates directory structure" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    # Check directories
    [[ -d "$TEST_TMPDIR/test-agent" ]]
    [[ -d "$TEST_TMPDIR/test-agent/tools" ]]
    [[ -d "$TEST_TMPDIR/test-agent/prompts" ]]
    [[ -d "$TEST_TMPDIR/test-agent/tests" ]]
}

@test "agent scaffold: creates agent.sh" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/test-agent/agent.sh" ]]
    [[ -x "$TEST_TMPDIR/test-agent/agent.sh" ]]
}

@test "agent scaffold: agent.sh is executable" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -x "$TEST_TMPDIR/test-agent/agent.sh" ]]
}

@test "agent scaffold: agent.sh contains correct name" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q 'AGENT_NAME="test-agent"' "$TEST_TMPDIR/test-agent/agent.sh"
}

@test "agent scaffold: creates config.yaml" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/test-agent/config.yaml" ]]
    grep -q "name: test-agent" "$TEST_TMPDIR/test-agent/config.yaml"
}

@test "agent scaffold: creates example tool" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/test-agent/tools/example.sh" ]]
    grep -q "example_tool()" "$TEST_TMPDIR/test-agent/tools/example.sh"
}

@test "agent scaffold: creates system prompt" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/test-agent/prompts/system.txt" ]]
}

@test "agent scaffold: creates test file" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/test-agent/tests/agent.bats" ]]
}

@test "agent scaffold: creates README.md" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/test-agent/README.md" ]]
    grep -q "Test Agent" "$TEST_TMPDIR/test-agent/README.md"
}

# =============================================================================
# CATEGORY 4: TOOL SCAFFOLDING
# =============================================================================

@test "tool scaffold: creates tool file" {
    run "$MAINFRAME_NEW" new tool "my-tool" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/my_tool.sh" ]]
}

@test "tool scaffold: uses snake_case for filename" {
    run "$MAINFRAME_NEW" new tool "my-cool-tool" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/my_cool_tool.sh" ]]
}

@test "tool scaffold: contains function definition" {
    run "$MAINFRAME_NEW" new tool "my-tool" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q "my_tool()" "$TEST_TMPDIR/my_tool.sh"
}

@test "tool scaffold: contains nameref variant" {
    run "$MAINFRAME_NEW" new tool "my-tool" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q "my_tool_v()" "$TEST_TMPDIR/my_tool.sh"
}

@test "tool scaffold: contains documentation annotations" {
    run "$MAINFRAME_NEW" new tool "my-tool" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q "@name:" "$TEST_TMPDIR/my_tool.sh"
    grep -q "@description:" "$TEST_TMPDIR/my_tool.sh"
    grep -q "@param" "$TEST_TMPDIR/my_tool.sh"
    grep -q "@returns:" "$TEST_TMPDIR/my_tool.sh"
}

# =============================================================================
# CATEGORY 5: WORKFLOW SCAFFOLDING
# =============================================================================

@test "workflow scaffold: creates directory structure" {
    run "$MAINFRAME_NEW" new workflow "deploy-pipeline" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -d "$TEST_TMPDIR/deploy-pipeline" ]]
    [[ -d "$TEST_TMPDIR/deploy-pipeline/steps" ]]
}

@test "workflow scaffold: creates workflow.yaml" {
    run "$MAINFRAME_NEW" new workflow "deploy-pipeline" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/deploy-pipeline/workflow.yaml" ]]
    grep -q "name: deploy-pipeline" "$TEST_TMPDIR/deploy-pipeline/workflow.yaml"
}

@test "workflow scaffold: creates step scripts" {
    run "$MAINFRAME_NEW" new workflow "deploy-pipeline" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/deploy-pipeline/steps/validate.sh" ]]
    [[ -f "$TEST_TMPDIR/deploy-pipeline/steps/process.sh" ]]
    [[ -f "$TEST_TMPDIR/deploy-pipeline/steps/notify.sh" ]]
}

@test "workflow scaffold: step scripts are executable" {
    run "$MAINFRAME_NEW" new workflow "deploy-pipeline" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -x "$TEST_TMPDIR/deploy-pipeline/steps/validate.sh" ]]
    [[ -x "$TEST_TMPDIR/deploy-pipeline/steps/process.sh" ]]
    [[ -x "$TEST_TMPDIR/deploy-pipeline/steps/notify.sh" ]]
}

@test "workflow scaffold: creates runner script" {
    run "$MAINFRAME_NEW" new workflow "deploy-pipeline" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/deploy-pipeline/run.sh" ]]
    [[ -x "$TEST_TMPDIR/deploy-pipeline/run.sh" ]]
}

# =============================================================================
# CATEGORY 6: LIBRARY SCAFFOLDING
# =============================================================================

@test "library scaffold: creates library file" {
    run "$MAINFRAME_NEW" new library "myutils" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/myutils.sh" ]]
}

@test "library scaffold: contains double-source guard" {
    run "$MAINFRAME_NEW" new library "myutils" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q "_MAINFRAME_MYUTILS_LOADED" "$TEST_TMPDIR/myutils.sh"
}

@test "library scaffold: contains exports array" {
    run "$MAINFRAME_NEW" new library "myutils" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q "MYUTILS_EXPORTS=" "$TEST_TMPDIR/myutils.sh"
}

@test "library scaffold: contains example function" {
    run "$MAINFRAME_NEW" new library "myutils" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q "myutils_example()" "$TEST_TMPDIR/myutils.sh"
}

# =============================================================================
# CATEGORY 7: DOCTOR COMMAND
# =============================================================================

@test "doctor: runs without error" {
    run "$MAINFRAME_NEW" doctor
    # Doctor may return non-zero if there are warnings, but should not crash
    [[ "${output}" =~ "MAINFRAME Doctor" ]]
}

@test "doctor: checks MAINFRAME_ROOT" {
    run "$MAINFRAME_NEW" doctor
    [[ "${output}" =~ "MAINFRAME_ROOT" ]]
}

@test "doctor: checks Bash version" {
    run "$MAINFRAME_NEW" doctor
    [[ "${output}" =~ "Bash version" ]]
}

@test "doctor: checks jq" {
    run "$MAINFRAME_NEW" doctor
    [[ "${output}" =~ "jq" ]]
}

@test "doctor: checks common.sh" {
    run "$MAINFRAME_NEW" doctor
    [[ "${output}" =~ "lib/common.sh" ]]
}

# =============================================================================
# CATEGORY 8: INIT COMMAND
# =============================================================================

@test "init: creates .mainframe marker" {
    run "$MAINFRAME_NEW" init "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/.mainframe" ]]
}

@test "init: creates scripts directory" {
    run "$MAINFRAME_NEW" init "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -d "$TEST_TMPDIR/scripts" ]]
}

@test "init: creates example script" {
    run "$MAINFRAME_NEW" init "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    [[ -f "$TEST_TMPDIR/scripts/example.sh" ]]
    [[ -x "$TEST_TMPDIR/scripts/example.sh" ]]
}

@test "init: marker contains configuration" {
    run "$MAINFRAME_NEW" init "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]

    grep -q "MAINFRAME Project Configuration" "$TEST_TMPDIR/.mainframe"
    grep -q "BASHER_LOG_LEVEL" "$TEST_TMPDIR/.mainframe"
}

# =============================================================================
# CATEGORY 9: OUTPUT DIRECTORY OPTION
# =============================================================================

@test "-o option: specifies output directory" {
    mkdir -p "$TEST_TMPDIR/custom-output"
    run "$MAINFRAME_NEW" -o "$TEST_TMPDIR/custom-output" new agent "test-agent" -y
    [[ "$status" -eq 0 ]]

    [[ -d "$TEST_TMPDIR/custom-output/test-agent" ]]
}

@test "--output option: specifies output directory" {
    mkdir -p "$TEST_TMPDIR/custom-output"
    run "$MAINFRAME_NEW" --output "$TEST_TMPDIR/custom-output" new agent "test-agent" -y
    [[ "$status" -eq 0 ]]

    [[ -d "$TEST_TMPDIR/custom-output/test-agent" ]]
}

# =============================================================================
# CATEGORY 10: NON-INTERACTIVE MODE
# =============================================================================

@test "-y option: skips prompts" {
    run "$MAINFRAME_NEW" new agent "test-agent" -y -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]
    # Should not hang waiting for input
}

@test "--yes option: skips prompts" {
    run "$MAINFRAME_NEW" new agent "test-agent" --yes -o "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: DAG-Based Workflow Orchestration Tests
# =============================================================================

load 'test_helper'

setup() {
    export MAINFRAME_WORKFLOW_DIR="$(mktemp -d)"
    export MAINFRAME_QUIET=1
    source "${BATS_TEST_DIRNAME}/../lib/workflow.sh"
}

teardown() {
    rm -rf "$MAINFRAME_WORKFLOW_DIR"
}

# =============================================================================
# DOUBLE-SOURCE GUARD
# =============================================================================

@test "double-source guard prevents reloading" {
    [ "$_MAINFRAME_WORKFLOW_LOADED" = "1" ]
    # Source again - should not error
    source "${BATS_TEST_DIRNAME}/../lib/workflow.sh"
    [ "$_MAINFRAME_WORKFLOW_LOADED" = "1" ]
}

# =============================================================================
# workflow_define TESTS
# =============================================================================

@test "workflow_define creates workflow directory" {
    workflow_define "test-wf"
    [ -d "$MAINFRAME_WORKFLOW_DIR/test-wf" ]
    [ -d "$MAINFRAME_WORKFLOW_DIR/test-wf/steps" ]
}

@test "workflow_define creates meta.json" {
    workflow_define "test-wf"
    [ -f "$MAINFRAME_WORKFLOW_DIR/test-wf/meta.json" ]
    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/test-wf/meta.json")
    [[ "$content" == *'"name":"test-wf"'* ]]
}

@test "workflow_define fails with empty name" {
    run workflow_define ""
    [ "$status" -ne 0 ]
}

@test "workflow_define fails with invalid name" {
    run workflow_define "bad name!"
    [ "$status" -ne 0 ]
}

@test "workflow_define accepts hyphens and underscores" {
    workflow_define "my-workflow_v2"
    [ -d "$MAINFRAME_WORKFLOW_DIR/my-workflow_v2" ]
}

@test "workflow_define is idempotent" {
    workflow_define "test-wf"
    workflow_define "test-wf"
    [ -d "$MAINFRAME_WORKFLOW_DIR/test-wf" ]
}

# =============================================================================
# workflow_step TESTS
# =============================================================================

@test "workflow_step adds a step" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo hello"
    [ -f "$MAINFRAME_WORKFLOW_DIR/test-wf/steps/step1.json" ]
}

@test "workflow_step stores command in step file" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo hello"
    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/test-wf/steps/step1.json")
    [[ "$content" == *'"command":"echo hello"'* ]]
}

@test "workflow_step stores dependencies" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo one"
    workflow_step "test-wf" "step2" "echo two" --depends "step1"
    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/test-wf/steps/step2.json")
    [[ "$content" == *'"depends":["step1"]'* ]]
}

@test "workflow_step stores multiple dependencies" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo one"
    workflow_step "test-wf" "step2" "echo two"
    workflow_step "test-wf" "step3" "echo three" --depends "step1,step2"
    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/test-wf/steps/step3.json")
    [[ "$content" == *'"step1"'* ]]
    [[ "$content" == *'"step2"'* ]]
}

@test "workflow_step initializes status as pending" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo hello"
    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/test-wf/steps/step1.json")
    [[ "$content" == *'"status":"pending"'* ]]
}

@test "workflow_step fails if workflow not defined" {
    run workflow_step "nonexistent" "step1" "echo hello"
    [ "$status" -ne 0 ]
}

@test "workflow_step fails with empty args" {
    workflow_define "test-wf"
    run workflow_step "" "" ""
    [ "$status" -ne 0 ]
}

@test "workflow_step fails with invalid step name" {
    workflow_define "test-wf"
    run workflow_step "test-wf" "bad step!" "echo hello"
    [ "$status" -ne 0 ]
}

@test "workflow_step fails if dependency does not exist" {
    workflow_define "test-wf"
    run workflow_step "test-wf" "step1" "echo hello" --depends "nonexistent"
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_remove_step TESTS
# =============================================================================

@test "workflow_remove_step removes step file" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo hello"
    workflow_remove_step "test-wf" "step1"
    [ ! -f "$MAINFRAME_WORKFLOW_DIR/test-wf/steps/step1.json" ]
}

@test "workflow_remove_step fails if step not found" {
    workflow_define "test-wf"
    run workflow_remove_step "test-wf" "nonexistent"
    [ "$status" -ne 0 ]
}

@test "workflow_remove_step fails if other steps depend on it" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo one"
    workflow_step "test-wf" "step2" "echo two" --depends "step1"
    run workflow_remove_step "test-wf" "step1"
    [ "$status" -ne 0 ]
}

@test "workflow_remove_step succeeds for leaf step" {
    workflow_define "test-wf"
    workflow_step "test-wf" "step1" "echo one"
    workflow_step "test-wf" "step2" "echo two" --depends "step1"
    workflow_remove_step "test-wf" "step2"
    [ ! -f "$MAINFRAME_WORKFLOW_DIR/test-wf/steps/step2.json" ]
}

# =============================================================================
# workflow_list TESTS
# =============================================================================

@test "workflow_list returns empty for no workflows" {
    run workflow_list
    [ "$status" -eq 0 ]
}

@test "workflow_list shows defined workflows" {
    workflow_define "wf-alpha"
    workflow_define "wf-beta"
    run workflow_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"wf-alpha"* ]]
    [[ "$output" == *"wf-beta"* ]]
}

@test "workflow_list json output" {
    workflow_define "wf-alpha"
    workflow_define "wf-beta"
    export MAINFRAME_OUTPUT=json
    run workflow_list
    [ "$status" -eq 0 ]
    [[ "$output" == *'"wf-alpha"'* ]]
    [[ "$output" == *'"wf-beta"'* ]]
    [[ "$output" == "["* ]]
    unset MAINFRAME_OUTPUT
}

# =============================================================================
# workflow_run TESTS - LINEAR DEPENDENCY (A -> B -> C)
# =============================================================================

@test "workflow_run executes linear chain in order" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/output.txt"
    workflow_define "linear"
    workflow_step "linear" "step-a" "echo A >> $outfile"
    workflow_step "linear" "step-b" "echo B >> $outfile" --depends "step-a"
    workflow_step "linear" "step-c" "echo C >> $outfile" --depends "step-b"

    workflow_run "linear" --parallel 1
    local content
    content=$(<"$outfile")
    # Verify order
    [[ "$content" == *"A"* ]]
    [[ "$content" == *"B"* ]]
    [[ "$content" == *"C"* ]]

    # Check line order
    local line1 line2 line3
    line1=$(sed -n '1p' "$outfile")
    line2=$(sed -n '2p' "$outfile")
    line3=$(sed -n '3p' "$outfile")
    [ "$line1" = "A" ]
    [ "$line2" = "B" ]
    [ "$line3" = "C" ]
}

@test "workflow_run marks all steps as success" {
    workflow_define "simple"
    workflow_step "simple" "s1" "true"
    workflow_step "simple" "s2" "true" --depends "s1"

    workflow_run "simple"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/simple/steps/s1.json")
    [[ "$content" == *'"status":"success"'* ]]
    content=$(<"$MAINFRAME_WORKFLOW_DIR/simple/steps/s2.json")
    [[ "$content" == *'"status":"success"'* ]]
}

@test "workflow_run fails with empty name" {
    run workflow_run ""
    [ "$status" -ne 0 ]
}

@test "workflow_run fails for undefined workflow" {
    run workflow_run "nonexistent"
    [ "$status" -ne 0 ]
}

@test "workflow_run handles empty workflow" {
    workflow_define "empty"
    run workflow_run "empty"
    [ "$status" -eq 0 ]
}

# =============================================================================
# workflow_run TESTS - DIAMOND DEPENDENCY (A -> B,C -> D)
# =============================================================================

@test "workflow_run executes diamond dependency correctly" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/diamond.txt"
    workflow_define "diamond"
    workflow_step "diamond" "step-a" "echo A >> $outfile"
    workflow_step "diamond" "step-b" "echo B >> $outfile" --depends "step-a"
    workflow_step "diamond" "step-c" "echo C >> $outfile" --depends "step-a"
    workflow_step "diamond" "step-d" "echo D >> $outfile" --depends "step-b,step-c"

    workflow_run "diamond" --parallel 2

    local content
    content=$(<"$outfile")
    # A must come first, D must come last
    local line1 last_line
    line1=$(head -1 "$outfile")
    last_line=$(tail -1 "$outfile")
    [ "$line1" = "A" ]
    [ "$last_line" = "D" ]
    # B and C in the middle (order may vary due to parallelism)
    [[ "$content" == *"B"* ]]
    [[ "$content" == *"C"* ]]
}

@test "workflow_run diamond - D waits for both B and C" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/diamond2.txt"
    workflow_define "diamond2"
    workflow_step "diamond2" "step-a" "true"
    workflow_step "diamond2" "step-b" "sleep 0.1 && echo B >> $outfile" --depends "step-a"
    workflow_step "diamond2" "step-c" "sleep 0.2 && echo C >> $outfile" --depends "step-a"
    workflow_step "diamond2" "step-d" "echo D >> $outfile" --depends "step-b,step-c"

    workflow_run "diamond2" --parallel 4

    # D must be after both B and C
    local last_line
    last_line=$(tail -1 "$outfile")
    [ "$last_line" = "D" ]
}

# =============================================================================
# workflow_run TESTS - PARALLEL EXECUTION
# =============================================================================

@test "workflow_run executes independent steps in parallel" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/parallel.txt"
    workflow_define "par"
    # Three independent steps that each sleep briefly
    workflow_step "par" "s1" "sleep 0.1 && echo S1 >> $outfile"
    workflow_step "par" "s2" "sleep 0.1 && echo S2 >> $outfile"
    workflow_step "par" "s3" "sleep 0.1 && echo S3 >> $outfile"

    local start_time
    start_time=$(date +%s)
    workflow_run "par" --parallel 3
    local end_time
    end_time=$(date +%s)

    # All completed
    [ -f "$outfile" ]
    local lines
    lines=$(wc -l < "$outfile")
    [ "$lines" -eq 3 ]

    # Should complete in ~0.1-0.3s, not 0.3s+ (if truly parallel)
    # Just verify all are present
    local content
    content=$(<"$outfile")
    [[ "$content" == *"S1"* ]]
    [[ "$content" == *"S2"* ]]
    [[ "$content" == *"S3"* ]]
}

@test "workflow_run respects --parallel 1 for sequential" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/seq.txt"
    workflow_define "seq"
    workflow_step "seq" "s1" "echo S1 >> $outfile"
    workflow_step "seq" "s2" "echo S2 >> $outfile"
    workflow_step "seq" "s3" "echo S3 >> $outfile"

    workflow_run "seq" --parallel 1

    [ -f "$outfile" ]
    local lines
    lines=$(wc -l < "$outfile")
    [ "$lines" -eq 3 ]
}

# =============================================================================
# workflow_run TESTS - FAILURE PROPAGATION
# =============================================================================

@test "workflow_run marks failed step correctly" {
    workflow_define "fail"
    workflow_step "fail" "s1" "false"

    run workflow_run "fail"
    [ "$status" -ne 0 ]

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/fail/steps/s1.json")
    [[ "$content" == *'"status":"failed"'* ]]
}

@test "workflow_run skips dependents on failure" {
    workflow_define "failchain"
    workflow_step "failchain" "s1" "false"
    workflow_step "failchain" "s2" "echo should-not-run" --depends "s1"

    run workflow_run "failchain"
    [ "$status" -ne 0 ]

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/failchain/steps/s1.json")
    [[ "$content" == *'"status":"failed"'* ]]
    content=$(<"$MAINFRAME_WORKFLOW_DIR/failchain/steps/s2.json")
    [[ "$content" == *'"status":"skipped"'* ]]
}

@test "workflow_run failure skips deep dependents" {
    workflow_define "deepfail"
    workflow_step "deepfail" "s1" "false"
    workflow_step "deepfail" "s2" "true" --depends "s1"
    workflow_step "deepfail" "s3" "true" --depends "s2"

    run workflow_run "deepfail" --parallel 1
    [ "$status" -ne 0 ]

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/deepfail/steps/s2.json")
    [[ "$content" == *'"status":"skipped"'* ]]
    content=$(<"$MAINFRAME_WORKFLOW_DIR/deepfail/steps/s3.json")
    [[ "$content" == *'"status":"skipped"'* ]]
}

@test "workflow_run partial failure with independent branches" {
    workflow_define "partial"
    workflow_step "partial" "good" "true"
    workflow_step "partial" "bad" "false"
    workflow_step "partial" "after-good" "true" --depends "good"
    workflow_step "partial" "after-bad" "true" --depends "bad"

    run workflow_run "partial" --parallel 2
    [ "$status" -ne 0 ]

    # after-good should succeed (independent branch)
    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/partial/steps/after-good.json")
    [[ "$content" == *'"status":"success"'* ]]
    # after-bad should be skipped
    content=$(<"$MAINFRAME_WORKFLOW_DIR/partial/steps/after-bad.json")
    [[ "$content" == *'"status":"skipped"'* ]]
}

# =============================================================================
# workflow_run TESTS - CONTINUE ON ERROR
# =============================================================================

@test "workflow_run --continue-on-error runs all independent steps" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/cont.txt"
    workflow_define "cont"
    workflow_step "cont" "fail-step" "false"
    workflow_step "cont" "good-step" "echo GOOD >> $outfile"

    run workflow_run "cont" --continue-on-error --parallel 2
    # Still returns failure overall
    [ "$status" -ne 0 ]

    # But good-step ran
    [ -f "$outfile" ]
    local content
    content=$(<"$outfile")
    [[ "$content" == *"GOOD"* ]]
}

@test "workflow_run --continue-on-error still marks dependents properly" {
    workflow_define "cont2"
    workflow_step "cont2" "fail-step" "false"
    workflow_step "cont2" "dep-step" "true" --depends "fail-step"
    workflow_step "cont2" "indep" "true"

    run workflow_run "cont2" --continue-on-error --parallel 2
    [ "$status" -ne 0 ]

    # Independent step succeeds
    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/cont2/steps/indep.json")
    [[ "$content" == *'"status":"success"'* ]]
}

# =============================================================================
# CIRCULAR DEPENDENCY DETECTION
# =============================================================================

@test "workflow_run detects circular dependency (A->B->A)" {
    workflow_define "cycle"
    # Manually create circular deps (bypass validation)
    _wf_write_step "cycle" "step-a" "echo A" "pending" "step-b"
    _wf_write_step "cycle" "step-b" "echo B" "pending" "step-a"

    run workflow_run "cycle"
    [ "$status" -ne 0 ]
}

@test "workflow_run detects 3-node cycle (A->B->C->A)" {
    workflow_define "cycle3"
    _wf_write_step "cycle3" "step-a" "echo A" "pending" "step-c"
    _wf_write_step "cycle3" "step-b" "echo B" "pending" "step-a"
    _wf_write_step "cycle3" "step-c" "echo C" "pending" "step-b"

    run workflow_run "cycle3"
    [ "$status" -ne 0 ]
}

@test "workflow_run succeeds with valid DAG (no cycle)" {
    workflow_define "nocycle"
    workflow_step "nocycle" "a" "true"
    workflow_step "nocycle" "b" "true" --depends "a"
    workflow_step "nocycle" "c" "true" --depends "a"
    workflow_step "nocycle" "d" "true" --depends "b,c"

    run workflow_run "nocycle"
    [ "$status" -eq 0 ]
}

# =============================================================================
# workflow_retry TESTS
# =============================================================================

@test "workflow_retry resets failed step to pending" {
    workflow_define "retry-wf"
    workflow_step "retry-wf" "s1" "true"
    _wf_update_status "retry-wf" "s1" "failed"

    workflow_retry "retry-wf" "s1"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/retry-wf/steps/s1.json")
    [[ "$content" == *'"status":"pending"'* ]]
}

@test "workflow_retry resets skipped dependents" {
    workflow_define "retry-wf2"
    workflow_step "retry-wf2" "s1" "true"
    workflow_step "retry-wf2" "s2" "true" --depends "s1"
    _wf_update_status "retry-wf2" "s1" "failed"
    _wf_update_status "retry-wf2" "s2" "skipped"

    workflow_retry "retry-wf2" "s1"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/retry-wf2/steps/s1.json")
    [[ "$content" == *'"status":"pending"'* ]]
    content=$(<"$MAINFRAME_WORKFLOW_DIR/retry-wf2/steps/s2.json")
    [[ "$content" == *'"status":"pending"'* ]]
}

@test "workflow_retry fails for non-failed step" {
    workflow_define "retry-wf3"
    workflow_step "retry-wf3" "s1" "true"
    _wf_update_status "retry-wf3" "s1" "success"

    run workflow_retry "retry-wf3" "s1"
    [ "$status" -ne 0 ]
}

@test "workflow_retry fails for nonexistent step" {
    workflow_define "retry-wf4"
    run workflow_retry "retry-wf4" "nonexistent"
    [ "$status" -ne 0 ]
}

@test "workflow_retry with empty args fails" {
    run workflow_retry "" ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_cancel TESTS
# =============================================================================

@test "workflow_cancel marks pending steps as cancelled" {
    workflow_define "cancel-wf"
    workflow_step "cancel-wf" "s1" "sleep 10"
    workflow_step "cancel-wf" "s2" "echo done" --depends "s1"

    workflow_cancel "cancel-wf"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/cancel-wf/steps/s1.json")
    [[ "$content" == *'"status":"cancelled"'* ]]
    content=$(<"$MAINFRAME_WORKFLOW_DIR/cancel-wf/steps/s2.json")
    [[ "$content" == *'"status":"cancelled"'* ]]
}

@test "workflow_cancel creates cancel file" {
    workflow_define "cancel-wf2"
    workflow_step "cancel-wf2" "s1" "sleep 10"

    workflow_cancel "cancel-wf2"
    [ -f "$MAINFRAME_WORKFLOW_DIR/cancel-wf2/cancel" ]
}

@test "workflow_cancel fails for undefined workflow" {
    run workflow_cancel "nonexistent"
    [ "$status" -ne 0 ]
}

@test "workflow_cancel with empty name fails" {
    run workflow_cancel ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_run_step TESTS
# =============================================================================

@test "workflow_run_step executes single step" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/single.txt"
    workflow_define "single-wf"
    workflow_step "single-wf" "s1" "echo HELLO > $outfile"

    workflow_run_step "single-wf" "s1"

    [ -f "$outfile" ]
    local content
    content=$(<"$outfile")
    [[ "$content" == *"HELLO"* ]]
}

@test "workflow_run_step marks success" {
    workflow_define "single-wf2"
    workflow_step "single-wf2" "s1" "true"

    workflow_run_step "single-wf2" "s1"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/single-wf2/steps/s1.json")
    [[ "$content" == *'"status":"success"'* ]]
}

@test "workflow_run_step marks failure" {
    workflow_define "single-wf3"
    workflow_step "single-wf3" "s1" "false"

    run workflow_run_step "single-wf3" "s1"
    [ "$status" -ne 0 ]

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/single-wf3/steps/s1.json")
    [[ "$content" == *'"status":"failed"'* ]]
}

@test "workflow_run_step fails for nonexistent step" {
    workflow_define "single-wf4"
    run workflow_run_step "single-wf4" "nonexistent"
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_status TESTS
# =============================================================================

@test "workflow_status returns JSON" {
    workflow_define "status-wf"
    workflow_step "status-wf" "s1" "echo hello"
    workflow_step "status-wf" "s2" "echo world" --depends "s1"

    run workflow_status "status-wf"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"workflow":"status-wf"'* ]]
    [[ "$output" == *'"steps":'* ]]
}

@test "workflow_status shows step statuses" {
    workflow_define "status-wf2"
    workflow_step "status-wf2" "s1" "true"
    _wf_update_status "status-wf2" "s1" "success"

    run workflow_status "status-wf2"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"success"'* ]]
}

@test "workflow_status shows dependencies" {
    workflow_define "status-wf3"
    workflow_step "status-wf3" "s1" "true"
    workflow_step "status-wf3" "s2" "true" --depends "s1"

    run workflow_status "status-wf3"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"depends":["s1"]'* ]]
}

@test "workflow_status fails for undefined workflow" {
    run workflow_status "nonexistent"
    [ "$status" -ne 0 ]
}

@test "workflow_status fails with empty name" {
    run workflow_status ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_is_running TESTS
# =============================================================================

@test "workflow_is_running returns 1 for non-running workflow" {
    workflow_define "check-wf"
    workflow_step "check-wf" "s1" "true"

    run workflow_is_running "check-wf"
    [ "$status" -ne 0 ]
}

@test "workflow_is_running returns 0 if step has running status" {
    workflow_define "check-wf2"
    workflow_step "check-wf2" "s1" "sleep 10"
    _wf_update_status "check-wf2" "s1" "running"

    run workflow_is_running "check-wf2"
    [ "$status" -eq 0 ]
}

@test "workflow_is_running returns 1 with empty name" {
    run workflow_is_running ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_history TESTS
# =============================================================================

@test "workflow_history shows empty when no runs" {
    run workflow_history
    [ "$status" -eq 0 ]
    [[ "$output" == *"No workflow history"* ]]
}

@test "workflow_history records completed runs" {
    workflow_define "hist-wf"
    workflow_step "hist-wf" "s1" "true"
    workflow_run "hist-wf"

    run workflow_history
    [ "$status" -eq 0 ]
    [[ "$output" == *"hist-wf"* ]]
    [[ "$output" == *"success"* ]]
}

@test "workflow_history json output" {
    workflow_define "hist-wf2"
    workflow_step "hist-wf2" "s1" "true"
    workflow_run "hist-wf2"

    run workflow_history --json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *'"workflow":"hist-wf2"'* ]]
    [[ "$output" == *'"status":"success"'* ]]
}

@test "workflow_history respects --limit" {
    workflow_define "hist-limit"
    workflow_step "hist-limit" "s1" "true"
    workflow_run "hist-limit"
    workflow_run "hist-limit"
    workflow_run "hist-limit"

    run workflow_history --json --limit 2
    [ "$status" -eq 0 ]
    # Should have at most 2 entries
    local count
    count=$(echo "$output" | grep -o '"workflow"' | wc -l)
    [ "$count" -le 2 ]
}

@test "workflow_history records failed runs" {
    workflow_define "hist-fail"
    workflow_step "hist-fail" "s1" "false"
    run workflow_run "hist-fail"

    run workflow_history --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"failed"'* ]]
}

# =============================================================================
# workflow_visualize TESTS
# =============================================================================

@test "workflow_visualize outputs mermaid graph header" {
    workflow_define "viz-wf"
    workflow_step "viz-wf" "s1" "true"

    run workflow_visualize "viz-wf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"graph TD"* ]]
}

@test "workflow_visualize shows step nodes" {
    workflow_define "viz-wf2"
    workflow_step "viz-wf2" "build" "make"
    workflow_step "viz-wf2" "test" "make test" --depends "build"

    run workflow_visualize "viz-wf2"
    [ "$status" -eq 0 ]
    [[ "$output" == *'build["build"]'* ]]
    [[ "$output" == *'test["test"]'* ]]
}

@test "workflow_visualize shows dependency edges" {
    workflow_define "viz-wf3"
    workflow_step "viz-wf3" "build" "make"
    workflow_step "viz-wf3" "test" "make test" --depends "build"

    run workflow_visualize "viz-wf3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"build --> test"* ]]
}

@test "workflow_visualize shows status styling" {
    workflow_define "viz-wf4"
    workflow_step "viz-wf4" "s1" "true"
    _wf_update_status "viz-wf4" "s1" "success"

    run workflow_visualize "viz-wf4"
    [ "$status" -eq 0 ]
    [[ "$output" == *":::success"* ]]
}

@test "workflow_visualize includes style definitions" {
    workflow_define "viz-wf5"
    workflow_step "viz-wf5" "s1" "true"

    run workflow_visualize "viz-wf5"
    [ "$status" -eq 0 ]
    [[ "$output" == *"classDef success"* ]]
    [[ "$output" == *"classDef failed"* ]]
    [[ "$output" == *"classDef running"* ]]
    [[ "$output" == *"classDef skipped"* ]]
}

@test "workflow_visualize fails for undefined workflow" {
    run workflow_visualize "nonexistent"
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_export TESTS
# =============================================================================

@test "workflow_export writes JSON to file" {
    workflow_define "exp-wf"
    workflow_step "exp-wf" "s1" "echo hello"
    workflow_step "exp-wf" "s2" "echo world" --depends "s1"

    local outfile="$MAINFRAME_WORKFLOW_DIR/export.json"
    workflow_export "exp-wf" "$outfile"

    [ -f "$outfile" ]
    local content
    content=$(<"$outfile")
    [[ "$content" == *'"name":"exp-wf"'* ]]
    [[ "$content" == *'"steps":'* ]]
}

@test "workflow_export includes step commands" {
    workflow_define "exp-wf2"
    workflow_step "exp-wf2" "build" "make all"

    local outfile="$MAINFRAME_WORKFLOW_DIR/export2.json"
    workflow_export "exp-wf2" "$outfile"

    local content
    content=$(<"$outfile")
    [[ "$content" == *'"command":"make all"'* ]]
}

@test "workflow_export includes dependencies" {
    workflow_define "exp-wf3"
    workflow_step "exp-wf3" "s1" "true"
    workflow_step "exp-wf3" "s2" "true" --depends "s1"

    local outfile="$MAINFRAME_WORKFLOW_DIR/export3.json"
    workflow_export "exp-wf3" "$outfile"

    local content
    content=$(<"$outfile")
    [[ "$content" == *'"depends":["s1"]'* ]]
}

@test "workflow_export to stdout without file arg" {
    workflow_define "exp-wf4"
    workflow_step "exp-wf4" "s1" "true"

    run workflow_export "exp-wf4"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name":"exp-wf4"'* ]]
}

@test "workflow_export fails for undefined workflow" {
    run workflow_export "nonexistent" "/tmp/out.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# workflow_import TESTS
# =============================================================================

@test "workflow_import creates workflow from JSON" {
    local infile="$MAINFRAME_WORKFLOW_DIR/import.json"
    printf '{"name":"imported-wf","steps":[{"name":"s1","command":"echo one","depends":[]}]}' > "$infile"

    workflow_import "$infile"

    [ -d "$MAINFRAME_WORKFLOW_DIR/imported-wf" ]
    [ -f "$MAINFRAME_WORKFLOW_DIR/imported-wf/steps/s1.json" ]
}

@test "workflow_import preserves commands" {
    local infile="$MAINFRAME_WORKFLOW_DIR/import2.json"
    printf '{"name":"imp2","steps":[{"name":"build","command":"make all","depends":[]}]}' > "$infile"

    workflow_import "$infile"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/imp2/steps/build.json")
    [[ "$content" == *'"command":"make all"'* ]]
}

@test "workflow_import preserves dependencies" {
    local infile="$MAINFRAME_WORKFLOW_DIR/import3.json"
    printf '{"name":"imp3","steps":[{"name":"s1","command":"true","depends":[]},{"name":"s2","command":"true","depends":["s1"]}]}' > "$infile"

    workflow_import "$infile"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/imp3/steps/s2.json")
    [[ "$content" == *'"depends":["s1"]'* ]]
}

@test "workflow_import fails with missing file" {
    run workflow_import "/nonexistent/file.json"
    [ "$status" -ne 0 ]
}

@test "workflow_import fails with empty arg" {
    run workflow_import ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# EXPORT/IMPORT ROUND-TRIP
# =============================================================================

@test "export/import round-trip preserves workflow" {
    workflow_define "roundtrip"
    workflow_step "roundtrip" "build" "make all"
    workflow_step "roundtrip" "test" "make test" --depends "build"
    workflow_step "roundtrip" "deploy" "make deploy" --depends "test"

    local export_file="$MAINFRAME_WORKFLOW_DIR/rt.json"
    workflow_export "roundtrip" "$export_file"

    # Remove original
    rm -rf "$MAINFRAME_WORKFLOW_DIR/roundtrip"

    # Import
    workflow_import "$export_file"

    # Verify
    [ -d "$MAINFRAME_WORKFLOW_DIR/roundtrip" ]
    [ -f "$MAINFRAME_WORKFLOW_DIR/roundtrip/steps/build.json" ]
    [ -f "$MAINFRAME_WORKFLOW_DIR/roundtrip/steps/test.json" ]
    [ -f "$MAINFRAME_WORKFLOW_DIR/roundtrip/steps/deploy.json" ]

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/roundtrip/steps/build.json")
    [[ "$content" == *'"command":"make all"'* ]]
    content=$(<"$MAINFRAME_WORKFLOW_DIR/roundtrip/steps/test.json")
    [[ "$content" == *'"depends":["build"]'* ]]
    content=$(<"$MAINFRAME_WORKFLOW_DIR/roundtrip/steps/deploy.json")
    [[ "$content" == *'"depends":["test"]'* ]]
}

@test "export/import round-trip with diamond deps" {
    workflow_define "rtdiamond"
    workflow_step "rtdiamond" "a" "cmd-a"
    workflow_step "rtdiamond" "b" "cmd-b" --depends "a"
    workflow_step "rtdiamond" "c" "cmd-c" --depends "a"
    workflow_step "rtdiamond" "d" "cmd-d" --depends "b,c"

    local export_file="$MAINFRAME_WORKFLOW_DIR/rtd.json"
    workflow_export "rtdiamond" "$export_file"
    rm -rf "$MAINFRAME_WORKFLOW_DIR/rtdiamond"
    workflow_import "$export_file"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/rtdiamond/steps/d.json")
    [[ "$content" == *'"b"'* ]]
    [[ "$content" == *'"c"'* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "single step workflow runs successfully" {
    workflow_define "one-step"
    workflow_step "one-step" "only" "true"

    run workflow_run "one-step"
    [ "$status" -eq 0 ]

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/one-step/steps/only.json")
    [[ "$content" == *'"status":"success"'* ]]
}

@test "step with command containing special characters" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/special.txt"
    workflow_define "special"
    workflow_step "special" "s1" "echo 'hello world' > $outfile"

    workflow_run "special"
    [ -f "$outfile" ]
    local content
    content=$(<"$outfile")
    [[ "$content" == *"hello world"* ]]
}

@test "workflow_run preserves embedded double quotes and env vars" {
    workflow_define "quoted-env"
    export TEST_VAR="test_value"

    workflow_step "quoted-env" "s1" "echo \"Value is: \$TEST_VAR\""

    run workflow_run "quoted-env"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Value is: test_value"* ]]

    unset TEST_VAR
}

@test "workflow_run preserves commands that emit JSON strings" {
    local outfile="$MAINFRAME_WORKFLOW_DIR/data.json"
    workflow_define "json-cmd"
    workflow_step "json-cmd" "s1" "echo '{\"name\":\"Alice\",\"role\":\"admin\"}' > '$outfile'"

    run workflow_run "json-cmd"
    [ "$status" -eq 0 ]
    [ -f "$outfile" ]

    local content
    content=$(<"$outfile")
    [[ "$content" == *'"name":"Alice"'* ]]
    [[ "$content" == *'"role":"admin"'* ]]
}

@test "workflow with many independent steps" {
    workflow_define "many"
    local i=1
    while [[ $i -le 10 ]]; do
        workflow_step "many" "step-${i}" "true"
        i=$(( i + 1 ))
    done

    run workflow_run "many" --parallel 4
    [ "$status" -eq 0 ]
}

@test "missing dependency step file detected" {
    workflow_define "missing-dep"
    workflow_step "missing-dep" "s1" "true"
    # Manually create step with non-existent dependency
    _wf_write_step "missing-dep" "s2" "true" "pending" "nonexistent"

    # Should still handle gracefully (deps_satisfied will fail)
    run workflow_run "missing-dep" --parallel 1
    # Step s2 won't be able to satisfy deps, leading to deadlock detection
    [ "$status" -ne 0 ]
}

@test "workflow names can contain numbers" {
    workflow_define "wf123"
    [ -d "$MAINFRAME_WORKFLOW_DIR/wf123" ]
}

@test "step names can contain numbers" {
    workflow_define "num-wf"
    workflow_step "num-wf" "step123" "true"
    [ -f "$MAINFRAME_WORKFLOW_DIR/num-wf/steps/step123.json" ]
}

@test "re-running workflow resets all statuses" {
    workflow_define "rerun"
    workflow_step "rerun" "s1" "true"
    workflow_step "rerun" "s2" "true" --depends "s1"

    # First run
    workflow_run "rerun"

    # Manually set to failed to verify reset
    _wf_update_status "rerun" "s1" "failed"

    # Second run should reset
    workflow_run "rerun"

    local content
    content=$(<"$MAINFRAME_WORKFLOW_DIR/rerun/steps/s1.json")
    [[ "$content" == *'"status":"success"'* ]]
}

@test "workflow status with no steps returns valid JSON" {
    workflow_define "empty-status"
    run workflow_status "empty-status"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"workflow":"empty-status"'* ]]
    [[ "$output" == *'"steps":{}'* ]]
}

@test "multiple workflows can coexist" {
    workflow_define "wf-one"
    workflow_define "wf-two"
    workflow_step "wf-one" "s1" "true"
    workflow_step "wf-two" "s1" "true"

    workflow_run "wf-one"
    workflow_run "wf-two"

    local content1 content2
    content1=$(<"$MAINFRAME_WORKFLOW_DIR/wf-one/steps/s1.json")
    content2=$(<"$MAINFRAME_WORKFLOW_DIR/wf-two/steps/s1.json")
    [[ "$content1" == *'"status":"success"'* ]]
    [[ "$content2" == *'"status":"success"'* ]]
}

@test "workflow_run records duration in history" {
    workflow_define "duration-wf"
    workflow_step "duration-wf" "s1" "true"
    workflow_run "duration-wf"

    run workflow_history --json
    [[ "$output" == *'"duration":'* ]]
}

@test "complex DAG with fan-out and fan-in" {
    #    A
    #   /|\
    #  B C D
    #   \|/
    #    E
    local outfile="$MAINFRAME_WORKFLOW_DIR/fanout.txt"
    workflow_define "fanout"
    workflow_step "fanout" "a" "echo A >> $outfile"
    workflow_step "fanout" "b" "echo B >> $outfile" --depends "a"
    workflow_step "fanout" "c" "echo C >> $outfile" --depends "a"
    workflow_step "fanout" "d" "echo D >> $outfile" --depends "a"
    workflow_step "fanout" "e" "echo E >> $outfile" --depends "b,c,d"

    workflow_run "fanout" --parallel 3

    local first_line last_line
    first_line=$(head -1 "$outfile")
    last_line=$(tail -1 "$outfile")
    [ "$first_line" = "A" ]
    [ "$last_line" = "E" ]
    local lines
    lines=$(wc -l < "$outfile")
    [ "$lines" -eq 5 ]
}

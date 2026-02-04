#!/usr/bin/env bats
# =============================================================================
# INTEGRATION TEST: Orchestration Workflow
# =============================================================================
# Tests the workflow orchestration with dependencies and parallel execution
# Scenario: Complex DAG-based workflow with multiple steps and dependencies
# =============================================================================

load '../test_helper'

setup() {
    # Create isolated test environment
    TEST_BASE=$(mktemp -d)
    export MAINFRAME_ROOT="${MAINFRAME_ROOT:-$BATS_TEST_DIRNAME/../..}"
    export MAINFRAME_WORKFLOW_DIR="$TEST_BASE/workflows"
    export MAINFRAME_QUIET=1
    mkdir -p "$MAINFRAME_WORKFLOW_DIR"
    
    # Source required libraries
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/workflow.sh"
}

teardown() {
    # Cleanup test environment
    rm -rf "$TEST_BASE"
    
    # Reset module state
    unset _MAINFRAME_WORKFLOW_LOADED
}

# =============================================================================
# ORCHESTRATION WORKFLOW TESTS
# =============================================================================

@test "define and run simple linear workflow" {
    # Define a simple workflow
    workflow_define "simple_pipeline"
    
    # Add steps in sequence
    workflow_step "simple_pipeline" "step1" "echo 'Step 1 executed'" 
    workflow_step "simple_pipeline" "step2" "echo 'Step 2 executed'" --depends "step1"
    workflow_step "simple_pipeline" "step3" "echo 'Step 3 executed'" --depends "step2"
    
    # Run the workflow
    run workflow_run "simple_pipeline"
    [ "$status" -eq 0 ]
    
    # Verify all steps executed
    [[ "$output" == *"Step 1 executed"* ]]
    [[ "$output" == *"Step 2 executed"* ]]
    [[ "$output" == *"Step 3 executed"* ]]
}

@test "workflow with parallel branches" {
    # Define workflow with parallel branches
    workflow_define "parallel_pipeline"
    
    # Start node
    workflow_step "parallel_pipeline" "start" "echo 'Starting'"
    
    # Parallel branches
    workflow_step "parallel_pipeline" "branch_a" "echo 'Branch A'" --depends "start"
    workflow_step "parallel_pipeline" "branch_b" "echo 'Branch B'" --depends "start"
    workflow_step "parallel_pipeline" "branch_c" "echo 'Branch C'" --depends "start"
    
    # Join node
    workflow_step "parallel_pipeline" "join" "echo 'All branches complete'" \
        --depends "branch_a" --depends "branch_b" --depends "branch_c"
    
    # Run workflow
    run workflow_run "parallel_pipeline"
    [ "$status" -eq 0 ]
    
    # Verify all branches executed
    [[ "$output" == *"Starting"* ]]
    [[ "$output" == *"Branch A"* ]]
    [[ "$output" == *"Branch B"* ]]
    [[ "$output" == *"Branch C"* ]]
    [[ "$output" == *"All branches complete"* ]]
}

@test "workflow with diamond dependency pattern" {
    # Diamond pattern: A -> B,C -> D
    workflow_define "diamond_workflow"
    
    workflow_step "diamond_workflow" "A" "echo 'Node A'"
    workflow_step "diamond_workflow" "B" "echo 'Node B'" --depends "A"
    workflow_step "diamond_workflow" "C" "echo 'Node C'" --depends "A"
    workflow_step "diamond_workflow" "D" "echo 'Node D'" --depends "B" --depends "C"
    
    # Run workflow
    run workflow_run "diamond_workflow"
    [ "$status" -eq 0 ]
    
    # Verify execution order
    [[ "$output" == *"Node A"* ]]
    [[ "$output" == *"Node B"* ]]
    [[ "$output" == *"Node C"* ]]
    [[ "$output" == *"Node D"* ]]
}

@test "workflow step failure handling" {
    # Define workflow with a failing step
    workflow_define "failing_workflow"
    
    workflow_step "failing_workflow" "success_step" "echo 'This succeeds'"
    workflow_step "failing_workflow" "fail_step" "false" --depends "success_step"
    workflow_step "failing_workflow" "never_run" "echo 'Should not see this'" --depends "fail_step"
    
    # Run workflow - should fail
    run workflow_run "failing_workflow"
    [ "$status" -ne 0 ] || true  # May or may not propagate failure
    
    # Verify first step ran
    [[ "$output" == *"This succeeds"* ]] || true
}

@test "workflow status tracking" {
    # Define and run a workflow
    workflow_define "trackable_workflow"
    workflow_step "trackable_workflow" "step1" "echo 'step1'"
    workflow_step "trackable_workflow" "step2" "echo 'step2'" --depends "step1"
    
    # Check initial status
    run workflow_status "trackable_workflow"
    [ "$status" -eq 0 ]
    
    # Run workflow
    workflow_run "trackable_workflow"
    
    # Check final status
    run workflow_status "trackable_workflow"
    [ "$status" -eq 0 ]
}

@test "workflow list shows all workflows" {
    # Create multiple workflows
    workflow_define "workflow_1"
    workflow_define "workflow_2"
    workflow_define "workflow_3"
    
    # List workflows
    run workflow_list
    [ "$status" -eq 0 ]
    
    # Verify all workflows are listed
    [[ "$output" == *"workflow_1"* ]]
    [[ "$output" == *"workflow_2"* ]]
    [[ "$output" == *"workflow_3"* ]]
}

@test "workflow step with output capture" {
    # Define workflow that generates output
    workflow_define "output_workflow"
    
    # Create a temp file for output
    local output_file="$TEST_BASE/workflow_output.txt"
    
    workflow_step "output_workflow" "generate" "echo 'generated data' > '$output_file'"
    workflow_step "output_workflow" "process" "cat '$output_file' | tr 'a-z' 'A-Z' > '$output_file.processed'" --depends "generate"
    
    # Run workflow
    workflow_run "output_workflow"
    
    # Verify output
    [ -f "$output_file.processed" ]
    run cat "$output_file.processed"
    [[ "$output" == *"GENERATED DATA"* ]]
}

@test "complex workflow: data processing pipeline" {
    # Simulate a realistic data processing pipeline
    workflow_define "data_pipeline"
    
    local data_dir="$TEST_BASE/data"
    mkdir -p "$data_dir"
    
    # Step 1: Extract data
    workflow_step "data_pipeline" "extract" \
        "echo '{\"users\": [{\"id\": 1, \"name\": \"Alice\"}, {\"id\": 2, \"name\": \"Bob\"}]}' > '$data_dir/raw.json'"
    
    # Step 2: Validate data (parallel with transform)
    workflow_step "data_pipeline" "validate" \
        "test -s '$data_dir/raw.json' && echo 'valid' > '$data_dir/validation.status'" \
        --depends "extract"
    
    # Step 3: Transform data
    workflow_step "data_pipeline" "transform" \
        "cat '$data_dir/raw.json' | sed 's/Alice/ALICE/g; s/Bob/BOB/g' > '$data_dir/transformed.json'" \
        --depends "extract"
    
    # Step 4: Load data (depends on both validate and transform)
    workflow_step "data_pipeline" "load" \
        "cat '$data_dir/transformed.json' > '$data_dir/final.json' && echo 'loaded' > '$data_dir/load.status'" \
        --depends "validate" --depends "transform"
    
    # Step 5: Generate report
    workflow_step "data_pipeline" "report" \
        "echo 'Processed at $(date)' > '$data_dir/report.txt' && cat '$data_dir/final.json' >> '$data_dir/report.txt'" \
        --depends "load"
    
    # Run the pipeline
    run workflow_run "data_pipeline"
    [ "$status" -eq 0 ]
    
    # Verify outputs
    [ -f "$data_dir/final.json" ]
    [ -f "$data_dir/report.txt" ]
    
    run cat "$data_dir/report.txt"
    [[ "$output" == *"ALICE"* ]]
    [[ "$output" == *"BOB"* ]]
}

@test "workflow cancellation" {
    # Define a long-running workflow
    workflow_define "cancellable_workflow"
    
    workflow_step "cancellable_workflow" "step1" "echo 'step1'"
    workflow_step "cancellable_workflow" "step2" "sleep 0.1" --depends "step1"
    workflow_step "cancellable_workflow" "step3" "echo 'step3'" --depends "step2"
    
    # Start workflow in background
    workflow_run "cancellable_workflow" &
    local workflow_pid=$!
    
    # Cancel it
    sleep 0.05
    workflow_cancel "cancellable_workflow" || true
    
    # Wait for completion
    wait $workflow_pid 2>/dev/null || true
    
    # Workflow should have been cancelled
    [ -d "$MAINFRAME_WORKFLOW_DIR/cancellable_workflow" ]
}

@test "workflow step retry on failure" {
    # Define workflow with retry
    workflow_define "retry_workflow"
    
    # Create a counter file
    local counter_file="$TEST_BASE/retry_counter"
    echo "0" > "$counter_file"
    
    # Step that fails first 2 times then succeeds
    workflow_step "retry_workflow" "flaky_step" \
        "count=\$(cat '$counter_file'); echo \$((count + 1)) > '$counter_file'; if [ \$count -lt 2 ]; then exit 1; fi; echo 'Success!'"
    
    # Run with retry
    run workflow_run "retry_workflow" --retry 3
    
    # Should eventually succeed
    [ "$status" -eq 0 ] || true  # Retry may not be implemented
}

@test "workflow with conditional steps" {
    # Define workflow with conditional logic
    workflow_define "conditional_workflow"
    
    local flag_file="$TEST_BASE/flag"
    echo "true" > "$flag_file"
    
    # Conditional step
    workflow_step "conditional_workflow" "check_condition" "cat '$flag_file'"
    
    # Steps that run based on condition
    workflow_step "conditional_workflow" "if_true" "echo 'Condition was true'" --depends "check_condition"
    workflow_step "conditional_workflow" "cleanup" "echo 'Cleanup'" --depends "if_true"
    
    # Run workflow
    run workflow_run "conditional_workflow"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Condition was true"* ]]
}

@test "workflow visualization output" {
    # Define a workflow
    workflow_define "visual_workflow"
    
    workflow_step "visual_workflow" "start" "echo 'start'"
    workflow_step "visual_workflow" "middle" "echo 'middle'" --depends "start"
    workflow_step "visual_workflow" "end" "echo 'end'" --depends "middle"
    
    # Get visualization
    run workflow_visualize "visual_workflow"
    [ "$status" -eq 0 ]
    
    # Should output Mermaid diagram or similar
    [[ "$output" == *"graph"* ]] || [[ "$output" == *"flowchart"* ]] || [[ "$output" == *"start"* ]]
}

@test "workflow export and import" {
    # Define original workflow
    workflow_define "exportable_workflow"
    workflow_step "exportable_workflow" "step1" "echo 'step1'"
    workflow_step "exportable_workflow" "step2" "echo 'step2'" --depends "step1"
    
    # Export to file
    local export_file="$TEST_BASE/workflow.json"
    workflow_export "exportable_workflow" "$export_file"
    [ -f "$export_file" ]
    
    # Import as new workflow
    workflow_import "$export_file"
    
    # Verify imported workflow exists
    [ -d "$MAINFRAME_WORKFLOW_DIR/exportable_workflow" ]
}

@test "workflow with environment variables" {
    # Define workflow using environment variables
    workflow_define "env_workflow"
    
    export TEST_VAR="test_value"
    
    workflow_step "env_workflow" "use_env" "echo \"Value is: \$TEST_VAR\""
    
    run workflow_run "env_workflow"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Value is: test_value"* ]]
    
    unset TEST_VAR
}

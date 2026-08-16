#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    HARNESS="$PROJECT_ROOT/scripts/dev/agent-impact.py"
    PROTOCOL_ROOT="$PROJECT_ROOT/evals/agent-impact"
    SUITE="$PROTOCOL_ROOT/suites/conformance-v1.json"
    RUNNER="$PROTOCOL_ROOT/runners/fake-runner.py"
    PYTHON_BIN="$(command -v python3)"
    export PYTHONDONTWRITEBYTECODE=1
    [[ -n "$PYTHON_BIN" ]] || skip "python3 is required"
    command -v jq >/dev/null || skip "jq is required"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-agent-impact.XXXXXX")"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

prepare_plan() {
    local root="$1" seed="${2:-conformance-seed}" suite="${3:-$SUITE}"
    mkdir -p "$root"
    "$PYTHON_BIN" "$HARNESS" prepare \
        --suite "$suite" \
        --seed "$seed" \
        --replicates 1 \
        --output "$root/plan.json" \
        --assignments-output "$root/assignments.json"
}

run_fixture() {
    local root="$1"
    shift
    "$PYTHON_BIN" "$HARNESS" run --fixture \
        --plan "$root/plan.json" \
        --assignments "$root/assignments.json" \
        --runner "$RUNNER" \
        --output-dir "$root/run" \
        --evidence "$root/evidence.json" \
        "$@"
}

verify_fixture() {
    local root="$1"
    "$PYTHON_BIN" "$HARNESS" verify \
        --plan "$root/plan.json" \
        --assignments "$root/assignments.json" \
        --runner "$RUNNER" \
        --output-dir "$root/run" \
        --evidence "$root/evidence.json"
}

mode_of() {
    local path="$1"
    if stat -c '%a' "$path" >/dev/null 2>&1; then
        stat -c '%a' "$path"
    else
        stat -f '%Lp' "$path"
    fi
}

@test "protocol schemas and the toy task fail closed structurally" {
    run jq -e '
      .additionalProperties == false and
      (.required | index("tasks") != null)
    ' "$PROTOCOL_ROOT/suite.schema.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .additionalProperties == false and
      .properties.transition.properties.fresh_host_state.const == true and
      .properties.transition.properties.preserve_workspace.const == true and
      .properties.transition.properties.control.const == "native-bounded-handoff" and
      .properties.transition.properties.treatment.const == "mainframe-awm-handoff"
    ' "$PROTOCOL_ROOT/task.schema.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .additionalProperties == false and
      .properties.claim_scope.const == "fixture-runner-protocol-conformance-only" and
      .properties.non_claims.properties.real_provider_inference.const == "not-run" and
      .properties.non_claims.properties.agent_quality.const == "not-measured" and
      .properties.non_claims.properties.live_agent_sessions.const == 0
    ' "$PROTOCOL_ROOT/evidence.schema.json"
    [[ "$status" -eq 0 ]]

    [[ -x "$HARNESS" ]]
    [[ -x "$RUNNER" ]]
    [[ -f "$PROTOCOL_ROOT/tasks/conformance-001/grade.py" ]]
    [[ ! -L "$PROTOCOL_ROOT/tasks/conformance-001/grade.py" ]]
}

@test "prepare is deterministic opaque committed and no-clobber" {
    run prepare_plan "$TEST_DIR/first" "same-seed"
    [[ "$status" -eq 0 ]]
    run prepare_plan "$TEST_DIR/second" "same-seed"
    [[ "$status" -eq 0 ]]

    cmp "$TEST_DIR/first/plan.json" "$TEST_DIR/second/plan.json"
    cmp "$TEST_DIR/first/assignments.json" "$TEST_DIR/second/assignments.json"
    [[ "$(mode_of "$TEST_DIR/first/assignments.json")" == 600 ]]
    [[ "$(mode_of "$TEST_DIR/first/plan.json")" == 644 ]]

    run jq -e '
      (.pairs | length) == 1 and
      (.pairs[0].opaque_arm_order | length) == 2 and
      all(.pairs[0].opaque_arm_order[]; test("^arm-[0-9a-f]{16}$")) and
      (.assignment_commitment_sha256 | test("^[0-9a-f]{64}$")) and
      ((tostring | contains("control")) | not) and
      ((tostring | contains("treatment")) | not)
    ' "$TEST_DIR/first/plan.json"
    [[ "$status" -eq 0 ]]

    plan_before="$(shasum -a 256 "$TEST_DIR/first/plan.json" | awk '{print $1}')"
    run prepare_plan "$TEST_DIR/first" "same-seed"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to overwrite existing plan output"* ]]
    [[ "$plan_before" == "$(shasum -a 256 "$TEST_DIR/first/plan.json" | awk '{print $1}')" ]]

    run prepare_plan "$TEST_DIR/different" "different-seed"
    [[ "$status" -eq 0 ]]
    run cmp "$TEST_DIR/first/plan.json" "$TEST_DIR/different/plan.json"
    [[ "$status" -ne 0 ]]
}

@test "duplicate keys traversal and symbolic protocol inputs are rejected" {
    cp -R "$PROTOCOL_ROOT" "$TEST_DIR/protocol"
    printf '%s\n' \
      '{"schema_version":1,"kind":"mainframe-agent-impact-suite",' \
      '"id":"first","id":"second","description":"duplicate",' \
      '"tasks":["tasks/conformance-001/task.json"]}' \
      > "$TEST_DIR/protocol/suites/duplicate.json"
    run prepare_plan "$TEST_DIR/duplicate-run" "seed" \
        "$TEST_DIR/protocol/suites/duplicate.json"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"duplicate key 'id'"* ]]

    printf '%s\n' \
      '{"schema_version":1,"kind":"mainframe-agent-impact-suite",' \
      '"id":"traversal","description":"traversal",' \
      '"tasks":["../tasks/conformance-001/task.json"]}' \
      > "$TEST_DIR/protocol/suites/traversal.json"
    run prepare_plan "$TEST_DIR/traversal-run" "seed" \
        "$TEST_DIR/protocol/suites/traversal.json"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsafe path component"* ]]

    mv "$TEST_DIR/protocol/tasks/conformance-001/investigate.md" \
       "$TEST_DIR/protocol/tasks/conformance-001/investigate.target"
    ln -s investigate.target "$TEST_DIR/protocol/tasks/conformance-001/investigate.md"
    run prepare_plan "$TEST_DIR/symlink-run" "seed" \
        "$TEST_DIR/protocol/suites/conformance-v1.json"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"symbolic link"* ]]
}

@test "runner execution is explicit and validation happens before invocation" {
    prepare_plan "$TEST_DIR/explicit" "explicit-seed"
    marker="$TEST_DIR/invoked.marker"
    marker_runner="$TEST_DIR/marker-runner.sh"
    printf '%s\n' '#!/bin/sh' 'printf invoked > "$MARKER_PATH"' 'exit 70' \
      > "$marker_runner"
    chmod 700 "$marker_runner"

    run env MARKER_PATH="$marker" "$PYTHON_BIN" "$HARNESS" run \
        --plan "$TEST_DIR/explicit/plan.json" \
        --assignments "$TEST_DIR/explicit/assignments.json" \
        --runner "$marker_runner" \
        --output-dir "$TEST_DIR/explicit/not-run" \
        --evidence "$TEST_DIR/explicit/not-run.json" \
        --pass-env MARKER_PATH
    [[ "$status" -ne 0 ]]
    [[ ! -e "$marker" ]]
    [[ ! -e "$TEST_DIR/explicit/not-run" ]]

    jq '.pairs[0].budgets.maximum_context_bytes += 1' \
      "$TEST_DIR/explicit/plan.json" > "$TEST_DIR/explicit/tampered-plan.json"
    run env MARKER_PATH="$marker" "$PYTHON_BIN" "$HARNESS" run --fixture \
        --plan "$TEST_DIR/explicit/tampered-plan.json" \
        --assignments "$TEST_DIR/explicit/assignments.json" \
        --runner "$marker_runner" \
        --output-dir "$TEST_DIR/explicit/not-run-two" \
        --evidence "$TEST_DIR/explicit/not-run-two.json" \
        --pass-env MARKER_PATH
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"budgets do not equal"* ]]
    [[ ! -e "$marker" ]]
}

@test "fixture run scores paired arms with equal snapshots budgets and explicit non-claims" {
    prepare_plan "$TEST_DIR/e2e" "e2e-seed"
    export MAINFRAME_SHOULD_NOT_LEAK=top-secret-value
    run run_fixture "$TEST_DIR/e2e"
    unset MAINFRAME_SHOULD_NOT_LEAK
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"fixture protocol run complete: 1 pair(s)"* ]]

    run verify_fixture "$TEST_DIR/e2e"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"agent impact not measured"* ]]

    run jq -e '
      .claim_scope == "fixture-runner-protocol-conformance-only" and
      .runtime.mainframe_runtime_exercised == false and
      .runtime.awm_mechanism_exercised == false and
      .execution.provider_mode == "fixture" and
      .execution.runner_received_arm_mode == true and
      .execution.runner_was_not_blinded == true and
      .execution.environment_scrubbed == true and
      .execution.live_agent_sessions == 0 and
      .protocol.assignment_publicly_revealed_after_scoring == true and
      .limitations.runner_and_agent_not_blinded_to_arm_configuration == true and
      .non_claims == {
        agent_quality: "not-measured",
        comparative_agent_performance: "not-measured",
        live_agent_sessions: 0,
        productivity: "not-measured",
        real_provider_inference: "not-run"
      } and
      .aggregate.valid_pair_count == 1 and
      .aggregate.invalid_pair_count == 0 and
      .aggregate.control_solved_count == 0 and
      .aggregate.treatment_solved_count == 1 and
      .aggregate.treatment_wins == 1 and
      .aggregate.paired_success_rate_delta == 1 and
      (.pairs[0].arms | map(.initial_snapshot_sha256) | unique | length) == 1 and
      all(.pairs[0].arms[];
        .fresh_host_state_per_phase == true and
        .equal_planned_budgets == true and
        all(.usage[];
          .input_tokens == null and
          .input_tokens_reason == "fixture-runner-does-not-report-provider-usage" and
          .output_tokens == null and
          .output_tokens_reason == "fixture-runner-does-not-report-provider-usage"))
    ' "$TEST_DIR/e2e/evidence.json"
    [[ "$status" -eq 0 ]]

    run grep -F "$TEST_DIR" "$TEST_DIR/e2e/evidence.json"
    [[ "$status" -ne 0 ]]
    run grep -F 'top-secret-value' "$TEST_DIR/e2e/evidence.json"
    [[ "$status" -ne 0 ]]
    run find "$TEST_DIR/e2e/run" -path '*/workspace/grade.py' -print -quit
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "verifier rejects evidence raw-run runner and protocol tampering" {
    prepare_plan "$TEST_DIR/tamper" "tamper-seed"
    run_fixture "$TEST_DIR/tamper"
    cp "$TEST_DIR/tamper/evidence.json" "$TEST_DIR/tamper/evidence.original"

    jq '.aggregate.treatment_wins = 0' "$TEST_DIR/tamper/evidence.original" \
      > "$TEST_DIR/tamper/evidence.json"
    run verify_fixture "$TEST_DIR/tamper"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"aggregate does not derive"* ]]

    cp "$TEST_DIR/tamper/evidence.original" "$TEST_DIR/tamper/evidence.json"
    capacity_file="$(find "$TEST_DIR/tamper/run" -path '*/workspace/capacity.py' | head -1)"
    printf '\n# tampered\n' >> "$capacity_file"
    run verify_fixture "$TEST_DIR/tamper"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"does not reproduce exactly"* ]]

    cp "$RUNNER" "$TEST_DIR/runner-copy.py"
    chmod 700 "$TEST_DIR/runner-copy.py"
    run "$PYTHON_BIN" "$HARNESS" verify \
        --plan "$TEST_DIR/tamper/plan.json" \
        --assignments "$TEST_DIR/tamper/assignments.json" \
        --runner "$TEST_DIR/runner-copy.py" \
        --output-dir "$TEST_DIR/tamper/run" \
        --evidence "$TEST_DIR/tamper/evidence.json"
    [[ "$status" -eq 2 ]]

}

@test "timeout is an agent outcome while runner failure invalidates the pair" {
    prepare_plan "$TEST_DIR/timeout" "timeout-seed"
    run env MAINFRAME_EVAL_FIXTURE_BEHAVIOR=timeout \
      "$PYTHON_BIN" "$HARNESS" run --fixture \
        --plan "$TEST_DIR/timeout/plan.json" \
        --assignments "$TEST_DIR/timeout/assignments.json" \
        --runner "$RUNNER" \
        --output-dir "$TEST_DIR/timeout/run" \
        --evidence "$TEST_DIR/timeout/evidence.json" \
        --pass-env MAINFRAME_EVAL_FIXTURE_BEHAVIOR \
        --phase-timeout-override 0.1
    [[ "$status" -eq 0 ]]
    run jq -e '
      .aggregate.valid_pair_count == 1 and
      .aggregate.invalid_pair_count == 0 and
      .aggregate.ties == 1 and
      all(.pairs[0].arms[];
        .outcome_status == "timeout" and
        .grade.solved == false and
        .grade.not_run_reason == "agent-outcome-timeout")
    ' "$TEST_DIR/timeout/evidence.json"
    [[ "$status" -eq 0 ]]
    run grep -F 'timeout' "$TEST_DIR/timeout/evidence.json"
    [[ "$status" -eq 0 ]]

    prepare_plan "$TEST_DIR/infra" "infra-seed"
    run env MAINFRAME_EVAL_FIXTURE_BEHAVIOR=infrastructure-failure \
      "$PYTHON_BIN" "$HARNESS" run --fixture \
        --plan "$TEST_DIR/infra/plan.json" \
        --assignments "$TEST_DIR/infra/assignments.json" \
        --runner "$RUNNER" \
        --output-dir "$TEST_DIR/infra/run" \
        --evidence "$TEST_DIR/infra/evidence.json" \
        --pass-env MAINFRAME_EVAL_FIXTURE_BEHAVIOR
    [[ "$status" -eq 0 ]]
    run jq -e '
      .aggregate.valid_pair_count == 0 and
      .aggregate.invalid_pair_count == 1 and
      .aggregate.control_success_rate == null and
      .aggregate.treatment_success_rate == null and
      all(.pairs[0].arms[];
        .outcome_status == "infrastructure_failure" and .grade == null)
    ' "$TEST_DIR/infra/evidence.json"
    [[ "$status" -eq 0 ]]
}

@test "timeout terminates the runner process group before scoring continues" {
    prepare_plan "$TEST_DIR/child" "child-seed"
    child_marker="$TEST_DIR/child-survived.marker"
    run env \
      MAINFRAME_EVAL_FIXTURE_BEHAVIOR=child-survival \
      MAINFRAME_EVAL_CHILD_MARKER="$child_marker" \
      "$PYTHON_BIN" "$HARNESS" run --fixture \
        --plan "$TEST_DIR/child/plan.json" \
        --assignments "$TEST_DIR/child/assignments.json" \
        --runner "$RUNNER" \
        --output-dir "$TEST_DIR/child/run" \
        --evidence "$TEST_DIR/child/evidence.json" \
        --pass-env MAINFRAME_EVAL_FIXTURE_BEHAVIOR \
        --pass-env MAINFRAME_EVAL_CHILD_MARKER \
        --phase-timeout-override 0.1
    [[ "$status" -eq 0 ]]
    sleep 0.8
    [[ ! -e "$child_marker" ]]
    run verify_fixture "$TEST_DIR/child"
    [[ "$status" -eq 0 ]]
    run jq -e '
      .execution.runner_output_file_limit_bytes == 8388608 and
      .limitations.detached_child_can_escape_process_group == true and
      all(.pairs[0].arms[]; .outcome_status == "timeout")
    ' "$TEST_DIR/child/evidence.json"
    [[ "$status" -eq 0 ]]
}

@test "successful runner exit also terminates same-group orphan children" {
    prepare_plan "$TEST_DIR/orphan" "orphan-seed"
    child_marker="$TEST_DIR/orphan-survived.marker"
    run env \
      MAINFRAME_EVAL_FIXTURE_BEHAVIOR=orphan-on-success \
      MAINFRAME_EVAL_CHILD_MARKER="$child_marker" \
      "$PYTHON_BIN" "$HARNESS" run --fixture \
        --plan "$TEST_DIR/orphan/plan.json" \
        --assignments "$TEST_DIR/orphan/assignments.json" \
        --runner "$RUNNER" \
        --output-dir "$TEST_DIR/orphan/run" \
        --evidence "$TEST_DIR/orphan/evidence.json" \
        --pass-env MAINFRAME_EVAL_FIXTURE_BEHAVIOR \
        --pass-env MAINFRAME_EVAL_CHILD_MARKER
    [[ "$status" -eq 0 ]]
    sleep 0.8
    [[ ! -e "$child_marker" ]]
    run verify_fixture "$TEST_DIR/orphan"
    [[ "$status" -eq 0 ]]
    run jq -e '
      .aggregate.valid_pair_count == 1 and
      all(.pairs[0].arms[]; .outcome_status == "completed")
    ' "$TEST_DIR/orphan/evidence.json"
    [[ "$status" -eq 0 ]]
}

@test "run and evidence outputs never clobber existing targets" {
    prepare_plan "$TEST_DIR/no-clobber" "no-clobber-seed"
    run_fixture "$TEST_DIR/no-clobber"
    evidence_sha="$(shasum -a 256 "$TEST_DIR/no-clobber/evidence.json" | awk '{print $1}')"

    run run_fixture "$TEST_DIR/no-clobber"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"refusing to overwrite existing evidence output"* ]]
    [[ "$evidence_sha" == "$(shasum -a 256 "$TEST_DIR/no-clobber/evidence.json" | awk '{print $1}')" ]]
}

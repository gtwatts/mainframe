#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TOOL="$PROJECT_ROOT/scripts/dev/agent-impact-local.py"
    PROTOCOL_ROOT="$PROJECT_ROOT/evals/agent-impact"
    STUDY="$PROTOCOL_ROOT/suites/local-development-smoke-v1.json"
    TRANSPORT="$PROTOCOL_ROOT/runners/local-fake-transport.py"
    PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
    [[ -n "$PYTHON_BIN" ]] || skip "python3 is required"
    command -v jq >/dev/null || skip "jq is required"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-agent-impact-local.XXXXXX")"
    chmod 700 "$TEST_DIR"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

mode_of() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

prepare_local() {
    local root="$1" seed="${2:-local-smoke-seed}"
    mkdir -p "$root"
    chmod 700 "$root"
    "$PYTHON_BIN" "$TOOL" prepare \
        --seed "$seed" \
        --output "$root/plan.json" \
        --assignments-output "$root/assignments.json"
}

run_local() {
    local root="$1"
    shift
    "$PYTHON_BIN" "$TOOL" run --fake-transport \
        --plan "$root/plan.json" \
        --assignments "$root/assignments.json" \
        --output-dir "$root/run" \
        --evidence "$root/evidence.json" \
        "$@"
}

verify_local() {
    local root="$1"
    "$PYTHON_BIN" "$TOOL" verify \
        --plan "$root/plan.json" \
        --assignments "$root/assignments.json" \
        --output-dir "$root/run" \
        --evidence "$root/evidence.json"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

@test "closed local schemas and CLI expose fake transport only" {
    local schema
    for schema in \
        local-study.schema.json local-task.schema.json local-plan.schema.json \
        local-assignments.schema.json local-runner-request.schema.json \
        local-runner-result.schema.json local-transition-receipt.schema.json \
        local-ledger-record.schema.json local-private-records.schema.json \
        local-evidence.schema.json; do
        run jq -e '.type == "object" and .additionalProperties == false' \
            "$PROTOCOL_ROOT/$schema"
        [[ "$status" -eq 0 ]]
    done

    run "$PYTHON_BIN" "$TOOL" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"fake transport only"* ]]
    run "$PYTHON_BIN" "$TOOL" run --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--fake-transport"* ]]
    [[ "$output" != *"ollama"* ]]
    [[ "$output" != *"provider"* ]]

    safety_job="$(awk '
      /^  test-safety:/ { in_job = 1 }
      /^  test-linux:/ { in_job = 0 }
      in_job { print }
    ' "$PROJECT_ROOT/.github/workflows/test.yml")"
    [[ "$safety_job" == *"os: [ubuntu-latest, macos-latest]"* ]]
    [[ "$safety_job" == *"actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065"* ]]
    [[ "$safety_job" == *"python-version: '3.9'"* ]]
    [[ "$safety_job" == *"tests/agent_impact_local.bats"* ]]

    run jq -e '
      .properties.claim_scope.const ==
        "local-development-smoke-protocol-conformance-only" and
      .properties.execution.properties.mode.const ==
        "deterministic-fake-transport-only" and
      .properties.non_claims.const.mainframe_benefit == "not-measured" and
      .properties.limitations.const.os_isolation == "not-provided" and
      .properties.limitations.const.assignment_blinding ==
        "request-and-environment-omission-only-same-uid-not-adversarial"
    ' "$PROTOCOL_ROOT/local-evidence.schema.json"
    [[ "$status" -eq 0 ]]
}

@test "prepare is deterministic opaque exactly three-pair private and no-clobber" {
    run prepare_local "$TEST_DIR/first" same-seed
    [[ "$status" -eq 0 ]]
    run prepare_local "$TEST_DIR/second" same-seed
    [[ "$status" -eq 0 ]]
    cmp "$TEST_DIR/first/plan.json" "$TEST_DIR/second/plan.json"
    cmp "$TEST_DIR/first/assignments.json" "$TEST_DIR/second/assignments.json"
    [[ "$(mode_of "$TEST_DIR/first/assignments.json")" == 600 ]]
    [[ "$(mode_of "$TEST_DIR/first/plan.json")" == 644 ]]

    run jq -e '
      .pair_count == 3 and (.pairs | length) == 3 and
      ([.pairs[].replicate] == [1,2,3]) and
      all(.pairs[]; (.opaque_arm_order | length) == 2) and
      (.binding.harness_basename == "agent-impact-local.py") and
      (.binding.harness_sha256 | test("^[0-9a-f]{64}$")) and
      ((tostring | contains("control")) | not) and
      ((tostring | contains("treatment")) | not) and
      ((tostring | contains("arm_mode")) | not)
    ' "$TEST_DIR/first/plan.json"
    [[ "$status" -eq 0 ]]

    before="$(sha256_file "$TEST_DIR/first/plan.json")"
    run prepare_local "$TEST_DIR/first" same-seed
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to overwrite existing"* ]]
    [[ "$before" == "$(sha256_file "$TEST_DIR/first/plan.json")" ]]
}

@test "three paired fake requests omit assignments and remain equal fresh and exactly verifiable" {
    prepare_local "$TEST_DIR/e2e" e2e-seed
    export MAINFRAME_LOCAL_AMBIENT_SECRET=must-not-leak
    run run_local "$TEST_DIR/e2e"
    unset MAINFRAME_LOCAL_AMBIENT_SECRET
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"3 pairs, 12 fake phase attempts"* ]]
    [[ "$output" == *"3 ties; paired delta 0"* ]]

    run verify_local "$TEST_DIR/e2e"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"real agent/provider/Pi/Ollama sessions: 0"* ]]

    run jq -e '
      .claim_scope == "local-development-smoke-protocol-conformance-only" and
      .protocol.assignment_reveal_embedded_in_local_evidence == true and
      .protocol.external_publication == "not-performed" and
      .protocol.private_reveal_available_to_harness == true and
      .runtime.mainframe_runtime_exercised == false and
      .runtime.mainframe_awm_exercised == false and
      .runtime.pi_runtime_exercised == false and
      .runtime.ollama_runtime_exercised == false and
      .execution.mode == "deterministic-fake-transport-only" and
      .execution.attempt_count == 12 and
      .execution.live_agent_sessions == 0 and
      .execution.pi_sessions == 0 and
      .execution.provider_sessions == 0 and
      .execution.provider_requests == 0 and
      .execution.network_requests == 0 and
      .aggregate == {
        control_mean_normalized_score: 1,
        control_solved_count: 3,
        invalid_pair_count: 0,
        pair_count: 3,
        paired_mean_normalized_score_delta: 0,
        ties: 3,
        treatment_losses: 0,
        treatment_mean_normalized_score: 1,
        treatment_solved_count: 3,
        treatment_wins: 0,
        valid_pair_count: 3
      } and
      .statistics.primary.exact_sign_flip == {
        assignments_enumerated: 8,
        extreme_assignments: 8,
        p_value: 1,
        two_sided: true
      } and
      .statistics.primary.bootstrap.lower == 0 and
      .statistics.primary.bootstrap.upper == 0 and
      .statistics.secondary.p_value == 1 and
      .non_claims.mainframe_benefit == "not-measured" and
      .limitations.network_denial == "not-enforced-by-os-sandbox"
    ' "$TEST_DIR/e2e/evidence.json"
    [[ "$status" -eq 0 ]]

    [[ "$(wc -l < "$TEST_DIR/e2e/run/attempt-ledger.jsonl" | tr -d ' ')" == 12 ]]
    [[ "$(find "$TEST_DIR/e2e/run" -name request.json | wc -l | tr -d ' ')" == 12 ]]
    [[ "$(jq -r '.. | objects | .fresh_state_id? // empty' "$TEST_DIR/e2e/run/records.json" | sort -u | wc -l | tr -d ' ')" == 12 ]]
    run grep -E '"(control|treatment|arm_mode|mechanism)"' \
        $(find "$TEST_DIR/e2e/run" -name request.json -print)
    [[ "$status" -ne 0 ]]
    run grep -R -F 'must-not-leak' "$TEST_DIR/e2e"
    [[ "$status" -ne 0 ]]
    run find "$TEST_DIR/e2e/run" -path '*/workspace/grade.py' -print -quit
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    run jq -e '
      all(.pairs[];
        ([.arms[].transition.continuation.sha256] | unique | length) == 1 and
        ([.arms[].grade.score] | unique) == [100])
    ' "$TEST_DIR/e2e/evidence.json"
    [[ "$status" -eq 0 ]]
}

@test "assignment leak checks allow ordinary paths containing control-plane" {
    local root="$TEST_DIR/mainframe-control-plane/e2e"
    prepare_local "$root" control-plane-path-seed

    run run_local "$root"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"3 pairs, 12 fake phase attempts"* ]]

    run verify_local "$root"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"real agent/provider/Pi/Ollama sessions: 0"* ]]
}

@test "offline verifier rejects request result ledger continuation tree and evidence tampering" {
    prepare_local "$TEST_DIR/tamper" tamper-seed
    run_local "$TEST_DIR/tamper"

    request="$(find "$TEST_DIR/tamper/run" -name request.json | head -1)"
    cp "$request" "$TEST_DIR/request.original"
    jq '.task_id = "changed"' "$request" > "$TEST_DIR/request.changed"
    mv "$TEST_DIR/request.changed" "$request"
    chmod 600 "$request"
    run verify_local "$TEST_DIR/tamper"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"request"*"digest changed"* ]]
    cp "$TEST_DIR/request.original" "$request"
    chmod 600 "$request"

    result="$(find "$TEST_DIR/tamper/run" -name result.json | head -1)"
    cp "$result" "$TEST_DIR/result.original"
    jq '.provider_requests = 1' "$result" > "$TEST_DIR/result.changed"
    mv "$TEST_DIR/result.changed" "$result"
    chmod 600 "$result"
    run verify_local "$TEST_DIR/tamper"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"result"*"digest changed"* ]]
    cp "$TEST_DIR/result.original" "$result"
    chmod 600 "$result"

    ledger="$TEST_DIR/tamper/run/attempt-ledger.jsonl"
    cp "$ledger" "$TEST_DIR/ledger.original"
    sed '1s/"sequence":1/"sequence":2/' "$ledger" > "$TEST_DIR/ledger.changed"
    mv "$TEST_DIR/ledger.changed" "$ledger"
    chmod 600 "$ledger"
    run verify_local "$TEST_DIR/tamper"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"ledger"*"digest changed"* ]]
    cp "$TEST_DIR/ledger.original" "$ledger"
    chmod 600 "$ledger"

    continuation="$(find "$TEST_DIR/tamper/run" -name neutral-continuation.txt | head -1)"
    cp "$continuation" "$TEST_DIR/continuation.original"
    printf 'tampered\n' >> "$continuation"
    run verify_local "$TEST_DIR/tamper"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"continuation"*"digest changed"* ]]
    cp "$TEST_DIR/continuation.original" "$continuation"
    chmod 600 "$continuation"

    workspace_source="$(find "$TEST_DIR/tamper/run" -path '*/workspace/config_merge.py' | head -1)"
    cp "$workspace_source" "$TEST_DIR/workspace.original"
    printf '# tampered\n' >> "$workspace_source"
    run verify_local "$TEST_DIR/tamper"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"final tree snapshot"* || "$output" == *"workspace"* ]]
    cp "$TEST_DIR/workspace.original" "$workspace_source"

    cp "$TEST_DIR/tamper/evidence.json" "$TEST_DIR/evidence.original"
    jq '.non_claims.mainframe_benefit = "measured"' \
        "$TEST_DIR/evidence.original" > "$TEST_DIR/tamper/evidence.json"
    chmod 600 "$TEST_DIR/tamper/evidence.json"
    run verify_local "$TEST_DIR/tamper"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"non-claims were weakened"* ]]
}

@test "study and private reveal reject symlinks hardlinks and broad permissions" {
    study_link="$TEST_DIR/study-link.json"
    ln -s "$STUDY" "$study_link"
    run "$PYTHON_BIN" "$TOOL" prepare \
        --study "$study_link" --seed bad \
        --output "$TEST_DIR/plan.json" \
        --assignments-output "$TEST_DIR/assignments.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"regular, non-symlink"* ]]

    prepare_local "$TEST_DIR/private" private-seed
    ln "$TEST_DIR/private/assignments.json" "$TEST_DIR/private/assignments.alias"
    run run_local "$TEST_DIR/private"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"exactly one hard link"* ]]
    rm "$TEST_DIR/private/assignments.alias"
    chmod 644 "$TEST_DIR/private/assignments.json"
    run run_local "$TEST_DIR/private"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"must not grant group or other permissions"* ]]
    [[ ! -e "$TEST_DIR/private/run" ]]
}

@test "successful fake transport cannot leave same-group children mutating the run" {
    prepare_local "$TEST_DIR/orphan" orphan-seed
    run run_local "$TEST_DIR/orphan" --fake-behavior orphan-on-success
    [[ "$status" -eq 0 ]]
    sleep 0.8
    [[ ! -e "$TEST_DIR/orphan/run/.orphan-survived.marker" ]]
    run grep -R -F 'mutated' "$TEST_DIR/orphan/run" \
        --include='config_merge.py'
    [[ "$status" -ne 0 ]]
    run verify_local "$TEST_DIR/orphan"
    [[ "$status" -eq 0 ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/awm-context-budget.bats
# Bounded Agent Working Memory context and handoff contracts
# =============================================================================

load "${BATS_TEST_DIRNAME}/../bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/../bats-assert/load.bash"

setup() {
    local physical_test_tmp
    physical_test_tmp="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export AWM_ROOT="${physical_test_tmp}/awm-context-budget"
    export AWM_CHARS_PER_TOKEN=3
    export AWM_SCHEMA_VERSION=2
    export AWM_CONTEXT_DISCOVERY_LIMIT=12
    export AWM_CONTEXT_LOG_LIMIT=8
    export MAINFRAME_AGENT_NAME="budget-parent-agent"

    source "${MAINFRAME_ROOT}/lib/awm.sh"
    mkdir -p "$AWM_ROOT"

    _AWM_SESSION_ID=""
    _AWM_SESSION_DIR=""
    _AWM_NAMESPACE=""

    command -v jq >/dev/null || skip "jq is required for exact JSON contract assertions"
}

teardown() {
    awm_close >/dev/null 2>&1 || true
    rm -rf -- "$AWM_ROOT" 2>/dev/null || true
}

output_chars() {
    LC_ALL=C printf '%s' "$1" | wc -c | tr -d '[:space:]'
}

estimated_tokens() {
    local chars="$1"
    printf '%d' "$(((chars + AWM_CHARS_PER_TOKEN - 1) / AWM_CHARS_PER_TOKEN))"
}

assert_within_context_budget() {
    local document="$1"
    local requested_tokens="$2"
    local actual_chars max_chars

    actual_chars=$(output_chars "$document")
    max_chars=$((requested_tokens * AWM_CHARS_PER_TOKEN))

    if ((actual_chars > max_chars)); then
        printf 'context budget exceeded: requested_tokens=%d chars_per_token=%d max_chars=%d actual_chars=%d\n' \
            "$requested_tokens" "$AWM_CHARS_PER_TOKEN" "$max_chars" "$actual_chars" >&2
        return 1
    fi
}

assert_json_budget_metadata() {
    local document="$1"
    local requested_tokens="$2"
    local expected_truncated="$3"
    local actual_chars actual_tokens max_chars

    actual_chars=$(output_chars "$document")
    actual_tokens=$(estimated_tokens "$actual_chars")
    max_chars=$((requested_tokens * AWM_CHARS_PER_TOKEN))

    jq -e \
        --argjson requested_tokens "$requested_tokens" \
        --argjson chars_per_token "$AWM_CHARS_PER_TOKEN" \
        --argjson max_chars "$max_chars" \
        --argjson actual_chars "$actual_chars" \
        --argjson actual_tokens "$actual_tokens" \
        --argjson truncated "$expected_truncated" \
        '.budget.requested_tokens == $requested_tokens and
         .budget.chars_per_token == $chars_per_token and
         .budget.max_chars == $max_chars and
         .budget.actual_chars == $actual_chars and
         .budget.actual_tokens == $actual_tokens and
         .budget.truncated == $truncated' <<<"$document" >/dev/null
}

assert_prompt_budget_metadata() {
    local document="$1"
    local requested_tokens="$2"
    local expected_truncated="$3"
    local actual_chars actual_tokens max_chars

    actual_chars=$(output_chars "$document")
    actual_tokens=$(estimated_tokens "$actual_chars")
    max_chars=$((requested_tokens * AWM_CHARS_PER_TOKEN))

    [[ "$document" == *"Budget:"* ]]
    [[ "$document" == *"requested_tokens=${requested_tokens}"* ]]
    [[ "$document" == *"chars_per_token=${AWM_CHARS_PER_TOKEN}"* ]]
    [[ "$document" == *"max_chars=${max_chars}"* ]]
    [[ "$document" == *"actual_chars=${actual_chars}"* ]]
    [[ "$document" == *"actual_tokens=${actual_tokens}"* ]]
    [[ "$document" == *"truncated=${expected_truncated}"* ]]
}

seed_oversized_session() {
    local sid filler i

    sid=$(awm_init "budget-session" --namespace "budget-team" --backend file)
    awm_resume "$sid" >/dev/null

    printf -v filler '%*s' 700 ''
    filler=${filler// /x}

    awm_discovery \
        "bounded task CRITICAL_BUDGET_SENTINEL" \
        --importance critical \
        --tags identity,provenance
    awm_log "questions" "bounded task open question" --importance high

    for i in 1 2; do
        awm_log \
            "decisions" \
            "bounded task log ${i} ${filler}" \
            --importance low
        awm_checkpoint \
            "bounded_task_checkpoint_${i}" \
            "bounded task value ${i} ${filler}" \
            --importance low
    done

    SEEDED_SESSION_ID="$sid"
}

@test "awm_context_for json bounds oversized output using --tokens times AWM_CHARS_PER_TOKEN" {
    local budget=640 document
    seed_oversized_session

    run awm_context_for "bounded task" --tokens "$budget" --format json
    assert_success
    document="$output"
    output=""

    json_valid "$document"
    assert_within_context_budget "$document" "$budget"
}

@test "awm_context_for json reports exact budget metadata and preserves critical provenance" {
    local budget=640 sid document
    seed_oversized_session
    sid="$SEEDED_SESSION_ID"

    run awm_context_for "bounded task" --tokens "$budget" --format json
    assert_success
    document="$output"
    output=""

    assert_json_budget_metadata "$document" "$budget" true
    jq -e \
        --arg sid "$sid" \
        --arg agent "$MAINFRAME_AGENT_NAME" \
        '.task == "bounded task" and
         .session_id == $sid and
         .provenance.schema_version == 2 and
         .provenance.namespace == "budget-team" and
         .provenance.backend == "file" and
         .provenance.source_agent == $agent and
         (.discoveries | tostring | contains("CRITICAL_BUDGET_SENTINEL"))' \
        <<<"$document" >/dev/null
}

@test "awm_context_for json reports truncated false when the complete package fits" {
    local budget=2048 sid document
    sid=$(awm_init "small-context" --namespace "budget-team" --backend file)
    awm_resume "$sid" >/dev/null

    run awm_context_for "small task" --tokens "$budget" --format json
    assert_success
    document="$output"
    output=""

    json_valid "$document"
    assert_within_context_budget "$document" "$budget"
    assert_json_budget_metadata "$document" "$budget" false
}

@test "awm_context_for prompt bounds oversized output using --tokens times AWM_CHARS_PER_TOKEN" {
    local budget=640 document
    seed_oversized_session

    run awm_context_for "bounded task" --tokens "$budget" --format prompt
    assert_success
    document="$output"
    output=""

    assert_within_context_budget "$document" "$budget"
}

@test "awm_context_for prompt reports exact budget metadata and preserves critical provenance" {
    local budget=640 sid document
    seed_oversized_session
    sid="$SEEDED_SESSION_ID"

    run awm_context_for "bounded task" --tokens "$budget" --format prompt
    assert_success
    document="$output"
    output=""

    assert_prompt_budget_metadata "$document" "$budget" true
    [[ "$document" == *"Task: bounded task"* ]]
    [[ "$document" == *"Session ID: ${sid}"* ]]
    [[ "$document" == *"Provenance:"* ]]
    [[ "$document" == *"schema_version=2"* ]]
    [[ "$document" == *"namespace=budget-team"* ]]
    [[ "$document" == *"backend=file"* ]]
    [[ "$document" == *"source_agent=${MAINFRAME_AGENT_NAME}"* ]]
    [[ "$document" == *"CRITICAL_BUDGET_SENTINEL"* ]]
}

@test "awm_handoff_prepare json keeps the complete outer package valid and within budget" {
    local budget=640 document
    seed_oversized_session

    run awm_handoff_prepare "bounded task reviewer" --tokens "$budget" --format json
    assert_success
    document="$output"
    output=""

    json_valid "$document"
    assert_within_context_budget "$document" "$budget"
    jq -e '.context | type == "object"' <<<"$document" >/dev/null
}

@test "awm_handoff_prepare json preserves provenance and reports outer and nested truncation" {
    local budget=640 sid document handoff_id handoff_file
    seed_oversized_session
    sid="$SEEDED_SESSION_ID"

    run awm_handoff_prepare "bounded task reviewer" --tokens "$budget" --format json
    assert_success
    document="$output"
    output=""

    assert_json_budget_metadata "$document" "$budget" true
    jq -e \
        --arg sid "$sid" \
        --arg agent "$MAINFRAME_AGENT_NAME" \
        --argjson chars_per_token "$AWM_CHARS_PER_TOKEN" \
        '.type == "handoff" and
         .parent_session == $sid and
         .parent_agent == $agent and
         .target_agent == "bounded task reviewer" and
         .provenance.schema_version == 2 and
         .provenance.namespace == "budget-team" and
         .provenance.backend == "file" and
         (.context | type == "object") and
         .context.task == "bounded task reviewer" and
         .context.session_id == $sid and
         .context.provenance.schema_version == 2 and
         .context.provenance.namespace == "budget-team" and
         .context.provenance.backend == "file" and
         .context.budget.chars_per_token == $chars_per_token and
         .context.budget.actual_chars <= .context.budget.max_chars and
         .context.budget.truncated == true and
         (.context.discoveries | tostring | contains("CRITICAL_BUDGET_SENTINEL"))' \
        <<<"$document" >/dev/null

    handoff_id=$(jq -r '.handoff_id' <<<"$document")
    handoff_file="${_AWM_SESSION_DIR}/handoffs/${handoff_id}.json"
    [[ -f "$handoff_file" ]]
    [[ "$(<"$handoff_file")" == "$document" ]]
    json_valid "$(<"$handoff_file")"
}

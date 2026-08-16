#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TOOL="$PROJECT_ROOT/scripts/dev/agent-impact-preregister.py"
    SOURCE_PROTOCOL="$PROJECT_ROOT/evals/agent-impact"
    LIVE_SCHEMA="$SOURCE_PROTOCOL/live-study.schema.json"
    PREREG_SCHEMA="$SOURCE_PROTOCOL/preregistration.schema.json"
    PYTHON_BIN="$(command -v python3)"
    export PYTHONDONTWRITEBYTECODE=1
    [[ -n "$PYTHON_BIN" ]] || skip "python3 is required"
    command -v jq >/dev/null || skip "jq is required"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-agent-impact-prereg.XXXXXX")"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

mode_of() {
    local path="$1"
    if stat -c '%a' "$path" >/dev/null 2>&1; then
        stat -c '%a' "$path"
    else
        stat -f '%Lp' "$path"
    fi
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

create_fixture() {
    local root="$1"
    mkdir -p "$root"
    cp -R "$SOURCE_PROTOCOL" "$root/protocol"

    cp -R "$root/protocol/tasks/conformance-001" \
        "$root/protocol/tasks/conformance-002"
    cp -R "$root/protocol/tasks/conformance-001" \
        "$root/protocol/tasks/conformance-003"
    local task_id
    for task_id in conformance-001 conformance-002 conformance-003; do
        jq --arg task_id "$task_id" '
          .id = $task_id |
          .title = ("Live fixture " + $task_id) |
          .transition.context_budget.maximum = 8192 |
          .budgets.wall_seconds_per_phase = 900 |
          .budgets.maximum_tool_calls_per_phase = 40
        ' "$root/protocol/tasks/$task_id/task.json" \
            > "$root/task.tmp"
        mv "$root/task.tmp" "$root/protocol/tasks/$task_id/task.json"
    done
    jq '.tasks = [
      "tasks/conformance-001/task.json",
      "tasks/conformance-002/task.json",
      "tasks/conformance-003/task.json"
    ]' "$root/protocol/suites/conformance-v1.json" > "$root/suite.tmp"
    mv "$root/suite.tmp" "$root/protocol/suites/conformance-v1.json"

    mkdir -p "$root/runner" "$root/release" "$root/policies"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf invoked > "${PREREG_MARKER:?}"' \
        'exit 70' > "$root/runner/live-runner"
    chmod 700 "$root/runner/live-runner"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf adapter-invoked > "${PREREG_MARKER:?}"' \
        'exit 70' > "$root/runner/provider-adapter"
    chmod 700 "$root/runner/provider-adapter"
    printf '%s\n' '{"type":"object","additionalProperties":false}' \
        > "$root/runner/adapter-request.schema.json"
    printf '%s\n' '{"type":"object","additionalProperties":false}' \
        > "$root/runner/adapter-result.schema.json"
    printf '%s\n' '{' \
        '  "schema_version": 1,' \
        '  "kind": "mainframe-agent-impact-live-runner-manifest",' \
        '  "runner_id": "fixture-runner",' \
        '  "runner_version": "1.0.0",' \
        '  "adapter": {' \
        '    "id": "fixture-adapter",' \
        '    "version": "2.0.0",' \
        '    "provider": "fixture-provider",' \
        '    "executable": "runner/provider-adapter",' \
        '    "request_schema": "runner/adapter-request.schema.json",' \
        '    "result_schema": "runner/adapter-result.schema.json"' \
        '  },' \
        '  "permitted_environment_names": ["HOME", "LANG", "PATH", "TMPDIR"]' \
        '}' > "$root/runner/manifest.json"
    printf '%s\n' 'sealed-mainframe-release-fixture' \
        > "$root/release/mainframe-fixture.tar.gz"
    archive_sha="$(sha256_of "$root/release/mainframe-fixture.tar.gz")"
    printf '%s  %s\n' "$archive_sha" 'mainframe-fixture.tar.gz' \
        > "$root/release/mainframe-fixture.tar.gz.sha256"
    printf '%s\n' \
        '{"schema_version":1,"kind":"mainframe-agent-impact-isolation-policy","id":"fixture-isolation","controls":{"boundary":"fresh-container-vm-or-separate-os-user","task_source":"byte-identical-read-only","workspace":"private-writable-per-arm","fresh_state":["cache","configuration","home","process","provider-session","temporary-directory","xdg"],"hidden_inputs":"not-mounted-or-readable","cross_arm_state":"none","resource_termination":"whole-workload-before-grading","network_egress":"default-deny-provider-proxy-only","grader":"outside-agent-boundary-network-denied-after-stop"}}' \
        > "$root/policies/isolation.policy"
    printf '%s\n' \
        '{"schema_version":1,"kind":"mainframe-agent-impact-provider-proxy-policy","id":"fixture-provider-proxy","controls":{"credentials":"outside-agent-environment","network_route":"sole-provider-egress-route","request_scope":["arm","model","pair","parameters","phase","provider","study"],"unregistered_invocation":"reject","duplicate_invocation":"reject","call_and_token_policy":"enforce-where-provider-supports","audit_record":"credential-free-append-only","direct_provider_access":"invalidates-run"}}' \
        > "$root/policies/provider-proxy.policy"
    printf '%s\n' \
        '{"schema_version":1,"kind":"mainframe-agent-impact-awm-mechanism-contract","id":"fixture-awm-contract","controls":{"control_comparator":"native-bounded-handoff","treatment_intervention":"mainframe-awm-handoff","writes":"recorded","state_receipts":"before-and-after-each-phase","export":"bounded-read-only-neutral-continuation-envelope","context_limit_unit":"bytes-under-LC_ALL-C","executable_binding":"release-and-installed-tree","arm_label_assertion":"insufficient-proof"}}' \
        > "$root/policies/awm-mechanism.contract"
    printf '%s' 'sixteen-byte-seed' > "$root/assignment.seed"
    chmod 600 "$root/assignment.seed"

    printf '%s\n' '{' \
        '  "schema_version": 2,' \
        '  "kind": "mainframe-agent-impact-live-study",' \
        '  "id": "live-v2-fixture",' \
        '  "title": "Preregistered live v2 fixture",' \
        '  "hypothesis": "A bounded MAINFRAME AWM handoff improves a fresh implementation session'"'"'s hidden grader score relative to an equally bounded native/manual handoff for a pinned provider, model, and fixed coding-task suite.",' \
        '  "stage": "pilot",' \
        '  "task_classes": [' \
        '    "nested-configuration-precedence-and-falsy-merge",' \
        '    "checkpoint-after-commit-idempotency",' \
        '    "safe-manifest-include"' \
        '  ],' \
        '  "suite": "protocol/suites/conformance-v1.json",' \
        '  "replicates_per_task": 6,' \
        '  "planned_runner": {' \
        '    "executable": "runner/live-runner",' \
        '    "manifest": "runner/manifest.json"' \
        '  },' \
        '  "mainframe_release": {' \
        '    "archive": "release/mainframe-fixture.tar.gz",' \
        '    "checksum_sidecar": "release/mainframe-fixture.tar.gz.sha256",' \
        '    "installed_tree_algorithm": "mainframe-package-tree-sha256-v1",' \
        '    "installed_tree_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"' \
        '  },' \
        '  "container_image_digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",' \
        '  "isolation_policy": "policies/isolation.policy",' \
        '  "provider_proxy_policy": "policies/provider-proxy.policy",' \
        '  "awm_mechanism_contract": "policies/awm-mechanism.contract",' \
        '  "host_environment": {' \
        '    "operating_system": "macos",' \
        '    "architecture": "arm64",' \
        '    "shell": {' \
        '      "name": "zsh",' \
        '      "version": "5.9",' \
        '      "executable_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
        '    }' \
        '  },' \
        '  "provider": {' \
        '    "name": "fixture-provider",' \
        '    "model": "fixture-model",' \
        '    "model_snapshot": "fixture-model-2026-08-08",' \
        '    "client": {"name": "fixture-sdk", "version": "1.2.3"},' \
        '    "host": {"name": "fixture-host", "version": "4.5.6"},' \
        '    "configuration": {' \
        '      "temperature": 0,' \
        '      "top_p": 1,' \
        '      "provider_seed": 8675309,' \
        '      "tool_choice": "auto",' \
        '      "reasoning_effort": "medium"' \
        '    }' \
        '  },' \
        '  "budgets": {' \
        '    "wall_seconds_per_phase": 900,' \
        '    "maximum_tool_calls_per_phase": 40,' \
        '    "maximum_context_bytes": 8192,' \
        '    "maximum_input_tokens_per_phase": 8192,' \
        '    "maximum_output_tokens_per_phase": 4096,' \
        '    "maximum_cost_usd_per_pair": 5' \
        '  },' \
        '  "endpoint": {' \
        '    "primary": "equal-task-weighted-paired-normalized-score-delta",' \
        '    "secondary": "paired-binary-solve-status",' \
        '    "direction": "higher-is-better",' \
        '    "unit": "normalized-task-score"' \
        '  },' \
        '  "statistics": {' \
        '    "estimator": "equal-task-weighted-mean-paired-normalized-score-delta",' \
        '    "randomization_test": "exact-task-blocked-sign-flip",' \
        '    "secondary_test": "two-sided-exact-mcnemar",' \
        '    "confidence_interval": "task-stratified-paired-bootstrap",' \
        '    "bootstrap_random_number_algorithm": "sha256-counter-prng-v1",' \
        '    "bootstrap_seed": 24680,' \
        '    "bootstrap_resamples": 10000,' \
        '    "confidence_level": 0.95,' \
        '    "alpha": 0.05' \
        '  },' \
        '  "exclusions": {' \
        '    "infrastructure_failure": "invalidate-complete-pair-and-publish",' \
        '    "agent_failure": "score-as-observed-no-exclusion",' \
        '    "missing_arm": "invalidate-complete-pair-and-publish",' \
        '    "reruns": "no-silent-reruns-publish-every-attempt"' \
        '  },' \
        '  "stopping": {' \
        '    "minimum_valid_pairs": 18,' \
        '    "maximum_planned_pairs": 18,' \
        '    "rule": "run-all-preregistered-pairs-no-optional-stopping"' \
        '  },' \
        '  "publication": {' \
        '    "publish_preregistration_before_first_session": true,' \
        '    "publish_assignment_reveal_after_scoring": true,' \
        '    "publish_all_attempts": true,' \
        '    "publish_invalid_pairs": true,' \
        '    "raw_artifacts": "private-hash-bound"' \
        '  }' \
        '}' > "$root/study.json"
}

prepare_fixture() {
    local root="$1" seed="${2:-sixteen-byte-seed}"
    printf '%s' "$seed" > "$root/assignment.seed"
    chmod 600 "$root/assignment.seed"
    PREREG_MARKER="$root/runner-invoked" "$PYTHON_BIN" "$TOOL" prepare \
        --study "$root/study.json" \
        --seed-file "$root/assignment.seed" \
        --output "$root/preregistration.json" \
        --assignments-output "$root/private-assignments.json"
}

verify_fixture() {
    local root="$1" seed="${2:-sixteen-byte-seed}"
    printf '%s' "$seed" > "$root/assignment.seed"
    chmod 600 "$root/assignment.seed"
    PREREG_MARKER="$root/runner-invoked" "$PYTHON_BIN" "$TOOL" verify \
        --study "$root/study.json" \
        --seed-file "$root/assignment.seed" \
        --preregistration "$root/preregistration.json" \
        --assignments "$root/private-assignments.json"
}

@test "v2 schemas are strict no-run contracts and CLI exposes no execution action" {
    run jq -e '
      .additionalProperties == false and
      .properties.replicates_per_task.minimum == 6 and
      .properties.replicates_per_task.multipleOf == 2 and
      (.required | index("stage") != null) and
      (.required | index("task_classes") != null) and
      (.required | index("hypothesis") != null) and
      (.required | index("isolation_policy") != null) and
      (.required | index("provider_proxy_policy") != null) and
      (.required | index("awm_mechanism_contract") != null) and
      (.required | index("host_environment") != null) and
      ."$defs".budgets.properties.wall_seconds_per_phase.const == 900 and
      ."$defs".budgets.properties.maximum_tool_calls_per_phase.const == 40 and
      ."$defs".budgets.properties.maximum_context_bytes.const == 8192 and
      ."$defs".endpoint.properties.primary.const ==
        "equal-task-weighted-paired-normalized-score-delta" and
      ."$defs".statistics.properties.randomization_test.const ==
        "exact-task-blocked-sign-flip" and
      ."$defs".statistics.properties.confidence_interval.const ==
        "task-stratified-paired-bootstrap" and
      ."$defs".statistics.properties.bootstrap_resamples.minimum == 10000 and
      ([.allOf[].then.properties.stopping.properties.minimum_valid_pairs.const // empty] |
        sort) == [18,36,60]
    ' "$LIVE_SCHEMA"
    [[ "$status" -eq 0 ]]

    run jq -e '
      .additionalProperties == false and
      .properties.claim_scope.const == "preregistered-live-study-not-run" and
      .properties.execution_status.const == "not-run" and
      .properties.non_claims.properties.live_agent_sessions.const == 0 and
      (.properties.bindings.required | index("policies") != null) and
      (.required | index("randomization_context_sha256") != null) and
      ([.allOf[].then.properties.planned_pair_count.const // empty] | sort) == [18,36,60] and
      ([.allOf[].then.properties.pairs.maxItems // empty] | sort) == [18,36,60]
    ' "$PREREG_SCHEMA"
    [[ "$status" -eq 0 ]]

    run "$PYTHON_BIN" -c '
import json, sys
from urllib.parse import urldefrag, urljoin
live = json.load(open(sys.argv[1], encoding="utf-8"))
prereg = json.load(open(sys.argv[2], encoding="utf-8"))
external = []
def walk(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "$ref" and not child.startswith("#"):
                external.append(child)
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)
walk(prereg)
assert external
for reference in external:
    base, fragment = urldefrag(urljoin(prereg["$id"], reference))
    assert base == live["$id"], (base, live["$id"])
    target = live
    for component in fragment.lstrip("/").split("/"):
        target = target[component.replace("~1", "/").replace("~0", "~")]
' "$LIVE_SCHEMA" "$PREREG_SCHEMA"
    [[ "$status" -eq 0 ]]

    run "$PYTHON_BIN" "$TOOL" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"{prepare,verify}"* ]]
    [[ "$output" != *"{prepare,verify,run}"* ]]
    run "$PYTHON_BIN" "$TOOL" prepare --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--seed-file"* ]]
    [[ "$output" != *"--seed SEED"* ]]
    run rg -n 'subprocess|Popen|os\.system|execv|posix_spawn' "$TOOL"
    [[ "$status" -eq 1 ]]
    [[ -x "$TOOL" ]]
}

@test "prepare is deterministic opaque balanced private and no-clobber" {
    create_fixture "$TEST_DIR/first"
    create_fixture "$TEST_DIR/second"
    run prepare_fixture "$TEST_DIR/first"
    [[ "$status" -eq 0 ]]
    run prepare_fixture "$TEST_DIR/second"
    [[ "$status" -eq 0 ]]

    cmp "$TEST_DIR/first/preregistration.json" "$TEST_DIR/second/preregistration.json"
    cmp "$TEST_DIR/first/private-assignments.json" "$TEST_DIR/second/private-assignments.json"
    [[ "$(mode_of "$TEST_DIR/first/preregistration.json")" == 644 ]]
    [[ "$(mode_of "$TEST_DIR/first/private-assignments.json")" == 600 ]]
    [[ ! -e "$TEST_DIR/first/runner-invoked" ]]
    run rg -n 'sixteen-byte-seed' \
        "$TEST_DIR/first/preregistration.json" \
        "$TEST_DIR/first/private-assignments.json"
    [[ "$status" -eq 1 ]]

    run jq -e '
      .claim_scope == "preregistered-live-study-not-run" and
      .execution_status == "not-run" and
      .design.hypothesis ==
        "A bounded MAINFRAME AWM handoff improves a fresh implementation session'"'"'s hidden grader score relative to an equally bounded native/manual handoff for a pinned provider, model, and fixed coding-task suite." and
      .non_claims.live_agent_sessions == 0 and
      .planned_pair_count == 18 and
      (.pairs | length) == 18 and
      all(.pairs[]; (.opaque_arm_order | length) == 2) and
      (.bindings.planned_runner.executable_sha256 | test("^[0-9a-f]{64}$")) and
      (.bindings.mainframe_release.archive_sha256 | test("^[0-9a-f]{64}$")) and
      (.bindings.policies.isolation.sha256 | test("^[0-9a-f]{64}$")) and
      (.bindings.policies.provider_proxy.sha256 | test("^[0-9a-f]{64}$")) and
      (.bindings.policies.awm_mechanism_contract.sha256 | test("^[0-9a-f]{64}$")) and
      .bindings.mainframe_release.installed_tree_algorithm ==
        "mainframe-package-tree-sha256-v1" and
      (.bindings.mainframe_release.installed_tree_sha256 | test("^[0-9a-f]{64}$")) and
      .bindings.planned_runner.adapter.id == "fixture-adapter" and
      .bindings.planned_runner.executable_mode == "0700" and
      .bindings.planned_runner.adapter.executable_mode == "0700" and
      .bindings.planned_runner.permitted_environment_names ==
        ["HOME", "LANG", "PATH", "TMPDIR"] and
      (.bindings.preregistration_protocol | length) == 4 and
      any(.bindings.preregistration_protocol[];
        .path == "docs/AGENT_IMPACT_LIVE_STUDY.md") and
      .bindings.policies.isolation.controls.network_egress ==
        "default-deny-provider-proxy-only" and
      .bindings.policies.provider_proxy.controls.credentials ==
        "outside-agent-environment" and
      .bindings.policies.awm_mechanism_contract.controls.state_receipts ==
        "before-and-after-each-phase" and
      .design.host_environment.shell.name == "zsh" and
      (.randomization_context_sha256 | test("^[0-9a-f]{64}$")) and
      ((.pairs | tostring | contains("control")) | not) and
      ((.pairs | tostring | contains("treatment")) | not)
    ' "$TEST_DIR/first/preregistration.json"
    [[ "$status" -eq 0 ]]

    run jq -e '
      ([.assignments[] | select(.arms[0].mode == "control")] | length) == 9 and
      ([.assignments[] | select(.arms[0].mode == "treatment")] | length) == 9 and
      all(.assignments[];
        ([.arms[].mode] | sort) == ["control", "treatment"])
    ' "$TEST_DIR/first/private-assignments.json"
    [[ "$status" -eq 0 ]]

    create_fixture "$TEST_DIR/context-change"
    jq '.provider.host.version = "4.5.7"' \
        "$TEST_DIR/context-change/study.json" > "$TEST_DIR/context-change/study.tmp"
    mv "$TEST_DIR/context-change/study.tmp" "$TEST_DIR/context-change/study.json"
    prepare_fixture "$TEST_DIR/context-change"
    first_seed_commitment="$(jq -r '.seed_commitment_sha256' \
        "$TEST_DIR/first/preregistration.json")"
    changed_seed_commitment="$(jq -r '.seed_commitment_sha256' \
        "$TEST_DIR/context-change/preregistration.json")"
    [[ "$first_seed_commitment" != "$changed_seed_commitment" ]]

    prereg_sha="$(sha256_of "$TEST_DIR/first/preregistration.json")"
    run prepare_fixture "$TEST_DIR/first"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"refusing to overwrite existing preregistration output"* ]]
    [[ "$prereg_sha" == "$(sha256_of "$TEST_DIR/first/preregistration.json")" ]]
}

@test "verify reproduces canonical artifacts exactly and rejects every tamper" {
    create_fixture "$TEST_DIR/exact"
    prepare_fixture "$TEST_DIR/exact"
    run verify_fixture "$TEST_DIR/exact"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"status":"verified-not-run"'* ]]
    [[ ! -e "$TEST_DIR/exact/runner-invoked" ]]

    cp "$TEST_DIR/exact/preregistration.json" "$TEST_DIR/exact/preregistration.good"
    jq '.claim_scope = "live-study-complete"' \
        "$TEST_DIR/exact/preregistration.good" > "$TEST_DIR/exact/preregistration.json"
    chmod 644 "$TEST_DIR/exact/preregistration.json"
    run verify_fixture "$TEST_DIR/exact"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"claim scope"* ]]

    cp "$TEST_DIR/exact/preregistration.good" "$TEST_DIR/exact/preregistration.json"
    chmod 644 "$TEST_DIR/exact/preregistration.json"
    jq '.planned_pair_count = 17' \
        "$TEST_DIR/exact/preregistration.good" > "$TEST_DIR/exact/preregistration.json"
    chmod 644 "$TEST_DIR/exact/preregistration.json"
    run verify_fixture "$TEST_DIR/exact"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"planned pair count"* ]]

    cp "$TEST_DIR/exact/preregistration.good" "$TEST_DIR/exact/preregistration.json"
    chmod 644 "$TEST_DIR/exact/preregistration.json"
    jq '.assignments[0].arms[0].mode = "treatment"' \
        "$TEST_DIR/exact/private-assignments.json" > "$TEST_DIR/exact/assignments.tmp"
    mv "$TEST_DIR/exact/assignments.tmp" "$TEST_DIR/exact/private-assignments.json"
    chmod 600 "$TEST_DIR/exact/private-assignments.json"
    run verify_fixture "$TEST_DIR/exact"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"do not exactly reproduce"* ]]

    rm -rf -- "$TEST_DIR/exact"
    create_fixture "$TEST_DIR/exact"
    prepare_fixture "$TEST_DIR/exact"
    printf '%s\n' '{"tampered":true}' > "$TEST_DIR/exact/runner/manifest.json"
    run verify_fixture "$TEST_DIR/exact"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"planned runner manifest keys differ"* ]]

    chmod 640 "$TEST_DIR/exact/private-assignments.json"
    run verify_fixture "$TEST_DIR/exact"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"mode must be exactly 0600"* ]]
}

@test "multiple tasks are replicate-round-robin and balanced within each task" {
    create_fixture "$TEST_DIR/round-robin"
    run prepare_fixture "$TEST_DIR/round-robin"
    [[ "$status" -eq 0 ]]
    run jq -e '
      [.pairs[] | [.replicate, .task_id]] == [
        [1,"conformance-001"], [1,"conformance-002"], [1,"conformance-003"],
        [2,"conformance-001"], [2,"conformance-002"], [2,"conformance-003"],
        [3,"conformance-001"], [3,"conformance-002"], [3,"conformance-003"],
        [4,"conformance-001"], [4,"conformance-002"], [4,"conformance-003"],
        [5,"conformance-001"], [5,"conformance-002"], [5,"conformance-003"],
        [6,"conformance-001"], [6,"conformance-002"], [6,"conformance-003"]
      ]
    ' "$TEST_DIR/round-robin/preregistration.json"
    [[ "$status" -eq 0 ]]
    run jq -e '
      [.assignments[] | {task_id, first: .arms[0].mode}] |
      group_by(.task_id) |
      length == 3 and
      all(.[];
        length == 6 and
        ([.[] | select(.first == "control")] | length) == 3 and
        ([.[] | select(.first == "treatment")] | length) == 3)
    ' "$TEST_DIR/round-robin/private-assignments.json"
    [[ "$status" -eq 0 ]]
}

@test "invalid design checksum hardlinks and policy drift fail closed without invocation" {
    create_fixture "$TEST_DIR/invalid"
    jq '.replicates_per_task = 7 | .stopping.maximum_planned_pairs = 7' \
        "$TEST_DIR/invalid/study.json" > "$TEST_DIR/invalid/study.tmp"
    mv "$TEST_DIR/invalid/study.tmp" "$TEST_DIR/invalid/study.json"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"must be even"* ]]
    [[ ! -e "$TEST_DIR/invalid/runner-invoked" ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    jq '.replicates_per_task = 8 | .stopping.maximum_planned_pairs = 24' \
        "$TEST_DIR/invalid/study.json" > "$TEST_DIR/invalid/study.tmp"
    mv "$TEST_DIR/invalid/study.tmp" "$TEST_DIR/invalid/study.json"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"pilot stage requires exactly 6"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    jq '.stage = "confirmatory" | .replicates_per_task = 6 | .stopping.maximum_planned_pairs = 18' \
        "$TEST_DIR/invalid/study.json" > "$TEST_DIR/invalid/study.tmp"
    mv "$TEST_DIR/invalid/study.tmp" "$TEST_DIR/invalid/study.json"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"confirmatory stage requires exactly 12 or 20"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    jq '.stage = "confirmatory" | .replicates_per_task = 14 | .stopping.maximum_planned_pairs = 42' \
        "$TEST_DIR/invalid/study.json" > "$TEST_DIR/invalid/study.tmp"
    mv "$TEST_DIR/invalid/study.tmp" "$TEST_DIR/invalid/study.json"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"confirmatory stage requires exactly 12 or 20"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    jq '.statistics.bootstrap_resamples = 9999' \
        "$TEST_DIR/invalid/study.json" > "$TEST_DIR/invalid/study.tmp"
    mv "$TEST_DIR/invalid/study.tmp" "$TEST_DIR/invalid/study.json"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"bootstrap resamples"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    jq '.stopping.minimum_valid_pairs = 17' \
        "$TEST_DIR/invalid/study.json" > "$TEST_DIR/invalid/study.tmp"
    mv "$TEST_DIR/invalid/study.tmp" "$TEST_DIR/invalid/study.json"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"minimum valid pairs must equal all planned pairs"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    chmod 644 "$TEST_DIR/invalid/assignment.seed"
    run env PREREG_MARKER="$TEST_DIR/invalid/runner-invoked" \
        "$PYTHON_BIN" "$TOOL" prepare \
        --study "$TEST_DIR/invalid/study.json" \
        --seed-file "$TEST_DIR/invalid/assignment.seed" \
        --output "$TEST_DIR/invalid/preregistration.json" \
        --assignments-output "$TEST_DIR/invalid/private-assignments.json"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"seed file mode must be exactly 0600"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    jq '.unexpected = true' "$TEST_DIR/invalid/runner/manifest.json" \
        > "$TEST_DIR/invalid/manifest.tmp"
    mv "$TEST_DIR/invalid/manifest.tmp" "$TEST_DIR/invalid/runner/manifest.json"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"planned runner manifest keys differ"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    jq 'del(.controls.network_egress)' \
        "$TEST_DIR/invalid/policies/isolation.policy" \
        > "$TEST_DIR/invalid/policy.tmp"
    mv "$TEST_DIR/invalid/policy.tmp" \
        "$TEST_DIR/invalid/policies/isolation.policy"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"isolation controls keys differ"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    printf '%064d  %s\n' 0 'mainframe-fixture.tar.gz' \
        > "$TEST_DIR/invalid/release/mainframe-fixture.tar.gz.sha256"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"does not match the archive"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    ln "$TEST_DIR/invalid/protocol/tasks/conformance-001/repository/capacity.py" \
        "$TEST_DIR/invalid/protocol/tasks/conformance-001/repository/capacity-hardlink.py"
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"hard-linked"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    dd if=/dev/zero \
        of="$TEST_DIR/invalid/protocol/tasks/conformance-001/repository/quota-a.bin" \
        bs=1048576 count=6 2>/dev/null
    dd if=/dev/zero \
        of="$TEST_DIR/invalid/protocol/tasks/conformance-002/repository/quota-b.bin" \
        bs=1048576 count=6 2>/dev/null
    dd if=/dev/zero \
        of="$TEST_DIR/invalid/protocol/tasks/conformance-003/repository/quota-c.bin" \
        bs=1048576 count=6 2>/dev/null
    run prepare_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"aggregate byte quota"* ]]

    if command -v xattr >/dev/null 2>&1; then
        rm -rf -- "$TEST_DIR/invalid"
        create_fixture "$TEST_DIR/invalid"
        xattr -w com.apple.ResourceFork dangerous \
            "$TEST_DIR/invalid/protocol/tasks/conformance-001/repository/capacity.py"
        run prepare_fixture "$TEST_DIR/invalid"
        [[ "$status" -eq 2 ]]
        [[ "$output" == *"unsupported extended attributes"* ]]

        rm -rf -- "$TEST_DIR/invalid"
        create_fixture "$TEST_DIR/invalid"
        xattr -w com.apple.ResourceFork dangerous \
            "$TEST_DIR/invalid/runner/live-runner"
        run prepare_fixture "$TEST_DIR/invalid"
        [[ "$status" -eq 2 ]]
        [[ "$output" == *"planned runner executable carries unsupported extended attributes"* ]]
    fi

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    prepare_fixture "$TEST_DIR/invalid"
    chmod 755 "$TEST_DIR/invalid/runner/live-runner"
    run verify_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"private assignments do not exactly reproduce"* ]]

    rm -rf -- "$TEST_DIR/invalid"
    create_fixture "$TEST_DIR/invalid"
    prepare_fixture "$TEST_DIR/invalid"
    jq '.id = "changed-provider-proxy"' \
        "$TEST_DIR/invalid/policies/provider-proxy.policy" \
        > "$TEST_DIR/invalid/policy.tmp"
    mv "$TEST_DIR/invalid/policy.tmp" \
        "$TEST_DIR/invalid/policies/provider-proxy.policy"
    run verify_fixture "$TEST_DIR/invalid"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"private assignments do not exactly reproduce"* ]]
    [[ ! -e "$TEST_DIR/invalid/runner-invoked" ]]
}

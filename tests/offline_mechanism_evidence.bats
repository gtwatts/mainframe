#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TOOL_DIR="$PROJECT_ROOT/scripts/dev/offline-impact"
    PYTHON_BIN="$(command -v python3)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    [[ -n "$PYTHON_BIN" ]] || skip "python3 is required"
    [[ -n "$BASH_BIN" ]] || skip "Bash 4.4+ is required"
    "$BASH_BIN" -c \
        '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))' \
        || skip "Bash 4.4+ is required"
    command -v jq >/dev/null || skip "jq is required"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-offline-mechanism.XXXXXX")"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

build_source_evidence() {
    local output="$1"
    local source_root="${2:-$PROJECT_ROOT}"
    "$PYTHON_BIN" "$TOOL_DIR/build-evidence.py" \
        --source-root "$source_root" \
        --bash "$BASH_BIN" \
        --output "$output"
}

verify_source_evidence() {
    local evidence="$1"
    local source_root="${2:-$PROJECT_ROOT}"
    "$PYTHON_BIN" "$TOOL_DIR/verify-evidence.py" \
        --source-root "$source_root" \
        --bash "$BASH_BIN" \
        --evidence "$evidence"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    fi
}

@test "source evidence binds raw rows and carries explicit non-claims" {
    evidence="$TEST_DIR/source-evidence.json"

    run build_source_evidence "$evidence"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"pass (12/12 exact rows)"* ]]

    run verify_source_evidence "$evidence"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"verified: pass (12/12 exact rows)"* ]]

    run jq -e '
      .schema_version == 1 and
      .kind == "mainframe-offline-agent-mechanism-evidence" and
      .claim_scope == "deterministic-policy-classification-fixtures-only" and
      .runtime.origin == "source-tree" and
      .runtime.archive == null and
      (.runtime.evaluated_source_digest_sha256 | test("^[0-9a-f]{64}$")) and
      (.runtime.evaluated_source_files | map(.path)) ==
        ["VERSION", "lib/agent_safety.sh"] and
      .execution == {
        block_tier: "high",
        case_count: 12,
        classifier_function: "agent_gate_classify",
        commands_executed: false
      } and
      (.rows | length) == 12 and
      all(.rows[];
        (.id | type == "string") and
        (.command | type == "string") and
        .executed == false and
        .exact_match == (.expected == .observed)) and
      .summary == {
        case_count: 12,
        exact_match_count: 12,
        expected_block_count: 6,
        fixture_false_negative_count: 0,
        fixture_false_positive_count: 0,
        mismatch_count: 0,
        observed_block_count: 6
      } and
      .result == "pass" and
      .non_claims == {
        agent_quality: "not-measured",
        comparative_agent_performance: "not-measured",
        live_agent_sessions: 0,
        productivity: "not-measured",
        real_provider_inference: "not-run"
      } and
      .limitations == {
        command_execution_prevention: "not-tested",
        generalization_beyond_fixtures: "not-established",
        os_sandbox_containment: "not-tested",
        policy_classification_only: true,
        synthetic_fixture_corpus: true
      }
    ' "$evidence"
    [[ "$status" -eq 0 ]]
}

@test "source evidence is deterministic and the builder does not clobber" {
    first="$TEST_DIR/first.json"
    second="$TEST_DIR/second.json"

    run build_source_evidence "$first"
    [[ "$status" -eq 0 ]]
    run build_source_evidence "$second"
    [[ "$status" -eq 0 ]]
    run cmp -s "$first" "$second"
    [[ "$status" -eq 0 ]]

    before="$(sha256_file "$first")"
    run build_source_evidence "$first"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to overwrite existing evidence output"* ]]
    after="$(sha256_file "$first")"
    [[ "$before" == "$after" ]]
}

@test "verifier rejects schema, aggregate, and selected-source tampering" {
    runtime="$TEST_DIR/runtime"
    mkdir -p "$runtime/lib"
    cp "$PROJECT_ROOT/VERSION" "$runtime/VERSION"
    cp "$PROJECT_ROOT/lib/agent_safety.sh" "$runtime/lib/agent_safety.sh"
    evidence="$TEST_DIR/source-evidence.json"
    schema_tamper="$TEST_DIR/schema-tamper.json"
    nonclaim_tamper="$TEST_DIR/nonclaim-tamper.json"
    fixture_digest_tamper="$TEST_DIR/fixture-digest-tamper.json"
    raw_row_tamper="$TEST_DIR/raw-row-tamper.json"
    aggregate_tamper="$TEST_DIR/aggregate-tamper.json"

    run build_source_evidence "$evidence" "$runtime"
    [[ "$status" -eq 0 ]]

    jq '.unexpected = true' "$evidence" > "$schema_tamper"
    run verify_source_evidence "$schema_tamper" "$runtime"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"does not satisfy the schema"* ]]

    jq '.non_claims.agent_quality = "measured"' "$evidence" > "$nonclaim_tamper"
    run verify_source_evidence "$nonclaim_tamper" "$runtime"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"expected constant 'not-measured'"* ]]

    jq '.protocol.fixture.sha256 = ("0" * 64)' \
        "$evidence" > "$fixture_digest_tamper"
    run verify_source_evidence "$fixture_digest_tamper" "$runtime"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"protocol.fixture.sha256"* ]]

    jq '.rows[0].command += " "' "$evidence" > "$raw_row_tamper"
    run verify_source_evidence "$raw_row_tamper" "$runtime"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *'rows[0].command'* ]]

    jq '.summary.exact_match_count = 11' "$evidence" > "$aggregate_tamper"
    run verify_source_evidence "$aggregate_tamper" "$runtime"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"summary does not derive exactly from the raw rows"* ]]

    printf '\n# source-digest-tamper\n' >> "$runtime/lib/agent_safety.sh"
    run verify_source_evidence "$evidence" "$runtime"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"does not match the selected current inputs"* ]]
    [[ "$output" == *"evaluated_source_digest_sha256"* ]]
}

@test "archive evidence verifies sidecar, archive bytes, and evaluated source" {
    runtime="$TEST_DIR/archive-runtime"
    mkdir -p "$runtime/lib"
    cp "$PROJECT_ROOT/VERSION" "$runtime/VERSION"
    cp "$PROJECT_ROOT/lib/agent_safety.sh" "$runtime/lib/agent_safety.sh"
    chmod 644 "$runtime/VERSION" "$runtime/lib/agent_safety.sh"
    archive="$TEST_DIR/mainframe-fixture.tar.gz"
    COPYFILE_DISABLE=1 tar -C "$runtime" -czf "$archive" VERSION lib
    archive_sha="$(sha256_file "$archive")"
    printf '%s  %s\n' "$archive_sha" "$(basename "$archive")" > "$archive.sha256"
    evidence="$TEST_DIR/archive-evidence.json"

    run "$PYTHON_BIN" "$TOOL_DIR/build-evidence.py" \
        --archive "$archive" \
        --bash "$BASH_BIN" \
        --output "$evidence"
    [[ "$status" -eq 0 ]]

    run "$PYTHON_BIN" "$TOOL_DIR/verify-evidence.py" \
        --archive "$archive" \
        --bash "$BASH_BIN" \
        --evidence "$evidence"
    [[ "$status" -eq 0 ]]

    run jq -e --arg sha "$archive_sha" '
      .runtime.origin == "release-archive" and
      .runtime.archive == {
        checksum_sidecar_basename: "mainframe-fixture.tar.gz.sha256",
        checksum_verified: true,
        path_basename: "mainframe-fixture.tar.gz",
        sha256: $sha
      } and
      (.runtime.evaluated_source_digest_sha256 | test("^[0-9a-f]{64}$")) and
      .result == "pass"
    ' "$evidence"
    [[ "$status" -eq 0 ]]

    archive_link="$TEST_DIR/mainframe-link.tar.gz"
    ln -s "$archive" "$archive_link"
    printf '%s  %s\n' "$archive_sha" "$(basename "$archive_link")" > "$archive_link.sha256"
    run "$PYTHON_BIN" "$TOOL_DIR/build-evidence.py" \
        --archive "$archive_link" \
        --bash "$BASH_BIN" \
        --output "$TEST_DIR/link-evidence.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"release archive must be a regular, non-symlink file"* ]]

    printf '%064d  %s\n' 0 "$(basename "$archive")" > "$archive.sha256"
    run "$PYTHON_BIN" "$TOOL_DIR/verify-evidence.py" \
        --archive "$archive" \
        --bash "$BASH_BIN" \
        --evidence "$evidence"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"checksum does not match"* ]]
}

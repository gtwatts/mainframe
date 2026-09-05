#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    PYTHON_BIN="${MAINFRAME_PYTHON:-/opt/homebrew/bin/python3}"
    [[ -x "$PYTHON_BIN" ]] || PYTHON_BIN="$(command -v python3)"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-public-claims.XXXXXX")"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

# Documentation correctness is stable; live promotion evidence has a TTL.
# The full verifier still runs every textual check. Permit only its single,
# explicit expiry failure here; release-readiness runs the same command and
# requires exit zero before attestation/publication. Other drift still fails.
assert_documentation_checks_pass() {
    if [[ "$status" -eq 0 ]]; then
        [[ "$output" == *"Public claim verification passed"* ]]
    else
        [[ "$status" -eq 1 ]]
        [[ "$output" =~ gate[[:space:]][a-z-]+[[:space:]]receipt[[:space:]]is[[:space:]]expired ]]
        [[ "$output" == *"Public claim verification failed with 1 rule(s)."* ]]
    fi
}

@test "historical outcome reports are warned and absent from the release payload" {
    local historical_doc
    for historical_doc in \
        docs/MAINFRAME_Technical_Report.md \
        docs/VALUE_PROOF.md; do
        grep -Fq 'Historical research only' "$PROJECT_ROOT/$historical_doc"
    done

    run "$BASH_BIN" -c \
        'source "$1"; mainframe_release_payload_files "$2"' \
        _ "$PROJECT_ROOT/scripts/dev/release-payload.sh" "$PROJECT_ROOT"

    [[ "$status" -eq 0 ]]
    [[ "$output" != *"docs/MAINFRAME_Technical_Report.md"* ]]
    [[ "$output" != *"docs/VALUE_PROOF.md"* ]]
}

@test "current documentation passes independently of promotion receipt expiry" {
    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh"

    assert_documentation_checks_pass
    [[ "$output" == *"Generated registry claim parity passed"* ]]
    if [[ "$status" -eq 0 ]]; then
        [[ "$output" == *"Control-plane claim contract passed: advertised=source-candidate"* ]]
    fi
}

@test "ultimate control-plane copy is blocked below the category-claim gate" {
    local claims="$TEST_DIR/ultimate-overclaim.md"
    printf '%s\n' 'MAINFRAME is the ultimate AI agent control plane.' > "$claims"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$claims"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Ultimate control-plane language requires the category-claim gate"* ]]
}

@test "first-use copy/paste discovery examples use an executable semantic query" {
    local query="create json object"

    grep -Fq "mainframe search \\\"$query\\\"" "$PROJECT_ROOT/install.sh"
    grep -Fq "mainframe search '$query'" "$PROJECT_ROOT/docs/COMPARISON.md"
    ! grep -Fq 'mainframe search \"json|path|validate\"' "$PROJECT_ROOT/install.sh"
    ! grep -Fq "mainframe search 'json|path|validate'" \
        "$PROJECT_ROOT/docs/COMPARISON.md"

    run "$PROJECT_ROOT/bin/mainframe" search "$query"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Canonical functions matching 'create json object':"* ]]
    [[ "$output" == *"json_object - json [risk=low, stable-core, pure, idempotent]"* ]]
}

@test "generated registry and public MCP counts reject stale current-document claims" {
    local claims="$TEST_DIR/stale-registry-count.md"
    printf '%s\n' \
        '# Current inventory' \
        'MAINFRAME exposes 4,385 Registry Functions.' \
        'The public MCP runner has 25 stable-core tools.' > "$claims"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$claims"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Generated registry count claims are stale"* ]]
    [[ "$output" == *"Generated MCP stable-core claims are stale"* ]]
}

@test "current docs do not advertise retired public MCP tiers" {
    local claims="$TEST_DIR/legacy-mcp-tier.md"
    printf '%s\n' 'Set MAINFRAME_MCP_TIER=full for broader tools.' > "$claims"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$claims"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"public MCP runner no longer supports legacy tier selection"* ]]
}

@test "generated gate counts reject stale current-document claims" {
    local claims="$TEST_DIR/stale-gate-count.md"
    local counts rule_count corpus_count
    counts="$("$PYTHON_BIN" -I -S -B - "$PROJECT_ROOT" <<'PY'
import ast
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
rules = json.loads((root / "security/gate-rules.json").read_text())["rules"]
tree = ast.parse((root / "scripts/export-gate-rules.py").read_text())
values = [
    node.value
    for node in tree.body
    if isinstance(node, ast.Assign)
    and any(isinstance(target, ast.Name) and target.id == "CORPUS" for target in node.targets)
]
corpus = ast.literal_eval(values[0])
print(len(rules), len(corpus))
PY
    )"
    read -r rule_count corpus_count <<< "$counts"
    printf '%s\n' \
        '# Current gate claims' \
        "$((rule_count + 1)) canonical lexical" \
        'gate rules.' \
        "The exporter has $((corpus_count + 1))-case" \
        'corpus.' \
        "$rule_count canonical lexical gate rules and $((rule_count + 2)) source rules." \
        > "$claims"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$claims"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Generated gate-rule count claims are stale"* ]]
    [[ "$output" == *"Generated exporter corpus claims are stale"* ]]
}

@test "generated gate counts accept current multiline and hyphenated claims" {
    local claims="$TEST_DIR/current-gate-count.md"
    local counts rule_count corpus_count
    counts="$("$PYTHON_BIN" -I -S -B - "$PROJECT_ROOT" <<'PY'
import ast
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
rules = json.loads((root / "security/gate-rules.json").read_text())["rules"]
tree = ast.parse((root / "scripts/export-gate-rules.py").read_text())
values = [
    node.value
    for node in tree.body
    if isinstance(node, ast.Assign)
    and any(isinstance(target, ast.Name) and target.id == "CORPUS" for target in node.targets)
]
corpus = ast.literal_eval(values[0])
print(len(rules), len(corpus))
PY
    )"
    read -r rule_count corpus_count <<< "$counts"
    printf '%s\n' \
        '# Current gate claims' \
        "The classifier is an ordered $rule_count-rule" \
        'lexical policy.' \
        "The exporter checks $corpus_count Bash/JavaScript parity cases" \
        "across all $rule_count rules." \
        > "$claims"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$claims"

    assert_documentation_checks_pass
    [[ "$output" == *"Generated gate claim parity passed: $rule_count rules, $corpus_count corpus cases."* ]]
}

@test "every shipped Markdown document is scanned or explicitly quarantined" {
    local inventory_file="$TEST_DIR/document-inventory.txt"
    local payload_file="$TEST_DIR/release-payload.txt"
    local current_doc relative_path dispositions

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --list-documents
    [[ "$status" -eq 0 ]]
    printf '%s\n' "$output" > "$inventory_file"

    run "$BASH_BIN" -c \
        'source "$1"; mainframe_release_payload_files "$2"' \
        _ "$PROJECT_ROOT/scripts/dev/release-payload.sh" "$PROJECT_ROOT"
    [[ "$status" -eq 0 ]]
    printf '%s\n' "$output" > "$payload_file"

    while IFS= read -r relative_path; do
        [[ "$relative_path" == *.md ]] || continue
        dispositions="$(awk -F '\t' -v path="$relative_path" \
            '$2 == path && ($1 == "scan" || $1 == "quarantine") { count++ }
             END { print count + 0 }' "$inventory_file")"
        [[ "$dispositions" -eq 1 ]]
    done < "$payload_file"

    for current_doc in \
        'docs/COMPARISON.md' \
        'docs/AGENT_IMPACT_EVALUATION.md' \
        'docs/AGENT_IMPACT_LIVE_STUDY.md'; do
        grep -Fxq $'scan\t'"$current_doc" "$inventory_file"
    done
    grep -Fq '**Your coding agents may change. Your safety policy and working memory should' \
        "$PROJECT_ROOT/docs/COMPARISON.md"
    grep -Fq 'MAINFRAME is defense in depth.' \
        "$PROJECT_ROOT/docs/COMPARISON.md"
}

@test "offline runtime preflight remains no-execution and non-eligible evidence" {
    local protocol="$PROJECT_ROOT/evals/agent-impact/README.md"
    local live_study="$PROJECT_ROOT/docs/AGENT_IMPACT_LIVE_STUDY.md"
    local claims="$PROJECT_ROOT/docs/CLAIMS_AND_BENCHMARKS.md"

    grep -Fq 'scripts/dev/agent-impact-runtime-preflight.py' "$protocol"
    grep -Fq -- '--arm-contract /absolute/path/to/arm.json' "$protocol"
    grep -Fq 'MAINFRAME archive and' "$protocol"
    grep -Fq 'Pi certification and package tree' "$protocol"
    grep -Fq 'start no child process' "$protocol"
    grep -Fq 'not eligible live-study evidence' "$protocol"
    grep -Fq 'does not inspect the machine process table' "$live_study"
    grep -Fq 'not eligible live-study' "$live_study"
    grep -Fq 'Generated/Reproduced static-readiness' "$claims"
    grep -Fq 'containment certificate' "$claims"
    grep -Fq 'authorization for a provider run' "$claims"
}

@test "installed AWM handoff evidence stays inside the mechanism-only claim" {
    local doc="$PROJECT_ROOT/docs/INSTALLED_AWM_HANDOFF_CONFORMANCE.md"
    local schema="$PROJECT_ROOT/evals/agent-impact/installed-awm-handoff-evidence.schema.json"

    grep -Fq \
        'installed-candidate-awm-handoff-mechanism-conformance-only' "$doc"
    grep -Fq \
        'This is installed-candidate AWM handoff mechanism-conformance evidence only; it does not measure MAINFRAME benefit, agent quality, developer productivity, or real provider inference.' \
        "$doc"
    grep -Fq 'same local account' "$doc"

    run "$PYTHON_BIN" -I -S -B - "$schema" <<'PY'
import json
from pathlib import Path
import sys

schema = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert schema["properties"]["claim_scope"]["const"] == (
    "installed-candidate-awm-handoff-mechanism-conformance-only"
)
assert schema["$defs"]["candidate"]["properties"]["installed_payload"]["const"] == (
    "authenticated-release-files-private-staging"
)
non_claims = schema["$defs"]["nonClaims"]["properties"]
assert non_claims["mainframe_benefit"]["const"] == "not-measured"
assert non_claims["agent_quality"]["const"] == "not-measured"
assert non_claims["developer_productivity"]["const"] == "not-measured"
assert non_claims["real_provider_inference"]["const"] == "not-run"
assert non_claims["same_local_account_isolation"]["const"] == "not-established"
PY
    [[ "$status" -eq 0 ]]
}

@test "unpublished verified install is not advertised as a live public path" {
    grep -Fq 'Verified release install (publication gated)' "$PROJECT_ROOT/README.md"
    grep -Fq '`get-mainframe.sh --latest` intentionally fails closed' "$PROJECT_ROOT/README.md"
    grep -Fq 'currently usable public installation path' "$PROJECT_ROOT/INSTALL.md"
    grep -Fq 'The verified mode is publication-gated' "$PROJECT_ROOT/INSTALL.md"
    grep -Fq "MAINFRAME's immutable release path is publication-gated" \
        "$PROJECT_ROOT/docs/AI_CLI_INTEGRATIONS.md"
    grep -Fq 'the currently usable public path is' \
        "$PROJECT_ROOT/docs/AI_CLI_INTEGRATIONS.md"
}

@test "primary install guides disclose control-plane, Pi, and managed-host Python prerequisites" {
    grep -Fq 'A protected fixed-location Python 3.9+' \
        "$PROJECT_ROOT/README.md"
    grep -Fq 'A protected fixed-location Python 3.9+' \
        "$PROJECT_ROOT/INSTALL.md"
    grep -Fq 'durable control-plane CLI and Pi diagnosis/lifecycle' \
        "$PROJECT_ROOT/README.md"
    grep -Fq 'durable control-plane CLI and Pi diagnosis/lifecycle' \
        "$PROJECT_ROOT/INSTALL.md"
    grep -Fq 'mainframe pi doctor' "$PROJECT_ROOT/INSTALL.md"
}

@test "extra current documentation cannot reintroduce unsupported outcome claims" {
    local claims="$TEST_DIR/unsupported-current-claims.md"
    printf '%s\n' \
        '# Current product claims' \
        'Token savings per bash task: 82%.' \
        'First-time correctness: 99%.' \
        'Based on 500 bash task samples.' \
        'Real-World Impact: AI Assistant Productivity.' \
        'AWM provides unlimited state for truly autonomous agents.' \
        'MAINFRAME is 20-72x faster.' > "$claims"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$claims"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Token-saving percentages require a published evaluation"* ]]
    [[ "$output" == *"Agent success percentages require a published evaluation"* ]]
    [[ "$output" == *"Sample-size claims require published raw evaluation evidence"* ]]
    [[ "$output" == *"Productivity claims require a live comparative evaluation"* ]]
    [[ "$output" == *"Unbounded autonomy claims exceed the AWM evidence boundary"* ]]
    [[ "$output" == *"Universal speedup ranges require a published benchmark"* ]]
}

@test "extra claim documents fail closed when missing or symbolic links" {
    local target="$TEST_DIR/target.md"
    local link="$TEST_DIR/link.md"
    printf '# benign\n' > "$target"
    ln -s "$target" "$link"

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$TEST_DIR/missing.md"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"must be a regular, non-symlink file"* ]]

    run "$BASH_BIN" "$PROJECT_ROOT/scripts/verify-public-claims.sh" \
        --extra-document "$link"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"must be a regular, non-symlink file"* ]]
}

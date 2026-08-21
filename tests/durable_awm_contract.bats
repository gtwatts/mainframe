#!/usr/bin/env bats
# Phase 4D RED contract for durable AWM.  These tests deliberately avoid naming
# a future kernel command or canonical tool ID.  They pin only the public
# fail-closed boundary and the storage/retrieval invariants the future Memory
# reducer must satisfy.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    FIXTURE_ROOT="$TEST_ROOT/runtime-without-kernel"
    AWM_ROOT="$TEST_ROOT/awm"
    PROJECT_DIR="$TEST_ROOT/project"
    TEST_HOME="$TEST_ROOT/home"
    BASH_BIN="${MAINFRAME_BASH:-${BASH:-bash}}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v "$BASH_BIN")"

    mkdir -p "$FIXTURE_ROOT/bin" "$PROJECT_DIR" "$TEST_HOME"
    cp "$PROJECT_ROOT/bin/mainframe" "$FIXTURE_ROOT/bin/mainframe"
    cp -R "$PROJECT_ROOT/lib" "$FIXTURE_ROOT/lib"
    chmod 0755 "$FIXTURE_ROOT/bin/mainframe"
    export AWM_ROOT BASH_BIN PROJECT_DIR TEST_HOME
}

legacy_checkpoint() {
    local key="$1" value="$2" ttl="${3:-0}"
    # The positional parameters are intentionally expanded by the child Bash.
    # shellcheck disable=SC2016
    env \
        HOME="$TEST_HOME" \
        AWM_ROOT="$AWM_ROOT" \
        MAINFRAME_AGENT_NAME=legacy-fixture \
        "$BASH_BIN" --noprofile --norc -c '
            source "$1/lib/awm.sh"
            awm_init legacy-fixture >/dev/null || exit
            sid="$_AWM_SESSION_ID"
            awm_checkpoint "$2" "$3" --ttl "$4" || exit
            printf "%s\n" "$sid"
        ' bash "$PROJECT_ROOT" "$key" "$value" "$ttl"
}

legacy_get() {
    local sid="$1" key="$2"
    # The positional parameters are intentionally expanded by the child Bash.
    # shellcheck disable=SC2016
    env \
        HOME="$TEST_HOME" \
        AWM_ROOT="$AWM_ROOT" \
        MAINFRAME_AGENT_NAME=legacy-fixture \
        "$BASH_BIN" --noprofile --norc -c '
            source "$1/lib/awm.sh"
            awm_resume "$2" >/dev/null || exit
            awm_get "$2" "$3"
        ' bash "$PROJECT_ROOT" "$sid" "$key"
}

legacy_find() {
    local sid="$1" query="$2"
    # The positional parameters are intentionally expanded by the child Bash.
    # shellcheck disable=SC2016
    env \
        HOME="$TEST_HOME" \
        AWM_ROOT="$AWM_ROOT" \
        MAINFRAME_AGENT_NAME=legacy-fixture \
        "$BASH_BIN" --noprofile --norc -c '
            source "$1/lib/awm.sh"
            awm_resume "$2" >/dev/null || exit
            awm_find "$3" --kind checkpoint
        ' bash "$PROJECT_ROOT" "$sid" "$query"
}

assert_legacy_checkpoint_unavailable() {
    local sid="$1" key="$2" sentinel="$3"

    run legacy_get "$sid" "$key"
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"$sentinel"* ]]

    run legacy_find "$sid" "$sentinel"
    [[ "$status" -eq 0 ]]
    run jq -e 'length == 0' <<<"$output"
    [[ "$status" -eq 0 ]]
}

@test "durable AWM: unavailable kernel denies all project mutations without legacy fallback" {
    local -a mutation

    for mutation in \
        "ensure --project $PROJECT_DIR" \
        "checkpoint --project $PROJECT_DIR key value" \
        "discovery --project $PROJECT_DIR finding" \
        "progress --project $PROJECT_DIR task 1/2" \
        "close --project $PROJECT_DIR" \
        "handoff prepare --project $PROJECT_DIR reviewer"; do
        # Test arguments contain only fixture paths and fixed tokens; splitting
        # here exercises the public argv grammar without evaluating a command.
        # shellcheck disable=SC2086
        run env \
            HOME="$TEST_HOME" \
            AWM_ROOT="$AWM_ROOT" \
            MAINFRAME_BASH="$BASH_BIN" \
            MAINFRAME_LIBS=awm \
            "$FIXTURE_ROOT/bin/mainframe" awm project $mutation

        [[ "$status" -ne 0 ]]
        [[ "$output" == *"control-plane"* || "$output" == *"kernel"* ]]
        [[ ! -e "$AWM_ROOT" ]]
    done
}

@test "durable AWM: public grammar accepts no caller authority or durable identity" {
    local flag

    for flag in --actor --policy --run-id --call-id --evidence-id --authority --trust-label; do
        run env \
            HOME="$TEST_HOME" \
            AWM_ROOT="$AWM_ROOT" \
            MAINFRAME_BASH="$BASH_BIN" \
            MAINFRAME_LIBS=awm \
            "$FIXTURE_ROOT/bin/mainframe" awm project ensure \
            --project "$PROJECT_DIR" "$flag" forged
        [[ "$status" -ne 0 ]]
        [[ ! -e "$AWM_ROOT" ]]
    done
}

@test "durable AWM: legacy records are explicitly untrusted and non-authorizing" {
    local sid result

    sid="$(legacy_checkpoint answer legacy-value)"
    result="$(legacy_find "$sid" legacy-value)"

    run jq -e '
        length == 1 and
        .[0].trust_label == "untrusted_legacy" and
        .[0].authoritative == false and
        .[0].provenance.source == "legacy_awm_v2" and
        .[0].provenance.run_id == null and
        .[0].provenance.call_id == null and
        .[0].provenance.evidence_id == null and
        .[0].provenance.input_digest == null
    ' <<<"$result"
    [[ "$status" -eq 0 ]]
}

@test "durable AWM: tampered metadata cannot release checkpoint content" {
    local sid metadata

    sid="$(legacy_checkpoint answer guarded-value)"
    metadata="$AWM_ROOT/sessions/$sid/index/answer.json"
    printf '{"tampered":true}\n' >"$metadata"

    run legacy_get "$sid" answer
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"guarded-value"* ]]
}

@test "durable AWM: duplicate ambiguous and noncanonical sidecars are denied and omitted" {
    local sid metadata content variant key sentinel

    for variant in duplicate extra nested_shadow malformed noncanonical; do
        key="sidecar_${variant}"
        sentinel="guarded-${variant}-value"
        sid="$(legacy_checkpoint "$key" "$sentinel")"
        metadata="$AWM_ROOT/sessions/$sid/index/${key}.json"
        content="$(<"$metadata")"
        case "$variant" in
            duplicate)
                # Same-value duplicates still create an ambiguous semantic
                # representation and must not be normalized into acceptance.
                content="${content/\{\"authoritative\":false/\{\"authoritative\":false,\"authoritative\":false}"
                printf '%s' "$content" >"$metadata"
                ;;
            extra)
                jq -cS '. + {unexpected_authority:"forged"}' \
                    <<<"$content" >"$metadata"
                ;;
            nested_shadow)
                jq -cS '.provenance.authoritative = true' \
                    <<<"$content" >"$metadata"
                ;;
            malformed)
                printf '{"authoritative":false' >"$metadata"
                ;;
            noncanonical)
                printf ' %s' "$content" >"$metadata"
                ;;
        esac
        assert_legacy_checkpoint_unavailable "$sid" "$key" "$sentinel"
    done
}

@test "durable AWM: expiry hides retrieval but does not claim on-disk purge" {
    local sid value_file

    sid="$(legacy_checkpoint expiring guarded-value 1)"
    value_file="$AWM_ROOT/sessions/$sid/data/expiring"
    sleep 2

    assert_legacy_checkpoint_unavailable "$sid" expiring guarded-value
    [[ -f "$value_file" ]]
    [[ "$(<"$value_file")" == guarded-value ]]
}

@test "durable AWM: any non-legacy record requires kernel provenance and remains non-authority" {
    local sid metadata

    sid="$(legacy_checkpoint binding legacy-value)"
    metadata="$AWM_ROOT/sessions/$sid/index/binding.json"

    run jq -e '
        .authoritative == false and
        if .trust_label == "untrusted_legacy" then
          true
        else
          (.provenance.run_id | type == "string" and length > 0) and
          (.provenance.call_id | type == "string" and length > 0) and
          (.provenance.evidence_id | type == "string" and length > 0) and
          (.provenance.input_digest | type == "string" and test("^[0-9a-f]{64}$"))
        end
    ' "$metadata"
    [[ "$status" -eq 0 ]]
}

#!/usr/bin/env bats
# Phase 1 deliverables 5-6: adapter host discovery + live AWM write/read,
# and cross-session nonce retrieval from a genuinely new session.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-p1-test.XXXXXX")"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    export AWM_ROOT="$TEST_DIR/awm"
}

teardown() {
    rm -rf "$TEST_DIR"
}

mf() {
    "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" "$@"
}

mf_in() {
    local directory="$1"
    shift
    (cd -- "$directory" && "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" "$@")
}

@test "onboarded host instructions drive one bounded project AWM protocol across processes" {
    local host project nested instruction block_hash expected_hash="" session_id
    for host in codex claude-code copilot gemini cursor jetbrains junie; do
        project="$TEST_DIR/project-$host"
        nested="$project/src/agent/work"
        mkdir -p "$nested"
        mf activate "$host" --project "$project" >/dev/null

        case "$host" in
            codex) instruction="$project/AGENTS.md" ;;
            claude-code) instruction="$project/CLAUDE.md" ;;
            copilot) instruction="$project/.github/copilot-instructions.md" ;;
            gemini) instruction="$project/GEMINI.md" ;;
            cursor) instruction="$project/.cursor/rules/mainframe.mdc" ;;
            jetbrains) instruction="$project/.aiassistant/rules/mainframe.md" ;;
            junie) instruction="$project/.junie/guidelines.md" ;;
        esac
        grep -Fq 'mainframe awm project ensure --project . --discover-root' "$instruction"
        grep -Fq 'mainframe work "<current task>" --project . --tokens 1200' "$instruction"
        grep -Fq 'do not initialize or renew memory without human confirmation' "$instruction"
        grep -Fq 'mainframe awm project handoff prepare --project . --discover-root <target> --tokens 1200 --format prompt' "$instruction"
        grep -Fq 'mainframe awm project summary --project . --discover-root --tokens 800' "$instruction"
        grep -Fq 'Never store credentials, tokens, secrets, raw sensitive payloads, or routine command chatter.' "$instruction"

        block_hash="$(sed -n '/MAINFRAME:BEGIN/,/MAINFRAME:END/p' "$instruction" | shasum -a 256 | awk '{print $1}')"
        [[ -z "$expected_hash" || "$block_hash" == "$expected_hash" ]]
        expected_hash="$block_hash"

        run mf_in "$nested" awm project ensure --project . --discover-root
        [[ "$status" -eq 0 ]]
        session_id="${output##*$'\n'}"
        [[ "$session_id" =~ ^[0-9a-f]{12}$ ]]

        # Every operation is a new CLI process. The canonical project mapping,
        # not a shell-local variable, must recover the same session.
        run mf_in "$nested" awm project checkpoint --project . --discover-root current_phase scanning --importance high
        [[ "$status" -eq 0 ]]
        run mf_in "$nested" awm project discovery --project . --discover-root "host $host durable finding" --importance high
        [[ "$status" -eq 0 ]]
        run mf_in "$nested" awm project progress --project . --discover-root onboarding 1/2 "checkpointed"
        [[ "$status" -eq 0 ]]
        run mf_in "$nested" awm project get --project . --discover-root current_phase
        [[ "$status" -eq 0 ]]
        [[ "$output" == "scanning" ]]
        run mf_in "$nested" work "resume $host" --project . --tokens 1200 --format prompt
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"host $host durable finding"* ]]
        [[ "$output" == *'<mainframe-project-memory-data>'* ]]
        run mf_in "$nested" awm project handoff prepare --project . --discover-root next-agent --tokens 1200 --format prompt
        [[ "$status" -eq 0 ]]
        run mf_in "$nested" awm project checkpoint --project . --discover-root completion_status complete --importance high
        [[ "$status" -eq 0 ]]
        run mf_in "$nested" awm project summary --project . --discover-root --tokens 800
        [[ "$status" -eq 0 ]]

        run mf awm project session --project "$project"
        [[ "$status" -eq 0 ]]
        [[ "$output" == "$session_id" ]]
    done
}

@test "nonce: cross-session retrieval from a genuinely new session" {
    # Session A: write a random nonce; only the session id leaves the process.
    read -r sid nonce < <("$BASH_BIN" -c '
        export MAINFRAME_LIBS=all
        source "'"$PROJECT_ROOT"'/lib/common.sh" >/dev/null 2>&1
        awm_init "nonce-e2e" >/dev/null
        nonce="nonce-$RANDOM-$RANDOM-$$"
        awm_checkpoint nonce_key "$nonce" >/dev/null
        printf "%s %s\n" "$_AWM_SESSION_ID" "$nonce"
    ')
    [ -n "$sid" ] && [ -n "$nonce" ]

    # Session B: a genuinely new, scrubbed environment (env -i). The nonce is
    # NOT passed in; it must be retrieved from AWM storage with only the sid.
    got=$(env -i PATH="$PATH" HOME="$HOME" MAINFRAME_ROOT="$PROJECT_ROOT" AWM_ROOT="$AWM_ROOT" \
        "$BASH_BIN" -c '
            export MAINFRAME_LIBS=all
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            awm_resume "'"$sid"'" >/dev/null 2>&1
            awm_get nonce_key
        ')
    [ "$got" = "$nonce" ]
}

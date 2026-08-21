#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    if ! "$BASH_BIN" -c \
        '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))'; then
        skip "Bash 4.4+ is required"
    fi
}

@test "public CLI routes structured control-plane commands before runtime loading" {
    local ledger="$BATS_TEST_TMPDIR/control-plane.jsonl"

    run env MAINFRAME_BASH="$BASH_BIN" \
        "$PROJECT_ROOT/bin/mainframe" control-plane --ledger "$ledger" show

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"ok": true'* ]]
    [[ "$output" == *'"event_count": 0'* ]]
}

@test "public control-plane route never executes a poisoned PATH Python" {
    local poison_bin="$BATS_TEST_TMPDIR/poison-bin"
    local marker="$BATS_TEST_TMPDIR/poisoned-python-ran"
    mkdir -p "$poison_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "poisoned\n" > "${MAINFRAME_POISON_MARKER:?}"' \
        'exit 97' > "$poison_bin/python3"
    chmod +x "$poison_bin/python3"

    run env \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_POISON_MARKER="$marker" \
        PATH="$poison_bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
        "$PROJECT_ROOT/bin/mainframe" control-plane \
            --ledger "$BATS_TEST_TMPDIR/poison-ledger.jsonl" show

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"ok": true'* ]]
    [[ ! -e "$marker" ]]
}

@test "public CLI cannot self-author approval for disposable write" {
    local ledger="$BATS_TEST_TMPDIR/write-ledger.jsonl"
    local workspace="$BATS_TEST_TMPDIR/disposable-workspace"
    local input_json='{"path":"result.txt","content":"bound write\n"}'
    local input_digest
    mkdir -p "$workspace"
    printf 'MAINFRAME_DISPOSABLE_WORKSPACE_V1\n' \
        > "$workspace/.mainframe-disposable-workspace"
    input_digest="$(/usr/bin/python3 -c \
        'import hashlib,json,sys; value=json.loads(sys.argv[1]); encoded=json.dumps(value,allow_nan=False,ensure_ascii=False,separators=(",",":"),sort_keys=True).encode(); print(hashlib.sha256(encoded).hexdigest())' \
        "$input_json")"

    run env MAINFRAME_BASH="$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" \
        control-plane --ledger "$ledger" run-create \
        --run-id run-1 --actor agent:worker --workspace "$workspace" \
        --policy policy:v1
    [[ "$status" -eq 0 ]]

    run env MAINFRAME_BASH="$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" \
        control-plane --ledger "$ledger" run-transition --run-id run-1 --to active
    [[ "$status" -eq 0 ]]

    run env MAINFRAME_BASH="$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" \
        control-plane --ledger "$ledger" call-create \
        --call-id call-1 --run-id run-1 --tool control_plane.disposable_write \
        --effect mutating --input-json "$input_json"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$input_digest"* ]]

    run env MAINFRAME_BASH="$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" \
        control-plane --ledger "$ledger" call-request-approval --call-id call-1
    [[ "$status" -eq 3 ]]
    [[ "$output" == *'"ok": false'* ]]
    [[ "$output" == *'direct approval requests are disabled'* ]]

    run env MAINFRAME_BASH="$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" \
        control-plane --ledger "$ledger" approval-grant \
        --approval-id approval-1 --call-id call-1 \
        --tool control_plane.disposable_write --input-digest "$input_digest" \
        --actor agent:worker --workspace "$workspace" --policy policy:v1 \
        --expires-at 2099-01-01T00:00:00Z
    [[ "$status" -eq 3 ]]
    [[ "$output" == *'"code": "approval_authority_unavailable"'* ]]
    [[ ! -e "$workspace/result.txt" ]]
}

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    source "${AGENT_SAFETY_TEST_SOURCE:-$PROJECT_ROOT/lib/agent_safety.sh}"
    TEST_ROOT=$(mktemp -d)
    TEST_ROOT=$(cd "$TEST_ROOT" && pwd -P)
    mkdir "$TEST_ROOT/project" "$TEST_ROOT/outside"
    export AGENT_SAFE_BASE="$TEST_ROOT/project"
    export AGENT_AUDIT_LOG="$TEST_ROOT/audit.jsonl"
    export AGENT_CURRENT_PROFILE=project
    export AGENT_AUDIT_INCLUDE_COMMANDS=0
    export AGENT_RISK_THRESHOLD=100
}
teardown() { rm -rf -- "$TEST_ROOT"; }
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

@test "paths: readonly policy rejects absolute and relative mutation executables in both APIs" {
    printf marker > "$AGENT_SAFE_BASE/source"
    export AGENT_CURRENT_PROFILE=readonly
    for api in agent_safe_exec agent_safe_exec_capture; do
        for cmd in cp /bin/cp; do
            run "$api" "$cmd" "$AGENT_SAFE_BASE/source" "$AGENT_SAFE_BASE/copy"
            [ "$status" -ne 0 ]
            [ ! -e "$AGENT_SAFE_BASE/copy" ]
        done
        cd /bin
        run "$api" ./chmod 777 "$AGENT_SAFE_BASE/source"
        [ "$status" -ne 0 ]
        [ "$(mode_of "$AGENT_SAFE_BASE/source")" != 777 ]
    done
}
@test "paths: outside copy is denied while ordinary inside copies work" {
    printf marker > "$AGENT_SAFE_BASE/source"
    for api in agent_safe_exec agent_safe_exec_capture; do
        run "$api" /bin/cp "$AGENT_SAFE_BASE/source" "$TEST_ROOT/outside/copy"
        [ "$status" -ne 0 ]
        [ ! -e "$TEST_ROOT/outside/copy" ]
        run "$api" /bin/cp "$AGENT_SAFE_BASE/source" "$AGENT_SAFE_BASE/copy"
        [ "$status" -eq 0 ]
        [ "$(cat "$AGENT_SAFE_BASE/copy")" = marker ]
    done
}
@test "paths: risk is identical for bare absolute and relative command forms" {
    for cmd in rm chmod dd systemctl curl; do
        expected=$(agent_risk_score "$cmd" -R "$AGENT_SAFE_BASE")
        [ "$(agent_risk_score "/usr/bin/$cmd" -R "$AGENT_SAFE_BASE")" = "$expected" ]
        [ "$(agent_risk_score "./$cmd" -R "$AGENT_SAFE_BASE")" = "$expected" ]
    done
}
@test "paths: actual supplied executable must exist and be executable" {
    mkdir "$AGENT_SAFE_BASE/bin"
    printf '#!/usr/bin/env bash\nprintf supplied' > "$AGENT_SAFE_BASE/bin/echo"
    run agent_safe_exec "$AGENT_SAFE_BASE/bin/echo"
    [ "$status" -ne 0 ]
    chmod 700 "$AGENT_SAFE_BASE/bin/echo"
    run agent_safe_exec "$AGENT_SAFE_BASE/bin/echo"
    [ "$status" -eq 0 ]
    [ "$output" = supplied ]
    run agent_safe_exec "$AGENT_SAFE_BASE/bin"
    [ "$status" -ne 0 ]
}
@test "paths: recursive deletion is confined but documented plain-delete compatibility remains" {
    printf marker > "$TEST_ROOT/outside/file"
    for cmd in rm /bin/rm; do
        run agent_validate_command "$cmd" -rf "$TEST_ROOT/outside"
        [ "$status" -ne 0 ]
        run agent_validate_command "$cmd" "$TEST_ROOT/outside/file"
        [ "$status" -eq 0 ]
    done
    for cmd in chmod /bin/chmod; do
        run agent_validate_command "$cmd" 600 "$TEST_ROOT/outside/file"
        [ "$status" -eq 0 ]
    done
    [ "$(cat "$TEST_ROOT/outside/file")" = marker ]
}
@test "line: outside traversal sibling and symlink escapes cannot append" {
    printf marker > "$TEST_ROOT/outside/file"
    mkdir "$TEST_ROOT/project-sibling"
    ln -s "$TEST_ROOT/outside" "$AGENT_SAFE_BASE/escape"
    ln -s "$TEST_ROOT/outside/missing" "$AGENT_SAFE_BASE/dangling"
    for path in "$TEST_ROOT/outside/file" "$AGENT_SAFE_BASE/../outside/file" "$TEST_ROOT/project-sibling/file" "$AGENT_SAFE_BASE/escape/file" "$AGENT_SAFE_BASE/dangling"; do
        run agent_ensure_line "$path" added
        [ "$status" -ne 0 ]
    done
    [ "$(cat "$TEST_ROOT/outside/file")" = marker ]
    [ ! -e "$TEST_ROOT/outside/missing" ]
    [ ! -e "$TEST_ROOT/project-sibling/file" ]
}
@test "line: inside writes idempotency and a literal leading dash line work" {
    agent_ensure_line "$AGENT_SAFE_BASE/file" -literal >/dev/null
    agent_ensure_line "$AGENT_SAFE_BASE/file" -literal >/dev/null
    [ "$(wc -l < "$AGENT_SAFE_BASE/file" | tr -d ' ')" = 1 ]
    ln -s file "$AGENT_SAFE_BASE/link"
    agent_ensure_line "$AGENT_SAFE_BASE/link" second >/dev/null
    [ "$(tail -1 "$AGENT_SAFE_BASE/file")" = second ]
}
@test "symlink: confine placement including linked parent escapes" {
    ln -s "$TEST_ROOT/outside" "$AGENT_SAFE_BASE/escape"
    for path in "$TEST_ROOT/outside/link" "$AGENT_SAFE_BASE/../outside/link" "$AGENT_SAFE_BASE/escape/link"; do
        run agent_ensure_symlink "$path" target
        [ "$status" -ne 0 ]
        [ ! -L "$TEST_ROOT/outside/link" ]
    done
}
@test "symlink: relative targets and replacement of outward links remain valid" {
    printf target > "$AGENT_SAFE_BASE/target"
    agent_ensure_symlink "$AGENT_SAFE_BASE/link" target >/dev/null
    agent_ensure_symlink "$AGENT_SAFE_BASE/link" target >/dev/null
    [ "$(cat "$AGENT_SAFE_BASE/link")" = target ]
    # A target reference does not write there or grant permission to append.
    agent_ensure_symlink "$AGENT_SAFE_BASE/link" "$TEST_ROOT/outside/missing" >/dev/null
    run agent_ensure_line "$AGENT_SAFE_BASE/link" forbidden
    [ "$status" -ne 0 ]
    agent_ensure_symlink "$AGENT_SAFE_BASE/link" target >/dev/null
    [ "$(cat "$AGENT_SAFE_BASE/link")" = target ]
    [ ! -e "$TEST_ROOT/outside/missing" ]
}
@test "audit: permissive umask keeps append rotate and clear owner-private" {
    umask 022
    export AGENT_AUDIT_MAX_BYTES=1 AGENT_AUDIT_KEEP=2
    agent_audit first
    agent_audit second
    [ "$(mode_of "$AGENT_AUDIT_LOG")" = 600 ]
    [ "$(mode_of "$AGENT_AUDIT_LOG.1")" = 600 ]
    agent_audit_clear
    [ "$(mode_of "$AGENT_AUDIT_LOG")" = 600 ]
    [ "$(umask)" = 0022 ]
}
@test "audit: default uses a private directory without changing caller umask" {
    run env -u AGENT_AUDIT_LOG TMPDIR="$TEST_ROOT" bash -c '
        umask 022; source "$1"; agent_audit test || exit
        p=$AGENT_AUDIT_LOG
        mode=$(stat -c %a "$p" 2>/dev/null || stat -f %Lp "$p")
        dir_mode=$(stat -c %a "${p%/*}" 2>/dev/null || stat -f %Lp "${p%/*}")
        [[ $mode == 600 && $dir_mode == 700 && $(umask) == 0022 ]]
    ' _ "${AGENT_SAFETY_TEST_SOURCE:-$PROJECT_ROOT/lib/agent_safety.sh}"
    [ "$status" -eq 0 ]
}
@test "audit: unsafe append clear and rotation targets leave victim untouched" {
    printf victim > "$TEST_ROOT/victim"
    chmod 644 "$TEST_ROOT/victim"
    ln -s "$TEST_ROOT/victim" "$AGENT_AUDIT_LOG"
    run agent_audit append
    [ "$status" -ne 0 ]
    run agent_audit_clear
    [ "$status" -ne 0 ]
    rm "$AGENT_AUDIT_LOG"
    ln "$TEST_ROOT/victim" "$AGENT_AUDIT_LOG"
    run agent_audit append
    [ "$status" -ne 0 ]
    rm "$AGENT_AUDIT_LOG"
    agent_audit initial
    ln -s "$TEST_ROOT/victim" "$AGENT_AUDIT_LOG.1"
    AGENT_AUDIT_MAX_BYTES=1
    run agent_audit rotate
    [ "$status" -ne 0 ]
    [ "$(cat "$TEST_ROOT/victim")" = victim ]
    [ "$(mode_of "$TEST_ROOT/victim")" = 644 ]
}
@test "audit: raw commands and callback arguments are redacted unless explicitly opted in" {
    agent_safe_exec echo inert-secret-4931 >/dev/null
    callback() { :; }; agent_register_callback callback
    agent_callback callback inert-secret-4931 >/dev/null
    run grep -F inert-secret-4931 "$AGENT_AUDIT_LOG"
    [ "$status" -eq 1 ]
    jq -se 'any(.[]; .action == "exec_start")' "$AGENT_AUDIT_LOG" >/dev/null
    AGENT_AUDIT_INCLUDE_COMMANDS=1
    agent_safe_exec echo explicit-raw-4931 >/dev/null
    grep -q explicit-raw-4931 "$AGENT_AUDIT_LOG"
}
@test "audit: descriptor path remains supported" {
    exec {test_fd}> "$TEST_ROOT/descriptor.jsonl"
    AGENT_AUDIT_FD=$test_fd
    AGENT_AUDIT_LOG=/nonexistent/unused
    agent_audit agent_gateway_decision host=codex decision=allow
    exec {test_fd}>&-
    jq -e '.details | index("decision=allow")' "$TEST_ROOT/descriptor.jsonl" >/dev/null
}

@test "paths: execution wrappers retain risk for executable paths containing spaces" {
    mkdir "$AGENT_SAFE_BASE/My Tools"
    ln -s /bin/chmod "$AGENT_SAFE_BASE/My Tools/chmod"
    printf marker > "$AGENT_SAFE_BASE/file"
    AGENT_RISK_THRESHOLD=50
    for api in agent_safe_exec agent_safe_exec_capture; do
        run "$api" "$AGENT_SAFE_BASE/My Tools/chmod" -R 777 "$AGENT_SAFE_BASE/file"
        [ "$status" -ne 0 ]
        [ "$(mode_of "$AGENT_SAFE_BASE/file")" != 777 ]
        run "$api" "$AGENT_SAFE_BASE/My Tools/chmod" 600 "$AGENT_SAFE_BASE/file"
        [ "$status" -eq 0 ]
        [ "$(mode_of "$AGENT_SAFE_BASE/file")" = 600 ]
    done
}
@test "paths: GNU copy flags cannot consume or hide an outside destination" {
    printf marker > "$AGENT_SAFE_BASE/source"
    for option in --backup -s; do
        run agent_validate_command /bin/cp "$AGENT_SAFE_BASE/source" "$option" "$TEST_ROOT/outside/copy"
        [ "$status" -ne 0 ]
        run agent_validate_command /bin/cp "$AGENT_SAFE_BASE/source" "$option" "$AGENT_SAFE_BASE/copy"
        [ "$status" -eq 0 ]
    done
    for cmd in cp mv; do
        for option in "-t$TEST_ROOT/outside" "-vt$TEST_ROOT/outside" "--target-directory=$TEST_ROOT/outside"; do
            run agent_validate_command "$cmd" "$AGENT_SAFE_BASE/source" "$option"
            [ "$status" -ne 0 ]
        done
    done
    cd "$TEST_ROOT/outside"
    run agent_validate_command /bin/cp "$AGENT_SAFE_BASE/source" -- -outside
    [ "$status" -ne 0 ]
    run agent_validate_command /bin/rm -rf -- -outside
    [ "$status" -ne 0 ]
}
@test "paths: GNU copy effect regressions and legitimate options on available GNU cp" {
    local cp_bin=""
    for candidate in /usr/bin/cp /bin/cp /opt/homebrew/bin/gcp /usr/local/bin/gcp; do
        if [[ -x "$candidate" ]] && "$candidate" --version 2>/dev/null | grep -q 'GNU coreutils'; then
            cp_bin=$candidate; break
        fi
    done
    [[ -n "$cp_bin" ]] || skip "GNU cp effect check requires GNU coreutils (Linux CI)"
    printf marker > "$AGENT_SAFE_BASE/source"
    for api in agent_safe_exec agent_safe_exec_capture; do
        for option in --backup -s; do
            run "$api" "$cp_bin" "$AGENT_SAFE_BASE/source" "$option" "$TEST_ROOT/outside/copy"
            [ "$status" -ne 0 ]
            [ ! -e "$TEST_ROOT/outside/copy" ]
            run "$api" "$cp_bin" "$AGENT_SAFE_BASE/source" "$option" "$AGENT_SAFE_BASE/copy"
            [ "$status" -eq 0 ]
            [ "$(cat "$AGENT_SAFE_BASE/copy")" = marker ]
            rm "$AGENT_SAFE_BASE/copy"
        done
        mkdir -p "$AGENT_SAFE_BASE/dest"
        run "$api" "$cp_bin" -vt"$AGENT_SAFE_BASE/dest" "$AGENT_SAFE_BASE/source"
        [ "$status" -eq 0 ]
        [ "$(cat "$AGENT_SAFE_BASE/dest/source")" = marker ]
    done
}

@test "audit: unavailable audit blocks execution with an actionable error" {
    printf original > "$TEST_ROOT/victim"
    ln -s "$TEST_ROOT/victim" "$AGENT_AUDIT_LOG"
    for api in agent_safe_exec agent_safe_exec_capture; do
        run "$api" /bin/cp "$TEST_ROOT/victim" "$AGENT_SAFE_BASE/copy"
        [ "$status" -ne 0 ]
        # Use an in-base source so this tests audit failure, not confinement.
        printf marker > "$AGENT_SAFE_BASE/source"
        run "$api" /bin/cp "$AGENT_SAFE_BASE/source" "$AGENT_SAFE_BASE/copy"
        [ "$status" -ne 0 ]
        [[ "$output" == *"audit unavailable; command was not executed"* ]]
        [ ! -e "$AGENT_SAFE_BASE/copy" ]
    done
    [ "$(cat "$TEST_ROOT/victim")" = original ]
}

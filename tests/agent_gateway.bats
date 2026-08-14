#!/usr/bin/env bats
# End-to-end contract tests for the host-facing enforced policy gateway.

load 'test_helper'

setup() {
    TEST_DIR="$(create_test_dir agent_gateway)"
    export MAINFRAME_AGENT_AUDIT_LOG="$TEST_DIR/gateway.jsonl"
    GATEWAY="$MAINFRAME_ROOT/bin/mainframe"

    # Bind the same reviewed machine-local dependencies that `mainframe launch`
    # exports, then exercise the exact machine-independent string written into
    # host configuration. Tests must not take the public CLI shortcut: the
    # system-Bash bootstrap is the security boundary under test.
    source "$MAINFRAME_ROOT/lib/activate.sh"
    _mainframe_enforce_bind_runtime "$TEST_DIR" || {
        printf 'gateway test runtime binding failed: %s\n' \
            "${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}" >&2
        return 1
    }
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

generated_hook_command() {
    local format="$1" host
    case "$format" in
        codex|auto) host=codex ;;
        claude) host=claude-code ;;
        copilot) host=copilot ;;
        gemini) host=gemini ;;
        *) return 1 ;;
    esac
    _mainframe_enforce_command_for "$host"
}

run_hook() {
    local format="$1" payload="$2" command
    command="$(generated_hook_command "$format")" || return 1
    run /bin/bash --noprofile --norc -c "$command" <<<"$payload"
}

@test "Claude Bash hook allows a benign command and records the decision" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}'

    run_hook claude "$payload"

    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
    [ "$(jq -r '.details | join(" ")' "$MAINFRAME_AGENT_AUDIT_LOG")" = \
      "host=claude event=PreToolUse tool=Bash risk=low rule=none decision=allow" ]
    [ "$(file_mode "$MAINFRAME_AGENT_AUDIT_LOG")" = "600" ]
}

@test "Claude Bash hook denies an absolute-path recursive delete before execution" {
    local canary="$TEST_DIR/must-survive"
    mkdir -p "$canary"
    local payload
    payload="$(jq -cn --arg cmd "/bin/rm -rf $canary" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"

    run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=critical rule=recursive-force-rm"* ]]
    [ -d "$canary" ]
    jq -e '.details | index("decision=deny")' "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "Codex PreToolUse Bash payload uses its explicit host adapter" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}'

    run_hook codex "$payload"

    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
    [ "$(jq -r '.details | join(" ")' "$MAINFRAME_AGENT_AUDIT_LOG")" = \
      "host=codex event=PreToolUse tool=Bash risk=low rule=none decision=allow" ]
}

@test "Codex PreToolUse denies a destructive command before execution" {
    local canary="$TEST_DIR/codex-must-survive"
    mkdir -p "$canary"
    local payload
    payload="$(jq -cn --arg cmd "/bin/rm -rf $canary" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"

    run_hook codex "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=critical rule=recursive-force-rm"* ]]
    [ -d "$canary" ]
}

@test "Gemini BeforeTool run_shell_command uses the same gate" {
    local payload='{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"git reset --hard HEAD~1"}}'

    run_hook gemini "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=high rule=git-reset-hard"* ]]
}

@test "gateway reads a Gemini hook payload from an inherited pipe without reopening stdin" {
    local payload='{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"terraform destroy -auto-approve"}}'
    local command
    command="$(generated_hook_command gemini)"

    run env \
        MAINFRAME_TEST_HOOK_COMMAND="$command" \
        MAINFRAME_TEST_HOOK_PAYLOAD="$payload" \
        /bin/bash --noprofile --norc -c '
            printf "%s" "$MAINFRAME_TEST_HOOK_PAYLOAD" |
                /bin/bash --noprofile --norc -c "$MAINFRAME_TEST_HOOK_COMMAND"
        '

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=high rule=terraform-destroy"* ]]
    jq -e '
        .details == [
          "host=gemini",
          "event=BeforeTool",
          "tool=run_shell_command",
          "risk=high",
          "rule=terraform-destroy",
          "decision=deny"
        ]
    ' "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "Copilot native camelCase preToolUse payload is enforced" {
    local payload='{"toolName":"bash","toolArgs":"{\"command\":\"terraform destroy -auto-approve\"}"}'

    run_hook copilot "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=high rule=terraform-destroy"* ]]
}

@test "Copilot native object-form toolArgs is enforced" {
    local payload='{"toolName":"bash","toolArgs":{"command":"git reset --hard HEAD~1"}}'

    run_hook copilot "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"git-reset-hard"* ]]
}

@test "Copilot PascalCase snake_case payload is enforced" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm publish"}}'

    run_hook copilot "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"npm-publish"* ]]
}

@test "PowerShell fails closed until a native classifier exists" {
    local payload='{"toolName":"powershell","toolArgs":{"command":"Remove-Item -Recurse -Force C:\\\\Temp\\\\x"}}'

    run_hook copilot "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"outside the POSIX shell policy scope"* ]]
}

@test "non-shell tools pass without requiring a command" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"README.md"}}'

    run_hook claude "$payload"

    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
    jq -e '.details | index("rule=non-shell-tool")' "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "malformed JSON fails closed" {
    run_hook auto '{not-json'

    [ "$status" -eq 2 ]
    [[ "$output" == *"malformed JSON hook payload"* ]]
}

@test "raw NUL in an inherited hook payload fails closed" {
    local command
    command="$(generated_hook_command gemini)"

    run env MAINFRAME_TEST_HOOK_COMMAND="$command" python3 - <<'PY'
import os
import subprocess

payload = (
    b'{"hook_event_name":"BeforeTool","tool_name":"run_shell_command",'
    b'"tool_input":{"command":"git status --short"}}\0'
)
process = subprocess.run(
    ["/bin/bash", "--noprofile", "--norc", "-c", os.environ["MAINFRAME_TEST_HOOK_COMMAND"]],
    input=payload,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    check=False,
)
output = process.stdout.decode("utf-8", errors="replace")
assert process.returncode == 2, (process.returncode, output)
assert "malformed JSON hook payload" in output, output
print("nul_payload=refused")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "nul_payload=refused" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
}

@test "shell tool without a command fails closed" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}'

    run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"missing a string command"* ]]
}

@test "generated hook ignores inherited shell functions and preserves denial" {
    local canary="$TEST_DIR/exported-functions-must-survive"
    local marker="$TEST_DIR/exported-function-called"
    local command payload
    mkdir -p "$canary"
    command="$(generated_hook_command codex)"
    payload="$("$MAINFRAME_AGENT_JQ" -cn --arg cmd "/bin/rm -rf $canary" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"

    run /usr/bin/env \
        MAINFRAME_TEST_HOOK_COMMAND="$command" \
        MAINFRAME_TEST_HOOK_PAYLOAD="$payload" \
        MAINFRAME_TEST_FUNCTION_MARKER="$marker" \
        /bin/bash --noprofile --norc -c '
            mark_function() {
                builtin printf "%s\n" "$1" >> "$MAINFRAME_TEST_FUNCTION_MARKER"
            }
            exit() { mark_function exit; return 0; }
            set() { mark_function set; return 0; }
            jq() { mark_function jq; return 0; }
            dirname() { mark_function dirname; return 0; }
            readlink() { mark_function readlink; return 0; }
            mkdir() { mark_function mkdir; return 0; }
            chmod() { mark_function chmod; return 0; }
            cat() { mark_function cat; return 0; }
            date() { mark_function date; return 0; }
            wc() { mark_function wc; return 0; }
            tr() { mark_function tr; return 0; }
            mv() { mark_function mv; return 0; }
            source() { mark_function source; return 0; }
            agent_gate_classify() { mark_function agent_gate_classify; return 0; }
            agent_audit() { mark_function agent_audit; return 0; }
            export -f mark_function exit set jq dirname readlink mkdir chmod cat
            export -f date wc tr mv source agent_gate_classify agent_audit
            builtin printf "%s" "$MAINFRAME_TEST_HOOK_PAYLOAD" |
                /bin/bash --noprofile --norc -c "$MAINFRAME_TEST_HOOK_COMMAND"
        '

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=critical rule=recursive-force-rm"* ]]
    [ -d "$canary" ]
    [ ! -e "$marker" ]
    "$MAINFRAME_AGENT_JQ" -e '.details | index("decision=deny")' \
        "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "generated hook ignores BASH_ENV inside privileged descendants" {
    local canary="$TEST_DIR/bash-env-must-survive"
    local startup_marker="$TEST_DIR/bash-env-sourced"
    local function_marker="$TEST_DIR/bash-env-function-called"
    local bash_env="$TEST_DIR/host-bash-env.sh"
    local command payload
    mkdir -p "$canary"
    command="$(generated_hook_command codex)"
    payload="$("$MAINFRAME_AGENT_JQ" -cn --arg cmd "/bin/rm -rf $canary" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"
    cat > "$bash_env" <<'EOF'
builtin printf 'sourced\n' >> "$MAINFRAME_TEST_BASH_ENV_MARKER"
mark_bash_env_function() {
    builtin printf '%s\n' "$1" >> "$MAINFRAME_TEST_FUNCTION_MARKER"
}
exit() { mark_bash_env_function exit; return 0; }
set() { mark_bash_env_function set; return 0; }
jq() { mark_bash_env_function jq; return 0; }
cat() { mark_bash_env_function cat; return 0; }
export -f mark_bash_env_function exit set jq cat
EOF

    # A fresh non-privileged shell reads BASH_ENV once before it can interpret
    # any hook command. The two privileged Bash descendants must not read it
    # again or import the functions it defines.
    run /usr/bin/env \
        BASH_ENV="$bash_env" \
        MAINFRAME_TEST_BASH_ENV_MARKER="$startup_marker" \
        MAINFRAME_TEST_FUNCTION_MARKER="$function_marker" \
        /bin/bash --noprofile --norc -c "$command" <<<"$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=critical rule=recursive-force-rm"* ]]
    [ -d "$canary" ]
    [ "$(count_lines "$startup_marker")" -eq 1 ]
    [ ! -e "$function_marker" ]
    "$MAINFRAME_AGENT_JQ" -e '.details | index("decision=deny")' \
        "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "generated hook ignores PATH helper replacements" {
    local canary="$TEST_DIR/path-fakes-must-survive"
    local fake_bin="$TEST_DIR/fake-bin"
    local marker="$TEST_DIR/path-fake-called"
    local helper command payload
    mkdir -p "$canary" "$fake_bin"
    command="$(generated_hook_command codex)"
    payload="$("$MAINFRAME_AGENT_JQ" -cn --arg cmd "/bin/rm -rf $canary" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"

    for helper in bash jq dirname readlink mkdir chmod cat date wc tr mv; do
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "%s\n" "$0" >> "$MAINFRAME_TEST_PATH_MARKER"' \
            'exit 0' > "$fake_bin/$helper"
        chmod +x "$fake_bin/$helper"
    done

    run /usr/bin/env \
        PATH="$fake_bin" \
        MAINFRAME_TEST_PATH_MARKER="$marker" \
        /bin/bash --noprofile --norc -c "$command" <<<"$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=critical rule=recursive-force-rm"* ]]
    [ -d "$canary" ]
    [ ! -e "$marker" ]
    "$MAINFRAME_AGENT_JQ" -e '.details | index("decision=deny")' \
        "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "generated hook blocks unsupported dynamic shell evaluation" {
    local command payload
    local -a commands=(
        "eval 'rm -rf /tmp/mainframe-dynamic-eval'"
        '$(printf "rm -rf /tmp/mainframe-dynamic-substitution")'
        "x='rm -rf'; \$x /tmp/mainframe-dynamic-variable"
        "payload='rm -rf /tmp/mainframe-dynamic-code'; bash -c \"\$payload\""
        "true; x=rm; (\$x -rf /tmp/mainframe-dynamic-subshell)"
        "\$'\\x72\\x6d' -rf /tmp/mainframe-dynamic-ansi"
        $'rm \036 -rf /tmp/mainframe-marker-collision'
        "sh -c 'eval \"rm -rf /tmp/mainframe-dynamic-shell\"'"
        'echo `printf hidden-command`'
    )

    for command in "${commands[@]}"; do
        payload="$("$MAINFRAME_AGENT_JQ" -cn --arg cmd "$command" \
            '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"
        run_hook claude "$payload"
        [ "$status" -eq 2 ]
        [[ "$output" == *"risk=critical"* ]]
    done
}

@test "generated hook seal rejects post-launch gateway replacement" {
    local runtime_root="$TEST_DIR/sealed-runtime"
    local project="$TEST_DIR/sealed-project"
    local payload command
    mkdir -p "$runtime_root/hooks" "$runtime_root/lib" "$project"
    cp "$MAINFRAME_ROOT/hooks/agent-gateway.sh" "$runtime_root/hooks/agent-gateway.sh"
    cp "$MAINFRAME_ROOT/lib/agent_safety.sh" "$runtime_root/lib/agent_safety.sh"
    chmod +x "$runtime_root/hooks/agent-gateway.sh"

    MAINFRAME_ROOT="$runtime_root"
    export MAINFRAME_ROOT
    _mainframe_enforce_bind_runtime "$project"
    command="$(_mainframe_enforce_command_for claude-code)"
    payload="$("$MAINFRAME_AGENT_JQ" -cn \
        --arg cmd ': > "$MAINFRAME_AGENT_GATEWAY"' \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"
    run /bin/bash --noprofile --norc -c "$command" <<<"$payload"
    [ "$status" -eq 0 ]

    : >"$MAINFRAME_AGENT_GATEWAY"
    payload="$("$MAINFRAME_AGENT_JQ" -cn --arg cmd 'rm -rf /tmp/mainframe-must-not-run' \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"
    run /bin/bash --noprofile --norc -c "$command" <<<"$payload"
    [ "$status" -eq 2 ]
}

@test "runtime binder rejects a PATH-first user jq wrapper" {
    local fake_bin="$TEST_DIR/user-bin"
    local marker="$TEST_DIR/fake-jq-ran"
    mkdir -p "$fake_bin"
    printf '%s\n' '#!/bin/sh' "printf 'ran\\n' > '$marker'" 'exit 0' \
        >"$fake_bin/jq"
    chmod +x "$fake_bin/jq"

    run env PATH="$fake_bin:$PATH" MAINFRAME_ROOT="$MAINFRAME_ROOT" \
        "$MAINFRAME_AGENT_BASH" --noprofile --norc -p -c \
        'source "$1/lib/activate.sh"; _mainframe_enforce_bind_runtime "$2"' \
        _ "$MAINFRAME_ROOT" "$TEST_DIR"

    [ "$status" -ne 0 ]
    [ ! -e "$marker" ]
}

@test "unsafe audit directory and hardlinked audit file fail closed" {
    local unsafe_dir="$TEST_DIR/unsafe-audit"
    local original="$TEST_DIR/original-audit"
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}'
    mkdir -p "$unsafe_dir"
    chmod 0777 "$unsafe_dir"
    MAINFRAME_AGENT_AUDIT_LOG="$unsafe_dir/gateway.jsonl"
    export MAINFRAME_AGENT_AUDIT_LOG
    run_hook claude "$payload"
    [ "$status" -eq 2 ]
    [[ "$output" == *"writable by group or other users"* ]]

    chmod 0700 "$unsafe_dir"
    printf 'original\n' >"$original"
    ln "$original" "$unsafe_dir/gateway.jsonl"
    run_hook claude "$payload"
    [ "$status" -eq 2 ]
    [[ "$output" == *"exactly one hard link"* ]]
    [ "$(<"$original")" = "original" ]
}

@test "audit JSON escapes every control byte used by host metadata" {
    local payload
    payload="$("$MAINFRAME_AGENT_JQ" -cn --arg tool $'Read\tFile\r\b\f\u0001' \
        '{hook_event_name:"PreToolUse",tool_name:$tool,tool_input:{}}')"

    run_hook claude "$payload"

    [ "$status" -eq 0 ]
    "$MAINFRAME_AGENT_JQ" -e . "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
    "$MAINFRAME_AGENT_JQ" -e '.details[2] == "tool=Read\tFile\r\b\f\u0001"' \
        "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "audit and denial output never disclose raw command secrets" {
    local secret="gateway-secret-$RANDOM-$$"
    local payload
    payload="$(jq -cn --arg cmd "printf '%s' '$secret'" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}')"

    run_hook claude "$payload"

    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
    run grep -Fq "$secret" "$MAINFRAME_AGENT_AUDIT_LOG"
    [ "$status" -eq 1 ]
    jq -e . "$MAINFRAME_AGENT_AUDIT_LOG" >/dev/null
}

@test "symbolic-link audit targets fail closed" {
    local target="$TEST_DIR/real-audit.jsonl"
    local link="$TEST_DIR/linked-audit.jsonl"
    : > "$target"
    ln -s "$target" "$link"
    export MAINFRAME_AGENT_AUDIT_LOG="$link"
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'

    run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"audit log may not be a symbolic link"* ]]
    [ ! -s "$target" ]
}

@test "symbolic-link audit directory ancestors fail closed" {
    local outside="$TEST_DIR/outside-audit"
    local linked_parent="$TEST_DIR/linked-state"
    mkdir -p "$outside"
    ln -s "$outside" "$linked_parent"
    export MAINFRAME_AGENT_AUDIT_LOG="$linked_parent/mainframe/gateway.jsonl"
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'

    run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"audit directory contains a symbolic-link"* ]]
    [ ! -e "$outside/mainframe/gateway.jsonl" ]
}

@test "relative audit paths fail closed" {
    export MAINFRAME_AGENT_AUDIT_LOG="relative/gateway.jsonl"
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'

    run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"audit log must be a canonical absolute path"* ]]
}

@test "generated hook rejects an incomplete or malformed five-value runtime contract" {
    local binding command
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'
    command="$(generated_hook_command codex)"

    for binding in \
        MAINFRAME_AGENT_BASH \
        MAINFRAME_AGENT_JQ \
        MAINFRAME_AGENT_GATEWAY \
        MAINFRAME_AGENT_SAFETY \
        MAINFRAME_AGENT_SEAL; do
        [[ "$command" == *"$binding"* ]]
        run /usr/bin/env -u "$binding" \
            /bin/bash --noprofile --norc -c "$command" <<<"$payload"
        [ "$status" -eq 2 ]
    done

    for binding in \
        MAINFRAME_AGENT_BASH \
        MAINFRAME_AGENT_JQ \
        MAINFRAME_AGENT_GATEWAY \
        MAINFRAME_AGENT_SAFETY; do
        run /usr/bin/env "$binding=relative/path" \
            /bin/bash --noprofile --norc -c "$command" <<<"$payload"
        [ "$status" -eq 2 ]
    done

    run /usr/bin/env MAINFRAME_AGENT_SEAL=not-a-four-digest-seal \
        /bin/bash --noprofile --norc -c "$command" <<<"$payload"
    [ "$status" -eq 2 ]
}

@test "stock macOS Bash 3.2 bootstraps the bound supported Bash" {
    [ -x /bin/bash ] || skip "/bin/bash unavailable"
    [ "$(/usr/bin/uname -s)" = "Darwin" ] || skip "macOS-only bootstrap contract"
    if /bin/bash -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))'; then
        skip "/bin/bash is already Bash 4.4+"
    fi
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'

    run_hook claude "$payload"

    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "unexpected gateway option errors are normalized to the blocking exit code" {
    run "$GATEWAY" agent-hook --not-a-real-option

    [ "$status" -eq 2 ]
    [[ "$output" == *"internal gateway failure"* ]]
}

@test "medium tier can be denied by policy configuration" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm publish"}}'

    MAINFRAME_AGENT_GATE_TIER=medium run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=medium rule=npm-publish"* ]]
}

@test "medium risk is denied by default" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'

    run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"risk=medium rule=git-push-force"* ]]
}

@test "invalid policy tier fails closed" {
    local payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'

    MAINFRAME_AGENT_GATE_TIER=unknown run_hook claude "$payload"

    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid MAINFRAME_AGENT_GATE_TIER"* ]]
}

@test "CLI exposes agent-hook help without reading stdin" {
    run "$GATEWAY" agent-hook --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mainframe agent-hook"* ]]
}

@test "clean-environment CLI exposes diagnostic agent-hook help" {
    run env -i \
        HOME="$HOME" \
        PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        MAINFRAME_BASH="$MAINFRAME_AGENT_BASH" \
        "$MAINFRAME_ROOT/bin/mainframe" agent-hook --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mainframe agent-hook"* ]]
}

@test "Linux audit descriptor identity dereferences fd and compares device plus inode" {
    run grep -F "/usr/bin/stat -L -c '%d:%i'" \
        "$MAINFRAME_ROOT/hooks/agent-gateway.sh"
    [ "$status" -eq 0 ]
}

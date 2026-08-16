#!/usr/bin/env bats
# Guided setup must remain discovery-only until one host is explicit.

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    TEST_DIR="$(create_test_dir guided-setup)"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    PROJECT_DIR="$TEST_DIR/project with spaces"
    CLI_DIR="$TEST_DIR/bin"
    RUNTIME_ROOT="$TEST_DIR/mainframe runtime"
    TEST_HOME="$TEST_DIR/home"
    PI_AGENT_DIR="$TEST_HOME/.pi/agent"
    BASE_PATH="$PATH"
    DISCOVERY_PATH="$CLI_DIR:/usr/bin:/bin"
    FAKE_HOST_LOG="$TEST_DIR/host.log"
    FAKE_HOST_PROBE_LOG="$TEST_DIR/host-probe.log"
    FAKE_PI_LOG="$TEST_DIR/pi.log"
    PROOF_INVOKE_AUDIT_LOG="$TEST_DIR/state/proof-invocations.jsonl"
    PROOF_XDG_STATE_HOME="$TEST_DIR/proof-xdg-state"
    PROOF_XDG_CONFIG_HOME="$TEST_DIR/proof-xdg-config"

    mkdir -p \
        "$PROJECT_DIR" \
        "$CLI_DIR" \
        "$TEST_HOME" \
        "$PI_AGENT_DIR" \
        "$RUNTIME_ROOT/bin" \
        "$RUNTIME_ROOT/hooks" \
        "$RUNTIME_ROOT/scripts/dev/native-host"
    cp "$PROJECT_ROOT/bin/mainframe" "$RUNTIME_ROOT/bin/mainframe"
    cp "$PROJECT_ROOT/hooks/agent-gateway.sh" \
        "$RUNTIME_ROOT/hooks/agent-gateway.sh"
    cp "$PROJECT_ROOT/scripts/dev/native-host/hosts.json" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/package-lock.json" \
        "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/release-platforms.json" \
        "$RUNTIME_ROOT/scripts/dev/native-host/release-platforms.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/hash-package-tree.py" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.py"
    cp "$PROJECT_ROOT/scripts/dev/native-host/hash-package-tree.mjs" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.mjs"
    chmod +x \
        "$RUNTIME_ROOT/bin/mainframe" \
        "$RUNTIME_ROOT/hooks/agent-gateway.sh" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.mjs" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.py"
    ln -s "$PROJECT_ROOT/lib" "$RUNTIME_ROOT/lib"
    ln -s "$PROJECT_ROOT/FUNCTIONS.json" "$RUNTIME_ROOT/FUNCTIONS.json"
    ln -s "$RUNTIME_ROOT/bin/mainframe" "$CLI_DIR/mainframe"

    chmod 700 "$TEST_HOME" "$TEST_HOME/.pi" "$PI_AGENT_DIR"
    export PROJECT_ROOT BASH_BIN TEST_DIR PROJECT_DIR CLI_DIR RUNTIME_ROOT
    export TEST_HOME PI_AGENT_DIR BASE_PATH FAKE_HOST_LOG FAKE_HOST_PROBE_LOG
    export FAKE_PI_LOG PROOF_INVOKE_AUDIT_LOG
    export PROOF_XDG_STATE_HOME PROOF_XDG_CONFIG_HOME
    export HOME="$TEST_HOME"
    export MAINFRAME_PI_AGENT_DIR="$PI_AGENT_DIR"
    export AWM_ROOT="$TEST_HOME/.mainframe/awm"
    export MAINFRAME_ROOT="$RUNTIME_ROOT"
    export MAINFRAME_BASH="$BASH_BIN"
    export MAINFRAME_AGENT_AUDIT_LOG="$TEST_DIR/state/gateway.jsonl"
    export SHELL=/bin/zsh
    unset MAINFRAME_AGENT_GATE_TIER PI_CODING_AGENT_DIR
    unset MAINFRAME_PI_YES MAINFRAME_YES
    unset _MAINFRAME_SETUP_TEST_FORCE_AWM_RETRIEVAL_FAILURE
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

setup_discovery() {
    env PATH="$DISCOVERY_PATH" "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" setup "$@"
}

setup_full() {
    env PATH="$CLI_DIR:$BASE_PATH" "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" setup "$@"
}

setup_proof() {
    env \
        PATH="$DISCOVERY_PATH" \
        XDG_STATE_HOME="$PROOF_XDG_STATE_HOME" \
        XDG_CONFIG_HOME="$PROOF_XDG_CONFIG_HOME" \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        MAINFRAME_INVOKE_AUDIT_LOG="$PROOF_INVOKE_AUDIT_LOG" \
        "$BASH_BIN" --noprofile --norc -p \
            "$PROJECT_ROOT/bin/mainframe" setup "$@"
}

setup_proof_temp_dirs() {
    local proof_base

    proof_base="$(cd -- /tmp && pwd -P)" || return 1
    find "$proof_base" -maxdepth 1 -type d \
        -name 'mainframe-setup-proof.*' -print | LC_ALL=C sort
}

sha256_file() {
    local file="$1" output digest

    if [[ -x /usr/bin/sha256sum ]]; then
        output="$(/usr/bin/sha256sum "$file")" || return 1
    elif [[ -x /bin/sha256sum ]]; then
        output="$(/bin/sha256sum "$file")" || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        output="$(/usr/bin/shasum -a 256 "$file")" || return 1
    elif [[ -x /usr/bin/openssl ]]; then
        output="$(/usr/bin/openssl dgst -sha256 -r "$file")" || return 1
    elif [[ -x /bin/openssl ]]; then
        output="$(/bin/openssl dgst -sha256 -r "$file")" || return 1
    else
        return 1
    fi
    read -r digest _ <<< "$output"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

pin_fake_host() {
    local host="$1" executable="$2" manifest manifest_host
    local uname_bin current_os current_arch platform_key digest temporary

    manifest="$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"
    case "$host" in
        codex|copilot|gemini) manifest_host="$host" ;;
        claude) manifest_host=claude ;;
        *) return 1 ;;
    esac
    if [[ -x /usr/bin/uname ]]; then
        uname_bin=/usr/bin/uname
    elif [[ -x /bin/uname ]]; then
        uname_bin=/bin/uname
    else
        return 1
    fi
    current_os="$($uname_bin -s)" || return 1
    current_arch="$($uname_bin -m)" || return 1
    platform_key="$(jq -er \
        --arg host "$manifest_host" \
        --arg prefix "$current_os-$current_arch" '
          [(.[$host].platforms // {}) | keys[] |
            select(. == $prefix or startswith($prefix + "-"))] |
          if length == 0 then $prefix else first end
        ' "$manifest")" || return 1
    digest="$(sha256_file "$executable")" || return 1
    temporary="$manifest.tmp.$$"
    jq \
        --arg host "$manifest_host" \
        --arg platform "$platform_key" \
        --arg digest "$digest" '
          .[$host].platforms = (.[$host].platforms // {}) |
          .[$host].platforms[$platform].executable_sha256 = $digest
        ' "$manifest" > "$temporary" || {
        rm -f "$temporary"
        return 1
    }
    mv "$temporary" "$manifest"
}

assert_no_setup_state() {
    [[ ! -e "$AWM_ROOT" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    [[ ! -e "$PROOF_INVOKE_AUDIT_LOG" ]]
    [[ ! -e "$PROOF_XDG_STATE_HOME" ]]
    [[ ! -e "$PROOF_XDG_CONFIG_HOME" ]]
    [[ ! -e "$PROJECT_DIR/AGENTS.md" ]]
    [[ ! -e "$PROJECT_DIR/CLAUDE.md" ]]
    [[ ! -e "$PROJECT_DIR/GEMINI.md" ]]
    [[ ! -e "$PROJECT_DIR/.codex/hooks.json" ]]
    [[ ! -e "$PROJECT_DIR/.claude/settings.json" ]]
    [[ ! -e "$PROJECT_DIR/.github/hooks/mainframe.json" ]]
    [[ -z "$(find "$PI_AGENT_DIR" -mindepth 1 -print -quit)" ]]
}

make_host_cli() {
    local name="$1"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'if [[ "${1:-}" == "--version" || "${1:-}" == "--help" ]]; then'
        printf '%s\n' '  printf "%s\n" "$1" >> "${FAKE_HOST_PROBE_LOG:?}"'
        printf '%s\n' '  exit 97'
        printf '%s\n' 'fi'
        printf '%s\n' 'printf "executed\n" >> "${FAKE_HOST_LOG:?}"'
        printf '%s\n' 'exit 0'
    } > "$CLI_DIR/$name"
    chmod +x "$CLI_DIR/$name"
    pin_fake_host "$name" "$CLI_DIR/$name"
}

make_pi_cli() {
    {
        printf '%s\n' '#!/usr/bin/env bash'
        # shellcheck disable=SC2016 # Expanded only by the isolated fake CLI.
        printf '%s\n' 'printf "executed\n" >> "${FAKE_PI_LOG:?}"'
        printf '%s\n' 'exit 97'
    } > "$CLI_DIR/pi"
    chmod +x "$CLI_DIR/pi"
}

@test "setup help documents discovery-only and explicit-host modes" {
    run setup_discovery --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe setup --project <dir>"* ]]
    [[ "$output" == *"Without --host"*"strictly read-only"* ]]
    [[ "$output" == *"never auto-selects a host"* ]]
    [[ "$output" == *"codex, claude-code, copilot, gemini"* ]]
    [[ "$output" == *"Pi uses a separate user-package flow"* ]]
    [[ "$output" == *"--proof"*"hostless zero-residue first-run mechanism proof"* ]]
}

@test "top-level help leads with read-only setup and the Pi preview path" {
    local start_line commands_line

    run env PATH="$DISCOVERY_PATH" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Start here (read-only):"* ]]
    [[ "$output" == *"mainframe setup --project . --proof"* ]]
    [[ "$output" == *"mainframe setup --project ."* ]]
    [[ "$output" == *"Using Pi:"* ]]
    [[ "$output" == *"mainframe pi doctor"* ]]
    [[ "$output" == *"mainframe pi install --dry-run"* ]]
    start_line="$(grep -nF 'Start here (read-only):' <<< "$output" | cut -d: -f1)"
    commands_line="$(grep -nF 'Commands:' <<< "$output" | cut -d: -f1)"
    [[ "$start_line" -lt "$commands_line" ]]
    assert_no_setup_state
}

@test "setup proof exercises fixed mechanisms and retains no user project or audit state" {
    local proof_dirs_before proof_dirs_after

    make_pi_cli
    make_host_cli codex
    proof_dirs_before="$(setup_proof_temp_dirs)"

    run setup_proof --project "$PROJECT_DIR" --proof
    proof_dirs_after="$(setup_proof_temp_dirs)"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME First-Run Proof"* ]]
    [[ "$output" == *"Mode: zero-residue mechanism proof"* ]]
    [[ "$output" == *"Install health:     PASS"* ]]
    [[ "$output" == *"Reviewed invocation: PASS (fixed pure contract; output=hello agent)"* ]]
    [[ "$output" == *"Durable memory:     PASS (fixed key retrieved by a fresh Bash process)"* ]]
    [[ "$output" == *"Temporary state:    REMOVED (private mode 700)"* ]]
    [[ "$output" == *"Shell policy:       PASS (classification only; canary not executed; rule=terraform-destroy)"* ]]
    [[ "$output" == *"Pi package:"*"CLI found; not executed"* ]]
    [[ "$output" == *"Host candidates: codex"* ]]
    [[ "$output" == *"Next safe command:  mainframe pi install --dry-run"* ]]
    [[ "$output" == *"Agent improvement/adoption: UNVERIFIED (mechanism proof only; no coding agent ran)"* ]]
    [[ "$output" == *"Live host protection: UNVERIFIED"* ]]
    [[ "$output" == *"temporary AWM and broker state were removed"* ]]
    [[ ! "$output" =~ [0-9a-f]{32} ]]
    [[ ! -e "$FAKE_PI_LOG" ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
    [[ "$proof_dirs_after" == "$proof_dirs_before" ]]
    assert_no_setup_state
    [[ -z "$(find "$PROJECT_DIR" -mindepth 1 -print -quit)" ]]
}

@test "setup proof removes ephemeral AWM after forced fresh-process retrieval failure" {
    local proof_dirs_before proof_dirs_after

    proof_dirs_before="$(setup_proof_temp_dirs)"
    export _MAINFRAME_SETUP_TEST_FORCE_AWM_RETRIEVAL_FAILURE=1
    run setup_proof --project "$PROJECT_DIR" --proof
    unset _MAINFRAME_SETUP_TEST_FORCE_AWM_RETRIEVAL_FAILURE
    proof_dirs_after="$(setup_proof_temp_dirs)"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ephemeral AWM fresh-process retrieval failed"* ]]
    [[ "$output" != *"Durable memory:     PASS"* ]]
    [[ ! "$output" =~ [0-9a-f]{32} ]]
    [[ "$proof_dirs_after" == "$proof_dirs_before" ]]
    assert_no_setup_state
    [[ -z "$(find "$PROJECT_DIR" -mindepth 1 -print -quit)" ]]
}

@test "setup proof rejects every mutation selector before proof execution" {
    local combination
    local -a combinations=(
        '--proof --host codex'
        '--proof --runtime auto'
        '--proof --dry-run'
        '--proof --yes'
        '--proof --proof'
    )

    for combination in "${combinations[@]}"; do
        # shellcheck disable=SC2206 # Test fixture intentionally expands fixed words.
        local -a args=( $combination )
        run setup_proof --project "$PROJECT_DIR" "${args[@]}"
        [[ "$status" -eq 2 ]]
        [[ "$output" == *"MAINFRAME setup:"* ]]
        assert_no_setup_state
    done
}

@test "top-level setup scrubs code loaders and never executes project PATH discoveries" {
    local injection_bin trusted_tools command_name jq_bin injection_detected=false
    local command_log loader_log bash_sentinel node_sentinel

    injection_bin="$PROJECT_DIR/injected bin"
    trusted_tools="$TEST_DIR/trusted tools"
    command_log="$TEST_DIR/injected-command.log"
    loader_log="$TEST_DIR/code-loader.log"
    bash_sentinel="$PROJECT_DIR/bash-env-sentinel.sh"
    node_sentinel="$PROJECT_DIR/node-options-sentinel.js"
    jq_bin="$(command -v jq)"
    mkdir -p "$injection_bin" "$trusted_tools"
    ln -s "$jq_bin" "$trusted_tools/jq"

    {
        printf '%s\n' 'printf "BASH_ENV executed\\n" >> "${SETUP_LOADER_LOG:?}"'
    } > "$bash_sentinel"
    {
        printf '%s\n' 'require("node:fs").appendFileSync('
        printf '%s\n' '  process.env.SETUP_LOADER_LOG,'
        printf '%s\n' '  "NODE_OPTIONS executed\\n",'
        printf '%s\n' ');'
    } > "$node_sentinel"

    for command_name in \
        bash zsh jq codex claude copilot gemini pi node \
        awk find grep openssl readlink sed sha256sum sort stat tr uname; do
        {
            printf '%s\n' '#!/bin/bash'
            printf '%s\n' 'printf "%s\\n" "${0##*/}" >> "${SETUP_COMMAND_LOG:?}"'
            printf '%s\n' 'exit 97'
        } > "$injection_bin/$command_name"
        chmod +x "$injection_bin/$command_name"
    done

    run env \
        PATH="$trusted_tools:$injection_bin:/usr/bin:/bin" \
        MAINFRAME_BASH="$BASH_BIN" \
        SETUP_COMMAND_LOG="$command_log" \
        SETUP_LOADER_LOG="$loader_log" \
        BASH_ENV="$bash_sentinel" \
        ENV="$bash_sentinel" \
        NODE_OPTIONS="--require=$node_sentinel" \
        NODE_PATH="$PROJECT_DIR/node modules" \
        PERL5OPT="-I$PROJECT_DIR/perl modules" \
        LD_LIBRARY_PATH="$PROJECT_DIR/loader path" \
        DYLD_LIBRARY_PATH="$PROJECT_DIR/loader path" \
        "$RUNTIME_ROOT/bin/mainframe" setup --project "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Mode: discovery only (strictly read-only)"* ]]
    if [[ -e "$command_log" ]]; then
        printf 'project/PATH command executed unexpectedly:\n%s\n' \
            "$(< "$command_log")" >&3
        injection_detected=true
    fi
    if [[ -e "$loader_log" ]]; then
        printf 'code-loader sentinel executed unexpectedly:\n%s\n' \
            "$(< "$loader_log")" >&3
        injection_detected=true
    fi
    [[ "$injection_detected" == false ]]
    assert_no_setup_state
}

@test "hostless setup reports Pi CLI and package state without executing or mutating Pi" {
    make_pi_cli

    run setup_discovery --project "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pi integration (user package; separate from project hooks)"* ]]
    [[ "$output" == *"CLI:     found ($CLI_DIR/pi; discovered only, not executed)"* ]]
    [[ "$output" == *"Package: not-installed ($PI_AGENT_DIR)"* ]]
    [[ "$output" == *"mainframe pi status"* ]]
    [[ "$output" == *"mainframe pi doctor"* ]]
    [[ "$output" == *"mainframe pi install --dry-run"* ]]
    [[ "$output" != *"mainframe setup"*"--host pi"*"--runtime"* ]]
    [[ ! -e "$FAKE_PI_LOG" ]]
    assert_no_setup_state
}

@test "setup explains that Pi must initialize its missing user agent directory first" {
    make_pi_cli
    rmdir "$PI_AGENT_DIR"

    run setup_discovery --project "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Package: not-initialized ($PI_AGENT_DIR does not exist)"* ]]
    [[ "$output" == *"Pi must create its user agent directory before MAINFRAME can preview activation."* ]]
    [[ "$output" == *"Exact next action:"* ]]
    [[ "$output" == *$'    pi\n'* ]]
    [[ "$output" == *"After Pi starts, exit it and run:"* ]]
    [[ "$output" == *"mainframe pi doctor"* ]]
    [[ "$output" != *"mainframe pi install --dry-run"* ]]
    [[ "$output" != *"mainframe pi install --yes"* ]]
    [[ "$output" != *"mainframe pi status"* ]]
    [[ ! -e "$FAKE_PI_LOG" ]]
    [[ ! -e "$PI_AGENT_DIR" ]]
    [[ ! -e "$AWM_ROOT" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
}

@test "missing Pi directory never recommends executing an undiscovered Pi command" {
    rmdir "$PI_AGENT_DIR"

    run setup_discovery --project "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"CLI:     missing (not found on PATH)"* ]]
    [[ "$output" == *"Install or safely expose Pi, run it once, and then rerun this discovery."* ]]
    [[ "$output" == *"no safe Pi CLI was found"* ]]
    [[ "$output" != *"Exact next action:"* ]]
    [[ "$output" != *$'    pi\n'* ]]
    [[ "$output" != *"mainframe pi install --dry-run"* ]]
    assert_no_setup_state
}

@test "explicit Pi setup with a missing agent directory offers no impossible apply" {
    make_pi_cli
    rmdir "$PI_AGENT_DIR"

    run setup_full --project "$PROJECT_DIR" --host pi

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME Pi Setup"* ]]
    [[ "$output" == *"Exact next action:"* ]]
    [[ "$output" == *$'    pi\n'* ]]
    [[ "$output" == *"mainframe pi doctor"* ]]
    [[ "$output" != *"mainframe pi status"* ]]
    [[ "$output" != *"mainframe pi install --dry-run"* ]]
    [[ "$output" != *"mainframe pi install --yes"* ]]
    [[ ! -e "$FAKE_PI_LOG" ]]
    assert_no_setup_state
}

@test "explicit Pi setup stays in the dedicated package flow and previews read-only" {
    make_pi_cli

    run setup_full --project "$PROJECT_DIR" --host pi

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME Pi Setup"* ]]
    [[ "$output" == *"Pi uses a user-scoped package flow, not project hook onboarding."* ]]
    [[ "$output" == *"Package: not-installed ($PI_AGENT_DIR)"* ]]
    [[ "$output" == *"mainframe pi install --yes"* ]]
    [[ ! -e "$FAKE_PI_LOG" ]]
    assert_no_setup_state

    run setup_full --project "$PROJECT_DIR" --host pi --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'action=install'* ]]
    [[ "$output" == *'dry_run=true'* ]]
    [[ "$output" == *'would_change=true'* ]]
    [[ "$output" == *"would_set_package_source=$PROJECT_ROOT"* ]]
    [[ ! -e "$FAKE_PI_LOG" ]]
    assert_no_setup_state
}

@test "explicit Pi setup applies only with same-command consent in the isolated agent directory" {
    run setup_full --project "$PROJECT_DIR" --host pi --yes

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'action=install'* ]]
    [[ "$output" == *'dry_run=false'* ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$output" == *"agent_dir=$PI_AGENT_DIR"* ]]
    [[ "$output" == *'restart_needed=true'* ]]
    jq -e --arg root "$PROJECT_ROOT" \
        '.packages == [$root]' "$PI_AGENT_DIR/settings.json" >/dev/null
    [[ ! -e "$PROJECT_DIR/AGENTS.md" ]]
    [[ ! -e "$PROJECT_DIR/.codex/hooks.json" ]]
    [[ ! -e "$AWM_ROOT" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
}

@test "hostless setup routes canonical Pi disk state to live doctor instead of another install" {
    make_pi_cli
    run setup_full --project "$PROJECT_DIR" --host pi --yes
    [[ "$status" -eq 0 ]]

    run setup_discovery --project "$PROJECT_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Package: ready ($PI_AGENT_DIR)"* ]]
    [[ "$output" == *"mainframe pi doctor"* ]]
    [[ "$output" == *"/mainframe doctor"* ]]
    [[ "$output" != *"mainframe pi install --dry-run"* ]]
    [[ ! -e "$FAKE_PI_LOG" ]]
}

@test "Pi setup rejects project-hook runtime flags and ambiguous consent" {
    run setup_full --project "$PROJECT_DIR" --host pi --runtime auto --dry-run

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--runtime does not apply to Pi's user-package flow"* ]]
    assert_no_setup_state

    run setup_full --project "$PROJECT_DIR" --host pi --dry-run --yes

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"choose exactly one of --dry-run or --yes for Pi"* ]]
    assert_no_setup_state
}

@test "bash and zsh setup completion expose the bounded host choices" {
    local expected
    expected="$(printf '%s\n' claude-code codex copilot gemini pi | LC_ALL=C sort)"

    run bash -c '
        source "$1"
        COMP_WORDS=(mainframe setup --host "")
        COMP_CWORD=3
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$expected" ]]

    if command -v zsh >/dev/null 2>&1; then
        run zsh -f -c '
            compdef() { :; }
            source "$1"
            _arguments() { printf "%s\n" "$@"; }
            words=(mainframe setup "")
            CURRENT=3
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh"
        [[ "$status" -eq 0 ]]
    [[ "$output" == *"--host[host or Pi package flow to configure]:host:(codex claude-code copilot gemini pi)"* ]]
    [[ "$output" == *"--project[project directory]:project directory:_directories"* ]]
        [[ "$output" == *"--proof[run the hostless zero-residue first-run mechanism proof]"* ]]
    fi
}

@test "setup reports no detections and remains read-only even with --yes" {
    local host
    run setup_discovery --project "$PROJECT_DIR" --yes

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Mode: discovery only (strictly read-only)"* ]]
    [[ "$output" == *"Shell discovery"*"bash"*"zsh"* ]]
    [[ "$output" == *"Detected candidates: none"* ]]
    [[ "$output" == *"No supported host CLI or project marker was detected."* ]]
    [[ "$output" == *"mainframe host status codex"* ]]
    [[ "$output" == *"mainframe host status claude-code"* ]]
    [[ "$output" == *"mainframe host status copilot"* ]]
    [[ "$output" == *"mainframe host status gemini"* ]]
    for host in codex claude-code copilot; do
        [[ "$output" == *"mainframe host install $host --download --dry-run"* ]]
        [[ "$output" == *"mainframe host install $host --download --yes"* ]]
        [[ "$output" == *"mainframe host install $host --package-dir /absolute/path/to/pinned-tarballs --dry-run"* ]]
        [[ "$output" == *"mainframe host install $host --package-dir /absolute/path/to/pinned-tarballs --yes"* ]]
        [[ "$output" == *"--host $host --runtime managed --dry-run"* ]]
        [[ "$output" == *"--host $host --runtime managed --yes"* ]]
    done
    [[ "$output" != *"mainframe host install gemini"* ]]
    [[ "$output" != *"npm install --global"* ]]
    assert_no_setup_state
    [[ -z "$(find "$PROJECT_DIR" -mindepth 1 -print -quit)" ]]
}

@test "setup reports one detected CLI without auto-selecting it" {
    make_host_cli codex

    run setup_discovery --project "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"codex"*"certified"* ]]
    [[ "$output" == *"CLI: $CLI_DIR/codex"* ]]
    [[ "$output" == *"Compatibility: pinned version 0.146.0; pinned-native:"* ]]
    [[ "$output" == *"Detected candidates: codex"* ]]
    [[ "$output" == *"No host was selected. Discovery never auto-selects"* ]]
    [[ "$output" == *"--host codex --runtime auto --dry-run"* ]]
    [[ "$output" != *"--host gemini --runtime auto --dry-run"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
    assert_no_setup_state
}

@test "setup detects an incompatible same-named host and recommends only managed recovery" {
    make_host_cli codex
    printf '%s\n' '# tampered after manifest pin' >> "$CLI_DIR/codex"

    run setup_discovery --project "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"codex"*"incompatible"* ]]
    [[ "$output" == *"launcher bytes are not certified for version 0.146.0"* ]]
    [[ "$output" == *"# codex runtime is unavailable under policy auto"* ]]
    [[ "$output" == *"mainframe host status codex"* ]]
    [[ "$output" == *"mainframe host install codex --download --dry-run"* ]]
    [[ "$output" == *"--host codex --runtime managed --dry-run"* ]]
    [[ "$output" != *"npm install --global"* ]]
    [[ "$output" != *"--host codex --runtime auto --dry-run"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
    assert_no_setup_state
}

@test "explicit setup for missing Codex fails with actionable managed recovery and no state" {
    run setup_discovery --project "$PROJECT_DIR" --host codex --dry-run

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"onboarding was not changed"* ]]
    [[ "$output" == *"mainframe host status codex --runtime auto"* ]]
    [[ "$output" == *"mainframe host install codex --download --dry-run"* ]]
    [[ "$output" == *"mainframe host install codex --download --yes"* ]]
    [[ "$output" == *"mainframe host install codex --package-dir /absolute/path/to/pinned-tarballs --dry-run"* ]]
    [[ "$output" == *"mainframe host install codex --package-dir /absolute/path/to/pinned-tarballs --yes"* ]]
    [[ "$output" == *"--host codex --runtime managed --dry-run"* ]]
    [[ "$output" == *"--host codex --runtime managed --yes"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
    assert_no_setup_state
    [[ -z "$(find "$PROJECT_DIR" -mindepth 1 -print -quit)" ]]
}

@test "setup combines multiple CLI and project-marker detections read-only" {
    make_host_cli codex
    mkdir -p "$PROJECT_DIR/.gemini"
    printf '%s\n' '{"user":"owned"}' > "$PROJECT_DIR/.gemini/settings.json"

    run setup_discovery --project "$PROJECT_DIR" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Detected candidates: codex gemini"* ]]
    [[ "$output" == *".gemini/settings.json"* ]]
    [[ "$output" == *"--host codex --runtime auto --dry-run"* ]]
    [[ "$output" == *"# gemini runtime is unavailable under policy auto"* ]]
    [[ "$output" == *"mainframe host status gemini"* ]]
    grep -Fxq '{"user":"owned"}' "$PROJECT_DIR/.gemini/settings.json"
    assert_no_setup_state
}

@test "setup rejects an invalid explicit host before any state change" {
    run setup_full --project "$PROJECT_DIR" --host all --yes

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported host: all"* ]]
    assert_no_setup_state
    [[ -z "$(find "$PROJECT_DIR" -mindepth 1 -print -quit)" ]]
}

@test "setup delegates explicit preview and consent to onboarding" {
    make_host_cli codex

    run setup_full --project "$PROJECT_DIR" --host codex --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME Onboarding Preflight"* ]]
    [[ "$output" == *"Activation preview:"* ]]
    [[ "$output" == *"Dry run complete. No project files, AWM state, or audit records were changed."* ]]
    assert_no_setup_state

    run setup_full --project "$PROJECT_DIR" --host codex --yes

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Consent: --yes"* ]]
    [[ "$output" == *"MAINFRAME onboarding complete"* ]]
    [[ -f "$PROJECT_DIR/AGENTS.md" ]]
    [[ -f "$PROJECT_DIR/.codex/hooks.json" ]]
    [[ -d "$AWM_ROOT" ]]
    [[ -f "$MAINFRAME_AGENT_AUDIT_LOG" ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
}

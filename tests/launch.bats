#!/usr/bin/env bats
# Fail-closed daily launch contract for supported coding-agent hosts.

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    TEST_DIR="$(create_test_dir launch)"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    PROJECT_DIR="$TEST_DIR/project with spaces"
    CLI_DIR="$TEST_DIR/bin with spaces"
    RUNTIME_ROOT="$TEST_DIR/mainframe runtime"
    TEST_HOME="$TEST_DIR/home"
    BASE_PATH="$PATH"
    FAKE_HOST_LOG="$TEST_DIR/host.log"
    FAKE_HOST_PROBE_LOG="$TEST_DIR/host-probe.log"

    mkdir -p \
        "$PROJECT_DIR" \
        "$CLI_DIR" \
        "$TEST_HOME" \
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

    export PROJECT_ROOT BASH_BIN TEST_DIR PROJECT_DIR CLI_DIR RUNTIME_ROOT
    export TEST_HOME BASE_PATH FAKE_HOST_LOG FAKE_HOST_PROBE_LOG
    export HOME="$TEST_HOME"
    export XDG_STATE_HOME="$TEST_DIR/xdg-state"
    export AWM_ROOT="$TEST_HOME/.mainframe/awm"
    export MAINFRAME_ROOT="$RUNTIME_ROOT"
    export MAINFRAME_AGENT_AUDIT_LOG="$TEST_DIR/state/gateway.jsonl"
    export PATH="$CLI_DIR:$BASE_PATH"
    export SHELL=/bin/zsh
    unset MAINFRAME_AGENT_GATE_TIER FAKE_HOST_EXIT
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

mf() {
    "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" "$@"
}

make_launch_contract_fixture() {
    local fixture="$TEST_DIR/launch-contract"
    mkdir -p "$fixture/lib" "$fixture/config" "$fixture/skills/codex"
    cp "$PROJECT_ROOT/lib/activate.sh" "$fixture/lib/activate.sh"
    cp "$PROJECT_ROOT/lib/launch.sh" "$fixture/lib/launch.sh"
    cp "$PROJECT_ROOT/config/host-capabilities.json" \
        "$fixture/config/host-capabilities.json"
    cp "$PROJECT_ROOT/skills/codex/AGENTS.md" \
        "$fixture/skills/codex/AGENTS.md"
    printf '%s\n' "$fixture"
}

launch_contract_query() {
    local fixture="$1" host="$2"
    local jq_bin
    jq_bin="$(command -v jq)"
    "$BASH_BIN" -c '
        MAINFRAME_ROOT="$1"
        source "$1/lib/activate.sh"
        source "$1/lib/launch.sh"
        _mainframe_launch_instruction_contract "$2" "$3"
    ' _ "$fixture" "$host" "$jq_bin"
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
        claude-code) manifest_host=claude ;;
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
    if [[ "$host" == gemini ]]; then
        # Gemini has no managed platform rows to infer from. Its synthetic
        # direct-native pin must use the exact advertised host tuple.
        platform_key="$("$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/host_runtime.sh"
            _mainframe_host_platform_id
        ' _ "$RUNTIME_ROOT")" || return 1
        [[ -n "$platform_key" ]] || return 1
    else
        platform_key="$(jq -er \
            --arg host "$manifest_host" \
            --arg prefix "$current_os-$current_arch" '
              [(.[$host].platforms // {}) | keys[] |
                select(. == $prefix or startswith($prefix + "-"))] |
              if length == 0 then $prefix else first end
            ' "$manifest")" || return 1
    fi
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

host_cli_name() {
    case "$1" in
        codex) printf 'codex\n' ;;
        claude-code) printf 'claude\n' ;;
        copilot) printf 'copilot\n' ;;
        gemini) printf 'gemini\n' ;;
        *) return 1 ;;
    esac
}

host_instruction_file() {
    local host="$1" project="$2"
    case "$host" in
        codex) printf '%s/AGENTS.md\n' "$project" ;;
        claude-code) printf '%s/CLAUDE.md\n' "$project" ;;
        copilot) printf '%s/.github/copilot-instructions.md\n' "$project" ;;
        gemini) printf '%s/GEMINI.md\n' "$project" ;;
        *) return 1 ;;
    esac
}

host_hook_file() {
    local host="$1" project="$2"
    case "$host" in
        codex) printf '%s/.codex/hooks.json\n' "$project" ;;
        claude-code) printf '%s/.claude/settings.json\n' "$project" ;;
        copilot) printf '%s/.github/hooks/mainframe.json\n' "$project" ;;
        gemini) printf '%s/.gemini/settings.json\n' "$project" ;;
        *) return 1 ;;
    esac
}

make_fake_host() {
    local host="$1" name file
    name="$(host_cli_name "$host")"
    file="$CLI_DIR/$name"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'if [[ "${1:-}" == "--version" || "${1:-}" == "--help" ]]; then'
        printf '%s\n' '  printf "%s\n" "$1" >> "${FAKE_HOST_PROBE_LOG:?}"'
        printf '%s\n' '  exit 97'
        printf '%s\n' 'fi'
        printf '%s\n' ': "${FAKE_HOST_LOG:?}"'
        printf '%s\n' '{'
        printf '%s\n' '  printf "cwd=%s\n" "$PWD"'
        printf '%s\n' '  printf "policy=%s\n" "${MAINFRAME_AGENT_GATE_TIER:-unset}"'
        printf '%s\n' '  printf "path=%s\n" "${PATH:-}"'
        printf '%s\n' '  printf "bash_env=%s\n" "${BASH_ENV-unset}"'
        printf '%s\n' '  printf "node_options=%s\n" "${NODE_OPTIONS-unset}"'
        printf '%s\n' '  printf "perl5opt=%s\n" "${PERL5OPT-unset}"'
        printf '%s\n' '  printf "ld_library_path=%s\n" "${LD_LIBRARY_PATH-unset}"'
        printf '%s\n' '  printf "dyld_library_path=%s\n" "${DYLD_LIBRARY_PATH-unset}"'
        printf '%s\n' '  printf "argc=%s\n" "$#"'
        printf '%s\n' '} > "$FAKE_HOST_LOG"'
        printf '%s\n' 'exit "${FAKE_HOST_EXIT:-0}"'
    } > "$file"
    chmod +x "$file"
    pin_fake_host "$host" "$file"
}

configure_ready_project() {
    local host="$1" project="$2"
    mkdir -p "$project"
    make_fake_host "$host"
    mf awm project ensure --project "$project" >/dev/null
    mf activate "$host" --project "$project" --enforce >/dev/null
}

tree_snapshot() {
    local root="$1"
    [[ -e "$root" ]] || return 0
    find "$root" -type f -exec cksum {} \; | LC_ALL=C sort
}

@test "launch help documents a narrow read-only fail-closed contract" {
    run mf launch --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe launch <host>"* ]]
    [[ "$output" == *"codex, claude-code, copilot, gemini"* ]]
    [[ "$output" == *"medium (default), high, critical"* ]]
    [[ "$output" == *"never onboards or repairs"* ]]
    [[ "$output" == *"Native host arguments are not accepted"* ]]
}

@test "bash and zsh completions expose launch hosts options and policies" {
    local expected
    expected="$(printf '%s\n' claude-code codex copilot gemini | LC_ALL=C sort)"

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe launch "")
        COMP_CWORD=2
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$expected" ]]

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe launch codex --policy "")
        COMP_CWORD=4
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$(printf '%s\n' critical high medium)" ]]

    if command -v zsh >/dev/null 2>&1; then
        run zsh -f -c '
            compdef() { :; }
            source "$1"
            _arguments() { printf "%s\n" "$@"; }
            words=(mainframe launch "")
            CURRENT=3
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"1:host:(codex claude-code copilot gemini)"* ]]
        [[ "$output" == *"--policy[gateway block tier]:policy:(medium high critical)"* ]]
    fi
}

@test "launch rejects unknown hosts options duplicate options and all native arguments" {
    run mf launch unknown
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported host: unknown"* ]]

    run mf launch codex --policy unsafe
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported policy tier"* ]]

    run mf launch codex --dry-run --dry-run
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--dry-run may be passed only once"* ]]

    run mf launch codex --project "$PROJECT_DIR" --project "$PROJECT_DIR"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--project requires exactly one directory"* ]]

    run mf launch codex prompt
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"native host arguments are not supported"* ]]

    run mf launch codex -- --ignore-user-config
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"native host arguments are not supported"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
}

@test "launch instruction contract resolves registry-owned version and destination" {
    local fixture
    fixture="$(make_launch_contract_fixture)"

    run launch_contract_query "$fixture" codex

    [[ "$status" -eq 0 ]]
    [[ "$output" == $'1\tAGENTS.md' ]]
}

@test "launch instruction contract rejects registry drift and unknown hosts" {
    local fixture
    fixture="$(make_launch_contract_fixture)"
    printf ' \n' >> "$fixture/config/host-capabilities.json"

    run launch_contract_query "$fixture" codex
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"invalid activation contract"* ]]

    fixture="$(make_launch_contract_fixture)"
    run launch_contract_query "$fixture" unknown-host
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unknown activation host destination"* ]]
}

@test "launch instruction contract rejects tampered destination and version" {
    local fixture
    fixture="$(make_launch_contract_fixture)"
    python3 - "$fixture/config/host-capabilities.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
registry = json.loads(path.read_text())
registry["hosts"]["codex"]["activation_instruction_file"] = "ESCAPED.md"
path.write_text(json.dumps(registry, indent=2) + "\n")
PY

    run launch_contract_query "$fixture" codex
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"invalid activation contract"* ]]

    fixture="$(make_launch_contract_fixture)"
    python3 - "$fixture/config/host-capabilities.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
registry = json.loads(path.read_text())
registry["activation_contract"]["block_version"] = 2
path.write_text(json.dumps(registry, indent=2) + "\n")
PY
    run launch_contract_query "$fixture" codex
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"invalid activation contract"* ]]
}

@test "launch rejects host bytes changed after pinning without version or help probes" {
    configure_ready_project codex "$PROJECT_DIR"
    printf '%s\n' '# tampered after manifest pin' >> "$CLI_DIR/codex"

    run mf launch codex --project "$PROJECT_DIR" --dry-run

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"launcher bytes are not certified for version 0.146.0"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
}

@test "launch rejects a PATH-first unreviewed Node shim without executing it" {
    local fake_bin="$TEST_DIR/unreviewed-node"
    local marker="$TEST_DIR/unreviewed-node-ran"
    mkdir -p "$fake_bin"
    printf '%s\n' '#!/bin/sh' "printf 'ran\\n' > '$marker'" 'exit 0' \
        >"$fake_bin/node"
    chmod +x "$fake_bin/node"

    run env PATH="$fake_bin:$BASE_PATH" \
        HOME="$HOME" MAINFRAME_ROOT="$RUNTIME_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/launch.sh"
            _mainframe_launch_node_executable "$2"
        ' _ "$RUNTIME_ROOT" "$PROJECT_DIR"

    [ "$status" -ne 0 ]
    [ ! -e "$marker" ]
}

@test "launch preflight PATH contains only fixed system tool directories" {
    run "$BASH_BIN" --noprofile --norc -p -c '
        source "$1/lib/launch.sh"
        _mainframe_launch_preflight_path
    ' _ "$RUNTIME_ROOT"

    [[ "$status" -eq 0 ]]
    [[ "$output" == "/usr/bin:/bin:/usr/sbin:/sbin" ]]
}

@test "package-tree authentication ignores Node preload and coverage environment" {
    local node_candidate preload marker coverage tree_root
    node_candidate="$(type -P node 2>/dev/null || true)"
    [[ -n "$node_candidate" ]] || skip "Node.js is unavailable"
    preload="$TEST_DIR/preload.cjs"
    marker="$TEST_DIR/node-preload-ran"
    coverage="$TEST_DIR/node-coverage"
    tree_root="$TEST_DIR/package-tree"
    mkdir -p "$tree_root"
    printf '%s\n' \
        "require('fs').writeFileSync(process.env.MAINFRAME_TEST_NODE_MARKER, 'ran\\n')" \
        > "$preload"
    printf '%s\n' 'package bytes' > "$tree_root/file.txt"

    run env \
        NODE_OPTIONS="--require=$preload" \
        NODE_V8_COVERAGE="$coverage" \
        MAINFRAME_TEST_NODE_MARKER="$marker" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/launch.sh"
            node="$(_mainframe_launch_resolve_executable "$2")" || exit 1
            hasher="$1/scripts/dev/native-host/hash-package-tree.mjs"
            _MAINFRAME_HOST_NODE="$node"
            _MAINFRAME_HOST_NODE_SHA="$(_mainframe_launch_sha256_file "$node")"
            _MAINFRAME_HOST_HASHER="$hasher"
            _MAINFRAME_HOST_HASHER_SHA="$(_mainframe_launch_sha256_file "$hasher")"
            _mainframe_launch_tree_sha256 "$3" "$node" "$4"
        ' _ "$RUNTIME_ROOT" "$node_candidate" "$PROJECT_DIR" "$tree_root"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    [[ ! -e "$marker" ]]
    [[ ! -e "$coverage" ]]
}

@test "launch AWM preflight ignores BASH_ENV" {
    local bash_env="$TEST_DIR/launch-bash-env.sh"
    local marker="$TEST_DIR/launch-bash-env-ran"
    configure_ready_project codex "$PROJECT_DIR"
    printf '%s\n' \
        "printf 'ran\\n' >> '$marker'" \
        > "$bash_env"

    run env BASH_ENV="$bash_env" PATH="$PATH" \
        "$BASH_BIN" --noprofile --norc -p "$RUNTIME_ROOT/bin/mainframe" \
        launch codex --project "$PROJECT_DIR" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry run complete"* ]]
    [[ ! -e "$marker" ]]
}

@test "launch scrubs passive Bash Node Perl and loader hooks before host exec" {
    local bash_env="$TEST_DIR/launch-environment-bash-hook.sh"
    local bash_marker="$TEST_DIR/launch-environment-bash-ran"
    local node_preload="$TEST_DIR/launch-environment-node-hook.cjs"
    local node_marker="$TEST_DIR/launch-environment-node-ran"
    local perl_lib="$PROJECT_DIR/perl-lib"
    local perl_marker="$TEST_DIR/launch-environment-perl-ran"

    configure_ready_project codex "$PROJECT_DIR"
    mkdir -p "$perl_lib"
    printf '%s\n' \
        "printf 'ran\\n' >> '$bash_marker'" \
        > "$bash_env"
    printf '%s\n' \
        "require('fs').writeFileSync(process.env.MAINFRAME_TEST_NODE_MARKER, 'ran\\n')" \
        > "$node_preload"
    printf '%s\n' \
        'package MainframeLaunchHook;' \
        'BEGIN {' \
        '  if (defined $ENV{MAINFRAME_TEST_PERL_MARKER}) {' \
        '    open my $fh, ">", $ENV{MAINFRAME_TEST_PERL_MARKER} or die $!;' \
        '    print {$fh} "ran\\n";' \
        '    close $fh;' \
        '  }' \
        '}' \
        '1;' \
        > "$perl_lib/MainframeLaunchHook.pm"

    # Stock macOS reaches Perl through /usr/bin/shasum. Prove the fixture is a
    # live startup hook before verifying that protected launch suppresses it.
    if [[ ! -x /usr/bin/sha256sum && ! -x /bin/sha256sum && \
          -x /usr/bin/shasum ]]; then
        MAINFRAME_TEST_PERL_MARKER="$perl_marker" \
            PERL5LIB="$perl_lib" PERL5OPT=-MMainframeLaunchHook \
            /usr/bin/shasum -a 256 "$perl_lib/MainframeLaunchHook.pm" >/dev/null
        [[ -e "$perl_marker" ]]
        rm -f "$perl_marker"
    fi

    run env \
        BASH_ENV="$bash_env" \
        NODE_OPTIONS="--require=$node_preload" \
        MAINFRAME_TEST_NODE_MARKER="$node_marker" \
        PERL5LIB="$perl_lib" \
        PERL5OPT=-MMainframeLaunchHook \
        MAINFRAME_TEST_PERL_MARKER="$perl_marker" \
        LD_LIBRARY_PATH="$PROJECT_DIR" \
        DYLD_LIBRARY_PATH="$PROJECT_DIR" \
        "$BASH_BIN" --noprofile --norc -p "$RUNTIME_ROOT/bin/mainframe" \
        launch codex --project "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ ! -e "$bash_marker" ]]
    [[ ! -e "$node_marker" ]]
    [[ ! -e "$perl_marker" ]]
    grep -Fxq 'bash_env=unset' "$FAKE_HOST_LOG"
    grep -Fxq 'node_options=unset' "$FAKE_HOST_LOG"
    grep -Fxq 'perl5opt=unset' "$FAKE_HOST_LOG"
    grep -Fxq 'ld_library_path=unset' "$FAKE_HOST_LOG"
    grep -Fxq 'dyld_library_path=unset' "$FAKE_HOST_LOG"
}

@test "launch does not load a project dynamic-loader constructor after entry" {
    local compiler loader_source loader_binary loader_marker platform loader_variable
    compiler="$(command -v cc 2>/dev/null || true)"
    [[ -n "$compiler" ]] || skip "a C compiler is required for the loader tripwire"
    loader_source="$TEST_DIR/launch-loader-hook.c"
    loader_marker="$TEST_DIR/launch-loader-hook-ran"
    platform="$(uname -s)"
    case "$platform" in
        Darwin)
            loader_binary="$PROJECT_DIR/launch-loader-hook.dylib"
            loader_variable=DYLD_INSERT_LIBRARIES
            ;;
        Linux)
            loader_binary="$PROJECT_DIR/launch-loader-hook.so"
            loader_variable=LD_PRELOAD
            ;;
        *) skip "dynamic-loader tripwire is supported on macOS and Linux" ;;
    esac

    configure_ready_project codex "$PROJECT_DIR"
    printf '%s\n' \
        '#include <stdio.h>' \
        '#include <stdlib.h>' \
        '__attribute__((constructor)) static void mainframe_loader_hook(void) {' \
        '  const char *path = getenv("MAINFRAME_TEST_LOADER_MARKER");' \
        '  if (path != NULL) {' \
        '    FILE *stream = fopen(path, "a");' \
        '    if (stream != NULL) { fputs("loaded\\n", stream); fclose(stream); }' \
        '  }' \
        '}' \
        > "$loader_source"
    if [[ "$platform" == Darwin ]]; then
        "$compiler" -dynamiclib -o "$loader_binary" "$loader_source" || \
            skip "could not compile the macOS loader tripwire"
    else
        "$compiler" -shared -fPIC -o "$loader_binary" "$loader_source" || \
            skip "could not compile the Linux loader tripwire"
    fi

    if [[ "$loader_variable" == DYLD_INSERT_LIBRARIES ]]; then
        MAINFRAME_TEST_LOADER_MARKER="$loader_marker" \
            DYLD_INSERT_LIBRARIES="$loader_binary" \
            "$BASH_BIN" --noprofile --norc -p -c ':'
    else
        MAINFRAME_TEST_LOADER_MARKER="$loader_marker" \
            LD_PRELOAD="$loader_binary" \
            "$BASH_BIN" --noprofile --norc -p -c ':'
    fi
    [[ -e "$loader_marker" ]] || skip "this platform did not load the constructor tripwire"
    rm -f "$loader_marker"

    run "$BASH_BIN" --noprofile --norc -p -c '
        export MAINFRAME_TEST_LOADER_MARKER="$1"
        if [[ "$2" == Darwin ]]; then
            export DYLD_INSERT_LIBRARIES="$3"
        else
            export LD_PRELOAD="$3"
        fi
        source "$4" launch codex --project "$5" --dry-run
    ' _ "$loader_marker" "$platform" "$loader_binary" \
        "$RUNTIME_ROOT/bin/mainframe" "$PROJECT_DIR"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry run complete"* ]]
    [[ ! -e "$loader_marker" ]]
}

@test "dry-run verifies every host without starting a provider or writing audit state" {
    local host project awm_before awm_after
    for host in codex claude-code copilot gemini; do
        project="$TEST_DIR/project-$host"
        configure_ready_project "$host" "$project"
        rm -f "$FAKE_HOST_LOG"
        awm_before="$(tree_snapshot "$AWM_ROOT")"

        run mf launch "$host" --project "$project" --dry-run

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"Managed instructions:  READY"* ]]
        [[ "$output" == *"AWM project session:   READY"* ]]
        [[ "$output" == *"Static protection:     READY"* ]]
        [[ "$output" == *"Host artifact identity: READY (pinned version"* ]]
        [[ "$output" == *"Host runtime load:     UNVERIFIED"* ]]
        [[ "$output" == *"No host was started"* ]]
        [[ ! -e "$FAKE_HOST_LOG" ]]
        [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
        [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
        awm_after="$(tree_snapshot "$AWM_ROOT")"
        [[ "$awm_after" == "$awm_before" ]]
    done
}

@test "launch execs the absolute host in the canonical project with medium policy" {
    local physical_project
    configure_ready_project codex "$PROJECT_DIR"
    physical_project="$(cd "$PROJECT_DIR" && pwd -P)"
    export MAINFRAME_AGENT_GATE_TIER=critical
    export FAKE_HOST_EXIT=37

    run mf launch codex --project "$PROJECT_DIR"

    [[ "$status" -eq 37 ]]
    [[ "$output" == *"Policy tier:           medium"* ]]
    [[ "$output" == *"Host runtime load:     UNVERIFIED"* ]]
    [[ "$output" == *"does not claim runtime protection"* ]]
    grep -Fxq "cwd=$physical_project" "$FAKE_HOST_LOG"
    grep -Fxq 'policy=medium' "$FAKE_HOST_LOG"
    grep -Fxq "path=$PATH" "$FAKE_HOST_LOG"
    grep -Fxq 'argc=0' "$FAKE_HOST_LOG"
}

@test "launch applies only an explicitly selected narrower policy" {
    configure_ready_project gemini "$PROJECT_DIR"

    run mf launch gemini --project "$PROJECT_DIR" --policy high

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Policy tier:           high"* ]]
    grep -Fxq 'policy=high' "$FAKE_HOST_LOG"
}

@test "launch refuses a missing or duplicated instruction block before host exec" {
    local instruction awm_before
    configure_ready_project codex "$PROJECT_DIR"
    instruction="$(host_instruction_file codex "$PROJECT_DIR")"
    awm_before="$(tree_snapshot "$AWM_ROOT")"
    rm -f "$instruction"

    run mf launch codex --project "$PROJECT_DIR"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"managed instruction block is missing, duplicated, stale, or unsafe"* ]]
    [[ "$output" == *"mainframe setup --project"*"project\\ with\\ spaces"*"--dry-run"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ "$(tree_snapshot "$AWM_ROOT")" == "$awm_before" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]

    mf activate codex --project "$PROJECT_DIR" >/dev/null
    printf '%s\n' '<!-- MAINFRAME:BEGIN v1 -->' >> "$instruction"
    run mf launch codex --project "$PROJECT_DIR"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"duplicated"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
}

@test "launch refuses missing AWM mapping and never creates it" {
    make_fake_host claude-code
    mf activate claude-code --project "$PROJECT_DIR" --enforce >/dev/null
    [[ ! -e "$AWM_ROOT" ]]

    run mf launch claude-code --project "$PROJECT_DIR"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"no valid private AWM mapping"* ]]
    [[ ! -e "$AWM_ROOT" ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
}

@test "launch refuses malformed static protection before host exec" {
    local hook
    configure_ready_project copilot "$PROJECT_DIR"
    hook="$(host_hook_file copilot "$PROJECT_DIR")"
    printf '%s\n' '{not-json' > "$hook"

    run mf launch copilot --project "$PROJECT_DIR"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Static readiness: NOT READY"* ]]
    [[ "$output" == *"static protection is not ready for copilot"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
}

@test "launch does not accept a shell function in place of an executable host" {
    configure_ready_project codex "$PROJECT_DIR"
    rm -f "$CLI_DIR/codex"

    run env PATH="$CLI_DIR:/usr/bin:/bin" \
        FAKE_HOST_LOG="$FAKE_HOST_LOG" \
        "$BASH_BIN" -c '
            codex() { printf "function-ran\n" > "$FAKE_HOST_LOG"; }
            export -f codex
            exec "$1" "$2" launch codex --project "$3"
        ' _ "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" "$PROJECT_DIR"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"system codex CLI is absent"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
}

@test "launch refuses a repo-controlled host executable beneath the project" {
    local project_bin
    configure_ready_project codex "$PROJECT_DIR"
    project_bin="$PROJECT_DIR/repo-bin"
    mkdir -p "$project_bin"
    mv "$CLI_DIR/codex" "$project_bin/codex"

    run env PATH="$project_bin:$CLI_DIR:$BASE_PATH" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" \
        launch codex --project "$PROJECT_DIR"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"system codex CLI is unsafe"* ]]
    [[ "$output" == *"project-controlled host executable"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]

    ln -s "$project_bin/codex" "$CLI_DIR/codex"
    run env PATH="$CLI_DIR:$BASE_PATH" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" \
        launch codex --project "$PROJECT_DIR"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"system codex CLI is unsafe"* ]]
    [[ "$output" == *"project-controlled host executable"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$MAINFRAME_AGENT_AUDIT_LOG" ]]
}

@test "launch rejects symlinked instructions and ignores a shadow MAINFRAME on PATH" {
    local instruction outside fake_path
    configure_ready_project gemini "$PROJECT_DIR"
    instruction="$(host_instruction_file gemini "$PROJECT_DIR")"
    outside="$TEST_DIR/outside-instructions"
    cp "$instruction" "$outside"
    rm -f "$instruction"
    ln -s "$outside" "$instruction"

    run mf launch gemini --project "$PROJECT_DIR"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"managed instruction block is missing, duplicated, stale, or unsafe"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]

    rm -f "$instruction"
    cp "$outside" "$instruction"
    fake_path="$TEST_DIR/fake-path"
    mkdir -p "$fake_path"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_path/mainframe"
    chmod +x "$fake_path/mainframe"

    run env PATH="$fake_path:$PATH" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" \
        launch gemini --project "$PROJECT_DIR" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Host artifact identity: READY (pinned version"* ]]
    [[ "$output" == *"Static protection:     READY"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
    [[ ! -e "$FAKE_HOST_PROBE_LOG" ]]
}

@test "launch preflight never executes PATH-first internal helper shims" {
    local fake_helpers="$TEST_DIR/internal-helper-shims"
    local marker="$TEST_DIR/internal-helper-ran"
    local helper real

    configure_ready_project codex "$PROJECT_DIR"
    mv "$CLI_DIR/codex" "$CLI_DIR/codex.real"
    ln -s codex.real "$CLI_DIR/codex"
    mkdir -p "$fake_helpers"
    for helper in \
        awk basename cat date dirname find grep head mkdir mktemp od readlink \
        sed sha256sum shasum openssl sort stat tail tr wc; do
        real="$(PATH="$BASE_PATH" type -P "$helper" 2>/dev/null || true)"
        [[ -n "$real" && "$real" == /* ]] || continue
        printf '%s\n' \
            '#!/bin/sh' \
            "printf '%s\\n' '$helper' >> '$marker'" \
            "exec '$real' \"\$@\"" > "$fake_helpers/$helper"
        chmod +x "$fake_helpers/$helper"
    done

    run env PATH="$fake_helpers:$CLI_DIR:$BASE_PATH" \
        HOME="$HOME" MAINFRAME_ROOT="$RUNTIME_ROOT" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" \
        launch codex --project "$PROJECT_DIR" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry run complete"* ]]
    if [[ -e "$marker" ]]; then
        printf 'PATH-first helper shims executed: %s\n' \
            "$(LC_ALL=C sort -u "$marker" | tr '\n' ' ')" >&2
    fi
    [[ ! -e "$marker" ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
}

@test "setup and onboard hand off a ready project to the exact launch command" {
    configure_ready_project codex "$PROJECT_DIR"

    run mf setup --project "$PROJECT_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe launch codex --project"* ]]
    [[ "$output" != *"--host codex --dry-run"* ]]

    run mf onboard --host codex --project "$PROJECT_DIR" --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe launch codex --project"* ]]
    [[ "$output" == *"Host runtime load:     UNVERIFIED"* ]]
    [[ ! -e "$FAKE_HOST_LOG" ]]
}

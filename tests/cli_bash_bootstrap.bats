#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    MAINFRAME_BIN="$PROJECT_ROOT/bin/mainframe"
    ROOT_LAUNCHER="$PROJECT_ROOT/mainframe"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-cli-bash.XXXXXX")"
    MODERN_BASH="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$MODERN_BASH" ]] || MODERN_BASH="$(command -v bash)"
    "$MODERN_BASH" -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ))
    ' || skip "Bash 4.4+ is unavailable"
}

@test "root compatibility launcher never executes an ambient PATH Bash" {
    local fake_bin="$TEST_DIR/ambient-root-bin"
    local marker="$TEST_DIR/ambient-root-bash-ran"
    mkdir -p "$fake_bin" "$TEST_DIR/home"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf 'ambient bash executed\\n' > '$marker'" \
        'exit 97' > "$fake_bin/bash"
    chmod +x "$fake_bin/bash"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        "$ROOT_LAUNCHER" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v"* ]]
    [[ ! -e "$marker" ]]
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

make_delegation_fixture() {
    FIXTURE_ROOT="$TEST_DIR/fixture-mainframe"
    FIXTURE_BIN="$FIXTURE_ROOT/bin/mainframe"
    AMBIENT_BIN="$TEST_DIR/ambient-bin"
    AMBIENT_BASH_MARKER="$TEST_DIR/ambient-bash-ran"

    mkdir -p \
        "$FIXTURE_ROOT/bin" \
        "$FIXTURE_ROOT/lib" \
        "$FIXTURE_ROOT/scripts/dev" \
        "$FIXTURE_ROOT/benchmarks" \
        "$FIXTURE_ROOT/tests/bats/bin" \
        "$FIXTURE_ROOT/tests/unit" \
        "$FIXTURE_ROOT/tests/integration" \
        "$AMBIENT_BIN" \
        "$TEST_DIR/home"
    FIXTURE_ROOT="$(cd "$FIXTURE_ROOT" && pwd -P)"
    FIXTURE_BIN="$FIXTURE_ROOT/bin/mainframe"
    cp "$MAINFRAME_BIN" "$FIXTURE_BIN"
    chmod +x "$FIXTURE_BIN"

    # These command paths do not need the full library surface; an isolated
    # fixture lets the test observe exactly which interpreter enters each
    # delegated script without changing any release-owned operation.
    printf '%s\n' '# Delegation test fixture.' > "$FIXTURE_ROOT/lib/common.sh"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "ambient bash executed\\n" > "${MAINFRAME_AMBIENT_BASH_MARKER:?}"' \
        'exit 97' > "$AMBIENT_BIN/bash"
    chmod +x "$AMBIENT_BIN/bash"
}

@test "CLI can re-exec an explicitly selected supported Bash" {
    run env -i \
        HOME="$TEST_DIR/home" \
        USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/bash "$MAINFRAME_BIN" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v"* ]]
}

@test "configured MAINFRAME_BASH remains the exact runtime under another supported Bash" {
    local active_version configured_version candidate
    active_version="$($MODERN_BASH --noprofile --norc -p -c 'printf "%s" "$BASH_VERSION"')"

    # Use a second supported fixed Bash when this host supplies one. This is
    # the Linux zsh-launch shape: the shebang may already be modern, but the
    # isolated profile's reviewed MAINFRAME_BASH still owns runtime identity.
    local configured=""
    for candidate in /usr/local/bin/bash /opt/homebrew/bin/bash \
            /home/linuxbrew/.linuxbrew/bin/bash /opt/local/bin/bash \
            /usr/bin/bash /bin/bash; do
        [[ -x "$candidate" ]] || continue
        [[ "$candidate" -ef "$MODERN_BASH" ]] && continue
        "$candidate" --noprofile --norc -p -c '
            (( BASH_VERSINFO[0] > 4 )) ||
            (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ))
        ' >/dev/null 2>&1 || continue
        configured="$candidate"
        break
    done
    [[ -n "$configured" ]] || \
        skip "a second supported fixed Bash is unavailable"
    configured_version="$($configured --noprofile --norc -p -c 'printf "%s" "$BASH_VERSION"')"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" MAINFRAME_BASH="$configured" \
        "$MODERN_BASH" --noprofile --norc -p "$MAINFRAME_BIN" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Bash version:    $configured_version"* ]]
    if [[ "$active_version" != "$configured_version" ]]; then
        [[ "$output" != *"Bash version:    $active_version"* ]]
    fi
}

@test "a supported active Bash cannot ignore an unsupported configured Bash" {
    /bin/bash --noprofile --norc -p -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ))
    ' >/dev/null 2>&1 && skip "/bin/bash is already supported on this host"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" MAINFRAME_BASH=/bin/bash \
        "$MODERN_BASH" --noprofile --norc -p "$MAINFRAME_BIN" version

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"MAINFRAME_BASH must resolve to a supported reviewed Bash 4.4+ installation."* ]]
    [[ "$output" != *"MAINFRAME v"* ]]
}

@test "bootstrap version probe rejects Bash 4.3 and accepts Bash 4.4" {
    local candidate="$TEST_DIR/versioned-bash"
    local probe="$TEST_DIR/probe-version.sh"
    sed -n '/^_mainframe_cli_bash_supported()/,/^}/p' "$MAINFRAME_BIN" > "$probe"
    printf '%s\n' '_mainframe_cli_bash_supported "$1"' >> "$probe"
    printf '%s\n' \
        '#!/bin/sh' \
        '[ "$#" -eq 5 ] || exit 99' \
        '[ "$1" = "--noprofile" ] || exit 99' \
        '[ "$2" = "--norc" ] || exit 99' \
        '[ "$3" = "-p" ] || exit 99' \
        '[ "$4" = "-c" ] || exit 99' \
        'case "$5" in' \
        '  *"BASH_VERSINFO[0] > 4"*"BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4"*) ;;' \
        '  *) exit 99 ;;' \
        'esac' \
        'if [ "${FAKE_BASH_MAJOR:?}" -gt 4 ] || {' \
        '   [ "$FAKE_BASH_MAJOR" -eq 4 ] && [ "${FAKE_BASH_MINOR:?}" -ge 4 ];' \
        '}; then exit 0; else exit 1; fi' \
        > "$candidate"
    chmod +x "$candidate"

    run env -i PATH="/usr/bin:/bin" FAKE_BASH_MAJOR=4 FAKE_BASH_MINOR=3 \
        "$MODERN_BASH" --noprofile --norc -p "$probe" "$candidate"
    [[ "$status" -eq 1 ]]

    run env -i PATH="/usr/bin:/bin" FAKE_BASH_MAJOR=4 FAKE_BASH_MINOR=4 \
        "$MODERN_BASH" --noprofile --norc -p "$probe" "$candidate"
    [[ "$status" -eq 0 ]]
}

@test "old-interpreter bootstrap accepts the documented MacPorts Bash path" {
    local probe="$TEST_DIR/probe-macports-path.sh"
    sed -n '/^_mainframe_cli_bash_allowed_for_launch()/,/^}/p' \
        "$MAINFRAME_BIN" > "$probe"
    printf '%s\n' \
        '_mainframe_cli_bash_allowed_for_launch /opt/local/bin/bash' \
        >> "$probe"

    run /bin/bash "$probe"

    [[ "$status" -eq 0 ]]
}

@test "macOS Bash 3.2 bootstrap keeps delegated CLI help on the verified Bash" {
    [[ "$(uname -s)" == "Darwin" ]] || skip "macOS Bash 3.2 regression"
    [[ "$(/bin/bash -c 'printf "%s" "${BASH_VERSINFO[0]}"')" == "3" ]] || \
        skip "/bin/bash is not Apple Bash 3.2"
    local modern_version init_work
    # shellcheck disable=SC2016 # The selected child Bash expands BASH_VERSION.
    modern_version="$("$MODERN_BASH" --noprofile --norc -p -c 'printf "%s" "$BASH_VERSION"')"
    init_work="$TEST_DIR/init-work"
    mkdir -p "$TEST_DIR/home" "$init_work"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/bash "$MAINFRAME_BIN" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Bash version:    $modern_version"* ]]

    # shellcheck disable=SC2016 # The child /bin/bash expands positional parameters.
    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/bash -c 'cd "$1" && exec /bin/bash "$2" new --help' \
        _ "$init_work" "$MAINFRAME_BIN"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME Scaffolding Tool"* ]]
    [[ "$output" == *"Usage: mainframe-new <command> [options]"* ]]
    [[ "$output" != *"Unknown option"* ]]
    [[ "$output" != *"unbound variable"* ]]

    # shellcheck disable=SC2016 # The child /bin/bash expands positional parameters.
    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/bash -c 'cd "$1" && exec /bin/bash "$2" init --help' \
        _ "$init_work" "$MAINFRAME_BIN"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME Scaffolding Tool"* ]]
    [[ "$output" == *"Usage: mainframe-new <command> [options]"* ]]
    [[ "$output" != *"unbound variable"* ]]
    [[ -z "$(find "$init_work" -mindepth 1 -print -quit)" ]]

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/bash "$MAINFRAME_BIN" build --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME Build - Static Binary Builder"* ]]
    [[ "$output" == *"Usage: mainframe build <command> [options] <script>"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "verified-Bash delegation preserves ordinary new and init arguments" {
    local scaffold_work="$TEST_DIR/scaffold-work"
    local init_target="$TEST_DIR/init-target"
    mkdir -p "$TEST_DIR/home" "$scaffold_work" "$init_target"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/bash "$MAINFRAME_BIN" new tool delegated-tool \
        --yes --output "$scaffold_work"

    [[ "$status" -eq 0 ]]
    [[ -f "$scaffold_work/delegated_tool.sh" ]]

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/bash "$MAINFRAME_BIN" init "$init_target"

    [[ "$status" -eq 0 ]]
    [[ -f "$init_target/.mainframe" ]]
    [[ -f "$init_target/scripts/example.sh" ]]
}

@test "legacy Bash operations bypass an ambient PATH Bash and preserve arguments" {
    make_delegation_fixture
    local modern_version
    # shellcheck disable=SC2016 # The selected child Bash expands BASH_VERSION.
    modern_version="$("$MODERN_BASH" --noprofile --norc -p -c 'printf "%s" "$BASH_VERSION"')"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'case "$-" in *p*) ;; *) exit 98 ;; esac' \
        'printf "operation-bash=%s\\n" "$BASH_VERSION"' \
        'printf "operation-arg-1=<%s>\\n" "${1-}"' \
        'printf "operation-arg-2=<%s>\\n" "${2-}"' \
        > "$FIXTURE_ROOT/scripts/dev/probe.sh"
    chmod +x "$FIXTURE_ROOT/scripts/dev/probe.sh"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$AMBIENT_BIN:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_AMBIENT_BASH_MARKER="$AMBIENT_BASH_MARKER" \
        "$MODERN_BASH" "$FIXTURE_BIN" run probe alpha "two words"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"operation-bash=$modern_version"* ]]
    [[ "$output" == *"operation-arg-1=<alpha>"* ]]
    [[ "$output" == *"operation-arg-2=<two words>"* ]]
    [[ ! -e "$AMBIENT_BASH_MARKER" ]]
}

@test "benchmark delegation bypasses an ambient PATH Bash" {
    make_delegation_fixture
    local modern_version
    # shellcheck disable=SC2016 # The selected child Bash expands BASH_VERSION.
    modern_version="$("$MODERN_BASH" --noprofile --norc -p -c 'printf "%s" "$BASH_VERSION"')"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'case "$-" in *p*) ;; *) exit 98 ;; esac' \
        'printf "benchmark-bash=%s\\n" "$BASH_VERSION"' \
        > "$FIXTURE_ROOT/benchmarks/superpower_benchmarks.sh"
    chmod +x "$FIXTURE_ROOT/benchmarks/superpower_benchmarks.sh"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$AMBIENT_BIN:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_AMBIENT_BASH_MARKER="$AMBIENT_BASH_MARKER" \
        "$MODERN_BASH" "$FIXTURE_BIN" benchmark

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"benchmark-bash=$modern_version"* ]]
    [[ ! -e "$AMBIENT_BASH_MARKER" ]]
}

@test "test command keeps both Bats and test files on the verified Bash" {
    make_delegation_fixture
    local canonical_bash modern_version reported_test_shell
    # shellcheck disable=SC2016 # The selected child Bash expands BASH_VERSION.
    modern_version="$("$MODERN_BASH" --noprofile --norc -p -c 'printf "%s" "$BASH_VERSION"')"
    canonical_bash="$(cd "${MODERN_BASH%/*}" && pwd -P)/${MODERN_BASH##*/}"
    canonical_bash="$(/usr/bin/readlink "$canonical_bash" 2>/dev/null || printf '%s' "$canonical_bash")"
    [[ "$canonical_bash" == /* ]] || \
        canonical_bash="$(cd "${MODERN_BASH%/*}" && pwd -P)/$canonical_bash"
    canonical_bash="$(cd "${canonical_bash%/*}" && pwd -P)/${canonical_bash##*/}"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'case "$-" in *p*) ;; *) exit 98 ;; esac' \
        'printf "runner-bash=%s\\n" "$BASH_VERSION"' \
        'printf "test-shell=%s\\n" "${BATS_TEST_SHELL-}"' \
        'printf "runner-arg-1=<%s>\\n" "${1-}"' \
        'printf "runner-arg-2=<%s>\\n" "${2-}"' \
        > "$FIXTURE_ROOT/tests/bats/bin/bats"
    chmod +x "$FIXTURE_ROOT/tests/bats/bin/bats"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$AMBIENT_BIN:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_AMBIENT_BASH_MARKER="$AMBIENT_BASH_MARKER" \
        "$MODERN_BASH" "$FIXTURE_BIN" test

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"runner-bash=$modern_version"* ]]
    reported_test_shell="$(printf '%s\n' "$output" | sed -n 's/^test-shell=//p')"
    [[ -x "$reported_test_shell" ]]
    [[ "$reported_test_shell" -ef "$canonical_bash" ]]
    [[ "$output" == *"runner-arg-1=<$FIXTURE_ROOT/tests/unit/>"* ]]
    [[ "$output" == *"runner-arg-2=<$FIXTURE_ROOT/tests/integration/>"* ]]
    [[ ! -e "$AMBIENT_BASH_MARKER" ]]
}

@test "doctor tolerates a minimal agent environment without user variables" {
    command -v jq >/dev/null 2>&1 || skip "jq is required"
    mkdir -p "$TEST_DIR/home"

    run env -i \
        HOME="$TEST_DIR/home" \
        PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        MAINFRAME_BASH="$MODERN_BASH" \
        "$MODERN_BASH" "$MAINFRAME_BIN" doctor

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Status: All checks passed!"* ]]
}

@test "macOS zsh login path ordering cannot strand the CLI on Apple Bash" {
    [[ "$(uname -s)" == "Darwin" ]] || skip "macOS-specific login-shell regression"
    [[ -x /bin/zsh ]] || skip "zsh is unavailable"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL=/bin/zsh TERM=dumb \
        PATH="/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        /bin/zsh -lic '"$1" version' _ "$MAINFRAME_BIN"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v"* ]]
}

@test "macOS launch bootstrap rejects a project-controlled Bash override without execution" {
    [[ "$(uname -s)" == "Darwin" ]] || skip "macOS Bash 3.2 regression"
    local trusted_bash=""
    local fake_bin="$TEST_DIR/project-bin"
    local marker="$TEST_DIR/project-bash-ran"
    if [[ -x /opt/homebrew/bin/bash ]]; then
        trusted_bash=/opt/homebrew/bin/bash
    elif [[ -x /usr/local/bin/bash ]]; then
        trusted_bash=/usr/local/bin/bash
    else
        skip "a fixed package-manager Bash is unavailable"
    fi
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf 'ran\\n' > '$marker'" \
        "exec '$trusted_bash' \"\$@\"" > "$fake_bin/bash"
    chmod +x "$fake_bin/bash"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH="$fake_bin/bash" \
        /bin/bash "$MAINFRAME_BIN" launch --help

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"supported reviewed Bash 4.4+ installation"* ]]
    [[ ! -e "$marker" ]]
}

@test "CLI rejects a bare Bash override without executing a PATH marker" {
    local fake_bin="$TEST_DIR/bare-override-bin"
    local marker="$TEST_DIR/bare-override-ran"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf 'ran\n' > '$marker'" \
        'exit 97' > "$fake_bin/bash"
    chmod +x "$fake_bin/bash"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH=bash \
        /bin/bash "$MAINFRAME_BIN" version

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"must be an absolute reviewed Bash path"* ]]
    [[ ! -e "$marker" ]]
}

@test "unprivileged Apple Bash entry removes imported functions before path resolution" {
    [[ "$(uname -s)" == "Darwin" ]] || skip "macOS Bash 3.2 regression"
    local marker="$TEST_DIR/imported-function-ran"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_IMPORTED_FUNCTION_MARKER="$marker" \
        'BASH_FUNC_cd%%=() { printf "ran\n" > "$MAINFRAME_IMPORTED_FUNCTION_MARKER"; builtin cd "$@"; }' \
        /bin/bash "$MAINFRAME_BIN" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v"* ]]
    [[ ! -e "$marker" ]]
}

@test "explicit Bash CLI protects re-entry before imported set or builtin functions" {
    local marker="$TEST_DIR/imported-primitive-function-ran"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH=/usr/bin:/bin MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_TEST_MARKER="$marker" \
        'BASH_FUNC_set%%=() { printf "set executed\n" >> "${MAINFRAME_TEST_MARKER:?}"; }' \
        'BASH_FUNC_builtin%%=() { printf "builtin executed\n" >> "${MAINFRAME_TEST_MARKER:?}"; }' \
        /bin/bash "$MAINFRAME_BIN" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v"* ]]
    [[ ! -e "$marker" ]]
}

@test "ordinary CLI initialization never executes a caller PATH tr shim" {
    local fake_bin="$TEST_DIR/ordinary-tr-bin"
    local marker="$TEST_DIR/ordinary-tr-ran"
    mkdir -p "$fake_bin" "$TEST_DIR/home"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf 'ran\\n' > '$marker'" \
        'exit 97' > "$fake_bin/tr"
    chmod +x "$fake_bin/tr"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        "$MODERN_BASH" "$MAINFRAME_BIN" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v"* ]]
    [[ ! -e "$marker" ]]
}

@test "gateway allowlist includes the documented MacPorts jq path" {
    local gateway_case="$TEST_DIR/gateway-case.txt"
    sed -n '/case "\$_mainframe_cli_jq_source" in/,/^[[:space:]]*esac/p' \
        "$MAINFRAME_BIN" > "$gateway_case"

    run "$MODERN_BASH" --noprofile --norc -p -c '
      _mainframe_cli_jq_source=/opt/local/bin/jq
      source "$1"
    ' _ "$gateway_case"

    [[ "$status" -eq 0 ]]
}

@test "ordinary CLI bootstrap never probes an ambient PATH Bash" {
    [[ "$(uname -s)" == "Darwin" ]] || skip "old-system-Bash bootstrap regression"
    local fake_bin="$TEST_DIR/ordinary-path-bin"
    local marker="$TEST_DIR/ordinary-path-bash-ran"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf 'ran\n' > '$marker'" \
        'exit 97' > "$fake_bin/bash"
    chmod +x "$fake_bin/bash"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH= \
        /bin/bash "$MAINFRAME_BIN" version

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v"* ]]
    [[ ! -e "$marker" ]]
}

@test "agent gateway rejects a project PATH jq without executing it" {
    local fake_bin="$TEST_DIR/gateway-jq-bin"
    local marker="$TEST_DIR/gateway-jq-ran"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        "printf 'ran\n' > '$marker'" \
        'exit 97' > "$fake_bin/jq"
    chmod +x "$fake_bin/jq"

    run env -i \
        HOME="$TEST_DIR/home" USER=mainframe-test LOGNAME=mainframe-test \
        PATH="$fake_bin:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        "$MODERN_BASH" "$MAINFRAME_BIN" agent-hook --format codex <<< '{}'

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"jq is outside a supported installation"* ]]
    [[ ! -e "$marker" ]]
}

@test "old-interpreter bootstrap happens before the gateway fast path" {
    command -v jq >/dev/null 2>&1 || skip "jq is required"
    local payload audit
    payload='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status --short"}}'
    audit="$TEST_DIR/gateway.jsonl"

    run env -i \
        HOME="$TEST_DIR/home" \
        USER=mainframe-test LOGNAME=mainframe-test \
        PATH="/usr/bin:/bin:$(dirname "$(command -v jq)")" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_AGENT_AUDIT_LOG="$audit" \
        /bin/bash -c 'printf "%s" "$1" | "$2" agent-hook --format codex' \
        _ "$payload" "$MAINFRAME_BIN"

    [[ "$status" -eq 0 ]]
    [[ "$output" == "{}" ]]
    jq -e '.details | index("host=codex") and index("decision=allow")' "$audit" >/dev/null
}

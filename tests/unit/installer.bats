#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    PROJECT_VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-installer-test.XXXXXX")"
    TEST_TMPDIR="$(cd "$TEST_TMPDIR" && pwd -P)"
    TEST_HOME="$TEST_TMPDIR/home"
    INSTALL_DIR="$TEST_HOME/.mainframe"
    BIN_DIR="$TEST_HOME/.local/bin"
    XDG_DIR="$TEST_HOME/.config"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    mkdir -p "$TEST_HOME"
}

teardown() {
    rm -rf -- "$TEST_TMPDIR"
}

create_fixture_repo() {
    local required
    FIXTURE_REPO="$TEST_TMPDIR/source"
    mkdir -p "$FIXTURE_REPO"

    cp -R "$PROJECT_ROOT/bin" "$FIXTURE_REPO/"
    cp -R "$PROJECT_ROOT/completions" "$FIXTURE_REPO/"
    cp -R "$PROJECT_ROOT/config" "$FIXTURE_REPO/"
    cp -R "$PROJECT_ROOT/hooks" "$FIXTURE_REPO/"
    cp -R "$PROJECT_ROOT/lib" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/FUNCTIONS.json" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/VERSION" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/get-mainframe.sh" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/install.sh" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/mainframe" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/uninstall.sh" "$FIXTURE_REPO/"

    # These installer cases exercise install, version, AWM help, and profile
    # loading. Assert that bounded fixture contract explicitly rather than
    # copying unrelated operation-script developer artifacts.
    for required in \
        bin/mainframe \
        completions/mainframe.bash completions/mainframe.zsh \
        config/function-export-policy.json \
        hooks/agent-gateway.sh hooks/dispatcher.sh \
        lib/common.sh lib/config.sh lib/args.sh lib/awm.sh \
        FUNCTIONS.json VERSION get-mainframe.sh install.sh mainframe uninstall.sh; do
        [[ -e "$FIXTURE_REPO/$required" ]] || {
            printf 'fixture is missing required installer path: %s\n' "$required" >&2
            return 1
        }
    done

    git -C "$FIXTURE_REPO" init -q -b main
    # Modern Git may detach automatic maintenance after a commit. Keep each
    # disposable fixture single-process so teardown cannot race a background
    # writer recreating objects beneath rm.
    git -C "$FIXTURE_REPO" config gc.auto 0
    git -C "$FIXTURE_REPO" config maintenance.auto false
    git -C "$FIXTURE_REPO" add .
    git -C "$FIXTURE_REPO" \
        -c user.name="MAINFRAME Tests" \
        -c user.email="tests@mainframe.invalid" \
        commit -qm "test fixture"
}

installer_env() {
    local argument requested_install_dir="$INSTALL_DIR" requested_parent requested_name
    local resolved_install_dir fixture_marker
    for argument in "$@"; do
        case "$argument" in
            MAINFRAME_INSTALL_DIR=*) requested_install_dir="${argument#*=}" ;;
        esac
    done
    [[ "$requested_install_dir" == /* ]] || requested_install_dir="$PWD/$requested_install_dir"
    requested_install_dir="${requested_install_dir%/}"
    [[ -n "$requested_install_dir" ]] || requested_install_dir=/
    requested_parent="${requested_install_dir%/*}"
    requested_name="${requested_install_dir##*/}"
    [[ -n "$requested_parent" ]] || requested_parent=/
    if [[ -d "$requested_install_dir" ]]; then
        resolved_install_dir="$(cd "$requested_install_dir" && pwd -P)"
    elif [[ -n "$requested_name" && -d "$requested_parent" ]]; then
        resolved_install_dir="$(cd "$requested_parent" && pwd -P)/$requested_name"
    else
        resolved_install_dir="$requested_install_dir"
    fi
    fixture_marker="$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$resolved_install_dir" > "$fixture_marker"
    chmod 600 "$fixture_marker"

    env \
        HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$XDG_DIR" \
        SHELL=/bin/bash \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        MAINFRAME_VERIFY_CHECKSUMS=0 \
        "$@" \
        --repo "file://$FIXTURE_REPO" --branch main --allow-unverified-source
}

make_traversal_probe() {
    TRAVERSAL_PROBE_BIN="$TEST_TMPDIR/traversal-probe-bin"
    TRAVERSAL_PROBE_MARKER="$TEST_TMPDIR/traversal-probe-ran"
    mkdir -p "$TRAVERSAL_PROBE_BIN"
    printf '%s\n' \
        '#!/bin/sh' \
        ': > "${MAINFRAME_TEST_TRAVERSAL_MARKER:?}"' \
        'exit 97' > "$TRAVERSAL_PROBE_BIN/find"
    chmod 755 "$TRAVERSAL_PROBE_BIN/find"
}

assert_unsafe_install_target_stops_at_preflight() {
    local target="$1"
    rm -f "$TRAVERSAL_PROBE_MARKER"

    run installer_env env \
        PATH="$TRAVERSAL_PROBE_BIN:/usr/bin:/bin" \
        MAINFRAME_TEST_TRAVERSAL_MARKER="$TRAVERSAL_PROBE_MARKER" \
        MAINFRAME_INSTALL_DIR="$target" \
        "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --force --no-shell --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Refusing unsafe MAINFRAME_INSTALL_DIR:"* ]]
    [[ "$output" != *"Scanning for required components"* ]]
    [[ "$output" != *"Deploying MAINFRAME"* ]]
    [[ ! -e "$TRAVERSAL_PROBE_MARKER" ]]
}

canonical_cli_commands() {
    awk '
        /^case "\$\{1:-help\}" in$/ {
            in_dispatch = 1
            next
        }
        in_dispatch && /^esac$/ {
            exit
        }
        in_dispatch && /^    [^[:space:]].*\)$/ {
            command_spec = $0
            sub(/^[[:space:]]+/, "", command_spec)
            sub(/\)$/, "", command_spec)
            if (command_spec == "*") {
                next
            }

            count = split(command_spec, names, "|")
            for (command_index = 1; command_index <= count; command_index++) {
                if (names[command_index] !~ /^-/) {
                    print names[command_index]
                }
            }
        }
    ' "$PROJECT_ROOT/bin/mainframe" | LC_ALL=C sort -u
}

bash_completion_commands() {
    bash -c '
        source "$1"
        COMP_WORDS=(mainframe "")
        COMP_CWORD=1
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u
}

zsh_completion_commands() {
    zsh -f -c '
        compdef() { :; }
        source "$1"
        _describe() {
            local specs_name="${@: -1}"
            local -a specs
            local spec
            specs=("${(@P)specs_name}")
            for spec in "${specs[@]}"; do
                print -r -- "${spec%%:*}"
            done
        }
        words=(mainframe "")
        _mainframe
    ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u
}

bash_completion_awm_commands() {
    bash -c '
        source "$1"
        COMP_WORDS=(mainframe awm "")
        COMP_CWORD=2
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u
}

zsh_completion_awm_commands() {
    zsh -f -c '
        compdef() { :; }
        source "$1"
        _describe() {
            local specs_name="${@: -1}"
            local -a specs
            local spec
            specs=("${(@P)specs_name}")
            for spec in "${specs[@]}"; do
                print -r -- "${spec%%:*}"
            done
        }
        words=(mainframe awm "")
        CURRENT=3
        _mainframe
    ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u
}

bash_completion_upgrade_options() {
    bash -c '
        source "$1"
        COMP_WORDS=(mainframe upgrade "")
        COMP_CWORD=2
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u
}

zsh_completion_upgrade_options() {
    zsh -f -c '
        compdef() { :; }
        source "$1"
        _arguments() {
            local spec
            for spec in "$@"; do
                case "$spec" in
                    \(-h\ --help\)*)
                        print -r -- -h
                        print -r -- --help
                        ;;
                    *--*)
                        spec="${spec%%\[*}"
                        spec="${spec##*--}"
                        print -r -- "--$spec"
                        ;;
                esac
            done
        }
        words=(mainframe upgrade "")
        CURRENT=3
        _mainframe
    ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u
}

bash_completion_awm_project_actions() {
    bash -c '
        source "$1"
        COMP_WORDS=(mainframe awm project "")
        COMP_CWORD=3
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u
}

zsh_completion_awm_project_actions() {
    zsh -f -c '
        compdef() { :; }
        source "$1"
        _describe() {
            local specs_name="${@: -1}"
            local -a specs
            local spec
            specs=("${(@P)specs_name}")
            for spec in "${specs[@]}"; do
                print -r -- "${spec%%:*}"
            done
        }
        words=(mainframe awm project "")
        CURRENT=4
        _mainframe
    ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u
}

bash_completion_awm_project_options() {
    local action="$1"
    bash -c '
        source "$1"
        COMP_WORDS=(mainframe awm project "$2" "")
        COMP_CWORD=4
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" "$action" | LC_ALL=C sort -u
}

zsh_completion_awm_project_options() {
    local action="$1"
    zsh -f -c '
        compdef() { :; }
        source "$1"
        _values() {
            shift
            local spec
            for spec in "$@"; do
                spec="${spec%%:*}"
                print -r -- "${spec%%\[*}"
            done
        }
        words=(mainframe awm project "$2" "")
        CURRENT=5
        _mainframe
    ' _ "$PROJECT_ROOT/completions/mainframe.zsh" "$action" | LC_ALL=C sort -u
}

bash_completion_awm_project_value() {
    local action="$1" option="$2"
    bash -c '
        source "$1"
        COMP_WORDS=(mainframe awm project "$2" "$3" "")
        COMP_CWORD=5
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" "$action" "$option" | LC_ALL=C sort -u
}

zsh_completion_awm_project_value() {
    local action="$1" option="$2"
    zsh -f -c '
        compdef() { :; }
        source "$1"
        _values() {
            shift
            printf "%s\n" "$@"
        }
        words=(mainframe awm project "$2" "$3" "")
        CURRENT=6
        _mainframe
    ' _ "$PROJECT_ROOT/completions/mainframe.zsh" "$action" "$option" | LC_ALL=C sort -u
}

@test "canonical installer gives a clean user the rich CLI and coherent shell setup" {
    local canonical_bash expected_root_line expected_bash_line expected_bin_line
    create_fixture_repo

    run installer_env "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-claude --no-ai-discovery
    [[ "$status" -eq 0 ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$INSTALL_DIR/bin/mainframe" ]]
    [[ -f "$TEST_HOME/.bashrc" ]]
    [[ -f "$TEST_HOME/.bash_profile" ]]
    grep -q '^# >>> MAINFRAME >>>$' "$TEST_HOME/.bashrc"
    printf -v expected_root_line 'export MAINFRAME_ROOT=%q' "$INSTALL_DIR"
    canonical_bash="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$BASH_BIN")"
    printf -v expected_bash_line 'export MAINFRAME_BASH=%q' "$canonical_bash"
    printf -v expected_bin_line '_MAINFRAME_SHELL_BIN_DIR=%q' "$BIN_DIR"
    grep -Fxq "$expected_root_line" "$TEST_HOME/.bashrc"
    grep -Fxq "$expected_bash_line" "$TEST_HOME/.bashrc"
    grep -Fxq "$expected_bin_line" "$TEST_HOME/.bashrc"
    grep -Fxq '# >>> MAINFRAME BASH LOGIN >>>' "$TEST_HOME/.bash_profile"
    grep -Fq '. "$HOME/.bashrc"' "$TEST_HOME/.bash_profile"

    run env HOME="$TEST_HOME" "$BIN_DIR/mainframe" version
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v$PROJECT_VERSION"* ]]
    [[ "$output" == *"MAINFRAME_ROOT:  $INSTALL_DIR"* ]]

    run env HOME="$TEST_HOME" AWM_ROOT="$TEST_TMPDIR/awm" "$BIN_DIR/mainframe" awm --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME AWM"* ]]
}

@test "environment-only source overrides cannot replace installer provenance" {
    local malicious_repo marker
    create_fixture_repo
    malicious_repo="$TEST_TMPDIR/malicious-source"
    marker="$TEST_TMPDIR/malicious-mainframe-executed"
    git clone -q --branch main "file://$FIXTURE_REPO" "$malicious_repo"
    printf '%s\n' \
        '#!/bin/sh' \
        ': > "${MAINFRAME_TEST_MALICIOUS_MARKER:?}"' \
        'exit 0' \
        > "$malicious_repo/bin/mainframe"
    chmod 755 "$malicious_repo/bin/mainframe"
    printf 'malicious-source\n' > "$malicious_repo/MALICIOUS_SOURCE"
    git -C "$malicious_repo" add bin/mainframe MALICIOUS_SOURCE
    git -C "$malicious_repo" \
        -c user.name="MAINFRAME Tests" \
        -c user.email="tests@mainframe.invalid" \
        commit -qm "malicious fixture"

    run env \
        HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$XDG_DIR" \
        SHELL=/bin/bash \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_REPO="file://$malicious_repo" \
        MAINFRAME_BRANCH=main \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        MAINFRAME_VERIFY_CHECKSUMS=0 \
        MAINFRAME_TEST_MALICIOUS_MARKER="$marker" \
        "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-shell --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"cannot select installation source"* ]]
    [[ "$output" == *"--allow-unverified-source"* ]]
    [[ ! -e "$marker" ]]
    [[ ! -e "$INSTALL_DIR/MALICIOUS_SOURCE" ]]
}

@test "explicit fixture source ignores ambient Git routing and execution hooks" {
    local malicious_repo marker helper_dir fixture_marker git_config
    create_fixture_repo
    malicious_repo="$TEST_TMPDIR/routed-malicious-source"
    marker="$TEST_TMPDIR/ambient-git-executed"
    helper_dir="$TEST_TMPDIR/malicious-git-exec-path"
    fixture_marker="$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    git_config="$TEST_HOME/.gitconfig"
    git clone -q --branch main "file://$FIXTURE_REPO" "$malicious_repo"
    printf '%s\n' \
        '#!/bin/sh' \
        ': > "${MAINFRAME_TEST_MALICIOUS_MARKER:?}"' \
        'exit 0' \
        > "$malicious_repo/bin/mainframe"
    chmod 755 "$malicious_repo/bin/mainframe"
    printf 'malicious-source\n' > "$malicious_repo/MALICIOUS_SOURCE"
    git -C "$malicious_repo" add bin/mainframe MALICIOUS_SOURCE
    git -C "$malicious_repo" \
        -c user.name="MAINFRAME Tests" \
        -c user.email="tests@mainframe.invalid" \
        commit -qm "routed malicious fixture"
    mkdir -p "$helper_dir"
    printf '%s\n' \
        '#!/bin/sh' \
        ': > "${MAINFRAME_TEST_MALICIOUS_MARKER:?}"' \
        'exit 97' \
        > "$helper_dir/git-upload-pack"
    chmod 755 "$helper_dir/git-upload-pack"
    printf '[url "%s"]\n\tinsteadOf = %s\n[core]\n\thooksPath = %s\n' \
        "file://$malicious_repo" "file://$FIXTURE_REPO" "$helper_dir" \
        > "$git_config"
    printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$INSTALL_DIR" > "$fixture_marker"
    chmod 600 "$fixture_marker"

    run env \
        HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$XDG_DIR" \
        SHELL=/bin/bash \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        MAINFRAME_VERIFY_CHECKSUMS=0 \
        MAINFRAME_TEST_MALICIOUS_MARKER="$marker" \
        GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0="url.file://$malicious_repo.insteadOf" \
        GIT_CONFIG_VALUE_0="file://$FIXTURE_REPO" \
        GIT_CONFIG_GLOBAL="$git_config" \
        GIT_EXEC_PATH="$helper_dir" \
        GIT_SSH="$helper_dir/git-upload-pack" \
        GIT_SSH_COMMAND="$helper_dir/git-upload-pack" \
        "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" \
        --repo "file://$FIXTURE_REPO" --branch main --allow-unverified-source \
        --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    [[ ! -e "$INSTALL_DIR/MALICIOUS_SOURCE" ]]
    [[ -x "$BIN_DIR/mainframe" ]]
}

@test "local explicit source requires the authenticated private fixture marker" {
    create_fixture_repo

    run env \
        HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$XDG_DIR" \
        SHELL=/bin/bash \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        MAINFRAME_VERIFY_CHECKSUMS=0 \
        "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" \
        --repo "file://$FIXTURE_REPO" --branch main --allow-unverified-source \
        --no-shell --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"authenticated private internal-test fixture"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$BIN_DIR/mainframe" ]]
}

@test "an already selected same-directory checkout needs no source override" {
    create_fixture_repo
    git clone -q --branch main "file://$FIXTURE_REPO" "$INSTALL_DIR"
    printf 'keep\n' > "$INSTALL_DIR/selected-checkout-sentinel"

    run env \
        HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$XDG_DIR" \
        SHELL=/bin/bash \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        MAINFRAME_VERIFY_CHECKSUMS=0 \
        "$BASH_BIN" --noprofile --norc -p \
        "$INSTALL_DIR/install.sh" --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ -f "$INSTALL_DIR/selected-checkout-sentinel" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
}

@test "canonical installer configures a fresh zsh with registered completions" {
    local canonical_bash expected_bash_line
    command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"
    create_fixture_repo
    INSTALL_DIR="$TEST_HOME/"'zsh-runtime-"$(touch${IFS}ZSH_ROOT_INJECTION)'
    BIN_DIR="$TEST_HOME/"'zsh-bin-`touch${IFS}ZSH_BIN_INJECTION`'

    run installer_env SHELL=/bin/zsh "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-claude --no-ai-discovery
    [[ "$status" -eq 0 ]]
    [[ ! -e "$TEST_HOME/ZSH_ROOT_INJECTION" ]]
    [[ ! -e "$TEST_HOME/ZSH_BIN_INJECTION" ]]
    [[ -f "$TEST_HOME/.zshrc" ]]
    grep -q '^# >>> MAINFRAME >>>$' "$TEST_HOME/.zshrc"
    canonical_bash="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$BASH_BIN")"
    printf -v expected_bash_line 'export MAINFRAME_BASH=%q' "$canonical_bash"
    grep -Fxq "$expected_bash_line" "$TEST_HOME/.zshrc"
    grep -Fq 'source "$MAINFRAME_ROOT/completions/mainframe.zsh"' "$TEST_HOME/.zshrc"

    run env HOME="$TEST_HOME" ZDOTDIR="$TEST_HOME" zsh -f -c '
        autoload -Uz compinit && compinit -i
        source "$HOME/.zshrc"
        [[ "${_comps[mainframe]-}" == "_mainframe" ]] || exit 70
        [[ "$(command -v mainframe)" == "$1" ]] || exit 71
        mainframe version
    ' _ "$BIN_DIR/mainframe"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v$PROJECT_VERSION"* ]]
    [[ ! -e "$TEST_HOME/ZSH_ROOT_INJECTION" ]]
    [[ ! -e "$TEST_HOME/ZSH_BIN_INJECTION" ]]
}

@test "bash and zsh top-level completions match the canonical CLI dispatch" {
    local canonical_commands
    local bash_commands
    canonical_commands="$(canonical_cli_commands)"
    bash_commands="$(bash_completion_commands)"

    [[ "$bash_commands" == "$canonical_commands" ]]

    if command -v zsh >/dev/null 2>&1; then
        local zsh_commands
        zsh_commands="$(zsh_completion_commands)"
        [[ "$zsh_commands" == "$canonical_commands" ]]
    fi
}

@test "bash and zsh complete the canonical AWM workflow commands" {
    local expected
    expected=$(printf '%s\n' \
        checkpoint context discovery doctor export find get handoff init inspect \
        project \
        list migrate progress resume status summary | LC_ALL=C sort -u)

    [[ "$(bash_completion_awm_commands)" == "$expected" ]]

    if command -v zsh >/dev/null 2>&1; then
        [[ "$(zsh_completion_awm_commands)" == "$expected" ]]
    fi
}

@test "bash and zsh complete transactional upgrade options" {
    local expected
    expected=$(printf '%s\n' \
        --allow-downgrade --confirm-agents-stopped --dry-run --help --journal \
        --recover --version -h | LC_ALL=C sort -u)

    [[ "$(bash_completion_upgrade_options)" == "$expected" ]]
    if command -v zsh >/dev/null 2>&1; then
        [[ "$(zsh_completion_upgrade_options)" == "$expected" ]]
    fi
}

@test "bash and zsh expose every project AWM action and its options" {
    local expected_actions action expected bash_options
    expected_actions=$(printf '%s\n' \
        checkpoint close context discovery ensure find get handoff progress session \
        status summary | LC_ALL=C sort -u)

    [[ "$(bash_completion_awm_project_actions)" == "$expected_actions" ]]
    if command -v zsh >/dev/null 2>&1; then
        [[ "$(zsh_completion_awm_project_actions)" == "$expected_actions" ]]
    fi

    while IFS='|' read -r action expected; do
        bash_options="$(bash_completion_awm_project_options "$action")"
        [[ "$bash_options" == "$(tr ' ' '\n' <<< "$expected" | LC_ALL=C sort -u)" ]]
        if command -v zsh >/dev/null 2>&1; then
            [[ "$(zsh_completion_awm_project_options "$action")" == "$bash_options" ]]
        fi
    done <<'EOF'
ensure|--discover-root --name --project
session|--discover-root --project
status|--discover-root --project
close|--discover-root --project
checkpoint|--discover-root --importance --project --tags --ttl
get|--discover-root --project
discovery|--discover-root --importance --project --tags
progress|--discover-root --project
summary|--discover-root --project --tokens
context|--discover-root --format --include --project --tokens
find|--discover-root --kind --limit --project
handoff|--discover-root --format --project --tokens prepare
EOF
}

@test "bash and zsh project AWM completion supplies bounded enum values" {
    local action option expected
    while IFS='|' read -r action option expected; do
        [[ "$(bash_completion_awm_project_value "$action" "$option")" == \
            "$(tr ' ' '\n' <<< "$expected" | LC_ALL=C sort -u)" ]]
        if command -v zsh >/dev/null 2>&1; then
            [[ "$(zsh_completion_awm_project_value "$action" "$option")" == \
                "$(tr ' ' '\n' <<< "$expected" | LC_ALL=C sort -u)" ]]
        fi
    done <<'EOF'
checkpoint|--importance|critical high low normal
context|--format|json prompt
find|--kind|checkpoint discovery log mixed
EOF
}

@test "bash and zsh project AWM completion treats --project as a directory" {
    mkdir -p "$TEST_TMPDIR/completion-project"

    run bash -c '
        source "$1"
        COMP_WORDS=(mainframe awm project ensure --project "$2/completion-p")
        COMP_CWORD=5
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" "$TEST_TMPDIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$TEST_TMPDIR/completion-project" ]]

    if command -v zsh >/dev/null 2>&1; then
        run zsh -f -c '
            compdef() { :; }
            source "$1"
            _directories() { print -r -- directory-completion-called; }
            words=(mainframe awm project ensure --project "$2/completion-p")
            CURRENT=6
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh" "$TEST_TMPDIR"
        [[ "$status" -eq 0 ]]
        [[ "$output" == "directory-completion-called" ]]
    fi
}

@test "running install.sh from a manually cloned target preserves the checkout" {
    create_fixture_repo
    git clone -q --branch main "file://$FIXTURE_REPO" "$INSTALL_DIR"
    printf 'keep\n' > "$INSTALL_DIR/manual-clone-sentinel"

    run installer_env "$BASH_BIN" --noprofile --norc -p \
        "$INSTALL_DIR/install.sh" --no-shell --no-claude --no-ai-discovery
    [[ "$status" -eq 0 ]]
    [[ -f "$INSTALL_DIR/manual-clone-sentinel" ]]
    [[ -x "$BIN_DIR/mainframe" ]]

    run env HOME="$TEST_HOME" "$INSTALL_DIR/mainframe" awm --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME AWM"* ]]
}

@test "installer refuses an unrelated non-empty target unless force is explicit" {
    local preserved_file
    create_fixture_repo
    mkdir -p "$INSTALL_DIR"
    printf 'do not delete\n' > "$INSTALL_DIR/user-file"

    run installer_env "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-shell --no-claude --no-ai-discovery
    [[ "$status" -ne 0 ]]
    [[ -f "$INSTALL_DIR/user-file" ]]
    [[ "$output" == *"is not a MAINFRAME checkout"* ]]

    run installer_env "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --force --no-shell --no-claude --no-ai-discovery
    [[ "$status" -eq 0 ]]
    [[ ! -e "$INSTALL_DIR/user-file" ]]
    preserved_file="$(find "$TEST_HOME" -type f -path '*/.mainframe.mainframe-quarantine.*/original/user-file' -print -quit)"
    [[ -n "$preserved_file" ]]
    grep -Fxq 'do not delete' "$preserved_file"
    [[ "$output" == *"Preserved existing target at"* ]]
    [[ -x "$BIN_DIR/mainframe" ]]
}

@test "installer rejects root and dot-dot aliases before dependency or target traversal" {
    local root_alias
    create_fixture_repo
    make_traversal_probe
    root_alias="$TEST_TMPDIR/root-alias"
    ln -s / "$root_alias"

    assert_unsafe_install_target_stops_at_preflight /
    assert_unsafe_install_target_stops_at_preflight /tmp/..
    assert_unsafe_install_target_stops_at_preflight "$root_alias"
}

@test "installer rejects HOME dot and symlink aliases without creating missing parents" {
    local home_alias missing_parent
    create_fixture_repo
    make_traversal_probe
    printf 'keep\n' > "$TEST_HOME/home-sentinel"
    home_alias="$TEST_TMPDIR/home-alias"
    missing_parent="$TEST_HOME/not-created"
    ln -s "$TEST_HOME" "$home_alias"

    assert_unsafe_install_target_stops_at_preflight "$TEST_HOME"
    assert_unsafe_install_target_stops_at_preflight "$TEST_HOME/."
    assert_unsafe_install_target_stops_at_preflight "$missing_parent/.."
    assert_unsafe_install_target_stops_at_preflight "$home_alias"

    grep -Fxq keep "$TEST_HOME/home-sentinel"
    [[ ! -e "$missing_parent" ]]
}

@test "inherited MAINFRAME_FORCE cannot authorize replacement" {
    create_fixture_repo
    mkdir -p "$INSTALL_DIR"
    printf 'do not delete\n' > "$INSTALL_DIR/user-file"

    run installer_env env \
        MAINFRAME_FORCE=1 \
        "$BASH_BIN" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-shell --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Inherited MAINFRAME_FORCE cannot authorize replacement"* ]]
    [[ "$output" == *"pass --force on the same command"* ]]
    [[ -f "$INSTALL_DIR/user-file" ]]
    grep -Fxq 'do not delete' "$INSTALL_DIR/user-file"
    [[ ! -e "$BIN_DIR/mainframe" ]]
}

@test "get-mainframe delegates to the canonical installer and honors MAINFRAME_DIR" {
    create_fixture_repo
    local alias_install_dir="$TEST_HOME/custom-mainframe"
    printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$alias_install_dir" \
        > "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    chmod 600 "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"

    run env \
        HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$XDG_DIR" \
        SHELL=/bin/bash \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_DIR="$alias_install_dir" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        MAINFRAME_VERIFY_CHECKSUMS=0 \
        bash "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --legacy-source \
        --legacy-installer-url "file://$PROJECT_ROOT/install.sh" \
        --repo "file://$FIXTURE_REPO" --branch main --allow-unverified-source \
        --no-claude --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$alias_install_dir/bin/mainframe" ]]

    run env HOME="$TEST_HOME" "$BIN_DIR/mainframe" quickref --list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Available libraries:"* ]]
}

@test "receipt-backed CLI delegates upgrade arguments to the trusted updater" {
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/scripts" "$BIN_DIR"
    cp "$PROJECT_ROOT/bin/mainframe" "$INSTALL_DIR/bin/mainframe"
    cp "$PROJECT_ROOT/lib/common.sh" "$INSTALL_DIR/lib/common.sh"
    cp "$PROJECT_ROOT/scripts/upgrade-release.sh" "$INSTALL_DIR/scripts/upgrade-release.sh"
    chmod 755 "$INSTALL_DIR/bin/mainframe" "$INSTALL_DIR/scripts/upgrade-release.sh"
    ln -s "$INSTALL_DIR/bin/mainframe" "$BIN_DIR/mainframe"
    printf '{}\n' > "$INSTALL_DIR/.mainframe-install-receipt.json"
    chmod 600 "$INSTALL_DIR/.mainframe-install-receipt.json"

    run env HOME="$TEST_HOME" MAINFRAME_VERSION=999.999.999 MAINFRAME_SKIP_AUTOLOAD=1 \
        "$BIN_DIR/mainframe" upgrade --version not-semver

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Upgrade version must be stable SemVer: not-semver"* ]]
    [[ "$output" != *"Update only works for git-based installations"* ]]

    run env HOME="$TEST_HOME" MAINFRAME_SKIP_AUTOLOAD=1 "$BIN_DIR/mainframe" upgrade --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe upgrade --version X.Y.Z"* ]]
    [[ "$output" == *"mainframe upgrade --recover"* ]]
}

@test "source update recognizes linked worktrees and ignores ambient Git routing" {
    local linked="$TEST_TMPDIR/linked-source"
    create_fixture_repo
    git -C "$FIXTURE_REPO" switch -q -c holding-branch
    git -C "$FIXTURE_REPO" worktree add -q "$linked" main
    printf 'linked-only change\n' >> "$linked/VERSION"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_ROOT="$linked" \
        MAINFRAME_SKIP_AUTOLOAD=1 \
        GIT_DIR="$FIXTURE_REPO/.git" \
        GIT_WORK_TREE="$FIXTURE_REPO" \
        GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0=core.worktree \
        GIT_CONFIG_VALUE_0="$FIXTURE_REPO" \
        "$linked/bin/mainframe" update

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Refusing to update a checkout with local changes"* ]]
    [[ "$(git -C "$FIXTURE_REPO" status --porcelain)" == "" ]]
    grep -Fq 'linked-only change' "$linked/VERSION"
}

@test "canonical CLI preserves bundled operation dispatch" {
    run "$PROJECT_ROOT/mainframe" operations data
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"json-to-csv"* ]]

    run "$PROJECT_ROOT/mainframe" json-to-csv --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"json-to-csv"* ]]
}

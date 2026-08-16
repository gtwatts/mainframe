#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-shell-test.XXXXXX")"
    TEST_TMPDIR="$(cd "$TEST_TMPDIR" && pwd -P)"
    TEST_HOME="$TEST_TMPDIR/home"
    TEST_BIN="$TEST_HOME/.local/bin"
    STALE_ROOT="$TEST_TMPDIR/candidate-a"
    TEST_PROJECT="$TEST_TMPDIR/project"
    mkdir -p "$TEST_HOME" "$TEST_BIN" "$STALE_ROOT/completions" "$TEST_PROJECT"

    MODERN_BASH="${MAINFRAME_BASH:-${BASH:-}}"
    if ! modern_bash "$MODERN_BASH"; then
        for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash; do
            if modern_bash "$candidate"; then
                MODERN_BASH="$candidate"
                break
            fi
        done
    fi
    modern_bash "$MODERN_BASH" || skip "Bash 4.4+ is required"
    ZSH_BIN=""
    for candidate in /bin/zsh /usr/bin/zsh /opt/homebrew/bin/zsh /usr/local/bin/zsh; do
        [[ -x "$candidate" ]] && { ZSH_BIN="$candidate"; break; }
    done
    JQ_BIN=""
    for candidate in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq /bin/jq; do
        [[ -x "$candidate" ]] && { JQ_BIN="$candidate"; break; }
    done
    [[ -n "$JQ_BIN" ]] || skip "jq is required"

    ln -s "$PROJECT_ROOT/bin/mainframe" "$TEST_BIN/mainframe"
    printf '# stale bash completion\n' > "$STALE_ROOT/completions/mainframe.bash"
    printf '# stale zsh completion\n' > "$STALE_ROOT/completions/mainframe.zsh"
    write_stale_profiles
}

teardown() {
    rm -rf -- "$TEST_TMPDIR"
}

modern_bash() {
    local candidate="${1:-}"
    [[ -x "$candidate" ]] || return 1
    "$candidate" --noprofile --norc -p -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))
    ' >/dev/null 2>&1
}

base_path() {
    printf '%s\n' "$TEST_BIN:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

write_homebrew_wrapper() {
    local wrapper="$1" target="$2" bash_opt_bin="$3" jq_opt_bin="$4"
    local opt_bin="$5" opt_libexec="$6"
    {
        printf '#!/bin/bash\n'
        # shellcheck disable=SC2016 # $PATH and $@ are literal wrapper syntax.
        printf 'PATH="%s:%s:$PATH" MAINFRAME_INSTALL_METHOD="homebrew" MAINFRAME_HOMEBREW_BASH_OPT_BIN="%s" MAINFRAME_HOMEBREW_JQ_OPT_BIN="%s" MAINFRAME_HOMEBREW_OPT_BIN="%s" MAINFRAME_HOMEBREW_OPT_LIBEXEC="%s" MAINFRAME_PI_LIFECYCLE_REQUIRED="1" exec "%s"  "$@"\n' \
            "$bash_opt_bin" "$jq_opt_bin" "$bash_opt_bin" "$jq_opt_bin" \
            "$opt_bin" "$opt_libexec" "$target"
    } > "$wrapper"
    chmod 0555 "$wrapper"
}

write_stale_runtime_block() {
    local shell_name="$1"
    cat <<EOF
# >>> MAINFRAME >>>
export MAINFRAME_ROOT=$STALE_ROOT
export MAINFRAME_BASH=$MODERN_BASH
export MAINFRAME_AI_ENABLED=1
_MAINFRAME_SHELL_BIN_DIR=$TEST_BIN
case ":\${PATH:-}:" in
    *":\${_MAINFRAME_SHELL_BIN_DIR}:"*) ;;
    *) export PATH="\${_MAINFRAME_SHELL_BIN_DIR}\${PATH:+:\${PATH}}" ;;
esac
unset _MAINFRAME_SHELL_BIN_DIR
EOF
    if [[ "$shell_name" == bash ]]; then
        printf '_MAINFRAME_BASHRC_LOADED=1\n'
    fi
    printf '[[ -f "$MAINFRAME_ROOT/completions/mainframe.%s" ]] && source "$MAINFRAME_ROOT/completions/mainframe.%s"\n' \
        "$shell_name" "$shell_name"
    printf '# <<< MAINFRAME <<<\n'
}

write_stale_profiles() {
    {
        printf 'bash-user-before\n'
        write_stale_runtime_block bash
        printf 'bash-user-after\n'
    } > "$TEST_HOME/.bashrc"
    cat > "$TEST_HOME/.profile" <<'EOF'
profile-user-before
# >>> MAINFRAME BASH LOGIN >>>
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && [ "${_MAINFRAME_BASHRC_LOADED:-}" != "1" ]; then
    . "$HOME/.bashrc"
fi
unset _MAINFRAME_BASHRC_LOADED
# <<< MAINFRAME BASH LOGIN <<<
profile-user-after
EOF
    {
        printf ': zsh-user-before\n'
        write_stale_runtime_block zsh
        printf ': zsh-user-after\n'
    } > "$TEST_HOME/.zshrc"
    chmod 600 "$TEST_HOME/.bashrc" "$TEST_HOME/.profile" "$TEST_HOME/.zshrc"
}

run_mainframe() {
    run env -i \
        HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="${ZSH_BIN:-/bin/zsh}" TERM=dumb TMPDIR="$TEST_TMPDIR" \
        PATH="$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
        "$TEST_BIN/mainframe" "$@"
}

run_mainframe_with_inherited_root() {
    run env -i \
        HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="${ZSH_BIN:-/bin/zsh}" TERM=dumb TMPDIR="$TEST_TMPDIR" \
        PATH="$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_ROOT="$STALE_ROOT" \
        "$TEST_BIN/mainframe" "$@"
}

file_sha() {
    if [[ -x /usr/bin/shasum ]]; then
        /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
    else
        /usr/bin/sha256sum "$1" | /usr/bin/awk '{print $1}'
    fi
}

@test "selected CLI detects stale Bash and zsh roots and doctor/setup stay non-ready" {
    run_mainframe shell status --shell all --json
    [[ "$status" -eq 2 ]]
    printf '%s' "$output" | "$JQ_BIN" -e \
        --arg active "$PROJECT_ROOT" '
          .schema_version == 1 and .state == "repair-required" and
          .active_root == $active and .bash_state == "repair-required" and
          .zsh_state == "repair-required" and .inherited_state == "absent"
        ' >/dev/null

    run_mainframe doctor
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Shell identity: repair-required"* ]]

    run_mainframe setup --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Install doctor: not-ready"* ]]
}

@test "Homebrew doctor authenticates the keg wrapper and accepts its public symlink" {
    local brew_root="$TEST_TMPDIR/homebrew" version=10.2.0
    local keg="$brew_root/Cellar/mainframe/$version"
    local keg_bin="$keg/bin" libexec="$keg/libexec"
    local opt_prefix="$brew_root/opt/mainframe" public_bin="$brew_root/bin"
    local bash_opt_bin="$brew_root/opt/bash/bin" jq_opt_bin="$brew_root/opt/jq/bin"
    local opt_bin="$opt_prefix/bin" opt_libexec="$opt_prefix/libexec"
    local wrapper="$keg_bin/mainframe" target="$libexec/bin/mainframe"
    local foreign_bin="$TEST_TMPDIR/foreign-bin"

    mkdir -p "$keg_bin" "$libexec" "$public_bin" \
        "$bash_opt_bin" "$jq_opt_bin" "$brew_root/opt"
    chmod 0775 "$brew_root"
    cp -R "$PROJECT_ROOT/bin" "$PROJECT_ROOT/config" "$PROJECT_ROOT/hooks" \
        "$PROJECT_ROOT/lib" "$libexec/"
    cp "$PROJECT_ROOT/FUNCTIONS.json" "$PROJECT_ROOT/VERSION" "$libexec/"
    ln -s "$MODERN_BASH" "$bash_opt_bin/bash"
    ln -s "$JQ_BIN" "$jq_opt_bin/jq"
    ln -s "../Cellar/mainframe/$version" "$opt_prefix"
    ln -s "../Cellar/mainframe/$version/bin/mainframe" "$public_bin/mainframe"
    write_homebrew_wrapper \
        "$wrapper" "$target" "$bash_opt_bin" "$jq_opt_bin" "$opt_bin" "$opt_libexec"

    run env -i \
        HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="${ZSH_BIN:-/bin/zsh}" TERM=dumb TMPDIR="$TEST_TMPDIR" \
        PATH="$public_bin:$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
        "$public_bin/mainframe" doctor

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Shell identity: Homebrew-managed wrapper (selected; profiles not required)"* ]]
    [[ "$output" == *"Status: All checks passed!"* ]]
    [[ "$output" != *"repair-required"* ]]

    run env -i \
        HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="${ZSH_BIN:-/bin/zsh}" TERM=dumb TMPDIR="$TEST_TMPDIR" \
        PATH="$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_INSTALL_METHOD=homebrew \
        "$target" doctor

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Shell identity: Homebrew-managed runtime binding is unverified (ERROR)"* ]]

    chmod 0755 "$wrapper"
    {
        printf '#!/bin/bash\n'
        printf ': claimed-opt-bin-substitution\n'
        # shellcheck disable=SC2016 # $PATH and $@ are literal wrapper syntax.
        printf 'PATH="%s:%s:$PATH" MAINFRAME_INSTALL_METHOD="homebrew" MAINFRAME_HOMEBREW_BASH_OPT_BIN="%s" MAINFRAME_HOMEBREW_JQ_OPT_BIN="%s" MAINFRAME_HOMEBREW_OPT_BIN="%s" MAINFRAME_HOMEBREW_OPT_LIBEXEC="%s" MAINFRAME_PI_LIFECYCLE_REQUIRED="1" exec "%s"  "$@"\n' \
            "$bash_opt_bin" "$jq_opt_bin" "$bash_opt_bin" "$jq_opt_bin" \
            "$opt_bin" "$opt_libexec" "$target"
    } > "$wrapper"
    chmod 0555 "$wrapper"
    run env -i \
        HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="${ZSH_BIN:-/bin/zsh}" TERM=dumb TMPDIR="$TEST_TMPDIR" \
        PATH="$public_bin:$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
        "$public_bin/mainframe" doctor

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Shell identity: Homebrew-managed runtime binding is unverified (ERROR)"* ]]
    [[ "$output" == *"Status: 1 issue(s) found"* ]]

    chmod 0755 "$wrapper"
    write_homebrew_wrapper \
        "$wrapper" "$target" "$bash_opt_bin" "$jq_opt_bin" "$opt_bin" "$opt_libexec"
    mkdir -m 0700 "$foreign_bin"
    printf '#!%s\nexit 0\n' "$MODERN_BASH" > "$foreign_bin/mainframe"
    chmod 0700 "$foreign_bin/mainframe"
    run env -i \
        HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="${ZSH_BIN:-/bin/zsh}" TERM=dumb TMPDIR="$TEST_TMPDIR" \
        PATH="$foreign_bin:$public_bin:$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
        "$public_bin/mainframe" doctor

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Shell identity: Homebrew-managed runtime is mismatch (ERROR)"* ]]
    [[ "$output" == *"Status: 1 issue(s) found"* ]]
}

@test "trusted shell ancestry admits root-owned sticky system temp roots" {
    local unsafe_parent="$TEST_TMPDIR/non-sticky-shared" unsafe_child="$TEST_TMPDIR/non-sticky-shared/home"

    run "$MODERN_BASH" --noprofile --norc -p -c \
        'source "$1"; _mainframe_shell_trusted_ancestry /var/tmp' \
        mainframe-shell-test "$PROJECT_ROOT/lib/shell.sh"
    [[ "$status" -eq 0 ]]

    mkdir -p "$unsafe_child"
    chmod 0777 "$unsafe_parent"
    chmod 0700 "$unsafe_child"
    run "$MODERN_BASH" --noprofile --norc -p -c \
        'source "$1"; _mainframe_shell_trusted_ancestry "$2"' \
        mainframe-shell-test "$PROJECT_ROOT/lib/shell.sh" "$unsafe_child"
    [[ "$status" -eq 77 ]]

    run rg -n --fixed-strings -- \
        '/tmp|/private/tmp|/var/tmp|/private/var/tmp)' "$PROJECT_ROOT/lib/shell.sh"
    [[ "$status" -eq 0 ]]
}

@test "repair dry-run leaves every profile byte-identical and requires explicit intent" {
    local bash_before profile_before zsh_before
    bash_before="$(file_sha "$TEST_HOME/.bashrc")"
    profile_before="$(file_sha "$TEST_HOME/.profile")"
    zsh_before="$(file_sha "$TEST_HOME/.zshrc")"

    run_mainframe shell repair --shell all
    [[ "$status" -eq 64 ]]
    [[ "$output" == *"requires --dry-run or --yes"* ]]

    run_mainframe shell repair --shell all --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Would repair MAINFRAME shell integration: $TEST_HOME/.bashrc"* ]]
    [[ "$output" == *"Would repair MAINFRAME shell integration: $TEST_HOME/.zshrc"* ]]
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]
    [[ "$(file_sha "$TEST_HOME/.profile")" == "$profile_before" ]]
    [[ "$(file_sha "$TEST_HOME/.zshrc")" == "$zsh_before" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '.mainframe-shell-*' -print)" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '*.mainframe-shell-backup-*' -print)" ]]
}

@test "dual-shell repair retargets A to B and fresh shells load B completions" {
    [[ -n "$ZSH_BIN" ]] || skip "zsh is required"

    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Repaired MAINFRAME shell integration: $TEST_HOME/.bashrc"* ]]
    [[ "$output" == *"Repaired MAINFRAME shell integration: $TEST_HOME/.zshrc"* ]]
    grep -Fxq 'bash-user-before' "$TEST_HOME/.bashrc"
    grep -Fxq 'bash-user-after' "$TEST_HOME/.bashrc"
    grep -Fxq 'profile-user-before' "$TEST_HOME/.profile"
    grep -Fxq 'profile-user-after' "$TEST_HOME/.profile"
    grep -Fxq ': zsh-user-before' "$TEST_HOME/.zshrc"
    grep -Fxq ': zsh-user-after' "$TEST_HOME/.zshrc"
    [[ "$(grep -Fxc '# >>> MAINFRAME >>>' "$TEST_HOME/.bashrc")" == 1 ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME >>>' "$TEST_HOME/.zshrc")" == 1 ]]
    grep -Fq "export MAINFRAME_ROOT=$PROJECT_ROOT" "$TEST_HOME/.bashrc"
    grep -Fq "export MAINFRAME_ROOT=$PROJECT_ROOT" "$TEST_HOME/.zshrc"
    ! grep -Fq "$STALE_ROOT" "$TEST_HOME/.bashrc"
    ! grep -Fq "$STALE_ROOT" "$TEST_HOME/.zshrc"

    run_mainframe shell status --shell all --json
    [[ "$status" -eq 0 ]]
    printf '%s' "$output" | "$JQ_BIN" -e \
        '.state == "ready" and .bash_state == "ready" and .zsh_state == "ready"' >/dev/null

    local shell_mode zsh_completion_fpath
    for shell_mode in -lic -ic; do
        run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
            SHELL="$MODERN_BASH" TERM=dumb PATH="$(base_path)" \
            EXPECTED_ROOT="$PROJECT_ROOT" EXPECTED_CLI="$TEST_BIN/mainframe" \
            "$MODERN_BASH" "$shell_mode" '
                [[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]] || exit 70
                [[ "$(command -v mainframe)" == "$EXPECTED_CLI" ]] || exit 71
                complete -p mainframe >/dev/null || exit 72
            '
        [[ "$status" -eq 0 ]]
    done

    # Hosted runners may append writable site-function directories that
    # compaudit correctly rejects. Use the system compinit directory alone for
    # this headless registration probe instead of weakening compinit checks.
    zsh_completion_fpath="$(
        env -i PATH="$(base_path)" "$ZSH_BIN" -fc '
            for directory in $fpath; do
                [[ -f "$directory/compinit" && -f "$directory/compaudit" ]] || continue
                print -r -- "$directory"
                exit 0
            done
            exit 1
        '
    )"
    [[ -n "$zsh_completion_fpath" ]]
    run env -i HOME="$TEST_HOME" ZDOTDIR="$TEST_HOME" \
        USER=mainframe-test LOGNAME=mainframe-test SHELL="$ZSH_BIN" TERM=dumb \
        PATH="$(base_path)" FPATH="$zsh_completion_fpath" \
        EXPECTED_ROOT="$PROJECT_ROOT" EXPECTED_CLI="$TEST_BIN/mainframe" \
        "$ZSH_BIN" -ic '
            [[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]] || exit 70
            [[ "$(whence -p mainframe)" == "$EXPECTED_CLI" ]] || exit 71
            [[ "${_comps[mainframe]:-}" == "_mainframe" ]] || exit 72
        '
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"not interactive and can't open terminal"* ]]
    [[ "$output" != *"compinit: initialization aborted"* ]]
}

@test "current profiles with a stale inherited root require a fresh parent instead of repair" {
    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 0 ]]

    run_mainframe_with_inherited_root shell status --shell all --json
    [[ "$status" -eq 2 ]]
    printf '%s' "$output" | "$JQ_BIN" -e \
        --arg active "$PROJECT_ROOT" \
        --arg inherited "$STALE_ROOT" '
          .schema_version == 1 and .state == "reload-required" and
          .active_root == $active and .bash_state == "ready" and
          .zsh_state == "ready" and .inherited_root == $inherited and
          .inherited_state == "stale" and
          .details == ["environment:stale-root"]
        ' >/dev/null

    run_mainframe_with_inherited_root shell status --shell all
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"State:          reload-required"* ]]
    [[ "$output" == *"start a fresh shell or restart the parent app"* ]]
    [[ "$output" != *"shell repair"* ]]

    run_mainframe_with_inherited_root doctor
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Shell identity: reload-required"* ]]
    [[ "$output" == *"start a fresh shell or restart the parent app"* ]]

    run_mainframe_with_inherited_root setup --project "$TEST_PROJECT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Install doctor: reload-required"* ]]
    [[ "$output" == *"start a fresh shell or restart the parent app"* ]]

    run_mainframe shell status --shell all --json
    [[ "$status" -eq 0 ]]
    printf '%s' "$output" | "$JQ_BIN" -e '.state == "ready"' >/dev/null
}

@test "repair is idempotent and does not create a second backup set" {
    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 0 ]]
    local bash_after profile_after zsh_after backup_count
    bash_after="$(file_sha "$TEST_HOME/.bashrc")"
    profile_after="$(file_sha "$TEST_HOME/.profile")"
    zsh_after="$(file_sha "$TEST_HOME/.zshrc")"
    backup_count="$(find "$TEST_HOME" -maxdepth 1 -name '*.mainframe-shell-backup-*' | wc -l | tr -d ' ')"

    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"already current for all"* ]]
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_after" ]]
    [[ "$(file_sha "$TEST_HOME/.profile")" == "$profile_after" ]]
    [[ "$(file_sha "$TEST_HOME/.zshrc")" == "$zsh_after" ]]
    [[ "$(find "$TEST_HOME" -maxdepth 1 -name '*.mainframe-shell-backup-*' | wc -l | tr -d ' ')" == "$backup_count" ]]
}

@test "exclusive lifecycle scratch files never follow a pre-existing symlink" {
    local victim="$TEST_TMPDIR/victim" collision collision_device
    local first_random second_random third_random fourth_random
    local scratch scratch_fd scratch_identity scratch_digest
    printf 'victim-original\n' > "$victim"
    chmod 600 "$victim"

    # Resetting Bash's PRNG reproduces the helper's first candidate exactly.
    # The existing candidate is a symlink to a user file, which noclobber must
    # refuse without opening or truncating its target.
    RANDOM=12345
    first_random="$RANDOM"
    second_random="$RANDOM"
    third_random="$RANDOM"
    fourth_random="$RANDOM"
    collision_device="$TEST_HOME/.race-probe.$$.$first_random$second_random.0"
    collision="$TEST_HOME/.race-probe.$$.$third_random$fourth_random.1"
    ln -s /dev/null "$collision_device"
    ln -s "$victim" "$collision"

    source "$PROJECT_ROOT/lib/shell.sh"
    RANDOM=12345
    _mainframe_shell_open_exclusive_file \
        "$TEST_HOME" race-probe scratch scratch_fd scratch_identity
    [[ "$scratch" != "$collision" ]]
    printf 'private-scratch\n' >&"$scratch_fd"
    _mainframe_shell_finalize_open_file \
        "$scratch" "$scratch_fd" "$scratch_identity" 600 ''
    scratch_digest="$(_mainframe_shell_digest_created_file \
        "$scratch" "$scratch_identity" 600)"
    [[ -n "$scratch_digest" ]]
    [[ "$(<"$victim")" == victim-original ]]
    [[ -L "$collision_device" ]]
    [[ "$(/usr/bin/readlink "$collision_device")" == /dev/null ]]
    [[ -L "$collision" ]]
    [[ "$(/usr/bin/readlink "$collision")" == "$victim" ]]
    _mainframe_shell_safe_remove_created "$scratch" "$scratch_identity"

    # A watcher may also replace the random pathname after it was opened. The
    # held descriptor must remain attached to the unlinked scratch inode, and
    # final validation must refuse both the replacement and its cleanup.
    _mainframe_shell_open_exclusive_file \
        "$TEST_HOME" swap-probe scratch scratch_fd scratch_identity
    rm -f -- "$scratch"
    ln -s "$victim" "$scratch"
    printf 'held-descriptor-only\n' >&"$scratch_fd"
    if _mainframe_shell_finalize_open_file \
        "$scratch" "$scratch_fd" "$scratch_identity" 600 ''; then
        false
    fi
    if _mainframe_shell_safe_remove_created "$scratch" "$scratch_identity"; then
        false
    fi
    [[ "$(<"$victim")" == victim-original ]]
    [[ -L "$scratch" ]]
    [[ "$(/usr/bin/readlink "$scratch")" == "$victim" ]]
}

@test "final profile replacement never follows a directory symlink planted after revalidation" {
    local profile="$TEST_HOME/.apply-race-profile"
    local saved="$TEST_HOME/.apply-race-original"
    local redirected="$TEST_HOME/apply-race-redirected"
    local apply_status redirected_entry
    mkdir -p "$redirected"
    chmod 700 "$redirected"
    printf 'apply-race-original\n' > "$profile"
    chmod 600 "$profile"

    source "$PROJECT_ROOT/lib/shell.sh"
    MAINFRAME_ROOT="$PROJECT_ROOT"
    _MAINFRAME_SHELL_SELECTED_BIN="$TEST_BIN"
    _MAINFRAME_SHELL_TARGET_FILES=("$profile")
    _MAINFRAME_SHELL_TARGET_KINDS=(bash-runtime)
    _mainframe_shell_prepare_files false

    # The apply path revalidates once before backups and once immediately
    # before replacement. Plant the directory symlink after that last check.
    eval "$(declare -f _mainframe_shell_revalidate_original | \
        /usr/bin/sed '1s/_mainframe_shell_revalidate_original/_test_real_revalidate_original/')"
    TEST_REVALIDATE_CALLS=0
    _mainframe_shell_revalidate_original() {
        TEST_REVALIDATE_CALLS=$((TEST_REVALIDATE_CALLS + 1))
        _test_real_revalidate_original "$@" || return $?
        if (( TEST_REVALIDATE_CALLS == 2 )); then
            mv -- "$profile" "$saved" || return 91
            ln -s "$redirected" "$profile" || return 92
        fi
    }

    if _mainframe_shell_apply_prepared; then
        apply_status=0
    else
        apply_status=$?
    fi
    redirected_entry="$(find "$redirected" -mindepth 1 -maxdepth 1 -print -quit)"

    [[ "$apply_status" -eq 0 ]]
    [[ "$TEST_REVALIDATE_CALLS" -ge 2 ]]
    [[ -f "$profile" && ! -L "$profile" ]]
    [[ "$(<"$saved")" == apply-race-original ]]
    grep -Fxq '# >>> MAINFRAME >>>' "$profile"
    [[ -z "$redirected_entry" ]]
    _mainframe_shell_cleanup_temps
}

@test "rollback preserves a replacement planted after apply without redirecting backup data" {
    local profile="$TEST_HOME/.rollback-race-profile"
    local stolen="$TEST_HOME/.rollback-race-stolen-output"
    local redirected="$TEST_HOME/rollback-race-redirected"
    local wanted_identity apply_status redirected_entry retained_backup
    mkdir -p "$redirected"
    chmod 700 "$redirected"
    printf 'rollback-race-original\n' > "$profile"
    chmod 600 "$profile"

    source "$PROJECT_ROOT/lib/shell.sh"
    MAINFRAME_ROOT="$PROJECT_ROOT"
    _MAINFRAME_SHELL_SELECTED_BIN="$TEST_BIN"
    _MAINFRAME_SHELL_TARGET_FILES=("$profile")
    _MAINFRAME_SHELL_TARGET_KINDS=(bash-runtime)
    _mainframe_shell_prepare_files false
    wanted_identity="${_MAINFRAME_SHELL_CHANGE_TEMP_IDENTITIES[0]}"

    # Swap the destination only when apply validates the newly installed
    # inode. Rollback must neither follow nor overwrite that concurrent change;
    # it retains the authenticated backup for manual recovery.
    eval "$(declare -f _mainframe_shell_validate_created_file | \
        /usr/bin/sed '1s/_mainframe_shell_validate_created_file/_test_real_validate_created_file/')"
    TEST_APPLY_DESTINATION_SWAPPED=false
    _mainframe_shell_validate_created_file() {
        if [[ "$1" == "$profile" && "$2" == "$wanted_identity" && \
              "$TEST_APPLY_DESTINATION_SWAPPED" == false ]]; then
            TEST_APPLY_DESTINATION_SWAPPED=true
            mv -- "$profile" "$stolen" || return 91
            ln -s "$redirected" "$profile" || return 92
        fi
        _test_real_validate_created_file "$@"
    }

    if _mainframe_shell_apply_prepared; then
        apply_status=0
    else
        apply_status=$?
    fi
    redirected_entry="$(find "$redirected" -mindepth 1 -maxdepth 1 -print -quit)"
    retained_backup="$(find "$TEST_HOME" -maxdepth 1 \
        -name '..rollback-race-profile.mainframe-shell-backup-*' \
        -type f -print -quit)"

    [[ "$apply_status" -eq 74 ]]
    [[ "$TEST_APPLY_DESTINATION_SWAPPED" == true ]]
    [[ -L "$profile" ]]
    [[ "$(/usr/bin/readlink "$profile")" == "$redirected" ]]
    [[ -n "$retained_backup" ]]
    [[ "$(<"$retained_backup")" == rollback-race-original ]]
    [[ -f "$stolen" && ! -L "$stolen" ]]
    [[ -z "$redirected_entry" ]]
    _mainframe_shell_cleanup_temps
}

@test "malformed or unsafe target refuses the complete repair before any profile changes" {
    local bash_before profile_before
    bash_before="$(file_sha "$TEST_HOME/.bashrc")"
    profile_before="$(file_sha "$TEST_HOME/.profile")"
    printf '\n# >>> MAINFRAME >>>\n' >> "$TEST_HOME/.zshrc"

    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *"refuses malformed managed markers: $TEST_HOME/.zshrc"* ]]
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]
    [[ "$(file_sha "$TEST_HOME/.profile")" == "$profile_before" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '*.mainframe-shell-backup-*' -print)" ]]

    rm -f "$TEST_HOME/.zshrc"
    printf 'external\n' > "$TEST_TMPDIR/external-zshrc"
    ln -s "$TEST_TMPDIR/external-zshrc" "$TEST_HOME/.zshrc"
    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *"refuses an unsafe profile: $TEST_HOME/.zshrc"* ]]
    grep -Fxq external "$TEST_TMPDIR/external-zshrc"
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]

    rm -f "$TEST_HOME/.zshrc"
    printf 'hard-linked\n' > "$TEST_TMPDIR/hardlinked-zshrc"
    ln "$TEST_TMPDIR/hardlinked-zshrc" "$TEST_HOME/.zshrc"
    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *"refuses an unsafe profile: $TEST_HOME/.zshrc"* ]]
    grep -Fxq hard-linked "$TEST_TMPDIR/hardlinked-zshrc"
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]

    rm -f "$TEST_HOME/.zshrc"
    printf 'writable-by-others\n' > "$TEST_HOME/.zshrc"
    chmod 666 "$TEST_HOME/.zshrc"
    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *"refuses an unsafe profile: $TEST_HOME/.zshrc"* ]]
    grep -Fxq writable-by-others "$TEST_HOME/.zshrc"
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]

    if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
        chmod 600 "$TEST_HOME/.zshrc"
        chmod +a 'everyone allow write' "$TEST_HOME/.zshrc"
        run_mainframe shell repair --shell all --yes
        [[ "$status" -eq 77 ]]
        [[ "$output" == *"refuses an unsafe profile: $TEST_HOME/.zshrc"* ]]
        chmod -a# 0 "$TEST_HOME/.zshrc"
    fi
}

@test "an explicit checkout is reported but cannot rewrite the PATH-selected installation" {
    local empty_bin="$TEST_TMPDIR/empty-bin" unsafe_bin="$TEST_TMPDIR/unsafe-bin" bash_before
    mkdir -p "$empty_bin" "$unsafe_bin"
    bash_before="$(file_sha "$TEST_HOME/.bashrc")"

    chmod 700 "$TEST_BIN"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL=/bin/zsh TERM=dumb PATH="$empty_bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" \
        "$PROJECT_ROOT/bin/mainframe" shell repair --shell all --yes
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"must run through the MAINFRAME CLI selected by PATH"* ]]
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]

    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL=/bin/zsh TERM=dumb PATH="$empty_bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
        MAINFRAME_BASH="$MODERN_BASH" "$PROJECT_ROOT/bin/mainframe" doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Shell identity: Explicit runtime (selected PATH integration not checked)"* ]]

    chmod 777 "$TEST_BIN"
    run_mainframe shell repair --shell all --yes
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"must run through the MAINFRAME CLI selected by PATH"* ]]
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]

    printf '#!/bin/sh\nprintf unsafe-first-must-never-run\n' > "$unsafe_bin/mainframe"
    chmod 755 "$unsafe_bin/mainframe"
    chmod 777 "$unsafe_bin"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL=/bin/zsh TERM=dumb \
        PATH="$unsafe_bin:$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
        "$TEST_BIN/mainframe" shell status --shell all --json
    [[ "$status" -eq 77 ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.state')" == blocked ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.selection_state')" == unsafe ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.selected_cli')" == "$unsafe_bin/mainframe" ]]
    [[ "$(file_sha "$TEST_HOME/.bashrc")" == "$bash_before" ]]

    chmod 700 "$TEST_BIN"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL=/bin/zsh TERM=dumb PATH="$TEST_BIN" MAINFRAME_BASH="$MODERN_BASH" \
        "$TEST_BIN/mainframe" shell status --shell all --json
    [[ "$status" -eq 2 ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.selection_state')" == ready ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.selected_cli')" == "$TEST_BIN/mainframe" ]]

    chmod 777 "$TEST_HOME/.local"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL=/bin/zsh TERM=dumb PATH="$TEST_BIN" MAINFRAME_BASH="$MODERN_BASH" \
        "$TEST_BIN/mainframe" shell status --shell all --json
    [[ "$status" -eq 77 ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.selection_state')" == unsafe ]]
    chmod 755 "$TEST_HOME/.local"

    if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
        chmod 700 "$unsafe_bin"
        chmod +a 'everyone allow add_file' "$unsafe_bin"
        run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
            SHELL=/bin/zsh TERM=dumb \
            PATH="$unsafe_bin:$(base_path)" MAINFRAME_BASH="$MODERN_BASH" \
            "$TEST_BIN/mainframe" shell status --shell all --json
        [[ "$status" -eq 77 ]]
        [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.selection_state')" == unsafe ]]
        chmod -a# 0 "$unsafe_bin"
    fi
}

@test "zsh lifecycle follows an owned absolute ZDOTDIR without rewriting HOME zshrc" {
    local custom_zdotdir="$TEST_HOME/.config/zsh" home_before
    mkdir -p "$custom_zdotdir"
    printf 'zdot-user-before\n' > "$custom_zdotdir/.zshrc"
    write_stale_runtime_block zsh >> "$custom_zdotdir/.zshrc"
    printf 'zdot-user-after\n' >> "$custom_zdotdir/.zshrc"
    chmod 600 "$custom_zdotdir/.zshrc"
    printf 'ZDOTDIR="$HOME/.config/zsh"\n' > "$TEST_HOME/.zshenv"
    chmod 600 "$TEST_HOME/.zshenv"
    home_before="$(file_sha "$TEST_HOME/.zshrc")"

    run_mainframe shell status --shell zsh --json
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"found a non-exported or otherwise hidden ZDOTDIR assignment"* ]]
    [[ "$output" == *"--zdotdir ABS"* ]]

    run_mainframe shell status --shell zsh --zdotdir "$custom_zdotdir" --json
    [[ "$status" -eq 2 ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.zsh_profile')" == "$custom_zdotdir/.zshrc" ]]
    [[ "$(printf '%s' "$output" | "$JQ_BIN" -r '.zdotdir_source')" == override ]]

    run_mainframe shell repair --shell zsh --zdotdir "$custom_zdotdir" --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$custom_zdotdir/.zshrc"* ]]
    [[ "$(file_sha "$TEST_HOME/.zshrc")" == "$home_before" ]]

    run env -i HOME="$TEST_HOME" \
        USER=mainframe-test LOGNAME=mainframe-test SHELL="$ZSH_BIN" TERM=dumb \
        PATH="$(base_path)" EXPECTED_ROOT="$PROJECT_ROOT" \
        "$ZSH_BIN" -ic '[[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]]'
    [[ "$status" -eq 0 ]]

    run_mainframe shell repair --shell zsh --zdotdir relative/zsh --dry-run
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"requires ZDOTDIR to be an existing absolute directory"* ]]
}

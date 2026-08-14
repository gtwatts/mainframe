#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-lifecycle-test.XXXXXX")"
    TEST_TMPDIR="$(cd "$TEST_TMPDIR" && pwd -P)"
    TEST_HOME="$TEST_TMPDIR/home"
    INSTALL_DIR="$TEST_HOME/.mainframe"
    BIN_DIR="$TEST_HOME/.local/bin"
    XDG_DIR="$TEST_HOME/.config"
    mkdir -p "$TEST_HOME" "$BIN_DIR" "$XDG_DIR"
    printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$INSTALL_DIR" \
        > "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    chmod 600 "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"

    MODERN_BASH="${MAINFRAME_BASH:-${BASH:-}}"
    if ! is_modern_bash "$MODERN_BASH"; then
        for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash; do
            if is_modern_bash "$candidate"; then
                MODERN_BASH="$candidate"
                break
            fi
        done
    fi
    is_modern_bash "$MODERN_BASH" || skip "Bash 4.4+ is required for installer lifecycle tests"

    ZSH_BIN=""
    for candidate in /bin/zsh /usr/bin/zsh /opt/homebrew/bin/zsh /usr/local/bin/zsh; do
        if [[ -x "$candidate" ]]; then
            ZSH_BIN="$candidate"
            break
        fi
    done
}

teardown() {
    rm -rf -- "$TEST_TMPDIR"
}

is_modern_bash() {
    local candidate="${1:-}"
    [[ -x "$candidate" ]] || return 1
    "$candidate" -c '
        ((BASH_VERSINFO[0] > 4)) ||
        ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))
    ' >/dev/null 2>&1
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
    cp "$PROJECT_ROOT/MANIFEST.json" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/VERSION" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/get-mainframe.sh" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/install.sh" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/mainframe" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT/uninstall.sh" "$FIXTURE_REPO/"

    # Lifecycle installer cases exercise install, version, profile loading,
    # and uninstall. Operation scripts are outside that fixture contract and
    # can contain large generated developer artifacts in a dirty checkout.
    for required in \
        bin/mainframe \
        completions/mainframe.bash completions/mainframe.zsh \
        config/function-export-policy.json \
        hooks/agent-gateway.sh hooks/dispatcher.sh \
        lib/common.sh lib/config.sh lib/args.sh \
        FUNCTIONS.json MANIFEST.json VERSION \
        get-mainframe.sh install.sh mainframe uninstall.sh; do
        [[ -e "$FIXTURE_REPO/$required" ]] || {
            printf 'fixture is missing required install lifecycle path: %s\n' "$required" >&2
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

create_installation_fixture() {
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$BIN_DIR"
    printf 'test-version\n' > "$INSTALL_DIR/VERSION"
    printf '# fixture\n' > "$INSTALL_DIR/lib/common.sh"
    printf '#!/usr/bin/env bash\n' > "$INSTALL_DIR/bin/mainframe"
    chmod +x "$INSTALL_DIR/bin/mainframe"
    regenerate_fixture_manifest
}

fixture_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    else
        shasum -a 256 "$file" | awk '{print $1}'
    fi
}

fixture_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

regenerate_fixture_manifest() {
    local relative
    (
        cd "$INSTALL_DIR"
        while IFS= read -r relative; do
            relative="${relative#./}"
            printf '%s  %s\n' "$(fixture_sha256 "$relative")" "$relative"
        done < <(find . -type f ! -name SHA256SUMS | LC_ALL=C sort)
    ) > "$INSTALL_DIR/SHA256SUMS"
}

write_managed_bashrc() {
    cat > "$TEST_HOME/.bashrc" <<EOF
user-before
# >>> MAINFRAME >>>
export MAINFRAME_ROOT="$INSTALL_DIR"
export PATH="$BIN_DIR:\$PATH"
# <<< MAINFRAME <<<
user-after
EOF
}

write_managed_bash_login() {
    cat > "$TEST_HOME/.bash_profile" <<'EOF'
login-user-before
# >>> MAINFRAME BASH LOGIN >>>
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
# <<< MAINFRAME BASH LOGIN <<<
login-user-after
EOF
}

@test "Bash install is idempotently discoverable in genuine login and interactive non-login shells" {
    local canonical_modern_bash expected_bash_line

    create_fixture_repo
    printf 'bashrc-user-before\n' > "$TEST_HOME/.bashrc"
    printf 'login-user-before\n. "$HOME/.bashrc"\n' > "$TEST_HOME/.bash_profile"

    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME >>>' "$TEST_HOME/.bashrc")" == "1" ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME BASH LOGIN >>>' "$TEST_HOME/.bash_profile")" == "1" ]]
    canonical_modern_bash="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$MODERN_BASH")"
    printf -v expected_bash_line 'export MAINFRAME_BASH=%q' "$canonical_modern_bash"
    grep -Fxq "$expected_bash_line" "$TEST_HOME/.bashrc"
    grep -Fxq 'bashrc-user-before' "$TEST_HOME/.bashrc"
    grep -Fxq 'login-user-before' "$TEST_HOME/.bash_profile"
    grep -Fq '. "$HOME/.bashrc"' "$TEST_HOME/.bash_profile"

    cp "$TEST_HOME/.bashrc" "$TEST_TMPDIR/bashrc.after-first-install"
    cp "$TEST_HOME/.bash_profile" "$TEST_TMPDIR/bash-profile.after-first-install"
    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery
    [[ "$status" -eq 0 ]]
    cmp -s "$TEST_HOME/.bashrc" "$TEST_TMPDIR/bashrc.after-first-install"
    cmp -s "$TEST_HOME/.bash_profile" "$TEST_TMPDIR/bash-profile.after-first-install"

    base_path="$(dirname "$MODERN_BASH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    for shell_mode in -lic -ic; do
        run env -i \
            HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
            SHELL="$MODERN_BASH" TERM=dumb PATH="$base_path" \
            EXPECTED_CLI="$BIN_DIR/mainframe" EXPECTED_ROOT="$INSTALL_DIR" \
            EXPECTED_BIN="$BIN_DIR" \
            "$MODERN_BASH" "$shell_mode" '
                [[ "$(command -v mainframe)" == "$EXPECTED_CLI" ]] || exit 70
                [[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]] || exit 71
                [[ "$(printf "%s" "$PATH" | tr ":" "\n" | grep -Fxc "$EXPECTED_BIN")" == "1" ]] || exit 72
            '
        [[ "$status" -eq 0 ]]
    done
}

@test "zsh install, completion, and recoverable uninstall preserve user profile content" {
    local base_path canonical_modern_bash expected_bash_line install_backup zshrc_after_install

    [[ -n "$ZSH_BIN" ]] || skip "zsh is required for installer lifecycle tests"
    create_fixture_repo
    printf '%s\n' \
        '# zsh-user-before' \
        'autoload -Uz compinit && compinit -i' \
        '# zsh-user-after' > "$TEST_HOME/.zshrc"

    run installer_env SHELL="$ZSH_BIN" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME >>>' "$TEST_HOME/.zshrc")" == "1" ]]
    canonical_modern_bash="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$MODERN_BASH")"
    printf -v expected_bash_line 'export MAINFRAME_BASH=%q' "$canonical_modern_bash"
    grep -Fxq "$expected_bash_line" "$TEST_HOME/.zshrc"
    grep -Fxq '# zsh-user-before' "$TEST_HOME/.zshrc"
    grep -Fxq '# zsh-user-after' "$TEST_HOME/.zshrc"

    zshrc_after_install="$TEST_TMPDIR/zshrc.after-first-install"
    cp "$TEST_HOME/.zshrc" "$zshrc_after_install"
    run installer_env SHELL="$ZSH_BIN" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery
    [[ "$status" -eq 0 ]]
    cmp -s "$TEST_HOME/.zshrc" "$zshrc_after_install"

    base_path="$(dirname "$MODERN_BASH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    run env -i \
        HOME="$TEST_HOME" ZDOTDIR="$TEST_HOME" \
        USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="$ZSH_BIN" TERM=dumb PATH="$base_path" \
        EXPECTED_CLI="$BIN_DIR/mainframe" EXPECTED_ROOT="$INSTALL_DIR" \
        EXPECTED_BIN="$BIN_DIR" \
        "$ZSH_BIN" -ic '
            [[ "$(whence -p mainframe)" == "$EXPECTED_CLI" ]] || exit 70
            [[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]] || exit 71
            [[ "${_comps[mainframe]:-}" == "_mainframe" ]] || exit 72
            path_count=0
            for path_entry in "${path[@]}"; do
                [[ "$path_entry" == "$EXPECTED_BIN" ]] && (( path_count += 1 ))
            done
            (( path_count == 1 )) || exit 73
        '
    [[ "$status" -eq 0 ]]

    run env HOME="$TEST_HOME" MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$INSTALL_DIR/uninstall.sh" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Would remove the exact MAINFRAME marker block(s) from $TEST_HOME/.zshrc"* ]]
    [[ "$output" == *"Would move installation to recoverable backup"* ]]
    cmp -s "$TEST_HOME/.zshrc" "$zshrc_after_install"
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ -d "$INSTALL_DIR" ]]

    run env HOME="$TEST_HOME" MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$INSTALL_DIR/uninstall.sh"
    [[ "$status" -eq 0 ]]
    grep -Fxq '# zsh-user-before' "$TEST_HOME/.zshrc"
    grep -Fxq '# zsh-user-after' "$TEST_HOME/.zshrc"
    [[ -z "$(grep -F 'MAINFRAME' "$TEST_HOME/.zshrc" || true)" ]]
    [[ ! -e "$BIN_DIR/mainframe" && ! -L "$BIN_DIR/mainframe" ]]
    [[ ! -e "$INSTALL_DIR" ]]
    install_backup="$(find "$TEST_HOME" -maxdepth 1 -type d \
        -name '.mainframe.uninstalled-*' -print -quit)"
    [[ -n "$install_backup" ]]
}

@test "Bash install bridges the first effective existing login profile" {
    create_fixture_repo
    printf 'profile-user-content\n' > "$TEST_HOME/.profile"

    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_HOME/.bashrc" ]]
    [[ ! -e "$TEST_HOME/.bash_profile" && ! -e "$TEST_HOME/.bash_login" ]]
    grep -Fxq 'profile-user-content' "$TEST_HOME/.profile"
    [[ "$(grep -Fxc '# >>> MAINFRAME BASH LOGIN >>>' "$TEST_HOME/.profile")" == "1" ]]

    base_path="$(dirname "$MODERN_BASH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="$MODERN_BASH" TERM=dumb PATH="$base_path" EXPECTED_CLI="$BIN_DIR/mainframe" \
        "$MODERN_BASH" -lic '[[ "$(command -v mainframe)" == "$EXPECTED_CLI" ]]'
    [[ "$status" -eq 0 ]]
}

@test "Bash login bridge does not source bashrc twice when profile already does" {
    create_fixture_repo
    cat > "$TEST_HOME/.bashrc" <<'EOF'
printf 'bashrc-loaded\n' >> "$HOME/bashrc-loads"
EOF
    cat > "$TEST_HOME/.profile" <<'EOF'
if [ -n "${BASH_VERSION:-}" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
EOF

    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME BASH LOGIN >>>' "$TEST_HOME/.profile")" == "1" ]]

    cp "$TEST_HOME/.bashrc" "$TEST_TMPDIR/debian-bashrc.after-first-install"
    cp "$TEST_HOME/.profile" "$TEST_TMPDIR/debian-profile.after-first-install"
    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery
    [[ "$status" -eq 0 ]]
    cmp -s "$TEST_HOME/.bashrc" "$TEST_TMPDIR/debian-bashrc.after-first-install"
    cmp -s "$TEST_HOME/.profile" "$TEST_TMPDIR/debian-profile.after-first-install"

    base_path="$(dirname "$MODERN_BASH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="$MODERN_BASH" TERM=dumb PATH="$base_path" EXPECTED_CLI="$BIN_DIR/mainframe" \
        "$MODERN_BASH" -lic '
            [[ "$(command -v mainframe)" == "$EXPECTED_CLI" ]] || exit 1
            [[ -z "${_MAINFRAME_BASHRC_LOADED+x}" ]]
        '

    [[ "$status" -eq 0 ]]
    [[ "$(grep -Fxc 'bashrc-loaded' "$TEST_HOME/bashrc-loads")" == "1" ]]
}

@test "shell profile escapes hostile install and bin path metacharacters as literal data" {
    local hostile_install hostile_bin base_path
    hostile_install="$TEST_HOME/"'runtime-$(touch${IFS}ROOT_INJECTION)'
    hostile_bin="$TEST_HOME/"'bin-`touch${IFS}BIN_INJECTION`'
    create_fixture_repo

    run installer_env env \
        MAINFRAME_INSTALL_DIR="$hostile_install" \
        MAINFRAME_BIN_DIR="$hostile_bin" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ ! -e "$TEST_HOME/ROOT_INJECTION" ]]
    [[ ! -e "$TEST_HOME/BIN_INJECTION" ]]
    [[ -L "$hostile_bin/mainframe" ]]

    base_path="$(dirname "$MODERN_BASH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="$MODERN_BASH" TERM=dumb PATH="$base_path" \
        EXPECTED_ROOT="$hostile_install" EXPECTED_BIN="$hostile_bin" \
        "$MODERN_BASH" --noprofile --norc -c '
            cd -- "$HOME" || exit 1
            source "$HOME/.bashrc" || exit 2
            [[ "$MAINFRAME_ROOT" == "$EXPECTED_ROOT" ]] || exit 3
            [[ "$(command -v mainframe)" == "$EXPECTED_BIN/mainframe" ]] || exit 4
        '

    [[ "$status" -eq 0 ]]
    [[ ! -e "$TEST_HOME/ROOT_INJECTION" ]]
    [[ ! -e "$TEST_HOME/BIN_INJECTION" ]]
}

@test "installer rejects control characters in profile paths before mutation" {
    local control_install
    control_install="$TEST_HOME/"$'runtime\nline-break'
    create_fixture_repo

    run installer_env env \
        MAINFRAME_INSTALL_DIR="$control_install" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"MAINFRAME_INSTALL_DIR must not contain control characters"* ]]
    [[ ! -e "$control_install" ]]
    [[ ! -e "$TEST_HOME/.bashrc" ]]
    [[ ! -e "$TEST_HOME/.bash_profile" ]]
}

@test "installer rejects colon bin paths and canonicalizes relative bin paths" {
    local colon_bin relative_bin expected_bin_line base_path
    colon_bin="$TEST_HOME/bin:second-entry"
    relative_bin="$TEST_HOME/relative-bin"
    create_fixture_repo

    run installer_env env \
        MAINFRAME_BIN_DIR="$colon_bin" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"MAINFRAME_BIN_DIR must not contain ':'"* ]]
    [[ ! -e "$colon_bin" ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$TEST_HOME/.bashrc" ]]

    run installer_env env \
        MAINFRAME_BIN_DIR=relative-bin \
        "$MODERN_BASH" -c '
            cd -- "$1" || exit 1
            exec "$2" --noprofile --norc -p "$3" --no-ai-discovery "${@:4}"
        ' _ "$TEST_HOME" "$MODERN_BASH" "$PROJECT_ROOT/install.sh"

    [[ "$status" -eq 0 ]]
    [[ -L "$relative_bin/mainframe" ]]
    printf -v expected_bin_line '_MAINFRAME_SHELL_BIN_DIR=%q' "$relative_bin"
    grep -Fxq "$expected_bin_line" "$TEST_HOME/.bashrc"

    base_path="$(dirname "$MODERN_BASH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    run env -i HOME="$TEST_HOME" USER=mainframe-test LOGNAME=mainframe-test \
        SHELL="$MODERN_BASH" TERM=dumb PATH="$base_path" EXPECTED_BIN="$relative_bin" \
        "$MODERN_BASH" --noprofile --norc -c '
            source "$HOME/.bashrc" || exit 1
            [[ "$(command -v mainframe)" == "$EXPECTED_BIN/mainframe" ]]
        '
    [[ "$status" -eq 0 ]]
}

@test "Bash install migrates a valid legacy runtime block out of the login profile" {
    create_fixture_repo
    write_managed_bashrc
    mv "$TEST_HOME/.bashrc" "$TEST_HOME/.bash_profile"

    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME >>>' "$TEST_HOME/.bashrc")" == "1" ]]
    [[ -z "$(grep -F '# >>> MAINFRAME >>>' "$TEST_HOME/.bash_profile" || true)" ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME BASH LOGIN >>>' "$TEST_HOME/.bash_profile")" == "1" ]]
    grep -Fxq 'user-before' "$TEST_HOME/.bash_profile"
    grep -Fxq 'user-after' "$TEST_HOME/.bash_profile"

    cat >> "$TEST_HOME/.bashrc" <<'EOF'
# >>> MAINFRAME BASH LOGIN >>>
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
# <<< MAINFRAME BASH LOGIN <<<
EOF
    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery
    [[ "$status" -eq 0 ]]
    [[ -z "$(grep -F 'MAINFRAME BASH LOGIN' "$TEST_HOME/.bashrc" || true)" ]]
    [[ "$(grep -Fxc '# >>> MAINFRAME >>>' "$TEST_HOME/.bashrc")" == "1" ]]
}

@test "Bash install refuses malformed runtime or login markers before installation mutation" {
    create_fixture_repo
    printf 'user-before\n# >>> MAINFRAME >>>\nuser-data\n' > "$TEST_HOME/.bashrc"
    original_bashrc="$(cat "$TEST_HOME/.bashrc")"

    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Malformed MAINFRAME marker block"* ]]
    [[ "$(cat "$TEST_HOME/.bashrc")" == "$original_bashrc" ]]
    [[ ! -e "$INSTALL_DIR" && ! -e "$BIN_DIR/mainframe" ]]

    rm "$TEST_HOME/.bashrc"
    printf 'login-before\n# >>> MAINFRAME BASH LOGIN >>>\nuser-data\n' > "$TEST_HOME/.bash_profile"
    original_login="$(cat "$TEST_HOME/.bash_profile")"
    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Malformed MAINFRAME Bash-login marker block"* ]]
    [[ "$(cat "$TEST_HOME/.bash_profile")" == "$original_login" ]]
    [[ ! -e "$INSTALL_DIR" && ! -e "$BIN_DIR/mainframe" ]]

    rm "$TEST_HOME/.bash_profile"
    printf '%s\n' \
        'user-before' \
        '# >>> MAINFRAME >>>' \
        '# >>> MAINFRAME BASH LOGIN >>>' \
        '# <<< MAINFRAME <<<' \
        '# <<< MAINFRAME BASH LOGIN <<<' \
        'user-after' > "$TEST_HOME/.bashrc"
    original_cross_nested="$(cat "$TEST_HOME/.bashrc")"
    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Overlapping MAINFRAME managed marker blocks"* ]]
    [[ "$(cat "$TEST_HOME/.bashrc")" == "$original_cross_nested" ]]
    [[ ! -e "$INSTALL_DIR" && ! -e "$BIN_DIR/mainframe" ]]
}

@test "default install leaves Claude settings untouched and directs read-only guided setup" {
    local installer_output search_query

    create_fixture_repo
    mkdir -p "$XDG_DIR/claude"
    printf '{"sentinel":"user-owned"}\n' > "$XDG_DIR/claude/settings.json"
    original_settings="$(cat "$XDG_DIR/claude/settings.json")"

    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-shell

    [[ "$status" -eq 0 ]]
    installer_output="$output"
    [[ "$(cat "$XDG_DIR/claude/settings.json")" == "$original_settings" ]]
    [[ ! -e "$XDG_DIR/claude/settings.json.bak" ]]
    [[ "$output" == *"mainframe doctor"* ]]
    [[ "$output" == *"mainframe setup --project . --proof"* ]]
    [[ "$output" == *"mainframe setup --project ."* ]]
    [[ "$output" != *"mainframe quickref --list"* ]]
    [[ "$output" != *"Get help:"*"mainframe help"* ]]
    [[ "$output" == *"never auto-selects a host"* ]]
    [[ "$output" == *"installer does not run setup or onboarding"* ]]
    [[ "$output" != *"--host claude-code"* ]]

    # The installer owns this first-use copy/paste contract. Capture its plain
    # text query without evaluating the printed shell command, then prove that
    # the installed CLI can resolve it through canonical semantic discovery.
    [[ "$installer_output" =~ mainframe\ search\ \"([^\"]+)\" ]]
    search_query="${BASH_REMATCH[1]}"
    [[ "$search_query" == "create json object" ]]

    run env \
        HOME="$TEST_HOME" \
        XDG_CONFIG_HOME="$XDG_DIR" \
        MAINFRAME_BASH="$MODERN_BASH" \
        "$BIN_DIR/mainframe" search "$search_query"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Canonical functions matching 'create json object':"* ]]
    [[ "$output" == *"json_object - json [risk=low, stable-core, pure, idempotent]"* ]]
}

@test "deprecated no-claude flag remains a successful no-op" {
    run "$MODERN_BASH" "$PROJECT_ROOT/install.sh" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--no-claude"*"Deprecated no-op"* ]]
}

@test "installer never replaces an unrelated CLI path" {
    create_fixture_repo
    unrelated_target="$TEST_TMPDIR/user-cli"
    printf '#!/bin/sh\n' > "$unrelated_target"
    ln -s "$unrelated_target" "$BIN_DIR/mainframe"

    run installer_env "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-shell

    [[ "$status" -ne 0 ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$unrelated_target" ]]
    [[ "$output" == *"already a symlink to a different target"* ]]
}

@test "direct installer never executes dependency shims from caller PATH" {
    marker="$TEST_TMPDIR/installer-ambient-tool-executed"
    fake_bin="$TEST_TMPDIR/installer-fake-bin"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "%s\n" "$0" >> "${MAINFRAME_TEST_TOOL_MARKER:?}"' \
        'exit 97' \
        > "$fake_bin/tool-shim"
    chmod 755 "$fake_bin/tool-shim"
    ln -s tool-shim "$fake_bin/git"
    ln -s tool-shim "$fake_bin/jq"
    create_fixture_repo

    run installer_env env \
        PATH="$fake_bin:$PATH" \
        MAINFRAME_TEST_TOOL_MARKER="$marker" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
}

@test "shell setup never promotes the install bin directory into the installer process" {
    marker="$TEST_TMPDIR/installer-bin-tool-executed"
    mkdir -p "$BIN_DIR"
    for tool in mkdir cp; do
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "%s\n" "$0" >> "${MAINFRAME_TEST_TOOL_MARKER:?}"' \
            'exec "/bin/${0##*/}" "$@"' \
            > "$BIN_DIR/$tool"
        chmod 755 "$BIN_DIR/$tool"
    done
    create_fixture_repo

    run installer_env env \
        MAINFRAME_TEST_TOOL_MARKER="$marker" \
        "$MODERN_BASH" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
}

@test "bootstrap accepts macOS system Bash and delegates to MAINFRAME_BASH" {
    bootstrap_log="$TEST_TMPDIR/bootstrap.log"
    stub_installer="$TEST_TMPDIR/stub-install.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "$BASH_VERSION" > "$BOOTSTRAP_LOG"' \
        'printf "%s\n" "$@" >> "$BOOTSTRAP_LOG"' \
        > "$stub_installer"
    chmod +x "$stub_installer"
    expected_version="$("$MODERN_BASH" -c 'printf "%s" "$BASH_VERSION"')"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        BOOTSTRAP_LOG="$bootstrap_log" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_INTERNAL_TESTING=1 \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --legacy-source \
        --legacy-installer-url "file://$stub_installer" \
        --repo "https://github.com/gtwatts/mainframe.git" --branch main \
        --allow-unverified-source --no-shell --no-claude

    [[ "$status" -eq 0 ]]
    [[ "$(sed -n '1p' "$bootstrap_log")" == "$expected_version" ]]
    grep -Fxq -- '--no-shell' "$bootstrap_log"
    grep -Fxq -- '--no-claude' "$bootstrap_log"
}

@test "bootstrap automatically locates Bash 4.4+ from a system-Bash launch" {
    bootstrap_log="$TEST_TMPDIR/bootstrap-auto.log"
    stub_installer="$TEST_TMPDIR/stub-auto-install.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "$BASH_VERSION" > "$BOOTSTRAP_LOG"' \
        > "$stub_installer"
    chmod +x "$stub_installer"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$(dirname "$MODERN_BASH"):$PATH" \
        BOOTSTRAP_LOG="$bootstrap_log" \
        MAINFRAME_BASH= \
        MAINFRAME_INTERNAL_TESTING=1 \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --legacy-source \
        --legacy-installer-url "file://$stub_installer" \
        --repo "https://github.com/gtwatts/mainframe.git" --branch main \
        --allow-unverified-source

    [[ "$status" -eq 0 ]]
    delegated_version="$(cat "$bootstrap_log")"
    delegated_major="${delegated_version%%.*}"
    delegated_minor="${delegated_version#*.}"
    delegated_minor="${delegated_minor%%.*}"
    ((delegated_major > 4 || (delegated_major == 4 && delegated_minor >= 4)))
}

@test "bootstrap rejects an invalid MAINFRAME_BASH with actionable guidance" {
    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_BASH="$TEST_TMPDIR/does-not-exist" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"MAINFRAME_BASH must name a trusted absolute Bash 4.4+ executable"* ]]
    [[ "$output" == *"brew install bash"* ]]
}

@test "bootstrap rejects a relative MAINFRAME_BASH without executing it" {
    marker="$TEST_TMPDIR/relative-bash-executed"
    fake_bin="$TEST_TMPDIR/relative-bin"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "executed\n" > "${MAINFRAME_TEST_MARKER:?}"' \
        'exit 0' \
        > "$fake_bin/bash"
    chmod 755 "$fake_bin/bash"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$fake_bin:$PATH" \
        MAINFRAME_TEST_MARKER="$marker" \
        MAINFRAME_BASH=bash \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$marker" ]]
    [[ "$output" == *"MAINFRAME_BASH must be an absolute path"* ]]
}

@test "bootstrap rejects a scratch-owned absolute Bash override without executing it" {
    marker="$TEST_TMPDIR/absolute-bash-executed"
    fake_bash="$TEST_TMPDIR/absolute-bash"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "executed\n" > "${MAINFRAME_TEST_MARKER:?}"' \
        'exit 0' \
        > "$fake_bash"
    chmod 755 "$fake_bash"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_TEST_MARKER="$marker" \
        MAINFRAME_BASH="$fake_bash" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$marker" ]]
    [[ "$output" == *"MAINFRAME_BASH must name a trusted absolute Bash 4.4+ executable"* ]]
}

@test "bootstrap and installer share one fixed Bash location contract" {
    local custom_bash="$TEST_TMPDIR/custom-bash"
    cp "$MODERN_BASH" "$custom_bash"
    chmod 700 "$custom_bash"
    create_fixture_repo

    run env \
        HOME="$TEST_HOME" TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_BASH="$custom_bash" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"MAINFRAME_BASH must name a trusted absolute Bash 4.4+ executable"* ]]

    run installer_env "$custom_bash" --noprofile --norc -p \
        "$PROJECT_ROOT/install.sh" --no-shell --no-ai-discovery

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Bash must resolve to a supported system"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
}

@test "bootstrap canonicalizes a relative install target before Bash exclusion" {
    marker="$TEST_TMPDIR/relative-install-bash-executed"
    relative_work="$TEST_TMPDIR/relative-install-work"
    fake_bash="$relative_work/relative-target/bin/bash"
    mkdir -p "$(dirname "$fake_bash")"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "executed\n" > "${MAINFRAME_TEST_MARKER:?}"' \
        'exit 0' \
        > "$fake_bash"
    chmod 755 "$fake_bash"

    run /bin/bash --noprofile --norc -p -c '
        cd "$1" || exit
        env HOME="$2" TMPDIR=/tmp \
            MAINFRAME_TEST_MARKER="$3" \
            MAINFRAME_INSTALL_DIR=relative-target \
            MAINFRAME_BASH="$4" \
            /bin/bash --noprofile --norc -p "$5"
    ' _ "$relative_work" "$TEST_HOME" "$marker" "$fake_bash" \
        "$PROJECT_ROOT/get-mainframe.sh"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$marker" ]]
    [[ "$output" == *"MAINFRAME_BASH must name a trusted absolute Bash 4.4+ executable"* ]]
}

@test "bootstrap never probes a PATH bash candidate" {
    marker="$TEST_TMPDIR/path-bash-executed"
    bootstrap_log="$TEST_TMPDIR/bootstrap-fixed.log"
    fake_bin="$TEST_TMPDIR/path-bin"
    stub_installer="$TEST_TMPDIR/stub-fixed-install.sh"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "executed\n" > "${MAINFRAME_TEST_MARKER:?}"' \
        'exit 0' \
        > "$fake_bin/bash"
    printf '%s\n' \
        '#!/bin/bash' \
        'printf "%s\n" "$BASH_VERSION" > "${BOOTSTRAP_LOG:?}"' \
        > "$stub_installer"
    chmod 755 "$fake_bin/bash" "$stub_installer"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$fake_bin:$PATH" \
        MAINFRAME_TEST_MARKER="$marker" \
        BOOTSTRAP_LOG="$bootstrap_log" \
        MAINFRAME_BASH= \
        MAINFRAME_INTERNAL_TESTING=1 \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --legacy-source \
        --legacy-installer-url "file://$stub_installer" \
        --repo "https://github.com/gtwatts/mainframe.git" --branch main \
        --allow-unverified-source

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    [[ -s "$bootstrap_log" ]]
}

@test "direct bootstrap and delegated installer ignore shell startup injection" {
    marker="$TEST_TMPDIR/bootstrap-startup-injection"
    bootstrap_log="$TEST_TMPDIR/bootstrap-clean-env.log"
    bash_env="$TEST_TMPDIR/bash-env"
    stub_installer="$TEST_TMPDIR/stub-clean-install.sh"
    printf '%s\n' \
        'printf "BASH_ENV executed\n" >> "${MAINFRAME_TEST_MARKER:?}"' \
        > "$bash_env"
    printf '%s\n' \
        '#!/bin/bash' \
        '[[ -z "${BASH_ENV:-}" ]] || exit 71' \
        'declare -F mainframe_bootstrap_injected >/dev/null 2>&1 && exit 72' \
        'printf "clean\n" > "${BOOTSTRAP_LOG:?}"' \
        > "$stub_installer"
    chmod 600 "$bash_env"
    chmod 755 "$stub_installer"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        BASH_ENV="$bash_env" \
        'BASH_FUNC_mainframe_bootstrap_injected%%=() { printf "function executed\n" >> "${MAINFRAME_TEST_MARKER:?}"; }' \
        MAINFRAME_TEST_MARKER="$marker" \
        BOOTSTRAP_LOG="$bootstrap_log" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_INTERNAL_TESTING=1 \
        "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --legacy-source \
        --legacy-installer-url "file://$stub_installer" \
        --repo "https://github.com/gtwatts/mainframe.git" --branch main \
        --allow-unverified-source

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    [[ "$(cat "$bootstrap_log")" == "clean" ]]
}

@test "explicit Bash bootstrap protects re-entry before imported set or builtin functions" {
    local marker="$TEST_TMPDIR/bootstrap-primitive-function-injection"
    local stub_installer="$TEST_TMPDIR/stub-primitive-install.sh"
    printf '%s\n' '#!/bin/bash' 'exit 0' > "$stub_installer"
    chmod 755 "$stub_installer"

    run env -i \
        HOME="$TEST_HOME" TMPDIR="$TEST_TMPDIR" PATH=/usr/bin:/bin \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_TEST_MARKER="$marker" \
        'BASH_FUNC_set%%=() { printf "set executed\n" >> "${MAINFRAME_TEST_MARKER:?}"; }' \
        'BASH_FUNC_builtin%%=() { printf "builtin executed\n" >> "${MAINFRAME_TEST_MARKER:?}"; }' \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --legacy-source \
        --legacy-installer-url "file://$stub_installer" \
        --repo "https://github.com/gtwatts/mainframe.git" --branch main \
        --allow-unverified-source

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
}

@test "direct installer entry ignores BASH_ENV" {
    marker="$TEST_TMPDIR/installer-startup-injection"
    bash_env="$TEST_TMPDIR/installer-bash-env"
    printf '%s\n' \
        'printf "BASH_ENV executed\n" >> "${MAINFRAME_TEST_MARKER:?}"' \
        > "$bash_env"
    chmod 600 "$bash_env"

    run env \
        HOME="$TEST_HOME" \
        BASH_ENV="$bash_env" \
        MAINFRAME_TEST_MARKER="$marker" \
        "$PROJECT_ROOT/install.sh" --help

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    [[ "$output" == *"MAINFRAME Installation Script"* ]]
}

@test "explicit Bash installer protects re-entry before imported set or builtin functions" {
    local marker="$TEST_TMPDIR/installer-primitive-function-injection"

    run env -i \
        HOME="$TEST_HOME" PATH=/usr/bin:/bin \
        MAINFRAME_TEST_MARKER="$marker" \
        'BASH_FUNC_set%%=() { printf "set executed\n" >> "${MAINFRAME_TEST_MARKER:?}"; }' \
        'BASH_FUNC_builtin%%=() { printf "builtin executed\n" >> "${MAINFRAME_TEST_MARKER:?}"; }' \
        "$MODERN_BASH" "$PROJECT_ROOT/install.sh" --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME Installation Script"* ]]
    [[ ! -e "$marker" ]]
}

@test "unprivileged explicit modern Bash is authenticated before installer re-entry" {
    create_fixture_repo

    run installer_env "$MODERN_BASH" \
        "$PROJECT_ROOT/install.sh" --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    grep -Fq "export MAINFRAME_BASH=" "$TEST_HOME/.bashrc" || \
        [[ ! -e "$TEST_HOME/.bashrc" ]]
}

@test "dry-run reports owned changes without altering profiles links or installation" {
    create_installation_fixture
    write_managed_bashrc
    write_managed_bash_login
    ln -s "$INSTALL_DIR/bin/mainframe" "$BIN_DIR/mainframe"
    original_profile="$(cat "$TEST_HOME/.bashrc")"
    original_login_profile="$(cat "$TEST_HOME/.bash_profile")"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --dry-run

    [[ "$status" -eq 0 ]]
    [[ -d "$INSTALL_DIR" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(cat "$TEST_HOME/.bashrc")" == "$original_profile" ]]
    [[ "$(cat "$TEST_HOME/.bash_profile")" == "$original_login_profile" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '.mainframe.uninstalled-*' -print -quit)" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '.bashrc.mainframe-backup-*' -print -quit)" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '.bash_profile.mainframe-backup-*' -print -quit)" ]]
    [[ "$output" == *"Would remove the exact MAINFRAME marker block"* ]]
    [[ "$output" == *"Would remove owned CLI symlink"* ]]
    [[ "$output" == *"Would move installation to recoverable backup"* ]]
}

@test "default uninstall preserves user profile content and moves install to backup" {
    create_installation_fixture
    write_managed_bashrc
    write_managed_bash_login
    ln -s "$INSTALL_DIR/bin/mainframe" "$BIN_DIR/mainframe"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh"

    [[ "$status" -eq 0 ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -L "$BIN_DIR/mainframe" ]]
    grep -Fxq 'user-before' "$TEST_HOME/.bashrc"
    grep -Fxq 'user-after' "$TEST_HOME/.bashrc"
    [[ -z "$(grep -F 'MAINFRAME' "$TEST_HOME/.bashrc" || true)" ]]
    grep -Fxq 'login-user-before' "$TEST_HOME/.bash_profile"
    grep -Fxq 'login-user-after' "$TEST_HOME/.bash_profile"
    [[ -z "$(grep -F 'MAINFRAME' "$TEST_HOME/.bash_profile" || true)" ]]

    install_backup="$(find "$TEST_HOME" -maxdepth 1 -type d -name '.mainframe.uninstalled-*' -print -quit)"
    profile_backup="$(find "$TEST_HOME" -maxdepth 1 -type f -name '.bashrc.mainframe-backup-*' -print -quit)"
    login_profile_backup="$(find "$TEST_HOME" -maxdepth 1 -type f -name '.bash_profile.mainframe-backup-*' -print -quit)"
    [[ -f "$install_backup/VERSION" ]]
    grep -Fxq '# >>> MAINFRAME >>>' "$profile_backup"
    grep -Fxq '# >>> MAINFRAME BASH LOGIN >>>' "$login_profile_backup"
    [[ "$output" == *"Restore installation with: mv"* ]]
    [[ "$output" == *"Restore CLI link with: ln -s"* ]]
}

@test "purge requires explicit flag and leaves a differently targeted CLI link alone" {
    create_installation_fixture
    unrelated_target="$TEST_TMPDIR/user-mainframe"
    printf '#!/bin/sh\n' > "$unrelated_target"
    ln -s "$unrelated_target" "$BIN_DIR/mainframe"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge

    [[ "$status" -eq 0 ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$unrelated_target" ]]
    [[ "$output" == *"different target unchanged"* ]]
    [[ "$output" == *"verified runtime files"* ]]
}

@test "runtime purge preserves default AWM state beside the removed installation" {
    create_installation_fixture
    mkdir -p "$INSTALL_DIR/awm/projects"
    printf '%s\n' '{"sentinel":"durable-memory"}' > "$INSTALL_DIR/awm/projects/project.json"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge

    [[ "$status" -eq 0 ]]
    [[ ! -e "$INSTALL_DIR" ]]
    awm_backup="$(find "$TEST_HOME" -maxdepth 1 -type d \
        -name '.mainframe.state-preserved-*' -print -quit)"
    [[ -f "$awm_backup/awm/projects/project.json" ]]
    [[ ! -e "$awm_backup/VERSION" ]]
    [[ "$output" == *"Preserved all unmanaged or modified in-root data"* ]]
    [[ "$output" == *"project hook files are not removed"* ]]
}

@test "runtime purge preserves non-AWM state and modified managed files" {
    create_installation_fixture
    mkdir -p "$INSTALL_DIR/config" "$INSTALL_DIR/tasks/private"
    printf '%s\n' 'shipped=true' > "$INSTALL_DIR/config/default.conf"
    regenerate_fixture_manifest
    printf '%s\n' 'user-modified=true' > "$INSTALL_DIR/config/default.conf"
    printf '%s\n' 'private task state' > "$INSTALL_DIR/tasks/private/task.txt"
    chmod 600 "$INSTALL_DIR/tasks/private/task.txt"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge

    [[ "$status" -eq 0 ]]
    [[ ! -e "$INSTALL_DIR" ]]
    state_backup="$(find "$TEST_HOME" -maxdepth 1 -type d \
        -name '.mainframe.state-preserved-*' -print -quit)"
    grep -Fxq 'user-modified=true' "$state_backup/config/default.conf"
    grep -Fxq 'private task state' "$state_backup/tasks/private/task.txt"
    [[ "$(fixture_mode "$state_backup/tasks/private/task.txt")" == "600" ]]
    [[ ! -e "$state_backup/VERSION" ]]
    [[ ! -e "$state_backup/SHA256SUMS" ]]
}

@test "purge-state requires purge and is the only path that deletes default AWM" {
    create_installation_fixture
    mkdir -p "$INSTALL_DIR/awm/projects"
    printf '%s\n' '{"sentinel":"durable-memory"}' > "$INSTALL_DIR/awm/projects/project.json"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge-state

    [[ "$status" -ne 0 ]]
    [[ -f "$INSTALL_DIR/awm/projects/project.json" ]]
    [[ "$output" == *"--purge-state requires --purge"* ]]

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge --purge-state

    [[ "$status" -eq 0 ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -type d \
        -name '.mainframe.state-preserved-*' -print -quit)" ]]
    [[ "$output" == *"including default AWM state"* ]]
}

@test "purge never follows a symlinked AWM state directory" {
    create_installation_fixture
    external_awm="$TEST_TMPDIR/external-awm"
    mkdir -p "$external_awm/projects"
    printf '%s\n' '{"sentinel":"external-state"}' > "$external_awm/projects/project.json"
    ln -s "$external_awm" "$INSTALL_DIR/awm"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge --purge-state

    [[ "$status" -eq 0 ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ -f "$external_awm/projects/project.json" ]]
    [[ "$output" == *"will not follow it"* ]]
    [[ "$output" == *"external target remains"* ]]
}

@test "state-preserving purge fails before mutation when ownership inventory is invalid" {
    create_installation_fixture
    write_managed_bashrc
    ln -s "$INSTALL_DIR/bin/mainframe" "$BIN_DIR/mainframe"
    printf '%s\n' 'not a canonical checksum record' > "$INSTALL_DIR/SHA256SUMS"
    original_profile="$(cat "$TEST_HOME/.bashrc")"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge

    [[ "$status" -ne 0 ]]
    [[ -d "$INSTALL_DIR" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(cat "$TEST_HOME/.bashrc")" == "$original_profile" ]]
    [[ "$output" == *"invalid SHA256SUMS record"* ]]
    [[ "$output" == *"recoverable uninstall"* ]]
}

@test "state-preserving purge rejects checksum paths outside the install root" {
    create_installation_fixture
    external_state="$TEST_HOME/external-state.txt"
    printf '%s\n' 'must survive' > "$external_state"
    printf '%s  %s\n' "$(fixture_sha256 "$external_state")" '../external-state.txt' \
        >> "$INSTALL_DIR/SHA256SUMS"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge

    [[ "$status" -ne 0 ]]
    [[ -d "$INSTALL_DIR" ]]
    grep -Fxq 'must survive' "$external_state"
    [[ "$output" == *"invalid SHA256SUMS record"* ]]
}

@test "purge refuses home, root, symlinked, and unrecognized targets" {
    run env HOME="$TEST_HOME" MAINFRAME_INSTALL_DIR="$TEST_HOME" MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Refusing unsafe installation target"* ]]

    run env HOME="$TEST_HOME" MAINFRAME_INSTALL_DIR=/ MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Refusing unsafe installation target"* ]]

    unrelated="$TEST_HOME/not-mainframe"
    mkdir -p "$unrelated"
    run env HOME="$TEST_HOME" MAINFRAME_INSTALL_DIR="$unrelated" MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge
    [[ "$status" -ne 0 ]]
    [[ -d "$unrelated" ]]
    [[ "$output" == *"does not look like a MAINFRAME installation"* ]]

    create_installation_fixture
    symlink_target="$TEST_HOME/mainframe-link"
    ln -s "$INSTALL_DIR" "$symlink_target"
    run env HOME="$TEST_HOME" MAINFRAME_INSTALL_DIR="$symlink_target" MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --purge
    [[ "$status" -ne 0 ]]
    [[ -d "$INSTALL_DIR" ]]
    [[ -L "$symlink_target" ]]
    [[ "$output" == *"Refusing a symlinked installation target"* ]]
}

@test "malformed shell marker block is never partially removed" {
    create_installation_fixture
    printf 'user-before\n# >>> MAINFRAME >>>\nuser-data\n' > "$TEST_HOME/.bashrc"
    original_profile="$(cat "$TEST_HOME/.bashrc")"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_HOME/.bashrc")" == "$original_profile" ]]
    [[ "$output" == *"Malformed MAINFRAME marker block"* ]]
}

@test "malformed Bash login bridge is left byte-for-byte unchanged" {
    create_installation_fixture
    printf 'login-before\n# >>> MAINFRAME BASH LOGIN >>>\nuser-data\n' > "$TEST_HOME/.bash_profile"
    original_profile="$(cat "$TEST_HOME/.bash_profile")"

    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/uninstall.sh" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$(cat "$TEST_HOME/.bash_profile")" == "$original_profile" ]]
    [[ "$output" == *"Malformed MAINFRAME marker block"* ]]
}

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-uninstall-cli.XXXXXX")"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    TEST_HOME="$TEST_DIR/home"
    RUNTIME_ROOT="$TEST_DIR/runtime"
    LOG_FILE="$TEST_DIR/uninstaller.log"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"

    if [[ ! -x "$BASH_BIN" ]]; then
        BASH_BIN="$(command -v bash)"
    fi
    if ! "$BASH_BIN" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))'; then
        skip "Bash 4.4+ is required for uninstall CLI tests"
    fi

    mkdir -p "$TEST_HOME" "$RUNTIME_ROOT/bin" "$RUNTIME_ROOT/lib"
    cp "$PROJECT_ROOT/bin/mainframe" "$RUNTIME_ROOT/bin/mainframe"
    cp "$PROJECT_ROOT/lib/common.sh" "$RUNTIME_ROOT/lib/common.sh"
    chmod 755 "$RUNTIME_ROOT/bin/mainframe"
    write_stub_uninstaller
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

write_stub_uninstaller() {
    cat > "$RUNTIME_ROOT/uninstall.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'install_dir=%s\n' "${MAINFRAME_INSTALL_DIR:-}"
    printf 'root=%s\n' "${MAINFRAME_ROOT:-}"
    printf 'bash=%s\n' "${MAINFRAME_BASH:-}"
    printf 'argc=%d\n' "$#"
    index=0
    for argument in "$@"; do
        printf 'arg[%d]=%s\n' "$index" "$argument"
        index=$((index + 1))
    done
} > "${MAINFRAME_TEST_LOG:?}"
exit "${MAINFRAME_TEST_EXIT:-0}"
STUB
    chmod 755 "$RUNTIME_ROOT/uninstall.sh"
}

commit_source_fixture() {
    git -C "$RUNTIME_ROOT" init -q -b main
    git -C "$RUNTIME_ROOT" add bin/mainframe lib/common.sh uninstall.sh
    git -C "$RUNTIME_ROOT" \
        -c user.name="MAINFRAME Tests" \
        -c user.email="tests@mainframe.invalid" \
        commit -qm "trusted source fixture"
}

write_complete_pi_payload() {
    mkdir -p "$RUNTIME_ROOT/skills/pi/extensions"
    cp "$PROJECT_ROOT/package.json" "$RUNTIME_ROOT/package.json"
    cp "$PROJECT_ROOT/lib/pi.sh" "$RUNTIME_ROOT/lib/pi.sh"
    cp "$PROJECT_ROOT/skills/pi/SKILL.md" "$RUNTIME_ROOT/skills/pi/SKILL.md"
    cp "$PROJECT_ROOT/skills/pi/extensions/mainframe.ts" \
        "$RUNTIME_ROOT/skills/pi/extensions/mainframe.ts"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

write_release_receipt() {
    command -v jq >/dev/null 2>&1 || skip "jq is required for release ownership tests"
    local uninstaller_sha manifest_sha bin_dir
    uninstaller_sha="$(sha256_file "$RUNTIME_ROOT/uninstall.sh")"
    printf '%s  uninstall.sh\n' "$uninstaller_sha" > "$RUNTIME_ROOT/SHA256SUMS"
    manifest_sha="$(sha256_file "$RUNTIME_ROOT/SHA256SUMS")"
    bin_dir="$TEST_HOME/.local/bin"
    mkdir -p "$bin_dir"
    jq -n \
        --arg version "10.2.0" \
        --arg archive_sha256 "0000000000000000000000000000000000000000000000000000000000000000" \
        --arg manifest_sha256 "$manifest_sha" \
        --arg install_dir "$RUNTIME_ROOT" \
        --arg bin_dir "$bin_dir" \
        --arg cli_link "$bin_dir/mainframe" \
        '{schema_version: 1, install_method: "release-archive", version: $version,
          archive_sha256: $archive_sha256, manifest_sha256: $manifest_sha256,
          install_dir: $install_dir, bin_dir: $bin_dir, cli_link: $cli_link,
          installed_at: "2026-08-08T12:00:00Z"}' \
        > "$RUNTIME_ROOT/.mainframe-install-receipt.json"
    chmod 600 "$RUNTIME_ROOT/.mainframe-install-receipt.json"
}

run_runtime_cli() {
    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_SKIP_AUTOLOAD=1 \
        MAINFRAME_TEST_LOG="$LOG_FILE" \
        "$@"
}

make_hostile_tool_path() {
    HOSTILE_BIN="$TEST_DIR/hostile-bin"
    HOSTILE_TOOL_LOG="$TEST_DIR/hostile-tool.log"
    mkdir -p "$HOSTILE_BIN"

    local tool
    for tool in tr git jq sha256sum shasum openssl; do
        printf '%s\n' \
            '#!/bin/sh' \
            "printf '%s\\n' '$tool' >> \"\${MAINFRAME_HOSTILE_TOOL_LOG:?}\"" \
            'exit 97' > "$HOSTILE_BIN/$tool"
        chmod +x "$HOSTILE_BIN/$tool"
    done
}

@test "uninstall delegates every argument and exit status to the receipt-owned uninstaller" {
    write_release_receipt
    local profile="$TEST_HOME/profile with spaces" delegated_bash
    local bin_dir="$TEST_HOME/bin with spaces"

    run_runtime_cli \
        MAINFRAME_INSTALL_DIR="$TEST_HOME/not-the-runtime" \
        MAINFRAME_TEST_EXIT=23 \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall \
        --dry-run --purge --purge-state \
        --dir "$RUNTIME_ROOT" --bin "$bin_dir" --shell-config "$profile"

    [[ "$status" -eq 23 ]]
    [[ -f "$RUNTIME_ROOT/uninstall.sh" ]]
    [[ -f "$RUNTIME_ROOT/bin/mainframe" ]]
    grep -Fxq "install_dir=$RUNTIME_ROOT" "$LOG_FILE"
    grep -Fxq "root=$RUNTIME_ROOT" "$LOG_FILE"
    delegated_bash="$(sed -n 's/^bash=//p' "$LOG_FILE")"
    [[ -n "$delegated_bash" && "$delegated_bash" -ef "$BASH_BIN" ]]
    grep -Fxq 'argc=9' "$LOG_FILE"
    grep -Fxq 'arg[0]=--dry-run' "$LOG_FILE"
    grep -Fxq 'arg[1]=--purge' "$LOG_FILE"
    grep -Fxq 'arg[2]=--purge-state' "$LOG_FILE"
    grep -Fxq 'arg[3]=--dir' "$LOG_FILE"
    grep -Fxq "arg[4]=$RUNTIME_ROOT" "$LOG_FILE"
    grep -Fxq 'arg[5]=--bin' "$LOG_FILE"
    grep -Fxq "arg[6]=$bin_dir" "$LOG_FILE"
    grep -Fxq 'arg[7]=--shell-config' "$LOG_FILE"
    grep -Fxq "arg[8]=$profile" "$LOG_FILE"
}

@test "uninstall delegates to the exact clean uninstaller tracked by a source checkout" {
    commit_source_fixture

    run_runtime_cli \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run

    [[ "$status" -eq 0 ]]
    grep -Fxq 'argc=1' "$LOG_FILE"
    grep -Fxq 'arg[0]=--dry-run' "$LOG_FILE"
    [[ -f "$RUNTIME_ROOT/uninstall.sh" ]]
}

@test "source-owned uninstall ignores caller PATH tr and Git shims" {
    commit_source_fixture
    make_hostile_tool_path

    run_runtime_cli \
        PATH="$HOSTILE_BIN:${PATH:-/usr/bin:/bin}" \
        MAINFRAME_HOSTILE_TOOL_LOG="$HOSTILE_TOOL_LOG" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run

    [[ "$status" -eq 0 ]]
    [[ -f "$LOG_FILE" ]]
    [[ ! -e "$HOSTILE_TOOL_LOG" ]]
}

@test "release-owned uninstall ignores caller PATH tr jq and hash shims" {
    write_release_receipt
    make_hostile_tool_path

    run_runtime_cli \
        PATH="$HOSTILE_BIN:${PATH:-/usr/bin:/bin}" \
        MAINFRAME_HOSTILE_TOOL_LOG="$HOSTILE_TOOL_LOG" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run

    [[ "$status" -eq 0 ]]
    [[ -f "$LOG_FILE" ]]
    [[ ! -e "$HOSTILE_TOOL_LOG" ]]
}

@test "uninstall refuses Homebrew ownership with the exact package-manager command" {
    run_runtime_cli \
        MAINFRAME_INSTALL_METHOD=homebrew \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"MAINFRAME is managed by Homebrew."* ]]
    [[ "$output" == *"deactivate MAINFRAME in every onboarded project"* ]]
    [[ "$output" == *"mainframe deactivate HOST --project . --enforce"* ]]
    [[ "$output" == *"mainframe pi remove --dry-run"* ]]
    [[ "$output" == *"mainframe pi remove --yes"* ]]
    [[ "$output" == *"brew uninstall gtwatts/mainframe/mainframe"* ]]
    [[ "$output" == *"direct uninstall can strand project hooks or a Pi package path"* ]]
    [[ ! -e "$LOG_FILE" ]]
}

@test "uninstall fails closed when any Pi lifecycle payload file is missing" {
    local missing
    commit_source_fixture

    for missing in \
        package.json \
        lib/pi.sh \
        skills/pi/SKILL.md \
        skills/pi/extensions/mainframe.ts; do
        write_complete_pi_payload
        rm -f -- "$RUNTIME_ROOT/$missing" "$LOG_FILE"

        run_runtime_cli \
            "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run

        [[ "$status" -eq 77 ]]
        [[ "$output" == *"Pi lifecycle payload is incomplete"* ]]
        [[ "$output" == *"$RUNTIME_ROOT/$missing"* ]]
        [[ ! -e "$LOG_FILE" ]]
    done
}

@test "Homebrew lifecycle marker fails closed when the entire Pi payload is missing" {
    run_runtime_cli \
        MAINFRAME_INSTALL_METHOD=homebrew \
        MAINFRAME_PI_LIFECYCLE_REQUIRED=1 \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run

    [[ "$status" -eq 77 ]]
    [[ "$output" == *"Pi lifecycle payload is incomplete"* ]]
    [[ "$output" == *"$RUNTIME_ROOT/package.json"* ]]
    [[ "$output" == *"$RUNTIME_ROOT/lib/pi.sh"* ]]
    [[ ! -e "$LOG_FILE" ]]
}

@test "uninstall refuses a missing non-regular or symbolic-linked uninstaller" {
    commit_source_fixture
    rm "$RUNTIME_ROOT/uninstall.sh"

    run_runtime_cli "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"trusted MAINFRAME uninstaller is missing"* ]]

    mkdir "$RUNTIME_ROOT/uninstall.sh"
    run_runtime_cli "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"must be a regular file"* ]]

    rmdir "$RUNTIME_ROOT/uninstall.sh"
    printf 'replacement\n' > "$TEST_DIR/replacement-uninstaller"
    ln -s "$TEST_DIR/replacement-uninstaller" "$RUNTIME_ROOT/uninstall.sh"
    run_runtime_cli "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"must not be a symbolic link"* ]]
    [[ ! -e "$LOG_FILE" ]]
}

@test "uninstall refuses an uninstaller not owned by the source or release metadata" {
    commit_source_fixture
    printf '\n# local replacement\n' >> "$RUNTIME_ROOT/uninstall.sh"

    run_runtime_cli "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"not owned by this source checkout"* ]]
    [[ ! -e "$LOG_FILE" ]]

    rm -rf "$RUNTIME_ROOT/.git"
    write_stub_uninstaller
    write_release_receipt
    printf '\n# post-receipt replacement\n' >> "$RUNTIME_ROOT/uninstall.sh"

    run_runtime_cli "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" uninstall --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"not owned by this verified release"* ]]
    [[ ! -e "$LOG_FILE" ]]
}

@test "bash and zsh completions expose the same uninstall options" {
    local expected bash_options zsh_options
    expected="$(printf '%s\n' \
        --bin --dir --dry-run --help --purge --purge-state --shell-config -h |
        LC_ALL=C sort -u)"

    bash_options="$(bash -c '
        source "$1"
        COMP_WORDS=(mainframe uninstall "")
        COMP_CWORD=2
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u)"
    [[ "$bash_options" == "$expected" ]]

    if command -v zsh >/dev/null 2>&1; then
        zsh_options="$(zsh -f -c '
            compdef() { :; }
            _arguments() {
                local spec
                for spec in "$@"; do
                    [[ "$spec" == \(*\)* ]] && spec="${spec#*)}"
                    print -r -- "${spec%%\[*}"
                done
            }
            source "$1"
            words=(mainframe uninstall "")
            CURRENT=3
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u)"
        [[ "$zsh_options" == "$expected" ]]
    fi
}

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-bootstrap-release.XXXXXX")"
    TEST_TMPDIR="$(cd "$TEST_TMPDIR" && pwd -P)"
    TEST_HOME="$TEST_TMPDIR/home"
    RELEASE_ROOT="$TEST_TMPDIR/releases"
    INSTALL_DIR="$TEST_HOME/.mainframe"
    BIN_DIR="$TEST_HOME/.local/bin"
    INSTALLER_LOG="$TEST_TMPDIR/installer.log"
    GIT_LOG="$TEST_TMPDIR/git.log"
    FAKE_BIN="$TEST_TMPDIR/fake-bin"
    JOURNAL_DIR="$TEST_HOME/..mainframe.bootstrap-journal"
    LOCK_FILE="$TEST_HOME/..mainframe.install.lock"
    LATEST_METADATA="$TEST_TMPDIR/latest-release.json"
    RELEASE_VERSION=10.2.3
    ASSET_NAME="mainframe-${RELEASE_VERSION}.tar.gz"

    mkdir -p "$TEST_HOME" "$BIN_DIR" "$FAKE_BIN"
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
    is_modern_bash "$MODERN_BASH" || skip "Bash 4.4+ is required for delegated installer tests"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "git invoked: %s\n" "$*" >> "${GIT_LOG:?}"' \
        'exit 97' \
        > "$FAKE_BIN/git"
    chmod +x "$FAKE_BIN/git"
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

sha256_digest() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    fi
}

create_valid_release() {
    local payload="$TEST_TMPDIR/payload"
    local release_dir="$RELEASE_ROOT/v$RELEASE_VERSION"
    local archive="$release_dir/$ASSET_NAME"
    local digest

    rm -rf -- "$payload"
    mkdir -p "$payload/bin" "$payload/lib" "$payload/scripts" "$release_dir"
    printf '%s\n' "$RELEASE_VERSION" > "$payload/VERSION"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -eu' \
        'printf "installer executed\n" >> "${INSTALLER_LOG:?}"' \
        'printf "arg=%s\n" "$@" >> "${INSTALLER_LOG:?}"' \
        'optional_pass=true' \
        'for argument in "$@"; do [[ "$argument" == "--no-shell" ]] && optional_pass=false; done' \
        'if [[ "${FIXTURE_OPTIONAL_FAIL:-0}" == "1" && "$optional_pass" == "true" ]]; then exit 42; fi' \
        'mkdir -p "${MAINFRAME_BIN_DIR:?}"' \
        'if [[ -L "$MAINFRAME_BIN_DIR/mainframe" ]]; then' \
        '  [[ "$(readlink "$MAINFRAME_BIN_DIR/mainframe")" == "$MAINFRAME_INSTALL_DIR/bin/mainframe" ]]' \
        'else' \
        '  ln -s "$MAINFRAME_INSTALL_DIR/bin/mainframe" "$MAINFRAME_BIN_DIR/mainframe"' \
        'fi' \
        > "$payload/install.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'root="$(cd "$(dirname "$0")/.." && pwd -P)"' \
        'case "${1:-}" in' \
        '  version)' \
        '    printf "MAINFRAME v%s\n" "$(< "$(dirname "$0")/../VERSION")"' \
        '    if [[ "${FIXTURE_VERSION_TRAILING_LINES:-0}" == "1" ]]; then' \
        '      for ((line = 0; line < 20000; line++)); do printf "diagnostic trailing line %s\n" "$line"; done' \
        '    fi' \
        '    ;;' \
        '  doctor)' \
        '    if [[ "${FIXTURE_SWAP_ROOT:-0}" == "1" ]]; then' \
        '      /bin/mv "$root" "$root.original"' \
        '      mkdir -p "$root"' \
        '      printf "user replacement\n" > "$root/user-owned"' \
        '      exit 1' \
        '    fi' \
        '    [[ "${FIXTURE_DOCTOR_FAIL:-0}" != "1" ]]' \
        '    ;;' \
        '  *) printf "fixture mainframe\n" ;;' \
        'esac' \
        > "$payload/bin/mainframe"
    printf '%s\n' '# fixture common library' > "$payload/lib/common.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$payload/get-mainframe.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$payload/scripts/upgrade-release.sh"
    chmod +x "$payload/install.sh" "$payload/bin/mainframe" "$payload/scripts/upgrade-release.sh"

    (
        cd "$payload"
        for file in VERSION bin/mainframe get-mainframe.sh install.sh lib/common.sh scripts/upgrade-release.sh; do
            printf '%s  %s\n' "$(sha256_digest "$file")" "$file"
        done
    ) > "$payload/SHA256SUMS"

    (
        cd "$payload"
        COPYFILE_DISABLE=1 tar -czf "$archive" \
            VERSION SHA256SUMS bin/mainframe get-mainframe.sh install.sh \
            lib/common.sh scripts/upgrade-release.sh
    )
    digest="$(sha256_digest "$archive")"
    printf '%s  %s\n' "$digest" "$ASSET_NAME" > "$archive.sha256"
}

write_latest_metadata() {
    local archive="$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME"
    local checksum="$archive.sha256"
    local archive_digest checksum_digest release_url

    archive_digest="$(sha256_digest "$archive")"
    checksum_digest="$(sha256_digest "$checksum")"
    release_url="file://$RELEASE_ROOT/v$RELEASE_VERSION"
    jq -n \
        --arg tag "v$RELEASE_VERSION" \
        --arg archive_name "$ASSET_NAME" \
        --arg archive_url "$release_url/$ASSET_NAME" \
        --arg archive_digest "sha256:$archive_digest" \
        --arg checksum_name "$ASSET_NAME.sha256" \
        --arg checksum_url "$release_url/$ASSET_NAME.sha256" \
        --arg checksum_digest "sha256:$checksum_digest" \
        '{
          tag_name: $tag,
          draft: false,
          prerelease: false,
          immutable: true,
          assets: [
            {name: $archive_name, state: "uploaded",
             browser_download_url: $archive_url, digest: $archive_digest},
            {name: $checksum_name, state: "uploaded",
             browser_download_url: $checksum_url, digest: $checksum_digest}
          ]
        }' > "$LATEST_METADATA"
}

create_valid_latest_release() {
    create_valid_release
    write_latest_metadata
}

repack_payload() {
    local payload="$TEST_TMPDIR/payload"
    local archive="$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME"
    (
        cd "$payload"
        COPYFILE_DISABLE=1 tar -czf "$archive" \
            VERSION SHA256SUMS bin/mainframe get-mainframe.sh install.sh \
            lib/common.sh scripts/upgrade-release.sh "${@}"
    )
    rewrite_checksum
}

file_mode() {
    local value
    value="$(stat -c '%a' "$1" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-7]{3,4}$ ]]; then printf '%s\n' "$value"; return; fi
    stat -f '%Lp' "$1"
}

rewrite_checksum() {
    local archive="$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME"
    local digest

    digest="$(sha256_digest "$archive")"
    printf '%s  %s\n' "$digest" "$ASSET_NAME" > "$archive.sha256"
}

enable_bootstrap_failpoints() {
    printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$INSTALL_DIR" \
        > "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    chmod 600 "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
}

run_release() {
    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        GIT_LOG="$GIT_LOG" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        FIXTURE_DOCTOR_FAIL="${FIXTURE_DOCTOR_FAIL:-0}" \
        FIXTURE_SWAP_ROOT="${FIXTURE_SWAP_ROOT:-0}" \
        FIXTURE_OPTIONAL_FAIL="${FIXTURE_OPTIONAL_FAIL:-0}" \
        FIXTURE_VERSION_TRAILING_LINES="${FIXTURE_VERSION_TRAILING_LINES:-0}" \
        RACE_TARGET="${RACE_TARGET:-}" \
        MAINFRAME_BOOTSTRAP_FAILPOINT="${MAINFRAME_BOOTSTRAP_FAILPOINT:-}" \
        MAINFRAME_BOOTSTRAP_INTERNAL_MV="${MAINFRAME_BOOTSTRAP_INTERNAL_MV:-}" \
        MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ="${MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ:-}" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_REPO="file://$TEST_TMPDIR/must-not-clone" \
        MAINFRAME_INSTALLER_URL="file://$TEST_TMPDIR/must-not-download-install-sh" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture "$@"
}

run_latest() {
    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        GIT_LOG="$GIT_LOG" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        FIXTURE_DOCTOR_FAIL="${FIXTURE_DOCTOR_FAIL:-0}" \
        FIXTURE_SWAP_ROOT="${FIXTURE_SWAP_ROOT:-0}" \
        FIXTURE_OPTIONAL_FAIL="${FIXTURE_OPTIONAL_FAIL:-0}" \
        FIXTURE_VERSION_TRAILING_LINES="${FIXTURE_VERSION_TRAILING_LINES:-0}" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_LATEST_RELEASE_API_URL="file://$LATEST_METADATA" \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_REPO="file://$TEST_TMPDIR/must-not-clone" \
        MAINFRAME_INSTALLER_URL="file://$TEST_TMPDIR/must-not-download-install-sh" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture --latest "$@"
}

run_implicit_latest() {
    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        GIT_LOG="$GIT_LOG" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        FIXTURE_DOCTOR_FAIL="${FIXTURE_DOCTOR_FAIL:-0}" \
        FIXTURE_SWAP_ROOT="${FIXTURE_SWAP_ROOT:-0}" \
        FIXTURE_OPTIONAL_FAIL="${FIXTURE_OPTIONAL_FAIL:-0}" \
        FIXTURE_VERSION_TRAILING_LINES="${FIXTURE_VERSION_TRAILING_LINES:-0}" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_LATEST_RELEASE_API_URL="file://$LATEST_METADATA" \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_REPO="file://$TEST_TMPDIR/must-not-clone" \
        MAINFRAME_INSTALLER_URL="file://$TEST_TMPDIR/must-not-download-install-sh" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture "$@"
}

assert_release_failure_is_pre_execution() {
    [[ "$status" -ne 0 ]]
    [[ ! -e "$INSTALLER_LOG" ]]
    [[ ! -e "$GIT_LOG" ]]
    [[ ! -e "$INSTALL_DIR" ]]
}

@test "bootstrap help is native, local, and dependency-free" {
    local flag

    for flag in -h --help; do
        run env \
            HOME="$TEST_HOME" \
            TMPDIR="$TEST_TMPDIR" \
            MAINFRAME_BASH="$TEST_TMPDIR/missing-bash" \
            MAINFRAME_LATEST_RELEASE_API_URL="file://$TEST_TMPDIR/must-not-read" \
            MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
            /bin/bash "$PROJECT_ROOT/get-mainframe.sh" "$flag"

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"MAINFRAME verified bootstrap installer"* ]]
        [[ "$output" == *"Show this local help without downloading anything"* ]]
        [[ "$output" == *"(no selector)"*"immutable stable release"* ]]
        [[ "$output" == *"--legacy-source"*"mutable source installer"* ]]
        [[ "$output" != *"Downloading MAINFRAME"* ]]
        [[ ! -e "$INSTALL_DIR" ]]
        [[ ! -e "$INSTALLER_LOG" ]]
        [[ ! -e "$GIT_LOG" ]]
        [[ -z "$(find "$TEST_TMPDIR" -maxdepth 1 -type d \
            -name 'mainframe-bootstrap.*' -print -quit)" ]]
    done
}

@test "versioned bootstrap verifies, stages, and delegates without invoking git" {
    create_valid_release

    run_release --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Verified SHA-256:"* ]]
    [[ -f "$INSTALL_DIR/VERSION" ]]
    [[ -x "$INSTALL_DIR/bin/mainframe" ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    [[ "$(file_mode "$INSTALL_DIR/.mainframe-install-receipt.json")" == "600" ]]
    jq -e \
        --arg version "$RELEASE_VERSION" \
        --arg install_dir "$INSTALL_DIR" \
        --arg bin_dir "$BIN_DIR" \
        '.schema_version == 1 and .install_method == "release-archive" and
         .version == $version and .install_dir == $install_dir and .bin_dir == $bin_dir and
         .cli_link == ($bin_dir + "/mainframe") and
         (.archive_sha256 | test("^[0-9a-f]{64}$")) and
         (.manifest_sha256 | test("^[0-9a-f]{64}$"))' \
        "$INSTALL_DIR/.mainframe-install-receipt.json" >/dev/null
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$INSTALL_DIR/bin/mainframe" ]]
    grep -Fxq 'installer executed' "$INSTALLER_LOG"
    grep -Fxq 'arg=--no-shell' "$INSTALLER_LOG"
    grep -Fxq 'arg=--no-ai-discovery' "$INSTALLER_LOG"
    [[ ! -e "$GIT_LOG" ]]
}

@test "versioned bootstrap never executes critical dependency shims from caller PATH" {
    local marker="$TEST_TMPDIR/ambient-tool-executed"
    local tool
    create_valid_release
    for tool in curl jq tar sha256sum shasum openssl awk; do
        printf '%s\n' \
            '#!/bin/sh' \
            'printf "%s\n" "$0" >> "${MAINFRAME_TEST_TOOL_MARKER:?}"' \
            'exit 97' \
            > "$FAKE_BIN/$tool"
        chmod 755 "$FAKE_BIN/$tool"
    done

    MAINFRAME_TEST_TOOL_MARKER="$marker" run_release --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
}

@test "bootstrap curl downloads ignore functions and strip proxy CA and TLS environment" {
    local fake_curl="$TEST_TMPDIR/fake-curl"
    local curl_env_log="$TEST_TMPDIR/curl-environment.log"
    local function_marker="$TEST_TMPDIR/curl-function-executed"
    local forbidden
    create_valid_release
    {
        printf '%s\n' '#!/bin/sh'
        printf '/usr/bin/env >> %q\n' "$curl_env_log"
        printf '%s\n' \
            'printf "%s\n" --call-- >> '"$(printf '%q' "$curl_env_log")" \
            'destination=' \
            'source_path=' \
            'while [ "$#" -gt 0 ]; do' \
            '  case "$1" in' \
            '    -o) destination="$2"; shift 2 ;;' \
            '    file://*) source_path="${1#file://}"; shift ;;' \
            '    *) shift ;;' \
            '  esac' \
            'done' \
            '[ -n "$source_path" ] && [ -n "$destination" ] || exit 91' \
            '/bin/cp "$source_path" "$destination"'
    } > "$fake_curl"
    chmod 755 "$fake_curl"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_BOOTSTRAP_INTERNAL_CURL="$fake_curl" \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        MAINFRAME_TEST_CURL_FUNCTION_MARKER="$function_marker" \
        HTTPS_PROXY=http://proxy.invalid:4444 \
        https_proxy=http://proxy.invalid:4444 \
        ALL_PROXY=socks5://proxy.invalid:1080 \
        NO_PROXY=attacker.invalid \
        CURL_CA_BUNDLE="$TEST_TMPDIR/attacker-ca.pem" \
        SSL_CERT_FILE="$TEST_TMPDIR/attacker-cert.pem" \
        SSL_CERT_DIR="$TEST_TMPDIR/attacker-certs" \
        CURL_SSL_BACKEND=attacker-tls \
        'BASH_FUNC_curl%%=() { : > "${MAINFRAME_TEST_CURL_FUNCTION_MARKER:?}"; }' \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ ! -e "$function_marker" ]]
    [[ -s "$curl_env_log" ]]
    grep -Fxq 'HOME=/' "$curl_env_log"
    grep -Fxq 'PATH=/usr/bin:/bin:/usr/sbin:/sbin' "$curl_env_log"
    grep -Fxq 'LC_ALL=C' "$curl_env_log"
    for forbidden in \
        HTTPS_PROXY https_proxy ALL_PROXY NO_PROXY CURL_CA_BUNDLE \
        SSL_CERT_FILE SSL_CERT_DIR CURL_SSL_BACKEND \
        MAINFRAME_BOOTSTRAP_INTERNAL_CURL MAINFRAME_TEST_CURL_FUNCTION_MARKER; do
        ! grep -q "^${forbidden}=" "$curl_env_log"
    done
}

@test "bootstrap source has one closed curl execution boundary and no download bypass" {
    local direct_calls
    direct_calls="$(awk '/^[[:space:]]*"\$bootstrap_curl"[[:space:]]/ { print }' \
        "$PROJECT_ROOT/get-mainframe.sh")"

    [[ "$(wc -l <<< "$direct_calls" | tr -d ' ')" == "1" ]]
    [[ "$direct_calls" == *"--disable --proxy '' --noproxy '*'"* ]]
    [[ "$(grep -c 'bootstrap_curl_download .*fsSL' "$PROJECT_ROOT/get-mainframe.sh")" -ge 5 ]]
}

@test "latest bootstrap resolves one immutable release into the exact versioned path" {
    local archive_digest
    create_valid_latest_release
    archive_digest="$(sha256_digest "$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME")"

    run_latest --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Resolved latest immutable MAINFRAME release: v$RELEASE_VERSION"* ]]
    [[ "$output" == *"Resolved GitHub archive SHA-256: $archive_digest"* ]]
    [[ "$output" == *"retry this exact release with --release-version $RELEASE_VERSION"* ]]
    [[ "$output" == *"Verified SHA-256: $archive_digest"* ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    jq -e --arg version "$RELEASE_VERSION" --arg digest "$archive_digest" \
        '.version == $version and .archive_sha256 == $digest' \
        "$INSTALL_DIR/.mainframe-install-receipt.json" >/dev/null
    grep -Fxq 'arg=--no-shell' "$INSTALLER_LOG"
    grep -Fxq 'arg=--no-ai-discovery' "$INSTALLER_LOG"
    [[ ! -e "$GIT_LOG" ]]
}

@test "selector-free bootstrap uses the immutable latest path" {
    local archive_digest
    create_valid_latest_release
    archive_digest="$(sha256_digest "$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME")"

    run_implicit_latest --no-shell --no-ai-discovery

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Resolved latest immutable MAINFRAME release: v$RELEASE_VERSION"* ]]
    [[ "$output" == *"Verified SHA-256: $archive_digest"* ]]
    [[ "$output" != *"legacy mutable installer URL"* ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    jq -e --arg version "$RELEASE_VERSION" --arg digest "$archive_digest" \
        '.version == $version and .archive_sha256 == $digest' \
        "$INSTALL_DIR/.mainframe-install-receipt.json" >/dev/null
    grep -Fxq 'arg=--no-shell' "$INSTALLER_LOG"
    grep -Fxq 'arg=--no-ai-discovery' "$INSTALLER_LOG"
    [[ ! -e "$GIT_LOG" ]]
}

@test "selector-free latest failure never falls back to mutable source" {
    run_implicit_latest

    assert_release_failure_is_pre_execution
    [[ "$output" == *"latest immutable release metadata could not be downloaded"* ]]
    [[ "$output" != *"legacy mutable installer URL"* ]]
}

@test "legacy-only provenance flags require the explicit legacy selector" {
    local -a arguments=()
    local encoded
    local -a cases=(
        '--repo|https://github.com/gtwatts/mainframe.git'
        '--branch|main'
        '--legacy-installer-url|https://example.invalid/install.sh'
        '--allow-unverified-source'
    )

    for encoded in "${cases[@]}"; do
        IFS='|' read -r -a arguments <<< "$encoded"
        run env \
            HOME="$TEST_HOME" \
            TMPDIR="$TEST_TMPDIR" \
            MAINFRAME_BASH="$TEST_TMPDIR/missing-bash" \
            MAINFRAME_LATEST_RELEASE_API_URL="file://$TEST_TMPDIR/must-not-read" \
            MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
            /bin/bash "$PROJECT_ROOT/get-mainframe.sh" "${arguments[@]}"

        [[ "$status" -eq 2 ]]
        [[ "$output" == *"require --legacy-source"* ]]
        [[ "$output" != *"MAINFRAME_BASH must"* ]]
        [[ "$output" != *"Downloading MAINFRAME"* ]]
        [[ ! -e "$INSTALL_DIR" ]]
        [[ ! -e "$INSTALLER_LOG" ]]
    done
}

@test "legacy source selector rejects release conflicts and malformed forms before network" {
    run env HOME="$TEST_HOME" MAINFRAME_VERSION= \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --legacy-source --latest
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--legacy-source conflicts"* ]]

    run env HOME="$TEST_HOME" MAINFRAME_VERSION= \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" \
        --legacy-source --release-version "$RELEASE_VERSION"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--legacy-source conflicts"* ]]

    run env HOME="$TEST_HOME" MAINFRAME_VERSION="$RELEASE_VERSION" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --legacy-source
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--legacy-source conflicts"* ]]

    run env HOME="$TEST_HOME" MAINFRAME_VERSION= \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --legacy-source --legacy-source
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--legacy-source may be specified only once"* ]]

    run env HOME="$TEST_HOME" MAINFRAME_VERSION= \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --legacy-source=yes
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--legacy-source does not accept a value"* ]]

    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "latest selector conflicts and malformed forms fail before metadata access" {
    run env \
        HOME="$TEST_HOME" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_LATEST_RELEASE_API_URL="file://$TEST_TMPDIR/must-not-be-read" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture --latest
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--latest conflicts with MAINFRAME_VERSION"* ]]

    run_latest --release-version "$RELEASE_VERSION"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--latest conflicts with --release-version"* ]]

    run_latest --latest
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--latest may be specified only once"* ]]

    run_latest --latest=10.2.3
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--latest does not accept a value"* ]]

    run_latest --dir "$TEST_TMPDIR/unsupported"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported versioned-bootstrap option: --dir"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "latest bootstrap rejects mutable prerelease and non-SemVer metadata" {
    create_valid_latest_release
    jq '.immutable = false' "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"not published, stable, and immutable"* ]]

    write_latest_metadata
    jq '.prerelease = true' "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"not published, stable, and immutable"* ]]

    write_latest_metadata
    jq '.tag_name = "v01.2.3"' "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"tag is not stable vMAJOR.MINOR.PATCH"* ]]
}

@test "latest bootstrap requires unique uploaded assets with exact canonical URLs and digests" {
    create_valid_latest_release
    jq '.assets += [.assets[0]]' "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"one exact uploaded archive and checksum asset"* ]]

    write_latest_metadata
    jq '.assets[0].browser_download_url += "?mutable=1"' \
        "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"canonical URLs and GitHub SHA-256 digests"* ]]

    write_latest_metadata
    jq '.assets[1].state = "new"' "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"one exact uploaded archive and checksum asset"* ]]

    write_latest_metadata
    jq '.assets[0].digest = null' "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"GitHub SHA-256 digests"* ]]
}

@test "latest bootstrap binds archive and checksum bytes to both GitHub digests" {
    create_valid_latest_release
    jq '.assets[0].digest = ("sha256:" + ("0" * 64))' \
        "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"archive does not match its GitHub API SHA-256 digest"* ]]

    write_latest_metadata
    jq '.assets[1].digest = ("sha256:" + ("0" * 64))' \
        "$LATEST_METADATA" > "$LATEST_METADATA.tmp"
    mv "$LATEST_METADATA.tmp" "$LATEST_METADATA"
    run_latest
    assert_release_failure_is_pre_execution
    [[ "$output" == *"checksum asset does not match its GitHub API SHA-256 digest"* ]]
}

@test "latest bootstrap requires the API-bound sidecar to name the API-bound archive" {
    local checksum="$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME.sha256"
    create_valid_latest_release
    printf '%064d  %s\n' 0 "$ASSET_NAME" > "$checksum"
    write_latest_metadata

    run_latest

    assert_release_failure_is_pre_execution
    [[ "$output" == *"checksum record does not match the GitHub archive digest"* ]]
}

@test "latest bootstrap permits only canonical production metadata or internal file fixtures" {
    create_valid_latest_release

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_LATEST_RELEASE_API_URL="https://example.invalid/latest" \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture --latest

    assert_release_failure_is_pre_execution
    [[ "$output" == *"custom MAINFRAME_LATEST_RELEASE_API_URL is disabled"* ]]

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_LATEST_RELEASE_API_URL="file://$LATEST_METADATA" \
        MAINFRAME_RELEASE_BASE_URL="https://example.invalid/releases" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --latest

    assert_release_failure_is_pre_execution
    [[ "$output" == *"custom MAINFRAME_RELEASE_BASE_URL is disabled"* ]]
}

@test "latest metadata failure never falls back to the mutable installer" {
    run_latest --no-shell

    assert_release_failure_is_pre_execution
    [[ "$output" == *"latest immutable release metadata could not be downloaded"* ]]
    [[ "$output" == *"--release-version X.Y.Z"* ]]
}

@test "version verification consumes trailing output without a pipefail SIGPIPE" {
    create_valid_release
    FIXTURE_VERSION_TRAILING_LINES=1

    run_release --no-shell

    [[ "$status" -eq 0 ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
}

@test "release version option is consumed and validated before download" {
    create_valid_release

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture \
        --release-version "$RELEASE_VERSION" --no-shell

    [[ "$status" -eq 0 ]]
    grep -Fxq 'arg=--no-shell' "$INSTALLER_LOG"
    ! grep -q -- '--release-version' "$INSTALLER_LOG"

    rm -rf -- "$INSTALL_DIR"
    : > "$INSTALLER_LOG"
    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$TEST_TMPDIR/should-not-be-read" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --release-version '../latest'

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"must be stable SemVer"* ]]
    [[ ! -s "$INSTALLER_LOG" ]]
    [[ ! -e "$INSTALL_DIR" ]]
}

@test "corrupt release archive fails checksum before extraction or installer execution" {
    create_valid_release
    printf 'tampered\n' >> "$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME"

    run_release

    assert_release_failure_is_pre_execution
    [[ "$output" == *"SHA-256 verification failed"* ]]
}

@test "missing release checksum fails closed before target creation" {
    create_valid_release
    rm -f -- "$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME.sha256"

    run_release

    assert_release_failure_is_pre_execution
}

@test "missing jq fails before download and leaves the target untouched" {
    enable_bootstrap_failpoints

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$TEST_TMPDIR/must-not-download" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"jq is required for a safety-ready MAINFRAME installation"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "checksum must be one lowercase SHA-256 record for the exact asset" {
    local checksum="$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME.sha256"
    local digest uppercase_digest
    create_valid_release
    digest="$(sha256_digest "$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME")"

    printf '%s  different.tar.gz\n' "$digest" > "$checksum"
    run_release
    assert_release_failure_is_pre_execution
    [[ "$output" == *"does not name the exact asset"* ]]

    uppercase_digest="$(printf '%s' "$digest" | tr '[:lower:]' '[:upper:]')"
    printf '%s  %s\n' "$uppercase_digest" "$ASSET_NAME" > "$checksum"
    run_release
    assert_release_failure_is_pre_execution
    [[ "$output" == *"not a lowercase SHA-256 record"* ]]

    printf '%s  %s\n%s  %s\n' "$digest" "$ASSET_NAME" "$digest" "$ASSET_NAME" > "$checksum"
    run_release
    assert_release_failure_is_pre_execution
    [[ "$output" == *"exactly one record"* ]]
}

@test "archive traversal member is rejected before extraction" {
    local payload="$TEST_TMPDIR/payload"
    local archive="$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME"
    create_valid_release

    if tar --version 2>/dev/null | grep -q 'GNU tar'; then
        (
            cd "$payload"
            tar -czf "$archive" \
                --transform='s|^install\.sh$|../install.sh|' \
                VERSION install.sh bin/mainframe
        )
    else
        (
            cd "$payload"
            COPYFILE_DISABLE=1 tar -czf "$archive" \
                -s ',^install\.sh$,../install.sh,' \
                VERSION install.sh bin/mainframe
        )
    fi
    rewrite_checksum

    run_release

    assert_release_failure_is_pre_execution
    [[ "$output" == *"unsafe member path"* ]]
}

@test "archive links are rejected before extraction" {
    local payload="$TEST_TMPDIR/payload"
    local archive="$RELEASE_ROOT/v$RELEASE_VERSION/$ASSET_NAME"
    create_valid_release
    ln -s ../../outside "$payload/escape-link"
    (
        cd "$payload"
        COPYFILE_DISABLE=1 tar -czf "$archive" VERSION install.sh bin/mainframe escape-link
    )
    rewrite_checksum

    run_release

    assert_release_failure_is_pre_execution
    [[ "$output" == *"links and special entries are not allowed"* ]]
}

@test "tampered inner payload fails its manifest before installer execution" {
    create_valid_release
    printf 'tampered\n' >> "$TEST_TMPDIR/payload/bin/mainframe"
    repack_payload

    run_release

    assert_release_failure_is_pre_execution
    [[ "$output" == *"payload checksum mismatch: bin/mainframe"* ]]
}

@test "duplicate inner manifest path fails before installer execution" {
    local duplicate_record
    create_valid_release
    duplicate_record="$(grep '  VERSION$' "$TEST_TMPDIR/payload/SHA256SUMS")"
    printf '%s\n' "$duplicate_record" >> "$TEST_TMPDIR/payload/SHA256SUMS"
    repack_payload

    run_release

    assert_release_failure_is_pre_execution
    [[ "$output" == *"duplicate SHA256SUMS path"* ]]
}

@test "unmanifested inner payload file fails before installer execution" {
    create_valid_release
    printf 'not inventoried\n' > "$TEST_TMPDIR/payload/extra.txt"
    repack_payload extra.txt

    run_release

    assert_release_failure_is_pre_execution
    [[ "$output" == *"absent from SHA256SUMS: extra.txt"* ]]
}

@test "archive-supplied install receipt is rejected before extraction" {
    create_valid_release
    printf '{}\n' > "$TEST_TMPDIR/payload/.mainframe-install-receipt.json"
    repack_payload .mainframe-install-receipt.json

    run_release

    assert_release_failure_is_pre_execution
    [[ "$output" == *"must not contain a machine-local install receipt"* ]]
}

@test "release receipt is withheld when installed doctor fails" {
    local failed_payload
    create_valid_release
    FIXTURE_DOCTOR_FAIL=1

    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed its doctor check; no release receipt was written"* ]]
    [[ "$output" == *"Incomplete release was deactivated and retained"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$BIN_DIR/mainframe" ]]
    failed_payload="$(find "$TEST_HOME" -path '*/.mainframe-failed-install.*/payload' -type d -print -quit)"
    [[ -n "$failed_payload" ]]
    [[ ! -e "$failed_payload/.mainframe-install-receipt.json" ]]
    grep -Fxq 'installer executed' "$INSTALLER_LOG"
}

@test "failure cleanup never moves a substituted install-root directory" {
    create_valid_release
    FIXTURE_SWAP_ROOT=1

    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed its doctor check"* ]]
    [[ -f "$INSTALL_DIR/user-owned" ]]
    [[ "$(< "$INSTALL_DIR/user-owned")" == "user replacement" ]]
    [[ -d "$INSTALL_DIR.original" ]]
    [[ ! -e "$BIN_DIR/mainframe" ]]
    [[ -z "$(find "$TEST_HOME" -path '*/.mainframe-failed-install.*/payload' -print -quit)" ]]
}

@test "versioned bootstrap rejects installer location overrides before download" {
    run_release --dir "$TEST_TMPDIR/other-root"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported versioned-bootstrap option: --dir"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "final-placement race cannot execute a substituted target" {
    create_valid_release
    enable_bootstrap_failpoints
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "${2:-}" == "${RACE_TARGET:-}" && "$1" == *mainframe-release-stage* ]]; then' \
        '  mkdir -p "$2"' \
        '  printf "user target\n" > "$2/user-owned"' \
        '  printf "#!/usr/bin/env bash\nprintf malicious-executed > \"${INSTALLER_LOG:?}\"\n" > "$2/install.sh"' \
        '  chmod +x "$2/install.sh"' \
        'fi' \
        'exec /bin/mv "$@"' \
        > "$FAKE_BIN/mv"
    chmod +x "$FAKE_BIN/mv"
    RACE_TARGET="$INSTALL_DIR"
    MAINFRAME_BOOTSTRAP_INTERNAL_MV="$FAKE_BIN/mv"

    run_release

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"install target changed during final placement; no payload code was executed"* ]]
    [[ -f "$INSTALL_DIR/user-owned" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
    [[ ! -e "$GIT_LOG" ]]
}

@test "versioned bootstrap refuses a nonempty target without changing it" {
    create_valid_release
    mkdir -p "$INSTALL_DIR"
    printf 'user owned\n' > "$INSTALL_DIR/keep.txt"

    run_release

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"will not overwrite a nonempty target"* ]]
    grep -Fxq 'user owned' "$INSTALL_DIR/keep.txt"
    [[ ! -e "$INSTALLER_LOG" ]]
    [[ ! -e "$GIT_LOG" ]]
}

@test "versioned bootstrap blocks local release sources outside internal verification" {
    create_valid_release

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=0 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"file:// release assets are disabled outside internal verification"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "internal-testing environment plus a forgeable HOME marker cannot authorize a local release source" {
    create_valid_release

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"file:// release assets are disabled outside internal verification"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "production versioned bootstrap rejects a custom HTTPS release origin before download" {
    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=0 \
        MAINFRAME_RELEASE_BASE_URL="https://releases.example.invalid/mainframe" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"custom MAINFRAME_RELEASE_BASE_URL is disabled outside internal verification"* ]]
    [[ "$output" == *"github.com/gtwatts/mainframe/releases/download"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "physical HOME identity blocks a symlinked HOME from becoming the install target" {
    local linked_home="$TEST_TMPDIR/linked-home"
    create_valid_release
    # This case intentionally targets HOME itself rather than the default
    # $HOME/.mainframe. Authenticate that exact private fixture so the local
    # release gate does not mask the physical-HOME safety assertion below.
    printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$TEST_HOME" \
        > "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    chmod 600 "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    ln -s "$TEST_HOME" "$linked_home"

    run env \
        HOME="$linked_home" \
        TMPDIR="$TEST_TMPDIR" \
        PATH="$FAKE_BIN:$PATH" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$TEST_HOME" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing unsafe MAINFRAME_INSTALL_DIR: $TEST_HOME"* ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "bootstrap failpoints require an exact private fixture marker" {
    local probe="$TEST_TMPDIR/probe-bootstrap-failpoint-auth.sh"
    rm -f "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    sed -n '/^portable_mode()/,/^}/p' "$PROJECT_ROOT/get-mainframe.sh" > "$probe"
    sed -n '/^single_line_value()/,/^}/p' "$PROJECT_ROOT/get-mainframe.sh" >> "$probe"
    sed -n '/^bootstrap_failpoint_is_authorized()/,/^}/p' \
        "$PROJECT_ROOT/get-mainframe.sh" >> "$probe"
    printf '%s\n' \
        'resolved_install_dir="$1"' \
        'bootstrap_failpoint_is_authorized' >> "$probe"

    run env HOME="$TEST_HOME" MAINFRAME_INTERNAL_TESTING=1 \
        /bin/bash "$probe" "$INSTALL_DIR"

    [[ "$status" -eq 1 ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
    [[ ! -e "$JOURNAL_DIR" ]]
}

@test "bootstrap internal tool overrides require the private fixture marker" {
    local marker="$TEST_TMPDIR/unauthorized-tool-executed"
    create_valid_release
    rm -f "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "executed\n" > "${MAINFRAME_TEST_TOOL_MARKER:?}"' \
        'exit 97' \
        > "$FAKE_BIN/internal-mv"
    chmod 755 "$FAKE_BIN/internal-mv"
    MAINFRAME_BOOTSTRAP_INTERNAL_MV="$FAKE_BIN/internal-mv"
    MAINFRAME_TEST_TOOL_MARKER="$marker"

    run_release --no-shell

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"tool overrides are disabled outside a private authenticated fixture"* ]]
    [[ ! -e "$marker" ]]
    [[ ! -e "$INSTALL_DIR" ]]

    MAINFRAME_BOOTSTRAP_INTERNAL_MV=""
    MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ=1
    run_release --no-shell
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"dependency test controls are disabled outside a private authenticated fixture"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
}

@test "bootstrap internal controls require the same-command fixture capability" {
    create_valid_release

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION="$RELEASE_VERSION" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --no-shell

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"dependency test controls are disabled outside a private authenticated fixture"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "SIGKILL after final placement resumes only the journaled payload" {
    local installer_count staged_cli_dir
    create_valid_release
    enable_bootstrap_failpoints
    MAINFRAME_BOOTSTRAP_FAILPOINT=kill-after-placement

    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ -d "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    [[ ! -e "$BIN_DIR/mainframe" && ! -L "$BIN_DIR/mainframe" ]]
    [[ -d "$JOURNAL_DIR" ]]
    [[ "$(file_mode "$JOURNAL_DIR")" == "700" ]]
    [[ "$(file_mode "$JOURNAL_DIR/record.json")" == "600" ]]
    staged_cli_dir="$(jq -r '.cli_stage_dir' "$JOURNAL_DIR/record.json")"
    [[ -L "$staged_cli_dir/mainframe" ]]
    [[ -f "$LOCK_FILE" ]]

    MAINFRAME_BOOTSTRAP_FAILPOINT=
    run_release --no-shell

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Resuming exact verified MAINFRAME"* ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ ! -e "$JOURNAL_DIR" ]]
    [[ ! -e "$LOCK_FILE" ]]
    installer_count="$(grep -c '^installer executed$' "$INSTALLER_LOG")"
    [[ "$installer_count" -eq 1 ]]
}

@test "SIGKILL after the core installer resumes a receiptless exact CLI identity" {
    local installer_count recorded_cli_identity
    create_valid_release
    enable_bootstrap_failpoints
    MAINFRAME_BOOTSTRAP_FAILPOINT=kill-after-core-installer

    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ -d "$INSTALL_DIR" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ ! -e "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    [[ -d "$JOURNAL_DIR" ]]
    recorded_cli_identity="$(jq -r '.cli_identity' "$JOURNAL_DIR/record.json")"
    [[ -n "$recorded_cli_identity" ]]

    MAINFRAME_BOOTSTRAP_FAILPOINT=
    run_release --no-shell

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Resuming exact verified MAINFRAME"* ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ ! -e "$JOURNAL_DIR" ]]
    [[ ! -e "$LOCK_FILE" ]]
    installer_count="$(grep -c '^installer executed$' "$INSTALLER_LOG")"
    [[ "$installer_count" -eq 2 ]]
}

@test "interrupted bootstrap never adopts a replacement at the recorded install path" {
    local interrupted_root="$TEST_TMPDIR/interrupted-root"
    create_valid_release
    enable_bootstrap_failpoints
    MAINFRAME_BOOTSTRAP_FAILPOINT=kill-after-placement
    run_release --no-shell
    [[ "$status" -ne 0 ]]

    mv "$INSTALL_DIR" "$interrupted_root"
    mkdir "$INSTALL_DIR"
    printf 'user replacement\n' > "$INSTALL_DIR/user-owned"
    MAINFRAME_BOOTSTRAP_FAILPOINT=
    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"recorded bootstrap payload identity no longer matches"* ]]
    [[ "$(< "$INSTALL_DIR/user-owned")" == "user replacement" ]]
    [[ -d "$interrupted_root" ]]
    [[ -d "$JOURNAL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "interrupted bootstrap rejects a same-target CLI link with a replacement inode" {
    local installer_count
    create_valid_release
    enable_bootstrap_failpoints
    MAINFRAME_BOOTSTRAP_FAILPOINT=kill-after-core-installer
    run_release --no-shell
    [[ "$status" -ne 0 ]]

    rm "$BIN_DIR/mainframe"
    ln -s "$INSTALL_DIR/bin/mainframe" "$BIN_DIR/mainframe"
    MAINFRAME_BOOTSTRAP_FAILPOINT=
    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"CLI path was replaced after the interrupted bootstrap"* ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$INSTALL_DIR/bin/mainframe" ]]
    [[ -d "$INSTALL_DIR" ]]
    [[ -d "$JOURNAL_DIR" ]]
    installer_count="$(grep -c '^installer executed$' "$INSTALLER_LOG")"
    [[ "$installer_count" -eq 1 ]]
}

@test "interrupted bootstrap payload remains bound to the newly verified archive manifest" {
    local manifest_sha record_tmp
    create_valid_release
    enable_bootstrap_failpoints
    MAINFRAME_BOOTSTRAP_FAILPOINT=kill-after-placement
    run_release --no-shell
    [[ "$status" -ne 0 ]]

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "substituted installer executed\n" > "${INSTALLER_LOG:?}"' \
        > "$INSTALL_DIR/install.sh"
    chmod +x "$INSTALL_DIR/install.sh"
    (
        cd "$INSTALL_DIR"
        for file in VERSION bin/mainframe get-mainframe.sh install.sh lib/common.sh scripts/upgrade-release.sh; do
            printf '%s  %s\n' "$(sha256_digest "$file")" "$file"
        done
    ) > "$INSTALL_DIR/SHA256SUMS"
    manifest_sha="$(sha256_digest "$INSTALL_DIR/SHA256SUMS")"
    record_tmp="$JOURNAL_DIR/record.replacement"
    jq --arg manifest_sha "$manifest_sha" '.manifest_sha256 = $manifest_sha' \
        "$JOURNAL_DIR/record.json" > "$record_tmp"
    chmod 600 "$record_tmp"
    mv "$record_tmp" "$JOURNAL_DIR/record.json"

    MAINFRAME_BOOTSTRAP_FAILPOINT=
    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"recovery record does not match this exact release request"* ]]
    [[ ! -e "$INSTALLER_LOG" ]]
    [[ -d "$INSTALL_DIR" ]]
    [[ -d "$JOURNAL_DIR" ]]
}

@test "optional installer failure reports receipt-backed partial success and exact retry" {
    local installer_count
    create_valid_release
    FIXTURE_OPTIONAL_FAIL=1

    run_release

    [[ "$status" -eq 42 ]]
    [[ "$output" == *"optional shell/discovery setup failed with status 42"* ]]
    [[ "$output" == *"Core MAINFRAME v$RELEASE_VERSION installation succeeded and remains receipt-backed"* ]]
    [[ "$output" == *"Retry only the optional setup with this exact command"* ]]
    [[ "$output" == *"$INSTALL_DIR/install.sh"* ]]
    [[ -f "$INSTALL_DIR/.mainframe-install-receipt.json" ]]
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ ! -e "$JOURNAL_DIR" ]]
    installer_count="$(grep -c '^installer executed$' "$INSTALLER_LOG")"
    [[ "$installer_count" -eq 2 ]]
}

@test "versioned bootstrap lock rejects directories and live owners" {
    local lock="$TEST_HOME/..mainframe.install.lock"
    create_valid_release
    mkdir "$lock"

    run_release --no-shell

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"did not create the exact regular lock path"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]

    rm -rf -- "$lock"
    printf '%s\n' "$$" > "$lock"
    chmod 600 "$lock"
    run_release --no-shell
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"another versioned install is running"* ]]
    [[ "$output" == *"$$"* ]]
    [[ ! -e "$INSTALL_DIR" ]]
    [[ ! -e "$INSTALLER_LOG" ]]
}

@test "legacy mutable installer URL remains available with an explicit warning" {
    local legacy_installer="$TEST_TMPDIR/legacy-install.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "legacy executed\n" > "${INSTALLER_LOG:?}"' \
        > "$legacy_installer"
    chmod +x "$legacy_installer"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        INSTALLER_LOG="$INSTALLER_LOG" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" \
        --internal-test-fixture --legacy-source \
        --legacy-installer-url "file://$legacy_installer" \
        --repo "https://github.com/gtwatts/mainframe.git" --branch main \
        --allow-unverified-source

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"legacy mutable installer URL"* ]]
    grep -Fxq 'legacy executed' "$INSTALLER_LOG"
}

@test "inherited legacy provenance cannot divert the selector-free latest path" {
    local legacy_installer="$TEST_TMPDIR/inherited-legacy-install.sh"
    local marker="$TEST_TMPDIR/inherited-legacy-executed"
    printf '%s\n' \
        '#!/bin/sh' \
        ': > "${MAINFRAME_TEST_LEGACY_MARKER:?}"' \
        > "$legacy_installer"
    chmod 755 "$legacy_installer"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_TMPDIR" \
        MAINFRAME_BASH="$MODERN_BASH" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_INSTALLER_URL="file://$legacy_installer" \
        MAINFRAME_REPO="file://$TEST_TMPDIR/inherited-repository" \
        MAINFRAME_BRANCH=attacker-branch \
        MAINFRAME_LATEST_RELEASE_API_URL="file://$TEST_TMPDIR/missing-latest.json" \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_TEST_LEGACY_MARKER="$marker" \
        /bin/bash "$PROJECT_ROOT/get-mainframe.sh" --internal-test-fixture

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"latest immutable release metadata could not be downloaded"* ]]
    [[ "$output" != *"legacy mutable installer URL"* ]]
    [[ ! -e "$marker" ]]
    [[ ! -e "$INSTALL_DIR" ]]
}

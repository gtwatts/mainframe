#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-upgrade-release.XXXXXX")"
    TEST_TMPDIR="$(cd "$TEST_TMPDIR" && pwd -P)"
    TEST_HOME="$TEST_TMPDIR/home"
    INSTALL_ROOT="$TEST_HOME/.mainframe"
    BIN_DIR="$TEST_HOME/.local/bin"
    RELEASE_ROOT="$TEST_TMPDIR/releases"
    CURRENT_VERSION=10.2.0
    TARGET_VERSION=10.3.0

    MODERN_BASH="${MAINFRAME_BASH:-${BASH:-}}"
    if ! is_modern_bash "$MODERN_BASH"; then
        for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash; do
            if is_modern_bash "$candidate"; then
                MODERN_BASH="$candidate"
                break
            fi
        done
    fi
    is_modern_bash "$MODERN_BASH" || skip "Bash 4.4+ is required"

    mkdir -p "$TEST_HOME" "$BIN_DIR" "$RELEASE_ROOT"
    create_runtime "$INSTALL_ROOT" "$CURRENT_VERSION"
    printf 'MAINFRAME_INTERNAL_TESTING:%s\n' "$INSTALL_ROOT" \
        > "$INSTALL_ROOT/.mainframe-internal-test-mode"
    chmod 600 "$INSTALL_ROOT/.mainframe-internal-test-mode"
    generate_manifest "$INSTALL_ROOT"
    ln -s "$INSTALL_ROOT/bin/mainframe" "$BIN_DIR/mainframe"
    write_fixture_receipt "$INSTALL_ROOT" "$CURRENT_VERSION" "$BIN_DIR"

    mkdir -p "$INSTALL_ROOT/awm/sessions" "$INSTALL_ROOT/cache" \
        "$INSTALL_ROOT/tasks" "$INSTALL_ROOT/user-notes"
    printf 'nonce-keep-me\n' > "$INSTALL_ROOT/awm/sessions/current.json"
    printf 'cached\n' > "$INSTALL_ROOT/cache/index"
    printf 'in-progress\n' > "$INSTALL_ROOT/tasks/active"
    printf 'spaces survive\n' > "$INSTALL_ROOT/user-notes/odd name.txt"
    chmod 700 "$INSTALL_ROOT/awm" "$INSTALL_ROOT/awm/sessions"
    chmod 640 "$INSTALL_ROOT/awm/sessions/current.json"
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

file_mode() {
    local value
    value="$(stat -c '%a' "$1" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-7]{3,4}$ ]]; then printf '%s\n' "$value"; return; fi
    stat -f '%Lp' "$1"
}

generate_manifest() {
    local root="$1" file
    (
        cd "$root"
        find . -type f \
            ! -name SHA256SUMS \
            ! -name .mainframe-install-receipt.json \
            -print | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r file; do
                printf '%s  %s\n' "$(sha256_digest "$file")" "$file"
            done
    ) > "$root/SHA256SUMS"
}

create_runtime() {
    local root="$1" version="$2"
    rm -rf -- "$root"
    mkdir -p "$root/bin" "$root/lib" "$root/scripts"
    chmod 700 "$root"
    printf '%s\n' "$version" > "$root/VERSION"
    printf '%s\n' '# fixture common library' > "$root/lib/common.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$root/install.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$root/get-mainframe.sh"
    cp "$PROJECT_ROOT/scripts/upgrade-release.sh" "$root/scripts/upgrade-release.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -eu' \
        'root="$(cd "$(dirname "$0")/.." && pwd -P)"' \
        'if [[ -n "${FIXTURE_EXEC_LOG:-}" && "${FIXTURE_EXEC_VERSION:-}" == "$(< "$root/VERSION")" ]]; then' \
        '  printf "exec:%s:%s\n" "$(< "$root/VERSION")" "${1:-}" >> "$FIXTURE_EXEC_LOG"' \
        'fi' \
        'case "${1:-}" in' \
        '  version)' \
        '    printf "MAINFRAME v%s\n" "$(< "$root/VERSION")"' \
        '    if [[ "${FIXTURE_VERSION_DETAIL_LINES:-0}" =~ ^[0-9]+$ ]]; then' \
        '      for ((detail_index = 0; detail_index < ${FIXTURE_VERSION_DETAIL_LINES:-0}; detail_index++)); do' \
        '        printf "version detail %06d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n" "$detail_index"' \
        '      done' \
        '    fi' \
        '    ;;' \
        '  doctor)' \
        '    if [[ "${FIXTURE_DOCTOR_FAIL_VERSION:-}" == "$(< "$root/VERSION")" ]]; then' \
        '      [[ -z "${FIXTURE_DOCTOR_DELAY:-}" ]] || sleep "$FIXTURE_DOCTOR_DELAY"' \
        '      exit 1' \
        '    fi' \
        '    ;;' \
        '  *) exit 64 ;;' \
        'esac' \
        > "$root/bin/mainframe"
    chmod 755 "$root/install.sh" "$root/bin/mainframe" "$root/scripts/upgrade-release.sh"
    generate_manifest "$root"
}

write_fixture_receipt() {
    local root="$1" version="$2" bin_dir="$3" manifest_sha
    manifest_sha="$(sha256_digest "$root/SHA256SUMS")"
    jq -n \
        --arg version "$version" \
        --arg archive_sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
        --arg manifest_sha256 "$manifest_sha" \
        --arg install_dir "$root" \
        --arg bin_dir "$bin_dir" \
        --arg cli_link "$bin_dir/mainframe" \
        '{schema_version: 1, install_method: "release-archive", version: $version,
          archive_sha256: $archive_sha256, manifest_sha256: $manifest_sha256,
          install_dir: $install_dir, bin_dir: $bin_dir, cli_link: $cli_link,
          installed_at: "2026-08-08T12:00:00Z"}' \
        > "$root/.mainframe-install-receipt.json"
    chmod 600 "$root/.mainframe-install-receipt.json"
}

create_release() {
    local version="$1" payload="$TEST_TMPDIR/payload-$1"
    create_runtime "$payload" "$version"
    repack_release "$version"
}

repack_release() {
    local version="$1" payload="$TEST_TMPDIR/payload-$1"
    local release_dir="$RELEASE_ROOT/v$version"
    local asset="mainframe-${version}.tar.gz" archive digest
    archive="$release_dir/$asset"
    mkdir -p "$release_dir"
    (
        cd "$payload"
        COPYFILE_DISABLE=1 tar -czf "$archive" \
            VERSION SHA256SUMS bin/mainframe get-mainframe.sh install.sh \
            lib/common.sh scripts/upgrade-release.sh "${@:2}"
    )
    digest="$(sha256_digest "$archive")"
    printf '%s  %s\n' "$digest" "$asset" > "$archive.sha256"
}

rewrite_release_checksum() {
    local version="$1" archive="$RELEASE_ROOT/v$1/mainframe-$1.tar.gz" digest
    digest="$(sha256_digest "$archive")"
    printf '%s  mainframe-%s.tar.gz\n' "$digest" "$version" > "$archive.sha256"
}

run_upgrade() {
    run env \
        HOME="$TEST_HOME" \
        PATH="${UPGRADE_PATH:-$PATH}" \
        MAINFRAME_ROOT="$INSTALL_ROOT" \
        MAINFRAME_RELEASE_BASE_URL="${UPGRADE_RELEASE_BASE_URL:-file://$RELEASE_ROOT}" \
        MAINFRAME_INTERNAL_TESTING="${MAINFRAME_INTERNAL_TESTING:-1}" \
        MAINFRAME_VERSION="$CURRENT_VERSION" \
        FIXTURE_VERSION_DETAIL_LINES="${FIXTURE_VERSION_DETAIL_LINES:-0}" \
        FIXTURE_DOCTOR_FAIL_VERSION="${FIXTURE_DOCTOR_FAIL_VERSION:-}" \
        FIXTURE_DOCTOR_DELAY="${FIXTURE_DOCTOR_DELAY:-}" \
        FIXTURE_EXEC_LOG="${FIXTURE_EXEC_LOG:-}" \
        FIXTURE_EXEC_VERSION="${FIXTURE_EXEC_VERSION:-}" \
        RACE_SOURCE="${RACE_SOURCE:-}" \
        RACE_TARGET="${RACE_TARGET:-}" \
        MUTATE_TARGET="${MUTATE_TARGET:-}" \
        REAL_CURL="${REAL_CURL:-}" \
        MAINFRAME_UPGRADE_FAILPOINT="${MAINFRAME_UPGRADE_FAILPOINT:-}" \
        "$MODERN_BASH" "$INSTALL_ROOT/scripts/upgrade-release.sh" "$@"
}

@test "file sources and failpoints require the private internal-test marker" {
    create_release "$TARGET_VERSION"
    rm -f -- "$INSTALL_ROOT/.mainframe-internal-test-mode"
    generate_manifest "$INSTALL_ROOT"
    write_fixture_receipt "$INSTALL_ROOT" "$CURRENT_VERSION" "$BIN_DIR"
    MAINFRAME_UPGRADE_FAILPOINT=after-staging-before-journal

    run_upgrade --version "$TARGET_VERSION" --dry-run

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failpoints are disabled outside a private internal-test fixture"* ]]
    assert_current_runtime_restored

    MAINFRAME_UPGRADE_FAILPOINT=""
    UPGRADE_RELEASE_BASE_URL="https://example.invalid/mainframe-releases"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Custom release origins are disabled"* ]]
    assert_current_runtime_restored
}

assert_current_runtime_restored() {
    [[ -d "$INSTALL_ROOT" ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$CURRENT_VERSION" ]]
    [[ "$(< "$INSTALL_ROOT/awm/sessions/current.json")" == "nonce-keep-me" ]]
    jq -e --arg version "$CURRENT_VERSION" '.version == $version' \
        "$INSTALL_ROOT/.mainframe-install-receipt.json" >/dev/null
    [[ -L "$BIN_DIR/mainframe" ]]
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$INSTALL_ROOT/bin/mainframe" ]]
}

@test "verified upgrade preserves private state, modes, receipt, link, and old backup" {
    local backup
    create_release "$TARGET_VERSION"

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -eq 0 ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$TARGET_VERSION" ]]
    [[ "$(file_mode "$INSTALL_ROOT")" == "700" ]]
    [[ "$(< "$INSTALL_ROOT/awm/sessions/current.json")" == "nonce-keep-me" ]]
    [[ "$(< "$INSTALL_ROOT/cache/index")" == "cached" ]]
    [[ "$(< "$INSTALL_ROOT/tasks/active")" == "in-progress" ]]
    [[ "$(< "$INSTALL_ROOT/user-notes/odd name.txt")" == "spaces survive" ]]
    [[ "$(file_mode "$INSTALL_ROOT/awm")" == "700" ]]
    [[ "$(file_mode "$INSTALL_ROOT/awm/sessions/current.json")" == "640" ]]
    [[ "$(file_mode "$INSTALL_ROOT/.mainframe-install-receipt.json")" == "600" ]]
    jq -e --arg version "$TARGET_VERSION" '.version == $version' \
        "$INSTALL_ROOT/.mainframe-install-receipt.json" >/dev/null
    [[ "$(readlink "$BIN_DIR/mainframe")" == "$INSTALL_ROOT/bin/mainframe" ]]
    backup="$(printf '%s\n' "$output" | awk -F ': ' '/Previous installation backup:/ { print $2 }')"
    [[ -d "$backup" ]]
    [[ "$(< "$backup/VERSION")" == "$CURRENT_VERSION" ]]
    [[ "$(< "$backup/awm/sessions/current.json")" == "nonce-keep-me" ]]
    [[ ! -e "$TEST_HOME/..mainframe.upgrade-journal.json" ]]
}

@test "dry run verifies and stages without mutation or quiescence confirmation" {
    create_release "$TARGET_VERSION"

    run_upgrade --version "$TARGET_VERSION" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry run verified v$TARGET_VERSION"* ]]
    assert_current_runtime_restored
    [[ ! -e "$TEST_HOME/..mainframe.upgrade-journal.json" ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '..mainframe.upgrade-transaction.*' -print -quit)" ]]
}

@test "upgrade ignores ambient curl and tar configuration" {
    create_release "$TARGET_VERSION"
    printf 'proto =https\n' > "$TEST_HOME/.curlrc"
    export TAR_OPTIONS='--strip-components=1'

    run_upgrade --version "$TARGET_VERSION" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry run verified v$TARGET_VERSION"* ]]
    assert_current_runtime_restored
}

@test "managed runtime mutation during download aborts before transaction publication" {
    local fake_bin="$TEST_TMPDIR/fake-curl-bin"
    create_release "$TARGET_VERSION"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'for argument in "$@"; do' \
        '  if [[ "$argument" == *.tar.gz.sha256 ]]; then' \
        '    printf "changed during download\n" >> "${MUTATE_TARGET:?}/lib/common.sh"' \
        '    break' \
        '  fi' \
        'done' \
        'exec "${REAL_CURL:?}" "$@"' \
        > "$fake_bin/curl"
    chmod 755 "$fake_bin/curl"
    UPGRADE_PATH="$fake_bin:$PATH"
    MUTATE_TARGET="$INSTALL_ROOT"
    REAL_CURL="$(command -v curl)"

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Managed runtime file was modified: lib/common.sh"* ]]
    [[ -z "$(find "$TEST_HOME" -maxdepth 1 -name '..mainframe.upgrade-transaction.*' -print -quit)" ]]
    [[ ! -e "$TEST_HOME/..mainframe.upgrade-journal.json" ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$CURRENT_VERSION" ]]
}

@test "cutover requires explicit agent quiescence before network access" {
    run_upgrade --version "$TARGET_VERSION"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--confirm-agents-stopped"* ]]
    assert_current_runtime_restored
}

@test "same version is a fully verified no-op without network access" {
    RELEASE_ROOT="$TEST_TMPDIR/does-not-exist"

    run_upgrade --version "$CURRENT_VERSION"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"already installed"* ]]
    assert_current_runtime_restored
}

@test "health verification accepts large trailing version output" {
    create_release "$TARGET_VERSION"
    FIXTURE_VERSION_DETAIL_LINES=20000

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Upgraded MAINFRAME from v$CURRENT_VERSION to v$TARGET_VERSION"* ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$TARGET_VERSION" ]]
}

@test "install root may not be the user home directory" {
    run env HOME="$INSTALL_ROOT" MAINFRAME_ROOT="$INSTALL_ROOT" \
        "$MODERN_BASH" "$INSTALL_ROOT/scripts/upgrade-release.sh" \
        --version "$CURRENT_VERSION"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unsafe or missing MAINFRAME_ROOT"* ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$CURRENT_VERSION" ]]
}

@test "same-version no-op rejects a modified managed runtime" {
    printf 'tampered\n' >> "$INSTALL_ROOT/lib/common.sh"

    run_upgrade --version "$CURRENT_VERSION"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Managed runtime file was modified: lib/common.sh"* ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$CURRENT_VERSION" ]]
}

@test "receipt boundary rejects malformed ownership evidence before network or mutation" {
    local original_receipt="$TEST_TMPDIR/original-receipt.json"
    local original_common original_state case_name expected saved_bin="$TEST_TMPDIR/saved-bin"
    local -a cases=(
        missing-receipt symlink-receipt root-mode receipt-mode extra-key wrong-method
        version-mismatch install-mismatch missing-bin symlink-bin cli-mismatch
        missing-cli wrong-cli-target manifest-mismatch
    )
    cp "$INSTALL_ROOT/.mainframe-install-receipt.json" "$original_receipt"
    original_common="$(sha256_digest "$INSTALL_ROOT/lib/common.sh")"
    original_state="$(sha256_digest "$INSTALL_ROOT/awm/sessions/current.json")"

    for case_name in "${cases[@]}"; do
        rm -f -- "$INSTALL_ROOT/.mainframe-install-receipt.json"
        cp "$original_receipt" "$INSTALL_ROOT/.mainframe-install-receipt.json"
        chmod 600 "$INSTALL_ROOT/.mainframe-install-receipt.json"
        chmod 700 "$INSTALL_ROOT"
        if [[ -d "$saved_bin" ]]; then mv -- "$saved_bin" "$BIN_DIR"; fi
        rm -f -- "$BIN_DIR/mainframe" "$TEST_HOME/bin-link"
        ln -s "$INSTALL_ROOT/bin/mainframe" "$BIN_DIR/mainframe"

        case "$case_name" in
            missing-receipt)
                rm "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="no regular release receipt"
                ;;
            symlink-receipt)
                mv "$INSTALL_ROOT/.mainframe-install-receipt.json" "$TEST_TMPDIR/receipt-target"
                ln -s "$TEST_TMPDIR/receipt-target" "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="no regular release receipt"
                ;;
            root-mode)
                chmod 755 "$INSTALL_ROOT"
                expected="private mode 700"
                ;;
            receipt-mode)
                chmod 644 "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="receipt must have mode 600"
                ;;
            extra-key)
                jq '.unexpected = true' "$original_receipt" > "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="receipt is malformed"
                ;;
            wrong-method)
                jq '.install_method = "source"' "$original_receipt" > "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="receipt is malformed"
                ;;
            version-mismatch)
                jq '.version = "10.1.0"' "$original_receipt" > "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="VERSION does not match the release receipt"
                ;;
            install-mismatch)
                jq '.install_dir = "/tmp/not-mainframe"' "$original_receipt" > "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="install path does not match"
                ;;
            missing-bin)
                mv -- "$BIN_DIR" "$saved_bin"
                expected="bin directory is missing"
                ;;
            symlink-bin)
                ln -s "$BIN_DIR" "$TEST_HOME/bin-link"
                jq --arg bin "$TEST_HOME/bin-link" \
                    '.bin_dir = $bin | .cli_link = ($bin + "/mainframe")' "$original_receipt" \
                    > "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="bin directory is missing or symbolic-linked"
                ;;
            cli-mismatch)
                jq '.cli_link = "/tmp/not-mainframe"' "$original_receipt" > "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="CLI path does not match"
                ;;
            missing-cli)
                rm "$BIN_DIR/mainframe"
                expected="does not contain the owned MAINFRAME symlink"
                ;;
            wrong-cli-target)
                rm "$BIN_DIR/mainframe"
                ln -s "$INSTALL_ROOT/bin/not-mainframe" "$BIN_DIR/mainframe"
                expected="no longer targets this MAINFRAME runtime"
                ;;
            manifest-mismatch)
                jq '.manifest_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
                    "$original_receipt" > "$INSTALL_ROOT/.mainframe-install-receipt.json"
                expected="SHA256SUMS no longer matches"
                ;;
        esac
        RELEASE_ROOT="$TEST_TMPDIR/network-must-not-be-used-$case_name"
        run_upgrade --version "$TARGET_VERSION" --dry-run
        [[ "$status" -ne 0 ]]
        [[ "$output" == *"$expected"* ]]
        [[ "$(< "$INSTALL_ROOT/VERSION")" == "$CURRENT_VERSION" ]]
        [[ "$(sha256_digest "$INSTALL_ROOT/lib/common.sh")" == "$original_common" ]]
        [[ "$(sha256_digest "$INSTALL_ROOT/awm/sessions/current.json")" == "$original_state" ]]
    done

    if [[ -d "$saved_bin" ]]; then mv -- "$saved_bin" "$BIN_DIR"; fi
    rm -f -- "$INSTALL_ROOT/.mainframe-install-receipt.json" "$BIN_DIR/mainframe" "$TEST_HOME/bin-link"
    cp "$original_receipt" "$INSTALL_ROOT/.mainframe-install-receipt.json"
    chmod 600 "$INSTALL_ROOT/.mainframe-install-receipt.json"
    chmod 700 "$INSTALL_ROOT"
    ln -s "$INSTALL_ROOT/bin/mainframe" "$BIN_DIR/mainframe"
    assert_current_runtime_restored
}

@test "downgrade is refused unless explicitly allowed" {
    local lower=10.1.9
    create_release "$lower"

    run_upgrade --version "$lower" --confirm-agents-stopped
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Refusing downgrade"* ]]
    assert_current_runtime_restored

    run_upgrade --version "$lower" --allow-downgrade --confirm-agents-stopped
    [[ "$status" -eq 0 ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$lower" ]]
    [[ "$(< "$INSTALL_ROOT/awm/sessions/current.json")" == "nonce-keep-me" ]]
}

@test "outer checksum corruption fails before mutation" {
    create_release "$TARGET_VERSION"
    printf 'tampered\n' >> "$RELEASE_ROOT/v$TARGET_VERSION/mainframe-$TARGET_VERSION.tar.gz"

    run_upgrade --version "$TARGET_VERSION" --dry-run

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"archive SHA-256 verification failed"* ]]
    assert_current_runtime_restored
}

@test "incomplete inner manifest and unmanifested file fail before mutation" {
    local payload="$TEST_TMPDIR/payload-$TARGET_VERSION" manifest_tmp
    create_release "$TARGET_VERSION"
    manifest_tmp="$TEST_TMPDIR/manifest.tmp"
    grep -v '  lib/common.sh$' "$payload/SHA256SUMS" > "$manifest_tmp"
    mv "$manifest_tmp" "$payload/SHA256SUMS"
    repack_release "$TARGET_VERSION"

    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"SHA256SUMS omits required runtime path: lib/common.sh"* ]]
    assert_current_runtime_restored

    create_release "$TARGET_VERSION"
    printf 'extra\n' > "$payload/extra.txt"
    repack_release "$TARGET_VERSION" extra.txt
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"absent from SHA256SUMS: extra.txt"* ]]
    assert_current_runtime_restored
}

@test "upgrade archive rejects receipts, duplicate members, links, and traversal" {
    local payload="$TEST_TMPDIR/payload-$TARGET_VERSION"
    local archive="$RELEASE_ROOT/v$TARGET_VERSION/mainframe-$TARGET_VERSION.tar.gz"
    create_release "$TARGET_VERSION"
    printf '{}\n' > "$payload/.mainframe-install-receipt.json"
    repack_release "$TARGET_VERSION" .mainframe-install-receipt.json
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"must not contain a machine-local install receipt"* ]]
    assert_current_runtime_restored

    create_release "$TARGET_VERSION"
    (
        cd "$payload"
        COPYFILE_DISABLE=1 tar -czf "$archive" \
            VERSION VERSION SHA256SUMS bin/mainframe get-mainframe.sh install.sh \
            lib/common.sh scripts/upgrade-release.sh
    )
    rewrite_release_checksum "$TARGET_VERSION"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"duplicate member paths"* ]]
    assert_current_runtime_restored

    create_release "$TARGET_VERSION"
    ln -s ../../outside "$payload/escape-link"
    repack_release "$TARGET_VERSION" escape-link
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"links and special entries are not allowed"* ]]
    assert_current_runtime_restored

    create_release "$TARGET_VERSION"
    if tar --version 2>/dev/null | grep -q 'GNU tar'; then
        (
            cd "$payload"
            tar -czf "$archive" --transform='s|^install\.sh$|../install.sh|' \
                VERSION SHA256SUMS bin/mainframe get-mainframe.sh install.sh \
                lib/common.sh scripts/upgrade-release.sh
        )
    else
        (
            cd "$payload"
            COPYFILE_DISABLE=1 tar -czf "$archive" -s ',^install\.sh$,../install.sh,' \
                VERSION SHA256SUMS bin/mainframe get-mainframe.sh install.sh \
                lib/common.sh scripts/upgrade-release.sh
        )
    fi
    rewrite_release_checksum "$TARGET_VERSION"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unsafe member path"* ]]
    assert_current_runtime_restored
}

@test "upgrade archive requires exact version and executable required payload" {
    local payload="$TEST_TMPDIR/payload-$TARGET_VERSION"
    local archive="$RELEASE_ROOT/v$TARGET_VERSION/mainframe-$TARGET_VERSION.tar.gz"
    create_release "$TARGET_VERSION"
    printf '10.3.1\n' > "$payload/VERSION"
    generate_manifest "$payload"
    repack_release "$TARGET_VERSION"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Release VERSION (10.3.1) does not match requested version ($TARGET_VERSION)"* ]]
    assert_current_runtime_restored

    create_release "$TARGET_VERSION"
    chmod 644 "$payload/scripts/upgrade-release.sh"
    repack_release "$TARGET_VERSION"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"installer, CLI, and next-version upgrader must be executable"* ]]
    assert_current_runtime_restored

    create_release "$TARGET_VERSION"
    (
        cd "$payload"
        COPYFILE_DISABLE=1 tar -czf "$archive" \
            VERSION SHA256SUMS bin/mainframe get-mainframe.sh install.sh lib/common.sh
    )
    rewrite_release_checksum "$TARGET_VERSION"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing a required runtime or upgrade file"* ]]
    assert_current_runtime_restored
}

@test "upgrade checksum record must name one exact lowercase digest" {
    local checksum="$RELEASE_ROOT/v$TARGET_VERSION/mainframe-$TARGET_VERSION.tar.gz.sha256"
    local archive="$RELEASE_ROOT/v$TARGET_VERSION/mainframe-$TARGET_VERSION.tar.gz" digest
    create_release "$TARGET_VERSION"
    digest="$(sha256_digest "$archive")"
    printf '%s  different.tar.gz\n' "$digest" > "$checksum"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"does not name the exact asset"* ]]
    assert_current_runtime_restored

    printf '%s  mainframe-%s.tar.gz\n%s  mainframe-%s.tar.gz\n' \
        "$digest" "$TARGET_VERSION" "$digest" "$TARGET_VERSION" > "$checksum"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"exactly one record"* ]]
    assert_current_runtime_restored
}

@test "unmanaged path collision fails before mutation" {
    local payload="$TEST_TMPDIR/payload-$TARGET_VERSION"
    printf 'current user value\n' > "$INSTALL_ROOT/future.conf"
    create_release "$TARGET_VERSION"
    printf 'new runtime value\n' > "$payload/future.conf"
    generate_manifest "$payload"
    repack_release "$TARGET_VERSION" future.conf

    run_upgrade --version "$TARGET_VERSION" --dry-run

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"State file collides with a new runtime path: future.conf"* ]]
    [[ "$(< "$INSTALL_ROOT/future.conf")" == "current user value" ]]
    assert_current_runtime_restored
}

@test "unmanaged files cannot enter managed runtime surfaces or executable roots" {
    create_release "$TARGET_VERSION"
    printf 'would be sourced\n' > "$INSTALL_ROOT/lib/evil.sh"

    run_upgrade --version "$TARGET_VERSION" --dry-run

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unmanaged state is inside a managed runtime surface: lib/evil.sh"* ]]
    [[ ! -e "$TEST_TMPDIR/payload-$TARGET_VERSION/lib/evil.sh" ]]
    rm -f -- "$INSTALL_ROOT/lib/evil.sh"

    printf '#!/usr/bin/env bash\n' > "$INSTALL_ROOT/run-me"
    chmod 700 "$INSTALL_ROOT/run-me"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unmanaged executable state is not eligible for automatic preservation: run-me"* ]]
    [[ -f "$INSTALL_ROOT/run-me" ]]
}

@test "upgrade lock rejects directories and live owners" {
    local lock="$TEST_HOME/..mainframe.upgrade.lock"
    create_release "$TARGET_VERSION"
    mkdir "$lock"

    run_upgrade --version "$TARGET_VERSION" --dry-run

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"did not create the exact regular lock path"* ]]
    assert_current_runtime_restored

    rm -rf -- "$lock"
    printf '%s\n' "$$" > "$lock"
    chmod 600 "$lock"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"still owns the lock"* ]]
    [[ "$output" == *"$$"* ]]
    assert_current_runtime_restored
}

@test "cutover never executes or removes a directory substituted during placement" {
    local fake_bin="$TEST_TMPDIR/fake-bin" journal recovery_script
    create_release "$TARGET_VERSION"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "$#" -eq 3 && "$1" == "--" && "$2" == *.upgrade-stage.*/runtime && "$3" == "${RACE_TARGET:?}" ]]; then' \
        '  mkdir -p "$3"' \
        '  printf "user replacement\n" > "$3/user-owned"' \
        'fi' \
        'exec /bin/mv "$@"' \
        > "$fake_bin/mv"
    chmod 755 "$fake_bin/mv"
    UPGRADE_PATH="$fake_bin:$PATH"
    RACE_TARGET="$INSTALL_ROOT"
    FIXTURE_EXEC_LOG="$TEST_TMPDIR/candidate-executed.log"
    FIXTURE_EXEC_VERSION="$TARGET_VERSION"

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Cutover did not activate the exact staged runtime; no candidate code was executed"* ]]
    [[ "$output" == *"leaving it untouched"* ]]
    [[ "$(< "$INSTALL_ROOT/user-owned")" == "user replacement" ]]
    [[ ! -e "$INSTALL_ROOT/runtime" ]]
    [[ ! -e "$FIXTURE_EXEC_LOG" ]]
    journal="$TEST_HOME/..mainframe.upgrade-journal.json"
    [[ -f "$journal" ]]
    [[ -f "$(jq -r '.backup_dir' "$journal")/VERSION" ]]
    [[ -f "$(jq -r '.transaction_dir' "$journal")/misplaced-candidate/VERSION" ]]

    recovery_script="$(jq -r '.recovery_script' "$journal")"
    run env HOME="$TEST_HOME" MAINFRAME_ROOT="$INSTALL_ROOT" \
        "$MODERN_BASH" "$recovery_script" --recover --journal "$journal"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"does not match the transaction-owned candidate; leaving it untouched"* ]]
    [[ "$(< "$INSTALL_ROOT/user-owned")" == "user replacement" ]]
    [[ -f "$journal" ]]
}

@test "backup destination substitution restores the exact previous runtime" {
    local fake_bin="$TEST_TMPDIR/fake-old-move-bin" journal transaction
    create_release "$TARGET_VERSION"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "$#" -eq 3 && "$1" == "--" && "$2" == "${RACE_SOURCE:?}" && "$3" == *.upgrade-transaction.*/previous ]]; then' \
        '  mkdir -p "$3"' \
        '  printf "user replacement\n" > "$3/user-owned"' \
        'fi' \
        'exec /bin/mv "$@"' \
        > "$fake_bin/mv"
    chmod 755 "$fake_bin/mv"
    UPGRADE_PATH="$fake_bin:$PATH"
    RACE_SOURCE="$INSTALL_ROOT"
    FIXTURE_EXEC_LOG="$TEST_TMPDIR/candidate-executed.log"
    FIXTURE_EXEC_VERSION="$TARGET_VERSION"

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Backup destination was substituted; restored and verified the previous installation"* ]]
    assert_current_runtime_restored
    journal="$TEST_HOME/..mainframe.upgrade-journal.json"
    [[ ! -e "$journal" ]]
    transaction="$(find "$TEST_HOME" -maxdepth 1 -type d -name '..mainframe.upgrade-transaction.*' -print -quit)"
    [[ -n "$transaction" ]]
    [[ "$(< "$transaction/previous/user-owned")" == "user replacement" ]]
    [[ ! -e "$transaction/previous/$(basename "$INSTALL_ROOT")" ]]
    [[ ! -e "$FIXTURE_EXEC_LOG" ]]
}

@test "symbolic links and special files in state fail closed" {
    local outside="$TEST_TMPDIR/outside.txt"
    create_release "$TARGET_VERSION"
    printf 'outside survives\n' > "$outside"
    ln -s "$outside" "$INSTALL_ROOT/user-link"

    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"state contains a symbolic link"* ]]
    [[ "$(< "$outside")" == "outside survives" ]]
    rm "$INSTALL_ROOT/user-link"

    mkfifo "$INSTALL_ROOT/active.pipe"
    run_upgrade --version "$TARGET_VERSION" --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"state contains a special file"* ]]
    [[ -p "$INSTALL_ROOT/active.pipe" ]]
}

@test "post-cutover health failure automatically restores the old runtime" {
    create_release "$TARGET_VERSION"
    FIXTURE_DOCTOR_FAIL_VERSION="$TARGET_VERSION"

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Runtime doctor failed for v$TARGET_VERSION"* ]]
    [[ "$output" == *"restored and verified the previous installation"* ]]
    assert_current_runtime_restored
    [[ -n "$(find "$TEST_HOME" -path '*/failed-candidate/VERSION' -print -quit)" ]]
    [[ ! -e "$TEST_HOME/..mainframe.upgrade-journal.json" ]]
}

@test "automatic rollback retains its journal when the old backup fails verification" {
    local journal="$TEST_HOME/..mainframe.upgrade-journal.json" watcher
    create_release "$TARGET_VERSION"
    FIXTURE_DOCTOR_FAIL_VERSION="$TARGET_VERSION"
    FIXTURE_DOCTOR_DELAY=0.5

    (
        local attempt state=""
        for ((attempt = 0; attempt < 500; attempt++)); do
            if [[ -f "$journal" ]]; then
                state="$(jq -r '.state // empty' "$journal" 2>/dev/null || true)"
                [[ "$state" == "new-active" ]] && break
            fi
            sleep 0.01
        done
        [[ "$state" == "new-active" ]] || exit 1
        printf 'tampered during transaction\n' >> \
            "$(jq -r '.backup_dir' "$journal")/lib/common.sh"
    ) &
    watcher=$!

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped
    wait "$watcher"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"restored but failed integrity or health verification"* ]]
    [[ -f "$journal" ]]
    [[ "$(< "$INSTALL_ROOT/VERSION")" == "$CURRENT_VERSION" ]]
    grep -Fq 'tampered during transaction' "$INSTALL_ROOT/lib/common.sh"
}

@test "rename failpoints automatically restore the old runtime" {
    local point
    create_release "$TARGET_VERSION"
    for point in after-old-move after-new-active after-new-journal; do
        MAINFRAME_UPGRADE_FAILPOINT="$point"
        run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped
        [[ "$status" -ne 0 ]]
        [[ "$output" == *"Injected upgrade failure at $point"* ]]
        assert_current_runtime_restored
        [[ ! -e "$TEST_HOME/..mainframe.upgrade-journal.json" ]]
    done
}

@test "SIGKILL before a journal leaves a safely reclaimable lock" {
    local lock="$TEST_HOME/..mainframe.upgrade.lock"
    create_release "$TARGET_VERSION"
    MAINFRAME_UPGRADE_FAILPOINT=kill-after-staging-before-journal

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -ne 0 ]]
    [[ -f "$lock" ]]
    assert_current_runtime_restored

    MAINFRAME_UPGRADE_FAILPOINT=""
    RELEASE_ROOT="$TEST_TMPDIR/no-network-needed"
    run_upgrade --version "$CURRENT_VERSION"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Clearing a crash-orphaned upgrade lock"* ]]
    [[ ! -e "$lock" ]]
    assert_current_runtime_restored
}

@test "SIGKILL after the root rename is recoverable without the original workspace" {
    local journal="$TEST_HOME/..mainframe.upgrade-journal.json" recovery_script workspace
    create_release "$TARGET_VERSION"
    MAINFRAME_UPGRADE_FAILPOINT=kill-after-old-move

    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped

    [[ "$status" -ne 0 ]]
    [[ ! -e "$INSTALL_ROOT" ]]
    [[ -f "$journal" ]]
    recovery_script="$(find "$TEST_HOME" -path '*/recover-upgrade.sh' -type f -print -quit)"
    [[ -n "$recovery_script" ]]
    workspace="$(jq -r '.workspace_dir' "$journal")"
    mv -- "$workspace" "$workspace.removed"

    run env HOME="$TEST_HOME" MAINFRAME_ROOT="$INSTALL_ROOT" \
        "$MODERN_BASH" "$recovery_script" --recover --journal "$journal"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Recorded staging workspace is absent"* ]]
    [[ "$output" == *"Recovery verified MAINFRAME v$CURRENT_VERSION"* ]]
    assert_current_runtime_restored
    [[ ! -e "$journal" ]]
    [[ -n "$(find "$TEST_HOME" -maxdepth 1 -name '..mainframe.upgrade-journal.json.recovered-*' -print -quit)" ]]
}

@test "copied recovery handles prepared and active-candidate SIGKILL states" {
    local journal="$TEST_HOME/..mainframe.upgrade-journal.json"
    local point recovery_script failed_dir
    create_release "$TARGET_VERSION"

    for point in kill-before-old-move kill-after-new-journal kill-after-health; do
        MAINFRAME_UPGRADE_FAILPOINT="$point"
        run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped
        [[ "$status" -ne 0 ]]
        [[ -f "$journal" ]]
        recovery_script="$(jq -r '.recovery_script' "$journal")"
        failed_dir="$(jq -r '.failed_dir' "$journal")"
        [[ -x "$recovery_script" ]]

        run env HOME="$TEST_HOME" MAINFRAME_ROOT="$INSTALL_ROOT" \
            "$MODERN_BASH" "$recovery_script" --recover --journal "$journal"

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"Recovery verified MAINFRAME v$CURRENT_VERSION"* ]]
        assert_current_runtime_restored
        [[ ! -e "$journal" ]]
        if [[ "$point" != "kill-before-old-move" ]]; then
            [[ "$(< "$failed_dir/VERSION")" == "$TARGET_VERSION" ]]
        fi
    done
}

@test "recovery refuses a journal that targets the user home" {
    local journal="$TEST_HOME/..mainframe.upgrade-journal.json" recovery_script bad_journal
    create_release "$TARGET_VERSION"
    MAINFRAME_UPGRADE_FAILPOINT=kill-after-old-move
    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped
    [[ "$status" -ne 0 ]]

    recovery_script="$(find "$TEST_HOME" -path '*/recover-upgrade.sh' -type f -print -quit)"
    bad_journal="$TEST_TMPDIR/.home.upgrade-journal.json"
    jq --arg home "$TEST_HOME" '.install_dir = $home' "$journal" > "$bad_journal"
    chmod 600 "$bad_journal"

    run env HOME="$TEST_HOME" MAINFRAME_ROOT="$INSTALL_ROOT" \
        "$MODERN_BASH" "$recovery_script" --recover --journal "$bad_journal"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Recovery install path is an unsafe broad target"* ]]
    [[ ! -e "$INSTALL_ROOT" ]]
    [[ -f "$journal" ]]
}

@test "recovery rejects traversal disguised beneath an owned transaction prefix" {
    local journal="$TEST_HOME/..mainframe.upgrade-journal.json" recovery_script victim bad_journal
    create_release "$TARGET_VERSION"
    MAINFRAME_UPGRADE_FAILPOINT=kill-after-old-move
    run_upgrade --version "$TARGET_VERSION" --confirm-agents-stopped
    [[ "$status" -ne 0 ]]

    recovery_script="$(find "$TEST_HOME" -path '*/recover-upgrade.sh' -type f -print -quit)"
    victim="$TEST_HOME/victim"
    mkdir -p "$victim"
    printf 'do not move\n' > "$victim/sentinel"
    bad_journal="$TEST_TMPDIR/bad-journal"
    jq '
      .transaction_dir = (.transaction_dir + "/../../victim") |
      .backup_dir = (.transaction_dir + "/previous") |
      .failed_dir = (.transaction_dir + "/failed-candidate") |
      .recovery_script = (.transaction_dir + "/recover-upgrade.sh")
    ' "$journal" > "$bad_journal"
    mv "$bad_journal" "$journal"
    chmod 600 "$journal"

    run env HOME="$TEST_HOME" MAINFRAME_ROOT="$INSTALL_ROOT" \
        "$MODERN_BASH" "$recovery_script" --recover --journal "$journal"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing or unsafe"* || "$output" == *"not canonical or sibling-owned"* || \
       "$output" == *"outside the owned sibling namespace"* ]]
    [[ "$(< "$victim/sentinel")" == "do not move" ]]
    [[ ! -e "$INSTALL_ROOT" ]]
}

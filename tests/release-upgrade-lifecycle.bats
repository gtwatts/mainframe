#!/usr/bin/env bats

# Composed distribution proof: build the real payload twice, install the first
# release through the public versioned bootstrap, then upgrade through the
# installed CLI while preserving real AWM state.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-release-upgrade-lifecycle.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
    TEST_HOME="$TEST_ROOT/home with spaces"
    INSTALL_DIR="$TEST_HOME/mainframe install"
    BIN_DIR="$TEST_HOME/local bin"
    RELEASE_ROOT="$TEST_ROOT/releases"
    RELEASE_SOURCE="$TEST_ROOT/release source"

    BASH_BIN="${MAINFRAME_BASH:-${BASH:-}}"
    if [[ -z "$BASH_BIN" || ! -x "$BASH_BIN" ]]; then
        BASH_BIN="$(command -v bash)"
    fi
    if ! "$BASH_BIN" --noprofile --norc -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))
    ' >/dev/null 2>&1; then
        skip "Bash 4.4+ is required"
    fi

    for required in curl jq python3 tar; do
        command -v "$required" >/dev/null 2>&1 || skip "$required is required"
    done

    CURRENT_VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
    IFS=. read -r version_major version_minor version_patch <<< "$CURRENT_VERSION"
    TARGET_VERSION="$version_major.$version_minor.$((version_patch + 1))"
    # Keep an installed Mainframe from the developer's ambient PATH from
    # becoming the selected CLI while this test exercises its private roots.
    TEST_PATH="$(dirname "$BASH_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"

    mkdir -p "$TEST_HOME" "$RELEASE_ROOT" "$RELEASE_SOURCE"
    printf 'MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:%s\n' "$INSTALL_DIR" \
        > "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    chmod 600 "$TEST_HOME/.mainframe-bootstrap-internal-test-mode"
    copy_release_source "$RELEASE_SOURCE"
}

teardown() {
    rm -rf -- "$TEST_ROOT"
}

copy_release_source() {
    local destination="$1" path payload_list="$TEST_ROOT/release-payload-files.txt"

    # shellcheck source=scripts/dev/release-payload.sh
    source "$PROJECT_ROOT/scripts/dev/release-payload.sh"
    # Copy the canonical file inventory rather than whole payload roots. A
    # maintainer checkout can contain large ignored artifacts (for example,
    # native-host node_modules) that are deliberately excluded from releases;
    # copying them makes this lifecycle proof slow and less representative.
    mainframe_release_payload_files "$PROJECT_ROOT" > "$payload_list" || return 1
    while IFS= read -r path; do
        mkdir -p "$destination/$(dirname "$path")"
        cp -p "$PROJECT_ROOT/$path" "$destination/$path"
    done < "$payload_list"
}

sha256_file() {
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
    if [[ "$value" =~ ^[0-7]{3,4}$ ]]; then
        printf '%s\n' "$value"
        return
    fi
    stat -f '%Lp' "$1"
}

publish_built_archive() {
    local version="$1" release_dir="$RELEASE_ROOT/v$1"
    local archive="$RELEASE_SOURCE/dist/mainframe-$version.tar.gz"

    mkdir -p "$release_dir"
    cp "$archive" "$archive.sha256" "$release_dir/"
}

enable_authenticated_upgrade_fixture() {
    local marker="$INSTALL_DIR/.mainframe-internal-test-mode"
    local marker_sha manifest_sha receipt_tmp

    printf 'MAINFRAME_INTERNAL_TESTING:%s\n' "$INSTALL_DIR" > "$marker"
    chmod 600 "$marker"
    marker_sha="$(sha256_file "$marker")"
    printf '%s  .mainframe-internal-test-mode\n' "$marker_sha" \
        >> "$INSTALL_DIR/SHA256SUMS"

    manifest_sha="$(sha256_file "$INSTALL_DIR/SHA256SUMS")"
    receipt_tmp="$(mktemp "$INSTALL_DIR/.mainframe-install-receipt.XXXXXX")"
    jq --arg manifest_sha "$manifest_sha" \
        '.manifest_sha256 = $manifest_sha' \
        "$INSTALL_DIR/.mainframe-install-receipt.json" > "$receipt_tmp"
    chmod 600 "$receipt_tmp"
    mv "$receipt_tmp" "$INSTALL_DIR/.mainframe-install-receipt.json"
}

@test "canonical release bootstrap and installed CLI upgrade preserve real AWM state" {
    local cli receipt session_id nonce backup target_archive_sha target_manifest_sha
    local install_parent install_base

    run env PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh"
    [[ "$status" -eq 0 ]]
    publish_built_archive "$CURRENT_VERSION"

    printf '%s\n' "$TARGET_VERSION" > "$RELEASE_SOURCE/VERSION"
    run env PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        "$BASH_BIN" "$RELEASE_SOURCE/scripts/sync-version.sh"
    [[ "$status" -eq 0 ]]
    run env PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        "$BASH_BIN" "$RELEASE_SOURCE/scripts/build-release-archive.sh"
    [[ "$status" -eq 0 ]]
    publish_built_archive "$TARGET_VERSION"

    run env \
        HOME="$TEST_HOME" \
        TMPDIR="$TEST_ROOT" \
        PATH="$TEST_PATH" \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_VERSION= \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        MAINFRAME_INSTALL_DIR="$INSTALL_DIR" \
        MAINFRAME_BIN_DIR="$BIN_DIR" \
        /bin/bash "$RELEASE_SOURCE/get-mainframe.sh" \
        --internal-test-fixture --release-version "$CURRENT_VERSION" \
        --no-shell --no-ai-discovery
    [[ "$status" -eq 0 ]]

    cli="$BIN_DIR/mainframe"
    receipt="$INSTALL_DIR/.mainframe-install-receipt.json"
    [[ -L "$cli" ]]
    [[ "$(readlink "$cli")" == "$INSTALL_DIR/bin/mainframe" ]]
    [[ "$(file_mode "$INSTALL_DIR")" == "700" ]]
    [[ "$(file_mode "$receipt")" == "600" ]]
    jq -e \
        --arg version "$CURRENT_VERSION" \
        --arg install_dir "$INSTALL_DIR" \
        --arg bin_dir "$BIN_DIR" \
        '.install_method == "release-archive" and .version == $version and
         .install_dir == $install_dir and .bin_dir == $bin_dir and
         .cli_link == ($bin_dir + "/mainframe")' \
        "$receipt" >/dev/null

    run env HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        "$cli" version
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v$CURRENT_VERSION"* ]]
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        "$cli" doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Status: All checks passed!"* ]]

    nonce="release-upgrade-$RANDOM-$RANDOM-$$"
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        AWM_ROOT="$INSTALL_DIR/awm" \
        "$cli" awm init release-upgrade-lifecycle
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[a-f0-9]{12}$ ]]
    session_id="$output"
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        AWM_ROOT="$INSTALL_DIR/awm" \
        "$cli" awm checkpoint --session "$session_id" upgrade_nonce "$nonce" --importance high
    [[ "$status" -eq 0 ]]

    # Exercise installed CLI dispatch through the real trusted curl while
    # keeping the release transport offline. The private marker is bound into
    # this fixture's manifest and receipt, so file:// remains unavailable to
    # ordinary installations and a PATH curl shim cannot intercept the call.
    enable_authenticated_upgrade_fixture

    run env \
        HOME="$TEST_HOME" \
        PATH="$TEST_PATH" \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_INTERNAL_TESTING=1 \
        MAINFRAME_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        AWM_ROOT="$INSTALL_DIR/awm" \
        "$cli" upgrade --version "$TARGET_VERSION" --confirm-agents-stopped
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Upgraded MAINFRAME from v$CURRENT_VERSION to v$TARGET_VERSION"* ]]
    backup="$(printf '%s\n' "$output" | sed -n \
        's/^\[MAINFRAME upgrade\] Previous installation backup: //p' | tail -1)"

    [[ -n "$backup" && -d "$backup" ]]
    [[ "$(file_mode "$backup")" == "700" ]]
    [[ "$(< "$backup/VERSION")" == "$CURRENT_VERSION" ]]
    jq -e --arg version "$CURRENT_VERSION" '.version == $version' \
        "$backup/.mainframe-install-receipt.json" >/dev/null
    [[ -f "$backup/awm/sessions/$session_id/data/upgrade_nonce" ]]
    [[ "$(< "$backup/awm/sessions/$session_id/data/upgrade_nonce")" == "$nonce" ]]

    [[ "$(< "$INSTALL_DIR/VERSION")" == "$TARGET_VERSION" ]]
    [[ "$(readlink "$cli")" == "$INSTALL_DIR/bin/mainframe" ]]
    [[ ! -e "$INSTALL_DIR/.mainframe-internal-test-mode" ]]
    [[ "$(file_mode "$INSTALL_DIR")" == "700" ]]
    [[ "$(file_mode "$receipt")" == "600" ]]
    target_archive_sha="$(awk '{print $1}' \
        "$RELEASE_ROOT/v$TARGET_VERSION/mainframe-$TARGET_VERSION.tar.gz.sha256")"
    target_manifest_sha="$(sha256_file "$INSTALL_DIR/SHA256SUMS")"
    jq -e \
        --arg version "$TARGET_VERSION" \
        --arg archive_sha "$target_archive_sha" \
        --arg manifest_sha "$target_manifest_sha" \
        --arg install_dir "$INSTALL_DIR" \
        --arg bin_dir "$BIN_DIR" \
        '.install_method == "release-archive" and .version == $version and
         .archive_sha256 == $archive_sha and .manifest_sha256 == $manifest_sha and
         .install_dir == $install_dir and .bin_dir == $bin_dir and
         .cli_link == ($bin_dir + "/mainframe")' \
        "$receipt" >/dev/null

    run env HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        "$cli" version
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME v$TARGET_VERSION"* ]]
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        "$cli" doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Status: All checks passed!"* ]]
    run env HOME="$TEST_HOME" PATH="$TEST_PATH" MAINFRAME_BASH="$BASH_BIN" \
        AWM_ROOT="$INSTALL_DIR/awm" \
        "$cli" awm get --session "$session_id" upgrade_nonce
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$nonce" ]]

    install_parent="$(dirname "$INSTALL_DIR")"
    install_base="$(basename "$INSTALL_DIR")"
    [[ ! -e "$install_parent/.${install_base}.upgrade-journal.json" ]]
}

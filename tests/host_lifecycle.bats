#!/usr/bin/env bats
# Offline, consent-gated lifecycle contract for private managed host payloads.

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    JQ_BIN="$(command -v jq)"
    NODE_BIN="$(command -v node)"
    TAR_BIN="$(command -v tar)"
    JQ_DIR="${JQ_BIN%/*}"
    NODE_DIR="${NODE_BIN%/*}"
    TEST_DIR="$(create_test_dir host-lifecycle)"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    RUNTIME_ROOT="$TEST_DIR/mainframe runtime"
    PROJECT_DIR="$TEST_DIR/project with spaces"
    CLI_DIR="$TEST_DIR/discovery bin"
    TEST_HOME="$TEST_DIR/home"
    XDG_DATA_HOME="$TEST_DIR/xdg data"
    PACKAGE_DIR="$TEST_DIR/package dir"
    COMMAND_LOG="$TEST_DIR/command-exec.log"
    VENDOR_LOG="$TEST_DIR/vendor-exec.log"
    DISCOVERY_PATH="$CLI_DIR:$JQ_DIR:$NODE_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
    RUNTIME_PAYLOAD_ROOT="$XDG_DATA_HOME/mainframe/host-payloads"

    [[ -x "$BASH_BIN" && -x "$JQ_BIN" && -x "$NODE_BIN" && -x "$TAR_BIN" ]] ||
        skip "host lifecycle fixtures require Bash 4.4+, jq, Node.js, and tar"
    "$BASH_BIN" -c '
      (( BASH_VERSINFO[0] > 4 ||
         (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))
    ' || skip "host lifecycle fixtures require Bash 4.4+"
    mkdir -p \
        "$RUNTIME_ROOT/bin" \
        "$RUNTIME_ROOT/scripts/dev/native-host" \
        "$PROJECT_DIR" \
        "$CLI_DIR" \
        "$TEST_HOME" \
        "$PACKAGE_DIR"
    cp "$PROJECT_ROOT/bin/mainframe" "$RUNTIME_ROOT/bin/mainframe"
    cp "$PROJECT_ROOT/FUNCTIONS.json" "$RUNTIME_ROOT/FUNCTIONS.json"
    cp "$PROJECT_ROOT/VERSION" "$RUNTIME_ROOT/VERSION"
    find "$PROJECT_ROOT/scripts/dev/native-host" -maxdepth 1 -type f \
        -exec cp {} "$RUNTIME_ROOT/scripts/dev/native-host/" \;
    chmod +x "$RUNTIME_ROOT/bin/mainframe"
    ln -s "$PROJECT_ROOT/lib" "$RUNTIME_ROOT/lib"
    ln -s "$JQ_BIN" "$CLI_DIR/jq"

    export PROJECT_ROOT BASH_BIN JQ_BIN NODE_BIN TAR_BIN JQ_DIR NODE_DIR
    export TEST_DIR RUNTIME_ROOT PROJECT_DIR CLI_DIR TEST_HOME XDG_DATA_HOME
    export PACKAGE_DIR COMMAND_LOG VENDOR_LOG DISCOVERY_PATH RUNTIME_PAYLOAD_ROOT
    export MAINFRAME_ROOT="$RUNTIME_ROOT"
    export MAINFRAME_BASH="$BASH_BIN"
    export HOST_LIFECYCLE_EXEC_LOG="$VENDOR_LOG"
    unset MAINFRAME_AGENT_JQ MAINFRAME_HOST_RUNTIME_ROOT
    unset MAINFRAME_HOST_RUNTIME_POLICY MAINFRAME_HOST_LIFECYCLE_FAILPOINT
}

teardown() {
    if [[ -d "${TEST_DIR:-}" ]]; then
        find "$TEST_DIR" -type d -exec chmod 700 {} + 2>/dev/null || true
    fi
    cleanup_test_dir "$TEST_DIR"
}

mf() {
    env PATH="$DISCOVERY_PATH" \
        HOME="$TEST_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        MAINFRAME_BASH="$BASH_BIN" \
        HOST_LIFECYCLE_EXEC_LOG="$VENDOR_LOG" \
        "$BASH_BIN" "$RUNTIME_ROOT/bin/mainframe" "$@"
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

npm_sri_sha512() {
    "$NODE_BIN" -e '
      const crypto = require("node:crypto");
      const fs = require("node:fs");
      const bytes = fs.readFileSync(process.argv[1]);
      process.stdout.write("sha512-" + crypto.createHash("sha512")
        .update(bytes).digest("base64") + "\n");
    ' "$1"
}

path_identity() {
    local path="$1" result
    result="$(/usr/bin/stat -c '%d:%i' "$path" 2>/dev/null ||
        /usr/bin/stat -f '%d:%i' "$path" 2>/dev/null ||
        /bin/stat -c '%d:%i' "$path" 2>/dev/null ||
        /bin/stat -f '%d:%i' "$path" 2>/dev/null)" || return 1
    [[ "$result" =~ ^[0-9]+:[0-9]+$ ]] || return 1
    printf '%s\n' "$result"
}

relative_tree_snapshot() {
    local root="$1"
    (
        cd "$root" || exit 1
        find . -type f -exec cksum {} \; | LC_ALL=C sort
    )
}

expected_details() {
    local host="$1"

    env PATH="$DISCOVERY_PATH" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        HOME="$TEST_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/common.sh"
          source "$1/lib/activate.sh"
          source "$1/lib/launch.sh"
          source "$1/lib/host_runtime.sh"
          _mainframe_enforce_bind_jq "$1" "$PATH"
          _mainframe_host_prepare_expected "$2"
          printf "version=%s\\n" "${_MAINFRAME_HOST_EXPECTED_VERSION-}"
          printf "platform=%s\\n" "${_MAINFRAME_HOST_EXPECTED_PLATFORM-}"
          printf "target=%s\\n" "${_MAINFRAME_HOST_EXPECTED_TARGET-}"
          printf "tree_root=%s\\n" "${_MAINFRAME_HOST_EXPECTED_TREE_ROOT-}"
          printf "executable=%s\\n" "${_MAINFRAME_HOST_EXPECTED_EXECUTABLE-}"
          printf "bundle_id=%s\\n" "${_MAINFRAME_HOST_EXPECTED_BUNDLE_ID-}"
          printf "supported=%s\\n" "${_MAINFRAME_HOST_EXPECTED_SUPPORTED-}"
          printf "error=%s\\n" "${_MAINFRAME_HOST_EXPECTED_ERROR-}"
        ' _ "$RUNTIME_ROOT" "$host"
}

make_npm_archive() {
    local source_parent="$1" archive="$2"
    (
        cd "$source_parent" || exit 1
        # Emit the same portable ustar shape used by registry package archives.
        # macOS bsdtar otherwise adds local provenance xattrs as PAX headers;
        # the product extractor correctly refuses all extended metadata.
        COPYFILE_DISABLE=1 "$TAR_BIN" --format ustar --no-xattrs \
            -czf "$archive" package
    )
}

make_codex_package_dir() {
    local manifest lock temporary expected
    local base_source platform_source expected_tree
    local base_name base_version platform_version
    local base_resolved platform_resolved base_archive platform_archive
    local base_integrity platform_integrity base_entrypoint entry_relative
    local manifest_platform package_alias alias_leaf binary binary_relative
    local entry_sha executable_sha tree_sha package_script

    manifest="$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"
    lock="$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json"
    CODEX_PLATFORM="$(env MAINFRAME_ROOT="$RUNTIME_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/host_runtime.sh"
          _mainframe_host_platform_id
        ' _ "$RUNTIME_ROOT")" || return 1
    "$JQ_BIN" -e --arg platform "$CODEX_PLATFORM" \
        'any(.platforms[]; .id == $platform)' \
        "$RUNTIME_ROOT/scripts/dev/native-host/release-platforms.json" \
        >/dev/null || skip "current platform is not advertised for managed hosts"
    manifest_platform="${CODEX_PLATFORM%-*}"
    base_name='@openai/codex'
    base_version="$($JQ_BIN -er '.codex.version' "$manifest")" || return 1
    package_alias="$($JQ_BIN -er --arg key "$manifest_platform" \
        '.codex.platforms[$key].package_alias' "$manifest")" || return 1
    alias_leaf="${package_alias##*/}"
    platform_version="$($JQ_BIN -er --arg key "$manifest_platform" \
        '.codex.platforms[$key].package_version' "$manifest")" || return 1
    binary="$($JQ_BIN -er --arg key "$manifest_platform" \
        '.codex.platforms[$key].binary' "$manifest")" || return 1
    base_entrypoint="$($JQ_BIN -er '.codex.entrypoint' "$manifest")" || return 1
    entry_relative="${base_entrypoint#node_modules/@openai/codex/}"
    binary_relative="${binary#node_modules/$package_alias/}"
    [[ "$entry_relative" != "$base_entrypoint" &&
       "$binary_relative" != "$binary" ]] || return 1

    base_resolved="$($JQ_BIN -er \
        '.packages["node_modules/@openai/codex"].resolved' "$lock")" || return 1
    platform_resolved="$($JQ_BIN -er --arg path "node_modules/$package_alias" \
        '.packages[$path].resolved' "$lock")" || return 1
    base_archive="$PACKAGE_DIR/${base_resolved##*/}"
    platform_archive="$PACKAGE_DIR/${platform_resolved##*/}"
    [[ "$base_archive" != "$platform_archive" ]] || return 1

    base_source="$TEST_DIR/base npm package"
    platform_source="$TEST_DIR/platform npm package"
    expected_tree="$TEST_DIR/expected @openai tree"
    mkdir -p \
        "$base_source/package/${entry_relative%/*}" \
        "$platform_source/package/${binary_relative%/*}" \
        "$expected_tree/codex" \
        "$expected_tree/$alias_leaf"
    package_script='node -e "require(\"node:fs\").appendFileSync(process.env.HOST_LIFECYCLE_EXEC_LOG, \"package-script\\n\")"'
    "$JQ_BIN" -n \
        --arg name "$base_name" \
        --arg version "$base_version" \
        --arg alias "$package_alias" \
        --arg platform_version "$platform_version" \
        --arg script "$package_script" '
          {
            name: $name,
            version: $version,
            bin: {codex: "bin/codex.js"},
            scripts: {preinstall: $script, postinstall: $script},
            optionalDependencies: {
              ($alias): ("npm:@openai/codex@" + $platform_version)
            }
          }
        ' > "$base_source/package/package.json" || return 1
    {
        printf '%s\n' '#!/usr/bin/env node'
        printf '%s\n' 'require("node:fs").appendFileSync('
        printf '%s\n' '  process.env.HOST_LIFECYCLE_EXEC_LOG, "base-entrypoint\\n");'
        printf '%s\n' 'process.exit(97);'
    } > "$base_source/package/$entry_relative"
    printf '%s\n' 'synthetic offline Codex base package' > \
        "$base_source/package/resource with spaces.txt"
    chmod 755 "$base_source/package/$entry_relative"
    chmod 644 "$base_source/package/package.json" \
        "$base_source/package/resource with spaces.txt"

    "$JQ_BIN" -n \
        --arg name '@openai/codex' \
        --arg version "$platform_version" '
          {name: $name, version: $version}
        ' > "$platform_source/package/package.json" || return 1
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'printf "platform-executable\\n" >> "${HOST_LIFECYCLE_EXEC_LOG:?}"'
        printf '%s\n' 'exit 97'
    } > "$platform_source/package/$binary_relative"
    printf '%s\n' 'synthetic platform resource' > \
        "$platform_source/package/platform resource.txt"
    chmod 755 "$platform_source/package/$binary_relative"
    chmod 644 "$platform_source/package/package.json" \
        "$platform_source/package/platform resource.txt"

    cp -R "$base_source/package/." "$expected_tree/codex/"
    cp -R "$platform_source/package/." "$expected_tree/$alias_leaf/"
    make_npm_archive "$base_source" "$base_archive" || return 1
    make_npm_archive "$platform_source" "$platform_archive" || return 1
    base_integrity="$(npm_sri_sha512 "$base_archive")" || return 1
    platform_integrity="$(npm_sri_sha512 "$platform_archive")" || return 1
    entry_sha="$(sha256_file "$base_source/package/$entry_relative")" || return 1
    executable_sha="$(sha256_file \
        "$platform_source/package/$binary_relative")" || return 1
    tree_sha="$("$NODE_BIN" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.mjs" \
        "$expected_tree")" || return 1
    [[ "$tree_sha" =~ ^[0-9a-f]{64}$ ]] || return 1

    temporary="$manifest.lifecycle.tmp.$$"
    "$JQ_BIN" \
        --arg key "$manifest_platform" \
        --arg base_integrity "$base_integrity" \
        --arg platform_integrity "$platform_integrity" \
        --arg entry_sha "$entry_sha" \
        --arg executable_sha "$executable_sha" \
        --arg tree_sha "$tree_sha" '
          .codex.integrity = $base_integrity |
          .codex.entrypoint_sha256 = $entry_sha |
          .codex.platforms[$key].integrity = $platform_integrity |
          .codex.platforms[$key].executable_sha256 = $executable_sha |
          .codex.platforms[$key].package_tree_sha256 = $tree_sha
        ' "$manifest" > "$temporary" || return 1
    mv "$temporary" "$manifest"

    temporary="$lock.lifecycle.tmp.$$"
    "$JQ_BIN" \
        --arg base_path 'node_modules/@openai/codex' \
        --arg platform_path "node_modules/$package_alias" \
        --arg base_integrity "$base_integrity" \
        --arg platform_integrity "$platform_integrity" '
          .packages[$base_path].integrity = $base_integrity |
          .packages[$platform_path].integrity = $platform_integrity
        ' "$lock" > "$temporary" || return 1
    mv "$temporary" "$lock"

    expected="$(expected_details codex)" || return 1
    CODEX_VERSION="$(sed -n 's/^version=//p' <<< "$expected")"
    CODEX_TARGET="$(sed -n 's/^target=//p' <<< "$expected")"
    CODEX_TREE_ROOT="$(sed -n 's/^tree_root=//p' <<< "$expected")"
    CODEX_EXECUTABLE="$(sed -n 's/^executable=//p' <<< "$expected")"
    CODEX_BUNDLE_ID="$(sed -n 's/^bundle_id=//p' <<< "$expected")"
    CODEX_PLATFORM_ARCHIVE="$platform_archive"
    [[ -n "$CODEX_VERSION" && -n "$CODEX_TARGET" &&
       -n "$CODEX_TREE_ROOT" && -n "$CODEX_EXECUTABLE" &&
       "$CODEX_BUNDLE_ID" =~ ^[0-9a-f]{64}$ ]] || return 1
}

make_command_traps() {
    local command_name
    for command_name in curl wget npm npx pnpm yarn; do
        {
            printf '%s\n' '#!/usr/bin/env bash'
            printf '%s\n' 'printf "%s\\n" "${0##*/}" >> "${COMMAND_LOG:?}"'
            printf '%s\n' 'exit 97'
        } > "$CLI_DIR/$command_name"
        chmod 755 "$CLI_DIR/$command_name"
    done
    export COMMAND_LOG
}

assert_payload_modes() {
    local target="$1" path
    [[ "$(file_mode "$target")" == 700 ]]
    [[ "$(file_mode "$target/receipt.json")" == 600 ]]
    while IFS= read -r path; do
        [[ "$(file_mode "$path")" == 500 ]] || return 1
    done < <(find "$target/payload" -type d -o -type f)
}

install_and_quarantine_codex() {
    local removal
    make_codex_package_dir || return 1
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null || return 1
    removal="$(mf host remove codex --yes --json)" || return 1
    QUARANTINE_ID="$($JQ_BIN -er '.quarantine_id |
        select(type == "string" and test("^removed\\.[0-9a-f]{18}$"))' \
        <<< "$removal")" || return 1
    QUARANTINE_BASE="$RUNTIME_PAYLOAD_ROOT/quarantine/v1/codex/$CODEX_VERSION/$CODEX_PLATFORM/$CODEX_BUNDLE_ID"
    QUARANTINE_SLOT="$QUARANTINE_BASE/$QUARANTINE_ID"
    QUARANTINE_GENERATION="$QUARANTINE_SLOT/generation"
    [[ -d "$QUARANTINE_GENERATION" && ! -L "$QUARANTINE_GENERATION" ]] || return 1
    export QUARANTINE_ID QUARANTINE_BASE QUARANTINE_SLOT QUARANTINE_GENERATION
}

@test "host lifecycle help documents offline package install and recoverable remove" {
    run mf host --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"host install"*"--package-dir"* ]]
    [[ "$output" == *"host remove"* ]]
    [[ "$output" == *"offline"* ]]
    [[ "$output" == *"never"*"npm"* || "$output" == *"does not"*"npm"* ]]

    run mf host install --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe host install HOST --package-dir DIR"* ]]
    [[ "$output" == *"--dry-run"*"--yes"*"--json"* ]]

    run mf host remove --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe host remove HOST"* ]]
    [[ "$output" == *"quarantine"* || "$output" == *"recover"* ]]
}

@test "host lifecycle rejects ambiguous grammar before creating managed state" {
    run mf host install
    [[ "$status" -eq 2 ]]

    run mf host install codex
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--package-dir"* ]]

    run mf host install codex --package-dir "$PACKAGE_DIR" \
        --package-dir "$PACKAGE_DIR" --yes
    [[ "$status" -eq 2 ]]

    run mf host install unknown --package-dir "$PACKAGE_DIR" --yes
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported host"* ]]

    run mf host install codex --package-dir "$PACKAGE_DIR" --dry-run --yes
    [[ "$status" -eq 2 ]]

    run mf host remove codex --package-dir "$PACKAGE_DIR" --yes
    [[ "$status" -eq 2 ]]

    run mf host remove codex unexpected --yes
    [[ "$status" -eq 2 ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "noninteractive install requires explicit consent after valid preflight" {
    make_codex_package_dir

    run mf host install codex --package-dir "$PACKAGE_DIR"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--yes"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    [[ ! -e "$VENDOR_LOG" ]]
}

@test "install dry-run authenticates packages and leaves no XDG data" {
    make_codex_package_dir

    run mf host install codex --package-dir "$PACKAGE_DIR" --dry-run --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .schema_version == 1 and .command == "host-install" and
      .host == "codex" and .result == "would-install" and
      .changed == false
    ' <<< "$output"
    [[ "$output" != *"$TEST_HOME"* ]]
    [[ "$output" != *"$PACKAGE_DIR"* ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    [[ ! -e "$VENDOR_LOG" ]]
}

@test "install rejects a missing required archive before creating managed state" {
    local withheld_archive
    make_codex_package_dir
    withheld_archive="$TEST_DIR/withheld-platform.tgz"
    mv "$CODEX_PLATFORM_ARCHIVE" "$withheld_archive"

    run mf host install codex --package-dir "$PACKAGE_DIR" --dry-run

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing"* || "$output" == *"archive"* ||
       "$output" == *"basename"* ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    [[ ! -e "$VENDOR_LOG" ]]
}

@test "consenting install reports persistent managed-root creation on package failure" {
    local empty_package_dir
    empty_package_dir="$TEST_DIR/empty package dir"
    mkdir -m 700 "$empty_package_dir"

    run mf host install codex --package-dir "$empty_package_dir" --yes --json

    [[ "$status" -ne 0 ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "error" and
      .[0].changed == true and .[0].mutation_state == "changed" and
      .[0].error.code == "package-archive"
    ' <<< "$output"
    [[ -d "$XDG_DATA_HOME" && ! -L "$XDG_DATA_HOME" ]]
    [[ -d "$RUNTIME_PAYLOAD_ROOT" && ! -L "$RUNTIME_PAYLOAD_ROOT" ]]
    [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
       ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
    [[ -z "$(find "$RUNTIME_PAYLOAD_ROOT" -maxdepth 1 \
        -name '.install-stage.*' -print -quit)" ]]
}

@test "JSON install confines denied root-creation diagnostics" {
    local locked_parent
    [[ "$EUID" -ne 0 ]] || skip "permission-denial fixture requires a non-root user"
    locked_parent="$TEST_DIR/private locked parent"
    mkdir -m 700 "$locked_parent"
    XDG_DATA_HOME="$locked_parent/private data"
    RUNTIME_PAYLOAD_ROOT="$XDG_DATA_HOME/mainframe/host-payloads"
    export XDG_DATA_HOME RUNTIME_PAYLOAD_ROOT
    make_codex_package_dir
    chmod 500 "$locked_parent"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json
    chmod 700 "$locked_parent"

    [[ "$status" -ne 0 ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "error"
    ' <<< "$output"
    [[ "$output" != *"$locked_parent"* ]]
    [[ "$output" != *"Permission denied"* ]]
}

@test "install rejects colliding required lock basenames before extraction" {
    local manifest_platform package_alias base_resolved temporary
    make_codex_package_dir
    manifest_platform="${CODEX_PLATFORM%-*}"
    package_alias="$($JQ_BIN -er --arg key "$manifest_platform" \
        '.codex.platforms[$key].package_alias' \
        "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json")"
    base_resolved="$($JQ_BIN -er \
        '.packages["node_modules/@openai/codex"].resolved' \
        "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json")"
    temporary="$TEST_DIR/colliding-package-lock.json"
    "$JQ_BIN" \
        --arg platform_path "node_modules/$package_alias" \
        --arg base_resolved "$base_resolved" \
        '.packages[$platform_path].resolved = $base_resolved' \
        "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json" \
        > "$temporary"
    mv "$temporary" "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json"

    run mf host install codex --package-dir "$PACKAGE_DIR" --dry-run

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"collision"* || "$output" == *"duplicate"* ||
       "$output" == *"basename"* || "$output" == *"ambiguous"* ||
       "$output" == *"package set"* ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    [[ ! -e "$VENDOR_LOG" ]]
}

@test "successful install atomically publishes one fully ready Codex generation" {
    make_codex_package_dir

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e --arg bundle "$CODEX_BUNDLE_ID" '
      .schema_version == 1 and .command == "host-install" and
      .host == "codex" and .result == "installed" and .changed == true and
      (.managed.bundle_id // .bundle_id) == $bundle
    ' <<< "$output"
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -f "$CODEX_TARGET/receipt.json" && ! -L "$CODEX_TARGET/receipt.json" ]]
    [[ -d "$CODEX_TARGET/payload" && ! -L "$CODEX_TARGET/payload" ]]
    assert_payload_modes "$CODEX_TARGET"
    [[ ! -e "$VENDOR_LOG" ]]

    run mf host status codex --runtime managed --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .hosts[0].managed.state == "ready" and
      .hosts[0].selection.state == "ready" and
      .hosts[0].selection.source == "managed" and
      .hosts[0].selection.trust_boundary ==
        "managed-direct-native-full-tree"
    ' <<< "$output"
}

@test "install is idempotent only for the already authenticated exact generation" {
    local before after identity
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    before="$(relative_tree_snapshot "$CODEX_TARGET")"
    identity="$(path_identity "$CODEX_TARGET")"

    run mf host install codex --package-dir "$PACKAGE_DIR" --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .command == "host-install" and .host == "codex" and
      .result == "already-installed" and .changed == false
    ' <<< "$output"
    after="$(relative_tree_snapshot "$CODEX_TARGET")"
    [[ "$after" == "$before" ]]
    [[ "$(path_identity "$CODEX_TARGET")" == "$identity" ]]
    [[ ! -d "$RUNTIME_PAYLOAD_ROOT/quarantine" ]]
}

@test "install refuses to overwrite or repair a corrupt deterministic target" {
    local resource before after
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    resource="$CODEX_TARGET/payload/node_modules/@openai/codex/resource with spaces.txt"
    chmod 700 "$resource"
    printf '%s\n' 'tampered after install' >> "$resource"
    chmod 500 "$resource"
    before="$(relative_tree_snapshot "$CODEX_TARGET")"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"corrupt"* || "$output" == *"refus"* ]]
    after="$(relative_tree_snapshot "$CODEX_TARGET")"
    [[ "$after" == "$before" ]]
    [[ -d "$CODEX_TARGET" ]]
    [[ ! -d "$RUNTIME_PAYLOAD_ROOT/quarantine" ]]
    [[ ! -e "$VENDOR_LOG" ]]

    run mf host status codex --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .hosts[0].managed.state == "corrupt" and
      .hosts[0].selection.state == "blocked"
    ' <<< "$output"
}

@test "remove quarantines one byte-identical private generation for recovery" {
    local before quarantine_base removed_dir quarantine_id generation path
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    before="$(relative_tree_snapshot "$CODEX_TARGET")"

    run mf host remove codex --yes --json

    [[ "$status" -eq 0 ]]
    [[ ! -e "$CODEX_TARGET" ]]
    quarantine_base="$RUNTIME_PAYLOAD_ROOT/quarantine/v1/codex/$CODEX_VERSION/$CODEX_PLATFORM/$CODEX_BUNDLE_ID"
    [[ -d "$quarantine_base" && ! -L "$quarantine_base" ]]
    removed_dir="$(find "$quarantine_base" -mindepth 1 -maxdepth 1 \
        -type d -name 'removed.*' -print)"
    [[ -n "$removed_dir" && "$(printf '%s\n' "$removed_dir" | wc -l | tr -d '[:space:]')" == 1 ]]
    quarantine_id="${removed_dir##*/}"
    generation="$removed_dir/generation"
    [[ -d "$generation" && ! -L "$generation" ]]
    [[ "$(relative_tree_snapshot "$generation")" == "$before" ]]
    [[ "$(file_mode "$removed_dir")" == 700 ]]
    [[ "$(file_mode "$generation")" == 700 ]]
    [[ "$(file_mode "$generation/receipt.json")" == 600 ]]
    while IFS= read -r path; do
        [[ "$(file_mode "$path")" == 500 ]]
    done < <(find "$generation/payload" -type d -o -type f)
    "$JQ_BIN" -e --arg quarantine_id "$quarantine_id" '
      .schema_version == 1 and .command == "host-remove" and
      .host == "codex" and .result == "removed" and .changed == true and
      .quarantine_id == $quarantine_id
    ' <<< "$output"
    [[ "$output" != *"$TEST_HOME"* ]]
    [[ "$output" != *"$XDG_DATA_HOME"* ]]

    run mf host status codex --runtime managed --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .hosts[0].managed.state == "absent" and
      .hosts[0].selection.state == "unavailable"
    ' <<< "$output"
}

@test "remove of an absent generation is an idempotent no-op" {
    run mf host remove codex --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .schema_version == 1 and .command == "host-remove" and
      .host == "codex" and .result == "already-absent" and
      .changed == false and .quarantine_id == null
    ' <<< "$output"
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "human remove prints one copyable exact-ID restore preview" {
    local quarantine_id
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null

    run mf host remove codex --yes

    [[ "$status" -eq 0 ]]
    quarantine_id="$(sed -n 's/^Quarantine ID: //p' <<< "$output")"
    [[ "$quarantine_id" =~ ^removed\.[0-9a-f]{18}$ ]]
    [[ "$output" == *"Restore preview: mainframe host restore codex --quarantine-id $quarantine_id --dry-run"* ]]
}

@test "remove JSON failure is a closed consent envelope" {
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null

    run mf host remove codex --json

    [[ "$status" -eq 2 ]]
    "$JQ_BIN" -e '
      .command == "host-remove" and .host == "codex" and
      .result == "error" and .changed == false and
      .mutation_state == "unchanged" and .source == null and
      .network_attempted == false and .archive_count == 0 and
      .error.code == "consent-required"
    ' <<< "$output"
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ "$output" != *"MAINFRAME host:"* ]]
}

@test "restore help and grammar require one exact generated quarantine ID" {
    local valid_id='removed.0123456789abcdef01'

    run mf host restore --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe host restore HOST --quarantine-id"* ]]
    [[ "$output" == *"offline"* ]]

    run mf host restore
    [[ "$status" -eq 2 ]]

    run mf host restore codex
    [[ "$status" -eq 2 ]]

    run mf host restore codex --quarantine-id removed.too-short --json
    [[ "$status" -eq 2 ]]
    "$JQ_BIN" -e '
      .command == "host-restore" and .host == "codex" and
      .result == "error" and .changed == false and
      .mutation_state == "unchanged" and .quarantine_id == null and
      .error.code == "quarantine-id-invalid"
    ' <<< "$output"

    run mf host restore codex --quarantine-id "$valid_id" \
        --quarantine-id "$valid_id" --yes
    [[ "$status" -eq 2 ]]

    run mf host restore codex --quarantine-id "$valid_id" --dry-run --yes
    [[ "$status" -eq 2 ]]

    run mf host restore unknown --quarantine-id "$valid_id" --yes
    [[ "$status" -eq 2 ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "restore dry-run fully authenticates one generation without mutation" {
    local before identity
    install_and_quarantine_codex
    before="$(relative_tree_snapshot "$QUARANTINE_GENERATION")"
    identity="$(path_identity "$QUARANTINE_GENERATION")"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --dry-run --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .schema_version == 1 and .command == "host-restore" and
      .mode == "managed-quarantine-restore" and .host == "codex" and
      .result == "would-restore" and .changed == false and
      .source == null and .network_attempted == false and
      .archive_count == 0 and .network.used == false and
      .network.package_count == 0 and .quarantine_id == $quarantine_id
    ' <<< "$output"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ "$(path_identity "$QUARANTINE_GENERATION")" == "$identity" ]]
    [[ "$(relative_tree_snapshot "$QUARANTINE_GENERATION")" == "$before" ]]
    [[ ! -e "$COMMAND_LOG" && ! -e "$VENDOR_LOG" ]]
}

@test "restore atomically republishes the exact quarantined generation" {
    local before identity
    install_and_quarantine_codex
    before="$(relative_tree_snapshot "$QUARANTINE_GENERATION")"
    identity="$(path_identity "$QUARANTINE_GENERATION")"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .schema_version == 1 and .command == "host-restore" and
      .mode == "managed-quarantine-restore" and .host == "codex" and
      .result == "restored" and .changed == true and
      .source == null and .network_attempted == false and
      .archive_count == 0 and .quarantine_id == $quarantine_id
    ' <<< "$output"
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ "$(path_identity "$CODEX_TARGET")" == "$identity" ]]
    [[ "$(relative_tree_snapshot "$CODEX_TARGET")" == "$before" ]]
    [[ ! -e "$QUARANTINE_GENERATION" && ! -L "$QUARANTINE_GENERATION" ]]
    [[ -d "$QUARANTINE_SLOT" && ! -L "$QUARANTINE_SLOT" ]]
    [[ -z "$(find "$QUARANTINE_SLOT" -mindepth 1 -print -quit)" ]]

    run mf host status codex --runtime managed --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .hosts[0].managed.state == "ready" and
      .hosts[0].selection.state == "ready" and
      .hosts[0].selection.source == "managed"
    ' <<< "$output"
}

@test "restore requires consent and refuses both ready and corrupt active targets" {
    local quarantine_identity resource
    install_and_quarantine_codex
    quarantine_identity="$(path_identity "$QUARANTINE_GENERATION")"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --json
    [[ "$status" -eq 2 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .command == "host-restore" and .result == "error" and
      .changed == false and .mutation_state == "unchanged" and
      .quarantine_id == $quarantine_id and
      .error.code == "consent-required"
    ' <<< "$output"

    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json
    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e '
      .command == "host-restore" and .changed == false and
      .mutation_state == "unchanged" and .error.code == "target-present"
    ' <<< "$output"
    [[ "$(path_identity "$QUARANTINE_GENERATION")" == "$quarantine_identity" ]]

    resource="$CODEX_TARGET/payload/node_modules/@openai/codex/resource with spaces.txt"
    chmod 700 "$resource"
    printf '%s\n' tampered >> "$resource"
    chmod 500 "$resource"
    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json
    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e '.error.code == "target-present" and .changed == false' <<< "$output"
    [[ "$(path_identity "$QUARANTINE_GENERATION")" == "$quarantine_identity" ]]
}

@test "restore rejects missing and tampered quarantine generations with finite JSON" {
    local missing='removed.ffffffffffffffffff'
    install_and_quarantine_codex

    run mf host restore codex --quarantine-id "$missing" --dry-run --json
    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e --arg quarantine_id "$missing" '
      .command == "host-restore" and .changed == false and
      .quarantine_id == $quarantine_id and
      .error.code == "quarantine-not-found"
    ' <<< "$output"

    chmod 700 "$QUARANTINE_GENERATION/receipt.json"
    printf '%s\n' tampered >> "$QUARANTINE_GENERATION/receipt.json"
    chmod 600 "$QUARANTINE_GENERATION/receipt.json"
    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --dry-run --json
    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .command == "host-restore" and .changed == false and
      .mutation_state == "unchanged" and .quarantine_id == $quarantine_id and
      .error.code == "quarantine-corrupt"
    ' <<< "$output"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ "$output" != *"$TEST_HOME"* && "$output" != *"$XDG_DATA_HOME"* ]]
}

@test "restore rejects symlinked or non-exact quarantine slots" {
    local moved_slot extra
    install_and_quarantine_codex
    moved_slot="$QUARANTINE_SLOT.real"
    mv "$QUARANTINE_SLOT" "$moved_slot"
    ln -s "$moved_slot" "$QUARANTINE_SLOT"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --dry-run --json
    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e '.error.code == "quarantine-corrupt" and .changed == false' <<< "$output"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]

    rm "$QUARANTINE_SLOT"
    mv "$moved_slot" "$QUARANTINE_SLOT"
    extra="$QUARANTINE_SLOT/unexpected"
    printf '%s\n' unexpected > "$extra"
    chmod 600 "$extra"
    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --dry-run --json
    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e '.error.code == "quarantine-corrupt" and .changed == false' <<< "$output"
    [[ -d "$QUARANTINE_GENERATION" && ! -L "$QUARANTINE_GENERATION" ]]
}

@test "restore refuses a target that appears while acquiring the lock" {
    local helper real_helper quarantine_identity
    install_and_quarantine_codex
    quarantine_identity="$(path_identity "$QUARANTINE_GENERATION")"
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "lock-acquire":
    root = pathlib.Path(sys.argv[2])
    sources = list(root.glob("quarantine/v1/codex/*/*/*/removed.*/generation"))
    if len(sources) != 1:
        raise SystemExit(92)
    parts = sources[0].relative_to(root).parts
    target = root.joinpath("v1", *parts[2:6])
    target.mkdir(mode=0o700)
    marker = target / "appeared-during-lock"
    descriptor = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.write(descriptor, b"do not overwrite\n")
    os.fsync(descriptor)
    os.close(descriptor)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json

    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e '
      .command == "host-restore" and .changed == false and
      .mutation_state == "unchanged" and .error.code == "target-present"
    ' <<< "$output"
    [[ -f "$CODEX_TARGET/appeared-during-lock" ]]
    [[ "$(path_identity "$QUARANTINE_GENERATION")" == "$quarantine_identity" ]]
}

@test "restore reports uncertain state when a pre-rename error cannot release its lock" {
    local helper real_helper quarantine_identity
    install_and_quarantine_codex
    quarantine_identity="$(path_identity "$QUARANTINE_GENERATION")"
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
command = sys.argv[1] if len(sys.argv) >= 2 else ""
if command == "lock-release" and len(sys.argv) >= 5:
    lock = pathlib.Path(sys.argv[2]) / sys.argv[4]
    blocker = lock / "release-blocker"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(blocker, flags, 0o600)
    os.write(descriptor, b"force pre-rename lock release failure\n")
    os.fsync(descriptor)
    os.close(descriptor)
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if command == "lock-acquire":
    root = pathlib.Path(sys.argv[2])
    sources = list(root.glob("quarantine/v1/codex/*/*/*/removed.*/generation"))
    if len(sources) != 1:
        raise SystemExit(92)
    parts = sources[0].relative_to(root).parts
    target = root.joinpath("v1", *parts[2:6])
    target.mkdir(mode=0o700)
    marker = target / "appeared-during-lock"
    descriptor = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.write(descriptor, b"do not overwrite\n")
    os.fsync(descriptor)
    os.close(descriptor)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json

    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .command == "host-restore" and .result == "error" and
      .changed == null and .mutation_state == "uncertain" and
      .quarantine_id == $quarantine_id and .error.code == "lifecycle-failed"
    ' <<< "$output"
    [[ -f "$CODEX_TARGET/appeared-during-lock" ]]
    [[ "$(path_identity "$QUARANTINE_GENERATION")" == "$quarantine_identity" ]]
    [[ -f "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock/release-blocker" ]]
}

@test "restore refuses source identity substitution while acquiring the lock" {
    local helper real_helper original_identity
    install_and_quarantine_codex
    original_identity="$(path_identity "$QUARANTINE_GENERATION")"
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import shutil
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "lock-acquire":
    root = pathlib.Path(sys.argv[2])
    sources = list(root.glob("quarantine/v1/codex/*/*/*/removed.*/generation"))
    if len(sources) != 1:
        raise SystemExit(92)
    source = sources[0]
    displaced = root / ".restore-race-original"
    source.rename(displaced)
    shutil.copytree(displaced, source, copy_function=shutil.copy2)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json

    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e '
      .command == "host-restore" and .changed == false and
      .mutation_state == "unchanged" and .error.code == "unsafe-state"
    ' <<< "$output"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -d "$QUARANTINE_GENERATION" && ! -L "$QUARANTINE_GENERATION" ]]
    [[ "$(path_identity "$QUARANTINE_GENERATION")" != "$original_identity" ]]
    [[ -d "$RUNTIME_PAYLOAD_ROOT/.restore-race-original" ]]
}

@test "restore JSON is uncertain when the helper fails after rename" {
    local helper real_helper
    install_and_quarantine_codex
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
if completed.returncode != 0:
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "move":
    raise SystemExit(91)
sys.stdout.write(completed.stdout)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json

    [[ "$status" -ne 0 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .command == "host-restore" and .result == "error" and
      .changed == null and .mutation_state == "uncertain" and
      .quarantine_id == $quarantine_id and .error.code == "lifecycle-failed"
    ' <<< "$output"
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ ! -e "$QUARANTINE_GENERATION" && ! -L "$QUARANTINE_GENERATION" ]]
}

@test "real TERM before restore rename emits a finite exact-ID recovery envelope" {
    local helper real_helper quarantine_identity
    install_and_quarantine_codex
    quarantine_identity="$(path_identity "$QUARANTINE_GENERATION")"
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import signal
import subprocess
import sys
import time

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
if len(sys.argv) >= 2 and sys.argv[1] == "move":
    lifecycle_pid = int(os.environ["MAINFRAME_HOST_LIFECYCLE_PID"])
    os.kill(lifecycle_pid, signal.SIGTERM)
    time.sleep(0.1)
    raise SystemExit(90)
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
raise SystemExit(completed.returncode)
PY
    chmod 600 "$helper"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json

    [[ "$status" -eq 143 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .command == "host-restore" and .result == "error" and
      .changed == null and .mutation_state == "uncertain" and
      .quarantine_id == $quarantine_id and .error.code == "interrupted"
    ' <<< "$output"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ "$(path_identity "$QUARANTINE_GENERATION")" == "$quarantine_identity" ]]
    [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
       ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
}

@test "restore reports changed when lock release fails after known rename" {
    local helper real_helper
    install_and_quarantine_codex
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 3 and sys.argv[1] == "move":
    lock = pathlib.Path(sys.argv[2]) / ".lifecycle-lock"
    blocker = lock / "release-blocker"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(blocker, flags, 0o600)
    os.write(descriptor, b"force owned lock release failure\n")
    os.fsync(descriptor)
    os.close(descriptor)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host restore codex --quarantine-id "$QUARANTINE_ID" --yes --json

    [[ "$status" -ne 0 ]]
    "$JQ_BIN" -e --arg quarantine_id "$QUARANTINE_ID" '
      .command == "host-restore" and .result == "error" and
      .changed == true and .mutation_state == "changed" and
      .quarantine_id == $quarantine_id and .error.code == "lifecycle-failed"
    ' <<< "$output"
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -f "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock/release-blocker" ]]
}

@test "JSON reports uncertain mutation when quarantine helper fails after rename" {
    local helper real_helper quarantine_base quarantine_id removed_dir
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
if completed.returncode != 0:
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "quarantine":
    raise SystemExit(91)
sys.stdout.write(completed.stdout)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host remove codex --yes --json

    [[ "$status" -ne 0 ]]
    "$JQ_BIN" -e '
      .command == "host-remove" and .result == "error" and
      .changed == null and .mutation_state == "uncertain" and
      (.quarantine_id | type == "string" and
        test("^removed\\.[0-9a-f]{18}$")) and
      .error.code == "lifecycle-failed"
    ' <<< "$output"
    quarantine_id="$($JQ_BIN -er '.quarantine_id' <<< "$output")"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    quarantine_base="$RUNTIME_PAYLOAD_ROOT/quarantine/v1/codex/$CODEX_VERSION/$CODEX_PLATFORM/$CODEX_BUNDLE_ID"
    [[ -d "$quarantine_base" && ! -L "$quarantine_base" ]]
    removed_dir="$quarantine_base/$quarantine_id"
    [[ -d "$removed_dir/generation" && ! -L "$removed_dir/generation" ]]
    [[ -f "$removed_dir/generation/receipt.json" && ! -L "$removed_dir/generation/receipt.json" ]]

    run mf host restore codex --quarantine-id "$quarantine_id" --dry-run --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e --arg quarantine_id "$quarantine_id" '
      .command == "host-restore" and .result == "would-restore" and
      .changed == false and .quarantine_id == $quarantine_id
    ' <<< "$output"
}

@test "real INT and TERM before quarantine rename emit finite recovery envelopes" {
    local expected_status helper quarantine_base quarantine_id real_helper
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import signal
import subprocess
import sys
import time

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
state = pathlib.Path(__file__).with_name("managed-host-signal-count")
command = sys.argv[1] if len(sys.argv) >= 2 else ""
if command == "quarantine":
    count = int(state.read_text(encoding="ascii")) if state.exists() else 0
    state.write_text(str(count + 1), encoding="ascii")
    lifecycle_pid = int(os.environ["MAINFRAME_HOST_LIFECYCLE_PID"])
    signum = signal.SIGINT if count == 0 else signal.SIGTERM
    os.kill(lifecycle_pid, signum)
    time.sleep(0.1)
    raise SystemExit(90)
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
raise SystemExit(completed.returncode)
PY
    chmod 600 "$helper"
    quarantine_base="$RUNTIME_PAYLOAD_ROOT/quarantine/v1/codex/$CODEX_VERSION/$CODEX_PLATFORM/$CODEX_BUNDLE_ID"

    for expected_status in 130 143; do
        run mf host remove codex --yes --json

        [[ "$status" -eq "$expected_status" ]]
        "$JQ_BIN" -e '
          .command == "host-remove" and .result == "error" and
          .changed == null and .mutation_state == "uncertain" and
          (.quarantine_id | type == "string" and
            test("^removed\\.[0-9a-f]{18}$")) and
          .error.code == "interrupted"
        ' <<< "$output"
        quarantine_id="$($JQ_BIN -er '.quarantine_id' <<< "$output")"
        [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
        [[ ! -e "$quarantine_base/$quarantine_id" &&
           ! -L "$quarantine_base/$quarantine_id" ]]
        [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
           ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
    done
}

@test "TERM after lock creation is deferred until the owned lock is published and cleaned" {
    local helper real_helper
    make_codex_package_dir
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import signal
import subprocess
import sys
import time

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "lock-acquire":
    sys.stdout.flush()
    lifecycle_pid = int(os.environ["MAINFRAME_HOST_LIFECYCLE_PID"])
    os.kill(lifecycle_pid, signal.SIGTERM)
    time.sleep(0.1)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -eq 143 ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "error" and
      .[0].changed == true and .[0].mutation_state == "changed" and
      .[0].error.code == "interrupted"
    ' <<< "$output"
    [[ "$output" != *"$RUNTIME_PAYLOAD_ROOT"* ]]
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
       ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
}

@test "failed lock identity publication reports an uncertain mutation" {
    local helper real_helper
    make_codex_package_dir
    mkdir -p "$RUNTIME_PAYLOAD_ROOT"
    chmod 700 "$XDG_DATA_HOME" "$XDG_DATA_HOME/mainframe" "$RUNTIME_PAYLOAD_ROOT"
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
if len(sys.argv) >= 2 and sys.argv[1] == "lock-acquire":
    lock = pathlib.Path(sys.argv[2]) / sys.argv[4]
    lock.mkdir(mode=0o700)
    raise SystemExit(91)
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
)
raise SystemExit(completed.returncode)
PY
    chmod 600 "$helper"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "error" and
      .[0].changed == null and .[0].mutation_state == "uncertain" and
      .[0].error.code == "lifecycle-failed"
    ' <<< "$output"
    [[ -d "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
}

@test "process-group TERM cannot kill the lock helper before owned cleanup" {
    local helper python_bin real_helper
    make_codex_package_dir
    python_bin="$(command -v python3)"
    [[ -x "$python_bin" ]] || skip "process-group harness requires Python 3"
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import signal
import subprocess
import sys
import time

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "lock-acquire":
    sys.stdout.flush()
    os.killpg(os.getpgrp(), signal.SIGTERM)
    time.sleep(0.1)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run env \
        PATH="$DISCOVERY_PATH" \
        HOME="$TEST_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        MAINFRAME_BASH="$BASH_BIN" \
        HOST_LIFECYCLE_EXEC_LOG="$VENDOR_LOG" \
        "$python_bin" -I -S -B - "$BASH_BIN" \
        "$RUNTIME_ROOT/bin/mainframe" "$PACKAGE_DIR" <<'PY'
import subprocess
import sys

completed = subprocess.run(
    [
        sys.argv[1],
        "--noprofile",
        "--norc",
        "-p",
        sys.argv[2],
        "host",
        "install",
        "codex",
        "--package-dir",
        sys.argv[3],
        "--yes",
        "--json",
    ],
    check=False,
    capture_output=True,
    text=True,
    start_new_session=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
status = completed.returncode
if status < 0:
    status = 128 + (-status)
raise SystemExit(status)
PY

    [[ "$status" -eq 143 ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "error" and
      .[0].changed == true and .[0].mutation_state == "changed" and
      .[0].error.code == "interrupted"
    ' <<< "$output"
    [[ "$output" != *"$RUNTIME_PAYLOAD_ROOT"* ]]
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
       ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
}

@test "TERM during workspace identity publication cleans the exact stage" {
    local helper marker real_helper
    make_codex_package_dir
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    marker="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-workspace-signal"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import signal
import subprocess
import sys
import time

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
marker = pathlib.Path(__file__).with_name("managed-host-workspace-signal")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "workspace-create":
    marker.write_text("sent\n", encoding="ascii")
    sys.stdout.flush()
    lifecycle_pid = int(os.environ["MAINFRAME_HOST_LIFECYCLE_PID"])
    os.kill(lifecycle_pid, signal.SIGTERM)
    time.sleep(0.1)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -eq 143 ]]
    [[ -e "$marker" ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "error" and
      .[0].changed == true and .[0].mutation_state == "changed" and
      .[0].error.code == "interrupted"
    ' <<< "$output"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
       ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
    [[ -z "$(find "$RUNTIME_PAYLOAD_ROOT" -maxdepth 1 \
        -name '.install-stage.*' -print -quit)" ]]
}

@test "workspace acquisition has no post-mktemp shell identity gap" {
    local before after
    make_codex_package_dir
    before="$(find /tmp -maxdepth 1 -name 'mainframe-host-stage.*' \
        -type d -print 2>/dev/null | LC_ALL=C sort)"

    run env \
        PATH="$DISCOVERY_PATH" \
        HOME="$TEST_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        MAINFRAME_BASH="$BASH_BIN" \
        HOST_LIFECYCLE_EXEC_LOG="$VENDOR_LOG" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/common.sh"
          source "$1/lib/activate.sh"
          source "$1/lib/launch.sh"
          source "$1/lib/host_runtime.sh"
          source "$1/lib/host_lifecycle.sh"
          shift
          original_stat_definition="$(declare -f _mainframe_host_stat_identity)"
          eval "${original_stat_definition/_mainframe_host_stat_identity/_mainframe_host_stat_identity_real}"
          _mainframe_host_stat_identity() {
              if [[ "$1" == *"/mainframe-host-stage."* &&
                    -z "${_MAINFRAME_HOST_LIFECYCLE_WORKSPACE_IDENTITY:-}" ]]; then
                  return 91
              fi
              _mainframe_host_stat_identity_real "$1"
          }
          _mainframe_host_install "$@"
        ' _ "$RUNTIME_ROOT" codex --package-dir "$PACKAGE_DIR" --dry-run --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "would-install" and
      .[0].changed == false
    ' <<< "$output"
    after="$(find /tmp -maxdepth 1 -name 'mainframe-host-stage.*' \
        -type d -print 2>/dev/null | LC_ALL=C sort)"
    [[ "$after" == "$before" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "workspace record remains cleanable when helper exits after publication" {
    local helper real_helper
    make_codex_package_dir
    mkdir -p "$RUNTIME_PAYLOAD_ROOT"
    chmod 700 "$XDG_DATA_HOME" "$XDG_DATA_HOME/mainframe" "$RUNTIME_PAYLOAD_ROOT"
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stdout.flush()
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "workspace-create":
    raise SystemExit(91)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -eq 1 ]]
    "$JQ_BIN" -e -s '
      length == 1 and
      .[0].command == "host-install" and .[0].result == "error" and
      .[0].changed == false and .[0].mutation_state == "unchanged" and
      .[0].error.code == "lifecycle-failed"
    ' <<< "$output"
    [[ -z "$(find "$RUNTIME_PAYLOAD_ROOT" -maxdepth 1 \
        -name '.install-stage.*' -print -quit)" ]]
    [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
       ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
}

@test "terminal JSON serialization ignores a deferred signal after its first envelope" {
    local mode
    for mode in success error; do
        run env \
            PATH="$DISCOVERY_PATH" \
            MAINFRAME_ROOT="$RUNTIME_ROOT" \
            "$BASH_BIN" --noprofile --norc -p -c '
              source "$1/lib/common.sh"
              source "$1/lib/activate.sh"
              source "$1/lib/launch.sh"
              source "$1/lib/host_runtime.sh"
              source "$1/lib/host_lifecycle.sh"
              terminal_kind="$2"
              sent_signal=false
              _MAINFRAME_HOST_LIFECYCLE_OPERATION_PID="${BASHPID:-$$}"
              _MAINFRAME_HOST_LIFECYCLE_JSON=true
              _MAINFRAME_HOST_LIFECYCLE_ERROR_COMMAND=host-install
              _MAINFRAME_HOST_LIFECYCLE_HOST=codex
              _MAINFRAME_HOST_EXPECTED_VERSION=1.2.3
              _MAINFRAME_HOST_EXPECTED_PLATFORM=test-platform
              _MAINFRAME_HOST_EXPECTED_BUNDLE_ID=fixture-bundle
              _MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA=fixture-package-set
              _mainframe_enforce_bind_jq() { return 0; }
              _mainframe_enforce_jq() {
                  printf "{\\\"terminal\\\":\\\"%s\\\"}\\n" "$terminal_kind"
                  if [[ "$sent_signal" == false ]]; then
                      sent_signal=true
                      kill -TERM "$_MAINFRAME_HOST_LIFECYCLE_OPERATION_PID"
                  fi
                  return 0
              }
              trap "_mainframe_host_lifecycle_on_signal 143" TERM
              if [[ "$terminal_kind" == success ]]; then
                  _mainframe_host_lifecycle_emit_json \
                      host-install codex installed true
              else
                  _MAINFRAME_HOST_LIFECYCLE_ERROR_CODE=E_STATE
                  _mainframe_host_lifecycle_emit_error_json
              fi
            ' _ "$PROJECT_ROOT" "$mode"

        [[ "$status" -eq 0 ]]
        [[ "$output" == "{\"terminal\":\"$mode\"}" ]]
    done
}

@test "real TERM after quarantine rename prints the exact recovery ID" {
    local helper quarantine_base quarantine_id real_helper
    make_codex_package_dir
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import signal
import subprocess
import sys
import time

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
if completed.returncode != 0:
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "quarantine":
    sys.stdout.write(completed.stdout)
    sys.stdout.flush()
    lifecycle_pid = int(os.environ["MAINFRAME_HOST_LIFECYCLE_PID"])
    os.kill(lifecycle_pid, signal.SIGTERM)
    time.sleep(0.1)
    raise SystemExit(0)
sys.stdout.write(completed.stdout)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host remove codex --yes

    [[ "$status" -eq 143 ]]
    [[ "$output" == *"managed-host lifecycle operation was interrupted"* ]]
    quarantine_id="$(sed -n 's/^Recovery ID: //p' <<< "$output")"
    [[ "$quarantine_id" =~ ^removed\.[0-9a-f]{18}$ ]]
    [[ "$output" == *"mainframe host status codex"* ]]
    [[ "$output" == *"mainframe host restore codex --quarantine-id $quarantine_id --dry-run"* ]]
    quarantine_base="$RUNTIME_PAYLOAD_ROOT/quarantine/v1/codex/$CODEX_VERSION/$CODEX_PLATFORM/$CODEX_BUNDLE_ID"
    [[ ! -e "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -d "$quarantine_base/$quarantine_id/generation" &&
       ! -L "$quarantine_base/$quarantine_id/generation" ]]
    [[ ! -e "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" &&
       ! -L "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock" ]]
}

@test "managed Gemini installation remains unsupported before package inspection" {
    run mf host install gemini --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"unsupported"* || "$output" == *"gated"* ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    [[ ! -e "$COMMAND_LOG" ]]
    [[ ! -e "$VENDOR_LOG" ]]
}

@test "lifecycle never invokes npm curl or package and vendor executables" {
    local removal quarantine_id
    make_command_traps
    make_codex_package_dir

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes
    [[ "$status" -eq 0 ]]
    [[ ! -e "$COMMAND_LOG" ]]
    [[ ! -e "$VENDOR_LOG" ]]

    run mf host remove codex --yes --json
    [[ "$status" -eq 0 ]]
    removal="$output"
    quarantine_id="$($JQ_BIN -er '.quarantine_id' <<< "$removal")"
    run mf host restore codex --quarantine-id "$quarantine_id" --yes
    [[ "$status" -eq 0 ]]
    [[ ! -e "$COMMAND_LOG" ]]
    [[ ! -e "$VENDOR_LOG" ]]
}

@test "managed bundle identity changes when only the MAINFRAME version changes" {
    local manifest_before lock_before first second first_bundle second_bundle temporary
    manifest_before="$(sha256_file \
        "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json")"
    lock_before="$(sha256_file \
        "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json")"
    first="$(expected_details codex)"
    first_bundle="$(sed -n 's/^bundle_id=//p' <<< "$first")"
    [[ "$first_bundle" =~ ^[0-9a-f]{64}$ ]]

    # The fixture normally symlinks the source lib directory. Make this test's
    # copy private before simulating the release version sync performed by
    # scripts/sync-version.sh.
    rm "$RUNTIME_ROOT/lib"
    cp -R "$PROJECT_ROOT/lib" "$RUNTIME_ROOT/lib"
    temporary="$TEST_DIR/common.changed-version.sh"
    sed 's/^readonly MAINFRAME_VERSION="[^"]*"/readonly MAINFRAME_VERSION="99.99.99"/' \
        "$RUNTIME_ROOT/lib/common.sh" > "$temporary"
    mv "$temporary" "$RUNTIME_ROOT/lib/common.sh"
    printf '%s\n' '99.99.99' > "$RUNTIME_ROOT/VERSION"
    second="$(expected_details codex)"
    second_bundle="$(sed -n 's/^bundle_id=//p' <<< "$second")"

    [[ "$second_bundle" =~ ^[0-9a-f]{64}$ ]]
    [[ "$second_bundle" != "$first_bundle" ]]
    [[ "$(sha256_file "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json")" == \
       "$manifest_before" ]]
    [[ "$(sha256_file "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json")" == \
       "$lock_before" ]]
}

@test "filesystem helper refuses destination substitution without moving either tree" {
    local root source target root_identity source_identity target_identity python_bin
    root="$TEST_DIR/private transaction root"
    source="$root/stage/generation"
    target="$root/v1/codex"
    python_bin="$(command -v python3)"
    mkdir -p "$source" "$target"
    chmod 700 "$root" "$root/stage" "$source" "$root/v1" "$target"
    printf '%s\n' source > "$source/source-marker"
    printf '%s\n' target > "$target/target-marker"
    chmod 500 "$source/source-marker" "$target/target-marker"
    root_identity="$(path_identity "$root")"
    source_identity="$(path_identity "$source")"
    target_identity="$(path_identity "$target")"

    run env -i PATH=/usr/bin:/bin LC_ALL=C \
        "$python_bin" -I -S -B \
        "$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py" \
        move "$root" "$root_identity" \
        stage/generation v1/codex "$source_identity"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"destination already exists"* ]]
    [[ "$(path_identity "$source")" == "$source_identity" ]]
    [[ "$(path_identity "$target")" == "$target_identity" ]]
    [[ "$(< "$source/source-marker")" == source ]]
    [[ "$(< "$target/target-marker")" == target ]]
}

@test "filesystem helper generates exact recovery IDs and refuses slot collisions" {
    local helper python_bin quarantine_id root root_identity slot source source_identity
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    python_bin="$(command -v python3)"

    run env -i PATH=/usr/bin:/bin LC_ALL=C \
        "$python_bin" -I -S -B "$helper" quarantine-id

    [[ "$status" -eq 0 ]]
    quarantine_id="$output"
    [[ "$quarantine_id" =~ ^removed\.[0-9a-f]{18}$ ]]

    root="$TEST_DIR/private quarantine collision root"
    source="$root/stage/generation"
    slot="$root/quarantine/$quarantine_id"
    mkdir -p "$source" "$slot"
    chmod 700 "$root" "$root/stage" "$source" "$root/quarantine" "$slot"
    printf '%s\n' source > "$source/source-marker"
    chmod 500 "$source/source-marker"
    root_identity="$(path_identity "$root")"
    source_identity="$(path_identity "$source")"

    run env -i PATH=/usr/bin:/bin LC_ALL=C \
        "$python_bin" -I -S -B "$helper" quarantine \
        "$root" "$root_identity" stage/generation quarantine \
        "$quarantine_id" "$source_identity"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"quarantine destination already exists"* ]]
    [[ "$(path_identity "$source")" == "$source_identity" ]]
    [[ "$(< "$source/source-marker")" == source ]]
    [[ -d "$slot" && ! -L "$slot" ]]
    [[ ! -e "$slot/generation" && ! -L "$slot/generation" ]]
}

@test "filesystem helper rolls back created state whose identity record cannot publish" {
    local operation parent parent_identity python_bin
    parent="$TEST_DIR/workspace transaction parent"
    mkdir -m 700 "$parent"
    parent="$(cd "$parent" && pwd -P)"
    parent_identity="$(path_identity "$parent")"
    python_bin="$(command -v python3)"
    [[ -x "$python_bin" ]] || skip "workspace helper rollback requires Python 3"

    for operation in workspace lock; do
        run "$python_bin" -I -S -B - \
            "$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py" \
            "$parent" "$parent_identity" "$operation" <<'PY'
import os
import subprocess
import sys

read_descriptor, write_descriptor = os.pipe()
os.close(read_descriptor)
if sys.argv[4] == "workspace":
    arguments = [
        "workspace-create",
        sys.argv[2],
        sys.argv[3],
        "managed",
    ]
else:
    arguments = [
        "lock-acquire",
        sys.argv[2],
        sys.argv[3],
        ".lifecycle-lock",
        str(os.getpid()),
    ]
completed = subprocess.run(
    [
        sys.executable,
        "-I",
        "-S",
        "-B",
        sys.argv[1],
        *arguments,
    ],
    check=False,
    stdout=write_descriptor,
    stderr=subprocess.PIPE,
    text=True,
)
os.close(write_descriptor)
raise SystemExit(0 if completed.returncode != 0 else 1)
PY

        [[ "$status" -eq 0 ]]
        [[ -z "$(find "$parent" -mindepth 1 -maxdepth 1 -print -quit)" ]]
    done
}

@test "filesystem helper rolls back first post-mkdir metadata failures" {
    local parent python_bin
    parent="$TEST_DIR/workspace metadata failure parent"
    mkdir -m 700 "$parent"
    parent="$(cd "$parent" && pwd -P)"
    python_bin="$(command -v python3)"
    [[ -x "$python_bin" ]] || skip "filesystem helper rollback requires Python 3"

    run "$python_bin" -I -S -B - \
        "$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py" \
        "$parent" <<'PY'
import errno
import importlib.util
import os
import pathlib
import sys

helper = pathlib.Path(sys.argv[1])
parent = pathlib.Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("managed_host_fs_under_test", helper)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

def path_identity(path):
    metadata = path.stat()
    return f"{metadata.st_dev}:{metadata.st_ino}"

original_stat_at = module.stat_at

def run_case(operation):
    calls = 0

    def failing_stat_at(descriptor, name):
        nonlocal calls
        calls += 1
        failure_call = 1 if operation == "workspace" else 2
        if calls == failure_call:
            raise OSError(errno.EIO, "injected post-mkdir metadata failure")
        return original_stat_at(descriptor, name)

    module.stat_at = failing_stat_at
    try:
        if operation == "workspace":
            module.create_workspace(str(parent), path_identity(parent), "managed")
        else:
            module.acquire_lock(
                str(parent), path_identity(parent), ".lifecycle-lock", str(os.getpid())
            )
    except OSError as exc:
        assert exc.errno == errno.EIO
    else:
        raise AssertionError(f"{operation} unexpectedly succeeded")
    finally:
        module.stat_at = original_stat_at
    assert not list(parent.iterdir()), f"{operation} left created state behind"

run_case("workspace")
run_case("lock")
PY

    [[ "$status" -eq 0 ]]
    [[ -z "$(find "$parent" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}

@test "managed extractor rejects implicit-parent case collisions" {
    local archive destination integrity python_bin version
    archive="$TEST_DIR/case-collision.tgz"
    destination="$TEST_DIR/case-collision destination"
    python_bin="$(command -v python3)"
    version='1.2.3'
    mkdir -p "$destination"
    # Construct the two spellings directly so this regression also works on
    # the default case-insensitive macOS filesystem.
    "$python_bin" -I -S -B - "$archive" "$version" <<'PY'
import io
import json
import sys
import tarfile

archive, version = sys.argv[1:]
members = [
    ("package", None),
    ("package/A", None),
    ("package/A/x", b"upper\n"),
    ("package/a", None),
    ("package/a/y", b"lower\n"),
    (
        "package/package.json",
        json.dumps({"name": "@openai/codex", "version": version}).encode() + b"\n",
    ),
]
with tarfile.open(archive, "w:gz", format=tarfile.USTAR_FORMAT) as output:
    for name, data in members:
        info = tarfile.TarInfo(name)
        info.mtime = 0
        if data is None:
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            output.addfile(info)
        else:
            info.mode = 0o644
            info.size = len(data)
            output.addfile(info, io.BytesIO(data))
PY
    integrity="$(npm_sri_sha512 "$archive")"

    run env -i PATH=/usr/bin:/bin LC_ALL=C \
        "$python_bin" -I -S -B \
        "$RUNTIME_ROOT/scripts/dev/native-host/extract-managed-package.py" \
        "$archive" "$destination" "$integrity" '@openai/codex' "$version"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"case-colliding"* ]]
}

@test "owned lifecycle lock substitution makes release fail closed" {
    local runtime_root lock original root_identity lock_identity owner python_bin
    runtime_root="$TEST_DIR/substituted lock root"
    lock="$runtime_root/.lifecycle-lock"
    original="$runtime_root/.lifecycle-lock.original"
    owner="$$"
    python_bin="$(command -v python3)"
    mkdir -p "$runtime_root"
    chmod 700 "$runtime_root"
    mkdir -m 700 "$lock"
    printf '%s\n' "$owner" > "$lock/owner"
    chmod 600 "$lock/owner"
    root_identity="$(path_identity "$runtime_root")"
    lock_identity="$(path_identity "$lock")"
    mv "$lock" "$original"
    mkdir -m 700 "$lock"
    printf '%s\n' "$owner" > "$lock/owner"
    chmod 600 "$lock/owner"

    run env -i PATH=/usr/bin:/bin LC_ALL=C \
        "$python_bin" -I -S -B \
        "$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py" \
        lock-release "$runtime_root" "$root_identity" \
        .lifecycle-lock "$lock_identity" "$owner"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"identity changed"* || "$output" == *"substituted"* ]]
    [[ "$output" != *'"result"'* ]]
    [[ "$output" != *"Installed and authenticated"* ]]
    [[ "$output" != *"Removed managed"* ]]
    [[ -d "$lock" && ! -L "$lock" ]]
    [[ -d "$original" && ! -L "$original" ]]
}

@test "CLI reports owned lock release failure without lifecycle success" {
    local helper real_helper
    make_codex_package_dir
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
if completed.returncode != 0:
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 3 and sys.argv[1] == "move":
    lock = pathlib.Path(sys.argv[2]) / ".lifecycle-lock"
    blocker = lock / "release-blocker"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(blocker, flags, 0o600)
    os.write(descriptor, b"force owned lock release failure\n")
    os.fsync(descriptor)
    os.close(descriptor)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -ne 0 ]]
    [[ "$output" != *'"result": "installed"'* ]]
    [[ "$output" != *'"result":"installed"'* ]]
    [[ "$output" != *"Installed and authenticated"* ]]
    "$JQ_BIN" -e '
      .command == "host-install" and .result == "error" and
      .changed == true and .error.code == "lifecycle-failed"
    ' <<< "$output"
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -f "$RUNTIME_PAYLOAD_ROOT/.lifecycle-lock/release-blocker" ]]
}

@test "JSON reports uncertain mutation when publication helper fails after rename" {
    local helper real_helper
    make_codex_package_dir
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
if completed.returncode != 0:
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "move":
    raise SystemExit(91)
sys.stdout.write(completed.stdout)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes --json

    [[ "$status" -ne 0 ]]
    "$JQ_BIN" -e '
      .command == "host-install" and .result == "error" and
      .changed == null and .mutation_state == "uncertain" and
      .error.code == "lifecycle-failed"
    ' <<< "$output"
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -f "$CODEX_TARGET/receipt.json" && ! -L "$CODEX_TARGET/receipt.json" ]]
}

@test "human install failure after rename directs exact managed-status recovery" {
    local helper real_helper
    make_codex_package_dir
    helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.py"
    real_helper="$RUNTIME_ROOT/scripts/dev/native-host/managed-host-fs.real.py"
    mv "$helper" "$real_helper"
    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import pathlib
import subprocess
import sys

real_helper = pathlib.Path(__file__).with_name("managed-host-fs.real.py")
completed = subprocess.run(
    [sys.executable, "-I", "-S", "-B", str(real_helper), *sys.argv[1:]],
    check=False,
    capture_output=True,
    text=True,
)
if completed.returncode != 0:
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    raise SystemExit(completed.returncode)
if len(sys.argv) >= 2 and sys.argv[1] == "move":
    raise SystemExit(91)
sys.stdout.write(completed.stdout)
raise SystemExit(0)
PY
    chmod 600 "$helper"

    run mf host install codex --package-dir "$PACKAGE_DIR" --yes

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"install outcome could not be proved"* ]]
    [[ "$output" == *"mainframe host status codex --runtime managed"* ]]
    [[ "$output" != *"Installed and authenticated"* ]]
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -f "$CODEX_TARGET/receipt.json" && ! -L "$CODEX_TARGET/receipt.json" ]]
}

@test "extractor archive-open failure is one-line redacted and traceback-free" {
    local archive destination extractor integrity python_bin line_count
    make_codex_package_dir
    archive="$CODEX_PLATFORM_ARCHIVE"
    destination="$TEST_DIR/archive-open destination"
    extractor="$RUNTIME_ROOT/scripts/dev/native-host/extract-managed-package.py"
    integrity="$(npm_sri_sha512 "$archive")"
    python_bin="$(command -v python3)"
    mkdir -p "$destination"

    run env -i PATH=/usr/bin:/bin LC_ALL=C \
        "$python_bin" -I -S -B - \
        "$extractor" "$archive" "$destination" "$integrity" <<'PY'
import errno
import importlib.util
import os
import sys

extractor, archive, destination, integrity = sys.argv[1:]
spec = importlib.util.spec_from_file_location("managed_extractor_under_test", extractor)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
real_open = module.os.open

def fail_archive_open(path, flags, *args, **kwargs):
    if os.fspath(path) == archive:
        raise OSError(errno.EACCES, "synthetic archive open failure", archive)
    return real_open(path, flags, *args, **kwargs)

module.os.open = fail_archive_open
sys.argv = [
    extractor,
    archive,
    destination,
    integrity,
    "@openai/codex",
    "1.2.3",
]
module.main()
PY

    [[ "$status" -ne 0 ]]
    line_count="$(printf '%s\n' "$output" | wc -l | tr -d '[:space:]')"
    [[ "$line_count" == 1 ]]
    [[ "$output" == "managed package extraction failed:"* ]]
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"$archive"* ]]
    [[ "$output" != *"$TEST_DIR"* ]]
    [[ -z "$(find "$destination" -mindepth 1 -print -quit)" ]]
}

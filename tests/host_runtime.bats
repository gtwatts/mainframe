#!/usr/bin/env bats
# Read-only selection and status contract for private coding-agent runtimes.

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    JQ_BIN="$(command -v jq)"
    NODE_BIN="$(command -v node)"
    JQ_DIR="${JQ_BIN%/*}"
    NODE_DIR="${NODE_BIN%/*}"
    TEST_DIR="$(create_test_dir host-runtime)"
    TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
    RUNTIME_ROOT="$TEST_DIR/mainframe runtime"
    PROJECT_DIR="$TEST_DIR/project with spaces"
    CLI_DIR="$TEST_DIR/discovery bin"
    TEST_HOME="$TEST_DIR/home"
    XDG_DATA_HOME="$TEST_DIR/xdg data"
    HOST_EXEC_LOG="$TEST_DIR/host-exec.log"
    NETWORK_LOG="$TEST_DIR/network.log"
    STATUS_DISCOVERY_PATH="$CLI_DIR:/usr/bin:/bin"
    DISCOVERY_PATH="$CLI_DIR:$JQ_DIR:$NODE_DIR:/usr/bin:/bin"

    mkdir -p \
        "$RUNTIME_ROOT/bin" \
        "$RUNTIME_ROOT/scripts/dev/native-host" \
        "$PROJECT_DIR" \
        "$CLI_DIR" \
        "$TEST_HOME"
    cp "$PROJECT_ROOT/bin/mainframe" "$RUNTIME_ROOT/bin/mainframe"
    cp "$PROJECT_ROOT/FUNCTIONS.json" "$RUNTIME_ROOT/FUNCTIONS.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/hosts.json" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/package-lock.json" \
        "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/package.json" \
        "$RUNTIME_ROOT/scripts/dev/native-host/package.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/release-platforms.json" \
        "$RUNTIME_ROOT/scripts/dev/native-host/release-platforms.json"
    cp "$PROJECT_ROOT/scripts/dev/native-host/hash-package-tree.mjs" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.mjs"
    cp "$PROJECT_ROOT/VERSION" "$RUNTIME_ROOT/VERSION"
    chmod +x \
        "$RUNTIME_ROOT/bin/mainframe" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.mjs"
    ln -s "$PROJECT_ROOT/lib" "$RUNTIME_ROOT/lib"
    ln -s "$JQ_BIN" "$CLI_DIR/jq"

    export PROJECT_ROOT BASH_BIN JQ_BIN NODE_BIN JQ_DIR NODE_DIR
    export TEST_DIR RUNTIME_ROOT PROJECT_DIR
    export CLI_DIR TEST_HOME XDG_DATA_HOME HOST_EXEC_LOG NETWORK_LOG
    export STATUS_DISCOVERY_PATH DISCOVERY_PATH
    export HOME="$TEST_HOME"
    export MAINFRAME_BASH="$BASH_BIN"
    unset MAINFRAME_AGENT_JQ MAINFRAME_HOST_RUNTIME_ROOT
    unset MAINFRAME_HOST_RUNTIME_POLICY
}

teardown() {
    if [[ -d "${XDG_DATA_HOME:-}" ]]; then
        find "$XDG_DATA_HOME" -type d -exec chmod 700 {} + 2>/dev/null || true
    fi
    cleanup_test_dir "$TEST_DIR"
}

mf() {
    env PATH="$STATUS_DISCOVERY_PATH" \
        _MAINFRAME_HOST_DISCOVERY_PATH="$STATUS_DISCOVERY_PATH" \
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

current_platform_key() {
    local host="$1" manifest_host current_os current_arch

    case "$host" in
        codex|copilot|gemini) manifest_host="$host" ;;
        claude-code) manifest_host=claude ;;
        *) return 1 ;;
    esac
    current_os="$(/usr/bin/uname -s 2>/dev/null || /bin/uname -s)" || return 1
    current_arch="$(/usr/bin/uname -m 2>/dev/null || /bin/uname -m)" || return 1
    "$JQ_BIN" -er \
        --arg host "$manifest_host" \
        --arg prefix "$current_os-$current_arch" '
          [(.[$host].platforms // {}) | keys[] |
            select(. == $prefix or startswith($prefix + "-"))] |
          if length == 0 then $prefix else first end
        ' "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"
}

pin_fake_native() {
    local host="$1" executable="$2" manifest_host platform digest temporary

    case "$host" in
        codex|copilot|gemini) manifest_host="$host" ;;
        claude-code) manifest_host=claude ;;
        *) return 1 ;;
    esac
    if [[ "$host" == gemini ]]; then
        # Gemini has no managed platform table to infer from. Its synthetic
        # direct-native pin must use the exact advertised host tuple.
        platform="$(prepare_expected "$host" | sed -n 's/^platform=//p')" || return 1
        [[ -n "$platform" ]] || return 1
    else
        platform="$(current_platform_key "$host")" || return 1
    fi
    digest="$(sha256_file "$executable")" || return 1
    temporary="$RUNTIME_ROOT/scripts/dev/native-host/hosts.json.tmp.$$"
    "$JQ_BIN" \
        --arg host "$manifest_host" \
        --arg platform "$platform" \
        --arg digest "$digest" '
          .[$host].platforms = (.[$host].platforms // {}) |
          .[$host].platforms[$platform].executable_sha256 = $digest
        ' "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json" > "$temporary" || {
        rm -f "$temporary"
        return 1
    }
    mv "$temporary" "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"
}

make_fake_system_host() {
    local host="$1" cli_name executable

    case "$host" in
        codex) cli_name=codex ;;
        claude-code) cli_name=claude ;;
        copilot) cli_name=copilot ;;
        gemini) cli_name=gemini ;;
        *) return 1 ;;
    esac
    executable="$CLI_DIR/$cli_name"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'printf "executed:%s\\n" "$0" >> "${HOST_EXEC_LOG:?}"'
        printf '%s\n' 'exit 97'
    } > "$executable"
    chmod +x "$executable"
    pin_fake_native "$host" "$executable"
}

make_valid_managed_host() {
    local host="$1" initial expected version platform manifest_platform
    local manifest_host tree_field tree_root executable target bundle_id cli_name
    local executable_sha tree_sha manifest_sha lock_sha package_set_sha mainframe_version
    local scratch temporary

    case "$host" in
        codex)
            manifest_host=codex
            tree_field=package_tree_sha256
            cli_name=codex
            ;;
        claude-code)
            manifest_host=claude
            tree_field=runtime_tree_sha256
            cli_name=claude
            ;;
        copilot)
            manifest_host=copilot
            tree_field=runtime_tree_sha256
            cli_name=copilot
            ;;
        *) return 1 ;;
    esac

    [[ -x "$NODE_BIN" ]] || return 1
    [[ -e "$CLI_DIR/node" ]] || ln -s "$NODE_BIN" "$CLI_DIR/node"

    initial="$(prepare_expected "$host")" || return 1
    version="$(sed -n 's/^version=//p' <<< "$initial")"
    platform="$(sed -n 's/^platform=//p' <<< "$initial")"
    manifest_platform="$(current_platform_key "$host")" || return 1
    tree_root="$(sed -n 's/^tree_root=//p' <<< "$initial")"
    executable="$(sed -n 's/^executable=//p' <<< "$initial")"
    [[ -n "$version" && -n "$platform" && -n "$tree_root" &&
       -n "$executable" ]] || return 1
    [[ "$tree_root" != /* && "$executable" != /* ]] || return 1

    scratch="$TEST_DIR/managed-$host-tree"
    mkdir -p "$scratch/${executable%/*}"
    mkdir -p "$scratch/$tree_root/empty resource directory"
    printf '%s\n' "synthetic $host resource" > \
        "$scratch/$tree_root/resource with spaces.txt"
    if [[ -f "$CLI_DIR/$cli_name" ]]; then
        cp "$CLI_DIR/$cli_name" "$scratch/$executable"
    else
        {
            printf '%s\n' '#!/usr/bin/env bash'
            printf '%s\n' 'printf "managed-executed:%s\\n" "$0" >> "${HOST_EXEC_LOG:?}"'
            printf '%s\n' 'exit 97'
        } > "$scratch/$executable"
    fi
    chmod +x "$scratch/$executable"
    executable_sha="$(sha256_file "$scratch/$executable")" || return 1
    tree_sha="$("$NODE_BIN" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.mjs" \
        "$scratch/$tree_root")" || return 1
    [[ "$tree_sha" =~ ^[0-9a-f]{64}$ ]] || return 1

    temporary="$RUNTIME_ROOT/scripts/dev/native-host/hosts.json.tmp.$$"
    "$JQ_BIN" \
        --arg host "$manifest_host" \
        --arg platform "$manifest_platform" \
        --arg tree_field "$tree_field" \
        --arg executable_sha "$executable_sha" \
        --arg tree_sha "$tree_sha" '
          .[$host].platforms[$platform].executable_sha256 = $executable_sha |
          .[$host].platforms[$platform][$tree_field] = $tree_sha
        ' "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json" > "$temporary" || {
        rm -f "$temporary"
        return 1
    }
    mv "$temporary" "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"

    expected="$(prepare_expected "$host")" || return 1
    target="$(sed -n 's/^target=//p' <<< "$expected")"
    bundle_id="$(sed -n 's/^bundle_id=//p' <<< "$expected")"
    tree_root="$(sed -n 's/^tree_root=//p' <<< "$expected")"
    executable="$(sed -n 's/^executable=//p' <<< "$expected")"
    [[ -n "$target" && -n "$bundle_id" ]] || return 1
    mkdir -p "$target"
    cp -R "$scratch/." "$target/"

    manifest_sha="$(sha256_file \
        "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json")" || return 1
    lock_sha="$(sha256_file \
        "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json")" || return 1
    package_set_sha="$(sed -n 's/^package_set_sha=//p' <<< "$expected")"
    [[ "$package_set_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    mainframe_version="$(tr -d '[:space:]' < "$RUNTIME_ROOT/VERSION")"
    "$JQ_BIN" -n \
        --arg bundle_id "$bundle_id" \
        --arg mainframe_version "$mainframe_version" \
        --arg host "$host" \
        --arg version "$version" \
        --arg platform "$platform" \
        --arg manifest_sha "$manifest_sha" \
        --arg lock_sha "$lock_sha" \
        --arg package_set_sha "$package_set_sha" \
        --arg tree_root "$tree_root" \
        --arg tree_sha "$tree_sha" \
        --arg executable "$executable" \
        --arg executable_sha "$executable_sha" '
          {
            schema_version: 1,
            kind: "mainframe-managed-host-payload",
            bundle_id: $bundle_id,
            mainframe_version: $mainframe_version,
            host: $host,
            host_version: $version,
            platform: $platform,
            hosts_manifest_sha256: $manifest_sha,
            package_lock_sha256: $lock_sha,
            package_set_sha256: $package_set_sha,
            tree_root: $tree_root,
            tree_sha256: $tree_sha,
            executable: $executable,
            executable_sha256: $executable_sha,
            launch_mode: "direct-native"
          }
        ' > "$target/receipt.json" || return 1

    find "$XDG_DATA_HOME" -type d -exec chmod 700 {} +
    find "$target/payload" -type d -exec chmod 500 {} +
    find "$target/payload" -type f -exec chmod 500 {} +
    chmod 500 "$target/$executable"
    chmod 600 "$target/receipt.json"
    printf '%s\n' "$target"
}

make_observer_traps() {
    local command_name

    for command_name in curl wget npm npx; do
        {
            printf '%s\n' '#!/usr/bin/env bash'
            printf '%s\n' 'printf "%s\\n" "$0 $*" >> "${NETWORK_LOG:?}"'
            printf '%s\n' 'exit 99'
        } > "$CLI_DIR/$command_name"
        chmod +x "$CLI_DIR/$command_name"
    done
}

resolve_host() {
    local host="$1" policy="$2"

    env PATH="$DISCOVERY_PATH" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        HOME="$TEST_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1/lib/common.sh"
            source "$1/lib/activate.sh"
            source "$1/lib/launch.sh"
            source "$1/lib/host_runtime.sh"
            if _mainframe_host_resolve "$2" "$3" "$4" "$5"; then
                result=0
            else
                result=$?
            fi
            printf "result=%s\\n" "$result"
            printf "managed_state=%s\\n" "${_MAINFRAME_RUNTIME_MANAGED_STATE-}"
            printf "system_state=%s\\n" "${_MAINFRAME_RUNTIME_SYSTEM_STATE-}"
            printf "selected_state=%s\\n" "${_MAINFRAME_RUNTIME_SELECTED_STATE-}"
            printf "source=%s\\n" "${_MAINFRAME_RUNTIME_SELECTED_SOURCE-}"
            printf "executable=%s\\n" "${_MAINFRAME_RUNTIME_EXECUTABLE-}"
            printf "version=%s\\n" "${_MAINFRAME_RUNTIME_VERSION-}"
            printf "identity=%s\\n" "${_MAINFRAME_RUNTIME_IDENTITY-}"
            printf "error=%s\\n" "${_MAINFRAME_RUNTIME_ERROR-}"
            exit "$result"
        ' _ "$RUNTIME_ROOT" "$host" "$PROJECT_DIR" "$policy" "$DISCOVERY_PATH"
}

prepare_expected() {
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
            printf "tree_sha=%s\\n" "${_MAINFRAME_HOST_EXPECTED_TREE_SHA-}"
            printf "executable=%s\\n" "${_MAINFRAME_HOST_EXPECTED_EXECUTABLE-}"
            printf "executable_sha=%s\\n" "${_MAINFRAME_HOST_EXPECTED_EXECUTABLE_SHA-}"
            printf "package_set_sha=%s\\n" "${_MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA-}"
            printf "bundle_id=%s\\n" "${_MAINFRAME_HOST_EXPECTED_BUNDLE_ID-}"
            printf "supported=%s\\n" "${_MAINFRAME_HOST_EXPECTED_SUPPORTED-}"
            printf "error=%s\\n" "${_MAINFRAME_HOST_EXPECTED_ERROR-}"
        ' _ "$RUNTIME_ROOT" "$host"
}

@test "host status help documents the bounded read-only offline contract" {
    run mf host status --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe host status [HOST] [--runtime auto|managed|system] [--json]"* ]]
    [[ "$output" == *"codex, claude-code, copilot, gemini"* ]]
    [[ "$output" == *"read-only"* ]]
    [[ "$output" == *"offline"* ]]
    [[ "$output" == *"managed"*"system"* ]]
}

@test "host status rejects unsupported hosts actions duplicate options and operands" {
    run mf host
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"mainframe host status"* ]]

    run mf host acquire codex
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported action"* ]]

    run mf host status unknown
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported host: unknown"* ]]

    run mf host status codex --json --json
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--json may be passed only once"* ]]

    run mf host status codex unexpected
    [[ "$status" -eq 2 ]]

    run mf host status codex --runtime newest
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported runtime policy"* ]]

    run mf host status codex --runtime auto --runtime system
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--runtime may be passed only once"* ]]
}

@test "missing all-host status is deterministic read-only and does not execute network or hosts" {
    local before after
    make_observer_traps
    before="$(find "$TEST_DIR" -mindepth 1 -print | LC_ALL=C sort)"

    run mf host status

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"codex"*"0.146.0"* ]]
    [[ "$output" == *"claude-code"*"2.1.220"* ]]
    [[ "$output" == *"copilot"*"1.0.78"* ]]
    [[ "$output" == *"gemini"*"0.53.1"* ]]
    [[ "$output" == *"absent"* ]]
    [[ ! -e "$NETWORK_LOG" ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]

    after="$(find "$TEST_DIR" -mindepth 1 -print | LC_ALL=C sort)"
    [[ "$after" == "$before" ]]
}

@test "human status offers online and offline install recovery for an absent managed Codex" {
    make_observer_traps

    run mf host status codex

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Managed:   absent"* ]]
    [[ "$output" == *"Recovery guidance:"* ]]
    [[ "$output" == *"mainframe host install codex --download --dry-run"* ]]
    [[ "$output" == *"mainframe host install codex --download --yes"* ]]
    [[ "$output" == *"mainframe host install codex --package-dir /absolute/path/to/pinned-tarballs --dry-run"* ]]
    [[ "$output" == *"mainframe host install codex --package-dir /absolute/path/to/pinned-tarballs --yes"* ]]
    [[ ! -e "$NETWORK_LOG" ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "Gemini human status never suggests an unsupported managed install" {
    run mf host status gemini

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Managed:   unsupported"* ]]
    [[ "$output" == *"No complete managed runtime is certified"* ]]
    [[ "$output" == *"mainframe host status gemini --runtime system"* ]]
    [[ "$output" != *"mainframe host install gemini"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "status never executes a discovered host and remains offline" {
    make_observer_traps
    make_fake_system_host codex

    run mf host status codex

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"codex"* ]]
    [[ "$output" == *"System:    ready"* ]]
    [[ "$output" == *"Selected:  ready (system"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
    [[ ! -e "$NETWORK_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "status JSON has a closed stable shape and canonical host order" {
    run mf host status --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      (keys | sort) == ["command", "hosts", "mode", "policy", "schema_version"] and
      .schema_version == 1 and
      .command == "host-status" and
      .mode == "read-only-offline" and
      .policy == "auto" and
      [.hosts[].host] == ["codex", "claude-code", "copilot", "gemini"] and
      all(.hosts[];
        (keys | sort) == [
          "certified_version", "host", "managed", "platform",
          "selection", "system"
        ] and
        (.certified_version | type) == "string" and
        (.platform | type) == "string" and
        (.managed | keys | sort) == ["state", "supported", "trust_boundary"] and
        (.managed.state | IN("ready", "absent", "corrupt", "unsupported")) and
        (.managed.supported | type) == "boolean" and
        (.managed.trust_boundary == null or
          (.managed.trust_boundary | type) == "string") and
        (.system | keys | sort) == ["state", "trust_boundary"] and
        (.system.state | IN("ready", "absent", "unsafe", "incompatible")) and
        (.system.trust_boundary == null or
          (.system.trust_boundary | type) == "string") and
        (.selection | keys | sort) == ["source", "state", "trust_boundary"] and
        (.selection.state | IN("ready", "unavailable", "blocked")) and
        (.selection.source == null or (.selection.source | IN("managed", "system"))) and
        (.selection.trust_boundary == null or
          (.selection.trust_boundary | type) == "string")) and
      all(.hosts[]; .system.state == "absent") and
      all(.hosts[]; .system.trust_boundary == null) and
      all(.hosts[]; .selection.state == "unavailable") and
      all(.hosts[]; .selection.trust_boundary == null) and
      ([.hosts[] | select(.host != "gemini") | .managed.state] | all(. == "absent")) and
      ([.hosts[] | select(.host != "gemini") | .managed.supported] | all(. == true)) and
      ([.hosts[] | select(.host != "gemini") | .managed.trust_boundary] |
        all(. == "managed-direct-native-full-tree")) and
      (.hosts[] | select(.host == "gemini") |
        .managed.state == "unsupported" and .managed.supported == false and
        .managed.trust_boundary == null)
    ' <<< "$output"

    run mf host status codex --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      (keys | sort) == ["command", "hosts", "mode", "policy", "schema_version"] and
      (.hosts | length) == 1 and
      .hosts[0].host == "codex"
    ' <<< "$output"

    [[ "$output" != *"$TEST_HOME"* ]]
    [[ "$output" != *"$XDG_DATA_HOME"* ]]
    [[ "$output" != *"$CLI_DIR"* ]]

    run mf host status codex --runtime system --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '.policy == "system"' <<< "$output"
}

@test "status reports source-specific trust and never calls system executable-only full-tree" {
    make_fake_system_host codex

    run mf host status codex --runtime system --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      (.hosts[0] | has("trust_boundary") | not) and
      .hosts[0].managed.trust_boundary == "managed-direct-native-full-tree" and
      .hosts[0].system == {
        "state":"ready",
        "trust_boundary":"system-direct-native-executable-only"
      } and
      .hosts[0].selection == {
        "state":"ready",
        "source":"system",
        "trust_boundary":"system-direct-native-executable-only"
      } and
      ([.hosts[0].system.trust_boundary, .hosts[0].selection.trust_boundary] |
        all(contains("full-tree") | not))
    ' <<< "$output"
    [[ "$output" != *"$CLI_DIR"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]

    run mf host status codex --runtime system
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Managed boundary:"*"managed-direct-native-full-tree"* ]]
    [[ "$output" == *"System boundary:"*"system-direct-native-executable-only"* ]]
    [[ "$output" == *"Selected boundary:"*"system-direct-native-executable-only"* ]]
    [[ "$output" != *"System boundary:"*"full-tree"* ]]
    [[ "$output" != *"Selected boundary:"*"full-tree"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "expected managed target is deterministic versioned and confined to XDG data" {
    run prepare_expected codex

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"version=0.146.0"* ]]
    [[ "$output" == *"supported=true"* ]]
    [[ "$output" == *"error="* ]]
    [[ "$output" =~ platform=([^[:space:]]+) ]]
    local platform="${BASH_REMATCH[1]}"
    [[ "$output" =~ bundle_id=([0-9a-f]{64}) ]]
    local bundle_id="${BASH_REMATCH[1]}"
    [[ "$output" == *"target=$XDG_DATA_HOME/mainframe/host-payloads/v1/codex/0.146.0/$platform/$bundle_id"* ]]
    [[ "$output" =~ tree_root=([^[:space:]]+) ]]
    [[ "${BASH_REMATCH[1]}" != /* ]]
    [[ "$output" =~ executable=([^[:space:]]+) ]]
    [[ "${BASH_REMATCH[1]}" != /* ]]
    [[ "$output" =~ tree_sha=([0-9a-f]{64}) ]]
    [[ "$output" =~ executable_sha=([0-9a-f]{64}) ]]
    [[ "$output" =~ package_set_sha=([0-9a-f]{64}) ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "managed bundle identity binds MAINFRAME version and exact SRI package set" {
    local expected bundle_id package_set_sha recomputed changed_version_id
    local version platform manifest_sha lock_sha tree_root tree_sha executable executable_sha

    expected="$(prepare_expected codex)"
    bundle_id="$(sed -n 's/^bundle_id=//p' <<< "$expected")"
    package_set_sha="$(sed -n 's/^package_set_sha=//p' <<< "$expected")"
    version="$(sed -n 's/^version=//p' <<< "$expected")"
    platform="$(sed -n 's/^platform=//p' <<< "$expected")"
    tree_root="$(sed -n 's/^tree_root=//p' <<< "$expected")"
    tree_sha="$(sed -n 's/^tree_sha=//p' <<< "$expected")"
    executable="$(sed -n 's/^executable=//p' <<< "$expected")"
    executable_sha="$(sed -n 's/^executable_sha=//p' <<< "$expected")"
    manifest_sha="$(sha256_file "$RUNTIME_ROOT/scripts/dev/native-host/hosts.json")"
    lock_sha="$(sha256_file "$RUNTIME_ROOT/scripts/dev/native-host/package-lock.json")"

    run env \
        PATH="$DISCOVERY_PATH" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        HOME="$TEST_HOME" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/common.sh"
          source "$1/lib/activate.sh"
          source "$1/lib/launch.sh"
          source "$1/lib/host_runtime.sh"
          current="$(_mainframe_host_sha256_fields \
            "$MAINFRAME_VERSION" "$2" "$3" "$4" "$5" "$6" "$7" \
            "$8" "$9" "${10}" "${11}")"
          changed="$(_mainframe_host_sha256_fields \
            "10.2.1" "$2" "$3" "$4" "$5" "$6" "$7" \
            "$8" "$9" "${10}" "${11}")"
          printf "current=%s\\nchanged=%s\\n" "$current" "$changed"
        ' _ "$RUNTIME_ROOT" codex "$version" "$platform" \
            "$manifest_sha" "$lock_sha" "$package_set_sha" \
            "$tree_root" "$tree_sha" "$executable" "$executable_sha"

    [[ "$status" -eq 0 ]]
    recomputed="$(sed -n 's/^current=//p' <<< "$output")"
    changed_version_id="$(sed -n 's/^changed=//p' <<< "$output")"
    [[ "$recomputed" == "$bundle_id" ]]
    [[ "$changed_version_id" =~ ^[0-9a-f]{64}$ ]]
    [[ "$changed_version_id" != "$bundle_id" ]]
    [[ "$package_set_sha" =~ ^[0-9a-f]{64}$ ]]
}

@test "missing release-platform policy blocks every runtime policy" {
    local policy_file saved_policy runtime_policy regression_failed=false
    make_fake_system_host codex
    policy_file="$RUNTIME_ROOT/scripts/dev/native-host/release-platforms.json"
    saved_policy="$TEST_DIR/release-platforms.saved.json"
    mv "$policy_file" "$saved_policy"

    for runtime_policy in auto managed system; do
        run resolve_host codex "$runtime_policy"
        if [[ "$status" -eq 0 || "$output" == *"source=system"* ||
              "$output" != *"selected_state=blocked"* ]]; then
            printf 'missing release policy did not block %s resolution:\n%s\n' \
                "$runtime_policy" "$output" >&3
            regression_failed=true
        fi
        [[ ! -e "$HOST_EXEC_LOG" ]]
    done
    [[ "$regression_failed" == false ]]

    run mf host status codex --runtime auto
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"release-platform policy is missing, malformed, or unsafe"* ]]
    [[ "$output" == *"mainframe doctor"* ]]
    [[ "$output" != *"mainframe host status codex --runtime system"* ]]
    [[ "$output" != *"mainframe host install codex"* ]]
}

@test "malformed release-platform policy blocks every runtime policy" {
    local policy_file runtime_policy regression_failed=false
    make_fake_system_host codex
    policy_file="$RUNTIME_ROOT/scripts/dev/native-host/release-platforms.json"
    printf '%s\n' '{"schema_version":1,"platforms":"not-an-array"}' > \
        "$policy_file"

    for runtime_policy in auto managed system; do
        run resolve_host codex "$runtime_policy"
        if [[ "$status" -eq 0 || "$output" == *"source=system"* ||
              "$output" != *"selected_state=blocked"* ]]; then
            printf 'malformed release policy did not block %s resolution:\n%s\n' \
                "$runtime_policy" "$output" >&3
            regression_failed=true
        fi
        [[ ! -e "$HOST_EXEC_LOG" ]]
    done
    [[ "$regression_failed" == false ]]

    run mf host status codex --runtime auto
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"release-platform policy is missing, malformed, or unsafe"* ]]
    [[ "$output" == *"mainframe doctor"* ]]
    [[ "$output" != *"mainframe host status codex --runtime system"* ]]
    [[ "$output" != *"mainframe host install codex"* ]]
}

@test "valid release policy with an unlisted platform blocks every runtime selection" {
    local policy_file current_platform temporary runtime_policy
    make_fake_system_host codex
    policy_file="$RUNTIME_ROOT/scripts/dev/native-host/release-platforms.json"
    current_platform="$(prepare_expected codex | sed -n 's/^platform=//p')"
    [[ -n "$current_platform" ]]
    temporary="$policy_file.tmp.$$"
    "$JQ_BIN" --arg platform "$current_platform" '
      .platforms = [.platforms[] | select(.id != $platform)]
    ' "$policy_file" > "$temporary"
    mv "$temporary" "$policy_file"

    run prepare_expected codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"supported=false"* ]]
    [[ "$output" == *"error="*"not release-certified"* ]]

    run mf host status codex --runtime auto --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .hosts[0].managed.state == "unsupported" and
      .hosts[0].selection.state != "ready" and
      .hosts[0].selection.source == null
    ' <<< "$output"

    run mf host status codex --runtime auto
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Managed:   unsupported"* ]]
    [[ "$output" == *"outside this release's certified runtime boundary"* ]]
    [[ "$output" == *"Neither managed nor system runtime selection is authorized"* ]]
    [[ "$output" != *"mainframe host status codex --runtime system"* ]]
    [[ "$output" != *"mainframe host install codex"* ]]

    for runtime_policy in auto managed system; do
        run resolve_host codex "$runtime_policy"
        [[ "$status" -ne 0 ]]
        [[ "$output" != *"selected_state=ready"* ]]
        [[ "$output" == *$'source=\nexecutable=\n'* ]]
        [[ ! -e "$HOST_EXEC_LOG" ]]
    done
}

@test "auto resolution falls back to an authenticated system host when managed is absent" {
    make_fake_system_host codex

    run resolve_host codex auto

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"result=0"* ]]
    [[ "$output" == *"source=system"* ]]
    [[ "$output" == *"executable=$CLI_DIR/codex"* ]]
    [[ "$output" == *"version=0.146.0"* ]]
    [[ "$output" == *"identity=pinned-native:"* ]]
    [[ "$output" == *$'error=\n'* || "$output" == *"error=" ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "valid managed Codex takes precedence over an authenticated system Codex" {
    local target
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"

    run resolve_host codex auto

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"source=managed"* ]]
    [[ "$output" == *"executable=$target/"* ]]
    [[ "$output" == *"version=0.146.0"* ]]
    [[ "$output" == *"identity=managed-full-tree; pinned-native:"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]

    run mf host status codex --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .hosts[0].managed == {
        "state":"ready",
        "supported":true,
        "trust_boundary":"managed-direct-native-full-tree"
      } and
      .hosts[0].system.state == "ready" and
      .hosts[0].system.trust_boundary == "system-direct-native-executable-only" and
      .hosts[0].selection == {
        "state":"ready",
        "source":"managed",
        "trust_boundary":"managed-direct-native-full-tree"
      }
    ' <<< "$output"
    [[ "$output" != *"$target"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "valid managed Claude Code and Copilot payloads use the generic direct-native branch" {
    local host expected_version target

    for host in claude-code copilot; do
        case "$host" in
            claude-code) expected_version=2.1.220 ;;
            copilot) expected_version=1.0.78 ;;
        esac
        target="$(make_valid_managed_host "$host")"

        run resolve_host "$host" managed

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"source=managed"* ]]
        [[ "$output" == *"executable=$target/"* ]]
        [[ "$output" == *"version=$expected_version"* ]]
        [[ "$output" == *"identity=managed-full-tree; pinned-native:"* ]]
        [[ ! -e "$HOST_EXEC_LOG" ]]

        run mf host status "$host" --runtime managed --json
        [[ "$status" -eq 0 ]]
        "$JQ_BIN" -e --arg host "$host" '
          .hosts == [{
            host: $host,
            certified_version: .hosts[0].certified_version,
            platform: .hosts[0].platform,
            managed: {
              state: "ready",
              supported: true,
              trust_boundary: "managed-direct-native-full-tree"
            },
            system: .hosts[0].system,
            selection: {
              state: "ready",
              source: "managed",
              trust_boundary: "managed-direct-native-full-tree"
            }
          }]
        ' <<< "$output"
        [[ "$output" != *"$target"* ]]
        [[ ! -e "$HOST_EXEC_LOG" ]]
    done
}

@test "payload byte tamper after a valid receipt blocks auto system fallback" {
    local target executable
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"
    executable="$($JQ_BIN -er '.executable' "$target/receipt.json")"
    chmod 700 "$target/$executable"
    printf '%s\n' '# tampered after receipt validation fixture' >> \
        "$target/$executable"
    chmod 500 "$target/$executable"

    run resolve_host codex auto

    [[ "$status" -ne 0 ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" != *"executable=$CLI_DIR/codex"* ]]
    [[ "$output" == *"error="*"corrupt"*"fallback refused"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "closed receipt rejects an extra field and a receipt symlink" {
    local target saved_receipt extra_receipt
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"
    saved_receipt="$TEST_DIR/valid-receipt.json"
    extra_receipt="$TEST_DIR/extra-receipt.json"
    cp "$target/receipt.json" "$saved_receipt"
    chmod 600 "$saved_receipt"

    "$JQ_BIN" '.unexpected = true' "$saved_receipt" > "$extra_receipt"
    chmod 600 "$extra_receipt"
    mv "$extra_receipt" "$target/receipt.json"

    run resolve_host codex auto
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"receipt"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]

    cp "$saved_receipt" "$target/receipt.json"
    chmod 600 "$target/receipt.json"
    rm "$target/receipt.json"
    ln -s "$saved_receipt" "$target/receipt.json"

    run resolve_host codex auto
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"receipt"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "hard-linked receipt is corrupt and blocks auto system fallback" {
    local target receipt_alias
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"
    receipt_alias="$TEST_DIR/hard-linked-receipt.json"
    if ! ln "$target/receipt.json" "$receipt_alias" 2>/dev/null; then
        skip "filesystem does not support regular-file hard links"
    fi

    run resolve_host codex auto

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"selected_state=blocked"* ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"receipt"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "hard-linked payload resource is corrupt and blocks auto system fallback" {
    local target resource payload_alias
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"
    resource="$target/payload/node_modules/@openai/resource with spaces.txt"
    payload_alias="$TEST_DIR/hard-linked-payload-resource.txt"
    [[ -f "$resource" ]]
    if ! ln "$resource" "$payload_alias" 2>/dev/null; then
        skip "filesystem does not support regular-file hard links"
    fi

    run resolve_host codex auto

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"selected_state=blocked"* ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"payload"* ||
       "$output" == *"error="*"tree"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "managed payload files must remain normalized owner-read-execute mode 0500" {
    local target executable resource
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"
    executable="$($JQ_BIN -er '.executable' "$target/receipt.json")"
    resource="$target/payload/node_modules/@openai/resource with spaces.txt"
    [[ -f "$resource" ]]

    chmod 700 "$target/$executable"
    run resolve_host codex auto
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"unsafe ownership, modes"* ]]

    chmod 500 "$target/$executable"
    chmod 600 "$resource"
    run resolve_host codex auto
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"unsafe ownership, modes"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "shell package-tree hash matches Node reference with spaces and empty directories" {
    local tree node_digest
    tree="$TEST_DIR/tree fixture with spaces"
    mkdir -p "$tree/empty directory" "$tree/nested path/another empty directory"
    printf '%s' 'alpha' > "$tree/file with spaces.txt"
    printf '%s' 'beta' > "$tree/nested path/data.bin"
    : > "$tree/empty file"
    node_digest="$("$NODE_BIN" \
        "$RUNTIME_ROOT/scripts/dev/native-host/hash-package-tree.mjs" \
        "$tree")"

    run env \
        PATH="$DISCOVERY_PATH" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        HOME="$TEST_HOME" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/common.sh"
          source "$1/lib/activate.sh"
          source "$1/lib/launch.sh"
          source "$1/lib/host_runtime.sh"
          _mainframe_host_tree_sha256 "$2"
        ' _ "$RUNTIME_ROOT" "$tree"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    [[ "$output" == "$node_digest" ]]
}

@test "managed policy fails clearly when its expected payload is absent" {
    run resolve_host codex managed

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"source="* ]]
    [[ "$output" == *"executable="* ]]
    [[ "$output" == *"error="*"managed"*"absent"* ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "case-insensitive project aliases cannot hide managed-root containment" {
    local parent base alias_project original_xdg
    parent="${PROJECT_DIR%/*}"
    base="${PROJECT_DIR##*/}"
    alias_project="$parent/${base^^}"
    [[ "$alias_project" != "$PROJECT_DIR" &&
       "$alias_project" -ef "$PROJECT_DIR" ]] ||
        skip "filesystem does not provide a case-insensitive project alias"
    make_fake_system_host codex
    original_xdg="$XDG_DATA_HOME"
    XDG_DATA_HOME="$alias_project/private runtime data"
    export XDG_DATA_HOME

    run resolve_host codex auto

    XDG_DATA_HOME="$original_xdg"
    export XDG_DATA_HOME
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"selected_state=blocked"* ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"inside the project"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "world-writable non-sticky XDG ancestor corrupts managed and blocks auto fallback" {
    local unsafe_parent target
    unsafe_parent="$TEST_DIR/world-writable ancestor"
    XDG_DATA_HOME="$unsafe_parent/owner-only data home"
    export XDG_DATA_HOME
    mkdir -p "$unsafe_parent"
    chmod 0777 "$unsafe_parent"
    [[ ! -k "$unsafe_parent" ]]
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"
    [[ -d "$target" ]]
    chmod 0700 "$XDG_DATA_HOME"

    run resolve_host codex auto

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"managed_state=corrupt"* ]]
    [[ "$output" == *"selected_state=blocked"* ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"untrusted ownership, permissions, or ancestry"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "macOS write-capable everyone ACL on XDG data home is rejected" {
    local target acl_listing
    [[ "$(uname -s)" == Darwin ]] || skip "macOS-only ACL regression"
    [[ -x /bin/chmod && -x /bin/ls ]] || skip "macOS ACL tooling is unavailable"
    make_fake_system_host codex
    target="$(make_valid_managed_host codex)"
    [[ -d "$target" ]]
    chmod 0700 "$XDG_DATA_HOME"
    if ! /bin/chmod +a "everyone allow write" "$XDG_DATA_HOME" 2>/dev/null; then
        skip "filesystem does not support writable macOS ACLs"
    fi
    acl_listing="$(LC_ALL=C /bin/ls -lde "$XDG_DATA_HOME" 2>/dev/null)" ||
        skip "filesystem cannot report macOS ACLs"
    [[ "$acl_listing" == *"everyone allow "*"write"* ||
       "$acl_listing" == *"everyone allow "*"add_file"* ]] ||
        skip "filesystem did not retain the writable everyone ACL"

    run resolve_host codex auto

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"managed_state=corrupt"* ]]
    [[ "$output" == *"selected_state=blocked"* ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error="*"untrusted ownership, permissions, or ancestry"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "nested-mount detector accepts the ordinary managed fixture" {
    local target
    target="$(make_valid_managed_host codex)"
    [[ -d "$target" ]]

    run env \
        PATH="$DISCOVERY_PATH" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        HOME="$TEST_HOME" \
        XDG_DATA_HOME="$XDG_DATA_HOME" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/common.sh"
          source "$1/lib/activate.sh"
          source "$1/lib/launch.sh"
          source "$1/lib/host_runtime.sh"
          _mainframe_host_no_nested_mounts "$2" "$3"
        ' _ "$RUNTIME_ROOT" "$XDG_DATA_HOME" "$target"

    [[ "$status" -eq 0 ]]
}

@test "mount conflict relation catches target ancestors and descendants only" {
    local target ancestor descendant sibling
    target="$(make_valid_managed_host codex)"
    [[ -d "$target" ]]
    ancestor="${target%/*}"
    descendant="$target/payload"
    sibling="$ancestor/unrelated sibling"
    mkdir "$sibling"
    chmod 0700 "$sibling"

    run env \
        PATH="$DISCOVERY_PATH" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        HOME="$TEST_HOME" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/common.sh"
          source "$1/lib/activate.sh"
          source "$1/lib/launch.sh"
          source "$1/lib/host_runtime.sh"
          if _mainframe_host_mount_conflicts "$2" "$3" "$4"; then
              printf "ancestor=conflict\\n"
          else
              printf "ancestor=clear\\n"
          fi
          if _mainframe_host_mount_conflicts "$2" "$3" "$5"; then
              printf "descendant=conflict\\n"
          else
              printf "descendant=clear\\n"
          fi
          if _mainframe_host_mount_conflicts "$2" "$3" "$6"; then
              printf "sibling=conflict\\n"
          else
              printf "sibling=clear\\n"
          fi
        ' _ "$RUNTIME_ROOT" "$XDG_DATA_HOME" "$target" \
            "$ancestor" "$descendant" "$sibling"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ancestor=conflict"* ]]
    [[ "$output" == *"descendant=conflict"* ]]
    [[ "$output" == *"sibling=clear"* ]]
}

@test "Gemini managed execution remains unsupported while auto may use certified system bytes" {
    make_fake_system_host gemini

    run resolve_host gemini managed
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"source="* ]]
    [[ "$output" == *"error="*"Gemini"*"unsupported"* ||
       "$output" == *"error="*"gemini"*"unsupported"* ]]

    run resolve_host gemini auto
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"source=system"* ]]
    [[ "$output" == *"executable=$CLI_DIR/gemini"* ]]
    [[ "$output" == *"version=0.53.1"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
}

@test "auto fails closed on a corrupt expected managed payload instead of using system" {
    local expected target
    make_fake_system_host codex
    expected="$(prepare_expected codex)"
    target="$(sed -n 's/^target=//p' <<< "$expected")"
    mkdir -p "$target"
    printf '%s\n' '{"schema_version":1,"corrupt":true}' > "$target/receipt.json"

    run resolve_host codex auto

    [[ "$status" -ne 0 ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" != *"executable=$CLI_DIR/codex"* ]]
    [[ "$output" == *"error="*"managed"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "corrupt human status offers diagnostic recovery without an install command" {
    local expected target
    make_observer_traps
    expected="$(prepare_expected codex)"
    target="$(sed -n 's/^target=//p' <<< "$expected")"
    mkdir -p "$target"
    printf '%s\n' '{"schema_version":1,"corrupt":true}' > "$target/receipt.json"

    run mf host status codex --runtime auto

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Managed:   corrupt"* ]]
    [[ "$output" == *"refuses automatic fallback, replacement, or removal"* ]]
    [[ "$output" == *"path-redacted status record"* ]]
    [[ "$output" == *"mainframe host status codex --runtime managed --json"* ]]
    [[ "$output" == *"docs/MANAGED_HOST_PAYLOADS.md"* ]]
    [[ "$output" != *"mainframe host install codex"* ]]
    [[ ! -e "$NETWORK_LOG" ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "explicit system policy bypasses a corrupt managed payload without executing it" {
    local expected target
    make_fake_system_host codex
    expected="$(prepare_expected codex)"
    target="$(sed -n 's/^target=//p' <<< "$expected")"
    mkdir -p "$target"
    printf '%s\n' '{"schema_version":1,"corrupt":true}' > "$target/receipt.json"

    run resolve_host codex system

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"source=system"* ]]
    [[ "$output" == *"executable=$CLI_DIR/codex"* ]]
    [[ "$output" == *"version=0.146.0"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "resolver rejects unknown hosts and runtime policies with cleared result globals" {
    run resolve_host unknown auto
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"source="* ]]
    [[ "$output" == *"executable="* ]]
    [[ "$output" == *"version="* ]]
    [[ "$output" == *"identity="* ]]
    [[ "$output" == *"error="*"unsupported host"* ]]

    run resolve_host codex newest
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"source="* ]]
    [[ "$output" == *"executable="* ]]
    [[ "$output" == *"version="* ]]
    [[ "$output" == *"identity="* ]]
    [[ "$output" == *"error="*"unsupported runtime policy"* ]]
}

@test "Linux system authentication rejects metadata for the other libc tuple" {
    local arch libc other_libc exact_key other_key manifest
    local exact_digest other_digest fake_digest temporary

    [[ "$(uname -s)" == Linux ]] || skip "Linux-only libc tuple regression"
    arch="$(uname -m)"
    case "$arch" in
        x86_64|aarch64) ;;
        *) skip "unsupported Linux test architecture: $arch" ;;
    esac
    libc="$(env \
        PATH="$DISCOVERY_PATH" \
        MAINFRAME_ROOT="$RUNTIME_ROOT" \
        HOME="$TEST_HOME" \
        "$BASH_BIN" --noprofile --norc -p -c '
          source "$1/lib/common.sh"
          source "$1/lib/activate.sh"
          source "$1/lib/launch.sh"
          source "$1/lib/host_runtime.sh"
          _mainframe_host_linux_libc
        ' _ "$RUNTIME_ROOT")"
    case "$libc" in
        glibc) other_libc=musl ;;
        musl) other_libc=glibc ;;
        *) skip "could not identify Linux libc" ;;
    esac
    exact_key="Linux-$arch-$libc"
    other_key="Linux-$arch-$other_libc"
    manifest="$RUNTIME_ROOT/scripts/dev/native-host/hosts.json"
    exact_digest="$($JQ_BIN -er --arg key "$exact_key" \
        '.copilot.platforms[$key].executable_sha256' "$manifest")"
    other_digest="$($JQ_BIN -er --arg key "$other_key" \
        '.copilot.platforms[$key].executable_sha256' "$manifest")"

    make_fake_system_host copilot
    fake_digest="$(sha256_file "$CLI_DIR/copilot")"
    temporary="$manifest.libc.tmp.$$"
    "$JQ_BIN" \
        --arg exact "$exact_key" \
        --arg other "$other_key" \
        --arg exact_digest "$exact_digest" \
        --arg fake_digest "$fake_digest" '
          .copilot.platforms[$exact].executable_sha256 = $exact_digest |
          .copilot.platforms[$other].executable_sha256 = $fake_digest
        ' "$manifest" > "$temporary"
    mv "$temporary" "$manifest"

    run resolve_host copilot system
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"source=system"* ]]
    [[ "$output" == *"error=system copilot CLI is incompatible"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]

    temporary="$manifest.libc.tmp.$$"
    "$JQ_BIN" \
        --arg exact "$exact_key" \
        --arg other "$other_key" \
        --arg other_digest "$other_digest" \
        --arg fake_digest "$fake_digest" '
          .copilot.platforms[$exact].executable_sha256 = $fake_digest |
          .copilot.platforms[$other].executable_sha256 = $other_digest
        ' "$manifest" > "$temporary"
    mv "$temporary" "$manifest"

    run resolve_host copilot system
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"source=system"* ]]
    [[ "$output" == *"identity=pinned-native:$exact_key:$fake_digest"* ]]
    [[ ! -e "$HOST_EXEC_LOG" ]]
}

@test "exact child enumeration fails closed without leaking denied paths" {
    local denied metadata_root metadata_child
    [[ "$EUID" -ne 0 ]] || skip "permission-denial regression requires a non-root test user"
    denied="$TEST_DIR/denied enumeration"
    mkdir "$denied"
    chmod 000 "$denied"

    run "$BASH_BIN" --noprofile --norc -p -c '
        source "$1/lib/host_runtime.sh"
        _mainframe_host_directory_children_exact "$2"
    ' _ "$PROJECT_ROOT" "$denied"
    chmod 700 "$denied"

    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]

    run "$BASH_BIN" --noprofile --norc -p -c '
        source "$1/lib/host_runtime.sh"
        _mainframe_host_target_inventory_exact "$2"
    ' _ "$PROJECT_ROOT" "$denied"

    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]

    run "$BASH_BIN" --noprofile --norc -p -c '
        source "$1/lib/host_runtime.sh"
        _mainframe_host_directory_children_exact "$2"
    ' _ "$PROJECT_ROOT" "$denied"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    mkdir "$denied/generation"
    run "$BASH_BIN" --noprofile --norc -p -c '
        source "$1/lib/host_runtime.sh"
        _mainframe_host_directory_children_exact "$2" generation
    ' _ "$PROJECT_ROOT" "$denied"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    metadata_root="$TEST_DIR/metadata enumeration"
    metadata_child="$metadata_root/denied child"
    mkdir -p "$metadata_child"
    chmod 500 "$metadata_root"
    chmod 000 "$metadata_child"
    run "$BASH_BIN" --noprofile --norc -p -c '
        source "$1/lib/host_runtime.sh"
        _mainframe_host_validate_tree_metadata "$2"
    ' _ "$PROJECT_ROOT" "$metadata_root"
    chmod 700 "$metadata_root" "$metadata_child"

    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]
}

@test "bash and zsh completions expose host lifecycle actions and status policies" {
    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host "")
        COMP_CWORD=2
        _mainframe_completions
        printf "%s\\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$(printf '%s\n' install remove restore status)" ]]

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host status "")
        COMP_CWORD=3
        _mainframe_completions
        printf "%s\\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"codex"* ]]
    [[ "$output" == *"claude-code"* ]]
    [[ "$output" == *"copilot"* ]]
    [[ "$output" == *"gemini"* ]]
    [[ "$output" == *"--runtime"* ]]
    [[ "$output" == *"--json"* ]]

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host status codex --runtime "")
        COMP_CWORD=5
        _mainframe_completions
        printf "%s\\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$(printf '%s\n' auto managed system)" ]]

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host restore "")
        COMP_CWORD=3
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"codex"* ]]
    [[ "$output" == *"claude-code"* ]]
    [[ "$output" == *"copilot"* ]]
    [[ "$output" != *"gemini"* ]]
    [[ "$output" == *"--quarantine-id"* ]]

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host restore codex --quarantine-id "")
        COMP_CWORD=5
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    if command -v zsh >/dev/null 2>&1; then
        run zsh -f -c '
            compdef() { :; }
            source "$1"
            _arguments() { printf "%s\\n" "$@"; }
            words=(mainframe host status "")
            CURRENT=4
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"1:command:(host)"* ]]
        [[ "$output" == *"2:action:(status)"* ]]
        [[ "$output" == *"3:host:(codex claude-code copilot gemini)"* ]]
        [[ "$output" == *"--runtime"*"(auto managed system)"* ]]
        [[ "$output" == *"--json"* ]]

        run zsh -f -c '
            compdef() { :; }
            source "$1"
            _arguments() { printf "%s\n" "$@"; }
            words=(mainframe host restore "")
            CURRENT=4
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"1:command:(host)"* ]]
        [[ "$output" == *"2:action:(restore)"* ]]
        [[ "$output" == *"3:host:(codex claude-code copilot)"* ]]
        [[ "$output" == *"--quarantine-id"* ]]

        local zsh_init
        printf -v zsh_init \
            'autoload -Uz compinit && compinit -i\nmainframe() { print -r -- "EXEC:$*:END"; }\nsource %q\n' \
            "$PROJECT_ROOT/completions/mainframe.zsh"
        run zsh -f -c '
            zmodload zsh/zpty || exit 1
            zpty completion_shell zsh -f
            zpty -w completion_shell "$1"
            local -a actions completion_inputs
            actions=(status install remove restore)
            completion_inputs=("$2" "$3" "$4" "$5")
            local action index transcript
            for index in {1..4}; do
                action="${actions[$index]}"
                zpty -w completion_shell "${completion_inputs[$index]}"
                zpty -r completion_shell transcript \
                    "*EXEC:host ${action} *:END*" || exit 2
                print -r -- "$transcript"
            done
            zpty -d completion_shell
        ' _ "$zsh_init" \
            $'mainframe host status gem\t\n' \
            $'mainframe host install code\t\n' \
            $'mainframe host remove claude-c\t\n' \
            $'mainframe host restore copi\t\n'
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"EXEC:host status gemini:END"* ]]
        [[ "$output" == *"EXEC:host install codex:END"* ]]
        [[ "$output" == *"EXEC:host remove claude-code:END"* ]]
        [[ "$output" == *"EXEC:host restore copilot:END"* ]]
    fi
}

@test "bash host lifecycle completion suppresses used and conflicting options" {
    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host install codex --download --json "")
        COMP_CWORD=6
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"--download"* ]]
    [[ "$output" != *"--package-dir"* ]]
    [[ "$output" != *"--json"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--yes"* ]]

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host restore codex --quarantine-id \
            removed.0123456789abcdef01 --dry-run "")
        COMP_CWORD=7
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"--quarantine-id"* ]]
    [[ "$output" != *"--dry-run"* ]]
    [[ "$output" != *"--yes"* ]]
    [[ "$output" == *"--json"* ]]

    run "$BASH_BIN" -c '
        source "$1"
        COMP_WORDS=(mainframe host status codex --runtime managed --json "")
        COMP_CWORD=7
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}" | LC_ALL=C sort
    ' _ "$PROJECT_ROOT/completions/mainframe.bash"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"--runtime"* ]]
    [[ "$output" != *"--json"* ]]
}

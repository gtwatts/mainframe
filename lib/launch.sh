#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/launch.sh - Fail-closed daily launcher for supported AI hosts
# =============================================================================
# Launch is intentionally narrower than the hosts' native CLIs. It verifies the
# one-time onboarding artifacts and private project memory without repairing or
# creating either, then replaces itself with the selected interactive host.
# =============================================================================

[[ -n "${_MAINFRAME_LAUNCH_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_LAUNCH_LOADED=1

_mainframe_launch_usage() {
    cat <<'EOF'
Usage: mainframe launch <host> [--project <dir>] [--policy <tier>] [--runtime <source>] [--dry-run]

Hosts: codex, claude-code, copilot, gemini
Policy tiers: medium (default), high, critical
Runtime sources: auto (default), managed, system

The default launch is a read-only, fail-closed preflight followed by an
interactive host exec. It requires the selected host's current MAINFRAME
instruction block, private project AWM mapping, and exact native shell hook to
already be ready. It never onboards or repairs a project.

Options:
  --project DIR     Existing onboarded project (default: current directory)
  --policy TIER     Gateway block tier for this host process (default: medium)
  --runtime SOURCE  Prefer managed, require managed, or require system
  --dry-run         Verify and print the launch target without starting it
  -h, --help        Show this help

Native host arguments are not accepted in this first safe contract. Start the
interactive host with this command, then enter the task in the host.
EOF
}

_mainframe_launch_error() {
    printf 'MAINFRAME launch: %s\n' "$*" >&2
}

_mainframe_launch_host_cli_name() {
    case "${1:-}" in
        codex) printf 'codex\n' ;;
        claude-code) printf 'claude\n' ;;
        copilot) printf 'copilot\n' ;;
        gemini) printf 'gemini\n' ;;
        *) return 1 ;;
    esac
}

_mainframe_launch_print_recovery() {
    local host="$1" project="$2"

    printf 'Review and restore onboarding with:\n' >&2
    printf '  mainframe setup --project %q --host %q --dry-run\n' \
        "$project" "$host" >&2
    printf '  mainframe setup --project %q --host %q\n' \
        "$project" "$host" >&2
}

# Run post-discovery preflight helpers from fixed operating-system directories.
# Bound Bash and jq are always invoked by absolute path; their package-manager
# directories must not enter PATH because a same-directory `sha256sum`, `awk`,
# or other helper could otherwise run during preflight.
_mainframe_launch_preflight_path() {
    printf '%s\n' '/usr/bin:/bin:/usr/sbin:/sbin'
}

# Remove only environment entries that can make an interpreter or dynamic
# loader execute caller-selected code. Ordinary host configuration, credentials,
# and discovery PATH remain intact. The public CLI performs the same scrub
# before loading common.sh; this local guard also protects direct library use
# and closes any accidental reintroduction before a sensitive helper or exec.
_mainframe_launch_scrub_code_loader_env() {
    local variable prefix

    builtin unset -v \
        BASH_ENV ENV \
        NODE_OPTIONS NODE_PATH NODE_V8_COVERAGE NODE_REPL_HISTORY \
        NODE_REDIRECT_WARNINGS \
        PERL5OPT PERL5LIB PERLLIB 2>/dev/null || return 1

    for prefix in LD_ DYLD_; do
        while IFS= read -r variable; do
            builtin unset -v "$variable" 2>/dev/null || return 1
        done < <(builtin compgen -A variable "$prefix")
    done
}

# Resolve a PATH result through symbolic links without GNU readlink -f. Bound
# the traversal so a malicious or broken link cycle cannot hang preflight.
_mainframe_launch_resolve_executable() {
    local source="$1" dir target links=0

    [[ "$source" == /* ]] || return 1
    while [[ -L "$source" ]]; do
        (( links < 40 )) || return 1
        links=$((links + 1))
        dir="${source%/*}"
        [[ -n "$dir" ]] || dir=/
        dir="$(cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
        if [[ -x /usr/bin/readlink ]]; then
            target="$(/usr/bin/readlink "$source")" || return 1
        elif [[ -x /bin/readlink ]]; then
            target="$(/bin/readlink "$source")" || return 1
        else
            return 1
        fi
        [[ "$target" == /* ]] && source="$target" || source="$dir/$target"
    done
    dir="${source%/*}"
    [[ -n "$dir" ]] || dir=/
    dir="$(cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
    source="$dir/${source##*/}"
    [[ -f "$source" && -x "$source" ]] || return 1
    [[ "$source" != *$'\n'* && "$source" != *$'\r'* && "$source" != *$'\t'* ]] || return 1
    printf '%s\n' "$source"
}

_mainframe_launch_host_manifest_key() {
    case "$1" in
        codex) printf 'codex\n' ;;
        claude-code) printf 'claude\n' ;;
        copilot) printf 'copilot\n' ;;
        gemini) printf 'gemini\n' ;;
        *) return 1 ;;
    esac
}

declare -ga _MAINFRAME_HOST_ARGV=()
declare -g _MAINFRAME_HOST_VERSION=""
declare -g _MAINFRAME_HOST_IDENTITY=""
declare -g _MAINFRAME_HOST_ERROR=""
declare -g _MAINFRAME_HOST_JQ=""
declare -g _MAINFRAME_HOST_NODE=""
declare -g _MAINFRAME_HOST_NODE_SHA=""
declare -g _MAINFRAME_HOST_HASHER=""
declare -g _MAINFRAME_HOST_HASHER_SHA=""
declare -g _MAINFRAME_LAUNCH_NODE_RESULT=""

_mainframe_launch_identity_fail() {
    _MAINFRAME_HOST_ERROR="$1"
    return 1
}

_mainframe_launch_path_within() {
    local root="$1" path="$2"
    [[ "$root" == / || "$path" == "$root" || "$path" == "$root/"* ]]
}

_mainframe_launch_install_root() {
    local executable="$1" relative="$2" suffix
    [[ "$relative" != /* && "$relative" != *$'\n'* &&
       "$relative" != *$'\r'* && "$relative" != *$'\t'* ]] || return 1
    suffix="/$relative"
    [[ "$executable" == *"$suffix" ]] || return 1
    executable="${executable%"$suffix"}"
    [[ -n "$executable" && -d "$executable" && ! -L "$executable" ]] || return 1
    printf '%s\n' "$executable"
}

# Run Node-backed authentication without caller-controlled preload, module
# search, coverage, or warning-output hooks. These variables can execute code
# or write files before the installed package-tree hasher starts.
_mainframe_launch_run_node() {
    local node_executable="$1"
    shift

    [[ "$node_executable" == /* && -x "$node_executable" ]] || return 1
    _mainframe_launch_scrub_code_loader_env || return 1
    /usr/bin/env \
        -u NODE_OPTIONS \
        -u NODE_PATH \
        -u NODE_V8_COVERAGE \
        -u NODE_REPL_HISTORY \
        -u NODE_REDIRECT_WARNINGS \
        "$node_executable" "$@"
}

_mainframe_launch_tree_sha256() {
    local project="$1" node_executable="$2" root="$3"
    shift 3
    local hasher="${MAINFRAME_ROOT:-}/scripts/dev/native-host/hash-package-tree.mjs"
    local digest output node_sha hasher_sha

    [[ -f "$hasher" && ! -L "$hasher" ]] || return 1
    [[ "$node_executable" == /* && -f "$node_executable" &&
       ! -L "$node_executable" && -x "$node_executable" ]] || return 1
    _mainframe_launch_path_within "$project" "$node_executable" && return 1
    [[ "$node_executable" == "$_MAINFRAME_HOST_NODE" &&
       "$hasher" == "$_MAINFRAME_HOST_HASHER" ]] || return 1
    node_sha="$(_mainframe_launch_sha256_file "$node_executable")" || return 1
    hasher_sha="$(_mainframe_launch_sha256_file "$hasher")" || return 1
    [[ "$node_sha" == "$_MAINFRAME_HOST_NODE_SHA" &&
       "$hasher_sha" == "$_MAINFRAME_HOST_HASHER_SHA" ]] || return 1
    if ! output="$(_mainframe_launch_run_node \
        "$node_executable" "$hasher" "$root" "$@" 2>&1)"; then
        printf '%s\n' "${output:-package-tree hasher failed without an error}" >&2
        return 1
    fi
    digest="$output"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    node_sha="$(_mainframe_launch_sha256_file "$node_executable")" || return 1
    hasher_sha="$(_mainframe_launch_sha256_file "$hasher")" || return 1
    [[ "$node_sha" == "$_MAINFRAME_HOST_NODE_SHA" &&
       "$hasher_sha" == "$_MAINFRAME_HOST_HASHER_SHA" ]] || return 1
    printf '%s\n' "$digest"
}

_mainframe_launch_node_executable() {
    local project="$1" discovery_path="${2:-${PATH:-}}"
    local candidate resolved hasher node_sha hasher_sha
    _MAINFRAME_LAUNCH_NODE_RESULT=""
    candidate="$(PATH="$discovery_path" type -P node 2>/dev/null || true)"
    [[ -n "$candidate" && "$candidate" == /* ]] || return 1
    resolved="$(_mainframe_launch_resolve_executable "$candidate")" || return 1
    _mainframe_launch_path_within "$project" "$resolved" && return 1
    case "$resolved" in
        /usr/bin/node|/bin/node|/usr/local/bin/node|\
        /opt/homebrew/Cellar/*/bin/node|/usr/local/Cellar/*/bin/node|\
        /home/linuxbrew/.linuxbrew/Cellar/*/bin/node|/nix/store/*/bin/node|\
        "${HOME:-}/.nvm/versions/node/"*/bin/node|\
        "${HOME:-}/.asdf/installs/nodejs/"*/bin/node|\
        "${HOME:-}/.local/share/mise/installs/node/"*/bin/node|\
        "${HOME:-}/.volta/tools/image/node/"*/bin/node|\
        "${HOME:-}/.local/share/fnm/node-versions/"*/installation/bin/node) ;;
        *) return 1 ;;
    esac
    hasher="${MAINFRAME_ROOT:-}/scripts/dev/native-host/hash-package-tree.mjs"
    [[ "$hasher" == /* && -f "$hasher" && ! -L "$hasher" &&
       -r "$hasher" ]] || return 1
    _mainframe_launch_path_within "$project" "$hasher" && return 1
    node_sha="$(_mainframe_launch_sha256_file "$resolved")" || return 1
    hasher_sha="$(_mainframe_launch_sha256_file "$hasher")" || return 1
    _MAINFRAME_HOST_NODE="$resolved"
    _MAINFRAME_HOST_NODE_SHA="$node_sha"
    _MAINFRAME_HOST_HASHER="$hasher"
    _MAINFRAME_HOST_HASHER_SHA="$hasher_sha"
    _MAINFRAME_LAUNCH_NODE_RESULT="$resolved"
}

_mainframe_launch_host_tooling_current() {
    local node_sha hasher_sha

    [[ -n "$_MAINFRAME_HOST_NODE" ]] || return 0
    node_sha="$(_mainframe_launch_sha256_file "$_MAINFRAME_HOST_NODE")" || return 1
    hasher_sha="$(_mainframe_launch_sha256_file "$_MAINFRAME_HOST_HASHER")" || return 1
    [[ "$node_sha" == "$_MAINFRAME_HOST_NODE_SHA" &&
       "$hasher_sha" == "$_MAINFRAME_HOST_HASHER_SHA" ]]
}

# Authenticate exact launcher, selected native runtime, and package-tree bytes
# without executing the discovered host. Native-host capability/version claims
# come from the same immutable manifest and certifiers that produced the pins.
_mainframe_launch_host_compatible() {
    local host="$1" host_executable="$2" project="${3:-/}"
    local discovery_path="${4:-${PATH:-}}"
    local manifest="${MAINFRAME_ROOT:-}/scripts/dev/native-host/hosts.json"
    local manifest_key certified_version host_sha jq_executable
    local current_platform manifest_platform platform_policy_state
    local platform_rows direct_key
    local entry_relative expected_entry_sha install_root node_executable
    local key package binary_relative expected_binary_sha expected_tree_sha
    local binary actual_binary_sha tree_root actual_tree_sha dependency
    local matches=0 selected_binary="" selected_key="" wrapper_relative="" tree_error=""
    local expected_stub_sha expected_wrapper_sha stub_relative cli_wrapper_relative

    _MAINFRAME_HOST_ARGV=()
    _MAINFRAME_HOST_VERSION=""
    _MAINFRAME_HOST_IDENTITY=""
    _MAINFRAME_HOST_ERROR=""
    _MAINFRAME_HOST_JQ=""
    _MAINFRAME_HOST_NODE=""
    _MAINFRAME_HOST_NODE_SHA=""
    _MAINFRAME_HOST_HASHER=""
    _MAINFRAME_HOST_HASHER_SHA=""
    _MAINFRAME_LAUNCH_NODE_RESULT=""

    jq_executable="${MAINFRAME_AGENT_JQ:-}"
    [[ "$jq_executable" == /* && -f "$jq_executable" &&
       ! -L "$jq_executable" && -x "$jq_executable" ]] ||
        _mainframe_launch_identity_fail 'a trusted jq binding is required to authenticate host artifacts' || return 1
    if _mainframe_launch_path_within "$project" "$jq_executable"; then
        _mainframe_launch_identity_fail 'refusing a project-controlled jq during host authentication'
        return 1
    fi
    _MAINFRAME_HOST_JQ="$jq_executable"
    [[ -f "$manifest" && ! -L "$manifest" ]] ||
        _mainframe_launch_identity_fail "the certified host manifest is missing or unsafe: $manifest" || return 1
    manifest_key="$(_mainframe_launch_host_manifest_key "$host")" || return 1
    certified_version="$("$jq_executable" -er \
        --arg host "$manifest_key" \
        'if .schema_version == 1 and (.[$host] | type) == "object"
         then .[$host].version
         else empty
         end
         | select(type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' \
        "$manifest" 2>/dev/null)" ||
        _mainframe_launch_identity_fail "the certified version for $host is missing or invalid" || return 1
    host_sha="$(_mainframe_launch_sha256_file "$host_executable")" ||
        _mainframe_launch_identity_fail "could not hash the resolved $host executable" || return 1
    if ! declare -F _mainframe_host_platform_id >/dev/null 2>&1 ||
       ! declare -F _mainframe_host_platform_policy_state >/dev/null 2>&1; then
        _mainframe_launch_identity_fail \
            'the exact host platform policy detector is unavailable'
        return 1
    fi
    current_platform="$(_mainframe_host_platform_id)" || {
        _mainframe_launch_identity_fail \
            'could not determine an exact supported macOS/Linux platform tuple'
        return 1
    }
    platform_policy_state="$(_mainframe_host_platform_policy_state \
        "$current_platform")" || {
        _mainframe_launch_identity_fail \
            'release-platform policy is missing, malformed, or unsafe'
        return 1
    }
    [[ "$platform_policy_state" == listed ]] || {
        _mainframe_launch_identity_fail \
            "platform $current_platform is not release-certified"
        return 1
    }
    case "$host" in
        codex) manifest_platform="${current_platform%-*}" ;;
        claude-code|copilot) manifest_platform="$current_platform" ;;
        gemini) manifest_platform="$current_platform" ;;
    esac
    platform_rows="$("$jq_executable" -cer \
        --arg host "$manifest_key" --arg platform "$manifest_platform" '
        [(.[$host].platforms // {}) | to_entries[] |
          select(.key == $platform)]
        ' "$manifest" 2>/dev/null)" ||
        _mainframe_launch_identity_fail "the platform pins for $host are invalid" || return 1

    # An exact current-platform native executable is independently identified.
    direct_key="$("$jq_executable" -er --arg digest "$host_sha" '
        [.[] | select(.value.executable_sha256 == $digest)] |
        if length == 1 then .[0].key elif length == 0 then "" else error("ambiguous") end
    ' <<<"$platform_rows" 2>/dev/null)" ||
        _mainframe_launch_identity_fail "$host native executable digest is ambiguous" || return 1
    if [[ -n "$direct_key" ]]; then
        _MAINFRAME_HOST_VERSION="$certified_version"
        _MAINFRAME_HOST_IDENTITY="pinned-native:$direct_key:$host_sha"
        _MAINFRAME_HOST_ARGV=("$host_executable")
        return 0
    fi

    case "$host" in
        gemini)
            entry_relative="$("$jq_executable" -er '.gemini.entrypoint' "$manifest")" || return 1
            expected_entry_sha="$("$jq_executable" -er '.gemini.entrypoint_sha256' "$manifest")" || return 1
            [[ "$host_sha" == "$expected_entry_sha" ]] || {
                _mainframe_launch_identity_fail \
                    "gemini launcher bytes are not certified for version $certified_version"
                return 1
            }
            install_root="$(_mainframe_launch_install_root "$host_executable" "$entry_relative")" || {
                _mainframe_launch_identity_fail 'gemini uses an unsupported package layout'
                return 1
            }
            _mainframe_launch_node_executable "$project" "$discovery_path" || {
                _mainframe_launch_identity_fail 'a non-project Node.js executable is required for Gemini'
                return 1
            }
            node_executable="$_MAINFRAME_LAUNCH_NODE_RESULT"
            expected_tree_sha="$("$jq_executable" -er '.gemini.package_tree_sha256' "$manifest")" || return 1
            actual_tree_sha="$(_mainframe_launch_tree_sha256 \
                "$project" "$node_executable" \
                "$install_root/node_modules/@google/gemini-cli" 2>&1)" || {
                _mainframe_launch_identity_fail \
                    "could not authenticate the Gemini package tree: $actual_tree_sha"
                return 1
            }
            [[ "$actual_tree_sha" == "$expected_tree_sha" ]] || {
                _mainframe_launch_identity_fail 'Gemini package-tree bytes do not match the certified manifest'
                return 1
            }
            _MAINFRAME_HOST_ARGV=("$node_executable" "$host_executable")
            selected_key=javascript-bundle
            ;;
        codex)
            entry_relative="$("$jq_executable" -er '.codex.entrypoint' "$manifest")" || return 1
            expected_entry_sha="$("$jq_executable" -er '.codex.entrypoint_sha256' "$manifest")" || return 1
            [[ "$host_sha" == "$expected_entry_sha" ]] || {
                _mainframe_launch_identity_fail \
                    "codex launcher bytes are not certified for version $certified_version"
                return 1
            }
            install_root="$(_mainframe_launch_install_root "$host_executable" "$entry_relative")" || {
                _mainframe_launch_identity_fail 'codex uses an unsupported package layout'
                return 1
            }
            _mainframe_launch_node_executable "$project" "$discovery_path" || {
                _mainframe_launch_identity_fail 'a non-project Node.js executable is required for Codex'
                return 1
            }
            node_executable="$_MAINFRAME_LAUNCH_NODE_RESULT"
            while IFS=$'\t' read -r key package binary_relative expected_binary_sha expected_tree_sha; do
                [[ -n "$key" ]] || continue
                binary="$install_root/$binary_relative"
                [[ -f "$binary" && ! -L "$binary" && -x "$binary" ]] || continue
                actual_binary_sha="$(_mainframe_launch_sha256_file "$binary")" || continue
                [[ "$actual_binary_sha" == "$expected_binary_sha" ]] || continue
                tree_root="$install_root/node_modules/@openai"
                actual_tree_sha="$(_mainframe_launch_tree_sha256 \
                    "$project" "$node_executable" "$tree_root" codex \
                    "${package##*/}" 2>&1)" || {
                    tree_error="$actual_tree_sha"
                    continue
                }
                [[ "$actual_tree_sha" == "$expected_tree_sha" ]] || {
                    tree_error='package-tree bytes differ from the certified manifest'
                    continue
                }
                matches=$((matches + 1))
                selected_key="$key"
            done < <("$jq_executable" -r '
                .[] | [.key, .value.package_alias, .value.binary,
                       .value.executable_sha256, .value.package_tree_sha256] | @tsv
            ' <<<"$platform_rows")
            [[ "$matches" -eq 1 ]] || {
                _mainframe_launch_identity_fail \
                    "Codex wrapper and selected native runtime tree did not match one certified platform${tree_error:+: $tree_error}"
                return 1
            }
            _MAINFRAME_HOST_ARGV=("$node_executable" "$host_executable")
            ;;
        copilot)
            entry_relative="$("$jq_executable" -er '.copilot.entrypoint' "$manifest")" || return 1
            expected_entry_sha="$("$jq_executable" -er '.copilot.entrypoint_sha256' "$manifest")" || return 1
            dependency="$("$jq_executable" -er '.copilot.dependency.package' "$manifest")" || return 1
            [[ "$host_sha" == "$expected_entry_sha" ]] || {
                _mainframe_launch_identity_fail \
                    "copilot launcher bytes are not certified for version $certified_version"
                return 1
            }
            install_root="$(_mainframe_launch_install_root "$host_executable" "$entry_relative")" || {
                _mainframe_launch_identity_fail 'copilot uses an unsupported package layout'
                return 1
            }
            _mainframe_launch_node_executable "$project" "$discovery_path" || {
                _mainframe_launch_identity_fail 'a non-project Node.js executable is required for Copilot'
                return 1
            }
            node_executable="$_MAINFRAME_LAUNCH_NODE_RESULT"
            while IFS=$'\t' read -r key package binary_relative expected_binary_sha expected_tree_sha; do
                [[ -n "$key" ]] || continue
                binary="$install_root/$binary_relative"
                [[ -f "$binary" && ! -L "$binary" && -x "$binary" ]] || continue
                actual_binary_sha="$(_mainframe_launch_sha256_file "$binary")" || continue
                [[ "$actual_binary_sha" == "$expected_binary_sha" ]] || continue
                tree_root="$install_root/node_modules"
                actual_tree_sha="$(_mainframe_launch_tree_sha256 \
                    "$project" "$node_executable" "$tree_root" '@github/copilot' \
                    "$dependency" "$package" 2>&1)" || {
                    tree_error="$actual_tree_sha"
                    continue
                }
                [[ "$actual_tree_sha" == "$expected_tree_sha" ]] || {
                    tree_error='package-tree bytes differ from the certified manifest'
                    continue
                }
                matches=$((matches + 1))
                selected_key="$key"
            done < <("$jq_executable" -r '
                .[] | [.key, .value.package, .value.binary,
                       .value.executable_sha256, .value.runtime_tree_sha256] | @tsv
            ' <<<"$platform_rows")
            [[ "$matches" -eq 1 ]] || {
                _mainframe_launch_identity_fail \
                    "Copilot wrapper, dependency, and native runtime tree did not match one certified platform${tree_error:+: $tree_error}"
                return 1
            }
            _MAINFRAME_HOST_ARGV=("$node_executable" "$host_executable")
            ;;
        claude-code)
            stub_relative="$("$jq_executable" -er '.claude.stub' "$manifest")" || return 1
            cli_wrapper_relative="$("$jq_executable" -er '.claude.cli_wrapper' "$manifest")" || return 1
            expected_stub_sha="$("$jq_executable" -er '.claude.stub_sha256' "$manifest")" || return 1
            expected_wrapper_sha="$("$jq_executable" -er '.claude.cli_wrapper_sha256' "$manifest")" || return 1
            if [[ "$host_sha" == "$expected_stub_sha" ]]; then
                wrapper_relative="$stub_relative"
            elif [[ "$host_sha" == "$expected_wrapper_sha" ]]; then
                wrapper_relative="$cli_wrapper_relative"
            else
                _mainframe_launch_identity_fail \
                    "claude-code launcher bytes are not certified for version $certified_version"
                return 1
            fi
            install_root="$(_mainframe_launch_install_root "$host_executable" "$wrapper_relative")" || {
                _mainframe_launch_identity_fail 'claude-code uses an unsupported package layout'
                return 1
            }
            _mainframe_launch_node_executable "$project" "$discovery_path" || {
                _mainframe_launch_identity_fail 'a non-project Node.js executable is required to authenticate the Claude wrapper'
                return 1
            }
            node_executable="$_MAINFRAME_LAUNCH_NODE_RESULT"
            while IFS=$'\t' read -r key package binary_relative expected_binary_sha expected_tree_sha; do
                [[ -n "$key" ]] || continue
                binary="$install_root/$binary_relative"
                [[ -f "$binary" && ! -L "$binary" && -x "$binary" ]] || continue
                actual_binary_sha="$(_mainframe_launch_sha256_file "$binary")" || continue
                [[ "$actual_binary_sha" == "$expected_binary_sha" ]] || continue
                tree_root="$install_root/node_modules"
                actual_tree_sha="$(_mainframe_launch_tree_sha256 \
                    "$project" "$node_executable" "$tree_root" \
                    '@anthropic-ai/claude-code' "$package" 2>&1)" || {
                    tree_error="$actual_tree_sha"
                    continue
                }
                [[ "$actual_tree_sha" == "$expected_tree_sha" ]] || {
                    tree_error='package-tree bytes differ from the certified manifest'
                    continue
                }
                matches=$((matches + 1))
                selected_key="$key"
                selected_binary="$binary"
            done < <("$jq_executable" -r '
                .[] | [.key, .value.package, .value.binary,
                       .value.executable_sha256, .value.runtime_tree_sha256] | @tsv
            ' <<<"$platform_rows")
            [[ "$matches" -eq 1 ]] || {
                _mainframe_launch_identity_fail \
                    "Claude wrapper and native runtime tree did not match one certified platform${tree_error:+: $tree_error}"
                return 1
            }
            _MAINFRAME_HOST_ARGV=("$selected_binary")
            ;;
    esac

    _MAINFRAME_HOST_VERSION="$certified_version"
    _MAINFRAME_HOST_IDENTITY="pinned-runtime:$selected_key:$host_sha:node-$_MAINFRAME_HOST_NODE_SHA:hasher-$_MAINFRAME_HOST_HASHER_SHA"
    return 0
}

# Resolve the managed block version and host destination from the same
# digest-bound registry consumed by generated adapters and activation. Launch
# receives the already-bound jq executable so project PATH never selects the
# parser for this authority-bearing lookup.
_mainframe_launch_instruction_contract() {
    local host="${1:-}" jq_executable="${2:-}"
    local source_file="${BASH_SOURCE[0]}" physical_lib physical_root
    local registry block_version relative

    [[ -n "$host" && "$jq_executable" == /* && -x "$jq_executable" ]] || {
        _mainframe_launch_error 'activation host contract requires a bound parser'
        return 1
    }
    physical_lib="$(cd "${source_file%/*}" && pwd -P)" || {
        _mainframe_launch_error 'activation host contract root cannot be resolved'
        return 1
    }
    physical_root="${physical_lib%/*}"
    registry="$physical_root/config/host-capabilities.json"

    # This validates the generated adapter marker against the exact registry
    # digest before any field from that registry can affect a project path.
    block_version="$(_mainframe_activate_block_version)" || return 1
    relative="$("$jq_executable" -er --arg host "$host" '
        .hosts[$host] as $record
        | if $record == null then empty
          else $record.activation_instruction_file
          end
        | select(type == "string" and length > 0)
    ' "$registry" 2>/dev/null)" || {
        _mainframe_launch_error "unknown activation host destination: $host"
        return 1
    }
    case "$relative" in
        ""|/*|.|..|./*|../*|*/./*|*/../*|*/.|*/..|*//*|*$'\n'*|*$'\r'*|*$'\t'*)
            _mainframe_launch_error "unsafe activation host destination for $host"
            return 1
            ;;
    esac
    printf '%s\t%s\n' "$block_version" "$relative"
}

# Strictly require one current managed instruction block. Protect status checks
# the native hook; this separate check preserves MAINFRAME's AWM/use protocol,
# which is the "better agent" half of the launch contract.
_mainframe_launch_instruction_current() {
    local host="$1" project="$2" preflight_path="${3:-${PATH:-}}"
    local jq_executable="${4:-}" contract block_version rel extra
    local file counts begin_count end_count begin end current expected

    if [[ -z "$jq_executable" ]]; then
        _mainframe_enforce_bind_jq "$project" "${PATH:-}" || return 1
        jq_executable="$MAINFRAME_AGENT_JQ"
    fi
    contract="$(PATH="$preflight_path" \
        _mainframe_launch_instruction_contract "$host" "$jq_executable")" || return 1
    IFS=$'\t' read -r block_version rel extra <<< "$contract"
    [[ -n "$block_version" && -n "$rel" && -z "$extra" ]] || return 1
    begin="<!-- MAINFRAME:BEGIN v${block_version} -->"
    end="<!-- MAINFRAME:END v${block_version} -->"
    if ! _mainframe_activate_validate_managed_path \
        "$project" "$rel" >/dev/null 2>&1; then
        return 1
    fi
    file="$project/$rel"
    [[ -f "$file" && ! -L "$file" ]] || return 1

    counts="$(PATH="$preflight_path" awk '
        {
            line = $0
            while ((position = index(line, "<!-- MAINFRAME:BEGIN")) > 0) {
                begins++
                line = substr(line, position + 22)
            }
            line = $0
            while ((position = index(line, "<!-- MAINFRAME:END")) > 0) {
                ends++
                line = substr(line, position + 20)
            }
        }
        END { printf "%d %d\n", begins, ends }
    ' "$file")" || return 1
    read -r begin_count end_count <<<"$counts"
    [[ "$begin_count" == 1 && "$end_count" == 1 ]] || return 1
    [[ "$(PATH="$preflight_path" grep -Fxc -- "$begin" "$file" || true)" == 1 ]] || return 1
    [[ "$(PATH="$preflight_path" grep -Fxc -- "$end" "$file" || true)" == 1 ]] || return 1

    current="$(PATH="$preflight_path" awk -v begin="$begin" -v end="$end" '
        $0 == begin { inside = 1 }
        inside { print }
        inside && $0 == end { exit }
    ' "$file")" || return 1
    expected="$(PATH="$preflight_path" _mainframe_activate_block)" || return 1
    [[ "$current" == "$expected" ]]
}

# Verify the selected host's exact hook record with the already-bound jq.
# Calling the general status command here would rediscover jq from PATH; launch
# instead reuses the same record validator after the privileged runtime has
# been bound and sealed.
_mainframe_launch_protection_current() {
    local host="$1" project="$2" preflight_path="$3"
    local record state detail

    record="$(PATH="$preflight_path" \
        _mainframe_protect_config_record "$host" "$project")" || return 1
    IFS=$'\t' read -r state detail <<<"$record"
    if [[ "$state" != configured ]]; then
        printf 'Static readiness: NOT READY (%s: %s)\n' "$state" "$detail"
        return 1
    fi
    printf 'Static readiness: READY\n'
}

_mainframe_launch_sha256_file() {
    local file="$1" digest="" rest=""
    [[ -f "$file" && ! -L "$file" ]] || return 1
    _mainframe_launch_scrub_code_loader_env || return 1

    if [[ -x /usr/bin/sha256sum ]]; then
        read -r digest rest < <(/usr/bin/sha256sum "$file") || return 1
    elif [[ -x /bin/sha256sum ]]; then
        read -r digest rest < <(/bin/sha256sum "$file") || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        read -r digest rest < <(/usr/bin/shasum -a 256 "$file") || return 1
    elif [[ -x /usr/bin/openssl ]]; then
        rest="$(/usr/bin/openssl dgst -sha256 "$file")" || return 1
        digest="${rest##* }"
    elif [[ -x /bin/openssl ]]; then
        rest="$(/bin/openssl dgst -sha256 "$file")" || return 1
        digest="${rest##* }"
    else
        return 1
    fi

    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

mainframe_launch() {
    local host="" project="." policy="medium" runtime_policy="auto" canonical_project
    local host_executable host_version host_identity cli
    local runtime_source
    local protect_output awm_output session_id preflight_path
    local discovery_path="${_MAINFRAME_LAUNCH_DISCOVERY_PATH:-${PATH:-}}"
    local bound_bash bound_jq bound_gateway bound_safety bound_seal
    local host_node host_node_sha host_hasher host_hasher_sha
    local host_set=false project_set=false policy_set=false runtime_set=false dry_run=false

    _mainframe_launch_scrub_code_loader_env || {
        _mainframe_launch_error 'could not clear inherited code-loader environment'
        return 1
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                if [[ "$project_set" == true || $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
                    _mainframe_launch_error '--project requires exactly one directory'
                    return 2
                fi
                project="$2"
                project_set=true
                shift 2
                ;;
            --policy)
                if [[ "$policy_set" == true || $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
                    _mainframe_launch_error '--policy requires exactly one tier'
                    return 2
                fi
                policy="$2"
                policy_set=true
                shift 2
                ;;
            --runtime)
                if [[ "$runtime_set" == true || $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
                    _mainframe_launch_error '--runtime requires exactly one source'
                    return 2
                fi
                runtime_policy="$2"
                runtime_set=true
                shift 2
                ;;
            --dry-run)
                if [[ "$dry_run" == true ]]; then
                    _mainframe_launch_error '--dry-run may be passed only once'
                    return 2
                fi
                dry_run=true
                shift
                ;;
            -h|--help)
                _mainframe_launch_usage
                return 0
                ;;
            --)
                _mainframe_launch_error 'native host arguments are not supported'
                return 2
                ;;
            --*)
                _mainframe_launch_error "unknown option: $1"
                return 2
                ;;
            *)
                if [[ "$host_set" == true ]]; then
                    _mainframe_launch_error \
                        "native host arguments are not supported: $1"
                    return 2
                fi
                host="$1"
                host_set=true
                shift
                ;;
        esac
    done

    if [[ "$host_set" != true ]]; then
        _mainframe_launch_error 'one host is required'
        _mainframe_launch_usage >&2
        return 2
    fi
    _mainframe_launch_host_cli_name "$host" >/dev/null || {
        _mainframe_launch_error \
            "unsupported host: $host (supported: codex, claude-code, copilot, gemini)"
        return 2
    }
    case "$policy" in
        medium|high|critical) ;;
        *)
            _mainframe_launch_error \
                "unsupported policy tier: $policy (supported: medium, high, critical)"
            return 2
            ;;
    esac
    case "$runtime_policy" in
        auto|managed|system) ;;
        *)
            _mainframe_launch_error \
                "unsupported runtime source: $runtime_policy (supported: auto, managed, system)"
            return 2
            ;;
    esac
    if [[ ! -d "$project" ]]; then
        _mainframe_launch_error "project directory not found: $project"
        return 2
    fi
    canonical_project="$(cd -- "$project" 2>/dev/null && pwd -P)" || {
        _mainframe_launch_error "could not resolve project directory: $project"
        return 2
    }

    # Bind the trusted parser and gateway runtime before host authentication;
    # authentication must never execute a PATH-first jq helper first.
    if ! _mainframe_enforce_bind_runtime "$canonical_project" "$discovery_path"; then
        _mainframe_launch_error \
            "the privileged gateway runtime is not ready: ${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}"
        _mainframe_launch_print_recovery "$host" "$canonical_project"
        return 1
    fi
    bound_bash="$MAINFRAME_AGENT_BASH"
    bound_jq="$MAINFRAME_AGENT_JQ"
    bound_gateway="$MAINFRAME_AGENT_GATEWAY"
    bound_safety="$MAINFRAME_AGENT_SAFETY"
    bound_seal="$MAINFRAME_AGENT_SEAL"
    preflight_path="$(_mainframe_launch_preflight_path)" || {
        _mainframe_launch_error 'could not construct the fixed preflight tool path'
        return 1
    }

    if ! _mainframe_host_resolve \
        "$host" "$canonical_project" "$runtime_policy" "$discovery_path"; then
        _mainframe_launch_error \
            "${_MAINFRAME_RUNTIME_ERROR:-host runtime resolution failed}"
        printf 'Inspect both managed and system host state with:\n' >&2
        printf '  mainframe host status %q --runtime %q\n' \
            "$host" "$runtime_policy" >&2
        return 1
    fi
    host_executable="$_MAINFRAME_RUNTIME_EXECUTABLE"
    host_version="$_MAINFRAME_RUNTIME_VERSION"
    host_identity="$_MAINFRAME_RUNTIME_IDENTITY"
    runtime_source="$_MAINFRAME_RUNTIME_SELECTED_SOURCE"
    host_node="$_MAINFRAME_HOST_NODE"
    host_node_sha="$_MAINFRAME_HOST_NODE_SHA"
    host_hasher="$_MAINFRAME_HOST_HASHER"
    host_hasher_sha="$_MAINFRAME_HOST_HASHER_SHA"

    if ! _mainframe_launch_instruction_current \
        "$host" "$canonical_project" "$preflight_path" "$bound_jq"; then
        _mainframe_launch_error \
            "the $host managed instruction block is missing, duplicated, stale, or unsafe"
        _mainframe_launch_print_recovery "$host" "$canonical_project"
        return 1
    fi

    if ! protect_output="$(_mainframe_launch_protection_current \
        "$host" "$canonical_project" "$preflight_path" 2>&1)"; then
        printf '%s\n' "$protect_output" >&2
        _mainframe_launch_error "static protection is not ready for $host"
        _mainframe_launch_print_recovery "$host" "$canonical_project"
        return 1
    fi

    cli="${MAINFRAME_ROOT:-}/bin/mainframe"
    if [[ ! -f "$cli" || -L "$cli" || ! -x "$cli" ]]; then
        _mainframe_launch_error "the installed MAINFRAME CLI could not be resolved"
        return 1
    fi
    if ! awm_output="$(PATH="$preflight_path" \
        "$bound_bash" --noprofile --norc -p "$cli" awm project status \
        --project "$canonical_project" 2>&1)"; then
        _mainframe_launch_error \
            "the project has no valid private AWM mapping; launch was refused"
        _mainframe_launch_print_recovery "$host" "$canonical_project"
        return 1
    fi
    session_id="$("$_MAINFRAME_HOST_JQ" -er '
        select(
            type == "object" and
            .schema_version == 1 and
            .status == "mapped" and
            .private == true and
            (.session_id | type == "string" and test("^[0-9a-f]{12}$"))
        ) | .session_id
    ' <<<"$awm_output" 2>/dev/null)" || {
        _mainframe_launch_error \
            "the project AWM status was not a valid private mapped session"
        _mainframe_launch_print_recovery "$host" "$canonical_project"
        return 1
    }

    printf 'MAINFRAME Agent Launch Preflight\n'
    printf 'Host:                  %s\n' "$host"
    printf 'Host executable:       %q\n' "$host_executable"
    printf 'Runtime source:        %s (policy=%s)\n' "$runtime_source" "$runtime_policy"
    printf 'Host artifact identity: READY (pinned version %s)\n' "$host_version"
    printf 'Identity scope:         %s\n' "$host_identity"
    printf 'Project:               %q\n' "$canonical_project"
    printf 'Policy tier:           %s\n' "$policy"
    printf 'Managed instructions:  READY\n'
    printf 'AWM project session:   READY (%s)\n' "$session_id"
    printf 'Static protection:     READY\n'
    printf 'Host runtime load:     UNVERIFIED\n'

    if [[ "$dry_run" == true ]]; then
        printf 'Dry run complete. No host was started and no project, AWM, or audit state was changed.\n'
        return 0
    fi

    printf 'Starting the host. Complete its native project-trust and hook-review flow.\n' >&2
    printf 'MAINFRAME does not claim runtime protection until the host confirms the hook loaded.\n' >&2
    export MAINFRAME_AGENT_GATE_TIER="$policy"
    cd -- "$canonical_project" || {
        _mainframe_launch_error "could not enter project: $canonical_project"
        return 1
    }
    # Close the update window between preflight and process replacement.
    if ! _mainframe_host_resolve \
        "$host" "$canonical_project" "$runtime_policy" "$discovery_path"; then
        _mainframe_launch_error \
            "host runtime identity changed before exec: ${_MAINFRAME_RUNTIME_ERROR:-authentication failed}"
        return 1
    fi
    if [[ "$_MAINFRAME_RUNTIME_SELECTED_SOURCE" != "$runtime_source" ||
          "$_MAINFRAME_RUNTIME_EXECUTABLE" != "$host_executable" ||
          "$_MAINFRAME_RUNTIME_VERSION" != "$host_version" ||
          "$_MAINFRAME_RUNTIME_IDENTITY" != "$host_identity" ]]; then
        _mainframe_launch_error 'host artifact identity changed before exec'
        return 1
    fi
    if [[ "$_MAINFRAME_HOST_NODE" != "$host_node" ||
          "$_MAINFRAME_HOST_NODE_SHA" != "$host_node_sha" ||
          "$_MAINFRAME_HOST_HASHER" != "$host_hasher" ||
          "$_MAINFRAME_HOST_HASHER_SHA" != "$host_hasher_sha" ]]; then
        _mainframe_launch_error 'Node.js or package-tree hasher identity changed before exec'
        return 1
    fi
    if ! _mainframe_enforce_bind_runtime "$canonical_project" "$discovery_path"; then
        _mainframe_launch_error \
            "gateway runtime bindings changed before exec: ${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}"
        return 1
    fi
    if [[ "$MAINFRAME_AGENT_BASH" != "$bound_bash" ||
          "$MAINFRAME_AGENT_JQ" != "$bound_jq" ||
          "$MAINFRAME_AGENT_GATEWAY" != "$bound_gateway" ||
          "$MAINFRAME_AGENT_SAFETY" != "$bound_safety" ||
          "$MAINFRAME_AGENT_SEAL" != "$bound_seal" ]]; then
        _mainframe_launch_error 'gateway runtime bindings changed before exec'
        return 1
    fi
    if ! _mainframe_launch_host_tooling_current; then
        _mainframe_launch_error 'Node.js or the package-tree hasher changed before exec'
        return 1
    fi
    PATH="$discovery_path"
    export PATH
    unset _MAINFRAME_LAUNCH_DISCOVERY_PATH
    _mainframe_launch_scrub_code_loader_env || {
        _mainframe_launch_error 'could not clear code-loader environment before host exec'
        return 1
    }
    exec "${_MAINFRAME_HOST_ARGV[@]}"
}

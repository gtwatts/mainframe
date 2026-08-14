#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/host_runtime.sh - Read-only managed/system host resolution
# =============================================================================
# This library deliberately contains no acquisition or removal path. It can
# inspect a deterministic, receipt-backed managed host payload and compare it
# with a certified host discovered on PATH. Callers decide whether to use the
# managed payload, the system CLI, or fail closed.
# =============================================================================

[[ -n "${_MAINFRAME_HOST_RUNTIME_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_HOST_RUNTIME_LOADED=1

declare -g _MAINFRAME_HOST_EXPECTED_VERSION=""
declare -g _MAINFRAME_HOST_EXPECTED_PLATFORM=""
declare -g _MAINFRAME_HOST_EXPECTED_TARGET=""
declare -g _MAINFRAME_HOST_EXPECTED_TREE_ROOT=""
declare -g _MAINFRAME_HOST_EXPECTED_TREE_SHA=""
declare -g _MAINFRAME_HOST_EXPECTED_EXECUTABLE=""
declare -g _MAINFRAME_HOST_EXPECTED_EXECUTABLE_SHA=""
declare -g _MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA=""
declare -g _MAINFRAME_HOST_EXPECTED_BUNDLE_ID=""
declare -g _MAINFRAME_HOST_EXPECTED_SUPPORTED=false
declare -g _MAINFRAME_HOST_EXPECTED_ERROR=""

declare -g _MAINFRAME_RUNTIME_MANAGED_STATE=""
declare -g _MAINFRAME_RUNTIME_MANAGED_DETAIL=""
declare -g _MAINFRAME_RUNTIME_MANAGED_EXECUTABLE=""
declare -g _MAINFRAME_RUNTIME_MANAGED_BOUNDARY=""
declare -g _MAINFRAME_RUNTIME_SYSTEM_STATE=""
declare -g _MAINFRAME_RUNTIME_SYSTEM_DETAIL=""
declare -g _MAINFRAME_RUNTIME_SYSTEM_EXECUTABLE=""
declare -g _MAINFRAME_RUNTIME_SYSTEM_BOUNDARY=""
declare -g _MAINFRAME_RUNTIME_SELECTED_STATE=""
declare -g _MAINFRAME_RUNTIME_SELECTED_SOURCE=""
declare -g _MAINFRAME_RUNTIME_SELECTED_BOUNDARY=""
declare -g _MAINFRAME_RUNTIME_EXECUTABLE=""
declare -g _MAINFRAME_RUNTIME_VERSION=""
declare -g _MAINFRAME_RUNTIME_IDENTITY=""
declare -g _MAINFRAME_RUNTIME_ERROR=""

_mainframe_host_usage() {
    cat <<'EOF'
Usage:
  mainframe host status [HOST] [--runtime auto|managed|system] [--json]
  mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]
  mainframe host remove HOST [--dry-run | --yes] [--json]
  mainframe host restore HOST --quarantine-id removed.<18-hex> [--dry-run | --yes] [--json]

Hosts: codex, claude-code, copilot, gemini
Runtime policies: auto (default), managed, system

Status is strictly read-only and offline. It authenticates the current managed
payload, when one exists, and compares it with a certified host CLI on PATH.

Install requires an explicit source. --download acquires only the exact
SRI-pinned package set from registry.npmjs.org; --package-dir stays offline.
Install never invokes npm, package scripts, or vendor executables.
Remove moves one authenticated generation into recoverable private quarantine.
Restore republishes one exact current authenticated quarantine generation and
is always offline. Install, remove, and restore require --yes to mutate state;
--dry-run fully preflights without changing the managed root.

No host action changes PATH, shell profiles, global packages, host
configuration, or project files, and no host action starts a coding agent.

Resolution:
  auto       Prefer a valid managed payload; use a certified system CLI only
             when the managed payload is absent or unsupported. A present but
             corrupt managed payload blocks fallback.
  managed    Require the exact receipt-backed managed payload.
  system     Explicitly inspect/select the certified CLI discovered on PATH.

Options:
  --runtime POLICY  auto, managed, or system (default: auto)
  --json            Emit a closed, path-redacted JSON status record
  -h, --help        Show this help

Run `mainframe host install --help`, `mainframe host remove --help`, or
`mainframe host restore --help` for the managed-lifecycle contract. Managed
Gemini remains gated until its complete runtime closure is pinned.
EOF
}

_mainframe_host_error() {
    printf 'MAINFRAME host: %s\n' "$*" >&2
}

_mainframe_host_supported() {
    case "${1:-}" in
        codex|claude-code|copilot|gemini) return 0 ;;
        *) return 1 ;;
    esac
}

_mainframe_host_hosts() {
    printf '%s\n' codex claude-code copilot gemini
}

_mainframe_host_manifest_key() {
    case "${1:-}" in
        codex) printf 'codex\n' ;;
        claude-code) printf 'claude\n' ;;
        copilot) printf 'copilot\n' ;;
        gemini) printf 'gemini\n' ;;
        *) return 1 ;;
    esac
}

_mainframe_host_cli_name() {
    case "${1:-}" in
        codex) printf 'codex\n' ;;
        claude-code) printf 'claude\n' ;;
        copilot) printf 'copilot\n' ;;
        gemini) printf 'gemini\n' ;;
        *) return 1 ;;
    esac
}

_mainframe_host_managed_boundary() {
    case "${1:-}" in
        codex|claude-code|copilot)
            printf 'managed-direct-native-full-tree\n'
            ;;
        gemini) return 1 ;;
        *) return 1 ;;
    esac
}

_mainframe_host_managed_install_hints() {
    local host="$1" project="${2:-}"

    printf '    Online preview (contacts only the locked registry URLs; installs nothing):\n'
    printf '      mainframe host install %q --download --dry-run\n' "$host"
    printf '    Apply only after reviewing that preview:\n'
    printf '      mainframe host install %q --download --yes\n' "$host"
    printf '    Offline alternative (supply the complete pinned package directory):\n'
    printf '      mainframe host install %q --package-dir /absolute/path/to/pinned-tarballs --dry-run\n' \
        "$host"
    printf '      mainframe host install %q --package-dir /absolute/path/to/pinned-tarballs --yes\n' \
        "$host"
    if [[ -n "$project" ]]; then
        printf '    Then preview and apply protected project setup with that exact runtime:\n'
        printf '      mainframe setup --project %q --host %q --runtime managed --dry-run\n' \
            "$project" "$host"
        printf '      mainframe setup --project %q --host %q --runtime managed --yes\n' \
            "$project" "$host"
    fi
}

_mainframe_host_recovery_platform_state() {
    local platform state

    platform="$(_mainframe_host_platform_id 2>/dev/null)" || {
        printf 'unrecognized|unknown\n'
        return 0
    }
    state="$(_mainframe_host_platform_policy_state "$platform" 2>/dev/null)" || {
        printf 'invalid|%s\n' "$platform"
        return 0
    }
    printf '%s|%s\n' "$state" "$platform"
}

_mainframe_host_recovery_hints() {
    local host="$1" policy="${2:-auto}" managed_state="${3:-unsupported}"
    local project="${4:-}" platform_result platform_state platform

    printf '  Recovery guidance:\n'
    platform_result="$(_mainframe_host_recovery_platform_state)"
    IFS='|' read -r platform_state platform <<< "$platform_result"
    case "$platform_state" in
        listed) ;;
        unlisted)
            printf '    Platform %s is outside this release\x27s certified runtime boundary.\n' \
                "$platform"
            printf '    Neither managed nor system runtime selection is authorized on this tuple.\n'
            return 0
            ;;
        invalid)
            printf '    The release-platform policy is missing, malformed, or unsafe.\n'
            printf '    Verify the MAINFRAME installation before selecting any runtime:\n'
            printf '      mainframe doctor\n'
            return 0
            ;;
        unrecognized|*)
            printf '    This operating-system/platform tuple could not be certified.\n'
            printf '    Neither managed nor system runtime selection is authorized.\n'
            return 0
            ;;
    esac
    if [[ -z "${_MAINFRAME_HOST_EXPECTED_VERSION:-}" ]]; then
        printf '    The certified host identity is unavailable or malformed.\n'
        printf '    Verify the MAINFRAME installation before selecting any runtime:\n'
        printf '      mainframe doctor\n'
        return 0
    fi
    if [[ "$managed_state" == unsupported && "$host" != gemini ]]; then
        printf '    No complete runtime identity is certified for %s on platform %s.\n' \
            "$host" "$platform"
        printf '    Neither managed nor system runtime selection is being suggested.\n'
        return 0
    fi

    if [[ "$policy" == system ]]; then
        printf '    The selected policy requires the exact certified system CLI shown above.\n'
        printf '    Install that system CLI, then run:\n'
        printf '      mainframe host status %q --runtime system\n' "$host"
        if [[ -n "$project" ]]; then
            printf '      mainframe setup --project %q --host %q --runtime system --dry-run\n' \
                "$project" "$host"
        fi
        case "$managed_state" in
            absent)
                printf '    Or explicitly opt into MAINFRAME\x27s certified private managed runtime:\n'
                _mainframe_host_managed_install_hints "$host" "$project"
                ;;
            ready)
                printf '    A certified private managed runtime is already ready as an explicit alternative:\n'
                if [[ -n "$project" ]]; then
                    printf '      mainframe setup --project %q --host %q --runtime managed --dry-run\n' \
                        "$project" "$host"
                else
                    printf '      mainframe host status %q --runtime managed\n' "$host"
                fi
                ;;
            corrupt)
                printf '    Explicit system policy may bypass the separate unsafe managed state.\n'
                printf '    Managed replacement and removal remain refused. Preserve this status record:\n'
                printf '      mainframe host status %q --runtime managed --json\n' "$host"
                ;;
            unsupported|*)
                printf '    No complete managed alternative is certified for this host/platform.\n'
                ;;
        esac
        return 0
    fi

    case "$managed_state" in
        absent)
            printf '    The certified private managed runtime is available but not installed.\n'
            _mainframe_host_managed_install_hints "$host" "$project"
            ;;
        ready)
            printf '    A certified managed runtime is ready, but policy %q did not select it.\n' \
                "$policy"
            if [[ -n "$project" ]]; then
                printf '      mainframe setup --project %q --host %q --runtime managed --dry-run\n' \
                    "$project" "$host"
                printf '      mainframe setup --project %q --host %q --runtime managed --yes\n' \
                    "$project" "$host"
            else
                printf '      mainframe host status %q --runtime managed\n' "$host"
            fi
            ;;
        corrupt)
            printf '    Managed state is unsafe. MAINFRAME refuses automatic fallback, replacement, or removal.\n'
            printf '    Preserve it and capture a path-redacted status record before recovery:\n'
            printf '      mainframe host status %q --runtime managed --json\n' "$host"
            printf '    Follow docs/MANAGED_HOST_PAYLOADS.md; no automatic mutation is being suggested.\n'
            ;;
        unsupported|*)
            printf '    No complete managed runtime is certified for this host/platform.\n'
            printf '    Install the exact certified system CLI version shown above, then run:\n'
            printf '      mainframe host status %q --runtime system\n' "$host"
            if [[ -n "$project" ]]; then
                printf '      mainframe setup --project %q --host %q --runtime system --dry-run\n' \
                    "$project" "$host"
            fi
            ;;
    esac
}

_mainframe_host_system_boundary() {
    local host="$1" identity="$2"
    case "$identity" in
        pinned-native:*) printf 'system-direct-native-executable-only\n' ;;
        pinned-runtime:*)
            if [[ "$host" == gemini ]]; then
                printf 'system-incomplete-closure-unpinned-node\n'
            else
                printf 'system-runtime-tree-unpinned-node\n'
            fi
            ;;
        *) return 1 ;;
    esac
}

_mainframe_host_reset_expected() {
    _MAINFRAME_HOST_EXPECTED_VERSION=""
    _MAINFRAME_HOST_EXPECTED_PLATFORM=""
    _MAINFRAME_HOST_EXPECTED_TARGET=""
    _MAINFRAME_HOST_EXPECTED_TREE_ROOT=""
    _MAINFRAME_HOST_EXPECTED_TREE_SHA=""
    _MAINFRAME_HOST_EXPECTED_EXECUTABLE=""
    _MAINFRAME_HOST_EXPECTED_EXECUTABLE_SHA=""
    _MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA=""
    _MAINFRAME_HOST_EXPECTED_BUNDLE_ID=""
    _MAINFRAME_HOST_EXPECTED_SUPPORTED=false
    _MAINFRAME_HOST_EXPECTED_ERROR=""
}

_mainframe_host_reset_resolution() {
    _MAINFRAME_RUNTIME_MANAGED_STATE=""
    _MAINFRAME_RUNTIME_MANAGED_DETAIL=""
    _MAINFRAME_RUNTIME_MANAGED_EXECUTABLE=""
    _MAINFRAME_RUNTIME_MANAGED_BOUNDARY=""
    _MAINFRAME_RUNTIME_SYSTEM_STATE=""
    _MAINFRAME_RUNTIME_SYSTEM_DETAIL=""
    _MAINFRAME_RUNTIME_SYSTEM_EXECUTABLE=""
    _MAINFRAME_RUNTIME_SYSTEM_BOUNDARY=""
    _MAINFRAME_RUNTIME_SELECTED_STATE=""
    _MAINFRAME_RUNTIME_SELECTED_SOURCE=""
    _MAINFRAME_RUNTIME_SELECTED_BOUNDARY=""
    _MAINFRAME_RUNTIME_EXECUTABLE=""
    _MAINFRAME_RUNTIME_VERSION=""
    _MAINFRAME_RUNTIME_IDENTITY=""
    _MAINFRAME_RUNTIME_ERROR=""
}

_mainframe_host_sha256_stream() {
    local output digest rest

    if [[ -x /usr/bin/sha256sum ]]; then
        read -r digest rest < <(/usr/bin/sha256sum) || return 1
    elif [[ -x /bin/sha256sum ]]; then
        read -r digest rest < <(/bin/sha256sum) || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        read -r digest rest < <(/usr/bin/shasum -a 256) || return 1
    elif [[ -x /usr/bin/openssl ]]; then
        output="$(/usr/bin/openssl dgst -sha256)" || return 1
        digest="${output##* }"
    elif [[ -x /bin/openssl ]]; then
        output="$(/bin/openssl dgst -sha256)" || return 1
        digest="${output##* }"
    else
        return 1
    fi
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

_mainframe_host_sha256_file() {
    local file="$1"
    [[ -f "$file" && ! -L "$file" ]] || return 1
    if declare -F _mainframe_launch_sha256_file >/dev/null 2>&1; then
        _mainframe_launch_sha256_file "$file"
    else
        _mainframe_host_sha256_stream < "$file"
    fi
}

_mainframe_host_sha256_fields() {
    local field
    {
        printf 'MAINFRAME-HOST-PAYLOAD-BUNDLE-ID-V1\0'
        for field in "$@"; do
            [[ "$field" != *$'\n'* && "$field" != *$'\r'* &&
               "$field" != *$'\t'* ]] || return 1
            printf '%s\0' "$field"
        done
    } | _mainframe_host_sha256_stream
}

_mainframe_host_locked_package_record() {
    local lock_path="$1" expected_name="$2" expected_version="$3"
    local expected_integrity="$4"
    local package_leaf expected_resolved
    local lock="${MAINFRAME_ROOT:-}/scripts/dev/native-host/package-lock.json"

    [[ "$lock_path" =~ ^node_modules/(@[a-z0-9._-]+/)?[a-z0-9._-]+$ &&
       "$lock_path" != *$'\n'* && "$lock_path" != *$'\r'* &&
       "$lock_path" != *$'\t'* ]] || return 1
    [[ "$expected_name" =~ ^(@[a-z0-9._-]+/)?[a-z0-9._-]+$ ]] || return 1
    [[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.-]+)?$ ]] || return 1
    [[ "$expected_integrity" =~ ^sha512-[A-Za-z0-9+/]+={0,2}$ ]] || return 1
    package_leaf="${expected_name##*/}"
    expected_resolved="https://registry.npmjs.org/$expected_name/-/$package_leaf-$expected_version.tgz"

    _mainframe_enforce_jq -er \
        --arg path "$lock_path" \
        --arg name "$expected_name" \
        --arg version "$expected_version" \
        --arg resolved "$expected_resolved" \
        --arg integrity "$expected_integrity" '
      .packages[$path] as $record |
      select($record | type == "object") |
      select(($record.name // $name) == $name) |
      select($record.version == $version) |
      select($record.integrity == $integrity) |
      select($record.resolved == $resolved) |
      [$path, $name, $version, $record.resolved, $integrity] | @tsv
    ' "$lock" 2>/dev/null
}

_mainframe_host_package_plan() {
    local host="$1" platform="$2" manifest
    local os arch libc platform_key
    local root_name root_version root_integrity root_path
    local platform_name platform_version platform_integrity platform_path
    local dependency_name dependency_version dependency_integrity dependency_path

    manifest="${MAINFRAME_ROOT:-}/scripts/dev/native-host/hosts.json"
    [[ -f "$manifest" && ! -L "$manifest" ]] || return 1
    IFS=- read -r os arch libc <<< "$platform"
    [[ -n "$os" && -n "$arch" && -n "$libc" ]] || return 1

    case "$host" in
        codex)
            platform_key="$os-$arch"
            root_name="$(_mainframe_enforce_jq -er '.codex.package' "$manifest" 2>/dev/null)" || return 1
            root_version="$(_mainframe_enforce_jq -er '.codex.version' "$manifest" 2>/dev/null)" || return 1
            root_integrity="$(_mainframe_enforce_jq -er '.codex.integrity' "$manifest" 2>/dev/null)" || return 1
            platform_name="$root_name"
            platform_path="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.codex.platforms[$key].package_alias' "$manifest" 2>/dev/null)" || return 1
            platform_version="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.codex.platforms[$key].package_version' "$manifest" 2>/dev/null)" || return 1
            platform_integrity="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.codex.platforms[$key].integrity' "$manifest" 2>/dev/null)" || return 1
            root_path="node_modules/$root_name"
            platform_path="node_modules/$platform_path"
            _mainframe_host_locked_package_record \
                "$root_path" "$root_name" "$root_version" "$root_integrity" || return 1
            _mainframe_host_locked_package_record \
                "$platform_path" "$platform_name" "$platform_version" "$platform_integrity" || return 1
            ;;
        claude-code)
            platform_key="$platform"
            root_name="$(_mainframe_enforce_jq -er '.claude.package' "$manifest" 2>/dev/null)" || return 1
            root_version="$(_mainframe_enforce_jq -er '.claude.version' "$manifest" 2>/dev/null)" || return 1
            root_integrity="$(_mainframe_enforce_jq -er '.claude.integrity' "$manifest" 2>/dev/null)" || return 1
            platform_name="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.claude.platforms[$key].package' "$manifest" 2>/dev/null)" || return 1
            platform_version="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.claude.platforms[$key].package_version' "$manifest" 2>/dev/null)" || return 1
            platform_integrity="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.claude.platforms[$key].integrity' "$manifest" 2>/dev/null)" || return 1
            root_path="node_modules/$root_name"
            platform_path="node_modules/$platform_name"
            _mainframe_host_locked_package_record \
                "$root_path" "$root_name" "$root_version" "$root_integrity" || return 1
            _mainframe_host_locked_package_record \
                "$platform_path" "$platform_name" "$platform_version" "$platform_integrity" || return 1
            ;;
        copilot)
            platform_key="$platform"
            root_name="$(_mainframe_enforce_jq -er '.copilot.package' "$manifest" 2>/dev/null)" || return 1
            root_version="$(_mainframe_enforce_jq -er '.copilot.version' "$manifest" 2>/dev/null)" || return 1
            root_integrity="$(_mainframe_enforce_jq -er '.copilot.integrity' "$manifest" 2>/dev/null)" || return 1
            dependency_name="$(_mainframe_enforce_jq -er '.copilot.dependency.package' "$manifest" 2>/dev/null)" || return 1
            dependency_version="$(_mainframe_enforce_jq -er '.copilot.dependency.version' "$manifest" 2>/dev/null)" || return 1
            dependency_integrity="$(_mainframe_enforce_jq -er '.copilot.dependency.integrity' "$manifest" 2>/dev/null)" || return 1
            platform_name="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.copilot.platforms[$key].package' "$manifest" 2>/dev/null)" || return 1
            platform_version="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.copilot.platforms[$key].package_version' "$manifest" 2>/dev/null)" || return 1
            platform_integrity="$(_mainframe_enforce_jq -er --arg key "$platform_key" \
                '.copilot.platforms[$key].integrity' "$manifest" 2>/dev/null)" || return 1
            root_path="node_modules/$root_name"
            platform_path="node_modules/$platform_name"
            dependency_path="node_modules/$dependency_name"
            _mainframe_host_locked_package_record \
                "$root_path" "$root_name" "$root_version" "$root_integrity" || return 1
            _mainframe_host_locked_package_record \
                "$platform_path" "$platform_name" "$platform_version" "$platform_integrity" || return 1
            _mainframe_host_locked_package_record \
                "$dependency_path" "$dependency_name" "$dependency_version" "$dependency_integrity" || return 1
            ;;
        *) return 1 ;;
    esac
}

_mainframe_host_package_set_sha256() {
    local host="$1" platform="$2"
    local lock_path package_name version resolved integrity
    local plan digest sort_bin

    plan="$(_mainframe_host_package_plan "$host" "$platform")" || return 1
    [[ -n "$plan" ]] || return 1
    [[ -x /usr/bin/sort ]] && sort_bin=/usr/bin/sort || sort_bin=/bin/sort
    [[ -x "$sort_bin" ]] || return 1
    digest="$({
        printf 'MAINFRAME-HOST-PACKAGE-SET-V1\0'
        while IFS=$'\t' read -r lock_path package_name version resolved integrity; do
            [[ -n "$lock_path" && -n "$package_name" && -n "$version" &&
               -n "$resolved" && -n "$integrity" ]] || return 1
            printf 'P\0%s\0%s\0%s\0%s\0%s\0' \
                "$lock_path" "$package_name" "$version" "$resolved" "$integrity"
        done < <(printf '%s\n' "$plan" | LC_ALL=C "$sort_bin")
    } | _mainframe_host_sha256_stream)" || return 1
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

_mainframe_host_absolute_path_syntax() {
    local path="${1:-}"
    [[ "$path" == /* && "$path" != / && "$path" != *'//'*
       && "$path" != */./* && "$path" != */../*
       && "$path" != */. && "$path" != */..
       && "$path" != *$'\n'* && "$path" != *$'\r'*
       && "$path" != *$'\t'* ]]
}

_mainframe_host_data_home() {
    local data_home
    if [[ -n "${XDG_DATA_HOME:-}" ]]; then
        data_home="$XDG_DATA_HOME"
    else
        data_home="${HOME:-}/.local/share"
    fi
    _mainframe_host_absolute_path_syntax "$data_home" || return 1
    printf '%s\n' "${data_home%/}"
}

_mainframe_host_runtime_root() {
    local data_home
    data_home="$(_mainframe_host_data_home)" || return 1
    printf '%s/mainframe/host-payloads\n' "$data_home"
}

_mainframe_host_stat_owner_mode() {
    local path="$1" result owner mode
    if [[ -x /usr/bin/stat ]]; then
        result="$(/usr/bin/stat -c '%u %a' "$path" 2>/dev/null ||
            /usr/bin/stat -f '%u %Mp%Lp' "$path" 2>/dev/null)" || return 1
    elif [[ -x /bin/stat ]]; then
        result="$(/bin/stat -c '%u %a' "$path" 2>/dev/null ||
            /bin/stat -f '%u %Mp%Lp' "$path" 2>/dev/null)" || return 1
    else
        return 1
    fi
    [[ "$result" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1
    read -r owner mode <<< "$result"
    [[ ${#mode} -eq 4 && "$mode" == 0* ]] && mode="${mode#0}"
    printf '%s %s\n' "$owner" "$mode"
}

_mainframe_host_stat_identity() {
    local path="$1" result
    if [[ -x /usr/bin/stat ]]; then
        result="$(/usr/bin/stat -c '%d:%i' "$path" 2>/dev/null ||
            /usr/bin/stat -f '%d:%i' "$path" 2>/dev/null)" || return 1
    elif [[ -x /bin/stat ]]; then
        result="$(/bin/stat -c '%d:%i' "$path" 2>/dev/null ||
            /bin/stat -f '%d:%i' "$path" 2>/dev/null)" || return 1
    else
        return 1
    fi
    [[ "$result" =~ ^[0-9]+:[0-9]+$ ]] || return 1
    printf '%s\n' "$result"
}

_mainframe_host_link_count() {
    local path="$1" result
    if [[ -x /usr/bin/stat ]]; then
        result="$(/usr/bin/stat -c '%h' "$path" 2>/dev/null ||
            /usr/bin/stat -f '%l' "$path" 2>/dev/null)" || return 1
    elif [[ -x /bin/stat ]]; then
        result="$(/bin/stat -c '%h' "$path" 2>/dev/null ||
            /bin/stat -f '%l' "$path" 2>/dev/null)" || return 1
    else
        return 1
    fi
    [[ "$result" =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "$result"
}

_mainframe_host_acl_listing_safe() {
    local line permissions
    while IFS= read -r line; do
        [[ "$line" == *' allow '* ]] || continue
        permissions=",${line#* allow },"
        case "$permissions" in
            *,write,*|*,append,*|*,delete,*|*,delete_child,*|\
            *,add_file,*|*,add_subdirectory,*|*,writeattr,*|\
            *,writeextattr,*|*,writeowner,*|*,writesecurity,*|*,chown,*)
                return 1
                ;;
        esac
    done
}

_mainframe_host_no_write_acl() {
    local path="$1"
    [[ "$(_mainframe_host_uname -s 2>/dev/null || true)" == Darwin ]] || return 0
    [[ -x /bin/ls ]] || return 1
    (
        set -o pipefail
        LC_ALL=C /bin/ls -lde "$path" 2>/dev/null |
            _mainframe_host_acl_listing_safe
    )
}

_mainframe_host_tree_no_write_acl() {
    local root="$1" find_bin
    [[ "$(_mainframe_host_uname -s 2>/dev/null || true)" == Darwin ]] || return 0
    [[ -x /bin/ls ]] || return 1
    [[ -x /usr/bin/find ]] && find_bin=/usr/bin/find || find_bin=/bin/find
    [[ -x "$find_bin" ]] || return 1
    (
        set -o pipefail
        LC_ALL=C "$find_bin" "$root" -exec /bin/ls -lde {} + 2>/dev/null |
            _mainframe_host_acl_listing_safe
    )
}

_mainframe_host_owned_private() {
    local path="$1" exact_mode="${2:-}" owner mode numeric
    read -r owner mode < <(_mainframe_host_stat_owner_mode "$path") || return 1
    [[ "$owner" -eq "$EUID" ]] || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
    [[ -z "$exact_mode" || "$mode" == "$exact_mode" ]]
}

_mainframe_host_trusted_ancestry() {
    local path="$1" current="" component owner mode numeric
    local sticky_parent=false
    local -a components=()
    _mainframe_host_absolute_path_syntax "$path" || return 1
    read -r owner mode < <(_mainframe_host_stat_owner_mode /) || return 1
    [[ "$owner" -eq 0 ]] || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
    IFS=/ read -r -a components <<< "${path#/}"

    # Existing ancestors must be controlled by root or the current user. A
    # root-owned sticky directory such as /tmp is accepted only when the next
    # path component already exists as a trusted directory; this prevents an
    # attacker from pre-creating an absent predictable child.
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
        current+="/$component"
        [[ ! -L "$current" ]] || return 1
        if [[ ! -e "$current" ]]; then
            [[ "$sticky_parent" == false ]] || return 1
            continue
        fi
        [[ -d "$current" ]] || return 1
        _mainframe_host_no_write_acl "$current" || return 1
        read -r owner mode < <(_mainframe_host_stat_owner_mode "$current") || return 1
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
        numeric=$((8#$mode))
        if [[ "$sticky_parent" == true ]]; then
            (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
            sticky_parent=false
        fi
        if (( (numeric & 0022) != 0 || (numeric & 07000) != 0 )); then
            if [[ "$owner" -eq 0 ]] &&
               (( (numeric & 01000) != 0 && (numeric & 06000) == 0 )); then
                sticky_parent=true
            else
                return 1
            fi
        fi
    done
    [[ "$sticky_parent" == false ]]
}

_mainframe_host_no_symlink_ancestry() {
    local path="$1" current="" component
    local -a components=()
    _mainframe_host_absolute_path_syntax "$path" || return 1
    IFS=/ read -r -a components <<< "${path#/}"
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
        current+="/$component"
        if [[ -L "$current" ]]; then
            return 1
        fi
        if [[ -e "$current" && ! -d "$current" && "$current" != "$path" ]]; then
            return 1
        fi
    done
}

_mainframe_host_path_within() {
    local root="$1" path="$2" root_identity current current_identity parent
    if [[ "$root" == / ]]; then
        [[ "$path" == /* ]]
        return
    fi
    _mainframe_host_absolute_path_syntax "$root" || return 1
    _mainframe_host_absolute_path_syntax "$path" || return 1
    [[ -d "$root" && ! -L "$root" ]] || return 1
    root_identity="$(_mainframe_host_stat_identity "$root")" || return 1

    # Compare directory identities rather than spelling. This catches
    # case-folded aliases on default macOS filesystems and still works for a
    # not-yet-created descendant by walking to its deepest existing ancestor.
    current="$path"
    while :; do
        if [[ -d "$current" && ! -L "$current" ]]; then
            current_identity="$(_mainframe_host_stat_identity "$current")" || return 1
            [[ "$current_identity" == "$root_identity" ]] && return 0
        fi
        [[ "$current" != / ]] || break
        parent="${current%/*}"
        [[ -n "$parent" ]] || parent=/
        [[ "$parent" != "$current" ]] || break
        current="$parent"
    done
    return 1
}

_mainframe_host_decode_mount_path() {
    local path="$1"
    path="${path//\\040/ }"
    path="${path//\\011/$'\t'}"
    path="${path//\\012/$'\n'}"
    path="${path//\\134/\\}"
    printf '%s\n' "$path"
}

_mainframe_host_mount_conflicts() {
    local root="$1" target="$2" mount_point="$3"
    [[ "$mount_point" != "$root" ]] || return 1
    _mainframe_host_path_within "$root" "$mount_point" || return 1
    _mainframe_host_path_within "$mount_point" "$target" ||
        _mainframe_host_path_within "$target" "$mount_point"
}

_mainframe_host_no_nested_mounts() {
    local root="$1" target="$2" os line prefix mount_point output
    os="$(_mainframe_host_uname -s 2>/dev/null)" || return 1
    case "$os" in
        Linux)
            [[ -f /proc/self/mountinfo && ! -L /proc/self/mountinfo ]] || return 1
            while IFS= read -r line; do
                prefix="${line%%' - '*}"
                read -r _ _ _ _ mount_point _ <<< "$prefix"
                [[ -n "$mount_point" ]] || return 1
                mount_point="$(_mainframe_host_decode_mount_path "$mount_point")" || return 1
                [[ "$mount_point" == / ]] ||
                _mainframe_host_absolute_path_syntax "$mount_point" || return 1
                if _mainframe_host_mount_conflicts \
                    "$root" "$target" "$mount_point"; then
                    return 1
                fi
            done < /proc/self/mountinfo
            ;;
        Darwin)
            [[ -x /sbin/mount ]] || return 1
            output="$(LC_ALL=C /sbin/mount 2>/dev/null)" || return 1
            while IFS= read -r line; do
                [[ "$line" == *' on '*' ('* ]] || return 1
                mount_point="${line#* on }"
                mount_point="${mount_point%% \(*}"
                mount_point="$(_mainframe_host_decode_mount_path "$mount_point")" || return 1
                [[ "$mount_point" == / ]] ||
                _mainframe_host_absolute_path_syntax "$mount_point" || return 1
                if _mainframe_host_mount_conflicts \
                    "$root" "$target" "$mount_point"; then
                    return 1
                fi
            done <<< "$output"
            ;;
        *) return 1 ;;
    esac
}

_mainframe_host_private_directory_chain() {
    local root="$1" target="$2" relative current component root_device device
    local -a components=()
    _mainframe_host_path_within "$root" "$target" || return 1
    relative="${target#"$root"}"
    relative="${relative#/}"
    current="$root"
    root_device="$(_mainframe_host_stat_identity "$root")" || return 1
    root_device="${root_device%%:*}"
    IFS=/ read -r -a components <<< "$relative"
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
        current+="/$component"
        [[ -e "$current" || -L "$current" ]] || continue
        [[ -d "$current" && ! -L "$current" ]] || return 1
        _mainframe_host_owned_private "$current" || return 1
        _mainframe_host_no_write_acl "$current" || return 1
        device="$(_mainframe_host_stat_identity "$current")" || return 1
        [[ "${device%%:*}" == "$root_device" ]] || return 1
    done
}

_mainframe_host_readonly_payload_chain() {
    local target="$1" tree_root="$2" relative current component target_device device
    local -a components=()
    _mainframe_host_path_within "$target" "$tree_root" || return 1
    relative="${tree_root#"$target"}"
    relative="${relative#/}"
    current="$target"
    target_device="$(_mainframe_host_stat_identity "$target")" || return 1
    target_device="${target_device%%:*}"
    IFS=/ read -r -a components <<< "$relative"
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
        current+="/$component"
        [[ -d "$current" && ! -L "$current" ]] || return 1
        _mainframe_host_owned_private "$current" 500 || return 1
        _mainframe_host_no_write_acl "$current" || return 1
        device="$(_mainframe_host_stat_identity "$current")" || return 1
        [[ "${device%%:*}" == "$target_device" ]] || return 1
    done
}

_mainframe_host_uname() {
    if [[ -x /usr/bin/uname ]]; then
        /usr/bin/uname "$@"
    elif [[ -x /bin/uname ]]; then
        /bin/uname "$@"
    else
        return 1
    fi
}

_mainframe_host_linux_libc() {
    local output candidate
    if [[ -x /usr/bin/getconf ]]; then
        output="$(LC_ALL=C /usr/bin/getconf GNU_LIBC_VERSION 2>/dev/null || true)"
        [[ "$output" == glibc\ * ]] && { printf 'glibc\n'; return 0; }
    elif [[ -x /bin/getconf ]]; then
        output="$(LC_ALL=C /bin/getconf GNU_LIBC_VERSION 2>/dev/null || true)"
        [[ "$output" == glibc\ * ]] && { printf 'glibc\n'; return 0; }
    fi
    for candidate in /lib/ld-musl-*.so.1 /lib64/ld-musl-*.so.1 \
        /usr/lib/ld-musl-*.so.1 /usr/lib64/ld-musl-*.so.1; do
        # Distribution musl loaders are commonly symlinks in root-controlled
        # system directories. Detection reads no loader bytes and executes
        # nothing, so a regular target is sufficient here.
        [[ -f "$candidate" ]] || continue
        printf 'musl\n'
        return 0
    done
    return 1
}

_mainframe_host_platform_id() {
    local os arch libc
    os="$(_mainframe_host_uname -s)" || return 1
    arch="$(_mainframe_host_uname -m)" || return 1
    case "$os" in
        Darwin) libc=none ;;
        Linux) libc="$(_mainframe_host_linux_libc)" || return 1 ;;
        *) return 1 ;;
    esac
    case "$arch" in
        arm64|aarch64|x86_64) ;;
        *) return 1 ;;
    esac
    printf '%s-%s-%s\n' "$os" "$arch" "$libc"
}

_mainframe_host_platform_policy_state() {
    local platform="$1"
    local definition="${MAINFRAME_ROOT:-}/scripts/dev/native-host/release-platforms.json"
    [[ -f "$definition" && ! -L "$definition" ]] || return 1
    _mainframe_enforce_jq -er --arg platform "$platform" '
      if (
        type == "object" and .schema_version == 1 and
        (.platforms | type) == "array" and (.platforms | length) > 0 and
        ([.platforms[].id] | length) == ([.platforms[].id] | unique | length) and
        all(.platforms[];
          type == "object" and
          (keys == ["arch", "id", "os", "system_libc"]) and
          (.id | type) == "string" and (.os | type) == "string" and
          (.arch | type) == "string" and (.system_libc | type) == "string" and
          (.os | IN("Darwin", "Linux")) and
          (.arch | IN("arm64", "aarch64", "x86_64")) and
          (.system_libc | IN("none", "glibc", "musl")) and
          (.id == (.os + "-" + .arch + "-" + .system_libc)) and
          ((.os == "Darwin" and .system_libc == "none") or
           (.os == "Linux" and (.system_libc | IN("glibc", "musl"))))
        )
      ) then
        if any(.platforms[]; .id == $platform) then "listed" else "unlisted" end
      else
        error("invalid release-platform policy")
      end
    ' "$definition" 2>/dev/null
}

_mainframe_host_platform_policy_valid() {
    [[ "$(_mainframe_host_platform_policy_state \
        '__mainframe-policy-validation-only__')" == unlisted ]]
}

_mainframe_host_prepare_expected() {
    local host="$1" manifest_key manifest lock platform platform_policy_state
    local lookup os arch libc
    local manifest_sha lock_sha version tree_root tree_sha executable executable_sha
    local package_set_sha mainframe_version
    local bundle_id runtime_root

    _mainframe_host_reset_expected
    _mainframe_host_supported "$host" || {
        _MAINFRAME_HOST_EXPECTED_ERROR="unsupported host: $host"
        return 1
    }
    manifest="${MAINFRAME_ROOT:-}/scripts/dev/native-host/hosts.json"
    lock="${MAINFRAME_ROOT:-}/scripts/dev/native-host/package-lock.json"
    [[ -f "$manifest" && ! -L "$manifest" && -f "$lock" && ! -L "$lock" ]] || {
        _MAINFRAME_HOST_EXPECTED_ERROR='host manifest or package lock is missing or unsafe'
        return 1
    }
    manifest_key="$(_mainframe_host_manifest_key "$host")" || return 1
    version="$(_mainframe_enforce_jq -er --arg host "$manifest_key" '
      select(.schema_version == 1) |
      .[$host].version |
      select(type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
    ' "$manifest" 2>/dev/null)" || {
        _MAINFRAME_HOST_EXPECTED_ERROR='certified host version is missing or invalid'
        return 1
    }
    _MAINFRAME_HOST_EXPECTED_VERSION="$version"
    platform="$(_mainframe_host_platform_id)" || {
        _MAINFRAME_HOST_EXPECTED_ERROR='could not identify a supported macOS/Linux platform tuple'
        return 0
    }
    _MAINFRAME_HOST_EXPECTED_PLATFORM="$platform"
    platform_policy_state="$(_mainframe_host_platform_policy_state "$platform")" || {
        _MAINFRAME_HOST_EXPECTED_ERROR='release-platform policy is missing, malformed, or unsafe'
        return 1
    }
    if [[ "$platform_policy_state" != listed ]]; then
        _MAINFRAME_HOST_EXPECTED_ERROR="platform $platform is pinned but not release-certified"
        return 0
    fi
    if [[ "$host" == gemini ]]; then
        _MAINFRAME_HOST_EXPECTED_ERROR='managed Gemini is gated until its complete dependency closure and Node runtime are pinned'
        return 0
    fi

    mainframe_version="${MAINFRAME_VERSION:-}"
    [[ "$mainframe_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        _MAINFRAME_HOST_EXPECTED_ERROR='MAINFRAME version is missing or invalid'
        return 1
    }

    IFS=- read -r os arch libc <<< "$platform"
    case "$host" in
        codex)
            lookup="$os-$arch"
            tree_root='payload/node_modules/@openai'
            tree_sha="$(_mainframe_enforce_jq -er --arg key "$lookup" \
                '.codex.platforms[$key].package_tree_sha256 |
                 select(type == "string" and test("^[0-9a-f]{64}$"))' \
                "$manifest" 2>/dev/null)" || {
                _MAINFRAME_HOST_EXPECTED_ERROR="no certified Codex payload for $platform"
                return 0
            }
            executable="$(_mainframe_enforce_jq -er --arg key "$lookup" \
                '.codex.platforms[$key].binary |
                 select(type == "string" and startswith("node_modules/") and
                        (contains("..") | not))' "$manifest" 2>/dev/null)" || return 1
            executable_sha="$(_mainframe_enforce_jq -er --arg key "$lookup" \
                '.codex.platforms[$key].executable_sha256 |
                 select(type == "string" and test("^[0-9a-f]{64}$"))' \
                "$manifest" 2>/dev/null)" || return 1
            ;;
        claude-code|copilot)
            lookup="$platform"
            tree_root='payload/node_modules'
            tree_sha="$(_mainframe_enforce_jq -er --arg host "$manifest_key" --arg key "$lookup" \
                '.[$host].platforms[$key].runtime_tree_sha256 |
                 select(type == "string" and test("^[0-9a-f]{64}$"))' \
                "$manifest" 2>/dev/null)" || {
                _MAINFRAME_HOST_EXPECTED_ERROR="no certified $host payload for $platform"
                return 0
            }
            executable="$(_mainframe_enforce_jq -er --arg host "$manifest_key" --arg key "$lookup" \
                '.[$host].platforms[$key].binary |
                 select(type == "string" and startswith("node_modules/") and
                        (contains("..") | not))' "$manifest" 2>/dev/null)" || return 1
            executable_sha="$(_mainframe_enforce_jq -er --arg host "$manifest_key" --arg key "$lookup" \
                '.[$host].platforms[$key].executable_sha256 |
                 select(type == "string" and test("^[0-9a-f]{64}$"))' \
                "$manifest" 2>/dev/null)" || return 1
            ;;
    esac
    executable="payload/$executable"
    manifest_sha="$(_mainframe_host_sha256_file "$manifest")" || return 1
    lock_sha="$(_mainframe_host_sha256_file "$lock")" || return 1
    package_set_sha="$(_mainframe_host_package_set_sha256 "$host" "$platform")" || {
        _MAINFRAME_HOST_EXPECTED_ERROR='certified host package set is missing, inconsistent, or unsafe'
        return 1
    }
    bundle_id="$(_mainframe_host_sha256_fields \
        "$mainframe_version" "$host" "$version" "$platform" \
        "$manifest_sha" "$lock_sha" "$package_set_sha" \
        "$tree_root" "$tree_sha" "$executable" "$executable_sha")" || return 1
    runtime_root="$(_mainframe_host_runtime_root)" || {
        _MAINFRAME_HOST_EXPECTED_ERROR='XDG data home is not a safe absolute path'
        return 1
    }

    _MAINFRAME_HOST_EXPECTED_TARGET="$runtime_root/v1/$host/$version/$platform/$bundle_id"
    _MAINFRAME_HOST_EXPECTED_TREE_ROOT="$tree_root"
    _MAINFRAME_HOST_EXPECTED_TREE_SHA="$tree_sha"
    _MAINFRAME_HOST_EXPECTED_EXECUTABLE="$executable"
    _MAINFRAME_HOST_EXPECTED_EXECUTABLE_SHA="$executable_sha"
    _MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA="$package_set_sha"
    _MAINFRAME_HOST_EXPECTED_BUNDLE_ID="$bundle_id"
    _MAINFRAME_HOST_EXPECTED_SUPPORTED=true
}

_mainframe_host_emit_tree_stream() {
    local root="$1" path relative size_before size_after
    local find_bin sort_bin cat_bin wc_bin
    [[ -d "$root" && ! -L "$root" ]] || return 1
    [[ -x /usr/bin/find ]] && find_bin=/usr/bin/find || find_bin=/bin/find
    [[ -x /usr/bin/sort ]] && sort_bin=/usr/bin/sort || sort_bin=/bin/sort
    [[ -x /bin/cat ]] && cat_bin=/bin/cat || cat_bin=/usr/bin/cat
    [[ -x /usr/bin/wc ]] && wc_bin=/usr/bin/wc || wc_bin=/bin/wc
    [[ -x "$find_bin" && -x "$sort_bin" && -x "$cat_bin" && -x "$wc_bin" ]] || return 1

    printf 'MAINFRAME-PACKAGE-TREE-SHA256-V1\0'
    while IFS= read -r path; do
        [[ "$path" == "$root/"* ]] || return 1
        relative="${path#"$root/"}"
        [[ -n "$relative" && "$relative" != *$'\n'* &&
           "$relative" != *$'\r'* && "$relative" != *$'\t'* ]] || return 1
        if [[ -L "$path" ]]; then
            return 1
        elif [[ -d "$path" ]]; then
            printf 'D\0%s\0' "$relative"
        elif [[ -f "$path" ]]; then
            size_before="$("$wc_bin" -c < "$path")" || return 1
            size_before="${size_before//[[:space:]]/}"
            [[ "$size_before" =~ ^[0-9]+$ ]] || return 1
            printf 'F\0%s\0%s\0' "$relative" "$size_before"
            "$cat_bin" -- "$path" || return 1
            size_after="$("$wc_bin" -c < "$path")" || return 1
            size_after="${size_after//[[:space:]]/}"
            [[ "$size_after" == "$size_before" ]] || return 1
        else
            return 1
        fi
    done < <(LC_ALL=C "$find_bin" "$root" -mindepth 1 -print | LC_ALL=C "$sort_bin")
}

_mainframe_host_tree_sha256() {
    local root="$1" digest
    digest="$(
        set -o pipefail
        _mainframe_host_emit_tree_stream "$root" | _mainframe_host_sha256_stream
    )" || return 1
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

_mainframe_host_validate_tree_metadata() {
    local root="$1" path find_bin root_device device listing
    [[ -d "$root" && ! -L "$root" ]] || return 1
    _mainframe_host_owned_private "$root" 500 || return 1
    _mainframe_host_tree_no_write_acl "$root" || return 1
    root_device="$(_mainframe_host_stat_identity "$root")" || return 1
    root_device="${root_device%%:*}"
    [[ -x /usr/bin/find ]] && find_bin=/usr/bin/find || find_bin=/bin/find
    [[ -x "$find_bin" ]] || return 1
    listing="$(LC_ALL=C "$find_bin" "$root" -mindepth 1 -print 2>/dev/null)" ||
        return 1
    if [[ -n "$listing" ]]; then
        while IFS= read -r path; do
            [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] || return 1
            [[ ! -L "$path" && ( -d "$path" || -f "$path" ) ]] || return 1
            _mainframe_host_owned_private "$path" 500 || return 1
            device="$(_mainframe_host_stat_identity "$path")" || return 1
            [[ "${device%%:*}" == "$root_device" ]] || return 1
            if [[ -f "$path" ]]; then
                [[ "$(_mainframe_host_link_count "$path")" == 1 ]] || return 1
            fi
        done <<< "$listing"
    fi
}

_mainframe_host_target_inventory_exact() {
    local target="$1" path name count=0 find_bin listing
    [[ -d "$target" && ! -L "$target" ]] || return 1
    [[ -x /usr/bin/find ]] && find_bin=/usr/bin/find || find_bin=/bin/find
    [[ -x "$find_bin" ]] || return 1
    listing="$(LC_ALL=C "$find_bin" "$target" \
        -mindepth 1 -maxdepth 1 -print 2>/dev/null)" || return 1
    if [[ -n "$listing" ]]; then
        while IFS= read -r path; do
            name="${path##*/}"
            case "$name" in
                payload|receipt.json) ;;
                *) return 1 ;;
            esac
            count=$((count + 1))
        done <<< "$listing"
    fi
    [[ "$count" -eq 2 ]]
}

_mainframe_host_directory_children_exact() {
    local directory="$1"
    shift
    local path name expected found=false count=0 find_bin listing
    [[ -d "$directory" && ! -L "$directory" ]] || return 1
    [[ -x /usr/bin/find ]] && find_bin=/usr/bin/find || find_bin=/bin/find
    [[ -x "$find_bin" ]] || return 1
    listing="$(LC_ALL=C "$find_bin" "$directory" \
        -mindepth 1 -maxdepth 1 -print 2>/dev/null)" || return 1
    if [[ -n "$listing" ]]; then
        while IFS= read -r path; do
            name="${path##*/}"
            found=false
            for expected in "$@"; do
                [[ "$name" == "$expected" ]] && { found=true; break; }
            done
            [[ "$found" == true ]] || return 1
            count=$((count + 1))
        done <<< "$listing"
    fi
    [[ "$count" -eq "$#" ]]
}

_mainframe_host_payload_inventory_exact() {
    local host="$1" target="$2"
    _mainframe_host_directory_children_exact "$target/payload" node_modules || return 1
    if [[ "$host" == codex ]]; then
        _mainframe_host_directory_children_exact \
            "$target/payload/node_modules" '@openai' || return 1
    fi
}

_mainframe_host_validate_receipt() {
    local host="$1" receipt="$2" manifest lock manifest_sha lock_sha
    manifest="${MAINFRAME_ROOT:-}/scripts/dev/native-host/hosts.json"
    lock="${MAINFRAME_ROOT:-}/scripts/dev/native-host/package-lock.json"
    manifest_sha="$(_mainframe_host_sha256_file "$manifest")" || return 1
    lock_sha="$(_mainframe_host_sha256_file "$lock")" || return 1
    [[ -f "$receipt" && ! -L "$receipt" ]] || return 1
    _mainframe_host_owned_private "$receipt" 600 || return 1
    _mainframe_host_no_write_acl "$receipt" || return 1
    [[ "$(_mainframe_host_link_count "$receipt")" == 1 ]] || return 1
    _mainframe_enforce_jq -e \
        --arg kind 'mainframe-managed-host-payload' \
        --arg bundle "$_MAINFRAME_HOST_EXPECTED_BUNDLE_ID" \
        --arg mainframe "${MAINFRAME_VERSION:-}" \
        --arg host "$host" \
        --arg version "$_MAINFRAME_HOST_EXPECTED_VERSION" \
        --arg platform "$_MAINFRAME_HOST_EXPECTED_PLATFORM" \
        --arg manifest "$manifest_sha" \
        --arg lock "$lock_sha" \
        --arg package_set "$_MAINFRAME_HOST_EXPECTED_PACKAGE_SET_SHA" \
        --arg tree_root "$_MAINFRAME_HOST_EXPECTED_TREE_ROOT" \
        --arg tree_sha "$_MAINFRAME_HOST_EXPECTED_TREE_SHA" \
        --arg executable "$_MAINFRAME_HOST_EXPECTED_EXECUTABLE" \
        --arg executable_sha "$_MAINFRAME_HOST_EXPECTED_EXECUTABLE_SHA" '
      type == "object" and
      (keys == [
        "bundle_id", "executable", "executable_sha256", "host",
        "host_version", "hosts_manifest_sha256", "kind", "launch_mode",
        "mainframe_version", "package_lock_sha256", "package_set_sha256", "platform",
        "schema_version", "tree_root", "tree_sha256"
      ]) and
      .schema_version == 1 and .kind == $kind and .bundle_id == $bundle and
      .mainframe_version == $mainframe and .host == $host and
      .host_version == $version and .platform == $platform and
      .hosts_manifest_sha256 == $manifest and .package_lock_sha256 == $lock and
      .package_set_sha256 == $package_set and
      .tree_root == $tree_root and .tree_sha256 == $tree_sha and
      .executable == $executable and .executable_sha256 == $executable_sha and
      .launch_mode == "direct-native"
    ' "$receipt" >/dev/null 2>&1
}

_mainframe_host_authenticate_generation() {
    local host="$1" target="$2" tree_root executable
    local actual_tree actual_executable

    [[ -d "$target" && ! -L "$target" ]] || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='current managed payload target is not a real directory'
        return 1
    }
    _mainframe_host_owned_private "$target" 700 || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='current managed payload target is not owner-only mode 0700'
        return 1
    }
    _mainframe_host_target_inventory_exact "$target" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload generation contains unexpected top-level entries'
        return 1
    }
    _mainframe_host_validate_receipt "$host" "$target/receipt.json" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload receipt is missing, malformed, stale, or unsafe'
        return 1
    }
    tree_root="$target/$_MAINFRAME_HOST_EXPECTED_TREE_ROOT"
    executable="$target/$_MAINFRAME_HOST_EXPECTED_EXECUTABLE"
    _mainframe_host_payload_inventory_exact "$host" "$target" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload contains entries outside the certified package closure'
        return 1
    }
    _mainframe_host_readonly_payload_chain "$target" "$tree_root" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload directories are not normalized owner-read-only mode 0500'
        return 1
    }
    _mainframe_host_validate_tree_metadata "$tree_root" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload tree has unsafe ownership, modes, links, or entry types'
        return 1
    }
    actual_tree="$(_mainframe_host_tree_sha256 "$tree_root")" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload tree could not be authenticated'
        return 1
    }
    [[ "$actual_tree" == "$_MAINFRAME_HOST_EXPECTED_TREE_SHA" ]] || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload tree differs from the certified tree'
        return 1
    }
    [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload executable is missing or unsafe'
        return 1
    }
    _mainframe_host_owned_private "$executable" 500 || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload executable ownership or mode is unsafe'
        return 1
    }
    actual_executable="$(_mainframe_host_sha256_file "$executable")" || return 1
    [[ "$actual_executable" == "$_MAINFRAME_HOST_EXPECTED_EXECUTABLE_SHA" ]] || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload executable differs from the certified executable'
        return 1
    }
    _MAINFRAME_RUNTIME_MANAGED_STATE=ready
    _MAINFRAME_RUNTIME_MANAGED_DETAIL="receipt and complete selected tree are current at $target"
    _MAINFRAME_RUNTIME_MANAGED_EXECUTABLE="$executable"
}

_mainframe_host_probe_managed() {
    local host="$1" project="${2:-}" data_home runtime_root target
    _MAINFRAME_RUNTIME_MANAGED_STATE=corrupt
    _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload authentication failed'
    _MAINFRAME_RUNTIME_MANAGED_EXECUTABLE=""
    _MAINFRAME_RUNTIME_MANAGED_BOUNDARY="$(_mainframe_host_managed_boundary \
        "$host" 2>/dev/null || true)"

    if ! _mainframe_host_prepare_expected "$host"; then
        _MAINFRAME_RUNTIME_MANAGED_DETAIL="${_MAINFRAME_HOST_EXPECTED_ERROR:-managed payload metadata is invalid}"
        return 1
    fi
    if [[ "$_MAINFRAME_HOST_EXPECTED_SUPPORTED" != true ]]; then
        _MAINFRAME_RUNTIME_MANAGED_STATE=unsupported
        _MAINFRAME_RUNTIME_MANAGED_DETAIL="$_MAINFRAME_HOST_EXPECTED_ERROR"
        return 0
    fi
    runtime_root="$(_mainframe_host_runtime_root)" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='XDG data home is not a safe absolute path'
        return 1
    }
    target="$_MAINFRAME_HOST_EXPECTED_TARGET"
    if [[ -n "$project" ]] && _mainframe_host_path_within "$project" "$runtime_root"; then
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload root resolves inside the project'
        return 1
    fi
    if [[ -n "${MAINFRAME_ROOT:-}" ]] &&
       _mainframe_host_path_within "$MAINFRAME_ROOT" "$runtime_root"; then
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload root resolves inside MAINFRAME_ROOT'
        return 1
    fi
    data_home="$(_mainframe_host_data_home)" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='XDG data home is not a safe absolute path'
        return 1
    }
    _mainframe_host_trusted_ancestry "$data_home" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='XDG data home has untrusted ownership, permissions, or ancestry'
        return 1
    }
    _mainframe_host_no_symlink_ancestry "$target" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload path has unsafe syntax or symlink ancestry'
        return 1
    }
    if [[ ! -e "$runtime_root" && ! -L "$runtime_root" ]]; then
        _MAINFRAME_RUNTIME_MANAGED_STATE=absent
        _MAINFRAME_RUNTIME_MANAGED_DETAIL="not installed; expected under $runtime_root"
        return 0
    fi
    [[ -d "$data_home" && ! -L "$data_home" ]] || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='XDG data home is not a real directory'
        return 1
    }
    _mainframe_host_owned_private "$data_home" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='XDG data home ownership or permissions are unsafe'
        return 1
    }
    _mainframe_host_private_directory_chain "$data_home" "$runtime_root" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload ancestry has unsafe ownership, permissions, links, or mounts'
        return 1
    }
    _mainframe_host_no_nested_mounts "$data_home" "$target" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload ancestry crosses an unsafe nested mount'
        return 1
    }
    [[ -d "$runtime_root" && ! -L "$runtime_root" ]] || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload root is not a real directory'
        return 1
    }
    _mainframe_host_owned_private "$runtime_root" 700 || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload root is not owner-only mode 0700'
        return 1
    }
    _mainframe_host_private_directory_chain "$runtime_root" "$target" || {
        _MAINFRAME_RUNTIME_MANAGED_DETAIL='managed payload directory chain has unsafe ownership, modes, or entry types'
        return 1
    }
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        _MAINFRAME_RUNTIME_MANAGED_STATE=absent
        _MAINFRAME_RUNTIME_MANAGED_DETAIL="current certified payload is not installed; expected $target"
        return 0
    fi
    _mainframe_host_authenticate_generation "$host" "$target"
}

_mainframe_host_probe_system() {
    local host="$1" project="$2" discovery_path="$3" cli candidate resolved
    _MAINFRAME_RUNTIME_SYSTEM_STATE=absent
    _MAINFRAME_RUNTIME_SYSTEM_DETAIL='host executable was not found on PATH'
    _MAINFRAME_RUNTIME_SYSTEM_EXECUTABLE=""
    _MAINFRAME_RUNTIME_SYSTEM_BOUNDARY=""
    cli="$(_mainframe_host_cli_name "$host")" || return 1
    candidate="$(PATH="$discovery_path" type -P "$cli" 2>/dev/null || true)"
    [[ -n "$candidate" ]] || return 0
    if [[ "$candidate" != /* || ! -x "$candidate" ]]; then
        _MAINFRAME_RUNTIME_SYSTEM_STATE=unsafe
        _MAINFRAME_RUNTIME_SYSTEM_DETAIL='PATH result is not an absolute executable'
        return 0
    fi
    resolved="$(_mainframe_launch_resolve_executable "$candidate")" || {
        _MAINFRAME_RUNTIME_SYSTEM_STATE=unsafe
        _MAINFRAME_RUNTIME_SYSTEM_DETAIL='PATH executable could not be safely resolved'
        return 0
    }
    if [[ "$project" == / || "$resolved" == "$project" || "$resolved" == "$project/"* ]]; then
        _MAINFRAME_RUNTIME_SYSTEM_STATE=unsafe
        _MAINFRAME_RUNTIME_SYSTEM_DETAIL='refusing a project-controlled host executable'
        _MAINFRAME_RUNTIME_SYSTEM_EXECUTABLE="$resolved"
        return 0
    fi
    _MAINFRAME_RUNTIME_SYSTEM_EXECUTABLE="$resolved"
    if _mainframe_launch_host_compatible "$host" "$resolved" "$project" "$discovery_path"; then
        _MAINFRAME_RUNTIME_SYSTEM_STATE=ready
        _MAINFRAME_RUNTIME_SYSTEM_DETAIL="pinned version $_MAINFRAME_HOST_VERSION; $_MAINFRAME_HOST_IDENTITY"
        _MAINFRAME_RUNTIME_SYSTEM_BOUNDARY="$(_mainframe_host_system_boundary \
            "$host" "$_MAINFRAME_HOST_IDENTITY")" || {
            _MAINFRAME_RUNTIME_SYSTEM_STATE=incompatible
            _MAINFRAME_RUNTIME_SYSTEM_DETAIL='authenticated host identity has no recognized trust boundary'
            _MAINFRAME_RUNTIME_SYSTEM_BOUNDARY=""
        }
    else
        _MAINFRAME_RUNTIME_SYSTEM_STATE=incompatible
        _MAINFRAME_RUNTIME_SYSTEM_DETAIL="${_MAINFRAME_HOST_ERROR:-host artifact authentication failed}"
    fi
}

_mainframe_host_authenticate_managed_for_launch() {
    local host="$1" project="$2" discovery_path="$3" executable
    executable="$_MAINFRAME_RUNTIME_MANAGED_EXECUTABLE"
    [[ -n "$executable" ]] || return 1
    if ! _mainframe_launch_host_compatible "$host" "$executable" "$project" "$discovery_path"; then
        _MAINFRAME_RUNTIME_MANAGED_STATE=corrupt
        _MAINFRAME_RUNTIME_MANAGED_DETAIL="managed executable failed host authentication: ${_MAINFRAME_HOST_ERROR:-unknown error}"
        _MAINFRAME_RUNTIME_MANAGED_EXECUTABLE=""
        return 1
    fi
}

_mainframe_host_resolve() {
    local host="$1" project="$2" policy="${3:-auto}"
    local discovery_path="${4:-${PATH:-}}"
    _mainframe_host_reset_resolution
    _mainframe_host_supported "$host" || {
        _MAINFRAME_RUNTIME_ERROR="unsupported host: $host"
        _MAINFRAME_RUNTIME_SELECTED_STATE=unavailable
        return 2
    }
    case "$policy" in
        auto|managed|system) ;;
        *)
            _MAINFRAME_RUNTIME_ERROR="unsupported runtime policy: $policy"
            _MAINFRAME_RUNTIME_SELECTED_STATE=unavailable
            return 2
            ;;
    esac
    if [[ -z "${MAINFRAME_AGENT_JQ:-}" ]]; then
        _mainframe_enforce_bind_jq "$project" "$discovery_path" || {
            _MAINFRAME_RUNTIME_ERROR="trusted host metadata is unavailable: ${_MAINFRAME_ENFORCE_BIND_ERROR:-jq binding failed}"
            _MAINFRAME_RUNTIME_SELECTED_STATE=blocked
            return 1
        }
    fi
    if ! _mainframe_host_platform_policy_valid; then
        _MAINFRAME_RUNTIME_SELECTED_STATE=blocked
        _MAINFRAME_RUNTIME_ERROR='release-platform policy is missing, malformed, ambiguous, or unsafe'
        return 1
    fi

    if [[ "$policy" != system ]]; then
        _mainframe_host_probe_managed "$host" "$project" || true
        if [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == ready ]]; then
            if _mainframe_host_authenticate_managed_for_launch \
                "$host" "$project" "$discovery_path"; then
                _MAINFRAME_RUNTIME_SELECTED_STATE=ready
                _MAINFRAME_RUNTIME_SELECTED_SOURCE=managed
                _MAINFRAME_RUNTIME_SELECTED_BOUNDARY="$_MAINFRAME_RUNTIME_MANAGED_BOUNDARY"
                _MAINFRAME_RUNTIME_EXECUTABLE="$_MAINFRAME_RUNTIME_MANAGED_EXECUTABLE"
                _MAINFRAME_RUNTIME_VERSION="$_MAINFRAME_HOST_VERSION"
                _MAINFRAME_RUNTIME_IDENTITY="managed-full-tree; $_MAINFRAME_HOST_IDENTITY"
                return 0
            fi
        fi
        if [[ "$policy" == managed ]]; then
            if [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == corrupt ]]; then
                _MAINFRAME_RUNTIME_SELECTED_STATE=blocked
            else
                _MAINFRAME_RUNTIME_SELECTED_STATE=unavailable
            fi
            _MAINFRAME_RUNTIME_ERROR="managed $host payload is $_MAINFRAME_RUNTIME_MANAGED_STATE: $_MAINFRAME_RUNTIME_MANAGED_DETAIL"
            return 1
        fi
        if [[ "$_MAINFRAME_RUNTIME_MANAGED_STATE" == corrupt ]]; then
            _MAINFRAME_RUNTIME_SELECTED_STATE=blocked
            _MAINFRAME_RUNTIME_ERROR="managed $host payload is corrupt; system fallback refused: $_MAINFRAME_RUNTIME_MANAGED_DETAIL"
            return 1
        fi
    fi

    _mainframe_host_probe_system "$host" "$project" "$discovery_path" || true
    if [[ "$_MAINFRAME_RUNTIME_SYSTEM_STATE" == ready ]]; then
        _MAINFRAME_RUNTIME_SELECTED_STATE=ready
        _MAINFRAME_RUNTIME_SELECTED_SOURCE=system
        _MAINFRAME_RUNTIME_SELECTED_BOUNDARY="$_MAINFRAME_RUNTIME_SYSTEM_BOUNDARY"
        _MAINFRAME_RUNTIME_EXECUTABLE="$_MAINFRAME_RUNTIME_SYSTEM_EXECUTABLE"
        _MAINFRAME_RUNTIME_VERSION="$_MAINFRAME_HOST_VERSION"
        _MAINFRAME_RUNTIME_IDENTITY="$_MAINFRAME_HOST_IDENTITY"
        return 0
    fi
    _MAINFRAME_RUNTIME_SELECTED_STATE=unavailable
    _MAINFRAME_RUNTIME_ERROR="system $host CLI is $_MAINFRAME_RUNTIME_SYSTEM_STATE: $_MAINFRAME_RUNTIME_SYSTEM_DETAIL"
    return 1
}

_mainframe_host_status_human() {
    local host="$1" policy="$2" project="$3" discovery_path="$4"
    local managed_state managed_detail system_state system_detail selected_state
    local selected_source expected_version expected_platform
    local managed_boundary system_boundary selected_boundary

    _mainframe_host_probe_managed "$host" "$project" || true
    managed_state="$_MAINFRAME_RUNTIME_MANAGED_STATE"
    managed_detail="$_MAINFRAME_RUNTIME_MANAGED_DETAIL"
    managed_boundary="$_MAINFRAME_RUNTIME_MANAGED_BOUNDARY"
    expected_version="$_MAINFRAME_HOST_EXPECTED_VERSION"
    expected_platform="$_MAINFRAME_HOST_EXPECTED_PLATFORM"
    _mainframe_host_probe_system "$host" "$project" "$discovery_path" || true
    system_state="$_MAINFRAME_RUNTIME_SYSTEM_STATE"
    system_detail="$_MAINFRAME_RUNTIME_SYSTEM_DETAIL"
    system_boundary="$_MAINFRAME_RUNTIME_SYSTEM_BOUNDARY"
    _mainframe_host_resolve "$host" "$project" "$policy" "$discovery_path" || true
    if [[ -n "${_MAINFRAME_RUNTIME_MANAGED_STATE:-}" ]]; then
        managed_state="$_MAINFRAME_RUNTIME_MANAGED_STATE"
        managed_detail="$_MAINFRAME_RUNTIME_MANAGED_DETAIL"
    fi
    selected_state="$_MAINFRAME_RUNTIME_SELECTED_STATE"
    selected_source="${_MAINFRAME_RUNTIME_SELECTED_SOURCE:-none}"
    selected_boundary="$_MAINFRAME_RUNTIME_SELECTED_BOUNDARY"

    printf '%s\n' "$host"
    printf '  Certified: %s (%s)\n' "${expected_version:-unavailable}" "${expected_platform:-unsupported platform}"
    printf '  Managed:   %s — %s\n' "$managed_state" "$managed_detail"
    printf '  Managed boundary:  %s\n' "${managed_boundary:-not established}"
    printf '  System:    %s — %s\n' "$system_state" "$system_detail"
    printf '  System boundary:   %s\n' "${system_boundary:-not established}"
    printf '  Selected:  %s (%s, policy=%s)\n' "$selected_state" "$selected_source" "$policy"
    printf '  Selected boundary: %s\n' "${selected_boundary:-not established}"
    if [[ "$selected_state" != ready ]]; then
        _mainframe_host_recovery_hints "$host" "$policy" "$managed_state"
    fi
}

_mainframe_host_status_json_row() {
    local host="$1" policy="$2" project="$3" discovery_path="$4"
    local managed_state managed_supported system_state selected_state selected_source
    local expected_version expected_platform
    local managed_boundary system_boundary selected_boundary

    _mainframe_host_probe_managed "$host" "$project" || true
    managed_state="$_MAINFRAME_RUNTIME_MANAGED_STATE"
    expected_version="$_MAINFRAME_HOST_EXPECTED_VERSION"
    expected_platform="$_MAINFRAME_HOST_EXPECTED_PLATFORM"
    managed_supported="$_MAINFRAME_HOST_EXPECTED_SUPPORTED"
    managed_boundary="$_MAINFRAME_RUNTIME_MANAGED_BOUNDARY"
    _mainframe_host_probe_system "$host" "$project" "$discovery_path" || true
    system_state="$_MAINFRAME_RUNTIME_SYSTEM_STATE"
    system_boundary="$_MAINFRAME_RUNTIME_SYSTEM_BOUNDARY"
    _mainframe_host_resolve "$host" "$project" "$policy" "$discovery_path" || true
    selected_state="$_MAINFRAME_RUNTIME_SELECTED_STATE"
    selected_source="$_MAINFRAME_RUNTIME_SELECTED_SOURCE"
    selected_boundary="$_MAINFRAME_RUNTIME_SELECTED_BOUNDARY"

    _mainframe_enforce_jq -cn \
        --arg host "$host" \
        --arg version "$expected_version" \
        --arg platform "$expected_platform" \
        --arg managed "$managed_state" \
        --argjson supported "$managed_supported" \
        --arg managed_boundary "$managed_boundary" \
        --arg system "$system_state" \
        --arg system_boundary "$system_boundary" \
        --arg selection "$selected_state" \
        --arg source "$selected_source" \
        --arg selected_boundary "$selected_boundary" '
      {
        host: $host,
        certified_version: (if $version == "" then null else $version end),
        platform: (if $platform == "" then null else $platform end),
        managed: {
          state: $managed,
          supported: $supported,
          trust_boundary: (if $managed_boundary == "" then null else $managed_boundary end)
        },
        system: {
          state: $system,
          trust_boundary: (if $system_boundary == "" then null else $system_boundary end)
        },
        selection: {
          state: $selection,
          source: (if $source == "" then null else $source end),
          trust_boundary: (if $selected_boundary == "" then null else $selected_boundary end)
        }
      }'
}

_mainframe_host_status() {
    local requested_host="" policy=auto json=false host project discovery_path
    local host_set=false policy_set=false json_set=false rows='[]' row

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --runtime)
                if [[ "$policy_set" == true ]]; then
                    _mainframe_host_error '--runtime may be passed only once'
                    return 2
                fi
                if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
                    _mainframe_host_error '--runtime requires exactly one policy'
                    return 2
                fi
                policy="$2"
                policy_set=true
                shift 2
                ;;
            --json)
                if [[ "$json_set" == true ]]; then
                    _mainframe_host_error '--json may be passed only once'
                    return 2
                fi
                json=true
                json_set=true
                shift
                ;;
            -h|--help)
                _mainframe_host_usage
                return 0
                ;;
            --*)
                _mainframe_host_error "unknown option: $1"
                return 2
                ;;
            *)
                if [[ "$host_set" == true ]]; then
                    _mainframe_host_error "unexpected argument: $1"
                    return 2
                fi
                requested_host="$1"
                host_set=true
                shift
                ;;
        esac
    done
    case "$policy" in
        auto|managed|system) ;;
        *)
            _mainframe_host_error "unsupported runtime policy: $policy (supported: auto, managed, system)"
            return 2
            ;;
    esac
    if [[ "$host_set" == true ]] && ! _mainframe_host_supported "$requested_host"; then
        _mainframe_host_error \
            "unsupported host: $requested_host (supported: codex, claude-code, copilot, gemini)"
        return 2
    fi
    project="${MAINFRAME_ROOT:-}"
    [[ "$project" == /* && -d "$project" ]] || {
        _mainframe_host_error 'MAINFRAME_ROOT is not a safe absolute directory'
        return 1
    }
    discovery_path="${_MAINFRAME_HOST_DISCOVERY_PATH:-${PATH:-}}"
    _mainframe_enforce_bind_jq "$project" "$discovery_path" || {
        _mainframe_host_error \
            "trusted host metadata is unavailable: ${_MAINFRAME_ENFORCE_BIND_ERROR:-jq binding failed}"
        return 1
    }

    if [[ "$json" == true ]]; then
        if [[ "$host_set" == true ]]; then
            row="$(_mainframe_host_status_json_row \
                "$requested_host" "$policy" "$project" "$discovery_path")" || return 1
            rows="$(_mainframe_enforce_jq -cn --argjson row "$row" '[$row]')" || return 1
        else
            while IFS= read -r host; do
                row="$(_mainframe_host_status_json_row \
                    "$host" "$policy" "$project" "$discovery_path")" || return 1
                rows="$(_mainframe_enforce_jq -cn \
                    --argjson rows "$rows" --argjson row "$row" '$rows + [$row]')" || return 1
            done < <(_mainframe_host_hosts)
        fi
        _mainframe_enforce_jq -n --arg policy "$policy" --argjson hosts "$rows" '
          {
            schema_version: 1,
            command: "host-status",
            mode: "read-only-offline",
            policy: $policy,
            hosts: $hosts
          }'
        return 0
    fi

    printf 'MAINFRAME Host Runtime Status\n'
    printf 'Mode: read-only and offline\n'
    printf 'Policy: %s\n' "$policy"
    printf 'Managed root: %s\n\n' "$(_mainframe_host_runtime_root 2>/dev/null || printf 'unsafe XDG data path')"
    if [[ "$host_set" == true ]]; then
        _mainframe_host_status_human "$requested_host" "$policy" "$project" "$discovery_path"
    else
        while IFS= read -r host; do
            _mainframe_host_status_human "$host" "$policy" "$project" "$discovery_path"
            printf '\n'
        done < <(_mainframe_host_hosts)
    fi
    printf 'No host was started and no runtime, shell, host, project, or network state was changed.\n'
}

mainframe_host() {
    local action="${1:-}"
    case "$action" in
        status)
            shift
            _mainframe_host_status "$@"
            ;;
        install)
            shift
            if ! declare -F _mainframe_host_install >/dev/null 2>&1; then
                _mainframe_host_error 'managed-host lifecycle support is unavailable'
                return 1
            fi
            _mainframe_host_install "$@"
            ;;
        remove)
            shift
            if ! declare -F _mainframe_host_remove >/dev/null 2>&1; then
                _mainframe_host_error 'managed-host lifecycle support is unavailable'
                return 1
            fi
            _mainframe_host_remove "$@"
            ;;
        restore)
            shift
            if ! declare -F _mainframe_host_restore >/dev/null 2>&1; then
                _mainframe_host_error 'managed-host lifecycle support is unavailable'
                return 1
            fi
            _mainframe_host_restore "$@"
            ;;
        -h|--help|help|'')
            _mainframe_host_usage
            ;;
        *)
            _mainframe_host_error \
                "unsupported action: $action (supported: status, install, remove, restore)"
            _mainframe_host_usage >&2
            return 2
            ;;
    esac
}

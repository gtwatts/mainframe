#!/bin/bash -p
# =============================================================================
# MAINFRAME bootstrap installer
# =============================================================================
# Installs a checksum-verified, versioned release archive. With no selector, the
# bootstrap uses the same immutable-latest resolver as --latest. An exact
# MAINFRAME_VERSION or --release-version remains reproducible. The old mutable
# install.sh path is available only with the explicit --legacy-source selector.
#
#   release_version=X.Y.Z
#   curl -fsSLo get-mainframe.sh \
#     "https://raw.githubusercontent.com/gtwatts/mainframe/v${release_version}/get-mainframe.sh"
#   /bin/bash --noprofile --norc -p get-mainframe.sh \
#     --release-version "$release_version"
#
# Convenience resolver (the downloaded bootstrap itself is still mutable):
#
#   curl -fsSLo get-mainframe.sh \
#     "https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh"
#   /bin/bash --noprofile --norc -p get-mainframe.sh --latest
#
# Explicit legacy mutable mode and custom location (MAINFRAME_DIR is a
# compatibility alias):
#
#   curl -fsSLo get-mainframe.sh \
#     https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh
#   MAINFRAME_DIR="$HOME/tools/mainframe" \
#     /bin/bash --noprofile --norc -p get-mainframe.sh --legacy-source
#
# Verified release (recommended):
#
#   MAINFRAME_VERSION=X.Y.Z /bin/bash --noprofile --norc -p get-mainframe.sh
#   /bin/bash --noprofile --norc -p get-mainframe.sh --release-version X.Y.Z
#   /bin/bash --noprofile --norc -p get-mainframe.sh --latest

# An explicit unprivileged `bash get-mainframe.sh` can import functions whose
# names shadow even bootstrap primitives such as `set` and `builtin`. Enter a
# fixed protected interpreter before executing any command in that process.
# Keeping the complete bootstrap in the protected branch lets the unprivileged
# branch reach EOF immediately and preserve the delegated command's status.
case "$-" in
    *p*)

set -euo pipefail

# Keep this pre-runtime bootstrap parseable by Apple's Bash 3.2. Direct
# execution enters through the fixed privileged shebang above; all later Bash
# probes and delegations use a freshly constructed environment and protected
# startup flags.
_mainframe_bootstrap_environment_key_is_safe() {
    case "${1:-}" in
        BASHOPTS|BASH_ENV|BASH_LOADABLES_PATH|BASH_XTRACEFD|CDPATH|ENV|GLOBIGNORE|\
        NODE_OPTIONS|NODE_PATH|NODE_REDIRECT_WARNINGS|NODE_REPL_HISTORY|NODE_V8_COVERAGE|\
        PERL5LIB|PERL5OPT|PERLLIB|PYTHONBREAKPOINT|PYTHONHOME|PYTHONINSPECT|\
        PYTHONPATH|PYTHONSTARTUP|PYTHONUSERBASE|PYTHONWARNINGS|RUBYOPT|RUBYLIB|SHELLOPTS|\
        MAINFRAME_BOOTSTRAP_INTERNAL_CURL|MAINFRAME_BOOTSTRAP_INTERNAL_MV|\
        MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ|_MAINFRAME_BOOTSTRAP_TEST_CURL|\
        _MAINFRAME_BOOTSTRAP_TEST_MV|BASH_FUNC_*|LD_*|DYLD_*) return 1 ;;
        *) return 0 ;;
    esac
}

_mainframe_bootstrap_run_clean() {
    local variable
    local -a clean_environment
    # Bash 3.2 treats an empty-array expansion as unset under `set -u`.
    clean_environment=(__mainframe_clean_environment_sentinel__)

    while IFS= read -r variable; do
        _mainframe_bootstrap_environment_key_is_safe "$variable" || continue
        clean_environment=("${clean_environment[@]}" "$variable=${!variable}")
    done < <(builtin compgen -e)

    /usr/bin/env -i "${clean_environment[@]:1}" LC_ALL=C "$@"
}

_mainframe_bootstrap_scrub_current_environment() {
    local function_name variable

    builtin unalias -a 2>/dev/null || true
    builtin unset -v \
        BASH_ENV BASH_LOADABLES_PATH BASH_XTRACEFD CDPATH ENV GLOBIGNORE \
        NODE_OPTIONS NODE_PATH NODE_REDIRECT_WARNINGS NODE_REPL_HISTORY \
        NODE_V8_COVERAGE PERL5LIB PERL5OPT PERLLIB \
        PYTHONBREAKPOINT PYTHONHOME PYTHONINSPECT PYTHONPATH PYTHONSTARTUP \
        PYTHONUSERBASE PYTHONWARNINGS RUBYOPT RUBYLIB 2>/dev/null || true
    while IFS= read -r variable; do
        case "$variable" in
            LD_*|DYLD_*) builtin unset -v "$variable" 2>/dev/null || return 1 ;;
        esac
    done < <(builtin compgen -e)
    while IFS= read -r function_name; do
        case "$function_name" in
            _mainframe_bootstrap_environment_key_is_safe|\
            _mainframe_bootstrap_run_clean|\
            _mainframe_bootstrap_scrub_current_environment)
                # shellcheck disable=SC2163 # Function name is intentionally indirect.
                builtin export -n -f "$function_name" 2>/dev/null || return 1
                ;;
            *) builtin unset -f "$function_name" 2>/dev/null || return 1 ;;
        esac
    done < <(builtin compgen -A function)
}

[[ -x /usr/bin/env ]] || {
    printf 'Error: the fixed /usr/bin/env executable is required for trusted bootstrap delegation.\n' >&2
    exit 1
}
_mainframe_bootstrap_scrub_current_environment || {
    printf 'Error: bootstrap could not clear inherited code-loader environment.\n' >&2
    exit 1
}

# Never resolve bootstrap dependencies through the caller's working-directory
# or package-manager PATH. System tools use this fixed path; dependencies that
# are commonly outside it (currently jq and Bash) are bound separately below.
MAINFRAME_BOOTSTRAP_SYSTEM_PATH=/usr/bin:/bin:/usr/sbin:/sbin
PATH="$MAINFRAME_BOOTSTRAP_SYSTEM_PATH"
export PATH
builtin hash -r

MAINFRAME_CANONICAL_REPO="https://github.com/gtwatts/mainframe.git"
MAINFRAME_CANONICAL_BRANCH="main"
MAINFRAME_CANONICAL_INSTALLER_URL="https://raw.githubusercontent.com/gtwatts/mainframe/main/install.sh"
MAINFRAME_INHERITED_REPO="${MAINFRAME_REPO:-}"
MAINFRAME_INHERITED_BRANCH="${MAINFRAME_BRANCH:-}"
MAINFRAME_INHERITED_INSTALLER_URL="${MAINFRAME_INSTALLER_URL:-}"
MAINFRAME_REPO="$MAINFRAME_CANONICAL_REPO"
MAINFRAME_BRANCH="$MAINFRAME_CANONICAL_BRANCH"
MAINFRAME_INSTALLER_URL="$MAINFRAME_CANONICAL_INSTALLER_URL"
MAINFRAME_INSTALL_DIR="${MAINFRAME_INSTALL_DIR:-${MAINFRAME_DIR:-$HOME/.mainframe}}"
MAINFRAME_BIN_DIR="${MAINFRAME_BIN_DIR:-$HOME/.local/bin}"
MAINFRAME_RELEASE_BASE_URL="${MAINFRAME_RELEASE_BASE_URL:-https://github.com/gtwatts/mainframe/releases/download}"
MAINFRAME_LATEST_RELEASE_API_URL="${MAINFRAME_LATEST_RELEASE_API_URL:-https://api.github.com/repos/gtwatts/mainframe/releases/latest}"
MAINFRAME_CANONICAL_RELEASE_BASE_URL="https://github.com/gtwatts/mainframe/releases/download"
MAINFRAME_CANONICAL_LATEST_RELEASE_API_URL="https://api.github.com/repos/gtwatts/mainframe/releases/latest"
MAINFRAME_GITHUB_API_VERSION="2026-03-10"
RECEIPT_NAME=".mainframe-install-receipt.json"

release_version="${MAINFRAME_VERSION:-}"
latest_requested=false
legacy_source_requested=false
latest_archive_api_digest=""
latest_checksum_api_digest=""
# Bash 3.2 treats an empty array expansion as unset under `set -u`. Keep an
# internal sentinel and slice it off when delegating to install.sh.
installer_args=(__mainframe_bootstrap_sentinel__)
bootstrap_internal_fixture_capability=false
bootstrap_repo_explicit=false
bootstrap_branch_explicit=false
bootstrap_unverified_source_allowed=false
bootstrap_legacy_installer_url_explicit=false

show_bootstrap_help() {
    cat <<'EOF'
MAINFRAME verified bootstrap installer

Usage:
  get-mainframe.sh [INSTALL_OPTIONS]
  get-mainframe.sh --latest [INSTALL_OPTIONS]
  get-mainframe.sh --release-version X.Y.Z [INSTALL_OPTIONS]
  get-mainframe.sh --legacy-source [LEGACY_OPTIONS] [INSTALL_OPTIONS]

Release selection:
  (no selector)          Resolve the latest published immutable stable release
  --latest               Explicit form of the same immutable-latest flow
  --release-version VER  Install one exact stable release version
  --legacy-source        Explicitly use the mutable source installer (unverified)

Bootstrap options:
  -h, --help             Show this local help without downloading anything
  --repo URL             Legacy source repository (requires --legacy-source)
  --branch REF           Legacy source branch (requires --legacy-source)
  --legacy-installer-url URL
                         Legacy installer URL (requires --legacy-source)
  --allow-unverified-source
                         Permit explicitly selected noncanonical legacy sources

Common install options forwarded after release selection include --no-shell
and --no-ai-discovery. MAINFRAME_INSTALL_DIR and MAINFRAME_BIN_DIR select the
target locations. The legacy source path is retained only for compatibility;
prefer the default immutable-latest flow or an inspected pinned release.
EOF
}

set_release_version() {
    local requested="$1"

    if [[ "$latest_requested" == "true" ]]; then
        printf 'Error: --latest conflicts with --release-version. Choose one release selector.\n' >&2
        return 1
    fi
    if [[ -n "$release_version" && "$release_version" != "$requested" ]]; then
        printf 'Error: MAINFRAME_VERSION (%s) conflicts with --release-version (%s).\n' \
            "$release_version" "$requested" >&2
        return 1
    fi
    release_version="$requested"
}

while (($# > 0)); do
    case "$1" in
        -h|--help)
            show_bootstrap_help
            exit 0
            ;;
        --latest)
            if [[ "$latest_requested" == "true" ]]; then
                printf 'Error: --latest may be specified only once.\n' >&2
                exit 2
            fi
            if [[ -n "$release_version" ]]; then
                printf 'Error: --latest conflicts with MAINFRAME_VERSION or --release-version. Choose one release selector.\n' >&2
                exit 2
            fi
            latest_requested=true
            shift
            ;;
        --latest=*)
            printf 'Error: --latest does not accept a value.\n' >&2
            exit 2
            ;;
        --release-version)
            if (($# < 2)) || [[ -z "$2" ]]; then
                printf 'Error: --release-version requires a value such as 10.1.0.\n' >&2
                exit 2
            fi
            set_release_version "$2" || exit 2
            shift 2
            ;;
        --release-version=*)
            requested_version="${1#*=}"
            if [[ -z "$requested_version" ]]; then
                printf 'Error: --release-version requires a value such as 10.1.0.\n' >&2
                exit 2
            fi
            set_release_version "$requested_version" || exit 2
            shift
            ;;
        --legacy-source)
            if [[ "$legacy_source_requested" == "true" ]]; then
                printf 'Error: --legacy-source may be specified only once.\n' >&2
                exit 2
            fi
            legacy_source_requested=true
            shift
            ;;
        --legacy-source=*)
            printf 'Error: --legacy-source does not accept a value.\n' >&2
            exit 2
            ;;
        --repo)
            if (($# < 2)) || [[ -z "$2" ]]; then
                printf 'Error: --repo requires a URL.\n' >&2
                exit 2
            fi
            if [[ "$bootstrap_repo_explicit" == "true" ]]; then
                printf 'Error: --repo may be specified only once.\n' >&2
                exit 2
            fi
            MAINFRAME_REPO="$2"
            bootstrap_repo_explicit=true
            installer_args=("${installer_args[@]}" --repo "$2")
            shift 2
            ;;
        --repo=*)
            printf 'Error: --repo requires a separate URL argument.\n' >&2
            exit 2
            ;;
        --branch)
            if (($# < 2)) || [[ -z "$2" ]]; then
                printf 'Error: --branch requires a ref.\n' >&2
                exit 2
            fi
            if [[ "$bootstrap_branch_explicit" == "true" ]]; then
                printf 'Error: --branch may be specified only once.\n' >&2
                exit 2
            fi
            MAINFRAME_BRANCH="$2"
            bootstrap_branch_explicit=true
            installer_args=("${installer_args[@]}" --branch "$2")
            shift 2
            ;;
        --branch=*)
            printf 'Error: --branch requires a separate ref argument.\n' >&2
            exit 2
            ;;
        --allow-unverified-source)
            if [[ "$bootstrap_unverified_source_allowed" == "true" ]]; then
                printf 'Error: --allow-unverified-source may be specified only once.\n' >&2
                exit 2
            fi
            bootstrap_unverified_source_allowed=true
            shift
            ;;
        --legacy-installer-url)
            if (($# < 2)) || [[ -z "$2" ]]; then
                printf 'Error: --legacy-installer-url requires a URL.\n' >&2
                exit 2
            fi
            if [[ "$bootstrap_legacy_installer_url_explicit" == "true" ]]; then
                printf 'Error: --legacy-installer-url may be specified only once.\n' >&2
                exit 2
            fi
            MAINFRAME_INSTALLER_URL="$2"
            bootstrap_legacy_installer_url_explicit=true
            shift 2
            ;;
        --legacy-installer-url=*)
            printf 'Error: --legacy-installer-url requires a separate URL argument.\n' >&2
            exit 2
            ;;
        --internal-test-fixture)
            if [[ "$bootstrap_internal_fixture_capability" == "true" ]]; then
                printf 'Error: --internal-test-fixture may be specified only once.\n' >&2
                exit 2
            fi
            bootstrap_internal_fixture_capability=true
            shift
            ;;
        *)
            installer_args=("${installer_args[@]}" "$1")
            shift
            ;;
    esac
done

if [[ "$legacy_source_requested" == "true" &&
      ( "$latest_requested" == "true" || -n "$release_version" ) ]]; then
    printf 'Error: --legacy-source conflicts with --latest, MAINFRAME_VERSION, and --release-version. Choose one release selector.\n' >&2
    exit 2
fi

if [[ "$legacy_source_requested" != "true" &&
      ( "$bootstrap_repo_explicit" == "true" ||
        "$bootstrap_branch_explicit" == "true" ||
        "$bootstrap_unverified_source_allowed" == "true" ||
        "$bootstrap_legacy_installer_url_explicit" == "true" ) ]]; then
    printf 'Error: --repo, --branch, --legacy-installer-url, and --allow-unverified-source require --legacy-source.\n' >&2
    exit 2
fi

# A selector-free invocation is the shortest safe install path. It is exactly
# the immutable --latest flow and therefore cannot fall back to mutable source
# installation when metadata or release assets are unavailable.
if [[ "$legacy_source_requested" != "true" &&
      "$latest_requested" != "true" && -z "$release_version" ]]; then
    latest_requested=true
fi

is_stable_semver() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

if [[ -n "$release_version" ]] && ! is_stable_semver "$release_version"; then
    printf 'Error: release version must be stable SemVer (MAJOR.MINOR.PATCH): %s\n' \
        "$release_version" >&2
    exit 2
fi

is_supported_bash() {
    local candidate="$1"
    [[ -x "$candidate" ]] || return 1
    _mainframe_bootstrap_run_clean \
        "$candidate" --noprofile --norc -p -c '
        ((BASH_VERSINFO[0] > 4)) ||
        ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))
    ' >/dev/null 2>&1
}

resolve_absolute_executable() {
    local source="$1" dir target links=0
    [[ "$source" == /* ]] || return 1
    [[ "$source" != *$'\n'* && "$source" != *$'\r'* &&
       "$source" != *$'\t'* ]] || return 1
    while [[ -L "$source" ]]; do
        (( links < 40 )) || return 1
        links=$((links + 1))
        dir="${source%/*}"
        [[ -n "$dir" ]] || dir=/
        dir="$(builtin cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
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
    dir="$(builtin cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
    source="$dir/${source##*/}"
    [[ -f "$source" && ! -L "$source" && -x "$source" ]] || return 1
    printf '%s\n' "$source"
}

portable_owner_mode() {
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

path_is_within() {
    local path="$1" root="$2"
    [[ -n "$root" && "$root" == /* ]] || return 1
    case "$path" in
        "$root"|"$root"/*) return 0 ;;
        *) return 1 ;;
    esac
}

known_bash_layout() {
    local candidate="$1" prefix remainder version
    case "$candidate" in
        /bin/bash|/usr/bin/bash|/usr/local/bin/bash|/opt/local/bin/bash|\
        /nix/store/*/bin/bash) return 0 ;;
    esac
    for prefix in \
        /opt/homebrew/Cellar/bash/ \
        /usr/local/Cellar/bash/ \
        /home/linuxbrew/.linuxbrew/Cellar/bash/; do
        case "$candidate" in
            "$prefix"*)
                remainder="${candidate#"$prefix"}"
                version="${remainder%%/*}"
                [[ -n "$version" && "$remainder" == "$version/bin/bash" ]] && return 0
                ;;
        esac
    done
    return 1
}

path_has_no_write_acl() {
    local path="$1" line listing permissions
    case "${OSTYPE:-}" in
        darwin*) ;;
        *) return 0 ;;
    esac
    [[ -x /bin/ls ]] || return 1
    listing="$(LC_ALL=C /bin/ls -lde "$path" 2>/dev/null)" || return 1
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
    done <<< "$listing"
}

executable_file_policy_is_safe() {
    local candidate="$1" owner mode numeric
    read -r owner mode < <(portable_owner_mode "$candidate") || return 1
    [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 &&
       (numeric & 0100) != 0 )) || return 1
    path_has_no_write_acl "$candidate" || return 1
    return 0
}

strict_bash_ancestry_is_safe() {
    local candidate="$1" directory current component owner mode numeric
    local old_ifs="$IFS"
    local -a components
    components=()
    directory="${candidate%/*}"
    [[ -n "$directory" ]] || directory=/
    IFS=/ read -r -a components <<< "${directory#/}"
    IFS="$old_ifs"
    current=""
    read -r owner mode < <(portable_owner_mode /) || return 1
    [[ "$owner" -eq 0 ]] || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
        current="$current/$component"
        [[ -d "$current" && ! -L "$current" ]] || return 1
        path_has_no_write_acl "$current" || return 1
        read -r owner mode < <(portable_owner_mode "$current") || return 1
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
        numeric=$((8#$mode))
        (( (numeric & 0022) == 0 && (numeric & 07000) == 0 )) || return 1
    done
}

bootstrap_origin_directory() {
    local source="${BASH_SOURCE[0]:-}" directory
    [[ -n "$source" ]] || return 1
    [[ "$source" == /* ]] || source="$PWD/$source"
    directory="${source%/*}"
    [[ -n "$directory" ]] || directory=/
    builtin cd -- "$directory" 2>/dev/null && pwd -P
}

canonical_requested_install_root() {
    local requested="${MAINFRAME_INSTALL_DIR:-}" parent name
    [[ -n "$requested" ]] || return 1
    [[ "$requested" == /* ]] || requested="$PWD/$requested"
    [[ "$requested" != *$'\n'* && "$requested" != *$'\r'* &&
       "$requested" != *$'\t'* ]] || return 1
    requested="${requested%/}"
    [[ -n "$requested" ]] || requested=/
    if [[ -d "$requested" ]]; then
        builtin cd -- "$requested" 2>/dev/null && pwd -P
        return
    fi
    parent="${requested%/*}"
    name="${requested##*/}"
    [[ -n "$parent" ]] || parent=/
    [[ -n "$name" && -d "$parent" ]] || {
        printf '%s\n' "$requested"
        return 0
    }
    parent="$(builtin cd -- "$parent" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "${parent%/}" "$name"
}

bash_override_location_is_safe() {
    local candidate="$1" origin="" temp_root="" temp_physical=""
    local install_root=""
    origin="$(bootstrap_origin_directory 2>/dev/null || true)"
    if [[ -n "$origin" ]] && path_is_within "$candidate" "$origin"; then
        return 1
    fi
    for temp_root in /tmp /private/tmp /var/tmp "${TMPDIR:-}"; do
        [[ -n "$temp_root" ]] || continue
        if [[ "$temp_root" != /* ]]; then
            continue
        fi
        temp_root="${temp_root%/}"
        if path_is_within "$candidate" "$temp_root"; then
            return 1
        fi
        if [[ -d "$temp_root" ]]; then
            temp_physical="$(builtin cd -- "$temp_root" 2>/dev/null && pwd -P)" || return 1
        else
            temp_physical=""
        fi
        if [[ -n "$temp_physical" ]] && \
           path_is_within "$candidate" "$temp_physical"; then
            return 1
        fi
    done
    install_root="$(canonical_requested_install_root 2>/dev/null || true)"
    if [[ -n "$install_root" ]] && path_is_within "$candidate" "$install_root"; then
        return 1
    fi
    known_bash_layout "$candidate" || strict_bash_ancestry_is_safe "$candidate"
}

select_bash_candidate() {
    local requested="$1" resolved
    resolved="$(resolve_absolute_executable "$requested" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || return 1
    executable_file_policy_is_safe "$resolved" || return 1
    # An environment override is selection, not authorization. Persisting an
    # arbitrary user-controlled Bash would make the installed CLI either
    # execute project-shaped code or reject the same path at first launch.
    # Fixed and explicit candidates therefore share one reviewed layout set.
    known_bash_layout "$resolved" || return 1
    is_supported_bash "$resolved" || return 1
    printf '%s\n' "$resolved"
}

known_jq_layout() {
    local candidate="$1" prefix remainder version
    case "$candidate" in
        /bin/jq|/usr/bin/jq|/usr/local/bin/jq|/opt/local/bin/jq|\
        /nix/store/*/bin/jq) return 0 ;;
    esac
    for prefix in \
        /opt/homebrew/Cellar/jq/ \
        /usr/local/Cellar/jq/ \
        /home/linuxbrew/.linuxbrew/Cellar/jq/; do
        case "$candidate" in
            "$prefix"*)
                remainder="${candidate#"$prefix"}"
                version="${remainder%%/*}"
                [[ -n "$version" && "$remainder" == "$version/bin/jq" ]] && return 0
                ;;
        esac
    done
    return 1
}

find_trusted_jq() {
    local candidate resolved
    for candidate in \
        /usr/bin/jq \
        /bin/jq \
        /opt/homebrew/bin/jq \
        /usr/local/bin/jq \
        /home/linuxbrew/.linuxbrew/bin/jq \
        /opt/local/bin/jq; do
        resolved="$(resolve_absolute_executable "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || continue
        known_jq_layout "$resolved" || continue
        executable_file_policy_is_safe "$resolved" || continue
        if _mainframe_bootstrap_run_clean "$resolved" --version >/dev/null 2>&1; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done
    return 1
}

# Bind jq without adding its package-manager directory to PATH.
jq() {
    "${bootstrap_jq:?trusted jq is not bound}" "$@"
}

bootstrap_internal_dependency_test_authorized() {
    local marker marker_value install_root owner mode
    [[ "${bootstrap_internal_fixture_capability:-false}" == "true" ]] || return 1
    [[ "${MAINFRAME_INTERNAL_TESTING:-}" == "1" ]] || return 1
    [[ -n "${HOME:-}" && -d "$HOME" ]] || return 1
    install_root="$(canonical_requested_install_root 2>/dev/null || true)"
    [[ -n "$install_root" ]] || return 1
    marker="$HOME/.mainframe-bootstrap-internal-test-mode"
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    read -r owner mode < <(portable_owner_mode "$marker") || return 1
    [[ "$owner" -eq "$EUID" && "$mode" == "600" ]] || return 1
    path_has_no_write_acl "$marker" || return 1
    marker_value="$(< "$marker")"
    [[ "$marker_value" == "MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:$install_root" ]]
}

validate_bootstrap_dependency_test_controls() {
    local override resolved
    case "${MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ:-}" in
        "") ;;
        1)
            if ! bootstrap_internal_dependency_test_authorized; then
                printf 'Error: bootstrap dependency test controls are disabled outside a private authenticated fixture.\n' >&2
                return 1
            fi
            ;;
        *)
            printf 'Error: unknown MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ value.\n' >&2
            return 1
            ;;
    esac
    _MAINFRAME_BOOTSTRAP_TEST_MV=""
    override="${MAINFRAME_BOOTSTRAP_INTERNAL_MV:-}"
    if [[ -n "$override" ]]; then
        if ! bootstrap_internal_dependency_test_authorized; then
            printf 'Error: bootstrap tool overrides are disabled outside a private authenticated fixture.\n' >&2
            return 1
        fi
        [[ "$override" == /* ]] || {
            printf 'Error: internal bootstrap mv override must be absolute.\n' >&2
            return 1
        }
        resolved="$(resolve_absolute_executable "$override" 2>/dev/null || true)"
        if [[ -z "$resolved" || "$resolved" != "$override" ]] ||
           ! executable_file_policy_is_safe "$resolved"; then
            printf 'Error: internal bootstrap mv override is not an exact safe executable.\n' >&2
            return 1
        fi
        _MAINFRAME_BOOTSTRAP_TEST_MV="$resolved"
    fi

    _MAINFRAME_BOOTSTRAP_TEST_CURL=""
    override="${MAINFRAME_BOOTSTRAP_INTERNAL_CURL:-}"
    if [[ -n "$override" ]]; then
        if ! bootstrap_internal_dependency_test_authorized; then
            printf 'Error: bootstrap tool overrides are disabled outside a private authenticated fixture.\n' >&2
            return 1
        fi
        [[ "$override" == /* ]] || {
            printf 'Error: internal bootstrap curl override must be absolute.\n' >&2
            return 1
        }
        resolved="$(resolve_absolute_executable "$override" 2>/dev/null || true)"
        if [[ -z "$resolved" || "$resolved" != "$override" ]] ||
           ! executable_file_policy_is_safe "$resolved"; then
            printf 'Error: internal bootstrap curl override is not an exact safe executable.\n' >&2
            return 1
        fi
        _MAINFRAME_BOOTSTRAP_TEST_CURL="$resolved"
    fi
}

find_supported_bash() {
    local candidate resolved

    if [[ -n "${MAINFRAME_BASH:-}" ]]; then
        if [[ "$MAINFRAME_BASH" != /* ]]; then
            printf 'Error: MAINFRAME_BASH must be an absolute path; PATH names and relative paths are never executed.\n' >&2
            return 1
        fi
        resolved="$(select_bash_candidate "$MAINFRAME_BASH" explicit || true)"
        if [[ -n "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
        printf 'Error: MAINFRAME_BASH must name a trusted absolute Bash 4.4+ executable: %s\n' \
            "$MAINFRAME_BASH" >&2
        return 1
    fi

    # Homebrew does not replace /bin/bash on macOS. Only fixed system and
    # package-manager entrypoints are considered; project and PATH wrappers
    # are never probed as interpreters.
    for candidate in \
        /opt/homebrew/bin/bash \
        /usr/local/bin/bash \
        /home/linuxbrew/.linuxbrew/bin/bash \
        /opt/local/bin/bash \
        /usr/bin/bash \
        /bin/bash
    do
        resolved="$(select_bash_candidate "$candidate" fixed || true)"
        if [[ -n "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done
    return 1
}

sha256_digest() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        printf 'Error: SHA-256 verification requires sha256sum, shasum, or openssl.\n' >&2
        return 1
    fi
}

validate_checksum_record() {
    local checksum_file="$1"
    local expected_name="$2"
    local line line_count digest

    line_count="$(awk 'END { print NR + 0 }' "$checksum_file")" || return 1
    if [[ "$line_count" != "1" ]]; then
        printf 'Error: release checksum must contain exactly one record.\n' >&2
        return 1
    fi

    IFS= read -r line < "$checksum_file" || [[ -n "$line" ]]
    digest="${line%% *}"
    if [[ "${#digest}" -ne 64 ]]; then
        printf 'Error: release checksum is not a lowercase SHA-256 record.\n' >&2
        return 1
    fi
    case "$digest" in
        *[!0-9a-f]*)
            printf 'Error: release checksum is not a lowercase SHA-256 record.\n' >&2
            return 1
            ;;
    esac
    if [[ "$line" != "$digest  $expected_name" ]]; then
        printf 'Error: release checksum does not name the exact asset: %s\n' \
            "$expected_name" >&2
        return 1
    fi

    printf '%s\n' "$digest"
}

bootstrap_curl_download() {
    # Downloads never inherit proxy routing, alternate CA bundles, TLS knobs,
    # curl config locations, credential helpers, or caller shell functions.
    # --disable is deliberately first and the direct/no-proxy policy is
    # explicit even though the process starts from an empty environment.
    /usr/bin/env -i \
        HOME=/ \
        PATH="$MAINFRAME_BOOTSTRAP_SYSTEM_PATH" \
        LC_ALL=C \
        LANG=C \
        "$bootstrap_curl" --disable --proxy '' --noproxy '*' "$@"
}

download_release_file() {
    local url="$1" destination="$2"
    case "$url" in
        https://*)
            bootstrap_curl_download -fsSL --proto '=https' --proto-redir '=https' \
                --tlsv1.2 "$url" -o "$destination"
            ;;
        file://*)
            if ! bootstrap_internal_dependency_test_authorized; then
                printf 'Error: file:// release assets are disabled outside internal verification.\n' >&2
                return 1
            fi
            bootstrap_curl_download -fsSL --proto '=file' "$url" -o "$destination"
            ;;
        *)
            printf 'Error: release assets must use HTTPS (file:// is reserved for local verification).\n' >&2
            return 1
            ;;
    esac
}

validate_release_base_url() {
    local requested="${MAINFRAME_RELEASE_BASE_URL%/}"

    if [[ "$requested" == "$MAINFRAME_CANONICAL_RELEASE_BASE_URL" ]]; then
        return 0
    fi
    if bootstrap_internal_dependency_test_authorized; then
        case "$requested" in
            file://*) return 0 ;;
        esac
    fi
    case "$requested" in
        file://*)
            printf 'Error: file:// release assets are disabled outside internal verification.\n' >&2
            ;;
        *)
            printf 'Error: custom MAINFRAME_RELEASE_BASE_URL is disabled outside internal verification.\n' >&2
            printf 'Production bootstrap must use %s.\n' \
                "$MAINFRAME_CANONICAL_RELEASE_BASE_URL" >&2
            ;;
    esac
    return 1
}

validate_latest_release_api_url() {
    local requested="$MAINFRAME_LATEST_RELEASE_API_URL"

    if [[ "$requested" == "$MAINFRAME_CANONICAL_LATEST_RELEASE_API_URL" ]]; then
        return 0
    fi
    if bootstrap_internal_dependency_test_authorized; then
        case "$requested" in
            file://*) return 0 ;;
        esac
    fi
    case "$requested" in
        file://*)
            printf 'Error: file:// latest-release metadata is disabled outside internal verification.\n' >&2
            ;;
        *)
            printf 'Error: custom MAINFRAME_LATEST_RELEASE_API_URL is disabled.\n' >&2
            printf 'Production bootstrap must use %s.\n' \
                "$MAINFRAME_CANONICAL_LATEST_RELEASE_API_URL" >&2
            ;;
    esac
    return 1
}

download_latest_release_metadata() {
    local destination="$1"

    validate_latest_release_api_url || return 1
    case "$MAINFRAME_LATEST_RELEASE_API_URL" in
        https://*)
            bootstrap_curl_download -fsSL --proto '=https' --proto-redir '=https' \
                --tlsv1.2 \
                -H 'Accept: application/vnd.github+json' \
                -H "X-GitHub-Api-Version: $MAINFRAME_GITHUB_API_VERSION" \
                "$MAINFRAME_LATEST_RELEASE_API_URL" -o "$destination"
            ;;
        file://*)
            bootstrap_curl_download -fsSL --proto '=file' \
                "$MAINFRAME_LATEST_RELEASE_API_URL" -o "$destination"
            ;;
        *)
            printf 'Error: latest-release metadata must use the canonical HTTPS API.\n' >&2
            return 1
            ;;
    esac
}

validate_legacy_bootstrap_provenance() {
    local source_noncanonical=false installer_noncanonical=false

    if [[ ( -n "$MAINFRAME_INHERITED_REPO" &&
            "$MAINFRAME_INHERITED_REPO" != "$MAINFRAME_CANONICAL_REPO" ) ||
          ( -n "$MAINFRAME_INHERITED_BRANCH" &&
            "$MAINFRAME_INHERITED_BRANCH" != "$MAINFRAME_CANONICAL_BRANCH" ) ||
          ( -n "$MAINFRAME_INHERITED_INSTALLER_URL" &&
            "$MAINFRAME_INHERITED_INSTALLER_URL" != "$MAINFRAME_CANONICAL_INSTALLER_URL" ) ]]; then
        printf 'Error: inherited MAINFRAME_INSTALLER_URL, MAINFRAME_REPO, or MAINFRAME_BRANCH cannot select legacy bootstrap provenance.\n' >&2
        printf 'Unset it and use same-command --legacy-installer-url URL --repo URL --branch REF --allow-unverified-source consent as applicable.\n' >&2
        return 1
    fi

    [[ -n "$MAINFRAME_REPO" && -n "$MAINFRAME_BRANCH" &&
       -n "$MAINFRAME_INSTALLER_URL" ]] || {
        printf 'Error: legacy bootstrap provenance values must not be empty.\n' >&2
        return 1
    }
    if [[ "$MAINFRAME_REPO" == -* || "$MAINFRAME_INSTALLER_URL" == -* ||
          "$MAINFRAME_REPO" == *$'\n'* || "$MAINFRAME_REPO" == *$'\r'* ||
          "$MAINFRAME_REPO" == *$'\t'* || "$MAINFRAME_BRANCH" == *$'\n'* ||
          "$MAINFRAME_BRANCH" == *$'\r'* || "$MAINFRAME_BRANCH" == *$'\t'* ||
          "$MAINFRAME_INSTALLER_URL" == *$'\n'* ||
          "$MAINFRAME_INSTALLER_URL" == *$'\r'* ||
          "$MAINFRAME_INSTALLER_URL" == *$'\t'* ]]; then
        printf 'Error: legacy bootstrap provenance contains an unsafe value.\n' >&2
        return 1
    fi

    if [[ "$MAINFRAME_REPO" != "$MAINFRAME_CANONICAL_REPO" ||
          "$MAINFRAME_BRANCH" != "$MAINFRAME_CANONICAL_BRANCH" ]]; then
        source_noncanonical=true
    fi
    if [[ "$MAINFRAME_INSTALLER_URL" != "$MAINFRAME_CANONICAL_INSTALLER_URL" ]]; then
        installer_noncanonical=true
    fi

    if [[ "$source_noncanonical" == "true" ]]; then
        if [[ "$bootstrap_repo_explicit" != "true" ||
              "$bootstrap_branch_explicit" != "true" ||
              "$bootstrap_unverified_source_allowed" != "true" ]]; then
            printf 'Error: a noncanonical legacy source requires --repo URL --branch REF --allow-unverified-source on the same command.\n' >&2
            return 1
        fi
        case "$MAINFRAME_REPO" in
            file://*|file:*|/*)
                if ! bootstrap_internal_dependency_test_authorized; then
                    printf 'Error: local legacy repositories are disabled outside an explicit authenticated internal-test fixture.\n' >&2
                    return 1
                fi
                ;;
        esac
        installer_args=("${installer_args[@]}" --allow-unverified-source)
    fi

    if [[ "$installer_noncanonical" == "true" ]]; then
        if [[ "$bootstrap_legacy_installer_url_explicit" != "true" ||
              "$bootstrap_repo_explicit" != "true" ||
              "$bootstrap_branch_explicit" != "true" ||
              "$bootstrap_unverified_source_allowed" != "true" ]]; then
            printf 'Error: a custom legacy installer requires --legacy-installer-url URL --repo URL --branch REF --allow-unverified-source on the same command.\n' >&2
            return 1
        fi
        case "$MAINFRAME_INSTALLER_URL" in
            https://*) ;;
            file://*)
                if ! bootstrap_internal_dependency_test_authorized; then
                    printf 'Error: file:// legacy installers are disabled outside an explicit authenticated internal-test fixture.\n' >&2
                    return 1
                fi
                ;;
            *)
                printf 'Error: legacy installers must use HTTPS (file:// is reserved for internal verification).\n' >&2
                return 1
                ;;
        esac
    elif [[ "$bootstrap_unverified_source_allowed" == "true" &&
            "$source_noncanonical" != "true" ]]; then
        printf 'Error: --allow-unverified-source requires explicit noncanonical legacy provenance.\n' >&2
        return 1
    fi
}

download_legacy_installer() {
    local destination="$1"
    case "$MAINFRAME_INSTALLER_URL" in
        https://*)
            bootstrap_curl_download -fsSL --proto '=https' --proto-redir '=https' \
                --tlsv1.2 "$MAINFRAME_INSTALLER_URL" -o "$destination"
            ;;
        file://*)
            bootstrap_internal_dependency_test_authorized || return 1
            bootstrap_curl_download -fsSL --proto '=file' \
                "$MAINFRAME_INSTALLER_URL" -o "$destination"
            ;;
        *) return 1 ;;
    esac
}

resolve_latest_release() {
    local metadata_file="$1"
    local tag asset_name checksum_name release_url archive_url checksum_url
    local asset_contract

    printf 'Resolving GitHub latest release metadata...\n'
    if ! download_latest_release_metadata "$metadata_file"; then
        printf 'Error: latest immutable release metadata could not be downloaded.\n' >&2
        printf 'Use an inspected pinned bootstrap with --release-version X.Y.Z instead.\n' >&2
        return 1
    fi
    chmod 600 "$metadata_file" || return 1

    tag="$(jq -er '
        if type == "object" and
           .draft == false and
           .prerelease == false and
           .immutable == true and
           (.tag_name | type == "string")
        then .tag_name
        else error("release is not a published immutable stable release")
        end
    ' "$metadata_file" 2>/dev/null)" || {
        printf 'Error: GitHub latest release is not published, stable, and immutable.\n' >&2
        return 1
    }
    case "$tag" in
        v*) release_version="${tag#v}" ;;
        *) release_version="" ;;
    esac
    if [[ -z "$release_version" ]] || ! is_stable_semver "$release_version" || \
       [[ "$tag" != "v$release_version" ]]; then
        printf 'Error: GitHub latest immutable release tag is not stable vMAJOR.MINOR.PATCH.\n' >&2
        return 1
    fi

    asset_name="mainframe-${release_version}.tar.gz"
    checksum_name="${asset_name}.sha256"
    release_url="${MAINFRAME_RELEASE_BASE_URL%/}/v${release_version}"
    archive_url="$release_url/$asset_name"
    checksum_url="$release_url/$checksum_name"

    asset_contract="$(jq -er \
        --arg archive_name "$asset_name" \
        --arg archive_url "$archive_url" \
        --arg checksum_name "$checksum_name" \
        --arg checksum_url "$checksum_url" '
        if (.assets | type) != "array" then
          error("assets is not an array")
        else
          [.assets[] | select(.name == $archive_name)] as $archives |
          [.assets[] | select(.name == $checksum_name)] as $checksums |
          if ($archives | length) == 1 and
             ($checksums | length) == 1 and
             $archives[0].state == "uploaded" and
             $checksums[0].state == "uploaded" and
             $archives[0].browser_download_url == $archive_url and
             $checksums[0].browser_download_url == $checksum_url and
             ($archives[0].digest | type) == "string" and
             ($checksums[0].digest | type) == "string" and
             ($archives[0].digest | test("^sha256:[0-9a-f]{64}$")) and
             ($checksums[0].digest | test("^sha256:[0-9a-f]{64}$"))
          then "valid"
          else error("release asset contract mismatch")
          end
        end
    ' "$metadata_file" 2>/dev/null)" || {
        printf 'Error: latest release does not contain one exact uploaded archive and checksum asset with canonical URLs and GitHub SHA-256 digests.\n' >&2
        return 1
    }
    if [[ "$asset_contract" != "valid" ]]; then
        printf 'Error: latest release asset metadata validation returned an unexpected result.\n' >&2
        return 1
    fi

    latest_archive_api_digest="$(jq -er --arg name "$asset_name" \
        '.assets[] | select(.name == $name) | .digest' "$metadata_file")" || return 1
    latest_checksum_api_digest="$(jq -er --arg name "$checksum_name" \
        '.assets[] | select(.name == $name) | .digest' "$metadata_file")" || return 1
    latest_archive_api_digest="${latest_archive_api_digest#sha256:}"
    latest_checksum_api_digest="${latest_checksum_api_digest#sha256:}"

    printf 'Resolved latest immutable MAINFRAME release: v%s\n' "$release_version"
    printf 'Resolved GitHub archive SHA-256: %s\n' "$latest_archive_api_digest"
    printf 'If interrupted, retry this exact release with --release-version %s.\n' \
        "$release_version"
}

is_safe_archive_member() {
    local member="$1"

    case "$member" in
        ""|.|..|/*|./*|../*|*/./*|*/.|*/../*|*/..|*//*|-*) return 1 ;;
    esac
    case "$member" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/@+=-]*) return 1 ;;
    esac
    return 0
}

validate_release_archive() {
    local archive="$1"
    local members_file="$2"
    local verbose_file="$3"
    local member listing member_count verbose_count entry_type
    local has_version=0 has_installer=0 has_cli=0 has_manifest=0 has_upgrader=0

    if ! env -u TAR_OPTIONS tar -tzf "$archive" > "$members_file"; then
        printf 'Error: release asset is not a readable gzip-compressed tar archive.\n' >&2
        return 1
    fi
    if ! env -u TAR_OPTIONS tar -tvzf "$archive" > "$verbose_file"; then
        printf 'Error: release archive metadata could not be inspected.\n' >&2
        return 1
    fi

    member_count=0
    while IFS= read -r member || [[ -n "$member" ]]; do
        member_count=$((member_count + 1))
        if ! is_safe_archive_member "$member"; then
            printf 'Error: release archive contains an unsafe member path: %s\n' \
                "$member" >&2
            return 1
        fi
        case "$member" in
            "$RECEIPT_NAME")
                printf 'Error: release archive must not contain a machine-local install receipt.\n' >&2
                return 1
                ;;
            VERSION) has_version=1 ;;
            install.sh) has_installer=1 ;;
            bin/mainframe) has_cli=1 ;;
            SHA256SUMS) has_manifest=1 ;;
            scripts/upgrade-release.sh) has_upgrader=1 ;;
        esac
    done < "$members_file"

    if [[ "$member_count" -eq 0 ]]; then
        printf 'Error: release archive is empty.\n' >&2
        return 1
    fi
    if ! awk '!seen[$0]++ { next } { exit 1 }' "$members_file"; then
        printf 'Error: release archive contains duplicate member paths.\n' >&2
        return 1
    fi

    verbose_count=0
    while IFS= read -r listing || [[ -n "$listing" ]]; do
        verbose_count=$((verbose_count + 1))
        entry_type="${listing%"${listing#?}"}"
        case "$entry_type" in
            -|d) ;;
            *)
                printf 'Error: release archive links and special entries are not allowed.\n' >&2
                return 1
                ;;
        esac
    done < "$verbose_file"
    if [[ "$verbose_count" -ne "$member_count" ]]; then
        printf 'Error: release archive member metadata is ambiguous.\n' >&2
        return 1
    fi

    if [[ "$has_version" -ne 1 || "$has_installer" -ne 1 || "$has_cli" -ne 1 || \
          "$has_manifest" -ne 1 || "$has_upgrader" -ne 1 ]]; then
        printf 'Error: release archive is missing a required runtime, manifest, or upgrade file.\n' >&2
        return 1
    fi
}

payload_manifest_paths=(__mainframe_manifest_sentinel__)

payload_manifest_contains() {
    local wanted="$1" existing
    for existing in "${payload_manifest_paths[@]:1}"; do
        [[ "$existing" == "$wanted" ]] && return 0
    done
    return 1
}

path_has_symlink_ancestor() {
    local root="$1" relative="$2" component index
    local parent="$root"
    local old_ifs="$IFS"
    local components=()

    IFS=/
    read -r -a components <<< "$relative"
    IFS="$old_ifs"
    for ((index = 0; index < ${#components[@]} - 1; index++)); do
        component="${components[$index]}"
        parent="$parent/$component"
        [[ -L "$parent" ]] && return 0
        [[ -d "$parent" ]] || return 1
    done
    return 1
}

validate_payload_manifest() {
    local root="$1" manifest="$1/SHA256SUMS"
    local line expected relative existing actual line_number=0 required path payload_error=0
    local paths_file="${bootstrap_dir:?}/payload-paths"

    payload_manifest_paths=(__mainframe_manifest_sentinel__)
    if [[ ! -f "$manifest" || -L "$manifest" ]]; then
        printf 'Error: extracted release has no regular SHA256SUMS inventory.\n' >&2
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        case "$line" in
            ""|'#'*) continue ;;
        esac
        if [[ ${#line} -lt 67 ]]; then
            printf 'Error: malformed SHA256SUMS record at line %s.\n' "$line_number" >&2
            return 1
        fi
        expected="${line:0:64}"
        relative="${line:66}"
        if [[ ${#expected} -ne 64 || "${line:64:2}" != "  " ]]; then
            printf 'Error: malformed SHA256SUMS record at line %s.\n' "$line_number" >&2
            return 1
        fi
        case "$expected" in
            *[!0-9a-f]*)
                printf 'Error: malformed SHA256SUMS digest at line %s.\n' "$line_number" >&2
                return 1
                ;;
        esac
        if ! is_safe_archive_member "$relative" || [[ "$relative" == "SHA256SUMS" || "$relative" == "$RECEIPT_NAME" ]]; then
            printf 'Error: unsafe SHA256SUMS path at line %s.\n' "$line_number" >&2
            return 1
        fi
        for existing in "${payload_manifest_paths[@]:1}"; do
            if [[ "$existing" == "$relative" ]]; then
                printf 'Error: duplicate SHA256SUMS path at line %s: %s\n' "$line_number" "$relative" >&2
                return 1
            fi
        done
        payload_manifest_paths=("${payload_manifest_paths[@]}" "$relative")
    done < "$manifest"

    if [[ ${#payload_manifest_paths[@]} -le 1 ]]; then
        printf 'Error: SHA256SUMS contains no runtime files.\n' >&2
        return 1
    fi
    for required in VERSION lib/common.sh bin/mainframe install.sh get-mainframe.sh scripts/upgrade-release.sh; do
        if ! payload_manifest_contains "$required"; then
            printf 'Error: SHA256SUMS omits required runtime path: %s\n' "$required" >&2
            return 1
        fi
    done

    for relative in "${payload_manifest_paths[@]:1}"; do
        path="$root/$relative"
        if [[ ! -f "$path" || -L "$path" ]] || path_has_symlink_ancestor "$root" "$relative"; then
            printf 'Error: managed runtime path is missing, linked, or non-regular: %s\n' "$relative" >&2
            return 1
        fi
        expected=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "${line:66}" == "$relative" && "${line:64:2}" == "  " ]] || continue
            expected="${line:0:64}"
            break
        done < "$manifest"
        actual="$(sha256_digest "$path")" || return 1
        if [[ "$actual" != "$expected" ]]; then
            printf 'Error: release payload checksum mismatch: %s\n' "$relative" >&2
            return 1
        fi
    done

    if ! find "$root" -xdev -mindepth 1 -print > "$paths_file"; then
        rm -f -- "$paths_file"
        printf 'Error: could not enumerate the extracted release payload.\n' >&2
        return 1
    fi
    while IFS= read -r path || [[ -n "$path" ]]; do
        relative="${path#"$root/"}"
        if [[ -L "$path" ]]; then
            printf 'Error: extracted release contains a symbolic link: %s\n' "$relative" >&2
            payload_error=1
            break
        elif [[ -d "$path" ]]; then
            continue
        elif [[ -f "$path" ]]; then
            if [[ "$relative" != "SHA256SUMS" && "$relative" != "$RECEIPT_NAME" ]] && \
               ! payload_manifest_contains "$relative"; then
                printf 'Error: release file is absent from SHA256SUMS: %s\n' "$relative" >&2
                payload_error=1
                break
            fi
        else
            printf 'Error: extracted release contains a special file: %s\n' "$relative" >&2
            payload_error=1
            break
        fi
    done < "$paths_file"
    rm -f -- "$paths_file"
    [[ "$payload_error" -eq 0 ]]
}

resolve_bin_directory() {
    local requested="$1" resolved
    if [[ -z "$requested" ]]; then
        printf 'Error: MAINFRAME_BIN_DIR must not be empty.\n' >&2
        return 1
    fi
    [[ "$requested" == /* ]] || requested="$PWD/$requested"
    mkdir -p "$requested" || return 1
    resolved="$(cd "$requested" && pwd -P)" || return 1
    if [[ "$resolved" == "/" ]]; then
        printf 'Error: refusing unsafe MAINFRAME_BIN_DIR: /.\n' >&2
        return 1
    fi
    printf '%s\n' "$resolved"
}

write_release_receipt() {
    local root="$1" version="$2" archive_sha="$3" bin_dir="$4"
    local manifest_sha receipt tmp

    manifest_sha="$(sha256_digest "$root/SHA256SUMS")" || return 1
    receipt="$root/$RECEIPT_NAME"
    tmp="$(mktemp "$root/.mainframe-install-receipt.XXXXXX")" || return 1
    if ! jq -n \
        --arg version "$version" \
        --arg archive_sha256 "$archive_sha" \
        --arg manifest_sha256 "$manifest_sha" \
        --arg install_dir "$root" \
        --arg bin_dir "$bin_dir" \
        --arg cli_link "$bin_dir/mainframe" \
        --arg installed_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{schema_version: 1, install_method: "release-archive", version: $version,
          archive_sha256: $archive_sha256, manifest_sha256: $manifest_sha256,
          install_dir: $install_dir, bin_dir: $bin_dir, cli_link: $cli_link,
          installed_at: $installed_at}' > "$tmp"; then
        rm -f -- "$tmp"
        return 1
    fi
    chmod 600 "$tmp" || { rm -f -- "$tmp"; return 1; }
    mv "$tmp" "$receipt"
}

resolve_install_target_path() {
    local requested="$1"
    local parent name resolved home_root

    if [[ -z "$requested" ]]; then
        printf 'Error: MAINFRAME_INSTALL_DIR must not be empty.\n' >&2
        return 1
    fi
    if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
        printf 'Error: HOME must name an existing directory.\n' >&2
        return 1
    fi
    home_root="$(cd "$HOME" && pwd -P)" || {
        printf 'Error: HOME could not be resolved safely: %s\n' "$HOME" >&2
        return 1
    }
    name="$(basename "$requested")"
    if [[ "$name" == "." || "$name" == ".." || "$name" == "/" ]]; then
        printf 'Error: unsafe MAINFRAME_INSTALL_DIR: %s\n' "$requested" >&2
        return 1
    fi

    parent="$(dirname "$requested")"
    mkdir -p "$parent"
    parent="$(cd "$parent" && pwd -P)"
    resolved="$parent/$name"

    case "$resolved" in
        /|"$home_root"|"$home_root"/)
            printf 'Error: refusing unsafe MAINFRAME_INSTALL_DIR: %s\n' "$resolved" >&2
            return 1
            ;;
    esac
    if [[ -L "$resolved" ]]; then
        printf 'Error: release install target must not be a symlink: %s\n' "$resolved" >&2
        return 1
    fi
    if [[ -e "$resolved" && ! -d "$resolved" ]]; then
        printf 'Error: release install target is not a directory: %s\n' "$resolved" >&2
        return 1
    fi

    printf '%s\n' "$resolved"
}

resolve_empty_install_target() {
    local resolved

    resolved="$(resolve_install_target_path "$1")" || return 1
    if [[ -d "$resolved" ]] && \
       [[ -n "$(find "$resolved" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        printf 'Error: release install will not overwrite a nonempty target: %s\n' \
            "$resolved" >&2
        return 1
    fi

    printf '%s\n' "$resolved"
}

path_identity() {
    local path="$1" value=""
    value="$(stat -c '%d:%i' "$path" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9]+:[0-9]+$ ]]; then printf '%s\n' "$value"; return; fi
    value="$(stat -f '%d:%i' "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+:[0-9]+$ ]] && printf '%s\n' "$value"
}

portable_mode() {
    local path="$1" value=""
    value="$(stat -c '%a' "$path" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-7]{3,4}$ ]]; then printf '%s\n' "$value"; return; fi
    value="$(stat -f '%Lp' "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-7]{3,4}$ ]] && printf '%s\n' "$value"
}

single_line_value() {
    local file="$1" value
    value="$(awk 'NR == 1 { value = $0 } END { if (NR != 1) exit 1; print value }' "$file")" || return 1
    printf '%s\n' "$value"
}

directory_matches_identity() {
    local path="$1" expected="$2"
    [[ -n "$expected" && -d "$path" && ! -L "$path" && \
       "$(path_identity "$path")" == "$expected" ]]
}

link_matches_identity() {
    local path="$1" expected_identity="$2" expected_target="$3"
    [[ -n "$expected_identity" && -L "$path" && \
       "$(path_identity "$path")" == "$expected_identity" && \
       "$(readlink "$path")" == "$expected_target" ]]
}

absolute_path_is_safe() {
    local path="$1"
    [[ "$path" == /* && "$path" != "/" && "$path" != *$'\n'* && \
       "$path" != *$'\r'* && "$path" != *$'\t'* ]]
}

prepare_release_installer_args() {
    local index argument skip_shell=false enable_ai=false
    core_installer_args=(__mainframe_core_installer_sentinel__)

    for ((index = 1; index < ${#installer_args[@]}; index++)); do
        argument="${installer_args[$index]}"
        case "$argument" in
            --no-shell)
                skip_shell=true
                ;;
            --ai-discovery)
                enable_ai=true
                ;;
            --no-ai-discovery|--no-claude)
                core_installer_args=("${core_installer_args[@]}" "$argument")
                ;;
            *)
                printf 'Error: unsupported versioned-bootstrap option: %s\n' "$argument" >&2
                printf 'Use MAINFRAME_INSTALL_DIR and MAINFRAME_BIN_DIR for release locations.\n' >&2
                return 1
                ;;
        esac
    done
    core_installer_args=("${core_installer_args[@]}" --no-shell --no-ai-discovery)
    if [[ "$skip_shell" == "false" || "$enable_ai" == "true" ]]; then
        release_optional_install=true
    fi
}

acquire_install_lock() {
    local install_dir="$1" parent base owner_pid="" owner_tmp cleanup_guard _attempt
    local owner_identity="" lock_identity="" link_status=1
    parent="$(dirname "$install_dir")"
    base="$(basename "$install_dir")"
    install_lock="$parent/.${base}.install.lock"

    cleanup_guard="$install_lock.cleanup"
    for _attempt in 1 2 3; do
        owner_tmp="$(mktemp "$parent/.mainframe-install-owner.XXXXXX")" || return 1
        printf '%s\n' "$$" > "$owner_tmp"
        chmod 600 "$owner_tmp"
        owner_identity="$(path_identity "$owner_tmp")"
        if [[ -z "$owner_identity" ]]; then
            rm -f -- "$owner_tmp"
            printf 'Error: could not identify the prepared install-lock owner record.\n' >&2
            return 1
        fi
        link_status=1
        if ln "$owner_tmp" "$install_lock" 2>/dev/null; then link_status=0; fi
        if [[ "$link_status" -eq 0 ]]; then
            lock_identity="$(path_identity "$install_lock")"
            if [[ -f "$install_lock" && ! -L "$install_lock" && \
                  -n "$lock_identity" && "$lock_identity" == "$owner_identity" ]]; then
                rm -f -- "$owner_tmp"
                install_lock_owned=true
                install_lock_identity="$lock_identity"
                return 0
            fi
            rm -f -- "$owner_tmp"
            printf 'Error: install lock publication did not create the exact regular lock path: %s\n' \
                "$install_lock" >&2
            return 1
        fi
        rm -f -- "$owner_tmp"
        if [[ ! -f "$install_lock" || -L "$install_lock" || \
              "$(portable_mode "$install_lock")" != "600" ]]; then
            printf 'Error: install lock is malformed or unsafe: %s\n' "$install_lock" >&2
            return 1
        fi
        owner_pid="$(single_line_value "$install_lock" 2>/dev/null || true)"
        if [[ ! "$owner_pid" =~ ^[1-9][0-9]*$ ]]; then
            printf 'Error: install lock owner is malformed: %s\n' "$install_lock" >&2
            return 1
        fi
        if kill -0 "$owner_pid" 2>/dev/null; then
            printf 'Error: another versioned install is running (pid %s).\n' "$owner_pid" >&2
            return 1
        fi
        mkdir "$cleanup_guard" 2>/dev/null || {
            printf 'Error: another process is inspecting the stale install lock.\n' >&2
            return 1
        }
        if [[ -f "$install_lock" && ! -L "$install_lock" && \
              "$(single_line_value "$install_lock" 2>/dev/null || true)" == "$owner_pid" ]] && \
           ! kill -0 "$owner_pid" 2>/dev/null; then
            rm -f -- "$install_lock"
        fi
        rmdir "$cleanup_guard" 2>/dev/null || return 1
    done
    printf 'Error: could not acquire the versioned install lock.\n' >&2
    return 1
}

bootstrap_failpoint_is_authorized() {
    local marker marker_value

    [[ "${bootstrap_internal_fixture_capability:-false}" == "true" ]] || return 1
    [[ "${MAINFRAME_INTERNAL_TESTING:-}" == "1" ]] || return 1
    marker="$HOME/.mainframe-bootstrap-internal-test-mode"
    [[ -f "$marker" && ! -L "$marker" && "$(portable_mode "$marker")" == "600" ]] || return 1
    marker_value="$(single_line_value "$marker" 2>/dev/null || true)"
    [[ "$marker_value" == "MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:$resolved_install_dir" ]]
}

validate_bootstrap_failpoint() {
    case "${MAINFRAME_BOOTSTRAP_FAILPOINT:-}" in
        "") return 0 ;;
        kill-after-placement|kill-after-core-installer) ;;
        *)
            printf 'Error: unknown MAINFRAME_BOOTSTRAP_FAILPOINT: %s\n' \
                "$MAINFRAME_BOOTSTRAP_FAILPOINT" >&2
            return 1
            ;;
    esac
    if ! bootstrap_failpoint_is_authorized; then
        printf 'Error: bootstrap failpoints are disabled outside a private internal-test fixture.\n' >&2
        return 1
    fi
}

run_bootstrap_failpoint() {
    local point="$1"
    if [[ "${MAINFRAME_BOOTSTRAP_FAILPOINT:-}" == "$point" ]]; then
        sync
        kill -9 "$$"
    fi
}

publish_bootstrap_journal() {
    local record manifest_sha journal_base published_identity

    manifest_sha="$(sha256_digest "$payload_dir/SHA256SUMS")" || return 1
    if [[ "$manifest_sha" != "$archive_manifest_digest" ]]; then
        printf 'Error: extracted payload manifest is not the one bound to the verified archive.\n' >&2
        return 1
    fi
    journal_manifest_sha="$manifest_sha"
    journal_base="$(basename "$resolved_install_dir")"
    journal_path="$install_parent/.${journal_base}.bootstrap-journal"
    if [[ -e "$journal_path" || -L "$journal_path" ]]; then
        printf 'Error: bootstrap recovery journal already exists: %s\n' "$journal_path" >&2
        return 1
    fi

    journal_stage_dir="$(mktemp -d "$install_parent/.${journal_base}.bootstrap-journal-stage.XXXXXX")" || return 1
    chmod 700 "$journal_stage_dir" || return 1
    journal_identity="$(path_identity "$journal_stage_dir")"
    if [[ -z "$journal_identity" ]]; then
        printf 'Error: could not identify the private bootstrap recovery journal.\n' >&2
        return 1
    fi
    record="$journal_stage_dir/record.json"
    if ! jq -n \
        --argjson owner_pid "$$" \
        --arg release_version "$release_version" \
        --arg archive_sha256 "$actual_digest" \
        --arg manifest_sha256 "$journal_manifest_sha" \
        --arg install_dir "$resolved_install_dir" \
        --arg payload_stage_path "$payload_dir" \
        --arg payload_identity "$stage_identity" \
        --arg bin_dir "$resolved_bin_dir" \
        --arg cli_link "$cli_link" \
        --argjson cli_owned "$cli_owned" \
        --arg cli_identity "$cli_identity" \
        --arg cli_stage_dir "$cli_stage_dir" \
        --arg cli_stage_dir_identity "$cli_stage_dir_identity" \
        --arg cli_stage_link "$cli_stage_link" \
        '{schema_version: 1, owner_pid: $owner_pid,
          release_version: $release_version, archive_sha256: $archive_sha256,
          manifest_sha256: $manifest_sha256, install_dir: $install_dir,
          payload_stage_path: $payload_stage_path, payload_identity: $payload_identity,
          bin_dir: $bin_dir, cli_link: $cli_link, cli_owned: $cli_owned,
          cli_identity: $cli_identity, cli_stage_dir: $cli_stage_dir,
          cli_stage_dir_identity: $cli_stage_dir_identity,
          cli_stage_link: $cli_stage_link}' > "$record"; then
        return 1
    fi
    chmod 600 "$record" || return 1
    journal_record_identity="$(path_identity "$record")"
    if [[ -z "$journal_record_identity" ]]; then
        printf 'Error: could not identify the bootstrap recovery record.\n' >&2
        return 1
    fi
    sync
    if ! mv "$journal_stage_dir" "$journal_path"; then
        printf 'Error: could not publish the bootstrap recovery journal.\n' >&2
        return 1
    fi
    published_identity="$(path_identity "$journal_path")"
    if [[ "$published_identity" != "$journal_identity" ]]; then
        if directory_matches_identity "$journal_path/$(basename "$journal_stage_dir")" "$journal_identity"; then
            journal_stage_dir="$journal_path/$(basename "$journal_stage_dir")"
        fi
        printf 'Error: bootstrap recovery journal path changed during publication.\n' >&2
        return 1
    fi
    journal_stage_dir=""
    journal_cleanup_authorized=true
    sync
}

load_bootstrap_journal() {
    local record values entry entry_name current_manifest current_version
    local jr_owner jr_version jr_archive jr_manifest jr_install jr_payload_stage
    local jr_payload_identity jr_bin jr_cli_link jr_cli_owned jr_cli_identity
    local jr_cli_stage_dir jr_cli_stage_dir_identity jr_cli_stage_link
    local final_payload=false final_cli=false staged_cli=false cli_stage_exact=false

    record="$journal_path/record.json"
    if [[ ! -d "$journal_path" || -L "$journal_path" || \
          "$(portable_mode "$journal_path")" != "700" ]]; then
        printf 'Error: bootstrap recovery journal is malformed or unsafe: %s\n' "$journal_path" >&2
        return 1
    fi
    journal_identity="$(path_identity "$journal_path")"
    if [[ -z "$journal_identity" || ! -f "$record" || -L "$record" || \
          "$(portable_mode "$record")" != "600" ]]; then
        printf 'Error: bootstrap recovery record is missing, linked, or not private.\n' >&2
        return 1
    fi
    journal_record_identity="$(path_identity "$record")"
    [[ -n "$journal_record_identity" ]] || {
        printf 'Error: bootstrap recovery record identity could not be read.\n' >&2
        return 1
    }
    while IFS= read -r entry || [[ -n "$entry" ]]; do
        entry_name="${entry#"$journal_path/"}"
        if [[ "$entry_name" != "record.json" ]]; then
            printf 'Error: bootstrap recovery journal contains an unexpected entry: %s\n' \
                "$entry_name" >&2
            return 1
        fi
    done < <(find "$journal_path" -mindepth 1 -maxdepth 1 -print)

    if ! jq -e '
        type == "object" and
        keys == ["archive_sha256", "bin_dir", "cli_identity", "cli_link",
                 "cli_owned", "cli_stage_dir", "cli_stage_dir_identity",
                 "cli_stage_link", "install_dir", "manifest_sha256", "owner_pid",
                 "payload_identity", "payload_stage_path", "release_version",
                 "schema_version"] and
        .schema_version == 1 and (.owner_pid | type == "number" and floor == . and . > 0) and
        (.cli_owned | type == "boolean") and
        ([.release_version, .archive_sha256, .manifest_sha256, .install_dir,
          .payload_stage_path, .payload_identity, .bin_dir, .cli_link, .cli_identity,
          .cli_stage_dir, .cli_stage_dir_identity, .cli_stage_link] |
         all(type == "string" and (test("[\u0000-\u001f\u007f]") | not)))
    ' "$record" >/dev/null; then
        printf 'Error: bootstrap recovery record has an invalid or noncanonical schema.\n' >&2
        return 1
    fi
    values="$(jq -jr '[
        (.owner_pid | tostring), .release_version, .archive_sha256,
        .manifest_sha256, .install_dir, .payload_stage_path, .payload_identity,
        .bin_dir, .cli_link, (.cli_owned | tostring), .cli_identity,
        .cli_stage_dir, .cli_stage_dir_identity, .cli_stage_link
    ] | join("\u001f")' "$record")" || return 1
    IFS=$'\x1f' read -r jr_owner jr_version jr_archive jr_manifest jr_install \
        jr_payload_stage jr_payload_identity jr_bin jr_cli_link jr_cli_owned \
        jr_cli_identity jr_cli_stage_dir jr_cli_stage_dir_identity jr_cli_stage_link \
        <<< "$values"

    if [[ ! "$jr_owner" =~ ^[1-9][0-9]*$ || "$jr_version" != "$release_version" || \
          "$jr_archive" != "$actual_digest" || "$jr_install" != "$resolved_install_dir" || \
          "$jr_bin" != "$resolved_bin_dir" || "$jr_cli_link" != "$cli_link" || \
          "$jr_manifest" != "$archive_manifest_digest" || \
          ! "$jr_payload_identity" =~ ^[0-9]+:[0-9]+$ || \
          ! "$jr_cli_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
        printf 'Error: bootstrap recovery record does not match this exact release request.\n' >&2
        return 1
    fi
    if ! absolute_path_is_safe "$jr_payload_stage" || \
       [[ "$(dirname "$jr_payload_stage")" != "$install_parent" || \
          "$(basename "$jr_payload_stage")" != .mainframe-release-stage.* ]]; then
        printf 'Error: bootstrap recovery payload staging path is unsafe.\n' >&2
        return 1
    fi

    current_manifest=""
    if directory_matches_identity "$resolved_install_dir" "$jr_payload_identity"; then
        final_payload=true
        current_manifest="$(sha256_digest "$resolved_install_dir/SHA256SUMS" 2>/dev/null || true)"
        current_version="$(single_line_value "$resolved_install_dir/VERSION" 2>/dev/null || true)"
        validate_payload_manifest "$resolved_install_dir" || return 1
    elif directory_matches_identity "$jr_payload_stage" "$jr_payload_identity" && \
         [[ ! -e "$resolved_install_dir" && ! -L "$resolved_install_dir" ]]; then
        current_manifest="$(sha256_digest "$jr_payload_stage/SHA256SUMS" 2>/dev/null || true)"
        current_version="$(single_line_value "$jr_payload_stage/VERSION" 2>/dev/null || true)"
        validate_payload_manifest "$jr_payload_stage" || return 1
    else
        printf 'Error: recorded bootstrap payload identity no longer matches its install or staging path.\n' >&2
        return 1
    fi
    if [[ "$current_manifest" != "$jr_manifest" || "$current_version" != "$release_version" ]]; then
        printf 'Error: recorded bootstrap payload no longer matches its verified release manifest.\n' >&2
        return 1
    fi

    if [[ "$jr_cli_owned" == "true" ]]; then
        if ! absolute_path_is_safe "$jr_cli_stage_dir" || \
           [[ "$(dirname "$jr_cli_stage_dir")" != "$resolved_bin_dir" || \
              "$(basename "$jr_cli_stage_dir")" != .mainframe-bootstrap-link.* || \
              "$jr_cli_stage_link" != "$jr_cli_stage_dir/mainframe" || \
              ! "$jr_cli_stage_dir_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
            printf 'Error: recorded bootstrap CLI staging identity is unsafe or no longer exact.\n' >&2
            return 1
        fi
        if directory_matches_identity "$jr_cli_stage_dir" "$jr_cli_stage_dir_identity"; then
            cli_stage_exact=true
        elif [[ -e "$jr_cli_stage_dir" || -L "$jr_cli_stage_dir" ]]; then
            printf 'Error: recorded bootstrap CLI staging path was replaced.\n' >&2
            return 1
        fi
        if link_matches_identity "$cli_link" "$jr_cli_identity" "$resolved_install_dir/bin/mainframe"; then
            final_cli=true
        elif [[ -e "$cli_link" || -L "$cli_link" ]]; then
            printf 'Error: MAINFRAME CLI path was replaced after the interrupted bootstrap: %s\n' \
                "$cli_link" >&2
            return 1
        fi
        if [[ "$cli_stage_exact" == "true" ]] && \
           link_matches_identity "$jr_cli_stage_link" "$jr_cli_identity" "$resolved_install_dir/bin/mainframe"; then
            staged_cli=true
        fi
        if [[ "$final_cli" != "true" && "$staged_cli" != "true" ]]; then
            printf 'Error: recorded bootstrap CLI identity no longer exists at an owned path.\n' >&2
            return 1
        fi
    elif [[ "$jr_cli_owned" == "false" ]]; then
        if [[ -n "$jr_cli_stage_dir" || -n "$jr_cli_stage_dir_identity" || \
              -n "$jr_cli_stage_link" ]] || \
           ! link_matches_identity "$cli_link" "$jr_cli_identity" "$resolved_install_dir/bin/mainframe"; then
            printf 'Error: preexisting exact MAINFRAME CLI link changed after the interrupted bootstrap.\n' >&2
            return 1
        fi
        final_cli=true
    else
        printf 'Error: bootstrap recovery CLI ownership flag is invalid.\n' >&2
        return 1
    fi

    stage_identity="$jr_payload_identity"
    journal_manifest_sha="$jr_manifest"
    cli_owned="$jr_cli_owned"
    cli_identity="$jr_cli_identity"
    cli_stage_dir="$jr_cli_stage_dir"
    cli_stage_dir_identity="$jr_cli_stage_dir_identity"
    cli_stage_link="$jr_cli_stage_link"
    if [[ "$final_payload" == "true" ]]; then
        placed_release=true
        payload_dir=""
    else
        payload_dir="$jr_payload_stage"
    fi
    journal_cleanup_authorized=true
    return 0
}

publish_owned_cli_link() {
    if [[ "$cli_owned" == "false" ]]; then
        link_matches_identity "$cli_link" "$cli_identity" "$resolved_install_dir/bin/mainframe" || {
            printf 'Error: preexisting exact MAINFRAME CLI link changed before installation.\n' >&2
            return 1
        }
        return 0
    fi
    if [[ -e "$cli_link" || -L "$cli_link" ]]; then
        if ! link_matches_identity "$cli_link" "$cli_identity" "$resolved_install_dir/bin/mainframe"; then
            printf 'Error: MAINFRAME CLI path changed before exact link publication: %s\n' "$cli_link" >&2
            return 1
        fi
        return 0
    else
        if ! directory_matches_identity "$cli_stage_dir" "$cli_stage_dir_identity"; then
            printf 'Error: private MAINFRAME CLI staging directory identity changed.\n' >&2
            return 1
        fi
        if ! link_matches_identity "$cli_stage_link" "$cli_identity" "$resolved_install_dir/bin/mainframe"; then
            printf 'Error: prepared MAINFRAME CLI link identity changed before publication.\n' >&2
            return 1
        fi
        if ! ln -P "$cli_stage_link" "$cli_link" 2>/dev/null; then
            printf 'Error: could not publish the exact MAINFRAME-owned CLI link: %s\n' "$cli_link" >&2
            return 1
        fi
        if ! link_matches_identity "$cli_link" "$cli_identity" "$resolved_install_dir/bin/mainframe"; then
            printf 'Error: MAINFRAME CLI link identity changed during publication.\n' >&2
            return 1
        fi
    fi
    sync
}

remove_private_cli_stage() {
    [[ "$cli_owned" == "true" && -n "$cli_stage_dir" ]] || return 0
    if [[ ! -e "$cli_stage_dir" && ! -L "$cli_stage_dir" ]]; then
        return 0
    fi
    directory_matches_identity "$cli_stage_dir" "$cli_stage_dir_identity" || return 1
    if [[ -e "$cli_stage_link" || -L "$cli_stage_link" ]]; then
        link_matches_identity "$cli_stage_link" "$cli_identity" "$resolved_install_dir/bin/mainframe" || return 1
        rm -f -- "$cli_stage_link" || return 1
    fi
    rmdir "$cli_stage_dir"
}

remove_bootstrap_journal() {
    local record="$journal_path/record.json"

    [[ "$journal_cleanup_authorized" == "true" ]] || return 1
    directory_matches_identity "$journal_path" "$journal_identity" || return 1
    [[ -f "$record" && ! -L "$record" && \
       "$(path_identity "$record")" == "$journal_record_identity" ]] || return 1
    rm -f -- "$record" || return 1
    rmdir "$journal_path"
}

validate_release_receipt() {
    local receipt="$resolved_install_dir/$RECEIPT_NAME" manifest_sha
    [[ -f "$receipt" && ! -L "$receipt" && "$(portable_mode "$receipt")" == "600" ]] || return 1
    manifest_sha="$(sha256_digest "$resolved_install_dir/SHA256SUMS")" || return 1
    [[ "$manifest_sha" == "$journal_manifest_sha" ]] || return 1
    jq -e \
        --arg version "$release_version" \
        --arg archive_sha256 "$actual_digest" \
        --arg manifest_sha256 "$journal_manifest_sha" \
        --arg install_dir "$resolved_install_dir" \
        --arg bin_dir "$resolved_bin_dir" \
        --arg cli_link "$cli_link" '
        type == "object" and
        keys == ["archive_sha256", "bin_dir", "cli_link", "install_dir",
                 "install_method", "installed_at", "manifest_sha256",
                 "schema_version", "version"] and
        .schema_version == 1 and .install_method == "release-archive" and
        .version == $version and .archive_sha256 == $archive_sha256 and
        .manifest_sha256 == $manifest_sha256 and .install_dir == $install_dir and
        .bin_dir == $bin_dir and .cli_link == $cli_link and
        (.installed_at | type == "string" and length > 0 and
         (test("[\u0000-\u001f\u007f]") | not))
    ' "$receipt" >/dev/null
}

verify_installed_release() {
    local reported_version version_output

    directory_matches_identity "$resolved_install_dir" "$stage_identity" || {
        printf 'Error: verified install-root identity changed before runtime verification.\n' >&2
        return 1
    }
    link_matches_identity "$cli_link" "$cli_identity" "$resolved_install_dir/bin/mainframe" || {
        printf 'Error: installer did not preserve the exact MAINFRAME CLI link identity: %s\n' \
            "$cli_link" >&2
        return 1
    }
    validate_payload_manifest "$resolved_install_dir" || {
        printf 'Error: installed release no longer matches its complete payload manifest.\n' >&2
        return 1
    }
    version_output="$(MAINFRAME_VERSION='' MAINFRAME_ROOT="$resolved_install_dir" MAINFRAME_BASH="$bootstrap_bash" \
        _mainframe_bootstrap_run_clean "$bootstrap_bash" --noprofile --norc -p \
        "$resolved_install_dir/bin/mainframe" version)" || {
        printf 'Error: installed MAINFRAME runtime failed its version check.\n' >&2
        return 1
    }
    reported_version="${version_output%%$'\n'*}"
    if [[ "$reported_version" != "MAINFRAME v$release_version" ]]; then
        printf 'Error: installed runtime reported %s instead of MAINFRAME v%s.\n' \
            "$reported_version" "$release_version" >&2
        return 1
    fi
    if ! MAINFRAME_VERSION='' MAINFRAME_ROOT="$resolved_install_dir" MAINFRAME_BASH="$bootstrap_bash" \
        _mainframe_bootstrap_run_clean "$bootstrap_bash" --noprofile --norc -p \
        "$resolved_install_dir/bin/mainframe" doctor >/dev/null 2>&1; then
        printf 'Error: installed MAINFRAME runtime failed its doctor check; no release receipt was written.\n' >&2
        return 1
    fi
}

report_optional_install_failure() {
    local status="$1" index

    printf 'Error: optional shell/discovery setup failed with status %s.\n' "$status" >&2
    printf 'Core MAINFRAME v%s installation succeeded and remains receipt-backed at %s.\n' \
        "$release_version" "$resolved_install_dir" >&2
    printf 'Retry only the optional setup with this exact command:\n  ' >&2
    printf 'MAINFRAME_INSTALL_DIR=%q MAINFRAME_BIN_DIR=%q MAINFRAME_BASH=%q %q --noprofile --norc -p %q' \
        "$resolved_install_dir" "$resolved_bin_dir" "$bootstrap_bash" \
        "$bootstrap_bash" "$resolved_install_dir/install.sh" >&2
    for ((index = 1; index < ${#installer_args[@]}; index++)); do
        printf ' %q' "${installer_args[$index]}" >&2
    done
    printf '\n' >&2
}

if [[ "$legacy_source_requested" == "true" ]]; then
    validate_legacy_bootstrap_provenance || exit 2
fi

bootstrap_bash="$(find_supported_bash || true)"
if [[ -z "$bootstrap_bash" ]]; then
    printf 'Error: MAINFRAME requires Bash 4.4+, but no suitable executable was found.\n' >&2
    printf 'macOS: install one with brew install bash, then retry; an override must be an absolute reviewed path.\n' >&2
    printf 'Linux: install a current bash package, then retry; an override must be an absolute reviewed path.\n' >&2
    exit 1
fi

validate_bootstrap_dependency_test_controls || exit 2

bootstrap_curl="${_MAINFRAME_BOOTSTRAP_TEST_CURL:-}"
if [[ -z "$bootstrap_curl" ]]; then
    bootstrap_curl="$(command -v curl 2>/dev/null || true)"
    case "$bootstrap_curl" in
        /usr/bin/curl|/bin/curl) ;;
        *) bootstrap_curl="" ;;
    esac
fi
if [[ -z "$bootstrap_curl" ]]; then
    printf 'Error: curl is required by the bootstrap installer.\n' >&2
    printf 'Manual install: git clone %s "%s" && %q --noprofile --norc -p "%s/install.sh"\n' \
        "$MAINFRAME_REPO" "$MAINFRAME_INSTALL_DIR" "$bootstrap_bash" \
        "$MAINFRAME_INSTALL_DIR" >&2
    exit 1
fi

bootstrap_jq=""
if [[ "${MAINFRAME_BOOTSTRAP_INTERNAL_NO_JQ:-}" != "1" ]]; then
    bootstrap_jq="$(find_trusted_jq || true)"
fi
if [[ -z "$bootstrap_jq" ]]; then
    printf 'Error: jq is required for a safety-ready MAINFRAME installation.\n' >&2
    printf 'macOS: brew install jq   Linux: install the jq package, then retry.\n' >&2
    exit 1
fi

bootstrap_dir="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-bootstrap.XXXXXX")"
payload_dir=""
stage_identity=""
placed_release=false
placement_in_progress=false
release_complete=false
release_optional_install=false
misplaced_payload=""
install_lock=""
install_lock_owned=false
install_lock_identity=""
cli_owned=false
cli_identity=""
cli_stage_dir=""
cli_stage_dir_identity=""
cli_stage_link=""
journal_path=""
journal_stage_dir=""
journal_identity=""
journal_record_identity=""
journal_manifest_sha=""
journal_cleanup_authorized=false
core_installer_args=(__mainframe_core_installer_sentinel__)
cleanup_bootstrap() {
    local status=$? failure_dir="" candidate_path="" exact_cli=false
    trap - EXIT INT TERM
    set +e

    if [[ "$status" -ne 0 && "$release_complete" != "true" ]]; then
        if [[ "$placed_release" == "true" && -n "${resolved_install_dir:-}" && \
              -d "$resolved_install_dir" && ! -L "$resolved_install_dir" && \
              "$(path_identity "$resolved_install_dir")" == "${stage_identity:-missing}" ]]; then
            candidate_path="$resolved_install_dir"
        elif [[ "$placement_in_progress" == "true" && -n "${resolved_install_dir:-}" && \
                -d "$resolved_install_dir" && ! -L "$resolved_install_dir" && \
                "$(path_identity "$resolved_install_dir")" == "${stage_identity:-missing}" ]]; then
            candidate_path="$resolved_install_dir"
        elif [[ -n "$misplaced_payload" && -d "$misplaced_payload" && ! -L "$misplaced_payload" && \
                "$(path_identity "$misplaced_payload")" == "${stage_identity:-missing}" ]]; then
            candidate_path="$misplaced_payload"
        elif [[ -n "$payload_dir" ]] && \
             directory_matches_identity "$payload_dir" "${stage_identity:-missing}"; then
            candidate_path="$payload_dir"
        fi
        if [[ "$cli_owned" == "true" && -n "${cli_link:-}" ]] && \
           link_matches_identity "$cli_link" "$cli_identity" "${resolved_install_dir:-}/bin/mainframe"; then
            exact_cli=true
        fi
        if [[ -n "${install_parent:-}" && \
              ( -n "$candidate_path" || \
                "$exact_cli" == "true" || "$journal_cleanup_authorized" == "true" ) ]]; then
            failure_dir="$(mktemp -d "$install_parent/.mainframe-failed-install.XXXXXX" 2>/dev/null || true)"
            if [[ -z "$failure_dir" ]]; then
                printf 'Warning: incomplete release cleanup directory could not be created.\n' >&2
            elif [[ -n "$candidate_path" ]] && mv "$candidate_path" "$failure_dir/payload"; then
                printf 'Incomplete release was deactivated and retained at %s\n' "$failure_dir/payload" >&2
            elif [[ -n "$candidate_path" ]]; then
                printf 'Warning: incomplete release could not be deactivated automatically: %s\n' \
                    "$candidate_path" >&2
            fi
            if [[ -n "$failure_dir" && "$exact_cli" == "true" ]]; then
                mv "$cli_link" "$failure_dir/cli-link"
            fi
            if [[ -n "$failure_dir" && "$cli_owned" == "true" && \
                  -n "$cli_stage_dir" ]] && \
               directory_matches_identity "$cli_stage_dir" "$cli_stage_dir_identity"; then
                mv "$cli_stage_dir" "$failure_dir/cli-stage"
            fi
            if [[ -n "$failure_dir" && "$journal_cleanup_authorized" == "true" ]] && \
               directory_matches_identity "$journal_path" "$journal_identity" && \
               [[ -f "$journal_path/record.json" && ! -L "$journal_path/record.json" && \
                  "$(path_identity "$journal_path/record.json")" == "$journal_record_identity" ]]; then
                mv "$journal_path" "$failure_dir/journal"
            fi
        fi
    fi
    if [[ -n "$payload_dir" ]] && directory_matches_identity "$payload_dir" "${stage_identity:-missing}"; then
        rm -rf -- "$payload_dir"
    fi
    if [[ -n "$cli_stage_dir" ]] && directory_matches_identity "$cli_stage_dir" "$cli_stage_dir_identity"; then
        if [[ -e "$cli_stage_link" || -L "$cli_stage_link" ]]; then
            if link_matches_identity "$cli_stage_link" "$cli_identity" "${resolved_install_dir:-}/bin/mainframe"; then
                rm -f -- "$cli_stage_link"
            fi
        fi
        rmdir "$cli_stage_dir" 2>/dev/null || true
    fi
    if [[ -n "$journal_stage_dir" ]] && \
       directory_matches_identity "$journal_stage_dir" "$journal_identity"; then
        rm -rf -- "$journal_stage_dir"
    fi
    rm -rf -- "$bootstrap_dir"
    if [[ "$install_lock_owned" == "true" && -f "$install_lock" && ! -L "$install_lock" && \
          "$(path_identity "$install_lock")" == "$install_lock_identity" && \
          "$(single_line_value "$install_lock" 2>/dev/null || true)" == "$$" ]]; then
        rm -f -- "$install_lock"
    fi
    exit "$status"
}
trap cleanup_bootstrap EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$latest_requested" == "true" || -n "$release_version" ]]; then
    for release_command in env tar stat ln sync; do
        if ! command -v "$release_command" >/dev/null 2>&1; then
            printf 'Error: %s is required for a versioned release install.\n' "$release_command" >&2
            exit 1
        fi
    done
    prepare_release_installer_args || exit 2
    validate_release_base_url || exit 1
fi

if [[ "$latest_requested" == "true" ]]; then
    resolve_latest_release "$bootstrap_dir/latest-release.json" || exit 1
fi

if [[ "$legacy_source_requested" == "true" ]]; then
    installer="$bootstrap_dir/install.sh"
    printf 'Warning: using the legacy mutable installer URL; no release checksum is verified.\n' >&2
    printf 'Omit --legacy-source, use --latest, or use --release-version X.Y.Z instead.\n' >&2
    printf 'Downloading MAINFRAME installer (legacy mode)...\n'
    if ! download_legacy_installer "$installer"; then
        printf 'Error: legacy installer download failed under the direct trusted transport policy.\n' >&2
        exit 1
    fi
    chmod +x "$installer"

    # Provenance is delegated only through the reviewed same-command flags.
    # Do not turn the bootstrap's parsed values back into inherited installer
    # authorization.
    unset MAINFRAME_REPO MAINFRAME_BRANCH MAINFRAME_INSTALLER_URL 2>/dev/null || true
    export MAINFRAME_INSTALL_DIR MAINFRAME_BIN_DIR
    _mainframe_bootstrap_run_clean "$bootstrap_bash" --noprofile --norc -p \
        "$installer" "${installer_args[@]:1}"
    exit $?
fi

asset_name="mainframe-${release_version}.tar.gz"
release_url="${MAINFRAME_RELEASE_BASE_URL%/}/v${release_version}"
archive="$bootstrap_dir/$asset_name"
checksum_file="$archive.sha256"
members_file="$bootstrap_dir/archive-members.txt"
verbose_file="$bootstrap_dir/archive-verbose.txt"

printf 'Downloading MAINFRAME v%s release archive...\n' "$release_version"
download_release_file "$release_url/$asset_name" "$archive"
download_release_file "$release_url/$asset_name.sha256" "$checksum_file"

actual_digest="$(sha256_digest "$archive")" || exit 1
checksum_actual_digest="$(sha256_digest "$checksum_file")" || exit 1
if [[ "$latest_requested" == "true" ]]; then
    if [[ "$actual_digest" != "$latest_archive_api_digest" ]]; then
        printf 'Error: downloaded release archive does not match its GitHub API SHA-256 digest.\n' >&2
        exit 1
    fi
    if [[ "$checksum_actual_digest" != "$latest_checksum_api_digest" ]]; then
        printf 'Error: downloaded release checksum asset does not match its GitHub API SHA-256 digest.\n' >&2
        exit 1
    fi
fi

expected_digest="$(validate_checksum_record "$checksum_file" "$asset_name")" || exit 1
if [[ "$latest_requested" == "true" && \
      "$expected_digest" != "$latest_archive_api_digest" ]]; then
    printf 'Error: release checksum record does not match the GitHub archive digest.\n' >&2
    exit 1
fi
if [[ "$actual_digest" != "$expected_digest" ]]; then
    printf 'Error: release archive SHA-256 verification failed.\n' >&2
    exit 1
fi
printf 'Verified SHA-256: %s\n' "$actual_digest"

validate_release_archive "$archive" "$members_file" "$verbose_file" || exit 1
archive_manifest_file="$bootstrap_dir/archive-SHA256SUMS"
if ! env -u TAR_OPTIONS tar -xOzf "$archive" SHA256SUMS > "$archive_manifest_file"; then
    printf 'Error: verified release archive manifest could not be read.\n' >&2
    exit 1
fi
chmod 600 "$archive_manifest_file" || exit 1
archive_manifest_digest="$(sha256_digest "$archive_manifest_file")" || exit 1
resolved_install_dir="$(resolve_install_target_path "$MAINFRAME_INSTALL_DIR")" || exit 1
acquire_install_lock "$resolved_install_dir" || exit 1
locked_install_dir="$(resolve_install_target_path "$MAINFRAME_INSTALL_DIR")" || exit 1
if [[ "$locked_install_dir" != "$resolved_install_dir" ]]; then
    printf 'Error: install target identity changed while acquiring its lock.\n' >&2
    exit 1
fi
resolved_bin_dir="$(resolve_bin_directory "$MAINFRAME_BIN_DIR")" || exit 1
install_parent="$(dirname "$resolved_install_dir")"
install_base="$(basename "$resolved_install_dir")"
cli_link="$resolved_bin_dir/mainframe"
journal_path="$install_parent/.${install_base}.bootstrap-journal"
validate_bootstrap_failpoint || exit 2

if [[ -e "$journal_path" || -L "$journal_path" ]]; then
    load_bootstrap_journal || exit 1
    printf 'Resuming exact verified MAINFRAME v%s bootstrap state.\n' "$release_version"
else
    locked_install_dir="$(resolve_empty_install_target "$MAINFRAME_INSTALL_DIR")" || exit 1
    if [[ "$locked_install_dir" != "$resolved_install_dir" ]]; then
        printf 'Error: install target identity changed after acquiring its lock.\n' >&2
        exit 1
    fi

    payload_dir="$(mktemp -d "$install_parent/.mainframe-release-stage.XXXXXX")" || exit 1
    chmod 700 "$payload_dir" || exit 1
    stage_identity="$(path_identity "$payload_dir")"
    if [[ -z "$stage_identity" ]]; then
        printf 'Error: could not identify the verified release staging directory.\n' >&2
        exit 1
    fi
    if ! env -u TAR_OPTIONS tar -xzf "$archive" -C "$payload_dir"; then
        printf 'Error: verified release archive could not be extracted.\n' >&2
        exit 1
    fi
    if [[ -n "$(find "$payload_dir" -type l -print -quit 2>/dev/null)" ]]; then
        printf 'Error: extracted release unexpectedly contains a symbolic link.\n' >&2
        exit 1
    fi
    if [[ ! -x "$payload_dir/install.sh" || ! -x "$payload_dir/bin/mainframe" || \
          ! -x "$payload_dir/scripts/upgrade-release.sh" ]]; then
        printf 'Error: extracted release is missing an executable MAINFRAME payload.\n' >&2
        exit 1
    fi
    validate_payload_manifest "$payload_dir" || exit 1
    embedded_version="$(single_line_value "$payload_dir/VERSION" 2>/dev/null || true)"
    if [[ "$embedded_version" != "$release_version" ]]; then
        printf 'Error: release archive VERSION (%s) does not match requested version (%s).\n' \
            "$embedded_version" "$release_version" >&2
        exit 1
    fi

    if [[ -e "$cli_link" || -L "$cli_link" ]]; then
        cli_owned=false
        if [[ ! -L "$cli_link" || \
              "$(readlink "$cli_link")" != "$resolved_install_dir/bin/mainframe" ]]; then
            printf 'Error: versioned install will not replace an existing CLI path: %s\n' \
                "$cli_link" >&2
            exit 1
        fi
        cli_identity="$(path_identity "$cli_link")"
    else
        cli_owned=true
        cli_stage_dir="$(mktemp -d "$resolved_bin_dir/.mainframe-bootstrap-link.XXXXXX")" || exit 1
        chmod 700 "$cli_stage_dir" || exit 1
        cli_stage_dir_identity="$(path_identity "$cli_stage_dir")"
        cli_stage_link="$cli_stage_dir/mainframe"
        ln -s "$resolved_install_dir/bin/mainframe" "$cli_stage_link" || exit 1
        cli_identity="$(path_identity "$cli_stage_link")"
    fi
    if [[ -z "$cli_identity" || \
          ( "$cli_owned" == "true" && -z "$cli_stage_dir_identity" ) ]]; then
        printf 'Error: could not identify the exact prepared MAINFRAME CLI link state.\n' >&2
        exit 1
    fi
    publish_bootstrap_journal || exit 1
fi

if [[ "$placed_release" != "true" ]]; then
    if [[ -d "$resolved_install_dir" ]]; then
        rmdir "$resolved_install_dir" || {
            printf 'Error: release install target changed before installation: %s\n' \
                "$resolved_install_dir" >&2
            exit 1
        }
    fi
    placement_in_progress=true
    placement_source="$payload_dir"
    if [[ -n "${_MAINFRAME_BOOTSTRAP_TEST_MV:-}" ]]; then
        placement_mv="$_MAINFRAME_BOOTSTRAP_TEST_MV"
    else
        placement_mv='mv'
    fi
    if ! "$placement_mv" "$placement_source" "$resolved_install_dir"; then
        printf 'Error: could not place the verified release at %s.\n' \
            "$resolved_install_dir" >&2
        exit 1
    fi
    if [[ "$(path_identity "$resolved_install_dir")" != "$stage_identity" ]]; then
        misplaced_payload="$resolved_install_dir/$(basename "$placement_source")"
        placement_in_progress=false
        payload_dir=""
        printf 'Error: install target changed during final placement; no payload code was executed.\n' >&2
        exit 1
    fi
    placed_release=true
    placement_in_progress=false
    payload_dir=""
    _MAINFRAME_BOOTSTRAP_TEST_MV=""
    unset MAINFRAME_BOOTSTRAP_INTERNAL_MV 2>/dev/null || true
    sync
fi
run_bootstrap_failpoint kill-after-placement
publish_owned_cli_link || exit 1

MAINFRAME_INSTALL_DIR="$resolved_install_dir"
MAINFRAME_BIN_DIR="$resolved_bin_dir"
unset MAINFRAME_REPO MAINFRAME_BRANCH MAINFRAME_INSTALLER_URL 2>/dev/null || true
export MAINFRAME_INSTALL_DIR MAINFRAME_BIN_DIR

if [[ -e "$MAINFRAME_INSTALL_DIR/$RECEIPT_NAME" || -L "$MAINFRAME_INSTALL_DIR/$RECEIPT_NAME" ]]; then
    if ! validate_release_receipt; then
        printf 'Error: interrupted bootstrap receipt does not exactly match the verified journal.\n' >&2
        exit 1
    fi
    verify_installed_release || exit 1
    release_complete=true
    printf 'Recovered already receipt-backed MAINFRAME v%s installation.\n' "$release_version"
else
    _mainframe_bootstrap_run_clean "$bootstrap_bash" --noprofile --norc -p \
        "$MAINFRAME_INSTALL_DIR/install.sh" "${core_installer_args[@]:1}"
    run_bootstrap_failpoint kill-after-core-installer
    verify_installed_release || exit 1
    if ! write_release_receipt "$MAINFRAME_INSTALL_DIR" "$release_version" "$actual_digest" "$MAINFRAME_BIN_DIR"; then
        printf 'Error: installed runtime passed verification, but its release receipt could not be written.\n' >&2
        exit 1
    fi
    release_complete=true
    sync
fi
printf 'Release receipt: %s\n' "$MAINFRAME_INSTALL_DIR/$RECEIPT_NAME"
optional_status=0

# Shell-profile and opt-in discovery writes are deliberately deferred until the
# runtime is receipt-backed and healthy. The recovery journal remains durable
# through this optional pass so a hard interruption can validate and retry it.
if [[ "$release_optional_install" == "true" ]]; then
    if _mainframe_bootstrap_run_clean "$bootstrap_bash" --noprofile --norc -p \
        "$MAINFRAME_INSTALL_DIR/install.sh" "${installer_args[@]:1}"; then
        :
    else
        optional_status=$?
    fi
fi

if ! remove_private_cli_stage; then
    printf 'Error: core installation is receipt-backed, but its exact CLI staging state could not be retired.\n' >&2
    printf 'Rerun this same versioned bootstrap command to validate and retire it safely.\n' >&2
    if [[ "$optional_status" -ne 0 ]]; then
        report_optional_install_failure "$optional_status"
    fi
    exit 1
fi
cli_stage_dir=""
if ! remove_bootstrap_journal; then
    printf 'Error: core installation is receipt-backed, but its recovery journal could not be retired.\n' >&2
    printf 'Rerun this same versioned bootstrap command to validate and retire it safely.\n' >&2
    if [[ "$optional_status" -ne 0 ]]; then
        report_optional_install_failure "$optional_status"
    fi
    exit 1
fi
journal_cleanup_authorized=false
sync
if [[ "$optional_status" -ne 0 ]]; then
    report_optional_install_failure "$optional_status"
    exit "$optional_status"
fi

        ;;
    *)
        /bin/bash --noprofile --norc -p -- "$0" "$@"
        ;;
esac

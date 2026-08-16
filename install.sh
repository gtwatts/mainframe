#!/bin/bash -p
# =============================================================================
# MAINFRAME Installation Script
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
# Preferred bootstrap: download a reviewed tag's get-mainframe.sh, then run
#   /bin/bash --noprofile --norc -p get-mainframe.sh --release-version X.Y.Z
# From a checkout with Bash 4.4+:
#   /absolute/path/to/bash --noprofile --norc -p ./install.sh [options]
# =============================================================================

# An explicit unprivileged `bash install.sh` can import functions whose names
# shadow even installer primitives such as `set` and `builtin`. Enter a fixed
# protected interpreter before executing any command in that process. The
# protected invocation documented above remains the path for selecting a
# non-system Bash on macOS.
case "$-" in
    *p*)

set -euo pipefail

# Direct execution uses the fixed privileged shebang. The verified bootstrap
# also invokes this file with --noprofile --norc -p and a clean environment.
# Remove passive loader hooks here as defense in depth for source-checkout
# installs before this script starts any dependency or repository command.
_mainframe_installer_scrub_code_loader_env() {
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
        if [[ "$function_name" == _mainframe_installer_scrub_code_loader_env ]]; then
            # shellcheck disable=SC2163 # Function name is intentionally indirect.
            builtin export -n -f "$function_name" 2>/dev/null || return 1
        else
            builtin unset -f "$function_name" 2>/dev/null || return 1
        fi
    done < <(builtin compgen -A function)
}

_mainframe_installer_scrub_code_loader_env || {
    printf 'Error: installer could not clear inherited code-loader environment.\n' >&2
    exit 1
}
unset -f _mainframe_installer_scrub_code_loader_env

# Source installs must not execute project or caller-PATH shims. Bash is the
# already-running explicitly selected interpreter; jq is resolved separately
# from fixed system/package-manager locations below.
MAINFRAME_INSTALLER_SYSTEM_PATH=/usr/bin:/bin:/usr/sbin:/sbin
PATH="$MAINFRAME_INSTALLER_SYSTEM_PATH"
export PATH
builtin hash -r

# =============================================================================
# CONFIGURATION
# =============================================================================

MAINFRAME_CANONICAL_REPO="https://github.com/gtwatts/mainframe.git"
MAINFRAME_CANONICAL_BRANCH="main"
MAINFRAME_INHERITED_REPO="${MAINFRAME_REPO:-}"
MAINFRAME_INHERITED_BRANCH="${MAINFRAME_BRANCH:-}"
MAINFRAME_INHERITED_FORCE="${MAINFRAME_FORCE:-}"
unset MAINFRAME_FORCE 2>/dev/null || true
MAINFRAME_REPO="$MAINFRAME_CANONICAL_REPO"
MAINFRAME_BRANCH="$MAINFRAME_CANONICAL_BRANCH"
MAINFRAME_REPO_EXPLICIT=false
MAINFRAME_BRANCH_EXPLICIT=false
MAINFRAME_UNVERIFIED_SOURCE_ALLOWED=false
MAINFRAME_FORCE_REQUESTED=false
MAINFRAME_INSTALL_DIR="${MAINFRAME_INSTALL_DIR:-$HOME/.mainframe}"
MAINFRAME_BIN_DIR="${MAINFRAME_BIN_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_SHELL_CONFIG=""
MAINFRAME_SHELL_NAME=""
MAINFRAME_BASH_LOGIN_CONFIG=""
MAINFRAME_INSTALLER_BASH=""
MAINFRAME_BEGIN_MARKER="# >>> MAINFRAME >>>"
MAINFRAME_END_MARKER="# <<< MAINFRAME <<<"
MAINFRAME_BASH_LOGIN_BEGIN_MARKER="# >>> MAINFRAME BASH LOGIN >>>"
MAINFRAME_BASH_LOGIN_END_MARKER="# <<< MAINFRAME BASH LOGIN <<<"
declare -a MAINFRAME_BASH_LOGIN_PROFILES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

info() {
    printf "${BLUE}[INTEL]${NC} %s\n" "$*"
}

success() {
    printf "${GREEN}[MISSION COMPLETE]${NC} %s\n" "$*"
}

warn() {
    printf "${YELLOW}[CAUTION]${NC} %s\n" "$*" >&2
}

error() {
    printf "${RED}[ABORT]${NC} %s\n" "$*" >&2
}

die() {
    error "$*"
    exit 1
}

command_exists() {
    command -v "$1" &>/dev/null
}

installer_resolve_absolute_executable() {
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
    [[ -f "$source" && ! -L "$source" && -x "$source" ]] || return 1
    [[ "$source" != *$'\n'* && "$source" != *$'\r'* &&
       "$source" != *$'\t'* ]] || return 1
    printf '%s\n' "$source"
}

installer_owner_mode() {
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

installer_path_has_no_write_acl() {
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

installer_jq_layout_is_known() {
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

installer_bash_layout_is_known() {
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

installer_current_bash_is_trusted() {
    installer_trusted_bash "${BASH:-}" >/dev/null
}

installer_trusted_bash() {
    local requested="$1" resolved owner mode numeric
    resolved="$(installer_resolve_absolute_executable "$requested" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || return 1
    installer_bash_layout_is_known "$resolved" || return 1
    read -r owner mode < <(installer_owner_mode "$resolved") || return 1
    [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || return 1
    numeric=$((8#$mode))
    (( (numeric & 0022) == 0 && (numeric & 07000) == 0 &&
       (numeric & 0100) != 0 )) || return 1
    installer_path_has_no_write_acl "$resolved" || return 1
    printf '%s\n' "$resolved"
}

installer_bash_is_supported() {
    local candidate="$1"
    /usr/bin/env -i PATH="$MAINFRAME_INSTALLER_SYSTEM_PATH" LC_ALL=C \
        "$candidate" --noprofile --norc -p -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ))
    ' >/dev/null 2>&1
}

installer_reenter_original_bash_if_needed() {
    local requested="${_MAINFRAME_INSTALLER_REENTRY_BASH:-}" resolved current
    [[ -n "$requested" ]] || return 0
    unset _MAINFRAME_INSTALLER_REENTRY_BASH

    resolved="$(installer_trusted_bash "$requested" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || \
        die "Bash must resolve to a supported system, Homebrew, Linuxbrew, MacPorts, or Nix installation"
    current="$(installer_resolve_absolute_executable "${BASH:-}" 2>/dev/null || true)"
    [[ "$resolved" != "$current" ]] || return 0
    installer_bash_is_supported "$resolved" || \
        die "Bash 4.4+ required (found unsupported re-entry candidate: $resolved)"

    exec "$resolved" --noprofile --norc -p -- "$0" "$@"
}

find_trusted_installer_jq() {
    local candidate resolved owner mode numeric
    for candidate in \
        /usr/bin/jq \
        /bin/jq \
        /opt/homebrew/bin/jq \
        /usr/local/bin/jq \
        /home/linuxbrew/.linuxbrew/bin/jq \
        /opt/local/bin/jq; do
        resolved="$(installer_resolve_absolute_executable "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || continue
        installer_jq_layout_is_known "$resolved" || continue
        read -r owner mode < <(installer_owner_mode "$resolved") || continue
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || continue
        numeric=$((8#$mode))
        (( (numeric & 0022) == 0 && (numeric & 07000) == 0 &&
           (numeric & 0100) != 0 )) || continue
        installer_path_has_no_write_acl "$resolved" || continue
        if /usr/bin/env -i PATH="$MAINFRAME_INSTALLER_SYSTEM_PATH" LC_ALL=C \
            "$resolved" --version >/dev/null 2>&1; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done
    return 1
}

installer_git_layout_is_known() {
    local candidate="$1" prefix remainder version
    case "$candidate" in
        /bin/git|/usr/bin/git|/opt/local/bin/git) return 0 ;;
    esac
    for prefix in \
        /opt/homebrew/Cellar/git/ \
        /usr/local/Cellar/git/ \
        /home/linuxbrew/.linuxbrew/Cellar/git/; do
        case "$candidate" in
            "$prefix"*)
                remainder="${candidate#"$prefix"}"
                version="${remainder%%/*}"
                [[ -n "$version" && "$remainder" == "$version/bin/git" ]] && return 0
                ;;
        esac
    done
    return 1
}

# Git has a broad environment surface: caller configuration can rewrite URLs,
# replace transport helpers, redirect the repository/index, or execute hooks.
# Every installer Git process starts from an empty environment and receives
# only fixed locale/path values plus command-scope safety overrides. The
# installer intentionally does not inherit credentials, proxies, Git config,
# SSH commands, helper paths, tracing sinks, or repository selectors.
installer_run_git_clean() {
    local executable="$1"
    shift

    [[ "$executable" == /* ]] || return 1
    /usr/bin/env -i \
        HOME=/ \
        XDG_CONFIG_HOME=/dev/null \
        PATH="$MAINFRAME_INSTALLER_SYSTEM_PATH" \
        LC_ALL=C \
        LANG=C \
        GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_SYSTEM=/dev/null \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_TERMINAL_PROMPT=0 \
        GIT_SSH_COMMAND='/usr/bin/ssh -F /dev/null' \
        "$executable" \
        -c core.hooksPath=/dev/null \
        -c core.fsmonitor=false \
        -c credential.helper= \
        -c http.proxy= \
        -c remote.origin.proxy= \
        -c protocol.ext.allow=never \
        "$@"
}

installer_git() {
    installer_run_git_clean "${MAINFRAME_INSTALLER_GIT:?trusted Git is not bound}" "$@"
}

find_trusted_installer_git() {
    local candidate resolved owner mode numeric
    for candidate in \
        /opt/homebrew/bin/git \
        /usr/local/bin/git \
        /home/linuxbrew/.linuxbrew/bin/git \
        /opt/local/bin/git \
        /usr/bin/git \
        /bin/git; do
        resolved="$(installer_resolve_absolute_executable "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved" ]] || continue
        installer_git_layout_is_known "$resolved" || continue
        read -r owner mode < <(installer_owner_mode "$resolved") || continue
        [[ "$owner" -eq 0 || "$owner" -eq "$EUID" ]] || continue
        numeric=$((8#$mode))
        (( (numeric & 0022) == 0 && (numeric & 07000) == 0 &&
           (numeric & 0100) != 0 )) || continue
        installer_path_has_no_write_acl "$resolved" || continue
        if installer_run_git_clean "$resolved" --version >/dev/null 2>&1; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done
    return 1
}

# Keep opt-in discovery compatible with a package-manager jq without adding
# that package-manager directory (and every neighboring executable) to PATH.
jq() {
    "${MAINFRAME_INSTALLER_JQ:?trusted jq is not bound}" "$@"
}

installer_lexical_absolute_path() {
    local path="$1" remaining component normalized=""

    [[ "$path" == /* ]] || path="$(builtin pwd -P)/$path"
    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done
    remaining="${path#/}"
    while [[ -n "$remaining" ]]; do
        if [[ "$remaining" == */* ]]; then
            component="${remaining%%/*}"
            remaining="${remaining#*/}"
        else
            component="$remaining"
            remaining=""
        fi
        case "$component" in
            ""|.) ;;
            ..) normalized="${normalized%/*}" ;;
            *) normalized="$normalized/$component" ;;
        esac
    done
    printf '%s\n' "${normalized:-/}"
}

# Canonicalize the complete requested target without creating it. Existing
# directories, including symbolic-link aliases, resolve physically. Missing
# suffixes are rebuilt over the nearest canonical parent, while final dot and
# dot-dot components are handled before any directory traversal or mutation.
installer_canonical_path() {
    local path="$1" parent name canonical_parent

    [[ "$path" == /* ]] || path="$(builtin pwd -P)/$path"
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* &&
       "$path" != *$'\t'* ]] || return 1
    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done

    if [[ -d "$path" ]]; then
        builtin cd -- "$path" 2>/dev/null && builtin pwd -P
        return
    fi

    parent="${path%/*}"
    name="${path##*/}"
    [[ -n "$parent" ]] || parent=/
    canonical_parent="$(installer_canonical_path "$parent")" || return 1
    case "$name" in
        ""|.) printf '%s\n' "$canonical_parent" ;;
        ..)
            if [[ "$canonical_parent" == "/" ]]; then
                printf '/\n'
            else
                parent="${canonical_parent%/*}"
                printf '%s\n' "${parent:-/}"
            fi
            ;;
        *) printf '%s/%s\n' "${canonical_parent%/}" "$name" ;;
    esac
}

canonical_dir() {
    local path parent

    path="$(installer_canonical_path "$1")" || return 1
    if [[ -d "$path" ]]; then
        printf '%s\n' "$path"
        return 0
    fi
    parent="${path%/*}"
    [[ -n "$parent" ]] || parent=/
    mkdir -p "$parent" || return 1
    installer_canonical_path "$path"
}

installer_canonical_requested_install_root() {
    local requested="${MAINFRAME_INSTALL_DIR:-}"
    [[ -n "$requested" ]] || return 1
    installer_canonical_path "$requested"
}

installer_install_root_is_safe() {
    local requested="$1" lexical canonical canonical_home

    [[ -n "$requested" ]] || return 1
    lexical="$(installer_lexical_absolute_path "$requested")" || return 1
    canonical="$(installer_canonical_path "$requested")" || return 1
    canonical_home="$(installer_canonical_path "$HOME")" || return 1
    [[ "$lexical" != "/" && "$canonical" != "/" &&
       "$canonical" != "$canonical_home" ]]
}

installer_uses_selected_checkout() {
    local source_root install_root
    source_root="$(cd -- "$SCRIPT_DIR" 2>/dev/null && pwd -P)" || return 1
    install_root="$(installer_canonical_requested_install_root)" || return 1
    [[ "$source_root" == "$install_root" && -f "$source_root/bin/mainframe" ]]
}

installer_private_fixture_source_authorized() {
    local marker marker_value install_root owner mode
    [[ "${MAINFRAME_INTERNAL_TESTING:-}" == "1" ]] || return 1
    [[ -n "${HOME:-}" && -d "$HOME" ]] || return 1
    install_root="$(installer_canonical_requested_install_root)" || return 1
    marker="$HOME/.mainframe-bootstrap-internal-test-mode"
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    read -r owner mode < <(installer_owner_mode "$marker") || return 1
    [[ "$owner" -eq "$EUID" && "$mode" == "600" ]] || return 1
    installer_path_has_no_write_acl "$marker" || return 1
    marker_value="$(< "$marker")"
    [[ "$marker_value" == "MAINFRAME_BOOTSTRAP_INTERNAL_TESTING:$install_root" ]]
}

validate_install_source_selection() {
    local inherited_repo_noncanonical=false
    local inherited_branch_noncanonical=false
    local source_noncanonical=false

    # Executing install.sh from the exact requested checkout selects that
    # checkout by path, not by inherited repository variables.
    if installer_uses_selected_checkout; then
        return 0
    fi

    if [[ -n "$MAINFRAME_INHERITED_REPO" &&
          "$MAINFRAME_INHERITED_REPO" != "$MAINFRAME_CANONICAL_REPO" ]]; then
        inherited_repo_noncanonical=true
    fi
    if [[ -n "$MAINFRAME_INHERITED_BRANCH" &&
          "$MAINFRAME_INHERITED_BRANCH" != "$MAINFRAME_CANONICAL_BRANCH" ]]; then
        inherited_branch_noncanonical=true
    fi
    if [[ "$inherited_repo_noncanonical" == "true" ||
          "$inherited_branch_noncanonical" == "true" ]]; then
        die "Inherited MAINFRAME_REPO or MAINFRAME_BRANCH cannot select installation source; unset it and pass --repo URL --branch REF --allow-unverified-source on the same command"
    fi

    [[ -n "$MAINFRAME_REPO" ]] || die "--repo must not be empty"
    [[ -n "$MAINFRAME_BRANCH" ]] || die "--branch must not be empty"
    if [[ "$MAINFRAME_REPO" =~ [[:cntrl:]] ||
          "$MAINFRAME_BRANCH" =~ [[:cntrl:]] ]]; then
        die "Repository URL and branch must not contain control characters"
    fi
    [[ "$MAINFRAME_REPO" != -* ]] || die "Repository URL must not begin with '-'"

    if [[ "$MAINFRAME_REPO" != "$MAINFRAME_CANONICAL_REPO" ||
          "$MAINFRAME_BRANCH" != "$MAINFRAME_CANONICAL_BRANCH" ]]; then
        source_noncanonical=true
    fi
    if [[ "$source_noncanonical" == "true" ]]; then
        if [[ "$MAINFRAME_REPO_EXPLICIT" != "true" ||
              "$MAINFRAME_BRANCH_EXPLICIT" != "true" ||
              "$MAINFRAME_UNVERIFIED_SOURCE_ALLOWED" != "true" ]]; then
            die "A noncanonical source requires --repo URL --branch REF --allow-unverified-source on the same command"
        fi
        case "$MAINFRAME_REPO" in
            file://*|file:*|/*)
                installer_private_fixture_source_authorized || \
                    die "Local unverified sources are restricted to an authenticated private internal-test fixture"
                ;;
        esac
    elif [[ "$MAINFRAME_UNVERIFIED_SOURCE_ALLOWED" == "true" ]]; then
        die "--allow-unverified-source is valid only with explicit noncanonical --repo and --branch values"
    fi
}

validate_installer_authorizations() {
    if [[ -n "$MAINFRAME_INHERITED_FORCE" ]]; then
        die "Inherited MAINFRAME_FORCE cannot authorize replacement; unset it and pass --force on the same command"
    fi
}

quarantine_install_dir() {
    local target="$1"
    local parent base quarantine

    installer_install_root_is_safe "$target" ||
        die "Refusing to replace unsafe install directory: $target"

    parent="$(dirname "$target")"
    base="$(basename "$target")"
    quarantine="$(mktemp -d "$parent/.${base#.}.mainframe-quarantine.XXXXXX")" || \
        die "Could not create a private quarantine beside: $target"
    if ! mv -- "$target" "$quarantine/original"; then
        rmdir "$quarantine" 2>/dev/null || true
        die "Could not preserve the existing target before replacement: $target"
    fi
    printf '%s\n' "$quarantine/original"
}

repo_urls_match() {
    local left="${1%.git}"
    local right="${2%.git}"
    [[ "$left" == "$right" ]]
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================

check_dependencies() {
    info "Scanning for required components..."

    local missing=()
    local source_dir install_dir

    # The executing Bash is persisted into shell configuration. Require the
    # same reviewed locations the installed CLI can authenticate later.
    MAINFRAME_INSTALLER_BASH="$(installer_trusted_bash "${BASH:-}" 2>/dev/null || true)"
    [[ -n "$MAINFRAME_INSTALLER_BASH" ]] || \
        die "Bash must resolve to a supported system, Homebrew, Linuxbrew, MacPorts, or Nix installation"

    # Required
    MAINFRAME_INSTALLER_JQ="$(find_trusted_installer_jq || true)"
    [[ -n "$MAINFRAME_INSTALLER_JQ" ]] || missing+=("jq")

    # A verified release archive is already the installation source and never
    # needs Git. The mutable source-checkout path still does.
    source_dir="$(canonical_dir "$SCRIPT_DIR")"
    install_dir="$(canonical_dir "$MAINFRAME_INSTALL_DIR")"
    if [[ -d "$source_dir/.git" || "$source_dir" != "$install_dir" ||
          ! -f "$source_dir/bin/mainframe" ]]; then
        MAINFRAME_INSTALLER_GIT="$(find_trusted_installer_git || true)"
        [[ -n "$MAINFRAME_INSTALLER_GIT" ]] || missing+=("git")
    fi

    # Recommended (with warnings)
    command_exists rg || warn "ripgrep not found - falling back to standard grep"

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        printf "\n"
        printf "Install them with:\n"
        printf "  Ubuntu/Debian: sudo apt install ${missing[*]}\n"
        printf "  macOS:         brew install ${missing[*]}\n"
        printf "  Fedora:        sudo dnf install ${missing[*]}\n"
        exit 1
    fi

    # Check Bash version
    local bash_version="${BASH_VERSION%%(*}"
    local bash_major="${bash_version%%.*}"
    local bash_minor="${bash_version#*.}"
    bash_minor="${bash_minor%%.*}"

    if [[ "$bash_major" -lt 4 ]] || [[ "$bash_major" -eq 4 && "$bash_minor" -lt 4 ]]; then
        die "Bash 4.4+ required (found: $BASH_VERSION)"
    fi

    success "All systems go"
}

# =============================================================================
# INSTALLATION
# =============================================================================

install_mainframe() {
    local source_dir install_dir bin_dir origin current_branch cli_link current_target
    local preserved_target

    source_dir="$(canonical_dir "$SCRIPT_DIR")"
    install_dir="$(installer_canonical_path "$MAINFRAME_INSTALL_DIR")" ||
        die "Could not canonicalize MAINFRAME_INSTALL_DIR"
    installer_install_root_is_safe "$install_dir" ||
        die "Refusing unsafe MAINFRAME_INSTALL_DIR: $install_dir"
    install_dir="$(canonical_dir "$install_dir")"
    bin_dir="$(canonical_dir "$MAINFRAME_BIN_DIR")"
    MAINFRAME_INSTALL_DIR="$install_dir"
    MAINFRAME_BIN_DIR="$bin_dir"

    info "Deploying MAINFRAME to $MAINFRAME_INSTALL_DIR..."

    if [[ "$source_dir" == "$install_dir" && -f "$install_dir/bin/mainframe" ]]; then
        info "Using existing MAINFRAME source checkout"
    elif [[ -d "$install_dir/.git" ]]; then
        origin="$(installer_git -C "$install_dir" config --local --get remote.origin.url 2>/dev/null || true)"
        if [[ -n "$origin" ]] && ! repo_urls_match "$origin" "$MAINFRAME_REPO"; then
            die "Existing directory is a different git repository: $install_dir"
        fi

        current_branch="$(installer_git -C "$install_dir" branch --show-current 2>/dev/null || true)"
        if [[ -n "$(installer_git -C "$install_dir" status --porcelain 2>/dev/null)" ]]; then
            warn "Existing checkout has local changes; leaving it unchanged"
        elif [[ "$current_branch" == "$MAINFRAME_BRANCH" ]]; then
            info "Updating existing MAINFRAME checkout..."
            installer_git -C "$install_dir" pull --ff-only --quiet origin "$MAINFRAME_BRANCH" || \
                warn "Update failed; using the existing checkout"
        else
            warn "Existing checkout is on '${current_branch:-detached HEAD}'; leaving it unchanged"
        fi
    elif [[ -e "$install_dir" ]]; then
        if [[ -z "$(find "$install_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
            rmdir "$install_dir"
            installer_git clone --depth 1 --branch "$MAINFRAME_BRANCH" -- "$MAINFRAME_REPO" "$install_dir" || die "Failed to clone repository"
        elif [[ "$MAINFRAME_FORCE_REQUESTED" == "true" ]]; then
            preserved_target="$(quarantine_install_dir "$install_dir")"
            warn "Preserved existing target at $preserved_target"
            if ! installer_git clone --depth 1 --branch "$MAINFRAME_BRANCH" -- \
                "$MAINFRAME_REPO" "$install_dir"; then
                warn "Replacement failed; the original target remains at $preserved_target"
                die "Failed to clone repository"
            fi
        else
            die "Install directory exists and is not a MAINFRAME checkout: $install_dir (use --force to replace it)"
        fi
    else
        installer_git clone --depth 1 --branch "$MAINFRAME_BRANCH" -- "$MAINFRAME_REPO" "$install_dir" || die "Failed to clone repository"
    fi

    success "Repository ready"

    # A release payload is untrusted until its internal manifest succeeds.
    # Verify before creating the launcher, changing shell profiles, sourcing a
    # payload library, or executing the installed CLI.
    verify_payload_integrity

    # Create bin directory
    mkdir -p "$MAINFRAME_BIN_DIR"

    # Install the canonical rich CLI. The root mainframe script remains a
    # compatibility launcher for source-checkout users.
    cli_link="$MAINFRAME_BIN_DIR/mainframe"
    if [[ -L "$cli_link" ]]; then
        current_target="$(readlink "$cli_link")"
        if [[ "$current_target" != "$MAINFRAME_INSTALL_DIR/bin/mainframe" ]]; then
            die "CLI path is already a symlink to a different target: $cli_link -> $current_target"
        fi
    elif [[ -e "$cli_link" ]]; then
        die "CLI path already exists and is not a MAINFRAME-owned symlink: $cli_link"
    else
        ln -s "$MAINFRAME_INSTALL_DIR/bin/mainframe" "$cli_link"
    fi

    # Preserve the reviewed payload modes. Release archives already normalize
    # executable source entries to 0755; broadly adding execute bits here would
    # turn sourced libraries and evidence inputs into a different installed
    # tree than the archive that was verified.
    chmod +x "$MAINFRAME_INSTALL_DIR/mainframe" "$MAINFRAME_INSTALL_DIR/bin/mainframe"
    chmod +x "$MAINFRAME_INSTALL_DIR/uninstall.sh" 2>/dev/null || true
    chmod +x "$MAINFRAME_INSTALL_DIR/hooks/agent-gateway.sh" 2>/dev/null || true
    chmod +x "$MAINFRAME_INSTALL_DIR/hooks/dispatcher.sh" 2>/dev/null || true

    success "Operations installed"
}

# =============================================================================
# SHELL CONFIGURATION
# =============================================================================

profile_marker_state() {
    local file="$1" begin_marker="$2" end_marker="$3"

    if [[ ! -e "$file" && ! -L "$file" ]]; then
        printf 'absent\n'
        return 0
    fi
    if [[ -L "$file" || ! -f "$file" ]]; then
        printf 'unsafe\n'
        return 0
    fi

    awk -v begin="$begin_marker" -v end="$end_marker" '
        BEGIN { inside = 0; begins = 0; ends = 0; invalid = 0 }
        $0 == begin {
            begins++
            if (inside || begins > 1) invalid = 1
            inside = 1
            next
        }
        $0 == end {
            ends++
            if (!inside || ends > 1) invalid = 1
            inside = 0
            next
        }
        END {
            if (inside || begins != ends || invalid) print "malformed"
            else if (begins == 1) print "valid"
            else print "absent"
        }
    ' "$file"
}

preflight_profile_markers() {
    local file="$1" begin_marker="$2" end_marker="$3" description="$4"
    local state
    state="$(profile_marker_state "$file" "$begin_marker" "$end_marker")"
    case "$state" in
        absent|valid) ;;
        malformed)
            die "Malformed $description marker block; leaving profile unchanged: $file"
            ;;
        unsafe)
            die "Refusing non-regular or symlinked shell profile: $file"
            ;;
        *)
            die "Could not inspect shell profile: $file"
            ;;
    esac
}

preflight_managed_marker_layout() {
    local file="$1" state

    [[ -f "$file" ]] || return 0
    state="$(awk \
        -v runtime_begin="$MAINFRAME_BEGIN_MARKER" \
        -v runtime_end="$MAINFRAME_END_MARKER" \
        -v login_begin="$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
        -v login_end="$MAINFRAME_BASH_LOGIN_END_MARKER" '
        BEGIN { inside = ""; invalid = 0 }
        $0 == runtime_begin {
            if (inside != "") invalid = 1
            inside = "runtime"
            next
        }
        $0 == login_begin {
            if (inside != "") invalid = 1
            inside = "login"
            next
        }
        $0 == runtime_end {
            if (inside != "runtime") invalid = 1
            inside = ""
            next
        }
        $0 == login_end {
            if (inside != "login") invalid = 1
            inside = ""
            next
        }
        END {
            if (inside != "" || invalid) print "malformed"
            else print "valid"
        }
    ' "$file")"
    [[ "$state" == "valid" ]] || \
        die "Overlapping MAINFRAME managed marker blocks; leaving profile unchanged: $file"
}

prepare_shell_configuration() {
    local profile

    MAINFRAME_SHELL_NAME=""
    MAINFRAME_SHELL_CONFIG=""
    MAINFRAME_BASH_LOGIN_CONFIG=""
    MAINFRAME_BASH_LOGIN_PROFILES=()

    case "${SHELL:-/bin/bash}" in
        */bash)
            MAINFRAME_SHELL_NAME="bash"
            MAINFRAME_SHELL_CONFIG="$HOME/.bashrc"

            # Bash login shells read only the first existing file in this
            # precedence order. Put the narrow bridge in that effective file.
            for profile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
                if [[ -e "$profile" || -L "$profile" ]]; then
                    MAINFRAME_BASH_LOGIN_PROFILES+=("$profile")
                    if [[ -z "$MAINFRAME_BASH_LOGIN_CONFIG" ]]; then
                        MAINFRAME_BASH_LOGIN_CONFIG="$profile"
                    fi
                fi
            done
            if [[ -z "$MAINFRAME_BASH_LOGIN_CONFIG" ]]; then
                MAINFRAME_BASH_LOGIN_CONFIG="$HOME/.bash_profile"
                MAINFRAME_BASH_LOGIN_PROFILES+=("$MAINFRAME_BASH_LOGIN_CONFIG")
            fi

            preflight_profile_markers \
                "$MAINFRAME_SHELL_CONFIG" \
                "$MAINFRAME_BEGIN_MARKER" "$MAINFRAME_END_MARKER" \
                "MAINFRAME"
            preflight_profile_markers \
                "$MAINFRAME_SHELL_CONFIG" \
                "$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
                "$MAINFRAME_BASH_LOGIN_END_MARKER" \
                "MAINFRAME Bash-login"
            preflight_managed_marker_layout "$MAINFRAME_SHELL_CONFIG"
            for profile in "${MAINFRAME_BASH_LOGIN_PROFILES[@]}"; do
                # Older installers could place the canonical runtime block in
                # a login profile. A valid block is migrated; malformed blocks
                # stop the install before any repository or profile mutation.
                preflight_profile_markers \
                    "$profile" \
                    "$MAINFRAME_BEGIN_MARKER" "$MAINFRAME_END_MARKER" \
                    "MAINFRAME"
                preflight_profile_markers \
                    "$profile" \
                    "$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
                    "$MAINFRAME_BASH_LOGIN_END_MARKER" \
                    "MAINFRAME Bash-login"
                preflight_managed_marker_layout "$profile"
            done
            ;;
        */zsh)
            MAINFRAME_SHELL_NAME="zsh"
            MAINFRAME_SHELL_CONFIG="$HOME/.zshrc"
            preflight_profile_markers \
                "$MAINFRAME_SHELL_CONFIG" \
                "$MAINFRAME_BEGIN_MARKER" "$MAINFRAME_END_MARKER" \
                "MAINFRAME"
            ;;
        */fish)
            MAINFRAME_SHELL_NAME="fish"
            MAINFRAME_SHELL_CONFIG="$HOME/.config/fish/config.fish"
            preflight_profile_markers \
                "$MAINFRAME_SHELL_CONFIG" \
                "$MAINFRAME_BEGIN_MARKER" "$MAINFRAME_END_MARKER" \
                "MAINFRAME"
            ;;
        *)
            warn "Unknown shell, skipping shell configuration"
            return 0
            ;;
    esac
}

profile_mode() {
    local file="$1" mode=""
    mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
    if [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
        printf '%s\n' "$mode"
        return 0
    fi
    mode="$(stat -f '%Lp' "$file" 2>/dev/null || true)"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] && printf '%s\n' "$mode"
}

remove_valid_profile_block() {
    local file="$1" begin_marker="$2" end_marker="$3"
    local tmp mode

    [[ "$(profile_marker_state "$file" "$begin_marker" "$end_marker")" == "valid" ]] || return 0
    tmp="$(mktemp "$(dirname "$file")/.mainframe-profile.XXXXXX")"
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { inside = 1; next }
        inside && $0 == end { inside = 0; next }
        !inside { print }
    ' "$file" > "$tmp"
    mode="$(profile_mode "$file")"
    [[ -z "$mode" ]] || chmod "$mode" "$tmp"
    mv "$tmp" "$file"
}

install_profile_block() {
    local file="$1" begin_marker="$2" end_marker="$3" block_file="$4"
    local state tmp mode

    mkdir -p "$(dirname "$file")"
    if [[ ! -e "$file" ]]; then
        : > "$file"
    fi
    state="$(profile_marker_state "$file" "$begin_marker" "$end_marker")"
    [[ "$state" == "absent" || "$state" == "valid" ]] || \
        die "Shell profile changed after preflight; leaving it unchanged: $file"

    tmp="$(mktemp "$(dirname "$file")/.mainframe-profile.XXXXXX")"
    if [[ "$state" == "valid" ]]; then
        awk -v begin="$begin_marker" -v end="$end_marker" -v block_file="$block_file" '
            function emit_block(    line) {
                while ((getline line < block_file) > 0) print line
                close(block_file)
            }
            $0 == begin { emit_block(); inside = 1; next }
            inside && $0 == end { inside = 0; next }
            !inside { print }
        ' "$file" > "$tmp"
    else
        awk '1' "$file" > "$tmp"
        if [[ -s "$tmp" ]]; then
            printf '\n' >> "$tmp"
        fi
        cat "$block_file" >> "$tmp"
    fi

    if cmp -s "$file" "$tmp"; then
        rm -f -- "$tmp"
        return 0
    fi
    mode="$(profile_mode "$file")"
    [[ -z "$mode" ]] || chmod "$mode" "$tmp"
    mv "$tmp" "$file"
}

write_posix_runtime_block() {
    local shell_name="$1" output="$2"
    {
        printf '%s\n' "$MAINFRAME_BEGIN_MARKER"
        printf 'export MAINFRAME_ROOT=%q\n' "$MAINFRAME_INSTALL_DIR"
        printf 'export MAINFRAME_BASH=%q\n' "$MAINFRAME_INSTALLER_BASH"
        printf 'export MAINFRAME_AI_ENABLED=1\n'
        printf '_MAINFRAME_SHELL_BIN_DIR=%q\n' "$MAINFRAME_BIN_DIR"
        printf 'case ":${PATH:-}:" in\n'
        printf '    *":${_MAINFRAME_SHELL_BIN_DIR}:"*) ;;\n'
        printf '    *) export PATH="${_MAINFRAME_SHELL_BIN_DIR}${PATH:+:${PATH}}" ;;\n'
        printf 'esac\n'
        printf 'unset _MAINFRAME_SHELL_BIN_DIR\n'
        if [[ "$shell_name" == "bash" ]]; then
            # The login bridge uses this shell-local sentinel to avoid sourcing
            # .bashrc twice when an existing Debian/Ubuntu-style .profile has
            # already sourced it.
            printf '_MAINFRAME_BASHRC_LOADED=1\n'
        fi
        printf '[[ -f "$MAINFRAME_ROOT/completions/mainframe.%s" ]] && source "$MAINFRAME_ROOT/completions/mainframe.%s"\n' "$shell_name" "$shell_name"
        printf '%s\n' "$MAINFRAME_END_MARKER"
    } > "$output"
}

write_bash_login_block() {
    local output="$1"
    {
        printf '%s\n' "$MAINFRAME_BASH_LOGIN_BEGIN_MARKER"
        printf 'if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && [ "${_MAINFRAME_BASHRC_LOADED:-}" != "1" ]; then\n'
        printf '    . "$HOME/.bashrc"\n'
        printf 'fi\n'
        printf 'unset _MAINFRAME_BASHRC_LOADED\n'
        printf '%s\n' "$MAINFRAME_BASH_LOGIN_END_MARKER"
    } > "$output"
}

setup_shell() {
    info "Configuring shell integration..."

    local profile block_file login_block_file

    if [[ -z "$MAINFRAME_SHELL_CONFIG" ]]; then
        warn "Could not find shell configuration file"
        return 0
    fi

    if [[ "$MAINFRAME_SHELL_NAME" == "fish" ]]; then
        mkdir -p "$(dirname "$MAINFRAME_SHELL_CONFIG")"
        touch "$MAINFRAME_SHELL_CONFIG"
        if [[ "$(profile_marker_state \
            "$MAINFRAME_SHELL_CONFIG" \
            "$MAINFRAME_BEGIN_MARKER" "$MAINFRAME_END_MARKER")" == "absent" ]]; then
            {
                printf '\n# >>> MAINFRAME >>>\n'
                printf 'set -gx MAINFRAME_ROOT "%s"\n' "$MAINFRAME_INSTALL_DIR"
                printf 'set -gx MAINFRAME_BASH "%s"\n' "$MAINFRAME_INSTALLER_BASH"
                printf 'set -gx MAINFRAME_AI_ENABLED 1\n'
                printf 'set -gx PATH "%s" $PATH\n' "$MAINFRAME_BIN_DIR"
                printf '# <<< MAINFRAME <<<\n'
            } >> "$MAINFRAME_SHELL_CONFIG"
        fi
    else
        block_file="$(mktemp "${TMPDIR:-/tmp}/mainframe-runtime-block.XXXXXX")"
        write_posix_runtime_block "$MAINFRAME_SHELL_NAME" "$block_file"
        if [[ "$MAINFRAME_SHELL_NAME" == "bash" ]]; then
            # A bridge is meaningful only in a login profile. If a previously
            # managed bridge was moved into .bashrc, remove that exact valid
            # block before writing the canonical runtime block so it cannot
            # recursively source .bashrc.
            remove_valid_profile_block \
                "$MAINFRAME_SHELL_CONFIG" \
                "$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
                "$MAINFRAME_BASH_LOGIN_END_MARKER"
        fi
        install_profile_block \
            "$MAINFRAME_SHELL_CONFIG" \
            "$MAINFRAME_BEGIN_MARKER" "$MAINFRAME_END_MARKER" \
            "$block_file"
        rm -f -- "$block_file"

        if [[ "$MAINFRAME_SHELL_NAME" == "bash" ]]; then
            # Remove valid blocks previously managed in Bash login profiles.
            # This migrates the legacy full-runtime placement and moves a
            # bridge if Bash's effective login profile has changed.
            for profile in "${MAINFRAME_BASH_LOGIN_PROFILES[@]}"; do
                remove_valid_profile_block \
                    "$profile" "$MAINFRAME_BEGIN_MARKER" "$MAINFRAME_END_MARKER"
                if [[ "$profile" != "$MAINFRAME_BASH_LOGIN_CONFIG" ]]; then
                    remove_valid_profile_block \
                        "$profile" \
                        "$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
                        "$MAINFRAME_BASH_LOGIN_END_MARKER"
                fi
            done

            login_block_file="$(mktemp "${TMPDIR:-/tmp}/mainframe-login-block.XXXXXX")"
            write_bash_login_block "$login_block_file"
            install_profile_block \
                "$MAINFRAME_BASH_LOGIN_CONFIG" \
                "$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
                "$MAINFRAME_BASH_LOGIN_END_MARKER" \
                "$login_block_file"
            rm -f -- "$login_block_file"
        fi
    fi

    success "Shell configuration added to $MAINFRAME_SHELL_CONFIG"
    if [[ -n "$MAINFRAME_BASH_LOGIN_CONFIG" ]]; then
        success "Bash login bridge added to $MAINFRAME_BASH_LOGIN_CONFIG"
    fi

    # The profile block activates MAINFRAME for future shells. Keep this
    # installer on its fixed system PATH so a pre-existing file in the user
    # bin directory cannot replace post-install tools such as mkdir or cp.
    export MAINFRAME_ROOT="$MAINFRAME_INSTALL_DIR"
}

# =============================================================================
# POST-INSTALL
# =============================================================================

post_install() {
    # Create default config if it doesn't exist
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mainframe"
    mkdir -p "$config_dir"

    if [[ ! -f "$config_dir/mainframe.conf" ]] && [[ -f "$MAINFRAME_INSTALL_DIR/config/mainframe.conf.example" ]]; then
        cp "$MAINFRAME_INSTALL_DIR/config/mainframe.conf.example" "$config_dir/mainframe.conf"
        success "Configuration created at $config_dir/mainframe.conf"
    fi
}

# =============================================================================
# AI DISCOVERY SETUP
# =============================================================================

setup_ai_discovery() {
    info "Configuring AI tool discovery..."

    # Source the AI discovery library
    if [[ -f "$MAINFRAME_INSTALL_DIR/lib/ai_discovery.sh" ]]; then
        export MAINFRAME_ROOT="$MAINFRAME_INSTALL_DIR"
        source "$MAINFRAME_INSTALL_DIR/lib/ai_discovery.sh"

        # Run the full discovery setup
        mainframe_ai_discovery_setup_universal
        mainframe_ai_discovery_setup_claude
        mainframe_ai_discovery_setup_cursor
        mainframe_ai_discovery_setup_aider

        success "AI tool integration files written (see per-host paths above)"
    else
        warn "AI discovery library not found, skipping"
    fi
}

# =============================================================================
# VERIFY INSTALLATION
# =============================================================================

verify_payload_integrity() {
    local verify_mode="${MAINFRAME_VERIFY_CHECKSUMS:-auto}"

    # SHA256SUMS is a release-artifact manifest. A moving git branch can
    # legitimately differ from it, so auto mode verifies tagged checkouts and
    # non-git release archives only. Set MAINFRAME_VERIFY_CHECKSUMS=1 to force.
    if [[ -f "$MAINFRAME_INSTALL_DIR/SHA256SUMS" ]]; then
        local should_verify=false
        case "$verify_mode" in
            1|true|always) should_verify=true ;;
            0|false|never) should_verify=false ;;
            auto)
                if [[ ! -d "$MAINFRAME_INSTALL_DIR/.git" ]] || \
                   installer_git -C "$MAINFRAME_INSTALL_DIR" describe --exact-match --tags HEAD &>/dev/null; then
                    should_verify=true
                fi
                ;;
            *) die "Invalid MAINFRAME_VERIFY_CHECKSUMS value: $verify_mode" ;;
        esac

        if [[ "$should_verify" == "true" ]]; then
            info "Verifying release checksums (SHA256SUMS)..."
            if ! (cd "$MAINFRAME_INSTALL_DIR" && _verify_checksums); then
                die "Checksum verification failed - installation may be corrupted or tampered with"
            fi
            success "Checksums verified"
        else
            warn "Skipping release checksums for a moving git checkout"
        fi
    else
        case "$verify_mode" in
            0|false|never)
                warn "SHA256SUMS not found; integrity verification was explicitly disabled"
                ;;
            1|true|always)
                die "SHA256SUMS not found - refusing an unverified installation"
                ;;
            auto)
                if [[ ! -d "$MAINFRAME_INSTALL_DIR/.git" ]]; then
                    die "SHA256SUMS not found - release archive is incomplete"
                fi
                warn "SHA256SUMS not found in source checkout; skipping integrity verification"
                ;;
            *) die "Invalid MAINFRAME_VERIFY_CHECKSUMS value: $verify_mode" ;;
        esac
    fi
}

verify_installation() {
    info "Verifying deployment..."

    # Check main entry point
    if [[ ! -x "$MAINFRAME_INSTALL_DIR/bin/mainframe" ]]; then
        die "Canonical CLI not executable"
    fi
    if [[ ! -x "$MAINFRAME_BIN_DIR/mainframe" ]]; then
        die "Installed CLI link not executable"
    fi

    # Check libraries
    for lib in common.sh config.sh args.sh; do
        if [[ ! -f "$MAINFRAME_INSTALL_DIR/lib/$lib" ]]; then
            die "Library missing: $lib"
        fi
    done

    # This is the first installed-payload execution. Release archives reached
    # this point only after verify_payload_integrity accepted every manifest
    # entry; mutable source checkouts emitted an explicit skip warning.
    if ! "$MAINFRAME_BIN_DIR/mainframe" version &>/dev/null; then
        die "MAINFRAME failed to run"
    fi

    success "Deployment verified"
}

# Verify files against SHA256SUMS using whichever tool is available
_verify_checksums() {
    local sums_file="SHA256SUMS"
    local failures=0 checked=0 line hash file actual hash_tool

    if command -v sha256sum &>/dev/null; then
        hash_tool=sha256sum
    elif command -v shasum &>/dev/null; then
        hash_tool=shasum
    elif command -v openssl &>/dev/null; then
        hash_tool=openssl
    else
        printf '  No SHA-256 implementation is available\n' >&2
        return 1
    fi

    while IFS= read -r line; do
        [[ "$line" == \#* || -z "$line" ]] && continue
        if [[ ! "$line" =~ ^([0-9a-f]{64})[[:space:]][[:space:]](.+)$ ]]; then
            printf '  MALFORMED manifest entry\n' >&2
            failures=$((failures + 1))
            continue
        fi
        hash="${BASH_REMATCH[1]}"
        file="${BASH_REMATCH[2]}"

        case "$file" in
            /*|../*|*/../*|*/..|./*|*/./*|*/.)
                printf '  UNSAFE PATH: %s\n' "$file" >&2
                failures=$((failures + 1))
                continue
                ;;
        esac

        if [[ -L "$file" || ! -f "$file" ]]; then
            printf '  MISSING: %s\n' "$file" >&2
            failures=$((failures + 1))
            continue
        fi

        case "$hash_tool" in
            sha256sum) actual=$(sha256sum "$file" | cut -d' ' -f1) ;;
            shasum) actual=$(shasum -a 256 "$file" | cut -d' ' -f1) ;;
            openssl) actual=$(openssl dgst -sha256 "$file" | awk '{print $NF}') ;;
        esac
        checked=$((checked + 1))
        [[ "$actual" != "$hash" ]] && {
            printf '  MISMATCH: %s\n' "$file" >&2
            failures=$((failures + 1))
        }
    done < "$sums_file"
    printf '  %d files checked, %d failures\n' "$checked" "$failures" >&2
    [[ "$failures" -eq 0 && "$checked" -gt 0 ]]
}

# =============================================================================
# PRINT SUMMARY
# =============================================================================

print_summary() {
    printf "\n"
    cat << 'EOF'
    __  ______    _____   ________  ___    __  _________
   /  |/  /   |  /  _/ | / / ____/ / _ \  /  |/  / ____/
  / /|_/ / /| |  / //  |/ / /_    / , _/ / /|_/ / __/
 / /  / / ___ |_/ // /|  / __/   / /| | / /  / / /___
/_/  /_/_/  |_/___/_/ |_/_/     /_/ |_|/_/  /_/_____/

EOF
    printf "${GREEN}${BOLD}MAINFRAME deployed successfully!${NC}\n"
    printf "\n"
    printf "Installation directory: ${BLUE}$MAINFRAME_INSTALL_DIR${NC}\n"
    printf "Binary location:        ${BLUE}$MAINFRAME_BIN_DIR/mainframe${NC}\n"
    printf "\n"
    printf "To get started:\n"
    if [[ -n "$MAINFRAME_SHELL_CONFIG" ]]; then
        printf "  1. Restart your shell or run: ${YELLOW}source %s${NC}\n" "$MAINFRAME_SHELL_CONFIG"
    else
        printf "  1. Add ${YELLOW}%s${NC} to PATH\n" "$MAINFRAME_BIN_DIR"
    fi
    printf "  2. Verify installation:       ${YELLOW}mainframe doctor${NC}\n"
    printf "  3. Prove core mechanisms (read-only):\n"
    printf "       ${YELLOW}cd /path/to/your/project${NC}\n"
    printf "       ${YELLOW}mainframe setup --project . --proof${NC}\n"
    printf "  4. Find reviewed helpers:     ${YELLOW}mainframe search \"create json object\"${NC}\n"
    printf "\n"
    printf "${BOLD}AI Tool Integration:${NC}\n"
    if [[ "${AI_DISCOVERY_CONFIGURED:-false}" == "true" ]]; then
        printf "  Opt-in discovery files were written for the hosts listed above.\n"
        printf "  Discovery does not prove protected project hooks are loaded or trusted.\n"
    else
        printf "  No project host files were written (onboarding requires explicit consent).\n"
    fi
    printf "  Discover available shells and supported coding-agent hosts (read-only):\n"
    printf "    ${YELLOW}cd /path/to/your/project${NC}\n"
    printf "    ${YELLOW}mainframe setup --project . --proof${NC}\n"
    printf "    ${YELLOW}mainframe setup --project .${NC}\n"
    printf "  Setup never auto-selects a host or changes a project without ${YELLOW}--host${NC}.\n"
    printf "  It prints exact preview and apply commands for detected candidates.\n"
    printf "  The installer does not run setup or onboarding for you.\n"
    printf "  Success verifies the gateway and project files only; restart the host,\n"
    printf "  complete its trust review, inspect its hook UI, and run a native canary.\n"
    printf "\n"
    printf "  Check status: ${YELLOW}mainframe doctor${NC}\n"
    printf "\n"
    printf "Documentation: https://github.com/gtwatts/mainframe\n"
    printf "\n"
    printf "${BOLD}YO JOE!${NC}\n"
    printf "\n"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
MAINFRAME Installation Script
"Mainframe can make a computer do anything short of tap dance."

Usage: $0 [options]

Options:
  -h, --help          Show this help message
  -d, --dir DIR       Install directory (default: ~/.mainframe)
  -b, --bin DIR       Binary directory (default: ~/.local/bin)
  --repo URL          Explicit repository URL (default: canonical MAINFRAME)
  --branch REF        Explicit Git branch/ref (default: main)
  --allow-unverified-source
                      Consent to an explicit noncanonical --repo and --branch
  --no-shell          Skip shell configuration
  --no-claude         Deprecated no-op (AI host writes are skipped by default)
  --ai-discovery      Write AI host integration files (opt-in; default skips)
  --force             Quarantine a conflicting target, then reinstall

Environment Variables:
  MAINFRAME_INSTALL_DIR  Override install directory
  MAINFRAME_BIN_DIR      Override binary directory
  MAINFRAME_REPO / MAINFRAME_BRANCH
                         Legacy provenance selectors; noncanonical values are rejected
  MAINFRAME_FORCE        Legacy authorization variable; inherited values are rejected
  MAINFRAME_VERIFY_CHECKSUMS  auto (default), 1, or 0
EOF
}

# =============================================================================
# MAIN
# =============================================================================

validate_install_path_inputs() {
    local label value canonical_install_dir
    local LC_ALL=C

    for label in MAINFRAME_INSTALL_DIR MAINFRAME_BIN_DIR; do
        value="${!label:-}"
        [[ -n "$value" ]] || die "$label must not be empty"
        if [[ "$value" =~ [[:cntrl:]] ]]; then
            die "$label must not contain control characters"
        fi
        if [[ "$label" == "MAINFRAME_BIN_DIR" && "$value" == *:* ]]; then
            die "MAINFRAME_BIN_DIR must not contain ':' because PATH uses it as a separator"
        fi
    done

    canonical_install_dir="$(installer_canonical_path "$MAINFRAME_INSTALL_DIR")" ||
        die "Could not canonicalize MAINFRAME_INSTALL_DIR"
    installer_install_root_is_safe "$MAINFRAME_INSTALL_DIR" ||
        die "Refusing unsafe MAINFRAME_INSTALL_DIR: $canonical_install_dir"
    MAINFRAME_INSTALL_DIR="$canonical_install_dir"
}

main() {
    local skip_shell=false
    local enable_ai_discovery=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dir)
                (($# >= 2)) || die "$1 requires a directory"
                MAINFRAME_INSTALL_DIR="$2"
                shift 2
                ;;
            -b|--bin)
                (($# >= 2)) || die "$1 requires a directory"
                MAINFRAME_BIN_DIR="$2"
                shift 2
                ;;
            --repo)
                (($# >= 2)) || die "--repo requires a URL"
                [[ "$MAINFRAME_REPO_EXPLICIT" != "true" ]] || \
                    die "--repo may be specified only once"
                MAINFRAME_REPO="$2"
                MAINFRAME_REPO_EXPLICIT=true
                shift 2
                ;;
            --branch)
                (($# >= 2)) || die "--branch requires a ref"
                [[ "$MAINFRAME_BRANCH_EXPLICIT" != "true" ]] || \
                    die "--branch may be specified only once"
                MAINFRAME_BRANCH="$2"
                MAINFRAME_BRANCH_EXPLICIT=true
                shift 2
                ;;
            --allow-unverified-source)
                [[ "$MAINFRAME_UNVERIFIED_SOURCE_ALLOWED" != "true" ]] || \
                    die "--allow-unverified-source may be specified only once"
                MAINFRAME_UNVERIFIED_SOURCE_ALLOWED=true
                shift
                ;;
            --no-shell)
                skip_shell=true
                shift
                ;;
            --no-claude)
                # Deprecated compatibility flag. Claude Code configuration is
                # never changed implicitly; explicit `mainframe onboard` is
                # the supported integration workflow.
                shift
                ;;
            --ai-discovery)
                enable_ai_discovery=true
                shift
                ;;
            --no-ai-discovery)
                # Deprecated: skipping is now the default; accept silently.
                shift
                ;;
            --force)
                [[ "$MAINFRAME_FORCE_REQUESTED" != "true" ]] || \
                    die "--force may be specified only once"
                MAINFRAME_FORCE_REQUESTED=true
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    # These values are later emitted as shell-profile literals and installation
    # provenance. Reject line-breaking/control bytes before any filesystem or
    # repository mutation; printable metacharacters are escaped with printf %q.
    validate_install_path_inputs
    validate_installer_authorizations
    validate_install_source_selection

    printf "${BOLD}${BLUE}"
    cat << 'EOF'
    __  ______    _____   ________  ___    __  _________
   /  |/  /   |  /  _/ | / / ____/ / _ \  /  |/  / ____/
  / /|_/ / /| |  / //  |/ / /_    / , _/ / /|_/ / __/
 / /  / / ___ |_/ // /|  / __/   / /| | / /  / / /___
/_/  /_/_/  |_/___/_/ |_/_/     /_/ |_|/_/  /_/_____/

EOF
    printf "       GI Joe Computer Specialist - 1986\n"
    printf "${NC}\n"

    check_dependencies
    [[ "$skip_shell" == "true" ]] || prepare_shell_configuration
    install_mainframe

    [[ "$skip_shell" != "true" ]] && setup_shell
    if [[ "$enable_ai_discovery" == "true" ]]; then
        setup_ai_discovery
        AI_DISCOVERY_CONFIGURED=true
    fi

    post_install
    verify_installation
    print_summary
}

installer_reenter_original_bash_if_needed "$@"
main "$@"

        ;;
    *)
        _MAINFRAME_INSTALLER_REENTRY_BASH="${BASH:-}" \
            /bin/bash --noprofile --norc -p -- "$0" "$@"
        ;;
esac

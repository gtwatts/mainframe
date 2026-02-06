#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
# =============================================================================
# MAINFRAME/lib/tirith_pipe.sh - Pipe-to-Shell and Dotfile Security
# =============================================================================
# Description: Detects dangerous pipe-to-shell patterns, dotfile overwrites,
#              and unsafe archive extraction commands.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# PUBLIC API:
#
#   tirith_check_curl_pipe_shell CMD [SOURCE]
#     Detects: curl ... | sh/bash/sudo sh patterns
#     Returns: 0=finding, 1=clean
#
#   tirith_check_wget_pipe_shell CMD [SOURCE]
#     Detects: wget -O- ... | sh/bash patterns
#     Returns: 0=finding, 1=clean
#
#   tirith_check_pipe_to_interpreter CMD [SOURCE]
#     Detects: any source command piped to any interpreter
#     Returns: 0=finding, 1=clean
#
#   tirith_check_dotfile_overwrite CMD [SOURCE]
#     Detects: commands that write to sensitive dotfiles
#     Returns: 0=finding, 1=clean
#
#   tirith_check_archive_extract CMD [SOURCE]
#     Detects: unsafe archive extraction without safe-dir flags
#     Returns: 0=finding, 1=clean
#
#   tirith_scan_pipe CMD [SOURCE]
#     Runs all 5 checks. Returns: 0=any findings, 1=clean
#
#   tirith_safe_exec URL [DEST_DIR]
#     Downloads a script to temp, displays for inspection. Helper, not detection.
#     Returns: 0 always
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TIRITH_PIPE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TIRITH_PIPE_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

# Commands that fetch remote content
readonly _TIRITH_SOURCE_CMDS="curl|wget|fetch|scp|rsync"

# Interpreters that execute piped input
readonly _TIRITH_INTERPRETERS="sh|bash|zsh|dash|ksh|python|python3|node|perl|ruby|php"

# Sensitive dotfiles that should not be overwritten by remote content
readonly -a _TIRITH_SENSITIVE_DOTFILES=(
    ".bashrc" ".bash_profile" ".profile" ".zshrc" ".zprofile"
    ".ssh/authorized_keys" ".ssh/config" ".ssh/known_hosts"
    ".gitconfig" ".npmrc" ".pip/pip.conf" ".pypirc"
    ".aws/credentials" ".docker/config.json" ".kube/config"
    ".gnupg/" ".netrc" ".env"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Centralized logging (delegates to _mainframe_log if available)
_tirith_pipe_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "tirith_pipe" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" && "${MAINFRAME_DEBUG:-}" == "1" ]]; then
        printf '[tirith_pipe] %s: %s\n' "$level" "$*" >&2
    fi
}

# JSON-escape a string for safe embedding in JSON values
_tirith_pipe_escape() {
    local str="$1"
    if declare -F json_escape &>/dev/null; then
        json_escape "$str"
        return
    fi
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# =============================================================================
# SHARED STATE INTEGRATION
# =============================================================================
# tirith_inject.sh defines _tirith_add_finding and _tirith_init_state.
# If they are not available, provide local fallbacks that store findings
# in a simple array for the current session.

declare -ga _TIRITH_PIPE_FINDINGS=()

# Local fallback for _tirith_init_state
_tirith_pipe_init_state() {
    if declare -F _tirith_init_state &>/dev/null; then
        _tirith_init_state
    else
        _TIRITH_PIPE_FINDINGS=()
    fi
}

# Local fallback for _tirith_add_finding
# Usage: _tirith_pipe_add_finding SOURCE SEVERITY RULE_ID MESSAGE
_tirith_pipe_add_finding() {
    local source="$1"
    local severity="$2"
    local rule_id="$3"
    local message="$4"

    if declare -F _tirith_add_finding &>/dev/null; then
        _tirith_add_finding "$source" "$severity" "$rule_id" "$message"
    else
        local escaped_msg
        escaped_msg=$(_tirith_pipe_escape "$message")
        _TIRITH_PIPE_FINDINGS+=("{\"source\":\"$source\",\"severity\":\"$severity\",\"rule\":\"$rule_id\",\"message\":\"$escaped_msg\"}")
        _tirith_pipe_log "warn" "[$rule_id] ($severity) $message"
    fi
}

# Initialize shared state at load time
_tirith_pipe_init_state

# =============================================================================
# RULE 1: CurlPipeShell
# =============================================================================
# Detects: curl ... | sh, curl ... | bash, curl ... | sudo sh, etc.
# Severity: high
#
# Examples caught:
#   curl -sSL https://example.com/install.sh | bash
#   curl https://example.com/script | sudo bash -
#   curl -fsSL url | sh -s --
#
# Usage: tirith_check_curl_pipe_shell CMD [SOURCE]
# Returns: 0=finding detected, 1=clean
# =============================================================================
tirith_check_curl_pipe_shell() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # Pattern: curl (with any flags/args) piped to (optionally sudo) an interpreter
    # The regex matches:
    #   - "curl" as a word boundary
    #   - followed by any characters (flags, URL, etc.)
    #   - a pipe "|"
    #   - optional whitespace
    #   - optional "sudo" with whitespace
    #   - one of the known interpreters
    #   - either end of string, whitespace, or " -" for flags like "bash -"
    if [[ "$cmd" =~ (^|[[:space:]|;&])curl[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(${_TIRITH_INTERPRETERS})([[:space:]]|$) ]]; then
        _tirith_pipe_add_finding "$source" "high" "CurlPipeShell" \
            "Piping curl output directly to interpreter: $cmd"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 2: WgetPipeShell
# =============================================================================
# Detects: wget -O- url | bash, wget -qO- url | sh, etc.
# Severity: high
#
# wget requires -O- or -O - to output to stdout for piping to work.
#
# Examples caught:
#   wget -O- https://example.com/install.sh | bash
#   wget -qO- https://example.com/script | sh
#   wget -O - https://example.com/setup | sudo bash
#   wget --output-document=- url | sh
#
# Usage: tirith_check_wget_pipe_shell CMD [SOURCE]
# Returns: 0=finding detected, 1=clean
# =============================================================================
tirith_check_wget_pipe_shell() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # Check for wget with stdout output flags piped to an interpreter
    # Match -O-, -O -, -qO-, -qO -, --output-document=-, --output-document -
    local wget_stdout_pattern='wget[[:space:]]+.*(-[a-zA-Z]*O[[:space:]]*-|--output-document[=[:space:]]*-)'

    if [[ "$cmd" =~ (^|[[:space:]|;&])${wget_stdout_pattern}.*\|[[:space:]]*(sudo[[:space:]]+)?(${_TIRITH_INTERPRETERS})([[:space:]]|$) ]]; then
        _tirith_pipe_add_finding "$source" "high" "WgetPipeShell" \
            "Piping wget output directly to interpreter: $cmd"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 3: PipeToInterpreter
# =============================================================================
# Generic catch-all for any source command piped to any interpreter.
# Catches patterns that rules 1 and 2 miss.
# Severity: high
#
# Examples caught:
#   fetch url | ruby
#   rsync remote:/script - | python
#   scp user@host:script /dev/stdout | bash
#   curl url | env bash
#
# Usage: tirith_check_pipe_to_interpreter CMD [SOURCE]
# Returns: 0=finding detected, 1=clean
# =============================================================================
tirith_check_pipe_to_interpreter() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # Pattern: any source command followed eventually by | then interpreter
    # This is intentionally broad to catch creative circumventions
    if [[ "$cmd" =~ (^|[[:space:]|;&])(${_TIRITH_SOURCE_CMDS})[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(${_TIRITH_INTERPRETERS})([[:space:]]|$) ]]; then
        _tirith_pipe_add_finding "$source" "high" "PipeToInterpreter" \
            "Remote content piped to interpreter: $cmd"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 4: DotfileOverwrite
# =============================================================================
# Detects commands that write to sensitive dotfiles via:
#   - Output redirection: > ~/.bashrc, >> ~/.profile
#   - Download flags: curl -o ~/.ssh/authorized_keys, wget -O ~/.gitconfig
#   - File copy/move: cp /tmp/evil ~/.bashrc, mv payload ~/.env
#   - Tee: tee ~/.npmrc, tee -a ~/.bashrc
#   - Truncation: > ~/.bashrc (bare redirect)
# Severity: high
#
# Usage: tirith_check_dotfile_overwrite CMD [SOURCE]
# Returns: 0=finding detected, 1=clean
# =============================================================================
tirith_check_dotfile_overwrite() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    local found=1
    local dotfile
    local dotfile_pattern
    local home_patterns

    for dotfile in "${_TIRITH_SENSITIVE_DOTFILES[@]}"; do
        # Build patterns for each home directory reference style:
        #   ~/dotfile, $HOME/dotfile, /home/*/dotfile
        # Escape dots and slashes in the dotfile name for regex
        dotfile_pattern="${dotfile//./\\.}"
        dotfile_pattern="${dotfile_pattern//\//\\/}"

        # Build combined home path pattern
        # Matches: ~/dotfile, $HOME/dotfile, ${HOME}/dotfile, /home/*/dotfile
        home_patterns="(~|\\\$HOME|\\\$\\{HOME\\}|/home/[^/[:space:]]+)/${dotfile_pattern}"

        # Check output redirection: > or >> to the dotfile
        local redir_pattern=">+[[:space:]]*${home_patterns}"
        if [[ "$cmd" =~ $redir_pattern ]]; then
            _tirith_pipe_add_finding "$source" "high" "DotfileOverwrite" \
                "Output redirection to sensitive dotfile ${dotfile}: $cmd"
            found=0
            continue
        fi

        # Check curl -o / wget -O targeting the dotfile
        if [[ "$cmd" =~ (-o|-O|--output|--output-document)[=[:space:]]+${home_patterns} ]]; then
            _tirith_pipe_add_finding "$source" "high" "DotfileOverwrite" \
                "Download targeting sensitive dotfile ${dotfile}: $cmd"
            found=0
            continue
        fi

        # Check cp/mv/install targeting the dotfile as last argument
        if [[ "$cmd" =~ (^|[[:space:]|;&])(cp|mv|install)[[:space:]].*[[:space:]]${home_patterns}([[:space:]]|$) ]]; then
            _tirith_pipe_add_finding "$source" "high" "DotfileOverwrite" \
                "File operation targeting sensitive dotfile ${dotfile}: $cmd"
            found=0
            continue
        fi

        # Check tee targeting the dotfile
        if [[ "$cmd" =~ (^|[[:space:]|;&])tee[[:space:]]+(-a[[:space:]]+)?${home_patterns}([[:space:]]|$) ]]; then
            _tirith_pipe_add_finding "$source" "high" "DotfileOverwrite" \
                "Tee targeting sensitive dotfile ${dotfile}: $cmd"
            found=0
            continue
        fi
    done

    return "$found"
}

# =============================================================================
# RULE 5: ArchiveExtract
# =============================================================================
# Detects archive extraction that could overwrite files unsafely:
#   - tar xf without --one-top-level or -C to a safe directory
#   - unzip without -d target directory
#   - 7z x without -o output directory
#   - Archive extraction from a URL in the same pipeline
# Severity: medium
#
# Usage: tirith_check_archive_extract CMD [SOURCE]
# Returns: 0=finding detected, 1=clean
# =============================================================================
tirith_check_archive_extract() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    local found=1

    # --- tar extraction without safe directory containment ---
    # Match tar with extract flag (x) but without --one-top-level or -C
    # tar xf, tar xzf, tar xjf, tar -xf, tar -xzf, tar --extract
    if [[ "$cmd" =~ (^|[[:space:]|;&])tar[[:space:]] ]]; then
        # Check if it is an extract operation (contains 'x' flag or --extract)
        local is_extract=0
        if [[ "$cmd" =~ (^|[[:space:]|;&])tar[[:space:]]+(-[a-zA-Z]*x[a-zA-Z]*|--extract) ]]; then
            is_extract=1
        fi
        # Also match tar xf (no dash prefix)
        if [[ "$cmd" =~ (^|[[:space:]|;&])tar[[:space:]]+[a-zA-Z]*x[a-zA-Z]*[[:space:]] ]]; then
            is_extract=1
        fi

        if [[ "$is_extract" -eq 1 ]]; then
            # Check for safety flags
            local has_safe_flag=0
            if [[ "$cmd" =~ --one-top-level ]]; then
                has_safe_flag=1
            fi
            if [[ "$cmd" =~ [[:space:]]-C[[:space:]] || "$cmd" =~ --directory ]]; then
                has_safe_flag=1
            fi

            if [[ "$has_safe_flag" -eq 0 ]]; then
                _tirith_pipe_add_finding "$source" "medium" "ArchiveExtract" \
                    "tar extraction without --one-top-level or -C (unsafe path traversal): $cmd"
                found=0
            fi
        fi
    fi

    # --- unzip without -d target ---
    if [[ "$cmd" =~ (^|[[:space:]|;&])unzip[[:space:]] ]]; then
        if [[ ! "$cmd" =~ [[:space:]]-d[[:space:]] ]]; then
            _tirith_pipe_add_finding "$source" "medium" "ArchiveExtract" \
                "unzip without -d target directory (extracts to cwd): $cmd"
            found=0
        fi
    fi

    # --- 7z extraction without -o output ---
    if [[ "$cmd" =~ (^|[[:space:]|;&])7z[[:space:]]+[xe][[:space:]] ]]; then
        if [[ ! "$cmd" =~ [[:space:]]-o ]]; then
            _tirith_pipe_add_finding "$source" "medium" "ArchiveExtract" \
                "7z extraction without -o output directory: $cmd"
            found=0
        fi
    fi

    # --- Archive extraction from a URL in a pipeline ---
    # e.g., curl url | tar xz, wget -O- url | tar xf -
    if [[ "$cmd" =~ (${_TIRITH_SOURCE_CMDS})[[:space:]].*\|.*[[:space:]](tar|unzip|7z|gunzip|bunzip2)[[:space:]] ]]; then
        _tirith_pipe_add_finding "$source" "medium" "ArchiveExtract" \
            "Archive extraction from remote URL in pipeline: $cmd"
        found=0
    fi

    return "$found"
}

# =============================================================================
# UTILITY: tirith_scan_pipe
# =============================================================================
# Runs all 5 detection rules on a command string.
#
# Usage: tirith_scan_pipe CMD [SOURCE]
# Returns: 0=any findings detected, 1=clean
# =============================================================================
tirith_scan_pipe() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    local found=1

    tirith_check_curl_pipe_shell "$cmd" "$source" && found=0
    tirith_check_wget_pipe_shell "$cmd" "$source" && found=0
    tirith_check_pipe_to_interpreter "$cmd" "$source" && found=0
    tirith_check_dotfile_overwrite "$cmd" "$source" && found=0
    tirith_check_archive_extract "$cmd" "$source" && found=0

    return "$found"
}

# =============================================================================
# UTILITY: tirith_safe_exec
# =============================================================================
# Downloads a remote script to a temporary file and displays it for
# human inspection before any execution. The caller decides whether
# to execute the downloaded script.
#
# Usage: tirith_safe_exec URL [DEST_DIR]
# Returns: 0 (always; this is a helper, not a detection function)
#
# Prints the temp file path to stdout so the caller can reference it:
#   local script_path
#   script_path=$(tirith_safe_exec "https://example.com/install.sh")
# =============================================================================
tirith_safe_exec() {
    local url="$1"
    local dest_dir="${2:-${TMPDIR:-/tmp}}"
    local max_preview_lines=50

    if [[ -z "$url" ]]; then
        _tirith_pipe_log "error" "tirith_safe_exec: URL required"
        return 0
    fi

    # Determine download tool
    local download_cmd=""
    if command -v curl &>/dev/null; then
        download_cmd="curl"
    elif command -v wget &>/dev/null; then
        download_cmd="wget"
    else
        _tirith_pipe_log "error" "tirith_safe_exec: neither curl nor wget found"
        printf ''
        return 0
    fi

    # Create temp file for the download
    local tmp_script
    tmp_script=$(mktemp "${dest_dir}/tirith_safe_exec.XXXXXX") || {
        _tirith_pipe_log "error" "tirith_safe_exec: failed to create temp file in ${dest_dir}"
        printf ''
        return 0
    }

    # Download the script
    _tirith_pipe_log "info" "Downloading $url to $tmp_script"
    local dl_rc=0
    case "$download_cmd" in
        curl)
            curl -fsSL --max-time 30 -o "$tmp_script" "$url" 2>/dev/null || dl_rc=$?
            ;;
        wget)
            wget -q --timeout=30 -O "$tmp_script" "$url" 2>/dev/null || dl_rc=$?
            ;;
    esac

    if [[ "$dl_rc" -ne 0 ]]; then
        _tirith_pipe_log "error" "tirith_safe_exec: download failed (exit $dl_rc): $url"
        rm -f "$tmp_script" 2>/dev/null
        printf ''
        return 0
    fi

    # Display warning header and preview
    {
        printf '\n'
        printf '=%.0s' {1..72}
        printf '\n'
        printf '  TIRITH SAFE EXEC - Script Preview\n'
        printf '=%.0s' {1..72}
        printf '\n'
        printf '  Source:    %s\n' "$url"
        printf '  Downloaded to: %s\n' "$tmp_script"
        printf '  Size:     %s bytes\n' "$(wc -c < "$tmp_script" 2>/dev/null || echo "unknown")"

        local total_lines
        total_lines=$(wc -l < "$tmp_script" 2>/dev/null || echo "0")
        printf '  Lines:    %s\n' "$total_lines"

        printf '=%.0s' {1..72}
        printf '\n'
        printf '  WARNING: Review the script below before executing.\n'
        printf '  DO NOT pipe remote scripts directly to a shell interpreter.\n'
        printf '=%.0s' {1..72}
        printf '\n\n'

        # Display first N lines with line numbers
        head -n "$max_preview_lines" "$tmp_script" | cat -n

        if [[ "$total_lines" -gt "$max_preview_lines" ]]; then
            printf '\n  ... (%d more lines not shown) ...\n' "$((total_lines - max_preview_lines))"
        fi

        printf '\n'
        printf '=%.0s' {1..72}
        printf '\n'
        printf '  To execute: bash %s\n' "$tmp_script"
        printf '  To delete:  rm %s\n' "$tmp_script"
        printf '=%.0s' {1..72}
        printf '\n'
    } >&2

    # Return the temp file path on stdout
    printf '%s' "$tmp_script"
    return 0
}

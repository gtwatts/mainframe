#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Script Debugging Helper
# =============================================================================
# Description: Debug bash scripts with syntax check, verbose mode, and analysis
# Category:    debug
# WOW Factor:  9/10
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
#
# Provides comprehensive script debugging:
# - Syntax validation (dry-run)
# - Verbose execution with trace
# - ShellCheck integration
# - Error analysis
# - Performance profiling
#
# Usage:
#   mainframe debug-script check script.sh
#   mainframe debug-script run script.sh
#   mainframe debug-script lint script.sh
#   mainframe debug-script profile script.sh
#
# =============================================================================

set -euo pipefail

# Source MAINFRAME libraries
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="debug-script"
readonly SCRIPT_VERSION="1.0.0"

# =============================================================================
# SYNTAX VALIDATION
# =============================================================================

check_syntax() {
    local script="$1"

    log_info "Checking syntax: $script"

    # Verify file exists
    if [[ ! -f "$script" ]]; then
        log_error "Script not found: $script"
        return 1
    fi

    # Run bash syntax check
    if bash -n "$script" 2>&1; then
        success "Syntax check passed"
        return 0
    else
        log_error "Syntax check failed"
        return 1
    fi
}

# =============================================================================
# VERBOSE EXECUTION
# =============================================================================

run_verbose() {
    local script="$1"
    shift
    local script_args=("$@")

    log_info "Running with verbose trace: $script"

    # Verify file exists
    if [[ ! -f "$script" ]]; then
        log_error "Script not found: $script"
        return 1
    fi

    # First do a syntax check
    if ! bash -n "$script" 2>/dev/null; then
        log_error "Syntax errors found, run 'debug-script check' first"
        return 1
    fi

    echo ""
    echo "${CLR_CYAN}=== BEGIN TRACE ===${CLR_RESET}"
    echo ""

    # Run with trace enabled
    bash -x "$script" "${script_args[@]}" 2>&1 | while IFS= read -r line; do
        if [[ "$line" == "+"* ]]; then
            # Trace line (command being executed)
            echo "${CLR_DIM}$line${CLR_RESET}"
        else
            # Regular output
            echo "$line"
        fi
    done
    local exit_code=${PIPESTATUS[0]}

    echo ""
    echo "${CLR_CYAN}=== END TRACE ===${CLR_RESET}"
    echo ""

    if [[ $exit_code -eq 0 ]]; then
        success "Script completed successfully"
    else
        log_error "Script exited with code: $exit_code"
    fi

    return $exit_code
}

# =============================================================================
# SHELLCHECK INTEGRATION
# =============================================================================

lint_script() {
    local script="$1"

    log_info "Linting script: $script"

    # Verify file exists
    if [[ ! -f "$script" ]]; then
        log_error "Script not found: $script"
        return 1
    fi

    # Check if shellcheck is available
    if ! command -v shellcheck &>/dev/null; then
        log_warn "shellcheck not installed, using basic checks only"

        # Basic checks
        local issues=0

        # Check for common issues
        echo ""
        echo "${CLR_BOLD}Basic lint checks:${CLR_RESET}"
        echo ""

        # Check for unquoted variables
        if grep -n '\$[a-zA-Z_][a-zA-Z_0-9]*[^}"]' "$script" 2>/dev/null | grep -v '^\s*#' | head -5; then
            echo "${CLR_YELLOW}  [WARN] Potentially unquoted variables${CLR_RESET}"
            issues=$((issues + 1))
        fi

        # Check for backticks (should use $())
        if grep -n '`' "$script" 2>/dev/null | grep -v '^\s*#' | head -5; then
            echo "${CLR_YELLOW}  [WARN] Use \$() instead of backticks${CLR_RESET}"
            issues=$((issues + 1))
        fi

        # Check for == in test (should use = for POSIX)
        if grep -n '\[ .*==.*\]' "$script" 2>/dev/null | grep -v '^\s*#' | head -5; then
            echo "${CLR_YELLOW}  [WARN] Use = instead of == in [ ] tests${CLR_RESET}"
            issues=$((issues + 1))
        fi

        # Check for missing shebang
        if ! head -1 "$script" | grep -q '^#!'; then
            echo "${CLR_YELLOW}  [WARN] Missing shebang line${CLR_RESET}"
            issues=$((issues + 1))
        fi

        echo ""
        if [[ $issues -eq 0 ]]; then
            success "No issues found (basic checks)"
        else
            log_warn "Found $issues potential issues"
        fi

        echo ""
        echo "${CLR_DIM}Tip: Install shellcheck for comprehensive linting:${CLR_RESET}"
        echo "${CLR_DIM}  apt install shellcheck  # Debian/Ubuntu${CLR_RESET}"
        echo "${CLR_DIM}  brew install shellcheck # macOS${CLR_RESET}"

        return 0
    fi

    # Run shellcheck
    echo ""
    if shellcheck -f tty "$script"; then
        success "No issues found"
        return 0
    else
        log_warn "Issues found (see above)"
        return 1
    fi
}

# =============================================================================
# PERFORMANCE PROFILING
# =============================================================================

profile_script() {
    local script="$1"
    shift
    local script_args=("$@")

    log_info "Profiling script: $script"

    # Verify file exists
    if [[ ! -f "$script" ]]; then
        log_error "Script not found: $script"
        return 1
    fi

    local temp_trace
    temp_trace=$(mktemp)
    trap "rm -f '$temp_trace'" RETURN

    # Enable timing in PS4
    export PS4='+ $(date +%s.%N) ${BASH_SOURCE}:${LINENO}: '

    # Run with timing
    local start_time
    start_time=$(date +%s.%N)

    bash -x "$script" "${script_args[@]}" 2>"$temp_trace"
    local exit_code=$?

    local end_time
    end_time=$(date +%s.%N)

    local total_time
    total_time=$(echo "$end_time - $start_time" | bc)

    echo ""
    echo "${CLR_BOLD}=== Profile Results ===${CLR_RESET}"
    echo ""
    echo "Total execution time: ${total_time}s"
    echo "Exit code: $exit_code"
    echo ""

    # Analyze slowest commands
    if [[ -s "$temp_trace" ]]; then
        echo "${CLR_BOLD}Top 10 slowest operations:${CLR_RESET}"
        echo ""

        # Parse trace and calculate durations
        awk '
        /^\+ [0-9]+\.[0-9]+/ {
            time = $2
            if (prev_time != "") {
                duration = time - prev_time
                prev_cmd = $0
                sub(/^\+ [0-9]+\.[0-9]+ /, "", prev_cmd)
                if (duration > 0.001) {
                    printf "%.3fs  %s\n", duration, prev_cmd
                }
            }
            prev_time = time
        }
        ' "$temp_trace" | sort -rn | head -10

        echo ""
    fi

    return $exit_code
}

# =============================================================================
# ERROR ANALYSIS
# =============================================================================

analyze_error() {
    local script="$1"
    local error_output="$2"

    log_info "Analyzing errors in: $script"

    echo ""
    echo "${CLR_BOLD}=== Error Analysis ===${CLR_RESET}"
    echo ""

    # Common error patterns and suggestions
    if echo "$error_output" | grep -qi "command not found"; then
        local cmd
        cmd=$(echo "$error_output" | grep -i "command not found" | awk -F: '{print $1}')
        echo "${CLR_RED}Command not found: $cmd${CLR_RESET}"
        echo ""
        echo "Suggestions:"
        echo "  1. Check if the command is installed: which $cmd"
        echo "  2. Check PATH: echo \$PATH"
        echo "  3. Install the missing package"
        echo ""
    fi

    if echo "$error_output" | grep -qi "permission denied"; then
        echo "${CLR_RED}Permission denied${CLR_RESET}"
        echo ""
        echo "Suggestions:"
        echo "  1. Check file permissions: ls -la"
        echo "  2. Make script executable: chmod +x script.sh"
        echo "  3. Check directory permissions"
        echo ""
    fi

    if echo "$error_output" | grep -qi "no such file or directory"; then
        echo "${CLR_RED}File or directory not found${CLR_RESET}"
        echo ""
        echo "Suggestions:"
        echo "  1. Check if path exists: ls -la /path/to/file"
        echo "  2. Check for typos in the path"
        echo "  3. Use quotes for paths with spaces"
        echo ""
    fi

    if echo "$error_output" | grep -qi "syntax error"; then
        echo "${CLR_RED}Syntax error detected${CLR_RESET}"
        echo ""
        echo "Suggestions:"
        echo "  1. Run syntax check: bash -n script.sh"
        echo "  2. Check for missing quotes or brackets"
        echo "  3. Run linter: mainframe debug-script lint script.sh"
        echo ""
    fi

    if echo "$error_output" | grep -qi "unbound variable"; then
        local var
        var=$(echo "$error_output" | grep -i "unbound variable" | awk '{print $NF}')
        echo "${CLR_RED}Unbound variable: $var${CLR_RESET}"
        echo ""
        echo "Suggestions:"
        echo "  1. Set a default: \${${var}:-default}"
        echo "  2. Check variable is assigned before use"
        echo "  3. Remove 'set -u' if intentional"
        echo ""
    fi
}

# =============================================================================
# STEP-THROUGH DEBUGGER
# =============================================================================

step_through() {
    local script="$1"
    shift
    local script_args=("$@")

    log_info "Step-through debugging: $script"
    echo ""
    echo "${CLR_YELLOW}Press ENTER to execute each command, 'q' to quit${CLR_RESET}"
    echo ""

    # Create temp file with debug wrapper
    local temp_script
    temp_script=$(mktemp)
    trap "rm -f '$temp_script'" RETURN

    # Add step-through wrapper to each command
    awk '
    /^#!/ { print; next }
    /^#/  { print; next }
    /^$/  { print; next }
    {
        print "echo \"" NR ": " $0 "\" >&2"
        print "read -p \"[Step " NR "] Press Enter or q to quit: \" __step"
        print "[[ \"$__step\" == \"q\" ]] && exit 0"
        print $0
    }
    ' "$script" > "$temp_script"

    bash "$temp_script" "${script_args[@]}"
}

# =============================================================================
# MAIN
# =============================================================================

show_help() {
    cat << EOF
${CLR_BOLD}$SCRIPT_NAME${CLR_RESET} - Script Debugging Helper

${CLR_BOLD}Usage:${CLR_RESET}
  mainframe $SCRIPT_NAME <command> <script> [args...]

${CLR_BOLD}Commands:${CLR_RESET}
  check       Syntax validation (bash -n)
  run         Verbose execution with trace (bash -x)
  lint        Static analysis with shellcheck
  profile     Performance profiling with timing
  analyze     Analyze error output
  step        Step-through debugger

${CLR_BOLD}Examples:${CLR_RESET}
  # Check syntax
  mainframe $SCRIPT_NAME check myscript.sh

  # Run with verbose trace
  mainframe $SCRIPT_NAME run myscript.sh arg1 arg2

  # Lint for common issues
  mainframe $SCRIPT_NAME lint myscript.sh

  # Profile performance
  mainframe $SCRIPT_NAME profile myscript.sh

  # Step through execution
  mainframe $SCRIPT_NAME step myscript.sh

${CLR_BOLD}Tips:${CLR_RESET}
  - Always run 'check' before 'run' to catch syntax errors
  - Use 'lint' to find potential bugs before they happen
  - Use 'profile' to identify slow commands
  - Install shellcheck for better linting: apt install shellcheck

${CLR_DIM}YO JOE!${CLR_RESET}
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        check|syntax|validate)
            if [[ $# -lt 1 ]]; then
                die "$EXIT_USAGE" "Missing script argument"
            fi
            check_syntax "$@"
            ;;
        run|trace|verbose)
            if [[ $# -lt 1 ]]; then
                die "$EXIT_USAGE" "Missing script argument"
            fi
            run_verbose "$@"
            ;;
        lint|shellcheck|analyze-static)
            if [[ $# -lt 1 ]]; then
                die "$EXIT_USAGE" "Missing script argument"
            fi
            lint_script "$@"
            ;;
        profile|time|perf)
            if [[ $# -lt 1 ]]; then
                die "$EXIT_USAGE" "Missing script argument"
            fi
            profile_script "$@"
            ;;
        analyze|error)
            if [[ $# -lt 2 ]]; then
                die "$EXIT_USAGE" "Usage: analyze <script> <error_output>"
            fi
            analyze_error "$@"
            ;;
        step|debug|step-through)
            if [[ $# -lt 1 ]]; then
                die "$EXIT_USAGE" "Missing script argument"
            fi
            step_through "$@"
            ;;
        -h|--help)
            show_help
            ;;
        *)
            die "$EXIT_USAGE" "Unknown command: $command"
            ;;
    esac
}

main "$@"

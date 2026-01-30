#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/intent.sh - Intent Verification Layer
# =============================================================================
# Description: Classify commands by risk level and verify intent before execution.
#              Provides safety layer for AI agents with static analysis only.
# Version: 1.0.0
# Security: NO execution of commands being analyzed - static analysis only
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_INTENT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_INTENT_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

# Risk levels (returned by intent_classify)
readonly INTENT_RISK_SAFE=0        # Read-only, reversible
readonly INTENT_RISK_LOW=1         # Minor side effects, easily reversible
readonly INTENT_RISK_MEDIUM=2      # Moderate side effects, recoverable
readonly INTENT_RISK_HIGH=3        # Significant changes, hard to reverse
readonly INTENT_RISK_CRITICAL=4    # Destructive, irreversible, privileged

# Risk labels for human-readable output
declare -gA _INTENT_RISK_LABELS=(
    [0]="safe" [1]="low" [2]="medium" [3]="high" [4]="critical"
)

# =============================================================================
# CONFIGURATION
# =============================================================================

# Strict mode requires explicit approval for medium+ risk
MAINFRAME_INTENT_STRICT="${MAINFRAME_INTENT_STRICT:-0}"

# Path to custom rules file (JSON)
MAINFRAME_INTENT_RULES="${MAINFRAME_INTENT_RULES:-${HOME}/.mainframe/intent_rules.json}"

# Blocked commands (comma-separated patterns)
MAINFRAME_INTENT_BLOCKED="${MAINFRAME_INTENT_BLOCKED:-}"

# =============================================================================
# PATTERN DATABASES
# =============================================================================

# Critical patterns (risk level 4) - Destructive, irreversible operations
declare -ga _INTENT_CRITICAL_PATTERNS=(
    # Filesystem destruction
    'rm[[:space:]]+-rf[[:space:]]+/'
    'rm[[:space:]]+-rf[[:space:]]+/\*'
    'rm[[:space:]]+-fr[[:space:]]+/'
    'rm[[:space:]]+-rf[[:space:]]+\*'
    'rm[[:space:]]+-rf[[:space:]]+~'
    'rm[[:space:]]+-rf[[:space:]]+\$HOME'
    'rm[[:space:]]+-rf[[:space:]]+\${HOME}'
    # Disk overwrite
    'dd[[:space:]]+.*if=/dev/zero[[:space:]]+of=/dev/'
    'dd[[:space:]]+.*of=/dev/[hs]d'
    ':>[[:space:]]*/dev/'
    # Filesystem formatting
    'mkfs\.'
    'wipefs'
    # Recursive permission disasters
    'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
    'chmod[[:space:]]+777[[:space:]]+/'
    'chown[[:space:]]+-R[[:space:]]+.*[[:space:]]+/'
    # Boot/system manipulation
    'rm[[:space:]].*-rf[[:space:]]+/boot'
    'rm[[:space:]].*-rf[[:space:]]+/etc'
    # Fork bombs
    ':\(\)[[:space:]]*{[[:space:]]*:|:&[[:space:]]*}'
    '\(\)[[:space:]]*{[[:space:]]*\|[[:space:]]*&'
    # Remote code execution patterns
    'curl[[:space:]].*\|[[:space:]]*bash'
    'curl[[:space:]].*\|[[:space:]]*sh'
    'wget[[:space:]].*\|[[:space:]]*bash'
    'wget[[:space:]].*\|[[:space:]]*sh'
    # Credential access
    'cat[[:space:]].*(/etc/shadow|/etc/passwd)'
    # Reverse shell patterns
    'nc[[:space:]]+-e'
    'bash[[:space:]]+-i[[:space:]]+>&'
)

# High risk patterns (risk level 3) - Significant changes, hard to reverse
declare -ga _INTENT_HIGH_PATTERNS=(
    # Recursive deletion
    'rm[[:space:]]+-rf'
    'rm[[:space:]]+-r[^f]'
    'rm[[:space:]]+-fr'
    # Privilege escalation
    'sudo[[:space:]]+'
    'su[[:space:]]+-'
    'doas[[:space:]]+'
    # Recursive permission changes
    'chmod[[:space:]]+-R'
    'chown[[:space:]]+-R'
    # Process termination
    'kill[[:space:]]+-9'
    'kill[[:space:]]+-SIGKILL'
    'killall'
    'pkill[[:space:]]+-9'
    # Service disruption
    'systemctl[[:space:]]+stop'
    'systemctl[[:space:]]+disable'
    'service[[:space:]]+.*[[:space:]]+stop'
    # SSH key operations
    '\.ssh/'
    'ssh-keygen[[:space:]]+-f'
    # Environment manipulation
    'export[[:space:]]+PATH='
    'unset[[:space:]]+PATH'
    # History/log tampering
    'history[[:space:]]+-c'
    '>[[:space:]]*/var/log'
    'shred[[:space:]].*log'
)

# Medium risk patterns (risk level 2) - Moderate side effects
declare -ga _INTENT_MEDIUM_PATTERNS=(
    # File operations
    'rm[[:space:]]+'
    'mv[[:space:]]+'
    'truncate'
    # In-place editing
    'sed[[:space:]]+-i'
    'perl[[:space:]]+-i'
    # Permission changes
    'chmod[[:space:]]+'
    'chown[[:space:]]+'
    # Output redirection (overwrite)
    '>[[:space:]]+[^|>]'
    # Package management
    'apt[[:space:]]+remove'
    'apt[[:space:]]+purge'
    'apt-get[[:space:]]+remove'
    'yum[[:space:]]+remove'
    'dnf[[:space:]]+remove'
    'pacman[[:space:]]+-R'
    'pip[[:space:]]+uninstall'
    'npm[[:space:]]+uninstall'
    # Git destructive operations
    'git[[:space:]]+push[[:space:]]+-f'
    'git[[:space:]]+push[[:space:]]+--force'
    'git[[:space:]]+reset[[:space:]]+--hard'
    'git[[:space:]]+clean[[:space:]]+-fd'
)

# Safe patterns (risk level 0) - Read-only operations
declare -ga _INTENT_SAFE_PATTERNS=(
    '^cat[[:space:]]+'
    '^ls[[:space:]]+'
    '^head[[:space:]]+'
    '^tail[[:space:]]+'
    '^grep[[:space:]]+'
    '^find[[:space:]]+'
    '^echo[[:space:]]+'
    '^printf[[:space:]]+'
    '^pwd[[:space:]]*$'
    '^whoami[[:space:]]*$'
    '^date[[:space:]]'
    '^file[[:space:]]+'
    '^stat[[:space:]]+'
    '^wc[[:space:]]+'
    '^du[[:space:]]+'
    '^df[[:space:]]+'
    '^which[[:space:]]+'
    '^type[[:space:]]+'
    '^env[[:space:]]*$'
    '^printenv'
)

# Obfuscation patterns - Commands trying to hide their intent
declare -ga _INTENT_OBFUSCATION_PATTERNS=(
    # Base64 encoding
    'base64[[:space:]]+-d'
    'base64[[:space:]]+--decode'
    # Hex encoding
    'xxd[[:space:]]+-r'
    'printf[[:space:]]+.*\\\\x'
    # Variable expansion tricks
    '\$\{[^}]*:-'
    '\$\{[^}]*:+'
    '\$\{[^}]*::'
    # Eval/exec wrappers
    'eval[[:space:]]+'
    'exec[[:space:]]+'
    '\$\('
    '\`'
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape string for JSON output
_intent_escape_json() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')   result+='\"' ;;
            '\')   result+='\\' ;;
            $'\b') result+='\b' ;;
            $'\f') result+='\f' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# Build JSON array from bash array
_intent_array_to_json() {
    local first=true
    printf '['
    for item in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "$(_intent_escape_json "$item")"
    done
    printf ']'
}

# Check if command matches any pattern in array
# Usage: _intent_matches_patterns "command" pattern_array_name
_intent_matches_patterns() {
    local cmd="$1"
    local -n patterns_ref="$2"

    local pattern
    for pattern in "${patterns_ref[@]}"; do
        [[ -z "$pattern" ]] && continue
        if [[ "$cmd" =~ $pattern ]]; then
            printf '%s' "$pattern"
            return 0
        fi
    done
    return 1
}

# Load custom rules from JSON file if it exists
_intent_load_custom_rules() {
    [[ ! -f "$MAINFRAME_INTENT_RULES" ]] && return 0

    # Verify file permissions (should not be world-writable)
    local perms
    perms=$(stat -c "%a" "$MAINFRAME_INTENT_RULES" 2>/dev/null)
    if [[ "$perms" =~ [2367]$ ]]; then
        printf '{"warning":"intent rules file is world-writable"}\n' >&2
        return 1
    fi

    # Parse custom rules (simple JSON parsing for blocked patterns)
    # Full implementation would use jq or similar
    return 0
}

# =============================================================================
# PUBLIC API
# =============================================================================

# intent_classify - Classify a command by risk level
# @description Analyze command string and determine risk level (0-4)
# @pre        None
# @post       None (static analysis only, no execution)
# @idempotent Yes
# @param      $1 command - Full command string to classify
# @param      --json - Output as JSON object
# @stdout     Risk level and classification details
# @return     Risk level (0-4)
#
# Usage: risk=$(intent_classify "rm -rf /tmp/cache")
# Usage: intent_classify "chmod 777 /etc/passwd" --json
intent_classify() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local risk=$INTENT_RISK_LOW
    local -a reasons=()
    local -a suggestions=()
    local matched_pattern=""

    # Empty command check
    if [[ -z "$command" ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"error":"empty command","risk":%d,"risk_label":"low"}\n' "$INTENT_RISK_LOW"
        fi
        return "$INTENT_RISK_LOW"
    fi

    # Check against blocked commands first
    if [[ -n "$MAINFRAME_INTENT_BLOCKED" ]]; then
        local IFS=','
        local blocked
        for blocked in $MAINFRAME_INTENT_BLOCKED; do
            blocked="${blocked#"${blocked%%[![:space:]]*}"}"
            blocked="${blocked%"${blocked##*[![:space:]]}"}"
            [[ -z "$blocked" ]] && continue
            if [[ "$command" =~ $blocked ]]; then
                risk=$INTENT_RISK_CRITICAL
                reasons+=("matches blocked command pattern")
            fi
        done
    fi

    # Check for obfuscation attempts
    if matched_pattern=$(_intent_matches_patterns "$command" _INTENT_OBFUSCATION_PATTERNS); then
        risk=$INTENT_RISK_CRITICAL
        reasons+=("contains obfuscation pattern: $matched_pattern")
        suggestions+=("review command manually for hidden intent")
    fi

    # Check critical patterns
    if [[ $risk -lt $INTENT_RISK_CRITICAL ]]; then
        if matched_pattern=$(_intent_matches_patterns "$command" _INTENT_CRITICAL_PATTERNS); then
            risk=$INTENT_RISK_CRITICAL
            reasons+=("matches critical pattern: $matched_pattern")
            suggestions+=("this command could cause irreversible damage")
        fi
    fi

    # Check high patterns (only if not already critical)
    if [[ $risk -lt $INTENT_RISK_HIGH ]]; then
        if matched_pattern=$(_intent_matches_patterns "$command" _INTENT_HIGH_PATTERNS); then
            risk=$INTENT_RISK_HIGH
            reasons+=("matches high-risk pattern: $matched_pattern")
            suggestions+=("consider using safer alternatives")
        fi
    fi

    # Check medium patterns
    if [[ $risk -lt $INTENT_RISK_MEDIUM ]]; then
        if matched_pattern=$(_intent_matches_patterns "$command" _INTENT_MEDIUM_PATTERNS); then
            risk=$INTENT_RISK_MEDIUM
            reasons+=("matches medium-risk pattern: $matched_pattern")
        fi
    fi

    # Check safe patterns (can override to SAFE level)
    if [[ $risk -le $INTENT_RISK_LOW ]]; then
        if _intent_matches_patterns "$command" _INTENT_SAFE_PATTERNS >/dev/null; then
            risk=$INTENT_RISK_SAFE
            reasons=("read-only operation")
        fi
    fi

    # Output result
    if [[ $json_output -eq 1 ]]; then
        local escaped_cmd
        escaped_cmd=$(_intent_escape_json "$command")
        local reasons_json suggestions_json
        reasons_json=$(_intent_array_to_json "${reasons[@]}")
        suggestions_json=$(_intent_array_to_json "${suggestions[@]}")
        printf '{"command":"%s","risk":%d,"risk_label":"%s","reasons":%s,"suggestions":%s}\n' \
            "$escaped_cmd" "$risk" "${_INTENT_RISK_LABELS[$risk]}" "$reasons_json" "$suggestions_json"
    else
        printf '%s\n' "${_INTENT_RISK_LABELS[$risk]}"
    fi

    return "$risk"
}

# intent_verify - Verify command safety with declared intent and path constraints
# @description Check if command matches declared intent and respects path boundaries
# @pre        None
# @post       None (verification only)
# @idempotent Yes
# @param      $1 declared_intent - What the command is supposed to do
# @param      $2 command - Actual command to verify
# @param      --strict - Fail if intent doesn't clearly match
# @param      --base-path - Allowed base path for operations
# @param      --json - Output as JSON
# @stdout     Verification result with confidence score
# @return     0 if verified, 1 if mismatch, 2 if uncertain
#
# Usage: intent_verify "delete temp files" "rm -rf /tmp/cache"
# Usage: intent_verify "delete old logs" "rm -rf /var/log" --strict --base-path /tmp
intent_verify() {
    local declared_intent="$1"
    local command="$2"
    shift 2

    local strict=0 json_output=0 base_path=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strict) strict=1; shift ;;
            --json) json_output=1; shift ;;
            --base-path) base_path="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local intent_lower="${declared_intent,,}"
    local cmd_lower="${command,,}"
    local verified="true"
    local confidence="0.5"
    local -a warnings=()
    local analysis=""

    # Check for clear intent/command mismatches
    if [[ "$intent_lower" =~ (read|view|show|list|display) ]] && \
       [[ "$cmd_lower" =~ (rm|delete|remove|truncate) ]]; then
        verified="false"
        confidence="0.1"
        warnings+=("MISMATCH: read intent with destructive command")
        analysis="declared intent suggests read-only operation but command is destructive"
    elif [[ "$intent_lower" =~ (delete|remove|clean) ]] && [[ "$cmd_lower" =~ rm[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (copy|backup|duplicate) ]] && [[ "$cmd_lower" =~ cp[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (move|rename) ]] && [[ "$cmd_lower" =~ mv[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (create|make|mkdir) ]] && [[ "$cmd_lower" =~ (mkdir|touch)[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (edit|modify|change|update) ]] && [[ "$cmd_lower" =~ (sed|vim|nano|edit) ]]; then
        confidence="0.85"
        analysis="intent likely matches command operation"
    else
        confidence="0.5"
        warnings+=("intent keywords do not clearly match command")
        analysis="unable to confirm intent matches command"
    fi

    # Path boundary validation if base_path specified
    if [[ -n "$base_path" ]]; then
        # Extract paths from command (simple heuristic)
        local -a cmd_paths=()
        local word
        for word in $command; do
            if [[ "$word" == /* ]]; then
                cmd_paths+=("$word")
            fi
        done

        # Check each path against base_path
        for word in "${cmd_paths[@]}"; do
            # Use validate_path_safe if available
            if declare -f validate_path_safe &>/dev/null; then
                if ! validate_path_safe "$word" "$base_path" 2>/dev/null; then
                    verified="false"
                    confidence="0.1"
                    warnings+=("path $word is outside allowed base: $base_path")
                fi
            else
                # Simple prefix check
                if [[ "$word" != "$base_path"* ]]; then
                    verified="false"
                    confidence="0.1"
                    warnings+=("path $word is outside allowed base: $base_path")
                fi
            fi
        done
    fi

    # Strict mode: fail on low confidence
    if [[ $strict -eq 1 ]]; then
        local conf_int="${confidence%.*}"
        [[ -z "$conf_int" ]] && conf_int=0
        if [[ "$confidence" != "0."* ]] && [[ $conf_int -lt 7 ]]; then
            verified="false"
        elif [[ "$confidence" == "0."* ]]; then
            local decimal="${confidence#0.}"
            [[ ${decimal:0:1} -lt 7 ]] && verified="false"
        fi
    fi

    # Classify risk
    local risk
    intent_classify "$command" >/dev/null
    risk=$?

    if [[ $risk -ge $INTENT_RISK_HIGH ]]; then
        warnings+=("command has high risk level: ${_INTENT_RISK_LABELS[$risk]}")
        # Use awk for decimal comparison (bash cannot compare decimals natively)
        if awk "BEGIN {exit !($confidence > 0.5)}"; then
            confidence="0.5"
        fi
    fi

    # Output
    if [[ $json_output -eq 1 ]]; then
        local escaped_intent escaped_cmd escaped_analysis
        escaped_intent=$(_intent_escape_json "$declared_intent")
        escaped_cmd=$(_intent_escape_json "$command")
        escaped_analysis=$(_intent_escape_json "$analysis")
        local warnings_json
        warnings_json=$(_intent_array_to_json "${warnings[@]}")
        printf '{"verified":%s,"confidence":%s,"intent":"%s","command":"%s","analysis":"%s","warnings":%s,"risk":%d}\n' \
            "$verified" "$confidence" "$escaped_intent" "$escaped_cmd" "$escaped_analysis" "$warnings_json" "$risk"
    else
        printf '%s (confidence: %s)\n' "$verified" "$confidence"
    fi

    [[ "$verified" == "true" ]] && return 0
    [[ "$confidence" == "0.5" ]] && return 2
    return 1
}

# intent_sandbox_recommend - Recommend sandbox settings based on command analysis
# @description Analyze command and suggest appropriate sandbox configuration
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      $1 command - Command to analyze
# @param      --json - Output as JSON
# @stdout     Sandbox recommendations
# @return     0 always
#
# Usage: intent_sandbox_recommend "rm -rf /tmp/cache"
# Usage: intent_sandbox_recommend "curl https://example.com" --json
intent_sandbox_recommend() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local risk
    intent_classify "$command" >/dev/null
    risk=$?

    local dry_run="false"
    local network="true"
    local timeout=300
    local -a allow_write=()
    local -a deny_write=()
    local -a recommendations=()

    case $risk in
        $INTENT_RISK_CRITICAL)
            dry_run="true"
            timeout=10
            deny_write+=("/")
            recommendations+=("CRITICAL: use dry-run mode only")
            recommendations+=("manual review required before execution")
            ;;
        $INTENT_RISK_HIGH)
            dry_run="true"
            timeout=60
            deny_write+=("/" "/etc" "/usr" "/boot" "/home")
            recommendations+=("recommend dry-run before actual execution")
            recommendations+=("use checkpoint before modifying files")
            ;;
        $INTENT_RISK_MEDIUM)
            timeout=120
            deny_write+=("/etc" "/usr" "/boot")
            recommendations+=("consider using backup before execution")
            ;;
        $INTENT_RISK_LOW)
            timeout=300
            recommendations+=("standard sandbox settings appropriate")
            ;;
        $INTENT_RISK_SAFE)
            timeout=300
            recommendations+=("minimal sandbox restrictions needed")
            ;;
    esac

    # Check for network commands
    if [[ "$command" =~ (curl|wget|nc|ssh|scp|rsync|ftp) ]]; then
        if [[ $risk -ge $INTENT_RISK_HIGH ]]; then
            network="false"
            recommendations+=("network access denied due to high risk")
        fi
    fi

    # Extract paths from command for allow_write suggestions
    local word
    for word in $command; do
        if [[ "$word" == /tmp/* ]] || [[ "$word" == /var/tmp/* ]]; then
            allow_write+=("$word")
        fi
    done

    if [[ $json_output -eq 1 ]]; then
        local allow_json deny_json rec_json
        allow_json=$(_intent_array_to_json "${allow_write[@]}")
        deny_json=$(_intent_array_to_json "${deny_write[@]}")
        rec_json=$(_intent_array_to_json "${recommendations[@]}")
        printf '{"risk":%d,"risk_label":"%s","sandbox":{"dry_run":%s,"network":%s,"timeout":%d,"allow_write":%s,"deny_write":%s},"recommendations":%s}\n' \
            "$risk" "${_INTENT_RISK_LABELS[$risk]}" "$dry_run" "$network" "$timeout" "$allow_json" "$deny_json" "$rec_json"
    else
        printf 'Risk Level: %s (%d)\n' "${_INTENT_RISK_LABELS[$risk]}" "$risk"
        printf 'Sandbox Settings:\n'
        printf '  Dry Run: %s\n' "$dry_run"
        printf '  Network: %s\n' "$network"
        printf '  Timeout: %ds\n' "$timeout"
        [[ ${#allow_write[@]} -gt 0 ]] && printf '  Allow Write: %s\n' "${allow_write[*]}"
        [[ ${#deny_write[@]} -gt 0 ]] && printf '  Deny Write: %s\n' "${deny_write[*]}"
        printf 'Recommendations:\n'
        for rec in "${recommendations[@]}"; do
            printf '  - %s\n' "$rec"
        done
    fi

    return 0
}

# intent_dry_run - Simulate command execution without side effects
# @description Parse and explain what a command would do without executing it
# @pre        None
# @post       None (analysis only, NO EXECUTION)
# @idempotent Yes
# @param      $1 command - Command to simulate
# @param      --json - Output as JSON
# @stdout     Simulation results
# @return     0 always
#
# Usage: intent_dry_run "rm -rf /tmp/cache"
intent_dry_run() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local -a would_affect=()
    local -a operations=()
    local risk
    intent_classify "$command" >/dev/null
    risk=$?

    # Parse command to identify operations (static analysis only)
    local base_cmd="${command%% *}"

    case "$base_cmd" in
        rm)
            operations+=("delete")
            # Extract targets
            local word
            for word in $command; do
                [[ "$word" == -* ]] && continue
                [[ "$word" == "rm" ]] && continue
                would_affect+=("$word")
            done
            ;;
        mv)
            operations+=("move/rename")
            local -a args=()
            for word in $command; do
                [[ "$word" == -* ]] && continue
                [[ "$word" == "mv" ]] && continue
                args+=("$word")
            done
            [[ ${#args[@]} -ge 2 ]] && would_affect+=("${args[0]} -> ${args[-1]}")
            ;;
        cp)
            operations+=("copy")
            ;;
        chmod)
            operations+=("change permissions")
            ;;
        chown)
            operations+=("change ownership")
            ;;
        mkdir)
            operations+=("create directory")
            ;;
        touch)
            operations+=("create/update file")
            ;;
        *)
            operations+=("$base_cmd operation")
            ;;
    esac

    if [[ $json_output -eq 1 ]]; then
        local ops_json affects_json escaped_cmd
        escaped_cmd=$(_intent_escape_json "$command")
        ops_json=$(_intent_array_to_json "${operations[@]}")
        affects_json=$(_intent_array_to_json "${would_affect[@]}")
        printf '{"dry_run":true,"command":"%s","operations":%s,"would_affect":%s,"risk":%d,"risk_label":"%s"}\n' \
            "$escaped_cmd" "$ops_json" "$affects_json" "$risk" "${_INTENT_RISK_LABELS[$risk]}"
    else
        printf '[DRY RUN] Command: %s\n' "$command"
        printf 'Operations: %s\n' "${operations[*]}"
        printf 'Risk Level: %s\n' "${_INTENT_RISK_LABELS[$risk]}"
        [[ ${#would_affect[@]} -gt 0 ]] && printf 'Would Affect:\n'
        for target in "${would_affect[@]}"; do
            printf '  - %s\n' "$target"
        done
    fi

    return 0
}

# intent_estimate_cost - Estimate I/O impact and time for a command
# @description Analyze command to estimate resource usage (no execution)
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      $1 command - Command to analyze
# @param      --json - Output as JSON
# @stdout     Cost estimation
# @return     0 always
#
# Usage: intent_estimate_cost "find / -name '*.log'"
intent_estimate_cost() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local io_level="low"
    local cpu_level="low"
    local time_estimate="seconds"
    local -a notes=()

    local base_cmd="${command%% *}"

    # Estimate based on command type
    case "$base_cmd" in
        find)
            io_level="high"
            time_estimate="minutes"
            [[ "$command" == *"/"[[:space:]]* ]] && notes+=("searching from root may take significant time")
            ;;
        grep|rg|ag)
            io_level="medium"
            [[ "$command" == *"-r"* ]] && io_level="high"
            ;;
        du|df)
            io_level="medium"
            [[ "$command" == *"/"[[:space:]]* ]] && time_estimate="minutes"
            ;;
        rm)
            io_level="medium"
            [[ "$command" == *"-r"* ]] && io_level="high"
            ;;
        tar|zip|gzip)
            io_level="high"
            cpu_level="medium"
            time_estimate="minutes"
            ;;
        gcc|make|npm|yarn|pip)
            io_level="high"
            cpu_level="high"
            time_estimate="minutes"
            ;;
        curl|wget)
            io_level="medium"
            time_estimate="variable (network dependent)"
            notes+=("depends on network speed and file size")
            ;;
        *)
            io_level="low"
            cpu_level="low"
            time_estimate="seconds"
            ;;
    esac

    if [[ $json_output -eq 1 ]]; then
        local notes_json escaped_cmd
        escaped_cmd=$(_intent_escape_json "$command")
        notes_json=$(_intent_array_to_json "${notes[@]}")
        printf '{"command":"%s","io_level":"%s","cpu_level":"%s","time_estimate":"%s","notes":%s}\n' \
            "$escaped_cmd" "$io_level" "$cpu_level" "$time_estimate" "$notes_json"
    else
        printf 'Cost Estimate for: %s\n' "$command"
        printf '  I/O Level: %s\n' "$io_level"
        printf '  CPU Level: %s\n' "$cpu_level"
        printf '  Time: %s\n' "$time_estimate"
        for note in "${notes[@]}"; do
            printf '  Note: %s\n' "$note"
        done
    fi

    return 0
}

# intent_explain - Generate human-readable explanation of command effects
# @description Parse command and explain what it does in plain language
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      $1 command - Command to explain
# @param      --json - Output as JSON
# @param      --verbose - Include detailed breakdown
# @stdout     Explanation of command effects
# @return     0 always
#
# Usage: intent_explain "find /var -name '*.log' -mtime +30 -delete"
# Usage: intent_explain "chmod -R 755 /app" --json
intent_explain() {
    local command="$1"
    shift

    local json_output=0 verbose=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --verbose) verbose=1; shift ;;
            *) shift ;;
        esac
    done

    local base_cmd="${command%% *}"
    local summary=""
    local -a details=()
    local -a flags=()

    # Build explanation based on command
    case "$base_cmd" in
        rm)
            summary="Delete files or directories"
            [[ "$command" == *"-r"* ]] && flags+=("-r: recursive deletion")
            [[ "$command" == *"-f"* ]] && flags+=("-f: force, no confirmation")
            [[ "$command" == *"-i"* ]] && flags+=("-i: interactive, ask before each removal")
            ;;
        mv)
            summary="Move or rename files/directories"
            [[ "$command" == *"-f"* ]] && flags+=("-f: force overwrite")
            [[ "$command" == *"-i"* ]] && flags+=("-i: interactive, ask before overwrite")
            ;;
        cp)
            summary="Copy files or directories"
            [[ "$command" == *"-r"* ]] && flags+=("-r: recursive copy")
            [[ "$command" == *"-p"* ]] && flags+=("-p: preserve permissions")
            ;;
        chmod)
            summary="Change file permissions"
            [[ "$command" == *"-R"* ]] && flags+=("-R: recursive, affects all files in directory")
            if [[ "$command" =~ 777 ]]; then
                details+=("WARNING: 777 gives read/write/execute to everyone")
            fi
            ;;
        chown)
            summary="Change file ownership"
            [[ "$command" == *"-R"* ]] && flags+=("-R: recursive, affects all files in directory")
            ;;
        find)
            summary="Search for files matching criteria"
            [[ "$command" == *"-delete"* ]] && details+=("WARNING: -delete will remove matching files")
            [[ "$command" == *"-exec"* ]] && details+=("NOTE: -exec will run a command on each match")
            ;;
        grep)
            summary="Search for patterns in files"
            [[ "$command" == *"-r"* ]] && flags+=("-r: recursive search")
            ;;
        curl|wget)
            summary="Download content from URL"
            [[ "$command" == *"|"* ]] && details+=("WARNING: output is piped to another command")
            ;;
        sudo)
            summary="Execute command with elevated privileges"
            details+=("WARNING: runs with root/superuser permissions")
            ;;
        *)
            summary="Execute $base_cmd command"
            ;;
    esac

    # Risk assessment
    local risk
    intent_classify "$command" >/dev/null
    risk=$?
    details+=("Risk Level: ${_INTENT_RISK_LABELS[$risk]}")

    if [[ $json_output -eq 1 ]]; then
        local escaped_cmd escaped_summary
        escaped_cmd=$(_intent_escape_json "$command")
        escaped_summary=$(_intent_escape_json "$summary")
        local flags_json details_json
        flags_json=$(_intent_array_to_json "${flags[@]}")
        details_json=$(_intent_array_to_json "${details[@]}")
        printf '{"command":"%s","summary":"%s","flags":%s,"details":%s,"risk":%d}\n' \
            "$escaped_cmd" "$escaped_summary" "$flags_json" "$details_json" "$risk"
    else
        printf 'Command: %s\n' "$command"
        printf 'Summary: %s\n' "$summary"
        if [[ ${#flags[@]} -gt 0 ]]; then
            printf 'Flags:\n'
            for flag in "${flags[@]}"; do
                printf '  %s\n' "$flag"
            done
        fi
        if [[ ${#details[@]} -gt 0 ]]; then
            printf 'Details:\n'
            for detail in "${details[@]}"; do
                printf '  %s\n' "$detail"
            done
        fi
    fi

    return 0
}

# intent_suggest_safer - Suggest safer alternatives to a risky command
# @description Analyze command and suggest safer ways to achieve same goal
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      $1 command - Original command
# @param      --json - Output as JSON array
# @stdout     List of safer alternative commands
# @return     0 if alternatives found, 1 if command is already safe, 2 if no alternatives
#
# Usage: intent_suggest_safer "rm -rf /"
# Usage: intent_suggest_safer "chmod 777 /etc" --json
intent_suggest_safer() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local risk
    intent_classify "$command" >/dev/null
    risk=$?

    # Already safe
    if [[ $risk -eq $INTENT_RISK_SAFE ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"already_safe":true,"alternatives":[]}\n'
        else
            printf 'Command is already safe (risk level: safe)\n'
        fi
        return 1
    fi

    local -a alternatives=()
    local base_cmd="${command%% *}"

    case "$base_cmd" in
        rm)
            if [[ "$command" == *"-rf"* ]]; then
                alternatives+=("Use 'rm -ri' for interactive confirmation")
                alternatives+=("Use 'trash-put' or 'gio trash' to move to trash instead")
                alternatives+=("Use 'find ... -delete' with specific patterns")
            fi
            alternatives+=("Create a backup first: cp -r <target> <target>.bak")
            alternatives+=("Use version control for important files")
            ;;
        chmod)
            if [[ "$command" =~ 777 ]]; then
                alternatives+=("Use 755 for directories (rwxr-xr-x)")
                alternatives+=("Use 644 for files (rw-r--r--)")
                alternatives+=("Use 700/600 for private files")
            fi
            if [[ "$command" == *"-R"* ]]; then
                alternatives+=("Apply permissions to specific files, not recursively")
                alternatives+=("Use find with -exec chmod for granular control")
            fi
            ;;
        chown)
            if [[ "$command" == *"-R"* ]]; then
                alternatives+=("Apply ownership to specific files, not recursively")
                alternatives+=("Verify target path before recursive operation")
            fi
            ;;
        curl|wget)
            if [[ "$command" == *"|"*"bash"* ]] || [[ "$command" == *"|"*"sh"* ]]; then
                alternatives+=("Download script first, review, then execute")
                alternatives+=("Verify script checksum before execution")
                alternatives+=("Use official package managers when available")
            fi
            ;;
        sudo)
            alternatives+=("Use 'sudo -l' to check permissions first")
            alternatives+=("Use specific sudo rules in /etc/sudoers.d/")
            alternatives+=("Consider using capabilities instead of full sudo")
            ;;
        kill)
            if [[ "$command" == *"-9"* ]]; then
                alternatives+=("Try SIGTERM (kill without -9) first")
                alternatives+=("Use pkill with specific pattern")
            fi
            ;;
    esac

    # Generic suggestions for high-risk commands
    if [[ $risk -ge $INTENT_RISK_HIGH ]] && [[ ${#alternatives[@]} -eq 0 ]]; then
        alternatives+=("Run in dry-run mode first if available")
        alternatives+=("Create checkpoint/backup before execution")
        alternatives+=("Test on non-production data first")
    fi

    if [[ ${#alternatives[@]} -eq 0 ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"alternatives":[],"message":"no specific alternatives found"}\n'
        else
            printf 'No specific safer alternatives found\n'
        fi
        return 2
    fi

    if [[ $json_output -eq 1 ]]; then
        local alt_json
        alt_json=$(_intent_array_to_json "${alternatives[@]}")
        printf '{"risk":%d,"alternatives":%s}\n' "$risk" "$alt_json"
    else
        printf 'Current Risk Level: %s\n' "${_INTENT_RISK_LABELS[$risk]}"
        printf 'Safer Alternatives:\n'
        for alt in "${alternatives[@]}"; do
            printf '  - %s\n' "$alt"
        done
    fi

    return 0
}

# intent_batch_verify - Verify multiple commands in a batch
# @description Analyze multiple commands and return aggregate safety assessment
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      commands - Commands to verify (one per line on stdin or as arguments)
# @param      --json - Output as JSON
# @param      --stop-on-critical - Stop processing if critical risk found
# @stdout     Batch verification results
# @return     Highest risk level found
#
# Usage: echo -e "ls -la\nrm -rf /tmp" | intent_batch_verify
# Usage: intent_batch_verify "ls -la" "rm -rf /tmp" --json
intent_batch_verify() {
    local -a commands=()
    local json_output=0 stop_on_critical=0

    # Parse options and collect commands
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --stop-on-critical) stop_on_critical=1; shift ;;
            *) commands+=("$1"); shift ;;
        esac
    done

    # Read from stdin if no commands provided
    if [[ ${#commands[@]} -eq 0 ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && commands+=("$line")
        done
    fi

    local max_risk=0
    local -a results=()
    local safe_count=0 low_count=0 medium_count=0 high_count=0 critical_count=0

    for cmd in "${commands[@]}"; do
        local risk
        intent_classify "$cmd" >/dev/null
        risk=$?

        (( risk > max_risk )) && max_risk=$risk

        case $risk in
            $INTENT_RISK_SAFE) ((safe_count++)) ;;
            $INTENT_RISK_LOW) ((low_count++)) ;;
            $INTENT_RISK_MEDIUM) ((medium_count++)) ;;
            $INTENT_RISK_HIGH) ((high_count++)) ;;
            $INTENT_RISK_CRITICAL) ((critical_count++)) ;;
        esac

        if [[ $json_output -eq 1 ]]; then
            local escaped_cmd
            escaped_cmd=$(_intent_escape_json "$cmd")
            results+=("{\"command\":\"$escaped_cmd\",\"risk\":$risk,\"risk_label\":\"${_INTENT_RISK_LABELS[$risk]}\"}")
        fi

        if [[ $stop_on_critical -eq 1 ]] && [[ $risk -eq $INTENT_RISK_CRITICAL ]]; then
            break
        fi
    done

    local total=${#commands[@]}

    if [[ $json_output -eq 1 ]]; then
        local results_json
        local IFS=','
        results_json="[${results[*]}]"
        printf '{"total":%d,"max_risk":%d,"max_risk_label":"%s","summary":{"safe":%d,"low":%d,"medium":%d,"high":%d,"critical":%d},"results":%s}\n' \
            "$total" "$max_risk" "${_INTENT_RISK_LABELS[$max_risk]}" \
            "$safe_count" "$low_count" "$medium_count" "$high_count" "$critical_count" \
            "$results_json"
    else
        printf 'Batch Verification Summary:\n'
        printf '  Total Commands: %d\n' "$total"
        printf '  Maximum Risk: %s (%d)\n' "${_INTENT_RISK_LABELS[$max_risk]}" "$max_risk"
        printf '  Breakdown:\n'
        printf '    Safe: %d\n' "$safe_count"
        printf '    Low: %d\n' "$low_count"
        printf '    Medium: %d\n' "$medium_count"
        printf '    High: %d\n' "$high_count"
        printf '    Critical: %d\n' "$critical_count"
    fi

    return $max_risk
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

declare -ga _INTENT_EXPORTS=(
    intent_classify
    intent_verify
    intent_sandbox_recommend
    intent_dry_run
    intent_estimate_cost
    intent_explain
    intent_suggest_safer
    intent_batch_verify
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_INTENT_EXPORTS[@]}" 2>/dev/null || true
fi

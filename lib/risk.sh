#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/risk.sh - Risk Quantification for AI Agent Decision-Making
# =============================================================================
# Description: Quantifies the danger level of shell commands on a 0-10 scale
#              so AI agents can make informed decisions about whether to proceed,
#              request confirmation, or abort. Integrates with scope.sh for
#              boundary enforcement and output.sh for structured JSON responses.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_RISK_LOADED:-}" ]] && return 0
_MAINFRAME_RISK_LOADED=1
readonly _MAINFRAME_RISK_LOADED

# =============================================================================
# RISK LEVEL CONSTANTS
# =============================================================================

readonly RISK_NONE=0          # No risk (read-only, idempotent)
readonly RISK_TRIVIAL=1       # Trivial (create temp file)
readonly RISK_LOW=2           # Low (write to project dir)
readonly RISK_MINOR=3         # Minor (modify config)
readonly RISK_MODERATE=4      # Moderate (install package)
readonly RISK_ELEVATED=5      # Elevated (modify system config)
readonly RISK_HIGH=6          # High (delete files)
readonly RISK_SEVERE=7        # Severe (modify permissions)
readonly RISK_CRITICAL=8      # Critical (network-facing changes)
readonly RISK_EXTREME=9       # Extreme (delete directories recursively)
readonly RISK_CATASTROPHIC=10 # Catastrophic (rm -rf /, format disk)

# =============================================================================
# CONFIGURATION
# =============================================================================

# Block operations scoring above this threshold
MAINFRAME_RISK_THRESHOLD="${MAINFRAME_RISK_THRESHOLD:-6}"

# Require confirmation for operations scoring at or above this threshold
MAINFRAME_RISK_CONFIRM_THRESHOLD="${MAINFRAME_RISK_CONFIRM_THRESHOLD:-5}"

# Log file for risk assessments (empty = no logging)
MAINFRAME_RISK_LOG="${MAINFRAME_RISK_LOG:-}"

# Output JSON from mainframe_risk_assess (1=json, 0=text)
MAINFRAME_RISK_JSON="${MAINFRAME_RISK_JSON:-1}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string (reuse from scope.sh pattern if available)
_risk_escape() {
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

# Clamp a score to the 0-10 range
_risk_clamp() {
    local score="$1"
    (( score < 0 )) && score=0
    (( score > 10 )) && score=10
    printf '%d' "$score"
}

# Extract the base command name from a potentially-pathed command
_risk_base_cmd() {
    local cmd="$1"
    # Strip path prefix
    cmd="${cmd##*/}"
    printf '%s' "$cmd"
}

# Check if a path argument targets a system-critical location
# Returns a modifier to add to the base score
_risk_path_modifier() {
    local path="$1"

    # Expand tilde
    if [[ "$path" == "~"* ]]; then
        path="${HOME}${path#\~}"
    fi

    # Normalize: remove trailing slashes for consistent matching
    path="${path%/}"

    # Critical system roots: /, /boot, /dev, /proc, /sys
    case "$path" in
        /|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*)
            printf '3'
            return
            ;;
    esac

    # System directories: /etc, /usr, /var, /lib, /sbin, /bin
    case "$path" in
        /etc|/etc/*|/usr|/usr/*|/var|/var/*|/lib|/lib/*|/sbin|/sbin/*|/bin|/bin/*)
            printf '2'
            return
            ;;
    esac

    # Home root (~ exactly, not subdirectories)
    case "$path" in
        "$HOME")
            printf '1'
            return
            ;;
    esac

    # Temp directories: safer
    case "$path" in
        /tmp|/tmp/*|/var/tmp|/var/tmp/*)
            printf -- '-2'
            return
            ;;
    esac

    # Current directory / project scope: slightly safer
    local pwd_resolved="${PWD:-}"
    if [[ -n "$pwd_resolved" && "$path" == "$pwd_resolved"* ]]; then
        printf -- '-1'
        return
    fi

    # Home subdirectories: neutral
    if [[ "$path" == "$HOME/"* ]]; then
        printf '0'
        return
    fi

    # Unknown paths: neutral
    printf '0'
}

# Check flags for risk modifiers
_risk_flag_modifier() {
    local -a args=("$@")
    local modifier=0
    local has_sudo=0
    local arg

    for arg in "${args[@]}"; do
        case "$arg" in
            --force|-f)
                (( modifier += 1 ))
                ;;
            --recursive|-r|-R|--recurse)
                (( modifier += 1 ))
                ;;
            --no-preserve-root)
                (( modifier += 3 ))
                ;;
            sudo)
                has_sudo=1
                ;;
        esac
    done

    (( has_sudo )) && (( modifier += 2 ))
    printf '%d' "$modifier"
}

# Get base score for a command name
_risk_cmd_base_score() {
    local cmd="$1"

    case "$cmd" in
        # Score 0: read-only, informational commands
        ls|cat|echo|printf|pwd|whoami|id|date|type|which|file|stat|wc|head|tail|\
        less|more|man|help|true|false|test|env|printenv|hostname|uname|uptime|\
        df|du|free|top|ps|pgrep|lsof|readlink|basename|dirname|realpath|tput|\
        read|set|declare|export|local|readonly|typeset|source|.|history|alias|\
        sort|uniq|tr|cut|paste|fold|fmt|column|seq|yes|diff|comm|cmp|grep|egrep|fgrep)
            printf '0'
            ;;
        # Score 1: trivial writes (temp/small scope)
        touch|tee)
            printf '1'
            ;;
        # Score 2: project-level writes
        mkdir|cp|mv|ln|install)
            printf '2'
            ;;
        # Score 3: in-place edits and version control writes
        sed|awk|perl|git|patch|ed)
            printf '3'
            ;;
        # Score 4: package managers
        pip|pip3|npm|npx|yarn|pnpm|bun|cargo|go|gem|composer|apt|apt-get|\
        dnf|yum|pacman|snap|flatpak|brew)
            printf '4'
            ;;
        # Score 5: system configuration changes
        chmod|chown|chgrp|systemctl|service|update-alternatives|ldconfig|\
        sysctl|modprobe|insmod|rmmod)
            printf '5'
            ;;
        # Score 6: file deletion (individual)
        rm|unlink|truncate|shred)
            printf '6'
            ;;
        # Score 3 base (escalates to 7+ via -delete/-exec rm pattern modifiers)
        find)
            printf '3'
            ;;
        # Score 4 base (escalates to 8+ via pipe-to-shell or firewall patterns)
        iptables|ip6tables|nft|ufw|firewall-cmd|ssh-keygen|ssh|scp|\
        nc|ncat|socat|curl|wget)
            printf '4'
            ;;
        # Score 9: disk-level operations
        mkfs|mkfs.*|fdisk|gdisk|parted|dd|wipefs|blkdiscard|lvm|pvcreate|\
        vgcreate|lvcreate)
            printf '9'
            ;;
        # Default: unknown commands get a baseline moderate score
        *)
            printf '3'
            ;;
    esac
}

# Detect dangerous argument patterns that escalate risk
_risk_pattern_detect() {
    local cmd="$1"
    shift
    local -a args=("$@")
    local -a reasons=()
    local modifier=0
    local all_args="${args[*]}"

    case "$cmd" in
        rm)
            # rm -rf / or rm -rf ~ is catastrophic
            if [[ "$all_args" == *"-rf"* || "$all_args" == *"-r"*"-f"* || \
                  "$all_args" == *"-fr"* ]]; then
                local target
                for target in "${args[@]}"; do
                    [[ "$target" == -* ]] && continue
                    case "$target" in
                        /|"$HOME"|~)
                            (( modifier += 4 ))
                            reasons+=("catastrophic_target")
                            ;;
                        /*)
                            reasons+=("absolute_path_delete")
                            ;;
                    esac
                done
            fi
            # -r flag on rm escalates to directory deletion
            if [[ "$all_args" == *"-r"* || "$all_args" == *"--recursive"* ]]; then
                (( modifier += 1 ))
                reasons+=("recursive_delete")
            fi
            ;;
        sed)
            # sed -i is in-place editing
            if [[ "$all_args" == *"-i"* || "$all_args" == *"--in-place"* ]]; then
                reasons+=("in_place_edit")
            fi
            ;;
        chmod|chown|chgrp)
            # -R flag makes permission changes recursive
            if [[ "$all_args" == *"-R"* || "$all_args" == *"--recursive"* ]]; then
                (( modifier += 2 ))
                reasons+=("recursive_permission_change")
            fi
            ;;
        find)
            # find with -delete or -exec rm is dangerous
            if [[ "$all_args" == *"-delete"* ]]; then
                (( modifier += 4 ))
                reasons+=("find_delete")
            fi
            if [[ "$all_args" == *"-exec"*"rm"* ]]; then
                (( modifier += 4 ))
                reasons+=("find_exec_rm")
            fi
            ;;
        curl|wget)
            # Piping to shell is extremely dangerous
            if [[ "$all_args" == *"|"*"bash"* || "$all_args" == *"|"*"sh"* || \
                  "$all_args" == *"|"*"zsh"* ]]; then
                (( modifier += 4 ))
                reasons+=("pipe_to_shell")
            fi
            ;;
        git)
            # git add/commit are safe; git push/force-push are riskier
            if [[ "$all_args" == *"push"*"--force"* || "$all_args" == *"push"*"-f"* ]]; then
                (( modifier += 2 ))
                reasons+=("force_push")
            fi
            if [[ "$all_args" == *"reset"*"--hard"* ]]; then
                (( modifier += 2 ))
                reasons+=("hard_reset")
            fi
            if [[ "$all_args" == *"clean"*"-fd"* || "$all_args" == *"clean"*"-df"* ]]; then
                (( modifier += 2 ))
                reasons+=("git_clean_force")
            fi
            ;;
        dd)
            # dd with of= to a device is extremely dangerous
            if [[ "$all_args" == *"of=/dev/"* ]]; then
                (( modifier += 1 ))
                reasons+=("dd_write_device")
            fi
            ;;
        ssh-keygen)
            # Key generation affects authentication (base 4 + 4 = 8 critical)
            (( modifier += 4 ))
            reasons+=("key_generation")
            if [[ "$all_args" == *"-f"* ]]; then
                reasons+=("key_overwrite")
            fi
            ;;
        iptables|ip6tables|nft|ufw|firewall-cmd)
            # Firewall modifications are network-facing (base 4 + 4 = 8 critical)
            (( modifier += 4 ))
            reasons+=("firewall_modification")
            ;;
        npm|npx|pip|pip3)
            # install subcommand (expected usage)
            if [[ "$all_args" == *"install"* ]]; then
                reasons+=("package_install")
            fi
            # Global install is riskier
            if [[ "$all_args" == *"-g"* || "$all_args" == *"--global"* || \
                  "$all_args" == *"--system"* ]]; then
                (( modifier += 1 ))
                reasons+=("global_install")
            fi
            ;;
    esac

    # Output modifier and reasons separated by pipe
    local reasons_str=""
    if [[ ${#reasons[@]} -gt 0 ]]; then
        local IFS=','
        reasons_str="${reasons[*]}"
    fi
    printf '%d|%s' "$modifier" "$reasons_str"
}

# Check scope integration: returns +3 if command targets out-of-scope paths
_risk_scope_modifier() {
    local -a args=("$@")

    # Only apply if scope module is loaded and enabled
    [[ "${MAINFRAME_SCOPE_ENABLED:-0}" != "1" ]] && { printf '0'; return; }
    declare -F mainframe_scope_check &>/dev/null || { printf '0'; return; }

    local arg
    for arg in "${args[@]}"; do
        # Skip flags
        [[ "$arg" == -* ]] && continue
        # Check if it looks like a path
        if [[ "$arg" == /* || "$arg" == ~* || "$arg" == ./* || "$arg" == ../* ]]; then
            if ! mainframe_scope_check "filesystem" "$arg" 2>/dev/null; then
                printf '3'
                return
            fi
        fi
    done

    printf '0'
}

# Append an assessment entry to the risk log
_risk_log_entry() {
    [[ -z "$MAINFRAME_RISK_LOG" ]] && return 0

    local score="$1"
    local cmd="$2"
    shift 2
    local args_str="$*"
    local ts
    ts=$(date +%s 2>/dev/null || printf '0')

    printf '%d\t%s\t%s\t%s\n' "$ts" "$score" "$cmd" "$args_str" >> "$MAINFRAME_RISK_LOG" 2>/dev/null
    return 0
}

# =============================================================================
# CORE SCORING ENGINE
# =============================================================================

# @pre: at least one argument (the command name)
# @post: calculates composite risk score from command, paths, flags, patterns
# @returns: the clamped 0-10 risk score via global _RISK_RESULT_SCORE,
#           reasons via _RISK_RESULT_REASONS, suggestion via _RISK_RESULT_SUGGESTION
#
# Internal calculation function. Sets global result variables to avoid subshells.
_risk_calculate() {
    local cmd="$1"
    shift
    local -a args=("$@")

    # Normalize command name
    local base_cmd
    base_cmd=$(_risk_base_cmd "$cmd")

    # 1. Base score from command identity
    local base_score
    base_score=$(_risk_cmd_base_score "$base_cmd")

    # 2. Flag-based modifier
    local flag_mod
    flag_mod=$(_risk_flag_modifier "${args[@]}")

    # 3. Pattern detection (returns "modifier|reason1,reason2")
    local pattern_result
    pattern_result=$(_risk_pattern_detect "$base_cmd" "${args[@]}")
    local pattern_mod="${pattern_result%%|*}"
    local pattern_reasons="${pattern_result#*|}"

    # 4. Path-based modifier (use first non-flag argument that looks like a path)
    local path_mod=0
    local target_path=""
    local arg
    for arg in "${args[@]}"; do
        [[ "$arg" == -* ]] && continue
        # Check if it could be a path
        if [[ "$arg" == /* || "$arg" == ~* || "$arg" == ./* || "$arg" == ../* || \
              "$arg" == "$HOME"* ]]; then
            target_path="$arg"
            path_mod=$(_risk_path_modifier "$arg")
            break
        fi
    done

    # 5. Scope modifier (out-of-scope = +3)
    local scope_mod
    scope_mod=$(_risk_scope_modifier "$cmd" "${args[@]}")

    # 6. Composite score
    local total=$(( base_score + flag_mod + pattern_mod + path_mod + scope_mod ))

    # Clamp to 0-10
    total=$(_risk_clamp "$total")

    # Build reasons list
    local -a all_reasons=()
    (( flag_mod > 0 )) && all_reasons+=("dangerous_flags")
    (( path_mod > 0 )) && all_reasons+=("system_path")
    (( path_mod == 3 )) && all_reasons+=("critical_path")
    (( scope_mod > 0 )) && all_reasons+=("out_of_scope")
    if [[ -n "$pattern_reasons" ]]; then
        local IFS=','
        local reason
        for reason in $pattern_reasons; do
            all_reasons+=("$reason")
        done
    fi

    # Build suggestion
    local suggestion=""
    if (( total >= 9 )); then
        suggestion="ABORT: This operation is extremely dangerous. Use a sandboxed environment."
    elif (( total >= 7 )); then
        suggestion="Use sandbox or create backup first. Consider atomic operations from atomic.sh."
    elif (( total >= 5 )); then
        suggestion="Confirm with user before proceeding. Consider using file_checkpoint from atomic.sh."
    elif (( total >= 3 )); then
        suggestion="Proceed with caution. Verify target paths are correct."
    else
        suggestion="Safe to proceed."
    fi

    # Set global results
    _RISK_RESULT_SCORE=$total
    _RISK_RESULT_TARGET="$target_path"
    _RISK_RESULT_REASONS=("${all_reasons[@]}")
    _RISK_RESULT_SUGGESTION="$suggestion"
}

# Global result variables (avoids subshell overhead)
declare -g _RISK_RESULT_SCORE=0
declare -g _RISK_RESULT_TARGET=""
declare -ga _RISK_RESULT_REASONS=()
declare -g _RISK_RESULT_SUGGESTION=""

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: COMMAND is non-empty
# @post: prints numeric risk score (0-10) to stdout
# @idempotent: yes
# @returns: 0 always; score printed to stdout
#
# Calculate and return the risk score for a command with its arguments.
# Uses pattern matching on command name, path arguments, and flags.
#
# Usage: mainframe_risk_score rm -rf /tmp/test
# Usage: score=$(mainframe_risk_score chmod -R 777 /etc)
mainframe_risk_score() {
    if [[ $# -eq 0 ]]; then
        printf '0'
        return 0
    fi

    _risk_calculate "$@"

    if [[ "$MAINFRAME_OUTPUT" == "json" ]]; then
        local elapsed_ms=0
        if declare -F output_timer_elapsed &>/dev/null; then
            local varname="_MAINFRAME_TIMER__default"
            [[ -n "${!varname:-}" ]] && elapsed_ms=$(output_timer_elapsed "_default")
        fi
        printf '{"ok":true,"data":%d,"meta":{"elapsed_ms":%d}}\n' \
            "$_RISK_RESULT_SCORE" "$elapsed_ms"
    else
        printf '%d' "$_RISK_RESULT_SCORE"
    fi

    _risk_log_entry "$_RISK_RESULT_SCORE" "$@"
    return 0
}

# @pre: COMMAND is non-empty
# @post: prints JSON assessment object to stdout
# @idempotent: yes
# @returns: 0 always
#
# Return a full risk assessment as a JSON object including score, level,
# command, target, reasons array, and actionable suggestion.
#
# Usage: mainframe_risk_assess rm -rf /home/user/project
# Output: {"score":7,"level":"severe","command":"rm","target":"/home/user/project",
#          "reasons":["recursive_delete","dangerous_flags"],"suggestion":"..."}
mainframe_risk_assess() {
    if [[ $# -eq 0 ]]; then
        if [[ "$MAINFRAME_RISK_JSON" == "1" ]]; then
            printf '{"score":0,"level":"none","command":"","target":"","reasons":[],"suggestion":"Safe to proceed."}\n'
        else
            printf 'score=0 level=none command= target= reasons= suggestion="Safe to proceed."\n'
        fi
        return 0
    fi

    _risk_calculate "$@"

    local cmd_base
    cmd_base=$(_risk_base_cmd "$1")

    local level
    level=$(mainframe_risk_label "$_RISK_RESULT_SCORE")

    if [[ "$MAINFRAME_RISK_JSON" == "1" ]]; then
        local escaped_cmd escaped_target escaped_suggestion
        escaped_cmd=$(_risk_escape "$cmd_base")
        escaped_target=$(_risk_escape "$_RISK_RESULT_TARGET")
        escaped_suggestion=$(_risk_escape "$_RISK_RESULT_SUGGESTION")

        # Build reasons JSON array
        local reasons_json="["
        local first=true
        local reason
        for reason in "${_RISK_RESULT_REASONS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                reasons_json+=","
            fi
            reasons_json+="\"$(_risk_escape "$reason")\""
        done
        reasons_json+="]"

        local result
        result=$(printf '{"score":%d,"level":"%s","command":"%s","target":"%s","reasons":%s,"suggestion":"%s"}' \
            "$_RISK_RESULT_SCORE" "$level" "$escaped_cmd" "$escaped_target" \
            "$reasons_json" "$escaped_suggestion")

        # Wrap in USOP envelope if output mode is json
        if [[ "$MAINFRAME_OUTPUT" == "json" ]]; then
            local elapsed_ms=0
            if declare -F output_timer_elapsed &>/dev/null; then
                local varname="_MAINFRAME_TIMER__default"
                [[ -n "${!varname:-}" ]] && elapsed_ms=$(output_timer_elapsed "_default")
            fi
            printf '{"ok":true,"data":%s,"meta":{"elapsed_ms":%d}}\n' "$result" "$elapsed_ms"
        else
            printf '%s\n' "$result"
        fi
    else
        local reasons_str=""
        local IFS=','
        reasons_str="${_RISK_RESULT_REASONS[*]}"
        printf 'score=%d level=%s command=%s target=%s reasons=%s suggestion="%s"\n' \
            "$_RISK_RESULT_SCORE" "$level" "$cmd_base" "$_RISK_RESULT_TARGET" \
            "$reasons_str" "$_RISK_RESULT_SUGGESTION"
    fi

    _risk_log_entry "$_RISK_RESULT_SCORE" "$@"
    return 0
}

# @pre: SCORE is a valid integer 0-10
# @post: prints the risk level label to stdout
# @idempotent: yes
# @returns: 0 on valid score, 1 on invalid input
#
# Convert a numeric risk score to its human-readable label.
#
# Usage: mainframe_risk_label 7   # Output: severe
# Usage: label=$(mainframe_risk_label "$score")
mainframe_risk_label() {
    local score="${1:-0}"

    # Validate integer
    if [[ ! "$score" =~ ^[0-9]+$ ]]; then
        printf 'unknown'
        return 1
    fi

    case "$score" in
        0)  printf 'none' ;;
        1)  printf 'trivial' ;;
        2)  printf 'low' ;;
        3)  printf 'minor' ;;
        4)  printf 'moderate' ;;
        5)  printf 'elevated' ;;
        6)  printf 'high' ;;
        7)  printf 'severe' ;;
        8)  printf 'critical' ;;
        9)  printf 'extreme' ;;
        10) printf 'catastrophic' ;;
        *)
            # Out of range: clamp label
            if (( score > 10 )); then
                printf 'catastrophic'
            else
                printf 'none'
            fi
            ;;
    esac
    return 0
}

# @pre: COMMAND is non-empty; MAINFRAME_RISK_THRESHOLD is set
# @post: returns 0 if allowed, 1 if blocked (score exceeds threshold)
# @idempotent: yes
# @returns: 0 if allowed, 1 if blocked
#
# Check a command against the current risk threshold.
# Operations scoring above MAINFRAME_RISK_THRESHOLD are blocked.
#
# Usage: mainframe_risk_check rm -rf /tmp/test && echo "allowed"
# Usage: if ! mainframe_risk_check "$cmd" "${args[@]}"; then echo "blocked"; fi
mainframe_risk_check() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    _risk_calculate "$@"
    local threshold="${MAINFRAME_RISK_THRESHOLD:-6}"

    if (( _RISK_RESULT_SCORE > threshold )); then
        if [[ "$MAINFRAME_OUTPUT" == "json" ]]; then
            local escaped_cmd
            escaped_cmd=$(_risk_escape "$(_risk_base_cmd "$1")")
            printf '{"ok":false,"error":{"code":"E_RISK_BLOCKED","msg":"Risk score %d exceeds threshold %d","score":%d,"threshold":%d,"command":"%s"}}\n' \
                "$_RISK_RESULT_SCORE" "$threshold" "$_RISK_RESULT_SCORE" "$threshold" "$escaped_cmd" >&2
        fi
        _risk_log_entry "$_RISK_RESULT_SCORE" "$@"
        return 1
    fi

    _risk_log_entry "$_RISK_RESULT_SCORE" "$@"
    return 0
}

# @pre: COMMAND is non-empty; MAINFRAME_RISK_CONFIRM_THRESHOLD is set
# @post: returns 0 if confirmation is required, 1 if not needed
# @idempotent: yes
# @returns: 0 if confirmation needed (score >= confirm threshold), 1 otherwise
#
# Determine whether a command requires user confirmation based on its risk score.
#
# Usage: mainframe_risk_require_confirm rm file.txt && echo "confirm first"
# Usage: if mainframe_risk_require_confirm "$cmd" "${args[@]}"; then prompt_user; fi
mainframe_risk_require_confirm() {
    if [[ $# -eq 0 ]]; then
        return 1
    fi

    _risk_calculate "$@"
    local threshold="${MAINFRAME_RISK_CONFIRM_THRESHOLD:-5}"

    if (( _RISK_RESULT_SCORE >= threshold )); then
        return 0
    fi
    return 1
}

# @pre: COMMAND is non-empty
# @post: prints multi-line human-readable risk explanation to stdout
# @idempotent: yes
# @returns: 0 always
#
# Provide a detailed, human-readable explanation of why a command has its
# risk score, including all contributing factors and the suggestion.
#
# Usage: mainframe_risk_explain rm -rf /etc/nginx
# Usage: mainframe_risk_explain chmod -R 777 /var/www
mainframe_risk_explain() {
    if [[ $# -eq 0 ]]; then
        printf 'No command provided. Risk score: 0 (none)\n'
        return 0
    fi

    _risk_calculate "$@"

    local cmd_base
    cmd_base=$(_risk_base_cmd "$1")
    local level
    level=$(mainframe_risk_label "$_RISK_RESULT_SCORE")
    local threshold="${MAINFRAME_RISK_THRESHOLD:-6}"
    local confirm_threshold="${MAINFRAME_RISK_CONFIRM_THRESHOLD:-5}"

    if [[ "$MAINFRAME_OUTPUT" == "json" ]]; then
        # In JSON mode, output structured explanation
        local escaped_cmd escaped_target escaped_suggestion
        escaped_cmd=$(_risk_escape "$cmd_base")
        escaped_target=$(_risk_escape "$_RISK_RESULT_TARGET")
        escaped_suggestion=$(_risk_escape "$_RISK_RESULT_SUGGESTION")

        local reasons_json="["
        local first=true
        local reason
        for reason in "${_RISK_RESULT_REASONS[@]}"; do
            $first || reasons_json+=","
            first=false
            reasons_json+="\"$(_risk_escape "$reason")\""
        done
        reasons_json+="]"

        local blocked="false"
        (( _RISK_RESULT_SCORE > threshold )) && blocked="true"
        local confirm="false"
        (( _RISK_RESULT_SCORE >= confirm_threshold )) && confirm="true"

        printf '{"ok":true,"data":{"score":%d,"level":"%s","command":"%s","target":"%s","reasons":%s,"blocked":%s,"requires_confirm":%s,"threshold":%d,"confirm_threshold":%d,"suggestion":"%s"}}\n' \
            "$_RISK_RESULT_SCORE" "$level" "$escaped_cmd" "$escaped_target" \
            "$reasons_json" "$blocked" "$confirm" "$threshold" "$confirm_threshold" \
            "$escaped_suggestion"
    else
        printf 'Risk Assessment: %s %s\n' "$cmd_base" "${*:2}"
        printf '  Score:      %d/10 (%s)\n' "$_RISK_RESULT_SCORE" "$level"
        if [[ -n "$_RISK_RESULT_TARGET" ]]; then
            printf '  Target:     %s\n' "$_RISK_RESULT_TARGET"
        fi
        if [[ ${#_RISK_RESULT_REASONS[@]} -gt 0 ]]; then
            printf '  Reasons:    '
            local first=true
            local reason
            for reason in "${_RISK_RESULT_REASONS[@]}"; do
                $first || printf ', '
                first=false
                printf '%s' "$reason"
            done
            printf '\n'
        fi
        if (( _RISK_RESULT_SCORE > threshold )); then
            printf '  Status:     BLOCKED (exceeds threshold %d)\n' "$threshold"
        elif (( _RISK_RESULT_SCORE >= confirm_threshold )); then
            printf '  Status:     CONFIRM REQUIRED (>= threshold %d)\n' "$confirm_threshold"
        else
            printf '  Status:     ALLOWED\n'
        fi
        printf '  Suggestion: %s\n' "$_RISK_RESULT_SUGGESTION"
    fi

    _risk_log_entry "$_RISK_RESULT_SCORE" "$@"
    return 0
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# @pre: commands array is non-empty
# @post: prints the command with the highest risk score
# @returns: 0 always; prints "score command" for the riskiest
#
# Compare multiple commands and return the riskiest one.
# Each command should be a quoted string.
#
# Usage: mainframe_risk_max "ls /tmp" "rm -rf /var" "cat /etc/passwd"
mainframe_risk_max() {
    local max_score=0
    local max_cmd=""
    local cmd_str

    for cmd_str in "$@"; do
        # Split command string into array
        local -a parts=()
        read -ra parts <<< "$cmd_str"
        _risk_calculate "${parts[@]}"
        if (( _RISK_RESULT_SCORE > max_score )); then
            max_score=$_RISK_RESULT_SCORE
            max_cmd="$cmd_str"
        fi
    done

    if [[ "$MAINFRAME_OUTPUT" == "json" ]]; then
        local escaped_cmd
        escaped_cmd=$(_risk_escape "$max_cmd")
        printf '{"ok":true,"data":{"score":%d,"command":"%s","level":"%s"}}\n' \
            "$max_score" "$escaped_cmd" "$(mainframe_risk_label "$max_score")"
    else
        printf '%d %s\n' "$max_score" "$max_cmd"
    fi
    return 0
}

# @pre: command is non-empty
# @post: returns 0 if safe (score <= 2), 1 otherwise
# @idempotent: yes
# @returns: 0 if safe, 1 if risky
#
# Quick check: is this command safe (score 0-2)?
#
# Usage: mainframe_risk_is_safe ls -la /tmp && echo "safe"
mainframe_risk_is_safe() {
    [[ $# -eq 0 ]] && return 0
    _risk_calculate "$@"
    (( _RISK_RESULT_SCORE <= 2 ))
}

# @pre: command is non-empty
# @post: returns 0 if destructive (score >= 6), 1 otherwise
# @idempotent: yes
# @returns: 0 if destructive, 1 if not
#
# Quick check: is this command destructive (score >= 6)?
#
# Usage: mainframe_risk_is_destructive rm -rf /home && echo "destructive!"
mainframe_risk_is_destructive() {
    [[ $# -eq 0 ]] && return 1
    _risk_calculate "$@"
    (( _RISK_RESULT_SCORE >= 6 ))
}

# @pre: none
# @post: prints current risk configuration as JSON to stdout
# @idempotent: yes
# @returns: 0 always
#
# Show current risk module configuration.
#
# Usage: mainframe_risk_status
mainframe_risk_status() {
    local log_set="false"
    [[ -n "$MAINFRAME_RISK_LOG" ]] && log_set="true"

    local scope_active="false"
    [[ "${MAINFRAME_SCOPE_ENABLED:-0}" == "1" ]] && scope_active="true"

    printf '{"threshold":%d,"confirm_threshold":%d,"json_output":%s,"logging":%s,"scope_integration":%s}\n' \
        "${MAINFRAME_RISK_THRESHOLD:-6}" \
        "${MAINFRAME_RISK_CONFIRM_THRESHOLD:-5}" \
        "$( [[ "${MAINFRAME_RISK_JSON:-1}" == "1" ]] && printf 'true' || printf 'false' )" \
        "$log_set" \
        "$scope_active"
}

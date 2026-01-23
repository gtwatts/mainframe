#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/dryrun.sh - Dry-Run / Plan-and-Apply Execution Model
# =============================================================================
# Description: Enables AI agents to preview what a script would do before
#              executing it. Builds a plan of operations that can be reviewed,
#              modified, reordered, or executed with approval gates. Integrates
#              with USOP (output.sh) for structured output and risk.sh for
#              automatic risk scoring of planned operations.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_DRYRUN_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DRYRUN_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable dry-run mode (0=normal execution, 1=plan-only)
MAINFRAME_DRY_RUN="${MAINFRAME_DRY_RUN:-0}"

# File to write plan to (empty = in-memory only)
MAINFRAME_PLAN_FILE="${MAINFRAME_PLAN_FILE:-}"

# Plan output format: text|json|markdown
MAINFRAME_PLAN_FORMAT="${MAINFRAME_PLAN_FORMAT:-text}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Indexed array of plan steps (each entry is a JSON string)
declare -ga _MAINFRAME_PLAN_STEPS=()

# Counter for plan steps
declare -g _MAINFRAME_PLAN_COUNT=0

# Execution results array (populated after mainframe_plan_execute)
declare -ga _MAINFRAME_PLAN_RESULTS=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string (use json_escape if available, otherwise inline)
_dryrun_escape() {
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

# Compute a basic risk score for a command (0-10 scale)
# If risk.sh is loaded and provides mainframe_risk_score, uses that.
# Otherwise, uses a heuristic based on command category.
_dryrun_risk_score() {
    local command="$1"
    shift
    local args="$*"

    # Delegate to risk.sh if available
    if declare -F mainframe_risk_score &>/dev/null; then
        mainframe_risk_score "$command" "$@"
        return
    fi

    # Heuristic risk scoring
    local score=1
    case "$command" in
        rm|rmdir)              score=7 ;;
        rm\ -rf*|rm\ -r*)     score=9 ;;
        mv)                    score=5 ;;
        cp)                    score=2 ;;
        mkdir)                 score=1 ;;
        chmod|chown)           score=6 ;;
        curl|wget)             score=4 ;;
        dd)                    score=9 ;;
        mkfs*|fdisk|parted)    score=10 ;;
        systemctl|service)     score=7 ;;
        docker)                score=5 ;;
        git\ push*)            score=6 ;;
        git\ reset\ --hard*)   score=8 ;;
        kill|killall|pkill)    score=6 ;;
        write|tee)             score=3 ;;
        *)                     score=2 ;;
    esac

    # Elevate risk if targeting system paths
    if [[ "$args" == */etc/* || "$args" == */usr/* || "$args" == */boot/* ]]; then
        (( score < 10 )) && (( score += 2 ))
        (( score > 10 )) && score=10
    fi

    # Elevate risk for recursive or force flags
    if [[ "$args" == *-rf* || "$args" == *--force* || "$args" == *-R* ]]; then
        (( score < 10 )) && (( score += 1 ))
    fi

    printf '%d' "$score"
}

# Determine if a command is reversible
_dryrun_is_reversible() {
    local command="$1"
    case "$command" in
        mkdir)      printf 'true' ;;
        cp)         printf 'true' ;;
        mv)         printf 'true' ;;
        rm|rmdir)   printf 'false' ;;
        chmod)      printf 'true' ;;
        write|tee)  printf 'false' ;;
        *)          printf 'false' ;;
    esac
}

# Build a JSON step object
_dryrun_build_step() {
    local step_num="$1"
    local description="$2"
    local command="$3"
    shift 3
    local -a args=("$@")

    local risk
    risk=$(_dryrun_risk_score "$command" "${args[@]}")

    local reversible
    reversible=$(_dryrun_is_reversible "$command")

    # Build args JSON array
    local args_json="["
    local first=true
    local arg
    for arg in "${args[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            args_json+=","
        fi
        args_json+="\"$(_dryrun_escape "$arg")\""
    done
    args_json+="]"

    local escaped_desc escaped_cmd
    escaped_desc=$(_dryrun_escape "$description")
    escaped_cmd=$(_dryrun_escape "$command")

    printf '{"step":%d,"command":"%s","args":%s,"risk":%d,"description":"%s","reversible":%s}' \
        "$step_num" "$escaped_cmd" "$args_json" "$risk" "$escaped_desc" "$reversible"
}

# Emit output respecting USOP mode
_dryrun_output() {
    local value="$1"
    local type="${2:-string}"

    if declare -F output &>/dev/null && [[ "$MAINFRAME_OUTPUT" == "json" ]]; then
        output -t "$type" "$value"
    else
        printf '%s\n' "$value"
    fi
}

# Emit error respecting USOP mode
_dryrun_error() {
    local code="$1"
    local msg="$2"

    if declare -F output_error &>/dev/null && [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        output_error "$code" "$msg"
    else
        printf 'error: [%s] %s\n' "$code" "$msg" >&2
    fi
    return 1
}

# Risk level label from numeric score
_dryrun_risk_label() {
    local score="$1"
    if (( score <= 2 )); then
        printf 'LOW'
    elif (( score <= 5 )); then
        printf 'MEDIUM'
    elif (( score <= 7 )); then
        printf 'HIGH'
    else
        printf 'CRITICAL'
    fi
}

# =============================================================================
# PUBLIC API: DRY-RUN MODE
# =============================================================================

# @pre: none
# @post: none (read-only check)
# @returns: 0 if dry-run mode is active, 1 otherwise
#
# Check whether dry-run mode is currently enabled.
#
# Usage: mainframe_dryrun_enabled && echo "dry-run active"
mainframe_dryrun_enabled() {
    [[ "$MAINFRAME_DRY_RUN" == "1" ]]
}

# =============================================================================
# PUBLIC API: PLAN MANAGEMENT
# =============================================================================

# @pre: description and command are non-empty
# @post: step added to _MAINFRAME_PLAN_STEPS; in normal mode, command executed
# @returns: step number (printed to stdout); exit code of command in normal mode
#
# Record a planned operation. In dry-run mode, records but does not execute.
# In normal mode, executes immediately and records for audit trail.
#
# Usage: mainframe_plan_add "Create build directory" mkdir -p ./build
# Usage: step=$(mainframe_plan_add "Remove temp files" rm -f /tmp/scratch.*)
mainframe_plan_add() {
    local description="$1"
    shift
    local command="$1"
    shift
    local -a args=("$@")

    if [[ -z "$description" || -z "$command" ]]; then
        _dryrun_error "E_ARG_MISSING" "mainframe_plan_add: description and command required"
        return 1
    fi

    local step_num=$_MAINFRAME_PLAN_COUNT
    _MAINFRAME_PLAN_COUNT=$(( _MAINFRAME_PLAN_COUNT + 1 ))

    local step_json
    step_json=$(_dryrun_build_step "$step_num" "$description" "$command" "${args[@]}")
    _MAINFRAME_PLAN_STEPS+=("$step_json")

    if mainframe_dryrun_enabled; then
        # Dry-run: print preview message
        printf '[DRY-RUN] Step %d: %s\n' "$step_num" "$description" >&2
        printf '[DRY-RUN]   Would execute: %s' "$command" >&2
        if [[ ${#args[@]} -gt 0 ]]; then
            printf ' %s' "${args[@]}" >&2
        fi
        printf '\n' >&2
    fi

    # Always return step number - execution happens via mainframe_plan_execute
    printf '%d' "$step_num"
    return 0
}

# @pre: plan may have zero or more steps
# @post: plan displayed to stdout in requested format
# @returns: 0
#
# Display the current plan in the specified format.
#
# Usage: mainframe_plan_show
# Usage: mainframe_plan_show --format json
# Usage: mainframe_plan_show --format markdown
mainframe_plan_show() {
    local format="$MAINFRAME_PLAN_FORMAT"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ${#_MAINFRAME_PLAN_STEPS[@]} -eq 0 ]]; then
        case "$format" in
            json) _dryrun_output "[]" "json_array" ;;
            *)    _dryrun_output "(no steps in plan)" ;;
        esac
        return 0
    fi

    case "$format" in
        json)
            local json="["
            local first=true
            local step
            for step in "${_MAINFRAME_PLAN_STEPS[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    json+=","
                fi
                json+="$step"
            done
            json+="]"
            _dryrun_output "$json" "json_array"
            ;;

        markdown)
            local step step_num cmd desc risk_score risk_label
            printf '## Execution Plan (%d steps)\n\n' "${#_MAINFRAME_PLAN_STEPS[@]}"
            for step in "${_MAINFRAME_PLAN_STEPS[@]}"; do
                # Parse fields from JSON (lightweight extraction)
                step_num="${step#*\"step\":}"
                step_num="${step_num%%,*}"
                desc="${step#*\"description\":\"}"
                desc="${desc%%\"*}"
                cmd="${step#*\"command\":\"}"
                cmd="${cmd%%\"*}"
                risk_score="${step#*\"risk\":}"
                risk_score="${risk_score%%,*}"
                risk_score="${risk_score%%\}*}"
                risk_label=$(_dryrun_risk_label "$risk_score")

                printf -- '- [ ] **Step %d** [%s:%d] %s\n' \
                    "$step_num" "$risk_label" "$risk_score" "$desc"
                printf '  - Command: `%s`\n' "$cmd"
            done
            ;;

        text|*)
            local step step_num cmd desc risk_score risk_label
            printf '=== Execution Plan (%d steps) ===\n\n' "${#_MAINFRAME_PLAN_STEPS[@]}"
            for step in "${_MAINFRAME_PLAN_STEPS[@]}"; do
                step_num="${step#*\"step\":}"
                step_num="${step_num%%,*}"
                desc="${step#*\"description\":\"}"
                desc="${desc%%\"*}"
                cmd="${step#*\"command\":\"}"
                cmd="${cmd%%\"*}"
                risk_score="${step#*\"risk\":}"
                risk_score="${risk_score%%,*}"
                risk_score="${risk_score%%\}*}"
                risk_label=$(_dryrun_risk_label "$risk_score")

                printf '  [%d] %-8s (risk:%d) %s\n' \
                    "$step_num" "$risk_label" "$risk_score" "$desc"
                printf '       cmd: %s\n' "$cmd"
            done
            printf '\n'
            ;;
    esac
    return 0
}

# @pre: none
# @post: _MAINFRAME_PLAN_STEPS and _MAINFRAME_PLAN_COUNT reset to empty/zero
# @returns: 0
#
# Clear all recorded plan steps and reset the counter.
#
# Usage: mainframe_plan_clear
mainframe_plan_clear() {
    _MAINFRAME_PLAN_STEPS=()
    _MAINFRAME_PLAN_COUNT=0
    _MAINFRAME_PLAN_RESULTS=()
    return 0
}

# @pre: none
# @post: none (read-only)
# @returns: 0; prints step count to stdout
#
# Print the number of currently recorded plan steps.
#
# Usage: count=$(mainframe_plan_count)
mainframe_plan_count() {
    printf '%d' "${#_MAINFRAME_PLAN_STEPS[@]}"
}

# @pre: plan has steps; optionally --confirm or --step N or --continue-on-error
# @post: commands executed; _MAINFRAME_PLAN_RESULTS populated
# @returns: 0 if all steps succeed, 1 if any fail (unless --continue-on-error)
#
# Execute the recorded plan. With --confirm, displays the plan and waits for
# user confirmation before proceeding. With --step N, executes only that step.
# With --continue-on-error, does not abort on first failure.
#
# Usage: mainframe_plan_execute
# Usage: mainframe_plan_execute --confirm
# Usage: mainframe_plan_execute --step 2
# Usage: mainframe_plan_execute --continue-on-error
mainframe_plan_execute() {
    local confirm=false
    local single_step=-1
    local continue_on_error=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --confirm)           confirm=true; shift ;;
            --step)              single_step="$2"; shift 2 ;;
            --continue-on-error) continue_on_error=true; shift ;;
            *)                   shift ;;
        esac
    done

    if [[ ${#_MAINFRAME_PLAN_STEPS[@]} -eq 0 ]]; then
        _dryrun_error "E_STATE_EMPTY" "No steps in plan to execute"
        return 1
    fi

    # Validate --step index
    if (( single_step >= 0 )); then
        if (( single_step >= ${#_MAINFRAME_PLAN_STEPS[@]} )); then
            _dryrun_error "E_ARG_RANGE" "Step $single_step does not exist (plan has ${#_MAINFRAME_PLAN_STEPS[@]} steps)"
            return 1
        fi
    fi

    # Confirmation gate
    if [[ "$confirm" == "true" ]]; then
        mainframe_plan_show >&2
        mainframe_plan_risk_summary >&2
        printf '\nProceed with execution? [y/N] ' >&2
        local answer
        read -r answer < /dev/tty 2>/dev/null || answer="n"
        case "${answer,,}" in
            y|yes) ;;
            *)
                printf 'Execution cancelled.\n' >&2
                return 1
                ;;
        esac
    fi

    # Execute steps
    _MAINFRAME_PLAN_RESULTS=()
    local all_ok=true
    local i step cmd args_raw rc

    local start_idx=0
    local end_idx=${#_MAINFRAME_PLAN_STEPS[@]}

    if (( single_step >= 0 )); then
        start_idx=$single_step
        end_idx=$(( single_step + 1 ))
    fi

    for (( i=start_idx; i<end_idx; i++ )); do
        step="${_MAINFRAME_PLAN_STEPS[$i]}"

        # Extract command from JSON
        cmd="${step#*\"command\":\"}"
        cmd="${cmd%%\"*}"

        # Extract args from JSON array
        args_raw="${step#*\"args\":}"
        args_raw="${args_raw%%],*}]"

        # Parse args array (lightweight: split on comma, strip quotes)
        local -a exec_args=()
        if [[ "$args_raw" != "[]" ]]; then
            local trimmed="${args_raw#[}"
            trimmed="${trimmed%]}"
            local arg_item=""
            local in_string=false
            local escaped=false
            local char
            local j
            for (( j=0; j<${#trimmed}; j++ )); do
                char="${trimmed:$j:1}"
                if [[ "$escaped" == "true" ]]; then
                    arg_item+="$char"
                    escaped=false
                    continue
                fi
                if [[ "$char" == "\\" ]]; then
                    escaped=true
                    arg_item+="$char"
                    continue
                fi
                if [[ "$char" == '"' ]]; then
                    if [[ "$in_string" == "true" ]]; then
                        in_string=false
                    else
                        in_string=true
                    fi
                    continue
                fi
                if [[ "$char" == "," && "$in_string" == "false" ]]; then
                    # Unescape the collected arg
                    arg_item="${arg_item//\\\\/\\}"
                    arg_item="${arg_item//\\\"/\"}"
                    arg_item="${arg_item//\\n/$'\n'}"
                    arg_item="${arg_item//\\t/$'\t'}"
                    exec_args+=("$arg_item")
                    arg_item=""
                    continue
                fi
                arg_item+="$char"
            done
            # Last argument
            if [[ -n "$arg_item" || "$in_string" == "false" ]]; then
                arg_item="${arg_item//\\\\/\\}"
                arg_item="${arg_item//\\\"/\"}"
                arg_item="${arg_item//\\n/$'\n'}"
                arg_item="${arg_item//\\t/$'\t'}"
                [[ -n "$arg_item" ]] && exec_args+=("$arg_item")
            fi
        fi

        # Execute
        printf '[EXEC] Step %d: %s\n' "$i" "$cmd" >&2
        "$cmd" "${exec_args[@]}"
        rc=$?

        if (( rc == 0 )); then
            _MAINFRAME_PLAN_RESULTS+=("{\"step\":$i,\"status\":\"success\",\"exit_code\":0}")
        else
            _MAINFRAME_PLAN_RESULTS+=("{\"step\":$i,\"status\":\"failed\",\"exit_code\":$rc}")
            all_ok=false
            if [[ "$continue_on_error" != "true" ]]; then
                printf '[EXEC] Step %d FAILED (exit code %d). Aborting.\n' "$i" "$rc" >&2
                return 1
            else
                printf '[EXEC] Step %d FAILED (exit code %d). Continuing.\n' "$i" "$rc" >&2
            fi
        fi
    done

    if [[ "$all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# @pre: plan may have steps
# @post: plan written to file or stdout in MAINFRAME_PLAN_FORMAT
# @returns: 0
#
# Export the plan to a file or stdout. Uses MAINFRAME_PLAN_FORMAT for formatting.
#
# Usage: mainframe_plan_export
# Usage: mainframe_plan_export /tmp/plan.json
mainframe_plan_export() {
    local file="${1:-${MAINFRAME_PLAN_FILE:-}}"

    if [[ -n "$file" ]]; then
        mainframe_plan_show --format "$MAINFRAME_PLAN_FORMAT" > "$file"
    else
        mainframe_plan_show --format "$MAINFRAME_PLAN_FORMAT"
    fi
    return 0
}

# @pre: step_number is a valid index into _MAINFRAME_PLAN_STEPS
# @post: step removed; remaining steps NOT renumbered (sparse array)
# @returns: 0 on success, 1 if step not found
#
# Remove a specific step from the plan by its step number.
#
# Usage: mainframe_plan_remove 2
mainframe_plan_remove() {
    local step_number="$1"

    if [[ -z "$step_number" ]]; then
        _dryrun_error "E_ARG_MISSING" "mainframe_plan_remove: step number required"
        return 1
    fi

    if [[ ! "$step_number" =~ ^[0-9]+$ ]]; then
        _dryrun_error "E_ARG_TYPE" "mainframe_plan_remove: step number must be integer"
        return 1
    fi

    if (( step_number >= ${#_MAINFRAME_PLAN_STEPS[@]} )); then
        _dryrun_error "E_ARG_RANGE" "Step $step_number does not exist"
        return 1
    fi

    # Rebuild the array without the removed step, renumbering sequentially
    local -a new_steps=()
    local i step new_num=0
    for (( i=0; i<${#_MAINFRAME_PLAN_STEPS[@]}; i++ )); do
        if (( i == step_number )); then
            continue
        fi
        step="${_MAINFRAME_PLAN_STEPS[$i]}"
        # Renumber step in JSON by splitting on the "step": field
        local prefix="${step%%\"step\":*}"
        local suffix="${step#*\"step\":}"
        suffix="${suffix#*,}"
        new_steps+=("${prefix}\"step\":${new_num},${suffix}")
        (( new_num++ )) || true
    done

    _MAINFRAME_PLAN_STEPS=("${new_steps[@]}")
    _MAINFRAME_PLAN_COUNT=${#_MAINFRAME_PLAN_STEPS[@]}
    return 0
}

# @pre: old_pos and new_pos are valid indices
# @post: step moved to new position; all steps renumbered sequentially
# @returns: 0 on success, 1 on invalid positions
#
# Move a step from one position to another, shifting other steps accordingly.
#
# Usage: mainframe_plan_reorder 3 0    # Move step 3 to position 0
mainframe_plan_reorder() {
    local old_pos="$1"
    local new_pos="$2"

    if [[ -z "$old_pos" || -z "$new_pos" ]]; then
        _dryrun_error "E_ARG_MISSING" "mainframe_plan_reorder: old_pos and new_pos required"
        return 1
    fi

    local count=${#_MAINFRAME_PLAN_STEPS[@]}

    if (( old_pos >= count || new_pos >= count )); then
        _dryrun_error "E_ARG_RANGE" "Position out of range (plan has $count steps)"
        return 1
    fi

    if (( old_pos == new_pos )); then
        return 0
    fi

    # Extract the step to move
    local moving_step="${_MAINFRAME_PLAN_STEPS[$old_pos]}"

    # Build new array with the step removed then inserted at new position
    local -a without=()
    local i
    for (( i=0; i<count; i++ )); do
        if (( i != old_pos )); then
            without+=("${_MAINFRAME_PLAN_STEPS[$i]}")
        fi
    done

    # Insert at new position
    local -a reordered=()
    local inserted=false
    for (( i=0; i<${#without[@]}; i++ )); do
        if (( i == new_pos )) && [[ "$inserted" == "false" ]]; then
            reordered+=("$moving_step")
            inserted=true
        fi
        reordered+=("${without[$i]}")
    done
    # If new_pos is at the end
    if [[ "$inserted" == "false" ]]; then
        reordered+=("$moving_step")
    fi

    # Renumber all steps
    local -a final=()
    for (( i=0; i<${#reordered[@]}; i++ )); do
        local step="${reordered[$i]}"
        local prefix="${step%%\"step\":*}"
        local suffix="${step#*\"step\":}"
        suffix="${suffix#*,}"
        final+=("${prefix}\"step\":${i},${suffix}")
    done

    _MAINFRAME_PLAN_STEPS=("${final[@]}")
    _MAINFRAME_PLAN_COUNT=${#_MAINFRAME_PLAN_STEPS[@]}
    return 0
}

# @pre: plan may have steps
# @post: none (read-only)
# @returns: 0; prints risk summary to stdout
#
# Show aggregate risk information: total score, max score, and distribution
# across risk levels. Useful for approval gates.
#
# Usage: mainframe_plan_risk_summary
mainframe_plan_risk_summary() {
    if [[ ${#_MAINFRAME_PLAN_STEPS[@]} -eq 0 ]]; then
        _dryrun_output "(no steps to assess)"
        return 0
    fi

    local total_risk=0
    local max_risk=0
    local low=0 medium=0 high=0 critical=0
    local step risk_score

    for step in "${_MAINFRAME_PLAN_STEPS[@]}"; do
        risk_score="${step#*\"risk\":}"
        risk_score="${risk_score%%,*}"
        risk_score="${risk_score%%\}*}"

        (( total_risk += risk_score ))
        (( risk_score > max_risk )) && max_risk=$risk_score

        if (( risk_score <= 2 )); then
            (( low++ )) || true
        elif (( risk_score <= 5 )); then
            (( medium++ )) || true
        elif (( risk_score <= 7 )); then
            (( high++ )) || true
        else
            (( critical++ )) || true
        fi
    done

    local count=${#_MAINFRAME_PLAN_STEPS[@]}
    local avg_risk=$(( total_risk / count ))

    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local json
        json=$(printf '{"total_risk":%d,"max_risk":%d,"avg_risk":%d,"steps":%d,"distribution":{"low":%d,"medium":%d,"high":%d,"critical":%d}}' \
            "$total_risk" "$max_risk" "$avg_risk" "$count" "$low" "$medium" "$high" "$critical")
        _dryrun_output "$json" "json_object"
    else
        printf '\n--- Risk Summary ---\n'
        printf '  Steps:     %d\n' "$count"
        printf '  Total:     %d\n' "$total_risk"
        printf '  Max:       %d (%s)\n' "$max_risk" "$(_dryrun_risk_label "$max_risk")"
        printf '  Average:   %d\n' "$avg_risk"
        printf '  LOW:       %d | MEDIUM: %d | HIGH: %d | CRITICAL: %d\n' \
            "$low" "$medium" "$high" "$critical"
    fi
    return 0
}

# @pre: _MAINFRAME_PLAN_RESULTS populated (after mainframe_plan_execute)
# @post: none (read-only)
# @returns: 0; prints execution results to stdout
#
# Display the success/failure status of each executed step.
#
# Usage: mainframe_plan_results
mainframe_plan_results() {
    if [[ ${#_MAINFRAME_PLAN_RESULTS[@]} -eq 0 ]]; then
        _dryrun_output "(no execution results available)"
        return 0
    fi

    if [[ "${MAINFRAME_OUTPUT:-raw}" == "json" ]]; then
        local json="["
        local first=true
        local result
        for result in "${_MAINFRAME_PLAN_RESULTS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                json+=","
            fi
            json+="$result"
        done
        json+="]"
        _dryrun_output "$json" "json_array"
    else
        printf '=== Execution Results ===\n'
        local result step_num status exit_code
        for result in "${_MAINFRAME_PLAN_RESULTS[@]}"; do
            step_num="${result#*\"step\":}"
            step_num="${step_num%%,*}"
            status="${result#*\"status\":\"}"
            status="${status%%\"*}"
            exit_code="${result#*\"exit_code\":}"
            exit_code="${exit_code%%\}*}"

            if [[ "$status" == "success" ]]; then
                printf '  [%d] OK   (exit: %s)\n' "$step_num" "$exit_code"
            else
                printf '  [%d] FAIL (exit: %s)\n' "$step_num" "$exit_code"
            fi
        done
    fi
    return 0
}

# =============================================================================
# WRAPPER FUNCTIONS (Transparent Dry-Run Wrappers)
# =============================================================================

# @pre: command is non-empty
# @post: in dry-run: step recorded, nothing executed; in normal: command executed
# @returns: 0 in dry-run; command exit code in normal mode
#
# Execute a command, or record it if in dry-run mode.
#
# Usage: dryrun_exec ls -la /tmp
# Usage: dryrun_exec docker compose up -d
dryrun_exec() {
    local command="$1"
    shift
    local -a args=("$@")

    if [[ -z "$command" ]]; then
        _dryrun_error "E_ARG_MISSING" "dryrun_exec: command required"
        return 1
    fi

    if mainframe_dryrun_enabled; then
        local desc="Execute: $command"
        if [[ ${#args[@]} -gt 0 ]]; then
            desc+=" ${args[*]}"
        fi
        mainframe_plan_add "$desc" "$command" "${args[@]}" > /dev/null
        printf '[DRY-RUN] Would execute: %s' "$command" >&2
        [[ ${#args[@]} -gt 0 ]] && printf ' %s' "${args[@]}" >&2
        printf '\n' >&2
        return 0
    else
        "$command" "${args[@]}"
        return $?
    fi
}

# @pre: file path is non-empty
# @post: in dry-run: step recorded; in normal: file written
# @returns: 0 in dry-run; write result in normal mode
#
# Write content to a file, or record the write if in dry-run mode.
#
# Usage: dryrun_write "/tmp/config.json" '{"key":"value"}'
dryrun_write() {
    local file="$1"
    local content="$2"

    if [[ -z "$file" ]]; then
        _dryrun_error "E_ARG_MISSING" "dryrun_write: file path required"
        return 1
    fi

    local byte_count=${#content}

    if mainframe_dryrun_enabled; then
        mainframe_plan_add "Write $file ($byte_count bytes)" "write" "$file" > /dev/null
        printf '[DRY-RUN] Would write: %s (%d bytes)\n' "$file" "$byte_count" >&2
        return 0
    else
        printf '%s' "$content" > "$file"
        return $?
    fi
}

# @pre: path is non-empty
# @post: in dry-run: step recorded; in normal: path removed
# @returns: 0 in dry-run; rm result in normal mode
#
# Remove a path, or record the removal if in dry-run mode.
#
# Usage: dryrun_rm "/tmp/scratch.txt"
# Usage: dryrun_rm "/tmp/build_dir"
dryrun_rm() {
    local path="$1"

    if [[ -z "$path" ]]; then
        _dryrun_error "E_ARG_MISSING" "dryrun_rm: path required"
        return 1
    fi

    if mainframe_dryrun_enabled; then
        mainframe_plan_add "Remove $path" "rm" "-rf" "$path" > /dev/null
        printf '[DRY-RUN] Would remove: %s\n' "$path" >&2
        return 0
    else
        rm -rf "$path"
        return $?
    fi
}

# @pre: path is non-empty
# @post: in dry-run: step recorded; in normal: directory created
# @returns: 0 in dry-run; mkdir result in normal mode
#
# Create a directory (with -p), or record if in dry-run mode.
#
# Usage: dryrun_mkdir "/tmp/build/output"
dryrun_mkdir() {
    local path="$1"

    if [[ -z "$path" ]]; then
        _dryrun_error "E_ARG_MISSING" "dryrun_mkdir: path required"
        return 1
    fi

    if mainframe_dryrun_enabled; then
        mainframe_plan_add "Create directory $path" "mkdir" "-p" "$path" > /dev/null
        printf '[DRY-RUN] Would create directory: %s\n' "$path" >&2
        return 0
    else
        mkdir -p "$path"
        return $?
    fi
}

# @pre: src and dst are non-empty
# @post: in dry-run: step recorded; in normal: file moved
# @returns: 0 in dry-run; mv result in normal mode
#
# Move a file or directory, or record if in dry-run mode.
#
# Usage: dryrun_mv "/tmp/old.txt" "/tmp/new.txt"
dryrun_mv() {
    local src="$1"
    local dst="$2"

    if [[ -z "$src" || -z "$dst" ]]; then
        _dryrun_error "E_ARG_MISSING" "dryrun_mv: source and destination required"
        return 1
    fi

    if mainframe_dryrun_enabled; then
        mainframe_plan_add "Move $src to $dst" "mv" "$src" "$dst" > /dev/null
        printf '[DRY-RUN] Would move: %s -> %s\n' "$src" "$dst" >&2
        return 0
    else
        mv "$src" "$dst"
        return $?
    fi
}

# @pre: src and dst are non-empty
# @post: in dry-run: step recorded; in normal: file copied
# @returns: 0 in dry-run; cp result in normal mode
#
# Copy a file or directory, or record if in dry-run mode.
#
# Usage: dryrun_cp "/tmp/source.txt" "/tmp/backup.txt"
dryrun_cp() {
    local src="$1"
    local dst="$2"

    if [[ -z "$src" || -z "$dst" ]]; then
        _dryrun_error "E_ARG_MISSING" "dryrun_cp: source and destination required"
        return 1
    fi

    if mainframe_dryrun_enabled; then
        mainframe_plan_add "Copy $src to $dst" "cp" "-r" "$src" "$dst" > /dev/null
        printf '[DRY-RUN] Would copy: %s -> %s\n' "$src" "$dst" >&2
        return 0
    else
        cp -r "$src" "$dst"
        return $?
    fi
}

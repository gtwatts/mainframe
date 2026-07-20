#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/parallel.sh - Parallel Execution Patterns
# =============================================================================
# Description: High-level parallel execution patterns for AI agent workflows.
#              Provides map, race, all, any, batch, and retry operations with
#              USOP-compliant JSON output and progress reporting.
#
# Dependencies: async.sh (for non-blocking execution primitives)
#
# Version: 1.0.0
# Requires: Bash 4.3+ (for namerefs and wait -n)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PARALLEL_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PARALLEL_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Auto-source dependencies if not loaded
if [[ -z "${_MAINFRAME_ASYNC_LOADED:-}" ]]; then
    _parallel_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_parallel_lib_dir}/async.sh" ]]; then
        source "${_parallel_lib_dir}/async.sh"
    fi
fi

if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    _parallel_lib_dir="${BASH_SOURCE[0]%/*}"
    if [[ -f "${_parallel_lib_dir}/json.sh" ]]; then
        source "${_parallel_lib_dir}/json.sh"
    fi
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default concurrency limit
PARALLEL_DEFAULT_CONCURRENCY="${PARALLEL_DEFAULT_CONCURRENCY:-4}"

# Default timeout for parallel operations (seconds)
PARALLEL_DEFAULT_TIMEOUT="${PARALLEL_DEFAULT_TIMEOUT:-300}"

# Default retry attempts
PARALLEL_DEFAULT_MAX_ATTEMPTS="${PARALLEL_DEFAULT_MAX_ATTEMPTS:-3}"

# Default batch size
PARALLEL_DEFAULT_BATCH_SIZE="${PARALLEL_DEFAULT_BATCH_SIZE:-10}"

# State directory for coordination files
PARALLEL_STATE_DIR="${PARALLEL_STATE_DIR:-${TMPDIR:-/tmp}/mainframe_parallel}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get current time in milliseconds
_parallel_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        local seconds="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        frac="${frac}000"
        printf '%s%s' "$seconds" "${frac:0:3}"
    else
        local ns
        ns=$(date +%s%N 2>/dev/null)
        if [[ "$ns" =~ ^[0-9]+$ && ${#ns} -gt 6 ]]; then
            printf '%s' "${ns:0:${#ns}-6}"
        else
            printf '%s000' "$(date +%s)"
        fi
    fi
}

# JSON escape helper
_parallel_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Build result JSON object
_parallel_build_result() {
    local ok="$1"
    local results_json="$2"
    local total_duration_ms="$3"
    local succeeded="$4"
    local failed="$5"
    local hint="${6:-}"

    local json="{"
    json+="\"ok\":$ok,"
    json+="\"data\":{"
    json+="\"results\":$results_json,"
    json+="\"total_duration_ms\":$total_duration_ms,"
    json+="\"succeeded\":$succeeded,"
    json+="\"failed\":$failed"
    json+="}"
    if [[ -n "$hint" ]]; then
        json+=",\"hint\":\"$(_parallel_json_escape "$hint")\""
    fi
    json+="}"

    printf '%s' "$json"
}

# Build single result entry
_parallel_build_entry() {
    local index="$1"
    local status="$2"
    local result="$3"
    local duration_ms="$4"
    local error="${5:-}"

    local json="{"
    json+="\"index\":$index,"
    json+="\"status\":\"$status\","
    json+="\"result\":\"$(_parallel_json_escape "$result")\","
    json+="\"duration_ms\":$duration_ms"
    if [[ -n "$error" ]]; then
        json+=",\"error\":\"$(_parallel_json_escape "$error")\""
    fi
    json+="}"

    printf '%s' "$json"
}

# Log helper (respects MAINFRAME_QUIET)
_parallel_log() {
    local level="$1"
    shift
    if [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[parallel] %s: %s\n' "$level" "$*" >&2
    fi
}

# Check if wait -n is supported (Bash 4.3+)
_parallel_has_wait_n() {
    ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3)))
}

# Wait for any child process (with fallback for older bash)
_parallel_wait_any() {
    if _parallel_has_wait_n; then
        wait -n 2>/dev/null
        return $?
    else
        # Fallback: poll until a child exits
        sleep 0.1
        return 0
    fi
}

# =============================================================================
# PARALLEL MAP
# =============================================================================

# @pre: function is callable, items is array
# @post: function applied to each item in parallel
# @returns: JSON result with all outputs
#
# Apply function to each item in parallel
#
# Usage: parallel_map "function" "${items[@]}"
# Example: results=$(parallel_map "curl -s" "http://a.com" "http://b.com")
parallel_map() {
    local func="$1"
    shift
    local -a items=("$@")

    local start_ms
    start_ms=$(_parallel_now_ms)

    # Track PIDs and their indices
    local -a pids=()
    local -a outputs=()
    local -a durations=()
    local -a statuses=()
    local -a tmpfiles=()

    # Ensure state directory exists
    mkdir -p "$PARALLEL_STATE_DIR"

    # Launch all tasks
    local i
    for i in "${!items[@]}"; do
        local item="${items[$i]}"
        local tmpfile
        tmpfile=$(mktemp "$PARALLEL_STATE_DIR/parallel_map_XXXXXX")
        tmpfiles+=("$tmpfile")

        (
            local task_start
            task_start=$(_parallel_now_ms)
            local output status
            output=$($func "$item" 2>&1)
            status=$?
            local task_end
            task_end=$(_parallel_now_ms)
            local task_duration=$((task_end - task_start))
            printf '%d\n%d\n%s' "$status" "$task_duration" "$output" > "$tmpfile"
        ) &
        pids+=($!)
    done

    # Wait for all tasks
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    # Collect results
    local succeeded=0
    local failed=0
    local results_json="["
    local first=true

    for i in "${!tmpfiles[@]}"; do
        local tmpfile="${tmpfiles[$i]}"
        if [[ -f "$tmpfile" ]]; then
            local content
            content=$(<"$tmpfile")
            rm -f "$tmpfile"

            local status duration output
            status=$(echo "$content" | head -1)
            duration=$(echo "$content" | sed -n '2p')
            output=$(echo "$content" | tail -n +3)

            local entry_status="done"
            local error=""
            if [[ "$status" -ne 0 ]]; then
                entry_status="error"
                error="exit code $status"
                ((failed++))
            else
                ((succeeded++))
            fi

            $first || results_json+=","
            first=false
            results_json+=$(_parallel_build_entry "$i" "$entry_status" "$output" "${duration:-0}" "$error")
        fi
    done
    results_json+="]"

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
}

# @pre: function is callable, n > 0, items is array
# @post: function applied with max n concurrent
# @returns: JSON result with all outputs
#
# Map with concurrency limit
#
# Usage: parallel_map_n "function" 4 "${items[@]}"
# Example: results=$(parallel_map_n "process_url" 4 "${urls[@]}")
parallel_map_n() {
    local func="$1"
    local limit="$2"
    shift 2
    local -a items=("$@")

    local start_ms
    start_ms=$(_parallel_now_ms)

    # Validate limit
    [[ "$limit" -lt 1 ]] && limit=1

    # Track state
    local -a pids=()
    local -a pid_to_index=()
    local -a tmpfiles=()
    local running=0
    local next_index=0

    # Ensure state directory
    mkdir -p "$PARALLEL_STATE_DIR"

    # Process items with concurrency limit
    while [[ $next_index -lt ${#items[@]} ]] || [[ $running -gt 0 ]]; do
        # Start new jobs up to limit
        while [[ $running -lt $limit ]] && [[ $next_index -lt ${#items[@]} ]]; do
            local item="${items[$next_index]}"
            local tmpfile
            tmpfile=$(mktemp "$PARALLEL_STATE_DIR/parallel_map_n_XXXXXX")
            tmpfiles[$next_index]="$tmpfile"

            (
                local task_start
                task_start=$(_parallel_now_ms)
                local output status
                output=$($func "$item" 2>&1)
                status=$?
                local task_end
                task_end=$(_parallel_now_ms)
                local task_duration=$((task_end - task_start))
                printf '%d\n%d\n%s' "$status" "$task_duration" "$output" > "$tmpfile"
            ) &

            local pid=$!
            pids+=("$pid")
            pid_to_index[$pid]=$next_index
            ((running++))
            ((next_index++))
        done

        # Wait for any job to finish
        if [[ $running -gt 0 ]]; then
            _parallel_wait_any
            # Check which jobs have finished
            local pid
            for pid in "${!pid_to_index[@]}"; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    unset "pid_to_index[$pid]"
                    ((running--))
                fi
            done
        fi
    done

    # Final wait for stragglers
    wait 2>/dev/null

    # Collect results
    local succeeded=0
    local failed=0
    local results_json="["
    local first=true

    local i
    for i in "${!items[@]}"; do
        local tmpfile="${tmpfiles[$i]}"
        if [[ -f "$tmpfile" ]]; then
            local content
            content=$(<"$tmpfile")
            rm -f "$tmpfile"

            local status duration output
            status=$(echo "$content" | head -1)
            duration=$(echo "$content" | sed -n '2p')
            output=$(echo "$content" | tail -n +3)

            local entry_status="done"
            local error=""
            if [[ "$status" -ne 0 ]]; then
                entry_status="error"
                error="exit code $status"
                ((failed++))
            else
                ((succeeded++))
            fi

            $first || results_json+=","
            first=false
            results_json+=$(_parallel_build_entry "$i" "$entry_status" "$output" "${duration:-0}" "$error")
        fi
    done
    results_json+="]"

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
}

# =============================================================================
# PARALLEL RACE / ALL / ANY
# =============================================================================

# @pre: at least one command provided
# @post: first command to complete wins, others cancelled
# @returns: JSON with winner's result
#
# First to complete wins, cancel others
#
# Usage: parallel_race "cmd1" "cmd2" "cmd3"
# Example: content=$(parallel_race "curl mirror1/file" "curl mirror2/file")
parallel_race() {
    local -a commands=("$@")

    if [[ ${#commands[@]} -eq 0 ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_COMMANDS","msg":"No commands provided"}}'
        return 1
    fi

    local start_ms
    start_ms=$(_parallel_now_ms)

    # Ensure state directory
    mkdir -p "$PARALLEL_STATE_DIR"

    local -a pids=()
    local -a tmpfiles=()

    # Launch all commands
    local i
    for i in "${!commands[@]}"; do
        local cmd="${commands[$i]}"
        local tmpfile
        tmpfile=$(mktemp "$PARALLEL_STATE_DIR/parallel_race_XXXXXX")
        tmpfiles+=("$tmpfile")

        (
            local task_start
            task_start=$(_parallel_now_ms)
            local output status
            # Use eval for command strings with pipes/redirects
            output=$(eval "$cmd" 2>&1)
            status=$?
            local task_end
            task_end=$(_parallel_now_ms)
            local task_duration=$((task_end - task_start))
            printf '%d\n%d\n%s' "$status" "$task_duration" "$output" > "$tmpfile"
        ) &
        pids+=($!)
    done

    # Wait for first to complete
    local winner_pid=-1
    local winner_index=-1

    if _parallel_has_wait_n; then
        # Bash 4.3+: Use wait -n
        wait -n "${pids[@]}" 2>/dev/null
        # Find which one finished
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                winner_index=$i
                winner_pid=${pids[$i]}
                break
            fi
        done
    else
        # Fallback: Poll until one finishes
        while [[ $winner_index -eq -1 ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    winner_index=$i
                    winner_pid=${pids[$i]}
                    break 2
                fi
            done
            sleep 0.05
        done
    fi

    # Kill remaining processes
    for i in "${!pids[@]}"; do
        if [[ $i -ne $winner_index ]]; then
            kill -TERM "${pids[$i]}" 2>/dev/null
            kill -KILL "${pids[$i]}" 2>/dev/null
        fi
    done

    # Wait for killed processes to clean up
    wait 2>/dev/null

    # Read winner's result
    local tmpfile="${tmpfiles[$winner_index]}"
    local status=1
    local duration=0
    local output=""

    if [[ -f "$tmpfile" ]]; then
        local content
        content=$(<"$tmpfile")
        status=$(echo "$content" | head -1)
        duration=$(echo "$content" | sed -n '2p')
        output=$(echo "$content" | tail -n +3)
    fi

    # Cleanup all temp files
    local tf
    for tf in "${tmpfiles[@]}"; do
        rm -f "$tf" 2>/dev/null
    done

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    local entry_status="done"
    local error=""
    if [[ "$status" -ne 0 ]]; then
        ok="false"
        entry_status="error"
        error="exit code $status"
    fi

    local results_json="["
    results_json+=$(_parallel_build_entry "$winner_index" "$entry_status" "$output" "${duration:-0}" "$error")
    results_json+="]"

    local succeeded=0
    local failed=0
    [[ "$ok" == "true" ]] && succeeded=1 || failed=1

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed" "winner_index=$winner_index"
}

# @pre: at least one command provided
# @post: all commands completed
# @returns: JSON with all results
#
# Wait for all, return all results
#
# Usage: parallel_all "cmd1" "cmd2" "cmd3"
# Example: results=$(parallel_all "check_service1" "check_service2")
parallel_all() {
    local -a commands=("$@")

    if [[ ${#commands[@]} -eq 0 ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_COMMANDS","msg":"No commands provided"}}'
        return 1
    fi

    local start_ms
    start_ms=$(_parallel_now_ms)

    # Ensure state directory
    mkdir -p "$PARALLEL_STATE_DIR"

    local -a pids=()
    local -a tmpfiles=()

    # Launch all commands
    local i
    for i in "${!commands[@]}"; do
        local cmd="${commands[$i]}"
        local tmpfile
        tmpfile=$(mktemp "$PARALLEL_STATE_DIR/parallel_all_XXXXXX")
        tmpfiles+=("$tmpfile")

        (
            local task_start
            task_start=$(_parallel_now_ms)
            local output status
            output=$(eval "$cmd" 2>&1)
            status=$?
            local task_end
            task_end=$(_parallel_now_ms)
            local task_duration=$((task_end - task_start))
            printf '%d\n%d\n%s' "$status" "$task_duration" "$output" > "$tmpfile"
        ) &
        pids+=($!)
    done

    # Wait for all
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    # Collect results
    local succeeded=0
    local failed=0
    local results_json="["
    local first=true

    for i in "${!tmpfiles[@]}"; do
        local tmpfile="${tmpfiles[$i]}"
        if [[ -f "$tmpfile" ]]; then
            local content
            content=$(<"$tmpfile")
            rm -f "$tmpfile"

            local status duration output
            status=$(echo "$content" | head -1)
            duration=$(echo "$content" | sed -n '2p')
            output=$(echo "$content" | tail -n +3)

            local entry_status="done"
            local error=""
            if [[ "$status" -ne 0 ]]; then
                entry_status="error"
                error="exit code $status"
                ((failed++))
            else
                ((succeeded++))
            fi

            $first || results_json+=","
            first=false
            results_json+=$(_parallel_build_entry "$i" "$entry_status" "$output" "${duration:-0}" "$error")
        fi
    done
    results_json+="]"

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
}

# @pre: at least one command provided
# @post: returns success if any command succeeds
# @returns: JSON with all results, ok=true if any succeeded
#
# Any success = overall success
#
# Usage: parallel_any "cmd1" "cmd2" "cmd3"
# Example: result=$(parallel_any "ping -c1 server1" "ping -c1 server2")
parallel_any() {
    local -a commands=("$@")

    if [[ ${#commands[@]} -eq 0 ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_COMMANDS","msg":"No commands provided"}}'
        return 1
    fi

    local start_ms
    start_ms=$(_parallel_now_ms)

    # Ensure state directory
    mkdir -p "$PARALLEL_STATE_DIR"

    local -a pids=()
    local -a tmpfiles=()

    # Launch all commands
    local i
    for i in "${!commands[@]}"; do
        local cmd="${commands[$i]}"
        local tmpfile
        tmpfile=$(mktemp "$PARALLEL_STATE_DIR/parallel_any_XXXXXX")
        tmpfiles+=("$tmpfile")

        (
            local task_start
            task_start=$(_parallel_now_ms)
            local output status
            output=$(eval "$cmd" 2>&1)
            status=$?
            local task_end
            task_end=$(_parallel_now_ms)
            local task_duration=$((task_end - task_start))
            printf '%d\n%d\n%s' "$status" "$task_duration" "$output" > "$tmpfile"
        ) &
        pids+=($!)
    done

    # Wait for all
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    # Collect results
    local succeeded=0
    local failed=0
    local results_json="["
    local first=true

    for i in "${!tmpfiles[@]}"; do
        local tmpfile="${tmpfiles[$i]}"
        if [[ -f "$tmpfile" ]]; then
            local content
            content=$(<"$tmpfile")
            rm -f "$tmpfile"

            local status duration output
            status=$(echo "$content" | head -1)
            duration=$(echo "$content" | sed -n '2p')
            output=$(echo "$content" | tail -n +3)

            local entry_status="done"
            local error=""
            if [[ "$status" -ne 0 ]]; then
                entry_status="error"
                error="exit code $status"
                ((failed++))
            else
                ((succeeded++))
            fi

            $first || results_json+=","
            first=false
            results_json+=$(_parallel_build_entry "$i" "$entry_status" "$output" "${duration:-0}" "$error")
        fi
    done
    results_json+="]"

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    # Any success = overall success
    local ok="false"
    [[ $succeeded -gt 0 ]] && ok="true"

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
}

# =============================================================================
# SEQUENTIAL EXECUTION (FOR COMPARISON)
# =============================================================================

# @pre: at least one command provided
# @post: commands executed sequentially
# @returns: JSON with all results
#
# Run commands in sequence (for comparison/debugging)
#
# Usage: parallel_sequence "cmd1" "cmd2"
parallel_sequence() {
    local -a commands=("$@")

    if [[ ${#commands[@]} -eq 0 ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_COMMANDS","msg":"No commands provided"}}'
        return 1
    fi

    local start_ms
    start_ms=$(_parallel_now_ms)

    local succeeded=0
    local failed=0
    local results_json="["
    local first=true

    local i
    for i in "${!commands[@]}"; do
        local cmd="${commands[$i]}"

        local task_start
        task_start=$(_parallel_now_ms)

        local output status
        output=$(eval "$cmd" 2>&1)
        status=$?

        local task_end
        task_end=$(_parallel_now_ms)
        local task_duration=$((task_end - task_start))

        local entry_status="done"
        local error=""
        if [[ "$status" -ne 0 ]]; then
            entry_status="error"
            error="exit code $status"
            ((failed++))
        else
            ((succeeded++))
        fi

        $first || results_json+=","
        first=false
        results_json+=$(_parallel_build_entry "$i" "$entry_status" "$output" "$task_duration" "$error")
    done
    results_json+="]"

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
}

# =============================================================================
# BATCH PROCESSING
# =============================================================================

# @pre: commands array, batch_size > 0
# @post: commands processed in batches
# @returns: JSON with all results
#
# Process in batches with optional concurrency per batch
#
# Usage: parallel_batch "${cmds[@]}" --batch-size 5
# Usage: parallel_batch --batch-size 10 --command "process_item" "${items[@]}"
parallel_batch() {
    local batch_size="$PARALLEL_DEFAULT_BATCH_SIZE"
    local command_template=""
    local -a items=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --batch-size)
                batch_size="$2"
                shift 2
                ;;
            --command)
                command_template="$2"
                shift 2
                ;;
            --)
                shift
                items+=("$@")
                break
                ;;
            -*)
                _parallel_log error "Unknown option: $1"
                printf '{"ok":false,"error":{"code":"E_INVALID_OPTION","msg":"Unknown option: %s"}}' "$1"
                return 1
                ;;
            *)
                items+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#items[@]} -eq 0 ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_ITEMS","msg":"No items provided"}}'
        return 1
    fi

    [[ "$batch_size" -lt 1 ]] && batch_size=1

    local start_ms
    start_ms=$(_parallel_now_ms)

    local total_succeeded=0
    local total_failed=0
    local all_results="["
    local first=true
    local global_index=0

    # Process in batches
    local i=0
    while [[ $i -lt ${#items[@]} ]]; do
        local batch_end=$((i + batch_size))
        [[ $batch_end -gt ${#items[@]} ]] && batch_end=${#items[@]}

        # Build batch commands
        local -a batch_cmds=()
        local j
        for ((j = i; j < batch_end; j++)); do
            local item="${items[$j]}"
            if [[ -n "$command_template" ]]; then
                batch_cmds+=("$command_template \"$item\"")
            else
                batch_cmds+=("$item")
            fi
        done

        # Execute batch using parallel_all
        local batch_result
        batch_result=$(parallel_all "${batch_cmds[@]}")

        # Extract results from batch
        # Parse the results array from the batch_result
        local batch_results
        batch_results=$(echo "$batch_result" | grep -o '"results":\[[^]]*\]' | sed 's/"results"://')

        # Update counters
        local batch_succeeded batch_failed
        batch_succeeded=$(echo "$batch_result" | grep -o '"succeeded":[0-9]*' | cut -d: -f2)
        batch_failed=$(echo "$batch_result" | grep -o '"failed":[0-9]*' | cut -d: -f2)
        total_succeeded=$((total_succeeded + batch_succeeded))
        total_failed=$((total_failed + batch_failed))

        # Append results (need to adjust indices)
        if [[ -n "$batch_results" && "$batch_results" != "[]" ]]; then
            # Strip brackets and add with adjusted indices
            local inner="${batch_results#[}"
            inner="${inner%]}"
            if [[ -n "$inner" ]]; then
                # Replace index values with global indices
                local entry
                while IFS= read -r entry; do
                    if [[ -n "$entry" ]]; then
                        $first || all_results+=","
                        first=false
                        # Update the index in the entry
                        local adjusted
                        adjusted=$(echo "$entry" | sed "s/\"index\":[0-9]*/\"index\":$global_index/")
                        all_results+="$adjusted"
                        ((global_index++))
                    fi
                done < <(echo "$inner" | tr '},{' '\n' | grep -v '^$' | sed 's/^/\{/' | sed 's/$/\}/' | sed 's/\}\}/\}/' | sed 's/\{\{/\{/')
            fi
        fi

        i=$batch_end
    done
    all_results+="]"

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    [[ $total_failed -gt 0 ]] && ok="false"

    _parallel_build_result "$ok" "$all_results" "$total_duration" "$total_succeeded" "$total_failed"
}

# =============================================================================
# TIMEOUT
# =============================================================================

# @pre: seconds > 0, command is valid
# @post: command completed or killed after timeout
# @returns: JSON with result
#
# Run command with timeout
#
# Usage: parallel_timeout 30 "long_command"
# Example: result=$(parallel_timeout 5 "curl -s http://slow-server.com")
parallel_timeout() {
    local seconds="$1"
    shift
    local command="$*"

    if [[ -z "$command" ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_COMMAND","msg":"No command provided"}}'
        return 1
    fi

    if ! [[ "$seconds" =~ ^[0-9]+$ ]] || [[ "$seconds" -le 0 ]]; then
        printf '{"ok":false,"error":{"code":"E_INVALID_TIMEOUT","msg":"Timeout must be positive integer"}}'
        return 1
    fi

    local start_ms
    start_ms=$(_parallel_now_ms)

    # Ensure state directory
    mkdir -p "$PARALLEL_STATE_DIR"

    local output_file
    output_file=$(mktemp "$PARALLEL_STATE_DIR/parallel_timeout_output_XXXXXX")
    local shell_bin="${BASH:-bash}"
    local cmd_pid
    local kill_target

    # Run the timed command in its own child shell so watchdog kills cannot
    # interfere with the caller's shell or the Bats test process.
    if command -v setsid &>/dev/null; then
        setsid "$shell_bin" -lc "$command" >"$output_file" 2>&1 &
        cmd_pid=$!
        kill_target="-$cmd_pid"
    else
        "$shell_bin" -lc "$command" >"$output_file" 2>&1 &
        cmd_pid=$!
        kill_target="$cmd_pid"
    fi

    # Start watchdog
    (
        sleep "$seconds"
        kill -TERM -- "$kill_target" 2>/dev/null
        sleep 1
        kill -KILL -- "$kill_target" 2>/dev/null
    ) &
    local watchdog_pid=$!

    # Wait for command
    wait "$cmd_pid" 2>/dev/null
    local wait_status=$?

    # Kill watchdog
    kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null

    # Read result
    local status="$wait_status"
    local output=""
    local timed_out=false

    if [[ -f "$output_file" ]]; then
        output=$(<"$output_file")
        rm -f "$output_file"
    fi

    # Check for timeout (SIGTERM=143, SIGKILL=137)
    if [[ $wait_status -eq 143 || $wait_status -eq 137 ]]; then
        timed_out=true
    fi

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    if [[ "$timed_out" == "true" ]]; then
        local results_json="["
        results_json+=$(_parallel_build_entry 0 "timeout" "$output" "$total_duration" "timed out after ${seconds}s")
        results_json+="]"
        _parallel_build_result "false" "$results_json" "$total_duration" 0 1 "Command exceeded timeout of ${seconds}s"
        return 124
    fi

    local ok="true"
    local entry_status="done"
    local error=""
    local succeeded=1
    local failed=0

    if [[ "$status" -ne 0 ]]; then
        ok="false"
        entry_status="error"
        error="exit code $status"
        succeeded=0
        failed=1
    fi

    local results_json="["
    results_json+=$(_parallel_build_entry 0 "$entry_status" "$output" "$total_duration" "$error")
    results_json+="]"

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
    return "$status"
}

# =============================================================================
# RETRY
# =============================================================================

# @pre: command is valid
# @post: command executed with retries on failure
# @returns: JSON with final result and attempt count
#
# Retry command on failure
#
# Usage: parallel_retry "command" --max-attempts 3 [--delay 1] [--backoff exponential]
# Example: result=$(parallel_retry "curl -s http://api.com" --max-attempts 5)
parallel_retry() {
    local command=""
    local max_attempts="$PARALLEL_DEFAULT_MAX_ATTEMPTS"
    local delay=1
    local backoff="exponential"
    local -a args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-attempts)
                max_attempts="$2"
                shift 2
                ;;
            --delay)
                delay="$2"
                shift 2
                ;;
            --backoff)
                backoff="$2"
                shift 2
                ;;
            --)
                shift
                command="$*"
                break
                ;;
            -*)
                if [[ -n "$command" ]]; then
                    args+=("$1")
                else
                    _parallel_log error "Unknown option: $1"
                    printf '{"ok":false,"error":{"code":"E_INVALID_OPTION","msg":"Unknown option: %s"}}' "$1"
                    return 1
                fi
                shift
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    command+=" $1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_COMMAND","msg":"No command provided"}}'
        return 1
    fi

    [[ "$max_attempts" -lt 1 ]] && max_attempts=1

    local start_ms
    start_ms=$(_parallel_now_ms)

    local attempt=1
    local last_status=1
    local last_output=""
    local last_duration=0
    local total_attempts=0

    while [[ $attempt -le $max_attempts ]]; do
        local task_start
        task_start=$(_parallel_now_ms)

        local output status
        output=$(eval "$command" 2>&1)
        status=$?

        local task_end
        task_end=$(_parallel_now_ms)
        last_duration=$((task_end - task_start))
        last_status=$status
        last_output="$output"
        total_attempts=$attempt

        if [[ $status -eq 0 ]]; then
            break
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            # Calculate delay
            local current_delay
            case "$backoff" in
                fixed)
                    current_delay=$delay
                    ;;
                linear)
                    current_delay=$((delay * attempt))
                    ;;
                exponential|*)
                    local power=1
                    local i
                    for ((i = 1; i < attempt; i++)); do
                        power=$((power * 2))
                    done
                    current_delay=$((delay * power))
                    ;;
            esac

            _parallel_log debug "Attempt $attempt failed, retrying in ${current_delay}s..."
            sleep "$current_delay"
        fi

        ((attempt++))
    done

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    local entry_status="done"
    local error=""
    local succeeded=1
    local failed=0

    if [[ "$last_status" -ne 0 ]]; then
        ok="false"
        entry_status="error"
        error="failed after $total_attempts attempts, exit code $last_status"
        succeeded=0
        failed=1
    fi

    local results_json="["
    results_json+=$(_parallel_build_entry 0 "$entry_status" "$last_output" "$last_duration" "$error")
    results_json+="]"

    local result
    result=$(_parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed" "attempts=$total_attempts")

    # Add attempts to data
    result=$(echo "$result" | sed "s/\"succeeded\":/\"attempts\":$total_attempts,\"succeeded\":/")

    printf '%s' "$result"
    return "$last_status"
}

# =============================================================================
# PROGRESS REPORTING
# =============================================================================

# @pre: commands array
# @post: commands executed with progress reporting
# @returns: JSON with all results
#
# Execute with progress bar
#
# Usage: parallel_progress "${cmds[@]}"
# Example: parallel_progress "task1" "task2" "task3" "task4"
parallel_progress() {
    local -a commands=("$@")

    if [[ ${#commands[@]} -eq 0 ]]; then
        printf '{"ok":false,"error":{"code":"E_NO_COMMANDS","msg":"No commands provided"}}'
        return 1
    fi

    local total=${#commands[@]}
    local start_ms
    start_ms=$(_parallel_now_ms)

    # Ensure state directory
    mkdir -p "$PARALLEL_STATE_DIR"

    local -a pids=()
    local -a tmpfiles=()

    # Progress display function
    _progress_bar() {
        local current="$1"
        local total="$2"
        local width=40
        local percent=$((current * 100 / total))
        local filled=$((current * width / total))
        local empty=$((width - filled))

        local bar=""
        local i
        for ((i = 0; i < filled; i++)); do bar+="="; done
        for ((i = 0; i < empty; i++)); do bar+=" "; done

        printf '\r[%s] %3d%% (%d/%d)' "$bar" "$percent" "$current" "$total" >&2
    }

    # Launch all commands
    local i
    for i in "${!commands[@]}"; do
        local cmd="${commands[$i]}"
        local tmpfile
        tmpfile=$(mktemp "$PARALLEL_STATE_DIR/parallel_progress_XXXXXX")
        tmpfiles+=("$tmpfile")

        (
            local task_start
            task_start=$(_parallel_now_ms)
            local output status
            output=$(eval "$cmd" 2>&1)
            status=$?
            local task_end
            task_end=$(_parallel_now_ms)
            local task_duration=$((task_end - task_start))
            printf '%d\n%d\n%s' "$status" "$task_duration" "$output" > "$tmpfile"
        ) &
        pids+=($!)
    done

    # Monitor progress
    local completed=0
    _progress_bar 0 "$total"

    while [[ $completed -lt $total ]]; do
        local new_completed=0
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                ((new_completed++))
            fi
        done

        if [[ $new_completed -ne $completed ]]; then
            completed=$new_completed
            _progress_bar "$completed" "$total"
        fi

        [[ $completed -lt $total ]] && sleep 0.1
    done

    # Newline after progress bar
    printf '\n' >&2

    # Wait for all (cleanup)
    wait 2>/dev/null

    # Collect results
    local succeeded=0
    local failed=0
    local results_json="["
    local first=true

    for i in "${!tmpfiles[@]}"; do
        local tmpfile="${tmpfiles[$i]}"
        if [[ -f "$tmpfile" ]]; then
            local content
            content=$(<"$tmpfile")
            rm -f "$tmpfile"

            local status duration output
            status=$(echo "$content" | head -1)
            duration=$(echo "$content" | sed -n '2p')
            output=$(echo "$content" | tail -n +3)

            local entry_status="done"
            local error=""
            if [[ "$status" -ne 0 ]]; then
                entry_status="error"
                error="exit code $status"
                ((failed++))
            else
                ((succeeded++))
            fi

            $first || results_json+=","
            first=false
            results_json+=$(_parallel_build_entry "$i" "$entry_status" "$output" "${duration:-0}" "$error")
        fi
    done
    results_json+="]"

    local end_ms
    end_ms=$(_parallel_now_ms)
    local total_duration=$((end_ms - start_ms))

    local ok="true"
    [[ $failed -gt 0 ]] && ok="false"

    _parallel_build_result "$ok" "$results_json" "$total_duration" "$succeeded" "$failed"
}

# =============================================================================
# CLEANUP
# =============================================================================

# Clean up state directory
parallel_cleanup() {
    if [[ -d "${PARALLEL_STATE_DIR:-}" && -n "$PARALLEL_STATE_DIR" ]]; then
        rm -rf "${PARALLEL_STATE_DIR:?}"/*
    fi
}

# Register cleanup on exit if enabled
if [[ -z "${PARALLEL_NO_CLEANUP:-}" ]]; then
    if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
        _mainframe_add_exit_trap "parallel_cleanup"
    else
        trap parallel_cleanup EXIT
    fi
fi

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_PARALLEL_EXPORTS=(
    # Map operations
    parallel_map
    parallel_map_n
    # Race/All/Any
    parallel_race
    parallel_all
    parallel_any
    # Sequential
    parallel_sequence
    # Batch
    parallel_batch
    # Timeout
    parallel_timeout
    # Retry
    parallel_retry
    # Progress
    parallel_progress
    # Cleanup
    parallel_cleanup
)

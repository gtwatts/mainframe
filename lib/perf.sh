#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/perf.sh - Performance Utilities & Bash Feature Gates
# =============================================================================
# Description: Bash version detection, feature gating for modern Bash (5.0+/5.3+),
#              and performance measurement utilities. Enables conditional use of
#              fast-path features (namerefs, EPOCHREALTIME, current-shell subst)
#              while maintaining Bash 4.0+ compatibility.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PERF_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PERF_LOADED=1

# =============================================================================
# BASH VERSION DETECTION
# =============================================================================

# @pre: none
# @post: prints bash version as "major.minor.patch"
# @idempotent: yes
# @returns: 0
#
# Get the current Bash version as a dot-separated string.
#
# Usage: ver=$(bash_version)
# Example: echo "Running Bash $(bash_version)"
bash_version() {
    printf '%s.%s.%s' "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" "${BASH_VERSINFO[2]}"
}

# @pre: none
# @post: prints bash major version number
# @idempotent: yes
# @returns: 0
#
# Get just the major version number.
#
# Usage: major=$(bash_version_major)
bash_version_major() {
    printf '%s' "${BASH_VERSINFO[0]}"
}

# @pre: required_major and required_minor are integers
# @post: returns 0 if current bash >= required version
# @idempotent: yes
# @returns: 0 if at least the required version, 1 otherwise
#
# Check if the current Bash version is at least the specified version.
#
# Usage: bash_version_at_least 5 0 && echo "Bash 5+"
# Example: bash_version_at_least 5 3 && echo "Current-shell subst available"
bash_version_at_least() {
    local req_major="${1:-0}"
    local req_minor="${2:-0}"

    local cur_major="${BASH_VERSINFO[0]}"
    local cur_minor="${BASH_VERSINFO[1]}"

    if (( cur_major > req_major )); then
        return 0
    elif (( cur_major == req_major && cur_minor >= req_minor )); then
        return 0
    fi
    return 1
}

# =============================================================================
# FEATURE DETECTION
# =============================================================================

# @pre: feature_name is a known feature string
# @post: returns 0 if feature is available in current bash
# @idempotent: yes
# @returns: 0 if available, 1 if not
#
# Check if a specific Bash feature is available. Features:
#   - namerefs: declare -n (Bash 4.3+)
#   - mapfile: mapfile/readarray builtin (Bash 4.0+)
#   - associative_arrays: declare -A (Bash 4.0+)
#   - epochrealtime: $EPOCHREALTIME variable (Bash 5.0+)
#   - epochseconds: $EPOCHSECONDS variable (Bash 5.0+)
#   - wait_n: wait -n for any child (Bash 4.3+)
#   - lastpipe: shopt -s lastpipe (Bash 4.2+)
#   - globasciiranges: shopt -s globasciiranges (Bash 4.3+)
#   - inherit_errexit: shopt -s inherit_errexit (Bash 4.4+)
#   - extglob: extended globbing (Bash 4.0+)
#
# Usage: bash_has_feature "namerefs" && declare -n ref=var
# Example: if bash_has_feature "epochrealtime"; then t=$EPOCHREALTIME; fi
bash_has_feature() {
    local feature="$1"

    case "$feature" in
        namerefs|nameref)
            bash_version_at_least 4 3
            ;;
        mapfile|readarray)
            bash_version_at_least 4 0
            ;;
        associative_arrays|assoc)
            bash_version_at_least 4 0
            ;;
        epochrealtime|EPOCHREALTIME)
            bash_version_at_least 5 0
            ;;
        epochseconds|EPOCHSECONDS)
            bash_version_at_least 5 0
            ;;
        wait_n)
            bash_version_at_least 4 3
            ;;
        lastpipe)
            bash_version_at_least 4 2
            ;;
        globasciiranges)
            bash_version_at_least 4 3
            ;;
        inherit_errexit)
            bash_version_at_least 4 4
            ;;
        extglob)
            bash_version_at_least 4 0
            ;;
        loadable_builtins)
            bash_version_at_least 4 0
            ;;
        *)
            return 1
            ;;
    esac
}

# @pre: none
# @post: prints JSON object with all feature availability
# @idempotent: yes
# @returns: 0
#
# List all known features and whether they're available.
# Returns a JSON object for AI agent consumption.
#
# Usage: features=$(bash_features)
bash_features() {
    local features=(
        namerefs mapfile associative_arrays epochrealtime
        epochseconds wait_n lastpipe globasciiranges
        inherit_errexit extglob loadable_builtins
    )

    local json="{"
    local first=true
    for feat in "${features[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        if bash_has_feature "$feat"; then
            json+="\"$feat\":true"
        else
            json+="\"$feat\":false"
        fi
    done
    json+="}"

    printf '%s' "$json"
}

# =============================================================================
# PERFORMANCE TIMING
# =============================================================================

# Internal: get high-res timestamp without subshell if possible
_perf_now() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    elif [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s.000000' "$EPOCHSECONDS"
    else
        date +%s.%N 2>/dev/null || date +%s
    fi
}

# @pre: timer_name is a valid variable-safe string
# @post: start time stored in variable PERF_TIMER_<name>
# @idempotent: no - resets timer each call
# @returns: 0
#
# Start a named performance timer. Uses variable storage to avoid subshells.
# The timer value is stored in a global variable PERF_TIMER_<name>.
#
# Usage: perf_timer_start "my_operation"
# Example: perf_timer_start "database_query"
perf_timer_start() {
    local name="$1"
    local varname="PERF_TIMER_${name}"
    local now
    now=$(_perf_now)
    printf -v "$varname" '%s' "$now"
    export "$varname"
}

# @pre: perf_timer_start was called with same name
# @post: duration printed to stdout
# @idempotent: yes - can be called multiple times (measures from start each time)
# @returns: 0 on success, 1 if timer not started
#
# Stop a named timer and print the elapsed duration in seconds.
#
# Usage: elapsed=$(perf_timer_elapsed "my_operation")
# Example: perf_timer_start "op"; sleep 1; echo "$(perf_timer_elapsed "op")s"
perf_timer_elapsed() {
    local name="$1"
    local varname="PERF_TIMER_${name}"
    local start="${!varname:-}"

    if [[ -z "$start" ]]; then
        printf '0'
        return 1
    fi

    local now
    now=$(_perf_now)

    if command -v bc &>/dev/null; then
        local result
        result=$(printf '%s - %s\n' "$now" "$start" | bc 2>/dev/null || echo "0")
        [[ "$result" == .* ]] && result="0$result"
        printf '%s' "$result"
    else
        local now_int start_int
        now_int="${now%%.*}"
        start_int="${start%%.*}"
        printf '%d' $((now_int - start_int))
    fi
}

# @pre: perf_timer_start was called with same name
# @post: JSON result printed with name and duration
# @returns: 0 on success, 1 if timer not started
#
# Stop a named timer and emit a JSON timing result.
#
# Usage: result=$(perf_timer_stop "my_operation")
perf_timer_stop() {
    local name="$1"
    local elapsed
    elapsed=$(perf_timer_elapsed "$name")
    local rc=$?

    local varname="PERF_TIMER_${name}"
    unset "$varname"

    printf '{"timer":"%s","duration_s":%s}' "$name" "$elapsed"
    return $rc
}

# =============================================================================
# PERFORMANCE COMPARISON
# =============================================================================

# @pre: cmd1 and cmd2 are executable strings
# @post: JSON comparison result printed
# @idempotent: no - timing varies
# @returns: 0
#
# Compare execution time of two commands/approaches.
# Runs each command N iterations and reports average times.
#
# Usage: result=$(perf_compare "cmd1" "cmd2" [iterations])
# Example: perf_compare "printf '%s' foo" 'echo foo' 100
perf_compare() {
    local cmd1="$1"
    local cmd2="$2"
    local iterations="${3:-10}"

    local start1 end1 start2 end2 dur1 dur2
    local i

    # Time cmd1
    start1=$(_perf_now)
    for ((i=0; i<iterations; i++)); do
        eval "$cmd1" >/dev/null 2>&1
    done
    end1=$(_perf_now)

    # Time cmd2
    start2=$(_perf_now)
    for ((i=0; i<iterations; i++)); do
        eval "$cmd2" >/dev/null 2>&1
    done
    end2=$(_perf_now)

    # Calculate durations
    if command -v bc &>/dev/null; then
        dur1=$(printf '%s - %s\n' "$end1" "$start1" | bc 2>/dev/null || echo "0")
        dur2=$(printf '%s - %s\n' "$end2" "$start2" | bc 2>/dev/null || echo "0")
        [[ "$dur1" == .* ]] && dur1="0$dur1"
        [[ "$dur2" == .* ]] && dur2="0$dur2"
    else
        local e1 s1 e2 s2
        e1="${end1%%.*}"; s1="${start1%%.*}"
        e2="${end2%%.*}"; s2="${start2%%.*}"
        dur1=$((e1 - s1))
        dur2=$((e2 - s2))
    fi

    local winner
    if command -v bc &>/dev/null; then
        local cmp
        cmp=$(printf '%s < %s\n' "$dur1" "$dur2" | bc 2>/dev/null || echo "0")
        if [[ "$cmp" == "1" ]]; then
            winner="cmd1"
        else
            winner="cmd2"
        fi
    else
        if (( dur1 < dur2 )); then
            winner="cmd1"
        else
            winner="cmd2"
        fi
    fi

    printf '{"iterations":%d,"cmd1_total_s":%s,"cmd2_total_s":%s,"winner":"%s"}' \
        "$iterations" "$dur1" "$dur2" "$winner"
}

# =============================================================================
# SUBSHELL AVOIDANCE HELPERS
# =============================================================================

# @pre: varname is a valid variable name, value is the content
# @post: variable set without forking a subshell
# @idempotent: yes
# @returns: 0
#
# Set a variable by name without subshell. Uses printf -v which is
# significantly faster than var=$(command) for simple assignments.
# This is a thin wrapper for documentation/discoverability.
#
# Usage: perf_setvar "result" "hello world"
perf_setvar() {
    local varname="$1"
    local value="$2"
    printf -v "$varname" '%s' "$value"
}

# @pre: varname is valid, command produces output on stdout
# @post: variable contains command output (no subshell on Bash 4.2+ with lastpipe)
# @idempotent: depends on command
# @returns: 0
#
# Capture command output into a variable using lastpipe (avoids subshell
# for the reader). Falls back to $() on older Bash.
#
# Usage: perf_capture "result" cat /etc/hostname
# Note: Only avoids subshell if lastpipe is available and job control is off.
perf_capture() {
    local varname="$1"
    shift

    if bash_has_feature "lastpipe" && [[ "$(set +o)" == *"+o monitor"* ]]; then
        local _capture_val=""
        "$@" | { IFS= read -r -d '' _capture_val || true; }
        printf -v "$varname" '%s' "$_capture_val"
    else
        local _val
        _val=$("$@") || true
        printf -v "$varname" '%s' "$_val"
    fi
}

# =============================================================================
# BENCHMARK UTILITY
# =============================================================================

# @pre: command is executable
# @post: JSON benchmark result printed
# @idempotent: no - timing varies
# @returns: exit code of the command
#
# Benchmark a single command with iteration count.
# Returns JSON with total time, average, and iterations.
#
# Usage: result=$(perf_benchmark "command args" [iterations])
# Example: perf_benchmark "sha256sum /dev/null" 50
perf_benchmark() {
    local cmd="$1"
    local iterations="${2:-10}"

    local start end duration avg
    local i exit_code=0

    start=$(_perf_now)
    for ((i=0; i<iterations; i++)); do
        eval "$cmd" >/dev/null 2>&1 || exit_code=$?
    done
    end=$(_perf_now)

    if command -v bc &>/dev/null; then
        duration=$(printf '%s - %s\n' "$end" "$start" | bc 2>/dev/null || echo "0")
        [[ "$duration" == .* ]] && duration="0$duration"
        avg=$(printf 'scale=6; %s / %d\n' "$duration" "$iterations" | bc 2>/dev/null || echo "0")
        [[ "$avg" == .* ]] && avg="0$avg"
    else
        local end_int start_int
        end_int="${end%%.*}"
        start_int="${start%%.*}"
        duration=$((end_int - start_int))
        avg=$((duration / iterations))
    fi

    printf '{"cmd":"%s","iterations":%d,"total_s":%s,"avg_s":%s,"exit_code":%d}' \
        "$cmd" "$iterations" "$duration" "$avg" "$exit_code"
    return $exit_code
}

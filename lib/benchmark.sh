#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/benchmark.sh - Benchmark Tracking Library
# =============================================================================
# Description: Performance regression testing and automated benchmark tracking.
#              Provides statistical analysis, baseline comparison, and reporting.
# Version: 1.0.0
# Requires: Bash 4.0+ (5.0+ recommended for EPOCHREALTIME)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_BENCHMARK_LOADED:-}" ]] && return 0
readonly _MAINFRAME_BENCHMARK_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly _BENCH_DEFAULT_ITERATIONS=100
readonly _BENCH_DEFAULT_WARMUP=5
readonly _BENCH_DEFAULT_THRESHOLD=10  # 10% regression threshold
readonly _BENCH_VERSION="1.0.0"

# =============================================================================
# INTERNAL: HIGH-RESOLUTION TIMING
# =============================================================================

# Get high-resolution timestamp in seconds with microsecond precision
# Priority: EPOCHREALTIME (Bash 5.0+) > date +%s.%N > date +%s
_bench_now() {
    # Fastest: Bash 5.0+ EPOCHREALTIME (microsecond precision)
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s' "$EPOCHREALTIME"
    # Medium: GNU date with nanoseconds
    elif date +%s.%N &>/dev/null; then
        date +%s.%N
    # Fallback: second precision only
    else
        printf '%s.000000' "$(date +%s)"
    fi
}

# Calculate elapsed time in milliseconds
# Usage: _bench_elapsed_ms "start_time" "end_time"
_bench_elapsed_ms() {
    local start="$1"
    local end="$2"

    if command -v bc &>/dev/null; then
        local result
        result=$(printf '(%s - %s) * 1000\n' "$end" "$start" | bc 2>/dev/null || echo "0")
        # Handle leading decimal point
        [[ "$result" == .* ]] && result="0$result"
        printf '%s' "$result"
    else
        # Integer arithmetic fallback (less precise)
        local start_int end_int
        start_int="${start%%.*}"
        end_int="${end%%.*}"
        printf '%d' $(( (end_int - start_int) * 1000 ))
    fi
}

# =============================================================================
# MEASUREMENT FUNCTIONS
# =============================================================================

# Measure wall clock time for a command in milliseconds
# Usage: bench_time "command [args...]"
# Returns: execution time in milliseconds
bench_time() {
    local cmd="$1"
    local start end

    start=$(_bench_now)
    eval "$cmd" >/dev/null 2>&1
    end=$(_bench_now)

    _bench_elapsed_ms "$start" "$end"
}

# Measure peak memory usage for a command in KB
# Usage: bench_memory "command [args...]"
# Returns: peak memory in KB (uses /usr/bin/time if available)
bench_memory() {
    local cmd="$1"

    # Try GNU time with memory reporting
    if command -v /usr/bin/time &>/dev/null; then
        local output
        output=$(/usr/bin/time -f '%M' bash -c "$cmd" 2>&1 >/dev/null | tail -1)
        if [[ "$output" =~ ^[0-9]+$ ]]; then
            printf '%s' "$output"
            return 0
        fi
    fi

    # Fallback: estimate from /proc/self/status on Linux
    if [[ -f /proc/self/status ]]; then
        local before_mem after_mem
        before_mem=$(awk '/VmRSS/ {print $2}' /proc/self/status 2>/dev/null || echo 0)
        eval "$cmd" >/dev/null 2>&1
        after_mem=$(awk '/VmRSS/ {print $2}' /proc/self/status 2>/dev/null || echo 0)
        printf '%d' $(( after_mem > before_mem ? after_mem - before_mem : 0 ))
        return 0
    fi

    # No memory measurement available
    printf '0'
    return 1
}

# Measure CPU time (user + system) for a command in milliseconds
# Usage: bench_cpu "command [args...]"
# Returns: CPU time in milliseconds
bench_cpu() {
    local cmd="$1"

    # Try GNU time with CPU time reporting
    if command -v /usr/bin/time &>/dev/null; then
        local output
        output=$(/usr/bin/time -f '%U %S' bash -c "$cmd" 2>&1 >/dev/null | tail -1)
        if [[ "$output" =~ ^([0-9.]+)\ ([0-9.]+)$ ]]; then
            local user_time="${BASH_REMATCH[1]}"
            local sys_time="${BASH_REMATCH[2]}"
            if command -v bc &>/dev/null; then
                local total
                total=$(printf '(%s + %s) * 1000\n' "$user_time" "$sys_time" | bc 2>/dev/null)
                [[ "$total" == .* ]] && total="0$total"
                printf '%s' "$total"
                return 0
            fi
        fi
    fi

    # Fallback to wall clock time
    bench_time "$cmd"
}

# =============================================================================
# STATISTICS FUNCTIONS
# =============================================================================

# Calculate mean of values
# Usage: _bench_mean value1 value2 ...
_bench_mean() {
    local sum=0
    local count=0

    for val in "$@"; do
        if command -v bc &>/dev/null; then
            sum=$(printf '%s + %s\n' "$sum" "$val" | bc 2>/dev/null)
        else
            sum=$(( sum + ${val%%.*} ))
        fi
        ((count++))
    done

    if [[ $count -eq 0 ]]; then
        printf '0'
        return 1
    fi

    if command -v bc &>/dev/null; then
        local result
        result=$(printf 'scale=6; %s / %d\n' "$sum" "$count" | bc 2>/dev/null)
        [[ "$result" == .* ]] && result="0$result"
        printf '%s' "$result"
    else
        printf '%d' $(( sum / count ))
    fi
}

# Calculate median of values
# Usage: _bench_median value1 value2 ...
_bench_median() {
    # Handle empty input
    [[ $# -eq 0 ]] && { printf '0'; return 1; }

    local -a sorted=()
    local count=0

    # Sort values
    while IFS= read -r val; do
        [[ -z "$val" ]] && continue  # Skip empty lines
        sorted+=("$val")
        (( ++count )) || true
    done < <(printf '%s\n' "$@" | sort -n)

    if [[ $count -eq 0 ]]; then
        printf '0'
        return 1
    fi

    local mid=$((count / 2))
    if (( count % 2 == 0 )); then
        # Even: average of two middle values
        if command -v bc &>/dev/null; then
            local result
            result=$(printf 'scale=6; (%s + %s) / 2\n' "${sorted[$mid-1]}" "${sorted[$mid]}" | bc 2>/dev/null)
            [[ "$result" == .* ]] && result="0$result"
            printf '%s' "$result"
        else
            printf '%d' $(( (${sorted[$mid-1]%%.*} + ${sorted[$mid]%%.*}) / 2 ))
        fi
    else
        printf '%s' "${sorted[$mid]}"
    fi
}

# Calculate standard deviation
# Usage: _bench_stddev mean value1 value2 ...
_bench_stddev() {
    local mean="$1"
    shift
    local sum_sq=0
    local count=0

    for val in "$@"; do
        if command -v bc &>/dev/null; then
            local diff
            diff=$(printf '%s - %s\n' "$val" "$mean" | bc 2>/dev/null)
            local sq
            sq=$(printf '%s * %s\n' "$diff" "$diff" | bc 2>/dev/null)
            sum_sq=$(printf '%s + %s\n' "$sum_sq" "$sq" | bc 2>/dev/null)
        else
            local diff=$(( ${val%%.*} - ${mean%%.*} ))
            sum_sq=$(( sum_sq + diff * diff ))
        fi
        ((count++))
    done

    if [[ $count -eq 0 ]]; then
        printf '0'
        return 1
    fi

    if command -v bc &>/dev/null; then
        local variance result
        variance=$(printf 'scale=6; %s / %d\n' "$sum_sq" "$count" | bc 2>/dev/null)
        result=$(printf 'scale=6; sqrt(%s)\n' "$variance" | bc 2>/dev/null)
        [[ "$result" == .* ]] && result="0$result"
        printf '%s' "$result"
    else
        # Approximate integer sqrt
        local variance=$(( sum_sq / count ))
        local s=0
        while (( s * s < variance )); do ((s++)); done
        printf '%d' "$s"
    fi
}

# Calculate percentile
# Usage: _bench_percentile P value1 value2 ...
# P: percentile (e.g., 95, 99)
_bench_percentile() {
    local p="$1"
    shift
    local -a sorted=()
    local count=0

    # Sort values
    while IFS= read -r val; do
        sorted+=("$val")
        ((count++))
    done < <(printf '%s\n' "$@" | sort -n)

    if [[ $count -eq 0 ]]; then
        printf '0'
        return 1
    fi

    # Calculate index (ceiling)
    local idx
    if command -v bc &>/dev/null; then
        idx=$(printf 'scale=0; (%d * %d + 99) / 100\n' "$p" "$count" | bc 2>/dev/null)
    else
        idx=$(( (p * count + 99) / 100 ))
    fi

    # Clamp to valid range
    (( idx < 1 )) && idx=1
    (( idx > count )) && idx=$count

    printf '%s' "${sorted[$idx-1]}"
}

# Find minimum value
# Usage: _bench_min value1 value2 ...
_bench_min() {
    local min=""
    for val in "$@"; do
        if [[ -z "$min" ]]; then
            min="$val"
        elif command -v bc &>/dev/null; then
            local cmp
            cmp=$(printf '%s < %s\n' "$val" "$min" | bc 2>/dev/null)
            [[ "$cmp" == "1" ]] && min="$val"
        else
            (( ${val%%.*} < ${min%%.*} )) && min="$val"
        fi
    done
    printf '%s' "${min:-0}"
}

# Find maximum value
# Usage: _bench_max value1 value2 ...
_bench_max() {
    local max=""
    for val in "$@"; do
        if [[ -z "$max" ]]; then
            max="$val"
        elif command -v bc &>/dev/null; then
            local cmp
            cmp=$(printf '%s > %s\n' "$val" "$max" | bc 2>/dev/null)
            [[ "$cmp" == "1" ]] && max="$val"
        else
            (( ${val%%.*} > ${max%%.*} )) && max="$val"
        fi
    done
    printf '%s' "${max:-0}"
}

# Detect outliers using IQR method
# Usage: _bench_detect_outliers value1 value2 ...
# Returns: count of outliers
_bench_detect_outliers() {
    local -a sorted=()
    local count=0

    # Sort values
    while IFS= read -r val; do
        sorted+=("$val")
        ((count++))
    done < <(printf '%s\n' "$@" | sort -n)

    if [[ $count -lt 4 ]]; then
        printf '0'
        return 0
    fi

    local q1 q3 iqr
    q1=$(_bench_percentile 25 "${sorted[@]}")
    q3=$(_bench_percentile 75 "${sorted[@]}")

    if command -v bc &>/dev/null; then
        iqr=$(printf '%s - %s\n' "$q3" "$q1" | bc 2>/dev/null)
        local lower upper
        lower=$(printf '%s - 1.5 * %s\n' "$q1" "$iqr" | bc 2>/dev/null)
        upper=$(printf '%s + 1.5 * %s\n' "$q3" "$iqr" | bc 2>/dev/null)

        local outlier_count=0
        for val in "${sorted[@]}"; do
            local below above
            below=$(printf '%s < %s\n' "$val" "$lower" | bc 2>/dev/null)
            above=$(printf '%s > %s\n' "$val" "$upper" | bc 2>/dev/null)
            (( below == 1 || above == 1 )) && ((outlier_count++))
        done
        printf '%d' "$outlier_count"
    else
        printf '0'
    fi
}

# Calculate confidence interval (95%)
# Usage: _bench_confidence_interval mean stddev count
_bench_confidence_interval() {
    local mean="$1"
    local stddev="$2"
    local count="$3"

    if command -v bc &>/dev/null && [[ $count -gt 0 ]]; then
        # 95% CI: mean +/- 1.96 * (stddev / sqrt(n))
        local se margin lower upper
        se=$(printf 'scale=6; %s / sqrt(%d)\n' "$stddev" "$count" | bc 2>/dev/null)
        margin=$(printf 'scale=6; 1.96 * %s\n' "$se" | bc 2>/dev/null)
        lower=$(printf 'scale=6; %s - %s\n' "$mean" "$margin" | bc 2>/dev/null)
        upper=$(printf 'scale=6; %s + %s\n' "$mean" "$margin" | bc 2>/dev/null)
        [[ "$lower" == .* ]] && lower="0$lower"
        [[ "$upper" == .* ]] && upper="0$upper"
        [[ "$lower" == -.* ]] && lower="-0${lower#-}"
        printf '%s %s' "$lower" "$upper"
    else
        printf '%s %s' "$mean" "$mean"
    fi
}

# =============================================================================
# CORE BENCHMARK FUNCTIONS
# =============================================================================

# Run a benchmark with statistical analysis
# Usage: benchmark_run NAME COMMAND [ITERATIONS] [WARMUP]
# Returns: JSON result object
benchmark_run() {
    local name="$1"
    local cmd="$2"
    local iterations="${3:-$_BENCH_DEFAULT_ITERATIONS}"
    local warmup="${4:-$_BENCH_DEFAULT_WARMUP}"

    # Validate inputs
    [[ -z "$name" || -z "$cmd" ]] && {
        printf '{"error":"missing name or command"}'
        return 1
    }

    # Warmup runs
    local i
    for ((i=0; i<warmup; i++)); do
        eval "$cmd" >/dev/null 2>&1
    done

    # Collect measurements
    local -a times=()
    for ((i=0; i<iterations; i++)); do
        local t
        t=$(bench_time "$cmd")
        times+=("$t")
    done

    # Calculate statistics
    local mean median stddev min max p95 p99
    mean=$(_bench_mean "${times[@]}")
    median=$(_bench_median "${times[@]}")
    stddev=$(_bench_stddev "$mean" "${times[@]}")
    min=$(_bench_min "${times[@]}")
    max=$(_bench_max "${times[@]}")
    p95=$(_bench_percentile 95 "${times[@]}")
    p99=$(_bench_percentile 99 "${times[@]}")

    # Outliers and confidence interval
    local outliers ci_lower ci_upper
    outliers=$(_bench_detect_outliers "${times[@]}")
    read -r ci_lower ci_upper < <(_bench_confidence_interval "$mean" "$stddev" "$iterations")

    # Get timestamp and platform
    local timestamp platform
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    platform=$(uname -sr 2>/dev/null || echo "unknown")

    # Build JSON result
    printf '{"name":"%s","iterations":%d,"warmup":%d,"stats":{"mean_ms":%s,"median_ms":%s,"stddev_ms":%s,"min_ms":%s,"max_ms":%s,"p95_ms":%s,"p99_ms":%s,"outliers":%d,"ci_lower_ms":%s,"ci_upper_ms":%s},"timestamp":"%s","platform":"%s"}' \
        "$name" "$iterations" "$warmup" \
        "$mean" "$median" "$stddev" "$min" "$max" "$p95" "$p99" "$outliers" \
        "$ci_lower" "$ci_upper" "$timestamp" "$platform"
}

# Compare benchmark results to a baseline
# Usage: benchmark_compare NAME BASELINE_FILE [THRESHOLD]
# THRESHOLD: percentage (default 10%)
# Returns: JSON comparison result, exit code 0 if ok, 1 if regression
benchmark_compare() {
    local name="$1"
    local baseline_file="$2"
    local threshold="${3:-$_BENCH_DEFAULT_THRESHOLD}"

    # Validate inputs
    [[ -z "$name" || -z "$baseline_file" ]] && {
        printf '{"error":"missing name or baseline file"}'
        return 1
    }

    [[ ! -f "$baseline_file" ]] && {
        printf '{"error":"baseline file not found: %s"}' "$baseline_file"
        return 1
    }

    # Read baseline
    local baseline_json
    baseline_json=$(<"$baseline_file")

    # Extract baseline mean (simple regex for pure bash)
    local baseline_mean=""
    if [[ "$baseline_json" =~ \"mean_ms\":([0-9.]+) ]]; then
        baseline_mean="${BASH_REMATCH[1]}"
    fi

    [[ -z "$baseline_mean" ]] && {
        printf '{"error":"could not extract baseline mean"}'
        return 1
    }

    # Get current benchmark data from last run (stored in _BENCH_LAST_RESULT)
    local current_mean="${_BENCH_LAST_MEAN:-0}"

    # Calculate percentage change
    local pct_change regression status
    if command -v bc &>/dev/null; then
        pct_change=$(printf 'scale=2; ((%s - %s) / %s) * 100\n' "$current_mean" "$baseline_mean" "$baseline_mean" | bc 2>/dev/null)
        [[ "$pct_change" == .* ]] && pct_change="0$pct_change"
        [[ "$pct_change" == -.* ]] && pct_change="-0${pct_change#-}"

        local is_regression
        is_regression=$(printf '%s > %s\n' "$pct_change" "$threshold" | bc 2>/dev/null)
        if [[ "$is_regression" == "1" ]]; then
            regression="true"
            status="REGRESSION"
        else
            regression="false"
            local is_improvement
            is_improvement=$(printf '%s < -%s\n' "$pct_change" "$threshold" | bc 2>/dev/null)
            if [[ "$is_improvement" == "1" ]]; then
                status="IMPROVEMENT"
            else
                status="OK"
            fi
        fi
    else
        pct_change="0"
        regression="false"
        status="UNKNOWN"
    fi

    printf '{"name":"%s","baseline_mean_ms":%s,"current_mean_ms":%s,"change_pct":%s,"threshold_pct":%d,"regression":%s,"status":"%s"}' \
        "$name" "$baseline_mean" "$current_mean" "$pct_change" "$threshold" "$regression" "$status"

    [[ "$regression" == "true" ]] && return 1
    return 0
}

# Save benchmark results to file
# Usage: benchmark_save NAME OUTPUT_FILE
benchmark_save() {
    local name="$1"
    local output_file="$2"

    [[ -z "$output_file" ]] && {
        printf '{"error":"missing output file"}'
        return 1
    }

    # Get the last result
    local result="${_BENCH_LAST_RESULT:-}"
    [[ -z "$result" ]] && {
        printf '{"error":"no benchmark result to save"}'
        return 1
    }

    # Create directory if needed
    local dir
    dir=$(dirname "$output_file")
    [[ -d "$dir" ]] || mkdir -p "$dir"

    # Write result
    printf '%s\n' "$result" > "$output_file"
    printf '{"saved":"%s","bytes":%d}' "$output_file" "${#result}"
}

# Generate benchmark report
# Usage: benchmark_report [FORMAT]
# FORMAT: text (default), json, markdown
benchmark_report() {
    local format="${1:-text}"

    local result="${_BENCH_LAST_RESULT:-}"
    [[ -z "$result" ]] && {
        printf '{"error":"no benchmark result to report"}'
        return 1
    }

    # Extract values using regex
    local name="" iterations="" mean="" median="" stddev="" min="" max="" p95="" p99=""
    [[ "$result" =~ \"name\":\"([^\"]+)\" ]] && name="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"iterations\":([0-9]+) ]] && iterations="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"mean_ms\":([0-9.]+) ]] && mean="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"median_ms\":([0-9.]+) ]] && median="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"stddev_ms\":([0-9.]+) ]] && stddev="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"min_ms\":([0-9.]+) ]] && min="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"max_ms\":([0-9.]+) ]] && max="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"p95_ms\":([0-9.]+) ]] && p95="${BASH_REMATCH[1]}"
    [[ "$result" =~ \"p99_ms\":([0-9.]+) ]] && p99="${BASH_REMATCH[1]}"

    case "$format" in
        json)
            printf '%s\n' "$result"
            ;;
        markdown)
            printf '# Benchmark: %s\n\n' "$name"
            printf '| Metric | Value |\n'
            printf '|--------|-------|\n'
            printf '| Iterations | %s |\n' "$iterations"
            printf '| Mean | %s ms |\n' "$mean"
            printf '| Median | %s ms |\n' "$median"
            printf '| Std Dev | %s ms |\n' "$stddev"
            printf '| Min | %s ms |\n' "$min"
            printf '| Max | %s ms |\n' "$max"
            printf '| P95 | %s ms |\n' "$p95"
            printf '| P99 | %s ms |\n' "$p99"
            ;;
        text|*)
            printf 'Benchmark: %s\n' "$name"
            printf '============================================\n'
            printf 'Iterations: %s\n' "$iterations"
            printf 'Mean:       %s ms\n' "$mean"
            printf 'Median:     %s ms\n' "$median"
            printf 'Std Dev:    %s ms\n' "$stddev"
            printf 'Min:        %s ms\n' "$min"
            printf 'Max:        %s ms\n' "$max"
            printf 'P95:        %s ms\n' "$p95"
            printf 'P99:        %s ms\n' "$p99"
            ;;
    esac
}

# =============================================================================
# CONVENIENCE WRAPPERS
# =============================================================================

# Run benchmark and store result for later use
# Usage: benchmark NAME COMMAND [ITERATIONS]
# This is the main entry point for most use cases
benchmark() {
    local name="$1"
    local cmd="$2"
    local iterations="${3:-$_BENCH_DEFAULT_ITERATIONS}"

    local result
    result=$(benchmark_run "$name" "$cmd" "$iterations")

    # Store for later use by compare/save/report
    _BENCH_LAST_RESULT="$result"

    # Extract mean for comparison
    if [[ "$result" =~ \"mean_ms\":([0-9.]+) ]]; then
        _BENCH_LAST_MEAN="${BASH_REMATCH[1]}"
    fi

    printf '%s\n' "$result"
}

# Run benchmark suite from file
# Usage: benchmark_suite SUITE_FILE [OUTPUT_DIR]
# Suite file format: one "NAME COMMAND" per line
benchmark_suite() {
    local suite_file="$1"
    local output_dir="${2:-.}"

    [[ ! -f "$suite_file" ]] && {
        printf '{"error":"suite file not found: %s"}' "$suite_file"
        return 1
    }

    [[ -d "$output_dir" ]] || mkdir -p "$output_dir"

    local results=()
    local line name cmd

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Parse "NAME COMMAND" (first word is name, rest is command)
        name="${line%% *}"
        cmd="${line#* }"

        printf 'Running benchmark: %s\n' "$name" >&2
        local result
        result=$(benchmark "$name" "$cmd")
        results+=("$result")

        # Save individual result
        printf '%s\n' "$result" > "${output_dir}/${name}.json"
    done < "$suite_file"

    # Output all results as JSON array
    printf '['
    local first=true
    for r in "${results[@]}"; do
        $first || printf ','
        first=false
        printf '%s' "$r"
    done
    printf ']\n'
}

# Check for regressions against baseline directory
# Usage: benchmark_check_regressions RESULTS_DIR BASELINE_DIR [THRESHOLD]
# Returns: exit code 0 if no regressions, 1 if any regressions found
benchmark_check_regressions() {
    local results_dir="$1"
    local baseline_dir="$2"
    local threshold="${3:-$_BENCH_DEFAULT_THRESHOLD}"

    local regressions=0
    local checked=0

    for result_file in "$results_dir"/*.json; do
        [[ -f "$result_file" ]] || continue
        local name
        name=$(basename "$result_file" .json)

        local baseline_file="${baseline_dir}/${name}.json"
        [[ -f "$baseline_file" ]] || continue

        # Load current result
        local current_json
        current_json=$(<"$result_file")
        if [[ "$current_json" =~ \"mean_ms\":([0-9.]+) ]]; then
            _BENCH_LAST_MEAN="${BASH_REMATCH[1]}"
        fi
        _BENCH_LAST_RESULT="$current_json"

        # Compare
        local comparison
        comparison=$(benchmark_compare "$name" "$baseline_file" "$threshold")

        if [[ "$comparison" =~ \"regression\":true ]]; then
            printf 'REGRESSION: %s\n' "$name" >&2
            printf '%s\n' "$comparison" >&2
            ((regressions++))
        fi
        ((checked++))
    done

    printf '{"checked":%d,"regressions":%d}' "$checked" "$regressions"
    (( regressions > 0 )) && return 1
    return 0
}

# =============================================================================
# NAMEREF VARIANTS (High-Performance)
# =============================================================================

# Run benchmark and store result in variable (no subshell)
# Usage: benchmark_run_v RESULT_VAR NAME COMMAND [ITERATIONS]
benchmark_run_v() {
    local -n __brv_out=$1
    shift
    __brv_out=$(benchmark_run "$@")
}

# Calculate statistics and store in variable
# Usage: benchmark_stats_v RESULT_VAR value1 value2 ...
benchmark_stats_v() {
    local -n __bsv_out=$1
    shift
    local -a values=("$@")

    local mean median stddev min max p95 p99 outliers ci_lower ci_upper
    mean=$(_bench_mean "${values[@]}")
    median=$(_bench_median "${values[@]}")
    stddev=$(_bench_stddev "$mean" "${values[@]}")
    min=$(_bench_min "${values[@]}")
    max=$(_bench_max "${values[@]}")
    p95=$(_bench_percentile 95 "${values[@]}")
    p99=$(_bench_percentile 99 "${values[@]}")
    outliers=$(_bench_detect_outliers "${values[@]}")
    local ci_result
    ci_result=$(_bench_confidence_interval "$mean" "$stddev" "${#values[@]}")
    read -r ci_lower ci_upper <<< "$ci_result"

    __bsv_out=$(printf '{"mean":%s,"median":%s,"stddev":%s,"min":%s,"max":%s,"p95":%s,"p99":%s,"outliers":%d,"ci_lower":%s,"ci_upper":%s,"count":%d}' \
        "$mean" "$median" "$stddev" "$min" "$max" "$p95" "$p99" "$outliers" "$ci_lower" "$ci_upper" "${#values[@]}")
}

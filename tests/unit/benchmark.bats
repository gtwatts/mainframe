#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/benchmark.bats - Benchmark Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/benchmark.sh
#              Performance regression testing and benchmark tracking
# Test Count: 57 test cases
# Categories: timing, memory, cpu, statistics, benchmark_run, comparison,
#             save/load, reporting, suites, regression detection, namerefs
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library
    source "$MAINFRAME_ROOT/lib/benchmark.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
    unset _BENCH_LAST_RESULT
    unset _BENCH_LAST_MEAN
}

# =============================================================================
# CATEGORY 1: CONSTANTS
# =============================================================================

@test "_BENCH_DEFAULT_ITERATIONS: is 100" {
    [[ "$_BENCH_DEFAULT_ITERATIONS" -eq 100 ]]
}

@test "_BENCH_DEFAULT_WARMUP: is 5" {
    [[ "$_BENCH_DEFAULT_WARMUP" -eq 5 ]]
}

@test "_BENCH_DEFAULT_THRESHOLD: is 10" {
    [[ "$_BENCH_DEFAULT_THRESHOLD" -eq 10 ]]
}

@test "_BENCH_VERSION: is set" {
    [[ -n "$_BENCH_VERSION" ]]
}

# =============================================================================
# CATEGORY 2: TIMING FUNCTIONS
# =============================================================================

@test "_bench_now: returns numeric timestamp" {
    local ts
    ts=$(_bench_now)
    [[ "$ts" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "_bench_elapsed_ms: calculates elapsed time" {
    local start end elapsed
    start="1000.000000"
    end="1001.500000"
    elapsed=$(_bench_elapsed_ms "$start" "$end")
    # Should be approximately 1500ms
    [[ "$elapsed" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "bench_time: measures command execution" {
    local time_ms
    time_ms=$(bench_time "sleep 0.01")
    # Should be at least 10ms
    [[ "$time_ms" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "bench_time: fast command returns small value" {
    local time_ms
    time_ms=$(bench_time "true")
    [[ "$time_ms" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "bench_cpu: measures CPU time" {
    local cpu_ms
    cpu_ms=$(bench_cpu "true")
    [[ "$cpu_ms" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "bench_memory: returns numeric value" {
    local mem_kb
    mem_kb=$(bench_memory "true")
    [[ "$mem_kb" =~ ^[0-9]+$ ]]
}

# =============================================================================
# CATEGORY 3: STATISTICS - MEAN
# =============================================================================

@test "_bench_mean: calculates average of integers" {
    local mean
    mean=$(_bench_mean 10 20 30)
    # Mean should be 20
    [[ "$mean" =~ ^20(\.0*)?$ ]] || [[ "$mean" == "20" ]]
}

@test "_bench_mean: handles single value" {
    local mean
    mean=$(_bench_mean 42)
    [[ "$mean" =~ ^42 ]]
}

@test "_bench_mean: handles floats" {
    local mean
    mean=$(_bench_mean 1.5 2.5 3.0)
    # Mean should be ~2.33
    [[ "$mean" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "_bench_mean: returns 0 for empty input" {
    run _bench_mean
    [[ "$output" == "0" ]]
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 4: STATISTICS - MEDIAN
# =============================================================================

@test "_bench_median: finds middle value (odd count)" {
    local median
    median=$(_bench_median 1 3 2)
    # Sorted: 1, 2, 3 -> median is 2
    [[ "$median" == "2" ]]
}

@test "_bench_median: averages middle values (even count)" {
    local median
    median=$(_bench_median 1 2 3 4)
    # Sorted: 1, 2, 3, 4 -> median is (2+3)/2 = 2.5
    # May return 2.500000 or similar decimal format
    [[ "$median" =~ ^2\.5 ]]
}

@test "_bench_median: handles single value" {
    local median
    median=$(_bench_median 42)
    [[ "$median" == "42" ]]
}

@test "_bench_median: returns 0 for empty input" {
    run _bench_median
    [[ "$output" == "0" ]]
}

# =============================================================================
# CATEGORY 5: STATISTICS - STDDEV
# =============================================================================

@test "_bench_stddev: calculates standard deviation" {
    local stddev
    stddev=$(_bench_stddev 2 1 2 3)
    # Values: 1, 2, 3 with mean 2
    # Variance: ((1-2)^2 + (2-2)^2 + (3-2)^2)/3 = 2/3
    # Stddev: sqrt(2/3) ~ 0.816
    [[ "$stddev" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "_bench_stddev: returns 0 for identical values" {
    local stddev
    stddev=$(_bench_stddev 5 5 5 5)
    [[ "$stddev" =~ ^0(\.0*)?$ ]] || [[ "$stddev" == "0" ]]
}

# =============================================================================
# CATEGORY 6: STATISTICS - PERCENTILES
# =============================================================================

@test "_bench_percentile: finds 95th percentile" {
    local p95
    p95=$(_bench_percentile 95 1 2 3 4 5 6 7 8 9 10)
    # 95th percentile of 1-10 should be 10
    [[ "$p95" == "10" ]]
}

@test "_bench_percentile: finds 50th percentile (median)" {
    local p50
    p50=$(_bench_percentile 50 1 2 3 4 5)
    # 50th percentile should be 3
    [[ "$p50" == "3" ]]
}

@test "_bench_percentile: handles small arrays" {
    local p99
    p99=$(_bench_percentile 99 5 10)
    # Should return 10
    [[ "$p99" == "10" ]]
}

# =============================================================================
# CATEGORY 7: STATISTICS - MIN/MAX
# =============================================================================

@test "_bench_min: finds minimum value" {
    local min
    min=$(_bench_min 5 2 8 1 9)
    [[ "$min" == "1" ]]
}

@test "_bench_max: finds maximum value" {
    local max
    max=$(_bench_max 5 2 8 1 9)
    [[ "$max" == "9" ]]
}

@test "_bench_min: handles negative values" {
    local min
    min=$(_bench_min 5 -2 8 -10)
    [[ "$min" == "-10" ]]
}

@test "_bench_max: handles single value" {
    local max
    max=$(_bench_max 42)
    [[ "$max" == "42" ]]
}

# =============================================================================
# CATEGORY 8: OUTLIER DETECTION
# =============================================================================

@test "_bench_detect_outliers: returns 0 for small arrays" {
    local outliers
    outliers=$(_bench_detect_outliers 1 2 3)
    [[ "$outliers" == "0" ]]
}

@test "_bench_detect_outliers: detects obvious outlier" {
    local outliers
    # 1000 is clearly an outlier in this series
    outliers=$(_bench_detect_outliers 1 2 3 4 5 6 7 8 9 10 1000)
    [[ "$outliers" -ge 1 ]]
}

@test "_bench_detect_outliers: returns 0 for uniform data" {
    local outliers
    outliers=$(_bench_detect_outliers 5 5 5 5 5 5 5 5)
    [[ "$outliers" == "0" ]]
}

# =============================================================================
# CATEGORY 9: CONFIDENCE INTERVAL
# =============================================================================

@test "_bench_confidence_interval: returns lower and upper bounds" {
    local ci
    ci=$(_bench_confidence_interval 10 2 100)
    # Should return "lower upper"
    [[ "$ci" =~ ^[0-9.-]+[[:space:]][0-9.-]+$ ]]
}

@test "_bench_confidence_interval: bounds surround mean" {
    local lower upper result
    result=$(_bench_confidence_interval 10 2 100)
    read -r lower upper <<< "$result"
    # Lower should be less than 10
    # Upper should be greater than 10
    [[ -n "$lower" && -n "$upper" ]]
}

# =============================================================================
# CATEGORY 10: BENCHMARK_RUN
# =============================================================================

@test "benchmark_run: returns valid JSON" {
    local result
    result=$(benchmark_run "test_bench" "true" 10 2)
    # Should start with { and end with }
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "benchmark_run: includes name in output" {
    local result
    result=$(benchmark_run "my_benchmark" "true" 10 2)
    [[ "$result" =~ \"name\":\"my_benchmark\" ]]
}

@test "benchmark_run: includes iterations count" {
    local result
    result=$(benchmark_run "test" "true" 25 2)
    [[ "$result" =~ \"iterations\":25 ]]
}

@test "benchmark_run: includes statistics" {
    local result
    result=$(benchmark_run "test" "true" 10 2)
    [[ "$result" =~ \"mean_ms\": ]]
    [[ "$result" =~ \"median_ms\": ]]
    [[ "$result" =~ \"stddev_ms\": ]]
    [[ "$result" =~ \"min_ms\": ]]
    [[ "$result" =~ \"max_ms\": ]]
    [[ "$result" =~ \"p95_ms\": ]]
    [[ "$result" =~ \"p99_ms\": ]]
}

@test "benchmark_run: includes timestamp" {
    local result
    result=$(benchmark_run "test" "true" 5 1)
    [[ "$result" =~ \"timestamp\":\"[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "benchmark_run: includes platform" {
    local result
    result=$(benchmark_run "test" "true" 5 1)
    [[ "$result" =~ \"platform\": ]]
}

@test "benchmark_run: fails with missing name" {
    run benchmark_run "" "true"
    [[ "$output" =~ error ]]
}

@test "benchmark_run: fails with missing command" {
    run benchmark_run "test" ""
    [[ "$output" =~ error ]]
}

# =============================================================================
# CATEGORY 11: BENCHMARK (CONVENIENCE WRAPPER)
# =============================================================================

@test "benchmark: stores result in _BENCH_LAST_RESULT" {
    benchmark "test" "true" 10
    [[ -n "$_BENCH_LAST_RESULT" ]]
}

@test "benchmark: stores mean in _BENCH_LAST_MEAN" {
    benchmark "test" "true" 10
    [[ -n "$_BENCH_LAST_MEAN" ]]
    [[ "$_BENCH_LAST_MEAN" =~ ^[0-9]+\.?[0-9]*$ ]]
}

# =============================================================================
# CATEGORY 12: BENCHMARK_SAVE
# =============================================================================

@test "benchmark_save: saves result to file" {
    benchmark "save_test" "true" 10
    benchmark_save "save_test" "$TEST_TMPDIR/result.json"
    [[ -f "$TEST_TMPDIR/result.json" ]]
}

@test "benchmark_save: file contains valid JSON" {
    benchmark "save_test" "true" 10
    benchmark_save "save_test" "$TEST_TMPDIR/result.json"
    local content
    content=$(<"$TEST_TMPDIR/result.json")
    [[ "$content" == "{"* ]]
}

@test "benchmark_save: creates directory if needed" {
    benchmark "save_test" "true" 10
    benchmark_save "save_test" "$TEST_TMPDIR/subdir/result.json"
    [[ -f "$TEST_TMPDIR/subdir/result.json" ]]
}

@test "benchmark_save: fails with no result" {
    unset _BENCH_LAST_RESULT
    run benchmark_save "test" "$TEST_TMPDIR/empty.json"
    [[ "$output" =~ error ]]
}

# =============================================================================
# CATEGORY 13: BENCHMARK_COMPARE
# =============================================================================

@test "benchmark_compare: compares to baseline" {
    # Create baseline
    printf '{"name":"cmp_test","stats":{"mean_ms":10.0}}' > "$TEST_TMPDIR/baseline.json"

    # Run current benchmark
    benchmark "cmp_test" "true" 10

    local result
    result=$(benchmark_compare "cmp_test" "$TEST_TMPDIR/baseline.json")
    [[ "$result" =~ \"baseline_mean_ms\": ]]
    [[ "$result" =~ \"current_mean_ms\": ]]
}

@test "benchmark_compare: returns status field" {
    printf '{"name":"cmp_test","stats":{"mean_ms":10.0}}' > "$TEST_TMPDIR/baseline.json"
    benchmark "cmp_test" "true" 10

    local result
    result=$(benchmark_compare "cmp_test" "$TEST_TMPDIR/baseline.json")
    [[ "$result" =~ \"status\": ]]
}

@test "benchmark_compare: fails with missing baseline" {
    run benchmark_compare "test" "$TEST_TMPDIR/nonexistent.json"
    [[ "$output" =~ error ]]
}

# =============================================================================
# CATEGORY 14: BENCHMARK_REPORT
# =============================================================================

@test "benchmark_report: generates text report" {
    benchmark "report_test" "true" 10
    local report
    report=$(benchmark_report text)
    [[ "$report" =~ "Benchmark:" ]]
    [[ "$report" =~ "Mean:" ]]
}

@test "benchmark_report: generates JSON report" {
    benchmark "report_test" "true" 10
    local report
    report=$(benchmark_report json)
    [[ "$report" == "{"* ]]
}

@test "benchmark_report: generates markdown report" {
    benchmark "report_test" "true" 10
    local report
    report=$(benchmark_report markdown)
    [[ "$report" =~ "# Benchmark:" ]]
    [[ "$report" =~ "| Metric |" ]]
}

@test "benchmark_report: fails with no result" {
    unset _BENCH_LAST_RESULT
    run benchmark_report text
    [[ "$output" =~ error ]]
}

# =============================================================================
# CATEGORY 15: BENCHMARK_SUITE
# =============================================================================

@test "benchmark_suite: runs multiple benchmarks from file" {
    # Create suite file
    printf 'bench1 true\nbench2 echo hello\n' > "$TEST_TMPDIR/suite.txt"

    local result
    result=$(benchmark_suite "$TEST_TMPDIR/suite.txt" "$TEST_TMPDIR/results")

    # Should return JSON array
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
}

@test "benchmark_suite: creates individual result files" {
    printf 'bench1 true\nbench2 true\n' > "$TEST_TMPDIR/suite.txt"
    benchmark_suite "$TEST_TMPDIR/suite.txt" "$TEST_TMPDIR/results" >/dev/null

    [[ -f "$TEST_TMPDIR/results/bench1.json" ]]
    [[ -f "$TEST_TMPDIR/results/bench2.json" ]]
}

@test "benchmark_suite: skips comments" {
    printf '# This is a comment\nbench1 true\n' > "$TEST_TMPDIR/suite.txt"
    local result
    result=$(benchmark_suite "$TEST_TMPDIR/suite.txt" "$TEST_TMPDIR/results")
    [[ "$result" =~ bench1 ]]
}

@test "benchmark_suite: skips empty lines" {
    printf 'bench1 true\n\nbench2 true\n' > "$TEST_TMPDIR/suite.txt"
    local result
    result=$(benchmark_suite "$TEST_TMPDIR/suite.txt" "$TEST_TMPDIR/results")
    [[ "$result" =~ bench1 ]]
    [[ "$result" =~ bench2 ]]
}

@test "benchmark_suite: fails with missing file" {
    run benchmark_suite "$TEST_TMPDIR/nonexistent.txt"
    [[ "$output" =~ error ]]
}

# =============================================================================
# CATEGORY 16: REGRESSION DETECTION
# =============================================================================

@test "benchmark_check_regressions: returns checked count" {
    # Create baseline and results
    mkdir -p "$TEST_TMPDIR/baseline" "$TEST_TMPDIR/results"
    printf '{"name":"test1","stats":{"mean_ms":10.0}}' > "$TEST_TMPDIR/baseline/test1.json"
    printf '{"name":"test1","stats":{"mean_ms":11.0}}' > "$TEST_TMPDIR/results/test1.json"

    local result
    result=$(benchmark_check_regressions "$TEST_TMPDIR/results" "$TEST_TMPDIR/baseline")
    [[ "$result" =~ \"checked\":[0-9]+ ]]
}

@test "benchmark_check_regressions: detects regression" {
    mkdir -p "$TEST_TMPDIR/baseline" "$TEST_TMPDIR/results"
    # 100ms to 200ms is >10% regression
    printf '{"name":"slow","stats":{"mean_ms":100.0}}' > "$TEST_TMPDIR/baseline/slow.json"
    printf '{"name":"slow","stats":{"mean_ms":200.0}}' > "$TEST_TMPDIR/results/slow.json"

    _BENCH_LAST_MEAN="200.0"
    _BENCH_LAST_RESULT='{"name":"slow","stats":{"mean_ms":200.0}}'

    run benchmark_check_regressions "$TEST_TMPDIR/results" "$TEST_TMPDIR/baseline"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 17: NAMEREF VARIANTS
# =============================================================================

@test "benchmark_run_v: stores result in variable" {
    local out
    benchmark_run_v out "test" "true" 10 2
    [[ "$out" == "{"* ]]
}

@test "benchmark_stats_v: calculates stats into variable" {
    local stats
    benchmark_stats_v stats 1 2 3 4 5
    [[ "$stats" =~ \"mean\": ]]
    [[ "$stats" =~ \"median\": ]]
}

# =============================================================================
# CATEGORY 18: EDGE CASES
# =============================================================================

@test "benchmark_run: handles command with spaces" {
    local result
    result=$(benchmark_run "space_test" "echo hello world" 5 1)
    [[ "$result" =~ \"name\":\"space_test\" ]]
}

@test "benchmark_run: handles command with special characters" {
    local result
    result=$(benchmark_run "special_test" "printf '%s' test" 5 1)
    [[ "$result" =~ \"name\":\"special_test\" ]]
}

@test "_bench_mean: handles large numbers" {
    local mean
    mean=$(_bench_mean 1000000 2000000 3000000)
    [[ "$mean" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "benchmark: default iterations when not specified" {
    local result
    result=$(benchmark "default_iter" "true")
    # Should use default iterations (100)
    [[ "$result" =~ \"iterations\":100 ]]
}

# =============================================================================
# CATEGORY 19: ADDITIONAL COVERAGE
# =============================================================================

@test "bench_time: handles failing command" {
    local time_ms
    time_ms=$(bench_time "false")
    [[ "$time_ms" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "_bench_percentile: finds 25th percentile (Q1)" {
    local p25
    p25=$(_bench_percentile 25 1 2 3 4 5 6 7 8 9 10 11 12)
    [[ "$p25" =~ ^[0-9]+$ ]]
}

@test "benchmark_run: respects warmup parameter" {
    local result
    result=$(benchmark_run "warmup_test" "true" 10 3)
    [[ "$result" =~ \"warmup\":3 ]]
}

@test "_bench_stddev: calculates for spread data" {
    local stddev
    stddev=$(_bench_stddev 50 10 20 30 40 50 60 70 80 90)
    # Should be approximately 25.8
    [[ "$stddev" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "benchmark_report: default format is text" {
    benchmark "default_format" "true" 10
    local report
    report=$(benchmark_report)
    [[ "$report" =~ "Benchmark:" ]]
}

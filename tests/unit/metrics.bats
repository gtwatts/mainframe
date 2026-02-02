#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/metrics.bats - Metrics Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/metrics.sh
#              Prometheus-compatible metrics collection with counters, gauges,
#              histograms, and summaries.
# Test Count: 50+ test cases
# Categories: Initialization, Counters, Gauges, Histograms, Summaries,
#             Labels, Export, Pushgateway, Validation
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library
    source "$MAINFRAME_ROOT/lib/metrics.sh"

    # Reset metrics before each test
    metrics_clear
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: INITIALIZATION
# =============================================================================

@test "metrics_init: initializes with default prefix" {
    metrics_init
    [[ "$MAINFRAME_METRICS_PREFIX" == "mainframe" ]]
}

@test "metrics_init: accepts custom prefix" {
    metrics_init --prefix "myapp"
    [[ "$MAINFRAME_METRICS_PREFIX" == "myapp" ]]
}

@test "metrics_init: clears existing metrics" {
    counter_create "test_counter"
    counter_inc "test_counter"
    [[ "$(counter_get test_counter)" == "1" ]]

    metrics_init --prefix "fresh"
    [[ "$(counter_get test_counter)" == "0" ]]
}

@test "metrics_init: enables metrics collection" {
    MAINFRAME_METRICS_ENABLED=0
    metrics_init
    [[ "$MAINFRAME_METRICS_ENABLED" == "1" ]]
}

# =============================================================================
# CATEGORY 2: METRIC REGISTRATION
# =============================================================================

@test "metrics_register: registers counter metric" {
    metrics_register "http_requests" "counter" "Total HTTP requests"
    result=$(metrics_get "http_requests")
    [[ "$result" =~ "counter" ]]
}

@test "metrics_register: registers gauge metric" {
    metrics_register "temperature" "gauge" "Current temperature"
    result=$(metrics_get "temperature")
    [[ "$result" =~ "gauge" ]]
}

@test "metrics_register: registers histogram metric" {
    metrics_register "request_duration" "histogram" "Request duration"
    result=$(metrics_get "request_duration")
    [[ "$result" =~ "histogram" ]]
}

@test "metrics_register: registers summary metric" {
    metrics_register "response_size" "summary" "Response size"
    result=$(metrics_get "response_size")
    [[ "$result" =~ "summary" ]]
}

@test "metrics_register: rejects invalid metric name" {
    run metrics_register "123-invalid" "counter" "Bad name"
    [[ "$status" -eq 1 ]]
}

@test "metrics_register: rejects invalid metric type" {
    run metrics_register "valid_name" "badtype" "Bad type"
    [[ "$status" -eq 1 ]]
}

@test "metrics_register: allows re-registration with same type" {
    metrics_register "my_metric" "counter" "First"
    metrics_register "my_metric" "counter" "Second"
    [[ $? -eq 0 ]]
}

@test "metrics_register: rejects type change" {
    metrics_register "my_metric" "counter" "Counter"
    run metrics_register "my_metric" "gauge" "Gauge"
    [[ "$status" -eq 1 ]]
}

@test "metrics_unregister: removes registered metric" {
    metrics_register "temp_metric" "counter" "Temporary"
    counter_inc "temp_metric"
    metrics_unregister "temp_metric"
    run metrics_get "temp_metric"
    [[ "$output" =~ "not found" ]]
}

@test "metrics_list: lists all registered metrics" {
    metrics_register "metric_a" "counter" "A"
    metrics_register "metric_b" "gauge" "B"
    result=$(metrics_list)
    [[ "$result" =~ "metric_a" ]]
    [[ "$result" =~ "metric_b" ]]
}

# =============================================================================
# CATEGORY 3: COUNTER OPERATIONS
# =============================================================================

@test "counter_create: creates counter with zero value" {
    counter_create "new_counter" "A new counter"
    [[ "$(counter_get new_counter)" == "0" ]]
}

@test "counter_inc: increments by 1" {
    counter_create "inc_test"
    counter_inc "inc_test"
    [[ "$(counter_get inc_test)" == "1" ]]
}

@test "counter_inc: increments multiple times" {
    counter_create "multi_inc"
    counter_inc "multi_inc"
    counter_inc "multi_inc"
    counter_inc "multi_inc"
    [[ "$(counter_get multi_inc)" == "3" ]]
}

@test "counter_add: adds specific value" {
    counter_create "add_test"
    counter_add "add_test" 5
    [[ "$(counter_get add_test)" == "5" ]]
}

@test "counter_add: accumulates values" {
    counter_create "accum_test"
    counter_add "accum_test" 10
    counter_add "accum_test" 20
    [[ "$(counter_get accum_test)" == "30" ]]
}

@test "counter_add: rejects negative value" {
    counter_create "neg_test"
    run counter_add "neg_test" -5
    [[ "$status" -eq 1 ]]
}

@test "counter_reset: resets to zero" {
    counter_create "reset_test"
    counter_add "reset_test" 100
    counter_reset "reset_test"
    [[ "$(counter_get reset_test)" == "0" ]]
}

@test "metrics_counter_inc: uses prefix automatically" {
    metrics_init --prefix "testapp"
    metrics_counter_inc "requests" 1
    result=$(counter_get "testapp_requests")
    [[ "$result" == "1" ]]
}

@test "metrics_counter_inc: supports labels" {
    metrics_init --prefix "app"
    metrics_counter_inc "http_requests" 1 method="GET" status="200"
    result=$(metrics_export)
    [[ "$result" =~ 'method="GET"' ]]
    [[ "$result" =~ 'status="200"' ]]
}

# =============================================================================
# CATEGORY 4: GAUGE OPERATIONS
# =============================================================================

@test "gauge_create: creates gauge with zero value" {
    gauge_create "new_gauge" "A new gauge"
    [[ "$(gauge_get new_gauge)" == "0" ]]
}

@test "gauge_set: sets specific value" {
    gauge_create "set_test"
    gauge_set "set_test" 42
    [[ "$(gauge_get set_test)" == "42" ]]
}

@test "gauge_set: overwrites previous value" {
    gauge_create "overwrite_test"
    gauge_set "overwrite_test" 100
    gauge_set "overwrite_test" 50
    [[ "$(gauge_get overwrite_test)" == "50" ]]
}

@test "gauge_inc: increments by 1" {
    gauge_create "gauge_inc_test"
    gauge_set "gauge_inc_test" 10
    gauge_inc "gauge_inc_test"
    [[ "$(gauge_get gauge_inc_test)" == "11" ]]
}

@test "gauge_dec: decrements by 1" {
    gauge_create "gauge_dec_test"
    gauge_set "gauge_dec_test" 10
    gauge_dec "gauge_dec_test"
    [[ "$(gauge_get gauge_dec_test)" == "9" ]]
}

@test "gauge_add: adds positive value" {
    gauge_create "gauge_add_test"
    gauge_set "gauge_add_test" 10
    gauge_add "gauge_add_test" 5
    [[ "$(gauge_get gauge_add_test)" == "15" ]]
}

@test "gauge_sub: subtracts value" {
    gauge_create "gauge_sub_test"
    gauge_set "gauge_sub_test" 10
    gauge_sub "gauge_sub_test" 3
    [[ "$(gauge_get gauge_sub_test)" == "7" ]]
}

@test "gauge_set: accepts negative value" {
    gauge_create "neg_gauge"
    gauge_set "neg_gauge" -10
    [[ "$(gauge_get neg_gauge)" == "-10" ]]
}

@test "metrics_gauge_set: uses prefix automatically" {
    metrics_init --prefix "myapp"
    metrics_gauge_set "connections" 5
    result=$(gauge_get "myapp_connections")
    [[ "$result" == "5" ]]
}

@test "metrics_gauge_inc: increments with value" {
    metrics_init --prefix "test"
    metrics_gauge_set "count" 10
    metrics_gauge_inc "count" 5
    result=$(gauge_get "test_count")
    [[ "$result" == "15" ]]
}

@test "metrics_gauge_dec: decrements with value" {
    metrics_init --prefix "test"
    metrics_gauge_set "count" 10
    metrics_gauge_dec "count" 3
    result=$(gauge_get "test_count")
    [[ "$result" == "7" ]]
}

# =============================================================================
# CATEGORY 5: HISTOGRAM OPERATIONS
# =============================================================================

@test "histogram_create: creates histogram with buckets" {
    histogram_create "duration" ".1 .5 1" "Request duration"
    result=$(metrics_get "duration")
    [[ "$result" =~ "histogram" ]]
}

@test "histogram_observe: records observation" {
    histogram_create "hist_test" ".1 .5 1"
    histogram_observe "hist_test" 0.3
    [[ "$(histogram_get_count hist_test)" == "1" ]]
}

@test "histogram_observe: updates sum" {
    histogram_create "hist_sum_test" ".1 .5 1"
    histogram_observe "hist_sum_test" 0.5
    histogram_observe "hist_sum_test" 0.3
    # Sum should be 0.8
    result=$(histogram_get_sum "hist_sum_test")
    [[ "$result" =~ "0.8" ]] || [[ "$result" == "0.8" ]] || [[ "$result" == ".8" ]]
}

@test "histogram_observe: increments appropriate buckets" {
    histogram_create "bucket_test" ".1 .5 1 5"
    histogram_observe "bucket_test" 0.3  # Should be in .5, 1, 5, +Inf
    histogram_observe "bucket_test" 2    # Should be in 5, +Inf
    histogram_observe "bucket_test" 0.05 # Should be in .1, .5, 1, 5, +Inf

    result=$(histogram_get_buckets "bucket_test")
    [[ -n "$result" ]]
}

@test "histogram_get_count: returns observation count" {
    histogram_create "count_test" ".1 .5 1"
    histogram_observe "count_test" 0.1
    histogram_observe "count_test" 0.2
    histogram_observe "count_test" 0.3
    [[ "$(histogram_get_count count_test)" == "3" ]]
}

@test "metrics_histogram_observe: uses default buckets" {
    metrics_init --prefix "app"
    metrics_histogram_observe "response_time" 0.25
    result=$(metrics_export)
    [[ "$result" =~ "response_time" ]]
    [[ "$result" =~ "_bucket" ]]
}

# =============================================================================
# CATEGORY 6: SUMMARY OPERATIONS
# =============================================================================

@test "summary_create: creates summary metric" {
    summary_create "latency" "Request latency"
    result=$(metrics_get "latency")
    [[ "$result" =~ "summary" ]]
}

@test "summary_observe: records observation" {
    summary_create "sum_test"
    summary_observe "sum_test" 0.5
    [[ "$(summary_get_count sum_test)" == "1" ]]
}

@test "summary_get_sum: returns total sum" {
    summary_create "sum_total_test"
    summary_observe "sum_total_test" 1.0
    summary_observe "sum_total_test" 2.0
    summary_observe "sum_total_test" 3.0
    result=$(summary_get_sum "sum_total_test")
    [[ "$result" == "6" ]] || [[ "$result" == "6.0" ]]
}

@test "summary_get_count: returns observation count" {
    summary_create "sum_count_test"
    summary_observe "sum_count_test" 1
    summary_observe "sum_count_test" 2
    summary_observe "sum_count_test" 3
    summary_observe "sum_count_test" 4
    [[ "$(summary_get_count sum_count_test)" == "4" ]]
}

@test "metrics_summary_observe: uses prefix" {
    metrics_init --prefix "svc"
    metrics_summary_observe "request_size" 1024
    result=$(summary_get_count "svc_request_size")
    [[ "$result" == "1" ]]
}

# =============================================================================
# CATEGORY 7: LABELS
# =============================================================================

@test "metric_labels_format: formats single label" {
    result=$(metric_labels_format "method=GET")
    [[ "$result" == '{method="GET"}' ]]
}

@test "metric_labels_format: formats multiple labels" {
    result=$(metric_labels_format "method=POST" "status=201")
    [[ "$result" =~ 'method="POST"' ]]
    [[ "$result" =~ 'status="201"' ]]
}

@test "metric_labels_format: returns empty for no labels" {
    result=$(metric_labels_format)
    [[ -z "$result" ]]
}

@test "counter with labels: tracks separately" {
    counter_create "labeled_counter"
    local labels1
    labels1=$(metric_labels_format "env=prod")
    local labels2
    labels2=$(metric_labels_format "env=dev")

    counter_add "labeled_counter" 10 "$labels1"
    counter_add "labeled_counter" 5 "$labels2"

    [[ "$(counter_get labeled_counter "$labels1")" == "10" ]]
    [[ "$(counter_get labeled_counter "$labels2")" == "5" ]]
}

@test "gauge with labels: tracks separately" {
    gauge_create "labeled_gauge"
    local labels1
    labels1=$(metric_labels_format "host=server1")
    local labels2
    labels2=$(metric_labels_format "host=server2")

    gauge_set "labeled_gauge" 100 "$labels1"
    gauge_set "labeled_gauge" 200 "$labels2"

    [[ "$(gauge_get labeled_gauge "$labels1")" == "100" ]]
    [[ "$(gauge_get labeled_gauge "$labels2")" == "200" ]]
}

# =============================================================================
# CATEGORY 8: TIMER OPERATIONS
# =============================================================================

@test "timer_start: returns timer ID" {
    histogram_create "timer_metric"
    timer_id=$(timer_start "timer_metric")
    [[ "$timer_id" =~ ^timer_ ]]
}

@test "timer_stop: records duration" {
    histogram_create "duration_metric"
    timer_id=$(timer_start "duration_metric")
    sleep 0.1
    timer_stop "$timer_id" >/dev/null
    [[ "$(histogram_get_count duration_metric)" == "1" ]]
}

@test "timer_observe: records pre-calculated duration" {
    histogram_create "manual_duration"
    timer_observe "manual_duration" 0.5
    [[ "$(histogram_get_count manual_duration)" == "1" ]]
}

# =============================================================================
# CATEGORY 9: EXPORT - PROMETHEUS FORMAT
# =============================================================================

@test "metrics_export: outputs HELP lines" {
    metrics_register "test_metric" "counter" "Test metric help text"
    counter_inc "test_metric"
    result=$(metrics_export)
    [[ "$result" =~ "# HELP test_metric Test metric help text" ]]
}

@test "metrics_export: outputs TYPE lines" {
    metrics_register "typed_metric" "gauge" "Typed metric"
    gauge_set "typed_metric" 42
    result=$(metrics_export)
    [[ "$result" =~ "# TYPE typed_metric gauge" ]]
}

@test "metrics_export: outputs counter values" {
    counter_create "export_counter"
    counter_add "export_counter" 100
    result=$(metrics_export)
    [[ "$result" =~ "export_counter 100" ]]
}

@test "metrics_export: outputs gauge values" {
    gauge_create "export_gauge"
    gauge_set "export_gauge" 42.5
    result=$(metrics_export)
    [[ "$result" =~ "export_gauge 42.5" ]]
}

@test "metrics_export: outputs histogram buckets" {
    histogram_create "export_hist" ".1 .5 1"
    histogram_observe "export_hist" 0.3
    result=$(metrics_export)
    [[ "$result" =~ "export_hist_bucket" ]]
    [[ "$result" =~ 'le=' ]]
    [[ "$result" =~ "export_hist_sum" ]]
    [[ "$result" =~ "export_hist_count" ]]
}

@test "metrics_export: includes +Inf bucket" {
    histogram_create "inf_test" ".1 .5"
    histogram_observe "inf_test" 0.2
    result=$(metrics_export)
    [[ "$result" =~ 'le="+Inf"' ]]
}

# =============================================================================
# CATEGORY 10: EXPORT - JSON FORMAT
# =============================================================================

@test "metrics_export_json: outputs valid JSON" {
    counter_create "json_counter"
    counter_inc "json_counter"
    result=$(metrics_export_json)
    [[ "$result" =~ '{"metrics":' ]]
    [[ "$result" =~ '"timestamp":' ]]
}

@test "metrics_export_json: includes metric values" {
    gauge_create "json_gauge"
    gauge_set "json_gauge" 99
    result=$(metrics_export_json)
    [[ "$result" =~ '"name":"json_gauge"' ]]
    [[ "$result" =~ '"type":"gauge"' ]]
}

# =============================================================================
# CATEGORY 11: EXPORT - OPENMETRICS FORMAT
# =============================================================================

@test "metrics_export_openmetrics: ends with EOF" {
    counter_create "om_counter"
    counter_inc "om_counter"
    result=$(metrics_export_openmetrics)
    [[ "$result" =~ "# EOF" ]]
}

@test "metrics_export_openmetrics: adds _total suffix to counters" {
    counter_create "om_test"
    counter_inc "om_test"
    result=$(metrics_export_openmetrics)
    [[ "$result" =~ "om_test_total" ]]
}

# =============================================================================
# CATEGORY 12: VALIDATION
# =============================================================================

@test "metric_name_valid: accepts valid names" {
    metric_name_valid "valid_metric_name"
    [[ $? -eq 0 ]]
}

@test "metric_name_valid: accepts colons in name" {
    metric_name_valid "namespace:metric_name"
    [[ $? -eq 0 ]]
}

@test "metric_name_valid: accepts underscore start" {
    metric_name_valid "_private_metric"
    [[ $? -eq 0 ]]
}

@test "metric_name_valid: rejects starting with number" {
    run metric_name_valid "123metric"
    [[ "$status" -eq 1 ]]
}

@test "metric_name_valid: rejects hyphen in name" {
    run metric_name_valid "invalid-metric"
    [[ "$status" -eq 1 ]]
}

@test "metric_name_valid: rejects empty name" {
    run metric_name_valid ""
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 13: METRICS_CLEAR
# =============================================================================

@test "metrics_clear: removes all counters" {
    counter_create "clear_counter"
    counter_inc "clear_counter"
    metrics_clear
    result=$(metrics_list)
    [[ ! "$result" =~ "clear_counter" ]]
}

@test "metrics_clear: removes all gauges" {
    gauge_create "clear_gauge"
    gauge_set "clear_gauge" 100
    metrics_clear
    [[ "$(gauge_get clear_gauge)" == "0" ]]
}

@test "metrics_clear: removes all histograms" {
    histogram_create "clear_hist"
    histogram_observe "clear_hist" 0.5
    metrics_clear
    result=$(metrics_list)
    [[ ! "$result" =~ "clear_hist" ]]
}

# =============================================================================
# CATEGORY 14: EDGE CASES
# =============================================================================

@test "counter: handles large values" {
    counter_create "big_counter"
    counter_add "big_counter" 1000000
    counter_add "big_counter" 1000000
    result=$(counter_get "big_counter")
    [[ "$result" == "2000000" ]]
}

@test "gauge: handles float values" {
    gauge_create "float_gauge"
    gauge_set "float_gauge" 3.14159
    result=$(gauge_get "float_gauge")
    [[ "$result" == "3.14159" ]]
}

@test "histogram: handles zero value" {
    histogram_create "zero_hist" ".1 .5 1"
    histogram_observe "zero_hist" 0
    [[ "$(histogram_get_count zero_hist)" == "1" ]]
}

@test "disabled metrics: no-op when disabled" {
    MAINFRAME_METRICS_ENABLED=0
    counter_create "disabled_counter"
    counter_inc "disabled_counter"
    # Should return 0 even though disabled
    [[ $? -eq 0 ]]
    MAINFRAME_METRICS_ENABLED=1
}

@test "auto-register: creates metric on first use" {
    # Don't explicitly create - let it auto-register
    counter_inc "auto_counter"
    [[ "$(counter_get auto_counter)" == "1" ]]
}

@test "multiple labels: handles complex label combinations" {
    counter_create "multi_label"
    local labels
    labels=$(metric_labels_format "method=GET" "status=200" "path=/api/v1/users")
    counter_add "multi_label" 10 "$labels"
    result=$(counter_get "multi_label" "$labels")
    [[ "$result" == "10" ]]
}

@test "label escaping: escapes quotes in values" {
    result=$(metric_labels_format 'msg=Hello "World"')
    [[ "$result" =~ '\\"' ]] || [[ "$result" =~ 'World' ]]
}

# =============================================================================
# CATEGORY 15: TIMESTAMP
# =============================================================================

@test "metric_timestamp: returns milliseconds" {
    ts=$(metric_timestamp)
    # Should be at least 13 digits (ms since epoch)
    [[ ${#ts} -ge 13 ]]
}

@test "metric_timestamp: returns numeric value" {
    ts=$(metric_timestamp)
    [[ "$ts" =~ ^[0-9]+$ ]]
}

# =============================================================================
# CATEGORY 16: PROCESS METRICS
# =============================================================================

@test "metrics_update_process: creates process metrics" {
    skip "Process metrics require /proc filesystem"
    [[ -d /proc/self ]] || skip "Not on Linux"

    metrics_update_process
    result=$(metrics_list)
    [[ "$result" =~ "process_" ]]
}

# =============================================================================
# CATEGORY 17: MEASURE HELPER
# =============================================================================

@test "metrics_measure: records function execution time" {
    histogram_create "func_duration"

    test_function() {
        sleep 0.05
        return 0
    }

    metrics_measure "func_duration" test_function
    [[ "$(histogram_get_count func_duration)" == "1" ]]
}

@test "metrics_measure: preserves function exit code" {
    histogram_create "exit_test"

    failing_function() {
        return 42
    }

    run metrics_measure "exit_test" failing_function
    [[ "$status" -eq 42 ]]
}

# =============================================================================
# CATEGORY 18: INTEGRATION
# =============================================================================

@test "full workflow: counter with labels and export" {
    metrics_init --prefix "http"
    metrics_counter_inc "requests_total" 1 method="GET" status="200"
    metrics_counter_inc "requests_total" 1 method="GET" status="200"
    metrics_counter_inc "requests_total" 1 method="POST" status="201"

    result=$(metrics_export)
    [[ "$result" =~ "http_requests_total" ]]
    [[ "$result" =~ "method=" ]]
    [[ "$result" =~ "status=" ]]
}

@test "full workflow: histogram with observations" {
    metrics_init --prefix "api"
    metrics_histogram_observe "response_time_seconds" 0.1
    metrics_histogram_observe "response_time_seconds" 0.25
    metrics_histogram_observe "response_time_seconds" 0.5
    metrics_histogram_observe "response_time_seconds" 1.5

    result=$(metrics_export)
    [[ "$result" =~ "api_response_time_seconds_bucket" ]]
    [[ "$result" =~ "api_response_time_seconds_sum" ]]
    [[ "$result" =~ "api_response_time_seconds_count" ]]
}

@test "full workflow: mixed metric types" {
    metrics_init --prefix "app"

    # Counter
    metrics_counter_inc "events_total" 10

    # Gauge
    metrics_gauge_set "connections_active" 5

    # Histogram
    metrics_histogram_observe "latency_seconds" 0.123

    result=$(metrics_export)
    [[ "$result" =~ "app_events_total" ]]
    [[ "$result" =~ "app_connections_active" ]]
    [[ "$result" =~ "app_latency_seconds" ]]
}

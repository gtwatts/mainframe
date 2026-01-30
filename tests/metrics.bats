#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Metrics Module Tests
# =============================================================================
# Comprehensive tests for Prometheus-compatible metrics library
# =============================================================================

load 'test_helper'

setup() {
    source_lib "metrics"
    export MAINFRAME_METRICS_ENABLED=1
    metrics_clear
    TEST_DIR=$(create_test_dir "metrics")
}

teardown() {
    metrics_clear
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# METRIC NAME VALIDATION TESTS
# =============================================================================

@test "metric_name_valid accepts valid names" {
    metric_name_valid "http_requests_total"
    metric_name_valid "my_metric"
    metric_name_valid "_internal_metric"
    metric_name_valid "my:namespaced:metric"
    metric_name_valid "UPPERCASE_METRIC"
    metric_name_valid "metric123"
}

@test "metric_name_valid rejects invalid names" {
    ! metric_name_valid ""
    ! metric_name_valid "123_starts_with_number"
    ! metric_name_valid "has-dashes"
    ! metric_name_valid "has spaces"
    ! metric_name_valid "has.dots"
}

# =============================================================================
# METRIC LABELS FORMAT TESTS
# =============================================================================

@test "metric_labels_format formats single label" {
    local result
    result=$(metric_labels_format "method=GET")
    [[ "$result" == '{method="GET"}' ]]
}

@test "metric_labels_format formats multiple labels" {
    local result
    result=$(metric_labels_format "method=GET" "status=200")
    [[ "$result" == '{method="GET",status="200"}' ]]
}

@test "metric_labels_format returns empty for no labels" {
    local result
    result=$(metric_labels_format)
    [[ -z "$result" ]]
}

@test "metric_labels_format escapes special characters" {
    local result
    result=$(metric_labels_format 'path=/api/v1/users')
    [[ "$result" == '{path="/api/v1/users"}' ]]
}

@test "metric_labels_format handles quoted values" {
    local result
    result=$(metric_labels_format 'method="POST"')
    [[ "$result" == '{method="POST"}' ]]
}

# =============================================================================
# METRIC REGISTRATION TESTS
# =============================================================================

@test "metrics_register creates counter" {
    metrics_register "test_counter" "counter" "A test counter"
    local info
    info=$(metrics_get "test_counter")
    [[ "$info" == *'"type":"counter"'* ]]
    [[ "$info" == *'"help":"A test counter"'* ]]
}

@test "metrics_register creates gauge" {
    metrics_register "test_gauge" "gauge" "A test gauge"
    local info
    info=$(metrics_get "test_gauge")
    [[ "$info" == *'"type":"gauge"'* ]]
}

@test "metrics_register creates histogram" {
    metrics_register "test_histogram" "histogram"
    local info
    info=$(metrics_get "test_histogram")
    [[ "$info" == *'"type":"histogram"'* ]]
}

@test "metrics_register creates summary" {
    metrics_register "test_summary" "summary"
    local info
    info=$(metrics_get "test_summary")
    [[ "$info" == *'"type":"summary"'* ]]
}

@test "metrics_register rejects invalid type" {
    ! metrics_register "test_metric" "invalid_type" 2>/dev/null
}

@test "metrics_register rejects invalid name" {
    ! metrics_register "123invalid" "counter" 2>/dev/null
}

@test "metrics_register allows re-registration with same type" {
    metrics_register "test_metric" "counter"
    metrics_register "test_metric" "counter"
}

@test "metrics_register rejects type change" {
    metrics_register "test_metric" "counter"
    ! metrics_register "test_metric" "gauge" 2>/dev/null
}

@test "metrics_unregister removes metric" {
    metrics_register "test_metric" "counter"
    metrics_unregister "test_metric"
    ! metrics_get "test_metric" 2>/dev/null
}

@test "metrics_list returns all registered metrics" {
    metrics_register "metric_a" "counter"
    metrics_register "metric_b" "gauge"
    local list
    list=$(metrics_list)
    [[ "$list" == *'"metric_a"'* ]]
    [[ "$list" == *'"metric_b"'* ]]
}

@test "metrics_clear removes all metrics" {
    metrics_register "metric_a" "counter"
    metrics_register "metric_b" "gauge"
    metrics_clear
    local list
    list=$(metrics_list)
    [[ "$list" == "[]" ]]
}

# =============================================================================
# COUNTER TESTS
# =============================================================================

@test "counter_create initializes to zero" {
    counter_create "test_counter"
    local val
    val=$(counter_get "test_counter")
    [[ "$val" == "0" ]]
}

@test "counter_inc increments by one" {
    counter_create "test_counter"
    counter_inc "test_counter"
    local val
    val=$(counter_get "test_counter")
    [[ "$val" == "1" ]]
}

@test "counter_inc increments multiple times" {
    counter_create "test_counter"
    counter_inc "test_counter"
    counter_inc "test_counter"
    counter_inc "test_counter"
    local val
    val=$(counter_get "test_counter")
    [[ "$val" == "3" ]]
}

@test "counter_add adds specified value" {
    counter_create "test_counter"
    counter_add "test_counter" 5
    local val
    val=$(counter_get "test_counter")
    [[ "$val" == "5" ]]
}

@test "counter_add rejects negative values" {
    counter_create "test_counter"
    ! counter_add "test_counter" -1 2>/dev/null
}

@test "counter_add handles float values" {
    counter_create "test_counter"
    counter_add "test_counter" 1.5
    counter_add "test_counter" 2.5
    local val
    val=$(counter_get "test_counter")
    # Should be 4 (with bc) or truncated without bc
    [[ "$val" == "4" || "$val" == "4.0" ]]
}

@test "counter_reset sets to zero" {
    counter_create "test_counter"
    counter_add "test_counter" 100
    counter_reset "test_counter"
    local val
    val=$(counter_get "test_counter")
    [[ "$val" == "0" ]]
}

@test "counter_labels creates labeled counter" {
    counter_labels "http_requests" "method status" "HTTP requests"
    local labels
    labels=$(metric_labels_format "method=GET" "status=200")
    counter_inc "http_requests" "$labels"
    counter_inc "http_requests" "$labels"
    local val
    val=$(counter_get "http_requests" "$labels")
    [[ "$val" == "2" ]]
}

@test "counter with different labels are independent" {
    counter_create "http_requests"
    local labels_get
    labels_get=$(metric_labels_format "method=GET")
    local labels_post
    labels_post=$(metric_labels_format "method=POST")

    counter_add "http_requests" 10 "$labels_get"
    counter_add "http_requests" 5 "$labels_post"

    local val_get val_post
    val_get=$(counter_get "http_requests" "$labels_get")
    val_post=$(counter_get "http_requests" "$labels_post")

    [[ "$val_get" == "10" ]]
    [[ "$val_post" == "5" ]]
}

@test "counter_inc auto-registers metric" {
    counter_inc "auto_counter"
    local val
    val=$(counter_get "auto_counter")
    [[ "$val" == "1" ]]
}

# =============================================================================
# GAUGE TESTS
# =============================================================================

@test "gauge_create initializes to zero" {
    gauge_create "test_gauge"
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "0" ]]
}

@test "gauge_set sets value" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 42
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "42" ]]
}

@test "gauge_set handles negative values" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" -10
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "-10" ]]
}

@test "gauge_set handles float values" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 3.14
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "3.14" ]]
}

@test "gauge_inc increments by one" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 10
    gauge_inc "test_gauge"
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "11" ]]
}

@test "gauge_dec decrements by one" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 10
    gauge_dec "test_gauge"
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "9" ]]
}

@test "gauge_add adds value" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 10
    gauge_add "test_gauge" 5
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "15" ]]
}

@test "gauge_add handles negative delta" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 10
    gauge_add "test_gauge" -3
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "7" ]]
}

@test "gauge_sub subtracts value" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 10
    gauge_sub "test_gauge" 3
    local val
    val=$(gauge_get "test_gauge")
    [[ "$val" == "7" ]]
}

@test "gauge_labels creates labeled gauge" {
    gauge_labels "cpu_usage" "cpu" "CPU usage"
    local labels
    labels=$(metric_labels_format "cpu=0")
    gauge_set "cpu_usage" 45.5 "$labels"
    local val
    val=$(gauge_get "cpu_usage" "$labels")
    [[ "$val" == "45.5" ]]
}

@test "gauge with different labels are independent" {
    gauge_create "temperature"
    local labels_room1
    labels_room1=$(metric_labels_format "room=living")
    local labels_room2
    labels_room2=$(metric_labels_format "room=bedroom")

    gauge_set "temperature" 22 "$labels_room1"
    gauge_set "temperature" 18 "$labels_room2"

    local val1 val2
    val1=$(gauge_get "temperature" "$labels_room1")
    val2=$(gauge_get "temperature" "$labels_room2")

    [[ "$val1" == "22" ]]
    [[ "$val2" == "18" ]]
}

@test "gauge_set auto-registers metric" {
    gauge_set "auto_gauge" 100
    local val
    val=$(gauge_get "auto_gauge")
    [[ "$val" == "100" ]]
}

# =============================================================================
# HISTOGRAM TESTS
# =============================================================================

@test "histogram_create with default buckets" {
    histogram_create "request_duration"
    local info
    info=$(metrics_get "request_duration")
    [[ "$info" == *'"type":"histogram"'* ]]
}

@test "histogram_create with custom buckets" {
    histogram_create "request_duration" ".1 .5 1 5"
    local buckets
    buckets=$(histogram_get_buckets "request_duration")
    [[ "$buckets" == *'"0.1"'* ]] || [[ "$buckets" == *'".1"'* ]]
}

@test "histogram_observe updates bucket counts" {
    histogram_create "request_duration" "0.1 0.5 1"
    histogram_observe "request_duration" 0.25

    local buckets
    buckets=$(histogram_get_buckets "request_duration")
    # 0.25 should be in 0.5, 1, and +Inf buckets
    [[ "$buckets" == *'"0.5":1'* ]]
    [[ "$buckets" == *'"1":1'* ]]
    [[ "$buckets" == *'"+Inf":1'* ]]
}

@test "histogram_observe updates sum and count" {
    histogram_create "request_duration"
    histogram_observe "request_duration" 0.5
    histogram_observe "request_duration" 1.5

    local sum count
    sum=$(histogram_get_sum "request_duration")
    count=$(histogram_get_count "request_duration")

    [[ "$sum" == "2" ]]
    [[ "$count" == "2" ]]
}

@test "histogram_get_buckets returns all buckets" {
    histogram_create "test_hist" "1 5 10"
    local buckets
    buckets=$(histogram_get_buckets "test_hist")
    [[ "$buckets" == *'"1":'* ]]
    [[ "$buckets" == *'"5":'* ]]
    [[ "$buckets" == *'"10":'* ]]
    [[ "$buckets" == *'"+Inf":'* ]]
}

@test "histogram with labels" {
    histogram_labels "http_duration" "method" ".1 .5 1" "HTTP request duration"
    local labels
    labels=$(metric_labels_format "method=GET")

    histogram_observe "http_duration" 0.25 "$labels"
    histogram_observe "http_duration" 0.75 "$labels"

    local count
    count=$(histogram_get_count "http_duration" "$labels")
    [[ "$count" == "2" ]]
}

@test "histogram_quantile estimates 50th percentile" {
    histogram_create "latency" "0.1 0.5 1 2 5"

    # Add observations
    for i in $(seq 1 100); do
        local val
        val=$(echo "scale=2; $i / 100" | bc)
        histogram_observe "latency" "$val"
    done

    local p50
    p50=$(histogram_quantile "latency" 0.5)
    # Should be around 0.5
    [[ -n "$p50" ]]
}

@test "histogram auto-registers on observe" {
    histogram_observe "auto_histogram" 1.5
    local count
    count=$(histogram_get_count "auto_histogram")
    [[ "$count" == "1" ]]
}

# =============================================================================
# SUMMARY TESTS
# =============================================================================

@test "summary_create initializes metric" {
    summary_create "request_latency"
    local info
    info=$(metrics_get "request_latency")
    [[ "$info" == *'"type":"summary"'* ]]
}

@test "summary_observe records value" {
    summary_create "request_latency"
    summary_observe "request_latency" 0.5

    local count
    count=$(summary_get_count "request_latency")
    [[ "$count" == "1" ]]
}

@test "summary_get_sum returns total" {
    summary_create "request_latency"
    summary_observe "request_latency" 0.5
    summary_observe "request_latency" 1.5
    summary_observe "request_latency" 2.0

    local sum
    sum=$(summary_get_sum "request_latency")
    [[ "$sum" == "4" ]]
}

@test "summary_get_count returns observation count" {
    summary_create "request_latency"
    summary_observe "request_latency" 0.1
    summary_observe "request_latency" 0.2
    summary_observe "request_latency" 0.3

    local count
    count=$(summary_get_count "request_latency")
    [[ "$count" == "3" ]]
}

@test "summary_get_quantiles returns quantile values" {
    summary_create "request_latency"

    # Add some observations
    for val in 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0; do
        summary_observe "request_latency" "$val"
    done

    local quantiles
    quantiles=$(summary_get_quantiles "request_latency")
    [[ "$quantiles" == *'"0.5":'* ]]
    [[ "$quantiles" == *'"0.9":'* ]]
}

@test "summary auto-registers on observe" {
    summary_observe "auto_summary" 0.5
    local count
    count=$(summary_get_count "auto_summary")
    [[ "$count" == "1" ]]
}

# =============================================================================
# TIMER TESTS
# =============================================================================

@test "timer_start returns timer ID" {
    histogram_create "duration"
    local timer_id
    timer_id=$(timer_start "duration")
    [[ "$timer_id" == timer_* ]]
}

@test "timer_stop records duration" {
    histogram_create "duration"
    local timer_id
    timer_id=$(timer_start "duration")

    # Small sleep to ensure measurable duration
    sleep 0.1

    timer_stop "$timer_id" >/dev/null

    local count
    count=$(histogram_get_count "duration")
    [[ "$count" == "1" ]]
}

@test "timer_stop returns duration" {
    histogram_create "duration"
    local timer_id duration
    timer_id=$(timer_start "duration")
    sleep 0.1
    duration=$(timer_stop "$timer_id")

    # Duration should be positive
    [[ -n "$duration" ]]
}

@test "timer_stop with invalid ID fails" {
    ! timer_stop "invalid_timer_id" 2>/dev/null
}

@test "timer with labels" {
    histogram_create "http_duration"
    local labels
    labels=$(metric_labels_format "method=GET")
    local timer_id
    timer_id=$(timer_start "http_duration" "$labels")
    sleep 0.05
    timer_stop "$timer_id" >/dev/null

    local count
    count=$(histogram_get_count "http_duration" "$labels")
    [[ "$count" == "1" ]]
}

@test "timer_observe records direct duration" {
    histogram_create "operation_time"
    timer_observe "operation_time" 0.5
    timer_observe "operation_time" 1.0

    local count
    count=$(histogram_get_count "operation_time")
    [[ "$count" == "2" ]]
}

# =============================================================================
# EXPORT: PROMETHEUS FORMAT TESTS
# =============================================================================

@test "metrics_export_prometheus includes HELP" {
    counter_create "test_counter" "A test counter"
    counter_inc "test_counter"

    local output
    output=$(metrics_export_prometheus)
    [[ "$output" == *'# HELP test_counter A test counter'* ]]
}

@test "metrics_export_prometheus includes TYPE" {
    counter_create "test_counter"
    local output
    output=$(metrics_export_prometheus)
    [[ "$output" == *'# TYPE test_counter counter'* ]]
}

@test "metrics_export_prometheus exports counter value" {
    counter_create "test_counter"
    counter_add "test_counter" 42
    local output
    output=$(metrics_export_prometheus)
    [[ "$output" == *'test_counter 42'* ]]
}

@test "metrics_export_prometheus exports gauge value" {
    gauge_create "test_gauge"
    gauge_set "test_gauge" 3.14
    local output
    output=$(metrics_export_prometheus)
    [[ "$output" == *'test_gauge 3.14'* ]]
}

@test "metrics_export_prometheus exports histogram buckets" {
    histogram_create "test_hist" "1 5"
    histogram_observe "test_hist" 2

    local output
    output=$(metrics_export_prometheus)
    [[ "$output" == *'test_hist_bucket'* ]]
    [[ "$output" == *'test_hist_sum'* ]]
    [[ "$output" == *'test_hist_count'* ]]
}

@test "metrics_export_prometheus exports labeled metrics" {
    counter_create "http_requests"
    local labels
    labels=$(metric_labels_format "method=GET")
    counter_add "http_requests" 100 "$labels"

    local output
    output=$(metrics_export_prometheus)
    [[ "$output" == *'method="GET"'* ]]
}

# =============================================================================
# EXPORT: JSON FORMAT TESTS
# =============================================================================

@test "metrics_export_json returns valid JSON" {
    counter_create "test_counter"
    counter_inc "test_counter"

    local output
    output=$(metrics_export_json)
    [[ "$output" == '{"metrics":'* ]]
    [[ "$output" == *'"timestamp":'* ]]
}

@test "metrics_export_json includes metric type" {
    counter_create "test_counter"
    local output
    output=$(metrics_export_json)
    [[ "$output" == *'"type":"counter"'* ]]
}

@test "metrics_export_json includes values" {
    counter_create "test_counter"
    counter_add "test_counter" 42

    local output
    output=$(metrics_export_json)
    [[ "$output" == *'"value":42'* ]]
}

@test "metrics_export_json includes histogram buckets" {
    histogram_create "test_hist" "1 5"
    histogram_observe "test_hist" 2

    local output
    output=$(metrics_export_json)
    [[ "$output" == *'"buckets":'* ]]
}

# =============================================================================
# EXPORT: OPENMETRICS FORMAT TESTS
# =============================================================================

@test "metrics_export_openmetrics ends with EOF" {
    counter_create "test_counter"
    local output
    output=$(metrics_export_openmetrics)
    [[ "$output" == *'# EOF'* ]]
}

@test "metrics_export_openmetrics adds _total to counters" {
    counter_create "test_counter"
    counter_inc "test_counter"
    local output
    output=$(metrics_export_openmetrics)
    [[ "$output" == *'test_counter_total'* ]]
}

# =============================================================================
# TIMESTAMP TESTS
# =============================================================================

@test "metric_timestamp returns milliseconds" {
    local ts
    ts=$(metric_timestamp)
    # Should be at least 13 digits (milliseconds since epoch)
    [[ ${#ts} -ge 13 ]]
}

# =============================================================================
# DISABLED METRICS TESTS
# =============================================================================

@test "metrics disabled skips all operations" {
    export MAINFRAME_METRICS_ENABLED=0

    counter_create "test_counter"
    counter_inc "test_counter"
    gauge_set "test_gauge" 100
    histogram_observe "test_hist" 1.0

    # Should all succeed silently
    local val
    val=$(counter_get "test_counter")
    [[ "$val" == "0" ]]

    export MAINFRAME_METRICS_ENABLED=1
}

# =============================================================================
# METRICS MEASURE FUNCTION
# =============================================================================

@test "metrics_measure records function duration" {
    histogram_create "function_duration"

    _test_function() {
        sleep 0.05
        return 0
    }

    metrics_measure "function_duration" _test_function

    local count
    count=$(histogram_get_count "function_duration")
    [[ "$count" == "1" ]]
}

@test "metrics_measure preserves function return code" {
    histogram_create "function_duration"

    _failing_function() {
        return 42
    }

    local rc=0
    metrics_measure "function_duration" _failing_function || rc=$?
    [[ "$rc" == "42" ]]
}

# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================

@test "counter_inc on gauge fails" {
    gauge_create "test_gauge"
    ! counter_inc "test_gauge" 2>/dev/null
}

@test "gauge_set on counter fails" {
    counter_create "test_counter"
    ! gauge_set "test_counter" 100 2>/dev/null
}

@test "histogram_observe on counter fails" {
    counter_create "test_counter"
    ! histogram_observe "test_counter" 1.0 2>/dev/null
}

@test "counter handles large values" {
    counter_create "big_counter"
    counter_add "big_counter" 1000000
    counter_add "big_counter" 1000000

    local val
    val=$(counter_get "big_counter")
    [[ "$val" == "2000000" ]]
}

@test "gauge handles very small float" {
    gauge_create "small_gauge"
    gauge_set "small_gauge" 0.000001

    local val
    val=$(gauge_get "small_gauge")
    [[ "$val" == "0.000001" ]]
}

# =============================================================================
# CONCURRENT ACCESS (basic test)
# =============================================================================

@test "counter handles rapid increments" {
    counter_create "rapid_counter"

    for i in $(seq 1 100); do
        counter_inc "rapid_counter"
    done

    local val
    val=$(counter_get "rapid_counter")
    [[ "$val" == "100" ]]
}

@test "histogram handles many observations" {
    histogram_create "many_obs" "1 5 10"

    for i in $(seq 1 50); do
        histogram_observe "many_obs" "$i"
    done

    local count
    count=$(histogram_get_count "many_obs")
    [[ "$count" == "50" ]]
}


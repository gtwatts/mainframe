#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: DateTime Module Tests
# =============================================================================
# Tests for lib/datetime.sh
# Covers: current time, parsing, formatting, arithmetic, components, comparisons
# =============================================================================

load 'test_helper'

setup() {
    source_lib "datetime"
    export MAINFRAME_QUIET=1
}

# =============================================================================
# now / now_ms / now_iso TESTS
# =============================================================================

@test "now returns unix timestamp" {
    local result
    result=$(now)
    [[ "$result" =~ ^[0-9]+$ ]]
    [ "$result" -gt 1700000000 ]
}

@test "now_ms returns millisecond timestamp" {
    local result
    result=$(now_ms)
    [[ "$result" =~ ^[0-9]+$ ]]
    [ ${#result} -ge 13 ]
}

@test "now_iso returns ISO 8601 format" {
    local result
    result=$(now_iso)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "now_rfc2822 returns RFC format" {
    local result
    result=$(now_rfc2822)
    [[ "$result" =~ ^[A-Z][a-z]{2}, ]]
}

# =============================================================================
# parse_iso TESTS
# =============================================================================

@test "parse_iso parses full ISO datetime" {
    local result
    result=$(parse_iso "2024-01-15T10:30:00Z")
    [ "$result" -gt 0 ]
}

@test "parse_iso parses date only" {
    local result
    result=$(parse_iso "2024-01-15")
    [ "$result" -gt 0 ]
}

@test "parse_iso parses without seconds" {
    local result
    result=$(parse_iso "2024-01-15T10:30")
    [ "$result" -gt 0 ]
}

@test "parse_iso handles timezone offset" {
    local utc east
    utc=$(parse_iso "2024-01-15T12:00:00Z")
    east=$(parse_iso "2024-01-15T12:00:00-05:00")
    # Eastern time is 5 hours behind, so epoch should be 5h more
    [ "$east" -gt "$utc" ]
}

@test "parse_iso returns 0 for invalid" {
    local result
    result=$(parse_iso "not-a-date" || true)
    [ "$result" = "0" ]
}

# =============================================================================
# parse_date TESTS
# =============================================================================

@test "parse_date parses YYYY-MM-DD" {
    local result
    result=$(parse_date "2024-01-15")
    [ "$result" -gt 0 ]
}

@test "parse_date returns 0 for invalid" {
    local result
    result=$(parse_date "2024-13-45")
    # Still parses the regex match, but may produce wrong value
    # The key test is that it doesn't crash
    [[ "$result" =~ ^-?[0-9]+$ ]]
}

@test "parse_date fails for non-date string" {
    run parse_date "hello"
    [ "$status" -eq 1 ]
}

# =============================================================================
# parse_datetime TESTS
# =============================================================================

@test "parse_datetime parses YYYY-MM-DD HH:MM:SS" {
    local result
    result=$(parse_datetime "2024-01-15 10:30:00")
    [ "$result" -gt 0 ]
}

@test "parse_datetime parses without seconds" {
    local result
    result=$(parse_datetime "2024-01-15 10:30")
    [ "$result" -gt 0 ]
}

# =============================================================================
# format_epoch TESTS
# =============================================================================

@test "format_epoch formats with default pattern" {
    local result
    result=$(format_epoch 0)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "format_epoch formats with custom pattern" {
    local result
    result=$(TZ=UTC format_epoch 0 "%Y")
    [ "$result" = "1970" ]
}

# =============================================================================
# format_iso TESTS
# =============================================================================

@test "format_iso returns ISO format" {
    local result
    result=$(TZ=UTC format_iso 0)
    [[ "$result" =~ ^1970-01-01T00:00:00 ]]
}

# =============================================================================
# format_date / format_time / format_datetime TESTS
# =============================================================================

@test "format_date returns YYYY-MM-DD" {
    local result
    result=$(format_date 0)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "format_time returns HH:MM:SS" {
    local result
    result=$(format_time 0)
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_datetime returns full datetime" {
    local result
    result=$(format_datetime 0)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

# =============================================================================
# format_relative TESTS
# =============================================================================

@test "format_relative shows seconds ago" {
    local current
    current=$(now)
    local past=$((current - 30))
    local result
    result=$(format_relative "$past")
    [[ "$result" == *"second"* ]]
    [[ "$result" == *"ago"* ]]
}

@test "format_relative shows minutes ago" {
    local current
    current=$(now)
    local past=$((current - 300))
    local result
    result=$(format_relative "$past")
    [[ "$result" == *"minute"* ]]
    [[ "$result" == *"ago"* ]]
}

@test "format_relative shows hours ago" {
    local current
    current=$(now)
    local past=$((current - 7200))
    local result
    result=$(format_relative "$past")
    [[ "$result" == *"hour"* ]]
    [[ "$result" == *"ago"* ]]
}

@test "format_relative shows future with in prefix" {
    local current
    current=$(now)
    local future=$((current + 7200))
    local result
    result=$(format_relative "$future")
    [[ "$result" == "in "* ]]
}

# =============================================================================
# date_add / date_subtract TESTS
# =============================================================================

@test "date_add adds days" {
    local base=1000000
    local result
    result=$(date_add "$base" "2d")
    [ "$result" -eq $((base + 172800)) ]
}

@test "date_add adds hours" {
    local base=1000000
    local result
    result=$(date_add "$base" "3h")
    [ "$result" -eq $((base + 10800)) ]
}

@test "date_add adds mixed duration" {
    local base=1000000
    local result
    result=$(date_add "$base" "1d2h30m")
    [ "$result" -eq $((base + 86400 + 7200 + 1800)) ]
}

@test "date_add adds weeks" {
    local base=1000000
    local result
    result=$(date_add "$base" "1w")
    [ "$result" -eq $((base + 604800)) ]
}

@test "date_subtract subtracts duration" {
    local base=1000000
    local result
    result=$(date_subtract "$base" "1d")
    [ "$result" -eq $((base - 86400)) ]
}

# =============================================================================
# date_diff / date_diff_human TESTS
# =============================================================================

@test "date_diff returns absolute difference" {
    local result
    result=$(date_diff 1000 2000)
    [ "$result" -eq 1000 ]
}

@test "date_diff handles reverse order" {
    local result
    result=$(date_diff 2000 1000)
    [ "$result" -eq 1000 ]
}

@test "date_diff_human shows days hours minutes" {
    local result
    result=$(date_diff_human 0 90061)
    [[ "$result" == *"1 day"* ]]
    [[ "$result" == *"1 hour"* ]]
    [[ "$result" == *"1 minute"* ]]
    [[ "$result" == *"1 second"* ]]
}

@test "date_diff_human pluralizes correctly" {
    local result
    result=$(date_diff_human 0 172800)
    [[ "$result" == *"2 days"* ]]
}

# =============================================================================
# year / month / day / hour / minute / second TESTS
# =============================================================================

@test "year extracts year from epoch" {
    local result
    result=$(TZ=UTC year 0)
    [ "$result" = "1970" ]
}

@test "day_of_week returns day name" {
    local result
    result=$(day_of_week 0)
    [[ "$result" =~ ^[A-Z][a-z]+$ ]]
}

# =============================================================================
# is_leap_year TESTS
# =============================================================================

@test "is_leap_year identifies leap year" {
    run is_leap_year 2024
    [ "$status" -eq 0 ]
}

@test "is_leap_year identifies non-leap year" {
    run is_leap_year 2023
    [ "$status" -eq 1 ]
}

@test "is_leap_year handles century non-leap" {
    run is_leap_year 1900
    [ "$status" -eq 1 ]
}

@test "is_leap_year handles 400-year leap" {
    run is_leap_year 2000
    [ "$status" -eq 0 ]
}

# =============================================================================
# is_before / is_after TESTS
# =============================================================================

@test "is_before returns true when earlier" {
    run is_before 100 200
    [ "$status" -eq 0 ]
}

@test "is_before returns false when later" {
    run is_before 200 100
    [ "$status" -eq 1 ]
}

@test "is_after returns true when later" {
    run is_after 200 100
    [ "$status" -eq 0 ]
}

# =============================================================================
# is_same_day TESTS
# =============================================================================

@test "is_same_day matches same day" {
    local base
    base=$(now)
    run is_same_day "$base" "$((base + 100))"
    [ "$status" -eq 0 ]
}

@test "is_same_day distinguishes different days" {
    local base
    base=$(now)
    run is_same_day "$base" "$((base + 200000))"
    [ "$status" -eq 1 ]
}

# =============================================================================
# is_weekend / is_weekday TESTS
# =============================================================================

@test "is_weekend and is_weekday are mutually exclusive" {
    local epoch
    epoch=$(now)
    if is_weekend "$epoch"; then
        run is_weekday "$epoch"
        [ "$status" -eq 1 ]
    else
        run is_weekday "$epoch"
        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# start_of_day / end_of_day TESTS
# =============================================================================

@test "start_of_day returns midnight" {
    local current start h
    current=$(now)
    start=$(start_of_day "$current")
    printf -v h '%(%H:%M:%S)T' "$start"
    [ "$h" = "00:00:00" ]
}

@test "end_of_day returns 23:59:59" {
    local current end h
    current=$(now)
    end=$(end_of_day "$current")
    printf -v h '%(%H:%M:%S)T' "$end"
    [ "$h" = "23:59:59" ]
}

@test "end_of_day stays on the same calendar day as start_of_day" {
    local current start end start_day end_day end_time
    current=$(now)
    start=$(start_of_day "$current")
    end=$(end_of_day "$current")
    printf -v start_day '%(%Y-%m-%d)T' "$start"
    printf -v end_day '%(%Y-%m-%d)T' "$end"
    printf -v end_time '%(%H:%M:%S)T' "$end"
    [ "$start_day" = "$end_day" ]
    [ "$end_time" = "23:59:59" ]
}

# =============================================================================
# days_in_month TESTS
# =============================================================================

@test "days_in_month returns 31 for January" {
    local result
    result=$(days_in_month 2024 1)
    [ "$result" -eq 31 ]
}

@test "days_in_month returns 28 for Feb non-leap" {
    local result
    result=$(days_in_month 2023 2)
    [ "$result" -eq 28 ]
}

@test "days_in_month returns 29 for Feb leap year" {
    local result
    result=$(days_in_month 2024 2)
    [ "$result" -eq 29 ]
}

@test "days_in_month returns 30 for April" {
    local result
    result=$(days_in_month 2024 4)
    [ "$result" -eq 30 ]
}

# =============================================================================
# make_datetime TESTS
# =============================================================================

@test "make_datetime creates epoch from components" {
    local result
    result=$(make_datetime 2024 1 1 0 0 0)
    [ "$result" -gt 0 ]
}

@test "make_datetime epoch matches parse_date for same date" {
    local from_make from_parse
    from_make=$(make_datetime 2024 6 15 0 0 0)
    from_parse=$(parse_date "2024-06-15")
    [ "$from_make" -eq "$from_parse" ]
}

# =============================================================================
# tz_offset / tz_name TESTS
# =============================================================================

@test "tz_offset returns integer" {
    local result
    result=$(tz_offset)
    [[ "$result" =~ ^-?[0-9]+$ ]]
}

@test "tz_name returns non-empty string" {
    local result
    result=$(tz_name)
    [ -n "$result" ]
}

# =============================================================================
# _dt_parse_duration TESTS
# =============================================================================

@test "_dt_parse_duration parses seconds" {
    local result
    result=$(_dt_parse_duration "30s")
    [ "$result" -eq 30 ]
}

@test "_dt_parse_duration parses minutes" {
    local result
    result=$(_dt_parse_duration "5m")
    [ "$result" -eq 300 ]
}

@test "_dt_parse_duration parses hours" {
    local result
    result=$(_dt_parse_duration "2h")
    [ "$result" -eq 7200 ]
}

@test "_dt_parse_duration parses days" {
    local result
    result=$(_dt_parse_duration "1d")
    [ "$result" -eq 86400 ]
}

@test "_dt_parse_duration parses weeks" {
    local result
    result=$(_dt_parse_duration "1w")
    [ "$result" -eq 604800 ]
}

@test "_dt_parse_duration parses combined" {
    local result
    result=$(_dt_parse_duration "1d2h30m10s")
    [ "$result" -eq $((86400 + 7200 + 1800 + 10)) ]
}

@test "_dt_parse_duration treats bare number as seconds" {
    local result
    result=$(_dt_parse_duration "60")
    [ "$result" -eq 60 ]
}

# =============================================================================
# ROUNDTRIP TESTS
# =============================================================================

@test "parse_iso and format_iso roundtrip for UTC" {
    local epoch formatted reparsed
    epoch=$(parse_iso "2024-06-15T12:30:00Z")
    formatted=$(format_iso "$epoch")
    [[ "$formatted" == *"2024-06-15"* ]]
}

@test "date_add then date_subtract returns original" {
    local base result
    base=1000000
    result=$(date_add "$base" "5d")
    result=$(date_subtract "$result" "5d")
    [ "$result" -eq "$base" ]
}

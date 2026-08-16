#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/datetime.bats - DateTime Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/datetime.sh
#              Pure bash date/time operations without external tools
# Test Count: 70+ test cases
# Categories: current time, parsing, formatting, arithmetic, components,
#             comparisons, boundaries, utilities
# Requires: Bash 4.2+ (for printf '%()T' format)
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library
    source "$MAINFRAME_ROOT/lib/datetime.sh"

    # Known epoch for testing: 2024-01-15 10:30:00 UTC
    # This equals 1705315800 (verified externally)
    TEST_EPOCH=1705315800
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: CURRENT TIME FUNCTIONS
# =============================================================================

@test "now: returns current Unix timestamp" {
    result=$(now)
    # Should be a number greater than year 2020 epoch
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 1577836800 ]]  # Jan 1, 2020
}

@test "now_ms: returns timestamp with milliseconds" {
    result=$(now_ms)
    # Should be a number ending in 000 (approximation)
    [[ "$result" =~ ^[0-9]+000$ ]]
}

@test "now_iso: returns ISO 8601 format" {
    result=$(now_iso)
    # Should match ISO format pattern
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "now_rfc2822: returns RFC 2822 format" {
    result=$(now_rfc2822)
    # Should contain day name and month abbreviation
    [[ "$result" =~ ^[A-Z][a-z]{2}, ]]
}

# =============================================================================
# CATEGORY 2: PARSING
# =============================================================================

@test "parse_iso: parses basic ISO date with time" {
    result=$(parse_iso "2024-01-15T10:30:00Z")
    # Should return a valid epoch (non-zero)
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "parse_iso: parses ISO date without seconds" {
    result=$(parse_iso "2024-01-15T10:30")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "parse_iso: parses date-only ISO format" {
    result=$(parse_iso "2024-01-15")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "parse_iso: handles positive timezone offset" {
    result=$(parse_iso "2024-01-15T10:30:00+05:00")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "parse_iso: handles negative timezone offset" {
    result=$(parse_iso "2024-01-15T10:30:00-08:00")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "parse_iso: returns 0 for invalid format" {
    run parse_iso "not-a-date"
    [[ "$output" == "0" ]]
    [[ "$status" -eq 1 ]]
}

@test "parse_date: parses YYYY-MM-DD format" {
    result=$(parse_date "2024-01-15")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "parse_date: returns 0 for invalid format" {
    run parse_date "01-15-2024"
    [[ "$output" == "0" ]]
    [[ "$status" -eq 1 ]]
}

@test "parse_datetime: parses YYYY-MM-DD HH:MM:SS format" {
    result=$(parse_datetime "2024-01-15 10:30:00")
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ "$result" -gt 0 ]]
}

@test "parse_datetime: parses without seconds" {
    result=$(parse_datetime "2024-01-15 10:30")
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "parse_datetime: returns 0 for invalid format" {
    run parse_datetime "invalid"
    [[ "$output" == "0" ]]
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 3: FORMATTING
# =============================================================================

@test "format_epoch: formats with default pattern" {
    result=$(format_epoch "$TEST_EPOCH")
    # Should return date/time string
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "format_epoch: formats with custom pattern" {
    result=$(format_epoch "$TEST_EPOCH" "%Y/%m/%d")
    [[ "$result" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]]
}

@test "format_epoch: uses current time when epoch is -1" {
    result=$(format_epoch -1)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "format_iso: returns ISO 8601 format" {
    result=$(format_iso "$TEST_EPOCH")
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "format_date: returns YYYY-MM-DD format" {
    result=$(format_date "$TEST_EPOCH")
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "format_date: accepts historical strftime format shape" {
    result=$(format_date "%Y")
    [[ "$result" =~ ^[0-9]{4}$ ]]
}

@test "format_current_date: uses requested strftime format" {
    result=$(format_current_date "%Y-%m")
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}$ ]]
}

@test "format_time: returns HH:MM:SS format" {
    result=$(format_time "$TEST_EPOCH")
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_datetime: returns YYYY-MM-DD HH:MM:SS format" {
    result=$(format_datetime "$TEST_EPOCH")
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_relative: returns 'just now' for current time" {
    current=$(now)
    result=$(format_relative "$current")
    [[ "$result" == "just now" ]]
}

@test "format_relative: returns 'X seconds ago' for recent past" {
    current=$(now)
    past=$((current - 30))
    result=$(format_relative "$past")
    [[ "$result" =~ "second" ]]
    [[ "$result" =~ "ago" ]]
}

@test "format_relative: returns 'X minutes ago'" {
    current=$(now)
    past=$((current - 300))  # 5 minutes
    result=$(format_relative "$past")
    [[ "$result" =~ "minute" ]]
    [[ "$result" =~ "ago" ]]
}

@test "format_relative: returns 'X hours ago'" {
    current=$(now)
    past=$((current - 7200))  # 2 hours
    result=$(format_relative "$past")
    [[ "$result" =~ "hour" ]]
    [[ "$result" =~ "ago" ]]
}

@test "format_relative: returns 'X days ago'" {
    current=$(now)
    past=$((current - 172800))  # 2 days
    result=$(format_relative "$past")
    [[ "$result" =~ "day" ]]
    [[ "$result" =~ "ago" ]]
}

@test "format_relative: returns 'in X' for future times" {
    current=$(now)
    future=$((current + 3600))  # 1 hour ahead
    result=$(format_relative "$future")
    [[ "$result" =~ ^in\  ]]
}

# =============================================================================
# CATEGORY 4: ARITHMETIC
# =============================================================================

@test "date_add: adds seconds" {
    result=$(date_add "$TEST_EPOCH" "30s")
    expected=$((TEST_EPOCH + 30))
    [[ "$result" -eq "$expected" ]]
}

@test "date_add: adds minutes" {
    result=$(date_add "$TEST_EPOCH" "5m")
    expected=$((TEST_EPOCH + 300))
    [[ "$result" -eq "$expected" ]]
}

@test "date_add: adds hours" {
    result=$(date_add "$TEST_EPOCH" "2h")
    expected=$((TEST_EPOCH + 7200))
    [[ "$result" -eq "$expected" ]]
}

@test "date_add: adds days" {
    result=$(date_add "$TEST_EPOCH" "3d")
    expected=$((TEST_EPOCH + 259200))
    [[ "$result" -eq "$expected" ]]
}

@test "date_add: adds weeks" {
    result=$(date_add "$TEST_EPOCH" "1w")
    expected=$((TEST_EPOCH + 604800))
    [[ "$result" -eq "$expected" ]]
}

@test "date_add: adds combined duration" {
    result=$(date_add "$TEST_EPOCH" "1d2h30m")
    expected=$((TEST_EPOCH + 86400 + 7200 + 1800))
    [[ "$result" -eq "$expected" ]]
}

@test "date_add: uses current time when epoch is -1" {
    current=$(now)
    result=$(date_add -1 "1h")
    expected=$((current + 3600))
    # Allow 2 second tolerance for execution time
    [[ "$result" -ge "$((expected - 2))" ]]
    [[ "$result" -le "$((expected + 2))" ]]
}

@test "date_subtract: subtracts duration" {
    result=$(date_subtract "$TEST_EPOCH" "1h")
    expected=$((TEST_EPOCH - 3600))
    [[ "$result" -eq "$expected" ]]
}

@test "date_subtract: subtracts combined duration" {
    result=$(date_subtract "$TEST_EPOCH" "1d6h")
    expected=$((TEST_EPOCH - 86400 - 21600))
    [[ "$result" -eq "$expected" ]]
}

@test "date_diff: returns absolute difference in seconds" {
    epoch1=1705315800
    epoch2=1705319400  # 1 hour later
    result=$(date_diff "$epoch1" "$epoch2")
    [[ "$result" -eq 3600 ]]
}

@test "date_diff: returns absolute value regardless of order" {
    epoch1=1705319400
    epoch2=1705315800  # 1 hour earlier
    result=$(date_diff "$epoch1" "$epoch2")
    [[ "$result" -eq 3600 ]]
}

@test "date_diff_human: returns human-readable difference" {
    epoch1=1705315800
    epoch2=$((epoch1 + 3661))  # 1 hour, 1 minute, 1 second
    result=$(date_diff_human "$epoch1" "$epoch2")
    [[ "$result" =~ "1 hour" ]]
    [[ "$result" =~ "1 minute" ]]
    [[ "$result" =~ "1 second" ]]
}

@test "date_diff_human: pluralizes correctly" {
    epoch1=1705315800
    epoch2=$((epoch1 + 7322))  # 2 hours, 2 minutes, 2 seconds
    result=$(date_diff_human "$epoch1" "$epoch2")
    [[ "$result" =~ "2 hours" ]]
    [[ "$result" =~ "2 minutes" ]]
    [[ "$result" =~ "2 seconds" ]]
}

# =============================================================================
# CATEGORY 5: COMPONENTS
# =============================================================================

@test "year: extracts year from epoch" {
    result=$(year "$TEST_EPOCH")
    [[ "$result" == "2024" ]]
}

@test "month: extracts month from epoch (1-12)" {
    result=$(month "$TEST_EPOCH")
    [[ "$result" == "1" ]]
}

@test "day: extracts day from epoch (1-31)" {
    result=$(day "$TEST_EPOCH")
    [[ "$result" -ge 1 && "$result" -le 31 ]]
}

@test "hour: extracts hour from epoch (0-23)" {
    result=$(hour "$TEST_EPOCH")
    [[ "$result" -ge 0 && "$result" -le 23 ]]
}

@test "minute: extracts minute from epoch (0-59)" {
    result=$(minute "$TEST_EPOCH")
    [[ "$result" -ge 0 && "$result" -le 59 ]]
}

@test "second: extracts second from epoch (0-59)" {
    result=$(second "$TEST_EPOCH")
    [[ "$result" -ge 0 && "$result" -le 59 ]]
}

@test "day_of_week: returns day name" {
    result=$(day_of_week "$TEST_EPOCH")
    # Should be a day name
    [[ "$result" =~ ^(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday)$ ]]
}

@test "day_of_year: returns 1-366" {
    result=$(day_of_year "$TEST_EPOCH")
    [[ "$result" -ge 1 && "$result" -le 366 ]]
}

@test "week_of_year: returns 1-53" {
    result=$(week_of_year "$TEST_EPOCH")
    [[ "$result" -ge 1 && "$result" -le 53 ]]
}

@test "is_leap_year: returns true for 2024" {
    is_leap_year 2024
    [[ $? -eq 0 ]]
}

@test "is_leap_year: returns false for 2023" {
    run is_leap_year 2023
    [[ "$status" -eq 1 ]]
}

@test "is_leap_year: returns true for century divisible by 400" {
    is_leap_year 2000
    [[ $? -eq 0 ]]
}

@test "is_leap_year: returns false for century not divisible by 400" {
    run is_leap_year 1900
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 6: COMPARISONS
# =============================================================================

@test "is_before: returns true when first is earlier" {
    is_before 1705315800 1705319400
    [[ $? -eq 0 ]]
}

@test "is_before: returns false when first is later" {
    run is_before 1705319400 1705315800
    [[ "$status" -eq 1 ]]
}

@test "is_after: returns true when first is later" {
    is_after 1705319400 1705315800
    [[ $? -eq 0 ]]
}

@test "is_after: returns false when first is earlier" {
    run is_after 1705315800 1705319400
    [[ "$status" -eq 1 ]]
}

@test "is_same_day: returns true for same calendar day" {
    # Same day, different times
    epoch1=$(parse_datetime "2024-01-15 08:00:00")
    epoch2=$(parse_datetime "2024-01-15 20:00:00")
    is_same_day "$epoch1" "$epoch2"
    [[ $? -eq 0 ]]
}

@test "is_same_day: returns false for different days" {
    epoch1=$(parse_datetime "2024-01-15 08:00:00")
    epoch2=$(parse_datetime "2024-01-16 08:00:00")
    run is_same_day "$epoch1" "$epoch2"
    [[ "$status" -eq 1 ]]
}

@test "is_weekend: returns true for Saturday" {
    # Find a known Saturday (2024-01-13 is Saturday)
    saturday=$(parse_date "2024-01-13")
    is_weekend "$saturday"
    [[ $? -eq 0 ]]
}

@test "is_weekend: returns true for Sunday" {
    # 2024-01-14 is Sunday
    sunday=$(parse_date "2024-01-14")
    is_weekend "$sunday"
    [[ $? -eq 0 ]]
}

@test "is_weekday: returns true for Monday-Friday" {
    # 2024-01-15 is Monday
    monday=$(parse_date "2024-01-15")
    is_weekday "$monday"
    [[ $? -eq 0 ]]
}

@test "is_weekday: returns false for weekend" {
    saturday=$(parse_date "2024-01-13")
    run is_weekday "$saturday"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 7: BOUNDARIES
# =============================================================================

@test "start_of_day: returns midnight" {
    result=$(start_of_day "$TEST_EPOCH")
    h=$(hour "$result")
    m=$(minute "$result")
    s=$(second "$result")
    [[ "$h" -eq 0 && "$m" -eq 0 && "$s" -eq 0 ]]
}

@test "end_of_day: returns 23:59:59" {
    result=$(end_of_day "$TEST_EPOCH")
    h=$(hour "$result")
    m=$(minute "$result")
    s=$(second "$result")
    [[ "$h" -eq 23 && "$m" -eq 59 && "$s" -eq 59 ]]
}

@test "start_of_day: handles DST transition day in local time" {
    (
        export TZ=America/New_York
        local epoch result rendered
        epoch=$(parse_datetime "2026-03-08 13:30:00")
        result=$(start_of_day "$epoch")
        printf -v rendered '%(%Y-%m-%d %H:%M:%S %z)T' "$result"
        [[ "$rendered" == "2026-03-08 00:00:00 -0500" ]]
    )
}

@test "end_of_day: handles DST transition day in local time" {
    (
        export TZ=America/New_York
        local epoch result rendered
        epoch=$(parse_datetime "2026-03-08 13:30:00")
        result=$(end_of_day "$epoch")
        printf -v rendered '%(%Y-%m-%d %H:%M:%S %z)T' "$result"
        [[ "$rendered" == "2026-03-08 23:59:59 -0400" ]]
    )
}

@test "start_of_month: returns first day of month" {
    result=$(start_of_month "$TEST_EPOCH")
    d=$(day "$result")
    [[ "$d" -eq 1 ]]
}

@test "end_of_month: returns last day of month" {
    # January has 31 days
    result=$(end_of_month "$TEST_EPOCH")
    d=$(day "$result")
    [[ "$d" -eq 31 ]]
}

@test "start_of_year: returns January 1st" {
    result=$(start_of_year "$TEST_EPOCH")
    m=$(month "$result")
    d=$(day "$result")
    [[ "$m" -eq 1 && "$d" -eq 1 ]]
}

@test "end_of_year: returns December 31st" {
    result=$(end_of_year "$TEST_EPOCH")
    m=$(month "$result")
    d=$(day "$result")
    [[ "$m" -eq 12 && "$d" -eq 31 ]]
}

# =============================================================================
# CATEGORY 8: UTILITIES
# =============================================================================

@test "days_in_month: returns 31 for January" {
    result=$(days_in_month 2024 1)
    [[ "$result" -eq 31 ]]
}

@test "days_in_month: returns 28 for February non-leap" {
    result=$(days_in_month 2023 2)
    [[ "$result" -eq 28 ]]
}

@test "days_in_month: returns 29 for February leap year" {
    result=$(days_in_month 2024 2)
    [[ "$result" -eq 29 ]]
}

@test "days_in_month: returns 30 for April" {
    result=$(days_in_month 2024 4)
    [[ "$result" -eq 30 ]]
}

@test "make_datetime: creates epoch from components" {
    result=$(make_datetime 2024 1 15 10 30 0)
    [[ "$result" -gt 0 ]]
    y=$(year "$result")
    m=$(month "$result")
    d=$(day "$result")
    [[ "$y" -eq 2024 && "$m" -eq 1 && "$d" -eq 15 ]]
}

@test "make_datetime: defaults time components to 0" {
    result=$(make_datetime 2024 6 15)
    h=$(hour "$result")
    [[ "$h" -eq 0 ]]
}

@test "tz_offset: returns offset in seconds" {
    result=$(tz_offset)
    [[ "$result" =~ ^-?[0-9]+$ ]]
}

@test "tz_name: returns timezone name" {
    result=$(tz_name)
    [[ -n "$result" ]]
    # Should be letters, possibly with numbers
    [[ "$result" =~ ^[A-Z]+ ]]
}

# =============================================================================
# CATEGORY 9: EDGE CASES
# =============================================================================

@test "parse_iso: handles dates before 1970" {
    # Some implementations may not support this
    result=$(parse_iso "1969-12-31T23:59:59Z")
    # Should return a negative number or handle gracefully
    [[ "$result" =~ ^-?[0-9]+$ ]]
}

@test "date_add: handles zero duration" {
    result=$(date_add "$TEST_EPOCH" "0s")
    [[ "$result" -eq "$TEST_EPOCH" ]]
}

@test "date_add: handles plain number as seconds" {
    result=$(date_add "$TEST_EPOCH" "100")
    expected=$((TEST_EPOCH + 100))
    [[ "$result" -eq "$expected" ]]
}

@test "format_relative: handles very old dates" {
    # 10 years ago
    current=$(now)
    old=$((current - 315360000))  # ~10 years
    result=$(format_relative "$old")
    [[ "$result" =~ "year" ]]
}

@test "is_same_day: handles epoch 0" {
    is_same_day 0 0
    [[ $? -eq 0 ]]
}

@test "year: handles current time with -1" {
    result=$(year -1)
    current_year=$(printf '%(%Y)T\n' -1)
    [[ "$result" == "$current_year" ]]
}

@test "date_diff: handles zero difference" {
    result=$(date_diff "$TEST_EPOCH" "$TEST_EPOCH")
    [[ "$result" -eq 0 ]]
}

@test "date_diff_human: handles zero difference" {
    result=$(date_diff_human "$TEST_EPOCH" "$TEST_EPOCH")
    [[ "$result" =~ "0 second" ]]
}

# =============================================================================
# CATEGORY 10: INTERNAL FUNCTIONS (WHITE BOX TESTING)
# =============================================================================

@test "_dt_parse_duration: parses seconds" {
    result=$(_dt_parse_duration "45s")
    [[ "$result" -eq 45 ]]
}

@test "_dt_parse_duration: parses minutes" {
    result=$(_dt_parse_duration "10m")
    [[ "$result" -eq 600 ]]
}

@test "_dt_parse_duration: parses hours" {
    result=$(_dt_parse_duration "2h")
    [[ "$result" -eq 7200 ]]
}

@test "_dt_parse_duration: parses days" {
    result=$(_dt_parse_duration "1d")
    [[ "$result" -eq 86400 ]]
}

@test "_dt_parse_duration: parses weeks" {
    result=$(_dt_parse_duration "1w")
    [[ "$result" -eq 604800 ]]
}

@test "_dt_parse_duration: parses combined" {
    result=$(_dt_parse_duration "1w2d3h4m5s")
    expected=$((604800 + 172800 + 10800 + 240 + 5))
    [[ "$result" -eq "$expected" ]]
}

@test "_dt_parse_duration: handles uppercase" {
    result=$(_dt_parse_duration "1H30M")
    expected=$((3600 + 1800))
    [[ "$result" -eq "$expected" ]]
}

@test "_dt_is_leap_year: correctly identifies leap years" {
    _dt_is_leap_year 2000 && [[ $? -eq 0 ]]
    _dt_is_leap_year 2004 && [[ $? -eq 0 ]]
    _dt_is_leap_year 2024 && [[ $? -eq 0 ]]
}

@test "_dt_is_leap_year: correctly rejects non-leap years" {
    run _dt_is_leap_year 2100
    [[ "$status" -eq 1 ]]
    run _dt_is_leap_year 2023
    [[ "$status" -eq 1 ]]
}

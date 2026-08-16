#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Pure Utility Focused Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "pure-util"
}

@test "format_date formats an epoch as YYYY-MM-DD" {
    local result
    result=$(TZ=UTC format_date 0)
    [[ "$result" == "1970-01-01" ]]
}

@test "format_date preserves historical strftime call shape" {
    local result
    result=$(format_date "%Y")
    [[ "$result" =~ ^[0-9]{4}$ ]]
}

@test "format_date supports literal text around strftime directives" {
    local result
    result=$(format_date "year=%Y")
    [[ "$result" =~ ^year=[0-9]{4}$ ]]
}

@test "format_current_date defaults to YYYY-MM-DD" {
    local result
    result=$(format_current_date)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

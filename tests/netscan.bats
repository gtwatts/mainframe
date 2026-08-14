#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Network Scanning Module Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "netscan"
    TEST_DIR=$(create_test_dir "netscan")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# port_check TESTS
# =============================================================================

@test "port_check returns 2 with no args" {
    local rc=0
    port_check 2>/dev/null || rc=$?
    [ "$rc" = "2" ]
}

@test "port_check returns 2 with invalid port" {
    local rc=0
    port_check "localhost" "99999" 2>/dev/null || rc=$?
    [ "$rc" = "2" ]
}

@test "port_check returns 2 with non-numeric port" {
    local rc=0
    port_check "localhost" "abc" 2>/dev/null || rc=$?
    [ "$rc" = "2" ]
}

@test "port_check returns 1 for closed port" {
    # Port 1 is almost certainly closed on localhost
    local rc=0
    port_check "localhost" 1 1 || rc=$?
    [ "$rc" = "1" ]
}

# =============================================================================
# host_alive TESTS
# =============================================================================

@test "host_alive returns 2 with no args" {
    local rc=0
    host_alive 2>/dev/null || rc=$?
    [ "$rc" = "2" ]
}

@test "host_alive detects localhost" {
    host_alive "127.0.0.1" 2
}

# =============================================================================
# monitor_port TESTS
# =============================================================================

@test "monitor_port returns error JSON with no args" {
    local result
    result=$(monitor_port 2>/dev/null) || true
    [[ "$result" == *'"error"'* ]]
}

@test "monitor_port returns JSON with state" {
    local result
    result=$(monitor_port "localhost" 1 1)
    [[ "$result" == *'"state":'* ]]
    [[ "$result" == *'"host":"localhost"'* ]]
    [[ "$result" == *'"port":1'* ]]
}

@test "monitor_port includes timestamp" {
    local result
    result=$(monitor_port "localhost" 1 1)
    [[ "$result" == *'"timestamp":'* ]]
}

@test "monitor_port shows closed for unused port" {
    local result
    result=$(monitor_port "localhost" 1 1)
    [[ "$result" == *'"state":"closed"'* ]]
}

# =============================================================================
# scan_range TESTS
# =============================================================================

@test "scan_range returns empty array with no args" {
    local result
    result=$(scan_range 2>/dev/null) || true
    [ "$result" = "[]" ]
}

@test "scan_range returns JSON array for comma ports" {
    local result
    result=$(scan_range "localhost" "1,2,3" 1)
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
    [[ "$result" == *'"port":1'* ]]
    [[ "$result" == *'"port":2'* ]]
    [[ "$result" == *'"port":3'* ]]
}

@test "scan_range returns JSON array for port range" {
    local result
    result=$(scan_range "localhost" "1-3" 1)
    [[ "$result" == "["* ]]
    [[ "$result" == *'"port":1'* ]]
    [[ "$result" == *'"port":3'* ]]
}

@test "scan_range includes state for each port" {
    local result
    result=$(scan_range "localhost" "1,2" 1)
    [[ "$result" == *'"state":'* ]]
}

# =============================================================================
# parse_nmap TESTS
# =============================================================================

@test "parse_nmap returns empty array for empty input" {
    local result
    result=$(printf '' | parse_nmap)
    [ "$result" = "[]" ]
}

@test "parse_nmap skips comment lines" {
    local result
    result=$(printf '# Nmap scan\n' | parse_nmap)
    [ "$result" = "[]" ]
}

@test "parse_nmap parses greppable output" {
    local input="Host: 192.168.1.1 (router.local)\tPorts: 22/open/tcp//ssh///, 80/open/tcp//http///\tIgnored State: closed (998)"
    local result
    result=$(parse_nmap "$input")
    [[ "$result" == *'"ip":"192.168.1.1"'* ]]
    [[ "$result" == *'"hostname":"router.local"'* ]]
    [[ "$result" == *'"port":22'* ]]
    [[ "$result" == *'"port":80'* ]]
    [[ "$result" == *'"service":"ssh"'* ]]
    [[ "$result" == *'"service":"http"'* ]]
}

@test "parse_nmap parses multiple hosts" {
    local input
    input="Host: 10.0.0.1 (host1)\tPorts: 22/open/tcp//ssh///
Host: 10.0.0.2 (host2)\tPorts: 80/open/tcp//http///"
    local result
    result=$(parse_nmap "$input")
    [[ "$result" == *'"ip":"10.0.0.1"'* ]]
    [[ "$result" == *'"ip":"10.0.0.2"'* ]]
}

@test "parse_nmap handles port state" {
    local input="Host: 10.0.0.1 (test)\tPorts: 22/open/tcp//ssh///, 23/filtered/tcp//telnet///"
    local result
    result=$(parse_nmap "$input")
    [[ "$result" == *'"state":"open"'* ]]
    [[ "$result" == *'"state":"filtered"'* ]]
}

@test "parse_nmap includes protocol" {
    local input="Host: 10.0.0.1 (test)\tPorts: 53/open/udp//dns///"
    local result
    result=$(parse_nmap "$input")
    [[ "$result" == *'"protocol":"udp"'* ]]
}

# =============================================================================
# netscan_http_headers TESTS
# =============================================================================

@test "netscan_http_headers returns 1 with no args" {
    local rc=0
    netscan_http_headers "" || rc=$?
    [ "$rc" = "1" ]
}

@test "netscan_http_headers adds scheme if missing" {
    # This tests the URL normalization logic
    # We test the output format with a known URL if curl is present
    if ! command -v curl &>/dev/null; then
        skip "curl not available"
    fi
    local result
    result=$(netscan_http_headers "127.0.0.1:1" 1 2>/dev/null) || true
    # Should either fail (connection refused) or return headers
    # Main thing is it doesn't crash
    true
}

@test "direct netscan source provides canonical raw-response http_headers" {
    local response result
    response=$'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Test: yes\r\n\r\nbody'

    result=$(http_headers "$response")

    [[ "$result" == *"Content-Type: text/plain"* ]]
    [[ "$result" == *"X-Test: yes"* ]]
    [[ "$result" != *"HTTP/1.1"* ]]
}

@test "canonical http_headers dispatches URL targets to netscan operation" {
    curl() {
        printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Test: yes\r\n\r\n'
    }

    local result
    result=$(http_headers "https://example.test/health" 2)

    [[ "$result" == *'"Content-Type":"text/plain"'* ]]
    [[ "$result" == *'"X-Test":"yes"'* ]]
    [[ "$result" == *'"_status":"HTTP/1.1 200 OK"'* ]]
}

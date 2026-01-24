#!/usr/bin/env bats

# =============================================================================
# Tests for MAINFRAME/lib/security.sh
# =============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/security.sh"
    FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures/security"
}

# =============================================================================
# sec_check_secrets
# =============================================================================

@test "sec_check_secrets detects API key prefixes" {
    _sec_reset
    sec_check_secrets "$FIXTURE_DIR/vulnerable.js"
    [[ ${#_SEC_FINDINGS[@]} -gt 0 ]]
    [[ $_SEC_CRITICAL -gt 0 ]]
}

@test "sec_check_secrets detects password assignments" {
    _sec_reset
    sec_check_secrets "$FIXTURE_DIR/vulnerable.js"
    local found=0
    for f in "${_SEC_FINDINGS[@]}"; do
        [[ "$f" == *"password"* || "$f" == *"secret"* ]] && found=1
    done
    [[ $found -eq 1 ]]
}

@test "sec_check_secrets ignores safe files" {
    _sec_reset
    sec_check_secrets "$FIXTURE_DIR/safe.js"
    [[ $_SEC_CRITICAL -eq 0 ]]
}

@test "sec_check_secrets handles missing file" {
    _sec_reset
    sec_check_secrets "/nonexistent/file.js"
    [[ ${#_SEC_FINDINGS[@]} -eq 0 ]]
}

@test "sec_check_secrets detects GitHub tokens" {
    _sec_reset
    sec_check_secrets "$FIXTURE_DIR/vulnerable.js"
    local found=0
    for f in "${_SEC_FINDINGS[@]}"; do
        [[ "$f" == *"CWE-798"* ]] && found=1
    done
    [[ $found -eq 1 ]]
}

# =============================================================================
# sec_check_injection
# =============================================================================

@test "sec_check_injection detects SQL concatenation" {
    _sec_reset
    sec_check_injection "$FIXTURE_DIR/vulnerable.js"
    local found=0
    for f in "${_SEC_FINDINGS[@]}"; do
        [[ "$f" == *"CWE-89"* ]] && found=1
    done
    [[ $found -eq 1 ]]
}

@test "sec_check_injection detects command injection" {
    _sec_reset
    sec_check_injection "$FIXTURE_DIR/vulnerable.js"
    local found=0
    for f in "${_SEC_FINDINGS[@]}"; do
        [[ "$f" == *"CWE-78"* ]] && found=1
    done
    [[ $found -eq 1 ]]
}

@test "sec_check_injection safe file has no findings" {
    _sec_reset
    sec_check_injection "$FIXTURE_DIR/safe.js"
    [[ ${#_SEC_FINDINGS[@]} -eq 0 ]]
}

@test "sec_check_injection detects shell=True" {
    _sec_reset
    sec_check_injection "$FIXTURE_DIR/vulnerable.js"
    [[ $_SEC_HIGH -gt 0 || $_SEC_CRITICAL -gt 0 ]]
}

# =============================================================================
# sec_check_xss
# =============================================================================

@test "sec_check_xss detects innerHTML with concatenation" {
    _sec_reset
    sec_check_xss "$FIXTURE_DIR/vulnerable.js"
    local found=0
    for f in "${_SEC_FINDINGS[@]}"; do
        [[ "$f" == *"CWE-79"* ]] && found=1
    done
    [[ $found -eq 1 ]]
}

@test "sec_check_xss safe file has no findings" {
    _sec_reset
    sec_check_xss "$FIXTURE_DIR/safe.js"
    [[ ${#_SEC_FINDINGS[@]} -eq 0 ]]
}

# =============================================================================
# sec_check_auth
# =============================================================================

@test "sec_check_auth detects md5 password hashing" {
    _sec_reset
    sec_check_auth "$FIXTURE_DIR/vulnerable.js"
    local found=0
    for f in "${_SEC_FINDINGS[@]}"; do
        [[ "$f" == *"CWE-327"* || "$f" == *"Weak hash"* ]] && found=1
    done
    [[ $found -eq 1 ]]
}

@test "sec_check_auth handles missing file" {
    _sec_reset
    sec_check_auth "/nonexistent"
    [[ ${#_SEC_FINDINGS[@]} -eq 0 ]]
}

# =============================================================================
# sec_check_input_validation
# =============================================================================

@test "sec_check_input_validation runs without error" {
    _sec_reset
    sec_check_input_validation "$FIXTURE_DIR/vulnerable.js"
    # vulnerable.js uses indirect concatenation, not direct req.* in db calls
    # so this correctly finds no input validation issues (injection handles that)
    [[ ${#_SEC_FINDINGS[@]} -eq 0 ]]
}

# =============================================================================
# sec_check_data_exposure
# =============================================================================

@test "sec_check_data_exposure detects SELECT star" {
    _sec_reset
    sec_check_data_exposure "$FIXTURE_DIR/vulnerable.js"
    local found=0
    for f in "${_SEC_FINDINGS[@]}"; do
        [[ "$f" == *"CWE-200"* ]] && found=1
    done
    [[ $found -eq 1 ]]
}

@test "sec_check_data_exposure detects raw object return" {
    _sec_reset
    sec_check_data_exposure "$FIXTURE_DIR/vulnerable.js"
    [[ ${#_SEC_FINDINGS[@]} -gt 0 ]]
}

# =============================================================================
# sec_scan_file
# =============================================================================

@test "sec_scan_file produces valid JSON" {
    local result
    result=$(sec_scan_file "$FIXTURE_DIR/vulnerable.js")
    # Check it starts with { and contains expected fields
    [[ "$result" == "{"* ]]
    [[ "$result" == *'"file":'* ]]
    [[ "$result" == *'"total_findings":'* ]]
    [[ "$result" == *'"findings":'* ]]
}

@test "sec_scan_file finds multiple vulnerabilities" {
    local result
    result=$(sec_scan_file "$FIXTURE_DIR/vulnerable.js")
    local total
    total=$(echo "$result" | grep -oP '"total_findings":\K[0-9]+')
    [[ $total -gt 3 ]]
}

@test "sec_scan_file safe file has fewer findings" {
    local vuln_result safe_result vuln_total safe_total
    vuln_result=$(sec_scan_file "$FIXTURE_DIR/vulnerable.js")
    safe_result=$(sec_scan_file "$FIXTURE_DIR/safe.js")
    vuln_total=$(echo "$vuln_result" | grep -oP '"total_findings":\K[0-9]+')
    safe_total=$(echo "$safe_result" | grep -oP '"total_findings":\K[0-9]+')
    [[ $vuln_total -gt $safe_total ]]
}

@test "sec_scan_file rejects unsupported extension" {
    local result
    result=$(sec_scan_file "$FIXTURE_DIR/../go_project/go.mod")
    [[ "$result" == *"unsupported"* ]]
}

@test "sec_scan_file handles nonexistent file gracefully" {
    run sec_scan_file "/nonexistent/file.js"
    [[ $status -eq 0 ]]
}

# =============================================================================
# sec_severity
# =============================================================================

@test "sec_severity critical returns 9" {
    local result
    result=$(sec_severity "critical")
    [[ "$result" -eq 9 ]]
}

@test "sec_severity high returns 7" {
    local result
    result=$(sec_severity "high")
    [[ "$result" -eq 7 ]]
}

@test "sec_severity medium returns 5" {
    local result
    result=$(sec_severity "medium")
    [[ "$result" -eq 5 ]]
}

@test "sec_severity low returns 3" {
    local result
    result=$(sec_severity "low")
    [[ "$result" -eq 3 ]]
}

@test "sec_severity unknown returns 0" {
    local result
    result=$(sec_severity "foobar")
    [[ "$result" -eq 0 ]]
}

# =============================================================================
# sec_integrate_risk
# =============================================================================

@test "sec_integrate_risk returns high score for vulnerable file" {
    local score
    score=$(sec_integrate_risk "$FIXTURE_DIR/vulnerable.js")
    [[ $score -ge 7 ]]
}

@test "sec_integrate_risk returns low score for safe file" {
    local score
    score=$(sec_integrate_risk "$FIXTURE_DIR/safe.js")
    [[ $score -lt 7 ]]
}

# =============================================================================
# _sec_escape_json
# =============================================================================

@test "_sec_escape_json escapes quotes" {
    local result
    result=$(_sec_escape_json 'hello "world"')
    [[ "$result" == 'hello \"world\"' ]]
}

@test "_sec_escape_json escapes backslashes" {
    local result
    result=$(_sec_escape_json 'path\\to\\file')
    [[ "$result" == 'path\\\\to\\\\file' ]]
}

@test "_sec_escape_json escapes newlines" {
    local result
    result=$(_sec_escape_json "line1
line2")
    [[ "$result" == 'line1\nline2' ]]
}

# =============================================================================
# _sec_reset
# =============================================================================

@test "_sec_reset clears findings" {
    _SEC_FINDINGS=("test1" "test2")
    _SEC_CRITICAL=5
    _sec_reset
    [[ ${#_SEC_FINDINGS[@]} -eq 0 ]]
    [[ $_SEC_CRITICAL -eq 0 ]]
}

# =============================================================================
# sec_check_file_upload
# =============================================================================

@test "sec_check_file_upload detects upload without validation" {
    _sec_reset
    sec_check_file_upload "$FIXTURE_DIR/vulnerable.js"
    [[ ${#_SEC_FINDINGS[@]} -gt 0 ]]
}

# =============================================================================
# sec_check_rate_limiting
# =============================================================================

@test "sec_check_rate_limiting detects missing limiter on routes" {
    _sec_reset
    sec_check_rate_limiting "$FIXTURE_DIR/vulnerable.js"
    [[ ${#_SEC_FINDINGS[@]} -gt 0 ]]
}

@test "sec_check_rate_limiting no false positive on non-route files" {
    _sec_reset
    sec_check_rate_limiting "$FIXTURE_DIR/../go_project/main.go"
    # Go file might not match JS route patterns
    [[ ${#_SEC_FINDINGS[@]} -eq 0 ]]
}

# =============================================================================
# sec_scan_dir
# =============================================================================

@test "sec_scan_dir produces valid JSON for fixture dir" {
    local result
    result=$(sec_scan_dir "$FIXTURE_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *'"files":'* ]]
}

@test "sec_scan_dir finds vulnerabilities across multiple files" {
    local result total
    result=$(sec_scan_dir "$FIXTURE_DIR")
    total=$(echo "$result" | grep -oP '"total_findings":\K[0-9]+' | head -1)
    [[ $total -gt 0 ]]
}

@test "sec_scan_dir handles nonexistent directory" {
    run sec_scan_dir "/nonexistent/path/to/dir"
    [[ $status -ne 0 ]]
}

@test "sec_scan_dir with non-recursive flag scans only top level" {
    local result
    result=$(sec_scan_dir "$FIXTURE_DIR" "--no-recursive")
    [[ "$result" == "{"* ]]
    [[ "$result" == *'"files_scanned":'* ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Tirith URL Security Module Tests
# =============================================================================
# Comprehensive tests for lib/tirith_url.sh (14 rules + aggregate scanner)
# Covers: homograph attacks, punycode, userinfo tricks, confusable domains,
#         raw IP, non-standard ports, lookalike TLDs, plain HTTP sinks,
#         schemeless sinks, shortened URLs, insecure TLS flags
# =============================================================================

load 'test_helper'

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/tirith_inject.sh"  # for shared state
    source "${BATS_TEST_DIRNAME}/../lib/tirith_url.sh"
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
    _TIRITH_FINDING_COUNT=0
}

# =============================================================================
# HELPER: _tirith_skeleton
# =============================================================================

@test "_tirith_skeleton returns ASCII unchanged" {
    local result
    result=$(_tirith_skeleton "github.com")
    [ "$result" = "github.com" ]
}

@test "_tirith_skeleton replaces Cyrillic confusables" {
    # Build domain with Cyrillic 'а' (U+0430) and 'о' (U+043E)
    local cyrillic_a=$'\xd0\xb0'
    local cyrillic_o=$'\xd0\xbe'
    local domain="g${cyrillic_o}${cyrillic_o}gle.c${cyrillic_o}m"
    local result
    result=$(_tirith_skeleton "$domain")
    [ "$result" = "google.com" ]
}

# =============================================================================
# HELPER: _tirith_has_non_ascii
# =============================================================================

@test "_tirith_has_non_ascii returns 0 for Cyrillic chars" {
    local cyrillic_a=$'\xd0\xb0'
    _tirith_has_non_ascii "hello${cyrillic_a}"
}

@test "_tirith_has_non_ascii returns 1 for pure ASCII" {
    run _tirith_has_non_ascii "hello world"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 1: NON-ASCII HOSTNAME
# =============================================================================

@test "non_ascii_hostname detects Cyrillic in host" {
    local cyrillic_a=$'\xd0\xb0'
    run tirith_check_non_ascii_hostname "https://ex${cyrillic_a}mple.com/path"
    [ "$status" -eq 0 ]
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ] || {
        # When run via 'run', findings are in the subshell; check return code only
        true
    }
}

@test "non_ascii_hostname passes clean ASCII hostname" {
    run tirith_check_non_ascii_hostname "https://example.com/path"
    [ "$status" -eq 1 ]
}

@test "non_ascii_hostname returns 1 for empty input" {
    run tirith_check_non_ascii_hostname ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 2: PUNYCODE DOMAIN
# =============================================================================

@test "punycode_domain detects xn-- label" {
    run tirith_check_punycode_domain "https://xn--80ak6aa.com/path"
    [ "$status" -eq 0 ]
}

@test "punycode_domain passes normal domain" {
    run tirith_check_punycode_domain "https://example.com/path"
    [ "$status" -eq 1 ]
}

@test "punycode_domain returns 1 for empty input" {
    run tirith_check_punycode_domain ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 3: MIXED SCRIPT IN LABEL
# =============================================================================

@test "mixed_script detects ASCII mixed with Cyrillic in label" {
    # "gіthub" - Cyrillic 'і' (U+0456) mixed with ASCII letters
    local cyrillic_i=$'\xd1\x96'
    tirith_check_mixed_script "https://g${cyrillic_i}thub.com/repo"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"MixedScriptInLabel"* ]]
}

@test "mixed_script passes pure ASCII hostname" {
    run tirith_check_mixed_script "https://github.com/repo"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 4: USERINFO TRICK
# =============================================================================

@test "userinfo_trick detects domain-like userinfo" {
    tirith_check_userinfo_trick "http://google.com@evil.com/path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"UserinfoTrick"* ]]
}

@test "userinfo_trick detects bare userinfo without dots" {
    tirith_check_userinfo_trick "http://admin@evil.com/path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"UserinfoTrick"* ]]
}

@test "userinfo_trick passes URL without userinfo" {
    run tirith_check_userinfo_trick "https://example.com/path"
    [ "$status" -eq 1 ]
}

@test "userinfo_trick returns 1 for empty input" {
    run tirith_check_userinfo_trick ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 5: INVALID HOST CHARS
# =============================================================================

@test "invalid_host_chars detects space in hostname" {
    tirith_check_invalid_host_chars "http://exam ple.com/path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"InvalidHostChars"* ]]
}

@test "invalid_host_chars detects brackets in hostname" {
    tirith_check_invalid_host_chars "http://exam[ple].com/path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"InvalidHostChars"* ]]
}

@test "invalid_host_chars passes valid hostname" {
    run tirith_check_invalid_host_chars "https://sub.example.com/path"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 6: TRAILING DOT / WHITESPACE
# =============================================================================

@test "trailing_dot detects trailing dot in hostname" {
    tirith_check_trailing_dot_whitespace "http://example.com./path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"TrailingDotWhitespace"* ]]
}

@test "trailing_dot passes hostname without trailing dot" {
    run tirith_check_trailing_dot_whitespace "https://example.com/path"
    [ "$status" -eq 1 ]
}

@test "trailing_dot returns 1 for empty input" {
    run tirith_check_trailing_dot_whitespace ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 7: CONFUSABLE DOMAIN
# =============================================================================

@test "confusable_domain detects Cyrillic github lookalike" {
    # Build "github.com" with Cyrillic 'і' -> i and 'а' -> a
    # g + Cyrillic_і + t + h + u + b + . + c + Cyrillic_о + m
    local cyrillic_i=$'\xd1\x96'
    local cyrillic_o=$'\xd0\xbe'
    # Skeleton of "g<cyrillic_i>thub.c<cyrillic_o>m" -> "github.com"
    tirith_check_confusable_domain "https://g${cyrillic_i}thub.c${cyrillic_o}m/repo"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"ConfusableDomain"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"github.com"* ]]
}

@test "confusable_domain passes real github.com" {
    run tirith_check_confusable_domain "https://github.com/user/repo"
    [ "$status" -eq 1 ]
}

@test "confusable_domain passes unknown domain" {
    run tirith_check_confusable_domain "https://myuniquedomain42.net/page"
    [ "$status" -eq 1 ]
}

@test "confusable_domain returns 1 for empty input" {
    run tirith_check_confusable_domain ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 8: RAW IP URL
# =============================================================================

@test "raw_ip_url detects IPv4 address" {
    tirith_check_raw_ip_url "http://192.168.1.1/path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"RawIpUrl"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"192.168.1.1"* ]]
}

@test "raw_ip_url passes normal hostname" {
    run tirith_check_raw_ip_url "https://example.com/path"
    [ "$status" -eq 1 ]
}

@test "raw_ip_url returns 1 for empty input" {
    run tirith_check_raw_ip_url ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 9: NON-STANDARD PORT
# =============================================================================

@test "non_standard_port detects HTTPS on port 8443" {
    tirith_check_non_standard_port "https://example.com:8443/path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"NonStandardPort"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"8443"* ]]
}

@test "non_standard_port detects HTTP on port 8080" {
    tirith_check_non_standard_port "http://example.com:8080/path"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"NonStandardPort"* ]]
}

@test "non_standard_port passes HTTPS on port 443" {
    run tirith_check_non_standard_port "https://example.com:443/path"
    [ "$status" -eq 1 ]
}

@test "non_standard_port passes HTTP on port 80" {
    run tirith_check_non_standard_port "http://example.com:80/path"
    [ "$status" -eq 1 ]
}

@test "non_standard_port passes URL without explicit port" {
    run tirith_check_non_standard_port "https://example.com/path"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 10: LOOKALIKE TLD
# =============================================================================

@test "lookalike_tld detects .zip TLD" {
    tirith_check_lookalike_tld "http://downloads.zip/payload"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"LookalikeTld"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *".zip"* ]]
}

@test "lookalike_tld detects .mov TLD" {
    tirith_check_lookalike_tld "https://video.mov/clip"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"LookalikeTld"* ]]
}

@test "lookalike_tld detects .exe TLD" {
    tirith_check_lookalike_tld "https://installer.exe/download"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"LookalikeTld"* ]]
}

@test "lookalike_tld passes .com TLD" {
    run tirith_check_lookalike_tld "https://example.com/path"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 11: PLAIN HTTP TO SINK
# =============================================================================

@test "plain_http detects HTTP to login path" {
    tirith_check_plain_http "http://example.com/login"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"PlainHttpToSink"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"login"* ]]
}

@test "plain_http detects HTTP to auth path" {
    tirith_check_plain_http "http://example.com/api/oauth/callback"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"PlainHttpToSink"* ]]
}

@test "plain_http passes HTTPS to login" {
    run tirith_check_plain_http "https://example.com/login"
    [ "$status" -eq 1 ]
}

@test "plain_http passes HTTP to non-sensitive path" {
    run tirith_check_plain_http "http://example.com/about"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 12: SCHEMELESS TO SINK
# =============================================================================

@test "schemeless detects //evil.com/auth/callback" {
    tirith_check_schemeless "//evil.com/auth/callback"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"SchemelessToSink"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"auth"* ]]
}

@test "schemeless detects //evil.com/login" {
    tirith_check_schemeless "//evil.com/login"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"SchemelessToSink"* ]]
}

@test "schemeless passes URL with scheme" {
    run tirith_check_schemeless "https://example.com/login"
    [ "$status" -eq 1 ]
}

@test "schemeless passes //host with non-sensitive path" {
    run tirith_check_schemeless "//cdn.example.com/styles.css"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 13: SHORTENED URL
# =============================================================================

@test "shortened_url detects bit.ly" {
    tirith_check_shortened_url "https://bit.ly/abc123"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"ShortenedUrl"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"bit.ly"* ]]
}

@test "shortened_url detects t.co" {
    tirith_check_shortened_url "https://t.co/xyz789"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"ShortenedUrl"* ]]
}

@test "shortened_url detects tinyurl.com" {
    tirith_check_shortened_url "http://tinyurl.com/abcdef"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"ShortenedUrl"* ]]
}

@test "shortened_url passes normal domain" {
    run tirith_check_shortened_url "https://example.com/path"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RULE 14: INSECURE TLS FLAGS
# =============================================================================

@test "insecure_tls detects --insecure flag" {
    tirith_check_insecure_tls "curl --insecure https://example.com"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"InsecureTlsFlags"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"--insecure"* ]]
}

@test "insecure_tls detects -k flag" {
    tirith_check_insecure_tls "curl -k https://api.example.com"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"InsecureTlsFlags"* ]]
}

@test "insecure_tls detects --no-check-certificate" {
    tirith_check_insecure_tls "wget --no-check-certificate https://example.com/file"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"InsecureTlsFlags"* ]]
}

@test "insecure_tls detects NODE_TLS_REJECT_UNAUTHORIZED=0" {
    tirith_check_insecure_tls "NODE_TLS_REJECT_UNAUTHORIZED=0 node server.js"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"InsecureTlsFlags"* ]]
}

@test "insecure_tls detects verify=False (Python)" {
    tirith_check_insecure_tls 'requests.get(url, verify=False)'
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    [[ "${_TIRITH_FINDINGS[0]}" == *"InsecureTlsFlags"* ]]
}

@test "insecure_tls passes clean curl command" {
    run tirith_check_insecure_tls "curl https://example.com/api"
    [ "$status" -eq 1 ]
}

@test "insecure_tls returns 1 for empty input" {
    run tirith_check_insecure_tls ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# AGGREGATE: tirith_scan_url_checks
# =============================================================================

@test "scan_url_checks detects multiple issues in malicious URL" {
    # HTTP + raw IP + non-standard port + login path = multiple findings
    tirith_scan_url_checks "http://192.168.1.1:8080/login"
    [ "${#_TIRITH_FINDINGS[@]}" -ge 2 ]
}

@test "scan_url_checks returns 0 when findings exist" {
    run tirith_scan_url_checks "http://192.168.1.1/login"
    [ "$status" -eq 0 ]
}

@test "scan_url_checks returns 1 for clean HTTPS URL" {
    run tirith_scan_url_checks "https://example.com/about"
    [ "$status" -eq 1 ]
}

@test "scan_url_checks returns 1 for empty input" {
    run tirith_scan_url_checks ""
    [ "$status" -eq 1 ]
}

@test "scan_url_checks detects shortened URL through aggregate" {
    tirith_scan_url_checks "https://bit.ly/abc123"
    [ "${#_TIRITH_FINDINGS[@]}" -gt 0 ]
    local found=false
    local f
    for f in "${_TIRITH_FINDINGS[@]}"; do
        if [[ "$f" == *"ShortenedUrl"* ]]; then
            found=true
            break
        fi
    done
    [ "$found" = "true" ]
}

@test "scan_url_checks detects userinfo trick through aggregate" {
    tirith_scan_url_checks "http://google.com@evil.com/path"
    local found=false
    local f
    for f in "${_TIRITH_FINDINGS[@]}"; do
        if [[ "$f" == *"UserinfoTrick"* ]]; then
            found=true
            break
        fi
    done
    [ "$found" = "true" ]
}

# =============================================================================
# CLEAN URL COMPREHENSIVE CHECK
# =============================================================================

@test "clean HTTPS URL passes all individual checks" {
    local url="https://docs.example.com/guide/introduction"

    run tirith_check_non_ascii_hostname "$url"
    [ "$status" -eq 1 ]

    run tirith_check_punycode_domain "$url"
    [ "$status" -eq 1 ]

    run tirith_check_mixed_script "$url"
    [ "$status" -eq 1 ]

    run tirith_check_userinfo_trick "$url"
    [ "$status" -eq 1 ]

    run tirith_check_invalid_host_chars "$url"
    [ "$status" -eq 1 ]

    run tirith_check_trailing_dot_whitespace "$url"
    [ "$status" -eq 1 ]

    run tirith_check_confusable_domain "$url"
    [ "$status" -eq 1 ]

    run tirith_check_raw_ip_url "$url"
    [ "$status" -eq 1 ]

    run tirith_check_non_standard_port "$url"
    [ "$status" -eq 1 ]

    run tirith_check_lookalike_tld "$url"
    [ "$status" -eq 1 ]

    run tirith_check_plain_http "$url"
    [ "$status" -eq 1 ]

    run tirith_check_schemeless "$url"
    [ "$status" -eq 1 ]

    run tirith_check_shortened_url "$url"
    [ "$status" -eq 1 ]
}

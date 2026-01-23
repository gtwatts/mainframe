#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Safe Context Profiles Tests
# =============================================================================
# Tests for lib/safecontext.sh - Environment-aware safety profiles
# =============================================================================

load 'test_helper'

setup() {
    source_lib "safecontext"
    export TEST_DIR="$(mktemp -d)"
    # Clear any env vars that could affect detection
    unset NODE_ENV RAILS_ENV MAINFRAME_ENV CI GITHUB_ACTIONS
    unset MAINFRAME_OUTPUT
    # Reset state between tests
    _MAINFRAME_CTX_PROFILE=""
    _MAINFRAME_CTX_RISK_THRESHOLD=""
    _MAINFRAME_CTX_CONFIRM_POLICY=""
    _MAINFRAME_CTX_LIMITS=""
    _MAINFRAME_CTX_DRY_RUN=""
    _MAINFRAME_CTX_OVERRIDES=()
    _MAINFRAME_CTX_CUSTOM_PROFILES=()
    _MAINFRAME_CTX_ENFORCED=0
}

teardown() {
    rm -rf "$TEST_DIR"
    mainframe_context_reset 2>/dev/null || true
}

# =============================================================================
# DOUBLE-SOURCE GUARD (1 test)
# =============================================================================

@test "double-source guard: _MAINFRAME_SAFECONTEXT_LOADED is set" {
    [ -n "$_MAINFRAME_SAFECONTEXT_LOADED" ]
    [ "$_MAINFRAME_SAFECONTEXT_LOADED" = "1" ]
}

# =============================================================================
# mainframe_context_set: PROFILE SETTING (10 tests)
# =============================================================================

@test "context_set: development profile succeeds" {
    run mainframe_context_set development
    [ "$status" -eq 0 ]
}

@test "context_set: staging profile succeeds" {
    run mainframe_context_set staging
    [ "$status" -eq 0 ]
}

@test "context_set: production profile succeeds" {
    run mainframe_context_set production
    [ "$status" -eq 0 ]
}

@test "context_set: testing profile succeeds" {
    run mainframe_context_set testing
    [ "$status" -eq 0 ]
}

@test "context_set: ci profile succeeds" {
    run mainframe_context_set ci
    [ "$status" -eq 0 ]
}

@test "context_set: unknown profile fails" {
    run mainframe_context_set nonexistent
    [ "$status" -eq 1 ]
}

@test "context_set: empty profile fails" {
    run mainframe_context_set ""
    [ "$status" -eq 1 ]
}

@test "context_set: no argument fails" {
    run mainframe_context_set
    [ "$status" -eq 1 ]
}

@test "context_set: sets development rules correctly" {
    mainframe_context_set development
    [ "$_MAINFRAME_CTX_RISK_THRESHOLD" = "8" ]
    [ "$_MAINFRAME_CTX_CONFIRM_POLICY" = "never" ]
    [ "$_MAINFRAME_CTX_LIMITS" = "permissive" ]
    [ "$_MAINFRAME_CTX_DRY_RUN" = "false" ]
}

@test "context_set: sets production rules correctly" {
    mainframe_context_set production
    [ "$_MAINFRAME_CTX_RISK_THRESHOLD" = "3" ]
    [ "$_MAINFRAME_CTX_CONFIRM_POLICY" = "always" ]
    [ "$_MAINFRAME_CTX_LIMITS" = "strict" ]
    [ "$_MAINFRAME_CTX_DRY_RUN" = "true" ]
}

# =============================================================================
# mainframe_context_get: PROFILE RETRIEVAL (4 tests)
# =============================================================================

@test "context_get: returns empty when no profile set" {
    _MAINFRAME_CTX_PROFILE=""
    run mainframe_context_get
    [ "$status" -eq 1 ]
}

@test "context_get: returns development after set" {
    mainframe_context_set development
    local result
    result=$(mainframe_context_get)
    [ "$result" = "development" ]
}

@test "context_get: returns production after set" {
    mainframe_context_set production
    local result
    result=$(mainframe_context_get)
    [ "$result" = "production" ]
}

@test "context_get: returns ci after set" {
    mainframe_context_set ci
    local result
    result=$(mainframe_context_get)
    [ "$result" = "ci" ]
}

# =============================================================================
# mainframe_context_detect: AUTO-DETECTION (9 tests)
# =============================================================================

@test "context_detect: CI=true detects ci" {
    export CI=true
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "ci" ]
}

@test "context_detect: GITHUB_ACTIONS=true detects ci" {
    export GITHUB_ACTIONS=true
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "ci" ]
}

@test "context_detect: NODE_ENV=production detects production" {
    export NODE_ENV=production
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "production" ]
}

@test "context_detect: MAINFRAME_ENV=production detects production" {
    export MAINFRAME_ENV=production
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "production" ]
}

@test "context_detect: RAILS_ENV=production detects production" {
    export RAILS_ENV=production
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "production" ]
}

@test "context_detect: NODE_ENV=test detects testing" {
    export NODE_ENV=test
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "testing" ]
}

@test "context_detect: MAINFRAME_ENV=testing detects testing" {
    export MAINFRAME_ENV=testing
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "testing" ]
}

@test "context_detect: staging hostname detects staging" {
    export HOSTNAME="web-staging-01"
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "staging" ]
}

@test "context_detect: default detects development" {
    unset NODE_ENV RAILS_ENV MAINFRAME_ENV CI GITHUB_ACTIONS HOSTNAME
    export HOSTNAME="my-laptop"
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "development" ]
}

# =============================================================================
# mainframe_context_rules: PROFILE RULES (7 tests)
# =============================================================================

@test "context_rules: development has risk_threshold 8" {
    local result
    result=$(mainframe_context_rules development)
    [[ "$result" == *'"risk_threshold":8'* ]]
}

@test "context_rules: staging has risk_threshold 6" {
    local result
    result=$(mainframe_context_rules staging)
    [[ "$result" == *'"risk_threshold":6'* ]]
}

@test "context_rules: production has dry_run true" {
    local result
    result=$(mainframe_context_rules production)
    [[ "$result" == *'"dry_run":true'* ]]
}

@test "context_rules: testing has risk_threshold 10" {
    local result
    result=$(mainframe_context_rules testing)
    [[ "$result" == *'"risk_threshold":10'* ]]
}

@test "context_rules: ci has confirm_policy never" {
    local result
    result=$(mainframe_context_rules ci)
    [[ "$result" == *'"confirm_policy":"never"'* ]]
}

@test "context_rules: uses current profile when no arg" {
    mainframe_context_set staging
    local result
    result=$(mainframe_context_rules)
    [[ "$result" == *'"profile":"staging"'* ]]
}

@test "context_rules: unknown profile returns error" {
    run mainframe_context_rules unknown_profile
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_context_override and mainframe_context_reset (8 tests)
# =============================================================================

@test "context_override: overrides risk_threshold" {
    mainframe_context_set development
    mainframe_context_override risk_threshold 5
    [ "${_MAINFRAME_CTX_OVERRIDES[risk_threshold]}" = "5" ]
}

@test "context_override: overrides confirm_policy" {
    mainframe_context_set development
    mainframe_context_override confirm_policy always
    [ "${_MAINFRAME_CTX_OVERRIDES[confirm_policy]}" = "always" ]
}

@test "context_override: overrides dry_run" {
    mainframe_context_set development
    mainframe_context_override dry_run true
    [ "${_MAINFRAME_CTX_OVERRIDES[dry_run]}" = "true" ]
}

@test "context_override: invalid key fails" {
    mainframe_context_set development
    run mainframe_context_override invalid_key value
    [ "$status" -eq 1 ]
}

@test "context_override: empty key fails" {
    run mainframe_context_override "" "value"
    [ "$status" -eq 1 ]
}

@test "context_reset: clears overrides" {
    mainframe_context_set development
    mainframe_context_override risk_threshold 2
    mainframe_context_reset
    [ -z "${_MAINFRAME_CTX_OVERRIDES[risk_threshold]:-}" ]
}

@test "context_reset: reverts to base profile rules" {
    mainframe_context_set production
    mainframe_context_override risk_threshold 9
    mainframe_context_reset
    [ "$_MAINFRAME_CTX_RISK_THRESHOLD" = "3" ]
}

@test "context_reset: clears enforced state" {
    mainframe_context_set development
    _MAINFRAME_CTX_ENFORCED=1
    mainframe_context_reset
    [ "$_MAINFRAME_CTX_ENFORCED" = "0" ]
}

# =============================================================================
# mainframe_context_is: CONTEXT CHECKING (5 tests)
# =============================================================================

@test "context_is: returns 0 when profile matches" {
    mainframe_context_set development
    mainframe_context_is development
}

@test "context_is: returns 1 when profile does not match" {
    mainframe_context_set development
    run mainframe_context_is production
    [ "$status" -eq 1 ]
}

@test "context_is: returns 1 when no profile set" {
    _MAINFRAME_CTX_PROFILE=""
    run mainframe_context_is development
    [ "$status" -eq 1 ]
}

@test "context_is: returns 1 for empty argument" {
    mainframe_context_set development
    run mainframe_context_is ""
    [ "$status" -eq 1 ]
}

@test "context_is: matches after detection" {
    export CI=true
    mainframe_context_detect
    mainframe_context_is ci
}

# =============================================================================
# mainframe_context_require: CONTEXT GUARD (5 tests)
# =============================================================================

@test "context_require: succeeds when matching" {
    mainframe_context_set production
    run mainframe_context_require production
    [ "$status" -eq 0 ]
}

@test "context_require: fails when not matching" {
    mainframe_context_set development
    run mainframe_context_require production
    [ "$status" -eq 1 ]
}

@test "context_require: fails when no profile set" {
    _MAINFRAME_CTX_PROFILE=""
    run mainframe_context_require production
    [ "$status" -eq 1 ]
}

@test "context_require: error message mentions both profiles" {
    mainframe_context_set development
    run mainframe_context_require production
    [ "$status" -eq 1 ]
    [[ "$output" == *"production"* ]]
    [[ "$output" == *"development"* ]]
}

@test "context_require: empty argument fails" {
    mainframe_context_set development
    run mainframe_context_require ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_context_enforce: ENFORCEMENT (7 tests)
# =============================================================================

@test "context_enforce: sets MAINFRAME_RISK_THRESHOLD for production" {
    mainframe_context_set production
    mainframe_context_enforce
    [ "$MAINFRAME_RISK_THRESHOLD" = "3" ]
}

@test "context_enforce: sets MAINFRAME_RISK_THRESHOLD for development" {
    mainframe_context_set development
    mainframe_context_enforce
    [ "$MAINFRAME_RISK_THRESHOLD" = "8" ]
}

@test "context_enforce: sets MAINFRAME_DRY_RUN for production" {
    mainframe_context_set production
    mainframe_context_enforce
    [ "$MAINFRAME_DRY_RUN" = "1" ]
}

@test "context_enforce: sets MAINFRAME_DRY_RUN to 0 for development" {
    mainframe_context_set development
    mainframe_context_enforce
    [ "$MAINFRAME_DRY_RUN" = "0" ]
}

@test "context_enforce: respects overrides" {
    mainframe_context_set development
    mainframe_context_override risk_threshold 2
    mainframe_context_enforce
    [ "$MAINFRAME_RISK_THRESHOLD" = "2" ]
}

@test "context_enforce: sets enforced flag" {
    mainframe_context_set testing
    mainframe_context_enforce
    [ "$_MAINFRAME_CTX_ENFORCED" = "1" ]
}

@test "context_enforce: fails when no profile active" {
    _MAINFRAME_CTX_PROFILE=""
    run mainframe_context_enforce
    [ "$status" -eq 1 ]
}

# =============================================================================
# mainframe_context_status: STATUS OUTPUT (4 tests)
# =============================================================================

@test "context_status: empty when no profile" {
    _MAINFRAME_CTX_PROFILE=""
    local result
    result=$(mainframe_context_status)
    [[ "$result" == *'"profile":""'* ]]
}

@test "context_status: shows profile name" {
    mainframe_context_set staging
    local result
    result=$(mainframe_context_status)
    [[ "$result" == *'"profile":"staging"'* ]]
}

@test "context_status: shows overrides" {
    mainframe_context_set development
    mainframe_context_override risk_threshold 3
    local result
    result=$(mainframe_context_status)
    [[ "$result" == *'"risk_threshold":"3"'* ]]
}

@test "context_status: shows enforced state" {
    mainframe_context_set development
    mainframe_context_enforce
    local result
    result=$(mainframe_context_status)
    [[ "$result" == *'"enforced":true'* ]]
}

# =============================================================================
# mainframe_context_list: PROFILE LISTING (3 tests)
# =============================================================================

@test "context_list: includes all built-in profiles" {
    local result
    result=$(mainframe_context_list)
    [[ "$result" == *"development"* ]]
    [[ "$result" == *"staging"* ]]
    [[ "$result" == *"production"* ]]
    [[ "$result" == *"testing"* ]]
    [[ "$result" == *"ci"* ]]
}

@test "context_list: includes custom profiles" {
    mainframe_context_custom "canary" "risk_threshold=4 confirm_policy=risk limits=strict dry_run=true"
    local result
    result=$(mainframe_context_list)
    [[ "$result" == *"canary"* ]]
}

@test "context_list: json output has array" {
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_context_list)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'["'* ]]
}

# =============================================================================
# mainframe_context_custom: CUSTOM PROFILES (10 tests)
# =============================================================================

@test "context_custom: creates profile with key=value format" {
    run mainframe_context_custom "local" "risk_threshold=9 confirm_policy=never limits=permissive dry_run=false"
    [ "$status" -eq 0 ]
}

@test "context_custom: creates profile with JSON format" {
    run mainframe_context_custom "canary" '{"risk_threshold":4,"confirm_policy":"risk","limits":"strict","dry_run":true}'
    [ "$status" -eq 0 ]
}

@test "context_custom: custom profile can be set" {
    mainframe_context_custom "myprofile" "risk_threshold=7 confirm_policy=risk limits=moderate dry_run=false"
    mainframe_context_set myprofile
    [ "$_MAINFRAME_CTX_RISK_THRESHOLD" = "7" ]
    [ "$_MAINFRAME_CTX_CONFIRM_POLICY" = "risk" ]
}

@test "context_custom: rejects empty name" {
    run mainframe_context_custom "" "risk_threshold=5"
    [ "$status" -eq 1 ]
}

@test "context_custom: rejects empty rules" {
    run mainframe_context_custom "test" ""
    [ "$status" -eq 1 ]
}

@test "context_custom: rejects invalid confirm_policy" {
    run mainframe_context_custom "bad" "risk_threshold=5 confirm_policy=invalid limits=moderate dry_run=false"
    [ "$status" -eq 1 ]
}

@test "context_custom: rejects invalid limits" {
    run mainframe_context_custom "bad" "risk_threshold=5 confirm_policy=never limits=invalid dry_run=false"
    [ "$status" -eq 1 ]
}

@test "context_custom: rejects invalid dry_run" {
    run mainframe_context_custom "bad" "risk_threshold=5 confirm_policy=never limits=none dry_run=maybe"
    [ "$status" -eq 1 ]
}

@test "context_custom: rejects non-numeric risk_threshold" {
    run mainframe_context_custom "bad" "risk_threshold=abc confirm_policy=never limits=none dry_run=false"
    [ "$status" -eq 1 ]
}

@test "context_custom: defaults missing values" {
    mainframe_context_custom "partial" "risk_threshold=7"
    mainframe_context_set partial
    [ "$_MAINFRAME_CTX_RISK_THRESHOLD" = "7" ]
    [ "$_MAINFRAME_CTX_CONFIRM_POLICY" = "risk" ]
    [ "$_MAINFRAME_CTX_LIMITS" = "moderate" ]
    [ "$_MAINFRAME_CTX_DRY_RUN" = "false" ]
}

# =============================================================================
# PROFILE RULES CORRECTNESS (5 tests)
# =============================================================================

@test "profile rules: staging has confirm_policy risk" {
    mainframe_context_set staging
    [ "$_MAINFRAME_CTX_CONFIRM_POLICY" = "risk" ]
}

@test "profile rules: staging has limits moderate" {
    mainframe_context_set staging
    [ "$_MAINFRAME_CTX_LIMITS" = "moderate" ]
}

@test "profile rules: testing has limits none" {
    mainframe_context_set testing
    [ "$_MAINFRAME_CTX_LIMITS" = "none" ]
}

@test "profile rules: ci has risk_threshold 5" {
    mainframe_context_set ci
    [ "$_MAINFRAME_CTX_RISK_THRESHOLD" = "5" ]
}

@test "profile rules: ci has dry_run false" {
    mainframe_context_set ci
    [ "$_MAINFRAME_CTX_DRY_RUN" = "false" ]
}

# =============================================================================
# ENFORCEMENT INTEGRATION (5 tests)
# =============================================================================

@test "enforce: always policy sets confirm threshold to 0" {
    mainframe_context_set production
    mainframe_context_enforce
    [ "$MAINFRAME_RISK_CONFIRM_THRESHOLD" = "0" ]
}

@test "enforce: never policy sets confirm threshold to 11" {
    mainframe_context_set development
    mainframe_context_enforce
    [ "$MAINFRAME_RISK_CONFIRM_THRESHOLD" = "11" ]
}

@test "enforce: risk policy sets confirm threshold to risk_threshold" {
    mainframe_context_set staging
    mainframe_context_enforce
    [ "$MAINFRAME_RISK_CONFIRM_THRESHOLD" = "6" ]
}

@test "enforce: sets MAINFRAME_LIMITS_POLICY" {
    mainframe_context_set production
    mainframe_context_enforce
    [ "$MAINFRAME_LIMITS_POLICY" = "strict" ]
}

@test "enforce: sets MAINFRAME_CONFIRM_POLICY" {
    mainframe_context_set production
    mainframe_context_enforce
    [ "$MAINFRAME_CONFIRM_POLICY" = "always" ]
}

# =============================================================================
# EDGE CASES (6 tests)
# =============================================================================

@test "edge: switching profiles clears overrides" {
    mainframe_context_set development
    mainframe_context_override risk_threshold 1
    mainframe_context_set production
    [ -z "${_MAINFRAME_CTX_OVERRIDES[risk_threshold]:-}" ]
}

@test "edge: detect with stg hostname pattern" {
    export HOSTNAME="app-stg-02.internal"
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "staging" ]
}

@test "edge: CI takes priority over NODE_ENV=production" {
    export CI=true
    export NODE_ENV=production
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "ci" ]
}

@test "edge: RAILS_ENV=test detects testing" {
    export RAILS_ENV=test
    mainframe_context_detect
    local result
    result=$(mainframe_context_get)
    [ "$result" = "testing" ]
}

@test "edge: multiple overrides tracked" {
    mainframe_context_set development
    mainframe_context_override risk_threshold 3
    mainframe_context_override dry_run true
    mainframe_context_override limits strict
    [ "${_MAINFRAME_CTX_OVERRIDES[risk_threshold]}" = "3" ]
    [ "${_MAINFRAME_CTX_OVERRIDES[dry_run]}" = "true" ]
    [ "${_MAINFRAME_CTX_OVERRIDES[limits]}" = "strict" ]
}

@test "edge: reset with no profile set does not error" {
    _MAINFRAME_CTX_PROFILE=""
    run mainframe_context_reset
    [ "$status" -eq 0 ]
}

# =============================================================================
# JSON OUTPUT MODE (5 tests)
# =============================================================================

@test "json: context_set outputs JSON when MAINFRAME_OUTPUT=json" {
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_context_set development)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"profile":"development"'* ]]
}

@test "json: context_get outputs JSON when MAINFRAME_OUTPUT=json" {
    mainframe_context_set staging
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_context_get)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"data":"staging"'* ]]
}

@test "json: context_set error outputs JSON when MAINFRAME_OUTPUT=json" {
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_context_set nonexistent)
    [[ "$result" == *'"ok":false'* ]]
    [[ "$result" == *'"code":"E_CTX_UNKNOWN"'* ]]
}

@test "json: context_enforce outputs JSON when MAINFRAME_OUTPUT=json" {
    mainframe_context_set testing
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_context_enforce)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"enforced":true'* ]]
}

@test "json: context_override outputs JSON when MAINFRAME_OUTPUT=json" {
    mainframe_context_set development
    export MAINFRAME_OUTPUT=json
    local result
    result=$(mainframe_context_override risk_threshold 4)
    [[ "$result" == *'"ok":true'* ]]
    [[ "$result" == *'"key":"risk_threshold"'* ]]
}

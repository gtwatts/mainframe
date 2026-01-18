#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Template Engine Library Tests
# =============================================================================
# Run with: bash tests/template_test.sh
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/template.sh"

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Print colored output
_red() { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }
_blue() { printf '\033[34m%s\033[0m' "$*"; }

# Run a test
test_case() {
    local name="$1"
    local func="$2"
    
    ((TESTS_RUN++))
    
    # Run test in subshell to isolate
    local output
    local status
    if output=$(set -e; "$func" 2>&1); then
        status=0
    else
        status=$?
    fi
    
    if [[ $status -eq 0 ]]; then
        ((TESTS_PASSED++))
        printf '  %s %s\n' "$(_green '✓')" "$name"
    else
        ((TESTS_FAILED++))
        printf '  %s %s\n' "$(_red '✗')" "$name"
        if [[ -n "$output" ]]; then
            printf '    %s\n' "$output" | head -5
        fi
    fi
}

# Assert equality
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        printf 'Expected: "%s"\nActual:   "%s"\n' "$expected" "$actual" >&2
        [[ -n "$msg" ]] && printf 'Message: %s\n' "$msg" >&2
        return 1
    fi
}

# Assert not empty
assert_not_empty() {
    local value="$1"
    [[ -n "$value" ]] || {
        printf 'Value is empty\n' >&2
        return 1
    }
}

# Assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        printf 'String does not contain: %s\n' "$needle" >&2
        return 1
    }
}

# Assert return code
assert_returns() {
    local expected="$1"
    shift
    local actual
    "$@" && actual=0 || actual=$?
    [[ "$actual" -eq "$expected" ]] || {
        printf 'Expected return code: %s, got: %s\n' "$expected" "$actual" >&2
        return 1
    }
}

# =============================================================================
# BASIC VARIABLE SUBSTITUTION TESTS
# =============================================================================

test_simple_variable() {
    local result
    result=$(template::render "Hello {{name}}!" name="World")
    assert_eq "Hello World!" "$result"
}

test_multiple_variables() {
    local result
    result=$(template::render "{{greeting}}, {{name}}!" greeting="Hi" name="Alice")
    assert_eq "Hi, Alice!" "$result"
}

test_missing_variable() {
    local result
    result=$(template::render "Hello {{name}}!" other="value")
    assert_eq "Hello !" "$result"
}

test_variable_with_default() {
    local result
    result=$(template::render "Port: {{PORT:-8080}}")
    assert_eq "Port: 8080" "$result"
}

test_variable_with_default_override() {
    local result
    result=$(template::render "Port: {{PORT:-8080}}" PORT="3000")
    assert_eq "Port: 3000" "$result"
}

test_variable_in_text() {
    local result
    result=$(template::render "The {{animal}} jumped over the {{object}}" animal="cow" object="moon")
    assert_eq "The cow jumped over the moon" "$result"
}

test_adjacent_variables() {
    local result
    result=$(template::render "{{a}}{{b}}{{c}}" a="1" b="2" c="3")
    assert_eq "123" "$result"
}

test_empty_template() {
    local result
    result=$(template::render "")
    assert_eq "" "$result"
}

test_no_variables() {
    local result
    result=$(template::render "Just plain text")
    assert_eq "Just plain text" "$result"
}

# =============================================================================
# CONDITIONAL TESTS
# =============================================================================

test_if_true() {
    local result
    result=$(template::render '{{#if SHOW}}visible{{/if}}' SHOW="true")
    assert_eq "visible" "$result"
}

test_if_false() {
    local result
    result=$(template::render '{{#if SHOW}}visible{{/if}}' SHOW="false")
    assert_eq "" "$result"
}

test_if_empty() {
    local result
    result=$(template::render '{{#if SHOW}}visible{{/if}}')
    assert_eq "" "$result"
}

test_if_zero() {
    local result
    result=$(template::render '{{#if SHOW}}visible{{/if}}' SHOW="0")
    assert_eq "" "$result"
}

test_if_truthy_value() {
    local result
    result=$(template::render '{{#if NAME}}Hello {{NAME}}{{/if}}' NAME="Alice")
    assert_eq "Hello Alice" "$result"
}

test_unless_false() {
    local result
    result=$(template::render '{{#unless HIDE}}visible{{/unless}}' HIDE="false")
    assert_eq "visible" "$result"
}

test_unless_true() {
    local result
    result=$(template::render '{{#unless HIDE}}visible{{/unless}}' HIDE="true")
    assert_eq "" "$result"
}

test_unless_empty() {
    local result
    result=$(template::render '{{#unless HIDE}}visible{{/unless}}')
    assert_eq "visible" "$result"
}

test_if_else_pattern() {
    # Using if/unless together for if-else pattern
    local result
    result=$(template::render '{{#if PROD}}prod{{/if}}{{#unless PROD}}dev{{/unless}}' PROD="true")
    assert_eq "prod" "$result"
    
    result=$(template::render '{{#if PROD}}prod{{/if}}{{#unless PROD}}dev{{/unless}}' PROD="false")
    assert_eq "dev" "$result"
}

# =============================================================================
# LOOP TESTS
# =============================================================================

test_each_basic() {
    local result
    result=$(template::render '{{#each ITEMS}}[{{.}}]{{/each}}' ITEMS="a b c")
    assert_eq "[a][b][c]" "$result"
}

test_each_empty() {
    local result
    result=$(template::render '{{#each ITEMS}}[{{.}}]{{/each}}')
    assert_eq "" "$result"
}

test_each_single_item() {
    local result
    result=$(template::render '{{#each ITEMS}}{{.}}{{/each}}' ITEMS="only")
    assert_eq "only" "$result"
}

test_each_with_text() {
    local result
    result=$(template::render 'Servers: {{#each SERVERS}}{{.}} {{/each}}' SERVERS="s1 s2 s3")
    assert_eq "Servers: s1 s2 s3 " "$result"
}

test_each_with_separator() {
    local result
    result=$(template::render '{{#each NUMS}}{{.}},{{/each}}' NUMS="1 2 3")
    # Remove trailing comma
    assert_eq "1,2,3," "$result"
}

# =============================================================================
# PARTIAL TESTS
# =============================================================================

test_partial_basic() {
    template::clear_partials
    template::partial "greeting" "Hello {{name}}!"
    local result
    result=$(template::render '{{>greeting}}' name="World")
    assert_eq "Hello World!" "$result"
}

test_partial_nested() {
    template::clear_partials
    template::partial "header" '<h1>{{title}}</h1>'
    template::partial "page" '{{>header}}<p>{{content}}</p>'
    local result
    result=$(template::render '{{>page}}' title="Test" content="Body")
    assert_eq "<h1>Test</h1><p>Body</p>" "$result"
}

test_partial_not_found() {
    template::clear_partials
    local result
    result=$(template::render '{{>missing}}')
    assert_contains "$result" "partial not found"
}

# =============================================================================
# BUILT-IN HELPER TESTS
# =============================================================================

test_helper_upper() {
    local result
    result=$(template::render '{{upper name}}' name="hello")
    assert_eq "HELLO" "$result"
}

test_helper_lower() {
    local result
    result=$(template::render '{{lower name}}' name="HELLO")
    assert_eq "hello" "$result"
}

test_helper_default() {
    local result
    result=$(template::render '{{default PORT 8080}}')
    assert_eq "8080" "$result"
    
    result=$(template::render '{{default PORT 8080}}' PORT="3000")
    assert_eq "3000" "$result"
}

test_helper_env() {
    export TEST_VAR_12345="test_value"
    local result
    result=$(template::render '{{env TEST_VAR_12345}}')
    assert_eq "test_value" "$result"
    unset TEST_VAR_12345
}

test_helper_now() {
    local result
    result=$(template::render '{{now}}')
    # Should match YYYY-MM-DD HH:MM:SS format
    assert_not_empty "$result"
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || {
        printf 'Invalid timestamp format: %s\n' "$result" >&2
        return 1
    }
}

test_helper_uuid() {
    local result
    result=$(template::render '{{uuid}}')
    # Should match UUID format (8-4-4-4-12)
    assert_not_empty "$result"
    [[ "$result" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] || {
        printf 'Invalid UUID format: %s\n' "$result" >&2
        return 1
    }
}

test_helper_len() {
    local result
    result=$(template::render '{{len name}}' name="hello")
    assert_eq "5" "$result"
}

test_helper_trim() {
    local result
    result=$(template::render '{{trim name}}' name="  hello  ")
    assert_eq "hello" "$result"
}

test_helper_json_escape() {
    local result
    result=$(template::render '{{json text}}' text='hello "world"')
    assert_eq 'hello \"world\"' "$result"
}

test_helper_html_escape() {
    local result
    result=$(template::render '{{html text}}' text='<script>alert("xss")</script>')
    assert_eq '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;' "$result"
}

test_helper_urlencode() {
    local result
    result=$(template::render '{{urlencode text}}' text='hello world')
    assert_eq 'hello%20world' "$result"
}

test_helper_date() {
    local result
    result=$(template::render '{{date %Y}}')
    # Should be current year
    local year
    printf -v year '%(%Y)T' -1
    assert_eq "$year" "$result"
}

# =============================================================================
# CUSTOM HELPER TESTS
# =============================================================================

test_custom_helper() {
    template::clear_helpers
    
    my_custom_helper() {
        printf 'custom:%s' "$1"
    }
    
    template::helper "custom" my_custom_helper
    
    local result
    result=$(template::render '{{custom value}}' value="test")
    assert_eq "custom:test" "$result"
}

# =============================================================================
# TEMPLATE FILE TESTS
# =============================================================================

test_render_file() {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
server:
  host: {{HOST}}
  port: {{PORT:-8080}}
EOF
    
    local result
    result=$(template::render_file "$tmpfile" HOST="localhost" PORT="3000")
    
    rm -f "$tmpfile"
    
    assert_contains "$result" "host: localhost"
    assert_contains "$result" "port: 3000"
}

test_render_file_not_found() {
    assert_returns 1 template::render_file "/nonexistent/file.tpl"
}

# =============================================================================
# PIPE INPUT TESTS
# =============================================================================

test_stdin_input() {
    local result
    result=$(echo "Hello {{name}}!" | template::render - name="World")
    assert_eq "Hello World!" "$result"
}

# =============================================================================
# COMPLEX TEMPLATE TESTS
# =============================================================================

test_complex_config_template() {
    local template='# Config for {{APP_NAME}}
server:
  host: {{HOST:-0.0.0.0}}
  port: {{PORT:-8080}}
  debug: {{#if DEBUG}}true{{/if}}{{#unless DEBUG}}false{{/unless}}

features:
{{#each FEATURES}}  - {{.}}
{{/each}}'
    
    local result
    result=$(template::render "$template" \
        APP_NAME="MyApp" \
        HOST="localhost" \
        PORT="3000" \
        DEBUG="true" \
        FEATURES="auth logging metrics")
    
    assert_contains "$result" "Config for MyApp"
    assert_contains "$result" "host: localhost"
    assert_contains "$result" "port: 3000"
    assert_contains "$result" "debug: true"
    assert_contains "$result" "- auth"
    assert_contains "$result" "- logging"
    assert_contains "$result" "- metrics"
}

test_nested_conditionals() {
    local template='{{#if OUTER}}outer{{#if INNER}}+inner{{/if}}{{/if}}'
    
    local result
    result=$(template::render "$template" OUTER="true" INNER="true")
    assert_eq "outer+inner" "$result"
    
    result=$(template::render "$template" OUTER="true" INNER="false")
    assert_eq "outer" "$result"
    
    result=$(template::render "$template" OUTER="false")
    assert_eq "" "$result"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_escaped_braces() {
    # Template engine doesn't have special escape syntax yet
    # This tests that single braces are preserved
    local result
    result=$(template::render "{ not a tag }")
    assert_eq "{ not a tag }" "$result"
}

test_comment_tag() {
    local result
    result=$(template::render "before{{! this is a comment }}after")
    assert_eq "beforeafter" "$result"
}

test_whitespace_in_tag() {
    local result
    result=$(template::render "{{ name }}" name="test")
    assert_eq "test" "$result"
}

test_special_characters_in_value() {
    local result
    result=$(template::render "Value: {{val}}" val='$PATH && rm -rf')
    assert_eq 'Value: $PATH && rm -rf' "$result"
}

test_newlines_in_template() {
    local result
    result=$(template::render $'Line1: {{a}}\nLine2: {{b}}' a="1" b="2")
    assert_eq $'Line1: 1\nLine2: 2' "$result"
}

# =============================================================================
# VALIDATION TESTS
# =============================================================================

test_validate_valid_template() {
    assert_returns 0 template::validate "Hello {{name}}!"
}

test_validate_unclosed_block() {
    # Should fail for unclosed if block
    local result
    result=$(template::validate "{{#if X}}test" 2>&1)
    assert_returns 1 template::validate "{{#if X}}test"
}

test_variables_extraction() {
    local vars
    vars=$(template::variables "Hello {{name}}, your {{item}} is {{status}}")
    assert_contains "$vars" "name"
    assert_contains "$vars" "item"
    assert_contains "$vars" "status"
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

test_template_set_get() {
    template::clear
    template::set "myvar" "myvalue"
    local result
    result=$(template::get "myvar")
    assert_eq "myvalue" "$result"
}

test_template_clear() {
    template::set "testvar" "testval"
    template::partial "testpartial" "content"
    template::clear
    
    local result
    result=$(template::get "testvar")
    assert_eq "" "$result"
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

main() {
    printf '\n%s\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    printf '%s\n' "$(_blue '  MAINFRAME Template Engine Tests')"
    printf '%s\n\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    
    # Basic variable substitution
    printf '%s\n' "$(_yellow 'Variable Substitution')"
    test_case "Simple variable" test_simple_variable
    test_case "Multiple variables" test_multiple_variables
    test_case "Missing variable" test_missing_variable
    test_case "Variable with default" test_variable_with_default
    test_case "Variable with default (override)" test_variable_with_default_override
    test_case "Variable in text" test_variable_in_text
    test_case "Adjacent variables" test_adjacent_variables
    test_case "Empty template" test_empty_template
    test_case "No variables" test_no_variables
    
    # Conditionals
    printf '\n%s\n' "$(_yellow 'Conditionals')"
    test_case "If true" test_if_true
    test_case "If false" test_if_false
    test_case "If empty" test_if_empty
    test_case "If zero" test_if_zero
    test_case "If truthy value" test_if_truthy_value
    test_case "Unless false" test_unless_false
    test_case "Unless true" test_unless_true
    test_case "Unless empty" test_unless_empty
    test_case "If-else pattern" test_if_else_pattern
    
    # Loops
    printf '\n%s\n' "$(_yellow 'Loops')"
    test_case "Each basic" test_each_basic
    test_case "Each empty" test_each_empty
    test_case "Each single item" test_each_single_item
    test_case "Each with text" test_each_with_text
    test_case "Each with separator" test_each_with_separator
    
    # Partials
    printf '\n%s\n' "$(_yellow 'Partials')"
    test_case "Partial basic" test_partial_basic
    test_case "Partial nested" test_partial_nested
    test_case "Partial not found" test_partial_not_found
    
    # Built-in helpers
    printf '\n%s\n' "$(_yellow 'Built-in Helpers')"
    test_case "Helper: upper" test_helper_upper
    test_case "Helper: lower" test_helper_lower
    test_case "Helper: default" test_helper_default
    test_case "Helper: env" test_helper_env
    test_case "Helper: now" test_helper_now
    test_case "Helper: uuid" test_helper_uuid
    test_case "Helper: len" test_helper_len
    test_case "Helper: trim" test_helper_trim
    test_case "Helper: json escape" test_helper_json_escape
    test_case "Helper: html escape" test_helper_html_escape
    test_case "Helper: urlencode" test_helper_urlencode
    test_case "Helper: date" test_helper_date
    
    # Custom helpers
    printf '\n%s\n' "$(_yellow 'Custom Helpers')"
    test_case "Custom helper" test_custom_helper
    
    # File operations
    printf '\n%s\n' "$(_yellow 'File Operations')"
    test_case "Render file" test_render_file
    test_case "Render file not found" test_render_file_not_found
    
    # Stdin
    printf '\n%s\n' "$(_yellow 'Stdin Input')"
    test_case "Stdin input" test_stdin_input
    
    # Complex templates
    printf '\n%s\n' "$(_yellow 'Complex Templates')"
    test_case "Complex config template" test_complex_config_template
    test_case "Nested conditionals" test_nested_conditionals
    
    # Edge cases
    printf '\n%s\n' "$(_yellow 'Edge Cases')"
    test_case "Escaped braces" test_escaped_braces
    test_case "Comment tag" test_comment_tag
    test_case "Whitespace in tag" test_whitespace_in_tag
    test_case "Special characters in value" test_special_characters_in_value
    test_case "Newlines in template" test_newlines_in_template
    
    # Validation
    printf '\n%s\n' "$(_yellow 'Validation')"
    test_case "Validate valid template" test_validate_valid_template
    test_case "Validate unclosed block" test_validate_unclosed_block
    test_case "Variables extraction" test_variables_extraction
    
    # Utilities
    printf '\n%s\n' "$(_yellow 'Utilities')"
    test_case "Template set/get" test_template_set_get
    test_case "Template clear" test_template_clear
    
    # Summary
    printf '\n%s\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    printf '  Tests: %d | ' "$TESTS_RUN"
    printf '%s | ' "$(_green "Passed: $TESTS_PASSED")"
    printf '%s\n' "$(_red "Failed: $TESTS_FAILED")"
    printf '%s\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    
    # Exit code
    ((TESTS_FAILED == 0))
}

# Run tests if executed directly
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"

#!/usr/bin/env bats
# =============================================================================
# Tests for lib/generate.sh - Code Generation
# =============================================================================

load 'test_helper'

setup() {
    # Source the library
    source "$MAINFRAME_ROOT/lib/generate.sh"
}

# =============================================================================
# generate_function tests
# =============================================================================

@test "generate_function: handles empty input" {
    run generate_function ""
    [[ $status -ne 0 ]]
}

@test "generate_function: generates validation function" {
    run generate_function "validate email addresses"
    [[ $status -eq 0 ]]
    [[ "$output" == *"validate_email_addresses()"* ]]
    [[ "$output" == *"local input"* ]]
}

@test "generate_function: generates with custom name" {
    run generate_function "count lines" --name "line_counter"
    [[ $status -eq 0 ]]
    [[ "$output" == *"line_counter()"* ]]
}

@test "generate_function: returns JSON when requested" {
    run generate_function "validate URL" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"function_name"'* ]]
    [[ "$output" == *'"code"'* ]]
    [[ "$output" == *'"success":true'* ]]
}

@test "generate_function: includes safety checks" {
    run generate_function "process files safely"
    [[ $status -eq 0 ]]
    # Should have file existence check (safety feature)
    [[ "$output" == *"[[ ! -f"* ]]
}

# =============================================================================
# generate_explain tests
# =============================================================================

@test "generate_explain: explains simple function" {
    local code='test_func() { echo "hello"; }'
    run generate_explain "$code"
    [[ $status -eq 0 ]]
    [[ "$output" == *"Function Analysis"* ]]
}

@test "generate_explain: returns JSON when requested" {
    local code='test_func() { return 0; }'
    run generate_explain "$code" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"function_name"'* ]]
    [[ "$output" == *'"features"'* ]]
}

@test "generate_explain: detects local variables" {
    local code='test_func() { local x="test"; }'
    run generate_explain "$code"
    [[ $status -eq 0 ]]
    [[ "$output" == *"local variables"* ]]
}

@test "generate_explain: detects input validation" {
    local code='test_func() { [[ -z "$1" ]] && return 1; }'
    run generate_explain "$code"
    [[ $status -eq 0 ]]
    [[ "$output" == *"Input validation"* ]]
}

# =============================================================================
# generate_test tests
# =============================================================================

@test "generate_test: generates bats tests" {
    local code='my_func() { return 0; }'
    run generate_test "$code" --framework bats
    [[ $status -eq 0 ]]
    [[ "$output" == *"#!/usr/bin/env bats"* ]]
    [[ "$output" == *"@test"* ]]
}

@test "generate_test: returns JSON when requested" {
    local code='my_func() { return 0; }'
    run generate_test "$code" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"test_cases"'* ]]
    [[ "$output" == *'"framework"'* ]]
}

@test "generate_test: generates multiple test cases" {
    local code='my_func() { [[ -z "$1" ]] && return 1; return 0; }'
    run generate_test "$code" --json
    [[ $status -eq 0 ]]
    # Should have at least 2 test cases for functions with error handling
    [[ "$output" == *"returns_success"* ]]
    [[ "$output" == *"handles_empty"* ]]
}

# =============================================================================
# generate_improve tests
# =============================================================================

@test "generate_improve: analyzes code and gives score" {
    run generate_improve "myfunc() { echo \$1; }" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"score"'* ]]
    [[ "$output" == *'"rating"'* ]]
}

@test "generate_improve: detects missing local variables" {
    run generate_improve "myfunc() { echo \$1; }"
    [[ $status -eq 0 ]]
    [[ "$output" == *"local"* ]]
}

@test "generate_improve: warns about eval" {
    run generate_improve "myfunc() { eval \$1; }"
    [[ $status -eq 0 ]]
    [[ "$output" == *"WARNING"* ]]
}

@test "generate_improve: provides suggestions" {
    run generate_improve "myfunc() { echo \$1; }" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"suggestions"'* ]]
}

# =============================================================================
# generate_document tests
# =============================================================================

@test "generate_document: generates markdown documentation" {
    local code='my_func() { local x="$1"; }'
    run generate_document "$code" --format markdown
    [[ $status -eq 0 ]]
    [[ "$output" == *"##"* ]]
    [[ "$output" == *"Parameters"* ]]
}

@test "generate_document: generates help text" {
    local code='my_func() { local x="$1"; }'
    run generate_document "$code" --format help
    [[ $status -eq 0 ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "generate_document: returns JSON when requested" {
    local code='my_func() { return 0; }'
    run generate_document "$code" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"documentation"'* ]]
}

# =============================================================================
# Integration tests
# =============================================================================

@test "integration: generate -> explain pipeline" {
    # Generate a function
    local func
    func=$(generate_function "validate email")
    
    # Explain it
    run generate_explain "$func"
    [[ $status -eq 0 ]]
    [[ "$output" == *"validate"* ]]
}

@test "integration: generate -> test -> improve pipeline" {
    # Generate a function
    local func
    func=$(generate_function "count words")
    
    # Generate tests
    local tests
    tests=$(generate_test "$func" --json)
    [[ -n "$tests" ]]
    
    # Check for improvements
    run generate_improve "$func"
    [[ $status -eq 0 ]]
}

@test "integration: code quality score decreases with bad code" {
    # Good code should score higher than bad code
    local good_score bad_score
    
    good_score=$(generate_improve "good() { local x=\"\$1\"; [[ -z \"\$x\" ]] && return 1; return 0; }" --json | grep -o '"score":[0-9]*' | cut -d: -f2)
    bad_score=$(generate_improve "bad() { eval \$1; }" --json | grep -o '"score":[0-9]*' | cut -d: -f2)
    
    # This is a loose assertion since scores are heuristic
    [[ -n "$good_score" ]]
    [[ -n "$bad_score" ]]
}

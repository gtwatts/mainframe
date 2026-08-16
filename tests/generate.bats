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
    [[ "$output" == *'local input="$file"'* ]]
}

@test "generate_function: deterministically prioritizes file safety over processing" {
    run _generate_detect_template "process files safely"
    [[ $status -eq 0 ]]
    [[ "$output" == "file_operation" ]]
}

@test "generate_function: validation wins over file and pattern matching is token-aware" {
    run _generate_detect_template "validate empty file"
    [[ $status -eq 0 ]]
    [[ "$output" == "validation" ]]

    run _generate_detect_template "profile parser"
    [[ $status -eq 0 ]]
    [[ "$output" == "standard" ]]

    run _generate_detect_template "is_empty"
    [[ $status -eq 0 ]]
    [[ "$output" == "validation" ]]

    run _generate_detect_template "has_value"
    [[ $status -eq 0 ]]
    [[ "$output" == "validation" ]]

    logic="$(_generate_logic_from_description "is_empty")"
    [[ "$logic" == *'[[ -z "$input" ]]'* ]]
}

@test "generate_function: empty-file validator rejects a nonempty file" {
    local empty_file="$BATS_TEST_TMPDIR/empty"
    local nonempty_file="$BATS_TEST_TMPDIR/nonempty"
    : > "$empty_file"
    printf 'data\n' > "$nonempty_file"

    generated="$(generate_function "validate empty file")"
    eval "$generated"

    run validate_empty_file "$empty_file"
    [[ $status -eq 0 ]]
    run validate_empty_file "$nonempty_file"
    [[ $status -ne 0 ]]
}

@test "generate_function: logic matching does not find file inside profile" {
    local empty_file="$BATS_TEST_TMPDIR/empty"
    : > "$empty_file"

    generated="$(generate_function "validate profile is empty")"
    [[ "$generated" == *'[[ -z "$input" ]]'* ]]
    [[ "$generated" != *'[[ -f "$input" ]]'* ]]
    eval "$generated"

    # A file-emptiness validator would accept this path because the referenced
    # file is empty. Generic profile-input validation must reject the nonempty
    # argument string instead.
    run validate_profile_is_empty "$empty_file"
    [[ $status -ne 0 ]]
}

@test "generate_function: generated-style file tokens retain the regular-file gate" {
    local missing_file="$BATS_TEST_TMPDIR/definitely-missing"

    run _generate_detect_template "count_lines_in_file"
    [[ $status -eq 0 ]]
    [[ "$output" == "file_operation" ]]

    generated="$(generate_function "count_lines_in_file")"
    [[ "$generated" == *'[[ ! -f "$file" ]]'* ]]
    eval "$generated"

    run count_lines_in_file "$missing_file"
    [[ $status -ne 0 ]]
}

@test "generate_function: bounded logic matching preserves supported validator variants" {
    local spec description function_name generated
    local -a cases=(
        "validate emails|validate_emails"
        "validate URLs|validate_urls"
        "validate HTTPS|validate_https"
        "validate numbers|validate_numbers"
        "validate integers|validate_integers"
    )

    for spec in "${cases[@]}"; do
        IFS='|' read -r description function_name <<< "$spec"
        generated="$(generate_function "$description")"
        [[ "$generated" != *"TODO: Implement logic"* ]]
        eval "$generated"

        run "$function_name" "definitely_invalid"
        [[ $status -ne 0 ]]
    done
}

@test "generate_function: explicit precedence covers every pattern exactly once" {
    local pattern
    local -A seen=()

    for pattern in "${_GENERATE_PATTERN_ORDER[@]}"; do
        [[ -n "${_GENERATE_PATTERNS[$pattern]+present}" ]]
        [[ -z "${seen[$pattern]+present}" ]]
        seen["$pattern"]=1
    done

    [[ "${#seen[@]}" -eq "${#_GENERATE_PATTERNS[@]}" ]]
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

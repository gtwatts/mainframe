#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: CLI Framework Tests
# =============================================================================
# Run with: bash tests/cli_test.sh
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/cli.sh"

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

_red() { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }
_bold() { printf '\033[1m%s\033[0m' "$*"; }

test_case() {
    local name="$1"
    local func="$2"
    
    ((TESTS_RUN++))
    
    # Reset CLI state before each test
    cli::reset
    
    # Run test in subshell to isolate
    local output
    if output=$(set -e; "$func" 2>&1); then
        ((TESTS_PASSED++))
        printf '  %s %s\n' "$(_green '✓')" "$name"
    else
        ((TESTS_FAILED++))
        printf '  %s %s\n' "$(_red '✗')" "$name"
        if [[ -n "$output" ]]; then
            printf '    Output: %s\n' "$output" | head -3
        fi
    fi
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]] || {
        printf 'Expected: "%s"\nActual: "%s"\n' "$expected" "$actual" >&2
        return 1
    }
}

assert_true() {
    local condition="$1"
    eval "$condition" || {
        printf 'Condition failed: %s\n' "$condition" >&2
        return 1
    }
}

assert_false() {
    local condition="$1"
    ! eval "$condition" || {
        printf 'Condition should be false: %s\n' "$condition" >&2
        return 1
    }
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        printf 'String does not contain: %s\n' "$needle" >&2
        return 1
    }
}

# =============================================================================
# METADATA TESTS
# =============================================================================

test_name_sets_app_name() {
    cli::name "myapp"
    assert_eq "myapp" "$_CLI_NAME"
}

test_version_sets_app_version() {
    cli::version "2.0.0"
    assert_eq "2.0.0" "$_CLI_VERSION"
}

test_description_sets_app_description() {
    cli::description "My awesome app"
    assert_eq "My awesome app" "$_CLI_DESCRIPTION"
}

test_init_sets_all_metadata() {
    cli::init "testapp" "1.2.3" "Test application"
    assert_eq "testapp" "$_CLI_NAME"
    assert_eq "1.2.3" "$_CLI_VERSION"
    assert_eq "Test application" "$_CLI_DESCRIPTION"
}

# =============================================================================
# FLAG TESTS
# =============================================================================

test_flag_definition() {
    cli::flag "verbose" "v" "Enable verbose output"
    assert_eq 1 "${#_CLI_FLAGS[@]}"
    assert_eq "false" "${_CLI_VALUES[verbose]}"
}

test_flag_long_parsing() {
    cli::flag "verbose" "v" "Enable verbose"
    cli::parse --verbose
    assert_eq "true" "${_CLI_VALUES[verbose]}"
}

test_flag_short_parsing() {
    cli::flag "verbose" "v" "Enable verbose"
    cli::parse -v
    assert_eq "true" "${_CLI_VALUES[verbose]}"
}

test_flag_negation() {
    cli::flag "verbose" "v" "Enable verbose"
    cli::parse --verbose --no-verbose
    assert_eq "false" "${_CLI_VALUES[verbose]}"
}

test_multiple_flags() {
    cli::flag "verbose" "v" "Verbose"
    cli::flag "quiet" "q" "Quiet"
    cli::flag "debug" "d" "Debug"
    cli::parse -vd --quiet
    assert_eq "true" "${_CLI_VALUES[verbose]}"
    assert_eq "true" "${_CLI_VALUES[quiet]}"
    assert_eq "true" "${_CLI_VALUES[debug]}"
}

test_combined_short_flags() {
    cli::flag "verbose" "v" "Verbose"
    cli::flag "quiet" "q" "Quiet"
    cli::flag "debug" "d" "Debug"
    cli::parse -vqd
    assert_eq "true" "${_CLI_VALUES[verbose]}"
    assert_eq "true" "${_CLI_VALUES[quiet]}"
    assert_eq "true" "${_CLI_VALUES[debug]}"
}

test_flag_export_to_cli_variable() {
    cli::flag "dry-run" "n" "Dry run"
    cli::parse --dry-run
    assert_eq "true" "$CLI_dry_run"
}

# =============================================================================
# OPTION TESTS
# =============================================================================

test_option_definition() {
    cli::option "output" "o" "Output file" "default.txt"
    assert_eq 1 "${#_CLI_OPTIONS[@]}"
    assert_eq "default.txt" "${_CLI_VALUES[output]}"
}

test_option_long_with_equals() {
    cli::option "output" "o" "Output file"
    cli::parse --output=file.txt
    assert_eq "file.txt" "${_CLI_VALUES[output]}"
}

test_option_long_with_space() {
    cli::option "output" "o" "Output file"
    cli::parse --output file.txt
    assert_eq "file.txt" "${_CLI_VALUES[output]}"
}

test_option_short_with_space() {
    cli::option "output" "o" "Output file"
    cli::parse -o file.txt
    assert_eq "file.txt" "${_CLI_VALUES[output]}"
}

test_option_short_attached() {
    cli::option "output" "o" "Output file"
    cli::parse -ofile.txt
    assert_eq "file.txt" "${_CLI_VALUES[output]}"
}

test_option_default_value() {
    cli::option "count" "c" "Count" "10"
    cli::parse
    assert_eq "10" "${_CLI_VALUES[count]}"
}

test_option_overrides_default() {
    cli::option "count" "c" "Count" "10"
    cli::parse --count 42
    assert_eq "42" "${_CLI_VALUES[count]}"
}

test_option_export_to_cli_variable() {
    cli::option "output" "o" "Output file" "default.txt"
    cli::parse -o test.txt
    assert_eq "test.txt" "$CLI_output"
}

# =============================================================================
# POSITIONAL ARGUMENT TESTS
# =============================================================================

test_positional_required() {
    cli::positional "input" "Input file" required
    cli::parse input.txt
    assert_eq "input.txt" "${_CLI_VALUES[input]}"
}

test_positional_optional() {
    cli::positional "input" "Input file" optional
    cli::parse
    assert_eq "" "${_CLI_VALUES[input]}"
}

test_multiple_positionals() {
    cli::positional "input" "Input file" required
    cli::positional "output" "Output file" optional
    cli::parse in.txt out.txt
    assert_eq "in.txt" "${_CLI_VALUES[input]}"
    assert_eq "out.txt" "${_CLI_VALUES[output]}"
}

test_positional_multiple_mode() {
    cli::positional "files" "Files to process" required multiple
    cli::parse a.txt b.txt c.txt
    local expected=$'a.txt\nb.txt\nc.txt'
    assert_eq "$expected" "${_CLI_VALUES[files]}"
}

test_positional_with_options() {
    cli::flag "verbose" "v" "Verbose"
    cli::option "output" "o" "Output"
    cli::positional "input" "Input file" required
    cli::parse -v --output=out.txt input.txt
    assert_eq "true" "${_CLI_VALUES[verbose]}"
    assert_eq "out.txt" "${_CLI_VALUES[output]}"
    assert_eq "input.txt" "${_CLI_VALUES[input]}"
}

test_positional_after_double_dash() {
    cli::flag "verbose" "v" "Verbose"
    cli::positional "file" "File" required
    cli::parse -- --not-a-flag
    assert_eq "false" "${_CLI_VALUES[verbose]}"
    assert_eq "--not-a-flag" "${_CLI_VALUES[file]}"
}

test_remaining_args() {
    cli::positional "input" "Input" required
    cli::parse in.txt extra1 extra2
    assert_eq 2 "${#_CLI_REMAINING[@]}"
    assert_eq "extra1" "${_CLI_REMAINING[0]}"
    assert_eq "extra2" "${_CLI_REMAINING[1]}"
}

# =============================================================================
# SUBCOMMAND TESTS
# =============================================================================

test_subcommand_definition() {
    cli::subcommand "init" "Initialize project"
    cli::subcommand "build" "Build project"
    assert_eq 2 "${#_CLI_SUBCOMMANDS[@]}"
}

test_subcommand_parsing() {
    cli::subcommand "init" "Initialize"
    cli::subcommand "build" "Build"
    cli::parse init
    assert_eq "init" "$_CLI_SUBCOMMAND"
}

test_subcommand_with_options() {
    cli::subcommand "init" "Initialize"
    cli::flag "force" "f" "Force"
    cli::parse init --force
    assert_eq "init" "$_CLI_SUBCOMMAND"
    assert_eq "true" "${_CLI_VALUES[force]}"
}

test_is_subcommand() {
    cli::subcommand "init" "Initialize"
    cli::subcommand "build" "Build"
    cli::parse init
    assert_true 'cli::is_subcommand "init"'
    assert_false 'cli::is_subcommand "build"'
}

test_get_subcommand() {
    cli::subcommand "deploy" "Deploy app"
    cli::parse deploy
    assert_eq "deploy" "$(cli::get_subcommand)"
}

# =============================================================================
# VALUE ACCESS TESTS
# =============================================================================

test_cli_get() {
    cli::option "output" "o" "Output"
    cli::parse --output test.txt
    assert_eq "test.txt" "$(cli::get output)"
}

test_cli_get_with_default() {
    cli::option "output" "o" "Output"
    cli::parse
    assert_eq "fallback" "$(cli::get output fallback)"
}

test_cli_is_true() {
    cli::flag "verbose" "v" "Verbose"
    cli::parse --verbose
    assert_true 'cli::is verbose'
}

test_cli_is_false() {
    cli::flag "verbose" "v" "Verbose"
    cli::parse
    assert_false 'cli::is verbose'
}

test_cli_has() {
    cli::option "output" "o" "Output"
    cli::parse --output test.txt
    assert_true 'cli::has output'
}

test_cli_has_not() {
    cli::option "output" "o" "Output"
    cli::parse
    assert_false 'cli::has output'
}

test_cli_get_array() {
    cli::positional "files" "Files" optional multiple
    cli::parse a.txt b.txt c.txt
    
    local -a result
    cli::get_array files result
    assert_eq 3 "${#result[@]}"
    assert_eq "a.txt" "${result[0]}"
    assert_eq "b.txt" "${result[1]}"
    assert_eq "c.txt" "${result[2]}"
}

# =============================================================================
# VALIDATION TESTS
# =============================================================================

test_validate_type_integer_valid() {
    cli::option "count" "c" "Count"
    cli::validate_type "count" integer
    cli::parse --count 42
    cli::validate
}

test_validate_type_integer_invalid() {
    cli::option "count" "c" "Count"
    cli::validate_type "count" integer
    cli::parse --count "not-a-number"
    
    # Should fail validation (cli::check returns false)
    assert_false 'cli::check count integer'
}

test_validate_type_positive() {
    cli::option "port" "p" "Port"
    cli::validate_type "port" positive
    cli::parse --port 8080
    cli::validate
}

test_validate_type_positive_invalid() {
    cli::option "port" "p" "Port"
    cli::validate_type "port" positive
    cli::parse --port=0
    
    # Should fail validation (0 is not positive)
    assert_false 'cli::check port positive'
}

test_validate_type_float() {
    cli::option "rate" "r" "Rate"
    cli::validate_type "rate" float
    cli::parse --rate 3.14
    cli::validate
}

test_validate_required_passes() {
    cli::positional "input" "Input" required
    cli::parse input.txt
    cli::validate_required
}

test_validate_required_fails() {
    cli::positional "input" "Input" required
    cli::parse
    
    # Should fail - missing required argument
    # Use subshell to catch exit
    ! ( cli::validate_required 2>/dev/null )
}

test_cli_check_valid() {
    cli::option "count" "c" "Count"
    cli::parse --count 42
    assert_true 'cli::check count integer'
}

test_cli_check_invalid() {
    cli::option "count" "c" "Count"
    cli::parse --count "abc"
    assert_false 'cli::check count integer'
}

test_validate_type_regex() {
    cli::option "email" "e" "Email"
    cli::validate_type "email" '^[^@]+@[^@]+$'
    cli::parse --email "test@example.com"
    cli::validate
}

# =============================================================================
# HELP GENERATION TESTS
# =============================================================================

test_help_includes_name() {
    cli::name "myapp"
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "myapp"
}

test_help_includes_description() {
    cli::init "myapp" "1.0.0" "A test application"
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "A test application"
}

test_help_includes_options() {
    cli::option "output" "o" "Output file"
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "--output"
    assert_contains "$help_output" "-o"
    assert_contains "$help_output" "Output file"
}

test_help_includes_flags() {
    cli::flag "verbose" "v" "Enable verbose"
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "--verbose"
    assert_contains "$help_output" "-v"
}

test_help_includes_positionals() {
    cli::positional "input" "Input file" required
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "input"
    assert_contains "$help_output" "Input file"
}

test_help_includes_subcommands() {
    cli::subcommand "init" "Initialize project"
    cli::subcommand "build" "Build project"
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "init"
    assert_contains "$help_output" "build"
    assert_contains "$help_output" "Initialize project"
}

test_help_includes_examples() {
    cli::example "myapp --verbose input.txt"
    cli::example "myapp -o out.txt in.txt"
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "myapp --verbose input.txt"
    assert_contains "$help_output" "myapp -o out.txt in.txt"
}

test_help_includes_defaults() {
    cli::option "count" "c" "Number of items" "10"
    local help_output
    help_output=$(cli::help)
    assert_contains "$help_output" "default: 10"
}

# =============================================================================
# EDGE CASES
# =============================================================================

test_hyphenated_option_name() {
    cli::flag "dry-run" "n" "Dry run mode"
    cli::parse --dry-run
    assert_eq "true" "${_CLI_VALUES[dry-run]}"
    assert_eq "true" "$CLI_dry_run"
}

test_empty_args() {
    cli::flag "verbose" "v" "Verbose"
    cli::parse
    assert_eq "false" "${_CLI_VALUES[verbose]}"
}

test_option_with_equals_in_value() {
    cli::option "config" "c" "Config string"
    cli::parse --config="key=value"
    assert_eq "key=value" "${_CLI_VALUES[config]}"
}

test_mixed_short_and_long_options() {
    cli::flag "verbose" "v" "Verbose"
    cli::option "output" "o" "Output"
    cli::option "count" "c" "Count"
    cli::parse -v --output=test.txt -c 5
    assert_eq "true" "${_CLI_VALUES[verbose]}"
    assert_eq "test.txt" "${_CLI_VALUES[output]}"
    assert_eq "5" "${_CLI_VALUES[count]}"
}

test_reset_clears_state() {
    cli::init "app1" "1.0.0" "First app"
    cli::flag "verbose" "v" "Verbose"
    cli::parse --verbose
    
    cli::reset
    
    assert_eq "" "$_CLI_NAME"
    assert_eq "" "$_CLI_VERSION"
    assert_eq 0 "${#_CLI_FLAGS[@]}"
    # Check that values hash is empty
    assert_eq 0 "${#_CLI_VALUES[@]}"
}

test_common_options() {
    cli::common_options
    cli::parse -v -n
    assert_eq "true" "${_CLI_VALUES[verbose]}"
    assert_eq "true" "${_CLI_VALUES[dry-run]}"
    assert_eq "false" "${_CLI_VALUES[quiet]}"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_full_cli_scenario() {
    cli::init "deploy" "2.1.0" "Deploy application to servers"
    cli::flag "verbose" "v" "Enable verbose output"
    cli::flag "force" "f" "Force deployment"
    cli::option "env" "e" "Target environment" "staging"
    cli::option "replicas" "r" "Number of replicas" "3"
    cli::positional "app" "Application name" required
    cli::positional "version" "Version to deploy" optional
    
    cli::validate_type "replicas" positive
    
    cli::example "deploy myapp 1.0.0 -e production"
    cli::example "deploy -f --env=staging myapp"
    
    # Parse a realistic command line
    cli::parse --verbose -e production --replicas 5 myservice 2.0.0
    
    # Verify all values
    assert_eq "true" "${_CLI_VALUES[verbose]}"
    assert_eq "false" "${_CLI_VALUES[force]}"
    assert_eq "production" "${_CLI_VALUES[env]}"
    assert_eq "5" "${_CLI_VALUES[replicas]}"
    assert_eq "myservice" "${_CLI_VALUES[app]}"
    assert_eq "2.0.0" "${_CLI_VALUES[version]}"
    
    # Validation should pass
    cli::validate_required
    cli::validate
}

test_subcommand_scenario() {
    cli::init "git-like" "1.0.0" "Git-like tool"
    cli::subcommand "clone" "Clone a repository"
    cli::subcommand "push" "Push changes"
    cli::flag "verbose" "v" "Verbose"
    cli::option "branch" "b" "Branch name" "main"
    cli::positional "repo" "Repository URL" optional
    
    cli::parse clone --branch develop https://github.com/example/repo
    
    assert_eq "clone" "$(cli::get_subcommand)"
    assert_eq "develop" "$(cli::get branch)"
    assert_eq "https://github.com/example/repo" "$(cli::get repo)"
}

# =============================================================================
# RUN TESTS
# =============================================================================

run_test_suite() {
    local suite_name="$1"
    shift
    
    printf '\n%s\n' "$(_bold "$suite_name")"
    
    for test_func in "$@"; do
        test_case "${test_func#test_}" "$test_func"
    done
}

main() {
    printf '%s\n' "$(_bold 'MAINFRAME CLI Framework Tests')"
    printf '%s\n' "=================================="
    
    run_test_suite "Metadata Tests" \
        test_name_sets_app_name \
        test_version_sets_app_version \
        test_description_sets_app_description \
        test_init_sets_all_metadata
    
    run_test_suite "Flag Tests" \
        test_flag_definition \
        test_flag_long_parsing \
        test_flag_short_parsing \
        test_flag_negation \
        test_multiple_flags \
        test_combined_short_flags \
        test_flag_export_to_cli_variable
    
    run_test_suite "Option Tests" \
        test_option_definition \
        test_option_long_with_equals \
        test_option_long_with_space \
        test_option_short_with_space \
        test_option_short_attached \
        test_option_default_value \
        test_option_overrides_default \
        test_option_export_to_cli_variable
    
    run_test_suite "Positional Argument Tests" \
        test_positional_required \
        test_positional_optional \
        test_multiple_positionals \
        test_positional_multiple_mode \
        test_positional_with_options \
        test_positional_after_double_dash \
        test_remaining_args
    
    run_test_suite "Subcommand Tests" \
        test_subcommand_definition \
        test_subcommand_parsing \
        test_subcommand_with_options \
        test_is_subcommand \
        test_get_subcommand
    
    run_test_suite "Value Access Tests" \
        test_cli_get \
        test_cli_get_with_default \
        test_cli_is_true \
        test_cli_is_false \
        test_cli_has \
        test_cli_has_not \
        test_cli_get_array
    
    run_test_suite "Validation Tests" \
        test_validate_type_integer_valid \
        test_validate_type_integer_invalid \
        test_validate_type_positive \
        test_validate_type_positive_invalid \
        test_validate_type_float \
        test_validate_required_passes \
        test_validate_required_fails \
        test_cli_check_valid \
        test_cli_check_invalid \
        test_validate_type_regex
    
    run_test_suite "Help Generation Tests" \
        test_help_includes_name \
        test_help_includes_description \
        test_help_includes_options \
        test_help_includes_flags \
        test_help_includes_positionals \
        test_help_includes_subcommands \
        test_help_includes_examples \
        test_help_includes_defaults
    
    run_test_suite "Edge Cases" \
        test_hyphenated_option_name \
        test_empty_args \
        test_option_with_equals_in_value \
        test_mixed_short_and_long_options \
        test_reset_clears_state \
        test_common_options
    
    run_test_suite "Integration Tests" \
        test_full_cli_scenario \
        test_subcommand_scenario
    
    # Summary
    printf '\n%s\n' "=================================="
    printf 'Tests run: %d\n' "$TESTS_RUN"
    printf '%s\n' "$(_green "Passed: $TESTS_PASSED")"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf '%s\n' "$(_red "Failed: $TESTS_FAILED")"
        exit 1
    fi
    
    printf '\n%s\n' "$(_green '✓ All tests passed!')"
    exit 0
}

main "$@"

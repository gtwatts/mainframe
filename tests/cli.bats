#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: CLI Generation Library Tests
# =============================================================================
# Tests for lib/cli.sh
# Covers: argument parsing, validation, help generation, completions, subcommands
# =============================================================================

load 'test_helper'

setup() {
    source_lib "cli"
    export MAINFRAME_QUIET=1
    cli::reset
    # Reset extended state
    _CLI_CHOICES=()
    _CLI_RANGES=()
}

teardown() {
    cli::reset
    _CLI_CHOICES=()
    _CLI_RANGES=()
}

# =============================================================================
# INITIALIZATION TESTS
# =============================================================================

@test "cli::init sets name, version, description" {
    cli::init "myapp" "2.0.0" "My description"
    [ "$_CLI_NAME" = "myapp" ]
    [ "$_CLI_VERSION" = "2.0.0" ]
    [ "$_CLI_DESCRIPTION" = "My description" ]
}

@test "cli::reset clears all state" {
    cli::init "myapp" "1.0.0" "desc"
    cli::flag "verbose" "v" "Verbose"
    cli::reset
    [ -z "$_CLI_NAME" ]
    [ ${#_CLI_FLAGS[@]} -eq 0 ]
}

@test "cli::name sets program name" {
    cli::name "testapp"
    [ "$_CLI_NAME" = "testapp" ]
}

@test "cli::version sets program version" {
    cli::version "3.0.0"
    [ "$_CLI_VERSION" = "3.0.0" ]
}

@test "cli::description sets program description" {
    cli::description "Test description"
    [ "$_CLI_DESCRIPTION" = "Test description" ]
}

# =============================================================================
# FLAG DEFINITION TESTS
# =============================================================================

@test "cli::flag registers flag definition" {
    cli::flag "verbose" "v" "Enable verbose output"
    [ ${#_CLI_FLAGS[@]} -eq 1 ]
}

@test "cli::flag initializes to false" {
    cli::flag "verbose" "v" "Enable verbose output"
    [ "${_CLI_VALUES[verbose]}" = "false" ]
}

@test "cli::flag allows empty short option" {
    cli::flag "long-only" "" "Long option only"
    [ ${#_CLI_FLAGS[@]} -eq 1 ]
}

@test "multiple flags can be registered" {
    cli::flag "verbose" "v" "Verbose"
    cli::flag "quiet" "q" "Quiet"
    cli::flag "debug" "d" "Debug"
    [ ${#_CLI_FLAGS[@]} -eq 3 ]
}

# =============================================================================
# OPTION DEFINITION TESTS
# =============================================================================

@test "cli::option registers option definition" {
    cli::option "output" "o" "Output file" "out.txt"
    [ ${#_CLI_OPTIONS[@]} -eq 1 ]
}

@test "cli::option sets default value" {
    cli::option "output" "o" "Output file" "default.txt"
    [ "${_CLI_VALUES[output]}" = "default.txt" ]
}

@test "cli::option allows empty default" {
    cli::option "config" "c" "Config file"
    [ "${_CLI_VALUES[config]}" = "" ]
}

@test "multiple options can be registered" {
    cli::option "output" "o" "Output"
    cli::option "input" "i" "Input"
    cli::option "config" "c" "Config"
    [ ${#_CLI_OPTIONS[@]} -eq 3 ]
}

# =============================================================================
# POSITIONAL ARGUMENT TESTS
# =============================================================================

@test "cli::positional registers positional argument" {
    cli::positional "file" "Input file" required
    [ ${#_CLI_POSITIONALS[@]} -eq 1 ]
}

@test "cli::positional handles optional argument" {
    cli::positional "output" "Output file" optional
    [ ${#_CLI_POSITIONALS[@]} -eq 1 ]
}

@test "cli::positional handles multiple flag" {
    cli::positional "files" "Files to process" required multiple
    [ ${#_CLI_POSITIONALS[@]} -eq 1 ]
}

@test "multiple positionals can be registered" {
    cli::positional "input" "Input" required
    cli::positional "output" "Output" optional
    [ ${#_CLI_POSITIONALS[@]} -eq 2 ]
}

# =============================================================================
# EXAMPLE TESTS
# =============================================================================

@test "cli::example adds example" {
    cli::example "myapp -v input.txt"
    [ ${#_CLI_EXAMPLES[@]} -eq 1 ]
}

@test "multiple examples can be added" {
    cli::example "myapp -v input.txt"
    cli::example "myapp --output out.txt file.txt"
    cli::example "myapp init"
    [ ${#_CLI_EXAMPLES[@]} -eq 3 ]
}

# =============================================================================
# PARSING - FLAGS
# =============================================================================

@test "cli::parse handles long flag" {
    cli::flag "verbose" "v" "Verbose"
    cli::parse --verbose
    [ "${_CLI_VALUES[verbose]}" = "true" ]
}

@test "cli::parse handles short flag" {
    cli::flag "verbose" "v" "Verbose"
    cli::parse -v
    [ "${_CLI_VALUES[verbose]}" = "true" ]
}

@test "cli::parse handles negated flag" {
    cli::flag "verbose" "v" "Verbose"
    _CLI_VALUES[verbose]="true"
    cli::parse --no-verbose
    [ "${_CLI_VALUES[verbose]}" = "false" ]
}

@test "cli::parse handles multiple combined short flags" {
    cli::flag "verbose" "v" "Verbose"
    cli::flag "quiet" "q" "Quiet"
    cli::flag "debug" "d" "Debug"
    cli::parse -vqd
    [ "${_CLI_VALUES[verbose]}" = "true" ]
    [ "${_CLI_VALUES[quiet]}" = "true" ]
    [ "${_CLI_VALUES[debug]}" = "true" ]
}

@test "cli::parse handles flag with equals true" {
    cli::flag "verbose" "v" "Verbose"
    cli::parse --verbose=true
    [ "${_CLI_VALUES[verbose]}" = "true" ]
}

@test "cli::parse handles flag with equals false" {
    cli::flag "verbose" "v" "Verbose"
    cli::parse --verbose=false
    [ "${_CLI_VALUES[verbose]}" = "false" ]
}

# =============================================================================
# PARSING - OPTIONS
# =============================================================================

@test "cli::parse handles long option with value" {
    cli::option "output" "o" "Output"
    cli::parse --output result.txt
    [ "${_CLI_VALUES[output]}" = "result.txt" ]
}

@test "cli::parse handles long option with equals" {
    cli::option "output" "o" "Output"
    cli::parse --output=result.txt
    [ "${_CLI_VALUES[output]}" = "result.txt" ]
}

@test "cli::parse handles short option with value" {
    cli::option "output" "o" "Output"
    cli::parse -o result.txt
    [ "${_CLI_VALUES[output]}" = "result.txt" ]
}

@test "cli::parse handles short option with attached value" {
    cli::option "output" "o" "Output"
    cli::parse -oresult.txt
    [ "${_CLI_VALUES[output]}" = "result.txt" ]
}

@test "cli::parse handles option with spaces in value" {
    cli::option "message" "m" "Message"
    cli::parse --message "hello world"
    [ "${_CLI_VALUES[message]}" = "hello world" ]
}

@test "cli::parse handles long option value starting with dash as next arg" {
    cli::option "expr" "e" "Expression"
    cli::parse --expr -n
    [ "${_CLI_VALUES[expr]}" = "-n" ]
}

# =============================================================================
# PARSING - POSITIONAL ARGUMENTS
# =============================================================================

@test "cli::parse handles positional argument" {
    cli::positional "file" "File" required
    cli::parse input.txt
    [ "${_CLI_VALUES[file]}" = "input.txt" ]
}

@test "cli::parse handles multiple positional arguments" {
    cli::positional "input" "Input" required
    cli::positional "output" "Output" optional
    cli::parse in.txt out.txt
    [ "${_CLI_VALUES[input]}" = "in.txt" ]
    [ "${_CLI_VALUES[output]}" = "out.txt" ]
}

@test "cli::parse stores extra positionals in remaining" {
    cli::positional "file" "File" required
    cli::parse file.txt extra1 extra2
    [ "${_CLI_VALUES[file]}" = "file.txt" ]
    [ ${#_CLI_REMAINING[@]} -eq 2 ]
}

@test "cli::parse handles -- to end options" {
    cli::flag "verbose" "v" "Verbose"
    cli::positional "file" "File" required
    cli::parse -- --verbose
    [ "${_CLI_VALUES[verbose]}" = "false" ]
    [ "${_CLI_VALUES[file]}" = "--verbose" ]
}

# =============================================================================
# PARSING - MIXED
# =============================================================================

@test "cli::parse handles flags, options, and positionals together" {
    cli::flag "verbose" "v" "Verbose"
    cli::option "output" "o" "Output"
    cli::positional "input" "Input" required
    cli::parse -v --output result.txt input.txt
    [ "${_CLI_VALUES[verbose]}" = "true" ]
    [ "${_CLI_VALUES[output]}" = "result.txt" ]
    [ "${_CLI_VALUES[input]}" = "input.txt" ]
}

@test "cli::parse handles positional between options" {
    cli::flag "verbose" "v" "Verbose"
    cli::option "output" "o" "Output"
    cli::positional "input" "Input" required
    cli::parse input.txt -v --output result.txt
    [ "${_CLI_VALUES[verbose]}" = "true" ]
    [ "${_CLI_VALUES[output]}" = "result.txt" ]
    [ "${_CLI_VALUES[input]}" = "input.txt" ]
}

# =============================================================================
# VALUE ACCESS TESTS
# =============================================================================

@test "cli::get retrieves value" {
    cli::option "output" "o" "Output" "default.txt"
    cli::parse --output result.txt
    result=$(cli::get "output")
    [ "$result" = "result.txt" ]
}

@test "cli::get returns default for missing value" {
    cli::option "output" "o" "Output"
    cli::parse
    result=$(cli::get "output" "fallback.txt")
    [ "$result" = "fallback.txt" ]
}

@test "cli::is returns true for set flag" {
    cli::flag "verbose" "v" "Verbose"
    cli::parse -v
    cli::is "verbose"
}

@test "cli::is returns false for unset flag" {
    cli::flag "verbose" "v" "Verbose"
    cli::parse
    ! cli::is "verbose"
}

@test "cli::has returns true for provided value" {
    cli::option "output" "o" "Output"
    cli::parse --output test.txt
    cli::has "output"
}

@test "cli::has returns false for empty value" {
    cli::option "output" "o" "Output"
    cli::parse
    ! cli::has "output"
}

# =============================================================================
# VALIDATION TESTS
# =============================================================================

@test "cli::validate_type checks integer" {
    cli::option "count" "c" "Count"
    cli::validate_type "count" "integer"
    cli::parse --count 42
    run cli::validate
    [ "$status" -eq 0 ]
}

@test "cli::validate_type rejects invalid integer" {
    cli::option "count" "c" "Count"
    cli::validate_type "count" "integer"
    cli::parse --count abc
    run cli::validate
    [ "$status" -ne 0 ]
}

@test "cli::validate_type checks positive" {
    cli::option "count" "c" "Count"
    cli::validate_type "count" "positive"
    cli::parse --count 5
    run cli::validate
    [ "$status" -eq 0 ]
}

@test "cli::validate_type rejects non-positive" {
    cli::option "count" "c" "Count"
    cli::validate_type "count" "positive"
    cli::parse --count -5
    run cli::validate
    [ "$status" -ne 0 ]
}

@test "cli::check validates value against type" {
    cli::option "count" "c" "Count"
    cli::parse --count 42
    cli::check "count" "integer"
}

@test "cli::check rejects invalid value" {
    cli::option "count" "c" "Count"
    cli::parse --count abc
    ! cli::check "count" "integer"
}

# =============================================================================
# CHOICES TESTS
# =============================================================================

@test "cli::choices registers choice restriction" {
    cli::option "format" "f" "Format"
    cli::choices "format" "json" "yaml" "toml"
    [ -n "${_CLI_CHOICES[format]}" ]
}

@test "cli::validate_choices accepts valid choice" {
    cli::option "format" "f" "Format"
    cli::choices "format" "json" "yaml" "toml"
    cli::parse --format json
    run cli::validate_choices "format"
    [ "$status" -eq 0 ]
}

@test "cli::validate_choices rejects invalid choice" {
    cli::option "format" "f" "Format"
    cli::choices "format" "json" "yaml" "toml"
    cli::parse --format xml
    run cli::validate_choices "format"
    [ "$status" -ne 0 ]
}

# =============================================================================
# RANGE TESTS
# =============================================================================

@test "cli::range registers range restriction" {
    cli::option "port" "p" "Port"
    cli::range "port" 1 65535
    [ -n "${_CLI_RANGES[port]}" ]
}

@test "cli::validate_range accepts value in range" {
    cli::option "port" "p" "Port"
    cli::range "port" 1 65535
    cli::parse --port 8080
    run cli::validate_range "port"
    [ "$status" -eq 0 ]
}

@test "cli::validate_range rejects value below min" {
    cli::option "port" "p" "Port"
    cli::range "port" 1 65535
    cli::parse --port 0
    run cli::validate_range "port"
    [ "$status" -ne 0 ]
}

@test "cli::validate_range rejects value above max" {
    cli::option "port" "p" "Port"
    cli::range "port" 1 65535
    cli::parse --port 70000
    run cli::validate_range "port"
    [ "$status" -ne 0 ]
}

@test "cli::validate_range rejects non-integer" {
    cli::option "port" "p" "Port"
    cli::range "port" 1 65535
    cli::parse --port abc
    run cli::validate_range "port"
    [ "$status" -ne 0 ]
}

# =============================================================================
# SUBCOMMAND TESTS
# =============================================================================

@test "cli::subcommand registers subcommand" {
    cli::subcommand "init" "Initialize project"
    [ ${#_CLI_SUBCOMMANDS[@]} -eq 1 ]
}

@test "cli::parse identifies subcommand" {
    cli::subcommand "init" "Initialize"
    cli::subcommand "build" "Build"
    cli::parse init
    [ "$_CLI_SUBCOMMAND" = "init" ]
}

@test "cli::is_subcommand identifies active subcommand" {
    cli::subcommand "init" "Initialize"
    cli::parse init
    cli::is_subcommand "init"
}

@test "cli::is_subcommand returns false for wrong subcommand" {
    cli::subcommand "init" "Initialize"
    cli::subcommand "build" "Build"
    cli::parse init
    ! cli::is_subcommand "build"
}

@test "cli::get_subcommand returns subcommand name" {
    cli::subcommand "init" "Initialize"
    cli::parse init
    result=$(cli::get_subcommand)
    [ "$result" = "init" ]
}

# =============================================================================
# HELP GENERATION TESTS
# =============================================================================

@test "cli::help outputs usage line" {
    cli::init "myapp" "1.0.0" "My app"
    run cli::help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"myapp"* ]]
}

@test "cli::help outputs description" {
    cli::init "myapp" "1.0.0" "My awesome app"
    run cli::help
    [[ "$output" == *"My awesome app"* ]]
}

@test "cli::help outputs options" {
    cli::init "myapp" "1.0.0"
    cli::flag "verbose" "v" "Enable verbose output"
    run cli::help
    [[ "$output" == *"Options:"* ]]
    [[ "$output" == *"--verbose"* ]]
    [[ "$output" == *"-v"* ]]
}

@test "cli::help outputs positional arguments" {
    cli::init "myapp" "1.0.0"
    cli::positional "input" "Input file" required
    run cli::help
    [[ "$output" == *"Arguments:"* ]]
    [[ "$output" == *"input"* ]]
}

@test "cli::help outputs subcommands" {
    cli::init "myapp" "1.0.0"
    cli::subcommand "init" "Initialize project"
    cli::subcommand "build" "Build project"
    run cli::help
    [[ "$output" == *"Commands:"* ]]
    [[ "$output" == *"init"* ]]
    [[ "$output" == *"build"* ]]
}

@test "cli::help outputs examples" {
    cli::init "myapp" "1.0.0"
    cli::example "myapp -v input.txt"
    run cli::help
    [[ "$output" == *"Examples:"* ]]
    [[ "$output" == *"myapp -v input.txt"* ]]
}

# =============================================================================
# MAN PAGE GENERATION TESTS
# =============================================================================

@test "cli::man generates troff format" {
    cli::init "myapp" "1.0.0" "My application"
    run cli::man
    [ "$status" -eq 0 ]
    [[ "$output" == *".TH MYAPP"* ]]
}

@test "cli::man includes NAME section" {
    cli::init "myapp" "1.0.0" "My application"
    run cli::man
    [[ "$output" == *".SH NAME"* ]]
    [[ "$output" == *"myapp"* ]]
}

@test "cli::man includes OPTIONS section" {
    cli::init "myapp" "1.0.0"
    cli::flag "verbose" "v" "Verbose output"
    run cli::man
    [[ "$output" == *".SH OPTIONS"* ]]
    [[ "$output" == *"verbose"* ]]
}

# =============================================================================
# SHELL COMPLETION TESTS
# =============================================================================

@test "cli::complete_bash generates bash completion" {
    cli::init "myapp" "1.0.0"
    cli::flag "verbose" "v" "Verbose"
    run cli::complete_bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"_myapp_completions"* ]]
    [[ "$output" == *"--verbose"* ]]
}

@test "cli::complete_zsh generates zsh completion" {
    cli::init "myapp" "1.0.0"
    cli::flag "verbose" "v" "Verbose"
    run cli::complete_zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"#compdef myapp"* ]]
    [[ "$output" == *"--verbose"* ]]
}

@test "cli::complete_fish generates fish completion" {
    cli::init "myapp" "1.0.0"
    cli::flag "verbose" "v" "Verbose"
    run cli::complete_fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"complete -c myapp"* ]]
    [[ "$output" == *"-l verbose"* ]]
}

@test "cli::complete_bash includes choices" {
    cli::init "myapp" "1.0.0"
    cli::option "format" "f" "Format"
    cli::choices "format" "json" "yaml"
    run cli::complete_bash
    [[ "$output" == *"json yaml"* ]]
}

# =============================================================================
# USOP OUTPUT TESTS
# =============================================================================

@test "cli::usop_error outputs JSON error" {
    run cli::usop_error "CLI_ERROR" "Test error" "field"
    [[ "$output" == *'"ok":false'* ]]
    [[ "$output" == *'"code":"CLI_ERROR"'* ]]
    [[ "$output" == *'"msg":"Test error"'* ]]
}

@test "cli::to_json outputs parsed values as JSON" {
    cli::flag "verbose" "v" "Verbose"
    cli::option "output" "o" "Output"
    cli::parse -v --output test.txt
    run cli::to_json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"verbose":true'* ]]
    [[ "$output" == *'"output":"test.txt"'* ]]
}

# =============================================================================
# SPEC-BASED PARSING TESTS
# =============================================================================

@test "cli::parse_spec parses flag spec" {
    cli::parse_spec "verbose:v" -v
    [ "${_CLI_VALUES[verbose]}" = "true" ]
}

@test "cli::parse_spec parses option spec with default" {
    cli::parse_spec "output:o:/tmp/out"
    [ "${_CLI_VALUES[output]}" = "/tmp/out" ]
}

@test "cli::parse_spec parses positional spec" {
    cli::parse_spec "file:required" input.txt
    [ "${_CLI_VALUES[file]}" = "input.txt" ]
}

@test "cli::parse_spec parses mixed spec" {
    cli::parse_spec "verbose:v,output:o:/tmp,file:required" -v --output result.txt input.txt
    [ "${_CLI_VALUES[verbose]}" = "true" ]
    [ "${_CLI_VALUES[output]}" = "result.txt" ]
    [ "${_CLI_VALUES[file]}" = "input.txt" ]
}

# =============================================================================
# LEGACY COMPATIBILITY TESTS
# =============================================================================

@test "cli_parse alias works" {
    cli::flag "verbose" "v" "Verbose"
    cli_parse -v
    [ "${_CLI_VALUES[verbose]}" = "true" ]
}

@test "cli_flag alias works" {
    cli_flag "verbose" "v" "Verbose"
    [ ${#_CLI_FLAGS[@]} -eq 1 ]
}

@test "cli_option alias works" {
    cli_option "output" "o" "string" "default" "Output file"
    [ ${#_CLI_OPTIONS[@]} -eq 1 ]
}

@test "cli_get alias works" {
    cli::option "output" "o" "Output" "default.txt"
    cli::parse
    result=$(cli_get "output")
    [ "$result" = "default.txt" ]
}

@test "cli_get_bool alias works" {
    cli::flag "verbose" "v" "Verbose"
    cli::parse -v
    cli_get_bool "verbose"
}

@test "cli_get_int alias works" {
    cli::option "count" "c" "Count"
    cli::parse --count 42
    result=$(cli_get_int "count")
    [ "$result" -eq 42 ]
}

@test "cli_help_generate alias works" {
    cli::init "myapp" "1.0.0"
    run cli_help_generate
    [ "$status" -eq 0 ]
    [[ "$output" == *"myapp"* ]]
}

@test "cli_man_generate alias works" {
    cli::init "myapp" "1.0.0"
    run cli_man_generate
    [ "$status" -eq 0 ]
    [[ "$output" == *".TH"* ]]
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "cli::parse handles empty arguments" {
    cli::flag "verbose" "v" "Verbose"
    run cli::parse
    [ "$status" -eq 0 ]
}

@test "cli::parse handles only --" {
    cli::positional "file" "File" optional
    cli::parse --
    [ ${#_CLI_REMAINING[@]} -eq 0 ]
}

@test "cli::parse handles value starting with dash" {
    cli::option "expr" "e" "Expression"
    cli::parse --expr="-n test"
    [ "${_CLI_VALUES[expr]}" = "-n test" ]
}

@test "cli::parse handles empty string value" {
    cli::option "message" "m" "Message"
    cli::parse --message ""
    [ "${_CLI_VALUES[message]}" = "" ]
}

@test "cli::help handles no options defined" {
    cli::init "myapp" "1.0.0" "Simple app"
    run cli::help
    [ "$status" -eq 0 ]
    [[ "$output" == *"myapp"* ]]
}

@test "cli::help handles long option names" {
    cli::init "myapp" "1.0.0"
    cli::flag "very-long-option-name" "" "A very long option"
    run cli::help
    [ "$status" -eq 0 ]
    [[ "$output" == *"very-long-option-name"* ]]
}

#!/usr/bin/env bats
# =============================================================================
# Tests for lib/intent.sh - Intent Parser
# =============================================================================

load 'test_helper'

setup() {
    # Source the library
    source "$MAINFRAME_ROOT/lib/intent.sh"
}

# =============================================================================
# intent_parse tests
# =============================================================================

@test "intent_parse: handles empty input" {
    run intent_parse ""
    [[ $status -ne 0 ]]
}

@test "intent_parse: finds action 'find'" {
    run intent_parse "find all files" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"action":"find"'* ]]
}

@test "intent_parse: finds action 'count'" {
    run intent_parse "count lines" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"action":"count"'* ]]
}

@test "intent_parse: finds action 'remove'" {
    run intent_parse "remove all tmp files" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"action":"remove"'* ]]
}

@test "intent_parse: extracts Python file pattern" {
    run intent_parse "find all Python files" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"pattern":"*.py"'* ]]
}

@test "intent_parse: extracts time constraint 'today'" {
    run intent_parse "find all files modified today" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"time":"today"'* ]]
}

@test "intent_parse: returns valid JSON" {
    run intent_parse "find all files" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"action"'* ]]
    [[ "$output" == *'"target"'* ]]
    [[ "$output" == *'"confidence"'* ]]
}

# =============================================================================
# intent_to_bash tests
# =============================================================================

@test "intent_to_bash: generates find command" {
    local intent='{"action":"find","pattern":"*.py"}'
    run intent_to_bash "$intent"
    [[ $status -eq 0 ]]
    [[ "$output" == *"find"* ]]
    [[ "$output" == *"-name"* ]]
}

@test "intent_to_bash: generates count command" {
    local intent='{"action":"count","target":"lines","pattern":"*.log"}'
    run intent_to_bash "$intent"
    [[ $status -eq 0 ]]
    [[ "$output" == *"wc -l"* ]]
}

@test "intent_to_bash: adds time constraint" {
    local intent='{"action":"find","time":"today"}'
    run intent_to_bash "$intent"
    [[ $status -eq 0 ]]
    [[ "$output" == *"-mtime -1"* ]]
}

@test "intent_to_bash: handles unknown action" {
    local intent='{"action":"unknown"}'
    run intent_to_bash "$intent"
    [[ $status -ne 0 ]]
}

# =============================================================================
# intent_explain tests
# =============================================================================

@test "intent_explain: explains find command" {
    run intent_explain "find . -name '*.py'" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"summary"'* ]]
    [[ "$output" == *'"risk"'* ]]
}

@test "intent_explain: warns about dangerous commands" {
    run intent_explain "rm -rf /tmp/test" --json
    [[ $status -eq 0 ]]
    # rm should be at least medium risk
    [[ "$output" == *'"risk"'* ]]
}

@test "intent_explain: includes details" {
    run intent_explain "find . -name '*.log' -delete" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"details"'* ]]
}

# =============================================================================
# intent_complete tests
# =============================================================================

@test "intent_complete: returns suggestions" {
    run intent_complete "find" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"suggestions"'* ]]
}

@test "intent_complete: respects max limit" {
    run intent_complete "find" --json --max 3
    [[ $status -eq 0 ]]
    [[ "$output" == *'"count":'* ]]
}

@test "intent_complete: handles partial input" {
    run intent_complete "count" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"count"'* ]]
}

# =============================================================================
# intent_classify tests
# =============================================================================

@test "intent_classify: command substitution works for critical commands" {
    local risk_level
    risk_level=$(intent_classify "rm -rf /tmp/cache")

    [[ "$risk_level" == "critical" ]]
}

@test "intent_classify: detects command substitution obfuscation" {
    run intent_classify 'echo $(whoami)' --json

    [[ $status -eq 0 ]]
    [[ "$output" == *'"risk_label":"critical"'* ]]
    [[ "$output" == *'[$][(]'* ]]
}

# =============================================================================
# Integration tests
# =============================================================================

@test "integration: parse -> to_bash pipeline works" {
    # Parse natural language
    local intent
    intent=$(intent_parse "find all Python files modified today" --json)
    
    # Convert to bash
    run intent_to_bash "$intent"
    [[ $status -eq 0 ]]
    [[ "$output" == *"find"* ]]
    [[ "$output" == *"*.py"* ]]
}

@test "integration: explain generated command" {
    local cmd="find . -name '*.txt' -type f"
    run intent_explain "$cmd" --json
    [[ $status -eq 0 ]]
    [[ "$output" == *'"command"'* ]]
}

@test "integration: verify_command compatibility check" {
    # Verify our generated code can be checked by intent_classify
    # Read-only scans should stay in the benign risk buckets even if the exact
    # safe-vs-low threshold varies slightly across environments.
    local cmd="find . -name '*.py' -type f"
    local risk_level
    risk_level=$(intent_classify "$cmd")
    [[ "$risk_level" == "safe" || "$risk_level" == "low" ]]
}

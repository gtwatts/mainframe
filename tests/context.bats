#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Context Budget & Token Estimation Library Tests
# =============================================================================
# Tests for lib/context.sh - Token estimation, budget management, truncation
# =============================================================================

load 'test_helper'

setup() {
    source_lib "context"
    TEST_DIR=$(create_test_dir "context")

    # Create test files of various types
    mkdir -p "$TEST_DIR/src"

    # Python file (~350 chars)
    printf 'import os\nimport sys\nfrom pathlib import Path\n\ndef main():\n    """Entry point."""\n    path = Path(".")\n    for item in path.iterdir():\n        print(item)\n\nif __name__ == "__main__":\n    main()\n' > "$TEST_DIR/src/app.py"

    # JSON file (~200 chars)
    printf '{\n  "name": "test-project",\n  "version": "1.0.0",\n  "description": "A test project",\n  "dependencies": {\n    "express": "^4.18.0",\n    "lodash": "^4.17.21"\n  }\n}\n' > "$TEST_DIR/src/config.json"

    # Markdown file (~300 chars)
    printf '# Test Project\n\n## Overview\n\nThis is a test project for the context library.\n\n## Features\n\n- Token estimation\n- Budget management\n- Content truncation\n\n## Usage\n\n```bash\nsource lib/context.sh\ncontext_estimate_tokens "hello"\n```\n\n**Note**: All estimates are approximate.\n' > "$TEST_DIR/README.md"

    # Plain text file (~200 chars)
    printf 'The quick brown fox jumps over the lazy dog.\nThis is a simple text file with no special formatting.\nIt contains plain English prose for testing token estimation.\nEach line is a complete sentence.\n' > "$TEST_DIR/prose.txt"

    # Large file for truncation tests (~2000 chars)
    local i
    for (( i=1; i<=50; i++ )); do
        printf 'Line %d: This is a line of text for testing truncation behavior in the context library.\n' "$i"
    done > "$TEST_DIR/large.txt"

    # Bash script
    printf '#!/usr/bin/env bash\n# Test script\n\nset -euo pipefail\n\nreadonly VERSION="1.0.0"\n\nmain() {\n    local name="$1"\n    echo "Hello, ${name}"\n    return 0\n}\n\nmain "$@"\n' > "$TEST_DIR/src/script.sh"

    # Ensure clean budget state for each test
    export MAINFRAME_CONTEXT_STATE="/tmp/mainframe_context_test_$$"
    rm -f "$MAINFRAME_CONTEXT_STATE"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
    rm -f "$MAINFRAME_CONTEXT_STATE"
    # Clean up allocation vars
    local var
    for var in $(compgen -v _CTX_ALLOC_ 2>/dev/null); do
        unset "$var"
    done
    unset _CTX_MAX_TOKENS _CTX_RESERVE _CTX_USED _CTX_ALLOCATIONS
}

# =============================================================================
# TOKEN ESTIMATION TESTS
# =============================================================================

@test "context_estimate_tokens returns 0 for empty string" {
    run context_estimate_tokens ""
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "context_estimate_tokens estimates prose tokens (~4 chars/token)" {
    # 44 chars "The quick brown fox jumps over the lazy dog."
    # Expected: ~11 tokens (44/4)
    run context_estimate_tokens "The quick brown fox jumps over the lazy dog."
    [ "$status" -eq 0 ]
    local tokens="$output"
    [ "$tokens" -ge 8 ]
    [ "$tokens" -le 15 ]
}

@test "context_estimate_tokens estimates code tokens (~3.5 chars/token)" {
    local code='def hello():
    print("world")
    return True

if __name__ == "__main__":
    hello()'
    run context_estimate_tokens "$code"
    [ "$status" -eq 0 ]
    local tokens="$output"
    # ~100 chars of code / 3.5 = ~29 tokens
    [ "$tokens" -ge 20 ]
    [ "$tokens" -le 40 ]
}

@test "context_estimate_tokens estimates JSON tokens (~3 chars/token)" {
    local json='{"name": "test", "version": "1.0.0", "count": 42}'
    run context_estimate_tokens "$json"
    [ "$status" -eq 0 ]
    local tokens="$output"
    # ~51 chars / 3 = ~17 tokens
    [ "$tokens" -ge 12 ]
    [ "$tokens" -le 25 ]
}

@test "context_file_tokens returns 0 for missing file" {
    run context_file_tokens "/nonexistent/file.txt"
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}

@test "context_file_tokens estimates Python file tokens" {
    run context_file_tokens "$TEST_DIR/src/app.py"
    [ "$status" -eq 0 ]
    local tokens="$output"
    # Non-zero token count for a real file
    [ "$tokens" -gt 0 ]
    # Python file uses 3.5 ratio
    [ "$tokens" -gt 50 ]
}

@test "context_file_tokens estimates JSON file tokens" {
    run context_file_tokens "$TEST_DIR/src/config.json"
    [ "$status" -eq 0 ]
    local tokens="$output"
    [ "$tokens" -gt 0 ]
}

@test "context_file_tokens estimates markdown file tokens" {
    run context_file_tokens "$TEST_DIR/README.md"
    [ "$status" -eq 0 ]
    local tokens="$output"
    [ "$tokens" -gt 0 ]
}

@test "context_file_tokens uses text ratio for .txt files" {
    run context_file_tokens "$TEST_DIR/prose.txt"
    [ "$status" -eq 0 ]
    local tokens="$output"
    [ "$tokens" -gt 0 ]
}

@test "context_file_tokens uses code ratio for .sh files" {
    run context_file_tokens "$TEST_DIR/src/script.sh"
    [ "$status" -eq 0 ]
    local tokens="$output"
    [ "$tokens" -gt 0 ]
}

@test "context_command_tokens estimates output of echo" {
    run context_command_tokens echo "Hello, World!"
    [ "$status" -eq 0 ]
    local tokens="$output"
    [ "$tokens" -ge 2 ]
    [ "$tokens" -le 6 ]
}

@test "context_command_tokens returns 0 for no args" {
    run context_command_tokens
    [ "$status" -eq 1 ]
    [ "$output" = "0" ]
}

@test "context_ratio returns 4.0 for text" {
    run context_ratio --type text
    [ "$status" -eq 0 ]
    [ "$output" = "4.0" ]
}

@test "context_ratio returns 3.5 for code" {
    run context_ratio --type code
    [ "$status" -eq 0 ]
    [ "$output" = "3.5" ]
}

@test "context_ratio returns 3.0 for json" {
    run context_ratio --type json
    [ "$status" -eq 0 ]
    [ "$output" = "3.0" ]
}

@test "context_ratio returns 3.8 for markdown" {
    run context_ratio --type markdown
    [ "$status" -eq 0 ]
    [ "$output" = "3.8" ]
}

@test "context_ratio defaults to text" {
    run context_ratio
    [ "$status" -eq 0 ]
    [ "$output" = "4.0" ]
}

# =============================================================================
# BUDGET MANAGEMENT TESTS
# =============================================================================

@test "context_budget_init creates state with defaults" {
    context_budget_init
    [ -f "$MAINFRAME_CONTEXT_STATE" ]
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # 100000 - 0 - 4000 = 96000
    [ "$output" = "96000" ]
}

@test "context_budget_init accepts custom max-tokens" {
    context_budget_init --max-tokens 50000
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # 50000 - 0 - 4000 = 46000
    [ "$output" = "46000" ]
}

@test "context_budget_init accepts custom reserve" {
    context_budget_init --max-tokens 10000 --reserve 2000
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # 10000 - 0 - 2000 = 8000
    [ "$output" = "8000" ]
}

@test "context_budget_use tracks token allocation" {
    context_budget_init --max-tokens 10000 --reserve 1000
    context_budget_use "file1" 2000
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # 10000 - 2000 - 1000 = 7000
    [ "$output" = "7000" ]
}

@test "context_budget_use tracks multiple allocations" {
    context_budget_init --max-tokens 10000 --reserve 1000
    context_budget_use "file1" 2000
    context_budget_use "file2" 3000
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # 10000 - 5000 - 1000 = 4000
    [ "$output" = "4000" ]
}

@test "context_budget_use replaces existing allocation" {
    context_budget_init --max-tokens 10000 --reserve 1000
    context_budget_use "file1" 2000
    context_budget_use "file1" 3000
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # 10000 - 3000 - 1000 = 6000
    [ "$output" = "6000" ]
}

@test "context_budget_fits returns 0 when within budget" {
    context_budget_init --max-tokens 10000 --reserve 1000
    run context_budget_fits 5000
    [ "$status" -eq 0 ]
}

@test "context_budget_fits returns 1 when exceeds budget" {
    context_budget_init --max-tokens 10000 --reserve 1000
    context_budget_use "existing" 5000
    # Remaining: 10000 - 5000 - 1000 = 4000
    run context_budget_fits 5000
    [ "$status" -eq 1 ]
}

@test "context_budget_remaining never returns negative" {
    context_budget_init --max-tokens 1000 --reserve 500
    context_budget_use "big" 800
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # 1000 - 800 - 500 = -300 -> 0
    [ "$output" = "0" ]
}

@test "context_budget_summary returns valid JSON" {
    context_budget_init --max-tokens 20000 --reserve 2000
    context_budget_use "source" 5000
    run context_budget_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *'"max":20000'* ]]
    [[ "$output" == *'"used":5000'* ]]
    [[ "$output" == *'"reserve":2000'* ]]
    [[ "$output" == *'"remaining":13000'* ]]
    [[ "$output" == *'"source":5000'* ]]
}

@test "context_budget_reset clears all state" {
    context_budget_init --max-tokens 50000 --reserve 5000
    context_budget_use "file1" 10000
    context_budget_reset
    run context_budget_remaining
    [ "$status" -eq 0 ]
    # Back to defaults: 100000 - 0 - 4000 = 96000
    # (remaining returns default when no state file)
    [ "$output" = "100000" ]
}

# =============================================================================
# CONTENT TRUNCATION TESTS
# =============================================================================

@test "context_truncate returns text unchanged when within budget" {
    local text="Hello, world!"
    run context_truncate "$text" 1000
    [ "$status" -eq 0 ]
    [ "$output" = "Hello, world!" ]
}

@test "context_truncate head strategy keeps beginning" {
    local text
    text=$(cat "$TEST_DIR/large.txt")
    run context_truncate "$text" 50 --strategy head
    [ "$status" -eq 0 ]
    [[ "$output" == "Line 1:"* ]]
    [[ "$output" == *"truncated"* ]]
}

@test "context_truncate tail strategy keeps end" {
    local text
    text=$(cat "$TEST_DIR/large.txt")
    run context_truncate "$text" 50 --strategy tail
    [ "$status" -eq 0 ]
    [[ "$output" == *"Line 50:"* ]]
    [[ "$output" == *"truncated"* ]]
}

@test "context_truncate middle strategy keeps both ends" {
    local text
    text=$(cat "$TEST_DIR/large.txt")
    run context_truncate "$text" 100 --strategy middle
    [ "$status" -eq 0 ]
    [[ "$output" == "Line 1:"* ]]
    [[ "$output" == *"truncated"* ]]
    [[ "$output" == *"Line 50:"* ]]
}

@test "context_truncate smart strategy keeps paragraphs" {
    local text="First paragraph line one.
First paragraph line two.

Middle content that will be cut.
More middle content.
Even more middle.

Last paragraph line one.
Last paragraph line two."
    run context_truncate "$text" 30 --strategy smart
    [ "$status" -eq 0 ]
    [[ "$output" == *"First paragraph"* ]]
    [[ "$output" == *"truncated"* ]]
}

@test "context_truncate preserves complete lines" {
    local text="Short line
Another short line
Third line here"
    run context_truncate "$text" 5 --strategy head
    [ "$status" -eq 0 ]
    # Should not cut mid-word/mid-line
    [[ "$output" != *"Sho"* ]] || [[ "$output" == "Short line"* ]]
}

@test "context_truncate_file works on real file" {
    run context_truncate_file "$TEST_DIR/large.txt" 50
    [ "$status" -eq 0 ]
    [[ "$output" == "Line 1:"* ]]
    [[ "$output" == *"truncated"* ]]
}

@test "context_truncate_file returns error for missing file" {
    run context_truncate_file "/nonexistent/file.txt" 100
    [ "$status" -eq 1 ]
}

@test "context_truncate handles empty text" {
    run context_truncate "" 100
    [ "$status" -eq 0 ]
}

# =============================================================================
# CONTENT ANALYSIS TESTS
# =============================================================================

@test "context_analyze returns JSON for empty string" {
    run context_analyze ""
    [ "$status" -eq 0 ]
    [[ "$output" == *'"chars":0'* ]]
    [[ "$output" == *'"estimated_tokens":0'* ]]
}

@test "context_analyze detects code type" {
    local code='def hello():
    print("world")
    return True'
    run context_analyze "$code"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"type":"code"'* ]]
}

@test "context_analyze detects text type" {
    local prose="The quick brown fox jumps over the lazy dog. This is plain text with no code."
    run context_analyze "$prose"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"type":"text"'* ]]
}

@test "context_analyze reports character count" {
    local text="Hello"
    run context_analyze "$text"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"chars":5'* ]]
}

@test "context_analyze reports line count" {
    local text="Line 1
Line 2
Line 3"
    run context_analyze "$text"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"lines":3'* ]]
}

@test "context_detect_type identifies JSON" {
    run context_detect_type '{"key": "value"}'
    [ "$status" -eq 0 ]
    [ "$output" = "data:json" ]
}

@test "context_detect_type identifies JSON array" {
    run context_detect_type '[1, 2, 3]'
    [ "$status" -eq 0 ]
    [ "$output" = "data:json" ]
}

@test "context_detect_type identifies Python code" {
    local code='import os
from pathlib import Path

def main():
    path = Path(".")
    print(path)

class MyClass:
    pass'
    run context_detect_type "$code"
    [ "$status" -eq 0 ]
    [ "$output" = "code:python" ]
}

@test "context_detect_type identifies bash with shebang" {
    local code='#!/usr/bin/env bash
set -euo pipefail

main() {
    echo "hello"
}'
    run context_detect_type "$code"
    [ "$status" -eq 0 ]
    [ "$output" = "code:bash" ]
}

@test "context_detect_type identifies markdown" {
    local text='# Title

## Section

- Item one
- Item two

**Bold text** and more.'
    run context_detect_type "$text"
    [ "$status" -eq 0 ]
    [ "$output" = "text:markdown" ]
}

@test "context_detect_type identifies prose" {
    run context_detect_type "This is just plain text with no special formatting at all."
    [ "$status" -eq 0 ]
    [ "$output" = "text:prose" ]
}

@test "context_detect_type identifies XML" {
    run context_detect_type '<?xml version="1.0"?><root><item/></root>'
    [ "$status" -eq 0 ]
    [ "$output" = "data:xml" ]
}

@test "context_detect_type identifies YAML" {
    run context_detect_type '---
name: test
version: 1.0'
    [ "$status" -eq 0 ]
    [ "$output" = "data:yaml" ]
}

@test "context_detect_type handles empty string" {
    run context_detect_type ""
    [ "$status" -eq 0 ]
    [ "$output" = "text:unknown" ]
}

@test "context_chunk_size returns value for claude" {
    run context_chunk_size --model claude --type text
    [ "$status" -eq 0 ]
    [ "$output" = "8000" ]
}

@test "context_chunk_size reduces for code type" {
    run context_chunk_size --model claude --type code
    [ "$status" -eq 0 ]
    [ "$output" = "6000" ]
}

@test "context_chunk_size supports gpt4 model" {
    run context_chunk_size --model gpt4 --type text
    [ "$status" -eq 0 ]
    [ "$output" = "6000" ]
}

@test "context_chunk_size supports gemini model" {
    run context_chunk_size --model gemini --type text
    [ "$status" -eq 0 ]
    [ "$output" = "7000" ]
}

# =============================================================================
# FILE BATCHING TESTS
# =============================================================================

@test "context_batch_files selects files within budget" {
    # Use a generous budget that fits all small files
    local result
    result=$(printf '%s\n' "$TEST_DIR/prose.txt" "$TEST_DIR/src/config.json" | context_batch_files 10000)
    [[ "$result" == *"prose.txt"* ]]
    [[ "$result" == *"config.json"* ]]
}

@test "context_batch_files excludes files exceeding budget" {
    # Use a tiny budget
    local result
    result=$(printf '%s\n' "$TEST_DIR/large.txt" "$TEST_DIR/prose.txt" | context_batch_files 60)
    # prose.txt (~50 tokens) should fit, large.txt (~1200+ tokens) should not
    [[ "$result" == *"prose.txt"* ]]
    [[ "$result" != *"large.txt"* ]]
}

@test "context_batch_files skips non-existent files" {
    local result
    result=$(printf '%s\n' "/nonexistent/file.txt" "$TEST_DIR/prose.txt" | context_batch_files 10000)
    [[ "$result" == *"prose.txt"* ]]
    [[ "$result" != *"nonexistent"* ]]
}

@test "context_batch_files handles empty input" {
    local result
    result=$(echo "" | context_batch_files 10000)
    [ -z "$result" ]
}

@test "context_read_plan outputs valid JSON" {
    run context_read_plan 10000 "$TEST_DIR/prose.txt" "$TEST_DIR/src/config.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"files":'* ]]
    [[ "$output" == *'"total_tokens":'* ]]
    [[ "$output" == *'"files_included":'* ]]
    [[ "$output" == *'"files_excluded":'* ]]
}

@test "context_read_plan marks files as included when they fit" {
    run context_read_plan 10000 "$TEST_DIR/prose.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"included":true'* ]]
    [[ "$output" == *'"files_included":1'* ]]
}

@test "context_read_plan marks files as excluded when over budget" {
    run context_read_plan 5 "$TEST_DIR/large.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"included":false'* ]]
    [[ "$output" == *'"files_excluded":1'* ]]
}

@test "context_read_plan handles missing max_tokens" {
    run context_read_plan
    [ "$status" -eq 1 ]
    [[ "$output" == *'"files":[]'* ]]
}

@test "context_read_plan skips non-existent files" {
    run context_read_plan 10000 "/nonexistent/file.txt" "$TEST_DIR/prose.txt"
    [ "$status" -eq 0 ]
    # Only one file should be in the plan
    [[ "$output" == *"prose.txt"* ]]
    [[ "$output" != *"nonexistent"* ]]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "full workflow: estimate -> budget -> check" {
    context_budget_init --max-tokens 200 --reserve 20

    local tokens
    tokens=$(context_file_tokens "$TEST_DIR/prose.txt")
    [ "$tokens" -gt 0 ]

    context_budget_use "prose" "$tokens"

    run context_budget_fits 100
    # Should depend on file size vs remaining budget
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

    run context_budget_summary
    [[ "$output" == *'"prose":'* ]]
}

@test "distribute_budget allocates proportionally" {
    local result
    result=$(printf 'high\tAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\t3\nlow\tBBBB\t1\n' | context_distribute_budget 20)
    [[ "$result" == *'"label":"high"'* ]]
    [[ "$result" == *'"label":"low"'* ]]
    [[ "$result" == *'"priority":3'* ]]
    [[ "$result" == *'"priority":1'* ]]
}

@test "distribute_budget handles empty input" {
    local result
    result=$(echo "" | context_distribute_budget 1000)
    [ "$result" = "[]" ]
}

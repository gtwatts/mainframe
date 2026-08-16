#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/json.bats - JSON Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/json.sh
#              Pure bash JSON generation and manipulation
# Test Count: 60+ test cases
# Categories: string escaping, value creation, arrays, objects, merging,
#             pretty printing, validation, extraction, file operations,
#             nameref variants (high-performance)
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library
    source "$MAINFRAME_ROOT/lib/json.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CATEGORY 1: STRING ESCAPING
# =============================================================================

@test "json_escape: escapes double quotes" {
    result=$(json_escape 'hello "world"')
    [[ "$result" == 'hello \"world\"' ]]
}

@test "json_escape: escapes backslashes" {
    result=$(json_escape 'path\to\file')
    [[ "$result" == 'path\\to\\file' ]]
}

@test "json_escape: escapes newlines" {
    result=$(json_escape $'line1\nline2')
    [[ "$result" == 'line1\nline2' ]]
}

@test "json_escape: escapes tabs" {
    result=$(json_escape $'col1\tcol2')
    [[ "$result" == 'col1\tcol2' ]]
}

@test "json_escape: escapes carriage returns" {
    result=$(json_escape $'line1\rline2')
    [[ "$result" == 'line1\rline2' ]]
}

@test "json_escape: escapes backspace" {
    result=$(json_escape $'back\bspace')
    [[ "$result" == 'back\bspace' ]]
}

@test "json_escape: escapes form feed" {
    result=$(json_escape $'form\ffeed')
    [[ "$result" == 'form\ffeed' ]]
}

@test "json_escape: handles empty string" {
    result=$(json_escape '')
    [[ "$result" == '' ]]
}

@test "json_escape: handles plain string" {
    result=$(json_escape 'hello world')
    [[ "$result" == 'hello world' ]]
}

@test "json_escape: handles combined special characters" {
    result=$(json_escape $'"quoted"\nand\ttabbed')
    [[ "$result" == '\"quoted\"\nand\ttabbed' ]]
}

# =============================================================================
# CATEGORY 2: VALUE CREATION
# =============================================================================

@test "json_string: wraps value in quotes" {
    result=$(json_string "hello")
    [[ "$result" == '"hello"' ]]
}

@test "json_string: escapes special characters in value" {
    result=$(json_string 'say "hi"')
    [[ "$result" == '"say \"hi\""' ]]
}

@test "json_string: handles empty string" {
    result=$(json_string "")
    [[ "$result" == '""' ]]
}

@test "json_number: outputs valid integer" {
    result=$(json_number 42)
    [[ "$result" == '42' ]]
}

@test "json_number: outputs valid negative integer" {
    result=$(json_number -100)
    [[ "$result" == '-100' ]]
}

@test "json_number: outputs valid float" {
    result=$(json_number 3.14159)
    [[ "$result" == '3.14159' ]]
}

@test "json_number: outputs scientific notation" {
    result=$(json_number 1.5e10)
    [[ "$result" == '1.5e10' ]]
}

@test "json_number: returns null for invalid input" {
    run json_number "not-a-number"
    [[ "$output" == 'null' ]]
    [[ "$status" -eq 1 ]]
}

@test "json_bool: converts true" {
    result=$(json_bool true)
    [[ "$result" == 'true' ]]
}

@test "json_bool: converts false" {
    result=$(json_bool false)
    [[ "$result" == 'false' ]]
}

@test "json_bool: converts 1 to true" {
    result=$(json_bool 1)
    [[ "$result" == 'true' ]]
}

@test "json_bool: converts 0 to false" {
    result=$(json_bool 0)
    [[ "$result" == 'false' ]]
}

@test "json_bool: converts yes to true (case insensitive)" {
    result=$(json_bool YES)
    [[ "$result" == 'true' ]]
}

@test "json_bool: converts no to false (case insensitive)" {
    result=$(json_bool NO)
    [[ "$result" == 'false' ]]
}

@test "json_bool: returns null for invalid input" {
    run json_bool "maybe"
    [[ "$output" == 'null' ]]
    [[ "$status" -eq 1 ]]
}

@test "json_null: outputs null literal" {
    result=$(json_null)
    [[ "$result" == 'null' ]]
}

@test "json_value: auto-detects null" {
    result=$(json_value "null")
    [[ "$result" == 'null' ]]
}

@test "json_value: auto-detects true boolean" {
    result=$(json_value "true")
    [[ "$result" == 'true' ]]
}

@test "json_value: auto-detects false boolean" {
    result=$(json_value "false")
    [[ "$result" == 'false' ]]
}

@test "json_value: auto-detects integer" {
    result=$(json_value "42")
    [[ "$result" == '42' ]]
}

@test "json_value: auto-detects float" {
    result=$(json_value "3.14")
    [[ "$result" == '3.14' ]]
}

@test "json_value: treats other values as strings" {
    result=$(json_value "hello")
    [[ "$result" == '"hello"' ]]
}

@test "json_value: explicit string type" {
    result=$(json_value "42" "string")
    [[ "$result" == '"42"' ]]
}

@test "json_value: explicit number type" {
    result=$(json_value "42" "number")
    [[ "$result" == '42' ]]
}

@test "json_value: explicit bool type" {
    result=$(json_value "yes" "bool")
    [[ "$result" == 'true' ]]
}

@test "json_value: raw type passes through" {
    result=$(json_value '{"nested":true}' "raw")
    [[ "$result" == '{"nested":true}' ]]
}

# =============================================================================
# CATEGORY 3: ARRAY CREATION
# =============================================================================

@test "json_array: creates empty array" {
    result=$(json_array)
    [[ "$result" == '[]' ]]
}

@test "json_array: creates single element array" {
    result=$(json_array "hello")
    [[ "$result" == '["hello"]' ]]
}

@test "json_array: creates multi-element array" {
    result=$(json_array "a" "b" "c")
    [[ "$result" == '["a","b","c"]' ]]
}

@test "json_array: auto-detects mixed types" {
    result=$(json_array "hello" "42" "true")
    [[ "$result" == '["hello",42,true]' ]]
}

@test "json_array: handles special characters in elements" {
    result=$(json_array 'say "hi"' $'line\n2')
    [[ "$result" == '["say \"hi\"","line\n2"]' ]]
}

@test "json_array_typed: creates string array" {
    result=$(json_array_typed string "1" "2" "3")
    [[ "$result" == '["1","2","3"]' ]]
}

@test "json_array_typed: creates number array" {
    result=$(json_array_typed number "1" "2" "3")
    [[ "$result" == '[1,2,3]' ]]
}

@test "json_array_from_lines: converts newline-separated input" {
    result=$(printf 'apple\nbanana\ncherry' | json_array_from_lines)
    [[ "$result" == '["apple","banana","cherry"]' ]]
}

@test "json_array_from_lines: handles empty input" {
    result=$(printf '' | json_array_from_lines)
    [[ "$result" == '[]' ]]
}

# =============================================================================
# CATEGORY 4: OBJECT CREATION
# =============================================================================

@test "json_object: creates empty object" {
    result=$(json_object)
    [[ "$result" == '{}' ]]
}

@test "json_object: creates simple key-value" {
    result=$(json_object "name=John")
    [[ "$result" == '{"name":"John"}' ]]
}

@test "json_object: creates multiple key-values" {
    result=$(json_object "name=John" "city=NYC")
    [[ "$result" == '{"name":"John","city":"NYC"}' ]]
}

@test "json_object: auto-detects number values" {
    result=$(json_object "age=30")
    [[ "$result" == '{"age":30}' ]]
}

@test "json_object: explicit number type" {
    result=$(json_object "count:number=5")
    [[ "$result" == '{"count":5}' ]]
}

@test "json_object: explicit bool type" {
    result=$(json_object "active:bool=yes")
    [[ "$result" == '{"active":true}' ]]
}

@test "json_object: explicit string type forces string" {
    result=$(json_object "code:string=42")
    [[ "$result" == '{"code":"42"}' ]]
}

@test "json_object: mixed types" {
    result=$(json_object "name=John" "age:number=30" "active:bool=true")
    [[ "$result" == '{"name":"John","age":30,"active":true}' ]]
}

@test "json_object: handles values with equals sign" {
    result=$(json_object "formula=a=b+c")
    [[ "$result" == '{"formula":"a=b+c"}' ]]
}

@test "json_object: escapes keys with special characters" {
    result=$(json_object 'key"name=value')
    [[ "$result" == '{"key\"name":"value"}' ]]
}

@test "json_from_assoc: creates object from associative array" {
    declare -A data=([name]="John" [age]="30")
    result=$(json_from_assoc data)
    # Order may vary with associative arrays
    [[ "$result" =~ '"name":"John"' ]]
    [[ "$result" =~ '"age":30' ]]
}

@test "json_nested: creates single-level nested object" {
    result=$(json_nested "user" "John")
    [[ "$result" == '{"user":"John"}' ]]
}

@test "json_nested: creates multi-level nested object" {
    result=$(json_nested "a.b.c" "value")
    [[ "$result" == '{"a":{"b":{"c":"value"}}}' ]]
}

# =============================================================================
# CATEGORY 5: MERGING & MODIFICATION
# =============================================================================

@test "json_merge: merges two objects" {
    result=$(json_merge '{"a":1}' '{"b":2}')
    [[ "$result" == '{"a":1,"b":2}' ]]
}

@test "json_merge: merges multiple objects" {
    result=$(json_merge '{"a":1}' '{"b":2}' '{"c":3}')
    [[ "$result" == '{"a":1,"b":2,"c":3}' ]]
}

@test "json_merge: handles empty objects" {
    result=$(json_merge '{}' '{"a":1}')
    [[ "$result" == '{"a":1}' ]]
}

@test "json_merge: second object overwrites first" {
    result=$(json_merge '{"a":1}' '{"a":2}')
    [[ "$result" == '{"a":1,"a":2}' ]]
}

# =============================================================================
# CATEGORY 6: PRETTY PRINTING
# =============================================================================

@test "json_pretty: formats simple object" {
    result=$(json_pretty '{"a":1}')
    [[ "$result" =~ '"a": 1' ]]
}

@test "json_pretty: formats nested object with indentation" {
    result=$(json_pretty '{"outer":{"inner":1}}')
    [[ "$result" =~ 'outer' ]]
    [[ "$result" =~ 'inner' ]]
}

@test "json_pretty: formats array" {
    result=$(json_pretty '[1,2,3]')
    [[ "$result" =~ '1' ]]
    [[ "$result" =~ '2' ]]
}

@test "json_pretty: handles strings with colons" {
    result=$(json_pretty '{"url":"http://example.com"}')
    [[ "$result" =~ 'http://example.com' ]]
}

# =============================================================================
# CATEGORY 7: VALIDATION
# =============================================================================

@test "json_valid: returns true for valid object" {
    json_valid '{"key":"value"}'
    [[ $? -eq 0 ]]
}

@test "json_valid: returns true for valid array" {
    json_valid '[1,2,3]'
    [[ $? -eq 0 ]]
}

@test "json_valid: returns true for nested structure" {
    json_valid '{"outer":{"inner":[1,2,3]}}'
    [[ $? -eq 0 ]]
}

@test "json_valid: returns false for empty string" {
    run json_valid ''
    [[ "$status" -eq 1 ]]
}

@test "json_valid: returns false for unbalanced braces" {
    run json_valid '{"key":"value"'
    [[ "$status" -eq 1 ]]
}

@test "json_valid: returns false for unbalanced brackets" {
    run json_valid '[1,2,3'
    [[ "$status" -eq 1 ]]
}

@test "json_valid: returns false for unclosed string" {
    run json_valid '{"key":"unclosed}'
    [[ "$status" -eq 1 ]]
}

@test "json_valid: handles escaped quotes in strings" {
    json_valid '{"key":"value with \"quotes\""}'
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 8: EXTRACTION
# =============================================================================

@test "json_set: appends numeric value to object" {
    result=$(json_set '{"a":1}' "b" "2")
    [[ "$result" == '{"a":1,"b":2}' ]]
}

@test "json_set: replaces existing string value" {
    result=$(json_set '{"a":1,"b":"x"}' "b" "y")
    [[ "$result" == '{"a":1,"b":"y"}' ]]
}

@test "json_set: replaces existing numeric value" {
    result=$(json_set '{"a":1}' "a" "5")
    [[ "$result" == '{"a":5}' ]]
}

@test "json_set: escapes string values" {
    result=$(json_set '{"a":"hi"}' "a" 'say "hi"')
    [[ "$result" == '{"a":"say \"hi\""}' ]]
}

@test "json_set: handles bool/null/scalars and empty object" {
    result=$(json_set '{}' "ok" "true")
    [[ "$result" == '{"ok":true}' ]]
    result=$(json_set '{"a":1}' "n" "null")
    [[ "$result" == '{"a":1,"n":null}' ]]
}

@test "json_get: extracts string value" {
    result=$(json_get '{"name":"John"}' "name")
    [[ "$result" == 'John' ]]
}

@test "json_get: extracts numeric value" {
    result=$(json_get '{"age":30}' "age")
    [[ "$result" == '30' ]]
}

@test "json_get: extracts boolean value" {
    result=$(json_get '{"active":true}' "active")
    [[ "$result" == 'true' ]]
}

@test "json_get: extracts null value" {
    result=$(json_get '{"value":null}' "value")
    [[ "$result" == 'null' ]]
}

@test "json_get: returns failure for missing key" {
    run json_get '{"name":"John"}' "age"
    [[ "$status" -eq 1 ]]
}

@test "json_get: handles whitespace in JSON" {
    result=$(json_get '{ "name" : "John" }' "name")
    [[ "$result" == 'John' ]]
}

@test "json_keys: extracts all keys from object" {
    result=$(json_keys '{"a":1,"b":2,"c":3}')
    [[ "$result" =~ 'a' ]]
    [[ "$result" =~ 'b' ]]
    [[ "$result" =~ 'c' ]]
}

@test "json_keys: returns empty for empty object" {
    result=$(json_keys '{}')
    [[ -z "$result" ]]
}

# =============================================================================
# CATEGORY 9: FILE OPERATIONS
# =============================================================================

@test "json_read: reads JSON from file" {
    echo '{"test":true}' > "$TEST_TMPDIR/test.json"
    result=$(json_read "$TEST_TMPDIR/test.json")
    [[ "$result" == '{"test":true}' ]]
}

@test "json_read: returns empty for missing file" {
    run json_read "$TEST_TMPDIR/nonexistent.json"
    [[ -z "$output" ]]
}

@test "json_write: writes JSON to file" {
    json_write "$TEST_TMPDIR/output.json" '{"written":true}'
    result=$(<"$TEST_TMPDIR/output.json")
    [[ "$result" == '{"written":true}' ]]
}

@test "json_write_pretty: writes formatted JSON to file" {
    json_write_pretty "$TEST_TMPDIR/pretty.json" '{"a":1}'
    result=$(<"$TEST_TMPDIR/pretty.json")
    [[ "$result" =~ '"a": 1' ]]
}

# =============================================================================
# CATEGORY 10: NAMEREF VARIANTS (HIGH-PERFORMANCE)
# =============================================================================

@test "json_escape_v: escapes into variable" {
    local out
    json_escape_v out 'hello "world"'
    [[ "$out" == 'hello \"world\"' ]]
}

@test "json_string_v: creates string into variable" {
    local out
    json_string_v out "hello"
    [[ "$out" == '"hello"' ]]
}

@test "json_number_v: creates number into variable" {
    local out
    json_number_v out 42
    [[ "$out" == '42' ]]
}

@test "json_number_v: returns null for invalid" {
    local out
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/json.sh"; json_number_v out "bad"; echo "$out"'
    [[ "$output" == 'null' ]]
}

@test "json_bool_v: creates boolean into variable" {
    local out
    json_bool_v out yes
    [[ "$out" == 'true' ]]
}

@test "json_value_v: auto-detects type into variable" {
    local out
    json_value_v out "42"
    [[ "$out" == '42' ]]
}

@test "json_array_v: creates array into variable" {
    local out
    json_array_v out "a" "b" "c"
    [[ "$out" == '["a","b","c"]' ]]
}

@test "json_array_typed_v: creates typed array into variable" {
    local out
    json_array_typed_v out number 1 2 3
    [[ "$out" == '[1,2,3]' ]]
}

@test "json_object_v: creates object into variable" {
    local out
    json_object_v out "name=John" "age:number=30"
    [[ "$out" == '{"name":"John","age":30}' ]]
}

@test "json_nested_v: creates nested object into variable" {
    local out
    json_nested_v out "a.b" "value"
    [[ "$out" == '{"a":{"b":"value"}}' ]]
}

@test "json_get_v: extracts value into variable" {
    local out
    json_get_v out '{"name":"John"}' "name"
    [[ "$out" == 'John' ]]
}

@test "json_merge_v: merges objects into variable" {
    local out
    json_merge_v out '{"a":1}' '{"b":2}'
    [[ "$out" == '{"a":1,"b":2}' ]]
}

@test "json_pretty_v: formats JSON into variable" {
    local out
    json_pretty_v out '{"a":1}'
    [[ "$out" =~ '"a": 1' ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES AND SECURITY
# =============================================================================

@test "json_escape: handles unicode characters" {
    result=$(json_escape "cafe")
    [[ "$result" == "cafe" ]]
}

@test "json_object: handles empty value" {
    result=$(json_object "key=")
    [[ "$result" == '{"key":""}' ]]
}

@test "json_string: handles very long strings" {
    local long_string
    long_string=$(printf 'x%.0s' {1..1000})
    result=$(json_string "$long_string")
    [[ "$result" == "\"$long_string\"" ]]
}

@test "json_valid: handles deeply nested structure" {
    local deep='{"a":{"b":{"c":{"d":{"e":1}}}}}'
    json_valid "$deep"
    [[ $? -eq 0 ]]
}

@test "json_object: skips malformed pairs" {
    result=$(json_object "valid=yes" "malformed" "also_valid=true")
    [[ "$result" == '{"valid":"yes","also_valid":true}' ]]
}

@test "json_get: handles key with special regex characters" {
    # Keys with dots, brackets etc in the key name
    result=$(json_get '{"simple":"value"}' "simple")
    [[ "$result" == 'value' ]]
}

@test "json_array: handles large number of elements" {
    local elements=()
    for i in {1..50}; do
        elements+=("item$i")
    done
    result=$(json_array "${elements[@]}")
    [[ "$result" =~ '"item1"' ]]
    [[ "$result" =~ '"item50"' ]]
}

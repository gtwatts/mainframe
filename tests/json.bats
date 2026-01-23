#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: JSON Module Tests
# =============================================================================
# Comprehensive tests for lib/json.sh (33 functions)
# Covers: escaping, value creation, arrays, objects, merging, pretty print,
#         validation, extraction, file ops, and nameref (_v) variants
# =============================================================================

load 'test_helper'

setup() {
    source_lib "json"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "json")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# json_escape TESTS
# =============================================================================

@test "json_escape handles plain string" {
    local result
    result=$(json_escape "hello world")
    [ "$result" = "hello world" ]
}

@test "json_escape escapes double quotes" {
    local result
    result=$(json_escape 'say "hello"')
    [ "$result" = 'say \"hello\"' ]
}

@test "json_escape escapes backslashes" {
    local result
    result=$(json_escape 'path\to\file')
    [ "$result" = 'path\\to\\file' ]
}

@test "json_escape escapes newlines" {
    local result
    result=$(json_escape $'line1\nline2')
    [ "$result" = 'line1\nline2' ]
}

@test "json_escape escapes tabs" {
    local result
    result=$(json_escape $'col1\tcol2')
    [ "$result" = 'col1\tcol2' ]
}

@test "json_escape escapes carriage return" {
    local result
    result=$(json_escape $'hello\rworld')
    [ "$result" = 'hello\rworld' ]
}

@test "json_escape escapes backspace" {
    local result
    result=$(json_escape $'hello\bworld')
    [ "$result" = 'hello\bworld' ]
}

@test "json_escape escapes form feed" {
    local result
    result=$(json_escape $'hello\fworld')
    [ "$result" = 'hello\fworld' ]
}

@test "json_escape handles empty string" {
    local result
    result=$(json_escape "")
    [ "$result" = "" ]
}

@test "json_escape handles combined special characters" {
    local result
    result=$(json_escape $'"quoted"\nnewline\ttab\\slash')
    [ "$result" = '\"quoted\"\nnewline\ttab\\slash' ]
}

@test "json_escape escapes control characters as unicode" {
    local result
    result=$(json_escape $'\x01')
    [ "$result" = '\u0001' ]
}

@test "json_escape handles dollar sign (bash special)" {
    local result
    result=$(json_escape '$HOME')
    [ "$result" = '$HOME' ]
}

@test "json_escape handles backtick (bash special)" {
    local result
    result=$(json_escape '`command`')
    [ "$result" = '`command`' ]
}

# =============================================================================
# json_string TESTS
# =============================================================================

@test "json_string wraps in quotes" {
    local result
    result=$(json_string "hello")
    [ "$result" = '"hello"' ]
}

@test "json_string escapes inner quotes" {
    local result
    result=$(json_string 'say "hi"')
    [ "$result" = '"say \"hi\""' ]
}

@test "json_string handles empty string" {
    local result
    result=$(json_string "")
    [ "$result" = '""' ]
}

# =============================================================================
# json_number TESTS
# =============================================================================

@test "json_number handles integer" {
    local result
    result=$(json_number 42)
    [ "$result" = "42" ]
}

@test "json_number handles negative integer" {
    local result
    result=$(json_number -7)
    [ "$result" = "-7" ]
}

@test "json_number handles float" {
    local result
    result=$(json_number 3.14)
    [ "$result" = "3.14" ]
}

@test "json_number handles scientific notation" {
    local result
    result=$(json_number "1.5e10")
    [ "$result" = "1.5e10" ]
}

@test "json_number handles negative exponent" {
    local result
    result=$(json_number "2.5E-3")
    [ "$result" = "2.5E-3" ]
}

@test "json_number returns null for non-numeric" {
    local result
    result=$(json_number "abc") || true
    [ "$result" = "null" ]
}

@test "json_number fails for non-numeric" {
    ! json_number "abc" >/dev/null
}

@test "json_number handles zero" {
    local result
    result=$(json_number 0)
    [ "$result" = "0" ]
}

# =============================================================================
# json_bool TESTS
# =============================================================================

@test "json_bool handles true" {
    local result
    result=$(json_bool "true")
    [ "$result" = "true" ]
}

@test "json_bool handles false" {
    local result
    result=$(json_bool "false")
    [ "$result" = "false" ]
}

@test "json_bool handles 1 as true" {
    local result
    result=$(json_bool "1")
    [ "$result" = "true" ]
}

@test "json_bool handles 0 as false" {
    local result
    result=$(json_bool "0")
    [ "$result" = "false" ]
}

@test "json_bool handles yes as true" {
    local result
    result=$(json_bool "yes")
    [ "$result" = "true" ]
}

@test "json_bool handles no as false" {
    local result
    result=$(json_bool "no")
    [ "$result" = "false" ]
}

@test "json_bool handles on as true" {
    local result
    result=$(json_bool "on")
    [ "$result" = "true" ]
}

@test "json_bool handles off as false" {
    local result
    result=$(json_bool "off")
    [ "$result" = "false" ]
}

@test "json_bool case insensitive (TRUE)" {
    local result
    result=$(json_bool "TRUE")
    [ "$result" = "true" ]
}

@test "json_bool returns null for invalid" {
    local result
    result=$(json_bool "maybe") || true
    [ "$result" = "null" ]
}

@test "json_bool fails for invalid value" {
    ! json_bool "maybe" >/dev/null
}

# =============================================================================
# json_null TESTS
# =============================================================================

@test "json_null returns null" {
    local result
    result=$(json_null)
    [ "$result" = "null" ]
}

# =============================================================================
# json_value TESTS (auto-detect)
# =============================================================================

@test "json_value auto-detects null" {
    local result
    result=$(json_value "null")
    [ "$result" = "null" ]
}

@test "json_value auto-detects true" {
    local result
    result=$(json_value "true")
    [ "$result" = "true" ]
}

@test "json_value auto-detects false" {
    local result
    result=$(json_value "false")
    [ "$result" = "false" ]
}

@test "json_value auto-detects integer" {
    local result
    result=$(json_value "42")
    [ "$result" = "42" ]
}

@test "json_value auto-detects float" {
    local result
    result=$(json_value "3.14")
    [ "$result" = "3.14" ]
}

@test "json_value auto-detects string" {
    local result
    result=$(json_value "hello")
    [ "$result" = '"hello"' ]
}

@test "json_value explicit string type" {
    local result
    result=$(json_value "42" "string")
    [ "$result" = '"42"' ]
}

@test "json_value explicit number type" {
    local result
    result=$(json_value "42" "number")
    [ "$result" = "42" ]
}

@test "json_value explicit bool type" {
    local result
    result=$(json_value "yes" "bool")
    [ "$result" = "true" ]
}

@test "json_value explicit null type" {
    local result
    result=$(json_value "anything" "null")
    [ "$result" = "null" ]
}

@test "json_value raw type passes through" {
    local result
    result=$(json_value '{"nested":true}' "raw")
    [ "$result" = '{"nested":true}' ]
}

# =============================================================================
# json_array TESTS
# =============================================================================

@test "json_array creates basic array" {
    local result
    result=$(json_array "a" "b" "c")
    [ "$result" = '["a","b","c"]' ]
}

@test "json_array creates empty array" {
    local result
    result=$(json_array)
    [ "$result" = '[]' ]
}

@test "json_array single element" {
    local result
    result=$(json_array "only")
    [ "$result" = '["only"]' ]
}

@test "json_array auto-detects number types" {
    local result
    result=$(json_array "1" "2" "3")
    [ "$result" = '[1,2,3]' ]
}

@test "json_array auto-detects mixed types" {
    local result
    result=$(json_array "hello" "42" "true")
    [ "$result" = '["hello",42,true]' ]
}

@test "json_array handles special characters in values" {
    local result
    result=$(json_array 'say "hi"' "normal")
    [ "$result" = '["say \"hi\"","normal"]' ]
}

# =============================================================================
# json_array_typed TESTS
# =============================================================================

@test "json_array_typed forces string type" {
    local result
    result=$(json_array_typed "string" "42" "true" "hello")
    [ "$result" = '["42","true","hello"]' ]
}

@test "json_array_typed forces number type" {
    local result
    result=$(json_array_typed "number" "1" "2" "3")
    [ "$result" = '[1,2,3]' ]
}

@test "json_array_typed empty typed array" {
    local result
    result=$(json_array_typed "string")
    [ "$result" = '[]' ]
}

# =============================================================================
# json_array_from_lines TESTS
# =============================================================================

@test "json_array_from_lines creates array from pipe" {
    local result
    result=$(printf 'alpha\nbeta\ngamma\n' | json_array_from_lines)
    [ "$result" = '["alpha","beta","gamma"]' ]
}

@test "json_array_from_lines single line" {
    local result
    result=$(printf 'only\n' | json_array_from_lines)
    [ "$result" = '["only"]' ]
}

@test "json_array_from_lines escapes content" {
    local result
    result=$(printf 'say "hello"\nnormal\n' | json_array_from_lines)
    [ "$result" = '["say \"hello\"","normal"]' ]
}

# =============================================================================
# json_object TESTS
# =============================================================================

@test "json_object creates basic object" {
    local result
    result=$(json_object "name=John" "city=NYC")
    [ "$result" = '{"name":"John","city":"NYC"}' ]
}

@test "json_object creates empty object" {
    local result
    result=$(json_object)
    [ "$result" = '{}' ]
}

@test "json_object handles number type" {
    local result
    result=$(json_object "age:number=30")
    [ "$result" = '{"age":30}' ]
}

@test "json_object handles bool type" {
    local result
    result=$(json_object "active:bool=true")
    [ "$result" = '{"active":true}' ]
}

@test "json_object handles null type" {
    local result
    result=$(json_object "deleted:null=")
    [ "$result" = '{"deleted":null}' ]
}

@test "json_object handles multiple typed values" {
    local result
    result=$(json_object "name=John" "age:number=30" "active:bool=true")
    [ "$result" = '{"name":"John","age":30,"active":true}' ]
}

@test "json_object handles empty value" {
    local result
    result=$(json_object "empty=")
    [ "$result" = '{"empty":""}' ]
}

@test "json_object handles value with equals sign" {
    local result
    result=$(json_object "expr=a=b")
    [ "$result" = '{"expr":"a=b"}' ]
}

@test "json_object handles special characters in value" {
    local result
    result=$(json_object 'msg=say "hi"')
    [ "$result" = '{"msg":"say \"hi\""}' ]
}

@test "json_object handles malformed pairs" {
    local result
    result=$(json_object "good=val" "badpair" "also_good=yes")
    # Malformed pairs produce empty value in current implementation
    assert_contains "$result" '"good":"val"'
    assert_contains "$result" '"also_good":"yes"'
}

@test "json_object auto-detects numeric strings" {
    local result
    result=$(json_object "count=42")
    [ "$result" = '{"count":42}' ]
}

@test "json_object auto-detects boolean strings" {
    local result
    result=$(json_object "flag=true")
    [ "$result" = '{"flag":true}' ]
}

@test "json_object auto-detects null string" {
    local result
    result=$(json_object "val=null")
    [ "$result" = '{"val":null}' ]
}

@test "json_object explicit string forces quoting" {
    local result
    result=$(json_object "port:string=8080")
    [ "$result" = '{"port":"8080"}' ]
}

@test "json_object handles raw type for nested JSON" {
    local result
    result=$(json_object 'inner:raw={"x":1}')
    [ "$result" = '{"inner":{"x":1}}' ]
}

# =============================================================================
# json_from_assoc TESTS
# =============================================================================

@test "json_from_assoc creates object from associative array" {
    declare -A data=([name]="Alice")
    local result
    result=$(json_from_assoc data)
    [ "$result" = '{"name":"Alice"}' ]
}

@test "json_from_assoc handles numeric values" {
    declare -A data=([count]="42")
    local result
    result=$(json_from_assoc data)
    [ "$result" = '{"count":42}' ]
}

@test "json_from_assoc handles empty associative array" {
    declare -A empty=()
    local result
    result=$(json_from_assoc empty)
    [ "$result" = '{}' ]
}

# =============================================================================
# json_nested TESTS
# =============================================================================

@test "json_nested creates single-level nesting" {
    local result
    result=$(json_nested "key" "value")
    [ "$result" = '{"key":"value"}' ]
}

@test "json_nested creates two-level nesting" {
    local result
    result=$(json_nested "a.b" "val")
    [ "$result" = '{"a":{"b":"val"}}' ]
}

@test "json_nested creates three-level nesting" {
    local result
    result=$(json_nested "a.b.c" "deep")
    [ "$result" = '{"a":{"b":{"c":"deep"}}}' ]
}

@test "json_nested handles numeric value" {
    local result
    result=$(json_nested "config.port" "8080")
    [ "$result" = '{"config":{"port":8080}}' ]
}

@test "json_nested handles boolean value" {
    local result
    result=$(json_nested "config.debug" "true")
    [ "$result" = '{"config":{"debug":true}}' ]
}

# =============================================================================
# json_merge TESTS
# =============================================================================

@test "json_merge combines two objects" {
    local result
    result=$(json_merge '{"a":1}' '{"b":2}')
    [ "$result" = '{"a":1,"b":2}' ]
}

@test "json_merge handles empty first object" {
    local result
    result=$(json_merge '{}' '{"b":2}')
    [ "$result" = '{"b":2}' ]
}

@test "json_merge handles empty second object" {
    local result
    result=$(json_merge '{"a":1}' '{}')
    [ "$result" = '{"a":1}' ]
}

@test "json_merge handles both empty objects" {
    local result
    result=$(json_merge '{}' '{}')
    [ "$result" = '{}' ]
}

@test "json_merge combines three objects" {
    local result
    result=$(json_merge '{"a":1}' '{"b":2}' '{"c":3}')
    [ "$result" = '{"a":1,"b":2,"c":3}' ]
}

@test "json_merge handles string values" {
    local result
    result=$(json_merge '{"name":"John"}' '{"city":"NYC"}')
    [ "$result" = '{"name":"John","city":"NYC"}' ]
}

# =============================================================================
# json_pretty TESTS
# =============================================================================

@test "json_pretty formats simple object" {
    local result
    result=$(json_pretty '{"a":1}')
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *': '* ]]
}

@test "json_pretty adds newlines" {
    local result
    result=$(json_pretty '{"a":1,"b":2}')
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -gt 1 ]
}

@test "json_pretty handles nested objects" {
    local result
    result=$(json_pretty '{"a":{"b":1}}')
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *'"b"'* ]]
}

@test "json_pretty handles arrays" {
    local result
    result=$(json_pretty '[1,2,3]')
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -gt 1 ]
}

@test "json_pretty preserves string content with special chars" {
    local result
    result=$(json_pretty '{"msg":"hello world"}')
    [[ "$result" == *'"hello world"'* ]]
}

# =============================================================================
# json_valid TESTS
# =============================================================================

@test "json_valid accepts valid object" {
    json_valid '{"a":1}'
}

@test "json_valid accepts valid array" {
    json_valid '[1,2,3]'
}

@test "json_valid accepts nested structure" {
    json_valid '{"a":{"b":[1,2,3]}}'
}

@test "json_valid accepts empty object" {
    json_valid '{}'
}

@test "json_valid accepts empty array" {
    json_valid '[]'
}

@test "json_valid accepts string with braces inside" {
    json_valid '{"msg":"use {braces} here"}'
}

@test "json_valid rejects empty string" {
    ! json_valid ""
}

@test "json_valid rejects whitespace only" {
    ! json_valid "   "
}

@test "json_valid rejects unbalanced open brace" {
    ! json_valid '{"a":1'
}

@test "json_valid rejects unbalanced close brace" {
    ! json_valid '"a":1}'
}

@test "json_valid rejects unclosed string" {
    ! json_valid '{"key":"unclosed'
}

@test "json_valid accepts escaped quotes in strings" {
    json_valid '{"msg":"say \"hi\""}'
}

@test "json_valid rejects extra closing bracket" {
    ! json_valid '[1,2,3]]'
}

# =============================================================================
# json_get TESTS
# =============================================================================

@test "json_get extracts string value" {
    local result
    result=$(json_get '{"name":"John"}' "name")
    [ "$result" = "John" ]
}

@test "json_get extracts numeric value" {
    local result
    result=$(json_get '{"age":30}' "age")
    [ "$result" = "30" ]
}

@test "json_get extracts boolean true" {
    local result
    result=$(json_get '{"active":true}' "active")
    [ "$result" = "true" ]
}

@test "json_get extracts boolean false" {
    local result
    result=$(json_get '{"active":false}' "active")
    [ "$result" = "false" ]
}

@test "json_get extracts null" {
    local result
    result=$(json_get '{"val":null}' "val")
    [ "$result" = "null" ]
}

@test "json_get returns failure for missing key" {
    ! json_get '{"name":"John"}' "missing"
}

@test "json_get handles spaces around colon" {
    local result
    result=$(json_get '{"name" : "John"}' "name")
    [ "$result" = "John" ]
}

@test "json_get extracts negative number" {
    local result
    result=$(json_get '{"offset":-5}' "offset")
    [ "$result" = "-5" ]
}

@test "json_get extracts float" {
    local result
    result=$(json_get '{"rate":3.14}' "rate")
    [ "$result" = "3.14" ]
}

@test "json_get from multi-key object" {
    local result
    result=$(json_get '{"name":"John","age":30,"city":"NYC"}' "city")
    [ "$result" = "NYC" ]
}

# =============================================================================
# json_keys TESTS
# =============================================================================

@test "json_keys extracts all top-level keys" {
    local result
    result=$(json_keys '{"a":1,"b":2,"c":3}')
    [[ "$result" == *"a"* ]]
    [[ "$result" == *"b"* ]]
    [[ "$result" == *"c"* ]]
}

@test "json_keys returns empty for empty object" {
    local result
    result=$(json_keys '{}')
    [ -z "$result" ]
}

@test "json_keys ignores nested keys" {
    local result
    result=$(json_keys '{"outer":{"inner":1}}')
    [[ "$result" == *"outer"* ]]
    [[ "$result" != *"inner"* ]]
}

@test "json_keys handles single key" {
    local result
    result=$(json_keys '{"only":1}')
    [ "$(echo "$result" | tr -d '\n')" = "only" ]
}

# =============================================================================
# json_read / json_write / json_write_pretty TESTS
# =============================================================================

@test "json_write creates file with JSON" {
    json_write "$TEST_DIR/out.json" '{"status":"ok"}'
    [ -f "$TEST_DIR/out.json" ]
    local content
    content=$(<"$TEST_DIR/out.json")
    [ "$content" = '{"status":"ok"}' ]
}

@test "json_read reads JSON from file" {
    echo -n '{"name":"test"}' > "$TEST_DIR/in.json"
    local result
    result=$(json_read "$TEST_DIR/in.json")
    [ "$result" = '{"name":"test"}' ]
}

@test "json_read returns empty for missing file" {
    local result
    result=$(json_read "$TEST_DIR/nonexistent.json") || true
    [ -z "$result" ]
}

@test "json_write_pretty creates formatted file" {
    json_write_pretty "$TEST_DIR/pretty.json" '{"a":1,"b":2}'
    [ -f "$TEST_DIR/pretty.json" ]
    local lines
    lines=$(wc -l < "$TEST_DIR/pretty.json")
    [ "$lines" -gt 1 ]
}

@test "json_write overwrites existing file" {
    json_write "$TEST_DIR/over.json" '{"old":true}'
    json_write "$TEST_DIR/over.json" '{"new":true}'
    local content
    content=$(<"$TEST_DIR/over.json")
    [ "$content" = '{"new":true}' ]
}

# =============================================================================
# NAMEREF VARIANTS (_v) TESTS
# =============================================================================

@test "json_escape_v stores result in variable" {
    local out
    json_escape_v out 'say "hi"'
    [ "$out" = 'say \"hi\"' ]
}

@test "json_escape_v handles newlines" {
    local out
    json_escape_v out $'line1\nline2'
    [ "$out" = 'line1\nline2' ]
}

@test "json_escape_v handles empty string" {
    local out
    json_escape_v out ""
    [ "$out" = "" ]
}

@test "json_string_v stores quoted string" {
    local out
    json_string_v out "hello"
    [ "$out" = '"hello"' ]
}

@test "json_string_v escapes content" {
    local out
    json_string_v out 'with "quotes"'
    [ "$out" = '"with \"quotes\""' ]
}

@test "json_number_v stores valid number" {
    local out
    json_number_v out "42"
    [ "$out" = "42" ]
}

@test "json_number_v stores null for invalid" {
    local out
    ! json_number_v out "abc"
    [ "$out" = "null" ]
}

@test "json_bool_v stores true" {
    local out
    json_bool_v out "yes"
    [ "$out" = "true" ]
}

@test "json_bool_v stores false" {
    local out
    json_bool_v out "off"
    [ "$out" = "false" ]
}

@test "json_bool_v stores null for invalid" {
    local out
    ! json_bool_v out "maybe"
    [ "$out" = "null" ]
}

@test "json_value_v auto-detects number" {
    local out
    json_value_v out "99"
    [ "$out" = "99" ]
}

@test "json_value_v auto-detects string" {
    local out
    json_value_v out "hello"
    [ "$out" = '"hello"' ]
}

@test "json_value_v explicit string type" {
    local out
    json_value_v out "42" "string"
    [ "$out" = '"42"' ]
}

@test "json_value_v explicit null type" {
    local out
    json_value_v out "anything" "null"
    [ "$out" = "null" ]
}

@test "json_value_v raw passes through" {
    local out
    json_value_v out '{"x":1}' "raw"
    [ "$out" = '{"x":1}' ]
}

@test "json_array_v creates array in variable" {
    local out
    json_array_v out "a" "b" "c"
    [ "$out" = '["a","b","c"]' ]
}

@test "json_array_v creates empty array" {
    local out
    json_array_v out
    [ "$out" = '[]' ]
}

@test "json_array_v auto-detects types" {
    local out
    json_array_v out "hello" "42" "true"
    [ "$out" = '["hello",42,true]' ]
}

@test "json_array_typed_v forces string type" {
    local out
    json_array_typed_v out "string" "42" "true"
    [ "$out" = '["42","true"]' ]
}

@test "json_object_v creates basic object" {
    local out
    json_object_v out "name=John" "age:number=30"
    [ "$out" = '{"name":"John","age":30}' ]
}

@test "json_object_v creates empty object" {
    local out
    json_object_v out
    [ "$out" = '{}' ]
}

@test "json_object_v handles bool type" {
    local out
    json_object_v out "active:bool=true"
    [ "$out" = '{"active":true}' ]
}

@test "json_object_v handles multiple types" {
    local out
    json_object_v out "name=Alice" "score:number=95" "passed:bool=yes"
    [ "$out" = '{"name":"Alice","score":95,"passed":true}' ]
}

@test "json_object_v escapes key with special chars" {
    local out
    json_object_v out 'key "name"=value'
    [ "$out" = '{"key \"name\"":"value"}' ]
}

@test "json_from_assoc_v creates object from associative array" {
    declare -A data=([city]="NYC")
    local out
    json_from_assoc_v out data
    [ "$out" = '{"city":"NYC"}' ]
}

@test "json_nested_v creates nested object" {
    local out
    json_nested_v out "a.b" "val"
    [ "$out" = '{"a":{"b":"val"}}' ]
}

@test "json_nested_v handles deep nesting" {
    local out
    json_nested_v out "x.y.z" "deep"
    [ "$out" = '{"x":{"y":{"z":"deep"}}}' ]
}

@test "json_nested_v detects numeric value" {
    local out
    json_nested_v out "config.port" "8080"
    [ "$out" = '{"config":{"port":8080}}' ]
}

@test "json_get_v extracts string value" {
    local out
    json_get_v out '{"name":"Alice"}' "name"
    [ "$out" = "Alice" ]
}

@test "json_get_v extracts numeric value" {
    local out
    json_get_v out '{"port":8080}' "port"
    [ "$out" = "8080" ]
}

@test "json_get_v fails for missing key" {
    local out
    ! json_get_v out '{"a":1}' "missing"
    [ "$out" = "" ]
}

@test "json_merge_v combines objects" {
    local out
    json_merge_v out '{"a":1}' '{"b":2}'
    [ "$out" = '{"a":1,"b":2}' ]
}

@test "json_merge_v handles empty objects" {
    local out
    json_merge_v out '{}' '{"b":2}'
    [ "$out" = '{"b":2}' ]
}

@test "json_pretty_v formats into variable" {
    local out
    json_pretty_v out '{"a":1}'
    [[ "$out" == *'"a"'* ]]
    [[ "$out" == *$'\n'* ]]
}

# =============================================================================
# EDGE CASES & INTEGRATION TESTS
# =============================================================================

@test "roundtrip: json_object then json_get" {
    local json
    json=$(json_object "user=alice" "role=admin")
    local user role
    user=$(json_get "$json" "user")
    role=$(json_get "$json" "role")
    [ "$user" = "alice" ]
    [ "$role" = "admin" ]
}

@test "roundtrip: json_write then json_read" {
    local original='{"key":"value","num":42}'
    json_write "$TEST_DIR/rt.json" "$original"
    local restored
    restored=$(json_read "$TEST_DIR/rt.json")
    [ "$restored" = "$original" ]
}

@test "json_object with long string value" {
    local long_val
    long_val=$(printf 'a%.0s' {1..200})
    local result
    result=$(json_object "data=$long_val")
    [[ "$result" == '{"data":"'* ]]
    [[ "$result" == *'"}' ]]
}

@test "json_array with many elements" {
    local result
    result=$(json_array "1" "2" "3" "4" "5" "6" "7" "8" "9" "10")
    [ "$result" = '[1,2,3,4,5,6,7,8,9,10]' ]
}

@test "json_merge preserves later values for overlapping keys" {
    local result
    result=$(json_merge '{"a":1,"b":2}' '{"b":3,"c":4}')
    # merge is simple concatenation - both b values present
    [[ "$result" == '{"a":1,"b":2,"b":3,"c":4}' ]]
}

@test "json_object handles newline in value" {
    local result
    result=$(json_object "msg=hello
world")
    [[ "$result" == '{"msg":"hello\nworld"}' ]]
}

@test "json_object handles tab in value" {
    local result
    result=$(json_object $'col=val1\tval2')
    [[ "$result" == '{"col":"val1\tval2"}' ]]
}

@test "json_valid with deeply nested braces" {
    json_valid '{"a":{"b":{"c":{"d":1}}}}'
}

@test "json_valid rejects mismatched bracket types" {
    ! json_valid '{"a":[1,2}'
}

@test "json_escape handles all escape sequences together" {
    local result
    result=$(json_escape $'"\\\/\b\f\n\r\t')
    [[ "$result" == *'\"'* ]]
    [[ "$result" == *'\\'* ]]
    [[ "$result" == *'\n'* ]]
    [[ "$result" == *'\r'* ]]
    [[ "$result" == *'\t'* ]]
    [[ "$result" == *'\b'* ]]
    [[ "$result" == *'\f'* ]]
}

@test "performance: _v variants avoid subshell (basic check)" {
    # Verify _v variant produces same result as subshell variant
    local subshell_result
    subshell_result=$(json_object "x=1" "y:number=2")
    local nameref_result
    json_object_v nameref_result "x=1" "y:number=2"
    [ "$subshell_result" = "$nameref_result" ]
}

@test "performance: json_array_v matches json_array output" {
    local subshell_result
    subshell_result=$(json_array "hello" "42" "true" "null")
    local nameref_result
    json_array_v nameref_result "hello" "42" "true" "null"
    [ "$subshell_result" = "$nameref_result" ]
}

@test "performance: json_nested_v matches json_nested output" {
    local subshell_result
    subshell_result=$(json_nested "a.b.c" "deep")
    local nameref_result
    json_nested_v nameref_result "a.b.c" "deep"
    [ "$subshell_result" = "$nameref_result" ]
}

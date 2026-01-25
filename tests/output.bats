#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Universal Structured Output Protocol (USOP) Tests
# =============================================================================
# Tests for lib/output.sh - Mode detection, envelopes, mainframe_call, helpers
# =============================================================================

load 'test_helper'

setup() {
    source_lib "output"
    # Reset output mode to default before each test
    MAINFRAME_OUTPUT="text"
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

@test "MAINFRAME_OUTPUT defaults to text" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/output.sh"; printf "%s" "$MAINFRAME_OUTPUT"'
    [ "$status" -eq 0 ]
    [ "$output" = "text" ]
}

@test "double-source guard prevents reloading" {
    [ "$_MAINFRAME_OUTPUT_LOADED" = "1" ]
}

# =============================================================================
# OUTPUT MODE DETECTION TESTS
# =============================================================================

@test "output_is_json returns 1 when MAINFRAME_OUTPUT=text" {
    MAINFRAME_OUTPUT="text"
    run output_is_json
    [ "$status" -ne 0 ]
}

@test "output_is_json returns 0 when MAINFRAME_OUTPUT=json" {
    MAINFRAME_OUTPUT="json"
    run output_is_json
    [ "$status" -eq 0 ]
}

@test "output_is_json returns 1 when MAINFRAME_OUTPUT is unset" {
    unset MAINFRAME_OUTPUT
    run output_is_json
    [ "$status" -ne 0 ]
}

@test "output_format returns text by default" {
    MAINFRAME_OUTPUT="text"
    run output_format
    [ "$status" -eq 0 ]
    [ "$output" = "text" ]
}

@test "output_format returns json when MAINFRAME_OUTPUT=json" {
    MAINFRAME_OUTPUT="json"
    run output_format
    [ "$status" -eq 0 ]
    [ "$output" = "json" ]
}

# =============================================================================
# JSON ESCAPE TESTS
# =============================================================================

@test "output_json_escape handles plain string" {
    run output_json_escape "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "output_json_escape escapes double quotes" {
    run output_json_escape 'say "hello"'
    [ "$status" -eq 0 ]
    [ "$output" = 'say \"hello\"' ]
}

@test "output_json_escape escapes backslashes" {
    run output_json_escape 'path\to\file'
    [ "$status" -eq 0 ]
    [ "$output" = 'path\\to\\file' ]
}

@test "output_json_escape escapes newlines" {
    local input=$'line1\nline2'
    run output_json_escape "$input"
    [ "$status" -eq 0 ]
    [ "$output" = 'line1\nline2' ]
}

@test "output_json_escape escapes tabs" {
    local input=$'col1\tcol2'
    run output_json_escape "$input"
    [ "$status" -eq 0 ]
    [ "$output" = 'col1\tcol2' ]
}

@test "output_json_escape escapes carriage returns" {
    local input=$'hello\rworld'
    run output_json_escape "$input"
    [ "$status" -eq 0 ]
    [ "$output" = 'hello\rworld' ]
}

@test "output_json_escape escapes backspace" {
    local input=$'hello\bworld'
    run output_json_escape "$input"
    [ "$status" -eq 0 ]
    [ "$output" = 'hello\bworld' ]
}

@test "output_json_escape escapes form feed" {
    local input=$'hello\fworld'
    run output_json_escape "$input"
    [ "$status" -eq 0 ]
    [ "$output" = 'hello\fworld' ]
}

@test "output_json_escape escapes control characters as unicode" {
    local input=$'\x01\x02\x03'
    run output_json_escape "$input"
    [ "$status" -eq 0 ]
    [ "$output" = '\u0001\u0002\u0003' ]
}

@test "output_json_escape handles empty string" {
    run output_json_escape ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "output_json_escape handles combined special chars" {
    local input=$'quote:"val"\nnewline\ttab\\slash'
    run output_json_escape "$input"
    [ "$status" -eq 0 ]
    [ "$output" = 'quote:\"val\"\nnewline\ttab\\slash' ]
}

# =============================================================================
# JSON HELPER TESTS
# =============================================================================

@test "output_json_string emits key-value pair" {
    run output_json_string "name" "John"
    [ "$status" -eq 0 ]
    [ "$output" = '"name":"John"' ]
}

@test "output_json_string escapes value" {
    run output_json_string "msg" 'say "hi"'
    [ "$status" -eq 0 ]
    [ "$output" = '"msg":"say \"hi\""' ]
}

@test "output_json_string escapes key" {
    run output_json_string 'key "1"' "value"
    [ "$status" -eq 0 ]
    [ "$output" = '"key \"1\"":"value"' ]
}

@test "output_json_number emits integer" {
    run output_json_number "age" "30"
    [ "$status" -eq 0 ]
    [ "$output" = '"age":30' ]
}

@test "output_json_number emits float" {
    run output_json_number "pi" "3.14"
    [ "$status" -eq 0 ]
    [ "$output" = '"pi":3.14' ]
}

@test "output_json_number emits negative" {
    run output_json_number "offset" "-5"
    [ "$status" -eq 0 ]
    [ "$output" = '"offset":-5' ]
}

@test "output_json_number emits scientific notation" {
    run output_json_number "big" "1.5e10"
    [ "$status" -eq 0 ]
    [ "$output" = '"big":1.5e10' ]
}

@test "output_json_number returns null for invalid" {
    run output_json_number "bad" "abc"
    [ "$status" -eq 1 ]
    [ "$output" = '"bad":null' ]
}

@test "output_json_bool emits true" {
    run output_json_bool "active" "true"
    [ "$status" -eq 0 ]
    [ "$output" = '"active":true' ]
}

@test "output_json_bool emits false" {
    run output_json_bool "active" "false"
    [ "$status" -eq 0 ]
    [ "$output" = '"active":false' ]
}

@test "output_json_bool handles yes/no" {
    run output_json_bool "flag" "yes"
    [ "$status" -eq 0 ]
    [ "$output" = '"flag":true' ]
}

@test "output_json_bool handles 1/0" {
    run output_json_bool "flag" "0"
    [ "$status" -eq 0 ]
    [ "$output" = '"flag":false' ]
}

@test "output_json_bool returns null for invalid" {
    run output_json_bool "flag" "maybe"
    [ "$status" -eq 1 ]
    [ "$output" = '"flag":null' ]
}

@test "output_json_null emits null" {
    run output_json_null "value"
    [ "$status" -eq 0 ]
    [ "$output" = '"value":null' ]
}

@test "output_json_array_from_lines converts lines to array" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/output.sh"; printf "alpha\nbeta\ngamma" | output_json_array_from_lines'
    [ "$status" -eq 0 ]
    [ "$output" = '["alpha","beta","gamma"]' ]
}

@test "output_json_array_from_lines handles single line" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/output.sh"; printf "only" | output_json_array_from_lines'
    [ "$status" -eq 0 ]
    [ "$output" = '["only"]' ]
}

@test "output_json_array_from_lines escapes special chars in lines" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/output.sh"; printf "say \"hi\"\npath\\\\file" | output_json_array_from_lines'
    [ "$status" -eq 0 ]
    [[ "$output" == *'\"hi\"'* ]]
}

# =============================================================================
# USOP ENVELOPE: output_success TESTS
# =============================================================================

@test "output_success emits basic envelope" {
    run output_success "hello"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":"hello"}' ]
}

@test "output_success includes message when provided" {
    run output_success "result" "Operation completed"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":"result","message":"Operation completed"}' ]
}

@test "output_success escapes data" {
    run output_success 'say "hi"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'say \"hi\"'* ]]
}

@test "output_success handles empty data" {
    run output_success ""
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":""}' ]
}

@test "output_success escapes message with newline" {
    run output_success "data" $'line1\nline2'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"message":"line1\nline2"'* ]]
}

@test "output_success handles multiline data" {
    local data=$'line1\nline2\nline3'
    run output_success "$data"
    [ "$status" -eq 0 ]
    [[ "$output" == *'line1\nline2\nline3'* ]]
}

@test "output_success without message omits message field" {
    run output_success "data"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"message"'* ]]
}

# =============================================================================
# USOP ENVELOPE: output_error TESTS
# =============================================================================

@test "output_error emits basic error envelope" {
    run output_error "something broke"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"error","error":"something broke","code":1}' ]
}

@test "output_error uses custom exit code" {
    run output_error "not found" 404
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"error","error":"not found","code":404}' ]
}

@test "output_error includes context" {
    run output_error "failed" 1 "during file read"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"error","error":"failed","code":1,"context":"during file read"}' ]
}

@test "output_error escapes error message" {
    run output_error 'file "test.txt" not found'
    [ "$status" -eq 0 ]
    [[ "$output" == *'file \"test.txt\" not found'* ]]
}

@test "output_error escapes context" {
    run output_error "failed" 1 'path: /tmp/"foo"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'path: /tmp/\"foo\"'* ]]
}

@test "output_error without context omits context field" {
    run output_error "error msg" 2
    [ "$status" -eq 0 ]
    [[ "$output" != *'"context"'* ]]
}

@test "output_error defaults exit code to 1" {
    run output_error "default code"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"code":1'* ]]
}

@test "output_error handles zero exit code" {
    run output_error "weird error" 0
    [ "$status" -eq 0 ]
    [[ "$output" == *'"code":0'* ]]
}

# =============================================================================
# USOP ENVELOPE: output_list TESTS
# =============================================================================

@test "output_list emits array envelope" {
    run output_list "apple" "banana" "cherry"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":["apple","banana","cherry"],"count":3}' ]
}

@test "output_list handles single item" {
    run output_list "only"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":["only"],"count":1}' ]
}

@test "output_list handles no items" {
    run output_list
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":[],"count":0}' ]
}

@test "output_list escapes items with quotes" {
    run output_list 'say "hi"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'say \"hi\"'* ]]
}

@test "output_list escapes items with backslash" {
    run output_list 'path\to'
    [ "$status" -eq 0 ]
    [[ "$output" == *'path\\to'* ]]
}

@test "output_list reports correct count" {
    run output_list a b c d e
    [ "$status" -eq 0 ]
    [[ "$output" == *'"count":5'* ]]
}

@test "output_list handles items with newlines" {
    run output_list $'multi\nline'
    [ "$status" -eq 0 ]
    [[ "$output" == *'multi\nline'* ]]
}

# =============================================================================
# USOP ENVELOPE: output_object TESTS
# =============================================================================

@test "output_object emits string key-value pairs" {
    run output_object "name=John" "city=NYC"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":{"name":"John","city":"NYC"}}' ]
}

@test "output_object handles number type" {
    run output_object "age:number=30"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":{"age":30}}' ]
}

@test "output_object handles bool type true" {
    run output_object "active:bool=true"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":{"active":true}}' ]
}

@test "output_object handles bool type false" {
    run output_object "active:bool=false"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":{"active":false}}' ]
}

@test "output_object handles null type" {
    run output_object "value:null="
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":{"value":null}}' ]
}

@test "output_object handles mixed types" {
    run output_object "name=John" "age:number=30" "active:bool=true"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name":"John"'* ]]
    [[ "$output" == *'"age":30'* ]]
    [[ "$output" == *'"active":true'* ]]
}

@test "output_object handles raw type" {
    run output_object 'items:raw=["a","b"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"items":["a","b"]'* ]]
}

@test "output_object escapes string values" {
    run output_object 'msg=say "hi"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'say \"hi\"'* ]]
}

@test "output_object handles invalid number gracefully" {
    run output_object "count:number=abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"count":null'* ]]
}

@test "output_object handles invalid bool gracefully" {
    run output_object "flag:bool=maybe"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"flag":null'* ]]
}

@test "output_object skips malformed pairs" {
    run output_object "valid=yes" "malformed" "also_valid=true"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"valid":"yes"'* ]]
    [[ "$output" == *'"also_valid":"true"'* ]]
}

@test "output_object handles float number" {
    run output_object "pi:number=3.14159"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"pi":3.14159'* ]]
}

@test "output_object handles negative number" {
    run output_object "offset:number=-10"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"offset":-10'* ]]
}

@test "output_object handles value with equals sign" {
    run output_object "equation=1+1=2"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"equation":"1+1=2"'* ]]
}

@test "output_object handles empty value" {
    run output_object "key="
    [ "$status" -eq 0 ]
    [[ "$output" == *'"key":""'* ]]
}

@test "output_object handles single pair" {
    run output_object "solo=value"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":{"solo":"value"}}' ]
}

@test "output_object handles bool yes/no/on/off" {
    run output_object "a:bool=yes" "b:bool=no" "c:bool=on" "d:bool=off"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a":true'* ]]
    [[ "$output" == *'"b":false'* ]]
    [[ "$output" == *'"c":true'* ]]
    [[ "$output" == *'"d":false'* ]]
}

@test "output_object handles scientific notation number" {
    run output_object "big:number=1.5e10"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"big":1.5e10'* ]]
}

# =============================================================================
# USOP ENVELOPE: output_progress TESTS
# =============================================================================

@test "output_progress emits progress envelope" {
    run output_progress "downloading" 3 10
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"progress","step":"downloading","current":3,"total":10}' ]
}

@test "output_progress includes message" {
    run output_progress "processing" 5 20 "Halfway there"
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"progress","step":"processing","current":5,"total":20,"message":"Halfway there"}' ]
}

@test "output_progress escapes step name" {
    run output_progress 'step "1"' 1 5
    [ "$status" -eq 0 ]
    [[ "$output" == *'step \"1\"'* ]]
}

@test "output_progress escapes message" {
    run output_progress "step" 1 5 'file "x.txt"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'file \"x.txt\"'* ]]
}

@test "output_progress handles zero values" {
    run output_progress "init" 0 0
    [ "$status" -eq 0 ]
    [[ "$output" == *'"current":0'* ]]
    [[ "$output" == *'"total":0'* ]]
}

@test "output_progress without message omits message field" {
    run output_progress "step" 1 5
    [ "$status" -eq 0 ]
    [[ "$output" != *'"message"'* ]]
}

@test "output_progress with large numbers" {
    run output_progress "scan" 999999 1000000
    [ "$status" -eq 0 ]
    [[ "$output" == *'"current":999999'* ]]
    [[ "$output" == *'"total":1000000'* ]]
}

# =============================================================================
# mainframe_call META-WRAPPER TESTS
# =============================================================================

@test "mainframe_call wraps successful function" {
    _test_hello() { printf "hello world"; }
    run mainframe_call _test_hello
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"success"'* ]]
    [[ "$output" == *'"function":"_test_hello"'* ]]
    [[ "$output" == *'"data":"hello world"'* ]]
    [[ "$output" == *'"exit_code":0'* ]]
    [[ "$output" == *'"duration_ms":'* ]]
}

@test "mainframe_call wraps failing function" {
    _test_fail() { printf "error output" >&2; return 1; }
    run mainframe_call _test_fail
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status":"error"'* ]]
    [[ "$output" == *'"exit_code":1'* ]]
    [[ "$output" == *'"stderr":"error output"'* ]]
}

@test "mainframe_call handles nonexistent function" {
    run mainframe_call "nonexistent_function_xyz"
    [ "$status" -eq 127 ]
    [[ "$output" == *'"status":"error"'* ]]
    [[ "$output" == *'"exit_code":127'* ]]
    [[ "$output" == *'Function not found'* ]]
}

@test "mainframe_call passes arguments" {
    _test_echo_args() { printf "%s %s" "$1" "$2"; }
    run mainframe_call _test_echo_args "foo" "bar"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"data":"foo bar"'* ]]
}

@test "mainframe_call captures stderr separately" {
    _test_both() { printf "stdout"; printf "stderr" >&2; }
    run mainframe_call _test_both
    [ "$status" -eq 0 ]
    [[ "$output" == *'"data":"stdout"'* ]]
    [[ "$output" == *'"stderr":"stderr"'* ]]
}

@test "mainframe_call omits stderr when empty" {
    _test_stdout_only() { printf "just stdout"; }
    run mainframe_call _test_stdout_only
    [ "$status" -eq 0 ]
    [[ "$output" != *'"stderr"'* ]]
}

@test "mainframe_call handles empty output" {
    _test_empty() { :; }
    run mainframe_call _test_empty
    [ "$status" -eq 0 ]
    [[ "$output" == *'"data":""'* ]]
    [[ "$output" == *'"status":"success"'* ]]
}

@test "mainframe_call captures nonzero exit codes" {
    _test_exit42() { return 42; }
    run mainframe_call _test_exit42
    [ "$status" -eq 42 ]
    [[ "$output" == *'"exit_code":42'* ]]
    [[ "$output" == *'"status":"error"'* ]]
}

@test "mainframe_call duration_ms is non-negative" {
    _test_quick() { printf "fast"; }
    run mainframe_call _test_quick
    [ "$status" -eq 0 ]
    # Extract duration_ms value
    local duration
    duration=$(printf '%s' "$output" | grep -o '"duration_ms":[0-9]*' | grep -o '[0-9]*$')
    [ "$duration" -ge 0 ]
}

@test "mainframe_call escapes multiline stdout" {
    _test_multiline() { printf "line1\nline2\nline3"; }
    run mainframe_call _test_multiline
    [ "$status" -eq 0 ]
    [[ "$output" == *'"data":"line1\nline2\nline3"'* ]]
}

@test "mainframe_call escapes tabs in stdout" {
    _test_tabs() { printf "col1\tcol2\tcol3"; }
    run mainframe_call _test_tabs
    [ "$status" -eq 0 ]
    [[ "$output" == *'"data":"col1\tcol2\tcol3"'* ]]
}

@test "mainframe_call escapes quotes in stdout" {
    _test_quotes() { printf 'say "hello"'; }
    run mainframe_call _test_quotes
    [ "$status" -eq 0 ]
    [[ "$output" == *'say \"hello\"'* ]]
}

@test "mainframe_call escapes function name with special chars" {
    eval '_test_func_123() { printf "ok"; }'
    run mainframe_call "_test_func_123"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"function":"_test_func_123"'* ]]
}

# =============================================================================
# CONDITIONAL OUTPUT: output_auto TESTS
# =============================================================================

@test "output_auto outputs text in text mode" {
    MAINFRAME_OUTPUT="text"
    run output_auto "plain result" '{"status":"success","data":"plain result"}'
    [ "$status" -eq 0 ]
    [ "$output" = "plain result" ]
}

@test "output_auto outputs json in json mode" {
    MAINFRAME_OUTPUT="json"
    run output_auto "plain result" '{"status":"success","data":"plain result"}'
    [ "$status" -eq 0 ]
    [ "$output" = '{"status":"success","data":"plain result"}' ]
}

@test "output_auto defaults to text mode when unset" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/output.sh"; output_auto "text_out" "json_out"'
    [ "$status" -eq 0 ]
    [ "$output" = "text_out" ]
}

@test "output_auto handles empty text" {
    MAINFRAME_OUTPUT="text"
    run output_auto "" '{"status":"success","data":""}'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "output_auto handles empty json" {
    MAINFRAME_OUTPUT="json"
    run output_auto "text" ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# =============================================================================
# EDGE CASE / INTEGRATION TESTS
# =============================================================================

@test "output_success produces valid JSON structure" {
    run output_success "test data" "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    [[ "$output" == *"}" ]]
    [[ "$output" == *'"status":"success"'* ]]
    [[ "$output" == *'"data":"test data"'* ]]
    [[ "$output" == *'"message":"test message"'* ]]
}

@test "output_error produces valid JSON structure" {
    run output_error "test error" 2 "test context"
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    [[ "$output" == *"}" ]]
    [[ "$output" == *'"status":"error"'* ]]
    [[ "$output" == *'"error":"test error"'* ]]
    [[ "$output" == *'"code":2'* ]]
    [[ "$output" == *'"context":"test context"'* ]]
}

@test "output_list with special characters produces valid JSON" {
    run output_list 'item "one"' $'item\ntwo' 'item\three'
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    [[ "$output" == *'"count":3'* ]]
}

@test "output_object with all types produces valid JSON" {
    run output_object "str=hello" "num:number=42" "flag:bool=true" "nil:null=" "raw:raw=[1,2,3]"
    [ "$status" -eq 0 ]
    [[ "$output" == '{"status":"success","data":{'* ]]
    [[ "$output" == *'}}' ]]
}

@test "MAINFRAME_OUTPUT env var controls mode" {
    run bash -c 'source "'"$MAINFRAME_ROOT"'/lib/output.sh"; MAINFRAME_OUTPUT=json; output_format'
    [ "$status" -eq 0 ]
    [ "$output" = "json" ]
}

@test "output_success with backslash in data" {
    run output_success 'C:\Users\admin'
    [ "$status" -eq 0 ]
    [[ "$output" == *'C:\\Users\\admin'* ]]
}

@test "output_error with multiline error message" {
    run output_error $'error\non line 2'
    [ "$status" -eq 0 ]
    [[ "$output" == *'error\non line 2'* ]]
}

@test "output_list with many items" {
    run output_list a b c d e f g h i j
    [ "$status" -eq 0 ]
    [[ "$output" == *'"count":10'* ]]
}

@test "output_object handles key with spaces" {
    run output_object "my key=my value"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"my key":"my value"'* ]]
}

@test "mainframe_call with function that writes to both streams" {
    _test_mixed_io() {
        printf "stdout line 1\nstdout line 2"
        printf "stderr line 1\nstderr line 2" >&2
        return 0
    }
    run mainframe_call _test_mixed_io
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"success"'* ]]
    [[ "$output" == *'stdout line 1\nstdout line 2'* ]]
    [[ "$output" == *'stderr line 1\nstderr line 2'* ]]
}

@test "all envelope functions output trailing newline" {
    # Verify each function outputs exactly one trailing newline
    local result

    result=$(output_success "data" | wc -l)
    [ "$result" -eq 1 ]

    result=$(output_error "err" | wc -l)
    [ "$result" -eq 1 ]

    result=$(output_list "a" "b" | wc -l)
    [ "$result" -eq 1 ]

    result=$(output_object "k=v" | wc -l)
    [ "$result" -eq 1 ]

    result=$(output_progress "s" 1 2 | wc -l)
    [ "$result" -eq 1 ]
}

@test "output_json_escape handles very long string" {
    local long_str
    long_str=$(printf '%0.s-' {1..1000})
    run output_json_escape "$long_str"
    [ "$status" -eq 0 ]
    [ ${#output} -eq 1000 ]
}

@test "output_json_number rejects empty string" {
    run output_json_number "val" ""
    [ "$status" -eq 1 ]
    [ "$output" = '"val":null' ]
}

@test "output_json_number rejects spaces" {
    run output_json_number "val" "12 34"
    [ "$status" -eq 1 ]
    [ "$output" = '"val":null' ]
}

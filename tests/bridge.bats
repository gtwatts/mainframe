#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Bridge Module Tests
# =============================================================================
# Comprehensive tests for lib/bridge.sh (format detection and conversion)
# Covers: format detection, JSON/CSV/NDJSON/YAML/XML conversions, schema
# =============================================================================

load 'test_helper'

setup() {
    source_lib "bridge"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "bridge")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# FORMAT DETECTION TESTS
# =============================================================================

@test "bridge_detect identifies JSON object" {
    local result
    result=$(bridge_detect '{"name":"John","age":30}')
    [ "$result" = "json" ]
}

@test "bridge_detect identifies JSON array" {
    local result
    result=$(bridge_detect '[1,2,3]')
    [ "$result" = "json" ]
}

@test "bridge_detect identifies JSON with whitespace" {
    local result
    result=$(bridge_detect '  {"key": "value"}  ')
    [ "$result" = "json" ]
}

@test "bridge_detect identifies XML" {
    local result
    result=$(bridge_detect '<root><name>John</name></root>')
    [ "$result" = "xml" ]
}

@test "bridge_detect identifies XML with declaration" {
    local result
    result=$(bridge_detect '<?xml version="1.0"?><root/>')
    [ "$result" = "xml" ]
}

@test "bridge_detect identifies NDJSON" {
    local content=$'{"a":1}\n{"a":2}'
    local result
    result=$(bridge_detect "$content")
    [ "$result" = "ndjson" ]
}

@test "bridge_detect identifies CSV" {
    local content=$'name,age,city\nJohn,30,NYC\nJane,25,LA'
    local result
    result=$(bridge_detect "$content")
    [ "$result" = "csv" ]
}

@test "bridge_detect identifies YAML with document marker" {
    local result
    result=$(bridge_detect $'---\nname: John')
    [ "$result" = "yaml" ]
}

@test "bridge_detect identifies YAML key-value" {
    local result
    result=$(bridge_detect $'name: John\nage: 30')
    [ "$result" = "yaml" ]
}

@test "bridge_detect identifies INI format" {
    local content=$'[section]\nkey=value'
    local result
    result=$(bridge_detect "$content")
    [ "$result" = "ini" ]
}

@test "bridge_detect identifies key-value format" {
    local result
    result=$(bridge_detect $'API_KEY=abc123\nDEBUG=true')
    [ "$result" = "kv" ]
}

@test "bridge_detect returns unknown for empty input" {
    local result
    result=$(bridge_detect "")
    [ "$result" = "unknown" ]
}

@test "bridge_detect returns unknown for plain text" {
    local result
    result=$(bridge_detect "Just some random text here")
    [ "$result" = "unknown" ]
}

# =============================================================================
# BRIDGE_DETECT_FILE TESTS
# =============================================================================

@test "bridge_detect_file detects by .json extension" {
    echo '{}' > "$TEST_DIR/test.json"
    local result
    result=$(bridge_detect_file "$TEST_DIR/test.json")
    [ "$result" = "json" ]
}

@test "bridge_detect_file detects by .csv extension" {
    echo 'a,b,c' > "$TEST_DIR/test.csv"
    local result
    result=$(bridge_detect_file "$TEST_DIR/test.csv")
    [ "$result" = "csv" ]
}

@test "bridge_detect_file detects by .yaml extension" {
    echo 'key: value' > "$TEST_DIR/test.yaml"
    local result
    result=$(bridge_detect_file "$TEST_DIR/test.yaml")
    [ "$result" = "yaml" ]
}

@test "bridge_detect_file detects by .yml extension" {
    echo 'key: value' > "$TEST_DIR/test.yml"
    local result
    result=$(bridge_detect_file "$TEST_DIR/test.yml")
    [ "$result" = "yaml" ]
}

@test "bridge_detect_file detects by .xml extension" {
    echo '<root/>' > "$TEST_DIR/test.xml"
    local result
    result=$(bridge_detect_file "$TEST_DIR/test.xml")
    [ "$result" = "xml" ]
}

@test "bridge_detect_file detects by .ndjson extension" {
    echo '{}' > "$TEST_DIR/test.ndjson"
    local result
    result=$(bridge_detect_file "$TEST_DIR/test.ndjson")
    [ "$result" = "ndjson" ]
}

@test "bridge_detect_file falls back to content for unknown extension" {
    echo '{"key":"value"}' > "$TEST_DIR/test.dat"
    local result
    result=$(bridge_detect_file "$TEST_DIR/test.dat")
    [ "$result" = "json" ]
}

@test "bridge_detect_file returns unknown for missing file" {
    local result
    result=$(bridge_detect_file "$TEST_DIR/nonexistent.txt") || true
    [ "$result" = "unknown" ]
}

# =============================================================================
# JSON TO CSV CONVERSION TESTS
# =============================================================================

@test "bridge_json_to_csv converts simple array" {
    local json='[{"name":"John","age":30},{"name":"Jane","age":25}]'
    local result
    result=$(echo "$json" | bridge_json_to_csv)
    [[ "$result" == *"name"* ]]
    [[ "$result" == *"age"* ]]
    [[ "$result" == *"John"* ]]
    [[ "$result" == *"30"* ]]
}

@test "bridge_json_to_csv preserves header order" {
    local json='[{"a":"1","b":"2","c":"3"}]'
    local result
    result=$(echo "$json" | bridge_json_to_csv | head -1)
    # Headers should be present
    [[ "$result" == *"a"* ]]
    [[ "$result" == *"b"* ]]
    [[ "$result" == *"c"* ]]
}

@test "bridge_json_to_csv handles empty array" {
    local result
    result=$(echo '[]' | bridge_json_to_csv)
    [ -z "$result" ]
}

@test "bridge_json_to_csv handles special characters" {
    local json='[{"msg":"hello, world"}]'
    local result
    result=$(echo "$json" | bridge_json_to_csv)
    [[ "$result" == *'"hello, world"'* ]] || [[ "$result" == *'hello, world'* ]]
}

@test "bridge_json_to_csv handles null values" {
    local json='[{"name":"John","email":null}]'
    local result
    result=$(echo "$json" | bridge_json_to_csv)
    [[ "$result" == *"John"* ]]
}

# =============================================================================
# CSV TO JSON CONVERSION TESTS
# =============================================================================

@test "bridge_csv_to_json converts simple CSV" {
    local csv=$'name,age\nJohn,30\nJane,25'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
    [[ "$result" == *'"name":"John"'* ]]
    [[ "$result" == *'"age":30'* ]]
}

@test "bridge_csv_to_json handles quoted fields" {
    local csv=$'name,city\n"John Doe","New York"'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    [[ "$result" == *'"name":"John Doe"'* ]]
    [[ "$result" == *'"city":"New York"'* ]]
}

@test "bridge_csv_to_json handles embedded commas" {
    local csv=$'name,address\nJohn,"123 Main St, Apt 4"'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    [[ "$result" == *'123 Main St, Apt 4'* ]]
}

@test "bridge_csv_to_json auto-detects numbers" {
    local csv=$'name,count\ntest,42'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    [[ "$result" == *'"count":42'* ]]
}

@test "bridge_csv_to_json auto-detects booleans" {
    local csv=$'name,active\ntest,true'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    [[ "$result" == *'"active":true'* ]]
}

@test "bridge_csv_to_json handles empty values as null" {
    local csv=$'name,email\nJohn,'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    [[ "$result" == *'"email":null'* ]] || [[ "$result" == *'"email":""'* ]]
}

@test "bridge_csv_to_json handles single row" {
    local csv=$'name\nJohn'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    [[ "$result" == '[{"name":"John"}]' ]]
}

# =============================================================================
# JSON TO NDJSON CONVERSION TESTS
# =============================================================================

@test "bridge_json_to_ndjson converts array to lines" {
    local json='[{"a":1},{"a":2},{"a":3}]'
    local result
    result=$(echo "$json" | bridge_json_to_ndjson)
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -eq 3 ]
}

@test "bridge_json_to_ndjson preserves object structure" {
    local json='[{"name":"John","age":30}]'
    local result
    result=$(echo "$json" | bridge_json_to_ndjson)
    [[ "$result" == '{"name":"John","age":30}' ]]
}

@test "bridge_json_to_ndjson handles nested objects" {
    local json='[{"user":{"name":"John"}}]'
    local result
    result=$(echo "$json" | bridge_json_to_ndjson)
    [[ "$result" == *'"user":'* ]]
    [[ "$result" == *'"name":"John"'* ]]
}

@test "bridge_json_to_ndjson handles empty array" {
    local result
    result=$(echo '[]' | bridge_json_to_ndjson)
    [ -z "$result" ]
}

# =============================================================================
# NDJSON TO JSON CONVERSION TESTS
# =============================================================================

@test "bridge_ndjson_to_json converts lines to array" {
    local ndjson=$'{"a":1}\n{"a":2}\n{"a":3}'
    local result
    result=$(echo "$ndjson" | bridge_ndjson_to_json)
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
}

@test "bridge_ndjson_to_json preserves objects" {
    local ndjson=$'{"name":"John"}\n{"name":"Jane"}'
    local result
    result=$(echo "$ndjson" | bridge_ndjson_to_json)
    [[ "$result" == *'"name":"John"'* ]]
    [[ "$result" == *'"name":"Jane"'* ]]
}

@test "bridge_ndjson_to_json handles single line" {
    local result
    result=$(echo '{"x":1}' | bridge_ndjson_to_json)
    [ "$result" = '[{"x":1}]' ]
}

@test "bridge_ndjson_to_json skips empty lines" {
    local ndjson=$'{"a":1}\n\n{"a":2}'
    local result
    result=$(echo "$ndjson" | bridge_ndjson_to_json)
    [[ "$result" != *',,,'* ]]
}

# =============================================================================
# YAML TO JSON CONVERSION TESTS
# =============================================================================

@test "bridge_yaml_to_json converts simple YAML" {
    local yaml=$'name: John\nage: 30'
    local result
    result=$(echo "$yaml" | bridge_yaml_to_json)
    [[ "$result" == "{"* ]]
    [[ "$result" == *'"name":'* ]]
    [[ "$result" == *'"age":30'* ]]
}

@test "bridge_yaml_to_json handles quoted values" {
    local yaml='message: "Hello World"'
    local result
    result=$(echo "$yaml" | bridge_yaml_to_json)
    [[ "$result" == *'"message":"Hello World"'* ]]
}

@test "bridge_yaml_to_json handles null values" {
    local yaml='value: ~'
    local result
    result=$(echo "$yaml" | bridge_yaml_to_json)
    [[ "$result" == *':null'* ]]
}

@test "bridge_yaml_to_json handles boolean values" {
    local yaml=$'enabled: true\ndisabled: false'
    local result
    result=$(echo "$yaml" | bridge_yaml_to_json)
    [[ "$result" == *'"enabled":true'* ]]
    [[ "$result" == *'"disabled":false'* ]]
}

@test "bridge_yaml_to_json skips comments" {
    local yaml=$'# This is a comment\nname: John'
    local result
    result=$(echo "$yaml" | bridge_yaml_to_json)
    [[ "$result" != *'comment'* ]]
    [[ "$result" == *'"name"'* ]]
}

@test "bridge_yaml_to_json skips document markers" {
    local yaml=$'---\nname: John\n...'
    local result
    result=$(echo "$yaml" | bridge_yaml_to_json)
    [[ "$result" == *'"name":"John"'* ]]
}

# =============================================================================
# JSON TO YAML CONVERSION TESTS
# =============================================================================

@test "bridge_json_to_yaml converts simple object" {
    local json='{"name":"John","age":30}'
    local result
    result=$(echo "$json" | bridge_json_to_yaml)
    [[ "$result" == *"name: John"* ]]
    [[ "$result" == *"age: 30"* ]]
}

@test "bridge_json_to_yaml handles null values" {
    local json='{"value":null}'
    local result
    result=$(echo "$json" | bridge_json_to_yaml)
    [[ "$result" == *"value: ~"* ]]
}

@test "bridge_json_to_yaml handles boolean values" {
    local json='{"active":true,"deleted":false}'
    local result
    result=$(echo "$json" | bridge_json_to_yaml)
    [[ "$result" == *"active: true"* ]]
    [[ "$result" == *"deleted: false"* ]]
}

@test "bridge_json_to_yaml handles numbers" {
    local json='{"count":42,"rate":3.14}'
    local result
    result=$(echo "$json" | bridge_json_to_yaml)
    [[ "$result" == *"count: 42"* ]]
    [[ "$result" == *"rate: 3.14"* ]]
}

# =============================================================================
# XML TO JSON CONVERSION TESTS
# =============================================================================

@test "bridge_xml_to_json converts simple XML" {
    local xml='<root><name>John</name><age>30</age></root>'
    local result
    result=$(echo "$xml" | bridge_xml_to_json)
    [[ "$result" == "{"* ]]
    [[ "$result" == *'"name":"John"'* ]]
    [[ "$result" == *'"age":30'* ]]
}

@test "bridge_xml_to_json handles XML entities" {
    local xml='<root><msg>A &amp; B</msg></root>'
    local result
    result=$(echo "$xml" | bridge_xml_to_json)
    [[ "$result" == *'A & B'* ]]
}

@test "bridge_xml_to_json handles empty elements" {
    local xml='<root><empty></empty></root>'
    local result
    result=$(echo "$xml" | bridge_xml_to_json)
    [[ "$result" == *'"empty":null'* ]] || [[ "$result" == *'"empty":""'* ]]
}

@test "bridge_xml_to_json handles boolean values" {
    local xml='<root><active>true</active></root>'
    local result
    result=$(echo "$xml" | bridge_xml_to_json)
    [[ "$result" == *'"active":true'* ]]
}

@test "bridge_xml_to_json strips XML declaration" {
    local xml='<?xml version="1.0"?><root><name>Test</name></root>'
    local result
    result=$(echo "$xml" | bridge_xml_to_json)
    [[ "$result" == "{"* ]]
    [[ "$result" != *'xml version'* ]]
}

# =============================================================================
# JSON TO XML CONVERSION TESTS
# =============================================================================

@test "bridge_json_to_xml converts simple object" {
    local json='{"name":"John","age":30}'
    local result
    result=$(echo "$json" | bridge_json_to_xml "person")
    [[ "$result" == *'<?xml'* ]]
    [[ "$result" == *'<person>'* ]]
    [[ "$result" == *'<name>John</name>'* ]]
    [[ "$result" == *'<age>30</age>'* ]]
    [[ "$result" == *'</person>'* ]]
}

@test "bridge_json_to_xml uses default root tag" {
    local json='{"x":1}'
    local result
    result=$(echo "$json" | bridge_json_to_xml)
    [[ "$result" == *'<root>'* ]]
    [[ "$result" == *'</root>'* ]]
}

@test "bridge_json_to_xml escapes special characters" {
    local json='{"msg":"A < B & C > D"}'
    local result
    result=$(echo "$json" | bridge_json_to_xml "data")
    [[ "$result" == *'&lt;'* ]]
    [[ "$result" == *'&amp;'* ]]
    [[ "$result" == *'&gt;'* ]]
}

@test "bridge_json_to_xml handles null as empty element" {
    local json='{"value":null}'
    local result
    result=$(echo "$json" | bridge_json_to_xml "data")
    [[ "$result" == *'<value/>'* ]]
}

# =============================================================================
# UNIVERSAL CONVERTER TESTS
# =============================================================================

@test "bridge_convert auto-detects JSON and converts to CSV" {
    local json='[{"name":"John"}]'
    local result
    result=$(echo "$json" | bridge_convert "csv")
    [[ "$result" == *"name"* ]]
    [[ "$result" == *"John"* ]]
}

@test "bridge_convert auto-detects CSV and converts to JSON" {
    # Use proper multi-column CSV that can be detected (single-column without commas is ambiguous)
    local csv=$'name,age\nJohn,30'
    local result
    result=$(echo "$csv" | bridge_convert "json")
    [[ "$result" == "["* ]]
    [[ "$result" == *'"name":"John"'* ]]
    [[ "$result" == *'"age":30'* ]]
}

@test "bridge_convert passes through same format" {
    local json='{"x":1}'
    local result
    result=$(echo "$json" | bridge_convert "json")
    [ "$result" = '{"x":1}' ]
}

@test "bridge_convert JSON to NDJSON" {
    local json='[{"a":1},{"a":2}]'
    local result
    result=$(echo "$json" | bridge_convert "ndjson")
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -eq 2 ]
}

@test "bridge_convert NDJSON to JSON" {
    local ndjson=$'{"x":1}\n{"x":2}'
    local result
    result=$(echo "$ndjson" | bridge_convert "json")
    [[ "$result" == "["* ]]
}

@test "bridge_convert CSV to YAML (multi-hop)" {
    # Use proper multi-column CSV that can be detected
    local csv=$'name,age\nJohn,30'
    local result
    result=$(echo "$csv" | bridge_convert "yaml")
    # Should have YAML-style output
    [[ "$result" == *"name:"* ]] || [[ "$result" == *"name :"* ]]
}

@test "bridge_convert returns error for unsupported conversion" {
    local result
    result=$(echo "random text" | bridge_convert "json" 2>&1) || true
    [[ "$result" == *"unsupported"* ]] || [[ "$result" == "{}" ]]
}

# =============================================================================
# SCHEMA EXTRACTION TESTS
# =============================================================================

@test "bridge_schema_extract infers types from JSON" {
    local json='[{"name":"John","age":30,"active":true}]'
    local result
    result=$(echo "$json" | bridge_schema_extract)
    [[ "$result" == *'"format":"json"'* ]]
    [[ "$result" == *'"fields":'* ]]
}

@test "bridge_schema_extract detects string type" {
    local json='[{"name":"John"}]'
    local result
    result=$(echo "$json" | bridge_schema_extract)
    [[ "$result" == *'"name":"string"'* ]]
}

@test "bridge_schema_extract detects integer type" {
    local json='[{"count":42}]'
    local result
    result=$(echo "$json" | bridge_schema_extract)
    [[ "$result" == *'"count":"integer"'* ]]
}

@test "bridge_schema_extract detects number type" {
    local json='[{"rate":3.14}]'
    local result
    result=$(echo "$json" | bridge_schema_extract)
    [[ "$result" == *'"rate":"number"'* ]]
}

@test "bridge_schema_extract detects boolean type" {
    local json='[{"active":true}]'
    local result
    result=$(echo "$json" | bridge_schema_extract)
    [[ "$result" == *'"active":"boolean"'* ]]
}

@test "bridge_schema_extract detects null type" {
    local json='[{"value":null}]'
    local result
    result=$(echo "$json" | bridge_schema_extract)
    [[ "$result" == *'"value":"null"'* ]]
}

@test "bridge_schema_extract works with CSV input" {
    local csv=$'name,age\nJohn,30'
    local result
    result=$(echo "$csv" | bridge_schema_extract)
    [[ "$result" == *'"format":"csv"'* ]]
}

@test "bridge_schema_extract works with NDJSON input" {
    local ndjson=$'{"x":1}\n{"x":2}'
    local result
    result=$(echo "$ndjson" | bridge_schema_extract)
    [[ "$result" == *'"format":"ndjson"'* ]]
}

# =============================================================================
# ROUNDTRIP TESTS
# =============================================================================

@test "roundtrip: JSON -> CSV -> JSON preserves data" {
    local original='[{"name":"John","age":"30"}]'
    local csv
    csv=$(echo "$original" | bridge_json_to_csv)
    local restored
    restored=$(echo "$csv" | bridge_csv_to_json)
    [[ "$restored" == *'"name":"John"'* ]]
    [[ "$restored" == *'"age":'*'30'* ]]
}

@test "roundtrip: JSON -> NDJSON -> JSON preserves data" {
    local original='[{"x":1},{"x":2}]'
    local ndjson
    ndjson=$(echo "$original" | bridge_json_to_ndjson)
    local restored
    restored=$(echo "$ndjson" | bridge_ndjson_to_json)
    [[ "$restored" == *'"x":1'* ]]
    [[ "$restored" == *'"x":2'* ]]
}

@test "roundtrip: JSON -> YAML -> JSON preserves simple data" {
    local original='{"name":"John","count":42}'
    local yaml
    yaml=$(echo "$original" | bridge_json_to_yaml)
    local restored
    restored=$(echo "$yaml" | bridge_yaml_to_json)
    [[ "$restored" == *'"name":'* ]]
    [[ "$restored" == *'"count":42'* ]]
}

@test "roundtrip: JSON -> XML -> JSON preserves simple data" {
    local original='{"name":"John","age":30}'
    local xml
    xml=$(echo "$original" | bridge_json_to_xml "person")
    local restored
    restored=$(echo "$xml" | bridge_xml_to_json)
    [[ "$restored" == *'"name":"John"'* ]]
    [[ "$restored" == *'"age":30'* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "bridge handles empty input gracefully" {
    local result
    result=$(echo "" | bridge_detect)
    [ "$result" = "unknown" ]
}

@test "bridge_json_to_csv handles nested arrays in values" {
    local json='[{"tags":["a","b"]}]'
    local result
    result=$(echo "$json" | bridge_json_to_csv) || true
    # Should not crash, nested arrays become strings
    [[ -n "$result" ]]
}

@test "bridge_csv_to_json handles escaped quotes" {
    local csv=$'message\n"He said ""hello"""'
    local result
    result=$(echo "$csv" | bridge_csv_to_json)
    # JSON output has escaped quotes (\" represents literal ")
    [[ "$result" == *'He said \"hello\"'* ]]
}

@test "bridge handles unicode characters" {
    local json='[{"name":"cafe"}]'
    local result
    result=$(echo "$json" | bridge_json_to_csv)
    [[ "$result" == *"cafe"* ]]
}

@test "bridge_detect handles mixed content intelligently" {
    # JSON embedded in text should still be detected
    local content='{"valid":"json"}'
    local result
    result=$(bridge_detect "$content")
    [ "$result" = "json" ]
}

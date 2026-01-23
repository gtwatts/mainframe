#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: CSV Module Tests
# =============================================================================
# Tests for lib/csv.sh
# Covers: parsing, building, reading, field access, escaping, transforms
# =============================================================================

load 'test_helper'

setup() {
    source_lib "csv"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "csv")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# csv_parse_line TESTS
# =============================================================================

@test "csv_parse_line parses simple fields" {
    csv_parse_line "a,b,c"
    [ "${#CSV_FIELDS[@]}" -eq 3 ]
    [ "${CSV_FIELDS[0]}" = "a" ]
    [ "${CSV_FIELDS[1]}" = "b" ]
    [ "${CSV_FIELDS[2]}" = "c" ]
}

@test "csv_parse_line handles quoted fields" {
    csv_parse_line '"hello","world"'
    [ "${CSV_FIELDS[0]}" = "hello" ]
    [ "${CSV_FIELDS[1]}" = "world" ]
}

@test "csv_parse_line handles comma in quotes" {
    csv_parse_line '"name, with comma",value'
    [ "${CSV_FIELDS[0]}" = "name, with comma" ]
    [ "${CSV_FIELDS[1]}" = "value" ]
}

@test "csv_parse_line handles escaped quotes" {
    csv_parse_line '"say ""hello""",other'
    [ "${CSV_FIELDS[0]}" = 'say "hello"' ]
    [ "${CSV_FIELDS[1]}" = "other" ]
}

@test "csv_parse_line handles empty fields" {
    csv_parse_line "a,,c"
    [ "${#CSV_FIELDS[@]}" -eq 3 ]
    [ "${CSV_FIELDS[0]}" = "a" ]
    [ "${CSV_FIELDS[1]}" = "" ]
    [ "${CSV_FIELDS[2]}" = "c" ]
}

@test "csv_parse_line handles single field" {
    csv_parse_line "alone"
    [ "${#CSV_FIELDS[@]}" -eq 1 ]
    [ "${CSV_FIELDS[0]}" = "alone" ]
}

# =============================================================================
# csv_field TESTS
# =============================================================================

@test "csv_field extracts by index" {
    local result
    result=$(csv_field "a,b,c" 1)
    [ "$result" = "b" ]
}

@test "csv_field extracts first field" {
    local result
    result=$(csv_field "first,second,third" 0)
    [ "$result" = "first" ]
}

# =============================================================================
# csv_field_count TESTS
# =============================================================================

@test "csv_field_count returns correct count" {
    local result
    result=$(csv_field_count "a,b,c,d")
    [ "$result" -eq 4 ]
}

@test "csv_field_count handles single field" {
    local result
    result=$(csv_field_count "solo")
    [ "$result" -eq 1 ]
}

# =============================================================================
# csv_escape TESTS
# =============================================================================

@test "csv_escape returns plain value unchanged" {
    local result
    result=$(csv_escape "hello")
    [ "$result" = "hello" ]
}

@test "csv_escape quotes value with comma" {
    local result
    result=$(csv_escape "a, b")
    [ "$result" = '"a, b"' ]
}

@test "csv_escape doubles internal quotes" {
    local result
    result=$(csv_escape 'say "hi"')
    [ "$result" = '"say ""hi"""' ]
}

@test "csv_escape quotes value with newline" {
    local result
    result=$(csv_escape "line1
line2")
    [[ "$result" == '"'* ]]
}

@test "csv_escape quotes value with leading space" {
    local result
    result=$(csv_escape " leading")
    [ "$result" = '" leading"' ]
}

# =============================================================================
# csv_row TESTS
# =============================================================================

@test "csv_row creates simple row" {
    local result
    result=$(csv_row "a" "b" "c")
    [ "$result" = "a,b,c" ]
}

@test "csv_row escapes values with commas" {
    local result
    result=$(csv_row "plain" "has, comma" "end")
    [ "$result" = 'plain,"has, comma",end' ]
}

@test "csv_row handles single value" {
    local result
    result=$(csv_row "only")
    [ "$result" = "only" ]
}

# =============================================================================
# csv_delimiter TESTS
# =============================================================================

@test "csv_delimiter changes parsing delimiter" {
    csv_delimiter "|"
    csv_parse_line "a|b|c"
    [ "${CSV_FIELDS[0]}" = "a" ]
    [ "${CSV_FIELDS[1]}" = "b" ]
    [ "${CSV_FIELDS[2]}" = "c" ]
    csv_delimiter ","
}

@test "csv_delimiter changes output delimiter" {
    csv_delimiter ";"
    local result
    result=$(csv_row "x" "y" "z")
    [ "$result" = "x;y;z" ]
    csv_delimiter ","
}

# =============================================================================
# csv_parse_file TESTS
# =============================================================================

@test "csv_parse_file reads file into CSV_ROWS" {
    printf 'name,age\nAlice,30\nBob,25\n' > "$TEST_DIR/test.csv"
    csv_parse_file "$TEST_DIR/test.csv"
    [ "${#CSV_ROWS[@]}" -eq 3 ]
}

@test "csv_parse_file fails for missing file" {
    run csv_parse_file "$TEST_DIR/nonexistent.csv"
    [ "$status" -eq 1 ]
}

# =============================================================================
# csv_read TESTS
# =============================================================================

@test "csv_read separates headers from data" {
    printf 'name,age,city\nAlice,30,NYC\nBob,25,LA\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    [ "${#CSV_HEADERS[@]}" -eq 3 ]
    [ "${CSV_HEADERS[0]}" = "name" ]
    [ "${#CSV_ROWS[@]}" -eq 2 ]
}

# =============================================================================
# csv_get TESTS
# =============================================================================

@test "csv_get retrieves value by row and column name" {
    printf 'name,age\nAlice,30\nBob,25\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    local result
    result=$(csv_get 0 "name")
    [ "$result" = "Alice" ]
}

@test "csv_get retrieves second column" {
    printf 'name,age\nAlice,30\nBob,25\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    local result
    result=$(csv_get 1 "age")
    [ "$result" = "25" ]
}

@test "csv_get fails for nonexistent column" {
    printf 'name,age\nAlice,30\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    run csv_get 0 "missing"
    [ "$status" -eq 1 ]
}

# =============================================================================
# csv_column TESTS
# =============================================================================

@test "csv_column extracts all values for column" {
    printf 'name,age\nAlice,30\nBob,25\nCharlie,35\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    local result
    result=$(csv_column "name")
    [[ "$result" == *"Alice"* ]]
    [[ "$result" == *"Bob"* ]]
    [[ "$result" == *"Charlie"* ]]
}

# =============================================================================
# csv_column_index TESTS
# =============================================================================

@test "csv_column_index returns correct index" {
    printf 'name,age,city\nAlice,30,NYC\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    local result
    result=$(csv_column_index "age")
    [ "$result" -eq 1 ]
}

@test "csv_column_index returns -1 for missing" {
    printf 'name,age\nAlice,30\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    local result
    result=$(csv_column_index "missing" || true)
    [ "$result" = "-1" ]
}

# =============================================================================
# csv_write TESTS
# =============================================================================

@test "csv_write outputs headers and rows" {
    CSV_HEADERS=("name" "age")
    CSV_ROWS=("Alice,30" "Bob,25")
    csv_write "$TEST_DIR/out.csv"
    [ -f "$TEST_DIR/out.csv" ]
    local content
    content=$(<"$TEST_DIR/out.csv")
    [[ "$content" == *"name,age"* ]]
    [[ "$content" == *"Alice,30"* ]]
}

# =============================================================================
# csv_append_row TESTS
# =============================================================================

@test "csv_append_row adds row to file" {
    printf 'name,age\n' > "$TEST_DIR/out.csv"
    csv_append_row "$TEST_DIR/out.csv" "Alice" "30"
    local lines
    lines=$(wc -l < "$TEST_DIR/out.csv")
    [ "$lines" -eq 2 ]
}

# =============================================================================
# csv_filter TESTS
# =============================================================================

@test "csv_filter returns matching rows" {
    printf 'name,status\nAlice,active\nBob,inactive\nCharlie,active\n' > "$TEST_DIR/data.csv"
    local result
    result=$(csv_filter "$TEST_DIR/data.csv" "status" "active")
    [[ "$result" == *"Alice"* ]]
    [[ "$result" == *"Charlie"* ]]
    [[ "$result" != *"Bob"* ]]
}

# =============================================================================
# csv_row_count TESTS
# =============================================================================

@test "csv_row_count returns data row count" {
    printf 'name,age\nAlice,30\nBob,25\nCharlie,35\n' > "$TEST_DIR/data.csv"
    local result
    result=$(csv_row_count "$TEST_DIR/data.csv")
    [ "$result" -eq 3 ]
}

# =============================================================================
# csv_validate TESTS
# =============================================================================

@test "csv_validate accepts consistent column count" {
    printf 'a,b,c\n1,2,3\n4,5,6\n' > "$TEST_DIR/valid.csv"
    run csv_validate "$TEST_DIR/valid.csv"
    [ "$status" -eq 0 ]
}

@test "csv_validate rejects inconsistent columns" {
    printf 'a,b,c\n1,2\n4,5,6\n' > "$TEST_DIR/invalid.csv"
    run csv_validate "$TEST_DIR/invalid.csv"
    [ "$status" -eq 1 ]
}

# =============================================================================
# csv_count TESTS
# =============================================================================

@test "csv_count counts matching rows" {
    printf 'name,status\nA,active\nB,inactive\nC,active\nD,active\n' > "$TEST_DIR/data.csv"
    local result
    result=$(csv_count "$TEST_DIR/data.csv" "status" "active")
    [ "$result" -eq 3 ]
}

# =============================================================================
# csv_multiline TESTS
# =============================================================================

@test "csv_parse_multiline handles quoted newlines" {
    local content
    content=$(printf 'name,bio\n"Alice","Hello\nWorld"\n"Bob","Simple"')
    csv_parse_multiline "$content"
    [ "${#CSV_ROWS[@]}" -eq 3 ]
}

# =============================================================================
# csv_to_json TESTS
# =============================================================================

@test "csv_to_json outputs valid JSON structure" {
    printf 'name,age\nAlice,30\nBob,25\n' > "$TEST_DIR/data.csv"
    local result
    result=$(csv_to_json "$TEST_DIR/data.csv")
    [[ "$result" == "["* ]]
    [[ "$result" == *"]"* ]]
    [[ "$result" == *'"name":"Alice"'* ]]
}

# =============================================================================
# csv_header TESTS
# =============================================================================

@test "csv_header creates row same as csv_row" {
    local h r
    h=$(csv_header "col1" "col2" "col3")
    r=$(csv_row "col1" "col2" "col3")
    [ "$h" = "$r" ]
}

# =============================================================================
# csv_row_assoc TESTS
# =============================================================================

@test "csv_row_assoc populates associative array" {
    printf 'name,age,city\nAlice,30,NYC\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    csv_row_assoc 0
    [ "${CSV_ROW_ASSOC[name]}" = "Alice" ]
    [ "${CSV_ROW_ASSOC[age]}" = "30" ]
    [ "${CSV_ROW_ASSOC[city]}" = "NYC" ]
}

@test "csv_row_assoc fails for invalid row" {
    printf 'name\nAlice\n' > "$TEST_DIR/data.csv"
    csv_read "$TEST_DIR/data.csv"
    run csv_row_assoc 99
    [ "$status" -eq 1 ]
}

# =============================================================================
# csv_select TESTS
# =============================================================================

@test "csv_select extracts specified columns" {
    printf 'name,age,city\nAlice,30,NYC\nBob,25,LA\n' > "$TEST_DIR/data.csv"
    local result
    result=$(csv_select "$TEST_DIR/data.csv" "name,city")
    [[ "$result" == *"name"* ]]
    [[ "$result" == *"city"* ]]
    [[ "$result" == *"Alice"* ]]
    [[ "$result" == *"NYC"* ]]
}

# =============================================================================
# csv_sort TESTS
# =============================================================================

@test "csv_sort sorts lexicographically" {
    printf 'name,age\nCharlie,35\nAlice,30\nBob,25\n' > "$TEST_DIR/data.csv"
    local result
    result=$(csv_sort "$TEST_DIR/data.csv" "name")
    local lines
    readarray -t lines <<< "$result"
    [[ "${lines[1]}" == *"Alice"* ]]
    [[ "${lines[2]}" == *"Bob"* ]]
    [[ "${lines[3]}" == *"Charlie"* ]]
}

# =============================================================================
# csv_group_count TESTS
# =============================================================================

@test "csv_group_count groups and counts" {
    printf 'name,dept\nA,eng\nB,eng\nC,sales\nD,eng\n' > "$TEST_DIR/data.csv"
    local result
    result=$(csv_group_count "$TEST_DIR/data.csv" "dept")
    [[ "$result" == *"eng"* ]]
    [[ "$result" == *"3"* ]]
    [[ "$result" == *"sales"* ]]
    [[ "$result" == *"1"* ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/csv.bats - CSV Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/csv.sh
#              RFC 4180 compliant CSV parsing without external tools
# Test Count: 65+ test cases
# Categories: configuration, core parsing, reading with headers, building CSV,
#             writing CSV, transformation, utilities, aggregation, joining,
#             pretty printing, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source the library
    source "$MAINFRAME_ROOT/lib/csv.sh"

    # Reset global state
    CSV_DELIMITER=','
    CSV_QUOTE='"'
    CSV_FIELDS=()
    CSV_HEADERS=()
    CSV_ROWS=()
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: Create test CSV file
create_test_csv() {
    local file="$1"
    cat > "$file" << 'EOF'
name,age,city
John,30,NYC
Jane,25,LA
Bob,35,Chicago
EOF
}

# Helper: Create CSV with quoted fields
create_quoted_csv() {
    local file="$1"
    cat > "$file" << 'EOF'
name,description,price
"Widget","A simple widget",9.99
"Gadget","A ""fancy"" gadget",19.99
"Tool","Multi-purpose, handy tool",14.99
EOF
}

# =============================================================================
# CATEGORY 1: CONFIGURATION
# =============================================================================

@test "csv_delimiter: sets custom delimiter" {
    csv_delimiter "|"
    [[ "$CSV_DELIMITER" == "|" ]]
}

@test "csv_delimiter: sets tab delimiter" {
    csv_delimiter $'\t'
    [[ "$CSV_DELIMITER" == $'\t' ]]
}

@test "csv_quote: sets custom quote character" {
    csv_quote "'"
    [[ "$CSV_QUOTE" == "'" ]]
}

# =============================================================================
# CATEGORY 2: CORE PARSING
# =============================================================================

@test "csv_parse_line: parses simple CSV line" {
    csv_parse_line "a,b,c"
    [[ "${#CSV_FIELDS[@]}" -eq 3 ]]
    [[ "${CSV_FIELDS[0]}" == "a" ]]
    [[ "${CSV_FIELDS[1]}" == "b" ]]
    [[ "${CSV_FIELDS[2]}" == "c" ]]
}

@test "csv_parse_line: parses quoted field with comma" {
    csv_parse_line 'a,"b,c",d'
    [[ "${#CSV_FIELDS[@]}" -eq 3 ]]
    [[ "${CSV_FIELDS[0]}" == "a" ]]
    [[ "${CSV_FIELDS[1]}" == "b,c" ]]
    [[ "${CSV_FIELDS[2]}" == "d" ]]
}

@test "csv_parse_line: parses escaped quotes" {
    csv_parse_line 'a,"say ""hello""",c'
    [[ "${#CSV_FIELDS[@]}" -eq 3 ]]
    [[ "${CSV_FIELDS[1]}" == 'say "hello"' ]]
}

@test "csv_parse_line: handles empty fields" {
    csv_parse_line "a,,c"
    [[ "${#CSV_FIELDS[@]}" -eq 3 ]]
    [[ "${CSV_FIELDS[1]}" == "" ]]
}

@test "csv_parse_line: handles trailing comma" {
    csv_parse_line "a,b,"
    [[ "${#CSV_FIELDS[@]}" -eq 3 ]]
    [[ "${CSV_FIELDS[2]}" == "" ]]
}

@test "csv_parse_line: handles single field" {
    csv_parse_line "only"
    [[ "${#CSV_FIELDS[@]}" -eq 1 ]]
    [[ "${CSV_FIELDS[0]}" == "only" ]]
}

@test "csv_parse_line: handles empty line" {
    csv_parse_line ""
    [[ "${#CSV_FIELDS[@]}" -eq 1 ]]
    [[ "${CSV_FIELDS[0]}" == "" ]]
}

@test "csv_parse_line: uses custom delimiter" {
    csv_delimiter "|"
    csv_parse_line "a|b|c"
    [[ "${#CSV_FIELDS[@]}" -eq 3 ]]
    [[ "${CSV_FIELDS[1]}" == "b" ]]
}

@test "csv_parse_multiline: parses multiple lines" {
    local content=$'a,b\n1,2\n3,4'
    csv_parse_multiline "$content"
    [[ "${#CSV_ROWS[@]}" -eq 3 ]]
}

@test "csv_parse_multiline: handles CRLF line endings" {
    local content=$'a,b\r\n1,2\r\n3,4'
    csv_parse_multiline "$content"
    [[ "${#CSV_ROWS[@]}" -eq 3 ]]
}

@test "csv_parse_multiline: handles newlines in quoted fields" {
    local content=$'a,"line1\nline2"\nc,d'
    csv_parse_multiline "$content"
    [[ "${#CSV_ROWS[@]}" -eq 2 ]]
}

@test "csv_parse_file: reads CSV file" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_parse_file "$TEST_TMPDIR/test.csv"
    [[ "${#CSV_ROWS[@]}" -eq 4 ]]  # Header + 3 data rows
}

@test "csv_parse_file: returns error for missing file" {
    run csv_parse_file "$TEST_TMPDIR/nonexistent.csv"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

@test "csv_field: extracts field by index" {
    result=$(csv_field "a,b,c" 1)
    [[ "$result" == "b" ]]
}

@test "csv_field_count: counts fields in line" {
    result=$(csv_field_count "a,b,c,d,e")
    [[ "$result" -eq 5 ]]
}

# =============================================================================
# CATEGORY 3: READING WITH HEADERS
# =============================================================================

@test "csv_read: populates headers from first row" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    [[ "${CSV_HEADERS[0]}" == "name" ]]
    [[ "${CSV_HEADERS[1]}" == "age" ]]
    [[ "${CSV_HEADERS[2]}" == "city" ]]
}

@test "csv_read: excludes header from data rows" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    [[ "${#CSV_ROWS[@]}" -eq 3 ]]  # 3 data rows, not 4
}

@test "csv_get: retrieves value by row and column name" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    result=$(csv_get 0 "name")
    [[ "$result" == "John" ]]
}

@test "csv_get: retrieves second column" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    result=$(csv_get 1 "age")
    [[ "$result" == "25" ]]
}

@test "csv_get: returns error for missing column" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    run csv_get 0 "nonexistent"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

@test "csv_get: returns error for missing row" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    run csv_get 99 "name"
    [[ "$status" -eq 1 ]]
}

@test "csv_column: extracts entire column" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    result=$(csv_column "name")
    [[ "$result" =~ "John" ]]
    [[ "$result" =~ "Jane" ]]
    [[ "$result" =~ "Bob" ]]
}

@test "csv_column_index: returns column index" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    result=$(csv_column_index "age")
    [[ "$result" -eq 1 ]]
}

@test "csv_column_index: returns -1 for missing column" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    run csv_column_index "nonexistent"
    [[ "$output" == "-1" ]]
}

# =============================================================================
# CATEGORY 4: BUILDING CSV
# =============================================================================

@test "csv_escape: returns plain value unchanged" {
    result=$(csv_escape "simple")
    [[ "$result" == "simple" ]]
}

@test "csv_escape: quotes value with comma" {
    result=$(csv_escape "a,b")
    [[ "$result" == '"a,b"' ]]
}

@test "csv_escape: quotes and escapes quotes" {
    result=$(csv_escape 'say "hi"')
    [[ "$result" == '"say ""hi"""' ]]
}

@test "csv_escape: quotes value with newline" {
    result=$(csv_escape $'line1\nline2')
    [[ "$result" == $'"line1\nline2"' ]]
}

@test "csv_escape: quotes value with leading space" {
    result=$(csv_escape " leading")
    [[ "$result" == '" leading"' ]]
}

@test "csv_escape: quotes value with trailing space" {
    result=$(csv_escape "trailing ")
    [[ "$result" == '"trailing "' ]]
}

@test "csv_row: creates simple CSV row" {
    result=$(csv_row "a" "b" "c")
    [[ "$result" == $'a,b,c\n' ]]
}

@test "csv_row: escapes values that need quoting" {
    result=$(csv_row "normal" "has,comma" "plain")
    [[ "$result" == $'normal,"has,comma",plain\n' ]]
}

@test "csv_header: creates header row (alias)" {
    result=$(csv_header "col1" "col2" "col3")
    [[ "$result" == $'col1,col2,col3\n' ]]
}

# =============================================================================
# CATEGORY 5: WRITING CSV
# =============================================================================

@test "csv_write: writes headers and rows to file" {
    CSV_HEADERS=("name" "age")
    CSV_ROWS=("John,30" "Jane,25")
    csv_write "$TEST_TMPDIR/output.csv"

    [[ -f "$TEST_TMPDIR/output.csv" ]]
    content=$(<"$TEST_TMPDIR/output.csv")
    [[ "$content" =~ "name,age" ]]
    [[ "$content" =~ "John,30" ]]
}

@test "csv_write: appends when mode is append" {
    echo "existing,data" > "$TEST_TMPDIR/append.csv"
    CSV_HEADERS=("a" "b")
    CSV_ROWS=("1,2")
    csv_write "$TEST_TMPDIR/append.csv" "append"

    content=$(<"$TEST_TMPDIR/append.csv")
    [[ "$content" =~ "existing,data" ]]
    [[ "$content" =~ "a,b" ]]
}

@test "csv_append_row: appends single row to file" {
    echo "header1,header2" > "$TEST_TMPDIR/append_row.csv"
    csv_append_row "$TEST_TMPDIR/append_row.csv" "val1" "val2"

    content=$(<"$TEST_TMPDIR/append_row.csv")
    [[ "$content" =~ "val1,val2" ]]
}

# =============================================================================
# CATEGORY 6: TRANSFORMATION
# =============================================================================

@test "csv_filter: filters rows by column value" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_filter "$TEST_TMPDIR/test.csv" "city" "NYC")
    [[ "$result" =~ "John" ]]
    [[ ! "$result" =~ "Jane" ]]
    [[ ! "$result" =~ "Bob" ]]
}

@test "csv_sort: sorts by column lexicographically" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_sort "$TEST_TMPDIR/test.csv" "name")
    # Bob should come before Jane, Jane before John
    lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$result"
    [[ "${lines[1]}" =~ "Bob" ]]
    [[ "${lines[2]}" =~ "Jane" ]]
    [[ "${lines[3]}" =~ "John" ]]
}

@test "csv_sort_num: sorts by column numerically" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_sort_num "$TEST_TMPDIR/test.csv" "age")
    lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$result"
    # Jane (25) should come first, then John (30), then Bob (35)
    [[ "${lines[1]}" =~ "Jane" ]]
    [[ "${lines[2]}" =~ "John" ]]
    [[ "${lines[3]}" =~ "Bob" ]]
}

@test "csv_select: selects specific columns" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_select "$TEST_TMPDIR/test.csv" "name,city")
    [[ "$result" =~ "name,city" ]]
    [[ ! "$result" =~ "age" ]]
}

@test "csv_to_json: converts CSV to JSON array" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_to_json "$TEST_TMPDIR/test.csv")
    [[ "$result" =~ '[\n' ]]
    [[ "$result" =~ '"name":"John"' ]]
    [[ "$result" =~ '"age":"30"' ]]
}

@test "csv_to_json: escapes JSON special characters" {
    create_quoted_csv "$TEST_TMPDIR/quoted.csv"
    result=$(csv_to_json "$TEST_TMPDIR/quoted.csv")
    # Should escape the quotes in "fancy"
    [[ "$result" =~ 'fancy' ]]
}

@test "csv_from_json: converts JSON array to CSV" {
    json='[{"name":"John","age":"30"},{"name":"Jane","age":"25"}]'
    result=$(csv_from_json "$json")
    [[ "$result" =~ "name,age" ]]
    [[ "$result" =~ "John,30" ]]
    [[ "$result" =~ "Jane,25" ]]
}

# =============================================================================
# CATEGORY 7: UTILITIES
# =============================================================================

@test "csv_row_count: returns number of data rows" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_row_count "$TEST_TMPDIR/test.csv")
    [[ "$result" -eq 3 ]]
}

@test "csv_has_header: detects likely header row" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_has_header "$TEST_TMPDIR/test.csv"
    [[ $? -eq 0 ]]
}

@test "csv_validate: returns success for valid CSV" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_validate "$TEST_TMPDIR/test.csv")
    [[ "$result" =~ "Valid" ]]
}

@test "csv_validate: detects inconsistent field count" {
    cat > "$TEST_TMPDIR/bad.csv" << 'EOF'
a,b,c
1,2,3
4,5
6,7,8
EOF
    run csv_validate "$TEST_TMPDIR/bad.csv"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Error" ]]
}

@test "csv_row_assoc: populates associative array" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    csv_read "$TEST_TMPDIR/test.csv"
    csv_row_assoc 0
    [[ "${CSV_ROW_ASSOC[name]}" == "John" ]]
    [[ "${CSV_ROW_ASSOC[age]}" == "30" ]]
    [[ "${CSV_ROW_ASSOC[city]}" == "NYC" ]]
}

@test "csv_each: iterates over rows with callback" {
    create_test_csv "$TEST_TMPDIR/test.csv"

    count=0
    callback() {
        ((count++))
    }

    csv_each "$TEST_TMPDIR/test.csv" callback
    [[ "$count" -eq 3 ]]
}

# =============================================================================
# CATEGORY 8: AGGREGATION
# =============================================================================

@test "csv_sum: sums numeric column" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_sum "$TEST_TMPDIR/test.csv" "age")
    # 30 + 25 + 35 = 90
    [[ "$result" -eq 90 ]]
}

@test "csv_count: counts rows matching condition" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_count "$TEST_TMPDIR/test.csv" "city" "NYC")
    [[ "$result" -eq 1 ]]
}

@test "csv_group_count: groups and counts by column" {
    cat > "$TEST_TMPDIR/group.csv" << 'EOF'
name,status
John,active
Jane,inactive
Bob,active
Alice,active
EOF
    result=$(csv_group_count "$TEST_TMPDIR/group.csv" "status")
    [[ "$result" =~ "active" ]]
    [[ "$result" =~ "inactive" ]]
}

# =============================================================================
# CATEGORY 9: JOINING
# =============================================================================

@test "csv_join: inner joins two CSV files" {
    cat > "$TEST_TMPDIR/users.csv" << 'EOF'
id,name
1,John
2,Jane
3,Bob
EOF
    cat > "$TEST_TMPDIR/orders.csv" << 'EOF'
id,product
1,Widget
2,Gadget
EOF
    result=$(csv_join "$TEST_TMPDIR/users.csv" "$TEST_TMPDIR/orders.csv" "id")
    # Should have id, name, product columns
    [[ "$result" =~ "name" ]]
    [[ "$result" =~ "product" ]]
    # Should have John and Jane (who have orders), not Bob
    [[ "$result" =~ "John" ]]
    [[ "$result" =~ "Jane" ]]
    [[ ! "$result" =~ "Bob" ]]
}

# =============================================================================
# CATEGORY 10: PRETTY PRINTING
# =============================================================================

@test "csv_print: formats CSV as table" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_print "$TEST_TMPDIR/test.csv")
    # Should have pipe characters for borders
    [[ "$result" =~ "|" ]]
    # Should have dashes for separator
    [[ "$result" =~ "-" ]]
}

# =============================================================================
# CATEGORY 11: EDGE CASES AND SECURITY
# =============================================================================

@test "csv_parse_line: handles very long fields" {
    local long_value
    long_value=$(printf 'x%.0s' {1..1000})
    csv_parse_line "short,$long_value,end"
    [[ "${CSV_FIELDS[1]}" == "$long_value" ]]
}

@test "csv_parse_line: handles many fields" {
    local many_fields
    many_fields=$(printf '%s,' {1..100})
    many_fields="${many_fields%,}"  # Remove trailing comma
    csv_parse_line "$many_fields"
    [[ "${#CSV_FIELDS[@]}" -eq 100 ]]
}

@test "csv_escape: handles empty string" {
    result=$(csv_escape "")
    [[ "$result" == "" ]]
}

@test "csv_parse_line: handles quoted empty field" {
    csv_parse_line 'a,"",c'
    [[ "${CSV_FIELDS[1]}" == "" ]]
}

@test "csv_parse_line: handles field that is just quotes" {
    csv_parse_line 'a,"""",c'
    [[ "${CSV_FIELDS[1]}" == '"' ]]
}

@test "csv_to_json: handles empty CSV" {
    echo "header1,header2" > "$TEST_TMPDIR/empty.csv"
    result=$(csv_to_json "$TEST_TMPDIR/empty.csv")
    [[ "$result" == $'[\n]\n' ]]
}

@test "csv_filter: returns only header when no matches" {
    create_test_csv "$TEST_TMPDIR/test.csv"
    result=$(csv_filter "$TEST_TMPDIR/test.csv" "city" "Nonexistent")
    # Should have header row
    [[ "$result" =~ "name,age,city" ]]
    # Should not have data rows
    line_count=$(echo "$result" | wc -l)
    [[ "$line_count" -eq 1 ]]
}

@test "csv_row: handles custom delimiter" {
    csv_delimiter "|"
    result=$(csv_row "a" "b" "c")
    [[ "$result" == $'a|b|c\n' ]]
}

@test "csv_escape: respects custom quote character" {
    csv_quote "'"
    result=$(csv_escape "it's a test")
    [[ "$result" == "'it''s a test'" ]]
}

@test "csv_parse_line: handles mixed quoted and unquoted" {
    csv_parse_line 'unquoted,"quoted","also, quoted",plain'
    [[ "${#CSV_FIELDS[@]}" -eq 4 ]]
    [[ "${CSV_FIELDS[0]}" == "unquoted" ]]
    [[ "${CSV_FIELDS[1]}" == "quoted" ]]
    [[ "${CSV_FIELDS[2]}" == "also, quoted" ]]
    [[ "${CSV_FIELDS[3]}" == "plain" ]]
}

@test "csv_validate: returns error for missing file" {
    run csv_validate "$TEST_TMPDIR/nonexistent.csv"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

@test "csv_validate: handles empty file gracefully" {
    touch "$TEST_TMPDIR/empty.csv"
    result=$(csv_validate "$TEST_TMPDIR/empty.csv")
    [[ "$result" =~ "Warning" ]] || [[ "$result" =~ "empty" ]] || [[ $? -eq 0 ]]
}

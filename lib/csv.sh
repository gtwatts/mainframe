#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/csv.sh - Pure Bash CSV Parsing Library
# =============================================================================
# Description: RFC 4180 compliant CSV parsing without external tools
# Handles: Quoted fields, embedded commas, escaped quotes, newlines in quotes
# =============================================================================
# "Mainframe can parse your data faster than you can say 'spreadsheet'."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CSV_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CSV_LOADED=1

# =============================================================================
# GLOBAL STATE
# =============================================================================

# Parsed data storage
declare -a CSV_FIELDS=()      # Fields from last parsed line
declare -a CSV_HEADERS=()     # Column headers
declare -a CSV_ROWS=()        # All data rows (serialized)
declare -g CSV_DELIMITER=','  # Field delimiter
declare -g CSV_QUOTE='"'      # Quote character

# =============================================================================
# CONFIGURATION
# =============================================================================

# Set custom delimiter
# Usage: csv_delimiter "|" or csv_delimiter $'\t' for tabs
csv_delimiter() {
    CSV_DELIMITER="${1:-,}"
}

# Set custom quote character
# Usage: csv_quote "'"
csv_quote() {
    CSV_QUOTE="${1:-\"}"
}

# =============================================================================
# CORE PARSING - RFC 4180 State Machine
# =============================================================================

# Parse single CSV line into CSV_FIELDS array
# Handles: quoted fields, embedded delimiters, escaped quotes
# Usage: csv_parse_line "field1,\"field, two\",field3"
# Returns: Populates CSV_FIELDS array
csv_parse_line() {
    local line="$1"
    local len=${#line}
    local i=0
    local field=""
    local in_quotes=false
    local char next_char

    CSV_FIELDS=()

    while ((i < len)); do
        char="${line:$i:1}"
        next_char="${line:$((i+1)):1}"

        if $in_quotes; then
            if [[ "$char" == "$CSV_QUOTE" ]]; then
                # Check for escaped quote (doubled)
                if [[ "$next_char" == "$CSV_QUOTE" ]]; then
                    field+="$CSV_QUOTE"
                    ((i++)) || true
                else
                    # End of quoted section
                    in_quotes=false
                fi
            else
                field+="$char"
            fi
        else
            if [[ "$char" == "$CSV_QUOTE" ]]; then
                in_quotes=true
            elif [[ "$char" == "$CSV_DELIMITER" ]]; then
                CSV_FIELDS+=("$field")
                field=""
            else
                field+="$char"
            fi
        fi
        ((i++)) || true
    done

    # Add final field
    CSV_FIELDS+=("$field")
}

# Parse multiline CSV content (handles newlines in quoted fields)
# Usage: csv_parse_multiline "$content"
# Returns: Populates CSV_ROWS array with serialized rows
csv_parse_multiline() {
    local content="$1"
    local len=${#content}
    local i=0
    local line=""
    local in_quotes=false
    local char next_char

    CSV_ROWS=()

    while ((i < len)); do
        char="${content:$i:1}"
        next_char="${content:$((i+1)):1}"

        if $in_quotes; then
            if [[ "$char" == "$CSV_QUOTE" ]]; then
                if [[ "$next_char" == "$CSV_QUOTE" ]]; then
                    line+="$char$next_char"
                    ((i++)) || true
                else
                    in_quotes=false
                    line+="$char"
                fi
            else
                line+="$char"
            fi
        else
            if [[ "$char" == "$CSV_QUOTE" ]]; then
                in_quotes=true
                line+="$char"
            elif [[ "$char" == $'\n' ]]; then
                # End of logical line
                if [[ -n "$line" || ${#CSV_ROWS[@]} -eq 0 ]]; then
                    # Serialize the line for storage
                    CSV_ROWS+=("$line")
                fi
                line=""
            elif [[ "$char" == $'\r' ]]; then
                # Handle CRLF - skip CR
                :
            else
                line+="$char"
            fi
        fi
        ((i++)) || true
    done

    # Add final line if not empty
    [[ -n "$line" ]] && CSV_ROWS+=("$line")
}

# Parse entire CSV file
# Usage: csv_parse_file "data.csv"
# Returns: Populates CSV_ROWS array
csv_parse_file() {
    local file="$1"
    local content

    [[ ! -f "$file" ]] && { printf 'Error: File not found: %s\n' "$file" >&2; return 1; }

    # Read entire file preserving newlines
    content=$(<"$file")
    csv_parse_multiline "$content"
}

# Get field N from a CSV line (0-indexed)
# Usage: csv_field "line" 2
csv_field() {
    local line="$1"
    local index="$2"

    csv_parse_line "$line"
    printf '%s\n' "${CSV_FIELDS[$index]:-}"
}

# Count fields in a CSV line
# Usage: csv_field_count "line"
csv_field_count() {
    local line="$1"
    csv_parse_line "$line"
    printf '%d\n' "${#CSV_FIELDS[@]}"
}

# =============================================================================
# READING WITH HEADERS
# =============================================================================

# Read CSV file with headers (first row becomes CSV_HEADERS)
# Usage: csv_read "data.csv"
# Returns: Populates CSV_HEADERS and CSV_ROWS (excluding header)
csv_read() {
    local file="$1"

    csv_parse_file "$file" || return 1

    # First row is headers
    if ((${#CSV_ROWS[@]} > 0)); then
        csv_parse_line "${CSV_ROWS[0]}"
        CSV_HEADERS=("${CSV_FIELDS[@]}")
        # Remove header row from data
        CSV_ROWS=("${CSV_ROWS[@]:1}")
    fi
}

# Get value by row number and column name
# Usage: csv_get 0 "name"  # First data row, "name" column
csv_get() {
    local row_num="$1"
    local col_name="$2"
    local col_idx=-1

    # Find column index
    for i in "${!CSV_HEADERS[@]}"; do
        if [[ "${CSV_HEADERS[$i]}" == "$col_name" ]]; then
            col_idx=$i
            break
        fi
    done

    ((col_idx < 0)) && { printf 'Error: Column not found: %s\n' "$col_name" >&2; return 1; }

    # Get row and parse
    if ((row_num < ${#CSV_ROWS[@]})); then
        csv_parse_line "${CSV_ROWS[$row_num]}"
        printf '%s\n' "${CSV_FIELDS[$col_idx]:-}"
    else
        printf 'Error: Row %d not found\n' "$row_num" >&2
        return 1
    fi
}

# Get entire column as array (prints each value on new line)
# Usage: csv_column "name"
csv_column() {
    local col_name="$1"
    local col_idx=-1

    # Find column index
    for i in "${!CSV_HEADERS[@]}"; do
        if [[ "${CSV_HEADERS[$i]}" == "$col_name" ]]; then
            col_idx=$i
            break
        fi
    done

    ((col_idx < 0)) && { printf 'Error: Column not found: %s\n' "$col_name" >&2; return 1; }

    # Extract column from each row
    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        printf '%s\n' "${CSV_FIELDS[$col_idx]:-}"
    done
}

# Get column index by name
# Usage: csv_column_index "name"
csv_column_index() {
    local col_name="$1"

    for i in "${!CSV_HEADERS[@]}"; do
        if [[ "${CSV_HEADERS[$i]}" == "$col_name" ]]; then
            printf '%d\n' "$i"
            return 0
        fi
    done
    printf '%d\n' "-1"
    return 1
}

# =============================================================================
# BUILDING CSV
# =============================================================================

# Escape a value for CSV output (quotes if needed)
# Usage: csv_escape "value with, comma"
csv_escape() {
    local value="$1"
    local needs_quote=false

    # Check if quoting needed: contains delimiter, quote, newline, or leading/trailing space
    if [[ "$value" == *"$CSV_DELIMITER"* ]] || \
       [[ "$value" == *"$CSV_QUOTE"* ]] || \
       [[ "$value" == *$'\n'* ]] || \
       [[ "$value" == *$'\r'* ]] || \
       [[ "$value" =~ ^[[:space:]] ]] || \
       [[ "$value" =~ [[:space:]]$ ]]; then
        needs_quote=true
    fi

    if $needs_quote; then
        # Escape quotes by doubling them
        local escaped="${value//$CSV_QUOTE/$CSV_QUOTE$CSV_QUOTE}"
        printf '%s%s%s' "$CSV_QUOTE" "$escaped" "$CSV_QUOTE"
    else
        printf '%s' "$value"
    fi
}

# Create a properly formatted CSV row
# Usage: csv_row "val1" "val2" "val with, comma"
# Returns: "val1,val2,"val with, comma""
csv_row() {
    local first=true
    local escaped

    for value in "$@"; do
        if $first; then
            first=false
        else
            printf '%s' "$CSV_DELIMITER"
        fi
        escaped=$(csv_escape "$value")
        printf '%s' "$escaped"
    done
    printf '\n'
}

# Create header row (alias for csv_row)
# Usage: csv_header "col1" "col2" "col3"
csv_header() {
    csv_row "$@"
}

# =============================================================================
# WRITING CSV
# =============================================================================

# Write CSV_HEADERS and CSV_ROWS to file
# Usage: csv_write "output.csv" [append]
csv_write() {
    local file="$1"
    local mode="${2:-overwrite}"
    local output=""

    # Build header row
    if ((${#CSV_HEADERS[@]} > 0)); then
        output=$(csv_row "${CSV_HEADERS[@]}")
    fi

    # Build data rows
    for row in "${CSV_ROWS[@]}"; do
        output+="$row"$'\n'
    done

    if [[ "$mode" == "append" ]]; then
        printf '%s' "$output" >> "$file"
    else
        printf '%s' "$output" > "$file"
    fi
}

# Append a single row to a file
# Usage: csv_append_row "file.csv" "val1" "val2" "val3"
csv_append_row() {
    local file="$1"
    shift
    csv_row "$@" >> "$file"
}

# =============================================================================
# TRANSFORMATION
# =============================================================================

# Filter rows where column equals value
# Usage: csv_filter "file.csv" "status" "active"
# Outputs: Filtered CSV to stdout
csv_filter() {
    local file="$1"
    local col_name="$2"
    local match_value="$3"

    csv_read "$file" || return 1

    local col_idx
    col_idx=$(csv_column_index "$col_name") || return 1

    # Output header
    csv_row "${CSV_HEADERS[@]}"

    # Filter and output matching rows
    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        if [[ "${CSV_FIELDS[$col_idx]}" == "$match_value" ]]; then
            printf '%s\n' "$row"
        fi
    done
}

# Sort CSV by column (lexicographic)
# Usage: csv_sort "file.csv" "name"
# Outputs: Sorted CSV to stdout
# Performance: O(n log n) via system sort with extracted keys
csv_sort() {
    local file="$1"
    local col_name="$2"

    csv_read "$file" || return 1

    local col_idx
    col_idx=$(csv_column_index "$col_name") || return 1

    # Output header first
    csv_row "${CSV_HEADERS[@]}"

    # Extract sort keys paired with row indices, delegate to system sort
    local -a sort_pairs=()
    local i
    for i in "${!CSV_ROWS[@]}"; do
        csv_parse_line "${CSV_ROWS[$i]}"
        sort_pairs+=("${CSV_FIELDS[$col_idx]}"$'\t'"$i")
    done

    # Sort key-index pairs, then output rows in sorted order
    local sorted idx
    sorted=$(printf '%s\n' "${sort_pairs[@]}" | LC_ALL=C sort -t$'\t' -k1,1)
    while IFS=$'\t' read -r _ idx; do
        printf '%s\n' "${CSV_ROWS[$idx]}"
    done <<< "$sorted"
}

# Sort CSV by column (numeric)
# Usage: csv_sort_num "file.csv" "age"
# Performance: O(n log n) via system sort with extracted keys
csv_sort_num() {
    local file="$1"
    local col_name="$2"

    csv_read "$file" || return 1

    local col_idx
    col_idx=$(csv_column_index "$col_name") || return 1

    # Output header first
    csv_row "${CSV_HEADERS[@]}"

    # Extract sort keys paired with row indices, delegate to system sort
    local -a sort_pairs=()
    local i
    for i in "${!CSV_ROWS[@]}"; do
        csv_parse_line "${CSV_ROWS[$i]}"
        sort_pairs+=("${CSV_FIELDS[$col_idx]}"$'\t'"$i")
    done

    # Sort key-index pairs numerically, then output rows in sorted order
    local sorted idx
    sorted=$(printf '%s\n' "${sort_pairs[@]}" | LC_ALL=C sort -t$'\t' -k1,1n)
    while IFS=$'\t' read -r _ idx; do
        printf '%s\n' "${CSV_ROWS[$idx]}"
    done <<< "$sorted"
}

# Select specific columns
# Usage: csv_select "file.csv" "name,email"
# Outputs: CSV with only selected columns
csv_select() {
    local file="$1"
    local columns="$2"

    csv_read "$file" || return 1

    # Parse column list
    local -a col_names=()
    local -a col_indices=()

    # Split columns by comma (handle our own delimiter)
    local old_delim="$CSV_DELIMITER"
    CSV_DELIMITER=','
    csv_parse_line "$columns"
    col_names=("${CSV_FIELDS[@]}")
    CSV_DELIMITER="$old_delim"

    # Find indices
    for col in "${col_names[@]}"; do
        local idx
        idx=$(csv_column_index "$col")
        if ((idx >= 0)); then
            col_indices+=("$idx")
        else
            printf 'Warning: Column not found: %s\n' "$col" >&2
        fi
    done

    # Output selected headers
    local -a selected_headers=()
    for idx in "${col_indices[@]}"; do
        selected_headers+=("${CSV_HEADERS[$idx]}")
    done
    csv_row "${selected_headers[@]}"

    # Output selected columns from each row
    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        local -a selected_fields=()
        for idx in "${col_indices[@]}"; do
            selected_fields+=("${CSV_FIELDS[$idx]:-}")
        done
        csv_row "${selected_fields[@]}"
    done
}

# Convert CSV to JSON array of objects
# Usage: csv_to_json "file.csv"
# Outputs: JSON array
csv_to_json() {
    local file="$1"

    csv_read "$file" || return 1

    printf '[\n'

    local first_row=true
    for row in "${CSV_ROWS[@]}"; do
        if $first_row; then
            first_row=false
        else
            printf ',\n'
        fi

        csv_parse_line "$row"
        printf '  {'

        local first_field=true
        for i in "${!CSV_HEADERS[@]}"; do
            if $first_field; then
                first_field=false
            else
                printf ','
            fi
            local value="${CSV_FIELDS[$i]:-}"
            # Escape JSON special characters (RFC 8259 compliant)
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            value="${value//$'\n'/\\n}"
            value="${value//$'\r'/\\r}"
            value="${value//$'\t'/\\t}"
            value="${value//$'\b'/\\b}"
            value="${value//$'\f'/\\f}"
            printf '"%s":"%s"' "${CSV_HEADERS[$i]}" "$value"
        done

        printf '}'
    done

    printf '\n]\n'
}

# Convert JSON array of objects to CSV
# Usage: csv_from_json '[ {"name":"John"}, {"name":"Jane"} ]'
# Note: Limited implementation - expects flat objects
csv_from_json() {
    local json="$1"
    local in_object=false
    local in_string=false
    local in_key=false
    local in_value=false
    local current_key=""
    local current_value=""
    local char prev_char=""
    local len=${#json}
    local -A row_data=()
    local -a all_keys=()
    local -a rows=()
    local first_object=true

    for ((i=0; i<len; i++)); do
        char="${json:$i:1}"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
                if $in_key; then
                    in_key=false
                elif $in_value; then
                    in_value=false
                    row_data["$current_key"]="$current_value"
                    # Track keys for header
                    if $first_object; then
                        all_keys+=("$current_key")
                    fi
                    current_key=""
                    current_value=""
                fi
            else
                if $in_key; then
                    current_key+="$char"
                elif $in_value; then
                    current_value+="$char"
                fi
            fi
        else
            case "$char" in
                '{')
                    in_object=true
                    row_data=()
                    ;;
                '}')
                    in_object=false
                    # Serialize row
                    local -a values=()
                    for key in "${all_keys[@]}"; do
                        values+=("${row_data[$key]:-}")
                    done
                    rows+=("$(csv_row "${values[@]}")")
                    first_object=false
                    ;;
                '"')
                    in_string=true
                    if $in_object && [[ -z "$current_key" ]]; then
                        in_key=true
                    fi
                    ;;
                ':')
                    if $in_object; then
                        in_value=true
                    fi
                    ;;
            esac
        fi
        prev_char="$char"
    done

    # Output CSV
    csv_row "${all_keys[@]}"
    for row in "${rows[@]}"; do
        printf '%s' "$row"
    done
}

# =============================================================================
# UTILITIES
# =============================================================================

# Count data rows (excluding header)
# Usage: csv_row_count "file.csv"
csv_row_count() {
    local file="$1"
    csv_read "$file" || return 1
    printf '%d\n' "${#CSV_ROWS[@]}"
}

# Check if first row looks like a header
# Usage: csv_has_header "file.csv"
# Returns: 0 if likely header, 1 otherwise
csv_has_header() {
    local file="$1"

    csv_parse_file "$file" || return 1

    ((${#CSV_ROWS[@]} < 2)) && return 1

    # Parse first two rows
    csv_parse_line "${CSV_ROWS[0]}"
    local -a first_row=("${CSV_FIELDS[@]}")
    csv_parse_line "${CSV_ROWS[1]}"
    local -a second_row=("${CSV_FIELDS[@]}")

    # Heuristics:
    # 1. Headers usually don't have numbers
    # 2. Headers are often different types than data
    local numeric_in_first=0
    local numeric_in_second=0

    for field in "${first_row[@]}"; do
        [[ "$field" =~ ^[0-9]+\.?[0-9]*$ ]] && ((numeric_in_first++))
    done

    for field in "${second_row[@]}"; do
        [[ "$field" =~ ^[0-9]+\.?[0-9]*$ ]] && ((numeric_in_second++))
    done

    # If first row has fewer numbers than second, likely a header
    ((numeric_in_first < numeric_in_second)) && return 0

    # Check if first row values look like identifiers (lowercase, underscores)
    local identifier_count=0
    for field in "${first_row[@]}"; do
        if [[ "$field" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            ((identifier_count++))
        fi
    done

    # If most first row fields look like identifiers
    ((identifier_count > ${#first_row[@]} / 2)) && return 0

    return 1
}

# Validate CSV format
# Usage: csv_validate "file.csv"
# Returns: 0 if valid, 1 with error messages otherwise
csv_validate() {
    local file="$1"
    local errors=0

    [[ ! -f "$file" ]] && { printf 'Error: File not found: %s\n' "$file" >&2; return 1; }

    csv_parse_file "$file" || return 1

    ((${#CSV_ROWS[@]} == 0)) && { printf 'Warning: Empty file\n' >&2; return 0; }

    # Get field count from first row
    csv_parse_line "${CSV_ROWS[0]}"
    local expected_fields=${#CSV_FIELDS[@]}

    # Validate each row has same number of fields
    local row_num=1
    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        if ((${#CSV_FIELDS[@]} != expected_fields)); then
            printf 'Error: Row %d has %d fields, expected %d\n' \
                "$row_num" "${#CSV_FIELDS[@]}" "$expected_fields" >&2
            ((errors++))
        fi
        ((row_num++))
    done

    ((errors > 0)) && return 1
    printf 'Valid: %d rows, %d columns\n' "${#CSV_ROWS[@]}" "$expected_fields"
    return 0
}

# Get row as associative array
# Usage: csv_row_assoc 0; echo "${CSV_ROW_ASSOC[name]}"
declare -gA CSV_ROW_ASSOC=()
csv_row_assoc() {
    local row_num="$1"

    CSV_ROW_ASSOC=()

    if ((row_num >= ${#CSV_ROWS[@]})); then
        printf 'Error: Row %d not found\n' "$row_num" >&2
        return 1
    fi

    csv_parse_line "${CSV_ROWS[$row_num]}"

    for i in "${!CSV_HEADERS[@]}"; do
        CSV_ROW_ASSOC["${CSV_HEADERS[$i]}"]="${CSV_FIELDS[$i]:-}"
    done
}

# Iterate over rows with callback
# Usage: csv_each "file.csv" callback_function
# Callback receives: row_num, then associative array CSV_ROW_ASSOC is populated
csv_each() {
    local file="$1"
    local callback="$2"

    csv_read "$file" || return 1

    local row_num=0
    for row in "${CSV_ROWS[@]}"; do
        csv_row_assoc "$row_num"
        "$callback" "$row_num"
        ((row_num++))
    done
}

# Map transformation over rows
# Usage: csv_map "file.csv" transform_function
# Transform function receives CSV_ROW_ASSOC and should output a csv_row
csv_map() {
    local file="$1"
    local transform="$2"

    csv_read "$file" || return 1

    # Output header
    csv_row "${CSV_HEADERS[@]}"

    local row_num=0
    for row in "${CSV_ROWS[@]}"; do
        csv_row_assoc "$row_num"
        "$transform" "$row_num"
        ((row_num++))
    done
}

# Reduce CSV to single value
# Usage: csv_reduce "file.csv" "column" reduce_function initial_value
csv_reduce() {
    local file="$1"
    local col_name="$2"
    local reducer="$3"
    local accumulator="$4"

    csv_read "$file" || return 1

    local col_idx
    col_idx=$(csv_column_index "$col_name") || return 1

    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        accumulator=$("$reducer" "$accumulator" "${CSV_FIELDS[$col_idx]}")
    done

    printf '%s\n' "$accumulator"
}

# =============================================================================
# AGGREGATION
# =============================================================================

# Sum a numeric column
# Usage: csv_sum "file.csv" "amount"
csv_sum() {
    local file="$1"
    local col_name="$2"
    local sum=0

    csv_read "$file" || return 1

    local col_idx
    col_idx=$(csv_column_index "$col_name") || return 1

    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        local value="${CSV_FIELDS[$col_idx]:-0}"
        # Remove non-numeric characters for flexibility
        value="${value//[^0-9.-]/}"
        [[ -n "$value" ]] && sum=$(printf '%s + %s\n' "$sum" "$value" | bc 2>/dev/null || echo "$((sum + ${value%.*}))")
    done

    printf '%s\n' "$sum"
}

# Count rows matching condition
# Usage: csv_count "file.csv" "status" "active"
csv_count() {
    local file="$1"
    local col_name="$2"
    local match_value="$3"
    local count=0

    csv_read "$file" || return 1

    local col_idx
    col_idx=$(csv_column_index "$col_name") || return 1

    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        [[ "${CSV_FIELDS[$col_idx]}" == "$match_value" ]] && ((count++))
    done

    printf '%d\n' "$count"
}

# Group by column and count
# Usage: csv_group_count "file.csv" "status"
# Outputs: value,count pairs
csv_group_count() {
    local file="$1"
    local col_name="$2"

    csv_read "$file" || return 1

    local col_idx
    col_idx=$(csv_column_index "$col_name") || return 1

    declare -A counts=()

    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        local value="${CSV_FIELDS[$col_idx]}"
        ((counts["$value"]++))
    done

    printf '%s,count\n' "$col_name"
    for key in "${!counts[@]}"; do
        printf '%s,%d\n' "$key" "${counts[$key]}"
    done
}

# =============================================================================
# JOINING
# =============================================================================

# Inner join two CSV files on a column
# Usage: csv_join "file1.csv" "file2.csv" "key_column"
csv_join() {
    local file1="$1"
    local file2="$2"
    local key_col="$3"

    # Read first file
    csv_read "$file1" || return 1
    local -a headers1=("${CSV_HEADERS[@]}")
    local -a rows1=("${CSV_ROWS[@]}")
    local key_idx1
    key_idx1=$(csv_column_index "$key_col") || return 1

    # Read second file
    csv_read "$file2" || return 1
    local -a headers2=("${CSV_HEADERS[@]}")
    local -a rows2=("${CSV_ROWS[@]}")
    local key_idx2
    key_idx2=$(csv_column_index "$key_col") || return 1

    # Build lookup for file2
    declare -A file2_lookup=()
    for row in "${rows2[@]}"; do
        csv_parse_line "$row"
        local key="${CSV_FIELDS[$key_idx2]}"
        file2_lookup["$key"]="$row"
    done

    # Output combined headers (avoid duplicate key column)
    local -a combined_headers=("${headers1[@]}")
    for i in "${!headers2[@]}"; do
        ((i != key_idx2)) && combined_headers+=("${headers2[$i]}")
    done
    csv_row "${combined_headers[@]}"

    # Join rows
    for row1 in "${rows1[@]}"; do
        csv_parse_line "$row1"
        local -a fields1=("${CSV_FIELDS[@]}")
        local key="${fields1[$key_idx1]}"

        if [[ -n "${file2_lookup[$key]:-}" ]]; then
            csv_parse_line "${file2_lookup[$key]}"
            local -a fields2=("${CSV_FIELDS[@]}")

            # Combine fields
            local -a combined=("${fields1[@]}")
            for i in "${!fields2[@]}"; do
                ((i != key_idx2)) && combined+=("${fields2[$i]}")
            done
            csv_row "${combined[@]}"
        fi
    done
}

# =============================================================================
# PRETTY PRINTING
# =============================================================================

# Print CSV as formatted table
# Usage: csv_print "file.csv"
csv_print() {
    local file="$1"
    local max_width="${2:-40}"

    csv_read "$file" || return 1

    # Calculate column widths
    local -a widths=()
    for i in "${!CSV_HEADERS[@]}"; do
        widths[$i]=${#CSV_HEADERS[$i]}
    done

    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        for i in "${!CSV_FIELDS[@]}"; do
            local len=${#CSV_FIELDS[$i]}
            ((len > widths[i])) && widths[$i]=$len
            ((widths[i] > max_width)) && widths[$i]=$max_width
        done
    done

    # Print header
    local header_line=""
    local separator=""
    for i in "${!CSV_HEADERS[@]}"; do
        local w=${widths[$i]}
        printf '| %-*s ' "$w" "${CSV_HEADERS[$i]:0:$w}"
        separator+="+-$(printf '%*s' "$w" '' | tr ' ' '-')-"
    done
    printf '|\n'
    printf '%s+\n' "$separator"

    # Print rows
    for row in "${CSV_ROWS[@]}"; do
        csv_parse_line "$row"
        for i in "${!CSV_FIELDS[@]}"; do
            local w=${widths[$i]}
            printf '| %-*s ' "$w" "${CSV_FIELDS[$i]:0:$w}"
        done
        printf '|\n'
    done
}

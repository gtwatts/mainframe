# CSV Functions

CSV parsing, reading, and writing.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## CSV Functions (csv.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `csv_parse_line` | `csv_parse_line "line"` | `csv_parse_line 'a,"b,c",d'` | Sets CSV_FIELDS array |
| `csv_parse_file` | `csv_parse_file "file"` | `csv_parse_file "data.csv"` | Sets CSV_ROWS array |
| `csv_field` | `csv_field "line" index` | `csv_field "a,b,c" 1` | `b` |
| `csv_field_count` | `csv_field_count "line"` | `csv_field_count "a,b,c"` | `3` |
| `csv_read` | `csv_read "file"` | `csv_read "data.csv"` | Sets CSV_HEADERS + CSV_ROWS |
| `csv_get` | `csv_get row_num "column"` | `csv_get 0 "name"` | Field value |
| `csv_column` | `csv_column "column"` | `csv_column "email"` | Column values array |
| `csv_row` | `csv_row val1 val2 ...` | `csv_row "John" "john@ex.com"` | `John,john@ex.com` |
| `csv_escape` | `csv_escape "value"` | `csv_escape 'has, comma'` | `"has, comma"` |
| `csv_header` | `csv_header col1 col2 ...` | `csv_header "name" "email"` | `name,email` |
| `csv_write` | `csv_write "file"` | `csv_write "out.csv"` | Writes CSV_ROWS to file |
| `csv_append_row` | `csv_append_row "file" vals...` | `csv_append_row "f.csv" "a" "b"` | Appends row |
| `csv_filter` | `csv_filter "file" "col" "val"` | `csv_filter "f.csv" "status" "active"` | Filtered CSV |
| `csv_sort` | `csv_sort "file" "column"` | `csv_sort "data.csv" "name"` | Sorted CSV |
| `csv_select` | `csv_select "file" "cols"` | `csv_select "f.csv" "name,email"` | Selected columns |
| `csv_to_json` | `csv_to_json "file"` | `csv_to_json "data.csv"` | JSON array |
| `csv_row_count` | `csv_row_count "file"` | `csv_row_count "data.csv"` | `100` |
| `csv_validate` | `csv_validate "file"` | `csv_validate "data.csv"` | (returns 0/1) |
| `csv_delimiter` | `csv_delimiter "char"` | `csv_delimiter "\t"` | Sets delimiter (TSV) |

---

## Quick Patterns

### Read and Iterate
```bash
csv_read "users.csv"
for i in $(seq 0 $((${#CSV_ROWS[@]}-1))); do
    name=$(csv_get $i "name")
    email=$(csv_get $i "email")
    echo "$name: $email"
done
```

### Create CSV
```bash
csv_row "John" "john@example.com" >> users.csv
```

### Filter and Sort
```bash
# Filter by column value
csv_filter "data.csv" "status" "active" > active.csv

# Sort by column
csv_sort "data.csv" "name" > sorted.csv

# Select specific columns
csv_select "data.csv" "name,email" > names-emails.csv
```

### Convert to JSON
```bash
csv_to_json "users.csv" > users.json
```

### Handle Special Characters
```bash
# Escape values with commas or quotes
escaped=$(csv_escape 'Has, comma and "quotes"')
# Result: "Has, comma and ""quotes"""
```

### Tab-Separated Values (TSV)
```bash
csv_delimiter "\t"
csv_read "data.tsv"
```

---

## Format Parsers (parsers.sh)

Additional parsing functions for common formats.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `parse_csv_line` | `parse_csv_line "line"` | `parse_csv_line '"John","30","NYC"'` | (populates `PARSE_CSV_FIELDS` array) |
| `parse_csv_json` | `json=$(parse_csv_json "line")` | `parse_csv_json '"John","30","NYC"'` | `["John","30","NYC"]` |
| `parse_key_value` | `json=$(parse_key_value < file)` | `echo "host=localhost" \| parse_key_value` | `{"host":"localhost"}` |
| `parse_ini` | `json=$(parse_ini < file.ini)` | `parse_ini "[db]\nhost=localhost"` | `{"db":{"host":"localhost"}}` |
| `parse_url` | `json=$(parse_url "url")` | `parse_url "https://user:pass@host:8080/path?q=1"` | URL components as JSON |
| `parse_semver` | `json=$(parse_semver "version")` | `parse_semver "1.2.3-beta.1+build.456"` | Semver components as JSON |
| `semver_compare` | `cmp=$(semver_compare "v1" "v2")` | `semver_compare "1.2.3" "1.3.0"` | `-1` |

### Quick Patterns (Parsers)
```bash
# Parse CSV data with quoted fields
parse_csv_line '"John Doe","42","New York, NY"'
echo "${PARSE_CSV_FIELDS[0]}"  # John Doe
echo "${PARSE_CSV_FIELDS[2]}"  # New York, NY (handles commas in quotes)

# Parse config file to JSON
config=$(parse_key_value < /etc/myapp.conf)
echo "$config"  # {"host":"localhost","port":"5432","debug":"true"}

# Parse INI with sections
result=$(parse_ini < /etc/config.ini)
echo "$result"
# {"database":{"host":"localhost","port":"5432"},"cache":{"ttl":"3600"}}

# Parse URL components
info=$(parse_url "https://api.example.com:8443/v2/users?page=1")
echo "$info"  # {"scheme":"https","host":"api.example.com","port":8443,...}

# Compare versions
cmp=$(semver_compare "1.9.0" "2.0.0")
if [[ "$cmp" == "-1" ]]; then
    echo "Upgrade available"
fi
```

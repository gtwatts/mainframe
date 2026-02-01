# Validation Functions

Input validation, sanitization, and regex operations.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Validation Functions (validation.sh)

### Type Validation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `validate_int` | `validate_int "value" [min] [max]` | `validate_int "42" 0 100` | (returns 0/1) |
| `validate_float` | `validate_float "value"` | `validate_float "3.14"` | (returns 0/1) |
| `validate_bool` | `validate_bool "value"` | `validate_bool "true"` | (returns 0/1) |
| `validate_uuid` | `validate_uuid "value"` | `validate_uuid "550e8400-..."` | (returns 0/1) |
| `validate_hex` | `validate_hex "value" [length]` | `validate_hex "ff00ff" 6` | (returns 0/1) |

### Format Validation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `validate_email` | `validate_email "address"` | `validate_email "a@b.com"` | (returns 0/1) |
| `validate_url` | `validate_url "url" [schemes]` | `validate_url "https://..."` | (returns 0/1) |
| `validate_domain` | `validate_domain "domain"` | `validate_domain "example.com"` | (returns 0/1) |
| `validate_ipv4` | `validate_ipv4 "address"` | `validate_ipv4 "192.168.1.1"` | (returns 0/1) |
| `validate_ipv6` | `validate_ipv6 "address"` | `validate_ipv6 "::1"` | (returns 0/1) |
| `validate_date` | `validate_date "YYYY-MM-DD"` | `validate_date "2024-01-15"` | (returns 0/1) |
| `validate_time` | `validate_time "HH:MM:SS"` | `validate_time "14:30:00"` | (returns 0/1) |
| `validate_semver` | `validate_semver "version"` | `validate_semver "1.2.3"` | (returns 0/1) |
| `validate_port` | `validate_port "port"` | `validate_port "8080"` | (returns 0/1) |
| `validate_mac` | `validate_mac "address"` | `validate_mac "00:1A:2B:..."` | (returns 0/1) |
| `validate_phone` | `validate_phone "number"` | `validate_phone "+1234567890"` | (returns 0/1) |
| `validate_cidr` | `validate_cidr "cidr"` | `validate_cidr "192.168.1.0/24"` | (returns 0/1) |
| `validate_base64` | `validate_base64 "string"` | `validate_base64 "aGVsbG8="` | (returns 0/1) |
| `validate_credit_card` | `validate_credit_card "num"` | `validate_credit_card "4111..."` | (returns 0/1) |

### Path Validation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `validate_path` | `validate_path "path" [type]` | `validate_path "/tmp" "dir"` | (returns 0/1) |
| `validate_path_safe` | `validate_path_safe "path" [base]` | `validate_path_safe "f.txt" "/app"` | (returns 0/1) |
| `validate_filename` | `validate_filename "name"` | `validate_filename "report.pdf"` | (returns 0/1) |
| `validate_path_chars` | `validate_path_chars "path"` | `validate_path_chars "/safe/path"` | (returns 0/1) |

### Sanitization

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `sanitize_shell_arg` | `sanitize_shell_arg "value"` | `sanitize_shell_arg "a; rm -rf"` | `a\;\ rm\ -rf` |
| `sanitize_filename` | `sanitize_filename "name" [repl]` | `sanitize_filename "a/b<c>.txt"` | `a_b_c_.txt` |
| `sanitize_sql` | `sanitize_sql "value"` | `sanitize_sql "O'Brien"` | `O''Brien` |
| `sanitize_html` | `sanitize_html "value"` | `sanitize_html "<script>"` | `&lt;script&gt;` |
| `sanitize_json` | `sanitize_json "value"` | `sanitize_json 'say "hi"'` | `say \"hi\"` |

### Complex Validation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `validate_regex` | `validate_regex "value" "pattern"` | `validate_regex "abc" "^[a-z]+$"` | (returns 0/1) |
| `validate_length` | `validate_length "value" [min] [max]` | `validate_length "hello" 1 10` | (returns 0/1) |
| `validate_enum` | `validate_enum "val" "opt1" "opt2"` | `validate_enum "a" "a" "b" "c"` | (returns 0/1) |
| `validate_all` | `validate_all "func" "${arr[@]}"` | `validate_all validate_int 1 2 3` | (returns 0/1) |
| `validate_json` | `validate_json "string"` | `validate_json '{"a":1}'` | (returns 0/1) |
| `validate_alnum` | `validate_alnum "string" [allow_]` | `validate_alnum "abc123"` | (returns 0/1) |
| `validate_slug` | `validate_slug "string"` | `validate_slug "my-slug"` | (returns 0/1) |

### Command Safety

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `validate_command_safe` | `validate_command_safe "cmd"` | `validate_command_safe "ls -la"` | (returns 0/1) |
| `build_safe_command` | `build_safe_command "cmd" args...` | `build_safe_command "grep" "pat" "file"` | Escaped command |

---

## Regex Functions (regex.sh)

Pure bash regex operations with ReDoS protection.

### Common Patterns (Constants)

| Constant | Description |
|----------|-------------|
| `REGEX_EMAIL` | RFC 5322 simplified |
| `REGEX_URL` | HTTP/HTTPS/FTP URL |
| `REGEX_IPV4` | IPv4 address |
| `REGEX_UUID` | UUID v1-v5 |
| `REGEX_SEMVER` | Semantic version |
| `REGEX_DATE_ISO` | ISO 8601 date |
| `REGEX_SLUG` | URL slug |
| `REGEX_IDENTIFIER` | Variable name |
| `REGEX_HEX_COLOR` | Hex color code |
| `REGEX_MAC_ADDRESS` | MAC address |

### Core Matching

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `regex_match` | `regex_match "string" "pattern"` | `regex_match "hello" "[a-z]+"` | (returns 0/1) |
| `regex_test` | `regex_test "string" "pattern"` | `regex_test "hello" "[a-z]+"` | (returns 0/1) |
| `regex_find` | `regex_find "string" "pattern"` | `regex_find "hi123" "[0-9]+"` | `123` |
| `regex_find_all` | `regex_find_all "string" "pattern"` | `regex_find_all "a1b2" "[0-9]"` | `1\n2` |
| `regex_groups` | `regex_groups "string" "pattern"` | `regex_groups "hi123" "([a-z]+)([0-9]+)"` | Groups output |

### Replacement

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `regex_replace` | `regex_replace "str" "pat" "repl"` | `regex_replace "hello" "l" "L"` | `heLlo` |
| `regex_replace_all` | `regex_replace_all "str" "pat" "repl"` | `regex_replace_all "aaa" "a" "b"` | `bbb` |
| `regex_sub` | `regex_sub "str" "pat" "\\1 \\2"` | `regex_sub "ab" "(.)(.)" "\\2\\1"` | `ba` |

### Extraction

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `regex_extract` | `regex_extract "string" "pattern"` | `regex_extract "hi123" "[0-9]+"` | `123` |
| `regex_extract_all` | `regex_extract_all "string" "pattern"` | `regex_extract_all "a1b2" "[0-9]"` | `1\n2` |

### Validation & Safety (ReDoS Protection)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `regex_is_valid` | `regex_is_valid "pattern"` | `regex_is_valid "[a-z]+"` | (returns 0/1) |
| `regex_compile_safe` | `regex_compile_safe "pattern"` | `regex_compile_safe "(a+)+"` | 1 (dangerous) |
| `regex_complexity_score` | `regex_complexity_score "pattern"` | `regex_complexity_score "[a-z]+"` | `7` (safe) |

### Pattern Builders

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `regex_any_of` | `regex_any_of opt1 opt2 ...` | `regex_any_of "cat" "dog"` | `(cat\|dog)` |
| `regex_sequence` | `regex_sequence pat1 pat2 ...` | `regex_sequence "[a-z]" "[0-9]"` | `[a-z][0-9]` |
| `regex_optional` | `regex_optional "pattern"` | `regex_optional "[a-z]+"` | `(?:[a-z]+)?` |
| `regex_repeat` | `regex_repeat "pat" min [max]` | `regex_repeat "[a-z]" 2 5` | `(?:[a-z]){2,5}` |
| `regex_anchor` | `regex_anchor "pat" [type]` | `regex_anchor "[a-z]+" "both"` | `^[a-z]+$` |

### Utilities

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `regex_escape` | `regex_escape "string"` | `regex_escape "file.txt"` | `file\.txt` |
| `regex_count` | `regex_count "string" "pattern"` | `regex_count "a1b2c3" "[0-9]"` | `3` |
| `regex_remove` | `regex_remove "string" "pattern"` | `regex_remove "a1b2" "[0-9]"` | `ab` |
| `glob_to_regex` | `glob_to_regex "glob"` | `glob_to_regex "*.txt"` | `^.*\.txt$` |

---

## Quick Patterns

### Input Validation
```bash
# Validate user input
read -p "Enter age: " age
if validate_int "$age" 1 120; then
    echo "Valid age: $age"
else
    echo "Invalid age"
fi
```

### Secure Path Handling
```bash
# Validate path stays within base directory
if validate_path_safe "$user_input" "/var/www/uploads"; then
    cat "$user_input"
else
    echo "Invalid path - access denied"
fi
```

### Sanitize for Output
```bash
# Sanitize user input for HTML display
username=$(sanitize_html "$raw_input")
echo "<p>Welcome, $username</p>"

# Build safe shell command
cmd=$(build_safe_command "grep" "$pattern" "$file")
eval "$cmd"
```

### Batch Validation
```bash
# Validate all items in array
ports=(80 443 8080)
if validate_all validate_port "${ports[@]}"; then
    echo "All ports valid"
fi
```

### Regex Matching
```bash
# Test if string matches pattern
if regex_match "$input" "^[0-9]+$"; then
    echo "Input is numeric"
fi

# Extract data
number=$(regex_find "Order #12345" "[0-9]+")
echo "Order number: $number"  # 12345
```

### ReDoS Protection
```bash
# Validate pattern safety before use
if regex_compile_safe "$user_pattern"; then
    regex_match "$input" "$user_pattern"
else
    echo "Pattern rejected - potential ReDoS attack"
fi
```

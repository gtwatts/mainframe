# MAINFRAME Function Cheatsheet

**Quick Reference for AI Coding Assistants**

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## String Functions (pure-string.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trim_string` | `trim_string "string"` | `trim_string "  hello  "` | `hello` |
| `trim_left` | `trim_left "string"` | `trim_left "  hello"` | `hello` |
| `trim_right` | `trim_right "string"` | `trim_right "hello  "` | `hello` |
| `to_lower` | `to_lower "string"` | `to_lower "HELLO"` | `hello` |
| `to_upper` | `to_upper "string"` | `to_upper "hello"` | `HELLO` |
| `capitalize` | `capitalize "string"` | `capitalize "hello"` | `Hello` |
| `strlen` | `strlen "string"` | `strlen "hello"` | `5` |
| `substring` | `substring "string" start [length]` | `substring "hello" 0 3` | `hel` |
| `contains` | `contains "string" "substr"` | `contains "hello" "ell"` | (returns 0/1) |
| `starts_with` | `starts_with "string" "prefix"` | `starts_with "hello" "hel"` | (returns 0/1) |
| `ends_with` | `ends_with "string" "suffix"` | `ends_with "hello" "lo"` | (returns 0/1) |
| `replace_first` | `replace_first "string" "old" "new"` | `replace_first "aa" "a" "b"` | `ba` |
| `replace_all` | `replace_all "string" "old" "new"` | `replace_all "aa" "a" "b"` | `bb` |
| `strip_all` | `strip_all "string" "chars"` | `strip_all "hello" "l"` | `heo` |
| `urlencode` | `urlencode "string"` | `urlencode "a b"` | `a%20b` |
| `urldecode` | `urldecode "string"` | `urldecode "a%20b"` | `a b` |
| `is_empty` | `is_empty "string"` | `is_empty ""` | (returns 0/1) |
| `pad_left` | `pad_left "string" width [char]` | `pad_left "hi" 5` | `   hi` |
| `pad_right` | `pad_right "string" width [char]` | `pad_right "hi" 5` | `hi   ` |
| `repeat_string` | `repeat_string "string" count` | `repeat_string "ab" 3` | `ababab` |

---

## Array Functions (pure-array.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `array_length` | `array_length "${arr[@]}"` | `array_length a b c` | `3` |
| `array_first` | `array_first "${arr[@]}"` | `array_first a b c` | `a` |
| `array_last` | `array_last "${arr[@]}"` | `array_last a b c` | `c` |
| `array_get` | `array_get index "${arr[@]}"` | `array_get 1 a b c` | `b` |
| `array_contains` | `array_contains "val" "${arr[@]}"` | `array_contains "b" a b c` | (returns 0/1) |
| `array_index_of` | `array_index_of "val" "${arr[@]}"` | `array_index_of "b" a b c` | `1` |
| `array_join` | `array_join "sep" "${arr[@]}"` | `array_join "," a b c` | `a,b,c` |
| `array_unique` | `array_unique "${arr[@]}"` | `array_unique a b a c` | `a b c` |
| `array_sort` | `array_sort "${arr[@]}"` | `array_sort c a b` | `a b c` |
| `array_reverse` | `array_reverse "${arr[@]}"` | `array_reverse a b c` | `c b a` |
| `array_slice` | `array_slice start count "${arr[@]}"` | `array_slice 1 2 a b c d` | `b c` |
| `array_sum` | `array_sum "${nums[@]}"` | `array_sum 1 2 3 4 5` | `15` |
| `array_avg` | `array_avg "${nums[@]}"` | `array_avg 10 20 30` | `20` |
| `array_min` | `array_min "${nums[@]}"` | `array_min 5 2 8` | `2` |
| `array_max` | `array_max "${nums[@]}"` | `array_max 5 2 8` | `8` |
| `array_remove` | `array_remove "val" "${arr[@]}"` | `array_remove "b" a b c` | `a c` |
| `array_diff` | `array_diff "a b c" "b"` | `array_diff "a b c" "b"` | `a c` |
| `array_intersect` | `array_intersect "a b" "b c"` | `array_intersect "a b" "b c"` | `b` |
| `array_shuffle` | `array_shuffle "${arr[@]}"` | `array_shuffle a b c` | (random order) |

---

## JSON Functions (json.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `json_object` | `json_object key=val key:type=val` | `json_object name=John age:number=30` | `{"name":"John","age":30}` |
| `json_array` | `json_array val1 val2 ...` | `json_array a b c` | `["a","b","c"]` |
| `json_array_typed` | `json_array_typed type val1 val2` | `json_array_typed number 1 2 3` | `[1,2,3]` |
| `json_nested` | `json_nested "path.to.key" value` | `json_nested "user.name" "John"` | `{"user":{"name":"John"}}` |
| `json_string` | `json_string "value"` | `json_string "hello"` | `"hello"` |
| `json_number` | `json_number value` | `json_number 42` | `42` |
| `json_bool` | `json_bool value` | `json_bool true` | `true` |
| `json_null` | `json_null` | `json_null` | `null` |
| `json_escape` | `json_escape "string"` | `json_escape 'say "hi"'` | `say \"hi\"` |
| `json_merge` | `json_merge json1 json2` | `json_merge '{"a":1}' '{"b":2}'` | `{"a":1,"b":2}` |
| `json_pretty` | `json_pretty json` | `json_pretty '{"a":1}'` | (formatted) |
| `json_valid` | `json_valid json` | `json_valid '{"a":1}'` | (returns 0/1) |
| `json_get` | `json_get json key` | `json_get '{"a":1}' "a"` | `1` |
| `json_keys` | `json_keys json` | `json_keys '{"a":1,"b":2}'` | `a b` |

**json_object type modifiers:**
- `key=value` → string
- `key:number=value` → number
- `key:bool=value` → boolean
- `key:null=` → null

---

## Utility Functions (pure-util.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `uuid` | `uuid` | `uuid` | `550e8400-e29b-...` |
| `timestamp` | `timestamp` | `timestamp` | `2026-01-17 12:30:45` |
| `timestamp_iso` | `timestamp_iso` | `timestamp_iso` | `2026-01-17T12:30:45Z` |
| `epoch` | `epoch` | `epoch` | `1737123045` |
| `epoch_ms` | `epoch_ms` | `epoch_ms` | `1737123045123` |
| `random_string` | `random_string [length]` | `random_string 16` | `a1b2c3d4e5f6g7h8` |
| `random_range` | `random_range min max` | `random_range 1 100` | `42` |
| `random_hex` | `random_hex [length]` | `random_hex 8` | `a1b2c3d4` |
| `is_email` | `is_email "email"` | `is_email "a@b.com"` | (returns 0/1) |
| `is_url` | `is_url "url"` | `is_url "https://..."` | (returns 0/1) |
| `is_ip` | `is_ip "ip"` | `is_ip "192.168.1.1"` | (returns 0/1) |
| `is_int` | `is_int "value"` | `is_int "123"` | (returns 0/1) |
| `is_float` | `is_float "value"` | `is_float "12.34"` | (returns 0/1) |
| `abs` | `abs number` | `abs -5` | `5` |
| `clamp` | `clamp value min max` | `clamp 15 0 10` | `10` |
| `pow` | `pow base exp` | `pow 2 3` | `8` |
| `factorial` | `factorial n` | `factorial 5` | `120` |
| `gcd` | `gcd a b` | `gcd 12 8` | `4` |
| `hex_to_rgb` | `hex_to_rgb "hex"` | `hex_to_rgb "ff0000"` | `255 0 0` |
| `rgb_to_hex` | `rgb_to_hex r g b` | `rgb_to_hex 255 0 0` | `ff0000` |
| `current_user` | `current_user` | `current_user` | `username` |
| `get_hostname` | `get_hostname` | `get_hostname` | `hostname` |
| `get_os` | `get_os` | `get_os` | `linux` |
| `cmd_exists` | `cmd_exists "cmd"` | `cmd_exists "git"` | (returns 0/1) |
| `cmd_path` | `cmd_path "cmd"` | `cmd_path "bash"` | `/bin/bash` |
| `format_bytes` | `format_bytes bytes` | `format_bytes 1048576` | `1.0MB` |
| `format_bytes_int` | `format_bytes_int bytes` | `format_bytes_int 1048576` | `1MB` |
| `format_duration` | `format_duration seconds` | `format_duration 3661` | `1h 1m 1s` |
| `format_number` | `format_number n` | `format_number 1234567` | `1,234,567` |
| `format_percent` | `format_percent val total` | `format_percent 75 100` | `75%` |

---

## File Functions (pure-file.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `read_file` | `read_file "path"` | `read_file "/etc/hosts"` | (file contents) |
| `file_head` | `file_head "path" [n]` | `file_head "file" 5` | (first 5 lines) |
| `file_tail` | `file_tail "path" [n]` | `file_tail "file" 5` | (last 5 lines) |
| `file_line` | `file_line "path" n` | `file_line "file" 3` | (line 3) |
| `file_lines` | `file_lines "path"` | `file_lines "file"` | `42` |
| `file_size` | `file_size "path"` | `file_size "file"` | `1024` |
| `file_exists` | `file_exists "path"` | `file_exists "file"` | (returns 0/1) |
| `dir_exists` | `dir_exists "path"` | `dir_exists "/tmp"` | (returns 0/1) |
| `file_write` | `file_write "path" "content"` | `file_write "f" "hi"` | (writes file) |
| `file_append` | `file_append "path" "content"` | `file_append "f" "more"` | (appends) |
| `path_basename` | `path_basename "path"` | `path_basename "/a/b.txt"` | `b.txt` |
| `path_dirname` | `path_dirname "path"` | `path_dirname "/a/b.txt"` | `/a` |
| `path_extension` | `path_extension "path"` | `path_extension "f.txt"` | `txt` |
| `path_stem` | `path_stem "path"` | `path_stem "file.txt"` | `file` |
| `path_join` | `path_join p1 p2 ...` | `path_join "/a" "b" "c"` | `/a/b/c` |
| `file_grep` | `file_grep "path" "pattern"` | `file_grep "f" "error"` | (matching lines) |

---

## Semver Functions (semver.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `semver_valid` | `semver_valid "version"` | `semver_valid "1.2.3"` | (returns 0/1) |
| `semver_bump_major` | `semver_bump_major "ver"` | `semver_bump_major "1.2.3"` | `2.0.0` |
| `semver_bump_minor` | `semver_bump_minor "ver"` | `semver_bump_minor "1.2.3"` | `1.3.0` |
| `semver_bump_patch` | `semver_bump_patch "ver"` | `semver_bump_patch "1.2.3"` | `1.2.4` |
| `semver_compare` | `semver_compare "v1" "v2"` | `semver_compare "1.0" "2.0"` | `-1` |
| `semver_gt` | `semver_gt "v1" "v2"` | `semver_gt "2.0" "1.0"` | (returns 0/1) |
| `semver_lt` | `semver_lt "v1" "v2"` | `semver_lt "1.0" "2.0"` | (returns 0/1) |
| `semver_eq` | `semver_eq "v1" "v2"` | `semver_eq "1.0" "1.0"` | (returns 0/1) |
| `semver_latest` | `semver_latest v1 v2 ...` | `semver_latest "1.0" "2.0"` | `2.0` |
| `semver_sort` | `semver_sort v1 v2 ...` | `semver_sort "2.0" "1.0"` | `1.0 2.0` |

---

## Common Functions (common.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `log_info` | `log_info "message"` | `log_info "Starting..."` | `[INFO] Starting...` |
| `log_warn` | `log_warn "message"` | `log_warn "Warning!"` | `[WARN] Warning!` |
| `log_error` | `log_error "message"` | `log_error "Failed!"` | `[ERROR] Failed!` |
| `success` | `success "message"` | `success "Done!"` | `[OK] Done!` |
| `failure` | `failure "message"` | `failure "Error!"` | `[FAIL] Error!` |
| `header` | `header "text"` | `header "Section"` | (formatted header) |
| `die` | `die code "message"` | `die 1 "Error"` | (exits with code) |
| `assert` | `assert condition "msg"` | `assert "[[ -f x ]]" "no file"` | (exits if false) |
| `progress_bar` | `progress_bar cur total [width]` | `progress_bar 50 100` | `[████░░░░] 50%` |
| `is_valid_email` | `is_valid_email "email"` | `is_valid_email "a@b.c"` | (returns 0/1) |
| `is_valid_url` | `is_valid_url "url"` | `is_valid_url "http://..."` | (returns 0/1) |
| `command_exists` | `command_exists "cmd"` | `command_exists "git"` | (returns 0/1) |
| `temp_file` | `temp_file` | `f=$(temp_file)` | `/tmp/xxx` |
| `temp_dir` | `temp_dir` | `d=$(temp_dir)` | `/tmp/xxx` |

---

## Async Functions (async.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `parallel` | `parallel cmd1 cmd2 ...` | `parallel "task1" "task2"` | (runs in parallel) |
| `parallel_limit` | `parallel_limit n cmds...` | `parallel_limit 4 "${tasks[@]}"` | (limited concurrency) |
| `retry` | `retry count cmd` | `retry 3 "curl url"` | (retries on failure) |
| `set_timeout` | `set_timeout secs cmd` | `set_timeout 5 "task"` | (runs after delay) |
| `debounce` | `debounce ms cmd` | `debounce 100 "save"` | (debounced call) |

---

## Config Functions (config.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `config_load` | `config_load "path"` | `config_load "app.conf"` | (loads config) |
| `config_get` | `config_get "key"` | `config_get "name"` | `value` |
| `config_get_int` | `config_get_int "key"` | `config_get_int "port"` | `8080` |
| `config_get_bool` | `config_get_bool "key"` | `config_get_bool "debug"` | (returns 0/1) |
| `config_set` | `config_set "key" "value"` | `config_set "name" "app"` | (sets value) |
| `config_has` | `config_has "key"` | `config_has "name"` | (returns 0/1) |
| `config_save` | `config_save "path"` | `config_save "app.conf"` | (saves config) |

---

## ANSI/Color Functions (ansi.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ansi_red` | `ansi_red` | `echo "$(ansi_red)Error$(ansi_reset)"` | (red text) |
| `ansi_green` | `ansi_green` | `echo "$(ansi_green)OK$(ansi_reset)"` | (green text) |
| `ansi_yellow` | `ansi_yellow` | `echo "$(ansi_yellow)Warn$(ansi_reset)"` | (yellow text) |
| `ansi_blue` | `ansi_blue` | `echo "$(ansi_blue)Info$(ansi_reset)"` | (blue text) |
| `ansi_bold` | `ansi_bold` | `echo "$(ansi_bold)Bold$(ansi_reset)"` | (bold text) |
| `ansi_reset` | `ansi_reset` | `ansi_reset` | (reset formatting) |
| `ansi_print` | `ansi_print color text` | `ansi_print red "Error"` | (colored text) |
| `ansi_styled` | `ansi_styled "styles" text` | `ansi_styled "bold,red" "X"` | (styled text) |

---

## Quick Patterns

### Generate JSON Response
```bash
response=$(json_object \
    status="success" \
    id="$(uuid)" \
    timestamp="$(timestamp)" \
    count:number=42 \
    active:bool=true
)
```

### Validate Input
```bash
is_valid_email "$email" || die 1 "Invalid email"
is_valid_url "$url" || die 1 "Invalid URL"
```

### Process Array
```bash
items=("a" "b" "c" "a")
unique=($(array_unique "${items[@]}"))
echo "Count: $(array_length "${unique[@]}")"
echo "Joined: $(array_join ', ' "${unique[@]}")"
```

### File Operations
```bash
if file_exists "$path"; then
    content=$(read_file "$path")
    lines=$(file_lines "$path")
    echo "File has $lines lines"
fi
```

### Progress Display
```bash
for i in {1..100}; do
    progress_bar "$i" 100
    sleep 0.01
done
echo ""
success "Complete!"
```

---

## DateTime Functions (datetime.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `now` | `now` | `now` | `1705312896` (Unix timestamp) |
| `now_ms` | `now_ms` | `now_ms` | `1705312896123` |
| `now_iso` | `now_iso` | `now_iso` | `2024-01-15T10:30:00-0500` |
| `now_rfc2822` | `now_rfc2822` | `now_rfc2822` | `Mon, 15 Jan 2024 10:30:00 -0500` |
| `parse_iso` | `parse_iso "iso_string"` | `parse_iso "2024-01-15T10:30:00Z"` | `1705312200` |
| `parse_date` | `parse_date "date_string"` | `parse_date "2024-01-15"` | `1705276800` |
| `format_epoch` | `format_epoch epoch "format"` | `format_epoch 1705312896 "%Y-%m-%d"` | `2024-01-15` |
| `format_iso` | `format_iso [epoch]` | `format_iso` | `2024-01-15T10:30:00Z` |
| `format_date` | `format_date [epoch]` | `format_date` | `2024-01-15` |
| `format_time` | `format_time [epoch]` | `format_time` | `10:30:00` |
| `format_relative` | `format_relative epoch` | `format_relative $(($(now)-3600))` | `1 hour ago` |
| `date_add` | `date_add epoch "duration"` | `date_add $(now) "2d"` | (epoch + 2 days) |
| `date_subtract` | `date_subtract epoch "duration"` | `date_subtract $(now) "1w"` | (epoch - 1 week) |
| `date_diff` | `date_diff epoch1 epoch2` | `date_diff 1705312896 1705226496` | `86400` (seconds) |
| `date_diff_human` | `date_diff_human epoch1 epoch2` | `date_diff_human $e1 $e2` | `1 day, 2 hours` |
| `year` | `year [epoch]` | `year` | `2024` |
| `month` | `month [epoch]` | `month` | `1` |
| `day` | `day [epoch]` | `day` | `15` |
| `day_of_week` | `day_of_week [epoch]` | `day_of_week` | `Monday` |
| `is_weekend` | `is_weekend [epoch]` | `is_weekend` | (returns 0/1) |
| `is_weekday` | `is_weekday [epoch]` | `is_weekday` | (returns 0/1) |
| `is_leap_year` | `is_leap_year year` | `is_leap_year 2024` | (returns 0/1) |
| `start_of_day` | `start_of_day [epoch]` | `start_of_day` | (midnight epoch) |
| `end_of_day` | `end_of_day [epoch]` | `end_of_day` | (23:59:59 epoch) |
| `start_of_month` | `start_of_month [epoch]` | `start_of_month` | (first day epoch) |
| `end_of_month` | `end_of_month [epoch]` | `end_of_month` | (last day epoch) |

---

## HTTP Functions (http.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `http_get` | `http_get "url"` | `http_get "http://api.example.com/data"` | Response body |
| `http_post` | `http_post "url" "data"` | `http_post "http://api.example.com" "name=test"` | Response body |
| `http_put` | `http_put "url" "data"` | `http_put "http://api.example.com/1" "{}"` | Response body |
| `http_delete` | `http_delete "url"` | `http_delete "http://api.example.com/1"` | Response body |
| `http_head` | `http_head "url"` | `http_head "http://example.com"` | Headers only |
| `http_json_get` | `http_json_get "url"` | `http_json_get "http://api.example.com"` | JSON response |
| `http_json_post` | `http_json_post "url" "json"` | `http_json_post "$url" '{"name":"test"}'` | JSON response |
| `url_parse` | `url_parse "url"` | `url_parse "http://host:8080/path?q=1"` | Sets URL_* vars |
| `url_encode` | `url_encode "string"` | `url_encode "hello world"` | `hello%20world` |
| `url_decode` | `url_decode "string"` | `url_decode "hello%20world"` | `hello world` |
| `query_string` | `query_string "k=v" "k2=v2"` | `query_string "a=1" "b=2"` | `a=1&b=2` |
| `http_header` | `http_header "name" "value"` | `http_header "Accept" "application/json"` | Header line |
| `http_auth_basic` | `http_auth_basic "user" "pass"` | `http_auth_basic "admin" "secret"` | Auth header |
| `http_auth_bearer` | `http_auth_bearer "token"` | `http_auth_bearer "abc123"` | Auth header |
| `http_status` | `http_status` | `http_status` | `200` (last response) |
| `http_body` | `http_body` | `http_body` | Response body |
| `http_header_get` | `http_header_get "name"` | `http_header_get "Content-Type"` | Header value |
| `http_is_success` | `http_is_success` | `http_is_success && echo "OK"` | (returns 0/1) |

**Note**: Pure bash HTTP only. HTTPS requires openssl.

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

## Git Functions (git.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_is_repo` | `git_is_repo` | `git_is_repo && echo "yes"` | (returns 0/1) |
| `git_root` | `git_root` | `git_root` | `/path/to/repo` |
| `git_branch` | `git_branch` | `git_branch` | `main` |
| `git_branches` | `git_branches` | `git_branches` | List of branches |
| `git_default_branch` | `git_default_branch` | `git_default_branch` | `main` or `master` |
| `git_is_dirty` | `git_is_dirty` | `git_is_dirty && echo "uncommitted"` | (returns 0/1) |
| `git_is_clean` | `git_is_clean` | `git_is_clean && git push` | (returns 0/1) |
| `git_has_staged` | `git_has_staged` | `git_has_staged` | (returns 0/1) |
| `git_has_unstaged` | `git_has_unstaged` | `git_has_unstaged` | (returns 0/1) |
| `git_has_untracked` | `git_has_untracked` | `git_has_untracked` | (returns 0/1) |
| `git_files_changed` | `git_files_changed` | `git_files_changed` | List of files |
| `git_commit_hash` | `git_commit_hash` | `git_commit_hash` | `abc1234` |
| `git_commit_hash_full` | `git_commit_hash_full` | `git_commit_hash_full` | Full 40-char hash |
| `git_commit_message` | `git_commit_message` | `git_commit_message` | Latest message |
| `git_commit_author` | `git_commit_author` | `git_commit_author` | `John Doe` |
| `git_commit_count` | `git_commit_count` | `git_commit_count` | `42` |
| `git_commits_ahead` | `git_commits_ahead` | `git_commits_ahead` | `3` |
| `git_commits_behind` | `git_commits_behind` | `git_commits_behind` | `0` |
| `git_tag_latest` | `git_tag_latest` | `git_tag_latest` | `v1.2.3` |
| `git_tags` | `git_tags` | `git_tags` | List of tags |
| `git_tag_exists` | `git_tag_exists "tag"` | `git_tag_exists "v1.0.0"` | (returns 0/1) |
| `git_describe` | `git_describe` | `git_describe` | `v1.2.3-4-gabc1234` |
| `git_remote_url` | `git_remote_url` | `git_remote_url` | `git@github.com:...` |
| `git_has_remote` | `git_has_remote` | `git_has_remote` | (returns 0/1) |
| `git_is_pushed` | `git_is_pushed` | `git_is_pushed` | (returns 0/1) |
| `git_user_name` | `git_user_name` | `git_user_name` | Configured name |
| `git_user_email` | `git_user_email` | `git_user_email` | Configured email |
| `git_summary` | `git_summary` | `git_summary` | `main @ abc1234 [clean]` |
| `git_log_oneline` | `git_log_oneline [n]` | `git_log_oneline 5` | Last 5 commits |
| `git_changed_since` | `git_changed_since "ref"` | `git_changed_since "HEAD~5"` | Changed files |

---

## Crypto Functions (crypto.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `base64_encode` | `base64_encode "string"` | `base64_encode "hello"` | `aGVsbG8=` |
| `base64_decode` | `base64_decode "encoded"` | `base64_decode "aGVsbG8="` | `hello` |
| `base64_encode_file` | `base64_encode_file "file"` | `base64_encode_file "image.png"` | Base64 string |
| `hex_encode` | `hex_encode "string"` | `hex_encode "hi"` | `6869` |
| `hex_decode` | `hex_decode "hex"` | `hex_decode "6869"` | `hi` |
| `md5` | `md5 "string"` | `md5 "hello"` | `5d41402abc4b2a76...` |
| `md5_file` | `md5_file "file"` | `md5_file "data.txt"` | MD5 hash |
| `sha1` | `sha1 "string"` | `sha1 "hello"` | SHA-1 hash |
| `sha256` | `sha256 "string"` | `sha256 "hello"` | `2cf24dba5fb0a30e...` |
| `sha256_file` | `sha256_file "file"` | `sha256_file "data.txt"` | SHA-256 hash |
| `sha512` | `sha512 "string"` | `sha512 "hello"` | SHA-512 hash |
| `hmac_sha256` | `hmac_sha256 "key" "msg"` | `hmac_sha256 "secret" "data"` | HMAC signature |
| `random_bytes` | `random_bytes count` | `random_bytes 16` | Hex bytes |
| `random_hex` | `random_hex length` | `random_hex 32` | Random hex string |
| `random_base64` | `random_base64 length` | `random_base64 24` | Random base64 |
| `random_token` | `random_token length` | `random_token 32` | URL-safe token |
| `checksum` | `checksum "file"` | `checksum "data.txt"` | SHA-256 hash |
| `checksum_verify` | `checksum_verify "file" "hash"` | `checksum_verify "f.txt" "$hash"` | (returns 0/1) |
| `password_hash` | `password_hash "password"` | `password_hash "secret123"` | Hashed password |
| `password_verify` | `password_verify "pw" "hash"` | `password_verify "secret" "$h"` | (returns 0/1) |
| `generate_password` | `generate_password [len]` | `generate_password 16` | Random password |
| `rot13` | `rot13 "string"` | `rot13 "hello"` | `uryyb` |

---

## Process Functions (proc.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `proc_exists` | `proc_exists pid` | `proc_exists $$` | (returns 0/1) |
| `proc_name` | `proc_name pid` | `proc_name $$` | `bash` |
| `proc_cmd` | `proc_cmd pid` | `proc_cmd $$` | Full command line |
| `proc_parent` | `proc_parent pid` | `proc_parent $$` | Parent PID |
| `proc_children` | `proc_children pid` | `proc_children $$` | Child PIDs |
| `proc_tree` | `proc_tree pid` | `proc_tree $$` | Process tree |
| `proc_user` | `proc_user pid` | `proc_user $$` | `gordon` |
| `proc_memory` | `proc_memory pid` | `proc_memory $$` | Memory in KB |
| `proc_cpu` | `proc_cpu pid` | `proc_cpu $$` | CPU percentage |
| `proc_threads` | `proc_threads pid` | `proc_threads $$` | Thread count |
| `proc_find_by_name` | `proc_find_by_name "name"` | `proc_find_by_name "node"` | PIDs |
| `proc_find_by_port` | `proc_find_by_port port` | `proc_find_by_port 8080` | PID |
| `proc_find_by_user` | `proc_find_by_user "user"` | `proc_find_by_user "root"` | PIDs |
| `pidfile_create` | `pidfile_create "file"` | `pidfile_create "/tmp/app.pid"` | Creates PID file |
| `pidfile_read` | `pidfile_read "file"` | `pidfile_read "/tmp/app.pid"` | PID value |
| `pidfile_check` | `pidfile_check "file"` | `pidfile_check "/tmp/app.pid"` | (returns 0/1) |
| `pidfile_remove` | `pidfile_remove "file"` | `pidfile_remove "/tmp/app.pid"` | Removes file |
| `lockfile_acquire` | `lockfile_acquire "file" [timeout]` | `lockfile_acquire "/tmp/app.lock"` | (returns 0/1) |
| `lockfile_release` | `lockfile_release "file"` | `lockfile_release "/tmp/app.lock"` | Releases lock |
| `with_lock` | `with_lock "file" "command"` | `with_lock "/tmp/l" "do_work"` | Runs with lock |
| `proc_signal` | `proc_signal pid "signal"` | `proc_signal $pid "TERM"` | Sends signal |
| `proc_kill` | `proc_kill pid` | `proc_kill $pid` | SIGTERM |
| `proc_kill_force` | `proc_kill_force pid` | `proc_kill_force $pid` | SIGKILL |
| `proc_kill_tree` | `proc_kill_tree pid` | `proc_kill_tree $pid` | Kills tree |
| `proc_wait` | `proc_wait pid` | `proc_wait $pid` | Waits for exit |
| `proc_wait_timeout` | `proc_wait_timeout pid secs` | `proc_wait_timeout $pid 30` | Waits with timeout |
| `proc_count` | `proc_count` | `proc_count` | Total processes |
| `proc_load` | `proc_load` | `proc_load` | Load average |
| `proc_uptime` | `proc_uptime` | `proc_uptime` | Uptime in seconds |
| `proc_uptime_human` | `proc_uptime_human` | `proc_uptime_human` | `5 days, 3 hours` |

---

## Path Functions (path.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `path_normalize` | `path_normalize "path"` | `path_normalize "/foo//bar/../baz"` | `/foo/baz` |
| `path_absolute` | `path_absolute "path"` | `path_absolute "relative/path"` | `/cwd/relative/path` |
| `path_relative` | `path_relative "target" "base"` | `path_relative "/a/b/c" "/a"` | `b/c` |
| `path_dir` | `path_dir "path"` | `path_dir "/foo/bar/baz.txt"` | `/foo/bar` |
| `path_base` | `path_base "path"` | `path_base "/foo/bar/baz.txt"` | `baz.txt` |
| `path_ext` | `path_ext "path"` | `path_ext "/foo/bar.tar.gz"` | `gz` |
| `path_ext_full` | `path_ext_full "path"` | `path_ext_full "/foo/bar.tar.gz"` | `tar.gz` |
| `path_stem` | `path_stem "path"` | `path_stem "/foo/bar.tar.gz"` | `bar.tar` |
| `path_stem_full` | `path_stem_full "path"` | `path_stem_full "/foo/bar.tar.gz"` | `bar` |
| `path_join` | `path_join p1 p2 ...` | `path_join "/foo" "bar" "baz"` | `/foo/bar/baz` |
| `path_replace_ext` | `path_replace_ext "path" "ext"` | `path_replace_ext "/foo/bar.txt" "md"` | `/foo/bar.md` |
| `path_add_suffix` | `path_add_suffix "path" "suffix"` | `path_add_suffix "/foo/bar.txt" "_bak"` | `/foo/bar_bak.txt` |
| `path_to_unix` | `path_to_unix "path"` | `path_to_unix "C:\Users\foo"` | `/c/Users/foo` |
| `path_to_windows` | `path_to_windows "path"` | `path_to_windows "/c/Users/foo"` | `C:\Users\foo` |
| `path_style` | `path_style "path"` | `path_style "C:\foo"` | `windows` |
| `path_quote` | `path_quote "path"` | `path_quote "/path with spaces"` | `'/path with spaces'` |
| `path_is_safe` | `path_is_safe "base" "path"` | `path_is_safe "/base" "/base/sub"` | (returns 0/1) |
| `path_ensure_dir` | `path_ensure_dir "path"` | `path_ensure_dir "/foo/bar/file.txt"` | (creates /foo/bar/) |
| `path_sanitize` | `path_sanitize "name"` | `path_sanitize "file: <bad>.txt"` | `file_bad.txt` |
| `path_expand_tilde` | `path_expand_tilde "path"` | `path_expand_tilde "~/Documents"` | `/home/user/Documents` |
| `path_common_prefix` | `path_common_prefix p1 p2 ...` | `path_common_prefix "/a/b/c" "/a/b/d"` | `/a/b` |
| `path_is_absolute` | `path_is_absolute "path"` | `path_is_absolute "/foo"` | (returns 0/1) |
| `path_is_relative` | `path_is_relative "path"` | `path_is_relative "foo"` | (returns 0/1) |
| `path_has_parent_ref` | `path_has_parent_ref "path"` | `path_has_parent_ref "../foo"` | (returns 0/1) |
| `path_is_hidden` | `path_is_hidden "path"` | `path_is_hidden ".bashrc"` | (returns 0/1) |
| `path_equals` | `path_equals "p1" "p2"` | `path_equals "/a/../b" "/b"` | (returns 0/1) |
| `path_depth` | `path_depth "path"` | `path_depth "/foo/bar/baz"` | `3` |
| `path_split` | `path_split "path" arr` | `path_split "/a/b" arr` | Sets arr=("a" "b") |
| `path_unique` | `path_unique "path"` | `path_unique "/foo/bar.txt"` | `/foo/bar (1).txt` |
| `path_resolve` | `path_resolve "path"` | `path_resolve "/link"` | (resolved symlink) |

---

## Quick Patterns (NEW)

### DateTime Operations
```bash
# Get current time
echo "Now: $(now_iso)"
echo "Epoch: $(now)"

# Time arithmetic
tomorrow=$(date_add $(now) "1d")
last_week=$(date_subtract $(now) "1w")

# Human-readable diff
echo "$(format_relative $last_week)"  # "1 week ago"
```

### HTTP Requests
```bash
# Simple GET
response=$(http_get "http://api.example.com/data")

# POST JSON
result=$(http_json_post "http://api.example.com" '{"name":"test"}')

# Check status
if http_is_success; then
    echo "Request succeeded"
fi
```

### CSV Processing
```bash
# Read and iterate
csv_read "users.csv"
for i in $(seq 0 $((${#CSV_ROWS[@]}-1))); do
    name=$(csv_get $i "name")
    email=$(csv_get $i "email")
    echo "$name: $email"
done

# Create CSV
csv_row "John" "john@example.com" >> users.csv
```

### Git Workflow
```bash
if git_is_dirty; then
    echo "Uncommitted changes in $(git_branch)"
    echo "Files: $(git_files_changed)"
fi
echo "$(git_summary)"  # main @ abc1234 [clean]
```

### Crypto Operations
```bash
# Hash data
hash=$(sha256 "sensitive data")

# Generate tokens
token=$(random_token 32)
password=$(generate_password 16)

# Verify checksums
if checksum_verify "download.tar.gz" "$expected_hash"; then
    echo "File verified"
fi
```

### Process Management
```bash
# Check if running
if proc_exists $pid; then
    echo "Memory: $(proc_memory $pid) KB"
fi

# Find by port
pid=$(proc_find_by_port 8080)

# Run with lock
with_lock "/tmp/myapp.lock" "run_exclusive_task"
```

### Path Manipulation
```bash
# Normalize and resolve paths
clean=$(path_normalize "/foo//bar/../baz")  # /foo/baz
abs=$(path_absolute "relative/path")        # /cwd/relative/path
rel=$(path_relative "/a/b/c/d" "/a/b")      # c/d

# Extract components
dir=$(path_dir "/foo/bar/file.txt")         # /foo/bar
base=$(path_base "/foo/bar/file.txt")       # file.txt
ext=$(path_ext "/foo/bar.tar.gz")           # gz
stem=$(path_stem "/foo/bar.tar.gz")         # bar.tar

# Build paths safely
full=$(path_join "/base" "sub" "file.txt")  # /base/sub/file.txt
new=$(path_replace_ext "doc.txt" "md")      # doc.md

# Safety checks
if path_is_safe "/allowed" "$user_path"; then
    process_file "$user_path"
fi

# Cross-platform
unix=$(path_to_unix "C:\Users\foo")         # /c/Users/foo
win=$(path_to_windows "/c/Users/foo")       # C:\Users\foo

# Handle spaces safely
safe=$(path_quote "/path with spaces/file") # properly escaped
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

## Quick Patterns (Validation)

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
    # Safe to use path
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

---

## Docker Functions (docker.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_running` | `docker_running` | `docker_running && echo "OK"` | (returns 0/1) |
| `docker_version` | `docker_version` | `docker_version` | `24.0.7` |
| `docker_container_exists` | `docker_container_exists "name"` | `docker_container_exists "nginx"` | (returns 0/1) |
| `docker_container_running` | `docker_container_running "name"` | `docker_container_running "nginx"` | (returns 0/1) |
| `docker_container_status` | `docker_container_status "name"` | `docker_container_status "nginx"` | `running` |
| `docker_container_id` | `docker_container_id "name"` | `docker_container_id "nginx"` | Full container ID |
| `docker_container_start` | `docker_container_start "name"` | `docker_container_start "nginx"` | (returns 0/1) |
| `docker_container_stop` | `docker_container_stop "name" [timeout]` | `docker_container_stop "nginx" 30` | (returns 0/1) |
| `docker_container_restart` | `docker_container_restart "name"` | `docker_container_restart "nginx"` | (returns 0/1) |
| `docker_container_remove` | `docker_container_remove "name" [force]` | `docker_container_remove "nginx" true` | (returns 0/1) |
| `docker_containers_running` | `docker_containers_running` | `docker_containers_running` | Container names |
| `docker_containers_all` | `docker_containers_all` | `docker_containers_all` | All container names |
| `docker_exec` | `docker_exec "name" "cmd"` | `docker_exec "nginx" "cat /etc/nginx/nginx.conf"` | Command output |
| `docker_logs` | `docker_logs "name" [lines]` | `docker_logs "nginx" 100` | Container logs |
| `docker_stats_json` | `docker_stats_json "name"` | `docker_stats_json "nginx"` | JSON stats |
| `docker_cpu` | `docker_cpu "name"` | `docker_cpu "nginx"` | `2.50%` |
| `docker_memory` | `docker_memory "name"` | `docker_memory "nginx"` | `150MiB / 16GiB` |
| `docker_container_ip` | `docker_container_ip "name"` | `docker_container_ip "nginx"` | `172.17.0.2` |
| `docker_container_ports` | `docker_container_ports "name"` | `docker_container_ports "nginx"` | Port mappings |
| `docker_container_env` | `docker_container_env "name"` | `docker_container_env "nginx"` | Environment vars |
| `docker_container_image` | `docker_container_image "name"` | `docker_container_image "nginx"` | `nginx:latest` |
| `docker_image_exists` | `docker_image_exists "image:tag"` | `docker_image_exists "nginx:latest"` | (returns 0/1) |
| `docker_image_pull` | `docker_image_pull "image:tag"` | `docker_image_pull "nginx:alpine"` | (returns 0/1) |
| `docker_image_remove` | `docker_image_remove "image:tag"` | `docker_image_remove "nginx:old"` | (returns 0/1) |
| `docker_images` | `docker_images` | `docker_images` | Image:tag list |
| `docker_port_used` | `docker_port_used "port"` | `docker_port_used 8080` | (returns 0/1) |
| `docker_port_container` | `docker_port_container "port"` | `docker_port_container 8080` | Container name |
| `compose_running` | `compose_running "service"` | `compose_running "web"` | (returns 0/1) |
| `compose_exec` | `compose_exec "service" "cmd"` | `compose_exec "web" "ls -la"` | Command output |
| `compose_up` | `compose_up [file] [detached]` | `compose_up` | (returns 0/1) |
| `compose_down` | `compose_down [file] [rm_volumes]` | `compose_down` | (returns 0/1) |
| `compose_logs` | `compose_logs "service" [lines]` | `compose_logs "web" 50` | Service logs |
| `compose_services` | `compose_services [file]` | `compose_services` | Service names |
| `docker_volume_exists` | `docker_volume_exists "name"` | `docker_volume_exists "data"` | (returns 0/1) |
| `docker_volume_create` | `docker_volume_create "name"` | `docker_volume_create "data"` | (returns 0/1) |
| `docker_volumes` | `docker_volumes` | `docker_volumes` | Volume names |
| `docker_network_exists` | `docker_network_exists "name"` | `docker_network_exists "app-net"` | (returns 0/1) |
| `docker_network_create` | `docker_network_create "name"` | `docker_network_create "app-net"` | (returns 0/1) |
| `docker_networks` | `docker_networks` | `docker_networks` | Network names |
| `docker_prune_containers` | `docker_prune_containers` | `docker_prune_containers` | Removes stopped |
| `docker_prune_images` | `docker_prune_images` | `docker_prune_images` | Removes dangling |
| `docker_prune_all` | `docker_prune_all [volumes]` | `docker_prune_all true` | Full cleanup |

---

## Quick Patterns (Docker)

### Check Docker Status
```bash
if docker_running; then
    echo "Docker is running: $(docker_version)"
else
    echo "Docker daemon not available"
fi
```

### Container Management
```bash
# Check and start container
if ! docker_container_running "myapp"; then
    docker_container_start "myapp"
fi

# Get stats
echo "CPU: $(docker_cpu "myapp")"
echo "Memory: $(docker_memory "myapp")"
```

### Docker Compose Workflow
```bash
# Start services
compose_up

# Check service
if compose_running "web"; then
    compose_exec "web" "npm run migrate"
fi

# Get logs
compose_logs "web" 100
```

### Port Conflict Check
```bash
if docker_port_used 8080; then
    container=$(docker_port_container 8080)
    echo "Port 8080 used by: $container"
fi
```

---

## Environment Functions (env.sh)

### Shell Detection

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `env_detect_shell` | `env_detect_shell` | `env_detect_shell` | `bash` |
| `env_config_file` | `env_config_file [shell]` | `env_config_file "bash"` | `~/.bashrc` |

### Variable Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `env_set` | `env_set "VAR" "value"` | `env_set "MY_VAR" "hello"` | (exports MY_VAR) |
| `env_get` | `env_get "VAR" [default]` | `env_get "MY_VAR" "fallback"` | `hello` or `fallback` |
| `env_unset` | `env_unset "VAR"` | `env_unset "MY_VAR"` | (unsets variable) |
| `env_persist` | `env_persist "VAR" "val" [shell]` | `env_persist "MY_VAR" "hello"` | (adds to ~/.bashrc) |
| `env_remove_persist` | `env_remove_persist "VAR" [shell]` | `env_remove_persist "MY_VAR"` | (removes from config) |

### PATH Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `env_path_prepend` | `env_path_prepend "/path"` | `env_path_prepend "/opt/bin"` | (adds to PATH start) |
| `env_path_append` | `env_path_append "/path"` | `env_path_append "/opt/bin"` | (adds to PATH end) |
| `env_path_remove` | `env_path_remove "/path"` | `env_path_remove "/old/bin"` | (removes from PATH) |
| `env_path_list` | `env_path_list` | `env_path_list` | (one path per line) |
| `env_path_has` | `env_path_has "/path"` | `env_path_has "/usr/bin"` | (returns 0/1) |
| `env_path_clean` | `env_path_clean` | `env_path_clean` | (removes duplicates) |
| `env_path_persist_prepend` | `env_path_persist_prepend "/path"` | `env_path_persist_prepend "/opt/bin"` | (persists to config) |
| `env_path_persist_append` | `env_path_persist_append "/path"` | `env_path_persist_append "/opt/bin"` | (persists to config) |

### Dotenv Support

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `env_load_dotenv` | `env_load_dotenv [file]` | `env_load_dotenv ".env"` | (loads .env file) |
| `env_save_dotenv` | `env_save_dotenv "file" VAR1 VAR2` | `env_save_dotenv "app.env" DB_HOST DB_PORT` | (saves to file) |
| `env_export_from` | `env_export_from "file"` | `env_export_from "config.env"` | (exports from file) |

### Validation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `env_is_set` | `env_is_set "VAR"` | `env_is_set "HOME"` | (returns 0/1) |
| `env_is_nonempty` | `env_is_nonempty "VAR"` | `env_is_nonempty "PATH"` | (returns 0/1) |
| `env_require` | `env_require "VAR" [msg]` | `env_require "API_KEY" "API key required"` | (exits if missing) |
| `env_require_all` | `env_require_all VAR1 VAR2` | `env_require_all DB_HOST DB_PORT` | (exits if any missing) |

### Utilities

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `env_list` | `env_list [pattern]` | `env_list "MY_APP"` | (matching vars) |
| `env_with` | `env_with "VAR=val" cmd args` | `env_with "DEBUG=1" ./script.sh` | (runs with temp env) |
| `env_copy` | `env_copy "SRC" "DEST"` | `env_copy "PATH" "BACKUP_PATH"` | (copies variable) |
| `env_swap` | `env_swap "VAR1" "VAR2"` | `env_swap "A" "B"` | (swaps values) |
| `env_get_int` | `env_get_int "VAR" [default]` | `env_get_int "PORT" 8080` | `8080` |
| `env_get_bool` | `env_get_bool "VAR" [default]` | `env_get_bool "DEBUG"` | (returns 0/1) |
| `env_get_array` | `env_get_array "VAR" arr` | `env_get_array "PATH" paths` | (splits on :) |
| `env_set_array` | `env_set_array "VAR" "${arr[@]}"` | `env_set_array "DIRS" "${dirs[@]}"` | (joins with :) |
| `env_debug` | `env_debug "VAR"` | `env_debug "HOME"` | `HOME=/home/user` |
| `env_diff` | `env_diff "file.env"` | `env_diff ".env"` | (shows differences) |
| `env_expand` | `env_expand "string"` | `env_expand '$HOME/bin'` | `/home/user/bin` |
| `env_summary` | `env_summary` | `env_summary` | (shell info summary) |
| `env_backup` | `env_backup "file"` | `env_backup "env.bak"` | (saves all env vars) |
| `env_restore` | `env_restore "file"` | `env_restore "env.bak"` | (loads env backup) |

---

## Quick Patterns (Environment)

### Environment Variable Setup
```bash
# Require critical variables
env_require "API_KEY" "API_KEY is required"
env_require_all DB_HOST DB_PORT DB_USER

# Get with defaults
port=$(env_get "PORT" "8080")
debug=$(env_get_bool "DEBUG" && echo "on" || echo "off")
```

### PATH Management
```bash
# Add to PATH (idempotent)
env_path_prepend "/opt/myapp/bin"
env_path_append "$HOME/.local/bin"

# Clean up PATH
env_path_clean  # Removes duplicates and non-existent dirs

# Check before using
if env_path_has "/usr/local/bin"; then
    echo "Local bin available"
fi
```

### Dotenv Workflow
```bash
# Load environment from file
if [[ -f ".env" ]]; then
    env_load_dotenv ".env"
fi

# Save current config
env_save_dotenv "backup.env" DB_HOST DB_PORT API_KEY

# Run with modified environment
env_with "NODE_ENV=production" npm start
```

### Shell Detection
```bash
# Detect shell and config file
shell=$(env_detect_shell)
config=$(env_config_file)
echo "Using $shell, config at $config"

# Persist across sessions
env_persist "MY_VAR" "my_value"
env_path_persist_prepend "/opt/bin"
```

---

## Defensive Guard Functions (guard.sh)

**Purpose**: Prevent common AI coding assistant failures. Call `guard_init` at script start for maximum protection.

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `guard_init` | `guard_init` | `guard_init` | Enable strict mode + error handlers |
| `guard_on_exit` | `guard_on_exit "command"` | `guard_on_exit "rm -f /tmp/lock"` | Register cleanup handler |
| `guard_path_exists` | `guard_path_exists path [type] [ctx]` | `guard_path_exists "/etc/config.json" file` | Verify path exists |
| `guard_path_safe` | `guard_path_safe base user_path` | `guard_path_safe "/var/www" "../etc/passwd"` | Prevent path traversal |
| `guard_path_chars` | `guard_path_chars path [strict]` | `guard_path_chars "$file" true` | Check for dangerous chars |
| `guard_symlink` | `guard_symlink path [policy]` | `guard_symlink "/link" reject` | Handle symlinks safely |
| `guard_destructive_path` | `guard_destructive_path path` | `guard_destructive_path "$DIR"` | Safety before rm/mv |
| `guard_var_set` | `guard_var_set name [nonempty] [default]` | `guard_var_set "API_KEY" true` | Verify variable is set |
| `guard_var_safe` | `guard_var_safe value` | `guard_var_safe "$input"` | Check for injection |
| `guard_array_bounds` | `guard_array_bounds arr index` | `guard_array_bounds myarr 5` | Bounds checking |
| `guard_command` | `guard_command cmd [hint]` | `guard_command jq "apt install jq"` | Verify command exists |
| `guard_commands` | `guard_commands cmd1 cmd2...` | `guard_commands git curl jq` | Check multiple commands |
| `guard_os` | `guard_os os` | `guard_os linux` | OS compatibility check |
| `guard_lock` | `guard_lock lockfile [timeout]` | `guard_lock "/tmp/myapp.lock" 30` | Acquire exclusive lock |
| `guard_unlock` | `guard_unlock lockfile` | `guard_unlock "/tmp/myapp.lock"` | Release lock |
| `guard_with_lock` | `guard_with_lock lockfile cmd` | `guard_with_lock "/tmp/x" process` | Run with lock held |
| `guard_disk_space` | `guard_disk_space path min_bytes` | `guard_disk_space "/var" 1073741824` | Check available space |
| `guard_memory` | `guard_memory min_bytes` | `guard_memory 536870912` | Check available RAM |
| `guard_integer` | `guard_integer val [min] [max]` | `guard_integer "$port" 1 65535` | Validate integer range |
| `guard_filename` | `guard_filename name` | `guard_filename "$input"` | Validate filename |
| `guard_file_op` | `guard_file_op op path` | `guard_file_op write "/var/log/app.log"` | Combined file safety |

### Safe Script Template
```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Enable all protections (strict mode + traps)
guard_init

# Register cleanup (runs automatically on exit)
TMP=$(mktemp)
guard_on_exit "rm -f '$TMP'"

# Verify dependencies
guard_commands git curl jq || exit 1

# Validate input safely
guard_var_set "TARGET_DIR" true || exit 1
guard_path_safe "/allowed/base" "$TARGET_DIR" || exit 1

# Check before destructive operations
guard_destructive_path "$TARGET_DIR" || exit 1

# Run with lock to prevent concurrent execution
guard_with_lock "/tmp/myapp.lock" do_work
```

### Path Traversal Prevention
```bash
# User provides path - could be malicious
user_input="../../etc/passwd"

# Validate path is within allowed base
if guard_path_safe "/var/www/uploads" "$user_input"; then
    cat "/var/www/uploads/$user_input"
else
    echo "Access denied"
fi
```

### Variable Safety
```bash
# Ensure required variables are set
guard_var_set "API_KEY" true || exit 1
guard_var_set "TIMEOUT" true 30  # Uses default of 30 if not set

# Validate user input for shell safety
user_input="; rm -rf /"
if guard_var_safe "$user_input"; then
    process "$user_input"
else
    echo "Invalid input rejected"
fi
```

---

## Process Substitution Functions (procsub.sh)

**Purpose**: Solve the "variable lost in subshell" problem - one of the most common bash gotchas.

### Core Functions

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `read_lines_from` | `read_lines_from "cmd" arr` | `read_lines_from "ls -1" files` | Read command output into array |
| `for_each_line` | `for_each_line "cmd" callback` | `for_each_line "cat f" 'echo "$line"'` | Process lines, keep variables |
| `diff_commands` | `diff_commands "cmd1" "cmd2" [opts]` | `diff_commands "sort a" "sort b" -u` | Diff two command outputs |
| `capture_output` | `capture_output var "cmd"` | `capture_output result "date"` | Capture output into variable |
| `process_file` | `process_file "file" callback` | `process_file "f.txt" 'echo "$line"'` | Process file, keep state |
| `tee_to_var` | `tee_to_var var "cmd"` | `tee_to_var out "ls -la"` | Tee to stdout AND variable |

### Advanced Functions

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `map_lines_from` | `map_lines_from "cmd" func arr` | `map_lines_from "seq 3" to_upper res` | Map function over lines |
| `filter_lines_from` | `filter_lines_from "cmd" pred arr` | `filter_lines_from "seq 10" is_even evens` | Filter lines with predicate |
| `reduce_lines_from` | `reduce_lines_from "cmd" fn init var` | `reduce_lines_from "seq 5" sum 0 total` | Reduce lines to single value |
| `commands_equal` | `commands_equal "cmd1" "cmd2"` | `commands_equal "sort a" "sort b"` | Check if outputs match |
| `read_n_lines_from` | `read_n_lines_from "cmd" n arr` | `read_n_lines_from "cat log" 10 head` | Read first N lines |
| `batch_lines_from` | `batch_lines_from "cmd" size cb` | `batch_lines_from "seq 10" 3 process` | Process in batches |
| `interleave_commands` | `interleave_commands "c1" "c2" arr` | `interleave_commands "seq 3" "seq 3" m` | Interleave two outputs |

### Utility Functions

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `count_lines_from` | `count_lines_from "cmd" var` | `count_lines_from "find . -name '*.sh'" n` | Count lines without subshell |
| `read_pairs_from` | `read_pairs_from "cmd" map [delim]` | `read_pairs_from "cat conf" cfg "="` | Read key=value pairs |

### The Subshell Problem

```bash
# BAD: Variable lost in subshell
count=0
cat file.txt | while read -r line; do
    ((count++))
done
echo "$count"  # Still 0! Pipeline runs in subshell

# GOOD: Using process substitution (this library)
count=0
for_each_line "cat file.txt" '((count++))'
echo "$count"  # Correct value!
```

### Common Patterns

```bash
# Collect lines into array
read_lines_from "find . -name '*.sh'" scripts
echo "Found ${#scripts[@]} scripts"

# Process with state tracking
total=0
process_file "numbers.txt" 'total=$((total + line))'
echo "Sum: $total"

# Filter and transform
is_positive() { [[ $1 -gt 0 ]]; }
filter_lines_from "seq -5 5" is_positive positives
echo "${positives[@]}"  # 1 2 3 4 5

# Batch processing
batch_lines_from "seq 1 100" 10 'echo "Batch $batch_num: ${#batch[@]} items"'

# Compare sorted outputs
if commands_equal "sort file1.txt" "sort file2.txt"; then
    echo "Files have same content"
fi
```

---

## Functional Programming (functional.sh)

### Predicates

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `is_even` | `is_even number` | `is_even 4 && echo "yes"` | (returns 0/1) |
| `is_odd` | `is_odd number` | `is_odd 3 && echo "yes"` | (returns 0/1) |
| `is_positive` | `is_positive number` | `is_positive 5 && echo "yes"` | (returns 0/1) |
| `is_negative` | `is_negative number` | `is_negative -3 && echo "yes"` | (returns 0/1) |
| `is_zero` | `is_zero number` | `is_zero 0 && echo "yes"` | (returns 0/1) |
| `is_empty` | `is_empty "string"` | `is_empty "" && echo "yes"` | (returns 0/1) |
| `is_not_empty` | `is_not_empty "string"` | `is_not_empty "hello"` | (returns 0/1) |
| `is_numeric` | `is_numeric "value"` | `is_numeric "42"` | (returns 0/1) |
| `is_alnum` | `is_alnum "value"` | `is_alnum "abc123"` | (returns 0/1) |

### Transformers

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `double` | `double number` | `double 5` | `10` |
| `square` | `square number` | `square 5` | `25` |
| `increment` | `increment number` | `increment 5` | `6` |
| `decrement` | `decrement number` | `decrement 5` | `4` |
| `negate` | `negate number` | `negate 5` | `-5` |
| `abs` | `abs number` | `abs -5` | `5` |

### Binary Functions (for reduce)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `sum` | `sum a b` | `sum 3 4` | `7` |
| `product` | `product a b` | `product 3 4` | `12` |
| `max` | `max a b` | `max 3 7` | `7` |
| `min` | `min a b` | `min 3 7` | `3` |
| `concat` | `concat s1 s2` | `concat "hello" "world"` | `helloworld` |

### Map

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_map` | `fp_map "func" elem1 elem2...` | `fp_map double 1 2 3 4 5` | `2 4 6 8 10` |
| `fp_map` | `echo -e "1\n2" \| fp_map "func"` | `echo -e "1\n2" \| fp_map double` | `2 4` |
| `fp_map_v` | `fp_map_v result_arr "func" elem...` | `fp_map_v res double 1 2 3` | (sets res array) |
| `fp_map_v_nr` | `fp_map_v_nr result_arr "func_nr" elem...` | `fp_map_v_nr res double_nr 1 2 3` | (nameref func) |

### Filter

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_filter` | `fp_filter "pred" elem1 elem2...` | `fp_filter is_even 1 2 3 4 5` | `2 4` |
| `fp_filter` | `echo -e "1\n2" \| fp_filter "pred"` | `echo -e "1\n2\n3" \| fp_filter is_odd` | `1 3` |
| `fp_filter_v` | `fp_filter_v result_arr "pred" elem...` | `fp_filter_v evens is_even 1 2 3 4 5` | (sets evens array) |

### Reduce

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_reduce` | `fp_reduce "func" init elem1 elem2...` | `fp_reduce sum 0 1 2 3 4 5` | `15` |
| `fp_reduce_v` | `fp_reduce_v result "func" init elem...` | `fp_reduce_v total sum 0 1 2 3 4 5` | (sets total) |
| `fp_reduce_v_nr` | `fp_reduce_v_nr result "func_nr" init...` | `fp_reduce_v_nr total sum_nr 0 1 2 3` | (nameref func) |

### Find

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_find` | `fp_find "pred" elem1 elem2...` | `fp_find is_even 1 3 5 6 7` | `6` |
| `fp_find_v` | `fp_find_v result "pred" elem...` | `fp_find_v found is_even 1 3 5 6` | (sets found) |
| `fp_find_index` | `fp_find_index "pred" elem1 elem2...` | `fp_find_index is_even 1 3 5 6 7` | `3` |

### Quantifiers

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_any` | `fp_any "pred" elem1 elem2...` | `fp_any is_even 1 3 5 6 7` | (returns 0) |
| `fp_all` | `fp_all "pred" elem1 elem2...` | `fp_all is_positive 1 2 3 4 5` | (returns 0) |
| `fp_none` | `fp_none "pred" elem1 elem2...` | `fp_none is_negative 1 2 3 4 5` | (returns 0) |

### Composition

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_compose` | `fp_compose "func1" "func2"...` | `fp_compose increment double` | (function def) |
| `fp_pipe` | `fp_pipe "func1" "func2"...` | `fp_pipe double increment` | (function def) |
| `fp_apply` | `fp_apply "$(fp_pipe...)" value` | `fp_apply "$(fp_pipe double increment)" 5` | `11` |

### Partition

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_partition_v` | `fp_partition_v matches rejects "pred" elem...` | `fp_partition_v evens odds is_even 1 2 3 4` | (sets both arrays) |

### Take / Drop

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_take` | `fp_take n elem1 elem2...` | `fp_take 3 1 2 3 4 5` | `1 2 3` |
| `fp_take_while` | `fp_take_while "pred" elem1 elem2...` | `fp_take_while is_positive 1 2 -1 3` | `1 2` |
| `fp_drop` | `fp_drop n elem1 elem2...` | `fp_drop 2 1 2 3 4 5` | `3 4 5` |
| `fp_drop_while` | `fp_drop_while "pred" elem1 elem2...` | `fp_drop_while is_positive 1 2 -1 3` | `-1 3` |

### Zip

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_zip` | `fp_zip arr1 arr2` | `fp_zip nums letters` | (tab-separated pairs) |
| `fp_zip_with` | `fp_zip_with "func" arr1 arr2` | `fp_zip_with sum nums1 nums2` | (combined values) |

### Utilities

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fp_count` | `fp_count "pred" elem1 elem2...` | `fp_count is_even 1 2 3 4 5 6` | `3` |
| `fp_group_by` | `fp_group_by "func" elem1 elem2...` | `fp_group_by modulo2 1 2 3 4` | (grouped output) |
| `identity` | `identity value` | `identity "hello"` | `hello` |
| `fp_const` | `fp_const value` | `fp_const 42` | (function that returns 42) |

### Nameref Variants (Zero Subshells)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `double_nr` | `double_nr value result_var` | `double_nr 5 result` | (sets result=10) |
| `square_nr` | `square_nr value result_var` | `square_nr 5 result` | (sets result=25) |
| `increment_nr` | `increment_nr value result_var` | `increment_nr 5 result` | (sets result=6) |
| `decrement_nr` | `decrement_nr value result_var` | `decrement_nr 5 result` | (sets result=4) |
| `sum_nr` | `sum_nr a b result_var` | `sum_nr 3 4 result` | (sets result=7) |
| `product_nr` | `product_nr a b result_var` | `product_nr 3 4 result` | (sets result=12) |
| `max_nr` | `max_nr a b result_var` | `max_nr 3 7 result` | (sets result=7) |
| `min_nr` | `min_nr a b result_var` | `min_nr 3 7 result` | (sets result=3) |

---

## Quick Patterns (Functional Programming)

### Basic Map/Filter/Reduce

```bash
# Transform data
fp_map double 1 2 3 4 5              # 2 4 6 8 10

# Filter data
fp_filter is_even 1 2 3 4 5 6        # 2 4 6

# Reduce to single value
fp_reduce sum 0 1 2 3 4 5            # 15
fp_reduce product 1 2 3 4            # 24
fp_reduce max 0 5 2 8 3 1            # 8
```

### Pipeline Style

```bash
# Chain operations with pipes
seq 1 10 \
    | fp_filter is_even \
    | fp_map double \
    | fp_reduce sum 0
# Result: 60 (2+4+6+8+10 doubled = 4+8+12+16+20 = 60)
```

### High-Performance Variants (No Subshells)

```bash
# Use nameref variants in loops for 20-80% speedup
fp_map_v results double 1 2 3 4 5
echo "${results[@]}"  # 2 4 6 8 10

fp_filter_v evens is_even 1 2 3 4 5 6
echo "${evens[@]}"    # 2 4 6

fp_reduce_v total sum 0 1 2 3 4 5
echo "$total"         # 15

# Fully subshell-free with nameref functions
fp_reduce_v_nr total sum_nr 0 1 2 3 4 5
```

### Finding Elements

```bash
# Find first match
fp_find is_even 1 3 5 6 7 8          # 6

# Find index
fp_find_index is_even 1 3 5 6 7      # 3

# Check existence
fp_any is_negative 1 2 -3 4 && echo "has negative"
fp_all is_positive 1 2 3 4 5 && echo "all positive"
```

### Partitioning Data

```bash
# Split into matching/non-matching
fp_partition_v evens odds is_even 1 2 3 4 5 6 7 8
echo "Evens: ${evens[@]}"   # 2 4 6 8
echo "Odds: ${odds[@]}"     # 1 3 5 7
```

### Take and Drop

```bash
# Take first N
fp_take 3 a b c d e f                # a b c

# Take while predicate holds
fp_take_while is_positive 1 2 3 -1 4 5  # 1 2 3

# Drop first N
fp_drop 2 a b c d e f                # c d e f

# Drop while predicate holds
fp_drop_while is_positive 1 2 -1 3 4    # -1 3 4
```

### Function Composition

```bash
# Compose (right to left): increment(double(x))
composed=$(fp_compose increment double)
fp_apply "$composed" 5               # 11 (5*2=10, 10+1=11)

# Pipe (left to right): double(increment(x))
piped=$(fp_pipe increment double)
fp_apply "$piped" 5                  # 12 (5+1=6, 6*2=12)
```

### Custom Predicates

```bash
# Define custom predicates
is_adult() { (($1 >= 18)); }
is_valid_port() { (($1 >= 1 && $1 <= 65535)); }

# Use with fp functions
fp_filter is_adult 12 25 17 30 16 45   # 25 30 45
fp_all is_valid_port 80 443 8080       # returns 0 (true)
```

### Custom Transformers

```bash
# Define custom transformers
add_tax() { echo $(($1 * 110 / 100)); }
prefix_http() { echo "http://$1"; }

# Use with fp functions
fp_map add_tax 100 200 300             # 110 220 330
fp_map prefix_http "a.com" "b.com"     # http://a.com http://b.com
```

---

## Safe Execution Functions (safe.sh)

**Purpose**: Strict mode helpers and gotcha prevention for AI-generated scripts. Provides safe patterns for error handling, retries, timeouts, and output capture.

### Strict Mode Management

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `enable_strict_mode` | `enable_strict_mode` | `enable_strict_mode` | Enable -euo pipefail + inherit_errexit |
| `disable_strict_mode` | `disable_strict_mode` | `disable_strict_mode` | Restore previous shell options |
| `is_strict_mode` | `is_strict_mode` | `is_strict_mode && echo "strict"` | Check if strict mode enabled |

### Unsafe Execution

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `unsafe_run` | `unsafe_run "cmd"` | `unsafe_run "grep pattern file"` | Run command without triggering errexit |
| `safe_exit_code` | `safe_exit_code "cmd"` | `safe_exit_code "test -f x"` | Capture exit code in SAFE_EXIT_CODE |

### Safe Sourcing

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `safe_source` | `safe_source "file" [required]` | `safe_source "/etc/config.sh"` | Source with existence check |
| `safe_source_all` | `safe_source_all required f1 f2...` | `safe_source_all true ~/.bashrc ~/.bash_aliases` | Source multiple files |
| `source_if_exists` | `source_if_exists "file"` | `source_if_exists "$HOME/.local_config"` | Optional source (no error if missing) |

### Output Capture

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `capture_both` | `capture_both out err "cmd"` | `capture_both stdout stderr "make"` | Capture stdout and stderr separately |
| `capture_stdout` | `capture_stdout "cmd"` | `result=$(capture_stdout "date")` | Capture stdout only |
| `capture_stderr` | `capture_stderr "cmd"` | `errors=$(capture_stderr "make")` | Capture stderr only |
| `capture_all` | `capture_all "cmd"` | `log=$(capture_all "npm install")` | Capture combined stdout+stderr |

### Retry with Backoff

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `retry_backoff` | `retry_backoff n "cmd" [delay] [max]` | `retry_backoff 5 "curl -sf http://api.example.com"` | Exponential backoff retry |
| `retry_backoff_jitter` | `retry_backoff_jitter n "cmd" [d] [m]` | `retry_backoff_jitter 5 "curl http://api"` | Retry with random jitter |
| `retry_with_callback` | `retry_with_callback n "cmd" "cb"` | `retry_with_callback 3 "cmd" on_retry` | Retry with callback on failure |

### Timeout Execution

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `run_with_timeout` | `run_with_timeout secs "cmd"` | `run_with_timeout 30 "long_task"` | Pure bash timeout (124 on timeout) |
| `timeout_cmd` | `timeout_cmd secs "cmd"` | `timeout_cmd 10 "curl http://slow-api"` | GNU timeout with bash fallback |

### Script Linting

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `lint_script` | `lint_script "file" [severity]` | `lint_script "deploy.sh" warning` | Run shellcheck on script |
| `check_syntax` | `check_syntax "file"` | `check_syntax "script.sh"` | Quick bash -n syntax check |
| `lint_scripts` | `lint_scripts "dir" [pattern]` | `lint_scripts "./scripts" "*.sh"` | Lint all scripts in directory |

### Error Context

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `enable_error_context` | `enable_error_context` | `enable_error_context` | Enable stack trace on errors |
| `disable_error_context` | `disable_error_context` | `disable_error_context` | Disable error context trap |

### Gotcha Prevention

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `default` | `default "var" "fallback"` | `val=$(default "MY_VAR" "none")` | Safe variable with default |
| `require_var` | `require_var "var" [msg]` | `require_var "API_KEY" "API key required"` | Assert variable is set |
| `array_get` | `array_get arr idx [default]` | `val=$(array_get arr 10 "n/a")` | Safe array access with bounds |
| `safe_math` | `safe_math "expr" [default]` | `result=$(safe_math "$a + $b" 0)` | Safe arithmetic evaluation |

---

### Safe Script Template

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Enable strict mode with detailed error context
enable_strict_mode
enable_error_context

# Require critical variables
require_var "API_KEY" "API_KEY environment variable required"

# Safe sourcing of optional configs
source_if_exists "$HOME/.local_config"
safe_source "/etc/myapp/config.sh" true  # Required file

# Commands that might fail (without triggering errexit)
if unsafe_run "ping -c 1 google.com"; then
    echo "Network available"
fi

# Retry with exponential backoff
if retry_backoff 5 "curl -sf http://api.example.com/health"; then
    echo "API is healthy"
else
    echo "API unreachable after 5 attempts"
fi

# Run with timeout
if run_with_timeout 30 "long_running_task"; then
    echo "Task completed"
elif [[ $? -eq 124 ]]; then
    echo "Task timed out"
fi
```

### Retry Patterns

```bash
# Basic retry with exponential backoff (1s, 2s, 4s, 8s, 16s delays)
retry_backoff 5 "curl -sf http://flaky-api.com/endpoint"

# Retry with jitter (prevents thundering herd in distributed systems)
retry_backoff_jitter 5 "curl -sf http://api.com/endpoint" 1 60

# Retry with callback for logging/alerting
on_failure() {
    echo "Attempt $1/$2 failed (exit code: $3)" >&2
}
retry_with_callback 3 "database_connect" on_failure
```

### Output Capture Patterns

```bash
# Capture both streams separately
capture_both stdout stderr "make build"
if [[ -n "$stderr" ]]; then
    echo "Build warnings: $stderr"
fi
echo "Build output: $stdout"

# Capture only what you need
version=$(capture_stdout "python --version 2>&1")
errors=$(capture_stderr "npm install")
log=$(capture_all "docker build .")
```

### Timeout Patterns

```bash
# Run with timeout, check for timeout exit code
if ! run_with_timeout 60 "heavy_computation"; then
    if [[ $? -eq 124 ]]; then
        echo "Computation timed out after 60 seconds"
    else
        echo "Computation failed"
    fi
fi

# Use GNU timeout if available (more reliable for complex commands)
timeout_cmd 30 "wget -q http://large-file.example.com/data.zip"
```

### Gotcha Prevention

```bash
# Safe variable access (no unbound variable errors)
timeout=$(default "TIMEOUT" "30")
debug_mode=$(default "DEBUG" "false")

# Safe array access with bounds checking
arr=(a b c)
val=$(array_get arr 10 "not found")  # Returns "not found"
val=$(array_get arr 1 "")            # Returns "b"

# Safe math with empty/invalid value handling
result=$(safe_math "$a + $b" 0)      # Returns 0 if a or b empty/invalid
```

---

## Metaprogramming Functions (meta.sh)

**Purpose**: Indirect variable access, type introspection, dynamic function calls, and constants.

### Variable Access

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `var_get` | `var_get "name" [result_var]` | `var_get "HOME"` | `/home/user` |
| `var_set` | `var_set "name" "value"` | `var_set "count" "5"` | (sets variable) |
| `var_exists` | `var_exists "name"` | `var_exists "HOME"` | (returns 0/1) |
| `var_nonempty` | `var_nonempty "name"` | `var_nonempty "PATH"` | (returns 0/1) |
| `var_unset` | `var_unset "name"` | `var_unset "temp"` | (unsets variable) |

### Variable Enumeration

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `vars_with_prefix` | `vars_with_prefix "PREFIX_" result` | `vars_with_prefix "MY_" vars` | Fills array with matching names |
| `vars_matching` | `vars_matching "MY_*_CONFIG" result` | `vars_matching "*_PATH" vars` | Glob pattern match |
| `vars_exported` | `vars_exported result` | `vars_exported exports` | All exported variable names |

### Variable Operations

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `var_copy` | `var_copy "source" "dest"` | `var_copy "old" "new"` | Copies value (handles arrays) |
| `var_swap` | `var_swap "var1" "var2"` | `var_swap "a" "b"` | Swaps two variables |
| `var_incr` | `var_incr "name" [amount]` | `var_incr "count" 5` | Increments integer |
| `var_decr` | `var_decr "name" [amount]` | `var_decr "count"` | Decrements integer |
| `var_append` | `var_append "name" "suffix"` | `var_append "msg" "!"` | Appends to string |
| `var_prepend` | `var_prepend "name" "prefix"` | `var_prepend "msg" "Hi "` | Prepends to string |

### Type Detection

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `var_type` | `var_type "name"` | `var_type "myarr"` | `string`, `array`, `assoc`, `integer`, `nameref`, `readonly`, `unset` |
| `var_is_array` | `var_is_array "name"` | `var_is_array "files"` | (returns 0/1) |
| `var_is_assoc` | `var_is_assoc "name"` | `var_is_assoc "config"` | (returns 0/1) |
| `var_is_readonly` | `var_is_readonly "name"` | `var_is_readonly "PI"` | (returns 0/1) |

### Constants

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `const` | `const "NAME" "value"` | `const "PI" "3.14159"` | Creates readonly variable |
| `const_default` | `const_default "NAME" "value"` | `const_default "TIMEOUT" "30"` | Creates if not exists |

### Function Introspection

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `func_exists` | `func_exists "name"` | `func_exists "myfunction"` | (returns 0/1) |
| `call_func` | `call_func "name" args...` | `call_func "log_info" "msg"` | Calls function by name |
| `func_def` | `func_def "name"` | `func_def "myfunction"` | Function definition |
| `func_source` | `func_source "name"` | `func_source "uuid"` | `filename:line` |
| `funcs_with_prefix` | `funcs_with_prefix "my_" result` | `funcs_with_prefix "test_" tests` | Fills array with matching |

### Dynamic Dispatch

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `call_method` | `call_method "prefix" "method" args` | `call_method "myobj" "init" arg1` | Calls `myobj_init arg1` |
| `method_exists` | `method_exists "prefix" "method"` | `method_exists "myobj" "save"` | (returns 0/1) |
| `call_or_default` | `call_or_default "name" "default" args` | `call_or_default "hook" "ok"` | Calls if exists, else returns default |

### Nameref Helpers

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `var_ref` | `var_ref "refname" "target"` | `var_ref "alias" "original"` | Creates nameref |
| `var_ref_target` | `var_ref_target "refname"` | `var_ref_target "alias"` | Returns target name |

### Array Operations by Name

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `array_push_byname` | `array_push_byname "arr" val...` | `array_push_byname "stack" "a" "b"` | Push to array |
| `array_pop_byname` | `array_pop_byname "arr" [result]` | `array_pop_byname "stack" item` | Pop from array |
| `array_len_byname` | `array_len_byname "arr"` | `array_len_byname "items"` | Array length |

### Common Patterns

```bash
# Dynamic variable access
config_port=8080
config_host="localhost"

var_get "config_port"          # 8080
var_set "config_timeout" "30"  # Sets dynamically

# Find all config variables
vars_with_prefix "config_" cfg_vars
for name in "${cfg_vars[@]}"; do
    echo "$name = $(var_get "$name")"
done
```

```bash
# Type-safe operations
declare -A settings
settings[debug]=true
settings[verbose]=false

if var_is_assoc "settings"; then
    echo "settings is an associative array"
fi
echo "Type: $(var_type "settings")"  # assoc
```

```bash
# Plugin/hook system
myapp_on_start() { echo "Starting..."; }
myapp_on_stop() { echo "Stopping..."; }

# Dynamic hook dispatch
for event in start stop cleanup; do
    if method_exists "myapp" "on_$event"; then
        call_method "myapp" "on_$event"
    fi
done
```

```bash
# Constants for configuration
const "VERSION" "1.0.0"
const "MAX_RETRIES" "3"
const_default "TIMEOUT" "30"  # Only sets if not already defined

# Trying to modify fails:
var_set "VERSION" "2.0.0"  # Error: VERSION is readonly
```

```bash
# Counter with increment
var_set "requests" "0"
var_incr "requests"
var_incr "requests" 5
echo "Total: $(var_get "requests")"  # 6
```

---

## Idempotent Operations (idempotent.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `ensure_dir` | `ensure_dir "path" [mode]` | Create dir only if missing, optionally fix permissions |
| `ensure_file` | `ensure_file "path" ["content"] [mode]` | Create/update file only if needed |
| `ensure_line` | `ensure_line "file" "line" [marker]` | Add line if not present (marker for replacement) |
| `ensure_symlink` | `ensure_symlink "target" "link" [force]` | Create/fix symlink atomically |
| `ensure_command` | `ensure_command "cmd" [msg]` | Assert command exists or fail |
| `ensure_dirs` | `ensure_dirs "dir1" "dir2" ...` | Create multiple directories |
| `ensure_lines` | `ensure_lines "file" "line1" "line2" ...` | Add multiple lines if missing |

---

## Atomic File Operations (atomic.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `atomic_write` | `atomic_write "path" "content" [mode]` | Write via temp+rename (no partial state) |
| `atomic_append` | `atomic_append "path" "content"` | Append with flock (concurrent-safe) |
| `atomic_replace` | `atomic_replace "path" "content" [verify_cmd]` | Replace with backup+verify+rollback |
| `safe_remove` | `safe_remove "path"` | Move to trash (recoverable) |
| `safe_restore` | `safe_restore "filename"` | Restore most recent trashed file |
| `file_checkpoint` | `file_checkpoint "path" "name"` | Create named snapshot for rollback |
| `file_rollback` | `file_rollback "path" "name"` | Restore file from named checkpoint |
| `file_checkpoints` | `file_checkpoints ["path"]` | List available checkpoints |
| `file_checkpoint_cleanup` | `file_checkpoint_cleanup [max_age_s]` | Remove old checkpoints (default: 24h) |

---

## Structured Observability (observe.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `trace_start` | `tid=$(trace_start "name")` | Begin named trace, returns trace ID |
| `trace_step` | `trace_step "$tid" "step" [status] [detail]` | Record step within trace |
| `trace_end` | `result=$(trace_end "$tid" [status])` | End trace, emit JSON summary |
| `observe_command` | `result=$(observe_command cmd [args...])` | Execute cmd, capture stdout/stderr/exit/timing as JSON |
| `stack_trace` | `trace=$(stack_trace)` | Current bash call stack as JSON |
| `observe_error` | `observe_error code "msg" [context]` | Structured JSON error to stderr |
| `observe_time` | `t=$(observe_time)` | High-resolution timestamp |
| `observe_elapsed` | `elapsed=$(observe_elapsed "$start")` | Duration since timestamp |

---

## Project Intelligence (project.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `project_detect` | `json=$(project_detect "dir")` | Detect language/framework/build from directory |
| `project_commands` | `json=$(project_commands "dir")` | Return build/test/lint/dev commands |
| `project_entry` | `json=$(project_entry "dir")` | Find main entry point files |
| `project_deps` | `json=$(project_deps "dir")` | Count and list dependencies |
| `project_structure` | `json=$(project_structure "dir")` | Directory tree with file counts |

Supported: TypeScript, Python, Rust, Go, Ruby, Java, PHP, C/C++, Elixir, Swift.
Frameworks: Next.js, FastAPI, Django, Rails, Axum, Gin, Spring, Laravel, Phoenix, +10 more.

---

## Design-by-Contract (contract.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `mainframe_error` | `mainframe_error code "msg" [key=val...]` | Structured JSON error with context |
| `contract_require` | `contract_require "expr" "msg"` | Assert precondition (input validation) |
| `contract_ensure` | `contract_ensure "expr" "msg"` | Assert postcondition (output validation) |
| `contract_invariant` | `contract_invariant "expr" "msg"` | Assert invariant (always true) |
| `contract_type_check` | `contract_type_check "val" "type" "name"` | Validate type (int/float/bool/file/dir/nonempty) |
| `contract_not_empty` | `contract_not_empty "arg1" "arg2" ...` | Assert all args non-empty |
| `contract_is_file` | `contract_is_file "path" ["name"]` | Assert file exists |
| `contract_is_dir` | `contract_is_dir "path" ["name"]` | Assert directory exists |
| `contract_in_range` | `contract_in_range val min max ["name"]` | Assert integer in [min, max] |
| `contracts_disable` | `contracts_disable` | Disable all checks (production) |
| `contracts_enable` | `contracts_enable` | Re-enable checks |

---

## Performance & Feature Gates (perf.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `bash_version` | `ver=$(bash_version)` | Returns "major.minor.patch" |
| `bash_version_major` | `major=$(bash_version_major)` | Returns major version number |
| `bash_version_at_least` | `bash_version_at_least major [minor]` | Check minimum bash version |
| `bash_has_feature` | `bash_has_feature "name"` | Check feature availability |
| `bash_features` | `json=$(bash_features)` | JSON of all features with availability |
| `perf_timer_start` | `perf_timer_start "name"` | Start named timer (no subshell) |
| `perf_timer_elapsed` | `s=$(perf_timer_elapsed "name")` | Get elapsed seconds |
| `perf_timer_stop` | `json=$(perf_timer_stop "name")` | Stop timer, return JSON result |
| `perf_compare` | `json=$(perf_compare "cmd1" "cmd2" [N])` | Compare two approaches |
| `perf_setvar` | `perf_setvar "varname" "value"` | Set variable without subshell |
| `perf_benchmark` | `json=$(perf_benchmark "cmd" [N])` | Benchmark command with iterations |

Features: `namerefs`, `mapfile`, `associative_arrays`, `epochrealtime`, `epochseconds`, `wait_n`, `lastpipe`, `inherit_errexit`, `extglob`, `loadable_builtins`

---

## Network Scanning (netscan.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `port_check` | `port_check "host" port [timeout]` | Check if TCP port is open |
| `host_alive` | `host_alive "host" [timeout]` | Check if host responds (ping/TCP) |
| `banner_grab` | `banner=$(banner_grab "host" port [timeout])` | Grab service banner |
| `http_headers` | `json=$(http_headers "url" [timeout])` | Extract HTTP headers as JSON |
| `monitor_port` | `json=$(monitor_port "host" port [timeout])` | Port state as JSON with timestamp |
| `scan_range` | `json=$(scan_range "host" "ports" [timeout])` | Scan port list/range |
| `parse_nmap` | `json=$(parse_nmap < scan.gnmap)` | Parse nmap greppable output to JSON |

Port specs: `"22,80,443"` (comma list) or `"1-1024"` (range)

---

## Format Parsers (parsers.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `parse_csv_line` | `parse_csv_line "line"` | Parse CSV into PARSE_CSV_FIELDS array |
| `parse_csv_json` | `json=$(parse_csv_json "line")` | Parse CSV line to JSON array |
| `parse_key_value` | `json=$(parse_key_value < file)` | Parse key=value / key: value to JSON |
| `parse_ini` | `json=$(parse_ini < file.ini)` | Parse INI file to nested JSON |
| `parse_url` | `json=$(parse_url "url")` | Parse URL components to JSON |
| `parse_semver` | `json=$(parse_semver "1.2.3-beta+build")` | Parse semver to JSON |
| `semver_compare` | `cmp=$(semver_compare "v1" "v2")` | Compare versions: -1, 0, 1 |

---

*900+ functions | 34 libraries | Zero dependencies | 20-72x faster*

**YO JOE!**

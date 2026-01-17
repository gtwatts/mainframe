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

*580+ functions | 20 libraries | Zero dependencies | 20-72x faster*

**YO JOE!**

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

## Universal Structured Output Protocol (output.sh)

**Purpose**: Enables MAINFRAME functions to output structured JSON envelopes for AI agents. Supports multiple output modes: `raw` (default), `json`, `minimal`, `debug`.

### Mode Control

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `output_init` | `output_init` | `output_init` | Initializes output system |
| `output_mode` | `output_mode [mode]` | `output_mode "json"` | Gets/sets mode |
| `output_is_json` | `output_is_json` | `output_is_json && echo "JSON mode"` | (returns 0/1) |
| `output_is_raw` | `output_is_raw` | `output_is_raw && echo "Raw mode"` | (returns 0/1) |
| `output_is_minimal` | `output_is_minimal` | `output_is_minimal` | (returns 0/1) |
| `output_is_debug` | `output_is_debug` | `output_is_debug` | (returns 0/1) |
| `output_format` | `output_format` | `echo "Mode: $(output_format)"` | Current mode name |
| `output_with_mode` | `output_with_mode "mode" cmd` | `output_with_mode "json" output_success "data"` | Temp mode change |

### Core Output Functions

| Function | Signature | Example | Output (json mode) |
|----------|-----------|---------|--------|
| `output_success` | `output_success "data" ["hint"]` | `output_success "result" "next_func"` | `{"ok":true,"data":"result","hint":"next_func"}` |
| `output_error` | `output_error "code" "msg" ["suggestion"]` | `output_error "E_NOT_FOUND" "File missing" "check path"` | `{"ok":false,"error":{"code":"E_NOT_FOUND","msg":"File missing","suggestion":"check path"}}` |
| `output_raw` | `output_raw "text"` | `output_raw "plain"` | `plain` (bypasses envelope) |
| `output_json` | `output_json '{"custom":1}'` | `output_json '{"a":1}'` | `{"a":1}` (unchanged) |

### Type-Specific Helpers

| Function | Signature | Example | Output (json mode) |
|----------|-----------|---------|--------|
| `output_string` | `output_string "text"` | `output_string "hello"` | `{"ok":true,"data":"hello"}` |
| `output_int` | `output_int number` | `output_int 42` | `{"ok":true,"data":42}` |
| `output_float` | `output_float number` | `output_float 3.14` | `{"ok":true,"data":3.14}` |
| `output_bool` | `output_bool value` | `output_bool true` | `{"ok":true,"data":true}` |
| `output_json_object` | `output_json_object '{"k":"v"}'` | `output_json_object '{"id":1}'` | `{"ok":true,"data":{"id":1}}` |
| `output_json_array` | `output_json_array '["a","b"]'` | `output_json_array '[1,2,3]'` | `{"ok":true,"data":[1,2,3]}` |
| `output_file_path` | `output_file_path "/path"` | `output_file_path "/tmp/f.txt"` | `{"ok":true,"data":"/tmp/f.txt"}` |
| `output_void` | `output_void` | `output_void` | `{"ok":true,"data":null}` |

### Timing Functions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `output_timer_start` | `output_timer_start` | `output_timer_start` | Records start time |
| `output_timer_elapsed` | `output_timer_elapsed` | `elapsed=$(output_timer_elapsed)` | Milliseconds elapsed |

### Function Wrapping

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `output_wrap` | `output_wrap func [args...]` | `output_wrap my_func arg1` | Wraps result in envelope |
| `mainframe_call` | `mainframe_call func [args...]` | `mainframe_call git_branch` | Legacy wrapper (status format) |

### Nameref Variant (Performance)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `output_v` | `output_v result_var "data"` | `output_v result "hello"` | Sets result var (no subshell) |

### Quick Patterns (Output)

```bash
# Set JSON output mode
export MAINFRAME_OUTPUT=json

# Simple success response
output_success "operation completed" "check_status"
# {"ok":true,"data":"operation completed","hint":"check_status"}

# Error with suggestion
output_error "E_FILE_NOT_FOUND" "Config file missing" "run init first"
# {"ok":false,"error":{"code":"E_FILE_NOT_FOUND","msg":"Config file missing","suggestion":"run init first"}}

# Typed outputs
output_int 42              # {"ok":true,"data":42}
output_bool true           # {"ok":true,"data":true}
output_json_object '{"name":"John","age":30}'
# {"ok":true,"data":{"name":"John","age":30}}

# Timing
output_timer_start
do_expensive_operation
output_success "done"  # Includes meta.elapsed_ms

# Wrap existing function
my_func() { echo "result"; }
output_wrap my_func
# {"ok":true,"data":"result","meta":{"elapsed_ms":2}}

# Performance: avoid subshell with nameref
output_v result "computed value"
echo "$result"  # {"ok":true,"data":"computed value"}

# Temporarily change mode
export MAINFRAME_OUTPUT=raw
result=$(output_with_mode "json" output_success "data")
# result contains JSON, but mode returns to raw
```

### Output Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `raw` | Plain text (default) | Human-readable scripts |
| `json` | Full envelope with meta/hint | AI agent consumption |
| `minimal` | Compact JSON (ok+data only) | Low-bandwidth scenarios |
| `debug` | JSON + timestamp + caller | Debugging agent behavior |

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

## v3.0 AI-Optimized Libraries

---

## Idempotent Operations (idempotent.sh)

**Purpose**: Check-before-act operations that produce the same result regardless of how many times executed. Essential for AI agents that re-run scripts after context loss.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ensure_dir` | `ensure_dir "path" [mode]` | `ensure_dir "/var/log/myapp" "0755"` | (returns 0, creates dir if missing) |
| `ensure_file` | `ensure_file "path" ["content"] [mode]` | `ensure_file "/etc/myapp.conf" "key=value" "0644"` | (returns 0, writes only if differs) |
| `ensure_line` | `ensure_line "file" "line" [marker]` | `ensure_line "/etc/hosts" "127.0.0.1 myapp.local"` | (returns 0, appends if not present) |
| `ensure_symlink` | `ensure_symlink "target" "link" [force]` | `ensure_symlink "/opt/app-v2" "/opt/app-current"` | (returns 0, creates/fixes symlink) |
| `ensure_command` | `ensure_command "cmd"` | `ensure_command "jq" \|\| exit 1` | (returns 0 if found, 1 if missing) |
| `ensure_dirs` | `ensure_dirs "dir1" "dir2" ...` | `ensure_dirs "/var/log" "/var/run" "/var/data"` | (returns 0 if all created) |
| `ensure_lines` | `ensure_lines "file" "line1" "line2"` | `ensure_lines "/etc/hosts" "127.0.0.1 a" "127.0.0.1 b"` | (returns 0 if all added) |
| `ensure_mount` | `ensure_mount "device" "mountpoint" [opts]` | `ensure_mount "tmpfs" "/tmp/ramdisk" "-t tmpfs -o size=512m"` | (returns 0, mounts if not mounted) |
| `ensure_service` | `ensure_service "name" [check_cmd]` | `ensure_service "nginx"` | (returns 0, starts if not running) |
| `ensure_package` | `ensure_package "name"` | `ensure_package "jq"` | (returns 0, installs if missing) |

### Quick Patterns (Idempotent)

```bash
# Setup project directories (safe to re-run)
ensure_dirs "/opt/myapp/bin" "/opt/myapp/config" "/opt/myapp/logs"

# Ensure config file with content
ensure_file "/opt/myapp/config/app.conf" "port=8080
host=0.0.0.0
log_level=info" "0644"

# Add lines to config (idempotent)
ensure_line "/etc/hosts" "127.0.0.1 myapp.local"
ensure_line "~/.bashrc" 'export PATH="/opt/bin:$PATH"' "MANAGED:opt-bin"

# Symlink management
ensure_symlink "/opt/app-v2.1" "/opt/app-current"

# Verify dependencies
ensure_command "git" || { echo "git required"; exit 1; }
ensure_package "curl"
ensure_service "redis" "redis-cli ping"
```

---

## Atomic File Operations (atomic.sh)

**Purpose**: File write operations that prevent partial state through temp-file-then-rename patterns, flock for concurrent access, and checkpoint/rollback for safe recovery.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `atomic_write` | `atomic_write "path" "content" [mode]` | `atomic_write "/etc/myapp.conf" "$config" "0644"` | (returns 0, file written atomically) |
| `atomic_append` | `atomic_append "path" "content"` | `atomic_append "/var/log/app.log" "[$(date)] Event"` | (returns 0, appended with flock) |
| `atomic_replace` | `atomic_replace "path" "content" [verify]` | `atomic_replace "/etc/nginx.conf" "$new_conf" "nginx -t"` | (returns 0, backup+verify+replace) |
| `safe_remove` | `safe_remove "path"` | `safe_remove "/etc/old-config.conf"` | (returns 0, moved to trash) |
| `safe_restore` | `safe_restore "filename"` | `safe_restore "old-config.conf"` | (returns 0, restored from trash) |
| `file_checkpoint` | `file_checkpoint "path" "name"` | `file_checkpoint "/etc/nginx.conf" "before-ssl"` | (returns 0, snapshot saved) |
| `file_rollback` | `file_rollback "path" "name"` | `file_rollback "/etc/nginx.conf" "before-ssl"` | (returns 0, file restored) |
| `file_checkpoints` | `file_checkpoints ["path"]` | `file_checkpoints "/etc/nginx.conf"` | `before-ssl\t/etc/nginx.conf\t2048 bytes` |
| `file_checkpoint_cleanup` | `file_checkpoint_cleanup [max_age_s]` | `file_checkpoint_cleanup 3600` | (returns 0, removes old checkpoints) |

### Quick Patterns (Atomic)

```bash
# Write config atomically (readers never see partial content)
config=$(generate_config)
atomic_write "/etc/myapp/config.json" "$config" "0644"

# Replace with verification and auto-rollback
atomic_replace "/etc/nginx/nginx.conf" "$new_config" "nginx -t"
# If nginx -t fails, original is automatically restored

# Checkpoint before risky changes
file_checkpoint "/etc/ssh/sshd_config" "before-hardening"
# ... make changes ...
# If something goes wrong:
file_rollback "/etc/ssh/sshd_config" "before-hardening"

# Safe deletion (recoverable)
safe_remove "/etc/old-service.conf"
# Oops, need it back:
safe_restore "old-service.conf"

# Concurrent-safe log appending
atomic_append "/var/log/deploy.log" "[$(date)] Deployed v2.1"
```

---

## Structured Observability (observe.sh)

**Purpose**: Trace, timing, and structured error reporting that produces JSON output AI agents can parse for debugging, error recovery, and performance analysis.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_start` | `tid=$(trace_start "name")` | `tid=$(trace_start "deploy_config")` | `trace_a1b2c3d4e5f6` |
| `trace_step` | `trace_step "$tid" "step" [status] [detail]` | `trace_step "$tid" "write_config" "ok" "3 keys"` | (JSON event to stderr) |
| `trace_end` | `result=$(trace_end "$tid" [status])` | `result=$(trace_end "$tid" "success")` | `{"event":"trace_end","trace_id":"...","duration_s":1.23,...}` |
| `observe_command` | `result=$(observe_command cmd [args])` | `result=$(observe_command ls -la /tmp)` | `{"cmd":"ls -la /tmp","exit_code":0,"duration_s":0.01,"stdout":"..."}` |
| `stack_trace` | `trace=$(stack_trace)` | `trace=$(stack_trace)` | `{"stack":[{"func":"myfunc","file":"script.sh","line":42}],"depth":3}` |
| `observe_error` | `observe_error code "msg" [context]` | `observe_error 2 "invalid port" "port=99999"` | `{"error":true,"code":2,"msg":"invalid port","context":"port=99999"}` |
| `observe_time` | `t=$(observe_time)` | `start=$(observe_time)` | `1705312896.123456` |
| `observe_elapsed` | `elapsed=$(observe_elapsed "$start")` | `elapsed=$(observe_elapsed "$start")` | `2.345678` |

### Quick Patterns (Observability)

```bash
# Trace a multi-step operation
tid=$(trace_start "deploy_application")
trace_step "$tid" "pull_image" "ok" "nginx:latest"
trace_step "$tid" "stop_old" "ok"
trace_step "$tid" "start_new" "ok" "port 8080"
summary=$(trace_end "$tid" "success")
echo "$summary"  # Full JSON with duration and all steps

# Observe a command (captures everything as JSON)
result=$(observe_command npm test)
echo "$result"  # {"cmd":"npm test","exit_code":0,"duration_s":12.5,...}

# Time a section of code
start=$(observe_time)
# ... expensive work ...
elapsed=$(observe_elapsed "$start")
echo "Took ${elapsed}s"

# Structured error for AI parsing
observe_error 1 "config file missing" "path=/etc/myapp.conf"
```

---

## Project Intelligence (project.sh)

**Purpose**: Detect project types, frameworks, build systems, and entry points from directory structure. Gives AI agents instant context without reading dozens of files.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `project_detect` | `json=$(project_detect [dir])` | `project_detect .` | `{"language":"typescript","framework":"nextjs","package_manager":"bun",...}` |
| `project_commands` | `json=$(project_commands [dir])` | `project_commands .` | `{"install":"bun install","build":"bun run build","test":"bun run test",...}` |
| `project_entry` | `json=$(project_entry [dir])` | `project_entry .` | `["src/index.ts","src/app.ts"]` |
| `project_deps` | `json=$(project_deps [dir])` | `project_deps .` | `{"total":45,"production":12,"development":33,"notable":["react","next"]}` |
| `project_structure` | `json=$(project_structure [dir] [depth])` | `project_structure . 2` | `{"directories":["src","tests","lib"],"file_count":87,"extensions":{".ts":42}}` |

**Supported Languages**: TypeScript, JavaScript, Python, Rust, Go, Ruby, Java, PHP, C/C++, Elixir, Swift.

**Detected Frameworks**: Next.js, Nuxt, SvelteKit, Astro, Remix, React, Vue, Angular, Express, Fastify, Django, FastAPI, Flask, Rails, Actix, Axum, Gin, Echo.

**Package Managers**: bun, pnpm, yarn, npm, poetry, uv, pipenv, cargo, go-modules, bundler, composer.

### Quick Patterns (Project Intelligence)

```bash
# Get instant project context
info=$(project_detect .)
echo "$info"
# {"language":"typescript","framework":"nextjs","package_manager":"bun",
#  "build_system":"vite","test_runner":"vitest","ci_provider":"github_actions",...}

# Find the right commands
cmds=$(project_commands .)
echo "$cmds"
# {"install":"bun install","build":"bun run build","test":"bun run test",
#  "lint":"bun run lint","dev":"bun run dev","start":"bun run start"}

# Discover entry points
entries=$(project_entry .)
echo "$entries"  # ["src/app/page.tsx","src/app/layout.tsx"]

# Analyze dependencies
deps=$(project_deps .)
echo "$deps"  # {"total":45,"production":12,"development":33,"notable":["react","next","prisma"]}
```

---

## Design-by-Contract (contract.sh)

**Purpose**: Precondition/postcondition assertions, type checking, and structured JSON error reporting that AI agents can parse for automated debugging and recovery.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `mainframe_error` | `mainframe_error code "msg" [key=val...]` | `mainframe_error 2 "invalid port" "port=99999" "range=1-65535"` | `{"error":true,"code":2,"msg":"invalid port","context":{"port":"99999"}}` |
| `contract_require` | `contract_require "expr" "msg"` | `contract_require "[[ -n \$arg ]]" "argument required"` | (returns 0 if true, JSON error + 1 if false) |
| `contract_ensure` | `contract_ensure "expr" "msg"` | `contract_ensure "[[ -f \$output ]]" "output not created"` | (returns 0 if true, JSON error + 1 if false) |
| `contract_invariant` | `contract_invariant "expr" "msg"` | `contract_invariant "[[ \$count -ge 0 ]]" "count negative"` | (returns 0 if true, JSON error + 1 if false) |
| `contract_type_check` | `contract_type_check "val" "type" "name"` | `contract_type_check "8080" "int" "port"` | (returns 0 if valid type) |
| `contract_not_empty` | `contract_not_empty "arg1" "arg2" ...` | `contract_not_empty "$file" "$content"` | (returns 0 if all non-empty) |
| `contract_is_file` | `contract_is_file "path" ["name"]` | `contract_is_file "/etc/config.json" "config"` | (returns 0 if file exists) |
| `contract_is_dir` | `contract_is_dir "path" ["name"]` | `contract_is_dir "/var/data" "data directory"` | (returns 0 if dir exists) |
| `contract_in_range` | `contract_in_range val min max ["name"]` | `contract_in_range "$port" 1 65535 "port"` | (returns 0 if in range) |
| `contracts_disable` | `contracts_disable` | `contracts_disable` | (disables all checks) |
| `contracts_enable` | `contracts_enable` | `contracts_enable` | (re-enables all checks) |

**Supported Types** for `contract_type_check`: `int`, `float`, `bool`, `string`, `nonempty`, `file`, `dir`, `path`.

### Quick Patterns (Contracts)

```bash
# Function with precondition/postcondition
deploy_service() {
    local config="$1" port="$2"

    # Preconditions
    contract_require "[[ -f '$config' ]]" "config file required" || return $?
    contract_type_check "$port" "int" "port" || return $?
    contract_in_range "$port" 1024 65535 "port" || return $?

    # ... do work ...

    # Postcondition
    contract_ensure "[[ -f /var/run/service.pid ]]" "service not started" || return $?
}

# Type checking
contract_type_check "$timeout" "int" "timeout"     # Is it an integer?
contract_type_check "$enabled" "bool" "enabled"    # true/false/yes/no/0/1?
contract_type_check "$output" "file" "output_file" # Does file exist?

# Structured errors for AI parsing
mainframe_error 1 "connection refused" "host=db.example.com" "port=5432"
# stderr: {"error":true,"code":1,"msg":"connection refused","context":{"host":"db.example.com","port":"5432"}}

# Disable in production for performance
[[ "$ENV" == "production" ]] && contracts_disable
```

---

## Performance & Feature Gates (perf.sh)

**Purpose**: Bash version detection, feature gating for modern Bash (5.0+/5.3+), and performance measurement utilities. Enables conditional use of fast-path features while maintaining Bash 4.0+ compatibility.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bash_version` | `bash_version` | `echo "Bash $(bash_version)"` | `5.2.21` |
| `bash_version_major` | `bash_version_major` | `echo "Major: $(bash_version_major)"` | `5` |
| `bash_version_at_least` | `bash_version_at_least major [minor]` | `bash_version_at_least 5 0 && echo "5+"` | (returns 0/1) |
| `bash_has_feature` | `bash_has_feature "name"` | `bash_has_feature "namerefs" && declare -n ref=var` | (returns 0/1) |
| `bash_features` | `json=$(bash_features)` | `bash_features` | `{"namerefs":true,"epochrealtime":true,...}` |
| `perf_timer_start` | `perf_timer_start "name"` | `perf_timer_start "database_query"` | (stores start time in variable) |
| `perf_timer_elapsed` | `s=$(perf_timer_elapsed "name")` | `perf_timer_elapsed "database_query"` | `0.234567` |
| `perf_timer_stop` | `json=$(perf_timer_stop "name")` | `perf_timer_stop "database_query"` | `{"timer":"database_query","duration_s":0.234567}` |
| `perf_compare` | `json=$(perf_compare "cmd1" "cmd2" [N])` | `perf_compare "printf '%s' foo" "echo foo" 100` | `{"iterations":100,"cmd1_total_s":0.05,"cmd2_total_s":0.08,"winner":"cmd1"}` |
| `perf_setvar` | `perf_setvar "varname" "value"` | `perf_setvar "result" "hello"` | (sets variable without subshell) |
| `perf_capture` | `perf_capture "varname" cmd [args]` | `perf_capture "hostname" cat /etc/hostname` | (captures output without subshell) |
| `perf_benchmark` | `json=$(perf_benchmark "cmd" [N])` | `perf_benchmark "sha256sum /dev/null" 50` | `{"cmd":"...","iterations":50,"total_s":0.5,"avg_s":0.01,"exit_code":0}` |

**Available Features**: `namerefs` (4.3+), `mapfile` (4.0+), `associative_arrays` (4.0+), `epochrealtime` (5.0+), `epochseconds` (5.0+), `wait_n` (4.3+), `lastpipe` (4.2+), `globasciiranges` (4.3+), `inherit_errexit` (4.4+), `extglob` (4.0+), `loadable_builtins` (4.0+).

### Quick Patterns (Performance)

```bash
# Feature-gated code paths
if bash_has_feature "epochrealtime"; then
    timestamp="$EPOCHREALTIME"  # No subshell, no fork
else
    timestamp=$(date +%s.%N)    # Fallback
fi

# Time operations
perf_timer_start "migration"
run_database_migration
elapsed=$(perf_timer_elapsed "migration")
echo "Migration took ${elapsed}s"

# Benchmark alternatives
result=$(perf_compare 'printf "%s" "$data"' 'echo "$data"' 1000)
echo "$result"  # Shows which is faster

# Full benchmark with stats
perf_benchmark "json_object name=test age:number=30" 100

# Avoid subshells in hot paths
perf_setvar "result" "computed_value"  # vs result="computed_value" in dynamic cases
```

---

## Network Scanning (netscan.sh)

**Purpose**: Pure-bash network utilities for port checking, host discovery, banner grabbing, and HTTP header extraction. Uses /dev/tcp with nc/ncat fallback.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `port_check` | `port_check "host" port [timeout]` | `port_check "localhost" 8080` | (returns 0 if open, 1 if closed) |
| `host_alive` | `host_alive "host" [timeout]` | `host_alive "192.168.1.1" 5` | (returns 0 if reachable) |
| `banner_grab` | `banner=$(banner_grab "host" port [timeout])` | `banner_grab "192.168.1.1" 22` | `SSH-2.0-OpenSSH_9.0` |
| `http_headers` | `json=$(http_headers "url" [timeout])` | `http_headers "http://localhost:8080"` | `{"Content-Type":"text/html","Server":"nginx",...}` |
| `monitor_port` | `json=$(monitor_port "host" port [timeout])` | `monitor_port "localhost" 5432` | `{"host":"localhost","port":5432,"state":"open","timestamp":1705312896}` |
| `scan_range` | `json=$(scan_range "host" "ports" [timeout])` | `scan_range "localhost" "22,80,443,8080"` | `[{"port":22,"state":"open"},{"port":80,"state":"closed"},...]` |
| `parse_nmap` | `json=$(parse_nmap < scan.gnmap)` | `nmap -oG - 192.168.1.0/24 \| parse_nmap` | `[{"ip":"192.168.1.1","ports":[{"port":22,"state":"open",...}]}]` |

**Port Specifications**: `"22,80,443"` (comma-separated list) or `"1-1024"` (range).

**Timeout**: Default 3 seconds, configurable via `MAINFRAME_NET_TIMEOUT` or per-call argument.

### Quick Patterns (Network)

```bash
# Check if service is ready
if port_check "localhost" 5432; then
    echo "PostgreSQL is accepting connections"
fi

# Wait for service startup
for i in {1..30}; do
    port_check "localhost" 8080 1 && break
    sleep 1
done

# Service discovery
if host_alive "db.internal" 2; then
    banner=$(banner_grab "db.internal" 5432 2)
    echo "Database banner: $banner"
fi

# Quick security scan
result=$(scan_range "server.example.com" "22,80,443,3306,5432,8080")
echo "$result"

# HTTP service check
headers=$(http_headers "http://api.example.com/health")
echo "$headers"  # JSON with all response headers

# Monitor with JSON output
status=$(monitor_port "localhost" 6379)
echo "$status"  # {"host":"localhost","port":6379,"state":"open","timestamp":...}
```

---

## Format Parsers (parsers.sh)

**Purpose**: Pure-bash parsers for common formats: CSV, key-value configs, INI files, URLs, and semantic versions. All output JSON for AI agent consumption.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `parse_csv_line` | `parse_csv_line "line"` | `parse_csv_line '"John","30","NYC"'` | (populates `PARSE_CSV_FIELDS` array) |
| `parse_csv_json` | `json=$(parse_csv_json "line")` | `parse_csv_json '"John","30","NYC"'` | `["John","30","NYC"]` |
| `parse_key_value` | `json=$(parse_key_value < file)` | `echo "host=localhost" \| parse_key_value` | `{"host":"localhost"}` |
| `parse_ini` | `json=$(parse_ini < file.ini)` | `parse_ini "[db]\nhost=localhost\nport=5432"` | `{"db":{"host":"localhost","port":"5432"}}` |
| `parse_url` | `json=$(parse_url "url")` | `parse_url "https://user:pass@host.com:8080/path?q=1#frag"` | `{"scheme":"https","host":"host.com","port":8080,"path":"/path","query":"q=1","fragment":"frag","user":"user","password":"pass"}` |
| `parse_semver` | `json=$(parse_semver "version")` | `parse_semver "1.2.3-beta.1+build.456"` | `{"major":1,"minor":2,"patch":3,"prerelease":"beta.1","build":"build.456","string":"1.2.3-beta.1+build.456"}` |
| `semver_compare` | `cmp=$(semver_compare "v1" "v2")` | `semver_compare "1.2.3" "1.3.0"` | `-1` |

### Quick Patterns (Parsers)

```bash
# Parse CSV data
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

# Parse and compare versions
current=$(parse_semver "2.1.0-rc.1")
echo "$current"  # {"major":2,"minor":1,"patch":0,"prerelease":"rc.1",...}

cmp=$(semver_compare "1.9.0" "2.0.0")
if [[ "$cmp" == "-1" ]]; then
    echo "Upgrade available"
fi

# Parse URL components
info=$(parse_url "https://api.example.com:8443/v2/users?page=1")
echo "$info"  # {"scheme":"https","host":"api.example.com","port":8443,"path":"/v2/users","query":"page=1"}
```

---

## Retry / Timeout / Circuit Breaker (retry.sh)

**Purpose**: Resilient operation primitives for AI agents -- retry with configurable backoff, timeouts, circuit breakers, polling/wait helpers, and token-bucket rate limiting.

### Retry

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `retry` | `retry [opts] cmd [args]` | `retry --max-attempts 5 --backoff exponential curl -sf http://api.com` | Retry with configurable backoff |
| `retry_simple` | `retry_simple N cmd [args]` | `retry_simple 3 curl -sf http://example.com` | Simple retry (exponential backoff) |

**Options**: `--max-attempts N` (default: 3), `--delay SECONDS` (default: 1), `--backoff linear|exponential|fixed` (default: exponential), `--max-delay SECONDS` (default: 30), `--jitter` (random 0-50% added), `--on-retry "callback"`.

### Timeout

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `with_timeout` | `with_timeout SECONDS cmd [args]` | `with_timeout 30 curl -sf http://slow-api.com` | Run with timeout (returns 124 on timeout) |
| `did_timeout` | `did_timeout` | `with_timeout 5 cmd; did_timeout && echo "timed out"` | Check if last with_timeout timed out |

### Circuit Breaker

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `circuit_breaker_init` | `circuit_breaker_init "name" [opts]` | `circuit_breaker_init "redis" --threshold 3 --timeout 30` | Initialize breaker |
| `circuit_breaker_call` | `circuit_breaker_call "name" cmd [args]` | `circuit_breaker_call "redis" redis-cli ping` | Execute through breaker (0=ok, 1=fail, 2=open) |
| `circuit_breaker_state` | `circuit_breaker_state "name"` | `state=$(circuit_breaker_state "redis")` | Query: closed/open/half-open |
| `circuit_breaker_failures` | `circuit_breaker_failures "name"` | `count=$(circuit_breaker_failures "redis")` | Current failure count |
| `circuit_breaker_reset` | `circuit_breaker_reset "name"` | `circuit_breaker_reset "redis"` | Force reset to closed |
| `circuit_breaker_list` | `circuit_breaker_list` | `circuit_breaker_list` | List all breakers (name, state, failures) |

**Options**: `--threshold N` (default: 5), `--timeout SECONDS` (default: 60), `--half-open-max N` (default: 1).

### Polling / Wait

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `wait_for` | `wait_for [opts] cmd [args]` | `wait_for --timeout 60 --interval 2 curl -sf http://localhost:8080/health` | Poll until condition true |
| `wait_for_file` | `wait_for_file "path" [timeout]` | `wait_for_file "/var/run/app.pid" 10` | Wait for file to exist |
| `wait_for_port` | `wait_for_port HOST PORT [timeout]` | `wait_for_port localhost 8080 60` | Wait for TCP port to open |

**Options**: `--timeout SECONDS` (default: 30), `--interval SECONDS` (default: 1), `--message "text"`.

### Rate Limiter

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `rate_limit_init` | `rate_limit_init "name" --rate N --per S` | `rate_limit_init "api" --rate 10 --per 60` | Initialize token bucket |
| `rate_limit_acquire` | `rate_limit_acquire "name" [--no-wait]` | `rate_limit_acquire "api"` | Acquire token (blocks or returns 1) |
| `rate_limit_reset` | `rate_limit_reset "name"` | `rate_limit_reset "api"` | Reset to full bucket |

### Quick Patterns (Retry)

```bash
# Retry with exponential backoff and jitter
retry --max-attempts 5 --backoff exponential --jitter curl -sf http://api.com

# Simple 3-attempt retry
retry_simple 3 wget -q http://example.com/file.zip

# Timeout with fallback
if ! with_timeout 30 long_running_task; then
    if did_timeout; then
        echo "Task timed out after 30s"
    else
        echo "Task failed"
    fi
fi

# Circuit breaker for flaky service
circuit_breaker_init "payment_api" --threshold 3 --timeout 30
if ! circuit_breaker_call "payment_api" curl -sf http://payments/charge; then
    case $? in
        1) echo "Payment failed" ;;
        2) echo "Payment service circuit is OPEN" ;;
    esac
fi

# Wait for service to be ready
wait_for_port localhost 5432 60
wait_for --timeout 30 --interval 2 curl -sf http://localhost:8080/health

# Rate-limited API calls
rate_limit_init "github_api" --rate 30 --per 60
for repo in "${repos[@]}"; do
    rate_limit_acquire "github_api"
    curl -sf "https://api.github.com/repos/$repo"
done
```

---

## Context Budget & Token Estimation (context.sh)

**Purpose**: Helps AI agents estimate token costs BEFORE operations, manage context budgets, and truncate/summarize content to fit within model limits. All estimates are approximations based on character-count heuristics.

### Token Estimation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_estimate_tokens` | `context_estimate_tokens "text"` | `context_estimate_tokens "Hello world"` | `3` |
| `context_file_tokens` | `context_file_tokens "path"` | `context_file_tokens "src/app.py"` | `285` |
| `context_command_tokens` | `context_command_tokens cmd [args]` | `context_command_tokens cat README.md` | `150` |
| `context_ratio` | `context_ratio [--type text\|code\|json\|markdown]` | `context_ratio --type code` | `3.5` |

### Budget Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_budget_init` | `context_budget_init [--max-tokens N] [--reserve N]` | `context_budget_init --max-tokens 128000 --reserve 4000` | (creates budget state) |
| `context_budget_use` | `context_budget_use "label" tokens` | `context_budget_use "config.ts" 2500` | (tracks allocation) |
| `context_budget_remaining` | `context_budget_remaining` | `context_budget_remaining` | `91500` |
| `context_budget_fits` | `context_budget_fits tokens` | `context_budget_fits 5000` | (returns 0=fits, 1=exceeds) |
| `context_budget_summary` | `context_budget_summary` | `context_budget_summary` | `{"max":128000,"used":36500,...}` |
| `context_budget_reset` | `context_budget_reset` | `context_budget_reset` | (clears all state) |

### Content Truncation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_truncate` | `context_truncate "text" max_tokens [--strategy S]` | `context_truncate "$big" 1000 --strategy smart` | (truncated text) |
| `context_truncate_file` | `context_truncate_file "path" max_tokens [--strategy S]` | `context_truncate_file "big.log" 500` | (truncated content) |
| `context_distribute_budget` | `echo "items" \| context_distribute_budget max_tokens` | (see patterns below) | (JSON with allocations) |

**Strategies**: `head` (default, keep beginning), `tail` (keep end), `middle` (keep both ends), `smart` (first+last paragraphs).

### Content Analysis

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_analyze` | `context_analyze "text"` | `context_analyze "$code"` | `{"chars":500,"lines":20,"type":"code","language":"python",...}` |
| `context_detect_type` | `context_detect_type "text"` | `context_detect_type "$src"` | `code:python` |
| `context_chunk_size` | `context_chunk_size [--type T] [--model M]` | `context_chunk_size --type code --model claude` | `6000` |

### File Batching

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `context_batch_files` | `echo "paths" \| context_batch_files max_tokens [--sort S]` | (see patterns below) | (file paths that fit) |
| `context_read_plan` | `context_read_plan max_tokens [files...]` | `context_read_plan 50000 src/*.ts` | `{"files":[...],"files_included":12,...}` |

### Quick Patterns (Context)

```bash
# Estimate before reading
tokens=$(context_file_tokens "src/main.ts")
echo "File would use ~$tokens tokens"

# Budget workflow for agent operations
context_budget_init --max-tokens 128000 --reserve 8000
for f in src/*.py; do
    tokens=$(context_file_tokens "$f")
    if context_budget_fits "$tokens"; then
        context_budget_use "$f" "$tokens"
        cat "$f"  # safe to read
    else
        echo "Skipping $f (would exceed budget)"
    fi
done
context_budget_summary  # JSON report

# Truncate large file for context
content=$(context_truncate_file "huge.log" 2000 --strategy tail)

# Plan which files to read
plan=$(context_read_plan 50000 src/*.ts tests/*.ts)
echo "$plan"  # Shows included/excluded files with token counts

# Batch files within budget (smallest first)
included=$(find src -name "*.py" | context_batch_files 30000 --sort size)
echo "$included"  # Paths that fit

# Distribute budget by priority
printf 'important\t%s\t3\nnice_to_have\t%s\t1\n' "$critical_content" "$extra_content" \
    | context_distribute_budget 10000
```

### Token Ratios

| Content Type | Chars/Token | Detection |
|--------------|-------------|-----------|
| English prose | 4.0 | Default |
| Code | 3.5 | >30% lines with indentation or `{};()=` |
| JSON/structured | 3.0 | Starts with `{` or `[` |
| Markdown | 3.8 | Contains `#`, `**`, triple backticks |

---

## Diff & Patch Operations (diff.sh)

**Purpose**: Surgical file editing for AI agents via unified diffs, search-and-replace, and safe patch application. Enables agents to make precise edits without dumping/rewriting entire files.

### Diff Generation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_strings` | `diff_strings "old" "new" [--context N]` | `diff_strings "hello" "world"` | Unified diff |
| `diff_files` | `diff_files "old_file" "new_file" [--context N]` | `diff_files "a.txt" "b.txt"` | Unified diff |
| `diff_preview` | `diff_preview "file" "new_content"` | `diff_preview "config.sh" "$new"` | Preview changes |
| `diff_edit_script` | `diff_edit_script "old" "new"` | `diff_edit_script "$old" "$new"` | Edit commands |

### Patch Application

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_apply` | `diff_apply "file" "diff" [--backup] [--dry-run] [--fuzz N]` | `diff_apply "f.txt" "$patch"` | (returns 0/1/2) |
| `diff_apply_string` | `diff_apply_string "text" "diff" [fuzz]` | `diff_apply_string "$text" "$patch"` | Patched text |
| `diff_reverse` | `diff_reverse "file" "diff"` | `diff_reverse "f.txt" "$patch"` | (returns 0/1/2) |

### Search-and-Replace (Agent-Friendly)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_replace` | `diff_replace "file" "old" "new" [--all] [--backup]` | `diff_replace "f.txt" "foo" "bar"` | (returns 0/1/2) |
| `diff_replace_string` | `diff_replace_string "text" "old" "new" [--all]` | `diff_replace_string "$s" "a" "b"` | Modified text |
| `diff_insert_after` | `diff_insert_after "file" "match" "new_text"` | `diff_insert_after "f.txt" "line" "new"` | (returns 0/1) |
| `diff_insert_before` | `diff_insert_before "file" "match" "new_text"` | `diff_insert_before "f.txt" "line" "new"` | (returns 0/1) |
| `diff_delete_lines` | `diff_delete_lines "file" "pattern" [--regex]` | `diff_delete_lines "f.txt" "TODO"` | (returns 0/1) |
| `diff_replace_range` | `diff_replace_range "file" start end "new"` | `diff_replace_range "f.txt" 2 4 "new"` | (returns 0/1) |

### Conflict Detection

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_can_apply` | `diff_can_apply "file" "diff"` | `diff_can_apply "f.txt" "$patch"` | (returns 0/1) |
| `diff_conflicts` | `diff_conflicts "file" "diff"` | `diff_conflicts "f.txt" "$patch"` | JSON array |
| `diff_validate_unique` | `diff_validate_unique "file" "text"` | `diff_validate_unique "f.txt" "foo"` | Match count |

### Diff Analysis

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `diff_stats` | `diff_stats "diff"` | `diff_stats "$patch"` | `{"additions":3,"deletions":1,...}` |
| `diff_changed_lines` | `diff_changed_lines "diff"` | `diff_changed_lines "$patch"` | +/- prefixed lines |
| `diff_affected_lines` | `diff_affected_lines "diff"` | `diff_affected_lines "$patch"` | Line numbers |

### Quick Patterns (Diff)

```bash
# Agent surgical edit (the PRIMARY use case)
diff_replace "src/config.ts" \
    'const PORT = 3000;' \
    'const PORT = 8080;' --backup

# Multiline replacement
diff_replace "src/app.ts" \
    $'function old() {\n    return null;\n}' \
    $'function new() {\n    return 42;\n}' --no-backup

# Insert after a matching line
diff_insert_after "Dockerfile" "FROM node:20" "RUN apt-get update"

# Preview changes before applying
preview=$(diff_preview "config.sh" "$new_content")
echo "$preview"

# Safe patch workflow
if diff_can_apply "main.py" "$patch"; then
    diff_apply "main.py" "$patch" --backup
else
    conflicts=$(diff_conflicts "main.py" "$patch")
    echo "Conflicts: $conflicts"
fi

# Validate before replacing
count=$(diff_validate_unique "src/index.ts" "$old_text")
case $? in
    0) diff_replace "src/index.ts" "$old_text" "$new_text" ;;
    1) echo "Text not found" ;;
    2) echo "Ambiguous: $count matches" ;;
esac

# Analyze a diff
stats=$(diff_stats "$patch")
echo "$stats"  # {"additions":5,"deletions":2,"changes":7,"files":1}

# Delete lines matching pattern
diff_delete_lines "output.log" "DEBUG" --regex

# Replace a range of lines (1-based)
diff_replace_range "script.sh" 10 15 "# replaced block"
```

---

## Agent Communication Protocol (agent.sh)

**Purpose**: Multi-agent coordination through file-based IPC. Provides agent registration, discovery, messaging (point-to-point, broadcast, pub/sub), work queues, synchronization primitives, and leader election.

### Registration & Discovery

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_init` | `agent_init` | `agent_init` | (creates directories) |
| `agent_register` | `agent_register "name" [capabilities...]` | `agent_register "worker1" "compute" "storage"` | (returns 0/1) |
| `agent_unregister` | `agent_unregister [name]` | `agent_unregister "worker1"` | (returns 0/1) |
| `agent_list` | `agent_list` | `agent_list` | JSON array of agents |
| `agent_list_v` | `agent_list_v result_array` | `agent_list_v agents` | (fills array) |
| `agent_status` | `agent_status [name]` | `agent_status "worker1"` | JSON status object |
| `agent_info` | `agent_info [name]` | `agent_info "worker1"` | JSON (alias for status) |
| `agent_info_v` | `agent_info_v result_var [name]` | `agent_info_v info "worker1"` | (stores in var) |
| `agent_discover` | `agent_discover "capability"` | `agent_discover "compute"` | Agent names (one/line) |
| `agent_find_by_capability` | `agent_find_by_capability "cap"` | `agent_find_by_capability "http"` | (alias for discover) |
| `agent_heartbeat` | `agent_heartbeat` | `agent_heartbeat` | (updates timestamp) |
| `agent_prune` | `agent_prune [--older-than SECS]` | `agent_prune --older-than 300` | (removes stale agents) |
| `agent_cleanup` | `agent_cleanup` | `agent_cleanup` | (removes all resources) |
| `agent_elect_leader` | `agent_elect_leader "group"` | `leader=$(agent_elect_leader "workers")` | Elected agent name |

### Messaging (Point-to-Point)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_send` | `agent_send "target" "message"` | `agent_send "worker2" "task_payload"` | (returns 0/1) |
| `agent_receive` | `agent_receive [timeout_secs]` | `msg=$(agent_receive 10)` | JSON envelope |
| `agent_receive_async` | `agent_receive_async` | `msg=$(agent_receive_async)` | JSON or empty |
| `agent_peek` | `agent_peek` | `next=$(agent_peek)` | JSON (doesn't consume) |
| `agent_inbox_count` | `agent_inbox_count` | `count=$(agent_inbox_count)` | Number of messages |
| `agent_clear_inbox` | `agent_clear_inbox` | `agent_clear_inbox` | (removes all messages) |
| `agent_broadcast` | `agent_broadcast "message"` | `agent_broadcast "shutdown"` | (sends to all agents) |

### Pub/Sub (Topic-Based)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_subscribe` | `agent_subscribe "topic"` | `agent_subscribe "news"` | (returns 0/1) |
| `agent_unsubscribe` | `agent_unsubscribe "topic"` | `agent_unsubscribe "news"` | (returns 0/1) |
| `agent_publish` | `agent_publish "topic" "message"` | `agent_publish "news" "headline"` | (returns 0/1) |

### Work Queues

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_work_queue` | `agent_work_queue "name"` | `agent_work_queue "tasks"` | (creates queue) |
| `agent_work_push` | `agent_work_push "queue" "item"` | `agent_work_push "tasks" "job_data"` | (returns 0/1) |
| `agent_work_push_tracked` | `agent_work_push_tracked "queue" "item"` | `id=$(agent_work_push_tracked "tasks" "job")` | Returns task_id |
| `agent_work_pop` | `agent_work_pop "queue"` | `item=$(agent_work_pop "tasks")` | JSON item |
| `agent_work_pop_tracked` | `agent_work_pop_tracked "queue"` | `item=$(agent_work_pop_tracked "tasks")` | JSON (marks in-progress) |
| `agent_work_complete` | `agent_work_complete "queue" "id"` | `agent_work_complete "tasks" "$id"` | (marks complete) |
| `agent_work_fail` | `agent_work_fail "queue" "id" "reason"` | `agent_work_fail "tasks" "$id" "timeout"` | (marks failed) |
| `agent_work_count` | `agent_work_count "queue"` | `count=$(agent_work_count "tasks")` | Item count |
| `agent_work_stats` | `agent_work_stats "queue"` | `agent_work_stats "tasks"` | JSON stats |
| `agent_work_clear` | `agent_work_clear "queue"` | `agent_work_clear "tasks"` | (empties queue) |

### Synchronization

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_barrier` | `agent_barrier "name" count [timeout]` | `agent_barrier "phase1" 3 30` | (waits for N agents) |
| `agent_signal` | `agent_signal "name"` | `agent_signal "data_ready"` | (raises signal) |
| `agent_wait` | `agent_wait "name" [timeout]` | `agent_wait "data_ready" 60` | (waits for signal) |
| `agent_lock` | `agent_lock "resource"` | `agent_lock "database"` | (blocks until acquired) |
| `agent_unlock` | `agent_unlock "resource"` | `agent_unlock "database"` | (releases lock) |
| `agent_trylock` | `agent_trylock "resource"` | `agent_trylock "database"` | (returns 0=acquired, 1=busy) |

### Quick Patterns (Agent)

```bash
# Initialize and register
agent_init
agent_register "worker-1" "compute" "http"

# Send/receive messages
agent_send "coordinator" '{"task":"analyze","id":123}'
msg=$(agent_receive 30)

# Pub/sub workflow
agent_subscribe "updates"
# ... elsewhere ...
agent_publish "updates" '{"version":"2.0"}'

# Work queue pattern
agent_work_queue "jobs"
task_id=$(agent_work_push_tracked "jobs" '{"url":"http://example.com"}')
item=$(agent_work_pop_tracked "jobs")
# process item...
agent_work_complete "jobs" "$task_id"

# Barrier synchronization (wait for all workers)
agent_barrier "phase_complete" 4 60

# Mutual exclusion
if agent_trylock "shared_resource"; then
    # ... critical section ...
    agent_unlock "shared_resource"
fi

# Leader election
leader=$(agent_elect_leader "workers")
[[ "$leader" == "$_MAINFRAME_AGENT_NAME" ]] && echo "I am the leader"

# Cleanup stale agents
agent_prune --older-than 300
```

---

## Caching & Memoization Functions (cache.sh)

**Purpose**: High-performance caching with function memoization, content-addressable storage, session cache, and LRU eviction. Designed for AI agent workflows with <0.1ms cache hits.

### Function Memoization

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `memoize` | `memoize [--ttl SECS] [--invalidate-on FILE] FUNC [ARGS]` | `memoize --ttl 300 http_get "https://api.com/data"` | Cached result |
| `memoize_clear` | `memoize_clear [PATTERN]` | `memoize_clear "http_get"` | Removed count |
| `memoize_stats` | `memoize_stats [--json]` | `memoize_stats --json` | Hit/miss stats |

### Content-Addressable Store (CAS)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cas_store` | `cas_store "content"` | `hash=$(cas_store "config data")` | SHA-256 hash |
| `cas_get` | `cas_get "hash"` | `content=$(cas_get "$hash")` | Stored content |
| `cas_exists` | `cas_exists "hash"` | `if cas_exists "$hash"; then ...` | (returns 0/1) |
| `cas_gc` | `cas_gc [--older-than DAYS]` | `cas_gc --older-than 30` | Removed count |

### Session Cache (In-Memory)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `session_cache_set` | `session_cache_set KEY VALUE` | `session_cache_set "user" "Gordon"` | (returns 0/1) |
| `session_cache_get` | `session_cache_get KEY [DEFAULT]` | `session_cache_get "user" "unknown"` | Stored value |
| `session_cache_has` | `session_cache_has KEY` | `if session_cache_has "user"; then ...` | (returns 0/1) |
| `session_cache_clear` | `session_cache_clear` | `session_cache_clear` | (clears all) |
| `session_cache_stats` | `session_cache_stats [--json]` | `session_cache_stats --json` | Entry count, bytes |

### Cache Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_invalidate` | `cache_invalidate PATTERN` | `cache_invalidate "expensive_*"` | Removed count |
| `cache_clear` | `cache_clear --force` | `cache_clear --force` | (clears all) |
| `cache_stats` | `cache_stats [--json]` | `cache_stats --json` | Full statistics |
| `cache_max_size` | `cache_max_size SIZE` | `cache_max_size "256MB"` | (sets limit) |
| `cache_evict_lru` | `cache_evict_lru [MAX_MB]` | `cache_evict_lru 100` | Evicted count |
| `cache_warm` | `cache_warm PROJECT_TYPE [DIR]` | `cache_warm "project-type=node"` | (preloads) |

### Dependency-Aware Invalidation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_depends_on` | `cache_depends_on KEY FILE...` | `cache_depends_on "$key" "config.json"` | (registers deps) |
| `cache_check_deps` | `cache_check_deps KEY` | `if cache_check_deps "$key"; then ...` | (returns 0/1) |

### Quick Patterns (Cache)

```bash
# Basic memoization (cache expensive function)
result=$(memoize expensive_compute "arg1" "arg2")

# Memoize with TTL (5 minute expiration)
api_data=$(memoize --ttl 300 curl_json "https://api.example.com/data")

# Dependency-aware caching (invalidate when file changes)
config=$(memoize --invalidate-on config.json parse_config)

# Content-addressable storage (automatic deduplication)
hash=$(cas_store "$(cat large_file.txt)")
content=$(cas_get "$hash")

# Session cache for fast repeated lookups (zero disk I/O)
session_cache_set "parsed_config" "$config_json"
config=$(session_cache_get "parsed_config")

# Cache warming for project
cache_warm "project-type=node" "/path/to/project"

# LRU eviction to stay under size limit
cache_max_size "512MB"

# Check cache statistics
cache_stats --json
# {"hits":150,"misses":23,"hit_ratio_pct":86,...}

# Clear memoized entries by function name
memoize_clear "http_get"

# Garbage collect old CAS entries
cas_gc --older-than 7
```

### Performance Targets

| Operation | Target Latency |
|-----------|----------------|
| Cache hit | <0.1ms |
| Cache miss + compute | compute time + <1ms |
| Session cache (in-memory) | ~0.01ms (zero disk I/O) |

### Storage Location

Default: `${MAINFRAME_CACHE_ROOT:-$HOME/.mainframe/cache}/`

Structure:
- `memo/` - Memoized function results
- `cas/` - Content-addressable store (sharded by hash prefix)
- `locks/` - Concurrency lock files

---

## Format Bridge Functions (bridge.sh)

**Purpose**: Auto-detect data formats and convert between JSON, CSV, YAML, XML, NDJSON, and key-value formats. Pure bash implementation with no external dependencies.

### Format Detection

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_detect` | `bridge_detect "content"` | `bridge_detect '{"a":1}'` | `json` |
| `bridge_detect_file` | `bridge_detect_file "path"` | `bridge_detect_file "data.csv"` | `csv` |

**Detected Formats**: `json`, `csv`, `yaml`, `xml`, `ini`, `ndjson`, `kv`, `unknown`

### JSON <-> CSV Conversions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_json_to_csv` | `echo '[...]' \| bridge_json_to_csv` | `echo '[{"a":1}]' \| bridge_json_to_csv` | `a\n1` |
| `bridge_csv_to_json` | `echo '...' \| bridge_csv_to_json` | `echo 'a\n1' \| bridge_csv_to_json` | `[{"a":1}]` |

### JSON <-> NDJSON Conversions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_json_to_ndjson` | `echo '[...]' \| bridge_json_to_ndjson` | `echo '[{"a":1},{"a":2}]' \| bridge_json_to_ndjson` | `{"a":1}\n{"a":2}` |
| `bridge_ndjson_to_json` | `echo '...' \| bridge_ndjson_to_json` | `echo '{"a":1}\n{"a":2}' \| bridge_ndjson_to_json` | `[{"a":1},{"a":2}]` |

### JSON <-> YAML Conversions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_yaml_to_json` | `echo '...' \| bridge_yaml_to_json` | `echo 'name: John' \| bridge_yaml_to_json` | `{"name":"John"}` |
| `bridge_json_to_yaml` | `echo '...' \| bridge_json_to_yaml` | `echo '{"name":"John"}' \| bridge_json_to_yaml` | `name: John` |

### JSON <-> XML Conversions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_xml_to_json` | `echo '...' \| bridge_xml_to_json` | `echo '<r><a>1</a></r>' \| bridge_xml_to_json` | `{"a":1}` |
| `bridge_json_to_xml` | `echo '...' \| bridge_json_to_xml "root"` | `echo '{"a":1}' \| bridge_json_to_xml "data"` | `<data><a>1</a></data>` |

### Universal Converter

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_convert` | `echo '...' \| bridge_convert "target"` | `cat data.csv \| bridge_convert "json"` | JSON array |

### Schema Extraction

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_schema_extract` | `echo '...' \| bridge_schema_extract` | `echo '[{"a":1}]' \| bridge_schema_extract` | `{"format":"json","fields":{"a":"integer"}}` |

### Quick Patterns (Bridge)

```bash
# Detect format
format=$(bridge_detect "$content")
echo "Format: $format"  # json, csv, yaml, xml, etc.

# Convert CSV to JSON
cat users.csv | bridge_csv_to_json > users.json

# Convert JSON array to NDJSON for streaming
cat data.json | bridge_json_to_ndjson > data.ndjson

# Universal conversion (auto-detects source)
cat config.yaml | bridge_convert "json" > config.json
cat data.csv | bridge_convert "xml" > data.xml

# Extract schema from data
cat records.json | bridge_schema_extract
# {"format":"json","fields":{"name":"string","age":"integer","active":"boolean"}}

# Roundtrip: JSON -> CSV -> JSON
original='[{"name":"John","age":30}]'
csv=$(echo "$original" | bridge_json_to_csv)
restored=$(echo "$csv" | bridge_csv_to_json)
```

### Supported Conversions

| From | To | Method |
|------|-----|--------|
| JSON | CSV, NDJSON, YAML, XML | Direct |
| CSV | JSON, NDJSON, YAML, XML | Direct or via JSON |
| NDJSON | JSON, CSV, YAML, XML | Direct or via JSON |
| YAML | JSON, CSV, NDJSON, XML | Direct or via JSON |
| XML | JSON, CSV, NDJSON, YAML | Direct or via JSON |

---

## Caching & Memoization (cache.sh)

**Purpose**: AI-agent optimized caching with function memoization, command output caching, file content caching with auto-invalidation, and computation caching with dependency tracking.

### Function Memoization (Decorator Style)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `memo_wrap` | `memo_wrap "fn" [ttl]` | `memo_wrap expensive_lookup 300` | Wraps function with caching |
| `memo_unwrap` | `memo_unwrap "fn"` | `memo_unwrap expensive_lookup` | Restores original function |
| `memo_clear` | `memo_clear "fn"` | `memo_clear expensive_lookup` | Clears cache for function |

### Memoize (Call-Style)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `memoize` | `memoize [--ttl N] [--invalidate-on F] fn [args]` | `memoize --ttl 60 my_func arg1 arg2` | Cached function output |
| `memoize_clear` | `memoize_clear [pattern]` | `memoize_clear "my_func"` | Clears matching entries |
| `memoize_stats` | `memoize_stats [--json]` | `memoize_stats --json` | `{"hits":50,"misses":12,...}` |

### Command Output Caching

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_command` | `cache_command TTL cmd [args]` | `cache_command 60 git status --porcelain` | Cached command output |

### File Content Caching

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_file` | `cache_file "path"` | `cache_file "/etc/hosts"` | File contents (cached until modified) |
| `cache_file_invalidate` | `cache_file_invalidate "path"` | `cache_file_invalidate "/etc/hosts"` | Clears file cache |

### Computation Caching

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_compute` | `cache_compute "key" fn [deps...]` | `cache_compute "summary" compute_fn package.json` | Cached result (invalidated when deps change) |

### Content-Addressable Store (CAS)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cas_store` | `cas_store "content"` | `hash=$(cas_store "my data")` | SHA-256 hash |
| `cas_get` | `cas_get "hash"` | `cas_get "$hash"` | Stored content |
| `cas_exists` | `cas_exists "hash"` | `cas_exists "$hash"` | (returns 0/1) |
| `cas_gc` | `cas_gc [--older-than days]` | `cas_gc --older-than 30` | Removed entry count |

### Session Cache (In-Memory)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `session_cache_set` | `session_cache_set "key" "value"` | `session_cache_set "user" "gordon"` | (stores value) |
| `session_cache_get` | `session_cache_get "key" [default]` | `session_cache_get "user" "anon"` | `gordon` or `anon` |
| `session_cache_has` | `session_cache_has "key"` | `session_cache_has "user"` | (returns 0/1) |
| `session_cache_clear` | `session_cache_clear` | `session_cache_clear` | (clears all) |
| `session_cache_stats` | `session_cache_stats [--json]` | `session_cache_stats` | Entry count, memory usage |

### Cache Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_stats` | `cache_stats [--json]` | `cache_stats --json` | `{"hits":100,"misses":20,...}` |
| `cache_stats_reset` | `cache_stats_reset` | `cache_stats_reset` | Resets hit/miss counters |
| `cache_clear` | `cache_clear --force` | `cache_clear --force` | Clears all caches |
| `cache_invalidate` | `cache_invalidate "pattern"` | `cache_invalidate "my_func*"` | Removed entry count |
| `cache_max_size` | `cache_max_size "size"` | `cache_max_size "256MB"` | Sets max cache size |
| `cache_evict_lru` | `cache_evict_lru [max_mb]` | `cache_evict_lru 100` | Evicts oldest entries |

### Prewarming

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_prewarm` | `cache_prewarm "profile"` | `cache_prewarm git` | Pre-caches common operations |
| `cache_warm` | `cache_warm "spec" [dir]` | `cache_warm "project-type=node" .` | Warms for project type |

**Profiles**: `standard`, `git`, `project`, `system`, `all`

### Dependency Tracking

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `cache_depends_on` | `cache_depends_on "key" file...` | `cache_depends_on "$key" config.json` | Registers dependencies |
| `cache_check_deps` | `cache_check_deps "key"` | `cache_check_deps "$key"` | 0=valid, 1=stale |

### Quick Patterns (Cache)

```bash
# Decorator-style memoization
expensive_lookup() {
    curl -sf "http://api.example.com/data/$1"
}
memo_wrap expensive_lookup 300  # Cache for 5 minutes
result=$(expensive_lookup "key")  # Cached

# Command output caching (great for git commands)
status=$(cache_command 5 git status --porcelain)
branch=$(cache_command 300 git branch --show-current)

# File caching with auto-invalidation
config=$(cache_file "config.json")  # Cached until file changes

# Computation with dependency tracking
build_summary() { ... }
summary=$(cache_compute "project_summary" build_summary package.json tsconfig.json)

# Prewarm cache at session start
cache_prewarm git     # Cache git status, branch, commit
cache_prewarm project # Cache package.json, tsconfig.json, etc.

# Check cache performance
cache_stats --json
# {"hits":150,"misses":30,"hit_ratio_pct":83,...}

# Clear cache for specific function
memo_clear expensive_lookup

# Reset counters for new benchmark
cache_stats_reset
```

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MAINFRAME_CACHE_ROOT` | `~/.mainframe/cache` | Cache directory |
| `MAINFRAME_CACHE_MAX_SIZE_MB` | `512` | Max cache size in MB |
| `MAINFRAME_CACHE_DEFAULT_TTL` | `0` | Default TTL (0 = no expiration) |

---

## Savant-Level Debugging (trace.sh)

**Purpose**: Advanced function tracing, variable watching, high-precision timing, session replay, and Mermaid diagram generation. Produces JSON output for AI agent debugging and analysis. All tracing is disabled by default for production safety.

### Control Functions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_enable` | `trace_enable` | `trace_enable` | (enables tracing globally) |
| `trace_disable` | `trace_disable` | `trace_disable` | (disables tracing globally) |
| `trace_is_enabled` | `trace_is_enabled` | `trace_is_enabled && echo "active"` | (returns 0/1) |
| `trace_status` | `trace_status` | `trace_status` | `{"enabled":true,"entries":42,"timers":2,...}` |
| `trace_set_output` | `trace_set_output "path"` | `trace_set_output "/tmp/traces.jsonl"` | (redirects output) |
| `trace_clear` | `trace_clear` | `trace_clear` | (clears all trace data) |

### Function Tracing

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_function` | `trace_function "name"` | `trace_function "process_file"` | (wraps function with timing/args trace) |
| `trace_untrace` | `trace_untrace "name"` | `trace_untrace "process_file"` | (restores original function) |
| `trace_all_in_file` | `trace_all_in_file "path"` | `trace_all_in_file "lib/utils.sh"` | (traces all functions in file) |

### Variable Watching

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_variable` | `trace_variable "var"` | `trace_variable "CONFIG_PATH"` | (watches variable changes via DEBUG trap) |
| `trace_unwatch` | `trace_unwatch "var"` | `trace_unwatch "CONFIG_PATH"` | (stops watching) |
| `trace_snapshot` | `trace_snapshot "name"` | `trace_snapshot "before_deploy"` | (captures all shell variables) |
| `trace_diff` | `trace_diff "snap1" "snap2"` | `trace_diff "before" "after"` | `{"diff":{"added":[],"removed":[],"changed":[...]}}` |

### High-Precision Timing

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_timer_start` | `trace_timer_start "label"` | `trace_timer_start "db_query"` | (starts nanosecond timer) |
| `trace_timer_stop` | `ns=$(trace_timer_stop "label")` | `elapsed=$(trace_timer_stop "db_query")` | `123456789` (nanoseconds) |
| `trace_timing` | `trace_timing "label" cmd [args]` | `trace_timing "fetch" curl -s http://api.com` | (times command, returns its exit code) |

### Output & Visualization

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_to_json` | `trace_to_json` | `all=$(trace_to_json)` | `[{"event":"timer_start",...},...]` |
| `trace_to_mermaid` | `trace_to_mermaid` | `trace_to_mermaid > diagram.md` | Mermaid sequence diagram |

### Session Recording & Replay

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `trace_record_start` | `trace_record_start "session"` | `trace_record_start "deployment"` | (begins recording) |
| `trace_record_stop` | `trace_record_stop` | `trace_record_stop` | (stops recording) |
| `trace_record_command` | `trace_record_command "cmd" [args]` | `trace_record_command "git" "commit" "-m" "msg"` | (records command in session) |
| `trace_replay` | `trace_replay "session"` | `trace_replay "deployment"` | `{"replay_session":"...","events":[...]}` |

### Quick Patterns (Trace)

```bash
# Enable tracing for debugging session
trace_enable
trace_set_output "/tmp/debug_session.jsonl"

# Time critical sections with nanosecond precision
trace_timer_start "database_migration"
run_migration
elapsed_ns=$(trace_timer_stop "database_migration")
echo "Migration took ${elapsed_ns}ns"

# Time commands inline
trace_timing "api_call" curl -sf http://api.example.com/data
# Emits: {"event":"timing","label":"api_call","elapsed_ns":123456789,...}

# Watch variable changes during debugging
trace_variable "DEPLOYMENT_STATUS"
DEPLOYMENT_STATUS="starting"
# Emits: {"event":"var_change","var":"DEPLOYMENT_STATUS","old":"","new":"starting",...}
DEPLOYMENT_STATUS="complete"
# Emits: {"event":"var_change","var":"DEPLOYMENT_STATUS","old":"starting","new":"complete",...}
trace_unwatch "DEPLOYMENT_STATUS"

# Compare environment before/after operation
trace_snapshot "before_install"
npm install
trace_snapshot "after_install"
changes=$(trace_diff "before_install" "after_install")
echo "$changes"  # {"diff":{"added":["NODE_PATH"],"changed":["PATH"],...}}

# Trace all functions in a library
trace_all_in_file "lib/deployment.sh"
source "lib/deployment.sh"
deploy_application "staging"  # All calls automatically traced
# Emits: {"event":"func_entry","func":"deploy_application","args":["staging"],...}
# Emits: {"event":"func_exit","func":"deploy_application","exit_code":0,"duration_s":12.5,...}

# Record and replay sessions
trace_record_start "my_workflow"
trace_record_command "git" "pull" "origin" "main"
trace_record_command "npm" "install"
trace_record_command "npm" "test"
trace_record_stop

# Later: replay to see what was executed
trace_replay "my_workflow"
# {"replay_session":"my_workflow","events":[{"event":"command","cmd":"git",...},...]}

# Generate Mermaid diagram from trace data
trace_to_mermaid
# sequenceDiagram
#     participant Main
#     participant deploy_application
#     Main->>deploy_application: call()
#     deploy_application-->>Main: return

# Export all traces as JSON for AI analysis
all_traces=$(trace_to_json)
echo "$all_traces" | jq '.[] | select(.event == "func_exit" and .duration_s > 1)'

# Disable before production
trace_disable
```

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MAINFRAME_TRACE_ENABLED` | `0` | Set to `1` to enable tracing |
| `MAINFRAME_TRACE_FILE` | `/dev/stderr` | Output destination (file path or `/dev/stderr`) |
| `MAINFRAME_TRACE_MAX_ENTRIES` | `1000` | Max entries to retain in memory |

### JSON Event Types

| Event | Fields | Description |
|-------|--------|-------------|
| `timer_start` | `label`, `timestamp_ns` | Timer started |
| `timer_stop` | `label`, `elapsed_ns`, `timestamp_ns` | Timer stopped |
| `timing` | `label`, `cmd`, `exit_code`, `elapsed_ns` | Command timing |
| `func_entry` | `func`, `args`, `timestamp` | Function called |
| `func_exit` | `func`, `exit_code`, `duration_s`, `timestamp` | Function returned |
| `var_change` | `var`, `old`, `new`, `func`, `file`, `line` | Variable changed |
| `snapshot` | `name`, `timestamp` | Snapshot captured |
| `record_start` | `session`, `timestamp` | Recording started |
| `record_stop` | `session`, `timestamp` | Recording stopped |

---

## Agent Communication Protocol (agent_comm.sh)

**Purpose**: Standardized inter-agent communication for AI collaboration. Provides agent identity management, message passing, status reporting, task coordination, and shared state for multi-agent workflows.

### Agent Identity

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_init` | `agent_init [name]` | `agent_init "worker"` | `{"success":true,"agent_id":"worker_1234_5678",...}` |
| `agent_register` | `agent_register` | `agent_register` | (updates registry) |
| `agent_add_capability` | `agent_add_capability "cap"` | `agent_add_capability "file_processing"` | (adds capability) |
| `agent_remove_capability` | `agent_remove_capability "cap"` | `agent_remove_capability "temp"` | (removes capability) |
| `agent_info` | `agent_info [agent_id]` | `agent_info` | `{"id":"...","pid":1234,...}` |

### Message Passing

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_send` | `agent_send agent type payload` | `agent_send "worker_2" "task" "process file"` | `{"success":true,"message_id":"msg_..."}` |
| `agent_receive` | `agent_receive [timeout]` | `msg=$(agent_receive 30)` | JSON message |
| `agent_peek` | `agent_peek [count]` | `agent_peek 5` | JSON array of messages |
| `agent_broadcast` | `agent_broadcast type payload` | `agent_broadcast "shutdown" "now"` | `{"success":true,"sent":3}` |
| `agent_request` | `agent_request agent type payload [timeout]` | `reply=$(agent_request "srv" "query" "data")` | Reply message or timeout |

### Status Reporting

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_status` | `agent_status status [details]` | `agent_status "working" "processing batch"` | (writes status) |
| `agent_get_status` | `agent_get_status agent_id` | `agent_get_status "worker_1"` | `{"status":"working",...}` |
| `agent_list` | `agent_list` | `agents=$(agent_list)` | `["agent_1","agent_2"]` |
| `agent_find_by_capability` | `agent_find_by_capability "cap"` | `agent_find_by_capability "gpu"` | `["gpu_worker_1"]` |

### Task Coordination

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_create_task` | `agent_create_task id desc [priority]` | `agent_create_task "task_1" "Process data"` | `{"success":true,"task_id":"task_1"}` |
| `agent_claim_task` | `agent_claim_task task_id` | `agent_claim_task "task_1"` | `{"success":true,...}` or fail if claimed |
| `agent_complete_task` | `agent_complete_task id result` | `agent_complete_task "task_1" "done"` | `{"success":true,...}` |
| `agent_fail_task` | `agent_fail_task id error` | `agent_fail_task "task_1" "timeout"` | (releases claim) |
| `agent_wait_task` | `agent_wait_task id [timeout]` | `result=$(agent_wait_task "task_1" 60)` | Task result or timeout |
| `agent_task_status` | `agent_task_status task_id` | `agent_task_status "task_1"` | `{"status":"in_progress",...}` |
| `agent_list_tasks` | `agent_list_tasks [status]` | `agent_list_tasks "pending"` | JSON array of tasks |

### Shared State

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_state_set` | `agent_state_set key value` | `agent_state_set "counter" "10"` | (atomic write) |
| `agent_state_get` | `agent_state_get key [default]` | `agent_state_get "counter" "0"` | Stored value |
| `agent_state_del` | `agent_state_del key` | `agent_state_del "temp"` | (removes key) |
| `agent_state_exists` | `agent_state_exists key` | `agent_state_exists "counter"` | (returns 0/1) |
| `agent_state_incr` | `agent_state_incr key [amount]` | `agent_state_incr "counter" 5` | New value (atomic) |
| `agent_state_decr` | `agent_state_decr key [amount]` | `agent_state_decr "counter" 1` | New value (atomic) |
| `agent_state_list` | `agent_state_list` | `keys=$(agent_state_list)` | `["key1","key2"]` |
| `agent_state_cas` | `agent_state_cas key expected new` | `agent_state_cas "lock" "" "taken"` | (returns 0 if swapped) |

### Cleanup

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_shutdown` | `agent_shutdown` | `agent_shutdown` | `{"success":true,"status":"shutdown"}` |
| `agent_cleanup_dead` | `agent_cleanup_dead` | `cleaned=$(agent_cleanup_dead)` | Number cleaned |
| `agent_cleanup_all` | `agent_cleanup_all` | `agent_cleanup_all` | (removes all agent data) |

### Error Reporting

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_error` | `agent_error "message"` | `agent_error "Connection failed"` | (logs error) |
| `agent_warn` | `agent_warn "message"` | `agent_warn "Slow response"` | (logs warning) |
| `agent_progress` | `agent_progress current total [desc]` | `agent_progress 50 100 "Files"` | `{"percent":50,...}` |

### Quick Patterns (Agent Communication)

```bash
# Initialize agent with capabilities
agent_init "data_processor"
agent_add_capability "csv_parsing"
agent_add_capability "json_transform"
agent_status "idle" "Ready for work"

# Send messages between agents
agent_send "coordinator" "ready" '{"capabilities":["csv","json"]}'
msg=$(agent_receive 30)  # Wait up to 30s for response

# Task coordination (atomic claiming)
agent_create_task "batch_001" "Process CSV files" "high"
if agent_claim_task "batch_001"; then
    # Only one agent can claim this task
    process_files
    agent_complete_task "batch_001" "Processed 150 files"
else
    echo "Task already claimed by another agent"
fi

# Wait for task result
result=$(agent_wait_task "batch_001" 120)
echo "Result: $(json_get "$result" "result")"

# Shared state for coordination
agent_state_set "processing_mode" "parallel"
mode=$(agent_state_get "processing_mode")

# Atomic counter for distributed counting
total=$(agent_state_incr "files_processed" 10)

# Compare-and-swap for locking
if agent_state_cas "global_lock" "" "$AGENT_ID"; then
    # Critical section - only one agent at a time
    do_exclusive_work
    agent_state_set "global_lock" ""  # Release
fi

# Find agents with specific capability
gpu_agents=$(agent_find_by_capability "gpu_compute")
for agent in $(echo "$gpu_agents" | jq -r '.[]'); do
    agent_send "$agent" "gpu_task" "render_frame"
done

# Broadcast to all agents
agent_broadcast "shutdown" "graceful"

# Progress reporting
for i in {1..100}; do
    process_item "$i"
    agent_progress "$i" 100 "Processing items"
done

# Cleanup on exit
trap 'agent_shutdown' EXIT
```

### Architecture

- **Registry**: `/tmp/mainframe_agents/registry/` - Agent registration files
- **Workspaces**: `/tmp/mainframe_agents/{agent_id}/` - Per-agent directories
- **Tasks**: `/tmp/mainframe_agents/tasks/` - Task coordination
- **Shared State**: `/tmp/mainframe_agents/shared_state/` - Key-value store

### Concurrency Guarantees

| Operation | Guarantee |
|-----------|-----------|
| Task claiming | Atomic via `mkdir` (only one agent succeeds) |
| State increment/decrement | Atomic via `flock` |
| Compare-and-swap | Atomic via `flock` |
| Message delivery | File-based (eventual consistency) |

---

## Agent Safety Stack (agent_safety.sh)

**Purpose**: AI agents use bash to control computers. Every operation must be safe, correct the first time, and provide clear feedback to minimize token usage.

### Safe Command Dispatch (NO EVAL)

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `agent_safe_exec` | `agent_safe_exec cmd [args]` | `agent_safe_exec rm -rf "$dir"` | Validated command execution |
| `agent_safe_exec_capture` | `agent_safe_exec_capture cmd [args]` | `agent_safe_exec_capture ls -la` | Execute with JSON output |
| `agent_validate_command` | `agent_validate_command cmd [args]` | `agent_validate_command rm -rf /tmp` | Validate before execution |
| `agent_risk_score` | `score=$(agent_risk_score cmd [args])` | `agent_risk_score rm -rf /etc` | Returns 0-100 risk score |
| `agent_requires_confirmation` | `agent_requires_confirmation cmd [args]` | `agent_requires_confirmation reboot` | Check if high-risk (returns 0/1) |

### Callback Whitelist (NO EVAL)

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `agent_register_callback` | `agent_register_callback "name"` | `agent_register_callback "my_handler"` | Register function for safe invocation |
| `agent_callback` | `agent_callback "name" [args]` | `agent_callback "my_handler" arg1 arg2` | Invoke registered callback safely |
| `agent_unregister_callback` | `agent_unregister_callback "name"` | `agent_unregister_callback "my_handler"` | Remove callback from whitelist |
| `agent_list_callbacks` | `agent_list_callbacks` | `agent_list_callbacks` | List all registered callbacks |

### Structured Error Output (Token-Efficient)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `agent_error` | `agent_error "msg" [context...]` | `agent_error "file not found" "path=/tmp/x"` | JSON error to stderr |
| `agent_success` | `agent_success "msg" [key=val...]` | `agent_success "done" "path=/tmp/x" "action=created"` | JSON success to stdout |
| `agent_result` | `agent_result "key" "val" [type]` | `agent_result "count" "42" "number"` | Typed JSON result |

**Types**: `string` (default), `number`, `bool`, `raw`

### Idempotent Operations

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `agent_ensure_file` | `agent_ensure_file "path" "content" [mode]` | `agent_ensure_file "/tmp/x" "hello" 0644` | Create/update file (idempotent) |
| `agent_ensure_dir` | `agent_ensure_dir "path" [mode]` | `agent_ensure_dir "/tmp/mydir" 0755` | Create directory (idempotent) |
| `agent_ensure_line` | `agent_ensure_line "path" "line"` | `agent_ensure_line "/etc/hosts" "127.0.0.1 myapp"` | Add line to file (idempotent) |
| `agent_ensure_symlink` | `agent_ensure_symlink "link" "target"` | `agent_ensure_symlink "/usr/local/bin/app" "/opt/app/bin"` | Create symlink (idempotent) |
| `agent_ensure_command` | `agent_ensure_command "cmd" [pkg]` | `agent_ensure_command "git" "git"` | Check command exists |

### Audit Trail

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `agent_audit` | `agent_audit "action" [key=val...]` | `agent_audit "file_created" "path=/tmp/x"` | Write JSONL audit entry |
| `agent_audit_replay` | `agent_audit_replay [filter]` | `agent_audit_replay "exec_"` | Replay/filter audit log |
| `agent_audit_clear` | `agent_audit_clear` | `agent_audit_clear` | Clear audit log |
| `agent_audit_path` | `agent_audit_path` | `agent_audit_path` | Get audit log file path |
| `agent_audit_stats` | `agent_audit_stats` | `agent_audit_stats` | JSON statistics |

### Sandbox Profiles

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `agent_set_profile` | `agent_set_profile "profile" [base]` | `agent_set_profile "project" "/home/user/app"` | Set security profile |
| `agent_get_profile` | `agent_get_profile` | `agent_get_profile` | Get current profile JSON |
| `agent_list_profiles` | `agent_list_profiles` | `agent_list_profiles` | List available profiles |

**Profiles**:
- `readonly` - Read files only, no writes
- `project` - Read/write within project base
- `system` - Full system access

### Initialization

| Function | Signature | Example | Purpose |
|----------|-----------|---------|---------|
| `agent_safety_init` | `agent_safety_init [profile] [base]` | `agent_safety_init "project" "$PWD"` | Initialize with profile |
| `agent_safety_cleanup` | `agent_safety_cleanup` | `agent_safety_cleanup` | Cleanup and final audit |

### Configuration Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `AGENT_AUDIT_LOG` | `/tmp/mainframe_agent_$$.audit.jsonl` | Audit log path |
| `AGENT_SAFE_BASE` | `""` | Base directory for path validation |
| `AGENT_CURRENT_PROFILE` | `project` | Current security profile |
| `AGENT_RISK_THRESHOLD` | `50` | Risk score requiring confirmation |

### Quick Patterns (Agent Safety)

```bash
# Initialize agent with project profile
agent_safety_init "project" "$PWD"

# Safe command execution with validation
if agent_safe_exec rm -rf "$build_dir"; then
    agent_success "build directory cleaned" "path=$build_dir"
fi

# Idempotent file creation
agent_ensure_file "$config_file" '{"port": 8080}' 0644
# Output: {"success":true,"message":"file written","data":{"path":"...","action":"created"}}

# Idempotent directory
agent_ensure_dir "$cache_dir" 0755
# Output: {"success":true,"message":"directory exists","data":{"path":"...","action":"none"}}

# Safe callback registration (no eval)
my_handler() { echo "Handling: $1"; }
agent_register_callback "my_handler"
agent_callback "my_handler" "test data"

# Check risk before execution
if agent_requires_confirmation rm -rf /etc; then
    echo "HIGH RISK: requires confirmation"
fi

# Structured error for AI self-correction
agent_error "file not found" "path=/missing/file" "suggestion=Check path exists"
# Output: {"success":false,"error":"file not found","function":"...","context":[...],"timestamp":"..."}

# Audit all actions
agent_audit "deployment_started" "version=1.2.3" "env=production"
agent_audit_stats
# Output: {"entries":15,"size_bytes":2048,"path":"..."}
```

---

## Runtime Introspection (introspect.sh) - NEW v6.0

**Purpose**: Self-discovery API for AI agents to query MAINFRAME's capabilities at runtime.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `mainframe_describe` | `mainframe_describe "func"` | `mainframe_describe "json_object"` | JSON metadata about function |
| `mainframe_signature` | `mainframe_signature "func"` | `mainframe_signature "array_join"` | Function signature string |
| `mainframe_capabilities` | `mainframe_capabilities ["cat"]` | `mainframe_capabilities "json"` | List functions by category |
| `mainframe_search` | `mainframe_search "pattern"` | `mainframe_search "array"` | Search function names/descriptions |
| `mainframe_version` | `mainframe_version` | `mainframe_version` | MAINFRAME version info |

### Quick Patterns (Introspection)

```bash
# Get function metadata (AI agent pattern)
mainframe_describe "json_object"
# {"name":"json_object","library":"json","signature":"json_object key=val...","description":"..."}

# Search for relevant functions
mainframe_search "array sort"
# [{"name":"array_sort",...},{"name":"array_unique",...}]

# List all JSON functions
mainframe_capabilities "json"
# ["json_object","json_array","json_get","json_merge",...]
```

---

## State Persistence (state.sh) - NEW v6.0

**Purpose**: Key-value state management with checkpointing for multi-step agentic workflows.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `state_init` | `state_init "/path" [--ttl N]` | `state_init "/tmp/my_state"` | Initialize state store |
| `state_set` | `state_set "key" "value"` | `state_set "step" "3"` | Set key-value pair |
| `state_get` | `state_get "key" [--default val]` | `state_get "step" --default "1"` | Get value with optional default |
| `state_delete` | `state_delete "key"` | `state_delete "temp_var"` | Delete a key |
| `state_list` | `state_list` | `state_list` | List all keys |
| `state_checkpoint` | `state_checkpoint ["label"]` | `state_checkpoint "pre_deploy"` | Create checkpoint |
| `state_rollback` | `state_rollback ["label"]` | `state_rollback "pre_deploy"` | Rollback to checkpoint |
| `state_history` | `state_history` | `state_history` | Show checkpoint history |
| `state_clear` | `state_clear` | `state_clear` | Clear all keys (keep store) |
| `state_destroy` | `state_destroy` | `state_destroy` | Delete entire state store |

### Quick Patterns (State)

```bash
# Initialize workflow state (path to state directory)
state_init "/tmp/my_workflow"

# Track progress across script restarts
state_set "current_step" "2"
state_set "processed_files" "15"

# Resume from saved state
step=$(state_get "current_step" --default "1")

# Create checkpoint before risky operation
state_checkpoint "before_deploy"

# Rollback on failure
if ! deploy_app; then
    state_rollback "before_deploy"
fi
```

---

## Event/Hook System (events.sh) - NEW v6.0

**Purpose**: Pub/sub events and synchronous hooks for extensibility.

### Hooks (Synchronous)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `hook_on` | `hook_on "name" "callback"` | `hook_on "pre_deploy" "my_fn"` | Register hook handler |
| `hook_off` | `hook_off "name" "callback"` | `hook_off "pre_deploy" "my_fn"` | Remove hook handler |
| `hook_trigger` | `hook_trigger "name" [args...]` | `hook_trigger "pre_deploy" "$ver"` | Execute all handlers |
| `hook_list` | `hook_list "name"` | `hook_list "pre_deploy"` | List handlers for hook |

### Events (Async/Pub-Sub)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `event_on` | `event_on "event" "callback"` | `event_on "file_changed" "reload"` | Subscribe to event |
| `event_off` | `event_off "event" "callback"` | `event_off "file_changed" "reload"` | Unsubscribe |
| `event_emit` | `event_emit "event" [args...]` | `event_emit "file_changed" "$f"` | Emit event to subscribers |
| `event_once` | `event_once "event" "callback"` | `event_once "ready" "init"` | One-time subscription |
| `event_list` | `event_list "event"` | `event_list "file_changed"` | List subscribers |

### Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `events_enable_logging` | `events_enable_logging` | `events_enable_logging` | Enable debug logging |
| `events_disable_logging` | `events_disable_logging` | `events_disable_logging` | Disable debug logging |
| `events_clear_all` | `events_clear_all` | `events_clear_all` | Clear all hooks/events |

### Quick Patterns (Events)

```bash
# Hook pattern - synchronous middleware
pre_deploy_check() { echo "Checking $1..."; }
hook_on "pre_deploy" "pre_deploy_check"
hook_trigger "pre_deploy" "v1.2.3"

# Event pattern - pub/sub notifications
on_file_change() { echo "File changed: $1"; }
event_on "file:changed" "on_file_change"
event_emit "file:changed" "/path/to/file"

# One-time handler
event_once "app:ready" "run_migrations"
event_emit "app:ready"  # Runs once, then auto-removes
```

---

## Testing/Mocking Framework (testing.sh) - NEW v6.0

**Purpose**: Unit testing primitives with function mocking and fixtures.

### Mocking

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `mock_function` | `mock_function "func" "response"` | `mock_function "http_get" "data"` | Mock a function |
| `mock_function_restore` | `mock_function_restore "func"` | `mock_function_restore "http_get"` | Restore original |
| `mock_function_restore_all` | `mock_function_restore_all` | `mock_function_restore_all` | Restore all mocks |
| `mock_call_count` | `mock_call_count "func"` | `mock_call_count "http_get"` | Number of calls |
| `mock_last_args` | `mock_last_args "func"` | `mock_last_args "http_get"` | Last call arguments |

### Environment Mocking

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `mock_env` | `mock_env "VAR" "value"` | `mock_env "API_KEY" "test"` | Mock env variable |
| `mock_env_restore` | `mock_env_restore "VAR"` | `mock_env_restore "API_KEY"` | Restore original |
| `mock_env_restore_all` | `mock_env_restore_all` | `mock_env_restore_all` | Restore all env |

### Assertions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `assert_equals` | `assert_equals "exp" "got" ["msg"]` | `assert_equals "5" "$x"` | Pass if equal |
| `assert_not_equals` | `assert_not_equals "a" "b"` | `assert_not_equals "" "$x"` | Pass if different |
| `assert_contains` | `assert_contains "hay" "needle"` | `assert_contains "$out" "OK"` | Pass if substring |
| `assert_empty` | `assert_empty "val"` | `assert_empty "$err"` | Pass if empty |
| `assert_not_empty` | `assert_not_empty "val"` | `assert_not_empty "$out"` | Pass if non-empty |
| `assert_exit_code` | `assert_exit_code exp cmd...` | `assert_exit_code 0 true` | Check exit code |
| `assert_file_exists` | `assert_file_exists "path"` | `assert_file_exists "$f"` | Pass if file exists |
| `assert_file_contains` | `assert_file_contains "f" "str"` | `assert_file_contains "$f" "ok"` | Check file content |
| `assert_true` | `assert_true cmd...` | `assert_true [[ -f $f ]]` | Pass if exit 0 |
| `assert_false` | `assert_false cmd...` | `assert_false [[ -f $f ]]` | Pass if exit non-0 |

### Fixtures

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `fixture_tempdir` | `fixture_tempdir ["name"]` | `d=$(fixture_tempdir "test")` | Create temp directory |
| `fixture_tempfile` | `fixture_tempfile ["name"] ["content"]` | `f=$(fixture_tempfile "cfg" "{}")` | Create temp file |
| `fixture_cleanup` | `fixture_cleanup` | `fixture_cleanup` | Clean up all fixtures |

### Test Structure

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `test_start` | `test_start "name"` | `test_start "test_json_parse"` | Begin test |
| `test_end` | `test_end` | `test_end` | End test (report result) |
| `test_summary` | `test_summary` | `test_summary` | Print test summary |
| `test_reset` | `test_reset` | `test_reset` | Reset test state |

### Quick Patterns (Testing)

```bash
# Basic test structure
test_start "test_array_sort"
result=$(array_sort c a b)
assert_equals "a b c" "$result"
test_end

# Mock external commands
mock_function "http_get" '{"status":"ok"}'
result=$(my_function_that_calls_http)
assert_contains "$result" "ok"
assert_equals 1 $(mock_call_count "http_get")
mock_function_restore "http_get"

# Fixture for temp files
tmpdir=$(fixture_tempdir "mytest")
echo "data" > "$tmpdir/input.txt"
# ... run tests ...
fixture_cleanup

# Full test suite
test_reset
test_start "test1"; assert_equals "a" "a"; test_end
test_start "test2"; assert_true true; test_end
test_summary
# Output: Tests: 2 passed, 0 failed
```

---

## Execution Sandboxing (sandbox.sh) - NEW v6.0

**Purpose**: Filesystem restriction layer for autonomous agent execution.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `sandbox_enable` | `sandbox_enable` | `sandbox_enable` | Enable sandbox mode |
| `sandbox_disable` | `sandbox_disable` | `sandbox_disable` | Disable sandbox |
| `sandbox_allow_write` | `sandbox_allow_write "path"` | `sandbox_allow_write "$PWD"` | Whitelist path for writes |
| `sandbox_deny_write` | `sandbox_deny_write "path"` | `sandbox_deny_write "/etc"` | Blacklist path |
| `sandbox_deny_network` | `sandbox_deny_network` | `sandbox_deny_network` | Block network commands |
| `sandbox_allow_network` | `sandbox_allow_network` | `sandbox_allow_network` | Allow network commands |
| `sandbox_exec` | `sandbox_exec cmd [args]` | `sandbox_exec rm -rf "$dir"` | Execute with checks |
| `sandbox_write` | `sandbox_write "path" "content"` | `sandbox_write "$f" "data"` | Safe file write |
| `sandbox_mkdir` | `sandbox_mkdir "path"` | `sandbox_mkdir "$dir"` | Safe mkdir |
| `sandbox_rm` | `sandbox_rm "path"` | `sandbox_rm "$tmpfile"` | Safe remove |
| `sandbox_status` | `sandbox_status` | `sandbox_status` | Show sandbox state |
| `sandbox_check` | `sandbox_check "op" "path"` | `sandbox_check write "/tmp/f"` | Check if operation allowed |
| `sandbox_audit_log` | `sandbox_audit_log` | `sandbox_audit_log` | Show audit log |

### Quick Patterns (Sandbox)

```bash
# Enable sandbox with restricted writes
sandbox_enable
sandbox_allow_write "$PWD/output"
sandbox_allow_write "/tmp"
sandbox_deny_write "/etc"
sandbox_deny_write "$HOME/.ssh"

# Safe execution - blocked writes are rejected
sandbox_write "/etc/passwd" "hacked"  # Returns 1, logged
sandbox_write "$PWD/output/result.txt" "data"  # OK

# Execute commands through sandbox
sandbox_exec rm -rf "$build_dir"  # Checked against allow/deny lists

# Check before write (op_type: write, exec, network)
if sandbox_check write "$target_path"; then
    sandbox_write "$target_path" "$content"
fi

# Review what was blocked
sandbox_audit_log
# Shows all denied operations
```

---

## Task Graphs (taskgraph.sh) - NEW v6.0

**Purpose**: Declarative task DAG with dependency resolution and parallel execution.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `task_define` | `task_define "name" "cmd" ["deps"]` | `task_define "build" "./build.sh" "lint test"` | Define task with dependencies |
| `task_run` | `task_run "name"` | `task_run "build"` | Run single task |
| `task_run_graph` | `task_run_graph ["root"]` | `task_run_graph "deploy"` | Run task DAG (topo sort) |
| `task_status` | `task_status` | `task_status` | Show all task statuses |
| `task_reset` | `task_reset ["name"]` | `task_reset "build"` | Reset task(s) to pending |
| `task_clear` | `task_clear` | `task_clear` | Clear all tasks |
| `task_list` | `task_list` | `task_list` | List all tasks |
| `task_output` | `task_output "name"` | `task_output "test"` | Get task stdout |
| `task_graph` | `task_graph` | `task_graph` | Show dependency graph |

### Task Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Not yet started |
| `running` | Currently executing |
| `completed` | Finished successfully |
| `failed` | Execution failed |
| `skipped` | Skipped (dependency failed) |

### Quick Patterns (Task Graph)

```bash
# Define a build pipeline DAG
task_define "lint" "npm run lint"
task_define "test" "npm test" "lint"
task_define "build" "./scripts/build.sh" "lint test"
task_define "deploy" "./scripts/deploy.sh" "build"

# Run full graph (respects dependencies)
task_run_graph "deploy"
# Execution order: lint -> test -> build -> deploy

# Check status (via internal array)
status="${_TASK_STATUS[build]}"  # "completed" or "failed"

# Get output from a task
build_output=$(task_output "build")

# Visualize graph
task_graph
# lint -> test -> build -> deploy

# Reset and re-run
task_reset
task_run_graph "deploy"
```

---

## USOP v3.0 Additions (output.sh) - NEW v6.0

**Purpose**: Enhanced structured output for AI agent consumption.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `usop_result` | `usop_result "data" ["meta"]` | `usop_result "done" "step=3"` | Standard result envelope |
| `usop_progress` | `usop_progress cur total ["msg"]` | `usop_progress 5 10 "files"` | Progress update |
| `usop_error_retryable` | `usop_error_retryable "code" "msg"` | `usop_error_retryable "TIMEOUT" "API slow"` | Retryable error |
| `usop_error_permanent` | `usop_error_permanent "code" "msg"` | `usop_error_permanent "INVALID" "Bad input"` | Non-retryable error |
| `usop_warning` | `usop_warning "msg" ["details"]` | `usop_warning "Deprecated API"` | Warning message |
| `usop_log` | `usop_log "level" "msg"` | `usop_log "info" "Starting"` | Structured log |
| `usop_debug` | `usop_debug "msg"` | `usop_debug "Variable=$x"` | Debug log |
| `usop_info` | `usop_info "msg"` | `usop_info "Processing..."` | Info log |
| `usop_warn` | `usop_warn "msg"` | `usop_warn "Slow response"` | Warning log |
| `usop_fatal` | `usop_fatal "msg"` | `usop_fatal "Cannot continue"` | Fatal error (exits) |

### Quick Patterns (USOP v3.0)

```bash
export MAINFRAME_OUTPUT=json

# Standard result
usop_result "Operation completed" "items_processed=42"
# {"ok":true,"data":"Operation completed","meta":{"items_processed":"42"}}

# Progress tracking for long operations
for i in {1..10}; do
    usop_progress $i 10 "Processing file $i"
    process_file $i
done
# {"type":"progress","current":5,"total":10,"percent":50,"message":"Processing file 5"}

# Error classification for AI retry logic
if ! api_call; then
    usop_error_retryable "API_TIMEOUT" "Request timed out after 30s"
    # {"ok":false,"error":{"code":"API_TIMEOUT","msg":"...","retryable":true}}
fi

# Permanent errors (no retry)
usop_error_permanent "INVALID_INPUT" "Email format invalid"
# {"ok":false,"error":{"code":"INVALID_INPUT","msg":"...","retryable":false}}

# Structured logging
usop_info "Starting deployment"
usop_debug "Config loaded: $config_path"
usop_warn "Using deprecated API version"
```

---

*2,100+ functions | 49 libraries | Zero dependencies | 20-72x faster*

**YO JOE!**

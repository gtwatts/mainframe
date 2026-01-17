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

*397 functions | 11 libraries | Zero dependencies | 20-72x faster*

**YO JOE!**

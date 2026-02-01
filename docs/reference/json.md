# JSON Functions

JSON creation, parsing, and manipulation.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

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

### json_object Type Modifiers

- `key=value` - string
- `key:number=value` - number
- `key:bool=value` - boolean
- `key:null=` - null

---

## Universal Structured Output Protocol (output.sh)

Enables MAINFRAME functions to output structured JSON envelopes for AI agents.

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

---

## Output Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `raw` | Plain text (default) | Human-readable scripts |
| `json` | Full envelope with meta/hint | AI agent consumption |
| `minimal` | Compact JSON (ok+data only) | Low-bandwidth scenarios |
| `debug` | JSON + timestamp + caller | Debugging agent behavior |

---

## Quick Patterns

### Set JSON output mode
```bash
export MAINFRAME_OUTPUT=json

# Simple success response
output_success "operation completed" "check_status"
# {"ok":true,"data":"operation completed","hint":"check_status"}

# Error with suggestion
output_error "E_FILE_NOT_FOUND" "Config file missing" "run init first"
# {"ok":false,"error":{"code":"E_FILE_NOT_FOUND","msg":"Config file missing","suggestion":"run init first"}}
```

### Typed Outputs
```bash
output_int 42              # {"ok":true,"data":42}
output_bool true           # {"ok":true,"data":true}
output_json_object '{"name":"John","age":30}'
# {"ok":true,"data":{"name":"John","age":30}}
```

### Timing
```bash
output_timer_start
do_expensive_operation
output_success "done"  # Includes meta.elapsed_ms
```

### Wrap existing function
```bash
my_func() { echo "result"; }
output_wrap my_func
# {"ok":true,"data":"result","meta":{"elapsed_ms":2}}
```

### Performance: avoid subshell with nameref
```bash
output_v result "computed value"
echo "$result"  # {"ok":true,"data":"computed value"}
```

### Temporarily change mode
```bash
export MAINFRAME_OUTPUT=raw
result=$(output_with_mode "json" output_success "data")
# result contains JSON, but mode returns to raw
```

---

## Format Bridge Functions (bridge.sh)

Auto-detect data formats and convert between JSON, CSV, YAML, XML, NDJSON.

### Format Detection

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_detect` | `bridge_detect "content"` | `bridge_detect '{"a":1}'` | `json` |
| `bridge_detect_file` | `bridge_detect_file "path"` | `bridge_detect_file "data.csv"` | `csv` |

**Detected Formats**: `json`, `csv`, `yaml`, `xml`, `ini`, `ndjson`, `kv`, `unknown`

### Conversions

| Function | Signature | Example |
|----------|-----------|---------|
| `bridge_json_to_csv` | `echo '[...]' \| bridge_json_to_csv` | Convert JSON array to CSV |
| `bridge_csv_to_json` | `echo '...' \| bridge_csv_to_json` | Convert CSV to JSON array |
| `bridge_json_to_ndjson` | `echo '[...]' \| bridge_json_to_ndjson` | Array to line-delimited |
| `bridge_ndjson_to_json` | `echo '...' \| bridge_ndjson_to_json` | Line-delimited to array |
| `bridge_yaml_to_json` | `echo '...' \| bridge_yaml_to_json` | YAML to JSON |
| `bridge_json_to_yaml` | `echo '...' \| bridge_json_to_yaml` | JSON to YAML |
| `bridge_xml_to_json` | `echo '...' \| bridge_xml_to_json` | XML to JSON |
| `bridge_json_to_xml` | `echo '...' \| bridge_json_to_xml "root"` | JSON to XML |
| `bridge_convert` | `echo '...' \| bridge_convert "target"` | Universal converter |

### Schema Extraction

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `bridge_schema_extract` | `echo '...' \| bridge_schema_extract` | `echo '[{"a":1}]' \| bridge_schema_extract` | `{"format":"json","fields":{"a":"integer"}}` |

### Quick Patterns (Bridge)
```bash
# Detect format
format=$(bridge_detect "$content")

# Convert CSV to JSON
cat users.csv | bridge_csv_to_json > users.json

# Universal conversion
cat config.yaml | bridge_convert "json" > config.json

# Extract schema from data
cat records.json | bridge_schema_extract
```

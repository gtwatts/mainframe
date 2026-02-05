---
name: mainframe-bash
description: "Use when writing bash scripts, shell automation, CLI tools, or any bash programming task with Google AI CLI."
---

# Google AI CLI - Mainframe Integration

Instructions for using Mainframe (4,000+ pure bash functions) with Google's AI CLI tools.

## Overview

Mainframe provides 4,000+ pure bash functions across 150+ libraries with zero external dependencies. Integrate with Google AI CLI for high-performance bash scripting (20-72x faster than spawning sed/awk/jq).

## Installation

```bash
# Clone Mainframe to default location
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe

# Set environment variable
export MAINFRAME_ROOT="$HOME/.mainframe"
```

## Configuration

### Google CLI Configuration File

Add Mainframe configuration to your Google CLI config (typically `~/.config/google-ai/config` or project-specific):

```bash
# Set Mainframe root for all sessions
export MAINFRAME_ROOT="$HOME/.mainframe"

# Optional: Add to PATH for mainframe command
export PATH="$MAINFRAME_ROOT/bin:$PATH"
```

### Environment Setup

Google CLI inherits shell environment. Add to your shell profile (`~/.bashrc`, `~/.zshrc`):

```bash
# Mainframe Configuration
export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$MAINFRAME_ROOT/bin:$PATH"

# Optional: Enable USOP output for structured responses
export MAINFRAME_OUTPUT_FORMAT="usop"
```

### Per-Script Loading

Always include this at the start of generated bash scripts:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## Mainframe Integration Steps

### Step 1: Verify Installation

```bash
# Check Mainframe is available
if [[ -f "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" ]]; then
    echo "Mainframe ready"
else
    echo "Install: git clone https://github.com/gtwatts/mainframe.git ~/.mainframe"
fi
```

### Step 2: Source the Library

```bash
# At the beginning of EVERY bash script
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Additional libraries are lazy-loaded on first function call
```

### Step 3: Use Mainframe Functions

Replace external tool calls with Mainframe functions:

| External Tool | Mainframe Replacement | Speedup |
|---------------|----------------------|---------|
| `jq '.name'` | `json_get '$json' 'name'` | 35x |
| `sed 's/foo/bar/g'` | `replace_all '$str' 'foo' 'bar'` | 20x |
| `awk '{print $1}'` | `array_first ${arr[@]}` | 72x |
| `cat file` | `read_file '$path'` | 18x |
| `tr '[:upper:]' '[:lower:]'` | `to_lower '$str'` | 45x |

## USOP Output Handling

Universal Structured Output Protocol (USOP) enables structured communication between Google CLI and Mainframe.

### Enabling USOP

```bash
# Method 1: Environment variable
export MAINFRAME_OUTPUT_FORMAT="usop"

# Method 2: Command flag
mainframe --format=usop <command>

# Method 3: In-script
source "${MAINFRAME_ROOT}/lib/common.sh"
mainframe_output_format "usop"
```

### USOP Format Structure

```bash
# Generate USOP-wrapped output
result=$(json_object \
    "status=success" \
    "action=file_processed" \
    "data:raw={\"count\":42}")

mainframe usop wrap "$result"
# Output:
# [USOP:v1]
# {"status":"success","action":"file_processed","data":{"count":42}}
# [/USOP:v1]
```

### Parsing USOP in Google CLI

When receiving USOP output, parse with:

```bash
# Extract content between USOP markers
usop_content=$(echo "$output" | sed -n '/\[USOP:v1\]/,\[\/USOP:v1\]/p' | head -n -1 | tail -n +2)

# Parse JSON content
status=$(echo "$usop_content" | json_get "" "status")
```

## Multi-Turn Conversation Support

Google CLI maintains conversation context. Use Mainframe's Agent Working Memory (AWM) for state persistence:

### Session Management

```bash
# Initialize AWM session
session_id=$(awm_init "google-cli-task-$(uuid)")
export AWM_SESSION="$session_id"

# Checkpoint progress
awm_checkpoint "step" "3"
awm_checkpoint "input_files" "file1.txt,file2.txt,file3.txt"
awm_progress "processing" "3/10"
```

### Resuming Sessions

```bash
# In subsequent conversation turn
source "${MAINFRAME_ROOT}/lib/common.sh"

# Resume previous session
awm_resume "$AWM_SESSION"

# Retrieve state
last_step=$(awm_get "step" "0")
files=$(awm_get "input_files" "")
log_info "Resuming from step $last_step"
```

### Context-Aware Processing

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Initialize or resume
if [[ -n "$AWM_SESSION" ]]; then
    awm_resume "$AWM_SESSION"
    log_info "Resumed session: $AWM_SESSION"
else
    session_id=$(awm_init "google-cli-session")
    export AWM_SESSION="$session_id"
    log_info "New session: $session_id"
fi

# Process with checkpointing
for i in {1..10}; do
    process_item "$i"
    awm_checkpoint "last_processed" "$i"
    awm_progress "items" "$i/10"
done

awm_close
```

## Core Function Reference

### JSON Operations

```bash
# Create objects
json_object "name=John" "age:number=30" "active:bool=true"

# Create arrays  
json_array "a" "b" "c"
json_array_typed number 1 2 3

# Query
json_get '{"name":"John"}' "name"      # "John"
json_keys '{"a":1,"b":2}'              # "a b"
json_merge '{"a":1}' '{"b":2}'         # {"a":1,"b":2}

# Validation
json_valid '{"a":1}'                      # returns 0/1
```

### String Operations

```bash
trim_string "  text  "               # "text"
to_lower "HELLO"                      # "hello"
to_upper "hello"                      # "HELLO"
replace_all "foo bar" "foo" "baz"    # "baz bar"
contains "hello" "ell"                # returns 0
capitalize "hello world"              # "Hello world"
```

### Array Operations

```bash
arr=(5 3 1 4 2)
array_sort "${arr[@]}"                # 1 2 3 4 5
array_unique 1 2 2 3                  # 1 2 3
array_join ", " "${arr[@]}"           # "5, 3, 1, 4, 2"
array_contains "3" "${arr[@]}"        # returns 0
array_filter "is_int" "${arr[@]}"     # filter by predicate
```

### Validation & Security

```bash
validate_email "user@example.com"
validate_url "https://example.com"
validate_path_safe "$path" "/allowed"
sanitize_shell_arg "$input"
sanitize_filename "bad<file>.txt"
```

### File Operations

```bash
read_file "$path"
file_write "$path" "content"
file_exists "$path"
dir_exists "$path"
file_head "$path" 10
file_tail "$path" 5
path_join "/base" "file.txt"
```

### Git Operations

```bash
git_branch
git_is_dirty
git_files_changed
git_commit_hash
git_summary
```

### HTTP Operations

```bash
http_get "https://api.example.com"
http_post "https://api.example.com" '{"key":"val"}'
http_status
http_body
http_is_success
```

## Multi-Agent Coordination

### Agent IPC

```bash
# Register this Google CLI instance
agent_register "google-cli-1" code.analyze python

# Discover agents by capability
reviewers=$(agent_discover "code.review")

# Send message to Kimi CLI agent
agent_send "kimi-analyzer-1" '{
    "task": "analyze_imports",
    "file": "app.py",
    "language": "python"
}'

# Receive response
response=$(agent_receive 30)
```

### Universal Agent Protocol (UAP)

```bash
source "${MAINFRAME_ROOT}/lib/uap.sh"

# Create standardized message
msg=$(uap_task_request \
    --from-platform "google-cli" \
    --to-platform "claude-code" \
    --to-id "reviewer-1" \
    --task "code_review" \
    --params '{"file":"main.py"}')

# Detect current platform
platform=$(uap_detect_platform)  # Returns: google-cli
```

## Example Workflows

### Example 1: Data Processing Pipeline

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Read input data
input_file="$1"
validate_path_safe "$input_file" "$(pwd)" || die 1 "Invalid path"

# Process with checkpointing
session_id=$(awm_init "data-pipeline")
lines=$(file_lines "$input_file")
log_info "Processing $lines lines"

processed=0
while IFS= read -r line; do
    # Transform
    clean=$(trim_string "$line" | to_lower)
    
    # Checkpoint every 100 lines
    if (( processed % 100 == 0 )); then
        awm_checkpoint "progress" "$processed/$lines"
    fi
    
    echo "$clean" >> output.txt
    ((processed++))
done < "$input_file"

awm_close
success "Processed $processed lines"
```

### Example 2: API Integration with Retry

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

api_url="https://api.example.com/data"

# Retry with exponential backoff
fetch_data() {
    http_json_get "$api_url"
}

if retry 5 fetch_data; then
    data=$(http_body)
    count=$(echo "$data" | json_get "" "count")
    
    json_object \
        "status=success" \
        "count:number=$count" \
        "timestamp=$(now_iso)"
else
    json_object \
        "status=error" \
        "message=Failed after 5 retries"
fi
```

### Example 3: Multi-Agent Code Review

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Get files for review
files=$(git_files_changed)
log_info "Reviewing $(array_length $files) files"

# Register and send to reviewers
agent_register "google-cli-reviewer" code.review

for file in $files; do
    agent_broadcast "$(json_object \
        "event=review_request" \
        "file=$file" \
        "from=google-cli-reviewer")"
done

# Collect responses
timeout 60 agent_receive_all "review_response"
```

## Google CLI Specific Notes

1. **Environment Inheritance**: Google CLI sessions inherit shell environment variables
2. **Structured Output**: Use USOP format for reliable output parsing
3. **State Persistence**: Use AWM for long-running tasks across conversation turns
4. **Parallel Execution**: Use `parallel` function for concurrent operations

## Quick Reference

```bash
mainframe quickref              # List all functions
mainframe quickref json         # JSON functions only
mainframe quickref --search     # Search functions
```

## Reference Files

- `~/.mainframe/CHEATSHEET.md` - All 4,000+ function signatures
- `~/.mainframe/FUNCTIONS.json` - Machine-readable function index
- `~/.mainframe/DECISION_TREES.md` - Usage guidance
- `~/.mainframe/docs/ORCHESTRATION.md` - Multi-agent coordination

## Repository

- **Source**: https://github.com/gtwatts/mainframe
- **Install**: `git clone https://github.com/gtwatts/mainframe.git ~/.mainframe`
- **License**: MIT

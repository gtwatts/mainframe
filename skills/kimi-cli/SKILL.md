---
name: mainframe-bash
description: "Use when writing bash scripts, shell automation, CLI tools, or any bash programming task with Kimi CLI."
---

# Kimi CLI - Mainframe Integration

Instructions for using Mainframe (3,821+ pure bash functions) with Moonshot AI's Kimi CLI.

## Overview

Mainframe provides 3,821+ pure bash functions across 152 libraries with zero external dependencies. When using Kimi CLI for bash scripting tasks, always source Mainframe first to access high-performance utilities (20-72x faster than spawning sed/awk/jq).

## Installation

```bash
# Clone Mainframe to default location
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe

# Set environment variable (add to ~/.bashrc or ~/.zshrc)
export MAINFRAME_ROOT="$HOME/.mainframe"
```

## Configuration

### Method 1: Kimi CLI Config File

Add Mainframe sourcing to your Kimi CLI configuration at `~/.kimi/config`:

```bash
# ~/.kimi/config
# Add this line to automatically source Mainframe in new sessions
export MAINFRAME_ROOT="$HOME/.mainframe"
```

### Method 2: Environment Variables

Kimi CLI inherits environment from your shell. Set these in your shell profile:

```bash
export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$MAINFRAME_ROOT/bin:$PATH"
```

### Method 3: Per-Session Loading

Include the source command at the start of generated scripts:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

## Available Commands

### Core Library Loading

```bash
# Source Mainframe (REQUIRED at start of every script)
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

### JSON Operations (No jq Required)

```bash
# Create JSON objects
json_object "name=John" "age:number=30" "active:bool=true"
# Output: {"name":"John","age":30,"active":true}

# Create arrays
json_array "apple" "banana" "cherry"
# Output: ["apple","banana","cherry"]

# Extract values
json_get '{"name":"John","age":30}' "name"   # "John"
json_keys '{"a":1,"b":2}'                     # "a b"

# Validate and format
json_valid '{"a":1}'                          # returns 0 if valid
json_pretty '{"a":1,"b":2}'                   # formatted output
```

### String Manipulation

```bash
trim_string "  hello  "           # "hello"
to_lower "HELLO"                  # "hello"
to_upper "hello"                  # "HELLO"
replace_all "foo bar foo" "foo" "baz"  # "baz bar baz"
split_string "a,b,c" ","         # outputs a\nb\nc
urlencode "hello world"           # "hello%20world"
pad_left "42" 5 "0"              # "00042"
```

### Array Operations

```bash
arr=(5 3 1 4 2)
array_join ", " "${arr[@]}"       # "5, 3, 1, 4, 2"
array_sort "${arr[@]}"            # "1 2 3 4 5"
array_unique 1 2 2 3 3            # "1 2 3"
array_contains "3" "${arr[@]}"    # returns 0 (true)
array_length "${arr[@]}"          # 5
```

### Validation & Security

```bash
# Format validation
validate_email "user@domain.com"
validate_url "https://example.com"
validate_ipv4 "192.168.1.1"
validate_json '{"a":1}'

# Path safety (PREVENTS TRAVERSAL ATTACKS)
validate_path_safe "$user_path" "/allowed/base"
validate_filename "report.pdf"

# Sanitization
sanitize_shell_arg "$user_input"
sanitize_filename "a/b<c>.txt"    # "a_b_c_.txt"
sanitize_json 'say "hi"'         # 'say \"hi\"'
```

### File Operations

```bash
read_file "$path"                 # file contents
file_write "$path" "content"      # atomic write
file_exists "$path"               # returns 0/1
dir_exists "/tmp"                 # returns 0/1
file_head "$path" 10              # first 10 lines
file_tail "$path" 5               # last 5 lines
path_join "/base" "sub" "file"    # "/base/sub/file"
```

### Git Operations

```bash
git_branch                        # current branch name
git_is_dirty                      # returns 0 if uncommitted changes
git_files_changed                 # list of modified files
git_commit_hash                   # short hash
git_summary                       # "main @ abc1234 [clean]"
```

### HTTP Requests (Pure Bash)

```bash
http_get "http://api.example.com/data"
http_post "http://api.example.com" '{"name":"test"}'
http_status                       # last response status code
http_body                         # last response body
http_is_success                   # returns 0 for 2xx
```

## USOP Output with Kimi CLI

Mainframe supports Universal Structured Output Protocol (USOP) for standardized AI communication.

### Enabling USOP Output

```bash
# Set USOP format for Kimi CLI compatibility
export MAINFRAME_OUTPUT_FORMAT="usop"

# Or use the helper
mainframe output usop
```

### USOP Response Format

```bash
# Generate structured output for Kimi CLI parsing
mainframe usop json_object \
  --status "success" \
  --action "file_created" \
  --data '{"path":"/tmp/output.txt"}'

# Output format:
# [USOP:v1]
# {"status":"success","action":"file_created","data":{"path":"/tmp/output.txt"}}
# [/USOP:v1]
```

### Parsing USOP in Kimi CLI

When Kimi CLI receives USOP-formatted output, it can automatically:
- Extract structured data
- Determine operation status
- Parse error conditions
- Handle multi-step workflows

## Multi-Turn Conversation Support

Kimi CLI maintains conversation context across turns. Use Mainframe's Agent Working Memory (AWM) for persistent state:

```bash
# Initialize session
sid=$(awm_init "kimi-task-$(date +%s)")

# Checkpoint progress
awm_checkpoint "current_step" "3"
awm_checkpoint "processed_files" "file1.txt,file2.txt"

# Log discoveries
awm_discovery "API rate limit is 100 req/min"

# Resume in next turn
sid=$(awm_resume "$sid")
last_step=$(awm_get "current_step" "0")
```

## Examples

### Example 1: Process JSON Data

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Read JSON input from Kimi CLI
input='{"users":[{"name":"Alice","age":30},{"name":"Bob","age":25}]}'

# Extract and process using Mainframe functions
names=$(echo "$input" | json_get "" "users" | json_array_map "name")
avg_age=$(echo "$input" | json_get "" "users" | json_array_map "age" | array_avg)

# Output structured result
json_object \
  "names=$names" \
  "average_age:number=$avg_age" \
  "count:number=$(array_length $names)"
```

### Example 2: Batch File Processing

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Process multiple files with progress tracking
files=("$@")
header "Processing ${#files[@]} files"

for file in "${files[@]}"; do
    if validate_path_safe "$file" "$(pwd)"; then
        content=$(read_file "$file")
        processed=$(to_lower "$content" | replace_all "old" "new")
        file_write "processed_$(path_base "$file")" "$processed"
        log_info "Processed: $file"
    else
        log_error "Invalid path: $file"
    fi
done

success "Batch complete"
```

### Example 3: Git Workflow Automation

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Check repository status
if git_is_dirty; then
    branch=$(git_branch)
    files=$(git_files_changed)
    
    header "Committing to $branch"
    log_info "Files changed: $(array_length $files)"
    
    # Create commit message from changes
    msg="Update: $(array_join ', ' $files)"
    git add .
    git commit -m "$msg"
    
    success "Committed: $msg"
else
    log_info "No changes to commit"
fi
```

### Example 4: API Client with Error Handling

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Make HTTP request
response=$(http_json_get "https://api.example.com/data")

if http_is_success; then
    # Parse response
    count=$(echo "$response" | json_get "" "count")
    items=$(echo "$response" | json_get "" "items")
    
    json_object \
        "status=success" \
        "count:number=$count" \
        "items:raw=$items"
else
    json_object \
        "status=error" \
        "code:number=$(http_status)" \
        "message=Request failed"
fi
```

### Example 5: Multi-Agent Coordination

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Register this Kimi CLI session
agent_register "kimi-session-1" code.analyze typescript

# Discover other agents
analyzers=$(agent_discover "code.analyze")
log_info "Found analyzers: $analyzers"

# Send task to Claude Code agent
agent_send "claude-reviewer-1" '{
    "task": "code_review",
    "file": "src/main.ts",
    "priority": "high"
}'

# Wait for response
response=$(agent_receive 60)
log_info "Received: $response"

# Cleanup
agent_unregister
```

## Quick Reference

```bash
# List all functions
mainframe quickref

# Search for specific function
mainframe quickref --search json

# Get help for specific function
mainframe help json_object
```

## Kimi CLI Specific Notes

1. **Context Window**: Kimi CLI has large context - you can include substantial Mainframe function references
2. **Environment Inheritance**: Variables set in `~/.kimi/config` are available in sessions
3. **Output Parsing**: Use USOP format for structured data exchange
4. **Long-Running Tasks**: Combine with AWM for persistence across context boundaries

## Reference Files

- `~/.mainframe/CHEATSHEET.md` - All 3,821+ function signatures
- `~/.mainframe/FUNCTIONS.json` - Machine-readable function index
- `~/.mainframe/DECISION_TREES.md` - "I need X" workflow guidance
- `~/.mainframe/docs/ORCHESTRATION.md` - Multi-agent coordination

## Repository

- **Source**: https://github.com/gtwatts/mainframe
- **Install**: `git clone https://github.com/gtwatts/mainframe.git ~/.mainframe`
- **License**: MIT

# Advanced Bash Scripting Guide: Patterns for AI Coding Assistants

**Research Source**: Advanced Bash-Scripting Guide (TLDP)
**Purpose**: Extract patterns valuable for pure bash libraries targeting AI coding assistants
**Target**: MAINFRAME library enhancement
**Date**: 2026-01-22

---

## Executive Summary

This research identifies patterns from the Advanced Bash-Scripting Guide that make bash scripts more predictable for AI to generate, safer to execute, and easier to debug. The analysis covers seven critical areas with specific recommendations for MAINFRAME library enhancements.

**Key Findings**:
1. Parameter substitution patterns provide defensive defaults - partially covered by MAINFRAME
2. Process substitution enables advanced data flow without subshell variable loss - NOT in MAINFRAME
3. Common gotchas document 34+ pitfalls AI agents frequently hit - MAINFRAME could add guards
4. Indirect references enable dynamic variable manipulation - NOT in MAINFRAME
5. Here documents provide safe multi-line string handling - NOT in MAINFRAME
6. Array operations have unintuitive edge cases - MAINFRAME arrays are solid but missing edge case docs

---

## 1. Parameter Substitution Patterns (Critical for AI)

### Why This Helps AI Agents
Parameter substitution provides defensive defaults and error handling without external tools. AI agents frequently generate scripts that fail on unset variables.

### Key Patterns

#### 1.1 Default Values with `${var:-default}`
```bash
# If var is unset OR empty, use default
filename=${1:-"default.txt"}
port=${PORT:-8080}
timeout=${TIMEOUT:-30}
```
**AI Value**: Prevents scripts from failing when optional parameters are missing.

#### 1.2 Assign Default with `${var:=default}`
```bash
# If var is unset OR empty, assign AND use default
: ${TMPDIR:=/tmp}
: ${LOG_LEVEL:=INFO}
```
**AI Value**: Ensures variables are always set with sensible defaults.

#### 1.3 Error on Unset with `${var:?message}`
```bash
# Exit with error if var is unset or empty
: ${CONFIG_FILE:?"CONFIG_FILE must be set"}
: ${API_KEY:?"API_KEY is required"}
```
**AI Value**: Fail-fast behavior catches configuration errors immediately.

#### 1.4 Alternate Value with `${var:+alt}`
```bash
# Use alt only if var IS set and non-empty
verbose_flag=${VERBOSE:+--verbose}
debug_opt=${DEBUG:+-x}
```
**AI Value**: Conditionally add flags without if/then blocks.

### MAINFRAME Status
**Partially Covered**: The validation.sh module has `env_require` but lacks:
- `param_default` - wrapping `${var:-default}` with logging
- `param_require` - wrapping `${var:?msg}` with better error format
- `param_if_set` - wrapping `${var:+alt}` pattern

### Recommendation: Add to validation.sh
```bash
# Proposed additions
param_default() {
    local var_name="$1"
    local default="$2"
    local -n ref="$var_name"
    echo "${ref:-$default}"
}

param_require() {
    local var_name="$1"
    local message="${2:-$var_name is required}"
    local -n ref="$var_name"
    if [[ -z "${ref:-}" ]]; then
        log_error "$message"
        return 1
    fi
    echo "$ref"
}
```

---

## 2. String Manipulation Without External Tools

### Why This Helps AI Agents
Pure bash string operations are faster, more portable, and reduce dependencies. AI agents often reach for sed/awk when bash builtins suffice.

### Key Patterns

#### 2.1 Substring Extraction
```bash
string="abcABC123ABCabc"

# From position (0-indexed)
echo ${string:7}      # 23ABCabc
echo ${string:7:3}    # 23A

# From right side (note the space or parentheses)
echo ${string: -4}    # Cabc
echo ${string:(-4)}   # Cabc
```

#### 2.2 Substring Removal
```bash
path="/home/user/documents/file.tar.gz"

# Remove shortest match from front
echo ${path#*/}       # home/user/documents/file.tar.gz

# Remove longest match from front
echo ${path##*/}      # file.tar.gz (like basename)

# Remove shortest match from back
echo ${path%/*}       # /home/user/documents (like dirname)

# Remove longest match from back
echo ${path%%/*}      # (empty - removes everything after first /)
```

**Mnemonic**: `#` is on left of `$` on keyboard (front), `%` is on right (back)

#### 2.3 Pattern Replacement
```bash
text="hello hello world"

# Replace first match
echo ${text/hello/hi}    # hi hello world

# Replace all matches
echo ${text//hello/hi}   # hi hi world

# Replace at front
echo ${text/#hello/hi}   # hi hello world

# Replace at back (if matches)
echo ${text/%world/earth}  # hello hello earth

# Delete (no replacement)
echo ${text//hello/}     # world
```

#### 2.4 Case Conversion (Bash 4+)
```bash
text="Hello World"

echo ${text,,}    # hello world (all lower)
echo ${text^^}    # HELLO WORLD (all upper)
echo ${text,}     # hello World (first char lower)
echo ${text^}     # Hello World (first char upper)
```

### MAINFRAME Status
**Well Covered**: pure-string.sh has `to_lower`, `to_upper`, `substring`, `replace_all`, etc.

**Missing**:
- `strip_prefix` / `strip_suffix` wrappers for `${var#pattern}` / `${var%pattern}`
- `basename_pure` / `dirname_pure` that use pure bash (no external calls)

### Recommendation: Add to pure-string.sh
```bash
# Pure bash equivalents - faster than command substitution
strip_prefix() {
    local string="$1"
    local pattern="$2"
    echo "${string#$pattern}"
}

strip_prefix_greedy() {
    local string="$1"
    local pattern="$2"
    echo "${string##$pattern}"
}

strip_suffix() {
    local string="$1"
    local pattern="$2"
    echo "${string%$pattern}"
}

strip_suffix_greedy() {
    local string="$1"
    local pattern="$2"
    echo "${string%%$pattern}"
}

# 10x faster than $(basename "$path")
basename_pure() {
    local path="$1"
    echo "${path##*/}"
}

# 10x faster than $(dirname "$path")
dirname_pure() {
    local path="$1"
    local dir="${path%/*}"
    echo "${dir:-/}"
}
```

---

## 3. Process Substitution (Not in MAINFRAME)

### Why This Helps AI Agents
Process substitution solves the notorious "variable lost in subshell" problem that trips up AI-generated scripts constantly.

### The Problem AI Agents Hit
```bash
# BROKEN: Variables set in pipe subshell are lost
count=0
cat file.txt | while read line; do
    ((count++))
done
echo "Count: $count"  # Always 0!
```

### The Solution: Process Substitution
```bash
# WORKS: No subshell for the while loop
count=0
while read line; do
    ((count++))
done < <(cat file.txt)
echo "Count: $count"  # Correct value!
```

### Key Patterns

#### 3.1 Reading from Process Output
```bash
# Compare two command outputs
diff <(ls dir1) <(ls dir2)

# Feed command output to while loop (preserving variables)
while read -r line; do
    process "$line"
done < <(some_command)

# Multiple inputs to a command
paste <(cut -f1 file1) <(cut -f2 file2)
```

#### 3.2 Writing to Process Input
```bash
# Tee to multiple processes
echo "data" | tee >(process1) >(process2) > /dev/null

# Compress while keeping original
tar cf - directory | tee >(gzip > backup.tar.gz) | wc -c
```

#### 3.3 Avoiding Subshell Variable Loss
```bash
# Pattern for accumulating data from a loop
declare -a results
while IFS= read -r line; do
    results+=("$line")
done < <(find . -name "*.txt")
echo "Found ${#results[@]} files"
```

### MAINFRAME Status
**NOT COVERED**: No process substitution helpers exist.

### Recommendation: Add new module `procsub.sh` or add to async.sh
```bash
# Read lines from command into array (preserving variables)
# Usage: read_lines_from "command" array_name
read_lines_from() {
    local cmd="$1"
    local -n arr="$2"
    arr=()
    while IFS= read -r line; do
        arr+=("$line")
    done < <(eval "$cmd")
}

# Process lines with callback (no subshell)
# Usage: for_each_line "command" callback_function
for_each_line() {
    local cmd="$1"
    local callback="$2"
    while IFS= read -r line; do
        "$callback" "$line"
    done < <(eval "$cmd")
}

# Diff two commands' outputs
# Usage: diff_commands "cmd1" "cmd2"
diff_commands() {
    diff <(eval "$1") <(eval "$2")
}
```

---

## 4. Common Gotchas AI Agents Must Avoid

### Why This Helps AI Agents
The ABS Guide documents 34+ common mistakes. AI agents hit these constantly because they pattern-match from training data that includes buggy examples.

### Critical Gotchas

#### 4.1 Whitespace in Variable Assignment
```bash
# WRONG - tries to run "var1" as command
var1 = 23

# CORRECT
var1=23
```

#### 4.2 Unquoted Variables with Whitespace
```bash
file="my document.txt"

# WRONG - word splitting
cat $file  # Tries: cat my document.txt (two args)

# CORRECT
cat "$file"
```

#### 4.3 Test Bracket Spacing
```bash
# WRONG - missing spaces
if [$a -le 5]

# CORRECT
if [ "$a" -le 5 ]

# EVEN BETTER (Bash)
if [[ "$a" -le 5 ]]
```

#### 4.4 Numeric vs String Comparison
```bash
# WRONG - string comparison for numbers
if [ "$a" = 273 ]

# CORRECT - numeric comparison
if [ "$a" -eq 273 ]

# GOTCHA - decimals fail with -eq
a=273.0
[ "$a" -eq 273 ]  # Error: integer expression expected
```

#### 4.5 Pipe Subshell Variable Loss
```bash
# WRONG - count is always 0
count=0
echo "a b c" | while read x; do ((count++)); done
echo $count

# CORRECT - use process substitution
count=0
while read x; do ((count++)); done < <(echo "a b c")
echo $count
```

#### 4.6 Empty Array vs Array with Empty Element
```bash
array1=( '' )   # One empty element - ${#array1[@]} is 1
array2=( )      # Empty array - ${#array2[@]} is 0

# GOTCHA: They behave differently in loops!
```

#### 4.7 Uninitialized Variables are Empty, Not Zero
```bash
# WRONG assumption
echo $((unset_var + 5))  # Works but unset_var is 0, not undefined

# SAFER
if [[ -v some_var ]]; then
    # Variable is set (even if empty)
fi
```

#### 4.8 Code Block Semicolon Requirement
```bash
# WRONG - missing semicolon
{ ls -l; df; echo "Done." }

# CORRECT
{ ls -l; df; echo "Done."; }
```

#### 4.9 Exporting Variables to Parent Process
```bash
# THIS DOESN'T WORK
# Child processes cannot export to parents
./child_script.sh  # Sets MY_VAR
echo $MY_VAR       # Empty - child can't affect parent
```

#### 4.10 DOS Line Endings
```bash
# Script with \r\n will fail with cryptic errors
# #!/bin/bash\r\n is NOT recognized

# Fix: dos2unix script.sh
```

### MAINFRAME Status
**PARTIALLY COVERED**: Some validation exists, but no comprehensive "safe mode" or gotcha guards.

### Recommendation: Add `safe.sh` module
```bash
# Enable strict mode (catch many gotchas)
enable_strict_mode() {
    set -euo pipefail
    shopt -s inherit_errexit 2>/dev/null || true
}

# Check for common script problems
lint_script() {
    local script="$1"
    local issues=()

    # Check for DOS line endings
    if file "$script" | grep -q "CRLF"; then
        issues+=("DOS line endings detected - run dos2unix")
    fi

    # Check for unquoted variables in dangerous contexts
    if grep -E '\$[a-zA-Z_][a-zA-Z_0-9]*[^"]' "$script" | grep -v '#'; then
        issues+=("Potentially unquoted variables detected")
    fi

    # Report issues
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf '%s\n' "${issues[@]}"
        return 1
    fi
}

# Safe variable access with default
safe_var() {
    local var_name="$1"
    local default="${2:-}"
    local -n ref="$var_name" 2>/dev/null || { echo "$default"; return; }
    echo "${ref:-$default}"
}
```

---

## 5. Here Documents for Safe Multi-Line Strings

### Why This Helps AI Agents
Here documents are the safest way to handle multi-line strings, avoiding quoting nightmares that AI agents often create.

### Key Patterns

#### 5.1 Basic Here Document
```bash
cat <<EOF
This is line 1
This is line 2
Variable expansion: $USER
Command substitution: $(date)
EOF
```

#### 5.2 Quoted Delimiter - No Expansion
```bash
cat <<'EOF'
$USER will print literally
$(date) will not execute
Backslashes are literal: \n \t
EOF
```

#### 5.3 Strip Leading Tabs with `<<-`
```bash
if true; then
    cat <<-EOF
		This text can be indented with tabs
		The tabs will be stripped from output
		Spaces are NOT stripped
	EOF
fi
```

#### 5.4 Here Document to Variable
```bash
read -r -d '' my_var <<'EOF'
Multi-line content
goes here
EOF
# Note: -d '' reads until EOF, not newline
```

#### 5.5 Here Document as Function Input
```bash
process_config() {
    while read -r key value; do
        echo "Setting $key = $value"
    done
}

process_config <<EOF
name John
age 30
city NYC
EOF
```

#### 5.6 Self-Documenting Script Pattern
```bash
show_help() {
    cat <<'HELP'
Usage: script.sh [options] <file>

Options:
    -v, --verbose    Enable verbose output
    -h, --help       Show this help message

Examples:
    script.sh input.txt
    script.sh -v data.csv
HELP
}
```

### MAINFRAME Status
**NOT COVERED**: No here document helpers exist.

### Recommendation: Add to template.sh or new heredoc.sh
```bash
# Create a here document string variable
# Usage: heredoc_to_var varname <<'EOF' ... EOF
heredoc_to_var() {
    local -n var="$1"
    var=$(cat)
}

# Render template with variable substitution
# Usage: template_render <<EOF ... EOF
template_render() {
    eval "cat <<TEMPLATE_EOF
$(cat)
TEMPLATE_EOF"
}

# Safe multi-line echo (avoids echo interpretation issues)
multiline() {
    cat <<'ML_EOF'
$@
ML_EOF
}
```

---

## 6. Indirect References and Dynamic Variables

### Why This Helps AI Agents
Indirect references enable metaprogramming patterns like dynamic configuration, table lookups, and variable variable names - but they're tricky to get right.

### Key Patterns

#### 6.1 Basic Indirect Reference (Bash 2+)
```bash
var_name="my_variable"
my_variable="hello world"

# Old way with eval (dangerous)
eval "value=\$$var_name"

# Better way with ${!...} (Bash 2+)
value="${!var_name}"
echo "$value"  # hello world
```

#### 6.2 Indirect Assignment with declare
```bash
var_name="config_value"
new_value="42"

# Assign to variable whose name is in var_name
declare "$var_name=$new_value"
echo "$config_value"  # 42
```

#### 6.3 Dynamic Configuration Pattern
```bash
# Load config dynamically
load_config() {
    local prefix="$1"
    local key value
    while IFS='=' read -r key value; do
        declare -g "${prefix}_${key}=$value"
    done < config.txt
}

load_config "APP"
echo "$APP_database"  # Value from config
```

#### 6.4 Variable Name Prefix Expansion
```bash
# List all variables starting with prefix
prefix="CONFIG_"
for var in "${!CONFIG_@}"; do
    echo "$var = ${!var}"
done
```

#### 6.5 Nameref Variables (Bash 4.3+)
```bash
# More readable than ${!...}
my_array=(a b c)

func_that_modifies_array() {
    local -n arr="$1"  # Nameref to the passed array name
    arr+=("d")
}

func_that_modifies_array my_array
echo "${my_array[@]}"  # a b c d
```

### MAINFRAME Status
**NOT COVERED**: No indirect reference helpers exist.

### Recommendation: Add to new `meta.sh` module
```bash
# Get value by variable name
# Usage: var_get "variable_name"
var_get() {
    local name="$1"
    echo "${!name}"
}

# Set value by variable name
# Usage: var_set "variable_name" "value"
var_set() {
    local name="$1"
    local value="$2"
    declare -g "$name=$value"
}

# Check if variable with name exists
# Usage: var_exists "variable_name"
var_exists() {
    local name="$1"
    declare -p "$name" &>/dev/null
}

# Get all variable names with prefix
# Usage: vars_with_prefix "PREFIX_"
vars_with_prefix() {
    local prefix="$1"
    local -a vars=()
    local var
    for var in $(compgen -v "$prefix"); do
        vars+=("$var")
    done
    echo "${vars[@]}"
}

# Dynamic config loader
# Usage: config_load_dynamic "prefix" < config_file
config_load_dynamic() {
    local prefix="$1"
    local key value
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        declare -g "${prefix}_${key}=$value"
    done
}
```

---

## 7. Array Operations and Edge Cases

### Why This Helps AI Agents
Bash arrays have unintuitive behaviors that cause bugs. Understanding these patterns prevents AI from generating broken array code.

### Key Patterns

#### 7.1 Array Declaration Styles
```bash
# Indexed array
declare -a arr1
arr1=(one two three)

# Sparse array (gaps allowed)
arr2[0]=first
arr2[5]=sixth
# arr2[1-4] are unset, not empty

# Associative array (Bash 4+)
declare -A dict
dict[name]="John"
dict[age]=30
```

#### 7.2 Array Length and Element Access
```bash
arr=(a b c d e)

# Length of array
echo ${#arr[@]}   # 5

# Length of first element
echo ${#arr}      # 1 (length of "a")
echo ${#arr[0]}   # 1 (same as above)

# All elements
echo ${arr[@]}    # a b c d e
echo ${arr[*]}    # a b c d e (different in quotes)

# Quoted difference
echo "${arr[@]}"  # "a" "b" "c" "d" "e" (5 words)
echo "${arr[*]}"  # "a b c d e" (1 word with IFS)
```

#### 7.3 Array Slicing
```bash
arr=(a b c d e f g)

# Slice from index 2
echo ${arr[@]:2}      # c d e f g

# Slice 3 elements starting at index 2
echo ${arr[@]:2:3}    # c d e

# Negative indices (Bash 4.2+)
echo ${arr[@]: -2}    # f g (last 2)
```

#### 7.4 Array Modification Patterns
```bash
arr=(a b c)

# Append element
arr+=("d")
arr[${#arr[@]}]="e"

# Prepend element (recreate array)
arr=("z" "${arr[@]}")

# Remove element by index
unset 'arr[1]'
# WARNING: This leaves a gap, not a reindex!

# Remove and reindex
arr=(a b c)
unset 'arr[1]'
arr=("${arr[@]}")  # Now: (a c) with indices 0,1
```

#### 7.5 Array String Operations (Apply to All Elements)
```bash
arr=(one two three)

# Uppercase all elements
echo ${arr[@]^^}      # ONE TWO THREE

# Replace in all elements
echo ${arr[@]//e/E}   # onE two thrEE

# Remove prefix from all elements
paths=(/home/user/a /home/user/b)
echo ${paths[@]#/home/user/}  # a b
```

#### 7.6 Empty Array vs Array with Empty Element (Gotcha!)
```bash
arr1=()       # Empty array
arr2=('')     # Array with one empty string

echo ${#arr1[@]}  # 0
echo ${#arr2[@]}  # 1

# This matters in conditionals!
if [[ ${#arr1[@]} -eq 0 ]]; then
    echo "arr1 is empty"
fi
```

### MAINFRAME Status
**WELL COVERED**: pure-array.sh is comprehensive.

**Missing Edge Cases**: Documentation for sparse arrays, empty vs empty-element distinction.

### Recommendation: Add edge case documentation and helpers
```bash
# Check if array is truly empty (not just containing empty strings)
array_is_empty() {
    local -n arr="$1"
    [[ ${#arr[@]} -eq 0 ]]
}

# Check if array has only empty strings
array_all_empty() {
    local -n arr="$1"
    local elem
    for elem in "${arr[@]}"; do
        [[ -n "$elem" ]] && return 1
    done
    return 0
}

# Compact array (remove empty elements and reindex)
array_compact() {
    local -n arr="$1"
    local -a new_arr=()
    local elem
    for elem in "${arr[@]}"; do
        [[ -n "$elem" ]] && new_arr+=("$elem")
    done
    arr=("${new_arr[@]}")
}

# Safe array access with default
array_get_safe() {
    local -n arr="$1"
    local index="$2"
    local default="${3:-}"
    if [[ $index -lt ${#arr[@]} ]] && [[ -n "${arr[$index]+set}" ]]; then
        echo "${arr[$index]}"
    else
        echo "$default"
    fi
}
```

---

## 8. I/O Redirection Patterns

### Why This Helps AI Agents
I/O redirection is powerful but error-prone. These patterns prevent common mistakes.

### Key Patterns

#### 8.1 Redirect Both stdout and stderr
```bash
# Old way (order matters!)
command > output.log 2>&1

# New way (Bash 4+)
command &> output.log

# Append both
command &>> output.log
```

#### 8.2 Suppress All Output
```bash
# Suppress stdout and stderr
command &>/dev/null

# Alternative
command >/dev/null 2>&1
```

#### 8.3 Redirect to Multiple Places
```bash
# tee for stdout
command | tee output.log

# Also capture stderr
command 2>&1 | tee output.log
```

#### 8.4 File Descriptor Manipulation
```bash
# Save and restore stdout
exec 3>&1           # Save stdout to fd 3
exec 1>output.log   # Redirect stdout to file
echo "To file"
exec 1>&3           # Restore stdout
exec 3>&-           # Close fd 3
echo "To terminal"
```

#### 8.5 Read and Write Same File (Danger!)
```bash
# WRONG - truncates file before reading
cat file.txt > file.txt  # File is now empty!

# CORRECT - use temp file or sponge
cat file.txt > temp && mv temp file.txt

# Or with process substitution
content=$(<file.txt)
echo "modified: $content" > file.txt
```

### MAINFRAME Status
**PARTIALLY COVERED**: Common patterns exist but not documented as recipes.

### Recommendation: Add to documentation or new `redirect.sh`
```bash
# Capture both stdout and stderr to variables
# Usage: capture_output stdout_var stderr_var command [args...]
capture_output() {
    local -n out="$1"
    local -n err="$2"
    shift 2

    local tmp_out tmp_err
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)

    "$@" >"$tmp_out" 2>"$tmp_err"
    local exit_code=$?

    out=$(<"$tmp_out")
    err=$(<"$tmp_err")

    rm -f "$tmp_out" "$tmp_err"
    return $exit_code
}

# Run command silently (suppress all output)
silent() {
    "$@" &>/dev/null
}

# Run command with output only on failure
quiet_unless_error() {
    local output
    if ! output=$("$@" 2>&1); then
        echo "$output" >&2
        return 1
    fi
}
```

---

## 9. Scripting Style Guidelines

### Why This Helps AI Agents
Consistent style makes scripts more predictable and easier to understand. These guidelines help AI generate maintainable code.

### Naming Conventions
```bash
# Constants: UPPER_SNAKE_CASE
readonly MAX_RETRIES=3
readonly DEFAULT_TIMEOUT=30

# Variables: lower_snake_case
file_count=0
current_user=""

# Functions: lower_snake_case with verb prefix
get_user_name() { ... }
validate_input() { ... }
process_file() { ... }

# Private functions: underscore prefix
_internal_helper() { ... }
```

### Error Code Constants
```bash
# Define at top of script
readonly E_SUCCESS=0
readonly E_INVALID_ARGS=1
readonly E_FILE_NOT_FOUND=2
readonly E_PERMISSION_DENIED=3
readonly E_NETWORK_ERROR=4

# Use consistently
if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file" >&2
    exit $E_FILE_NOT_FOUND
fi
```

### Function Documentation
```bash
# Describe purpose, parameters, return values
# @description Process a data file and output results
# @param $1 - Input file path
# @param $2 - Output format (json|csv|text)
# @return 0 on success, non-zero on error
# @stdout Processed output in requested format
process_data() {
    local input_file="$1"
    local format="${2:-text}"
    ...
}
```

### Script Header Template
```bash
#!/usr/bin/env bash
#
# script_name.sh - Brief description
#
# Usage: script_name.sh [options] <required_arg>
#
# Options:
#   -v, --verbose    Enable verbose output
#   -h, --help       Show this help
#
# Examples:
#   script_name.sh input.txt
#   script_name.sh -v data.csv
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
```

### MAINFRAME Status
**PARTIALLY COVERED**: Style varies across modules.

### Recommendation
Document official MAINFRAME style guide and provide a script template generator.

---

## 10. Summary of Recommendations for MAINFRAME

### High Priority Additions

| Module | Addition | Benefit |
|--------|----------|---------|
| `validation.sh` | `param_default`, `param_require`, `param_if_set` | Defensive parameter handling |
| `pure-string.sh` | `strip_prefix`, `strip_suffix`, `basename_pure`, `dirname_pure` | Faster pure-bash alternatives |
| NEW: `procsub.sh` | `read_lines_from`, `for_each_line`, `diff_commands` | Solve subshell variable loss |
| NEW: `safe.sh` | `enable_strict_mode`, `lint_script`, `safe_var` | Guard against common gotchas |
| `template.sh` | `heredoc_to_var`, `template_render` | Safe multi-line strings |
| NEW: `meta.sh` | `var_get`, `var_set`, `vars_with_prefix`, `config_load_dynamic` | Dynamic variable manipulation |
| `pure-array.sh` | `array_is_empty`, `array_compact`, `array_get_safe` | Edge case handling |

### Documentation Priority

1. **Gotchas Guide**: Document the 10+ critical gotchas with MAINFRAME solutions
2. **Patterns Cookbook**: Common recipes using MAINFRAME functions
3. **AI Agent Guidelines**: Specific guidance for AI-generated scripts

### Testing Priority

1. Add tests for edge cases (empty arrays, unset variables, special characters)
2. Add tests for the subshell variable loss scenarios
3. Add tests for whitespace in paths and variables

---

## Appendix: Quick Reference Card for AI Agents

### Safe Defaults
```bash
var="${1:-default}"              # Parameter with default
: ${REQUIRED_VAR:?"Must be set"} # Fail if unset
flag="${VERBOSE:+--verbose}"     # Optional flag
```

### String Operations
```bash
${var#prefix}   # Remove shortest prefix
${var##prefix}  # Remove longest prefix
${var%suffix}   # Remove shortest suffix
${var%%suffix}  # Remove longest suffix
${var/old/new}  # Replace first
${var//old/new} # Replace all
```

### Array Essentials
```bash
${#arr[@]}      # Length
${arr[@]}       # All elements (quoted = separate words)
${arr[@]:2:3}   # Slice
arr+=("new")    # Append
unset 'arr[i]'  # Delete (leaves gap!)
```

### Safe Practices
```bash
set -euo pipefail              # Strict mode
[[ ... ]] over [ ... ]         # Bash test (safer)
"$var" not $var                # Always quote
while ... done < <(cmd)        # Process substitution
local var inside functions     # Scope variables
```

### Dangerous Patterns to Avoid
```bash
# AVOID                         # USE INSTEAD
cat file | while read ...       while read ... done < <(cat file)
[ $var = value ]                [[ "$var" = "value" ]]
var = value                     var=value (no spaces!)
echo $var                       echo "$var"
for f in $(ls)                  for f in *
```

---

*Research completed: 2026-01-22*
*Source: Advanced Bash-Scripting Guide (TLDP), Revision 10*

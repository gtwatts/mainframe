# MAINFRAME Advanced Bash Techniques

**Source**: Black Hat Bash (No Starch Press, 2024)
**Purpose**: Extract defensive/robust bash patterns to enhance MAINFRAME
**Focus**: Reliability, error handling, process management for vibe coders

---

## Key Techniques Identified

### 1. Debugging & Validation Patterns

```bash
# Syntax validation (dry-run) - catches errors before execution
bash -n script.sh

# Verbose execution - shows commands as they run
bash -x script.sh

# Toggle debugging within script
set -x   # Turn on debugging
# ... debug this section ...
set +x   # Turn off debugging
```

**MAINFRAME Application**: Add a `--dry-run` flag to all scripts that validates commands without executing them.

---

### 2. Robust Variable Handling

```bash
# Always use curly braces for clarity
echo "${variable}"

# Check for empty variables before use
if [[ -z "${variable}" ]]; then
    echo "Error: variable is empty"
    exit 1
fi

# Local scope in functions (prevents pollution)
my_function() {
    local my_var="local value"
    # my_var only exists inside this function
}

# Unset variables when done
unset sensitive_variable
```

**MAINFRAME Application**: Create `var-safe.sh` that validates and sanitizes variables.

---

### 3. File Test Operators

| Operator | Description |
|----------|-------------|
| `-d FILE` | Is directory |
| `-f FILE` | Is regular file |
| `-r FILE` | Is readable |
| `-w FILE` | Is writable |
| `-x FILE` | Is executable |
| `-s FILE` | Size > 0 |
| `-e FILE` | Exists |

```bash
# Comprehensive file check before operations
if [[ -f "${file}" ]] && [[ -r "${file}" ]] && [[ -s "${file}" ]]; then
    # File exists, is readable, and has content
    process_file "${file}"
fi
```

**MAINFRAME Application**: Add pre-flight checks to all file operations.

---

### 4. Command Exit Code Handling

```bash
# Execute only if command succeeds
if command; then
    echo "Command succeeded"
fi

# Execute only if command fails
if ! command; then
    echo "Command failed"
fi

# Check specific exit codes
command
case $? in
    0) echo "Success" ;;
    1) echo "General error" ;;
    126) echo "Permission problem" ;;
    127) echo "Command not found" ;;
    *) echo "Unknown error: $?" ;;
esac
```

**MAINFRAME Application**: Enhance error messages with specific failure analysis.

---

### 5. Arithmetic Safety

```bash
# Safe arithmetic (avoids set -e issues)
result=$((value + 1))   # Preferred
count=$((count + 1))    # Instead of ((count++))

# let command for complex math
let "result = 4 * 5"

# expr for external math
result=$(expr 5 + 5)
```

**MAINFRAME Application**: Already implemented this fix in circuit-breaker.sh and self-heal.sh.

---

### 6. Process Watchdog Pattern

```bash
#!/bin/bash
# Watch for a condition, then act
INTERVAL=5
TARGET="$1"

while true; do
    if condition_met "${TARGET}"; then
        echo "Condition detected!"
        take_action "${TARGET}"
        break
    fi
    sleep "${INTERVAL}"
done
```

**MAINFRAME Application**: Create `watchdog.sh` for monitoring conditions.

---

### 7. HTTP Request Patterns

```bash
# Get HTTP status code only
status_code=$(curl -s -o /dev/null -w "%{http_code}" "${url}")

# Comprehensive curl with all variables
curl -s -o /dev/null -w "\
Response Code: %{http_code}\n\
Time Total: %{time_total}s\n\
Size Download: %{size_download} bytes\n\
Speed Download: %{speed_download} bytes/s\n" "${url}"

# Read response line by line
while read -r line; do
    process_line "${line}"
done < <(curl -s "${url}")
```

**MAINFRAME Application**: Enhance `http-get.sh` with detailed response metrics.

---

### 8. Job Control Patterns

```bash
# Run in background
command &
bg_pid=$!

# Wait for specific background job
wait "${bg_pid}"

# Check if process is running
if kill -0 "${pid}" 2>/dev/null; then
    echo "Process ${pid} is running"
fi

# Trap cleanup on exit
cleanup() {
    kill "${bg_pid}" 2>/dev/null
    rm -f "${temp_file}"
}
trap cleanup EXIT
```

**MAINFRAME Application**: Create `process-manager.sh` with job control.

---

### 9. Input Validation Patterns

```bash
# Validate required arguments
if [[ -z "${1}" ]]; then
    echo "Usage: $0 <required_arg>"
    exit 1
fi

# Validate file exists
if [[ ! -f "${input_file}" ]]; then
    echo "Error: File not found: ${input_file}"
    exit 1
fi

# Validate directory
if [[ ! -d "${target_dir}" ]]; then
    echo "Error: Directory not found: ${target_dir}"
    exit 1
fi

# Validate number
if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    echo "Error: Not a number: ${value}"
    exit 1
fi
```

**MAINFRAME Application**: Create `validate.sh` library for input checking.

---

### 10. sed/awk Patterns

```bash
# Safe sed in-place (with backup)
sed -i.bak 's/old/new/g' file.txt

# Extract field from output
result=$(echo "${output}" | awk '{print $2}')

# Parse key=value
value=$(echo "${line}" | awk -F'=' '{print $2}')

# Delete lines matching pattern
sed '/pattern/d' file.txt

# Print specific line range
sed -n '5,10p' file.txt
```

**MAINFRAME Application**: Add safe sed wrapper with automatic backup.

---

## New MAINFRAME Scripts to Implement

Based on the techniques above, here are priority scripts to add:

### Tier 1: Critical

1. **`validate-input.sh`** - Universal input validation
   - Check file exists, readable, writable
   - Validate numbers, strings, paths
   - Return meaningful error messages

2. **`process-watch.sh`** - Watchdog for processes
   - Monitor a process until condition
   - Auto-restart on crash
   - Timeout and cleanup

3. **`http-diagnostic.sh`** - Comprehensive HTTP debugging
   - Status codes, timing, sizes
   - Header inspection
   - Retry with backoff

4. **`debug-script.sh`** - Script debugging helper
   - Syntax validation (bash -n)
   - Verbose execution (bash -x)
   - Step-through mode

### Tier 2: High Priority

5. **`sed-safe.sh`** - Safe sed operations
   - Auto-backup before changes
   - Cross-platform compatibility
   - Preview mode

6. **`var-check.sh`** - Variable validation
   - Check for empty/unset
   - Type validation
   - Scope management

7. **`job-manager.sh`** - Background job control
   - Start/stop/status jobs
   - PID tracking
   - Cleanup on exit

### Tier 3: Enhancement

8. **`trap-handler.sh`** - Signal handling
   - Graceful shutdown
   - Cleanup routines
   - Error recovery

9. **`exit-analyzer.sh`** - Exit code analysis
   - Translate codes to messages
   - Suggest fixes
   - Log failures

10. **`loop-safe.sh`** - Safe loop execution
    - Iteration limits
    - Progress tracking
    - Graceful break

---

## Implementation Patterns for MAINFRAME

### Standard Script Template

```bash
#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Script Name
# =============================================================================
# Description: What this script does
# Category:    category
# WOW Factor:  X/10
# =============================================================================

set -euo pipefail

# Source MAINFRAME libraries
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="script-name"
readonly SCRIPT_VERSION="1.0.0"

# =============================================================================
# VALIDATION
# =============================================================================

validate_inputs() {
    # Check required arguments
    if [[ -z "${1:-}" ]]; then
        die "$EXIT_USAGE" "Missing required argument"
    fi

    # Check file exists
    if [[ ! -f "${1}" ]]; then
        die "$EXIT_NOINPUT" "File not found: ${1}"
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup() {
    # Remove temp files, kill background jobs
    [[ -n "${temp_file:-}" ]] && rm -f "${temp_file}"
    [[ -n "${bg_pid:-}" ]] && kill "${bg_pid}" 2>/dev/null
}
trap cleanup EXIT

# =============================================================================
# MAIN
# =============================================================================

main() {
    validate_inputs "$@"
    # Script logic here
}

main "$@"
```

---

## Key Takeaways for Vibe Coders

1. **Always validate inputs** - Check files exist before reading
2. **Use proper quoting** - `"${variable}"` prevents word splitting
3. **Handle errors explicitly** - Check exit codes, provide context
4. **Clean up after yourself** - Use trap to remove temp files
5. **Local variables in functions** - Prevent namespace pollution
6. **Test before production** - Use `bash -n` and `bash -x`

---

**YO JOE!**

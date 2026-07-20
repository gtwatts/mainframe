#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/procsub.sh - Process Substitution Library
# =============================================================================
# Description: Solve the "variable lost in subshell" problem
# =============================================================================
# The classic bash gotcha: variables set in pipelines are lost because
# each pipe segment runs in a subshell. This library provides functions
# that use process substitution to keep variables in the current shell.
#
# BAD (variable lost):
#   count=0
#   cat file | while read line; do ((count++)); done
#   echo $count  # Still 0!
#
# GOOD (with this library):
#   count=0
#   for_each_line "cat file" 'process_line "$line"; ((count++))'
#   echo $count  # Correct value!
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PROCSUB_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PROCSUB_LOADED=1

# =============================================================================
# SECURITY: Safe Command Execution
# =============================================================================
# These functions avoid direct eval of user input by using bash -c for isolation
# or by validating function names before invocation.

# Execute a command string safely via subprocess isolation
# Usage: _procsub_safe_exec "command string"
# Security: Runs in subprocess, cannot affect parent shell variables
_procsub_safe_exec() {
    local cmd="$1"

    # Block command substitution so callers cannot smuggle side effects through
    # a "read-only" capture helper.
    if [[ "$cmd" == *'`'* ]] || [[ "$cmd" == *'$('* && "$cmd" != *'$(('* ]]; then
        printf 'procsub: blocked dangerous pattern in command: %s\n' "$cmd" >&2
        return 1
    fi

    bash -c "$cmd"
}

# Validate and execute a function by name (no eval needed)
# Usage: _procsub_call_func "func_name" [args...]
# Security: Only calls declared functions, not arbitrary code
_procsub_call_func() {
    local func="$1"
    shift

    # Validate function exists
    if ! declare -F "$func" &>/dev/null; then
        printf 'procsub: function not found: %s\n' "$func" >&2
        return 1
    fi

    "$func" "$@"
}

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

# Read lines from command output into array without losing variables
# Usage: read_lines_from "command" array_name
# Example:
#   read_lines_from "ls -1" files
#   echo "Found ${#files[@]} files"
# Returns: 0 on success, 1 on empty/failure
# Security: Uses subprocess isolation via bash -c
read_lines_from() {
    local cmd="$1"
    local -n __rfl_arr=$2
    __rfl_arr=()

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        __rfl_arr+=("$line")
    done < <(_procsub_safe_exec "$cmd")

    [[ ${#__rfl_arr[@]} -gt 0 ]]
}

# Execute callback for each line from command, keeping variables in scope
# Usage: for_each_line "command" callback_function_name
# Example:
#   count=0
#   my_callback() { echo "Line: $1"; ((count++)); }
#   for_each_line "cat data.txt" my_callback
#   echo "Processed $count lines"
# Notes:
#   - Callback receives line as $1 argument
#   - All variable changes persist in the current shell
#   - callback MUST be a function name (not arbitrary code)
# Returns: 0 on success
# Security: Validates callback is a declared function
for_each_line() {
    local cmd="$1"
    local callback="$2"
    local line

    # Validate callback is a function
    if ! declare -F "$callback" &>/dev/null; then
        printf 'for_each_line: callback must be a function name, got: %s\n' "$callback" >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        "$callback" "$line"
    done < <(_procsub_safe_exec "$cmd")
}

# Diff two commands' outputs using process substitution
# Usage: diff_commands "cmd1" "cmd2" [diff_opts...]
# Example:
#   diff_commands "sort file1" "sort file2"
#   diff_commands "ls dir1" "ls dir2" -u
# Returns: diff exit code (0 if identical, 1 if different)
# Security: Uses subprocess isolation via bash -c
diff_commands() {
    local cmd1="$1"
    local cmd2="$2"
    shift 2
    local diff_opts=("$@")

    diff "${diff_opts[@]}" <(_procsub_safe_exec "$cmd1") <(_procsub_safe_exec "$cmd2")
}

# Read command output into variable without subshell
# Usage: capture_output varname "command"
# Example:
#   capture_output result "date +%Y-%m-%d"
#   echo "Today is: $result"
# Returns: Command's exit code
# Security: Uses subprocess isolation via bash -c
capture_output() {
    local -n __co_var=$1
    local cmd="$2"
    local __co_exit_code

    __co_var=$(_procsub_safe_exec "$cmd")
    __co_exit_code=$?

    return "$__co_exit_code"
}

# Process file lines with callback function, preserving state in current shell
# Usage: process_file "file" callback_function_name
# Example:
#   total=0
#   my_processor() {
#       local line="$1" lineno="$2"
#       IFS=, read -r name value <<< "$line"
#       total=$((total + value))
#   }
#   process_file "data.csv" my_processor
#   echo "Sum: $total"
# Notes:
#   - Callback receives line as $1, lineno as $2
#   - callback MUST be a function name (not arbitrary code)
# Returns: 0 on success, 1 if file not found
# Security: Validates callback is a declared function
process_file() {
    local file="$1"
    local callback="$2"
    local line
    local lineno=0

    [[ -f "$file" ]] || return 1

    # Validate callback is a function
    if ! declare -F "$callback" &>/dev/null; then
        printf 'process_file: callback must be a function name, got: %s\n' "$callback" >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((lineno++))
        "$callback" "$line" "$lineno"
    done < "$file"
}

# Tee command output to variable AND stdout simultaneously
# Usage: tee_to_var varname "command"
# Example:
#   tee_to_var output "ls -la"
#   # Output was displayed AND captured in $output
#   echo "Captured ${#output} bytes"
# Returns: Command's exit code
# Security: Uses subprocess isolation via bash -c
tee_to_var() {
    local -n __ttv_var=$1
    local cmd="$2"
    local __ttv_tmpfile
    local __ttv_exit_code

    __ttv_tmpfile=$(mktemp)

    # Run command via subprocess, tee to file and stdout
    _procsub_safe_exec "$cmd" | tee "$__ttv_tmpfile"
    __ttv_exit_code=${PIPESTATUS[0]}

    # Read file into variable
    __ttv_var=$(<"$__ttv_tmpfile")

    # Cleanup
    rm -f "$__ttv_tmpfile"

    return "$__ttv_exit_code"
}

# =============================================================================
# ADVANCED FUNCTIONS
# =============================================================================

# Map function over command output, collecting results in array
# Usage: map_lines_from "command" function_name result_array
# Example:
#   to_upper() { printf '%s\n' "${1^^}"; }
#   map_lines_from "echo -e 'hello\nworld'" to_upper results
#   echo "${results[@]}"  # HELLO WORLD
# Returns: 0 on success
# Security: Validates function name, uses subprocess for command
map_lines_from() {
    local cmd="$1"
    local func="$2"
    local -n __mlf_arr=$3
    __mlf_arr=()

    # Validate function exists
    if ! declare -F "$func" &>/dev/null; then
        printf 'map_lines_from: function not found: %s\n' "$func" >&2
        return 1
    fi

    local line result
    while IFS= read -r line || [[ -n "$line" ]]; do
        result=$("$func" "$line")
        __mlf_arr+=("$result")
    done < <(_procsub_safe_exec "$cmd")
}

# Filter lines from command using predicate function
# Usage: filter_lines_from "command" predicate_function result_array
# Example:
#   is_even() { [[ $(($1 % 2)) -eq 0 ]]; }
#   filter_lines_from "seq 1 10" is_even evens
#   echo "${evens[@]}"  # 2 4 6 8 10
# Returns: 0 on success
# Security: Validates predicate is a function, uses subprocess for command
filter_lines_from() {
    local cmd="$1"
    local predicate="$2"
    local -n __flf_arr=$3
    __flf_arr=()

    # Validate predicate is a function
    if ! declare -F "$predicate" &>/dev/null; then
        printf 'filter_lines_from: predicate must be a function name, got: %s\n' "$predicate" >&2
        return 1
    fi

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if "$predicate" "$line"; then
            __flf_arr+=("$line")
        fi
    done < <(_procsub_safe_exec "$cmd")
}

# Reduce lines from command to single value
# Usage: reduce_lines_from "command" reducer_function initial_value result_var
# Example:
#   sum_reducer() { echo $(($1 + $2)); }
#   reduce_lines_from "seq 1 5" sum_reducer 0 total
#   echo "$total"  # 15
# Returns: 0 on success
# Security: Validates reducer is a function, uses subprocess for command
reduce_lines_from() {
    local cmd="$1"
    local reducer="$2"
    local initial="$3"
    local -n __rlf_result=$4

    # Validate reducer is a function
    if ! declare -F "$reducer" &>/dev/null; then
        printf 'reduce_lines_from: reducer must be a function name, got: %s\n' "$reducer" >&2
        return 1
    fi

    __rlf_result="$initial"
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        __rlf_result=$("$reducer" "$__rlf_result" "$line")
    done < <(_procsub_safe_exec "$cmd")
}

# Compare two commands for equality
# Usage: commands_equal "cmd1" "cmd2"
# Example:
#   if commands_equal "cat file1 | sort" "cat file2 | sort"; then
#       echo "Files have same content"
#   fi
# Returns: 0 if outputs are identical, 1 otherwise
# Security: Uses subprocess isolation via bash -c
commands_equal() {
    local cmd1="$1"
    local cmd2="$2"

    diff -q <(_procsub_safe_exec "$cmd1") <(_procsub_safe_exec "$cmd2") >/dev/null 2>&1
}

# Read first N lines from command into array
# Usage: read_n_lines_from "command" n array_name
# Example:
#   read_n_lines_from "cat largefile.txt" 10 first_lines
#   echo "First 10 lines: ${first_lines[*]}"
# Returns: 0 on success
# Security: Uses subprocess isolation via bash -c
read_n_lines_from() {
    local cmd="$1"
    local n="$2"
    local -n __rnlf_arr=$3
    __rnlf_arr=()

    local line count=0
    while IFS= read -r line && [[ $count -lt $n ]]; do
        __rnlf_arr+=("$line")
        ((count++))
    done < <(_procsub_safe_exec "$cmd")

    [[ ${#__rnlf_arr[@]} -gt 0 ]]
}

# Process lines in batches
# Usage: batch_lines_from "command" batch_size callback_function_name
# Example:
#   process_batch() {
#       local -n batch_ref=$1
#       local batch_num=$2
#       echo "Processing batch $batch_num of ${#batch_ref[@]} items"
#       printf '%s\n' "${batch_ref[@]}"
#   }
#   batch_lines_from "seq 1 10" 3 process_batch
# Notes:
#   - Callback receives batch array name as $1, batch_num as $2
#   - callback MUST be a function name (not arbitrary code)
# Returns: 0 on success
# Security: Validates callback is a function, uses subprocess for command
batch_lines_from() {
    local cmd="$1"
    local batch_size="$2"
    local callback="$3"
    local -a __blf_batch=()
    local line
    local batch_num=0

    # Validate callback is a function
    if ! declare -F "$callback" &>/dev/null; then
        printf 'batch_lines_from: callback must be a function name, got: %s\n' "$callback" >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        __blf_batch+=("$line")

        if [[ ${#__blf_batch[@]} -ge $batch_size ]]; then
            ((batch_num++))
            "$callback" __blf_batch "$batch_num"
            __blf_batch=()
        fi
    done < <(_procsub_safe_exec "$cmd")

    # Process remaining items
    if [[ ${#__blf_batch[@]} -gt 0 ]]; then
        ((batch_num++))
        "$callback" __blf_batch "$batch_num"
    fi
}

# Interleave output from two commands
# Usage: interleave_commands "cmd1" "cmd2" result_array
# Example:
#   interleave_commands "echo -e 'a\nb'" "echo -e '1\n2'" merged
#   echo "${merged[@]}"  # a 1 b 2
# Returns: 0 on success
# Security: Uses subprocess isolation via bash -c
interleave_commands() {
    local cmd1="$1"
    local cmd2="$2"
    local -n __ic_arr=$3
    __ic_arr=()

    local line1 line2
    local fd1 fd2

    # Open process substitutions as file descriptors (isolated via bash -c)
    exec {fd1}< <(_procsub_safe_exec "$cmd1")
    exec {fd2}< <(_procsub_safe_exec "$cmd2")

    while true; do
        local has1=0 has2=0

        if read -r line1 <&"$fd1" 2>/dev/null; then
            __ic_arr+=("$line1")
            has1=1
        fi

        if read -r line2 <&"$fd2" 2>/dev/null; then
            __ic_arr+=("$line2")
            has2=1
        fi

        [[ $has1 -eq 0 && $has2 -eq 0 ]] && break
    done

    # Close file descriptors
    exec {fd1}<&-
    exec {fd2}<&-
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Count lines from command without subshell variable loss
# Usage: count_lines_from "command" count_var
# Example:
#   count_lines_from "find . -name '*.sh'" total
#   echo "Found $total shell files"
# Returns: 0 on success
# Security: Uses subprocess isolation via bash -c
count_lines_from() {
    local cmd="$1"
    local -n __clf_count=$2
    __clf_count=0

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((__clf_count++))
    done < <(_procsub_safe_exec "$cmd")
}

# Read key=value pairs from command into associative array
# Usage: read_pairs_from "command" assoc_array [delimiter]
# Example:
#   read_pairs_from "cat config.txt" config "="
#   echo "${config[key1]}"
# Returns: 0 on success
# Security: Uses subprocess isolation via bash -c
read_pairs_from() {
    local cmd="$1"
    local -n __rpf_map=$2
    local delim="${3:-=}"

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        key="${line%%"$delim"*}"
        value="${line#*"$delim"}"
        __rpf_map["$key"]="$value"
    done < <(_procsub_safe_exec "$cmd")
}

# =============================================================================
# EXPORT
# =============================================================================

export -f _procsub_safe_exec _procsub_call_func
export -f read_lines_from for_each_line diff_commands capture_output
export -f process_file tee_to_var
export -f map_lines_from filter_lines_from reduce_lines_from
export -f commands_equal read_n_lines_from batch_lines_from
export -f interleave_commands count_lines_from read_pairs_from

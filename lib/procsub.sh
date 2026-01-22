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
# CORE FUNCTIONS
# =============================================================================

# Read lines from command output into array without losing variables
# Usage: read_lines_from "command" array_name
# Example:
#   read_lines_from "ls -1" files
#   echo "Found ${#files[@]} files"
# Returns: 0 on success, 1 on empty/failure
read_lines_from() {
    local cmd="$1"
    local -n __rfl_arr=$2
    __rfl_arr=()

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        __rfl_arr+=("$line")
    done < <(eval "$cmd")

    [[ ${#__rfl_arr[@]} -gt 0 ]]
}

# Execute callback for each line from command, keeping variables in scope
# Usage: for_each_line "command" callback_function
# Example:
#   count=0
#   for_each_line "cat data.txt" 'echo "Line: $line"; ((count++))'
#   echo "Processed $count lines"
# Notes:
#   - The variable 'line' is available in the callback
#   - All variable changes persist in the current shell
# Returns: 0 on success
for_each_line() {
    local cmd="$1"
    local callback="$2"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        eval "$callback"
    done < <(eval "$cmd")
}

# Diff two commands' outputs using process substitution
# Usage: diff_commands "cmd1" "cmd2" [diff_opts...]
# Example:
#   diff_commands "sort file1" "sort file2"
#   diff_commands "ls dir1" "ls dir2" -u
# Returns: diff exit code (0 if identical, 1 if different)
diff_commands() {
    local cmd1="$1"
    local cmd2="$2"
    shift 2
    local diff_opts=("$@")

    diff "${diff_opts[@]}" <(eval "$cmd1") <(eval "$cmd2")
}

# Read command output into variable without subshell
# Usage: capture_output varname "command"
# Example:
#   capture_output result "date +%Y-%m-%d"
#   echo "Today is: $result"
# Returns: Command's exit code
capture_output() {
    local -n __co_var=$1
    local cmd="$2"
    local __co_exit_code

    __co_var=$(eval "$cmd")
    __co_exit_code=$?

    return "$__co_exit_code"
}

# Process file lines with callback, preserving state in current shell
# Usage: process_file "file" callback
# Example:
#   total=0
#   process_file "data.csv" 'IFS=, read -r name value <<< "$line"; total=$((total + value))'
#   echo "Sum: $total"
# Notes:
#   - The variable 'line' contains each line
#   - The variable 'lineno' contains current line number (1-based)
# Returns: 0 on success, 1 if file not found
process_file() {
    local file="$1"
    local callback="$2"
    local line
    local lineno=0

    [[ -f "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((lineno++))
        eval "$callback"
    done < "$file"
}

# Tee command output to variable AND stdout simultaneously
# Usage: tee_to_var varname "command"
# Example:
#   tee_to_var output "ls -la"
#   # Output was displayed AND captured in $output
#   echo "Captured ${#output} bytes"
# Returns: Command's exit code
tee_to_var() {
    local -n __ttv_var=$1
    local cmd="$2"
    local __ttv_tmpfile
    local __ttv_exit_code

    __ttv_tmpfile=$(mktemp)

    # Run command, tee to file and stdout
    eval "$cmd" | tee "$__ttv_tmpfile"
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
map_lines_from() {
    local cmd="$1"
    local func="$2"
    local -n __mlf_arr=$3
    __mlf_arr=()

    local line result
    while IFS= read -r line || [[ -n "$line" ]]; do
        result=$("$func" "$line")
        __mlf_arr+=("$result")
    done < <(eval "$cmd")
}

# Filter lines from command using predicate function
# Usage: filter_lines_from "command" predicate_function result_array
# Example:
#   is_even() { [[ $(($1 % 2)) -eq 0 ]]; }
#   filter_lines_from "seq 1 10" is_even evens
#   echo "${evens[@]}"  # 2 4 6 8 10
# Returns: 0 on success
filter_lines_from() {
    local cmd="$1"
    local predicate="$2"
    local -n __flf_arr=$3
    __flf_arr=()

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if "$predicate" "$line"; then
            __flf_arr+=("$line")
        fi
    done < <(eval "$cmd")
}

# Reduce lines from command to single value
# Usage: reduce_lines_from "command" reducer_function initial_value result_var
# Example:
#   sum_reducer() { echo $(($1 + $2)); }
#   reduce_lines_from "seq 1 5" sum_reducer 0 total
#   echo "$total"  # 15
# Returns: 0 on success
reduce_lines_from() {
    local cmd="$1"
    local reducer="$2"
    local initial="$3"
    local -n __rlf_result=$4

    __rlf_result="$initial"
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        __rlf_result=$("$reducer" "$__rlf_result" "$line")
    done < <(eval "$cmd")
}

# Compare two commands for equality
# Usage: commands_equal "cmd1" "cmd2"
# Example:
#   if commands_equal "cat file1 | sort" "cat file2 | sort"; then
#       echo "Files have same content"
#   fi
# Returns: 0 if outputs are identical, 1 otherwise
commands_equal() {
    local cmd1="$1"
    local cmd2="$2"

    diff -q <(eval "$cmd1") <(eval "$cmd2") >/dev/null 2>&1
}

# Read first N lines from command into array
# Usage: read_n_lines_from "command" n array_name
# Example:
#   read_n_lines_from "cat largefile.txt" 10 first_lines
#   echo "First 10 lines: ${first_lines[*]}"
# Returns: 0 on success
read_n_lines_from() {
    local cmd="$1"
    local n="$2"
    local -n __rnlf_arr=$3
    __rnlf_arr=()

    local line count=0
    while IFS= read -r line && [[ $count -lt $n ]]; do
        __rnlf_arr+=("$line")
        ((count++))
    done < <(eval "$cmd")

    [[ ${#__rnlf_arr[@]} -gt 0 ]]
}

# Process lines in batches
# Usage: batch_lines_from "command" batch_size callback
# Example:
#   process_batch() {
#       echo "Processing batch of ${#batch[@]} items"
#       printf '%s\n' "${batch[@]}"
#   }
#   batch_lines_from "seq 1 10" 3 process_batch
# Notes:
#   - The array 'batch' is available in the callback
#   - The variable 'batch_num' contains current batch number (1-based)
# Returns: 0 on success
batch_lines_from() {
    local cmd="$1"
    local batch_size="$2"
    local callback="$3"
    local -a batch=()
    local line
    local batch_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        batch+=("$line")

        if [[ ${#batch[@]} -ge $batch_size ]]; then
            ((batch_num++))
            eval "$callback"
            batch=()
        fi
    done < <(eval "$cmd")

    # Process remaining items
    if [[ ${#batch[@]} -gt 0 ]]; then
        ((batch_num++))
        eval "$callback"
    fi
}

# Interleave output from two commands
# Usage: interleave_commands "cmd1" "cmd2" result_array
# Example:
#   interleave_commands "echo -e 'a\nb'" "echo -e '1\n2'" merged
#   echo "${merged[@]}"  # a 1 b 2
# Returns: 0 on success
interleave_commands() {
    local cmd1="$1"
    local cmd2="$2"
    local -n __ic_arr=$3
    __ic_arr=()

    local line1 line2
    local fd1 fd2

    # Open process substitutions as file descriptors
    exec {fd1}< <(eval "$cmd1")
    exec {fd2}< <(eval "$cmd2")

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
count_lines_from() {
    local cmd="$1"
    local -n __clf_count=$2
    __clf_count=0

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((__clf_count++))
    done < <(eval "$cmd")
}

# Read key=value pairs from command into associative array
# Usage: read_pairs_from "command" assoc_array [delimiter]
# Example:
#   read_pairs_from "cat config.txt" config "="
#   echo "${config[key1]}"
# Returns: 0 on success
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
    done < <(eval "$cmd")
}

# =============================================================================
# EXPORT
# =============================================================================

export -f read_lines_from for_each_line diff_commands capture_output
export -f process_file tee_to_var
export -f map_lines_from filter_lines_from reduce_lines_from
export -f commands_equal read_n_lines_from batch_lines_from
export -f interleave_commands count_lines_from read_pairs_from

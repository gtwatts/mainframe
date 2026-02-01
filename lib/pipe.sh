#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/pipe.sh - Unix Pipeline Processing Library
# =============================================================================
# "The power of the shell is in the pipe." - Doug McIlroy
# =============================================================================
# Stream processing functions designed for maximum composability.
# Every function reads stdin OR args, writes stdout, enabling:
#   cat file | pipe_map upper | pipe_filter '[0-9]' | pipe_unique
# =============================================================================

[[ -n "${_MAINFRAME_PIPE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PIPE_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/common.sh"
source "${BASH_SOURCE%/*}/pure-string.sh"

# =============================================================================
# SECURITY: Command Validation
# =============================================================================

# Validate a command/expression for dangerous patterns
# Usage: _pipe_validate_cmd "command"
# Returns: 0 if safe, 1 if dangerous pattern detected
_pipe_validate_cmd() {
    local cmd="$1"

    # Block command substitution
    [[ "$cmd" == *'$('* ]] && return 1
    [[ "$cmd" == *'`'* ]] && return 1

    # Block dangerous operators
    [[ "$cmd" == *';'* ]] && return 1
    [[ "$cmd" == *'&&'* ]] && return 1
    [[ "$cmd" == *'||'* ]] && return 1

    # Block redirects that could write to arbitrary files
    [[ "$cmd" == *'>'* ]] && return 1
    [[ "$cmd" == *'>>'* ]] && return 1

    # Block backgrounding
    [[ "$cmd" == *'&'* ]] && return 1

    # Block eval and source
    [[ "$cmd" == *'eval '* ]] && return 1
    [[ "$cmd" == *'eval$'* ]] && return 1
    [[ "$cmd" == *'source '* ]] && return 1

    return 0
}

# Safe command execution via subprocess isolation
# Usage: _pipe_safe_exec "command" <<< "input"
_pipe_safe_exec() {
    local cmd="$1"

    # Validate command before execution
    if ! _pipe_validate_cmd "$cmd"; then
        printf 'pipe: blocked dangerous command pattern\n' >&2
        return 1
    fi

    # Execute in subprocess for isolation
    bash -c "$cmd"
}

# =============================================================================
# CORE STREAM PRIMITIVES
# =============================================================================

# Read input from stdin or arguments
# Usage: _pipe_input "$@" | while read -r line; do ...; done
# Returns: streams lines to stdout
_pipe_input() {
    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$@"
    elif [[ ! -t 0 ]]; then
        cat
    fi
}

# Apply a function/command to each line
# Usage: pipe_map <function> [args...]
# Example: echo -e "hello\nworld" | pipe_map 'tr a-z A-Z'
#          echo -e "foo\nbar" | pipe_map upper  # uses MAINFRAME upper()
# Security: Commands are validated for dangerous patterns before execution
pipe_map() {
    local func="$1"
    shift
    local extra_args=("$@")
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if declare -F "$func" &>/dev/null; then
            # It's a bash function - safe to call directly
            "$func" "$line" "${extra_args[@]}"
        elif type -p "$func" &>/dev/null; then
            # It's an external command - execute directly without shell interpretation
            printf '%s\n' "$line" | "$func" "${extra_args[@]}"
        else
            # It's a command expression - validate and use subprocess
            if _pipe_validate_cmd "$func"; then
                printf '%s\n' "$line" | bash -c "$func"
            else
                printf 'pipe_map: blocked dangerous command pattern: %s\n' "$func" >&2
                return 1
            fi
        fi
    done
}

# Filter lines matching a pattern (grep-like)
# Usage: pipe_filter <pattern> [-v]
# Example: echo -e "foo\nbar\nbaz" | pipe_filter 'ba'
#          echo -e "1\n2\n3" | pipe_filter '^[12]$'
pipe_filter() {
    local pattern="$1"
    local invert="${2:-}"

    if [[ "$invert" == "-v" ]]; then
        grep -v -E -- "$pattern" || true
    else
        grep -E -- "$pattern" || true
    fi
}

# Filter lines NOT matching a pattern
# Usage: pipe_reject <pattern>
pipe_reject() {
    pipe_filter "$1" -v
}

# Reduce/fold stream to single value
# Usage: pipe_reduce <function> [initial]
# Example: echo -e "1\n2\n3" | pipe_reduce 'expr $acc + $line' 0
# Security: Expression is validated for dangerous patterns
pipe_reduce() {
    local func="$1"
    local acc="${2:-}"
    local line first=1

    # Security: Validate the reducer expression upfront
    if ! _pipe_validate_cmd "$func"; then
        printf 'pipe_reduce: blocked dangerous expression pattern\n' >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $first -eq 1 && -z "$acc" ]]; then
            acc="$line"
            first=0
        else
            # Execute in subprocess with acc and line in environment
            acc=$(acc="$acc" line="$line" bash -c "$func")
        fi
    done
    printf '%s\n' "$acc"
}

# Take first N lines
# Usage: pipe_take <n>
# Example: echo -e "1\n2\n3\n4\n5" | pipe_take 3
pipe_take() {
    local n="${1:-10}"
    local count=0 line

    while IFS= read -r line && [[ $count -lt $n ]]; do
        printf '%s\n' "$line"
        ((count++))
    done
}

# Drop first N lines
# Usage: pipe_drop <n>
# Example: echo -e "1\n2\n3\n4\n5" | pipe_drop 2
pipe_drop() {
    local n="${1:-1}"
    local count=0 line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $count -ge $n ]]; then
            printf '%s\n' "$line"
        fi
        ((count++))
    done
}

# Take lines while condition is true
# Usage: pipe_take_while <pattern>
# Example: echo -e "1\n2\n3\na\n4" | pipe_take_while '^[0-9]'
pipe_take_while() {
    local pattern="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $pattern ]]; then
            printf '%s\n' "$line"
        else
            break
        fi
    done
}

# Drop lines while condition is true, then emit rest
# Usage: pipe_drop_while <pattern>
pipe_drop_while() {
    local pattern="$1"
    local line dropping=1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $dropping -eq 1 && "$line" =~ $pattern ]]; then
            continue
        fi
        dropping=0
        printf '%s\n' "$line"
    done
}

# =============================================================================
# DEDUPLICATION & SORTING
# =============================================================================

# Remove duplicate lines (preserves order, pure bash)
# Usage: pipe_unique
# Example: echo -e "a\nb\na\nc\nb" | pipe_unique
pipe_unique() {
    local -A seen
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "${seen[$line]:-}" ]]; then
            seen[$line]=1
            printf '%s\n' "$line"
        fi
    done
}

# Remove consecutive duplicate lines (like uniq)
# Usage: pipe_uniq
pipe_uniq() {
    local prev="" line first=1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $first -eq 1 ]] || [[ "$line" != "$prev" ]]; then
            printf '%s\n' "$line"
            first=0
        fi
        prev="$line"
    done
}

# Sort lines (wrapper with sane defaults)
# Usage: pipe_sort [-r] [-n] [-u]
pipe_sort() {
    sort "$@"
}

# Reverse line order
# Usage: pipe_reverse
# Example: echo -e "1\n2\n3" | pipe_reverse
pipe_reverse() {
    local -a lines
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done

    local i
    for ((i=${#lines[@]}-1; i>=0; i--)); do
        printf '%s\n' "${lines[i]}"
    done
}

# Shuffle lines randomly
# Usage: pipe_shuffle
pipe_shuffle() {
    local -a lines
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done

    local n=${#lines[@]}
    local i j tmp
    for ((i=n-1; i>0; i--)); do
        j=$((RANDOM % (i+1)))
        tmp="${lines[i]}"
        lines[i]="${lines[j]}"
        lines[j]="$tmp"
    done

    printf '%s\n' "${lines[@]}"
}

# =============================================================================
# FIELD PROCESSING (awk-like)
# =============================================================================

# Extract field(s) by position
# Usage: pipe_field <n> [delimiter]
# Example: echo "a:b:c" | pipe_field 2 ':'   # outputs: b
#          echo "a b c" | pipe_field 1       # outputs: a
pipe_field() {
    local field_num="$1"
    local delim="${2:- }"
    local line idx

    while IFS= read -r line || [[ -n "$line" ]]; do
        local IFS="$delim"
        local -a fields
        read -ra fields <<< "$line"

        # Calculate index fresh for each line
        if [[ $field_num -lt 0 ]]; then
            # Negative index from end
            idx=$((${#fields[@]} + field_num))
        else
            # Convert to 0-based
            idx=$((field_num - 1))
        fi

        if [[ $idx -ge 0 && $idx -lt ${#fields[@]} ]]; then
            printf '%s\n' "${fields[idx]}"
        else
            printf '\n'
        fi
    done
}

# Extract multiple fields
# Usage: pipe_fields <n1,n2,...> [delimiter] [output_delim]
# Example: echo "a:b:c:d" | pipe_fields 1,3 ':' ' '   # outputs: a c
pipe_fields() {
    local positions="$1"
    local delim="${2:- }"
    local out_delim="${3:-$delim}"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        local IFS="$delim"
        local -a fields result
        read -ra fields <<< "$line"

        IFS=',' read -ra pos_arr <<< "$positions"
        for p in "${pos_arr[@]}"; do
            local idx=$((p - 1))
            if [[ $idx -ge 0 && $idx -lt ${#fields[@]} ]]; then
                result+=("${fields[idx]}")
            fi
        done

        local IFS="$out_delim"
        printf '%s\n' "${result[*]}"
    done
}

# Count fields per line
# Usage: pipe_nf [delimiter]
# Example: echo "a b c" | pipe_nf    # outputs: 3
pipe_nf() {
    local delim="${1:- }"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        local IFS="$delim"
        local -a fields
        read -ra fields <<< "$line"
        printf '%d\n' "${#fields[@]}"
    done
}

# =============================================================================
# AGGREGATION
# =============================================================================

# Count lines
# Usage: pipe_count
pipe_count() {
    local count=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((count++))
    done
    printf '%d\n' "$count"
}

# Sum numeric values
# Usage: pipe_sum
# Example: echo -e "1\n2\n3" | pipe_sum   # outputs: 6
pipe_sum() {
    local sum=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            sum=$(awk "BEGIN {print $sum + $line}")
        fi
    done
    printf '%s\n' "$sum"
}

# Calculate average
# Usage: pipe_avg
pipe_avg() {
    local sum=0 count=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            sum=$(awk "BEGIN {print $sum + $line}")
            ((count++))
        fi
    done
    if [[ $count -gt 0 ]]; then
        awk "BEGIN {printf \"%.2f\n\", $sum / $count}"
    else
        printf '0\n'
    fi
}

# Find min value
# Usage: pipe_min
pipe_min() {
    local min="" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            if [[ -z "$min" ]] || awk "BEGIN {exit !($line < $min)}"; then
                min="$line"
            fi
        fi
    done
    [[ -n "$min" ]] && printf '%s\n' "$min"
}

# Find max value
# Usage: pipe_max
pipe_max() {
    local max="" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            if [[ -z "$max" ]] || awk "BEGIN {exit !($line > $max)}"; then
                max="$line"
            fi
        fi
    done
    [[ -n "$max" ]] && printf '%s\n' "$max"
}

# Group and count (like uniq -c but better)
# Usage: pipe_group_count [delimiter]
# Example: echo -e "a\nb\na\na" | pipe_group_count
pipe_group_count() {
    local -A counts
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((counts[$line]++))
    done

    for key in "${!counts[@]}"; do
        printf '%d\t%s\n' "${counts[$key]}" "$key"
    done
}

# =============================================================================
# LINE MANIPULATION
# =============================================================================

# Prepend string to each line
# Usage: pipe_prepend <prefix>
# Example: echo -e "foo\nbar" | pipe_prepend '> '
pipe_prepend() {
    local prefix="$1"
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s%s\n' "$prefix" "$line"
    done
}

# Append string to each line
# Usage: pipe_append <suffix>
pipe_append() {
    local suffix="$1"
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s%s\n' "$line" "$suffix"
    done
}

# Wrap each line
# Usage: pipe_wrap <prefix> <suffix>
# Example: echo -e "foo\nbar" | pipe_wrap '"' '"'
pipe_wrap() {
    local prefix="$1"
    local suffix="$2"
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s%s%s\n' "$prefix" "$line" "$suffix"
    done
}

# Number lines
# Usage: pipe_number [start] [format]
# Example: echo -e "a\nb\nc" | pipe_number 1 '%3d: '
pipe_number() {
    local start="${1:-1}"
    local fmt="${2:-%d\t}"
    local line n=$start

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf "$fmt%s\n" "$n" "$line"
        ((n++))
    done
}

# Replace pattern in each line
# Usage: pipe_replace <pattern> <replacement>
pipe_replace() {
    local pattern="$1"
    local replacement="$2"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "${line//$pattern/$replacement}"
    done
}

# =============================================================================
# JOINING & SPLITTING
# =============================================================================

# Join all lines with delimiter
# Usage: pipe_join [delimiter]
# Example: echo -e "a\nb\nc" | pipe_join ','   # outputs: a,b,c
pipe_join() {
    local delim="${1:-,}"
    local first=1 line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $first -eq 1 ]]; then
            printf '%s' "$line"
            first=0
        else
            printf '%s%s' "$delim" "$line"
        fi
    done
    printf '\n'
}

# Split line into multiple lines
# Usage: pipe_split [delimiter]
# Example: echo "a,b,c" | pipe_split ','
pipe_split() {
    local delim="${1:-,}"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        local IFS="$delim"
        local -a parts
        read -ra parts <<< "$line"
        printf '%s\n' "${parts[@]}"
    done
}

# Chunk lines into groups
# Usage: pipe_chunk <size> [delimiter]
# Example: echo -e "1\n2\n3\n4\n5" | pipe_chunk 2   # outputs groups of 2
pipe_chunk() {
    local size="${1:-1}"
    local delim="${2:-$'\n'}"
    local -a chunk
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        chunk+=("$line")
        if [[ ${#chunk[@]} -eq $size ]]; then
            local IFS="$delim"
            printf '%s\n' "${chunk[*]}"
            chunk=()
        fi
    done

    # Emit remaining
    if [[ ${#chunk[@]} -gt 0 ]]; then
        local IFS="$delim"
        printf '%s\n' "${chunk[*]}"
    fi
}

# =============================================================================
# CONDITIONALS
# =============================================================================

# Apply different transforms based on condition
# Usage: pipe_if <condition_pattern> <true_cmd> [false_cmd]
# Example: echo -e "1\n2\n3" | pipe_if '^[12]$' 'tr 0-9 a-j' 'cat'
# Security: Commands are validated for dangerous patterns
pipe_if() {
    local pattern="$1"
    local true_cmd="$2"
    local false_cmd="${3:-cat}"
    local line

    # Security: Validate both commands upfront
    if ! _pipe_validate_cmd "$true_cmd"; then
        printf 'pipe_if: blocked dangerous true_cmd pattern\n' >&2
        return 1
    fi
    if ! _pipe_validate_cmd "$false_cmd"; then
        printf 'pipe_if: blocked dangerous false_cmd pattern\n' >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $pattern ]]; then
            # Check if it's an external command we can call directly
            local first_word="${true_cmd%% *}"
            if type -p "$first_word" &>/dev/null && [[ "$true_cmd" == "$first_word" || "$true_cmd" == "$first_word "* ]]; then
                printf '%s\n' "$line" | $true_cmd
            else
                printf '%s\n' "$line" | bash -c "$true_cmd"
            fi
        else
            local first_word="${false_cmd%% *}"
            if type -p "$first_word" &>/dev/null && [[ "$false_cmd" == "$first_word" || "$false_cmd" == "$first_word "* ]]; then
                printf '%s\n' "$line" | $false_cmd
            else
                printf '%s\n' "$line" | bash -c "$false_cmd"
            fi
        fi
    done
}

# =============================================================================
# PARALLEL PROCESSING
# =============================================================================

# Process lines in parallel (requires GNU parallel or xargs -P)
# Usage: pipe_parallel <command> [jobs]
# Example: echo -e "1\n2\n3" | pipe_parallel 'sleep {} && echo done-{}' 3
pipe_parallel() {
    local cmd="$1"
    local jobs="${2:-4}"

    if command -v parallel &>/dev/null; then
        parallel -j "$jobs" "$cmd"
    else
        xargs -P "$jobs" -I {} bash -c "$cmd"
    fi
}

# =============================================================================
# DEBUGGING & INSPECTION
# =============================================================================

# Tee to stderr (inspect stream without disrupting)
# Usage: pipe_peek [prefix]
# Example: echo -e "a\nb" | pipe_peek '[DEBUG]' | pipe_map upper
pipe_peek() {
    local prefix="${1:-}"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$prefix" ]]; then
            printf '%s %s\n' "$prefix" "$line" >&2
        else
            printf '%s\n' "$line" >&2
        fi
        printf '%s\n' "$line"
    done
}

# Assert stream is not empty
# Usage: pipe_assert_nonempty [message]
pipe_assert_nonempty() {
    local msg="${1:-Stream is empty}"
    local line found=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        found=1
        printf '%s\n' "$line"
    done

    if [[ $found -eq 0 ]]; then
        printf '%s\n' "$msg" >&2
        return 1
    fi
}

# =============================================================================
# STDIN-AWARE WRAPPERS
# =============================================================================
# These wrap common operations to be stdin-aware

# Upper-case (stdin-aware)
pipe_upper() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "${line^^}"
    done
}

# Lower-case (stdin-aware)
pipe_lower() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "${line,,}"
    done
}

# Trim whitespace (stdin-aware)
pipe_trim() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading
        line="${line#"${line%%[![:space:]]*}"}"
        # Trim trailing
        line="${line%"${line##*[![:space:]]}"}"
        printf '%s\n' "$line"
    done
}

# Length of each line (stdin-aware)
pipe_length() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%d\n' "${#line}"
    done
}

# =============================================================================
# EXPORT
# =============================================================================

export -f _pipe_input _pipe_validate_cmd _pipe_safe_exec pipe_map pipe_filter pipe_reject pipe_reduce
export -f pipe_take pipe_drop pipe_take_while pipe_drop_while
export -f pipe_unique pipe_uniq pipe_sort pipe_reverse pipe_shuffle
export -f pipe_field pipe_fields pipe_nf
export -f pipe_count pipe_sum pipe_avg pipe_min pipe_max pipe_group_count
export -f pipe_prepend pipe_append pipe_wrap pipe_number pipe_replace
export -f pipe_join pipe_split pipe_chunk
export -f pipe_if pipe_parallel
export -f pipe_peek pipe_assert_nonempty
export -f pipe_upper pipe_lower pipe_trim pipe_length

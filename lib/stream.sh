#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/stream.sh - Advanced Stream Processing Paradigms
# =============================================================================
# "In Unix, everything is a file. And every file is a stream."
# =============================================================================
# Advanced streaming patterns for lethal shell scripting:
# - Record-based processing (multi-line records)
# - State machines (stateful stream transforms)
# - Multi-stream operations (merge, zip, diff)
# - Fan-out/fan-in (parallel processing with results merge)
# - Windowing (sliding, tumbling, session windows)
# - Backpressure and buffering
# =============================================================================

[[ -n "${_MAINFRAME_STREAM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_STREAM_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/common.sh"
source "${BASH_SOURCE%/*}/pipe.sh"

# =============================================================================
# RECORD-BASED PROCESSING
# =============================================================================

# Process multi-line records separated by delimiter
# Usage: stream_records <delimiter> <command>
# Example: stream_records '---' 'wc -l'   # count lines per record
stream_records() {
    local delim="$1"
    local cmd="$2"
    local record="" line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$delim" ]]; then
            if [[ -n "$record" ]]; then
                printf '%s' "$record" | eval "$cmd"
            fi
            record=""
        else
            record+="$line"$'\n'
        fi
    done

    # Final record
    if [[ -n "$record" ]]; then
        printf '%s' "$record" | eval "$cmd"
    fi
}

# Process records by blank-line separation (paragraph mode)
# Usage: stream_paragraphs <command>
stream_paragraphs() {
    local cmd="$1"
    local record="" line in_record=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            if [[ $in_record -eq 1 ]]; then
                printf '%s' "$record" | eval "$cmd"
                record=""
                in_record=0
            fi
        else
            in_record=1
            record+="$line"$'\n'
        fi
    done

    # Final record
    if [[ -n "$record" ]]; then
        printf '%s' "$record" | eval "$cmd"
    fi
}

# Process fixed-size record blocks (N lines per record)
# Usage: stream_blocks <n> <command>
# Example: echo -e "a\nb\nc\nd\ne\nf" | stream_blocks 2 'paste -sd,'
stream_blocks() {
    local n="$1"
    local cmd="$2"
    local -a block
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        block+=("$line")
        if [[ ${#block[@]} -eq $n ]]; then
            printf '%s\n' "${block[@]}" | eval "$cmd"
            block=()
        fi
    done

    # Handle remainder
    if [[ ${#block[@]} -gt 0 ]]; then
        printf '%s\n' "${block[@]}" | eval "$cmd"
    fi
}

# =============================================================================
# STATE MACHINES
# =============================================================================

# Process stream with state transitions
# Usage: stream_state <initial_state> <transition_func>
# transition_func receives: $state $line, should output: new_state [output]
# Example: Count balanced braces
stream_state() {
    local state="$1"
    local transition_func="$2"
    local line result

    while IFS= read -r line || [[ -n "$line" ]]; do
        result=$("$transition_func" "$state" "$line")
        state="${result%%$'\n'*}"
        output="${result#*$'\n'}"
        [[ "$output" != "$result" ]] && printf '%s\n' "$output"
    done
}

# Track context depth (brackets, tags, etc)
# Usage: stream_depth <open_pattern> <close_pattern>
# Example: echo -e "{\n  x\n  {\n    y\n  }\n}" | stream_depth '{' '}'
stream_depth() {
    local open="$1"
    local close="$2"
    local depth=0 line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Count opens and closes on this line
        local opens closes
        opens=$(printf '%s' "$line" | grep -o "$open" | wc -l)
        closes=$(printf '%s' "$line" | grep -o "$close" | wc -l)

        printf '%d\t%s\n' "$depth" "$line"
        depth=$((depth + opens - closes))
    done
}

# Accumulate until pattern, then emit
# Usage: stream_collect_until <pattern>
# Example: Collect SQL until semicolon
stream_collect_until() {
    local pattern="$1"
    local buffer="" line

    while IFS= read -r line || [[ -n "$line" ]]; do
        buffer+="$line"$'\n'
        if [[ "$line" =~ $pattern ]]; then
            printf '%s' "$buffer"
            buffer=""
        fi
    done

    # Emit any remaining
    [[ -n "$buffer" ]] && printf '%s' "$buffer"
}

# =============================================================================
# MULTI-STREAM OPERATIONS
# =============================================================================

# Merge two sorted streams
# Usage: stream_merge <file1> <file2>
stream_merge() {
    local file1="$1"
    local file2="$2"
    sort -m "$file1" "$file2"
}

# Zip two streams together (line by line)
# Usage: stream_zip <file> [delimiter]
# Example: echo -e "a\nb" | stream_zip <(echo -e "1\n2") ':'
stream_zip() {
    local file="$1"
    local delim="${2:-$'\t'}"
    paste -d"$delim" - "$file"
}

# Diff two streams
# Usage: stream_diff <file>
# Input from stdin is compared with file
stream_diff() {
    local file="$1"
    diff - "$file"
}

# Interleave streams (round-robin)
# Usage: stream_interleave <file1> <file2> ...
stream_interleave() {
    local -a files=("$@")
    local -a fds
    local i line done=0

    # Open all files
    for i in "${!files[@]}"; do
        exec {fds[i]}<"${files[i]}"
    done

    while [[ $done -eq 0 ]]; do
        done=1
        for i in "${!fds[@]}"; do
            if IFS= read -r line <&"${fds[i]}"; then
                printf '%s\n' "$line"
                done=0
            fi
        done
    done

    # Close all
    for fd in "${fds[@]}"; do
        exec {fd}<&-
    done
}

# =============================================================================
# WINDOWING OPERATIONS
# =============================================================================

# Sliding window of N elements
# Usage: stream_window <size> [step]
# Example: echo -e "1\n2\n3\n4\n5" | stream_window 3 1
stream_window() {
    local size="$1"
    local step="${2:-1}"
    local -a window
    local line count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        window+=("$line")
        ((count++))

        if [[ ${#window[@]} -eq $size ]]; then
            printf '%s\n' "${window[*]}"
            # Slide by step
            window=("${window[@]:$step}")
        fi
    done

    # Emit partial window at end if any
    if [[ ${#window[@]} -gt 0 && ${#window[@]} -lt $size ]]; then
        printf '%s\n' "${window[*]}"
    fi
}

# Tumbling window (non-overlapping)
# Usage: stream_tumble <size>
stream_tumble() {
    stream_window "$1" "$1"
}

# Session window (group by time gaps - simulated with line gaps)
# Usage: stream_session <max_gap>
# Groups lines until a line matching __GAP__ or N consecutive empty lines
stream_session() {
    local max_gap="$1"
    local -a session
    local gap_count=0 line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            ((gap_count++))
            if [[ $gap_count -ge $max_gap && ${#session[@]} -gt 0 ]]; then
                printf '%s\n' "${session[*]}"
                session=()
            fi
        else
            gap_count=0
            session+=("$line")
        fi
    done

    [[ ${#session[@]} -gt 0 ]] && printf '%s\n' "${session[*]}"
}

# =============================================================================
# FAN-OUT / FAN-IN PATTERNS
# =============================================================================

# Fan-out: duplicate stream to multiple commands
# Usage: stream_fanout <cmd1> <cmd2> ...
# Example: echo "data" | stream_fanout 'wc -c' 'md5sum' 'sha256sum'
stream_fanout() {
    local -a cmds=("$@")
    local temp_dir=$(mktemp -d)
    local input=$(cat)
    local i

    # Run all commands in parallel
    for i in "${!cmds[@]}"; do
        printf '%s' "$input" | eval "${cmds[i]}" > "$temp_dir/out_$i" &
    done
    wait

    # Output results
    for i in "${!cmds[@]}"; do
        cat "$temp_dir/out_$i"
    done

    rm -rf "$temp_dir"
}

# Distribute lines round-robin to N workers
# Usage: stream_distribute <n> <command>
stream_distribute() {
    local n="$1"
    local cmd="$2"
    local -a fifos pids
    local i line count=0 temp_dir

    temp_dir=$(mktemp -d)

    # Create FIFOs and start workers
    for ((i=0; i<n; i++)); do
        fifos[i]="$temp_dir/fifo_$i"
        mkfifo "${fifos[i]}"
        eval "$cmd" < "${fifos[i]}" &
        pids[i]=$!
    done

    # Distribute lines
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line" > "${fifos[$((count % n))]}"
        ((count++))
    done

    # Close FIFOs
    for fifo in "${fifos[@]}"; do
        exec 3>"$fifo"
        exec 3>&-
    done

    wait
    rm -rf "$temp_dir"
}

# =============================================================================
# BUFFERING AND FLOW CONTROL
# =============================================================================

# Buffer N lines before emitting
# Usage: stream_buffer <n>
stream_buffer() {
    local n="$1"
    local -a buffer
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        buffer+=("$line")
        if [[ ${#buffer[@]} -ge $n ]]; then
            printf '%s\n' "${buffer[@]}"
            buffer=()
        fi
    done

    # Emit remainder
    [[ ${#buffer[@]} -gt 0 ]] && printf '%s\n' "${buffer[@]}"
}

# Rate limit output (lines per second)
# Usage: stream_throttle <lines_per_sec>
stream_throttle() {
    local rate="$1"
    local delay=$(awk "BEGIN {print 1/$rate}")
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line"
        sleep "$delay"
    done
}

# Debounce - only emit after quiet period
# Usage: stream_debounce <seconds>
stream_debounce() {
    local seconds="$1"
    local line last=""

    while IFS= read -t "$seconds" -r line || [[ -n "$line" ]]; do
        last="$line"
    done

    [[ -n "$last" ]] && printf '%s\n' "$last"
}

# =============================================================================
# PATTERN MATCHING PARADIGMS
# =============================================================================

# Extract matches from stream
# Usage: stream_extract <pattern>
# Example: echo "email: foo@bar.com" | stream_extract '[a-z]+@[a-z]+\.[a-z]+'
stream_extract() {
    local pattern="$1"
    grep -oE "$pattern"
}

# Transform matching lines, pass others through
# Usage: stream_transform <pattern> <command>
stream_transform() {
    local pattern="$1"
    local cmd="$2"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $pattern ]]; then
            printf '%s\n' "$line" | eval "$cmd"
        else
            printf '%s\n' "$line"
        fi
    done
}

# Context grep - show N lines around matches
# Usage: stream_context <pattern> <before> <after>
stream_context() {
    local pattern="$1"
    local before="${2:-2}"
    local after="${3:-2}"
    grep -B "$before" -A "$after" "$pattern"
}

# =============================================================================
# CONDITIONAL FLOWS
# =============================================================================

# Branch stream based on pattern
# Usage: stream_branch <pattern> <match_file> <nomatch_file>
stream_branch() {
    local pattern="$1"
    local match_file="$2"
    local nomatch_file="$3"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $pattern ]]; then
            printf '%s\n' "$line" >> "$match_file"
        else
            printf '%s\n' "$line" >> "$nomatch_file"
        fi
    done
}

# Route lines to different outputs based on patterns
# Usage: stream_route "pattern1:file1" "pattern2:file2" "default:file3"
stream_route() {
    local -a routes=("$@")
    local line matched

    while IFS= read -r line || [[ -n "$line" ]]; do
        matched=0
        for route in "${routes[@]}"; do
            local pattern="${route%%:*}"
            local file="${route#*:}"
            if [[ "$pattern" == "default" ]]; then
                continue
            elif [[ "$line" =~ $pattern ]]; then
                printf '%s\n' "$line" >> "$file"
                matched=1
                break
            fi
        done
        if [[ $matched -eq 0 ]]; then
            for route in "${routes[@]}"; do
                if [[ "${route%%:*}" == "default" ]]; then
                    printf '%s\n' "$line" >> "${route#*:}"
                    break
                fi
            done
        fi
    done
}

# =============================================================================
# AGGREGATION PARADIGMS
# =============================================================================

# Group by key field and aggregate
# Usage: stream_group_by <field> <delimiter> <agg_cmd>
# Example: echo -e "a:1\na:2\nb:3" | stream_group_by 1 ':' 'paste -sd+ | bc'
stream_group_by() {
    local field="$1"
    local delim="$2"
    local agg_cmd="$3"
    local -A groups
    local line key

    while IFS= read -r line || [[ -n "$line" ]]; do
        local IFS="$delim"
        local -a parts
        read -ra parts <<< "$line"
        key="${parts[$((field-1))]}"
        groups[$key]+="$line"$'\n'
    done

    for key in "${!groups[@]}"; do
        printf '%s\t%s\n' "$key" "$(printf '%s' "${groups[$key]}" | eval "$agg_cmd")"
    done
}

# Top N by value
# Usage: stream_top <n> [field] [delimiter]
stream_top() {
    local n="$1"
    local field="${2:-1}"
    local delim="${3:- }"
    sort -t"$delim" -k"$field" -rn | head -n "$n"
}

# Bottom N by value
# Usage: stream_bottom <n> [field] [delimiter]
stream_bottom() {
    local n="$1"
    local field="${2:-1}"
    local delim="${3:- }"
    sort -t"$delim" -k"$field" -n | head -n "$n"
}

# =============================================================================
# COMPOSITION HELPERS
# =============================================================================

# Chain multiple operations (for readability)
# Usage: stream_chain 'cmd1' 'cmd2' 'cmd3'
# Example: echo "data" | stream_chain 'tr a-z A-Z' 'grep X' 'wc -l'
stream_chain() {
    local line
    local -a cmds=("$@")

    # Build pipeline dynamically
    local pipeline=""
    for cmd in "${cmds[@]}"; do
        if [[ -n "$pipeline" ]]; then
            pipeline+=" | $cmd"
        else
            pipeline="$cmd"
        fi
    done

    eval "$pipeline"
}

# Retry failed pipeline with backoff
# Usage: stream_retry <max_attempts> <command>
stream_retry() {
    local max="$1"
    shift
    local cmd="$*"
    local attempt=1

    while [[ $attempt -le $max ]]; do
        if eval "$cmd"; then
            return 0
        fi
        sleep $((attempt * 2))
        ((attempt++))
    done
    return 1
}

# =============================================================================
# EXPORT
# =============================================================================

export -f stream_records stream_paragraphs stream_blocks
export -f stream_state stream_depth stream_collect_until
export -f stream_merge stream_zip stream_diff stream_interleave
export -f stream_window stream_tumble stream_session
export -f stream_fanout stream_distribute
export -f stream_buffer stream_throttle stream_debounce
export -f stream_extract stream_transform stream_context
export -f stream_branch stream_route
export -f stream_group_by stream_top stream_bottom
export -f stream_chain stream_retry

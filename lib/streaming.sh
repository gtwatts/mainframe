#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/streaming.sh - Stream Processing Library v7.4
# =============================================================================
# Description: Functional stream processing primitives for AI agent workflows.
#              Provides map, filter, reduce, parallel processing, rate limiting,
#              type-aware pipes, and USOP-compliant JSON output.
#
# Version: 1.0.0
# Requires: Bash 4.3+ (for namerefs)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_STREAMING_LOADED:-}" ]] && return 0
readonly _MAINFRAME_STREAMING_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default parallel workers
STREAMING_DEFAULT_WORKERS="${STREAMING_DEFAULT_WORKERS:-4}"

# Default batch size
STREAMING_DEFAULT_BATCH_SIZE="${STREAMING_DEFAULT_BATCH_SIZE:-100}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON escape for USOP output
_streaming_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

_streaming_valid_var_name() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

_streaming_array_clear() {
    local array_name="$1"

    _streaming_valid_var_name "$array_name" || return 1
    eval "$array_name=()"
}

_streaming_array_append() {
    local array_name="$1"
    local _streaming_item="$2"

    _streaming_valid_var_name "$array_name" || return 1
    eval "$array_name+=(\"\$_streaming_item\")"
}

_streaming_run_pipe_processor() {
    local processor="$1"

    if declare -F "$processor" >/dev/null 2>&1; then
        "$processor"
    elif [[ "$processor" == *[[:space:]]* ]]; then
        bash -lc "$processor"
    else
        "$processor"
    fi
}

_streaming_key_for_line() {
    local key_fn="$1"
    local line="$2"

    if declare -F "$key_fn" >/dev/null 2>&1; then
        "$key_fn" "$line"
    elif [[ "$key_fn" == *[[:space:]]* ]]; then
        printf '%s\n' "$line" | bash -lc "$key_fn"
    else
        "$key_fn" <<< "$line"
    fi
}

# =============================================================================
# CORE STREAMING FUNCTIONS
# =============================================================================

# @pre: fn is a valid function name, input is stdin or file path
# @post: each line transformed by fn
# @idempotent: yes
# @returns: transformed stream to stdout
#
# Apply function to each line of input
# Usage: echo -e "1\n2\n3" | stream_map double
# Usage: stream_map double < file.txt
stream_map() {
    local fn="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        "$fn" "$line"
    done
}

# @pre: fn is a valid function name, result_array is a valid variable name
# @post: result_array contains transformed elements
# @idempotent: yes
# @returns: 0 on success
#
# Map with nameref output (no subshells)
# Usage: stream_map_v result_array "double" 1 2 3 4 5
stream_map_v() {
    local result_name="$1"
    local fn="$2"
    shift 2

    _streaming_array_clear "$result_name" || return 1

    local item tmp
    for item in "$@"; do
        tmp=$("$fn" "$item")
        _streaming_array_append "$result_name" "$tmp" || return 1
    done
}

# @pre: predicate is a valid function returning 0/1
# @post: only lines matching predicate pass through
# @idempotent: yes
# @returns: filtered stream to stdout
#
# Filter lines by predicate function
# Usage: echo -e "1\n2\n3\n4" | stream_filter is_even
stream_filter() {
    local predicate="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if "$predicate" "$line"; then
            printf '%s\n' "$line"
        fi
    done
}

# @pre: predicate is a valid function, result_array is valid variable name
# @post: result_array contains filtered elements
# @idempotent: yes
# @returns: 0 on success
#
# Filter with nameref output (no subshells)
# Usage: stream_filter_v result_array "is_even" 1 2 3 4 5
stream_filter_v() {
    local result_name="$1"
    local predicate="$2"
    shift 2

    _streaming_array_clear "$result_name" || return 1

    local item
    for item in "$@"; do
        if "$predicate" "$item"; then
            _streaming_array_append "$result_name" "$item" || return 1
        fi
    done
}

# @pre: fn is binary function, init is initial accumulator value
# @post: single value from folding all input
# @idempotent: yes
# @returns: reduced value to stdout
#
# Fold stream to single value
# Usage: echo -e "1\n2\n3" | stream_reduce sum 0
stream_reduce() {
    local fn="$1"
    local acc="$2"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        acc=$("$fn" "$acc" "$line")
    done

    printf '%s\n' "$acc"
}

# @pre: result is valid variable name, fn is binary function
# @post: result contains reduced value
# @idempotent: yes
# @returns: 0 on success
#
# Reduce with nameref output (no subshells for iteration)
# Usage: stream_reduce_v result "sum" 0 1 2 3 4 5
stream_reduce_v() {
    local result_name="$1"
    local fn="$2"
    local acc="$3"
    shift 3

    _streaming_valid_var_name "$result_name" || return 1

    local item
    for item in "$@"; do
        acc=$("$fn" "$acc" "$item")
    done
    printf -v "$result_name" '%s' "$acc"
}

# @pre: n is positive integer
# @post: first n lines emitted
# @idempotent: yes
# @returns: truncated stream to stdout
#
# Take first N items from stream
# Usage: cat bigfile.txt | stream_take 10
stream_take() {
    local n="$1"
    local count=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((count >= n)) && break
        printf '%s\n' "$line"
        ((count++))
    done
}

# @pre: n is positive integer
# @post: first n lines skipped
# @idempotent: yes
# @returns: stream without first n items
#
# Skip first N items from stream
# Usage: cat file.txt | stream_skip 5
stream_skip() {
    local n="$1"
    local count=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if ((count >= n)); then
            printf '%s\n' "$line"
        fi
        ((count++))
    done
}

# @pre: n is positive integer
# @post: first n lines emitted
# @idempotent: yes
# @returns: first n lines (alias for stream_take)
#
# First N lines (alias for stream_take)
# Usage: cat file.txt | stream_head 5
stream_head() {
    stream_take "$@"
}

# @pre: n is positive integer
# @post: last n lines emitted
# @idempotent: yes
# @returns: last n lines
#
# Last N lines from stream
# Usage: cat file.txt | stream_tail 5
stream_tail() {
    local n="$1"
    local -a buffer=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        buffer+=("$line")
        if ((${#buffer[@]} > n)); then
            buffer=("${buffer[@]:1}")
        fi
    done

    local item
    for item in "${buffer[@]}"; do
        printf '%s\n' "$item"
    done
}

# @pre: none
# @post: duplicate lines removed (preserves first occurrence)
# @idempotent: yes
# @returns: deduplicated stream
#
# Remove duplicate lines (preserves order)
# Usage: cat file.txt | stream_unique
stream_unique() {
    local -A seen=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "${seen[$line]:-}" ]]; then
            seen[$line]=1
            printf '%s\n' "$line"
        fi
    done
}

# @pre: none
# @post: lines sorted alphabetically
# @idempotent: yes
# @returns: sorted stream
#
# Sort stream alphabetically
# Usage: cat file.txt | stream_sort
stream_sort() {
    sort "$@"
}

# @pre: none
# @post: lines in reverse order
# @idempotent: no (applying twice restores original)
# @returns: reversed stream
#
# Reverse stream order
# Usage: cat file.txt | stream_reverse
stream_reverse() {
    local -a lines=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done

    local i
    for ((i=${#lines[@]}-1; i>=0; i--)); do
        printf '%s\n' "${lines[$i]}"
    done
}

# =============================================================================
# PARALLEL STREAMING FUNCTIONS
# =============================================================================

# @pre: fn is valid function, workers is positive integer
# @post: input processed in parallel by workers
# @idempotent: yes (output order may vary)
# @returns: transformed stream (unordered)
#
# Parallel map with worker pool
# Usage: cat urls.txt | stream_parallel curl_fetch 4
stream_parallel() {
    local fn="$1"
    local workers="${2:-$STREAMING_DEFAULT_WORKERS}"

    local temp_dir fifo_in fifo_out
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/streaming_parallel.XXXXXX")
    fifo_in="$temp_dir/in"
    fifo_out="$temp_dir/out"
    mkfifo "$fifo_in" "$fifo_out"

    # Start worker processes
    local i
    for ((i=0; i<workers; i++)); do
        (
            while IFS= read -r line; do
                "$fn" "$line"
            done
        ) < "$fifo_in" >> "$fifo_out" &
    done

    # Feed input and read output in parallel
    {
        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '%s\n' "$line"
        done > "$fifo_in"
        # Close input FIFO to signal EOF
        exec 3>"$fifo_in"
        exec 3>&-
    } &

    cat "$fifo_out"

    wait
    rm -rf "$temp_dir"
}

# @pre: size is positive integer, fn is valid function
# @post: input processed in batches of size
# @idempotent: yes
# @returns: batch-processed results
#
# Process stream in batches
# Usage: cat items.txt | stream_batch 10 process_batch
stream_batch() {
    local size="$1"
    local fn="$2"
    local -a batch=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        batch+=("$line")
        if ((${#batch[@]} >= size)); then
            printf '%s\n' "${batch[@]}" | _streaming_run_pipe_processor "$fn"
            batch=()
        fi
    done

    # Process remaining items
    if ((${#batch[@]} > 0)); then
        printf '%s\n' "${batch[@]}" | _streaming_run_pipe_processor "$fn"
    fi
}

# @pre: size is positive integer
# @post: stream split into size-line chunks
# @idempotent: yes
# @returns: chunked stream with separator
#
# Split stream into chunks of N lines
# Usage: cat file.txt | stream_chunk 5
stream_chunk() {
    local size="$1"
    local separator="${2:-}"
    local -a chunk=()
    local line first_chunk=true

    while IFS= read -r line || [[ -n "$line" ]]; do
        chunk+=("$line")
        if ((${#chunk[@]} >= size)); then
            if [[ -n "$separator" ]] && ! $first_chunk; then
                printf '%s\n' "$separator"
            fi
            first_chunk=false
            printf '%s\n' "${chunk[@]}"
            chunk=()
        fi
    done

    # Emit remaining chunk
    if ((${#chunk[@]} > 0)); then
        if [[ -n "$separator" ]] && ! $first_chunk; then
            printf '%s\n' "$separator"
        fi
        printf '%s\n' "${chunk[@]}"
    fi
}

# @pre: n is positive integer, fns are valid function names
# @post: input split to n processors
# @idempotent: yes
# @returns: combined output from all processors
#
# Fan out stream to multiple processors
# Usage: cat data.txt | stream_fanout 3 proc1 proc2 proc3
stream_fanout() {
    local n="$1"
    shift
    local -a fns=("$@")

    # Validate we have enough functions
    if ((${#fns[@]} < n)); then
        echo "stream_fanout: need $n functions, got ${#fns[@]}" >&2
        return 1
    fi

    local temp_dir
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/streaming_fanout.XXXXXX")

    # Preserve exact input bytes, including trailing newlines.
    local input_file="$temp_dir/input"
    cat > "$input_file"

    # Run each processor
    local i
    for ((i=0; i<n; i++)); do
        _streaming_run_pipe_processor "${fns[$i]}" < "$input_file" > "$temp_dir/out_$i" &
    done
    wait

    # Combine output
    for ((i=0; i<n; i++)); do
        cat "$temp_dir/out_$i"
    done

    rm -rf "$temp_dir"
}

# @pre: files exist and are readable
# @post: streams merged in round-robin fashion
# @idempotent: yes
# @returns: interleaved stream
#
# Merge multiple streams (files or FDs)
# Usage: stream_fanin file1.txt file2.txt file3.txt
stream_fanin() {
    local -a files=("$@")

    if ((${#files[@]} == 0)); then
        cat  # Just pass through stdin
        return
    fi

    # Interleave lines from all files
    local -a fds=()
    local i line done_count=0

    # Open all files
    for i in "${!files[@]}"; do
        exec {fds[i]}<"${files[i]}"
    done

    # Read round-robin until all exhausted
    while ((done_count < ${#files[@]})); do
        done_count=0
        for i in "${!fds[@]}"; do
            if [[ -n "${fds[i]:-}" ]]; then
                if IFS= read -r line <&"${fds[i]}"; then
                    printf '%s\n' "$line"
                else
                    exec {fds[i]}<&-
                    fds[i]=""
                    ((done_count++))
                fi
            else
                ((done_count++))
            fi
        done
    done
}

# @pre: n is positive integer, period is time spec (e.g., "1s", "100ms")
# @post: output rate limited to n items per period
# @idempotent: yes
# @returns: rate-limited stream
#
# Rate limit stream output
# Usage: cat requests.txt | stream_rate_limit 10 1s
stream_rate_limit() {
    local n="$1"
    local period="${2:-1s}"
    local count=0
    local line

    # Convert period to seconds
    local delay
    case "$period" in
        *ms) delay=$(awk "BEGIN {print ${period%ms}/1000}") ;;
        *s)  delay="${period%s}" ;;
        *m)  delay=$((${period%m} * 60)) ;;
        *)   delay="$period" ;;
    esac

    local interval
    interval=$(awk "BEGIN {print $delay / $n}")

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line"
        sleep "$interval"
    done
}

# =============================================================================
# TYPE-AWARE STREAMING FUNCTIONS
# =============================================================================

# @pre: input is NDJSON (newline-delimited JSON)
# @post: each line parsed and passed to callback or emitted
# @idempotent: yes
# @returns: parsed JSON stream
#
# Parse JSON lines (NDJSON format)
# Usage: cat data.ndjson | stream_json_lines
stream_json_lines() {
    local fn="${1:-}"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "${line// /}" ]] && continue

        # Basic JSON validation
        if [[ "$line" =~ ^\{.*\}$ ]] || [[ "$line" =~ ^\[.*\]$ ]]; then
            if [[ -n "$fn" ]]; then
                "$fn" "$line"
            else
                printf '%s\n' "$line"
            fi
        fi
    done
}

# @pre: input is valid CSV with optional header
# @post: each line converted to array or JSON
# @idempotent: yes
# @returns: parsed CSV stream
#
# Parse CSV lines (handles quoted fields)
# Usage: cat data.csv | stream_csv_lines
stream_csv_lines() {
    local include_header="${1:-false}"
    local delimiter="${2:-,}"
    local first_line=true
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip header unless requested
        if $first_line; then
            first_line=false
            if [[ "$include_header" != "true" ]]; then
                continue
            fi
        fi

        printf '%s\n' "$line"
    done
}

# @pre: none
# @post: detected type emitted
# @idempotent: yes
# @returns: type string (json, csv, text, binary)
#
# Auto-detect stream content type
# Usage: cat file | stream_detect_type
stream_detect_type() {
    local -a sample=()
    local line count=0

    # Sample first 10 lines
    while IFS= read -r line && ((count < 10)); do
        sample+=("$line")
        ((count++))
    done

    # Pass through remaining content
    printf '%s\n' "${sample[@]}"
    cat

    # Detect type from sample
    local type="text"
    local json_count=0 csv_count=0

    for line in "${sample[@]}"; do
        # Check for JSON
        if [[ "$line" =~ ^\{.*\}$ ]] || [[ "$line" =~ ^\[.*\]$ ]]; then
            ((json_count++))
        fi
        # Check for CSV (has commas and consistent field count)
        if [[ "$line" == *,* ]]; then
            ((csv_count++))
        fi
    done

    # Determine type based on sample
    if ((json_count > count / 2)); then
        type="json"
    elif ((csv_count > count / 2)); then
        type="csv"
    fi

    # Output type to stderr (stream passes through stdout)
    echo "$type" >&2
}

# @pre: schema_fn is function that validates each line
# @post: invalid lines skipped or error emitted
# @idempotent: yes
# @returns: validated stream
#
# Validate stream against schema function
# Usage: cat data.json | stream_validate is_valid_json
stream_validate() {
    local schema_fn="$1"
    local strict="${2:-false}"
    local line line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        if "$schema_fn" "$line"; then
            printf '%s\n' "$line"
        elif [[ "$strict" == "true" ]]; then
            echo "stream_validate: line $line_num failed validation" >&2
            return 1
        fi
    done
}

# =============================================================================
# ADDITIONAL STREAM OPERATIONS
# =============================================================================

# @pre: none
# @post: count emitted to stdout
# @idempotent: yes
# @returns: number of lines
#
# Count lines in stream
# Usage: cat file.txt | stream_count
stream_count() {
    local count=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((count++))
    done

    printf '%d\n' "$count"
}

# @pre: predicate is valid function
# @post: returns 0 if any line matches, 1 otherwise
# @idempotent: yes
# @returns: exit code 0/1
#
# Check if any line matches predicate
# Usage: cat file.txt | stream_any is_error && echo "found errors"
stream_any() {
    local predicate="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if "$predicate" "$line"; then
            return 0
        fi
    done
    return 1
}

# @pre: predicate is valid function
# @post: returns 0 if all lines match, 1 otherwise
# @idempotent: yes
# @returns: exit code 0/1
#
# Check if all lines match predicate
# Usage: cat file.txt | stream_all is_valid && echo "all valid"
stream_all() {
    local predicate="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if ! "$predicate" "$line"; then
            return 1
        fi
    done
    return 0
}

# @pre: predicate is valid function
# @post: returns 0 if no lines match, 1 otherwise
# @idempotent: yes
# @returns: exit code 0/1
#
# Check if no lines match predicate
# Usage: cat file.txt | stream_none is_empty && echo "no empty lines"
stream_none() {
    local predicate="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if "$predicate" "$line"; then
            return 1
        fi
    done
    return 0
}

# @pre: predicate is valid function
# @post: first matching line emitted
# @idempotent: yes
# @returns: first match or exit 1 if not found
#
# Find first matching line
# Usage: cat file.txt | stream_find 'grep -q error'
stream_find() {
    local predicate="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if "$predicate" "$line"; then
            printf '%s\n' "$line"
            return 0
        fi
    done
    return 1
}

# @pre: predicate holds initially
# @post: lines emitted while predicate holds
# @idempotent: yes
# @returns: prefix of stream
#
# Take lines while predicate holds
# Usage: cat file.txt | stream_take_while is_not_empty
stream_take_while() {
    local predicate="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if "$predicate" "$line"; then
            printf '%s\n' "$line"
        else
            break
        fi
    done
}

# @pre: predicate holds initially
# @post: lines dropped while predicate holds
# @idempotent: yes
# @returns: suffix of stream
#
# Drop lines while predicate holds
# Usage: cat file.txt | stream_drop_while is_comment
stream_drop_while() {
    local predicate="$1"
    local dropping=true
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if $dropping && "$predicate" "$line"; then
            continue
        fi
        dropping=false
        printf '%s\n' "$line"
    done
}

# @pre: key_fn extracts grouping key
# @post: lines grouped by key
# @idempotent: yes
# @returns: grouped output (key: items)
#
# Group lines by key function
# Usage: cat data.csv | stream_group_by 'cut -d, -f1'
stream_group_by() {
    local key_fn="$1"
    local -A groups=()
    local line key

    while IFS= read -r line || [[ -n "$line" ]]; do
        key=$(_streaming_key_for_line "$key_fn" "$line")
        if [[ -n "${groups[$key]:-}" ]]; then
            groups[$key]+=$'\n'"$line"
        else
            groups[$key]="$line"
        fi
    done

    for key in "${!groups[@]}"; do
        printf '%s:\n%s\n' "$key" "${groups[$key]}"
    done
}

# @pre: none
# @post: emits (index, line) pairs
# @idempotent: yes
# @returns: indexed stream
#
# Add line numbers to stream
# Usage: cat file.txt | stream_enumerate
stream_enumerate() {
    local start="${1:-0}"
    local line idx="$start"

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%d\t%s\n' "$idx" "$line"
        ((idx++))
    done
}

# @pre: file2 exists
# @post: zipped pairs emitted
# @idempotent: yes
# @returns: paired stream
#
# Zip two streams together
# Usage: cat file1.txt | stream_zip file2.txt
stream_zip() {
    local file2="$1"
    local delimiter="${2:-$'\t'}"
    local line1 line2

    exec 3< "$file2"

    while IFS= read -r line1 || [[ -n "$line1" ]]; do
        if IFS= read -r line2 <&3; then
            printf '%s%s%s\n' "$line1" "$delimiter" "$line2"
        else
            break
        fi
    done

    exec 3<&-
}

# =============================================================================
# USOP OUTPUT FUNCTIONS
# =============================================================================

# @pre: input is valid stream
# @post: USOP JSON envelope with stream data
# @idempotent: yes
# @returns: JSON envelope
#
# Wrap stream in USOP envelope
# Usage: cat data.txt | stream_to_usop
stream_to_usop() {
    local -a lines=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done

    # Build JSON array
    local json_array="["
    local first=true
    for line in "${lines[@]}"; do
        $first || json_array+=","
        first=false
        json_array+="\"$(_streaming_json_escape "$line")\""
    done
    json_array+="]"

    # USOP envelope
    printf '{"ok":true,"data":%s,"meta":{"count":%d}}' "$json_array" "${#lines[@]}"
}

# @pre: json is USOP envelope with data array
# @post: array elements emitted as stream
# @idempotent: yes
# @returns: stream from USOP data
#
# Extract stream from USOP envelope
# Usage: stream_from_usop '{"ok":true,"data":["a","b","c"]}'
stream_from_usop() {
    local json="$1"

    # Simple extraction - find data array and parse
    if [[ "$json" =~ \"data\":\[([^\]]*)\] ]]; then
        local data="${BASH_REMATCH[1]}"
        # Parse JSON array elements (simple case: strings)
        while [[ "$data" =~ \"([^\"]+)\" ]]; do
            printf '%s\n' "${BASH_REMATCH[1]}"
            data="${data#*\"${BASH_REMATCH[1]}\"}"
        done
    fi
}

# @pre: none
# @post: statistics about stream emitted
# @idempotent: yes
# @returns: JSON statistics
#
# Compute stream statistics
# Usage: cat numbers.txt | stream_stats
stream_stats() {
    local count=0 sum=0 min="" max=""
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((count++))

        # Numeric stats (if applicable)
        if [[ "$line" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            sum=$(awk "BEGIN {print $sum + $line}")
            if [[ -z "$min" ]] || awk "BEGIN {exit !($line < $min)}"; then
                min="$line"
            fi
            if [[ -z "$max" ]] || awk "BEGIN {exit !($line > $max)}"; then
                max="$line"
            fi
        fi
    done

    local avg=""
    if ((count > 0)) && [[ -n "$min" ]]; then
        avg=$(awk "BEGIN {printf \"%.2f\", $sum / $count}")
    fi

    # Output USOP format
    printf '{"ok":true,"data":{"count":%d' "$count"
    if [[ -n "$min" ]]; then
        printf ',"sum":%s,"min":%s,"max":%s,"avg":%s' "$sum" "$min" "$max" "$avg"
    fi
    printf '}}'
}

# =============================================================================
# FUNCTIONAL COMPOSITION
# =============================================================================

# @pre: fns are valid function names
# @post: composed pipeline applied to input
# @idempotent: yes
# @returns: transformed stream
#
# Compose multiple stream operations
# Usage: cat data.txt | stream_compose "stream_filter is_valid" "stream_map transform" "stream_take 10"
stream_compose() {
    local -a fns=("$@")

    # Build pipeline
    local pipeline="cat"
    for fn in "${fns[@]}"; do
        pipeline+=" | $fn"
    done

    eval "$pipeline"
}

# @pre: fn is valid function
# @post: stream teed to function and passed through
# @idempotent: yes
# @returns: original stream (side effect: fn called)
#
# Tap into stream for side effects
# Usage: cat data.txt | stream_tap log_line | process
stream_tap() {
    local fn="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        "$fn" "$line" >&2  # Side effect to stderr
        printf '%s\n' "$line"  # Pass through
    done
}

# =============================================================================
# EXPORTS
# =============================================================================

export -f stream_map stream_map_v
export -f stream_filter stream_filter_v
export -f stream_reduce stream_reduce_v
export -f stream_take stream_skip stream_head stream_tail
export -f stream_unique stream_sort stream_reverse
export -f stream_parallel stream_batch stream_chunk
export -f stream_fanout stream_fanin stream_rate_limit
export -f stream_json_lines stream_csv_lines stream_detect_type stream_validate
export -f stream_count stream_any stream_all stream_none stream_find
export -f stream_take_while stream_drop_while stream_group_by
export -f stream_enumerate stream_zip
export -f stream_to_usop stream_from_usop stream_stats
export -f stream_compose stream_tap

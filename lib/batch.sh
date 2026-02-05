#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/batch.sh - Batch Operations for Hot Paths
# =============================================================================
# Description: Single-call operations on multiple items to reduce syscall
#              overhead and improve performance for bulk operations.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_BATCH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_BATCH_LOADED=1

# =============================================================================
# BATCH FILE OPERATIONS
# =============================================================================

# Check existence of multiple files in a single call
# Usage: batch_file_exists PATH1 PATH2 ...
# Output: JSON array of booleans: [true,false,true]
batch_file_exists() {
    local first=true
    printf '['
    for path in "$@"; do
        $first || printf ','
        first=false
        if [[ -e "$path" ]]; then
            printf 'true'
        else
            printf 'false'
        fi
    done
    printf ']'
}

# Get file info for multiple files
# Usage: batch_file_info PATH1 PATH2 ...
# Output: JSON array of file info objects
batch_file_info() {
    local first=true
    printf '['
    for path in "$@"; do
        $first || printf ','
        first=false
        
        if [[ ! -e "$path" ]]; then
            printf 'null'
            continue
        fi
        
        local size=0 mtime=0 mode="" type="file"
        
        if [[ -d "$path" ]]; then
            type="directory"
        elif [[ -L "$path" ]]; then
            type="symlink"
        elif [[ -f "$path" ]]; then
            type="file"
        else
            type="other"
        fi
        
        if [[ -f "$path" ]]; then
            size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo 0)
            mtime=$(stat -f%m "$path" 2>/dev/null || stat -c%Y "$path" 2>/dev/null || echo 0)
        fi
        
        mode=$(stat -f%Lp "$path" 2>/dev/null || stat -c%a "$path" 2>/dev/null || echo "?")
        
        printf '{"path":"%s","exists":true,"type":"%s","size":%d,"mtime":%d,"mode":"%s"}' \
            "$path" "$type" "$size" "$mtime" "$mode"
    done
    printf ']'
}

# =============================================================================
# BATCH JSON OPERATIONS
# =============================================================================

# Validate multiple JSON strings at once
# Usage: batch_json_validate JSON1 JSON2 ...
# Output: JSON array of validation results: [{"valid":true},{"valid":false,"error":"..."}]
batch_json_validate() {
    local first=true
    local json
    
    printf '['
    for json in "$@"; do
        $first || printf ','
        first=false
        
        local is_valid=false
        local error_msg=""
        
        if declare -F json_valid_fast &>/dev/null; then
            if json_valid_fast "$json"; then
                is_valid=true
            else
                error_msg="invalid JSON structure"
            fi
        elif declare -F json_valid &>/dev/null; then
            if json_valid "$json"; then
                is_valid=true
            else
                error_msg="invalid JSON structure"
            fi
        else
            # Basic validation
            if [[ "${json:0:1}" == "{" || "${json:0:1}" == "[" ]]; then
                is_valid=true
            else
                error_msg="must start with { or ["
            fi
        fi
        
        if [[ "$is_valid" == true ]]; then
            printf '{"valid":true}'
        else
            printf '{"valid":false,"error":"%s"}' "$error_msg"
        fi
    done
    printf ']'
}

# Extract multiple keys from a single JSON object
# Usage: batch_json_extract JSON KEY1 KEY2 ...
# Output: JSON array of values
batch_json_extract() {
    local json="$1"
    shift
    local first=true
    local key
    
    printf '['
    for key in "$@"; do
        $first || printf ','
        first=false
        
        local value
        local found=false
        
        if declare -F json_extract_fast_v &>/dev/null; then
            if json_extract_fast_v value "$json" "$key"; then
                found=true
            fi
        elif declare -F json_get &>/dev/null; then
            value=$(json_get "$json" "$key" 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                found=true
            fi
        else
            # Basic extraction
            if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
                value="${BASH_REMATCH[1]}"
                found=true
            elif [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                value="${BASH_REMATCH[1]}"
                found=true
            fi
        fi
        
        if [[ "$found" == true ]]; then
            if [[ "$value" =~ ^(true|false|null|[0-9]+)$ ]]; then
                printf '%s' "$value"
            else
                printf '"%s"' "$value"
            fi
        else
            printf 'null'
        fi
    done
    printf ']'
}

# =============================================================================
# BATCH MAINFRAME CALLS (USOP)
# =============================================================================

# Batch execute mainframe function calls
# Format: "function|arg1|arg2|..." 
# Usage: batch_mainframe_call "trim_string|  hello  " "to_upper|world"
# Output: JSON array of results
batch_mainframe_call() {
    local first=true
    local call
    
    printf '['
    for call in "$@"; do
        $first || printf ','
        first=false
        
        # Parse function and arguments
        local IFS='|'
        local -a parts=($call)
        unset IFS
        
        local func="${parts[0]}"
        local result=""
        local error=""
        local success=false
        
        if [[ -z "$func" ]]; then
            error="empty function name"
        elif ! declare -F "$func" &>/dev/null; then
            # Try common aliases
            case "$func" in
                trim) func="trim_string" ;;
                upper) func="to_upper" ;;
                lower) func="to_lower" ;;
                reverse) func="reverse_string" ;;
            esac
        fi
        
        if [[ -n "$func" ]] && declare -F "$func" &>/dev/null; then
            # Build argument list
            local -a args=()
            local i
            for ((i=1; i<${#parts[@]}; i++)); do
                args+=("${parts[$i]}")
            done
            
            # Execute function
            result=$("$func" "${args[@]}" 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                success=true
            else
                error="function execution failed"
            fi
        else
            error="function not found: ${parts[0]}"
        fi
        
        if [[ "$success" == true ]]; then
            printf '{"success":true,"result":'
            if [[ "$result" =~ ^[0-9]+$ || "$result" =~ ^(true|false|null)$ ]]; then
                printf '%s}' "$result"
            else
                printf '"%s"}' "${result//\"/\\\"}"
            fi
        else
            printf '{"success":false,"error":"%s"}' "$error"
        fi
    done
    printf ']'
}

# Batch execute with direct result output (no JSON wrapper)
# Usage: batch_mainframe_exec "trim_string|  hello  " "to_upper|world"
# Output: Results separated by newlines
batch_mainframe_exec() {
    local call
    
    for call in "$@"; do
        local IFS='|'
        local -a parts=($call)
        unset IFS
        
        local func="${parts[0]}"
        
        if ! declare -F "$func" &>/dev/null; then
            case "$func" in
                trim) func="trim_string" ;;
                upper) func="to_upper" ;;
                lower) func="to_lower" ;;
            esac
        fi
        
        if declare -F "$func" &>/dev/null; then
            local -a args=()
            local i
            for ((i=1; i<${#parts[@]}; i++)); do
                args+=("${parts[$i]}")
            done
            "$func" "${args[@]}" 2>/dev/null || printf 'ERROR'
        else
            printf 'ERROR: function not found'
        fi
        printf '\n'
    done
}

# =============================================================================
# BATCH TOKEN OPERATIONS
# =============================================================================

# Count tokens for multiple texts in one call
# Usage: batch_token_count TEXT1 TEXT2 ... [MODEL]
# Note: Last argument can be a model name if it matches known models
# Output: JSON array of token counts
batch_token_count() {
    local -a texts=("$@")
    local model="default"
    local last_arg="${!#}"
    
    # Check if last arg is a model name
    if [[ "$last_arg" =~ ^(gpt-|claude-|llama-|gemini-|default)$ ]] || [[ "$#" -eq 0 ]]; then
        model="$last_arg"
        # shellcheck disable=SC2184
        unset texts[-1]
    fi
    
    local first=true
    printf '['
    for text in "${texts[@]}"; do
        $first || printf ','
        first=false
        
        local count=0
        if declare -F llm_count_tokens &>/dev/null; then
            count=$(llm_count_tokens "$text" "$model" 2>/dev/null || echo 0)
        elif declare -F token_count_cached &>/dev/null; then
            count=$(token_count_cached "$text" "$model" 2>/dev/null || echo 0)
        else
            # Fallback: simple estimation
            count=$(( (${#text} + 2) / 4 ))
        fi
        
        printf '%d' "$count"
    done
    printf ']'
}

# Batch token count with detailed info
# Usage: batch_token_count_detailed TEXT1 TEXT2 ... [MODEL]
# Output: JSON array with tokens, chars, and model info
batch_token_count_detailed() {
    local -a texts=("$@")
    local model="default"
    local last_arg="${!#}"
    
    if [[ "$last_arg" =~ ^(gpt-|claude-|llama-|gemini-|default)$ ]]; then
        model="$last_arg"
        # shellcheck disable=SC2184
        unset texts[-1]
    fi
    
    local first=true
    printf '['
    for text in "${texts[@]}"; do
        $first || printf ','
        first=false
        
        local count=0
        local chars=${#text}
        
        if declare -F llm_count_tokens &>/dev/null; then
            count=$(llm_count_tokens "$text" "$model" 2>/dev/null || echo 0)
        else
            count=$(( (chars + 2) / 4 ))
        fi
        
        printf '{"tokens":%d,"chars":%d,"model":"%s"}' "$count" "$chars" "$model"
    done
    printf ']'
}

# =============================================================================
# BATCH VALIDATION OPERATIONS
# =============================================================================

# Validate multiple values with the same validator
# Usage: batch_validate "validator" VALUE1 VALUE2 ...
# Example: batch_validate "email" "a@b.com" "invalid" "c@d.com"
# Output: JSON array of results: [true,false,true]
batch_validate() {
    local validator="$1"
    shift
    
    local first=true
    printf '['
    for value in "$@"; do
        $first || printf ','
        first=false
        
        local result=false
        
        if declare -F validate_cached &>/dev/null; then
            if validate_cached "$validator" "$value" 2>/dev/null; then
                result=true
            fi
        else
            case "$validator" in
                int|integer)
                    [[ "$value" =~ ^-?[0-9]+$ ]] && result=true
                    ;;
                email)
                    [[ "$value" =~ ^[A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && result=true
                    ;;
                url)
                    [[ "$value" =~ ^https?:// ]] && result=true
                    ;;
                uuid)
                    [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] && result=true
                    ;;
                *)
                    if declare -F "$validator" &>/dev/null; then
                        "$validator" "$value" 2>/dev/null && result=true
                    fi
                    ;;
            esac
        fi
        
        printf '%s' "$result"
    done
    printf ']'
}

# =============================================================================
# BATCH STRING OPERATIONS
# =============================================================================

# Trim multiple strings
# Usage: batch_trim "  hello  " "  world  "
# Output: JSON array: ["hello","world"]
batch_trim() {
    local first=true
    printf '['
    for str in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "${str#"${str%%[![:space:]]*}"}"
    done
    printf ']'
}

# Convert multiple strings to uppercase
# Usage: batch_upper "hello" "world"
batch_upper() {
    local first=true
    printf '['
    for str in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "${str^^}"
    done
    printf ']'
}

# Convert multiple strings to lowercase  
# Usage: batch_lower "HELLO" "WORLD"
batch_lower() {
    local first=true
    printf '['
    for str in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "${str,,}"
    done
    printf ']'
}

# =============================================================================
# PERFORMANCE BENCHMARKING
# =============================================================================

# Benchmark batch operations vs individual calls
batch_benchmark() {
    local iterations="${1:-100}"
    
    printf 'Batch Operations Benchmark\n'
    printf '===========================\n\n'
    
    # Create test files
    local tmpdir=$(mktemp -d)
    for i in {1..10}; do
        touch "$tmpdir/file$i.txt"
    done
    
    # Benchmark batch_file_exists
    printf 'Testing batch_file_exists vs individual [[ -e ]]...\n'
    
    local start end batch_ms
    start=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    for ((i=0; i<iterations; i++)); do
        batch_file_exists "$tmpdir/file1.txt" "$tmpdir/file2.txt" "$tmpdir/file3.txt" "$tmpdir/file4.txt" "$tmpdir/file5.txt" >/dev/null
    done
    end=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    batch_ms=$(( (end - start) / 1000000 ))
    
    printf '  Batch (%d calls):  %d ms\n' "$iterations" "$batch_ms"
    
    # Benchmark individual
    start=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    for ((i=0; i<iterations; i++)); do
        [[ -e "$tmpdir/file1.txt" ]]; [[ -e "$tmpdir/file2.txt" ]]; [[ -e "$tmpdir/file3.txt" ]]; [[ -e "$tmpdir/file4.txt" ]]; [[ -e "$tmpdir/file5.txt" ]]
    done
    end=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
    local individual_ms=$(( (end - start) / 1000000 ))
    
    printf '  Individual:        %d ms\n' "$individual_ms"
    
    if [[ $individual_ms -gt 0 ]]; then
        local speedup=$(echo "scale=1; $individual_ms / $batch_ms" | bc 2>/dev/null || echo "?")
        printf '  Speedup:           %sx\n' "$speedup"
    fi
    
    # Cleanup
    rm -rf "$tmpdir"
    
    printf '\nBenchmark complete.\n'
}

#!/usr/bin/env bash
# AWM Context Streaming Engine
# Prevents context overflow through intelligent data management
# Version: 2.0.0

# Prevent double-loading
[[ -n "${_AWM_STREAM_LOADED:-}" ]] && return 0
readonly _AWM_STREAM_LOADED=1

# Load dependencies
# shellcheck source=./awm_storage.sh
source "${BASH_SOURCE%/*}/awm_storage.sh" 2>/dev/null || source "$(dirname "$0")/awm_storage.sh"

# =============================================================================
# TOKEN BUDGET CONFIGURATION
# =============================================================================

# Model-specific token limits
declare -gA AWM_MODEL_LIMITS=(
    ["claude-3-opus"]=200000
    ["claude-3.5-sonnet"]=200000
    ["claude-3-sonnet"]=200000
    ["claude-3-haiku"]=200000
    ["claude-opus-4"]=200000
    ["claude-sonnet-4"]=200000
    ["gpt-4-turbo"]=128000
    ["gpt-4o"]=128000
    ["gpt-4o-mini"]=128000
    ["gpt-4"]=8192
    ["gpt-3.5-turbo"]=16385
    ["gemini-pro"]=1000000
    ["gemini-1.5-pro"]=2000000
    ["gemini-2.0-flash"]=1000000
    ["glm-4"]=128000
    ["glm-4.7"]=128000
    ["deepseek-chat"]=128000
    ["qwen-turbo"]=128000
    ["default"]=32000
)

# Content type to chars-per-token ratio
declare -gA AWM_CONTENT_RATIOS=(
    ["code"]=3.5
    ["json"]=3.0
    ["markdown"]=3.8
    ["prose"]=4.0
    ["mixed"]=3.7
    ["default"]=4.0
)

# Pre-rot threshold (trigger compression at this percentage)
AWM_PREROT_THRESHOLD="${AWM_PREROT_THRESHOLD:-0.75}"

# Current budget state
_AWM_BUDGET_MAX=0
_AWM_BUDGET_USED=0
_AWM_BUDGET_MODEL=""
_AWM_BUDGET_RESERVE=4000  # Reserve for system prompt and safety

# =============================================================================
# BUDGET MANAGEMENT
# =============================================================================

# Initialize token budget for a model
# Usage: awm_budget_init [model|auto]
# Returns: 0 on success
awm_budget_init() {
    local model="${1:-auto}"

    if [[ "$model" == "auto" ]]; then
        # Try to detect model from environment
        model="${MAINFRAME_MODEL:-}"
        [[ -z "$model" ]] && model="${ANTHROPIC_MODEL:-}"
        [[ -z "$model" ]] && model="${OPENAI_MODEL:-}"
        [[ -z "$model" ]] && model="default"
    fi

    _AWM_BUDGET_MODEL="$model"

    # Get limit from table or use explicit budget
    if [[ -n "${MAINFRAME_TOKEN_BUDGET:-}" ]]; then
        _AWM_BUDGET_MAX="$MAINFRAME_TOKEN_BUDGET"
    elif [[ -n "${AWM_MODEL_LIMITS[$model]}" ]]; then
        _AWM_BUDGET_MAX="${AWM_MODEL_LIMITS[$model]}"
    else
        _AWM_BUDGET_MAX="${AWM_MODEL_LIMITS[default]}"
    fi

    _AWM_BUDGET_USED=0

    # Return effective budget
    echo $((_AWM_BUDGET_MAX - _AWM_BUDGET_RESERVE))
}

# Get maximum available tokens
# Usage: awm_budget_max
awm_budget_max() {
    [[ $_AWM_BUDGET_MAX -eq 0 ]] && awm_budget_init >/dev/null
    echo $((_AWM_BUDGET_MAX - _AWM_BUDGET_RESERVE))
}

# Get current token usage estimate
# Usage: awm_budget_used
awm_budget_used() {
    echo "$_AWM_BUDGET_USED"
}

# Get remaining available tokens
# Usage: awm_budget_remaining
awm_budget_remaining() {
    [[ $_AWM_BUDGET_MAX -eq 0 ]] && awm_budget_init >/dev/null
    local effective=$((_AWM_BUDGET_MAX - _AWM_BUDGET_RESERVE))
    echo $((effective - _AWM_BUDGET_USED))
}

# Check if content fits in remaining budget
# Usage: awm_budget_fits "content"|token_count
# Returns: 0 if fits, 1 if exceeds
awm_budget_fits() {
    local input="$1"
    local tokens

    if [[ "$input" =~ ^[0-9]+$ ]]; then
        tokens="$input"
    else
        tokens=$(awm_estimate_tokens "$input")
    fi

    local remaining
    remaining=$(awm_budget_remaining)

    [[ $tokens -le $remaining ]]
}

# Record token usage
# Usage: awm_budget_use "label" token_count
awm_budget_use() {
    local label="$1"
    local tokens="$2"

    ((_AWM_BUDGET_USED += tokens))

    # Check pre-rot threshold
    local max
    max=$(awm_budget_max)
    local threshold
    threshold=$(echo "$max * $AWM_PREROT_THRESHOLD" | bc | cut -d. -f1)

    if [[ $_AWM_BUDGET_USED -ge $threshold ]]; then
        # Trigger warning
        printf '{"warning":"prerot_threshold","used":%d,"max":%d,"threshold":%.0f%%}\n' \
            "$_AWM_BUDGET_USED" "$max" "$(echo "$AWM_PREROT_THRESHOLD * 100" | bc)" >&2
    fi
}

# Reset budget to zero (new conversation)
# Usage: awm_budget_reset
awm_budget_reset() {
    _AWM_BUDGET_USED=0
}

# Get budget summary as JSON
# Usage: awm_budget_summary
awm_budget_summary() {
    [[ $_AWM_BUDGET_MAX -eq 0 ]] && awm_budget_init >/dev/null

    local max remaining used_pct
    max=$(awm_budget_max)
    remaining=$(awm_budget_remaining)
    used_pct=$(echo "scale=1; $_AWM_BUDGET_USED * 100 / $max" | bc)

    printf '{"model":"%s","max":%d,"used":%d,"remaining":%d,"used_percent":%.1f,"prerot_at":%.0f}' \
        "$_AWM_BUDGET_MODEL" "$max" "$_AWM_BUDGET_USED" "$remaining" "$used_pct" \
        "$(echo "$max * $AWM_PREROT_THRESHOLD" | bc)"
}

# =============================================================================
# TOKEN ESTIMATION
# =============================================================================

# Estimate tokens for content
# Usage: awm_estimate_tokens "content" [type]
# Returns: integer token estimate
awm_estimate_tokens() {
    local content="$1"
    local type="${2:-auto}"

    [[ -z "$content" ]] && echo 0 && return 0

    # Auto-detect content type
    if [[ "$type" == "auto" ]]; then
        type=$(awm_detect_content_type "$content")
    fi

    local ratio="${AWM_CONTENT_RATIOS[$type]:-${AWM_CONTENT_RATIOS[default]}}"
    local chars=${#content}

    # tokens = chars / ratio
    echo "scale=0; $chars / $ratio" | bc
}

# Estimate tokens for a file
# Usage: awm_estimate_file_tokens "filepath" [type]
awm_estimate_file_tokens() {
    local filepath="$1"
    local type="${2:-auto}"

    [[ ! -f "$filepath" ]] && echo 0 && return 1

    local content
    content=$(cat "$filepath")
    awm_estimate_tokens "$content" "$type"
}

# Detect content type from content
# Usage: awm_detect_content_type "content"
# Returns: code|json|markdown|prose|mixed
awm_detect_content_type() {
    local content="$1"
    local sample="${content:0:2000}"  # Analyze first 2KB

    # Check for JSON
    if echo "$sample" | grep -qE '^\s*[\[{]' && echo "$sample" | jq . >/dev/null 2>&1; then
        echo "json"
        return 0
    fi

    # Check for code patterns
    local code_indicators=0

    # Function/class definitions
    echo "$sample" | grep -qE '(function |def |class |const |let |var |import |from |#include)' && ((code_indicators++))

    # Braces/brackets density
    local brace_count
    brace_count=$(echo "$sample" | grep -o '[{}();]' | wc -l)
    [[ $brace_count -gt 20 ]] && ((code_indicators++))

    # Indentation pattern
    echo "$sample" | grep -qE '^(    |\t){2,}' && ((code_indicators++))

    if [[ $code_indicators -ge 2 ]]; then
        echo "code"
        return 0
    fi

    # Check for markdown
    local md_indicators=0
    echo "$sample" | grep -qE '^#{1,6} ' && ((md_indicators++))
    echo "$sample" | grep -qE '^\s*[-*] ' && ((md_indicators++))
    echo "$sample" | grep -qE '```' && ((md_indicators++))
    echo "$sample" | grep -qE '\[.*\]\(.*\)' && ((md_indicators++))

    if [[ $md_indicators -ge 2 ]]; then
        echo "markdown"
        return 0
    fi

    # Check for prose (sentences, paragraphs)
    local sentence_count
    sentence_count=$(echo "$sample" | grep -o '[.!?]' | wc -l)
    local word_count
    word_count=$(echo "$sample" | wc -w)

    if [[ $sentence_count -gt 5 ]] && [[ $word_count -gt 100 ]]; then
        echo "prose"
        return 0
    fi

    echo "mixed"
}

# =============================================================================
# MEMORY POINTER SYSTEM
# =============================================================================

# Create a memory pointer for large content
# Usage: awm_pointer_create "content" [type] [metadata_json]
# Returns: ptr://awm/[hash]
awm_pointer_create() {
    local content="$1"
    local type="${2:-auto}"
    local metadata="${3:-{}}"

    # Validate metadata is valid JSON
    if ! echo "$metadata" | jq . >/dev/null 2>&1; then
        metadata='{}'
    fi

    # Generate content hash
    local hash
    hash=$(echo -n "$content" | sha256sum | cut -c1-32)

    local pointer="ptr://awm/$hash"

    # Store content with metadata
    local store_data
    store_data=$(jq -n \
        --arg content "$content" \
        --arg type "$type" \
        --arg ts "$(date -Iseconds)" \
        --argjson meta "$metadata" \
        '{content: $content, type: $type, created: $ts, metadata: $meta}')

    awm_store_set "ptr:$hash" "$store_data"

    # Also index for search
    awm_store_index "ptr:$hash" "$content" "$metadata"

    echo "$pointer"
}

# Resolve a memory pointer to content
# Usage: awm_pointer_resolve "ptr://awm/[hash]"
# Returns: original content
awm_pointer_resolve() {
    local pointer="$1"

    # Extract hash from pointer
    local hash
    hash="${pointer#ptr://awm/}"

    local data
    data=$(awm_store_get "ptr:$hash")

    [[ -z "$data" ]] && return 1

    echo "$data" | jq -r '.content'
}

# Check if pointer exists and is valid
# Usage: awm_pointer_exists "ptr://awm/[hash]"
# Returns: 0 if valid, 1 if not
awm_pointer_exists() {
    local pointer="$1"
    local hash
    hash="${pointer#ptr://awm/}"

    awm_store_exists "ptr:$hash"
}

# Get pointer metadata
# Usage: awm_pointer_meta "ptr://awm/[hash]"
awm_pointer_meta() {
    local pointer="$1"
    local hash
    hash="${pointer#ptr://awm/}"

    local data
    data=$(awm_store_get "ptr:$hash")

    [[ -z "$data" ]] && return 1

    echo "$data" | jq '{type: .type, created: .created, metadata: .metadata}'
}

# Wrap large result - store and return pointer if too big
# Usage: awm_wrap_result "content" [max_tokens] [preview_chars]
# Returns: original if small, or {_ptr, preview, tokens} if large
awm_wrap_result() {
    local content="$1"
    local max_tokens="${2:-2000}"
    local preview_chars="${3:-200}"

    local tokens
    tokens=$(awm_estimate_tokens "$content")

    if [[ $tokens -le $max_tokens ]]; then
        # Small enough - return as-is
        echo "$content"
    else
        # Too large - create pointer and return reference
        local pointer
        pointer=$(awm_pointer_create "$content")

        local preview="${content:0:$preview_chars}"
        [[ ${#content} -gt $preview_chars ]] && preview+="..."

        jq -n \
            --arg ptr "$pointer" \
            --arg preview "$preview" \
            --argjson tokens "$tokens" \
            '{_ptr: $ptr, preview: $preview, tokens: $tokens, message: "Content stored externally. Use awm_pointer_resolve to retrieve."}'
    fi
}

# =============================================================================
# SEMANTIC CHUNKING
# =============================================================================

# Chunk content by semantic boundaries
# Usage: awm_chunk "content" [type] [max_tokens]
# Returns: JSON array of chunks
awm_chunk() {
    local content="$1"
    local type="${2:-auto}"
    local max_tokens="${3:-4000}"

    [[ "$type" == "auto" ]] && type=$(awm_detect_content_type "$content")

    case "$type" in
        code)
            awm_chunk_code "$content" "$max_tokens"
            ;;
        json)
            awm_chunk_json "$content" "$max_tokens"
            ;;
        markdown)
            awm_chunk_markdown "$content" "$max_tokens"
            ;;
        prose)
            awm_chunk_prose "$content" "$max_tokens"
            ;;
        *)
            awm_chunk_generic "$content" "$max_tokens"
            ;;
    esac
}

# Chunk code at function/class boundaries
awm_chunk_code() {
    local content="$1"
    local max_tokens="$2"

    local chunks='[]'
    local current_chunk=""
    local current_tokens=0

    # Split on function/class definitions
    local IFS=$'\n'
    local in_block=0
    local block_depth=0

    while IFS= read -r line; do
        local line_tokens
        line_tokens=$(awm_estimate_tokens "$line" "code")

        # Detect block boundaries
        if echo "$line" | grep -qE '^(function |def |class |const.*= *function|const.*= *\(|export (default |async )?function)'; then
            # Start of new function/class
            if [[ -n "$current_chunk" ]] && [[ $current_tokens -gt 0 ]]; then
                # Save previous chunk
                chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
            fi
            current_chunk="$line"
            current_tokens=$line_tokens
            in_block=1
        elif [[ $in_block -eq 1 ]]; then
            # Count braces for block depth
            local opens closes
            opens=$(echo "$line" | grep -o '{' | wc -l)
            closes=$(echo "$line" | grep -o '}' | wc -l)
            ((block_depth += opens - closes))

            current_chunk+=$'\n'"$line"
            ((current_tokens += line_tokens))

            # Check if block closed and chunk is big enough
            if [[ $block_depth -le 0 ]] && [[ $current_tokens -ge $((max_tokens / 2)) ]]; then
                chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
                current_chunk=""
                current_tokens=0
                in_block=0
                block_depth=0
            fi
        else
            # Outside block - accumulate
            if [[ $((current_tokens + line_tokens)) -gt $max_tokens ]]; then
                # Chunk full - save and start new
                [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
                current_chunk="$line"
                current_tokens=$line_tokens
            else
                current_chunk+=$'\n'"$line"
                ((current_tokens += line_tokens))
            fi
        fi
    done <<< "$content"

    # Add remaining chunk
    [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')

    echo "$chunks"
}

# Chunk JSON at object/array boundaries
awm_chunk_json() {
    local content="$1"
    local max_tokens="$2"

    # Try to parse and split at top level
    if echo "$content" | jq -e 'type == "array"' >/dev/null 2>&1; then
        # Array - split into chunks of items
        local total
        total=$(echo "$content" | jq 'length')
        local chunk_size=10  # Start with 10 items per chunk

        local chunks='[]'
        local offset=0

        while [[ $offset -lt $total ]]; do
            local chunk
            chunk=$(echo "$content" | jq ".[$offset:$((offset + chunk_size))]")
            local tokens
            tokens=$(awm_estimate_tokens "$chunk" "json")

            # Adjust chunk size if needed
            while [[ $tokens -gt $max_tokens ]] && [[ $chunk_size -gt 1 ]]; do
                ((chunk_size--))
                chunk=$(echo "$content" | jq ".[$offset:$((offset + chunk_size))]")
                tokens=$(awm_estimate_tokens "$chunk" "json")
            done

            chunks=$(echo "$chunks" | jq --arg c "$chunk" '. + [$c]')
            ((offset += chunk_size))
        done

        echo "$chunks"
    elif echo "$content" | jq -e 'type == "object"' >/dev/null 2>&1; then
        # Object - split by keys
        local keys
        keys=$(echo "$content" | jq -r 'keys[]')

        local chunks='[]'
        local current_chunk='{}'
        local current_tokens=2  # {}

        for key in $keys; do
            local value
            value=$(echo "$content" | jq --arg k "$key" '.[$k]')
            local pair_tokens
            pair_tokens=$(awm_estimate_tokens "\"$key\":$value" "json")

            if [[ $((current_tokens + pair_tokens)) -gt $max_tokens ]]; then
                # Chunk full
                chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
                current_chunk=$(jq -n --arg k "$key" --argjson v "$value" '{($k): $v}')
                current_tokens=$((pair_tokens + 2))
            else
                current_chunk=$(echo "$current_chunk" | jq --arg k "$key" --argjson v "$value" '. + {($k): $v}')
                ((current_tokens += pair_tokens + 1))  # +1 for comma
            fi
        done

        [[ "$current_chunk" != '{}' ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')

        echo "$chunks"
    else
        # Not valid JSON - fall back to generic
        awm_chunk_generic "$content" "$max_tokens"
    fi
}

# Chunk markdown at heading boundaries
awm_chunk_markdown() {
    local content="$1"
    local max_tokens="$2"

    local chunks='[]'
    local current_chunk=""
    local current_tokens=0

    while IFS= read -r line; do
        local line_tokens
        line_tokens=$(awm_estimate_tokens "$line" "markdown")

        # Check for heading (new section)
        if echo "$line" | grep -qE '^#{1,3} '; then
            # Heading found - check if we should split
            if [[ $current_tokens -ge $((max_tokens / 2)) ]]; then
                # Save current chunk
                [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
                current_chunk="$line"
                current_tokens=$line_tokens
            else
                current_chunk+=$'\n'"$line"
                ((current_tokens += line_tokens))
            fi
        else
            if [[ $((current_tokens + line_tokens)) -gt $max_tokens ]]; then
                # Chunk full
                [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
                current_chunk="$line"
                current_tokens=$line_tokens
            else
                [[ -n "$current_chunk" ]] && current_chunk+=$'\n'
                current_chunk+="$line"
                ((current_tokens += line_tokens))
            fi
        fi
    done <<< "$content"

    [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')

    echo "$chunks"
}

# Chunk prose at paragraph/sentence boundaries
awm_chunk_prose() {
    local content="$1"
    local max_tokens="$2"

    local chunks='[]'
    local current_chunk=""
    local current_tokens=0

    # Split by paragraphs (double newline)
    local IFS=$'\n\n'
    for paragraph in $content; do
        local para_tokens
        para_tokens=$(awm_estimate_tokens "$paragraph" "prose")

        if [[ $para_tokens -gt $max_tokens ]]; then
            # Paragraph too big - split by sentences
            # Save current chunk first
            [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
            current_chunk=""
            current_tokens=0

            # Split sentences (rough approximation)
            echo "$paragraph" | sed 's/\([.!?]\) /\1\n/g' | while IFS= read -r sentence; do
                local sent_tokens
                sent_tokens=$(awm_estimate_tokens "$sentence" "prose")

                if [[ $((current_tokens + sent_tokens)) -gt $max_tokens ]]; then
                    [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
                    current_chunk="$sentence"
                    current_tokens=$sent_tokens
                else
                    [[ -n "$current_chunk" ]] && current_chunk+=" "
                    current_chunk+="$sentence"
                    ((current_tokens += sent_tokens))
                fi
            done
        elif [[ $((current_tokens + para_tokens)) -gt $max_tokens ]]; then
            # Would exceed - save current and start new
            [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
            current_chunk="$paragraph"
            current_tokens=$para_tokens
        else
            [[ -n "$current_chunk" ]] && current_chunk+=$'\n\n'
            current_chunk+="$paragraph"
            ((current_tokens += para_tokens))
        fi
    done

    [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')

    echo "$chunks"
}

# Generic chunking by lines with token limit
awm_chunk_generic() {
    local content="$1"
    local max_tokens="$2"

    local chunks='[]'
    local current_chunk=""
    local current_tokens=0

    while IFS= read -r line; do
        local line_tokens
        line_tokens=$(awm_estimate_tokens "$line")

        if [[ $((current_tokens + line_tokens)) -gt $max_tokens ]]; then
            [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')
            current_chunk="$line"
            current_tokens=$line_tokens
        else
            [[ -n "$current_chunk" ]] && current_chunk+=$'\n'
            current_chunk+="$line"
            ((current_tokens += line_tokens))
        fi
    done <<< "$content"

    [[ -n "$current_chunk" ]] && chunks=$(echo "$chunks" | jq --arg c "$current_chunk" '. + [$c]')

    echo "$chunks"
}

# =============================================================================
# COMPRESSION PIPELINE
# =============================================================================

# Compress content at specified level
# Usage: awm_compress "content" level
# level: 1=light, 2=remove comments, 3=summarize, 4=key facts, 5=one-line
awm_compress() {
    local content="$1"
    local level="${2:-1}"

    case "$level" in
        1)
            # Light: normalize whitespace
            printf '%s' "$content" | tr '\t\r\n' '   ' | awk '{$1=$1; print}'
            ;;
        2)
            # Medium: remove comments and docstrings
            echo "$content" | \
                sed '/^[[:space:]]*#/d' | \
                sed '/^[[:space:]]*\/\//d' | \
                sed '/^[[:space:]]*\/\*/,/\*\//d' | \
                sed '/^[[:space:]]*"""/,/"""/d' | \
                sed '/^[[:space:]]*'"'''"'/,/'"'''"'/d' | \
                sed '/^[[:space:]]*$/d'
            ;;
        3)
            # Heavy: extract key patterns (no LLM)
            echo "$content" | \
                grep -E '(function |def |class |export |import |return |throw |error|TODO|FIXME|NOTE)' | \
                head -50
            ;;
        4)
            # Very heavy: just function/class signatures
            echo "$content" | \
                grep -E '^[[:space:]]*(function |def |class |const [a-zA-Z]+.*=.*=>|export (default )?(function|class|const))' | \
                sed 's/{.*//' | \
                head -30
            ;;
        5)
            # Maximum: single line summary
            local lines words chars
            lines=$(echo "$content" | wc -l)
            words=$(echo "$content" | wc -w)
            chars=${#content}
            echo "[Compressed: $lines lines, $words words, $chars chars]"
            ;;
        *)
            echo "$content"
            ;;
    esac
}

# =============================================================================
# OBSERVATION MASKING
# =============================================================================

# Mask observations in session (replace with pointers)
# Usage: awm_mask_observations session_id [categories...]
awm_mask_observations() {
    local session_id="$1"
    shift
    local categories=("$@")

    [[ ${#categories[@]} -eq 0 ]] && categories=("tool_results" "file_contents" "api_responses")

    local masked=0

    for category in "${categories[@]}"; do
        local list_key="session:${session_id}:${category}"
        local len
        len=$(awm_store_len "$list_key")

        for ((i = 0; i < len; i++)); do
            local entry
            entry=$(awm_store_range "$list_key" "$i" "$i" | jq -r '.[0]')

            local tokens
            tokens=$(awm_estimate_tokens "$entry")

            if [[ $tokens -gt 500 ]]; then
                # Replace with pointer
                local pointer
                pointer=$(awm_pointer_create "$entry" "observation" "{\"session\":\"$session_id\",\"category\":\"$category\",\"index\":$i}")

                # Store mask record
                awm_store_set "mask:${session_id}:${category}:${i}" "$pointer"
                ((masked++))
            fi
        done
    done

    echo "$masked"
}

# Unmask observations (restore from pointers)
# Usage: awm_unmask_observations session_id category index
awm_unmask_observations() {
    local session_id="$1"
    local category="$2"
    local index="$3"

    local pointer
    pointer=$(awm_store_get "mask:${session_id}:${category}:${index}")

    [[ -z "$pointer" ]] && return 1

    awm_pointer_resolve "$pointer"
}

# =============================================================================
# STREAMING UTILITIES
# =============================================================================

# Stream chunks with budget enforcement
# Usage: awm_stream_chunks chunks_json callback [budget]
awm_stream_chunks() {
    local chunks_json="$1"
    local callback="$2"
    local budget="${3:-$(awm_budget_remaining)}"

    local used=0
    local count
    count=$(echo "$chunks_json" | jq 'length')

    for ((i = 0; i < count; i++)); do
        local chunk
        chunk=$(echo "$chunks_json" | jq -r ".[$i]")
        local tokens
        tokens=$(awm_estimate_tokens "$chunk")

        if [[ $((used + tokens)) -gt $budget ]]; then
            # Budget exceeded - return remaining as pointers
            local remaining=$((count - i))
            echo "{\"streamed\":$i,\"remaining\":$remaining,\"budget_exceeded\":true}"
            return 1
        fi

        # Call callback with chunk
        $callback "$chunk" "$i" "$tokens"
        ((used += tokens))
        awm_budget_use "stream_chunk_$i" "$tokens"
    done

    echo "{\"streamed\":$count,\"remaining\":0,\"budget_exceeded\":false}"
}

# Create summary for large content (multi-chunk)
# Usage: awm_summarize_chunks chunks_json
awm_summarize_chunks() {
    local chunks_json="$1"

    local count
    count=$(echo "$chunks_json" | jq 'length')

    local total_tokens=0
    local summaries='[]'

    for ((i = 0; i < count; i++)); do
        local chunk
        chunk=$(echo "$chunks_json" | jq -r ".[$i]")
        local tokens
        tokens=$(awm_estimate_tokens "$chunk")
        ((total_tokens += tokens))

        # Create mini-summary (first 100 chars)
        local preview="${chunk:0:100}"
        [[ ${#chunk} -gt 100 ]] && preview+="..."

        summaries=$(echo "$summaries" | jq \
            --argjson i "$i" \
            --arg preview "$preview" \
            --argjson tokens "$tokens" \
            '. + [{index: $i, preview: $preview, tokens: $tokens}]')
    done

    jq -n \
        --argjson count "$count" \
        --argjson total_tokens "$total_tokens" \
        --argjson chunks "$summaries" \
        '{chunk_count: $count, total_tokens: $total_tokens, chunks: $chunks}'
}

# =============================================================================
# TRUNCATION STRATEGIES
# =============================================================================

# @pre: content is a string
# @post: content truncated to fit token budget
# @returns: truncated content
#
# Truncate content using specified strategy.
#
# Usage: awm_truncate "content" max_tokens [strategy]
# strategy: head|tail|middle|smart (default: smart)
awm_truncate() {
    local content="$1"
    local max_tokens="${2:-4000}"
    local strategy="${3:-smart}"

    local current_tokens
    current_tokens=$(awm_estimate_tokens "$content")

    [[ $current_tokens -le $max_tokens ]] && echo "$content" && return 0

    local ratio
    ratio=$(echo "scale=4; $max_tokens / $current_tokens" | bc)
    local max_chars
    max_chars=$(echo "scale=0; ${#content} * $ratio" | bc | cut -d. -f1)

    case "$strategy" in
        head)
            echo "${content:0:$max_chars}..."
            ;;
        tail)
            local start=$((${#content} - max_chars))
            echo "...${content:$start}"
            ;;
        middle)
            local half=$((max_chars / 2))
            echo "${content:0:$half}...[truncated]...${content: -$half}"
            ;;
        smart|*)
            # Smart: try to keep complete lines/sentences
            local truncated="${content:0:$max_chars}"
            # Find last complete sentence or line
            local last_break
            last_break=$(echo "$truncated" | grep -bo '[.!?\n]' | tail -1 | cut -d: -f1)
            if [[ -n "$last_break" ]] && [[ $last_break -gt $((max_chars / 2)) ]]; then
                echo "${content:0:$((last_break + 1))}..."
            else
                echo "$truncated..."
            fi
            ;;
    esac
}

# @pre: files is an array of file paths
# @post: read plan generated
# @returns: JSON read plan
#
# Generate a read plan for files that fit in budget.
#
# Usage: awm_read_plan budget_tokens file1 file2 ...
awm_read_plan() {
    local budget="$1"
    shift
    local files=("$@")

    local included='[]'
    local excluded='[]'
    local used=0

    for file in "${files[@]}"; do
        [[ ! -f "$file" ]] && continue

        local tokens
        tokens=$(awm_estimate_file_tokens "$file")

        if [[ $((used + tokens)) -le $budget ]]; then
            included=$(echo "$included" | jq \
                --arg f "$file" \
                --argjson t "$tokens" \
                '. + [{file: $f, tokens: $t}]')
            ((used += tokens))
        else
            excluded=$(echo "$excluded" | jq \
                --arg f "$file" \
                --argjson t "$tokens" \
                --arg r "budget_exceeded" \
                '. + [{file: $f, tokens: $t, reason: $r}]')
        fi
    done

    jq -n \
        --argjson budget "$budget" \
        --argjson used "$used" \
        --argjson remaining "$((budget - used))" \
        --argjson included "$included" \
        --argjson excluded "$excluded" \
        '{budget: $budget, used: $used, remaining: $remaining, included: $included, excluded: $excluded}'
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_AWM_STREAM_EXPORTS=(
    # Budget Management
    awm_budget_init
    awm_budget_max
    awm_budget_used
    awm_budget_remaining
    awm_budget_fits
    awm_budget_use
    awm_budget_reset
    awm_budget_summary
    # Token Estimation
    awm_estimate_tokens
    awm_estimate_file_tokens
    awm_detect_content_type
    # Memory Pointers
    awm_pointer_create
    awm_pointer_resolve
    awm_pointer_exists
    awm_pointer_meta
    awm_wrap_result
    # Semantic Chunking
    awm_chunk
    awm_chunk_code
    awm_chunk_json
    awm_chunk_markdown
    awm_chunk_prose
    awm_chunk_generic
    # Compression
    awm_compress
    # Observation Masking
    awm_mask_observations
    awm_unmask_observations
    # Streaming
    awm_stream_chunks
    awm_summarize_chunks
    # Truncation
    awm_truncate
    awm_read_plan
)

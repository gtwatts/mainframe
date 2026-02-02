#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/llm_tokens.sh - LLM Token Estimation and Cost Management
# =============================================================================
# Description: Pure bash tokenizer library for LLM context management.
#              Provides model-specific token counting, cost estimation,
#              text truncation, and chunk splitting for AI agent workflows.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# LIMITATIONS:
#   - Token estimates use character-based heuristics (not actual BPE tokenizers)
#   - Accuracy is typically within 10-20% of actual token counts
#   - Pricing data is approximate and may become outdated
#   - Optional tiktoken integration requires Python + tiktoken package
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_LLM_TOKENS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_LLM_TOKENS_LOADED=1

# =============================================================================
# MODEL DEFINITIONS
# =============================================================================

# Characters-per-token ratios by model family
# These are empirically-derived approximations for English text
declare -gA _LLM_CHARS_PER_TOKEN=(
    # OpenAI models (~4 chars/token for English)
    [gpt-4]=4.0
    [gpt-4-turbo]=4.0
    [gpt-4o]=4.0
    [gpt-4o-mini]=4.0
    [gpt-3.5-turbo]=4.0
    [o1]=4.0
    [o1-mini]=4.0
    [o1-preview]=4.0

    # Anthropic models (~3.5 chars/token)
    [claude-3-opus]=3.5
    [claude-3-sonnet]=3.5
    [claude-3-haiku]=3.5
    [claude-3.5-sonnet]=3.5
    [claude-3.5-haiku]=3.5
    [claude-opus-4]=3.5
    [claude-sonnet-4]=3.5

    # Local/Open models (~4 chars/token)
    [llama]=4.0
    [llama-2]=4.0
    [llama-3]=4.0
    [llama-3.1]=4.0
    [llama-3.2]=4.0
    [mistral]=4.0
    [mixtral]=4.0
    [qwen]=4.0
    [qwen-2]=4.0
    [qwen-2.5]=4.0
    [deepseek]=4.0
    [deepseek-v3]=4.0
    [phi-3]=4.0
    [gemma]=4.0
    [gemma-2]=4.0

    # Google models (~4 chars/token)
    [gemini]=4.0
    [gemini-pro]=4.0
    [gemini-1.5-pro]=4.0
    [gemini-1.5-flash]=4.0
    [gemini-2.0-flash]=4.0

    # Default fallback
    [default]=4.0
)

# Pricing per 1 million tokens (input, output) in USD
# Format: "input_price:output_price"
declare -gA _LLM_PRICING_PER_1M=(
    # OpenAI models
    [gpt-4]="30.00:60.00"
    [gpt-4-turbo]="10.00:30.00"
    [gpt-4o]="2.50:10.00"
    [gpt-4o-mini]="0.15:0.60"
    [gpt-3.5-turbo]="0.50:1.50"
    [o1]="15.00:60.00"
    [o1-mini]="3.00:12.00"
    [o1-preview]="15.00:60.00"

    # Anthropic models
    [claude-3-opus]="15.00:75.00"
    [claude-3-sonnet]="3.00:15.00"
    [claude-3-haiku]="0.25:1.25"
    [claude-3.5-sonnet]="3.00:15.00"
    [claude-3.5-haiku]="0.80:4.00"
    [claude-opus-4]="15.00:75.00"
    [claude-sonnet-4]="3.00:15.00"

    # Google models
    [gemini-pro]="0.50:1.50"
    [gemini-1.5-pro]="1.25:5.00"
    [gemini-1.5-flash]="0.075:0.30"
    [gemini-2.0-flash]="0.10:0.40"

    # Local/Open models (typically free, but we track compute cost estimates)
    [llama]="0.00:0.00"
    [llama-2]="0.00:0.00"
    [llama-3]="0.00:0.00"
    [llama-3.1]="0.00:0.00"
    [llama-3.2]="0.00:0.00"
    [mistral]="0.00:0.00"
    [mixtral]="0.00:0.00"
    [qwen]="0.00:0.00"
    [qwen-2]="0.00:0.00"
    [qwen-2.5]="0.00:0.00"
    [deepseek]="0.14:0.28"
    [deepseek-v3]="0.27:1.10"
    [phi-3]="0.00:0.00"
    [gemma]="0.00:0.00"
    [gemma-2]="0.00:0.00"

    # Default (free/unknown)
    [default]="0.00:0.00"
)

# Context window sizes (max tokens)
declare -gA _LLM_CONTEXT_WINDOW=(
    [gpt-4]=8192
    [gpt-4-turbo]=128000
    [gpt-4o]=128000
    [gpt-4o-mini]=128000
    [gpt-3.5-turbo]=16385
    [o1]=200000
    [o1-mini]=128000
    [o1-preview]=128000
    [claude-3-opus]=200000
    [claude-3-sonnet]=200000
    [claude-3-haiku]=200000
    [claude-3.5-sonnet]=200000
    [claude-3.5-haiku]=200000
    [claude-opus-4]=200000
    [claude-sonnet-4]=200000
    [gemini-pro]=32000
    [gemini-1.5-pro]=2000000
    [gemini-1.5-flash]=1000000
    [gemini-2.0-flash]=1000000
    [llama]=4096
    [llama-2]=4096
    [llama-3]=8192
    [llama-3.1]=131072
    [llama-3.2]=131072
    [mistral]=32000
    [mixtral]=32000
    [qwen]=32000
    [qwen-2]=131072
    [qwen-2.5]=131072
    [deepseek]=64000
    [deepseek-v3]=128000
    [phi-3]=128000
    [gemma]=8192
    [gemma-2]=8192
    [default]=8192
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Get chars-per-token ratio for a model
# Usage: _llm_get_ratio "model"
_llm_get_ratio() {
    local model="$1"
    local ratio="${_LLM_CHARS_PER_TOKEN[$model]:-}"

    if [[ -z "$ratio" ]]; then
        # Try model family prefix matching
        local prefix
        for prefix in "${!_LLM_CHARS_PER_TOKEN[@]}"; do
            if [[ "$model" == "$prefix"* ]]; then
                ratio="${_LLM_CHARS_PER_TOKEN[$prefix]}"
                break
            fi
        done
    fi

    echo "${ratio:-${_LLM_CHARS_PER_TOKEN[default]}}"
}

# Convert ratio to integer x10 for integer math
# Usage: _llm_ratio_x10 "3.5"
_llm_ratio_x10() {
    local ratio="$1"
    local int_part="${ratio%.*}"
    local dec_part="${ratio#*.}"

    # Handle no decimal case
    if [[ "$int_part" == "$ratio" ]]; then
        dec_part="0"
    fi

    # Take first digit of decimal
    dec_part="${dec_part:0:1}"
    echo $(( int_part * 10 + dec_part ))
}

# Convert chars to tokens using ratio x10
# Usage: _llm_chars_to_tokens chars ratio_x10
_llm_chars_to_tokens() {
    local chars="$1"
    local ratio_x10="$2"

    if [[ "$ratio_x10" -eq 0 ]]; then
        ratio_x10=40  # fallback
    fi

    # tokens = chars * 10 / ratio_x10 (with rounding)
    echo $(( (chars * 10 + ratio_x10 / 2) / ratio_x10 ))
}

# Convert tokens to chars using ratio x10
# Usage: _llm_tokens_to_chars tokens ratio_x10
_llm_tokens_to_chars() {
    local tokens="$1"
    local ratio_x10="$2"

    # chars = tokens * ratio_x10 / 10
    echo $(( tokens * ratio_x10 / 10 ))
}

# Check if tiktoken is available (Python package)
# Usage: _llm_has_tiktoken
_llm_has_tiktoken() {
    command -v python3 &>/dev/null && \
        python3 -c "import tiktoken" &>/dev/null
}

# Count tokens using tiktoken (OpenAI models only)
# Usage: _llm_tiktoken_count "text" "model"
_llm_tiktoken_count() {
    local text="$1"
    local model="$2"

    python3 << EOF
import tiktoken
try:
    enc = tiktoken.encoding_for_model("$model")
except KeyError:
    enc = tiktoken.get_encoding("cl100k_base")
text = '''$text'''
print(len(enc.encode(text)))
EOF
}

# Cache for repeated token counts (simple hash-based)
declare -gA _LLM_TOKEN_CACHE

# Generate cache key from text (first 100 chars + length + hash suffix)
_llm_cache_key() {
    local text="$1"
    local model="$2"
    local len=${#text}
    local prefix="${text:0:100}"
    # Simple hash: sum of char codes mod 10000
    local hash=0
    local i
    for ((i=0; i<${#text} && i<1000; i++)); do
        hash=$(( (hash + $(printf '%d' "'${text:i:1}")) % 10000 ))
    done
    echo "${model}:${len}:${hash}:${prefix}"
}

# =============================================================================
# PUBLIC API: TOKEN COUNTING
# =============================================================================

# Count tokens for text using model's tokenizer
# Falls back to character-based estimation if tiktoken unavailable
# Usage: llm_count_tokens "text" ["model"]
# Output: integer token count
llm_count_tokens() {
    local text="$1"
    local model="${2:-default}"

    # Handle empty text
    if [[ -z "$text" ]]; then
        echo 0
        return 0
    fi

    # Check cache
    local cache_key
    cache_key=$(_llm_cache_key "$text" "$model")
    if [[ -n "${_LLM_TOKEN_CACHE[$cache_key]:-}" ]]; then
        echo "${_LLM_TOKEN_CACHE[$cache_key]}"
        return 0
    fi

    local tokens

    # Try tiktoken for OpenAI models if available
    if [[ "$model" == gpt-* ]] || [[ "$model" == o1* ]]; then
        if _llm_has_tiktoken; then
            tokens=$(_llm_tiktoken_count "$text" "$model" 2>/dev/null)
            if [[ "$tokens" =~ ^[0-9]+$ ]]; then
                _LLM_TOKEN_CACHE[$cache_key]="$tokens"
                echo "$tokens"
                return 0
            fi
        fi
    fi

    # Fall back to character-based estimation
    local char_count=${#text}
    local ratio
    ratio=$(_llm_get_ratio "$model")
    local ratio_x10
    ratio_x10=$(_llm_ratio_x10 "$ratio")

    tokens=$(_llm_chars_to_tokens "$char_count" "$ratio_x10")

    # Cache result
    _LLM_TOKEN_CACHE[$cache_key]="$tokens"

    echo "$tokens"
}

# Count tokens in a file
# Usage: llm_count_tokens_file "/path/to/file" ["model"]
# Output: integer token count
llm_count_tokens_file() {
    local filepath="$1"
    local model="${2:-default}"

    if [[ ! -f "$filepath" ]]; then
        echo 0
        return 1
    fi

    local content
    content=$(<"$filepath")
    llm_count_tokens "$content" "$model"
}

# Clear the token count cache
# Usage: llm_clear_cache
llm_clear_cache() {
    _LLM_TOKEN_CACHE=()
}

# =============================================================================
# PUBLIC API: COST ESTIMATION
# =============================================================================

# Estimate API cost for text based on token count
# Usage: llm_estimate_cost "text" ["model"] [--type input|output|both]
# Output: JSON object with cost details
llm_estimate_cost() {
    local text="$1"
    local model="${2:-default}"
    shift 2 2>/dev/null || true

    local cost_type="input"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) cost_type="$2"; shift 2 ;;
            input|output|both) cost_type="$1"; shift ;;
            *) shift ;;
        esac
    done

    local tokens
    tokens=$(llm_count_tokens "$text" "$model")

    # Get pricing
    local pricing="${_LLM_PRICING_PER_1M[$model]:-${_LLM_PRICING_PER_1M[default]}}"
    local input_price="${pricing%:*}"
    local output_price="${pricing#*:}"

    # Calculate costs (in USD, 6 decimal places)
    # cost = tokens * price_per_1m / 1000000
    local input_cost output_cost total_cost

    # Use awk for floating point math
    input_cost=$(awk "BEGIN {printf \"%.6f\", $tokens * $input_price / 1000000}")
    output_cost=$(awk "BEGIN {printf \"%.6f\", $tokens * $output_price / 1000000}")

    case "$cost_type" in
        input)
            total_cost="$input_cost"
            ;;
        output)
            total_cost="$output_cost"
            ;;
        both)
            total_cost=$(awk "BEGIN {printf \"%.6f\", $input_cost + $output_cost}")
            ;;
    esac

    # Output JSON
    printf '{"ok":true,"data":{"tokens":%d,"model":"%s","cost_type":"%s","input_cost_usd":%s,"output_cost_usd":%s,"total_cost_usd":%s,"input_price_per_1m":%s,"output_price_per_1m":%s}}\n' \
        "$tokens" "$model" "$cost_type" "$input_cost" "$output_cost" "$total_cost" "$input_price" "$output_price"
}

# Get pricing info for a model
# Usage: llm_get_pricing "model"
# Output: JSON with pricing details
llm_get_pricing() {
    local model="${1:-default}"

    local pricing="${_LLM_PRICING_PER_1M[$model]:-${_LLM_PRICING_PER_1M[default]}}"
    local input_price="${pricing%:*}"
    local output_price="${pricing#*:}"
    local context="${_LLM_CONTEXT_WINDOW[$model]:-${_LLM_CONTEXT_WINDOW[default]}}"
    local ratio
    ratio=$(_llm_get_ratio "$model")

    printf '{"ok":true,"data":{"model":"%s","input_price_per_1m_usd":%s,"output_price_per_1m_usd":%s,"context_window":%d,"chars_per_token":%s}}\n' \
        "$model" "$input_price" "$output_price" "$context" "$ratio"
}

# List all supported models
# Usage: llm_list_models
# Output: JSON array of model names
llm_list_models() {
    local models=()
    local model
    for model in "${!_LLM_CHARS_PER_TOKEN[@]}"; do
        [[ "$model" != "default" ]] && models+=("\"$model\"")
    done

    # Sort and output
    printf '{"ok":true,"data":[%s]}\n' "$(IFS=,; echo "${models[*]}" | tr ' ' ',' | sed 's/,,/,/g')"
}

# =============================================================================
# PUBLIC API: TEXT TRUNCATION
# =============================================================================

# Truncate text to fit within a token limit
# Usage: llm_truncate_to_tokens "text" max_tokens ["model"] [--strategy head|tail|middle]
# Strategies:
#   head   - Keep first N tokens (default)
#   tail   - Keep last N tokens
#   middle - Keep start and end, cut middle
# Output: Truncated text
llm_truncate_to_tokens() {
    local text="$1"
    local max_tokens="$2"
    local model="${3:-default}"
    shift 3 2>/dev/null || true

    local strategy="head"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strategy) strategy="$2"; shift 2 ;;
            head|tail|middle) strategy="$1"; shift ;;
            *) shift ;;
        esac
    done

    # Handle empty or invalid input
    if [[ -z "$text" ]] || [[ -z "$max_tokens" ]] || [[ "$max_tokens" -le 0 ]]; then
        printf '%s' "$text"
        return 0
    fi

    # Check if truncation needed
    local current_tokens
    current_tokens=$(llm_count_tokens "$text" "$model")

    if [[ "$current_tokens" -le "$max_tokens" ]]; then
        printf '%s' "$text"
        return 0
    fi

    # Calculate target character count
    local ratio
    ratio=$(_llm_get_ratio "$model")
    local ratio_x10
    ratio_x10=$(_llm_ratio_x10 "$ratio")
    local target_chars
    target_chars=$(_llm_tokens_to_chars "$max_tokens" "$ratio_x10")

    # Reserve space for truncation marker (~20 chars)
    target_chars=$(( target_chars - 30 ))
    [[ $target_chars -lt 10 ]] && target_chars=10

    local truncated_tokens=$(( current_tokens - max_tokens ))

    case "$strategy" in
        head)
            _llm_truncate_head "$text" "$target_chars" "$truncated_tokens"
            ;;
        tail)
            _llm_truncate_tail "$text" "$target_chars" "$truncated_tokens"
            ;;
        middle)
            _llm_truncate_middle "$text" "$target_chars" "$truncated_tokens"
            ;;
        *)
            _llm_truncate_head "$text" "$target_chars" "$truncated_tokens"
            ;;
    esac
}

# Internal: Truncate keeping head (preserves complete lines when possible)
_llm_truncate_head() {
    local text="$1"
    local target_chars="$2"
    local truncated_tokens="$3"

    local result=""
    local char_count=0

    # Try to preserve complete lines
    while IFS= read -r line || [[ -n "$line" ]]; do
        local line_len=$(( ${#line} + 1 ))
        if [[ $(( char_count + line_len )) -gt $target_chars ]]; then
            # If first line is too long, just cut at char limit
            if [[ -z "$result" ]]; then
                result="${text:0:$target_chars}"
            fi
            break
        fi
        if [[ -n "$result" ]]; then
            result+=$'\n'
        fi
        result+="$line"
        char_count=$(( char_count + line_len ))
    done <<< "$text"

    printf '%s\n... [truncated ~%d tokens] ...' "$result" "$truncated_tokens"
}

# Internal: Truncate keeping tail
_llm_truncate_tail() {
    local text="$1"
    local target_chars="$2"
    local truncated_tokens="$3"

    local total_chars=${#text}
    local skip_chars=$(( total_chars - target_chars ))
    [[ $skip_chars -lt 0 ]] && skip_chars=0

    local result=""
    local char_count=0
    local started=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        local line_len=$(( ${#line} + 1 ))
        char_count=$(( char_count + line_len ))
        if [[ $char_count -gt $skip_chars ]]; then
            started=true
        fi
        if $started; then
            if [[ -n "$result" ]]; then
                result+=$'\n'
            fi
            result+="$line"
        fi
    done <<< "$text"

    printf '... [truncated ~%d tokens] ...\n%s' "$truncated_tokens" "$result"
}

# Internal: Truncate keeping start and end
_llm_truncate_middle() {
    local text="$1"
    local target_chars="$2"
    local truncated_tokens="$3"

    local half_chars=$(( target_chars / 2 ))

    # Get head portion
    local head_result=""
    local head_chars=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        local line_len=$(( ${#line} + 1 ))
        if [[ $(( head_chars + line_len )) -gt $half_chars ]]; then
            break
        fi
        if [[ -n "$head_result" ]]; then
            head_result+=$'\n'
        fi
        head_result+="$line"
        head_chars=$(( head_chars + line_len ))
    done <<< "$text"

    # Get tail portion
    local total_chars=${#text}
    local tail_start=$(( total_chars - half_chars ))
    [[ $tail_start -lt 0 ]] && tail_start=0

    local tail_result=""
    local char_count=0
    local started=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        local line_len=$(( ${#line} + 1 ))
        char_count=$(( char_count + line_len ))
        if [[ $char_count -gt $tail_start ]]; then
            started=true
        fi
        if $started; then
            if [[ -n "$tail_result" ]]; then
                tail_result+=$'\n'
            fi
            tail_result+="$line"
        fi
    done <<< "$text"

    printf '%s\n... [truncated ~%d tokens] ...\n%s' "$head_result" "$truncated_tokens" "$tail_result"
}

# =============================================================================
# PUBLIC API: CHUNK SPLITTING
# =============================================================================

# Split text into token-sized chunks
# Usage: llm_split_chunks "text" chunk_size ["model"] [--overlap tokens] [--preserve-lines]
# Options:
#   --overlap N      Overlap N tokens between chunks (default: 0)
#   --preserve-lines Try to split at line boundaries
# Output: JSON array of chunks with metadata
llm_split_chunks() {
    local text="$1"
    local chunk_size="$2"
    local model="${3:-default}"
    shift 3 2>/dev/null || true

    local overlap=0
    local preserve_lines=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --overlap) overlap="$2"; shift 2 ;;
            --preserve-lines) preserve_lines=true; shift ;;
            *) shift ;;
        esac
    done

    # Validate inputs
    if [[ -z "$text" ]]; then
        printf '{"ok":true,"data":{"chunks":[],"total_chunks":0,"total_tokens":0}}\n'
        return 0
    fi

    if [[ -z "$chunk_size" ]] || [[ "$chunk_size" -le 0 ]]; then
        printf '{"ok":false,"error":"Invalid chunk_size: must be positive integer"}\n'
        return 1
    fi

    # Calculate target chars per chunk
    local ratio
    ratio=$(_llm_get_ratio "$model")
    local ratio_x10
    ratio_x10=$(_llm_ratio_x10 "$ratio")
    local chars_per_chunk
    chars_per_chunk=$(_llm_tokens_to_chars "$chunk_size" "$ratio_x10")
    local overlap_chars
    overlap_chars=$(_llm_tokens_to_chars "$overlap" "$ratio_x10")

    local total_tokens
    total_tokens=$(llm_count_tokens "$text" "$model")

    # Split into chunks
    local -a chunks=()
    local -a chunk_tokens=()
    local pos=0
    local text_len=${#text}
    local chunk_num=0

    while [[ $pos -lt $text_len ]]; do
        local end=$(( pos + chars_per_chunk ))
        [[ $end -gt $text_len ]] && end=$text_len

        local chunk_text="${text:pos:$((end - pos))}"

        # Try to preserve lines if requested and not at end
        if $preserve_lines && [[ $end -lt $text_len ]]; then
            # Find last newline in chunk using bash string ops (fast)
            local before_last_nl="${chunk_text%$'\n'*}"
            if [[ "$before_last_nl" != "$chunk_text" ]]; then
                local last_nl=${#before_last_nl}
                # Only split at newline if we're at least 50% through chunk
                if [[ $last_nl -gt $(( ${#chunk_text} / 2 )) ]]; then
                    chunk_text="${chunk_text:0:$((last_nl + 1))}"
                    end=$(( pos + ${#chunk_text} ))
                fi
            fi
        fi

        local tokens
        tokens=$(llm_count_tokens "$chunk_text" "$model")

        chunks+=("$chunk_text")
        chunk_tokens+=("$tokens")
        ((chunk_num++))

        # Move position, accounting for overlap
        # If we reached end of text, we're done
        [[ $end -eq $text_len ]] && break

        pos=$(( end - overlap_chars ))
        # Ensure forward progress (prevent infinite loop)
        [[ $pos -le $((end - chars_per_chunk)) ]] && pos=$end
        [[ $pos -ge $text_len ]] && break
    done

    # Build JSON output
    printf '{"ok":true,"data":{"chunks":['
    local first=true
    local i
    for ((i=0; i<${#chunks[@]}; i++)); do
        if $first; then
            first=false
        else
            printf ','
        fi

        # Escape chunk text for JSON
        local escaped_chunk
        escaped_chunk=$(printf '%s' "${chunks[i]}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

        printf '{"index":%d,"tokens":%d,"text":"%s"}' \
            "$i" "${chunk_tokens[i]}" "$escaped_chunk"
    done
    printf '],"total_chunks":%d,"total_tokens":%d,"chunk_size":%d,"overlap":%d,"model":"%s"}}\n' \
        "${#chunks[@]}" "$total_tokens" "$chunk_size" "$overlap" "$model"
}

# Split a file into token-sized chunks
# Usage: llm_split_chunks_file "/path/to/file" chunk_size ["model"] [options]
# Output: JSON array of chunks
llm_split_chunks_file() {
    local filepath="$1"
    shift

    if [[ ! -f "$filepath" ]]; then
        printf '{"ok":false,"error":"File not found: %s"}\n' "$filepath"
        return 1
    fi

    local content
    content=$(<"$filepath")
    llm_split_chunks "$content" "$@"
}

# =============================================================================
# PUBLIC API: MODEL UTILITIES
# =============================================================================

# Get context window size for a model
# Usage: llm_context_window "model"
# Output: integer max tokens
llm_context_window() {
    local model="${1:-default}"
    echo "${_LLM_CONTEXT_WINDOW[$model]:-${_LLM_CONTEXT_WINDOW[default]}}"
}

# Check if text fits in model's context window
# Usage: llm_fits_context "text" "model" [--reserve tokens]
# Returns: 0 if fits, 1 if exceeds
llm_fits_context() {
    local text="$1"
    local model="${2:-default}"
    shift 2 2>/dev/null || true

    local reserve=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reserve) reserve="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local tokens
    tokens=$(llm_count_tokens "$text" "$model")
    local max_tokens
    max_tokens=$(llm_context_window "$model")
    local available=$(( max_tokens - reserve ))

    [[ $tokens -le $available ]]
}

# Get model family from model name
# Usage: llm_model_family "gpt-4-turbo-2024-04-09"
# Output: "gpt-4" or "claude-3" etc.
llm_model_family() {
    local model="$1"

    # Extract base model family
    case "$model" in
        gpt-4*) echo "gpt-4" ;;
        gpt-3.5*) echo "gpt-3.5-turbo" ;;
        o1-mini*) echo "o1-mini" ;;
        o1-preview*) echo "o1-preview" ;;
        o1*) echo "o1" ;;
        claude-3-opus*|claude-opus-4*) echo "claude-opus" ;;
        claude-3-sonnet*|claude-3.5-sonnet*|claude-sonnet-4*) echo "claude-sonnet" ;;
        claude-3-haiku*|claude-3.5-haiku*) echo "claude-haiku" ;;
        claude*) echo "claude" ;;
        gemini-1.5-pro*) echo "gemini-1.5-pro" ;;
        gemini-1.5-flash*) echo "gemini-1.5-flash" ;;
        gemini-2.0*) echo "gemini-2.0-flash" ;;
        gemini*) echo "gemini" ;;
        llama-3.2*) echo "llama-3.2" ;;
        llama-3.1*) echo "llama-3.1" ;;
        llama-3*) echo "llama-3" ;;
        llama-2*) echo "llama-2" ;;
        llama*) echo "llama" ;;
        mistral*) echo "mistral" ;;
        mixtral*) echo "mixtral" ;;
        qwen-2.5*) echo "qwen-2.5" ;;
        qwen-2*) echo "qwen-2" ;;
        qwen*) echo "qwen" ;;
        deepseek-v3*) echo "deepseek-v3" ;;
        deepseek*) echo "deepseek" ;;
        phi*) echo "phi-3" ;;
        gemma-2*) echo "gemma-2" ;;
        gemma*) echo "gemma" ;;
        *) echo "default" ;;
    esac
}

# =============================================================================
# PUBLIC API: USOP-COMPLIANT WRAPPERS
# =============================================================================

# USOP-compliant token count
# Usage: llm_count_tokens_usop "text" ["model"]
# Output: JSON envelope with token count
llm_count_tokens_usop() {
    local text="$1"
    local model="${2:-default}"

    local tokens
    tokens=$(llm_count_tokens "$text" "$model")

    printf '{"ok":true,"data":{"tokens":%d,"model":"%s","chars":%d}}\n' \
        "$tokens" "$model" "${#text}"
}

# USOP-compliant truncation
# Usage: llm_truncate_usop "text" max_tokens ["model"] [options]
# Output: JSON envelope with truncated text and metadata
llm_truncate_usop() {
    local text="$1"
    local max_tokens="$2"
    local model="${3:-default}"
    shift 3 2>/dev/null || true

    local original_tokens
    original_tokens=$(llm_count_tokens "$text" "$model")

    local truncated
    truncated=$(llm_truncate_to_tokens "$text" "$max_tokens" "$model" "$@")

    local new_tokens
    new_tokens=$(llm_count_tokens "$truncated" "$model")

    local was_truncated="false"
    [[ $new_tokens -lt $original_tokens ]] && was_truncated="true"

    # Escape text for JSON
    local escaped
    escaped=$(printf '%s' "$truncated" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

    printf '{"ok":true,"data":{"text":"%s","original_tokens":%d,"final_tokens":%d,"max_tokens":%d,"was_truncated":%s,"model":"%s"}}\n' \
        "$escaped" "$original_tokens" "$new_tokens" "$max_tokens" "$was_truncated" "$model"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

LLM_TOKENS_EXPORTS=(
    # Token counting
    llm_count_tokens
    llm_count_tokens_file
    llm_count_tokens_usop
    llm_clear_cache

    # Cost estimation
    llm_estimate_cost
    llm_get_pricing
    llm_list_models

    # Truncation
    llm_truncate_to_tokens
    llm_truncate_usop

    # Chunk splitting
    llm_split_chunks
    llm_split_chunks_file

    # Model utilities
    llm_context_window
    llm_fits_context
    llm_model_family
)

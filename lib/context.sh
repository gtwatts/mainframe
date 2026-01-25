#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/context.sh - Token Estimation & Context Budget Management
# =============================================================================
# Description: Helps AI agents estimate token costs, manage context budgets,
#              and truncate/summarize content to fit within model limits.
# Version: 1.0.0
# =============================================================================
# LIMITATIONS:
#   - Token estimates are APPROXIMATIONS based on character-count heuristics
#   - Actual tokenization depends on the specific model's tokenizer (BPE, etc.)
#   - Estimates are typically within 10-20% of actual token counts
#   - Language detection uses heuristics, not full parsing
#   - JSON parsing is regex-based for budget state management
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CONTEXT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CONTEXT_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

# Characters-per-token ratios by content type
readonly _CTX_RATIO_TEXT="4.0"
readonly _CTX_RATIO_CODE="3.5"
readonly _CTX_RATIO_JSON="3.0"
readonly _CTX_RATIO_MARKDOWN="3.8"

# Default budget values
readonly _CTX_DEFAULT_MAX_TOKENS=100000
readonly _CTX_DEFAULT_RESERVE=4000

# Recommended chunk sizes by model family
readonly _CTX_CHUNK_CLAUDE=8000
readonly _CTX_CHUNK_GPT4=6000
readonly _CTX_CHUNK_GEMINI=7000

# Budget state file location
: "${MAINFRAME_CONTEXT_STATE:=/tmp/mainframe_context_$$}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Integer division with rounding: (a + b/2) / b
_ctx_div_round() {
    local numerator="$1"
    local denominator="$2"
    echo $(( (numerator + denominator / 2) / denominator ))
}

# Multiply integer by decimal ratio (using integer math)
# Usage: _ctx_chars_to_tokens char_count ratio_x10
# ratio_x10 is the ratio multiplied by 10 (e.g., 35 for 3.5)
_ctx_chars_to_tokens() {
    local chars="$1"
    local ratio_x10="$2"
    # tokens = chars * 10 / ratio_x10
    echo $(( (chars * 10 + ratio_x10 / 2) / ratio_x10 ))
}

# Get ratio as integer x10 for a content type
_ctx_ratio_x10() {
    local content_type="${1:-text}"
    case "$content_type" in
        code)     echo 35 ;;
        json)     echo 30 ;;
        markdown) echo 38 ;;
        text|*)   echo 40 ;;
    esac
}

# Count lines in a string that look like code
_ctx_code_line_count() {
    local text="$1"
    local total_lines=0
    local code_lines=0

    while IFS= read -r line; do
        ((total_lines++))
        # Lines starting with whitespace or containing code-like chars
        if [[ "$line" =~ ^[[:space:]] ]] || [[ "$line" =~ [\{\}\;\(\)=] ]]; then
            ((code_lines++))
        fi
    done <<< "$text"

    echo "$total_lines $code_lines"
}

# Read budget state file into variables
_ctx_read_state() {
    if [[ ! -f "$MAINFRAME_CONTEXT_STATE" ]]; then
        return 1
    fi
    # shellcheck disable=SC1090  # dynamic state file path
    source "$MAINFRAME_CONTEXT_STATE"
}

# Write budget state to file
_ctx_write_state() {
    cat > "$MAINFRAME_CONTEXT_STATE" << EOF
_CTX_MAX_TOKENS=${_CTX_MAX_TOKENS:-$_CTX_DEFAULT_MAX_TOKENS}
_CTX_RESERVE=${_CTX_RESERVE:-$_CTX_DEFAULT_RESERVE}
_CTX_USED=${_CTX_USED:-0}
_CTX_ALLOCATIONS="${_CTX_ALLOCATIONS:-}"
EOF
}

# Escape a label for safe storage (replace spaces/special chars)
_ctx_escape_label() {
    local label="$1"
    printf '%s' "$label" | tr ' /:' '___'
}

# Get token count for an allocation by label
_ctx_get_allocation() {
    local label="$1"
    local escaped
    escaped=$(_ctx_escape_label "$label")
    local alloc_var="_CTX_ALLOC_${escaped}"
    echo "${!alloc_var:-0}"
}

# =============================================================================
# TOKEN ESTIMATION
# =============================================================================

# Estimate token count for a string
# Uses character-based heuristic (~4 chars/token for English, ~3.5 for code)
# Usage: context_estimate_tokens "string"
# Output: integer token count (approximate)
context_estimate_tokens() {
    local text="$1"

    if [[ -z "$text" ]]; then
        echo 0
        return 0
    fi

    local char_count=${#text}

    # Detect content type for ratio selection
    local content_type
    content_type=$(context_detect_type "$text")
    local base_type="${content_type%%:*}"

    local ratio_x10
    case "$base_type" in
        code) ratio_x10=35 ;;
        data) ratio_x10=30 ;;
        *)    ratio_x10=40 ;;
    esac

    _ctx_chars_to_tokens "$char_count" "$ratio_x10"
}

# Estimate tokens for a file
# Usage: context_file_tokens "/path/to/file"
# Output: integer token count (approximate)
context_file_tokens() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo 0
        return 1
    fi

    local char_count
    char_count=$(wc -c < "$filepath" 2>/dev/null)
    char_count="${char_count// /}"

    if [[ "$char_count" -eq 0 ]]; then
        echo 0
        return 0
    fi

    # Detect type from extension
    local ext="${filepath##*.}"
    local ratio_x10
    case "$ext" in
        py|rb|go|rs|c|h|cpp|java|ts|js|tsx|jsx|sh|bash|zsh)
            ratio_x10=35 ;;
        json|yaml|yml|toml|xml|csv)
            ratio_x10=30 ;;
        md|mdx|rst)
            ratio_x10=38 ;;
        *)
            ratio_x10=40 ;;
    esac

    _ctx_chars_to_tokens "$char_count" "$ratio_x10"
}

# Estimate tokens for command output (runs command, counts result)
# Usage: context_command_tokens command [args...]
# Output: integer token count
# Side effect: stores command output in $_CTX_LAST_OUTPUT for reuse
context_command_tokens() {
    if [[ $# -eq 0 ]]; then
        echo 0
        return 1
    fi

    _CTX_LAST_OUTPUT=$("$@" 2>/dev/null)
    local char_count=${#_CTX_LAST_OUTPUT}

    if [[ "$char_count" -eq 0 ]]; then
        echo 0
        return 0
    fi

    # Use text ratio as default for command output
    _ctx_chars_to_tokens "$char_count" 40
}

# Get character-to-token ratio for a content type
# Usage: context_ratio [--type text|code|json|markdown]
# Output: float ratio (e.g., "3.5")
context_ratio() {
    local content_type="text"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) content_type="$2"; shift 2 ;;
            *) content_type="$1"; shift ;;
        esac
    done

    case "$content_type" in
        code)     echo "$_CTX_RATIO_CODE" ;;
        json)     echo "$_CTX_RATIO_JSON" ;;
        markdown) echo "$_CTX_RATIO_MARKDOWN" ;;
        text|*)   echo "$_CTX_RATIO_TEXT" ;;
    esac
}

# =============================================================================
# BUDGET MANAGEMENT
# =============================================================================

# Initialize a context budget
# Usage: context_budget_init [--max-tokens N] [--reserve N]
# shellcheck disable=SC2120  # function has optional args with defaults
context_budget_init() {
    _CTX_MAX_TOKENS=$_CTX_DEFAULT_MAX_TOKENS
    _CTX_RESERVE=$_CTX_DEFAULT_RESERVE
    _CTX_USED=0
    _CTX_ALLOCATIONS=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-tokens) _CTX_MAX_TOKENS="$2"; shift 2 ;;
            --reserve)    _CTX_RESERVE="$2"; shift 2 ;;
            *)            shift ;;
        esac
    done

    # Clear any existing allocation vars
    local var
    for var in $(compgen -v _CTX_ALLOC_ 2>/dev/null); do
        unset "$var"
    done

    _ctx_write_state
}

# Record token usage with a label
# Usage: context_budget_use "label" token_count
context_budget_use() {
    local label="$1"
    local tokens="$2"

    if [[ -z "$label" ]] || [[ -z "$tokens" ]]; then
        return 1
    fi

    _ctx_read_state || {
        # Auto-initialize if no state exists
        context_budget_init
    }

    local escaped
    escaped=$(_ctx_escape_label "$label")

    # Update allocation
    local alloc_var="_CTX_ALLOC_${escaped}"
    local prev="${!alloc_var:-0}"
    printf -v "$alloc_var" '%d' "$tokens"
    export "${alloc_var?}"

    # Update used total
    _CTX_USED=$(( _CTX_USED - prev + tokens ))

    # Track allocation labels
    if [[ "$_CTX_ALLOCATIONS" != *"|${escaped}|"* ]]; then
        _CTX_ALLOCATIONS="${_CTX_ALLOCATIONS}|${escaped}|"
    fi

    _ctx_write_state

    # Also persist alloc vars
    echo "_CTX_ALLOC_${escaped}=${tokens}" >> "$MAINFRAME_CONTEXT_STATE"
}

# Check remaining budget
# Usage: context_budget_remaining
# Output: integer remaining tokens (max - used - reserve)
context_budget_remaining() {
    _ctx_read_state || {
        echo "$_CTX_DEFAULT_MAX_TOKENS"
        return 0
    }

    local remaining=$(( _CTX_MAX_TOKENS - _CTX_USED - _CTX_RESERVE ))
    if [[ $remaining -lt 0 ]]; then
        remaining=0
    fi
    echo "$remaining"
}

# Check if a token count fits within the remaining budget
# Usage: context_budget_fits token_count
# Returns: 0 if fits, 1 if exceeds budget
context_budget_fits() {
    local tokens="$1"

    if [[ -z "$tokens" ]]; then
        return 1
    fi

    local remaining
    remaining=$(context_budget_remaining)

    [[ "$tokens" -le "$remaining" ]]
}

# Get budget summary as JSON
# Usage: context_budget_summary
# Output: JSON object with budget details
context_budget_summary() {
    _ctx_read_state || {
        context_budget_init
        _ctx_read_state
    }

    local remaining=$(( _CTX_MAX_TOKENS - _CTX_USED - _CTX_RESERVE ))
    [[ $remaining -lt 0 ]] && remaining=0

    # Build allocations JSON
    local alloc_json="{"
    local first=true

    # Parse allocation labels
    local label
    while IFS= read -r label; do
        [[ -z "$label" ]] && continue
        local alloc_var="_CTX_ALLOC_${label}"
        local val="${!alloc_var:-0}"
        if $first; then
            first=false
        else
            alloc_json+=","
        fi
        alloc_json+="\"${label}\":${val}"
    done <<< "$(echo "$_CTX_ALLOCATIONS" | tr '|' '\n' | sort -u)"

    alloc_json+="}"

    printf '{"max":%d,"used":%d,"remaining":%d,"reserve":%d,"allocations":%s}\n' \
        "$_CTX_MAX_TOKENS" "$_CTX_USED" "$remaining" "$_CTX_RESERVE" "$alloc_json"
}

# Reset budget (clear all state)
# Usage: context_budget_reset
context_budget_reset() {
    # Clear allocation vars
    local var
    for var in $(compgen -v _CTX_ALLOC_ 2>/dev/null); do
        unset "$var"
    done

    _CTX_MAX_TOKENS=$_CTX_DEFAULT_MAX_TOKENS
    _CTX_RESERVE=$_CTX_DEFAULT_RESERVE
    _CTX_USED=0
    _CTX_ALLOCATIONS=""

    rm -f "$MAINFRAME_CONTEXT_STATE"
}

# =============================================================================
# CONTENT TRUNCATION
# =============================================================================

# Truncate text to fit within N tokens
# Usage: context_truncate "text" max_tokens [--strategy head|tail|middle|smart]
# Strategies:
#   head   - keep first N tokens (default)
#   tail   - keep last N tokens
#   middle - keep start and end, cut middle
#   smart  - keep first paragraph + last paragraph + truncation marker
context_truncate() {
    local text="$1"
    local max_tokens="$2"
    shift 2

    local strategy="head"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strategy) strategy="$2"; shift 2 ;;
            *)          strategy="$1"; shift ;;
        esac
    done

    if [[ -z "$text" ]] || [[ -z "$max_tokens" ]]; then
        printf '%s' "$text"
        return 0
    fi

    # Estimate current tokens
    local current_tokens
    current_tokens=$(context_estimate_tokens "$text")

    # If already within budget, return as-is
    if [[ "$current_tokens" -le "$max_tokens" ]]; then
        printf '%s' "$text"
        return 0
    fi

    # Determine content type for char limit calculation
    local content_type
    content_type=$(context_detect_type "$text")
    local base_type="${content_type%%:*}"
    local ratio_x10
    case "$base_type" in
        code) ratio_x10=35 ;;
        data) ratio_x10=30 ;;
        *)    ratio_x10=40 ;;
    esac

    # Target character count for max_tokens
    local target_chars=$(( max_tokens * ratio_x10 / 10 ))

    case "$strategy" in
        head)
            _ctx_truncate_head "$text" "$target_chars" "$current_tokens" "$max_tokens"
            ;;
        tail)
            _ctx_truncate_tail "$text" "$target_chars" "$current_tokens" "$max_tokens"
            ;;
        middle)
            _ctx_truncate_middle "$text" "$target_chars" "$current_tokens" "$max_tokens"
            ;;
        smart)
            _ctx_truncate_smart "$text" "$target_chars" "$current_tokens" "$max_tokens"
            ;;
        *)
            _ctx_truncate_head "$text" "$target_chars" "$current_tokens" "$max_tokens"
            ;;
    esac
}

# Internal: truncate keeping head (complete lines)
_ctx_truncate_head() {
    local text="$1"
    local target_chars="$2"
    local orig_tokens="$3"
    local max_tokens="$4"

    local result=""
    local char_count=0
    local truncated_tokens=$(( orig_tokens - max_tokens ))

    while IFS= read -r line; do
        local line_len=$(( ${#line} + 1 ))  # +1 for newline
        if [[ $(( char_count + line_len )) -gt $target_chars ]]; then
            break
        fi
        if [[ -n "$result" ]]; then
            result+=$'\n'
        fi
        result+="$line"
        char_count=$(( char_count + line_len ))
    done <<< "$text"

    printf '%s\n... (truncated ~%d tokens) ...' "$result" "$truncated_tokens"
}

# Internal: truncate keeping tail (complete lines)
_ctx_truncate_tail() {
    local text="$1"
    local target_chars="$2"
    local orig_tokens="$3"
    local max_tokens="$4"

    local truncated_tokens=$(( orig_tokens - max_tokens ))
    local total_chars=${#text}
    local skip_chars=$(( total_chars - target_chars ))
    [[ $skip_chars -lt 0 ]] && skip_chars=0

    # Find the first complete line after skip_chars
    local result=""
    local char_count=0
    local started=false

    while IFS= read -r line; do
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

    printf '... (truncated ~%d tokens) ...\n%s' "$truncated_tokens" "$result"
}

# Internal: truncate keeping start and end, cut middle
_ctx_truncate_middle() {
    local text="$1"
    local target_chars="$2"
    local orig_tokens="$3"
    local max_tokens="$4"

    local truncated_tokens=$(( orig_tokens - max_tokens ))
    local half_chars=$(( target_chars / 2 ))

    # Get head portion (complete lines)
    local head_result=""
    local head_chars=0
    while IFS= read -r line; do
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

    # Get tail portion (complete lines from end)
    local total_chars=${#text}
    local tail_start=$(( total_chars - half_chars ))
    [[ $tail_start -lt 0 ]] && tail_start=0

    local tail_result=""
    local char_count=0
    local started=false
    while IFS= read -r line; do
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

    printf '%s\n... (truncated ~%d tokens) ...\n%s' "$head_result" "$truncated_tokens" "$tail_result"
}

# Internal: smart truncation (first paragraph + last paragraph)
_ctx_truncate_smart() {
    local text="$1"
    local target_chars="$2"
    local orig_tokens="$3"
    local max_tokens="$4"

    local truncated_tokens=$(( orig_tokens - max_tokens ))

    # Extract first paragraph (up to first blank line or target_chars/2)
    local first_para=""
    local first_chars=0
    local half_chars=$(( target_chars / 2 ))

    while IFS= read -r line; do
        if [[ -z "$line" ]] && [[ -n "$first_para" ]]; then
            break
        fi
        local line_len=$(( ${#line} + 1 ))
        if [[ $(( first_chars + line_len )) -gt $half_chars ]]; then
            break
        fi
        if [[ -n "$first_para" ]]; then
            first_para+=$'\n'
        fi
        first_para+="$line"
        first_chars=$(( first_chars + line_len ))
    done <<< "$text"

    # Extract last paragraph (from last blank line to end, up to half_chars)
    local last_para=""
    local total_chars=${#text}
    local tail_start=$(( total_chars - half_chars ))
    [[ $tail_start -lt 0 ]] && tail_start=0

    local char_count=0
    local last_block=""
    local current_block=""
    while IFS= read -r line; do
        local line_len=$(( ${#line} + 1 ))
        char_count=$(( char_count + line_len ))
        if [[ $char_count -gt $tail_start ]]; then
            if [[ -z "$line" ]]; then
                last_block="$current_block"
                current_block=""
            else
                if [[ -n "$current_block" ]]; then
                    current_block+=$'\n'
                fi
                current_block+="$line"
            fi
        fi
    done <<< "$text"

    # Use the last non-empty block
    if [[ -n "$current_block" ]]; then
        last_para="$current_block"
    elif [[ -n "$last_block" ]]; then
        last_para="$last_block"
    fi

    printf '%s\n... (truncated ~%d tokens) ...\n%s' "$first_para" "$truncated_tokens" "$last_para"
}

# Truncate a file's content to fit within max_tokens
# Usage: context_truncate_file "/path" max_tokens [--strategy head|tail|middle|smart]
context_truncate_file() {
    local filepath="$1"
    local max_tokens="$2"
    shift 2

    if [[ ! -f "$filepath" ]]; then
        return 1
    fi

    local content
    content=$(cat "$filepath")
    context_truncate "$content" "$max_tokens" "$@"
}

# Distribute token budget across multiple items by priority
# Reads JSON-like input from stdin: label\tcontent\tpriority (tab-separated)
# Usage: echo -e "file1\tcontent1\t1\nfile2\tcontent2\t2" | context_distribute_budget max_tokens
# Output: JSON with truncated content per item
context_distribute_budget() {
    local max_tokens="$1"

    if [[ -z "$max_tokens" ]]; then
        echo '[]'
        return 1
    fi

    # Read items
    local -a labels=()
    local -a contents=()
    local -a priorities=()
    local total_priority=0

    while IFS=$'\t' read -r label content priority; do
        [[ -z "$label" ]] && continue
        labels+=("$label")
        contents+=("$content")
        priorities+=("${priority:-1}")
        total_priority=$(( total_priority + ${priority:-1} ))
    done

    if [[ ${#labels[@]} -eq 0 ]]; then
        echo '[]'
        return 0
    fi

    [[ $total_priority -eq 0 ]] && total_priority=1

    # Distribute budget proportionally
    printf '['
    local first=true
    local i
    for (( i=0; i<${#labels[@]}; i++ )); do
        local item_budget=$(( max_tokens * priorities[i] / total_priority ))
        local truncated
        truncated=$(context_truncate "${contents[i]}" "$item_budget" --strategy head)

        local actual_tokens
        actual_tokens=$(context_estimate_tokens "$truncated")

        if $first; then
            first=false
        else
            printf ','
        fi

        # Escape content for JSON output
        local escaped_content
        escaped_content=$(printf '%s' "$truncated" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

        printf '{"label":"%s","tokens":%d,"priority":%d,"content":"%s"}' \
            "${labels[i]}" "$actual_tokens" "${priorities[i]}" "$escaped_content"
    done
    printf ']\n'
}

# =============================================================================
# CONTENT ANALYSIS
# =============================================================================

# Analyze content complexity (affects token estimation accuracy)
# Usage: context_analyze "text"
# Output: JSON with chars, lines, estimated_tokens, type, language, density
context_analyze() {
    local text="$1"

    if [[ -z "$text" ]]; then
        printf '{"chars":0,"lines":0,"estimated_tokens":0,"type":"text","language":"unknown","density":"low"}\n'
        return 0
    fi

    local chars=${#text}
    local lines=0
    while IFS= read -r _; do
        ((lines++))
    done <<< "$text"

    local content_type
    content_type=$(context_detect_type "$text")
    local base_type="${content_type%%:*}"
    local language="${content_type#*:}"

    local tokens
    tokens=$(context_estimate_tokens "$text")

    # Density: chars per line (low < 40, medium 40-80, high > 80)
    local density="low"
    if [[ $lines -gt 0 ]]; then
        local avg_chars=$(( chars / lines ))
        if [[ $avg_chars -gt 80 ]]; then
            density="high"
        elif [[ $avg_chars -gt 40 ]]; then
            density="medium"
        fi
    fi

    printf '{"chars":%d,"lines":%d,"estimated_tokens":%d,"type":"%s","language":"%s","density":"%s"}\n' \
        "$chars" "$lines" "$tokens" "$base_type" "$language" "$density"
}

# Detect content type and language
# Usage: context_detect_type "text"
# Output: "code:python" or "code:bash" or "text:prose" or "data:json" etc.
context_detect_type() {
    local text="$1"

    if [[ -z "$text" ]]; then
        echo "text:unknown"
        return 0
    fi

    # Check for JSON first (starts with { or [)
    local trimmed="${text#"${text%%[![:space:]]*}"}"
    if [[ "$trimmed" == "{"* ]] || [[ "$trimmed" == "["* ]]; then
        echo "data:json"
        return 0
    fi

    # Check for XML/HTML
    if [[ "$trimmed" == "<?xml"* ]] || [[ "$trimmed" == "<!DOCTYPE"* ]] || [[ "$trimmed" == "<html"* ]]; then
        echo "data:xml"
        return 0
    fi

    # Check for YAML (starts with --- or key: value patterns)
    if [[ "$trimmed" == "---"* ]]; then
        echo "data:yaml"
        return 0
    fi

    # Count code indicators
    local total_lines=0
    local code_lines=0
    local shebang=false
    local has_def=false
    local has_class=false
    local has_import=false
    local has_function=false
    local has_const=false
    local first_line=true

    while IFS= read -r line; do
        ((total_lines++))

        if $first_line; then
            first_line=false
            if [[ "$line" == "#!"* ]]; then
                shebang=true
            fi
        fi

        # Code-like patterns
        if [[ "$line" =~ ^[[:space:]] ]] || [[ "$line" =~ [\{\}\;\(\)=] ]]; then
            ((code_lines++))
        fi

        # Language-specific indicators
        [[ "$line" =~ ^(def |async def ) ]] && has_def=true
        [[ "$line" =~ ^class\  ]] && has_class=true
        [[ "$line" =~ ^(import |from .* import ) ]] && has_import=true
        [[ "$line" =~ ^(function |const |let |var |export ) ]] && has_function=true
        [[ "$line" =~ ^(const |let |var ) ]] && has_const=true
    done <<< "$text"

    [[ $total_lines -eq 0 ]] && total_lines=1

    local code_percent=$(( code_lines * 100 / total_lines ))

    # If more than 30% of lines look like code, classify as code
    if [[ $code_percent -gt 30 ]]; then
        # Detect language
        if $shebang && [[ "$text" == *"/bash"* || "$text" == *"env bash"* || "$text" == *"/sh"* || "$text" == *"env sh"* ]]; then
            echo "code:bash"
        elif $has_def || ($has_import && $has_class); then
            echo "code:python"
        elif $has_function || $has_const; then
            echo "code:javascript"
        elif $shebang; then
            echo "code:shell"
        else
            echo "code:unknown"
        fi
    else
        # Check if it looks like markdown
        local md_indicators=0
        if [[ "$text" == *"# "* ]]; then ((md_indicators++)); fi
        if [[ "$text" == *"## "* ]]; then ((md_indicators++)); fi
        if [[ "$text" == *"- "* ]]; then ((md_indicators++)); fi
        if [[ "$text" == *'```'* ]]; then ((md_indicators++)); fi
        if [[ "$text" == *"**"* ]]; then ((md_indicators++)); fi

        if [[ $md_indicators -ge 2 ]]; then
            echo "text:markdown"
        else
            echo "text:prose"
        fi
    fi
}

# Get optimal chunk size for content type and model
# Usage: context_chunk_size [--type code|text|json] [--model claude|gpt4|gemini]
# Output: recommended max tokens per chunk
context_chunk_size() {
    local content_type="text"
    local model="claude"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)  content_type="$2"; shift 2 ;;
            --model) model="$2"; shift 2 ;;
            *)       shift ;;
        esac
    done

    local base_size
    case "$model" in
        claude)  base_size=$_CTX_CHUNK_CLAUDE ;;
        gpt4)    base_size=$_CTX_CHUNK_GPT4 ;;
        gemini)  base_size=$_CTX_CHUNK_GEMINI ;;
        *)       base_size=$_CTX_CHUNK_CLAUDE ;;
    esac

    # Adjust by content type (code benefits from smaller chunks for accuracy)
    case "$content_type" in
        code) echo $(( base_size * 75 / 100 )) ;;
        json) echo $(( base_size * 80 / 100 )) ;;
        *)    echo "$base_size" ;;
    esac
}

# =============================================================================
# FILE BATCHING
# =============================================================================

# Determine which files from stdin fit within a token budget
# Usage: echo "/path/file1\n/path/file2" | context_batch_files max_tokens [--sort size|alpha|mtime]
# Output: file paths that fit, one per line
context_batch_files() {
    local max_tokens="$1"
    shift

    local sort_by="size"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sort) sort_by="$2"; shift 2 ;;
            *)      shift ;;
        esac
    done

    if [[ -z "$max_tokens" ]]; then
        return 1
    fi

    # Read file paths
    local -a files=()
    local -a tokens=()
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        [[ ! -f "$filepath" ]] && continue
        files+=("$filepath")
        local ft
        ft=$(context_file_tokens "$filepath")
        tokens+=("$ft")
    done

    # Sort files
    local -a indices=()
    local i
    for (( i=0; i<${#files[@]}; i++ )); do
        indices+=("$i")
    done

    case "$sort_by" in
        size)
            # Sort by token count ascending (smallest first for maximum coverage)
            local n=${#indices[@]}
            local swapped=true
            while $swapped; do
                swapped=false
                for (( i=0; i<n-1; i++ )); do
                    local j=$(( i + 1 ))
                    if [[ ${tokens[${indices[i]}]} -gt ${tokens[${indices[j]}]} ]]; then
                        local tmp="${indices[i]}"
                        indices[i]="${indices[j]}"
                        indices[j]="$tmp"
                        swapped=true
                    fi
                done
                ((n--))
            done
            ;;
        alpha)
            # Sort alphabetically
            local n=${#indices[@]}
            local swapped=true
            while $swapped; do
                swapped=false
                for (( i=0; i<n-1; i++ )); do
                    local j=$(( i + 1 ))
                    if [[ "${files[${indices[i]}]}" > "${files[${indices[j]}]}" ]]; then
                        local tmp="${indices[i]}"
                        indices[i]="${indices[j]}"
                        indices[j]="$tmp"
                        swapped=true
                    fi
                done
                ((n--))
            done
            ;;
        mtime)
            # Sort by modification time (newest first)
            local n=${#indices[@]}
            local swapped=true
            while $swapped; do
                swapped=false
                for (( i=0; i<n-1; i++ )); do
                    local j=$(( i + 1 ))
                    local mt_i mt_j
                    mt_i=$(stat -c '%Y' "${files[${indices[i]}]}" 2>/dev/null || echo 0)
                    mt_j=$(stat -c '%Y' "${files[${indices[j]}]}" 2>/dev/null || echo 0)
                    if [[ "$mt_i" -lt "$mt_j" ]]; then
                        local tmp="${indices[i]}"
                        indices[i]="${indices[j]}"
                        indices[j]="$tmp"
                        swapped=true
                    fi
                done
                ((n--))
            done
            ;;
    esac

    # Greedily select files that fit
    local used=0
    for i in "${indices[@]}"; do
        local file_tokens="${tokens[$i]}"
        if [[ $(( used + file_tokens )) -le $max_tokens ]]; then
            echo "${files[$i]}"
            used=$(( used + file_tokens ))
        fi
    done
}

# Plan file reading order to maximize coverage within budget
# Usage: context_read_plan max_tokens [files...]
# Output: JSON plan with file details and inclusion status
context_read_plan() {
    local max_tokens="$1"
    shift

    if [[ -z "$max_tokens" ]]; then
        echo '{"files":[],"total_tokens":0,"files_included":0,"files_excluded":0}'
        return 1
    fi

    # Collect file info
    local -a file_paths=()
    local -a file_tokens=()

    for filepath in "$@"; do
        if [[ -f "$filepath" ]]; then
            file_paths+=("$filepath")
            local ft
            ft=$(context_file_tokens "$filepath")
            file_tokens+=("$ft")
        fi
    done

    # Sort by size ascending for greedy packing
    local -a indices=()
    local i
    for (( i=0; i<${#file_paths[@]}; i++ )); do
        indices+=("$i")
    done

    local n=${#indices[@]}
    local swapped=true
    while $swapped; do
        swapped=false
        for (( i=0; i<n-1; i++ )); do
            local j=$(( i + 1 ))
            if [[ ${file_tokens[${indices[i]}]} -gt ${file_tokens[${indices[j]}]} ]]; then
                local tmp="${indices[i]}"
                indices[i]="${indices[j]}"
                indices[j]="$tmp"
                swapped=true
            fi
        done
        ((n--))
    done

    # Determine inclusion
    local used=0
    local included=0
    local excluded=0
    local -a file_included=()

    for i in "${indices[@]}"; do
        if [[ $(( used + file_tokens[i] )) -le $max_tokens ]]; then
            file_included[i]=true
            used=$(( used + file_tokens[i] ))
            ((included++))
        else
            file_included[i]=false
            ((excluded++))
        fi
    done

    # Output JSON
    printf '{"files":['
    local first=true
    for (( i=0; i<${#file_paths[@]}; i++ )); do
        if $first; then
            first=false
        else
            printf ','
        fi
        printf '{"path":"%s","tokens":%d,"included":%s}' \
            "${file_paths[i]}" "${file_tokens[i]}" "${file_included[i]:-false}"
    done
    printf '],"total_tokens":%d,"files_included":%d,"files_excluded":%d}\n' \
        "$used" "$included" "$excluded"
}

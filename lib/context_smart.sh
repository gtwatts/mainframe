#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206

# =============================================================================
# MAINFRAME/lib/context_smart.sh - Intelligent Context Management
# =============================================================================
# Description: Smart context management with semantic relevance scoring,
#              multi-factor ranking, and automatic content optimization.
# Version: 1.0.0
# Standards: USOP (Universal Structured Output Protocol)
# =============================================================================
# "Intelligent agents need intelligent context selection."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CONTEXT_SMART_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CONTEXT_SMART_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

# Scoring weights (percentages)
readonly _CTX_SCORE_KEYWORD_WEIGHT=30
readonly _CTX_SCORE_TYPE_WEIGHT=20
readonly _CTX_SCORE_RECENCY_WEIGHT=15
readonly _CTX_SCORE_FREQUENCY_WEIGHT=20
readonly _CTX_SCORE_IMPORTANCE_WEIGHT=15

# Content type confidence thresholds
readonly _CTX_CONFIDENCE_HIGH=80
readonly _CTX_CONFIDENCE_MEDIUM=50

# State directory
: "${MAINFRAME_CONTEXT_STATE_DIR:=${HOME}/.mainframe/context}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_ctx_smart_epoch() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v _ts '%(%s)T' -1 2>/dev/null && [[ -n "$_ts" ]]; then
        printf '%s' "$_ts"
    else
        date +%s
    fi
}

_ctx_smart_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    str="${str//[^[:print:][:space:]]/}"
    printf '%s' "$str"
}

# Portable lowercase conversion
_ctx_smart_tolower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

_ctx_smart_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "context_smart" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[context_smart] %s: %s\n' "$level" "$*" >&2
    fi
}

# USOP output helpers
_ctx_smart_usop_success() {
    local data="${1:-null}"
    local hint="${2:-}"
    local timestamp
    timestamp=$(_ctx_smart_epoch)
    
    if [[ -z "$hint" ]]; then
        printf '{"ok":true,"data":%s,"meta":{"timestamp":%s000}}\n' "$data" "$timestamp"
    else
        printf '{"ok":true,"data":%s,"meta":{"timestamp":%s000},"hint":"%s"}\n' \
            "$data" "$timestamp" "$(_ctx_smart_json_escape "$hint")"
    fi
}

_ctx_smart_usop_error() {
    local code="$1"
    local msg="$2"
    local suggestion="${3:-}"
    local timestamp
    timestamp=$(_ctx_smart_epoch)
    
    if [[ -z "$suggestion" ]]; then
        printf '{"ok":false,"error":{"code":"%s","msg":"%s"},"meta":{"timestamp":%s000}}\n' \
            "$code" "$(_ctx_smart_json_escape "$msg")" "$timestamp"
    else
        printf '{"ok":false,"error":{"code":"%s","msg":"%s","suggestion":"%s"},"meta":{"timestamp":%s000}}\n' \
            "$code" "$(_ctx_smart_json_escape "$msg")" "$(_ctx_smart_json_escape "$suggestion")" "$timestamp"
    fi
}

# Token estimation using context.sh if available
_ctx_smart_estimate_tokens() {
    local content="$1"
    
    if declare -F context_estimate_tokens &>/dev/null; then
        context_estimate_tokens "$content"
    else
        # Fallback: rough estimate (4 chars per token)
        local char_count=${#content}
        printf '%d' $(( (char_count + 3) / 4 ))
    fi
}

# =============================================================================
# SEMANTIC RELEVANCE SCORING
# =============================================================================

# Score relevance of content against a query
# Usage: context_score_relevance --content "..." --query "..."
# Returns: 0-100 relevance score
context_score_relevance() {
    local content=""
    local query=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --content) content="$2"; shift 2 ;;
            --query) query="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$content" || -z "$query" ]]; then
        _ctx_smart_usop_error "MISSING_ARGUMENTS" "Both --content and --query required"
        return 1
    fi
    
    # Normalize to lowercase for comparison
    local content_lower query_lower
    content_lower=$(_ctx_smart_tolower "$content")
    query_lower=$(_ctx_smart_tolower "$query")
    
    # Split query into words
    local -a query_words=()
    local word
    for word in $query_lower; do
        [[ ${#word} -gt 2 ]] && query_words+=("$word")
    done
    
    # Calculate keyword overlap score
    local matches=0
    local total_words=${#query_words[@]}
    
    if [[ $total_words -eq 0 ]]; then
        printf '%d\n' 0
        return 0
    fi
    
    for word in "${query_words[@]}"; do
        if [[ "$content_lower" == *"$word"* ]]; then
            ((matches++))
        fi
    done
    
    local keyword_score=$(( matches * 100 / total_words ))
    
    # Apply weights
    local final_score=$(( keyword_score ))
    
    _ctx_smart_log debug "Scored relevance: query_words=$total_words matches=$matches score=$final_score"
    
    printf '%d\n' "$final_score"
}

# Score relevance with multiple factors
# Internal: returns detailed scoring breakdown
_ctx_smart_score_detailed() {
    local content="$1"
    local query="$2"
    local content_type="${3:-text}"
    local timestamp="${4:-$(_ctx_smart_epoch)}"
    local access_count="${5:-1}"
    local user_importance="${6:-normal}"
    
    # Normalize
    local content_lower query_lower
    content_lower=$(_ctx_smart_tolower "$content")
    query_lower=$(_ctx_smart_tolower "$query")
    
    # 1. Keyword overlap (TF-IDF-style): 30%
    local -a query_words=()
    local word
    for word in $query_lower; do
        [[ ${#word} -gt 2 ]] && query_words+=("$word")
    done
    
    local matches=0
    local total_words=${#query_words[@]}
    
    for word in "${query_words[@]}"; do
        # Count occurrences for TF component
        local count=0
        local temp="$content_lower"
        while [[ "$temp" == *"$word"* ]]; do
            temp="${temp#*"$word"}"
            ((count++))
        done
        [[ $count -gt 0 ]] && ((matches++))
    done
    
    local keyword_score=0
    [[ $total_words -gt 0 ]] && keyword_score=$(( matches * 100 / total_words ))
    
    # 2. Content type importance: 20%
    local type_score=50
    case "$content_type" in
        code:*|data:json) type_score=80 ;;  # Code and structured data are important
        text:markdown) type_score=70 ;;     # Markdown often contains key info
        text:prose) type_score=40 ;;        # Prose is less structured
    esac
    
    # 3. Recency: 15% (based on age in days)
    local now
    now=$(_ctx_smart_epoch)
    local age_days=$(( (now - timestamp) / 86400 ))
    local recency_score=100
    if [[ $age_days -gt 30 ]]; then
        recency_score=20
    elif [[ $age_days -gt 7 ]]; then
        recency_score=50
    elif [[ $age_days -gt 1 ]]; then
        recency_score=80
    fi
    
    # 4. Access frequency: 20%
    local frequency_score=0
    if [[ $access_count -gt 10 ]]; then
        frequency_score=100
    elif [[ $access_count -gt 5 ]]; then
        frequency_score=80
    elif [[ $access_count -gt 2 ]]; then
        frequency_score=60
    else
        frequency_score=$(( access_count * 20 ))
    fi
    
    # 5. User-marked importance: 15%
    local importance_score=50
    case "$user_importance" in
        critical) importance_score=100 ;;
        high) importance_score=80 ;;
        normal) importance_score=50 ;;
        low) importance_score=20 ;;
    esac
    
    # Calculate weighted total
    local weighted_score=$((
        (keyword_score * _CTX_SCORE_KEYWORD_WEIGHT / 100) +
        (type_score * _CTX_SCORE_TYPE_WEIGHT / 100) +
        (recency_score * _CTX_SCORE_RECENCY_WEIGHT / 100) +
        (frequency_score * _CTX_SCORE_FREQUENCY_WEIGHT / 100) +
        (importance_score * _CTX_SCORE_IMPORTANCE_WEIGHT / 100)
    ))
    
    # Output JSON with breakdown
    printf '{"total":%d,"breakdown":{"keyword":%d,"type":%d,"recency":%d,"frequency":%d,"importance":%d}}\n' \
        "$weighted_score" "$keyword_score" "$type_score" "$recency_score" "$frequency_score" "$importance_score"
}

# =============================================================================
# SMART CONTENT SELECTION
# =============================================================================

# Select content items within budget based on relevance
# Usage: context_select_by_relevance --budget 4000 --items "content1" "content2" ...
# Returns: JSON array of selected content within budget
context_select_by_relevance() {
    local budget=""
    local -a items=()
    local query=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --budget) budget="$2"; shift 2 ;;
            --items) 
                shift
                while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
                    items+=("$1")
                    shift
                done
                ;;
            --query) query="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$budget" ]]; then
        _ctx_smart_usop_error "MISSING_BUDGET" "Token budget required (--budget)"
        return 1
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        _ctx_smart_usop_success '[]'
        return 0
    fi
    
    # Score and rank all items
    local -a scored_items=()
    local i
    for ((i=0; i<${#items[@]}; i++)); do
        local content="${items[$i]}"
        local score
        
        if [[ -n "$query" ]]; then
            score=$(context_score_relevance --content "$content" --query "$query" 2>/dev/null | grep -o '[0-9]*' | head -1)
        else
            # Without query, score by content type
            local content_type
            content_type=$(context_detect_type_v2 "$content" 2>/dev/null | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
            case "$content_type" in
                code:*) score=80 ;;
                data:*) score=70 ;;
                text:markdown) score=60 ;;
                *) score=50 ;;
            esac
        fi
        
        score="${score:-50}"
        local tokens
        tokens=$(_ctx_smart_estimate_tokens "$content")
        
        # Format: score|tokens|index|content
        scored_items+=("$(printf '%04d|%010d|%04d|%s' "$score" "$tokens" "$i" "$content")")
    done
    
    # Sort by score descending (highest first)
    # shellcheck disable=SC2207
    IFS=$'\n' sorted_items=($(sort -t'|' -k1,1nr <<< "${scored_items[*]}")); unset IFS
    
    # Select items within budget
    local -a selected=()
    local used_tokens=0
    local selected_count=0
    
    for item in "${sorted_items[@]}"; do
        # shellcheck disable=SC2155
        local tokens=$(echo "$item" | cut -d'|' -f2 | sed 's/^0*//')
        [[ -z "$tokens" ]] && tokens=0
        # shellcheck disable=SC2155
        local content=$(echo "$item" | cut -d'|' -f4-)
        # shellcheck disable=SC2155
        local score=$(echo "$item" | cut -d'|' -f1 | sed 's/^0*//')
        [[ -z "$score" ]] && score=0
        
        if [[ $(( used_tokens + tokens )) -le $budget ]]; then
            local escaped_content
            escaped_content=$(_ctx_smart_json_escape "$content")
            selected+=("{\"content\":\"$escaped_content\",\"tokens\":$tokens,\"score\":$score}")
            used_tokens=$(( used_tokens + tokens ))
            ((selected_count++))
        fi
    done
    
    # Build JSON response
    local result="["
    local first=true
    for item in "${selected[@]}"; do
        $first || result+=","
        first=false
        result+="$item"
    done
    result+="]"
    
    _ctx_smart_log debug "Selected $selected_count items within budget $budget (used: $used_tokens)"
    
    _ctx_smart_usop_success "$result" "context_select_by_relevance"
}

# =============================================================================
# CONTENT TYPE DETECTION V2
# =============================================================================

# Enhanced content type detection with confidence score
# Usage: context_detect_type_v2 "content"
# Returns: JSON with type and confidence
# shellcheck disable=SC2034
type_confidence=0
context_detect_type_v2() {
    local text="$1"
    
    if [[ -z "$text" ]]; then
        printf '{"type":"text:unknown","confidence":0}\n'
        return 0
    fi
    
    local trimmed="${text#"${text%%[![:space:]]*}"}"
    local confidence=0
    local detected_type="text:prose"
    
    # Check for JSON
    if [[ "$trimmed" == "{"* ]] || [[ "$trimmed" == "["* ]]; then
        # Validate JSON structure
        local has_json_markers=false
        [[ "$trimmed" == *":"* ]] && has_json_markers=true
        [[ "$trimmed" == *","* ]] && has_json_markers=true
        
        if $has_json_markers; then
            detected_type="data:json"
            confidence=95
            printf '{"type":"%s","confidence":%d}\n' "$detected_type" "$confidence"
            return 0
        fi
    fi
    
    # Check for XML/HTML
    if [[ "$trimmed" == "<?xml"* ]] || [[ "$trimmed" == "<!DOCTYPE"* ]] || [[ "$trimmed" == "<html"* ]]; then
        detected_type="data:xml"
        confidence=90
        printf '{"type":"%s","confidence":%d}\n' "$detected_type" "$confidence"
        return 0
    fi
    
    # Check for YAML
    if [[ "$trimmed" == "---"* ]] || [[ "$trimmed" =~ ^[a-zA-Z_][a-zA-Z0-9_]*:\  ]]; then
        detected_type="data:yaml"
        confidence=85
        printf '{"type":"%s","confidence":%d}\n' "$detected_type" "$confidence"
        return 0
    fi
    
    # Code detection
    local total_lines=0
    local code_lines=0
    local shebang=false
    # shellcheck disable=SC2034
    local has_def=false
    # shellcheck disable=SC2034
    local has_class=false
    # shellcheck disable=SC2034
    local has_import=false
    # shellcheck disable=SC2034
    local has_function=false
    # shellcheck disable=SC2034
    local has_const=false
    local first_line=true
    
    # Language-specific patterns
    local py_patterns=0
    local bash_patterns=0
    local js_patterns=0
    local go_patterns=0
    local rust_patterns=0
    
    while IFS= read -r line; do
        ((total_lines++))
        
        if $first_line; then
            first_line=false
            if [[ "$line" == "#!"* ]]; then
                # shellcheck disable=SC2034
                shebang=true
                [[ "$line" == *"python"* ]] && ((py_patterns+=5))
                [[ "$line" == *"bash"* ]] && ((bash_patterns+=5))
                [[ "$line" == *"/sh"* ]] && ((bash_patterns+=3))
            fi
        fi
        
        # Code-like patterns
        if [[ "$line" =~ ^[[:space:]] ]] || [[ "$line" =~ [\{\}\;\(\)=] ]]; then
            ((code_lines++))
        fi
        
        # Python patterns
        [[ "$line" =~ ^(def |async def |class |import |from ) ]] && ((py_patterns++))
        [[ "$line" =~ ^[[:space:]]+(def |class |if |for |while |with |try:) ]] && ((py_patterns++))
        
        # Bash patterns
        [[ "$line" =~ ^(function |if \[|then$|fi$|for |while |case ) ]] && ((bash_patterns++))
        [[ "$line" =~ \$\{ ]] && ((bash_patterns++))
        [[ "$line" == *"#!/"*"bash"* ]] && ((bash_patterns+=3))
        
        # JavaScript/TypeScript patterns
        [[ "$line" =~ ^(const |let |var |function |=> |export |import ) ]] && ((js_patterns++))
        [[ "$line" == *"=>"* ]] && ((js_patterns++))
        
        # Go patterns
        [[ "$line" =~ ^(func |package |import \(|type |struct ) ]] && ((go_patterns++))
        [[ "$line" == *":="* ]] && ((go_patterns++))
        
        # Rust patterns
        [[ "$line" =~ ^(fn |impl |struct |enum |use |mod |let mut ) ]] && ((rust_patterns++))
        [[ "$line" == *"->"* ]] && ((rust_patterns++))
        
    done <<< "$text"
    
    [[ $total_lines -eq 0 ]] && total_lines=1
    
    local code_percent=$(( code_lines * 100 / total_lines ))
    
    if [[ $code_percent -gt 30 ]]; then
        # Determine language by pattern matching
        local max_patterns=$py_patterns
        local lang="python"
        
        if [[ $bash_patterns -gt $max_patterns ]]; then
            max_patterns=$bash_patterns
            lang="bash"
        fi
        
        if [[ $js_patterns -gt $max_patterns ]]; then
            max_patterns=$js_patterns
            lang="javascript"
        fi
        
        if [[ $go_patterns -gt $max_patterns ]]; then
            max_patterns=$go_patterns
            lang="go"
        fi
        
        if [[ $rust_patterns -gt $max_patterns ]]; then
            max_patterns=$rust_patterns
            lang="rust"
        fi
        
        detected_type="code:$lang"
        confidence=$(( 50 + code_percent / 2 ))
        [[ $confidence -gt 98 ]] && confidence=98
        
        # Boost confidence for high pattern match
        if [[ $max_patterns -gt $(( total_lines / 3 )) ]]; then
            confidence=$(( confidence + 10 ))
            [[ $confidence -gt 98 ]] && confidence=98
        fi
        
    else
        # Check for Markdown
        local md_indicators=0
        [[ "$text" == *"# "* ]] && ((md_indicators++))
        [[ "$text" == *"## "* ]] && ((md_indicators++))
        [[ "$text" == *"### "* ]] && ((md_indicators++))
        [[ "$text" == *"- "* ]] && ((md_indicators++))
        [[ "$text" == *'```'* ]] && ((md_indicators++))
        [[ "$text" == *"**"* ]] && ((md_indicators++))
        [[ "$text" == *"__"* ]] && ((md_indicators++))
        [[ "$text" == *"|"*"|"* ]] && ((md_indicators++))
        
        if [[ $md_indicators -ge 3 ]]; then
            detected_type="text:markdown"
            confidence=$(( 50 + md_indicators * 10 ))
            [[ $confidence -gt 95 ]] && confidence=95
        else
            detected_type="text:prose"
            confidence=$(( 100 - code_percent ))
        fi
    fi
    
    printf '{"type":"%s","confidence":%d}\n' "$detected_type" "$confidence"
}

# =============================================================================
# AUTOMATIC CONTEXT OPTIMIZATION
# =============================================================================

# Optimize content to fit within token budget
# Usage: context_optimize --max-tokens 4000 --content "..."
# Returns: Optimized content
context_optimize() {
    local max_tokens=""
    local content=""
    local strategy="smart"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-tokens) max_tokens="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            --strategy) strategy="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$max_tokens" || -z "$content" ]]; then
        _ctx_smart_usop_error "MISSING_ARGUMENTS" "Both --max-tokens and --content required"
        return 1
    fi
    
    # First, estimate current tokens
    local current_tokens
    current_tokens=$(_ctx_smart_estimate_tokens "$content")
    
    # If already within budget, return as-is
    if [[ $current_tokens -le $max_tokens ]]; then
        printf '%s\n' "$content"
        return 0
    fi
    
    # Use context.sh truncate if available
    if declare -F context_truncate &>/dev/null; then
        local result
        result=$(context_truncate "$content" "$max_tokens" --strategy "$strategy" 2>/dev/null)
        if [[ -n "$result" ]]; then
            printf '%s\n' "$result"
            return 0
        fi
    fi
    
    # Fallback: simple truncation
    local target_chars=$(( max_tokens * 4 ))
    local half_chars=$(( target_chars / 2 ))
    
    # Keep first and last portions
    local head="${content:0:$half_chars}"
    local tail_start=$(( ${#content} - half_chars ))
    [[ $tail_start -lt 0 ]] && tail_start=0
    local tail="${content:$tail_start}"
    
    printf '%s\n... (truncated to fit %d tokens) ...\n%s\n' "$head" "$max_tokens" "$tail"
}

# =============================================================================
# BATCH OPTIMIZATION
# =============================================================================

# Optimize multiple content pieces as a batch
# Usage: context_optimize_batch --max-tokens 4000 --strategy balanced < items.txt
context_optimize_batch() {
    local max_tokens=""
    local strategy="balanced"  # balanced, priority, equal
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-tokens) max_tokens="$2"; shift 2 ;;
            --strategy) strategy="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$max_tokens" ]]; then
        _ctx_smart_usop_error "MISSING_ARGUMENTS" "--max-tokens required"
        return 1
    fi
    
    # Read all items from stdin
    local -a items=()
    local line
    while IFS= read -r line; do
        items+=("$line")
    done
    
    if [[ ${#items[@]} -eq 0 ]]; then
        _ctx_smart_usop_success '[]'
        return 0
    fi
    
    # Calculate per-item budget based on strategy
    local -a budgets=()
    local item_count=${#items[@]}
    
    case "$strategy" in
        equal)
            local per_item=$(( max_tokens / item_count ))
            for ((i=0; i<item_count; i++)); do
                # shellcheck disable=SC2206
                budgets+=($per_item)
            done
            ;;
        priority|balanced|*)
            # Proportional allocation based on content size
            local -a item_tokens=()
            local total_tokens=0
            
            for item in "${items[@]}"; do
                local tokens
                tokens=$(_ctx_smart_estimate_tokens "$item")
                # shellcheck disable=SC2206
                item_tokens+=($tokens)
                total_tokens=$(( total_tokens + tokens ))
            done
            
            if [[ $total_tokens -le $max_tokens ]]; then
                # Everything fits
                for ((i=0; i<item_count; i++)); do
                    # shellcheck disable=SC2206
                    budgets+=(${item_tokens[$i]})
                done
            else
                # Scale down proportionally
                local scale=$(( max_tokens * 100 / total_tokens ))
                for ((i=0; i<item_count; i++)); do
                    budgets+=($(( item_tokens[i] * scale / 100 )))
                done
            fi
            ;;
    esac
    
    # Optimize each item
    local -a results=()
    for ((i=0; i<item_count; i++)); do
        local optimized
        optimized=$(context_optimize --max-tokens "${budgets[$i]}" --content "${items[$i]}" 2>/dev/null)
        local escaped
        escaped=$(_ctx_smart_json_escape "$optimized")
        results+=("{\"item\":$i,\"budget\":${budgets[$i]},\"content\":\"$escaped\"}")
    done
    
    # Build result
    local result="["
    local first=true
    for item in "${results[@]}"; do
        $first || result+=","
        first=false
        result+="$item"
    done
    result+="]"
    
    _ctx_smart_usop_success "$result"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

CONTEXT_SMART_EXPORTS=(
    context_score_relevance
    context_select_by_relevance
    context_detect_type_v2
    context_optimize
    context_optimize_batch
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${CONTEXT_SMART_EXPORTS[@]}" 2>/dev/null || true
fi

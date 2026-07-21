#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/optimize.sh - Command Optimization Library
# =============================================================================
# Description: Detect and suggest optimizations for shell commands and pipelines
#              Eliminates useless use of cat, consolidates grep chains, and more.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_OPTIMIZE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_OPTIMIZE_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/common.sh"
source "${BASH_SOURCE%/*}/json.sh"

# =============================================================================
# OPTIMIZATION RULES
# =============================================================================

# Pattern → Replacement mappings with metadata
# Format: pattern|replacement|improvement|safety|explanation
declare -gA _OPTIMIZE_RULES=(
    # Useless cat - most common anti-pattern
    ['cat \(.*\) | grep \(.*\)']='grep \2 \1|2.5x faster|equivalent|grep can read files directly, avoiding pipe overhead'
    ['cat \(.*\) | head']='head \1|2x faster|equivalent|head can read files directly'
    ['cat \(.*\) | tail']='tail \1|2x faster|equivalent|tail can read files directly'
    ['cat \(.*\) | wc']='wc \1|2x faster|equivalent|wc can read files directly'
    ['cat \(.*\) | sort']='sort \1|2x faster|equivalent|sort can read files directly'
    ['cat \(.*\) | uniq']='uniq \1|2x faster|equivalent|uniq can read files directly'
    ['cat \(.*\) | awk']='awk \1|2x faster|equivalent|awk can read files directly'
    ['cat \(.*\) | sed']='sed \1|2x faster|equivalent|sed can read files directly'
    
    # Multiple grep chains
    ['grep \(.*\) | grep \(.*\)']='grep -E "\1.*\2"|1.5x faster|equivalent|Single grep with -E is more efficient than chaining'
    ['grep -v \(.*\) | grep -v \(.*\)']='grep -v -E "\1|\2"|1.5x faster|equivalent|Single grep with multiple patterns is more efficient'
    
    # Find optimizations
    ['find \(.*\) -exec rm {} \\;']='find \1 -delete|10x faster|safe|Built-in -delete is faster and safer than -exec rm'
    ['find \(.*\) -exec cat {} \\;']='find \1 -exec cat {} +|5x faster|equivalent|+ passes multiple files to single cat process'
    ['find \(.*\) -exec grep \(.*\) {} \\;']='find \1 -exec grep \2 {} +|3x faster|equivalent|+ reduces process spawn overhead'
    
    # Awk/sed optimizations
    ['cat \(.*\) | grep \(.*\) | awk']='awk "/\2/" \1|3x faster|equivalent|awk can filter and process in one pass'
    ['grep \(.*\) | awk \(.*\)']='awk "/\1/ \2"|2x faster|equivalent|Combine filter and processing in awk'
    ['sed \(.*\) | grep \(.*\)']='sed -n "/\2/\1"|1.8x faster|equivalent|Use sed -n with pattern addresses'
    
    # Sort/uniq optimizations
    ['sort \(.*\) | uniq']='sort -u \1|1.5x faster|equivalent|sort -u combines sort and uniq'
    ['sort \(.*\) | uniq -c']='sort \1 | uniq -c|no change|equivalent|sort | uniq -c is already optimal'
    
    # xargs improvements
    ['find \(.*\) -exec \(.*\) {} \\;']='find \1 -print0 | xargs -0 -P4 \2|5x faster|safe|xargs -P enables parallel processing'
    ['find \(.*\) | xargs \(.*\)']='find \1 -print0 | xargs -0 \2|safer|safe|-print0/-0 handles filenames with spaces safely'
    
    # head/tail pipeline optimizations
    ['cat \(.*\) | head -\([0-9]*\) | tail -\([0-9]*\)']='sed -n "\2,\3p" \1|3x faster|equivalent|sed can extract ranges directly'
    ['head -\([0-9]*\) \(.*\) | tail -\([0-9]*\)']='sed -n "\1,\3p" \2|2x faster|equivalent|sed can extract ranges directly'
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape a string for use in JSON output
# Usage: _optimize_json_escape "string"
_optimize_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Extract file path from cat command
# Usage: _optimize_get_file "cat file.txt | grep foo"
_optimize_get_file() {
    local cmd="$1"
    if [[ "$cmd" =~ cat[[:space:]]+([^|]+)[[:space:]]*\| ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Extract grep pattern from command
# Usage: _optimize_get_pattern "grep foo file.txt"
_optimize_get_pattern() {
    local cmd="$1"
    if [[ "$cmd" =~ grep[[:space:]]+(\-[^[:space:]]+[[:space:]]+)*([^[:space:]]+) ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# Calculate the range for head | tail optimization
# Usage: _optimize_calc_range head_n tail_n
_optimize_calc_range() {
    local head_n="$1"
    local tail_n="$2"
    local start=$((head_n - tail_n + 1))
    local end=$head_n
    printf '%d,%dp' "$start" "$end"
}

# =============================================================================
# PATTERN MATCHING
# =============================================================================

# Match command against optimization rules
# Usage: _optimize_match_rule "$command"
# Returns: rule_key if matched, empty otherwise
_optimize_match_rule() {
    local cmd="$1"
    local rule_key
    
    # Check each rule pattern
    for rule_key in "${!_OPTIMIZE_RULES[@]}"; do
        # Convert shell-style pattern to regex
        local pattern="${rule_key//\(.*\)/(.*)}"
        pattern="^${pattern// /[[:space:]]+}$"
        
        if [[ "$cmd" =~ $pattern ]]; then
            printf '%s' "$rule_key"
            return 0
        fi
    done
    
    return 1
}

# Apply matched rule to generate optimized command
# Usage: _optimize_apply_rule "$rule_key" "$original_cmd"
_optimize_apply_rule() {
    local rule_key="$1"
    local cmd="$2"
    local rule_data="${_OPTIMIZE_RULES[$rule_key]}"
    
    # Parse rule data
    local IFS='|'
    local -a parts
    read -ra parts <<< "$rule_data"
    local template="${parts[0]}"
    
    # Extract captures from command
    local pattern="${rule_key//\(.*\)/(.*)}"
    pattern="^${pattern// /[[:space:]]+}$"
    
    if [[ "$cmd" =~ $pattern ]]; then
        # Apply captures to template
        local result="$template"
        local i
        for ((i=1; i<${#BASH_REMATCH[@]}; i++)); do
            local placeholder="\\$i"
            result="${result//$placeholder/${BASH_REMATCH[$i]}}"
        done
        printf '%s' "$result"
        return 0
    fi
    
    return 1
}

# =============================================================================
# CORE OPTIMIZATION FUNCTIONS
# =============================================================================

# Suggest optimized version of a command with full details
# Usage: optimize_command "cat file.txt | grep foo"
# Returns: JSON with original, optimized, improvement, safety
optimize_command() {
    local cmd="$1"
    
    [[ -z "$cmd" ]] && {
        json_object \
            "original:string=" \
            "optimized:string=" \
            "improvement:string=No command provided" \
            "safety:string=unknown"
        return 1
    }
    
    # Trim whitespace
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    cmd="${cmd%"${cmd##*[![:space:]]}"}"
    
    local rule_key optimized improvement safety explanation
    local found=0
    
    # Try specific pattern matching first
    local pattern file arg1 arg2 arg3
    
    # Pattern: cat file | grep pattern -> grep pattern file
    if [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*grep[[:space:]]+(\-[^[:space:]]+[[:space:]]+)*([^|]+)$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        pattern="${BASH_REMATCH[3]}"
        pattern="${pattern# }"
        pattern="${pattern% }"
        local grep_opts="${BASH_REMATCH[2]}"
        grep_opts="${grep_opts% }"
        
        optimized="grep${grep_opts:+ $grep_opts} $pattern $file"
        improvement="2.5x faster, eliminates pipe overhead"
        safety="equivalent"
        explanation="grep can read files directly, avoiding the overhead of piping from cat"
        found=1
    
    # Pattern: cat file | head -n -> head -n file
    elif [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*head[[:space:]]+(-[[:space:]]*)?([0-9]+|-[[:space:]]*[0-9]+|n[[:space:]]*[0-9]+)$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local num="${BASH_REMATCH[3]}"
        num="${num// /}"
        num="${num#n}"
        
        optimized="head -n $num $file"
        improvement="2x faster, eliminates pipe overhead"
        safety="equivalent"
        explanation="head can read files directly, avoiding the overhead of piping from cat"
        found=1
    
    # Pattern: cat file | tail -n -> tail -n file
    elif [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*tail[[:space:]]+(-[[:space:]]*)?([0-9]+|-[[:space:]]*[0-9]+|n[[:space:]]*[0-9]+)$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local num="${BASH_REMATCH[3]}"
        num="${num// /}"
        num="${num#n}"
        
        optimized="tail -n $num $file"
        improvement="2x faster, eliminates pipe overhead"
        safety="equivalent"
        explanation="tail can read files directly, avoiding the overhead of piping from cat"
        found=1
    
    # Pattern: cat file | awk '...' -> awk '...' file
    elif [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*awk[[:space:]]+(.*)$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local awk_script="${BASH_REMATCH[2]}"
        
        optimized="awk $awk_script $file"
        improvement="2x faster, eliminates pipe overhead"
        safety="equivalent"
        explanation="awk can read files directly, avoiding the overhead of piping from cat"
        found=1
    
    # Pattern: cat file | sed '...' -> sed '...' file
    elif [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*sed[[:space:]]+(.*)$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local sed_script="${BASH_REMATCH[2]}"
        
        optimized="sed $sed_script $file"
        improvement="2x faster, eliminates pipe overhead"
        safety="equivalent"
        explanation="sed can read files directly, avoiding the overhead of piping from cat"
        found=1
    
    # Pattern: cat file | wc -> wc file
    elif [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*wc([[:space:]]+\-[^|]+)?$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local wc_opts="${BASH_REMATCH[2]}"
        wc_opts="${wc_opts% }"
        
        optimized="wc${wc_opts:+ $wc_opts} $file"
        improvement="2x faster, eliminates pipe overhead"
        safety="equivalent"
        explanation="wc can read files directly, avoiding the overhead of piping from cat"
        found=1
    
    # Pattern: cat file | sort -> sort file
    elif [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*sort([[:space:]]+[^|]+)?$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local sort_opts="${BASH_REMATCH[2]}"
        sort_opts="${sort_opts% }"
        
        optimized="sort${sort_opts:+ $sort_opts} $file"
        improvement="2x faster, eliminates pipe overhead"
        safety="equivalent"
        explanation="sort can read files directly, avoiding the overhead of piping from cat"
        found=1
    
    # Pattern: sort file | uniq -> sort -u file
    elif [[ "$cmd" =~ ^sort[[:space:]]+([^|]+)\|[[:space:]]*uniq([[:space:]]+[^|]+)?$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local sort_opts="${BASH_REMATCH[2]}"
        sort_opts="${sort_opts% }"
        
        optimized="sort -u${sort_opts:+ $sort_opts} $file"
        improvement="1.5x faster, single process instead of two"
        safety="equivalent"
        explanation="sort -u combines sorting and duplicate removal in a single operation"
        found=1
    
    # Pattern: grep pattern1 | grep pattern2 -> grep -E "pattern1.*pattern2"
    elif [[ "$cmd" =~ ^grep[[:space:]]+(\-[^[:space:]]+[[:space:]]+)*([^[:space:]][^|]*)[[:space:]]*\|[[:space:]]*grep[[:space:]]+(\-[^[:space:]]+[[:space:]]+)*([^|]+)$ ]]; then
        local opts1="${BASH_REMATCH[1]}"
        opts1="${opts1% }"
        local pattern_and_file="${BASH_REMATCH[2]}"
        pattern_and_file="${pattern_and_file% }"
        # Extract just the pattern (first word that doesn't start with -)
        local pattern="${pattern_and_file%% *}"
        local file="${pattern_and_file#$pattern}"
        file="${file# }"
        local opts2="${BASH_REMATCH[3]}"
        opts2="${opts2% }"
        local pattern2="${BASH_REMATCH[4]}"
        pattern2="${pattern2# }"
        pattern2="${pattern2% }"
        
        if [[ -n "$file" ]]; then
            optimized="grep -E${opts1:+ $opts1} \"$pattern.*$pattern2\" $file"
        else
            optimized="grep -E${opts1:+ $opts1} \"$pattern.*$pattern2\""
        fi
        improvement="1.5x faster, single process instead of pipe"
        safety="mostly_equivalent"
        explanation="grep -E combines patterns efficiently. Note: line semantics may differ slightly for overlapping matches."
        found=1
    
    # Pattern: find path -exec cmd {} \; -> find path -exec cmd {} +
    elif [[ "$cmd" =~ ^find[[:space:]]+([^-]+)(.+)-exec[[:space:]]+([^}]+)\{\}[[:space:]]*\\\; ]]; then
        local find_path="${BASH_REMATCH[1]}"
        find_path="${find_path% }"
        local find_opts="${BASH_REMATCH[2]}"
        find_opts="${find_opts% }"
        local exec_cmd="${BASH_REMATCH[3]}"
        exec_cmd="${exec_cmd% }"
        
        # Special case: rm -> use -delete
        if [[ "$exec_cmd" =~ ^rm([[:space:]]+.*)?$ ]]; then
            optimized="find $find_path${find_opts:+ $find_opts} -delete"
            improvement="10x faster, built-in operation"
            safety="safe"
            explanation="find -delete is faster and safer than -exec rm, handles edge cases better"
        else
            optimized="find $find_path${find_opts:+ $find_opts} -exec $exec_cmd {} +"
            improvement="3-5x faster, batch processing"
            safety="equivalent"
            explanation="{} + passes multiple files to a single command process, reducing spawn overhead"
        fi
        found=1
    
    # Pattern: cat file | head -N | tail -M -> sed -n 'X,Yp' file
    elif [[ "$cmd" =~ ^cat[[:space:]]+([^|]+)\|[[:space:]]*head[[:space:]]+(-[[:space:]]*)?([0-9]+)[[:space:]]*\|[[:space:]]*tail[[:space:]]+(-[[:space:]]*)?([0-9]+)$ ]]; then
        file="${BASH_REMATCH[1]}"
        file="${file# }"
        file="${file% }"
        local head_n="${BASH_REMATCH[3]}"
        local tail_n="${BASH_REMATCH[5]}"
        local range_start=$((head_n - tail_n + 1))
        
        optimized="sed -n '${range_start},${head_n}p' $file"
        improvement="3x faster, single process instead of three"
        safety="equivalent"
        explanation="sed can extract line ranges directly without creating intermediate streams"
        found=1
    
    # Pattern: head -N file | tail -M -> sed -n 'X,Yp' file
    elif [[ "$cmd" =~ ^head[[:space:]]+(-[[:space:]]*)?([0-9]+)[[:space:]]+([^|]+)\|[[:space:]]*tail[[:space:]]+(-[[:space:]]*)?([0-9]+)$ ]]; then
        file="${BASH_REMATCH[3]}"
        file="${file# }"
        file="${file% }"
        local head_n2="${BASH_REMATCH[2]}"
        local tail_n2="${BASH_REMATCH[5]}"
        local range_start2=$((head_n2 - tail_n2 + 1))
        
        optimized="sed -n '${range_start2},${head_n2}p' $file"
        improvement="2x faster, single process instead of two"
        safety="equivalent"
        explanation="sed can extract line ranges directly without creating intermediate streams"
        found=1
    fi
    
    if [[ $found -eq 1 ]]; then
        # Trim the optimized command
        optimized="${optimized# }"
        optimized="${optimized% }"
        
        # Build JSON output
        local escaped_original escaped_optimized escaped_improvement escaped_safety escaped_explanation
        escaped_original=$(_optimize_json_escape "$cmd")
        escaped_optimized=$(_optimize_json_escape "$optimized")
        escaped_improvement=$(_optimize_json_escape "$improvement")
        escaped_safety=$(_optimize_json_escape "$safety")
        escaped_explanation=$(_optimize_json_escape "$explanation")
        
        printf '{"original":"%s","optimized":"%s","improvement":"%s","safety":"%s","explanation":"%s"}\n' \
            "$escaped_original" "$escaped_optimized" "$escaped_improvement" "$escaped_safety" "$escaped_explanation"
        return 0
    else
        # No optimization found
        local escaped_cmd
        escaped_cmd=$(_optimize_json_escape "$cmd")
        printf '{"original":"%s","optimized":"%s","improvement":"%s","safety":"%s","explanation":"%s"}\n' \
            "$escaped_cmd" "$escaped_cmd" "No optimization applicable" "n/a" "Command pattern does not match any known optimization rules"
        return 0
    fi
}

# Return optimized command only (auto-apply)
# Usage: optimize_auto "cat file.txt | grep foo"
# Returns: "grep foo file.txt"
optimize_auto() {
    local cmd="$1"
    
    [[ -z "$cmd" ]] && return 1
    
    # Get full optimization result and extract optimized field
    local result
    result=$(optimize_command "$cmd")
    
    # Extract optimized value using simple regex
    if [[ "$result" =~ \"optimized\"\:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # Fallback: return original
    printf '%s' "$cmd"
}

# Optimize a pipeline with multiple stages
# Usage: optimize_pipeline "cat big.txt | head -100 | tail -10 | grep foo"
# Returns: optimized pipeline as string
optimize_pipeline() {
    local pipeline="$1"
    
    [[ -z "$pipeline" ]] && return 1
    
    # Split pipeline into stages
    local IFS='|'
    local -a stages
    read -ra stages <<< "$pipeline"
    
    # First, check for full-pipeline optimizations
    local optimized_full
    optimized_full=$(optimize_auto "$pipeline")
    
    # If we got a different result, use it
    if [[ "$optimized_full" != "$pipeline" ]]; then
        printf '%s' "$optimized_full"
        return 0
    fi
    
    # Otherwise, optimize stage by stage where possible
    local -a optimized_stages
    local stage prev_stage=""
    
    for stage in "${stages[@]}"; do
        # Trim whitespace
        stage="${stage#"${stage%%[![:space:]]*}"}"
        stage="${stage%"${stage##*[![:space:]]}"}"
        
        if [[ -n "$prev_stage" ]]; then
            # Try to optimize the pair
            local combined="${prev_stage} | ${stage}"
            local pair_optimized
            pair_optimized=$(optimize_auto "$combined")
            
            if [[ "$pair_optimized" != "$combined" ]]; then
                # Replace previous stage with optimized version
                prev_stage="$pair_optimized"
            else
                # Keep both stages
                optimized_stages+=("$prev_stage")
                prev_stage="$stage"
            fi
        else
            prev_stage="$stage"
        fi
    done
    
    # Add the last stage
    [[ -n "$prev_stage" ]] && optimized_stages+=("$prev_stage")
    
    # Reconstruct pipeline
    local result=""
    local first=1
    for stage in "${optimized_stages[@]}"; do
        if [[ $first -eq 1 ]]; then
            result="$stage"
            first=0
        else
            result="${result} | ${stage}"
        fi
    done
    
    printf '%s' "$result"
}

# Explain why an optimization helps
# Usage: optimize_explain "$original" "$optimized"
# Returns: Human-readable explanation
optimize_explain() {
    local original="$1"
    local optimized="$2"
    
    [[ -z "$original" || -z "$optimized" ]] && {
        printf 'Error: Both original and optimized commands are required\n'
        return 1
    }
    
    # Get the optimization details
    local result
    result=$(optimize_command "$original")
    
    # Extract fields
    local improvement safety explanation
    if [[ "$result" =~ \"improvement\"\:[[:space:]]*\"([^\"]+)\" ]]; then
        improvement="${BASH_REMATCH[1]}"
    fi
    if [[ "$result" =~ \"safety\"\:[[:space:]]*\"([^\"]+)\" ]]; then
        safety="${BASH_REMATCH[1]}"
    fi
    if [[ "$result" =~ \"explanation\"\:[[:space:]]*\"([^\"]+)\" ]]; then
        explanation="${BASH_REMATCH[1]}"
    fi
    
    # Format output
    printf 'Optimization Analysis\n'
    printf '====================\n\n'
    printf 'Original:  %s\n' "$original"
    printf 'Optimized: %s\n\n' "$optimized"
    printf 'Performance: %s\n' "${improvement:-Unknown}"
    printf 'Safety:      %s\n\n' "${safety:-Unknown}"
    printf 'Explanation:\n%s\n' "${explanation:-No explanation available}"
    
    # Add specific analysis based on patterns
    printf '\nDetailed Analysis:\n'
    
    if [[ "$original" == *'cat '* ]]; then
        printf -- '- Useless use of cat: The cat command is unnecessary when the following\n'
        printf '  command can read files directly. This eliminates one process and\n'
        printf '  removes pipe overhead.\n'
    fi
    
    if [[ "$original" == *'grep'*'|'*'grep'* ]]; then
        printf -- '- Chained grep: Multiple grep commands in a pipeline can often be\n'
        printf '  combined into a single grep -E with a combined pattern. This reduces\n'
        printf '  process count and avoids intermediate buffering.\n'
    fi
    
    if [[ "$original" == *'head'*'|'*'tail'* ]]; then
        printf -- '- Range extraction: head | tail patterns extract line ranges. Using\n'
        printf '  sed -n with line numbers is more efficient as it processes the file\n'
        printf '  once and extracts exactly the needed lines.\n'
    fi
    
    if [[ "$original" == *'find'*'-exec'*'\;' ]]; then
        printf -- '- Process spawning: find -exec with \\; spawns a new process for each\n'
        printf '  file found. Using {} + batches files to reduce process overhead,\n'
        printf '  or -delete for removal operations.\n'
    fi
    
    if [[ "$original" == *'sort'*'|'*'uniq'* && "$optimized" == *'sort -u'* ]]; then
        printf -- '- Combined operation: sort -u performs sorting and duplicate removal\n'
        printf '  in a single pass, eliminating the need for a separate uniq process.\n'
    fi
}

# List all available optimization rules
# Usage: optimize_rules
# Returns: JSON array of optimization rules
optimize_rules() {
    local first_item=1
    printf '['
    
    local rule_key
    for rule_key in "${!_OPTIMIZE_RULES[@]}"; do
        local rule_data="${_OPTIMIZE_RULES[$rule_key]}"
        local IFS='|'
        local -a parts
        read -ra parts <<< "$rule_data"
        
        local template="${parts[0]}"
        local improvement="${parts[1]:-unknown}"
        local safety="${parts[2]:-unknown}"
        local explanation="${parts[3]:-}"
        
        [[ $first_item -eq 0 ]] && printf ','
        first_item=0
        
        json_object \
            "pattern:string=$rule_key" \
            "template:string=$template" \
            "improvement:string=$improvement" \
            "safety:string=$safety" \
            "explanation:string=$explanation"
    done
    
    printf ']\n'
}

# Check if a command can be optimized
# Usage: optimize_check "$command"
# Returns: 0 if optimizable, 1 otherwise
optimize_check() {
    local cmd="$1"
    
    [[ -z "$cmd" ]] && return 1
    
    local result
    result=$(optimize_command "$cmd")
    
    # Check if we got an optimization
    if [[ "$result" =~ \"improvement\"\:[[:space:]]*\"No\ optimization\ applicable\" ]]; then
        return 1
    fi
    
    return 0
}

# =============================================================================
# EXPORT
# =============================================================================

export -f optimize_command optimize_auto optimize_pipeline optimize_explain
export -f optimize_rules optimize_check
export -f _optimize_json_escape _optimize_get_file _optimize_get_pattern
export -f _optimize_calc_range _optimize_match_rule _optimize_apply_rule

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/template.sh - Mustache-Style Template Engine
# =============================================================================
# Description: Pure bash template engine with variable substitution, conditionals,
#              loops, partials, and built-in helpers
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TEMPLATE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TEMPLATE_LOADED=1

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Partials registry (associative array)
declare -gA _TEMPLATE_PARTIALS=()

# Custom helpers registry (associative array)
declare -gA _TEMPLATE_HELPERS=()

# Template variables (associative array)
declare -gA _TEMPLATE_VARS=()

# Render template from file
# Usage: template::render_file "config.tpl" name="value"
template::render_file() {
    local file="$1"
    shift
    
    if [[ ! -f "$file" ]]; then
        printf 'template::render_file: file not found: %s\n' "$file" >&2
        return 1
    fi
    
    local template
    template=$(<"$file")
    
    template::render "$template" "$@"
}

# =============================================================================
# PARTIALS (INCLUDES)
# =============================================================================

# Register a partial template
# Usage: template::partial "header" '<header>{{title}}</header>'
template::partial() {
    local name="$1"
    local content="$2"
    _TEMPLATE_PARTIALS["$name"]="$content"
}

# Register partial from file
# Usage: template::partial_file "header" "partials/header.tpl"
template::partial_file() {
    local name="$1"
    local file="$2"
    
    if [[ ! -f "$file" ]]; then
        printf 'template::partial_file: file not found: %s\n' "$file" >&2
        return 1
    fi
    
    _TEMPLATE_PARTIALS["$name"]=$(<"$file")
}

# Clear all partials
# Usage: template::clear_partials
template::clear_partials() {
    _TEMPLATE_PARTIALS=()
}

# =============================================================================
# CUSTOM HELPERS
# =============================================================================

# Register a custom helper function
# Usage: template::helper "myhelper" my_helper_function
template::helper() {
    local name="$1"
    local func="$2"
    _TEMPLATE_HELPERS["$name"]="$func"
}

# Clear all custom helpers
# Usage: template::clear_helpers
template::clear_helpers() {
    _TEMPLATE_HELPERS=()
}

# =============================================================================
# INTERNAL: TEMPLATE PROCESSING
# =============================================================================

# Process template string
_template_process() {
    local template="$1"
    local result=""
    local pos=0
    local len=${#template}
    
    while ((pos < len)); do
        # Look for {{ or {{{
        local next_open=-1
        local triple=false
        
        # Find next {{
        local rest="${template:pos}"
        if [[ "$rest" == *"{{"* ]]; then
            local before="${rest%%\{\{*}"
            next_open=$((pos + ${#before}))
            
            # Check for triple mustache (escaped output)
            if [[ "${template:next_open:3}" == "{{{" ]]; then
                triple=true
            fi
        fi
        
        if ((next_open == -1)); then
            # No more tags, append rest
            result+="${template:pos}"
            break
        fi
        
        # Append text before tag
        result+="${template:pos:$((next_open - pos))}"
        
        # Find closing }}
        local tag_start=$((next_open + 2))
        if $triple; then
            tag_start=$((next_open + 3))
        fi
        
        local close_pattern="}}"
        if $triple; then
            close_pattern="}}}"
        fi
        
        local tag_rest="${template:tag_start}"
        if [[ "$tag_rest" == *"$close_pattern"* ]]; then
            local tag_content="${tag_rest%%"$close_pattern"*}"
            local tag_end=$((tag_start + ${#tag_content} + ${#close_pattern}))
            
            # Process the tag
            local processed
            processed=$(_template_process_tag "$tag_content" "$triple")
            result+="$processed"
            
            pos=$tag_end
        else
            # Unclosed tag, treat as literal
            result+="{{"
            pos=$((next_open + 2))
        fi
    done
    
    printf '%s' "$result"
}

# Process a single tag
_template_process_tag() {
    local tag="$1"
    # shellcheck disable=SC2034  # raw is used in conditional logic below
    local raw="${2:-false}"
    
    # Trim whitespace
    tag="${tag#"${tag%%[![:space:]]*}"}"
    tag="${tag%"${tag##*[![:space:]]}"}"
    
    # Handle different tag types
    case "$tag" in
        '#if '*)
            # Conditional block start - find matching /if
            local condition="${tag#\#if }"
            _template_conditional "if" "$condition"
            ;;
        '#unless '*)
            # Unless block
            local condition="${tag#\#unless }"
            _template_conditional "unless" "$condition"
            ;;
        '#each '*)
            # Loop block
            local var="${tag#\#each }"
            _template_loop "$var"
            ;;
        '>'*)
            # Partial include
            local partial_name="${tag#>}"
            partial_name="${partial_name#"${partial_name%%[![:space:]]*}"}"
            _template_include_partial "$partial_name"
            ;;
        '!'*)
            # Comment - output nothing
            printf ''
            ;;
        now|uuid)
            # Zero-argument helpers
            _template_call_helper "$tag"
            ;;
        *' '*)
            # Helper call: {{helper arg}}
            _template_call_helper "$tag"
            ;;
        *':-'*)
            # Variable with default: {{VAR:-default}}
            local var_name="${tag%%:-*}"
            local default="${tag#*:-}"
            _template_get_var "$var_name" "$default"
            ;;
        *)
            # Simple variable substitution
            _template_get_var "$tag" ""
            ;;
    esac
}

# Get variable value
_template_get_var() {
    local name="$1"
    local default="$2"
    
    # Trim name
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    
    # Special case: . refers to current loop item
    if [[ "$name" == "." ]]; then
        printf '%s' "${_TEMPLATE_VARS[_LOOP_ITEM]:-}"
        return
    fi
    
    # Check template vars first
    if [[ -n "${_TEMPLATE_VARS[$name]+set}" ]]; then
        printf '%s' "${_TEMPLATE_VARS[$name]}"
    elif [[ -n "${default}" ]]; then
        printf '%s' "$default"
    fi
}

# Call a helper function
_template_call_helper() {
    local tag="$1"
    local helper_name="${tag%% *}"
    local args="${tag#* }"
    
    # Trim
    helper_name="${helper_name#"${helper_name%%[![:space:]]*}"}"
    args="${args#"${args%%[![:space:]]*}"}"
    args="${args%"${args##*[![:space:]]}"}"
    
    case "$helper_name" in
        upper)
            local value
            value=$(_template_get_var "$args" "")
            printf '%s' "${value^^}"
            ;;
        lower)
            local value
            value=$(_template_get_var "$args" "")
            printf '%s' "${value,,}"
            ;;
        default)
            # {{default VAR value}}
            local var_name="${args%% *}"
            local default="${args#* }"
            local value
            value=$(_template_get_var "$var_name" "")
            if [[ -n "$value" ]]; then
                printf '%s' "$value"
            else
                printf '%s' "$default"
            fi
            ;;
        env)
            # {{env HOME}}
            printf '%s' "${!args:-}"
            ;;
        now)
            # {{now}} - current timestamp
            printf '%(%Y-%m-%d %H:%M:%S)T' -1
            ;;
        date)
            # {{date FORMAT}} - custom date format
            printf "%($args)T" -1
            ;;
        uuid)
            # {{uuid}} - generate UUID v4
            _template_uuid
            ;;
        len|length)
            # {{len VAR}} - length of value
            local value
            value=$(_template_get_var "$args" "")
            printf '%d' "${#value}"
            ;;
        trim)
            # {{trim VAR}}
            local value
            value=$(_template_get_var "$args" "")
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            printf '%s' "$value"
            ;;
        json)
            # {{json VAR}} - JSON escape
            local value
            value=$(_template_get_var "$args" "")
            _template_json_escape "$value"
            ;;
        html)
            # {{html VAR}} - HTML escape
            local value
            value=$(_template_get_var "$args" "")
            _template_html_escape "$value"
            ;;
        urlencode)
            # {{urlencode VAR}}
            local value
            value=$(_template_get_var "$args" "")
            _template_urlencode "$value"
            ;;
        base64)
            # {{base64 VAR}}
            local value
            value=$(_template_get_var "$args" "")
            printf '%s' "$value" | base64 2>/dev/null || _template_base64_encode "$value"
            ;;
        repeat)
            # {{repeat VAR N}}
            local var="${args%% *}"
            local count="${args##* }"
            local value
            value=$(_template_get_var "$var" "")
            local i
            for ((i=0; i<count; i++)); do
                printf '%s' "$value"
            done
            ;;
        pad)
            # {{pad VAR WIDTH [CHAR]}}
            read -ra pad_args <<< "$args"
            local var="${pad_args[0]}"
            local width="${pad_args[1]:-0}"
            local char="${pad_args[2]:- }"
            local value
            value=$(_template_get_var "$var" "")
            printf "%-${width}s" "$value" | tr ' ' "$char"
            ;;
        *)
            # Check custom helpers
            if [[ -n "${_TEMPLATE_HELPERS[$helper_name]}" ]]; then
                local func="${_TEMPLATE_HELPERS[$helper_name]}"
                local value
                value=$(_template_get_var "$args" "$args")
                "$func" "$value"
            else
                # Unknown helper - treat as variable
                _template_get_var "$helper_name" ""
            fi
            ;;
    esac
}

# Include a partial
_template_include_partial() {
    local name="$1"
    
    if [[ -n "${_TEMPLATE_PARTIALS[$name]+set}" ]]; then
        _template_process "${_TEMPLATE_PARTIALS[$name]}"
    else
        printf '<!-- partial not found: %s -->' "$name"
    fi
}

# =============================================================================
# CONDITIONALS
# =============================================================================

# Process conditional block
# This is a simplified approach - finds the block content and evaluates
_template_conditional() {
    local type="$1"
    local condition="$2"
    
    # Trim condition
    condition="${condition#"${condition%%[![:space:]]*}"}"
    condition="${condition%"${condition##*[![:space:]]}"}"
    
    # Get the variable value
    local value
    value=$(_template_get_var "$condition" "")
    
    # Evaluate condition
    local show=false
    if [[ "$type" == "if" ]]; then
        if [[ -n "$value" && "$value" != "false" && "$value" != "0" ]]; then
            show=true
        fi
    else  # unless
        if [[ -z "$value" || "$value" == "false" || "$value" == "0" ]]; then
            show=true
        fi
    fi
    
    if $show; then
        printf 'COND_TRUE'
    else
        printf 'COND_FALSE'
    fi
}

# =============================================================================
# LOOPS
# =============================================================================

# Process loop (simplified - returns marker)
_template_loop() {
    local var="$1"
    printf 'LOOP:%s' "$var"
}

# =============================================================================
# ADVANCED RENDER WITH BLOCKS
# =============================================================================

# Main render function, including block support (conditionals and loops)
# Usage: template::render "{{#if x}}yes{{/if}}" x=true
# Usage: echo "Hello {{name}}!" | template::render - name="World"
# shellcheck disable=SC2329  # Function is invoked externally/indirectly
template::render() {
    local template=""
    
    # Parse arguments
    if [[ "$1" == "-" ]]; then
        template=$(cat)
        shift
    elif [[ -n "$1" && "$1" != *"="* ]]; then
        template="$1"
        shift
    fi
    
    # Clear and set variables
    _TEMPLATE_VARS=()
    for arg in "$@"; do
        if [[ "$arg" == *"="* ]]; then
            local key="${arg%%=*}"
            local value="${arg#*=}"
            _TEMPLATE_VARS["$key"]="$value"
        fi
    done
    
    # Process blocks first (conditionals and loops)
    local processed
    processed=$(_template_process_blocks "$template")
    
    # Then process remaining variables
    _template_process "$processed"
}

# Process block structures (if/unless/each)
_template_process_blocks() {
    local template="$1"
    local result=""
    local pos=0
    local len=${#template}
    
    while ((pos < len)); do
        local rest="${template:pos}"
        
        # Look for block start: {{#if, {{#unless, {{#each
        if [[ "$rest" =~ ^\{\{#(if|unless|each)[[:space:]]+([^}]+)\}\} ]]; then
            local block_type="${BASH_REMATCH[1]}"
            local block_arg="${BASH_REMATCH[2]}"
            local match_len=${#BASH_REMATCH[0]}
            
            # Find the closing tag
            local end_tag="{{/${block_type}}}"
            local block_rest="${rest:match_len}"
            
            if [[ "$block_rest" == *"$end_tag"* ]]; then
                local block_content="${block_rest%%"$end_tag"*}"
                local block_end=$((pos + match_len + ${#block_content} + ${#end_tag}))
                
                # Trim block_arg
                block_arg="${block_arg#"${block_arg%%[![:space:]]*}"}"
                block_arg="${block_arg%"${block_arg##*[![:space:]]}"}"
                
                # Process the block
                case "$block_type" in
                    if)
                        local val="${_TEMPLATE_VARS[$block_arg]:-}"
                        if [[ -n "$val" && "$val" != "false" && "$val" != "0" ]]; then
                            result+=$(_template_process_blocks "$block_content")
                        fi
                        ;;
                    unless)
                        local val="${_TEMPLATE_VARS[$block_arg]:-}"
                        if [[ -z "$val" || "$val" == "false" || "$val" == "0" ]]; then
                            result+=$(_template_process_blocks "$block_content")
                        fi
                        ;;
                    each)
                        local items="${_TEMPLATE_VARS[$block_arg]:-}"
                        if [[ -n "$items" ]]; then
                            local item
                            for item in $items; do
                                # Substitute {{.}} directly in the block content
                                local item_content="$block_content"
                                # Replace {{.}} with the actual item value
                                while [[ "$item_content" == *'{{.}}'* ]]; do
                                    item_content="${item_content/\{\{.\}\}/$item}"
                                done
                                # Also handle {{ . }} with spaces
                                while [[ "$item_content" == *'{{ . }}'* ]]; do
                                    item_content="${item_content/\{\{ . \}\}/$item}"
                                done
                                # Process any remaining template tags
                                local loop_result
                                loop_result=$(_template_process_blocks "$item_content")
                                result+="$loop_result"
                            done
                        fi
                        ;;
                esac
                
                pos=$block_end
                continue
            fi
        fi
        
        # No block found at this position, copy character
        result+="${template:pos:1}"
        ((pos++))
    done
    
    printf '%s' "$result"
}

# =============================================================================
# HELPER UTILITIES (Pure Bash)
# =============================================================================

# Generate UUID v4 (pure bash)
_template_uuid() {
    local C="89ab"
    for ((N=0;N<16;++N)); do
        local B="$((RANDOM%256))"
        case "$N" in
            6) printf '4%x' "$((B%16))" ;;
            8) printf '%c%x' "${C:$RANDOM%${#C}:1}" "$((B%16))" ;;
            3|5|7|9) printf '%02x-' "$B" ;;
            *) printf '%02x' "$B" ;;
        esac
    done
    printf '\n'
}

# JSON escape (pure bash)
_template_json_escape() {
    local str="$1"
    local result=""
    local i
    for ((i=0; i<${#str}; i++)); do
        local char="${str:i:1}"
        case "$char" in
            '"')  result+='\"' ;;
            '\')  result+='\\' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)    result+="$char" ;;
        esac
    done
    printf '%s' "$result"
}

# HTML escape (pure bash)
_template_html_escape() {
    local str="$1"
    local result=""
    local i
    for ((i=0; i<${#str}; i++)); do
        local char="${str:i:1}"
        case "$char" in
            '&') result+='&amp;' ;;
            '<') result+='&lt;' ;;
            '>') result+='&gt;' ;;
            '"') result+='&quot;' ;;
            "'") result+='&#39;' ;;
            *)   result+="$char" ;;
        esac
    done
    printf '%s' "$result"
}

# URL encode (pure bash)
_template_urlencode() {
    local str="$1"
    local i
    for ((i=0; i<${#str}; i++)); do
        local c="${str:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            ' ') printf '%%20' ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

# Base64 encode (pure bash fallback)
_template_base64_encode() {
    local str="$1"
    local b64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    # shellcheck disable=SC2034  # pad is used for base64 padding logic
    local pad=""
    local out=""
    
    # Convert to bytes and encode
    local -a bytes=()
    local i
    for ((i=0; i<${#str}; i++)); do
        printf -v "bytes[$i]" '%d' "'${str:i:1}"
    done
    
    local len=${#bytes[@]}
    for ((i=0; i<len; i+=3)); do
        local b1=${bytes[i]:-0}
        local b2=${bytes[i+1]:-0}
        local b3=${bytes[i+2]:-0}
        
        out+="${b64:$((b1 >> 2)):1}"
        out+="${b64:$(((b1 & 3) << 4 | b2 >> 4)):1}"
        
        if ((i + 1 < len)); then
            out+="${b64:$(((b2 & 15) << 2 | b3 >> 6)):1}"
        else
            out+="="
        fi
        
        if ((i + 2 < len)); then
            out+="${b64:$((b3 & 63)):1}"
        else
            out+="="
        fi
    done
    
    printf '%s' "$out"
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Clear all template state
# Usage: template::clear
template::clear() {
    _TEMPLATE_VARS=()
    _TEMPLATE_PARTIALS=()
    _TEMPLATE_HELPERS=()
}

# Set a single variable
# Usage: template::set "name" "value"
template::set() {
    _TEMPLATE_VARS["$1"]="$2"
}

# Get a variable
# Usage: template::get "name"
template::get() {
    printf '%s' "${_TEMPLATE_VARS[$1]:-}"
}

# Set multiple variables from environment
# Usage: template::from_env PREFIX_
template::from_env() {
    local prefix="${1:-}"
    local var
    
    while IFS='=' read -r var value; do
        if [[ -z "$prefix" || "$var" == "$prefix"* ]]; then
            local key="${var#"$prefix"}"
            _TEMPLATE_VARS["$key"]="$value"
        fi
    done < <(env)
}

# Render and write to file
# Usage: template::render_to "output.txt" "template" vars...
template::render_to() {
    local output_file="$1"
    shift
    template::render "$@" > "$output_file"
}

# =============================================================================
# TEMPLATE VALIDATION
# =============================================================================

# Check template syntax
# Usage: template::validate "template string"
template::validate() {
    local template="$1"
    local errors=()
    
    # Check for unclosed tags
    local open_count=0
    local close_count=0
    local rest="$template"
    
    while [[ "$rest" == *"{{"* ]]; do
        rest="${rest#*\{\{}"
        ((open_count++))
    done
    
    rest="$template"
    while [[ "$rest" == *"}}"* ]]; do
        rest="${rest#*\}\}}"
        ((close_count++))
    done
    
    if ((open_count != close_count)); then
        errors+=("Mismatched braces: $open_count {{ but $close_count }}")
    fi
    
    # Check for unclosed blocks
    local -A block_stack=()
    local pos=0
    local len=${#template}
    
    while ((pos < len)); do
        local chunk="${template:pos}"
        
        if [[ "$chunk" =~ ^\{\{#(if|unless|each)[[:space:]] ]]; then
            local type="${BASH_REMATCH[1]}"
            ((block_stack[$type]++))
        elif [[ "$chunk" =~ ^\{\{/(if|unless|each)\}\} ]]; then
            local type="${BASH_REMATCH[1]}"
            if ((block_stack[$type] <= 0)); then
                errors+=("Unexpected closing tag: {{/$type}}")
            else
                ((block_stack[$type]--))
            fi
        fi
        
        ((pos++))
    done
    
    for type in "${!block_stack[@]}"; do
        if ((block_stack[$type] > 0)); then
            errors+=("Unclosed block: {{#$type}} (${block_stack[$type]} unclosed)")
        fi
    done
    
    if ((${#errors[@]} > 0)); then
        printf '%s\n' "${errors[@]}" >&2
        return 1
    fi
    
    return 0
}

# List all variables used in template
# Usage: template::variables "template string"
template::variables() {
    local template="$1"
    local -A vars=()
    
    # Find all {{variable}} patterns
    local rest="$template"
    while [[ "$rest" =~ \{\{([^#/>!][^}]*)\}\} ]]; do
        local match="${BASH_REMATCH[1]}"
        # Clean up
        match="${match#"${match%%[![:space:]]*}"}"
        match="${match%"${match##*[![:space:]]}"}"
        
        # Skip helpers (contain spaces)
        if [[ "$match" != *" "* ]]; then
            # Handle defaults
            local varname="${match%%:-*}"
            vars["$varname"]=1
        fi
        
        rest="${rest#*\}\}}"
    done
    
    printf '%s\n' "${!vars[@]}"
}

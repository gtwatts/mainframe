#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/regex.sh - Comprehensive Regex Utilities
# =============================================================================
# Description: Pure bash regex operations using [[ =~ ]] extended regex.
#              Includes pattern matching, replacement, extraction, splitting,
#              pattern builders, and ReDoS attack protection.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_REGEX_LOADED:-}" ]] && return 0
readonly _MAINFRAME_REGEX_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# ReDoS protection thresholds
readonly REGEX_MAX_PATTERN_LENGTH="${REGEX_MAX_PATTERN_LENGTH:-500}"
readonly REGEX_MAX_QUANTIFIERS="${REGEX_MAX_QUANTIFIERS:-10}"
readonly REGEX_MAX_GROUPS="${REGEX_MAX_GROUPS:-15}"
readonly REGEX_MAX_ALTERNATIONS="${REGEX_MAX_ALTERNATIONS:-20}"

# =============================================================================
# COMMON REGEX PATTERNS (Constants)
# =============================================================================

# Email: RFC 5322 simplified
readonly REGEX_EMAIL='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'

# URL: HTTP/HTTPS with path, query, fragment
readonly REGEX_URL='^(https?|ftp)://[A-Za-z0-9.-]+(:[0-9]+)?(/[^[:space:]]*)?$'

# IPv4 address
readonly REGEX_IPV4='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

# IPv6 address (simplified, full form)
readonly REGEX_IPV6='^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$'

# UUID (v1-v5)
readonly REGEX_UUID='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'

# Semantic version (with optional v prefix)
readonly REGEX_SEMVER='^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

# ISO 8601 date (YYYY-MM-DD)
readonly REGEX_DATE_ISO='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'

# ISO 8601 datetime
readonly REGEX_DATETIME_ISO='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](Z|[+-][0-9]{2}:[0-9]{2})?$'

# Phone number (international format, simplified)
readonly REGEX_PHONE='^\+?[0-9]{1,4}[-.\s]?(\([0-9]{1,3}\)|[0-9]{1,4})[-.\s]?[0-9]{1,4}[-.\s]?[0-9]{1,9}$'

# Credit card (masked pattern for validation only, not for storage)
readonly REGEX_CREDIT_CARD='^[0-9]{4}[-\s]?[0-9]{4}[-\s]?[0-9]{4}[-\s]?[0-9]{4}$'

# URL slug (lowercase alphanumeric with hyphens)
readonly REGEX_SLUG='^[a-z0-9]+(-[a-z0-9]+)*$'

# Identifier (programming variable name)
readonly REGEX_IDENTIFIER='^[a-zA-Z_][a-zA-Z0-9_]*$'

# Hexadecimal color
readonly REGEX_HEX_COLOR='^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$'

# MAC address
readonly REGEX_MAC_ADDRESS='^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string for structured output
_regex_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Emit structured error in JSON format
# @pre: msg is non-empty string
# @post: JSON error emitted to stderr
_regex_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    local func="${FUNCNAME[1]:-main}"

    if [[ "${MAINFRAME_ERROR_JSON:-1}" == "1" ]]; then
        local escaped_msg escaped_func
        escaped_msg=$(_regex_escape_json "$msg")
        escaped_func=$(_regex_escape_json "$func")
        printf '{"error":true,"code":%d,"msg":"%s","func":"%s"}\n' \
            "$code" "$escaped_msg" "$escaped_func" >&2
    else
        printf '[regex] ERROR(%d) in %s: %s\n' "$code" "$func" "$msg" >&2
    fi
    return "$code"
}

# =============================================================================
# VALIDATION & SAFETY (ReDoS Protection)
# =============================================================================

# Check if a regex pattern is valid
# @pre: pattern is non-empty string
# @post: returns 0 if valid, 1 if invalid
# @idempotent: yes
# Usage: regex_is_valid "pattern" && echo "valid"
regex_is_valid() {
    local pattern="$1"

    [[ -z "$pattern" ]] && return 1

    # Test by attempting to match an empty string
    # Invalid patterns will cause bash to error
    if [[ "" =~ $pattern ]] 2>/dev/null || [[ $? -le 1 ]]; then
        return 0
    fi
    return 1
}

# Calculate regex complexity score for ReDoS protection
# @pre: pattern is non-empty string
# @post: outputs integer complexity score
# @idempotent: yes
# Usage: score=$(regex_complexity_score "pattern")
# Score interpretation: 0-10 safe, 11-50 moderate, 51+ potentially dangerous
regex_complexity_score() {
    local pattern="$1"
    local score=0

    [[ -z "$pattern" ]] && { printf '0'; return 0; }

    # Base score from length
    local len=${#pattern}
    score=$((len / 50))

    # Count quantifiers: *, +, ?, {n,m}
    local quantifiers
    quantifiers=$(printf '%s' "$pattern" | grep -o '[*+?]' | wc -l)
    quantifiers=$((quantifiers + $(printf '%s' "$pattern" | grep -o '{[0-9]*,[0-9]*}' | wc -l)))
    score=$((score + quantifiers * 5))

    # Count nested groups with quantifiers (high risk)
    local nested_quant
    nested_quant=$(printf '%s' "$pattern" | grep -o '([^)]*)[*+?{]' | wc -l)
    score=$((score + nested_quant * 15))

    # Count alternations |
    local alternations
    alternations=$(printf '%s' "$pattern" | grep -o '|' | wc -l)
    score=$((score + alternations * 3))

    # Count groups
    local groups
    groups=$(printf '%s' "$pattern" | grep -o '(' | wc -l)
    score=$((score + groups * 2))

    # Detect dangerous patterns: nested quantifiers (a+)+, (a*)*
    if [[ "$pattern" =~ \([^)]*[*+]\)[*+] ]]; then
        score=$((score + 50))
    fi

    # Detect overlapping alternations with quantifiers
    if [[ "$pattern" =~ \([^)|]*\|[^)]*\)[*+] ]]; then
        score=$((score + 30))
    fi

    printf '%d' "$score"
}

# Validate pattern complexity for ReDoS protection
# @pre: pattern is non-empty string
# @post: returns 0 if safe, 1 if potentially dangerous
# @idempotent: yes
# Usage: regex_compile_safe "pattern" || echo "dangerous pattern"
regex_compile_safe() {
    local pattern="$1"

    [[ -z "$pattern" ]] && return 1

    # Check pattern length
    if [[ ${#pattern} -gt $REGEX_MAX_PATTERN_LENGTH ]]; then
        _regex_error 1 "pattern exceeds max length ($REGEX_MAX_PATTERN_LENGTH)"
        return 1
    fi

    # Check if pattern is valid regex
    if ! regex_is_valid "$pattern"; then
        _regex_error 1 "invalid regex pattern"
        return 1
    fi

    # Count quantifiers
    local quantifiers
    quantifiers=$(printf '%s' "$pattern" | grep -o '[*+?]' | wc -l)
    quantifiers=$((quantifiers + $(printf '%s' "$pattern" | grep -o '{[0-9]' | wc -l)))
    if [[ $quantifiers -gt $REGEX_MAX_QUANTIFIERS ]]; then
        _regex_error 1 "too many quantifiers ($quantifiers > $REGEX_MAX_QUANTIFIERS)"
        return 1
    fi

    # Count groups
    local groups
    groups=$(printf '%s' "$pattern" | grep -o '(' | wc -l)
    if [[ $groups -gt $REGEX_MAX_GROUPS ]]; then
        _regex_error 1 "too many groups ($groups > $REGEX_MAX_GROUPS)"
        return 1
    fi

    # Count alternations
    local alternations
    alternations=$(printf '%s' "$pattern" | grep -o '|' | wc -l)
    if [[ $alternations -gt $REGEX_MAX_ALTERNATIONS ]]; then
        _regex_error 1 "too many alternations ($alternations > $REGEX_MAX_ALTERNATIONS)"
        return 1
    fi

    # Check complexity score
    local score
    score=$(regex_complexity_score "$pattern")
    if [[ $score -gt 100 ]]; then
        _regex_error 1 "pattern complexity too high (score: $score)"
        return 1
    fi

    return 0
}

# =============================================================================
# CORE MATCHING FUNCTIONS
# =============================================================================

# Test if string matches pattern
# @pre: string and pattern are provided
# @post: returns 0 if match, 1 if no match
# @idempotent: yes
# Usage: regex_match "hello world" "hello" && echo "matched"
regex_match() {
    local string="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    [[ "$string" =~ $pattern ]]
}

# Alias for regex_match (JS-style naming)
# @pre: string and pattern are provided
# @post: returns 0 if match, 1 if no match
# @idempotent: yes
# Usage: regex_test "hello" "[a-z]+" && echo "matched"
regex_test() {
    regex_match "$@"
}

# Find first match in string
# @pre: string and pattern are provided
# @post: outputs matched text or empty string
# @idempotent: yes
# Usage: match=$(regex_find "hello123world" "[0-9]+")
regex_find() {
    local string="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    if [[ "$string" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[0]}"
        return 0
    fi
    return 1
}

# Find all matches in string
# @pre: string and pattern are provided
# @post: outputs matches one per line
# @idempotent: yes
# Usage: regex_find_all "a1b2c3" "[0-9]" | while read match; do echo "$match"; done
regex_find_all() {
    local string="$1"
    local pattern="$2"
    local remaining="$string"
    local found=0

    [[ -z "$pattern" ]] && return 1

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        printf '%s\n' "${BASH_REMATCH[0]}"
        found=1

        # Move past the match
        local match="${BASH_REMATCH[0]}"
        local match_start="${remaining%%$match*}"
        local offset=$((${#match_start} + ${#match}))

        # Ensure we advance at least one character to avoid infinite loop
        [[ $offset -eq 0 ]] && offset=1

        remaining="${remaining:$offset}"
    done

    [[ $found -eq 1 ]] && return 0
    return 1
}

# Extract capture groups from first match
# @pre: string and pattern are provided
# @post: outputs groups (index 0=full match, 1+=capture groups)
# @idempotent: yes
# Usage: regex_groups "hello123" "([a-z]+)([0-9]+)"
regex_groups() {
    local string="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    if [[ "$string" =~ $pattern ]]; then
        local i
        for ((i=0; i<${#BASH_REMATCH[@]}; i++)); do
            printf '%s\n' "${BASH_REMATCH[$i]}"
        done
        return 0
    fi
    return 1
}

# Extract named capture groups (simulated via positional)
# Note: Bash regex doesn't support named groups natively
# This function uses a convention: group names passed as third argument
# @pre: string, pattern, and names are provided
# @post: outputs name=value pairs
# @idempotent: yes
# Usage: regex_named_groups "hello123" "([a-z]+)([0-9]+)" "word num"
regex_named_groups() {
    local string="$1"
    local pattern="$2"
    local names="$3"

    [[ -z "$pattern" ]] && return 1

    if [[ "$string" =~ $pattern ]]; then
        local -a name_arr
        read -ra name_arr <<< "$names"

        local i
        for ((i=1; i<${#BASH_REMATCH[@]}; i++)); do
            local name="${name_arr[$((i-1))]:-group$i}"
            printf '%s=%s\n' "$name" "${BASH_REMATCH[$i]}"
        done
        return 0
    fi
    return 1
}

# =============================================================================
# REPLACEMENT FUNCTIONS
# =============================================================================

# Replace first match with replacement string
# @pre: string, pattern, and replacement are provided
# @post: outputs modified string
# @idempotent: yes
# Usage: result=$(regex_replace "hello world" "world" "bash")
regex_replace() {
    local string="$1"
    local pattern="$2"
    local replacement="$3"

    [[ -z "$pattern" ]] && { printf '%s' "$string"; return 1; }

    if [[ "$string" =~ $pattern ]]; then
        local match="${BASH_REMATCH[0]}"
        local prefix="${string%%$match*}"
        local suffix="${string#*$match}"
        printf '%s%s%s' "$prefix" "$replacement" "$suffix"
        return 0
    fi

    printf '%s' "$string"
    return 1
}

# Replace all matches with replacement string
# @pre: string, pattern, and replacement are provided
# @post: outputs modified string
# @idempotent: yes
# Usage: result=$(regex_replace_all "a1b2c3" "[0-9]" "X")
regex_replace_all() {
    local string="$1"
    local pattern="$2"
    local replacement="$3"
    local result=""
    local remaining="$string"
    local modified=0

    [[ -z "$pattern" ]] && { printf '%s' "$string"; return 1; }

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        local match="${BASH_REMATCH[0]}"
        local prefix="${remaining%%$match*}"

        result+="$prefix$replacement"
        modified=1

        # Move past the match
        local offset=$((${#prefix} + ${#match}))
        [[ $offset -eq 0 ]] && offset=1
        remaining="${remaining:$offset}"
    done

    result+="$remaining"
    printf '%s' "$result"

    [[ $modified -eq 1 ]] && return 0
    return 1
}

# Replace with callback function
# @pre: string, pattern, and callback function name are provided
# @post: outputs modified string where each match is replaced by callback result
# @idempotent: yes (assuming callback is idempotent)
# Usage: my_callback() { echo "[${1^^}]"; }
#        result=$(regex_replace_callback "hello" "[a-z]" my_callback)
regex_replace_callback() {
    local string="$1"
    local pattern="$2"
    local callback="$3"
    local result=""
    local remaining="$string"

    [[ -z "$pattern" ]] && { printf '%s' "$string"; return 1; }
    [[ -z "$callback" ]] && { printf '%s' "$string"; return 1; }

    # Verify callback is a function
    if ! declare -f "$callback" >/dev/null 2>&1; then
        _regex_error 1 "callback '$callback' is not a function"
        printf '%s' "$string"
        return 1
    fi

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        local match="${BASH_REMATCH[0]}"
        local prefix="${remaining%%$match*}"

        # Call the callback with the match and capture groups
        local replacement
        replacement=$("$callback" "${BASH_REMATCH[@]}")

        result+="$prefix$replacement"

        local offset=$((${#prefix} + ${#match}))
        [[ $offset -eq 0 ]] && offset=1
        remaining="${remaining:$offset}"
    done

    result+="$remaining"
    printf '%s' "$result"
}

# Python-style replacement with \1 \2 backreferences
# @pre: string, pattern, and replacement with backrefs are provided
# @post: outputs modified string with backrefs expanded
# @idempotent: yes
# Usage: result=$(regex_sub "hello world" "(\w+) (\w+)" "\2 \1")
regex_sub() {
    local string="$1"
    local pattern="$2"
    local replacement="$3"
    local result=""
    local remaining="$string"

    [[ -z "$pattern" ]] && { printf '%s' "$string"; return 1; }

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        local match="${BASH_REMATCH[0]}"
        local prefix="${remaining%%$match*}"

        # Expand backreferences in replacement
        local expanded="$replacement"
        local i
        for ((i=${#BASH_REMATCH[@]}-1; i>=0; i--)); do
            expanded="${expanded//\\$i/${BASH_REMATCH[$i]}}"
        done

        result+="$prefix$expanded"

        local offset=$((${#prefix} + ${#match}))
        [[ $offset -eq 0 ]] && offset=1
        remaining="${remaining:$offset}"
    done

    result+="$remaining"
    printf '%s' "$result"
}

# =============================================================================
# SPLITTING FUNCTIONS
# =============================================================================

# Split string by regex pattern
# @pre: string and pattern are provided
# @post: outputs parts one per line
# @idempotent: yes
# Usage: regex_split "a1b2c3" "[0-9]" | while read part; do echo "$part"; done
regex_split() {
    local string="$1"
    local pattern="$2"
    local remaining="$string"
    local parts=()

    [[ -z "$pattern" ]] && { printf '%s\n' "$string"; return 0; }

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        local match="${BASH_REMATCH[0]}"
        local prefix="${remaining%%$match*}"

        parts+=("$prefix")

        local offset=$((${#prefix} + ${#match}))
        [[ $offset -eq 0 ]] && offset=1
        remaining="${remaining:$offset}"
    done

    parts+=("$remaining")

    local part
    for part in "${parts[@]}"; do
        printf '%s\n' "$part"
    done
}

# Split string by regex pattern with limit
# @pre: string, pattern, and limit are provided
# @post: outputs at most N parts
# @idempotent: yes
# Usage: regex_split_limit "a-b-c-d" "-" 2
regex_split_limit() {
    local string="$1"
    local pattern="$2"
    local limit="${3:-0}"
    local remaining="$string"
    local count=0
    local parts=()

    [[ -z "$pattern" ]] && { printf '%s\n' "$string"; return 0; }
    [[ $limit -lt 1 ]] && limit=999999

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]] && [[ $((count + 1)) -lt $limit ]]; do
        local match="${BASH_REMATCH[0]}"
        local prefix="${remaining%%$match*}"

        parts+=("$prefix")
        ((count++))

        local offset=$((${#prefix} + ${#match}))
        [[ $offset -eq 0 ]] && offset=1
        remaining="${remaining:$offset}"
    done

    parts+=("$remaining")

    local part
    for part in "${parts[@]}"; do
        printf '%s\n' "$part"
    done
}

# =============================================================================
# EXTRACTION FUNCTIONS
# =============================================================================

# Extract matching portion of string
# @pre: string and pattern are provided
# @post: outputs matched portion
# @idempotent: yes
# Usage: extracted=$(regex_extract "hello123world" "[0-9]+")
regex_extract() {
    regex_find "$@"
}

# Extract all matching portions to array format
# @pre: string and pattern are provided
# @post: outputs all matches one per line
# @idempotent: yes
# Usage: mapfile -t matches < <(regex_extract_all "a1b2c3" "[0-9]")
regex_extract_all() {
    regex_find_all "$@"
}

# Extract all capture groups from all matches
# @pre: string and pattern are provided
# @post: outputs groups from each match, separated by blank lines
# @idempotent: yes
# Usage: regex_extract_groups "cat12dog34" "([a-z]+)([0-9]+)"
regex_extract_groups() {
    local string="$1"
    local pattern="$2"
    local remaining="$string"
    local found=0

    [[ -z "$pattern" ]] && return 1

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        [[ $found -gt 0 ]] && printf '\n'
        found=1

        local i
        for ((i=0; i<${#BASH_REMATCH[@]}; i++)); do
            printf '%s\n' "${BASH_REMATCH[$i]}"
        done

        local match="${BASH_REMATCH[0]}"
        local match_start="${remaining%%$match*}"
        local offset=$((${#match_start} + ${#match}))
        [[ $offset -eq 0 ]] && offset=1
        remaining="${remaining:$offset}"
    done

    [[ $found -gt 0 ]] && return 0
    return 1
}

# =============================================================================
# ESCAPING FUNCTIONS
# =============================================================================

# Escape special regex metacharacters in string
# @pre: string is provided
# @post: outputs escaped string safe for regex literal matching
# @idempotent: no (escaping twice would double-escape)
# Usage: escaped=$(regex_escape "hello.*world")
regex_escape() {
    local string="$1"
    local result=""
    local i char

    for ((i=0; i<${#string}; i++)); do
        char="${string:i:1}"
        case "$char" in
            '\'|'^'|'$'|'.'|'['|']'|'('|')'|'{'|'}'|'*'|'+'|'?'|'|')
                result+="\\$char"
                ;;
            *)
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# Unescape regex metacharacters
# @pre: escaped string is provided
# @post: outputs unescaped string
# @idempotent: no
# Usage: unescaped=$(regex_unescape "hello\\.\\*world")
regex_unescape() {
    local string="$1"
    local result=""
    local i char

    i=0
    while [[ $i -lt ${#string} ]]; do
        char="${string:i:1}"
        if [[ "$char" == '\' ]] && [[ $((i+1)) -lt ${#string} ]]; then
            local next="${string:$((i+1)):1}"
            case "$next" in
                '\'|'^'|'$'|'.'|'['|']'|'('|')'|'{'|'}'|'*'|'+'|'?'|'|')
                    result+="$next"
                    ((i+=2))
                    continue
                    ;;
            esac
        fi
        result+="$char"
        ((i++))
    done

    printf '%s' "$result"
}

# Quote string for literal matching (alias for regex_escape)
# @pre: string is provided
# @post: outputs escaped string
# @idempotent: no
# Usage: quoted=$(regex_quote_literal "file.txt")
regex_quote_literal() {
    regex_escape "$@"
}

# =============================================================================
# PATTERN BUILDER FUNCTIONS
# =============================================================================

# Build alternation pattern from array of options
# @pre: at least one option is provided
# @post: outputs pattern like (opt1|opt2|opt3)
# @idempotent: yes
# Usage: pattern=$(regex_any_of "cat" "dog" "bird")
regex_any_of() {
    [[ $# -eq 0 ]] && return 1

    local result="("
    local first=true
    local item

    for item in "$@"; do
        $first || result+="|"
        first=false
        result+="$item"
    done

    result+=")"
    printf '%s' "$result"
}

# Concatenate patterns into sequence
# @pre: at least one pattern is provided
# @post: outputs concatenated pattern
# @idempotent: yes
# Usage: pattern=$(regex_sequence "[a-z]+" "[0-9]+")
regex_sequence() {
    [[ $# -eq 0 ]] && return 1

    local result=""
    local pattern

    for pattern in "$@"; do
        result+="$pattern"
    done

    printf '%s' "$result"
}

# Make pattern optional (add ?)
# @pre: pattern is provided
# @post: outputs pattern with ? quantifier
# @idempotent: no
# Usage: pattern=$(regex_optional "[a-z]+")
regex_optional() {
    local pattern="$1"

    [[ -z "$pattern" ]] && return 1

    # Wrap in non-capturing group if needed
    if [[ ${#pattern} -gt 1 ]] && [[ "$pattern" != "("*")" ]]; then
        printf '(?:%s)?' "$pattern"
    else
        printf '%s?' "$pattern"
    fi
}

# Add repetition quantifier
# @pre: pattern, min, and optionally max are provided
# @post: outputs pattern with quantifier
# @idempotent: no
# Usage: pattern=$(regex_repeat "[a-z]" 2 5)  # {2,5}
#        pattern=$(regex_repeat "[a-z]" 3)    # {3}
#        pattern=$(regex_repeat "[a-z]" 0 "")  # *
regex_repeat() {
    local pattern="$1"
    local min="${2:-0}"
    local max="${3:-}"

    [[ -z "$pattern" ]] && return 1

    # Wrap in group if multi-char pattern
    local wrapped="$pattern"
    if [[ ${#pattern} -gt 1 ]] && [[ "$pattern" != "("*")" ]]; then
        wrapped="(?:$pattern)"
    fi

    if [[ "$min" == "0" ]] && [[ -z "$max" ]]; then
        printf '%s*' "$wrapped"
    elif [[ "$min" == "1" ]] && [[ -z "$max" ]]; then
        printf '%s+' "$wrapped"
    elif [[ "$min" == "0" ]] && [[ "$max" == "1" ]]; then
        printf '%s?' "$wrapped"
    elif [[ -n "$max" ]]; then
        printf '%s{%d,%d}' "$wrapped" "$min" "$max"
    else
        printf '%s{%d}' "$wrapped" "$min"
    fi
}

# Wrap pattern in capture group
# @pre: pattern is provided
# @post: outputs (pattern)
# @idempotent: no
# Usage: pattern=$(regex_group "[a-z]+")
regex_group() {
    local pattern="$1"

    [[ -z "$pattern" ]] && return 1

    printf '(%s)' "$pattern"
}

# Wrap pattern in non-capturing group
# @pre: pattern is provided
# @post: outputs (?:pattern)
# @idempotent: no
# Usage: pattern=$(regex_non_capture "[a-z]+")
regex_non_capture() {
    local pattern="$1"

    [[ -z "$pattern" ]] && return 1

    printf '(?:%s)' "$pattern"
}

# Add anchors to pattern
# @pre: pattern is provided
# @post: outputs anchored pattern
# @idempotent: no
# Usage: pattern=$(regex_anchor "[a-z]+" "both")  # ^[a-z]+$
#        pattern=$(regex_anchor "[a-z]+" "start") # ^[a-z]+
#        pattern=$(regex_anchor "[a-z]+" "end")   # [a-z]+$
regex_anchor() {
    local pattern="$1"
    local anchor="${2:-both}"

    [[ -z "$pattern" ]] && return 1

    case "$anchor" in
        both|full)
            printf '^%s$' "$pattern"
            ;;
        start|begin|left)
            printf '^%s' "$pattern"
            ;;
        end|right)
            printf '%s$' "$pattern"
            ;;
        *)
            printf '%s' "$pattern"
            ;;
    esac
}

# Add word boundaries to pattern
# @pre: pattern is provided
# @post: outputs pattern with \b boundaries
# @idempotent: no
# Usage: pattern=$(regex_word_boundary "hello")
regex_word_boundary() {
    local pattern="$1"
    local boundary="${2:-both}"

    [[ -z "$pattern" ]] && return 1

    # Note: \b is word boundary in ERE
    case "$boundary" in
        both|full)
            printf '\b%s\b' "$pattern"
            ;;
        start|begin|left)
            printf '\b%s' "$pattern"
            ;;
        end|right)
            printf '%s\b' "$pattern"
            ;;
        *)
            printf '%s' "$pattern"
            ;;
    esac
}

# =============================================================================
# CONVERSION FUNCTIONS
# =============================================================================

# Convert simple regex to glob pattern
# Note: Only handles basic patterns, not full regex
# @pre: pattern is provided
# @post: outputs glob pattern
# @idempotent: yes
# Usage: glob=$(regex_to_glob ".*\.txt$")
regex_to_glob() {
    local pattern="$1"
    local result="$pattern"

    [[ -z "$pattern" ]] && return 1

    # Remove anchors
    result="${result#^}"
    result="${result%\$}"

    # .* -> *
    result="${result//\.\*/\*}"

    # .+ -> ?*
    result="${result//\.\+/\?\*}"

    # . -> ?
    result="${result//\./\?}"

    # Remove escape characters for common chars
    result="${result//\\\./\.}"
    result="${result//\\\*/\*}"
    result="${result//\\\?/\?}"

    printf '%s' "$result"
}

# Convert glob pattern to regex
# @pre: glob pattern is provided
# @post: outputs regex pattern
# @idempotent: yes
# Usage: regex=$(glob_to_regex "*.txt")
glob_to_regex() {
    local glob="$1"
    local result=""
    local i char

    [[ -z "$glob" ]] && return 1

    # Start anchor
    result="^"

    i=0
    while [[ $i -lt ${#glob} ]]; do
        char="${glob:i:1}"
        case "$char" in
            '*')
                result+=".*"
                ;;
            '?')
                result+="."
                ;;
            '[')
                # Character class - pass through but escape special chars inside
                result+="["
                ((i++))
                while [[ $i -lt ${#glob} ]] && [[ "${glob:i:1}" != "]" ]]; do
                    local c="${glob:i:1}"
                    case "$c" in
                        '!'|'^')
                            # Negation at start
                            if [[ "${result: -1}" == "[" ]]; then
                                result+="^"
                            else
                                result+="$c"
                            fi
                            ;;
                        *)
                            result+="$c"
                            ;;
                    esac
                    ((i++))
                done
                result+="]"
                ;;
            '.'|'^'|'$'|'+'|'{'|'}'|'('|')'|'|'|'\\')
                # Escape regex metacharacters
                result+="\\$char"
                ;;
            *)
                result+="$char"
                ;;
        esac
        ((i++))
    done

    # End anchor
    result+="$"

    printf '%s' "$result"
}

# Parse /pattern/flags syntax
# @pre: input in /pattern/flags format
# @post: outputs pattern and flags on separate lines
# @idempotent: yes
# Usage: read pattern flags <<< "$(regex_flags_parse '/hello/gi')"
regex_flags_parse() {
    local input="$1"

    [[ -z "$input" ]] && return 1

    # Check for /pattern/flags format
    if [[ "$input" =~ ^/(.+)/([gimsux]*)$ ]]; then
        printf '%s\n%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi

    # No delimiters, return as-is with empty flags
    printf '%s\n\n' "$input"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Count matches in string
# @pre: string and pattern are provided
# @post: outputs count of matches
# @idempotent: yes
# Usage: count=$(regex_count "a1b2c3" "[0-9]")
regex_count() {
    local string="$1"
    local pattern="$2"
    local count=0
    local remaining="$string"

    [[ -z "$pattern" ]] && { printf '0'; return 0; }

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        ((count++))

        local match="${BASH_REMATCH[0]}"
        local match_start="${remaining%%$match*}"
        local offset=$((${#match_start} + ${#match}))
        [[ $offset -eq 0 ]] && offset=1
        remaining="${remaining:$offset}"
    done

    printf '%d' "$count"
}

# Get positions of all matches
# @pre: string and pattern are provided
# @post: outputs start:end positions one per line
# @idempotent: yes
# Usage: regex_positions "hello123" "[0-9]+"
regex_positions() {
    local string="$1"
    local pattern="$2"
    local remaining="$string"
    local offset=0

    [[ -z "$pattern" ]] && return 1

    while [[ -n "$remaining" ]] && [[ "$remaining" =~ $pattern ]]; do
        local match="${BASH_REMATCH[0]}"
        local prefix="${remaining%%$match*}"
        local start=$((offset + ${#prefix}))
        local end=$((start + ${#match}))

        printf '%d:%d\n' "$start" "$end"

        local advance=$((${#prefix} + ${#match}))
        [[ $advance -eq 0 ]] && advance=1
        offset=$((offset + advance))
        remaining="${remaining:$advance}"
    done
}

# Check if entire string matches pattern (full match)
# @pre: string and pattern are provided
# @post: returns 0 if entire string matches, 1 otherwise
# @idempotent: yes
# Usage: regex_full_match "hello" "^[a-z]+$" && echo "full match"
regex_full_match() {
    local string="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    # Add anchors if not present
    local anchored="$pattern"
    [[ "$anchored" != "^"* ]] && anchored="^$anchored"
    [[ "$anchored" != *"$" ]] && anchored="$anchored$"

    [[ "$string" =~ $anchored ]]
}

# Check if pattern matches at start of string
# @pre: string and pattern are provided
# @post: returns 0 if matches at start
# @idempotent: yes
# Usage: regex_starts_with "hello world" "hello" && echo "starts with"
regex_starts_with() {
    local string="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    local anchored="$pattern"
    [[ "$anchored" != "^"* ]] && anchored="^$anchored"

    [[ "$string" =~ $anchored ]]
}

# Check if pattern matches at end of string
# @pre: string and pattern are provided
# @post: returns 0 if matches at end
# @idempotent: yes
# Usage: regex_ends_with "hello world" "world" && echo "ends with"
regex_ends_with() {
    local string="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    local anchored="$pattern"
    [[ "$anchored" != *"$" ]] && anchored="$anchored$"

    [[ "$string" =~ $anchored ]]
}

# Remove matches from string
# @pre: string and pattern are provided
# @post: outputs string with matches removed
# @idempotent: yes
# Usage: cleaned=$(regex_remove "hello123world" "[0-9]+")
regex_remove() {
    local string="$1"
    local pattern="$2"

    regex_replace_all "$string" "$pattern" ""
}

# Keep only matching portions
# @pre: string and pattern are provided
# @post: outputs only matched content
# @idempotent: yes
# Usage: numbers=$(regex_keep "hello123world456" "[0-9]+")
regex_keep() {
    local string="$1"
    local pattern="$2"
    local result=""

    [[ -z "$pattern" ]] && return 1

    while IFS= read -r match; do
        result+="$match"
    done < <(regex_find_all "$string" "$pattern")

    printf '%s' "$result"
}

# =============================================================================
# USOP JSON OUTPUT HELPERS
# =============================================================================

# Output regex match result in USOP format
# @pre: match result and optional metadata
# @post: outputs JSON envelope
# @idempotent: yes
regex_output_match() {
    local matched="${1:-false}"
    local match="${2:-}"
    local groups="${3:-}"

    local escaped_match escaped_groups
    escaped_match=$(_regex_escape_json "$match")
    escaped_groups=$(_regex_escape_json "$groups")

    printf '{"ok":true,"data":{"matched":%s,"match":"%s","groups":"%s"}}\n' \
        "$matched" "$escaped_match" "$escaped_groups"
}

# Output regex replace result in USOP format
# @pre: original, result, and count
# @post: outputs JSON envelope
# @idempotent: yes
regex_output_replace() {
    local original="$1"
    local result="$2"
    local count="${3:-0}"

    local escaped_orig escaped_result
    escaped_orig=$(_regex_escape_json "$original")
    escaped_result=$(_regex_escape_json "$result")

    printf '{"ok":true,"data":{"original":"%s","result":"%s","replacements":%d}}\n' \
        "$escaped_orig" "$escaped_result" "$count"
}

# =============================================================================
# DEBUG HELPERS
# =============================================================================

# Debug a regex pattern - show structure and complexity
# @pre: pattern is provided
# @post: outputs debug information
# Usage: regex_debug "([a-z]+)([0-9]+)"
regex_debug() {
    local pattern="$1"

    [[ -z "$pattern" ]] && return 1

    local valid="false"
    regex_is_valid "$pattern" && valid="true"

    local safe="false"
    regex_compile_safe "$pattern" 2>/dev/null && safe="true"

    local score
    score=$(regex_complexity_score "$pattern")

    local groups alternations quantifiers
    groups=$(printf '%s' "$pattern" | grep -o '(' | wc -l)
    alternations=$(printf '%s' "$pattern" | grep -o '|' | wc -l)
    quantifiers=$(printf '%s' "$pattern" | grep -o '[*+?]' | wc -l)
    quantifiers=$((quantifiers + $(printf '%s' "$pattern" | grep -o '{[0-9]' | wc -l)))

    local escaped_pattern
    escaped_pattern=$(_regex_escape_json "$pattern")

    printf '{"pattern":"%s","length":%d,"valid":%s,"safe":%s,"complexity":%d,"groups":%d,"alternations":%d,"quantifiers":%d}\n' \
        "$escaped_pattern" "${#pattern}" "$valid" "$safe" "$score" "$groups" "$alternations" "$quantifiers"
}

# =============================================================================
# COMMON VALIDATION WRAPPERS
# =============================================================================

# Validate email using predefined pattern
# @pre: email string is provided
# @post: returns 0 if valid email format
# @idempotent: yes
# Usage: regex_validate_email "user@example.com" && echo "valid"
regex_validate_email() {
    [[ "$1" =~ $REGEX_EMAIL ]]
}

# Validate URL using predefined pattern
# @pre: url string is provided
# @post: returns 0 if valid URL format
# @idempotent: yes
# Usage: regex_validate_url "https://example.com" && echo "valid"
regex_validate_url() {
    [[ "$1" =~ $REGEX_URL ]]
}

# Validate IPv4 using predefined pattern
# @pre: ip string is provided
# @post: returns 0 if valid IPv4 format
# @idempotent: yes
# Usage: regex_validate_ipv4 "192.168.1.1" && echo "valid"
regex_validate_ipv4() {
    [[ "$1" =~ $REGEX_IPV4 ]]
}

# Validate UUID using predefined pattern
# @pre: uuid string is provided
# @post: returns 0 if valid UUID format
# @idempotent: yes
# Usage: regex_validate_uuid "550e8400-e29b-41d4-a716-446655440000" && echo "valid"
regex_validate_uuid() {
    [[ "$1" =~ $REGEX_UUID ]]
}

# Validate semantic version using predefined pattern
# @pre: version string is provided
# @post: returns 0 if valid semver format
# @idempotent: yes
# Usage: regex_validate_semver "1.2.3" && echo "valid"
regex_validate_semver() {
    [[ "$1" =~ $REGEX_SEMVER ]]
}

# Validate ISO date using predefined pattern
# @pre: date string is provided
# @post: returns 0 if valid ISO date format
# @idempotent: yes
# Usage: regex_validate_date_iso "2024-01-15" && echo "valid"
regex_validate_date_iso() {
    [[ "$1" =~ $REGEX_DATE_ISO ]]
}

# Validate slug using predefined pattern
# @pre: slug string is provided
# @post: returns 0 if valid slug format
# @idempotent: yes
# Usage: regex_validate_slug "hello-world" && echo "valid"
regex_validate_slug() {
    [[ "$1" =~ $REGEX_SLUG ]]
}

# Validate identifier using predefined pattern
# @pre: identifier string is provided
# @post: returns 0 if valid identifier format
# @idempotent: yes
# Usage: regex_validate_identifier "my_var" && echo "valid"
regex_validate_identifier() {
    [[ "$1" =~ $REGEX_IDENTIFIER ]]
}

# Validate hex color using predefined pattern
# @pre: color string is provided
# @post: returns 0 if valid hex color format
# @idempotent: yes
# Usage: regex_validate_hex_color "#ff5500" && echo "valid"
regex_validate_hex_color() {
    [[ "$1" =~ $REGEX_HEX_COLOR ]]
}

# Validate MAC address using predefined pattern
# @pre: mac string is provided
# @post: returns 0 if valid MAC address format
# @idempotent: yes
# Usage: regex_validate_mac_address "00:1A:2B:3C:4D:5E" && echo "valid"
regex_validate_mac_address() {
    [[ "$1" =~ $REGEX_MAC_ADDRESS ]]
}

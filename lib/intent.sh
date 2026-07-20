#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/intent.sh - Intent Parser and Natural Language to Bash
# =============================================================================
# Description: Parse natural language to structured intent, generate bash code,
#              and provide auto-complete suggestions. Rule-based (no LLM required).
# Version: 2.0.0 (V10 Intent Parser Extension)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_INTENT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_INTENT_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

# Risk levels used by intent classification
readonly INTENT_RISK_SAFE=0        # Read-only, reversible
readonly INTENT_RISK_LOW=1         # Minor side effects, easily reversible
readonly INTENT_RISK_MEDIUM=2      # Moderate side effects, recoverable
readonly INTENT_RISK_HIGH=3        # Significant changes, hard to reverse
readonly INTENT_RISK_CRITICAL=4    # Destructive, irreversible, privileged

# Risk labels for human-readable output
declare -gA _INTENT_RISK_LABELS=(
    [0]="safe" [1]="low" [2]="medium" [3]="high" [4]="critical"
)

# =============================================================================
# CONFIGURATION
# =============================================================================

# Strict mode requires explicit approval for medium+ risk
MAINFRAME_INTENT_STRICT="${MAINFRAME_INTENT_STRICT:-0}"

# Path to custom rules file (JSON)
MAINFRAME_INTENT_RULES="${MAINFRAME_INTENT_RULES:-${HOME}/.mainframe/intent_rules.json}"

# Blocked commands (comma-separated patterns)
MAINFRAME_INTENT_BLOCKED="${MAINFRAME_INTENT_BLOCKED:-}"

# =============================================================================
# PATTERN DATABASES - V10 Intent Parsing
# =============================================================================

# Action patterns - map natural language to command types
declare -gA _INTENT_ACTION_PATTERNS=(
    ["find"]="find search locate look for"
    ["count"]="count number of how many"
    ["remove"]="remove delete eliminate get rid of"
    ["copy"]="copy duplicate backup"
    ["move"]="move rename relocate"
    ["sort"]="sort order organize"
    ["show"]="show display list view print"
    ["get"]="get fetch download retrieve from url"
    ["compress"]="compress archive zip gzip tar"
    ["extract"]="extract unzip decompress unpack"
    ["replace"]="replace substitute change"
    ["create"]="create make generate new"
    ["backup"]="backup save snapshot"
)

# Target patterns - what is being operated on
declare -gA _INTENT_TARGET_PATTERNS=(
    ["files"]="files file documents"
    ["directories"]="directories directories folders dirs"
    ["lines"]="lines line rows"
    ["words"]="words word"
    ["size"]="size bytes space"
    ["content"]="content text inside"
    ["database"]="database db"
    ["logs"]="logs log"
)

# Time patterns - temporal constraints
declare -gA _INTENT_TIME_PATTERNS=(
    ["today"]="today"
    ["yesterday"]="yesterday"
    ["week"]="this week past week last week"
    ["month"]="this month past month last month"
    ["hour"]="last hour past hour"
    ["minute"]="last minute past minute"
)

# File type patterns
declare -gA _INTENT_TYPE_PATTERNS=(
    ["python"]="python py"
    ["javascript"]="javascript js node"
    ["bash"]="bash shell sh script"
    ["json"]="json"
    ["yaml"]="yaml yml"
    ["text"]="text txt"
    ["image"]="image img png jpg jpeg gif"
    ["log"]="log"
)

# Critical patterns (risk level 4) - Destructive, irreversible operations
declare -ga _INTENT_CRITICAL_PATTERNS=(
    # Filesystem destruction
    'rm[[:space:]]+-rf[[:space:]]+/'
    'rm[[:space:]]+-rf[[:space:]]+/\*'
    'rm[[:space:]]+-fr[[:space:]]+/'
    'rm[[:space:]]+-rf[[:space:]]+\*'
    'rm[[:space:]]+-rf[[:space:]]+~'
    'rm[[:space:]]+-rf[[:space:]]+\$HOME'
    'rm[[:space:]]+-rf[[:space:]]+\${HOME}'
    # Disk overwrite
    'dd[[:space:]]+.*if=/dev/zero[[:space:]]+of=/dev/'
    'dd[[:space:]]+.*of=/dev/[hs]d'
    ':>[[:space:]]*/dev/'
    # Filesystem formatting
    'mkfs\.'
    'wipefs'
    # Recursive permission disasters
    'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
    'chmod[[:space:]]+777[[:space:]]+/'
    'chown[[:space:]]+-R[[:space:]]+.*[[:space:]]+/'
    # Boot/system manipulation
    'rm[[:space:]].*-rf[[:space:]]+/boot'
    'rm[[:space:]].*-rf[[:space:]]+/etc'
    # Fork bombs
    ':\(\)[[:space:]]*{[[:space:]]*:|:\&[[:space:]]*}'
    '\(\)[[:space:]]*{[[:space:]]*\|[[:space:]]*\&'
    # Remote code execution patterns
    'curl[[:space:]].*\|[[:space:]]*bash'
    'curl[[:space:]].*\|[[:space:]]*sh'
    'wget[[:space:]].*\|[[:space:]]*bash'
    'wget[[:space:]].*\|[[:space:]]*sh'
    # Credential access
    'cat[[:space:]].*(/etc/shadow|/etc/passwd)'
    # Reverse shell patterns
    'nc[[:space:]]+-e'
    'bash[[:space:]]+-i[[:space:]]+>&'
)

# High risk patterns (risk level 3) - Significant changes, hard to reverse
declare -ga _INTENT_HIGH_PATTERNS=(
    # Recursive deletion
    'rm[[:space:]]+-rf'
    'rm[[:space:]]+-r[^f]'
    'rm[[:space:]]+-fr'
    # Privilege escalation
    'sudo[[:space:]]+'
    'su[[:space:]]+-'
    'doas[[:space:]]+'
    # Recursive permission changes
    'chmod[[:space:]]+-R'
    'chown[[:space:]]+-R'
    # Process termination
    'kill[[:space:]]+-9'
    'kill[[:space:]]+-SIGKILL'
    'killall'
    'pkill[[:space:]]+-9'
    # Service disruption
    'systemctl[[:space:]]+stop'
    'systemctl[[:space:]]+disable'
    'service[[:space:]]+.*[[:space:]]+stop'
    # SSH key operations
    '\.ssh/'
    'ssh-keygen[[:space:]]+-f'
    # Environment manipulation
    'export[[:space:]]+PATH='
    'unset[[:space:]]+PATH'
    # History/log tampering
    'history[[:space:]]+-c'
    '>[[:space:]]*/var/log'
    'shred[[:space:]].*log'
)

# Medium risk patterns (risk level 2) - Moderate side effects
declare -ga _INTENT_MEDIUM_PATTERNS=(
    # File operations
    'rm[[:space:]]+'
    'mv[[:space:]]+'
    'truncate'
    # In-place editing
    'sed[[:space:]]+-i'
    'perl[[:space:]]+-i'
    # Permission changes
    'chmod[[:space:]]+'
    'chown[[:space:]]+'
    # Output redirection (overwrite)
    '>[[:space:]]+[^|>]'
    # Package management
    'apt[[:space:]]+remove'
    'apt[[:space:]]+purge'
    'apt-get[[:space:]]+remove'
    'yum[[:space:]]+remove'
    'dnf[[:space:]]+remove'
    'pacman[[:space:]]+-R'
    'pip[[:space:]]+uninstall'
    'npm[[:space:]]+uninstall'
    # Git destructive operations
    'git[[:space:]]+push[[:space:]]+-f'
    'git[[:space:]]+push[[:space:]]+--force'
    'git[[:space:]]+reset[[:space:]]+--hard'
    'git[[:space:]]+clean[[:space:]]+-fd'
)

# Safe patterns (risk level 0) - Read-only operations
declare -ga _INTENT_SAFE_PATTERNS=(
    '^cat[[:space:]]+'
    '^ls[[:space:]]+'
    '^head[[:space:]]+'
    '^tail[[:space:]]+'
    '^grep[[:space:]]+'
    '^find[[:space:]]+'
    '^echo[[:space:]]+'
    '^printf[[:space:]]+'
    '^pwd[[:space:]]*$'
    '^whoami[[:space:]]*$'
    '^date[[:space:]]'
    '^file[[:space:]]+'
    '^stat[[:space:]]+'
    '^wc[[:space:]]+'
    '^du[[:space:]]+'
    '^df[[:space:]]+'
    '^which[[:space:]]+'
    '^type[[:space:]]+'
    '^env[[:space:]]*$'
    '^printenv'
)

# Obfuscation patterns - Commands trying to hide their intent
declare -ga _INTENT_OBFUSCATION_PATTERNS=(
    # Base64 encoding
    'base64[[:space:]]+-d'
    'base64[[:space:]]+--decode'
    # Hex encoding
    'xxd[[:space:]]+-r'
    'printf[[:space:]]+.*\\\\x'
    # Variable expansion tricks
    '\$\{[^}]*:-'
    '\$\{[^}]*:+'
    '\$\{[^}]*::'
    # Eval/exec wrappers
    'eval[[:space:]]+'
    'exec[[:space:]]+'
    '[$][(]' '\`'
)

# Common command completions for intent_complete
declare -ga _INTENT_COMMON_COMMANDS=(
    "find . -name '*.txt'"
    "find . -name '*.py' -type f"
    "find . -mtime -1"
    "grep -r 'pattern' ."
    "wc -l filename"
    "ls -la"
    "cp -r source dest"
    "mv source dest"
    "rm -i filename"
    "sort -u filename"
    "curl -O URL"
    "tar -czf archive.tar.gz files"
    "tar -xzf archive.tar.gz"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape string for JSON output
_intent_escape_json() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')   result+='\\"' ;;
            '\\')   result+='\\\\' ;;
            $'\b') result+='\\b' ;;
            $'\f') result+='\\f' ;;
            $'\n') result+='\\n' ;;
            $'\r') result+='\\r' ;;
            $'\t') result+='\\t' ;;
            *)
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# Build JSON array from bash array
_intent_array_to_json() {
    local first=true
    printf '['
    for item in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "$(_intent_escape_json "$item")"
    done
    printf ']'
}

# Check if command matches any pattern in array
# Usage: _intent_matches_patterns "command" pattern_array_name
_intent_matches_patterns() {
    local cmd="$1"
    local -n patterns_ref="$2"

    local pattern
    for pattern in "${patterns_ref[@]}"; do
        [[ -z "$pattern" ]] && continue
        if [[ "$cmd" =~ $pattern ]]; then
            printf '%s' "$pattern"
            return 0
        fi
    done
    return 1
}

# Load custom rules from JSON file if it exists
_intent_load_custom_rules() {
    [[ ! -f "$MAINFRAME_INTENT_RULES" ]] && return 0

    # Verify file permissions (should not be world-writable)
    local perms
    perms=$(stat -c "%a" "$MAINFRAME_INTENT_RULES" 2>/dev/null)
    if [[ "$perms" =~ [2367]$ ]]; then
        printf '{"warning":"intent rules file is world-writable"}\n' >&2
        return 1
    fi

    # Parse custom rules (simple JSON parsing for blocked patterns)
    # Full implementation would use jq or similar
    return 0
}

# =============================================================================
# V10 INTENT PARSING FUNCTIONS
# =============================================================================

# _intent_match_category - Match input against pattern category
# @internal
# @param $1 input - Natural language input
# @param $2 category_name - Name of associative array to match against
# @stdout Matched key or empty
_intent_match_category() {
    local input="${1,,}"  # lowercase
    local -n patterns="$2"
    local key keywords

    for key in "${!patterns[@]}"; do
        keywords="${patterns[$key]}"
        for kw in $keywords; do
            if [[ "$input" == *"$kw"* ]]; then
                printf '%s' "$key"
                return 0
            fi
        done
    done
    return 1
}

# _intent_extract_pattern - Extract file pattern from input
# @internal
# @param $1 input - Natural language input
# @stdout Extracted pattern (e.g., "*.py", "*.txt")
_intent_extract_pattern() {
    local input="$1"
    local pattern=""

    # Look for explicit patterns like "*.py"
    if [[ "$input" =~ \*\.[a-zA-Z]+ ]]; then
        pattern="${BASH_REMATCH[0]}"
    # Look for "all X files" pattern
    elif [[ "$input" =~ all[[:space:]]+([a-zA-Z]+)[[:space:]]+files ]]; then
        local ext="${BASH_REMATCH[1],,}"  # lowercase
        case "$ext" in
            python|py) pattern="*.py" ;;
            javascript|js) pattern="*.js" ;;
            bash|shell|sh) pattern="*.sh" ;;
            json) pattern="*.json" ;;
            yaml|yml) pattern="*.yml" ;;
            text|txt) pattern="*.txt" ;;
            log) pattern="*.log" ;;
            image|png|jpg|jpeg|gif) pattern="*.png" ;;
            *) pattern="*.${ext}" ;;
        esac
    # Look for "X files" pattern
    elif [[ "$input" =~ ([a-zA-Z\.]+)[[:space:]]+files ]]; then
        local ext="${BASH_REMATCH[1]}"
        [[ "$ext" == *.* ]] && pattern="*${ext}" || pattern="*.${ext}"
    fi

    printf '%s' "$pattern"
}

# _intent_extract_path - Extract path from input
# @internal
# @param $1 input - Natural language input
# @stdout Extracted path or "."
_intent_extract_path() {
    local input="$1"
    local path="."

    # Look for "in /path" or "from /path"
    if [[ "$input" =~ (in|from|under)[[:space:]]+(/[[:alnum:]/_.-]+) ]]; then
        path="${BASH_REMATCH[2]}"
    # Look for "directory /path"
    elif [[ "$input" =~ director(y|ies)[[:space:]]+(/[[:alnum:]/_.-]+) ]]; then
        path="${BASH_REMATCH[2]}"
    fi

    printf '%s' "$path"
}

# intent_parse - Parse natural language to structured intent
# @description Analyze natural language and extract structured intent
# @pre        None
# @post       Returns JSON structure describing intent
# @idempotent Yes
# @param      $1 input - Natural language input to parse
# @param      --json - Force JSON output
# @stdout     Structured intent JSON or error message
# @return     0 on success, 1 on parse failure
#
# Usage: intent_parse "find all Python files modified today"
# Output: {"action":"find","target":"files","pattern":"*.py","time":"today","path":"."}
intent_parse() {
    local input="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    # Initialize intent structure
    local action="" target="" time="" type="" pattern="" path="." operation=""
    local -a criteria=()

    # Empty input check
    if [[ -z "$input" ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"error":"empty input","parsed":false}\n'
        else
            printf 'Error: Empty input\n'
        fi
        return 1
    fi

    # Match action
    action=$(_intent_match_category "$input" _INTENT_ACTION_PATTERNS)
    [[ -z "$action" ]] && action="unknown"

    # Match target
    target=$(_intent_match_category "$input" _INTENT_TARGET_PATTERNS)
    [[ -z "$target" ]] && target="files"

    # Match time constraint
    time=$(_intent_match_category "$input" _INTENT_TIME_PATTERNS)

    # Match file type
    type=$(_intent_match_category "$input" _INTENT_TYPE_PATTERNS)

    # Extract pattern
    pattern=$(_intent_extract_pattern "$input")

    # Extract path
    path=$(_intent_extract_path "$input")

    # Determine operation based on action
    case "$action" in
        find) operation="list" ;;
        count) operation="count" ;;
        remove) operation="delete" ;;
        copy) operation="duplicate" ;;
        move) operation="relocate" ;;
        sort) operation="order" ;;
        show) operation="display" ;;
        get) operation="fetch" ;;
        compress) operation="archive" ;;
        extract) operation="decompress" ;;
        replace) operation="substitute" ;;
        create) operation="generate" ;;
        backup) operation="snapshot" ;;
        *) operation="execute" ;;
    esac

    # Build criteria object
    local criteria_json="{}"
    if [[ -n "$type" ]]; then
        criteria_json="{\"type\":\"$type\"}"
    fi
    if [[ -n "$time" ]]; then
        [[ "$criteria_json" != "{}" ]] && criteria_json="${criteria_json%\}},\"modified\":\"$time\"}"
    fi

    # Calculate confidence score
    local confidence="0.8"
    [[ "$action" == "unknown" ]] && confidence="0.3"

    # Build output
    if [[ $json_output -eq 1 ]]; then
        local escaped_input escaped_pattern escaped_path
        escaped_input=$(_intent_escape_json "$input")
        escaped_pattern=$(_intent_escape_json "$pattern")
        escaped_path=$(_intent_escape_json "$path")
        
        printf '{"action":"%s","target":"%s","operation":"%s","confidence":%s,"path":"%s","pattern":"%s"' \
            "$action" "$target" "$operation" "$confidence" "$escaped_path" "$escaped_pattern"
        
        if [[ -n "$time" ]]; then
            printf ',"time":"%s"' "$time"
        fi
        if [[ -n "$type" ]]; then
            printf ',"file_type":"%s"' "$type"
        fi
        printf '}\n'
    else
        printf 'Parsed Intent:\n'
        printf '  Action: %s\n' "$action"
        printf '  Target: %s\n' "$target"
        printf '  Operation: %s\n' "$operation"
        printf '  Path: %s\n' "$path"
        [[ -n "$pattern" ]] && printf '  Pattern: %s\n' "$pattern"
        [[ -n "$time" ]] && printf '  Time: %s\n' "$time"
        [[ -n "$type" ]] && printf '  File Type: %s\n' "$type"
        printf '  Confidence: %s\n' "$confidence"
    fi

    [[ "$action" != "unknown" ]]
}

# intent_to_bash - Convert intent JSON to bash command
# @description Generate bash code from structured intent
# @pre        Valid intent JSON from intent_parse
# @post       Returns bash command string
# @idempotent Yes
# @param      $1 intent_json - JSON structure from intent_parse
# @param      --safe - Add safety checks to generated code
# @param      --json - Output as JSON
# @stdout     Bash command or JSON with command and metadata
# @return     0 on success, 1 on conversion failure
#
# Usage: intent_to_bash '{"action":"find","pattern":"*.py"}'
# Output: "find . -name '*.py' -type f"
intent_to_bash() {
    local intent_json="$1"
    local safe_mode=0 json_output=0
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --safe) safe_mode=1; shift ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    # Validate input
    if [[ -z "$intent_json" ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"error":"empty intent","command":"","success":false}\n'
        else
            printf '# Error: Empty intent\n'
        fi
        return 1
    fi

    # Parse JSON fields (simple regex extraction)
    local action="" pattern="" path="" time="" target=""
    
    if [[ "$intent_json" =~ \"action\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        action="${BASH_REMATCH[1]}"
    fi
    if [[ "$intent_json" =~ \"pattern\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        pattern="${BASH_REMATCH[1]}"
    fi
    if [[ "$intent_json" =~ \"path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        path="${BASH_REMATCH[1]}"
    fi
    if [[ "$intent_json" =~ \"time\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        time="${BASH_REMATCH[1]}"
    fi
    if [[ "$intent_json" =~ \"target\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        target="${BASH_REMATCH[1]}"
    fi

    # Default values
    [[ -z "$path" ]] && path="."
    [[ -z "$target" ]] && target="files"

    # Generate bash command based on action
    local bash_cmd=""
    local safety_checks=""

    case "$action" in
        find)
            if [[ -n "$pattern" ]]; then
                bash_cmd="find $path -name '$pattern'"
                [[ "$target" == "files" ]] && bash_cmd+=" -type f"
                [[ "$target" == "directories" ]] && bash_cmd+=" -type d"
            else
                bash_cmd="find $path"
                [[ "$target" == "files" ]] && bash_cmd+=" -type f"
                [[ "$target" == "directories" ]] && bash_cmd+=" -type d"
            fi
            
            # Add time constraint
            case "$time" in
                today) bash_cmd+=" -mtime -1" ;;
                yesterday) bash_cmd+=" -mtime 1" ;;
                week) bash_cmd+=" -mtime -7" ;;
                month) bash_cmd+=" -mtime -30" ;;
            esac
            ;;
        
        count)
            if [[ "$target" == "lines" ]]; then
                if [[ -n "$pattern" ]]; then
                    bash_cmd="find $path -name '$pattern' -exec wc -l {} + 2>/dev/null | tail -1"
                else
                    bash_cmd="wc -l"
                fi
            elif [[ "$target" == "files" ]]; then
                if [[ -n "$pattern" ]]; then
                    bash_cmd="find $path -name '$pattern' -type f | wc -l"
                else
                    bash_cmd="find $path -type f | wc -l"
                fi
            else
                bash_cmd="wc -l"
            fi
            ;;
        
        remove)
            if [[ $safe_mode -eq 1 ]]; then
                bash_cmd="# SAFETY: Review before executing\n"
                bash_cmd+="# Preview what would be deleted:\n"
                bash_cmd+="find $path"
                [[ -n "$pattern" ]] && bash_cmd+=" -name '$pattern'"
                bash_cmd+=" -type f -print\n"
                bash_cmd+="# Then uncomment to delete:\n"
                bash_cmd+="# find $path"
                [[ -n "$pattern" ]] && bash_cmd+=" -name '$pattern'"
                bash_cmd+=" -type f -delete"
            else
                bash_cmd="# WARNING: Destructive operation\n"
                bash_cmd+="find $path"
                [[ -n "$pattern" ]] && bash_cmd+=" -name '$pattern'"
                bash_cmd+=" -type f -delete"
            fi
            ;;
        
        sort)
            bash_cmd="sort"
            ;;
        
        show)
            if [[ "$target" == "files" ]]; then
                bash_cmd="ls -la $path"
            else
                bash_cmd="cat"
            fi
            ;;
        
        get)
            bash_cmd="curl -O"
            ;;
        
        copy)
            bash_cmd="cp -r"
            ;;
        
        move)
            bash_cmd="mv"
            ;;
        
        compress)
            bash_cmd="tar -czf archive_\$(date +%Y%m%d_%H%M%S).tar.gz"
            ;;
        
        extract)
            bash_cmd="tar -xzf"
            ;;
        
        backup)
            bash_cmd="# Backup with timestamp\n"
            bash_cmd+="cp -r \${source:-.} \${source:-backup}_\$(date +%Y%m%d_%H%M%S)"
            ;;
        
        *)
            if [[ $json_output -eq 1 ]]; then
                printf '{"error":"unknown action: %s","command":"","success":false}\n' "$action"
            else
                printf '# Unknown action: %s\n' "$action"
                printf '# Try: find, count, remove, sort, show, get, copy, move, compress, extract, backup\n'
            fi
            return 1
            ;;
    esac

    # Output result
    if [[ $json_output -eq 1 ]]; then
        local escaped_cmd escaped_intent
        escaped_cmd=$(_intent_escape_json "$bash_cmd")
        escaped_intent=$(_intent_escape_json "$intent_json")
        printf '{"intent":%s,"command":"%s","action":"%s","safe_mode":%s,"success":true}\n' \
            "$escaped_intent" "$escaped_cmd" "$action" "$([[ $safe_mode -eq 1 ]] && echo "true" || echo "false")"
    else
        printf '%s\n' "$bash_cmd"
    fi

    return 0
}

# intent_explain - Explain what bash code does in plain English
# @description Parse bash code and explain its effects
# @pre        None
# @post       Returns human-readable explanation
# @idempotent Yes
# @param      $1 bash_code - Bash code to explain
# @param      --json - Output as JSON
# @param      --verbose - Include detailed breakdown
# @stdout     Explanation of code effects
# @return     0 always
#
# Usage: intent_explain "find . -name '*.py' -mtime -1"
intent_explain() {
    local bash_code="$1"
    shift

    local json_output=0 verbose=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --verbose) verbose=1; shift ;;
            *) shift ;;
        esac
    done

    # Handle multiline input
    bash_code="${bash_code//$'\n'/ }"
    
    local base_cmd="${bash_code%% *}"
    local summary=""
    local -a details=()
    local -a safety=()

    # Build explanation based on command
    case "$base_cmd" in
        find)
            summary="Search for files matching criteria"
            
            if [[ "$bash_code" == *"-name"* ]]; then
                if [[ "$bash_code" =~ -name[[:space:]]+[\"\']?([^\"\'[:space:]]+)[\"\']? ]]; then
                    details+=("Looking for files named: ${BASH_REMATCH[1]}")
                fi
            fi
            
            if [[ "$bash_code" == *"-type f"* ]]; then
                details+=("Only matching regular files (not directories)")
            elif [[ "$bash_code" == *"-type d"* ]]; then
                details+=("Only matching directories")
            fi
            
            if [[ "$bash_code" == *"-mtime"* ]]; then
                if [[ "$bash_code" =~ -mtime[[:space:]]+(-?[0-9]+) ]]; then
                    local days="${BASH_REMATCH[1]}"
                    if [[ "$days" == "-1" ]]; then
                        details+=("Only files modified in the last 24 hours")
                    elif [[ "$days" == "1" ]]; then
                        details+=("Only files modified exactly 1 day ago")
                    elif [[ "$days" == "-7" ]]; then
                        details+=("Only files modified in the last week")
                    elif [[ "$days" == "-30" ]]; then
                        details+=("Only files modified in the last month")
                    else
                        details+=("Modified within $days days")
                    fi
                fi
            fi
            
            if [[ "$bash_code" == *"-delete"* ]]; then
                safety+=("WARNING: This will DELETE matching files permanently")
            fi
            
            if [[ "$bash_code" == *"-exec"* ]]; then
                details+=("Will execute a command on each matching file")
            fi
            ;;
        
        grep)
            summary="Search for text patterns in files"
            
            if [[ "$bash_code" == *"-r"* ]] || [[ "$bash_code" == *"--recursive"* ]]; then
                details+=("Recursively searches directories")
            fi
            
            if [[ "$bash_code" == *"-i"* ]]; then
                details+=("Case-insensitive matching")
            fi
            
            # Extract pattern
            if [[ "$bash_code" =~ [\"\']([^\"\']+)[\"\'] ]]; then
                details+=("Searching for: ${BASH_REMATCH[1]}")
            fi
            ;;
        
        wc)
            summary="Count lines, words, or bytes"
            
            if [[ "$bash_code" == *"-l"* ]]; then
                details+=("Counting lines")
            elif [[ "$bash_code" == *"-w"* ]]; then
                details+=("Counting words")
            elif [[ "$bash_code" == *"-c"* ]]; then
                details+=("Counting bytes")
            else
                details+=("Counting lines, words, and bytes")
            fi
            ;;
        
        rm)
            summary="Delete files or directories"
            safety+=("DESTRUCTIVE: Files will be permanently removed")
            
            if [[ "$bash_code" == *"-r"* ]] || [[ "$bash_code" == *"-R"* ]]; then
                details+=("Recursive deletion (includes subdirectories)")
            fi
            
            if [[ "$bash_code" == *"-f"* ]]; then
                details+=("Force mode: no confirmation prompts")
                safety+=("DANGER: No confirmation before deletion")
            fi
            
            if [[ "$bash_code" == *"-i"* ]]; then
                details+=("Interactive mode: asks before each removal")
                safety+=("SAFER: Will prompt for confirmation")
            fi
            ;;
        
        cp)
            summary="Copy files or directories"
            
            if [[ "$bash_code" == *"-r"* ]] || [[ "$bash_code" == *"-R"* ]]; then
                details+=("Recursive copy (includes subdirectories)")
            fi
            
            if [[ "$bash_code" == *"-p"* ]]; then
                details+=("Preserves file permissions and timestamps")
            fi
            
            if [[ "$bash_code" == *"-v"* ]]; then
                details+=("Verbose mode: shows each file copied")
            fi
            ;;
        
        mv)
            summary="Move or rename files/directories"
            
            if [[ "$bash_code" == *"-i"* ]]; then
                details+=("Interactive: asks before overwriting")
            fi
            
            if [[ "$bash_code" == *"-f"* ]]; then
                details+=("Force: overwrites without prompting")
                safety+=("WARNING: May overwrite existing files")
            fi
            ;;
        
        sort)
            summary="Sort lines of text"
            
            if [[ "$bash_code" == *"-r"* ]]; then
                details+=("Reverse order (descending)")
            fi
            
            if [[ "$bash_code" == *"-u"* ]]; then
                details+=("Unique: removes duplicate lines")
            fi
            
            if [[ "$bash_code" == *"-n"* ]]; then
                details+=("Numeric sort (not alphabetic)")
            fi
            ;;
        
        curl)
            summary="Download content from URL"
            
            if [[ "$bash_code" == *"-O"* ]]; then
                details+=("Save to file with original name")
            fi
            
            if [[ "$bash_code" == *"-o"* ]]; then
                details+=("Save to specified filename")
            fi
            
            if [[ "$bash_code" == *"-L"* ]]; then
                details+=("Follow redirects")
            fi
            
            if [[ "$bash_code" == *"|"* ]]; then
                safety+=("WARNING: Output piped to another command")
            fi
            ;;
        
        tar)
            summary="Archive or extract files"
            
            if [[ "$bash_code" == *"-c"* ]] || [[ "$bash_code" == *"--create"* ]]; then
                details+=("Create new archive")
            fi
            
            if [[ "$bash_code" == *"-x"* ]] || [[ "$bash_code" == *"--extract"* ]]; then
                details+=("Extract from archive")
            fi
            
            if [[ "$bash_code" == *"-z"* ]] || [[ "$bash_code" == *"--gzip"* ]]; then
                details+=("Use gzip compression")
            fi
            
            if [[ "$bash_code" == *"-v"* ]]; then
                details+=("Verbose: list files processed")
            fi
            ;;
        
        ls)
            summary="List directory contents"
            
            if [[ "$bash_code" == *"-l"* ]]; then
                details+=("Long format: permissions, owner, size, date")
            fi
            
            if [[ "$bash_code" == *"-a"* ]]; then
                details+=("All files: includes hidden files (starting with .)")
            fi
            
            if [[ "$bash_code" == *"-h"* ]]; then
                details+=("Human-readable sizes (KB, MB, GB)")
            fi
            ;;
        
        cat)
            summary="Display file contents"
            details+=("Outputs entire file content to terminal")
            ;;
        
        chmod)
            summary="Change file permissions"
            safety+=("MODIFIES PERMISSIONS: affects file access")
            
            if [[ "$bash_code" == *"-R"* ]]; then
                details+=("Recursive: affects all files in directory")
                safety+=("WARNING: Mass permission change")
            fi
            
            if [[ "$bash_code" =~ 777 ]]; then
                safety+=("CRITICAL: 777 gives full access to EVERYONE")
            fi
            ;;
        
        *)
            summary="Execute $base_cmd command"
            details+=("Runs the $base_cmd program with provided arguments")
            ;;
    esac

    # Risk assessment
    local risk=0
    if _intent_matches_patterns "$bash_code" _INTENT_CRITICAL_PATTERNS &>/dev/null; then
        risk=$INTENT_RISK_CRITICAL
        safety+=("CRITICAL RISK: This command could cause serious damage")
    elif _intent_matches_patterns "$bash_code" _INTENT_HIGH_PATTERNS &>/dev/null; then
        risk=$INTENT_RISK_HIGH
        safety+=("HIGH RISK: Use with caution")
    elif _intent_matches_patterns "$bash_code" _INTENT_MEDIUM_PATTERNS &>/dev/null; then
        risk=$INTENT_RISK_MEDIUM
        safety+=("MEDIUM RISK: Has side effects")
    fi

    # Output
    if [[ $json_output -eq 1 ]]; then
        local escaped_cmd escaped_summary
        escaped_cmd=$(_intent_escape_json "$bash_code")
        escaped_summary=$(_intent_escape_json "$summary")
        local details_json safety_json
        details_json=$(_intent_array_to_json "${details[@]}")
        safety_json=$(_intent_array_to_json "${safety[@]}")
        printf '{"command":"%s","summary":"%s","details":%s,"safety":%s,"risk":%d}\n' \
            "$escaped_cmd" "$escaped_summary" "$details_json" "$safety_json" "$risk"
    else
        printf 'Command: %s\n' "$bash_code"
        printf 'Summary: %s\n' "$summary"
        
        if [[ ${#details[@]} -gt 0 ]]; then
            printf '\nDetails:\n'
            for detail in "${details[@]}"; do
                printf '  • %s\n' "$detail"
            done
        fi
        
        if [[ ${#safety[@]} -gt 0 ]]; then
            printf '\nSafety Considerations:\n'
            for note in "${safety[@]}"; do
                printf '  ⚠ %s\n' "$note"
            done
        fi
        
        printf '\nRisk Level: %s\n' "${_INTENT_RISK_LABELS[$risk]}"
    fi

    return 0
}

# intent_complete - Provide auto-complete suggestions for partial commands
# @description Suggest completions based on partial input and common patterns
# @pre        None
# @post       Returns list of suggestions
# @idempotent Yes
# @param      $1 partial - Partial command to complete
# @param      --json - Output as JSON
# @param      --max N - Maximum suggestions (default: 10)
# @stdout     List of completion suggestions
# @return     0 always
#
# Usage: intent_complete "find all py"
# Output: find all python files
#         find all .py files modified today
intent_complete() {
    local partial="$1"
    shift

    local json_output=0 max_suggestions=10
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --max) max_suggestions="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local -a suggestions=()
    local partial_lower="${partial,,}"

    # Pattern-based suggestions
    case "$partial_lower" in
        *find*)
            suggestions+=("find all files")
            suggestions+=("find all directories")
            suggestions+=("find all *.py files")
            suggestions+=("find all *.txt files")
            suggestions+=("find all files modified today")
            suggestions+=("find all files larger than 1MB")
            ;;&
        *count*)
            suggestions+=("count lines in file")
            suggestions+=("count files in directory")
            suggestions+=("count words in file")
            suggestions+=("count all *.log files")
            ;;&
        *remove*|*delete*)
            suggestions+=("remove all *.tmp files")
            suggestions+=("remove empty directories")
            suggestions+=("remove files older than 30 days")
            ;;&
        *sort*)
            suggestions+=("sort file alphabetically")
            suggestions+=("sort file numerically")
            suggestions+=("sort and remove duplicates")
            ;;&
        *show*|*list*)
            suggestions+=("show all files")
            suggestions+=("show hidden files")
            suggestions+=("list directory contents")
            ;;&
        *get*|*download*)
            suggestions+=("get from URL")
            suggestions+=("download file from URL")
            ;;&
        *backup*)
            suggestions+=("backup directory with timestamp")
            suggestions+=("backup all important files")
            ;;&
        *compress*)
            suggestions+=("compress directory to tar.gz")
            suggestions+=("compress files to zip")
            ;;&
        *extract*)
            suggestions+=("extract tar.gz archive")
            suggestions+=("extract zip file")
            ;;&
    esac

    # Add matching common commands
    for cmd in "${_INTENT_COMMON_COMMANDS[@]}"; do
        local cmd_lower="${cmd,,}"
        if [[ "$cmd_lower" == *"$partial_lower"* ]]; then
            suggestions+=("$cmd")
        fi
    done

    # Remove duplicates while preserving order
    local -a unique_suggestions=()
    local seen
    for sug in "${suggestions[@]}"; do
        seen=0
        for existing in "${unique_suggestions[@]}"; do
            if [[ "$sug" == "$existing" ]]; then
                seen=1
                break
            fi
        done
        [[ $seen -eq 0 ]] && unique_suggestions+=("$sug")
    done

    # Limit results
    local count=${#unique_suggestions[@]}
    [[ $count -gt $max_suggestions ]] && count=$max_suggestions

    # Output
    if [[ $json_output -eq 1 ]]; then
        local sug_json
        sug_json=$(_intent_array_to_json "${unique_suggestions[@]:0:$count}")
        printf '{"partial":"%s","suggestions":%s,"count":%d}\n' \
            "$(_intent_escape_json "$partial")" "$sug_json" "$count"
    else
        printf 'Suggestions for "%s":\n' "$partial"
        for ((i=0; i<count; i++)); do
            printf '  %d. %s\n' $((i+1)) "${unique_suggestions[$i]}"
        done
    fi

    return 0
}

# =============================================================================
# ORIGINAL INTENT VERIFICATION FUNCTIONS (PRESERVED)
# =============================================================================

# _intent_classify_analysis - Analyze a command and populate risk metadata
# @description Internal helper for command classification
# @param      $1 command - Full command string to classify
# @param      $2 risk_ref - Nameref for numeric risk output
# @param      $3 reasons_ref - Nameref for reasons array output
# @param      $4 suggestions_ref - Nameref for suggestions array output
# @param      $5 matched_pattern_ref - Nameref for matched pattern output
# @return     0 on valid input, 1 on empty command
_intent_classify_analysis() {
    local command="$1"
    local -n risk_ref="$2"
    local -n reasons_ref="$3"
    local -n suggestions_ref="$4"
    local -n matched_pattern_ref="$5"

    risk_ref=$INTENT_RISK_LOW
    reasons_ref=()
    suggestions_ref=()
    matched_pattern_ref=""

    [[ -z "$command" ]] && return 1

    # Check against blocked commands first
    if [[ -n "$MAINFRAME_INTENT_BLOCKED" ]]; then
        local IFS=','
        local blocked
        for blocked in $MAINFRAME_INTENT_BLOCKED; do
            blocked="${blocked#"${blocked%%[![:space:]]*}"}"
            blocked="${blocked%"${blocked##*[![:space:]]}"}"
            [[ -z "$blocked" ]] && continue
            if [[ "$command" =~ $blocked ]]; then
                risk_ref=$INTENT_RISK_CRITICAL
                reasons_ref+=("matches blocked command pattern")
            fi
        done
    fi

    # Check for obfuscation attempts
    if matched_pattern_ref=$(_intent_matches_patterns "$command" _INTENT_OBFUSCATION_PATTERNS); then
        risk_ref=$INTENT_RISK_CRITICAL
        reasons_ref+=("contains obfuscation pattern: $matched_pattern_ref")
        suggestions_ref+=("review command manually for hidden intent")
    fi

    # Check critical patterns
    if [[ $risk_ref -lt $INTENT_RISK_CRITICAL ]]; then
        if matched_pattern_ref=$(_intent_matches_patterns "$command" _INTENT_CRITICAL_PATTERNS); then
            risk_ref=$INTENT_RISK_CRITICAL
            reasons_ref+=("matches critical pattern: $matched_pattern_ref")
            suggestions_ref+=("this command could cause irreversible damage")
        fi
    fi

    # Check high patterns (only if not already critical)
    if [[ $risk_ref -lt $INTENT_RISK_HIGH ]]; then
        if matched_pattern_ref=$(_intent_matches_patterns "$command" _INTENT_HIGH_PATTERNS); then
            risk_ref=$INTENT_RISK_HIGH
            reasons_ref+=("matches high-risk pattern: $matched_pattern_ref")
            suggestions_ref+=("consider using safer alternatives")
        fi
    fi

    # Check medium patterns
    if [[ $risk_ref -lt $INTENT_RISK_MEDIUM ]]; then
        if matched_pattern_ref=$(_intent_matches_patterns "$command" _INTENT_MEDIUM_PATTERNS); then
            risk_ref=$INTENT_RISK_MEDIUM
            reasons_ref+=("matches medium-risk pattern: $matched_pattern_ref")
        fi
    fi

    # Prefer a direct command-prefix check for known read-only commands so the
    # safe classification does not depend solely on regex-engine quirks.
    if [[ $risk_ref -le $INTENT_RISK_LOW ]]; then
        local base_cmd="${command%%[[:space:]]*}"
        case "$base_cmd" in
            cat|ls|head|tail|grep|find|echo|printf|pwd|whoami|date|file)
                risk_ref=$INTENT_RISK_SAFE
                reasons_ref=("read-only operation")
                ;;
        esac

        if [[ $risk_ref -le $INTENT_RISK_LOW ]] && _intent_matches_patterns "$command" _INTENT_SAFE_PATTERNS >/dev/null; then
            risk_ref=$INTENT_RISK_SAFE
            reasons_ref=("read-only operation")
        fi
    fi

    return 0
}

# _intent_classify_risk - Return numeric risk without using shell exit status
# @description Internal helper for callers that need the numeric risk value
# @param      $1 command - Full command string to classify
# @stdout     Numeric risk level (0-4)
# @return     0 always
_intent_classify_risk() {
    local risk matched_pattern
    local -a reasons=()
    local -a suggestions=()

    _intent_classify_analysis "$1" risk reasons suggestions matched_pattern || true
    printf '%s\n' "$risk"
    return 0
}

# intent_classify - Classify a command by risk level
# @description Analyze command string and determine risk level (0-4)
# @pre        None
# @post       None (static analysis only, no execution)
# @idempotent Yes
# @param      $1 command - Full command string to classify
# @param      --json - Output as JSON object
# @stdout     Risk level and classification details
# @return     0 on successful classification, 1 on invalid input
#
# Usage: risk=$(intent_classify "rm -rf /tmp/cache")
# Usage: intent_classify "chmod 777 /etc/passwd" --json
intent_classify() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local risk matched_pattern
    local -a reasons=()
    local -a suggestions=()

    if ! _intent_classify_analysis "$command" risk reasons suggestions matched_pattern; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"error":"empty command","risk":%d,"risk_label":"low"}\n' "$INTENT_RISK_LOW"
        fi
        return 1
    fi

    # Output result
    if [[ $json_output -eq 1 ]]; then
        local escaped_cmd
        escaped_cmd=$(_intent_escape_json "$command")
        local reasons_json suggestions_json
        reasons_json=$(_intent_array_to_json "${reasons[@]}")
        suggestions_json=$(_intent_array_to_json "${suggestions[@]}")
        printf '{"command":"%s","risk":%d,"risk_label":"%s","reasons":%s,"suggestions":%s}\n' \
            "$escaped_cmd" "$risk" "${_INTENT_RISK_LABELS[$risk]}" "$reasons_json" "$suggestions_json"
    else
        printf '%s\n' "${_INTENT_RISK_LABELS[$risk]}"
    fi

    return 0
}

# intent_verify - Verify command safety with declared intent and path constraints
# @description Check if command matches declared intent and respects path boundaries
# @pre        None
# @post       None (verification only)
# @idempotent Yes
# @param      $1 declared_intent - What the command is supposed to do
# @param      $2 command - Actual command to verify
# @param      --strict - Fail if intent doesn't clearly match
# @param      --base-path - Allowed base path for operations
# @param      --json - Output as JSON
# @stdout     Verification result with confidence score
# @return     0 if verified, 1 if mismatch, 2 if uncertain
#
# Usage: intent_verify "delete temp files" "rm -rf /tmp/cache"
# Usage: intent_verify "delete old logs" "rm -rf /var/log" --strict --base-path /tmp
intent_verify() {
    local declared_intent="$1"
    local command="$2"
    shift 2

    local strict=0 json_output=0 base_path=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strict) strict=1; shift ;;
            --json) json_output=1; shift ;;
            --base-path) base_path="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local intent_lower="${declared_intent,,}"
    local cmd_lower="${command,,}"
    local verified="true"
    local confidence="0.5"
    local -a warnings=()
    local analysis=""

    # Check for clear intent/command mismatches
    if [[ "$intent_lower" =~ (read|view|show|list|display) ]] && \
       [[ "$cmd_lower" =~ (rm|delete|remove|truncate) ]]; then
        verified="false"
        confidence="0.1"
        warnings+=("MISMATCH: read intent with destructive command")
        analysis="declared intent suggests read-only operation but command is destructive"
    elif [[ "$intent_lower" =~ (delete|remove|clean) ]] && [[ "$cmd_lower" =~ rm[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (copy|backup|duplicate) ]] && [[ "$cmd_lower" =~ cp[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (move|rename) ]] && [[ "$cmd_lower" =~ mv[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (create|make|mkdir) ]] && [[ "$cmd_lower" =~ (mkdir|touch)[[:space:]] ]]; then
        confidence="0.9"
        analysis="intent matches command operation"
    elif [[ "$intent_lower" =~ (edit|modify|change|update) ]] && [[ "$cmd_lower" =~ (sed|vim|nano|edit) ]]; then
        confidence="0.85"
        analysis="intent likely matches command operation"
    else
        confidence="0.5"
        warnings+=("intent keywords do not clearly match command")
        analysis="unable to confirm intent matches command"
    fi

    # Path boundary validation if base_path specified
    if [[ -n "$base_path" ]]; then
        # Extract paths from command (simple heuristic)
        local -a cmd_paths=()
        local word
        for word in $command; do
            if [[ "$word" == /* ]]; then
                cmd_paths+=("$word")
            fi
        done

        # Check each path against base_path
        for word in "${cmd_paths[@]}"; do
            # Use validate_path_safe if available
            if declare -f validate_path_safe &>/dev/null; then
                if ! validate_path_safe "$word" "$base_path" 2>/dev/null; then
                    verified="false"
                    confidence="0.1"
                    warnings+=("path $word is outside allowed base: $base_path")
                fi
            else
                # Simple prefix check
                if [[ "$word" != "$base_path"* ]]; then
                    verified="false"
                    confidence="0.1"
                    warnings+=("path $word is outside allowed base: $base_path")
                fi
            fi
        done
    fi

    # Strict mode: fail on low confidence
    if [[ $strict -eq 1 ]]; then
        local conf_int="${confidence%.*}"
        [[ -z "$conf_int" ]] && conf_int=0
        if [[ "$confidence" != "0."* ]] && [[ $conf_int -lt 7 ]]; then
            verified="false"
        elif [[ "$confidence" == "0."* ]]; then
            local decimal="${confidence#0.}"
            [[ ${decimal:0:1} -lt 7 ]] && verified="false"
        fi
    fi

    # Classify risk
    local risk
    risk=$(_intent_classify_risk "$command")

    if [[ $risk -ge $INTENT_RISK_HIGH ]]; then
        warnings+=("command has high risk level: ${_INTENT_RISK_LABELS[$risk]}")
        # Use awk for decimal comparison (bash cannot compare decimals natively)
        if awk "BEGIN {exit !($confidence > 0.5)}"; then
            confidence="0.5"
        fi
    fi

    # Output
    if [[ $json_output -eq 1 ]]; then
        local escaped_intent escaped_cmd escaped_analysis
        escaped_intent=$(_intent_escape_json "$declared_intent")
        escaped_cmd=$(_intent_escape_json "$command")
        escaped_analysis=$(_intent_escape_json "$analysis")
        local warnings_json
        warnings_json=$(_intent_array_to_json "${warnings[@]}")
        printf '{"verified":%s,"confidence":%s,"intent":"%s","command":"%s","analysis":"%s","warnings":%s,"risk":%d}\n' \
            "$verified" "$confidence" "$escaped_intent" "$escaped_cmd" "$escaped_analysis" "$warnings_json" "$risk"
    else
        printf '%s (confidence: %s)\n' "$verified" "$confidence"
    fi

    [[ "$verified" == "true" ]] && return 0
    [[ "$confidence" == "0.5" ]] && return 2
    return 1
}

# intent_sandbox_recommend - Recommend sandbox settings based on command analysis
# @description Analyze command and suggest appropriate sandbox configuration
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      $1 command - Command to analyze
# @param      --json - Output as JSON
# @stdout     Sandbox recommendations
# @return     0 always
#
# Usage: intent_sandbox_recommend "rm -rf /tmp/cache"
# Usage: intent_sandbox_recommend "curl https://example.com" --json
intent_sandbox_recommend() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local risk
    risk=$(_intent_classify_risk "$command")

    local dry_run="false"
    local network="true"
    local timeout=300
    local -a allow_write=()
    local -a deny_write=()
    local -a recommendations=()

    case $risk in
        $INTENT_RISK_CRITICAL)
            dry_run="true"
            timeout=10
            deny_write+=("/")
            recommendations+=("CRITICAL: use dry-run mode only")
            recommendations+=("manual review required before execution")
            ;;
        $INTENT_RISK_HIGH)
            dry_run="true"
            timeout=60
            deny_write+=("/" "/etc" "/usr" "/boot" "/home")
            recommendations+=("recommend dry-run before actual execution")
            recommendations+=("use checkpoint before modifying files")
            ;;
        $INTENT_RISK_MEDIUM)
            timeout=120
            deny_write+=("/etc" "/usr" "/boot")
            recommendations+=("consider using backup before execution")
            ;;
        $INTENT_RISK_LOW)
            timeout=300
            recommendations+=("standard sandbox settings appropriate")
            ;;
        $INTENT_RISK_SAFE)
            timeout=300
            recommendations+=("minimal sandbox restrictions needed")
            ;;
    esac

    # Check for network commands
    if [[ "$command" =~ (curl|wget|nc|ssh|scp|rsync|ftp) ]]; then
        if [[ $risk -ge $INTENT_RISK_HIGH ]]; then
            network="false"
            recommendations+=("network access denied due to high risk")
        fi
    fi

    # Extract paths from command for allow_write suggestions
    local word
    for word in $command; do
        if [[ "$word" == /tmp/* ]] || [[ "$word" == /var/tmp/* ]]; then
            allow_write+=("$word")
        fi
    done

    if [[ $json_output -eq 1 ]]; then
        local allow_json deny_json rec_json
        allow_json=$(_intent_array_to_json "${allow_write[@]}")
        deny_json=$(_intent_array_to_json "${deny_write[@]}")
        rec_json=$(_intent_array_to_json "${recommendations[@]}")
        printf '{"risk":%d,"risk_label":"%s","sandbox":{"dry_run":%s,"network":%s,"timeout":%d,"allow_write":%s,"deny_write":%s},"recommendations":%s}\n' \
            "$risk" "${_INTENT_RISK_LABELS[$risk]}" "$dry_run" "$network" "$timeout" "$allow_json" "$deny_json" "$rec_json"
    else
        printf 'Risk Level: %s (%d)\n' "${_INTENT_RISK_LABELS[$risk]}" "$risk"
        printf 'Sandbox Settings:\n'
        printf '  Dry Run: %s\n' "$dry_run"
        printf '  Network: %s\n' "$network"
        printf '  Timeout: %ds\n' "$timeout"
        [[ ${#allow_write[@]} -gt 0 ]] && printf '  Allow Write: %s\n' "${allow_write[*]}"
        [[ ${#deny_write[@]} -gt 0 ]] && printf '  Deny Write: %s\n' "${deny_write[*]}"
        printf 'Recommendations:\n'
        for rec in "${recommendations[@]}"; do
            printf '  - %s\n' "$rec"
        done
    fi

    return 0
}

# intent_dry_run - Simulate command execution without side effects
# @description Parse and explain what a command would do without executing it
# @pre        None
# @post       None (analysis only, NO EXECUTION)
# @idempotent Yes
# @param      $1 command - Command to simulate
# @param      --json - Output as JSON
# @stdout     Simulation results
# @return     0 always
#
# Usage: intent_dry_run "rm -rf /tmp/cache"
intent_dry_run() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local -a would_affect=()
    local -a operations=()
    local risk
    risk=$(_intent_classify_risk "$command")

    # Parse command to identify operations (static analysis only)
    local base_cmd="${command%% *}"

    case "$base_cmd" in
        rm)
            operations+=("delete")
            # Extract targets
            local word
            for word in $command; do
                [[ "$word" == -* ]] && continue
                [[ "$word" == "rm" ]] && continue
                would_affect+=("$word")
            done
            ;;
        mv)
            operations+=("move/rename")
            local -a args=()
            for word in $command; do
                [[ "$word" == -* ]] && continue
                [[ "$word" == "mv" ]] && continue
                args+=("$word")
            done
            [[ ${#args[@]} -ge 2 ]] && would_affect+=("${args[0]} -> ${args[-1]}")
            ;;
        cp)
            operations+=("copy")
            ;;
        chmod)
            operations+=("change permissions")
            ;;
        chown)
            operations+=("change ownership")
            ;;
        mkdir)
            operations+=("create directory")
            ;;
        touch)
            operations+=("create/update file")
            ;;
        *)
            operations+=("$base_cmd operation")
            ;;
    esac

    if [[ $json_output -eq 1 ]]; then
        local ops_json affects_json escaped_cmd
        escaped_cmd=$(_intent_escape_json "$command")
        ops_json=$(_intent_array_to_json "${operations[@]}")
        affects_json=$(_intent_array_to_json "${would_affect[@]}")
        printf '{"dry_run":true,"command":"%s","operations":%s,"would_affect":%s,"risk":%d,"risk_label":"%s"}\n' \
            "$escaped_cmd" "$ops_json" "$affects_json" "$risk" "${_INTENT_RISK_LABELS[$risk]}"
    else
        printf '[DRY RUN] Command: %s\n' "$command"
        printf 'Operations: %s\n' "${operations[*]}"
        printf 'Risk Level: %s\n' "${_INTENT_RISK_LABELS[$risk]}"
        [[ ${#would_affect[@]} -gt 0 ]] && printf 'Would Affect:\n'
        for target in "${would_affect[@]}"; do
            printf '  - %s\n' "$target"
        done
    fi

    return 0
}

# intent_estimate_cost - Estimate I/O impact and time for a command
# @description Analyze command to estimate resource usage (no execution)
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      $1 command - Command to analyze
# @param      --json - Output as JSON
# @stdout     Cost estimation
# @return     0 always
#
# Usage: intent_estimate_cost "find / -name '*.log'"
intent_estimate_cost() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local io_level="low"
    local cpu_level="low"
    local time_estimate="seconds"
    local -a notes=()

    local base_cmd="${command%% *}"

    # Estimate based on command type
    case "$base_cmd" in
        find)
            io_level="high"
            time_estimate="minutes"
            [[ "$command" == *"/"[[:space:]]* ]] && notes+=("searching from root may take significant time")
            ;;
        grep|rg|ag)
            io_level="medium"
            [[ "$command" == *"-r"* ]] && io_level="high"
            ;;
        du|df)
            io_level="medium"
            [[ "$command" == *"/"[[:space:]]* ]] && time_estimate="minutes"
            ;;
        rm)
            io_level="medium"
            [[ "$command" == *"-r"* ]] && io_level="high"
            ;;
        tar|zip|gzip)
            io_level="high"
            cpu_level="medium"
            time_estimate="minutes"
            ;;
        gcc|make|npm|yarn|pip)
            io_level="high"
            cpu_level="high"
            time_estimate="minutes"
            ;;
        curl|wget)
            io_level="medium"
            time_estimate="variable (network dependent)"
            notes+=("depends on network speed and file size")
            ;;
        *)
            io_level="low"
            cpu_level="low"
            time_estimate="seconds"
            ;;
    esac

    if [[ $json_output -eq 1 ]]; then
        local notes_json escaped_cmd
        escaped_cmd=$(_intent_escape_json "$command")
        notes_json=$(_intent_array_to_json "${notes[@]}")
        printf '{"command":"%s","io_level":"%s","cpu_level":"%s","time_estimate":"%s","notes":%s}\n' \
            "$escaped_cmd" "$io_level" "$cpu_level" "$time_estimate" "$notes_json"
    else
        printf 'Cost Estimate for: %s\n' "$command"
        printf '  I/O Level: %s\n' "$io_level"
        printf '  CPU Level: %s\n' "$cpu_level"
        printf '  Time: %s\n' "$time_estimate"
        for note in "${notes[@]}"; do
            printf '  Note: %s\n' "$note"
        done
    fi

    return 0
}

# intent_suggest_safer - Suggest safer alternatives to a risky command
# @description Analyze command and suggest safer ways to achieve same goal
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      $1 command - Original command
# @param      --json - Output as JSON array
# @stdout     List of safer alternative commands
# @return     0 if alternatives found, 1 if command is already safe, 2 if no alternatives
#
# Usage: intent_suggest_safer "rm -rf /"
# Usage: intent_suggest_safer "chmod 777 /etc" --json
intent_suggest_safer() {
    local command="$1"
    local json_output=0
    [[ "$2" == "--json" ]] && json_output=1

    local risk
    risk=$(_intent_classify_risk "$command")

    # Already safe
    if [[ $risk -eq $INTENT_RISK_SAFE ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"already_safe":true,"alternatives":[]}\n'
        else
            printf 'Command is already safe (risk level: safe)\n'
        fi
        return 1
    fi

    local -a alternatives=()
    local base_cmd="${command%% *}"

    case "$base_cmd" in
        rm)
            if [[ "$command" == *"-rf"* ]]; then
                alternatives+=("Use 'rm -ri' for interactive confirmation")
                alternatives+=("Use 'trash-put' or 'gio trash' to move to trash instead")
                alternatives+=("Use 'find ... -delete' with specific patterns")
            fi
            alternatives+=("Create a backup first: cp -r <target> <target>.bak")
            alternatives+=("Use version control for important files")
            ;;
        chmod)
            if [[ "$command" =~ 777 ]]; then
                alternatives+=("Use 755 for directories (rwxr-xr-x)")
                alternatives+=("Use 644 for files (rw-r--r--)")
                alternatives+=("Use 700/600 for private files")
            fi
            if [[ "$command" == *"-R"* ]]; then
                alternatives+=("Apply permissions to specific files, not recursively")
                alternatives+=("Use find with -exec chmod for granular control")
            fi
            ;;
        chown)
            if [[ "$command" == *"-R"* ]]; then
                alternatives+=("Apply ownership to specific files, not recursively")
                alternatives+=("Verify target path before recursive operation")
            fi
            ;;
        curl|wget)
            if [[ "$command" == *"|"*"bash"* ]] || [[ "$command" == *"|"*"sh"* ]]; then
                alternatives+=("Download script first, review, then execute")
                alternatives+=("Verify script checksum before execution")
                alternatives+=("Use official package managers when available")
            fi
            ;;
        sudo)
            alternatives+=("Use 'sudo -l' to check permissions first")
            alternatives+=("Use specific sudo rules in /etc/sudoers.d/")
            alternatives+=("Consider using capabilities instead of full sudo")
            ;;
        kill)
            if [[ "$command" == *"-9"* ]]; then
                alternatives+=("Try SIGTERM (kill without -9) first")
                alternatives+=("Use pkill with specific pattern")
            fi
            ;;
    esac

    # Generic suggestions for high-risk commands
    if [[ $risk -ge $INTENT_RISK_HIGH ]] && [[ ${#alternatives[@]} -eq 0 ]]; then
        alternatives+=("Run in dry-run mode first if available")
        alternatives+=("Create checkpoint/backup before execution")
        alternatives+=("Test on non-production data first")
    fi

    if [[ ${#alternatives[@]} -eq 0 ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"alternatives":[],"message":"no specific alternatives found"}\n'
        else
            printf 'No specific safer alternatives found\n'
        fi
        return 2
    fi

    if [[ $json_output -eq 1 ]]; then
        local alt_json
        alt_json=$(_intent_array_to_json "${alternatives[@]}")
        printf '{"risk":%d,"alternatives":%s}\n' "$risk" "$alt_json"
    else
        printf 'Current Risk Level: %s\n' "${_INTENT_RISK_LABELS[$risk]}"
        printf 'Safer Alternatives:\n'
        for alt in "${alternatives[@]}"; do
            printf '  - %s\n' "$alt"
        done
    fi

    return 0
}

# intent_batch_verify - Verify multiple commands in a batch
# @description Analyze multiple commands and return aggregate safety assessment
# @pre        None
# @post       None (analysis only)
# @idempotent Yes
# @param      commands - Commands to verify (one per line on stdin or as arguments)
# @param      --json - Output as JSON
# @param      --stop-on-critical - Stop processing if critical risk found
# @stdout     Batch verification results
# @return     Highest risk level found
#
# Usage: echo -e "ls -la\nrm -rf /tmp" | intent_batch_verify
# Usage: intent_batch_verify "ls -la" "rm -rf /tmp" --json
intent_batch_verify() {
    local -a commands=()
    local json_output=0 stop_on_critical=0

    # Parse options and collect commands
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --stop-on-critical) stop_on_critical=1; shift ;;
            *) commands+=("$1"); shift ;;
        esac
    done

    # Read from stdin if no commands provided
    if [[ ${#commands[@]} -eq 0 ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && commands+=("$line")
        done
    fi

    local max_risk=0
    local -a results=()
    local safe_count=0 low_count=0 medium_count=0 high_count=0 critical_count=0

    for cmd in "${commands[@]}"; do
        local risk
        risk=$(_intent_classify_risk "$cmd")

        (( risk > max_risk )) && max_risk=$risk

        case $risk in
            $INTENT_RISK_SAFE) ((safe_count++)) ;;
            $INTENT_RISK_LOW) ((low_count++)) ;;
            $INTENT_RISK_MEDIUM) ((medium_count++)) ;;
            $INTENT_RISK_HIGH) ((high_count++)) ;;
            $INTENT_RISK_CRITICAL) ((critical_count++)) ;;
        esac

        if [[ $json_output -eq 1 ]]; then
            local escaped_cmd
            escaped_cmd=$(_intent_escape_json "$cmd")
            results+=("{\"command\":\"$escaped_cmd\",\"risk\":$risk,\"risk_label\":\"${_INTENT_RISK_LABELS[$risk]}\"}")
        fi

        if [[ $stop_on_critical -eq 1 ]] && [[ $risk -eq $INTENT_RISK_CRITICAL ]]; then
            break
        fi
    done

    local total=${#commands[@]}

    if [[ $json_output -eq 1 ]]; then
        local results_json
        local IFS=','
        results_json="[${results[*]}]"
        printf '{"total":%d,"max_risk":%d,"max_risk_label":"%s","summary":{"safe":%d,"low":%d,"medium":%d,"high":%d,"critical":%d},"results":%s}\n' \
            "$total" "$max_risk" "${_INTENT_RISK_LABELS[$max_risk]}" \
            "$safe_count" "$low_count" "$medium_count" "$high_count" "$critical_count" \
            "$results_json"
    else
        printf 'Batch Verification Summary:\n'
        printf '  Total Commands: %d\n' "$total"
        printf '  Maximum Risk: %s (%d)\n' "${_INTENT_RISK_LABELS[$max_risk]}" "$max_risk"
        printf '  Breakdown:\n'
        printf '    Safe: %d\n' "$safe_count"
        printf '    Low: %d\n' "$low_count"
        printf '    Medium: %d\n' "$medium_count"
        printf '    High: %d\n' "$high_count"
        printf '    Critical: %d\n' "$critical_count"
    fi

    return $max_risk
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

declare -ga _INTENT_EXPORTS=(
    intent_parse
    intent_to_bash
    intent_explain
    intent_complete
    intent_classify
    intent_verify
    intent_sandbox_recommend
    intent_dry_run
    intent_estimate_cost
    intent_suggest_safer
    intent_batch_verify
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_INTENT_EXPORTS[@]}" 2>/dev/null || true
fi

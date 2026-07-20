#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/codesearch.sh - Semantic Code Search (regex-based)
# =============================================================================
# Description: Pattern-based code search for AI agents without full AST parsing.
#              Uses regex patterns optimized for common programming languages.
# Version: 1.0.0
# Requires: Bash 4.0+
# Security: See v6.0-SECURITY-REVIEW.md Section 2 for threat model
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CODESEARCH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CODESEARCH_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Maximum results to return (prevent resource exhaustion)
MAINFRAME_CODESEARCH_MAX_RESULTS="${MAINFRAME_CODESEARCH_MAX_RESULTS:-100}"

# Context lines around matches
MAINFRAME_CODESEARCH_CONTEXT_LINES="${MAINFRAME_CODESEARCH_CONTEXT_LINES:-2}"

# Search timeout in seconds
MAINFRAME_CODESEARCH_TIMEOUT="${MAINFRAME_CODESEARCH_TIMEOUT:-30}"

# Maximum files to search
MAINFRAME_CODESEARCH_MAX_FILES="${MAINFRAME_CODESEARCH_MAX_FILES:-10000}"

# Safe base directory (defaults to PWD, can be overridden)
MAINFRAME_CODESEARCH_SAFE_BASE="${MAINFRAME_CODESEARCH_SAFE_BASE:-}"

# =============================================================================
# LANGUAGE PATTERNS
# =============================================================================

# File extension to language mapping
declare -gA _CODESEARCH_EXTENSIONS=(
    # JavaScript/TypeScript
    [js]="javascript"
    [mjs]="javascript"
    [cjs]="javascript"
    [jsx]="javascript"
    [ts]="typescript"
    [tsx]="typescript"
    [mts]="typescript"
    [cts]="typescript"
    # Python
    [py]="python"
    [pyw]="python"
    [pyi]="python"
    # Go
    [go]="go"
    # Rust
    [rs]="rust"
    # C/C++
    [c]="c"
    [h]="c"
    [cpp]="cpp"
    [cc]="cpp"
    [cxx]="cpp"
    [hpp]="cpp"
    [hh]="cpp"
    [hxx]="cpp"
    # Java
    [java]="java"
    # Bash/Shell
    [sh]="bash"
    [bash]="bash"
    [zsh]="bash"
    # Ruby
    [rb]="ruby"
    # PHP
    [php]="php"
    # Swift
    [swift]="swift"
    # Kotlin
    [kt]="kotlin"
    [kts]="kotlin"
)

# Function definition patterns by language
# Note: These are simplified regex patterns - ~90% accuracy is acceptable
declare -gA _CODESEARCH_FUNC_PATTERNS=(
    # Python: def func_name(...) or async def func_name(...)
    [python]='^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\('

    # JavaScript: function name(...), async function name(...), name = function, name = (...) =>
    [javascript]='^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?)?(async[[:space:]]+)?function[[:space:]]*([a-zA-Z_$][a-zA-Z0-9_$]*)?[[:space:]]*\('

    # TypeScript: same as JavaScript with type annotations
    [typescript]='^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?)?(async[[:space:]]+)?function[[:space:]]*([a-zA-Z_$][a-zA-Z0-9_$]*)?[[:space:]]*[<(]'

    # Go: func Name(...) or func (r Receiver) Name(...)
    [go]='^func[[:space:]]+(\([^)]*\)[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\('

    # Rust: fn name(...) or pub fn name(...) or async fn name(...)
    [rust]='^[[:space:]]*(pub[[:space:]]+)?(async[[:space:]]+)?fn[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*[<(]'

    # C/C++: type name(...) - simplified
    [c]='^[[:space:]]*(static[[:space:]]+)?(inline[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_*[:space:]]+)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\('
    [cpp]='^[[:space:]]*(virtual[[:space:]]+)?(static[[:space:]]+)?(inline[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_*[:space:]<>:]+)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\('

    # Java: modifiers type name(...)
    [java]='^[[:space:]]*(public|private|protected)?[[:space:]]*(static[[:space:]]+)?(final[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_<>,[:space:]]*)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\('

    # Bash: function name() or name()
    [bash]='^[[:space:]]*(function[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{'

    # Ruby: def name or def self.name
    [ruby]='^[[:space:]]*(def[[:space:]]+)(self\.)?([a-zA-Z_][a-zA-Z0-9_!?=]*)'

    # PHP: function name(...) or public function name(...)
    [php]='^[[:space:]]*(public|private|protected)?[[:space:]]*(static[[:space:]]+)?function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\('

    # Swift: func name(...) or class func name(...)
    [swift]='^[[:space:]]*(public|private|internal|fileprivate|open)?[[:space:]]*(class[[:space:]]+|static[[:space:]]+)?(override[[:space:]]+)?func[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*[<(]'

    # Kotlin: fun name(...) or suspend fun name(...)
    [kotlin]='^[[:space:]]*(public|private|protected|internal)?[[:space:]]*(suspend[[:space:]]+)?fun[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*[<(]'
)

# Class/struct definition patterns
declare -gA _CODESEARCH_CLASS_PATTERNS=(
    [python]='^[[:space:]]*(class[[:space:]]+)([a-zA-Z_][a-zA-Z0-9_]*)([[:space:]]*\(|[[:space:]]*:)'
    [javascript]='^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?)?class[[:space:]]+([a-zA-Z_$][a-zA-Z0-9_$]*)'
    [typescript]='^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?)?(abstract[[:space:]]+)?class[[:space:]]+([a-zA-Z_$][a-zA-Z0-9_$]*)'
    [go]='^type[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+struct[[:space:]]*\{'
    [rust]='^[[:space:]]*(pub[[:space:]]+)?struct[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*[<{(]?'
    [java]='^[[:space:]]*(public[[:space:]]+)?(abstract[[:space:]]+)?(final[[:space:]]+)?class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
    [cpp]='^[[:space:]]*(class|struct)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
    [c]='^[[:space:]]*(typedef[[:space:]]+)?struct[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)?[[:space:]]*\{'
    [ruby]='^[[:space:]]*(class[[:space:]]+)([A-Z][a-zA-Z0-9_]*)'
    [php]='^[[:space:]]*(abstract[[:space:]]+)?(final[[:space:]]+)?class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
    [swift]='^[[:space:]]*(public|private|internal|fileprivate|open)?[[:space:]]*(final[[:space:]]+)?class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
    [kotlin]='^[[:space:]]*(public|private|protected|internal)?[[:space:]]*(data[[:space:]]+|sealed[[:space:]]+|open[[:space:]]+)?class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
)

# Interface/protocol definition patterns
declare -gA _CODESEARCH_INTERFACE_PATTERNS=(
    [typescript]='^[[:space:]]*(export[[:space:]]+)?interface[[:space:]]+([a-zA-Z_$][a-zA-Z0-9_$]*)'
    [go]='^type[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+interface[[:space:]]*\{'
    [rust]='^[[:space:]]*(pub[[:space:]]+)?trait[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
    [java]='^[[:space:]]*(public[[:space:]]+)?interface[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
    [php]='^[[:space:]]*(interface[[:space:]]+)([a-zA-Z_][a-zA-Z0-9_]*)'
    [swift]='^[[:space:]]*(public|private|internal)?[[:space:]]*protocol[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
    [kotlin]='^[[:space:]]*(public|private|protected|internal)?[[:space:]]*(sealed[[:space:]]+)?interface[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)'
)

# Constant/readonly patterns
declare -gA _CODESEARCH_CONST_PATTERNS=(
    [python]='^([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]'
    [javascript]='^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+([A-Z][A-Z0-9_]*)[[:space:]]*='
    [typescript]='^[[:space:]]*(export[[:space:]]+)?(const|readonly)[[:space:]]+([a-zA-Z_$][a-zA-Z0-9_$]*)[[:space:]]*[:=]'
    [go]='^const[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*='
    [rust]='^[[:space:]]*(pub[[:space:]]+)?const[[:space:]]+([A-Z][A-Z0-9_]*)[[:space:]]*:'
    [java]='^[[:space:]]*(public|private|protected)?[[:space:]]*(static[[:space:]]+)?final[[:space:]]+([A-Za-z_][A-Za-z0-9_<>]*)[[:space:]]+([A-Z][A-Z0-9_]*)'
    [bash]='^[[:space:]]*(readonly|declare[[:space:]]+-r)[[:space:]]+([A-Z][A-Z0-9_]*)='
    [php]='^[[:space:]]*(const|define\()[[:space:]]*['\''"]?([A-Z][A-Z0-9_]*)'
)

# Import/require patterns
declare -gA _CODESEARCH_IMPORT_PATTERNS=(
    [python]='^[[:space:]]*(from[[:space:]]+[a-zA-Z0-9_.]+[[:space:]]+)?import[[:space:]]+'
    [javascript]='^[[:space:]]*(import[[:space:]]+.*from|require[[:space:]]*\()'
    [typescript]='^[[:space:]]*(import[[:space:]]+.*from|import[[:space:]]+type)'
    [go]='^[[:space:]]*(import[[:space:]]+[("]])'
    [rust]='^[[:space:]]*(use[[:space:]]+|extern[[:space:]]+crate[[:space:]]+)'
    [java]='^[[:space:]]*import[[:space:]]+([a-zA-Z0-9_.]+;)'
    [php]='^[[:space:]]*(use[[:space:]]+|require(_once)?[[:space:]]*\(|include(_once)?[[:space:]]*\()'
    [ruby]='^[[:space:]]*(require[[:space:]]+|require_relative[[:space:]]+|load[[:space:]]+)'
    [swift]='^[[:space:]]*import[[:space:]]+([a-zA-Z_][a-zA-Z0-9_.]*)'
    [kotlin]='^[[:space:]]*import[[:space:]]+([a-zA-Z_][a-zA-Z0-9_.]*)'
)

# Export patterns
declare -gA _CODESEARCH_EXPORT_PATTERNS=(
    [javascript]='^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?(const|let|var|function|class|interface|type|enum)[[:space:]]+|module\.exports[[:space:]]*=)'
    [typescript]='^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?(const|let|var|function|class|interface|type|enum)[[:space:]]+|export[[:space:]]*\{)'
    [python]='^[[:space:]]*__all__[[:space:]]*='
    [go]='^(func|type|var|const)[[:space:]]+[A-Z]'
    [rust]='^[[:space:]]*pub[[:space:]]+(fn|struct|enum|trait|type|const|mod)[[:space:]]+'
)

# Sensitive file patterns to exclude from search results (security)
declare -ga _CODESEARCH_SENSITIVE_PATTERNS=(
    "*.env"
    "*.env.*"
    "*.pem"
    "*.key"
    "*.p12"
    "*.pfx"
    "*credentials*"
    "*secret*"
    ".git/config"
    ".netrc"
    "*id_rsa*"
    "*id_ed25519*"
    "*_rsa"
    "*.ssh/*"
)

# Directories to exclude from search
declare -ga _CODESEARCH_EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    ".venv"
    "venv"
    "__pycache__"
    ".pytest_cache"
    "target"
    "dist"
    "build"
    ".next"
    ".nuxt"
    "vendor"
    ".cargo"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON string escaping
_codesearch_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"       # Escape backslashes first
    str="${str//\"/\\\"}"       # Escape quotes
    str="${str//$'\n'/\\n}"     # Escape newlines
    str="${str//$'\r'/\\r}"     # Escape carriage returns
    str="${str//$'\t'/\\t}"     # Escape tabs
    # Escape control characters
    local i char result=""
    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        if [[ "$char" < $'\x20' && "$char" != $'\n' && "$char" != $'\r' && "$char" != $'\t' ]]; then
            printf -v char '\\u%04x' "'$char"
        fi
        result+="$char"
    done
    printf '%s' "$result"
}

# Build JSON array from arguments
_codesearch_json_array() {
    local result="["
    local first=true
    local item
    for item in "$@"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi
        result+="\"$(_codesearch_escape_json "$item")\""
    done
    result+="]"
    printf '%s' "$result"
}

# Log function (uses MAINFRAME log_* if available)
_codesearch_log() {
    local level="$1"
    shift
    if declare -F "log_${level}" &>/dev/null; then
        "log_${level}" "[codesearch] $*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[codesearch] %s: %s\n' "${level}" "$*" >&2
    fi
}

_codesearch_run_with_timeout() {
    local duration="$1"
    shift

    if command -v timeout &>/dev/null; then
        timeout "$duration" "$@"
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$duration" "$@"
    else
        "$@"
    fi
}

# Validate search path against safe base (security: prevent path traversal)
_codesearch_validate_path() {
    local search_path="$1"
    local safe_base="${MAINFRAME_CODESEARCH_SAFE_BASE:-${AGENT_SAFE_BASE:-$PWD}}"

    # Normalize paths
    local abs_search abs_base
    abs_search=$(cd "$(dirname "$search_path")" 2>/dev/null && pwd)/$(basename "$search_path") 2>/dev/null
    if [[ -z "$abs_search" ]]; then
        abs_search=$(realpath -m "$search_path" 2>/dev/null) || {
            printf '{"error":"invalid_path","message":"Cannot resolve search path"}\n' >&2
            return 1
        }
    fi

    abs_base=$(cd "$safe_base" 2>/dev/null && pwd) || abs_base="$safe_base"

    # Verify search path is within safe base
    if [[ "$abs_search" != "$abs_base"* ]]; then
        printf '{"error":"path_traversal","message":"Search path outside allowed directory","path":"%s","allowed_base":"%s"}\n' \
            "$(_codesearch_escape_json "$abs_search")" "$(_codesearch_escape_json "$abs_base")" >&2
        return 1
    fi

    return 0
}

# Validate pattern for injection attacks (security)
_codesearch_validate_pattern() {
    local pattern="$1"

    # Reject shell metacharacters
    if [[ "$pattern" == *'$('* || "$pattern" == *'`'* ]]; then
        printf '{"error":"pattern_injection","message":"Shell metacharacters in pattern"}\n' >&2
        return 1
    fi

    # Length limit
    if (( ${#pattern} > 1000 )); then
        printf '{"error":"pattern_too_long","message":"Pattern exceeds 1000 characters"}\n' >&2
        return 1
    fi

    return 0
}

# Check if file is sensitive (should be excluded)
_codesearch_is_sensitive() {
    local filepath="$1"
    local basename="${filepath##*/}"
    local pattern

    for pattern in "${_CODESEARCH_SENSITIVE_PATTERNS[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$basename" == $pattern ]] || [[ "$filepath" == *"$pattern"* ]]; then
            return 0  # Is sensitive
        fi
    done

    return 1  # Not sensitive
}

# Build find exclude arguments
_codesearch_build_excludes() {
    local -a args=()
    local dir pattern

    # Exclude directories
    for dir in "${_CODESEARCH_EXCLUDE_DIRS[@]}"; do
        args+=(-path "*/$dir" -prune -o)
    done

    # Exclude sensitive files
    for pattern in "${_CODESEARCH_SENSITIVE_PATTERNS[@]}"; do
        args+=(-name "$pattern" -prune -o)
    done

    printf '%s\n' "${args[@]}"
}

# Build grep include arguments for language filter
_codesearch_lang_extensions() {
    local lang="$1"
    local -a exts=()
    local ext

    for ext in "${!_CODESEARCH_EXTENSIONS[@]}"; do
        if [[ "${_CODESEARCH_EXTENSIONS[$ext]}" == "$lang" ]]; then
            exts+=("$ext")
        fi
    done

    printf '%s\n' "${exts[@]}"
}

# =============================================================================
# PUBLIC API - Language Detection
# =============================================================================

# code_detect_lang - Detect programming language of a file
# @pre: File exists or path provided
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 filepath - Path to file
# @stdout: Language name (lowercase) or "unknown"
# @return: 0 on success, 1 if file not found
#
# Usage: lang=$(code_detect_lang "main.py")  # python
# Usage: lang=$(code_detect_lang "App.tsx")  # typescript
code_detect_lang() {
    local filepath="$1"

    [[ -z "$filepath" ]] && { printf 'unknown'; return 1; }

    # Get extension
    local ext="${filepath##*.}"
    ext="${ext,,}"  # lowercase

    # Lookup in extension map
    if [[ -n "${_CODESEARCH_EXTENSIONS[$ext]:-}" ]]; then
        printf '%s' "${_CODESEARCH_EXTENSIONS[$ext]}"
        return 0
    fi

    # Fallback: check shebang for scripts without extension
    if [[ -f "$filepath" && -r "$filepath" ]]; then
        local shebang
        shebang=$(head -1 "$filepath" 2>/dev/null)
        case "$shebang" in
            *python*) printf 'python'; return 0 ;;
            *bash*|*/sh) printf 'bash'; return 0 ;;
            *node*) printf 'javascript'; return 0 ;;
            *ruby*) printf 'ruby'; return 0 ;;
            *perl*) printf 'perl'; return 0 ;;
        esac
    fi

    printf 'unknown'
    return 1
}

# =============================================================================
# PUBLIC API - Function Search
# =============================================================================

# code_find_functions - Find function/method definitions in source files
# @pre: Directory/file exists and is readable
# @post: None (read-only search)
# @idempotent: Yes
# @param: $1 path - File or directory to search
# @param: --lang - Language filter: python|javascript|typescript|bash|go|rust|c|cpp|java
# @param: --name - Function name pattern (regex)
# @param: --exported - Only exported/public functions
# @param: --json - Output as JSON array
# @param: --context - Include N lines of context (default: 0)
# @stdout: Matched functions with file:line:name format or JSON
# @return: 0 on success, 1 if path not found, 2 if no matches
#
# Usage: code_find_functions "src/" --lang python
# Usage: code_find_functions "src/" --lang javascript --name "^handle" --json
code_find_functions() {
    local path="$1"
    shift || { printf '{"error":"no_path","message":"Path argument required"}\n' >&2; return 1; }

    local lang="" name_pattern="" json_output=0 context=0 exported_only=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --name) name_pattern="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            --context) context="$2"; shift 2 ;;
            --exported) exported_only=1; shift ;;
            *) shift ;;
        esac
    done

    # Validate path
    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found","path":"%s"}\n' "$(_codesearch_escape_json "$path")" >&2; return 1; }

    # Security: validate path is within allowed scope
    _codesearch_validate_path "$path" || return 1

    # Security: validate name pattern
    [[ -n "$name_pattern" ]] && { _codesearch_validate_pattern "$name_pattern" || return 1; }

    local -a results=()
    local count=0

    # Find files to search
    local -a files=()
    if [[ -f "$path" ]]; then
        files=("$path")
    else
        # Build find command with excludes
        local find_cmd="find '$path' -type f"
        for dir in "${_CODESEARCH_EXCLUDE_DIRS[@]}"; do
            find_cmd+=" -not -path '*/$dir/*'"
        done

        # Add language extension filter if specified
        if [[ -n "$lang" ]]; then
            local exts
            exts=$(_codesearch_lang_extensions "$lang")
            if [[ -n "$exts" ]]; then
                local ext_filter=""
                while IFS= read -r ext; do
                    [[ -n "$ext" ]] && ext_filter+=" -name '*.$ext' -o"
                done <<< "$exts"
                ext_filter="${ext_filter% -o}"
                find_cmd+=" \\( $ext_filter \\)"
            fi
        fi

        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && files+=("$f")
        done < <(eval "$find_cmd" 2>/dev/null | head -n "$MAINFRAME_CODESEARCH_MAX_FILES")
    fi

    # Search each file
    local file
    for file in "${files[@]}"; do
        # Skip sensitive files
        _codesearch_is_sensitive "$file" && continue

        local file_lang
        file_lang=$(code_detect_lang "$file")

        # Skip if language filter doesn't match
        [[ -n "$lang" && "$file_lang" != "$lang" ]] && continue
        [[ "$file_lang" == "unknown" ]] && continue

        local pattern="${_CODESEARCH_FUNC_PATTERNS[$file_lang]:-}"
        [[ -z "$pattern" ]] && continue

        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))

            if [[ "$line" =~ $pattern ]]; then
                # Extract function name from match groups
                local func_name=""
                local i
                local -a captures=("${BASH_REMATCH[@]}")
                for ((i=${#captures[@]}-1; i>=1; i--)); do
                    local match="${captures[$i]}"
                    # Look for identifier-like strings
                    if [[ -n "$match" && "$match" =~ ^[a-zA-Z_$][a-zA-Z0-9_$]*$ ]]; then
                        # Skip common keywords
                        case "$match" in
                            async|function|def|class|export|public|private|protected|static|const|let|var|fn|pub|func|override|suspend|abstract|final|virtual|inline|readonly) continue ;;
                        esac
                        func_name="$match"
                        break
                    fi
                done

                [[ -z "$func_name" ]] && continue

                # Apply name pattern filter
                if [[ -n "$name_pattern" ]]; then
                    [[ ! "$func_name" =~ $name_pattern ]] && continue
                fi

                # Check exported filter
                if [[ $exported_only -eq 1 ]]; then
                    case "$file_lang" in
                        python)
                            # Python: no underscore prefix = public
                            [[ "$func_name" == _* ]] && continue
                            ;;
                        go)
                            # Go: uppercase first letter = exported
                            [[ ! "$func_name" =~ ^[A-Z] ]] && continue
                            ;;
                        javascript|typescript)
                            # JS/TS: check for export keyword
                            [[ ! "$line" =~ ^[[:space:]]*(export|module\.exports) ]] && continue
                            ;;
                        rust)
                            # Rust: check for pub keyword
                            [[ ! "$line" =~ ^[[:space:]]*pub[[:space:]] ]] && continue
                            ;;
                    esac
                fi

                if [[ $json_output -eq 1 ]]; then
                    local escaped_file escaped_name escaped_line
                    escaped_file=$(_codesearch_escape_json "$file")
                    escaped_name=$(_codesearch_escape_json "$func_name")
                    escaped_line=$(_codesearch_escape_json "$line")
                    results+=("{\"file\":\"$escaped_file\",\"line\":$line_num,\"name\":\"$escaped_name\",\"lang\":\"$file_lang\",\"code\":\"$escaped_line\"}")
                else
                    printf '%s:%d:%s\n' "$file" "$line_num" "$func_name"
                fi

                count=$((count + 1))
                [[ $count -ge $MAINFRAME_CODESEARCH_MAX_RESULTS ]] && break 2
            fi
        done < "$file"
    done

    [[ $count -eq 0 ]] && return 2

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${results[*]}")"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Class Search
# =============================================================================

# code_find_classes - Find class/struct/type definitions
# @pre: Directory/file exists
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 path - File or directory to search
# @param: --lang - Language filter
# @param: --name - Class name pattern (regex)
# @param: --json - Output as JSON array
# @stdout: Matched classes: file:line:type:name
# @return: 0 on success, 1 if path not found
#
# Usage: code_find_classes "src/" --lang typescript
# Usage: code_find_classes "models.py" --lang python --name "User"
code_find_classes() {
    local path="$1"
    shift || { printf '{"error":"no_path","message":"Path argument required"}\n' >&2; return 1; }

    local lang="" name_pattern="" json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --name) name_pattern="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found","path":"%s"}\n' "$(_codesearch_escape_json "$path")" >&2; return 1; }
    _codesearch_validate_path "$path" || return 1
    [[ -n "$name_pattern" ]] && { _codesearch_validate_pattern "$name_pattern" || return 1; }

    local -a results=()
    local count=0

    local -a files=()
    if [[ -f "$path" ]]; then
        files=("$path")
    else
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && files+=("$f")
        done < <(find "$path" -type f \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/target/*' \
            -not -path '*/__pycache__/*' \
            2>/dev/null | head -n "$MAINFRAME_CODESEARCH_MAX_FILES")
    fi

    local file
    for file in "${files[@]}"; do
        _codesearch_is_sensitive "$file" && continue

        local file_lang
        file_lang=$(code_detect_lang "$file")
        [[ -n "$lang" && "$file_lang" != "$lang" ]] && continue
        [[ "$file_lang" == "unknown" ]] && continue

        local pattern="${_CODESEARCH_CLASS_PATTERNS[$file_lang]:-}"
        [[ -z "$pattern" ]] && continue

        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))

            if [[ "$line" =~ $pattern ]]; then
                local class_name=""
                local class_type="class"
                local i
                local -a captures=("${BASH_REMATCH[@]}")

                # Determine type (struct vs class)
                [[ "$line" =~ struct ]] && class_type="struct"
                [[ "$line" =~ type.*struct ]] && class_type="struct"

                for ((i=${#captures[@]}-1; i>=1; i--)); do
                    local match="${captures[$i]}"
                    if [[ -n "$match" && "$match" =~ ^[a-zA-Z_$][a-zA-Z0-9_$]*$ ]]; then
                        case "$match" in
                            class|struct|type|export|public|private|abstract|final|sealed|data|open|internal) continue ;;
                        esac
                        class_name="$match"
                        break
                    fi
                done

                [[ -z "$class_name" ]] && continue

                if [[ -n "$name_pattern" ]]; then
                    [[ ! "$class_name" =~ $name_pattern ]] && continue
                fi

                if [[ $json_output -eq 1 ]]; then
                    local escaped_file escaped_name
                    escaped_file=$(_codesearch_escape_json "$file")
                    escaped_name=$(_codesearch_escape_json "$class_name")
                    results+=("{\"file\":\"$escaped_file\",\"line\":$line_num,\"name\":\"$escaped_name\",\"type\":\"$class_type\",\"lang\":\"$file_lang\"}")
                else
                    printf '%s:%d:%s:%s\n' "$file" "$line_num" "$class_type" "$class_name"
                fi

                count=$((count + 1))
                [[ $count -ge $MAINFRAME_CODESEARCH_MAX_RESULTS ]] && break 2
            fi
        done < "$file"
    done

    [[ $count -eq 0 ]] && return 2

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${results[*]}")"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Interface Search
# =============================================================================

# code_find_interfaces - Find interface/trait/protocol definitions
# @pre: Directory/file exists
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 path - File or directory to search
# @param: --lang - Language filter
# @param: --name - Interface name pattern (regex)
# @param: --json - Output as JSON array
# @stdout: Matched interfaces: file:line:name
# @return: 0 on success, 1 if path not found, 2 if no matches
#
# Usage: code_find_interfaces "src/" --lang typescript
# Usage: code_find_interfaces "src/" --lang rust --json
code_find_interfaces() {
    local path="$1"
    shift || { printf '{"error":"no_path","message":"Path argument required"}\n' >&2; return 1; }

    local lang="" name_pattern="" json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --name) name_pattern="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$path" || return 1
    [[ -n "$name_pattern" ]] && { _codesearch_validate_pattern "$name_pattern" || return 1; }

    local -a results=()
    local count=0

    local -a files=()
    if [[ -f "$path" ]]; then
        files=("$path")
    else
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && files+=("$f")
        done < <(find "$path" -type f \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            2>/dev/null | head -n "$MAINFRAME_CODESEARCH_MAX_FILES")
    fi

    local file
    for file in "${files[@]}"; do
        _codesearch_is_sensitive "$file" && continue

        local file_lang
        file_lang=$(code_detect_lang "$file")
        [[ -n "$lang" && "$file_lang" != "$lang" ]] && continue

        local pattern="${_CODESEARCH_INTERFACE_PATTERNS[$file_lang]:-}"
        [[ -z "$pattern" ]] && continue

        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))

            if [[ "$line" =~ $pattern ]]; then
                local iface_name=""
                local i
                local -a captures=("${BASH_REMATCH[@]}")

                for ((i=${#captures[@]}-1; i>=1; i--)); do
                    local match="${captures[$i]}"
                    if [[ -n "$match" && "$match" =~ ^[a-zA-Z_$][a-zA-Z0-9_$]*$ ]]; then
                        case "$match" in
                            interface|trait|protocol|export|public|private|sealed|internal) continue ;;
                        esac
                        iface_name="$match"
                        break
                    fi
                done

                [[ -z "$iface_name" ]] && continue

                if [[ -n "$name_pattern" ]]; then
                    [[ ! "$iface_name" =~ $name_pattern ]] && continue
                fi

                if [[ $json_output -eq 1 ]]; then
                    local escaped_file escaped_name
                    escaped_file=$(_codesearch_escape_json "$file")
                    escaped_name=$(_codesearch_escape_json "$iface_name")
                    results+=("{\"file\":\"$escaped_file\",\"line\":$line_num,\"name\":\"$escaped_name\",\"lang\":\"$file_lang\"}")
                else
                    printf '%s:%d:%s\n' "$file" "$line_num" "$iface_name"
                fi

                count=$((count + 1))
                [[ $count -ge $MAINFRAME_CODESEARCH_MAX_RESULTS ]] && break 2
            fi
        done < "$file"
    done

    [[ $count -eq 0 ]] && return 2

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${results[*]}")"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Constants Search
# =============================================================================

# code_find_constants - Find const/readonly declarations
# @pre: Directory/file exists
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 path - File or directory to search
# @param: --lang - Language filter
# @param: --name - Constant name pattern (regex)
# @param: --json - Output as JSON array
# @stdout: Matched constants: file:line:name
# @return: 0 on success, 1 if path not found, 2 if no matches
#
# Usage: code_find_constants "src/" --lang python
# Usage: code_find_constants "config.ts" --lang typescript --json
code_find_constants() {
    local path="$1"
    shift || { printf '{"error":"no_path"}\n' >&2; return 1; }

    local lang="" name_pattern="" json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --name) name_pattern="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$path" || return 1
    [[ -n "$name_pattern" ]] && { _codesearch_validate_pattern "$name_pattern" || return 1; }

    local -a results=()
    local count=0

    local -a files=()
    if [[ -f "$path" ]]; then
        files=("$path")
    else
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && files+=("$f")
        done < <(find "$path" -type f \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            2>/dev/null | head -n "$MAINFRAME_CODESEARCH_MAX_FILES")
    fi

    local file
    for file in "${files[@]}"; do
        _codesearch_is_sensitive "$file" && continue

        local file_lang
        file_lang=$(code_detect_lang "$file")
        [[ -n "$lang" && "$file_lang" != "$lang" ]] && continue

        local pattern="${_CODESEARCH_CONST_PATTERNS[$file_lang]:-}"
        [[ -z "$pattern" ]] && continue

        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))

            if [[ "$line" =~ $pattern ]]; then
                local const_name=""
                local i
                local -a captures=("${BASH_REMATCH[@]}")

                for ((i=${#captures[@]}-1; i>=1; i--)); do
                    local match="${captures[$i]}"
                    if [[ -n "$match" && "$match" =~ ^[A-Za-z_$][A-Za-z0-9_$]*$ ]]; then
                        case "$match" in
                            const|readonly|let|var|final|static|export|public|private|declare) continue ;;
                        esac
                        const_name="$match"
                        break
                    fi
                done

                [[ -z "$const_name" ]] && continue

                if [[ -n "$name_pattern" ]]; then
                    [[ ! "$const_name" =~ $name_pattern ]] && continue
                fi

                if [[ $json_output -eq 1 ]]; then
                    local escaped_file escaped_name
                    escaped_file=$(_codesearch_escape_json "$file")
                    escaped_name=$(_codesearch_escape_json "$const_name")
                    results+=("{\"file\":\"$escaped_file\",\"line\":$line_num,\"name\":\"$escaped_name\",\"lang\":\"$file_lang\"}")
                else
                    printf '%s:%d:%s\n' "$file" "$line_num" "$const_name"
                fi

                count=$((count + 1))
                [[ $count -ge $MAINFRAME_CODESEARCH_MAX_RESULTS ]] && break 2
            fi
        done < "$file"
    done

    [[ $count -eq 0 ]] && return 2

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${results[*]}")"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Caller Search
# =============================================================================

# code_find_callers - Find all call sites of a function/method
# @pre: Directory exists
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 func_name - Function name to find callers of
# @param: $2 path - Directory to search
# @param: --lang - Language filter (improves accuracy)
# @param: --json - Output as JSON array
# @param: --context - Lines of context around match
# @stdout: Call sites: file:line:context
# @return: 0 on success, 1 if no callers found
#
# Usage: code_find_callers "authenticate" "src/"
# Usage: code_find_callers "handleSubmit" "components/" --lang typescript --json
code_find_callers() {
    local func_name="$1"
    local path="$2"
    shift 2 || { printf '{"error":"insufficient_args","message":"Function name and path required"}\n' >&2; return 1; }

    local lang="" json_output=0 context=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            --context) context="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Security: validate inputs
    [[ -z "$func_name" ]] && { printf '{"error":"no_function_name"}\n' >&2; return 1; }
    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$path" || return 1
    _codesearch_validate_pattern "$func_name" || return 1

    # Build call pattern: func_name followed by ( with optional whitespace
    local call_pattern="${func_name}[[:space:]]*\("

    local -a results=()
    local count=0

    # Use grep with excludes
    local grep_opts="-rn"
    [[ $context -gt 0 ]] && grep_opts+=" -C$context"

    # Build exclude patterns for grep
    local -a grep_excludes=()
    for dir in "${_CODESEARCH_EXCLUDE_DIRS[@]}"; do
        grep_excludes+=(--exclude-dir="$dir")
    done
    for pattern in "${_CODESEARCH_SENSITIVE_PATTERNS[@]}"; do
        grep_excludes+=(--exclude="$pattern")
    done

    # Add language extension filter
    local -a include_patterns=()
    if [[ -n "$lang" ]]; then
        local exts
        exts=$(_codesearch_lang_extensions "$lang")
        while IFS= read -r ext; do
            [[ -n "$ext" ]] && include_patterns+=(--include="*.$ext")
        done <<< "$exts"
    fi

    while IFS= read -r match; do
        [[ -z "$match" ]] && continue

        # Skip function definition itself (simple heuristic)
        if [[ "$match" =~ (def|function|fn|func)[[:space:]]+${func_name} ]]; then
            continue
        fi

        if [[ $json_output -eq 1 ]]; then
            # Parse grep output: file:line:content
            local file line content
            file="${match%%:*}"
            local rest="${match#*:}"
            line="${rest%%:*}"
            content="${rest#*:}"

            # Skip sensitive files
            _codesearch_is_sensitive "$file" && continue

            local escaped_file escaped_content
            escaped_file=$(_codesearch_escape_json "$file")
            escaped_content=$(_codesearch_escape_json "$content")
            results+=("{\"file\":\"$escaped_file\",\"line\":$line,\"content\":\"$escaped_content\"}")
        else
            printf '%s\n' "$match"
        fi

        count=$((count + 1))
        [[ $count -ge $MAINFRAME_CODESEARCH_MAX_RESULTS ]] && break
    done < <(_codesearch_run_with_timeout "${MAINFRAME_CODESEARCH_TIMEOUT}s" grep "$grep_opts" "${grep_excludes[@]}" "${include_patterns[@]}" -E "$call_pattern" "$path" 2>/dev/null)

    [[ $count -eq 0 ]] && return 1

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${results[*]}")"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Import/Export Search
# =============================================================================

# code_find_imports - Extract import statements
# @pre: Directory/file exists
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 path - File or directory
# @param: --lang - Language filter
# @param: --module - Filter by module name pattern
# @param: --json - Output as JSON
# @stdout: Import statements: file:line:module:symbols
# @return: 0 on success, 1 if path not found
#
# Usage: code_find_imports "src/" --lang python
# Usage: code_find_imports "src/" --lang typescript --module "react"
code_find_imports() {
    local path="$1"
    shift || { printf '{"error":"no_path"}\n' >&2; return 1; }

    local lang="" module_pattern="" json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --module) module_pattern="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$path" || return 1
    [[ -n "$module_pattern" ]] && { _codesearch_validate_pattern "$module_pattern" || return 1; }

    local -a results=()
    local count=0

    local -a files=()
    if [[ -f "$path" ]]; then
        files=("$path")
    else
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && files+=("$f")
        done < <(find "$path" -type f \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            2>/dev/null | head -n "$MAINFRAME_CODESEARCH_MAX_FILES")
    fi

    local file
    for file in "${files[@]}"; do
        _codesearch_is_sensitive "$file" && continue

        local file_lang
        file_lang=$(code_detect_lang "$file")
        [[ -n "$lang" && "$file_lang" != "$lang" ]] && continue

        local pattern="${_CODESEARCH_IMPORT_PATTERNS[$file_lang]:-}"
        [[ -z "$pattern" ]] && continue

        local line_num=0
        local in_go_import_block=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))

            local module=""
            local matched_import=0
            case "$file_lang" in
                python)
                    if [[ "$line" =~ $pattern ]]; then
                        matched_import=1
                        if [[ "$line" =~ from[[:space:]]+([a-zA-Z0-9_.]+)[[:space:]]+import ]]; then
                            module="${BASH_REMATCH[1]}"
                        elif [[ "$line" =~ import[[:space:]]+([a-zA-Z0-9_.]+) ]]; then
                            module="${BASH_REMATCH[1]}"
                        fi
                    fi
                    ;;
                javascript|typescript)
                    if [[ "$line" =~ $pattern ]]; then
                        matched_import=1
                        if [[ "$line" == *" from '"* ]]; then
                            module="${line#* from \'}"
                            module="${module%%\'*}"
                        elif [[ "$line" == *' from "'* ]]; then
                            module="${line#* from \"}"
                            module="${module%%\"*}"
                        elif [[ "$line" == *"require('"* ]]; then
                            module="${line#*require(\'}"
                            module="${module%%\'*}"
                        elif [[ "$line" == *'require("'* ]]; then
                            module="${line#*require(\"}"
                            module="${module%%\"*}"
                        fi
                    fi
                    ;;
                go)
                    if [[ "$line" =~ ^[[:space:]]*import[[:space:]]*\($ ]]; then
                        in_go_import_block=1
                        continue
                    fi
                    if [[ $in_go_import_block -eq 1 && "$line" =~ ^[[:space:]]*\)[[:space:]]*$ ]]; then
                        in_go_import_block=0
                        continue
                    fi
                    if [[ "$line" =~ ^[[:space:]]*import[[:space:]]+\"([^\"]+)\" ]]; then
                        matched_import=1
                        module="${BASH_REMATCH[1]}"
                    elif [[ $in_go_import_block -eq 1 && "$line" =~ ^[[:space:]]*\"([^\"]+)\" ]]; then
                        matched_import=1
                        module="${BASH_REMATCH[1]}"
                    fi
                    ;;
                rust)
                    if [[ "$line" =~ $pattern ]]; then
                        matched_import=1
                        if [[ "$line" =~ use[[:space:]]+([a-zA-Z0-9_:]+) ]]; then
                            module="${BASH_REMATCH[1]}"
                        fi
                    fi
                    ;;
                *)
                    if [[ "$line" =~ $pattern ]]; then
                        matched_import=1
                        module="$line"
                    fi
                    ;;
            esac

            [[ $matched_import -eq 0 ]] && continue
            [[ -z "$module" ]] && module="(unknown)"

            if [[ -n "$module_pattern" ]]; then
                [[ ! "$module" =~ $module_pattern ]] && continue
            fi

            if [[ $json_output -eq 1 ]]; then
                local escaped_file escaped_module escaped_line
                escaped_file=$(_codesearch_escape_json "$file")
                escaped_module=$(_codesearch_escape_json "$module")
                escaped_line=$(_codesearch_escape_json "$line")
                results+=("{\"file\":\"$escaped_file\",\"line\":$line_num,\"module\":\"$escaped_module\",\"statement\":\"$escaped_line\",\"lang\":\"$file_lang\"}")
            else
                printf '%s:%d:%s\n' "$file" "$line_num" "$module"
            fi

            count=$((count + 1))
            [[ $count -ge $MAINFRAME_CODESEARCH_MAX_RESULTS ]] && break 2
        done < "$file"
    done

    [[ $count -eq 0 ]] && return 2

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${results[*]}")"
    fi

    return 0
}

# code_find_exports - Extract export statements
# @pre: Directory/file exists
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 path - File or directory
# @param: --lang - Language filter
# @param: --json - Output as JSON
# @stdout: Export statements: file:line:export_name
# @return: 0 on success, 1 if path not found, 2 if no matches
#
# Usage: code_find_exports "src/" --lang typescript
# Usage: code_find_exports "lib/" --lang go --json
code_find_exports() {
    local path="$1"
    shift || { printf '{"error":"no_path"}\n' >&2; return 1; }

    local lang="" json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$path" || return 1

    local -a results=()
    local count=0

    local -a files=()
    if [[ -f "$path" ]]; then
        files=("$path")
    else
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && files+=("$f")
        done < <(find "$path" -type f \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            2>/dev/null | head -n "$MAINFRAME_CODESEARCH_MAX_FILES")
    fi

    local file
    for file in "${files[@]}"; do
        _codesearch_is_sensitive "$file" && continue

        local file_lang
        file_lang=$(code_detect_lang "$file")
        [[ -n "$lang" && "$file_lang" != "$lang" ]] && continue

        local pattern="${_CODESEARCH_EXPORT_PATTERNS[$file_lang]:-}"
        [[ -z "$pattern" ]] && continue

        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))

            if [[ "$line" =~ $pattern ]]; then
                local export_name=""

                # Extract export name based on language
                case "$file_lang" in
                    javascript|typescript)
                        if [[ "$line" =~ export[[:space:]]+(default[[:space:]]+)?(const|let|var|function|class)[[:space:]]+([a-zA-Z_$][a-zA-Z0-9_$]*) ]]; then
                            export_name="${BASH_REMATCH[3]}"
                        elif [[ "$line" =~ module\.exports ]]; then
                            export_name="module.exports"
                        fi
                        ;;
                    go)
                        if [[ "$line" =~ ^(func|type|var|const)[[:space:]]+([A-Z][a-zA-Z0-9_]*) ]]; then
                            export_name="${BASH_REMATCH[2]}"
                        fi
                        ;;
                    rust)
                        if [[ "$line" =~ pub[[:space:]]+(fn|struct|enum|trait|type|const|mod)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                            export_name="${BASH_REMATCH[2]}"
                        fi
                        ;;
                    python)
                        if [[ "$line" =~ __all__[[:space:]]*= ]]; then
                            export_name="__all__"
                        fi
                        ;;
                esac

                [[ -z "$export_name" ]] && continue

                if [[ $json_output -eq 1 ]]; then
                    local escaped_file escaped_name escaped_line
                    escaped_file=$(_codesearch_escape_json "$file")
                    escaped_name=$(_codesearch_escape_json "$export_name")
                    escaped_line=$(_codesearch_escape_json "$line")
                    results+=("{\"file\":\"$escaped_file\",\"line\":$line_num,\"name\":\"$escaped_name\",\"statement\":\"$escaped_line\",\"lang\":\"$file_lang\"}")
                else
                    printf '%s:%d:%s\n' "$file" "$line_num" "$export_name"
                fi

                count=$((count + 1))
                [[ $count -ge $MAINFRAME_CODESEARCH_MAX_RESULTS ]] && break 2
            fi
        done < "$file"
    done

    [[ $count -eq 0 ]] && return 2

    if [[ $json_output -eq 1 ]]; then
        printf '[%s]\n' "$(IFS=,; printf '%s' "${results[*]}")"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Symbol Identification
# =============================================================================

# code_symbol_at - Identify symbol at file:line:col
# @pre: File exists and is readable
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 file - Path to source file
# @param: $2 line - Line number (1-indexed)
# @param: $3 col - Column number (1-indexed)
# @param: --json - Output as JSON
# @stdout: Symbol information
# @return: 0 on success, 1 if file not found, 2 if no symbol at position
#
# Usage: code_symbol_at "src/app.ts" 42 15
# Usage: code_symbol_at "main.py" 100 5 --json
code_symbol_at() {
    local file="$1"
    local line_num="$2"
    local col="$3"
    shift 3 || { printf '{"error":"insufficient_args","message":"File, line, and column required"}\n' >&2; return 1; }

    local json_output=0
    [[ "$1" == "--json" ]] && json_output=1

    [[ ! -f "$file" ]] && { printf '{"error":"file_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$file" || return 1

    # Read the specific line
    local line
    line=$(sed -n "${line_num}p" "$file" 2>/dev/null)
    [[ -z "$line" ]] && { printf '{"error":"line_not_found"}\n' >&2; return 1; }

    # Extract symbol at column position
    # Find word boundaries around the column
    local before="${line:0:$col}"
    local after="${line:$col}"

    # Find start of symbol (word boundary)
    local symbol_start
    if [[ "$before" =~ ([a-zA-Z_$][a-zA-Z0-9_$]*)$ ]]; then
        symbol_start="${BASH_REMATCH[1]}"
    else
        symbol_start=""
    fi

    # Find end of symbol
    local symbol_end
    if [[ "$after" =~ ^([a-zA-Z0-9_$]*) ]]; then
        symbol_end="${BASH_REMATCH[1]}"
    else
        symbol_end=""
    fi

    local symbol="${symbol_start}${symbol_end}"
    [[ -z "$symbol" ]] && { printf '{"error":"no_symbol_at_position"}\n' >&2; return 2; }

    # Determine symbol type by context
    local symbol_type="identifier"
    local file_lang
    file_lang=$(code_detect_lang "$file")

    # Check if it's a function definition
    if [[ "$line" =~ (function|def|fn|func)[[:space:]]+${symbol} ]]; then
        symbol_type="function_definition"
    # Check if it's a class definition
    elif [[ "$line" =~ (class|struct|type)[[:space:]]+${symbol} ]]; then
        symbol_type="class_definition"
    # Check if it's a function call
    elif [[ "$line" =~ ${symbol}[[:space:]]*\( ]]; then
        symbol_type="function_call"
    # Check if it's an import
    elif [[ "$line" =~ (import|from|require|use)[[:space:]].*${symbol} ]]; then
        symbol_type="import"
    fi

    if [[ $json_output -eq 1 ]]; then
        local escaped_symbol escaped_line
        escaped_symbol=$(_codesearch_escape_json "$symbol")
        escaped_line=$(_codesearch_escape_json "$line")
        printf '{"symbol":"%s","type":"%s","line":%d,"column":%d,"context":"%s","lang":"%s"}\n' \
            "$escaped_symbol" "$symbol_type" "$line_num" "$col" "$escaped_line" "$file_lang"
    else
        printf '%s:%s\n' "$symbol" "$symbol_type"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Index Building
# =============================================================================

# code_build_index - Build symbol index for completion/navigation
# @pre: Directory exists and is readable
# @post: Index cached (if cache.sh loaded)
# @idempotent: Yes (with cache)
# @param: $1 path - Directory to index
# @param: --lang - Language filter
# @param: --json - Output as JSON
# @stdout: Symbol index
# @return: 0 on success, 1 if path not found
#
# Usage: code_build_index "src/"
# Usage: code_build_index "src/" --lang typescript --json
code_build_index() {
    local path="$1"
    shift || { printf '{"error":"no_path"}\n' >&2; return 1; }

    local lang="" json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang) lang="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    [[ ! -d "$path" ]] && { printf '{"error":"path_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$path" || return 1

    # Build comprehensive index
    local -a functions=()
    local -a classes=()
    local -a interfaces=()
    local -a constants=()

    # Collect functions
    while IFS= read -r func; do
        [[ -n "$func" ]] && functions+=("$func")
    done < <(code_find_functions "$path" ${lang:+--lang "$lang"} 2>/dev/null)

    # Collect classes
    while IFS= read -r class; do
        [[ -n "$class" ]] && classes+=("$class")
    done < <(code_find_classes "$path" ${lang:+--lang "$lang"} 2>/dev/null)

    # Collect interfaces
    while IFS= read -r iface; do
        [[ -n "$iface" ]] && interfaces+=("$iface")
    done < <(code_find_interfaces "$path" ${lang:+--lang "$lang"} 2>/dev/null)

    # Collect constants
    while IFS= read -r const; do
        [[ -n "$const" ]] && constants+=("$const")
    done < <(code_find_constants "$path" ${lang:+--lang "$lang"} 2>/dev/null)

    if [[ $json_output -eq 1 ]]; then
        local funcs_json classes_json ifaces_json consts_json
        funcs_json=$(_codesearch_json_array "${functions[@]}")
        classes_json=$(_codesearch_json_array "${classes[@]}")
        ifaces_json=$(_codesearch_json_array "${interfaces[@]}")
        consts_json=$(_codesearch_json_array "${constants[@]}")

        printf '{"path":"%s","functions":%s,"classes":%s,"interfaces":%s,"constants":%s,"totals":{"functions":%d,"classes":%d,"interfaces":%d,"constants":%d}}\n' \
            "$(_codesearch_escape_json "$path")" \
            "$funcs_json" "$classes_json" "$ifaces_json" "$consts_json" \
            "${#functions[@]}" "${#classes[@]}" "${#interfaces[@]}" "${#constants[@]}"
    else
        printf '# Symbol Index for %s\n\n' "$path"
        printf '## Functions (%d)\n' "${#functions[@]}"
        printf '%s\n' "${functions[@]}"
        printf '\n## Classes (%d)\n' "${#classes[@]}"
        printf '%s\n' "${classes[@]}"
        printf '\n## Interfaces (%d)\n' "${#interfaces[@]}"
        printf '%s\n' "${interfaces[@]}"
        printf '\n## Constants (%d)\n' "${#constants[@]}"
        printf '%s\n' "${constants[@]}"
    fi

    return 0
}

# =============================================================================
# PUBLIC API - Unified Search
# =============================================================================

# code_search - Unified search by symbol type
# @pre: Directory/file exists
# @post: None (read-only)
# @idempotent: Yes
# @param: $1 path - File or directory to search
# @param: --type - Symbol type: function|class|interface|const|import|export|all
# @param: --lang - Language filter
# @param: --name - Name pattern (regex)
# @param: --json - Output as JSON
# @stdout: Search results
# @return: 0 on success, 1 if path not found, 2 if no matches
#
# Usage: code_search "src/" --type function --lang python
# Usage: code_search "src/" --type all --name "User" --json
code_search() {
    local path="$1"
    shift || { printf '{"error":"no_path"}\n' >&2; return 1; }

    local symbol_type="all" lang="" name_pattern="" json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) symbol_type="$2"; shift 2 ;;
            --lang) lang="$2"; shift 2 ;;
            --name) name_pattern="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    [[ ! -e "$path" ]] && { printf '{"error":"path_not_found"}\n' >&2; return 1; }
    _codesearch_validate_path "$path" || return 1

    local -a all_results=()
    local has_results=0

    # Build common args
    local -a common_args=()
    [[ -n "$lang" ]] && common_args+=(--lang "$lang")
    [[ -n "$name_pattern" ]] && common_args+=(--name "$name_pattern")
    [[ $json_output -eq 1 ]] && common_args+=(--json)

    case "$symbol_type" in
        function|func|fn)
            code_find_functions "$path" "${common_args[@]}" && has_results=1
            ;;
        class|struct|type)
            code_find_classes "$path" "${common_args[@]}" && has_results=1
            ;;
        interface|trait|protocol)
            code_find_interfaces "$path" "${common_args[@]}" && has_results=1
            ;;
        const|constant|readonly)
            code_find_constants "$path" "${common_args[@]}" && has_results=1
            ;;
        import|require|use)
            code_find_imports "$path" ${lang:+--lang "$lang"} ${name_pattern:+--module "$name_pattern"} ${json_output:+--json} && has_results=1
            ;;
        export)
            code_find_exports "$path" ${lang:+--lang "$lang"} ${json_output:+--json} && has_results=1
            ;;
        all|*)
            # Search all types and combine results
            local funcs classes ifaces consts

            if [[ $json_output -eq 1 ]]; then
                funcs=$(code_find_functions "$path" "${common_args[@]}" 2>/dev/null) && has_results=1
                classes=$(code_find_classes "$path" "${common_args[@]}" 2>/dev/null) && has_results=1
                ifaces=$(code_find_interfaces "$path" "${common_args[@]}" 2>/dev/null) && has_results=1
                consts=$(code_find_constants "$path" "${common_args[@]}" 2>/dev/null) && has_results=1

                # Combine JSON results
                printf '{"functions":%s,"classes":%s,"interfaces":%s,"constants":%s}\n' \
                    "${funcs:-[]}" "${classes:-[]}" "${ifaces:-[]}" "${consts:-[]}"
            else
                printf '=== Functions ===\n'
                code_find_functions "$path" "${common_args[@]}" 2>/dev/null && has_results=1
                printf '\n=== Classes ===\n'
                code_find_classes "$path" "${common_args[@]}" 2>/dev/null && has_results=1
                printf '\n=== Interfaces ===\n'
                code_find_interfaces "$path" "${common_args[@]}" 2>/dev/null && has_results=1
                printf '\n=== Constants ===\n'
                code_find_constants "$path" "${common_args[@]}" 2>/dev/null && has_results=1
            fi
            return $((has_results ? 0 : 2))
            ;;
    esac

    [[ $has_results -eq 0 ]] && return 2
    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_CODESEARCH_EXPORTS=(
    # Language detection
    code_detect_lang
    # Symbol search
    code_find_functions
    code_find_classes
    code_find_interfaces
    code_find_constants
    # Reference search
    code_find_callers
    code_find_imports
    code_find_exports
    # Symbol identification
    code_symbol_at
    # Indexing
    code_build_index
    # Unified search
    code_search
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${MAINFRAME_CODESEARCH_EXPORTS[@]}" 2>/dev/null || true
fi

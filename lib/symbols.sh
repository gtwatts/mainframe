#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/symbols.sh - Multi-Language Symbol Extraction Library
# =============================================================================
# Description: Pure bash multi-language symbol extraction - function names, class
#              definitions, exports, and interfaces. Fast heuristic extraction for
#              AI agents to understand code structure without reading entire files.
# Version: 1.0.0
# =============================================================================
# LIMITATIONS (regex-based parsing, not AST):
#   - Cannot handle symbols inside multiline strings or block comments
#   - Best-effort comment skipping (lines starting with # // /*)
#   - Indentation-based scope detection is approximate
#   - Multiline signatures may be partially captured
#   - Decorators/annotations attached by adjacency heuristic
#   - Complex generics and template parameters may confuse extractors
#   - Does not resolve imports or type aliases
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SYMBOLS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SYMBOLS_LOADED=1

# =============================================================================
# LANGUAGE DETECTION
# =============================================================================

# Detect language from file extension and content
# Output: language name string
symbols_detect_language() {
    local file="$1"
    [[ -f "$file" ]] || { echo "unknown"; return 1; }

    local ext="${file##*.}"
    case "$ext" in
        py)     echo "python" ;;
        ts|tsx) echo "typescript" ;;
        js|jsx|mjs|cjs) echo "javascript" ;;
        go)     echo "go" ;;
        rs)     echo "rust" ;;
        sh|bash|zsh) echo "bash" ;;
        c|h)    echo "c" ;;
        cpp|cc|cxx|hpp|hh|hxx) echo "cpp" ;;
        rb)     echo "ruby" ;;
        java)   echo "java" ;;
        kt|kts) echo "kotlin" ;;
        *)
            # Try shebang detection
            local first_line
            first_line=$(head -1 "$file" 2>/dev/null)
            case "$first_line" in
                *python3*|*python*) echo "python" ;;
                *bash*|*sh*)        echo "bash" ;;
                *ruby*)             echo "ruby" ;;
                *node*)             echo "javascript" ;;
                *)                  echo "unknown" ;;
            esac
            ;;
    esac
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Strip single-line comments from a line for pattern matching
# This is best-effort: full-line comments are skipped, inline comments trimmed
_symbols_is_comment_line() {
    local line="$1"
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
        '#'*|'//'*|'/*'*|'*'*|'"""'*|"'''"*) return 0 ;;
    esac
    return 1
}

# Escape a string for JSON output
_symbols_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\n'/\\n}"
    printf '%s' "$str"
}

# =============================================================================
# PYTHON EXTRACTOR
# =============================================================================

# Extract symbols from a Python file
# Output: type:name:line_number per line
symbols_python() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0
    local in_class=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Skip comment lines
        _symbols_is_comment_line "$line" && continue

        # Skip decorator lines (tracked for context only)
        if [[ "$line" =~ ^[[:space:]]*@([a-zA-Z_][a-zA-Z0-9_.]*) ]]; then
            continue
        fi

        # Class definition
        if [[ "$line" =~ ^([[:space:]]*)class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            local indent="${#BASH_REMATCH[1]}"
            local name="${BASH_REMATCH[2]}"
            if [[ $indent -eq 0 ]]; then
                in_class="$name"
                printf 'class:%s:%d\n' "$name" "$line_num"
            else
                printf 'class:%s:%d\n' "$name" "$line_num"
            fi
            continue
        fi

        # Function/method definition (async or regular)
        if [[ "$line" =~ ^([[:space:]]*)(async[[:space:]]+)?def[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            local indent="${#BASH_REMATCH[1]}"
            local is_async="${BASH_REMATCH[2]}"
            local name="${BASH_REMATCH[3]}"

            if [[ $indent -gt 0 && -n "$in_class" ]]; then
                printf 'method:%s:%d\n' "$name" "$line_num"
            else
                if [[ -n "$is_async" ]]; then
                    printf 'function:%s:%d\n' "$name" "$line_num"
                else
                    printf 'function:%s:%d\n' "$name" "$line_num"
                fi
                # Reset class tracking if we're back at top level
                if [[ $indent -eq 0 ]]; then
                    in_class=""
                fi
            fi
            continue
        fi

        # Top-level assignment (potential constant/export)
        if [[ "$line" =~ ^([A-Z][A-Z0-9_]*)[[:space:]]*= ]]; then
            printf 'constant:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi
    done < "$file"
}

# =============================================================================
# TYPESCRIPT/JAVASCRIPT EXTRACTOR
# =============================================================================

# Extract symbols from a TypeScript/JavaScript file
# Output: type:name:line_number per line
symbols_typescript() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0
    local in_block_comment=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Handle block comments
        if [[ $in_block_comment -eq 1 ]]; then
            [[ "$line" == *"*/"* ]] && in_block_comment=0
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*/\* ]] && [[ "$line" != *"*/"* ]]; then
            in_block_comment=1
            continue
        fi

        # Skip single-line comments
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == //* ]] && continue

        # Interface
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?interface[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'interface:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Type alias
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?type[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*= ]]; then
            printf 'type:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Enum
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?enum[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'enum:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Class (including export default class)
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'class:%s:%d\n' "${BASH_REMATCH[3]}" "$line_num"
            continue
        fi

        # Function declaration (including export, async)
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'function:%s:%d\n' "${BASH_REMATCH[4]}" "$line_num"
            continue
        fi

        # Arrow function assigned to const/let (export const foo = (...) => or async (...) =>)
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=.*(\(|async) ]]; then
            local name="${BASH_REMATCH[3]}"
            # Check if it looks like a function (has arrow or function keyword after)
            if [[ "$line" =~ "=>" ]] || [[ "$line" =~ "async" ]]; then
                printf 'function:%s:%d\n' "$name" "$line_num"
                continue
            fi
        fi

        # Exported const/let that is not a function (simple value)
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)(const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*= ]]; then
            local name="${BASH_REMATCH[3]}"
            # Only if we did NOT already match as a function above
            if [[ ! "$line" =~ "=>" ]] && [[ ! "$line" =~ "async" ]] && [[ ! "$line" =~ "function" ]]; then
                printf 'export:%s:%d\n' "$name" "$line_num"
                continue
            fi
        fi

        # Named exports: export { Foo, Bar }
        if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+\{([^}]+)\} ]]; then
            local exports="${BASH_REMATCH[1]}"
            # Split by comma
            local IFS=','
            local item
            for item in $exports; do
                item="${item#"${item%%[![:space:]]*}"}"
                item="${item%"${item##*[![:space:]]}"}"
                # Handle 'as' aliases: take the alias name
                if [[ "$item" =~ ([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+as[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                    printf 'export:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
                elif [[ "$item" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)$ ]]; then
                    printf 'export:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
                fi
            done
            continue
        fi

    done < "$file"
}

# =============================================================================
# GO EXTRACTOR
# =============================================================================

# Extract symbols from a Go file
# Output: type:name:line_number per line
symbols_go() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0
    local in_block_comment=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Handle block comments
        if [[ $in_block_comment -eq 1 ]]; then
            [[ "$line" == *"*/"* ]] && in_block_comment=0
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*/\* ]] && [[ "$line" != *"*/"* ]]; then
            in_block_comment=1
            continue
        fi

        # Skip single-line comments
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == //* ]] && continue

        # Method with receiver: func (r *Type) Name(
        if [[ "$line" =~ ^func[[:space:]]+\([[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+\*?([a-zA-Z_][a-zA-Z0-9_]*)\)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'method:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Function: func Name(
        if [[ "$line" =~ ^func[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'function:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Type struct
        if [[ "$line" =~ ^type[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+struct ]]; then
            printf 'struct:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Type interface
        if [[ "$line" =~ ^type[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+interface ]]; then
            printf 'interface:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Package-level const
        if [[ "$line" =~ ^const[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'constant:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Package-level var
        if [[ "$line" =~ ^var[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'variable:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

    done < "$file"
}

# =============================================================================
# RUST EXTRACTOR
# =============================================================================

# Extract symbols from a Rust file
# Output: type:name:line_number per line
symbols_rust() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0
    local in_block_comment=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Handle block comments
        if [[ $in_block_comment -eq 1 ]]; then
            [[ "$line" == *"*/"* ]] && in_block_comment=0
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*/\* ]] && [[ "$line" != *"*/"* ]]; then
            in_block_comment=1
            continue
        fi

        # Skip single-line comments
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == //* ]] && continue

        # Module
        if [[ "$line" =~ ^(pub[[:space:]]+)?mod[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'module:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Struct
        if [[ "$line" =~ ^(pub[[:space:]]+)?struct[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'struct:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Enum
        if [[ "$line" =~ ^(pub[[:space:]]+)?enum[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'enum:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Trait
        if [[ "$line" =~ ^(pub[[:space:]]+)?trait[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'trait:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Impl block
        if [[ "$line" =~ ^impl[[:space:]]+(.*[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*(\{|$) ]]; then
            # Handle "impl Trait for Type" and "impl Type"
            if [[ "$line" =~ ^impl[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+for[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                printf 'impl:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            elif [[ "$line" =~ ^impl[[:space:]]+([a-zA-Z_][a-zA-Z0-9_<>]*)[[:space:]]*\{ ]]; then
                local impl_name="${BASH_REMATCH[1]}"
                impl_name="${impl_name%%<*}"
                printf 'impl:%s:%d\n' "$impl_name" "$line_num"
            elif local _re_impl='impl[[:space:]]+<[^>]+>[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)' && [[ "$line" =~ ^$_re_impl ]]; then
                printf 'impl:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            fi
            continue
        fi

        # Function (pub, async, or plain fn)
        if [[ "$line" =~ ^[[:space:]]*(pub[[:space:]]+)?(async[[:space:]]+)?fn[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'function:%s:%d\n' "${BASH_REMATCH[3]}" "$line_num"
            continue
        fi

        # Const
        if [[ "$line" =~ ^(pub[[:space:]]+)?const[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'constant:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Static
        if [[ "$line" =~ ^(pub[[:space:]]+)?static[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'static:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

    done < "$file"
}

# =============================================================================
# BASH/SHELL EXTRACTOR
# =============================================================================

# Extract symbols from a Bash/Shell file
# Output: type:name:line_number per line
symbols_bash() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Skip comment lines
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == '#'* ]] && continue

        # function keyword style: function name { or function name() {
        if [[ "$line" =~ ^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'function:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Short form: name() {
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\)[[:space:]]* ]]; then
            printf 'function:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

    done < "$file"
}

# =============================================================================
# C/C++ EXTRACTOR
# =============================================================================

# Extract symbols from a C/C++ file
# Output: type:name:line_number per line
symbols_c() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0
    local in_block_comment=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Handle block comments
        if [[ $in_block_comment -eq 1 ]]; then
            [[ "$line" == *"*/"* ]] && in_block_comment=0
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*/\* ]] && [[ "$line" != *"*/"* ]]; then
            in_block_comment=1
            continue
        fi

        # Skip single-line comments
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == //* ]] && continue

        # Preprocessor define
        if [[ "$line" =~ ^[[:space:]]*\#define[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'macro:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Class (C++)
        if [[ "$line" =~ ^[[:space:]]*(class|struct)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*[\{:] ]]; then
            local kind="${BASH_REMATCH[1]}"
            local name="${BASH_REMATCH[2]}"
            if [[ "$kind" == "class" ]]; then
                printf 'class:%s:%d\n' "$name" "$line_num"
            else
                printf 'struct:%s:%d\n' "$name" "$line_num"
            fi
            continue
        fi

        # Typedef struct
        if [[ "$line" =~ ^[[:space:]]*typedef[[:space:]]+struct ]]; then
            # The name comes at the end: } Name;
            # We will catch it as struct since it is inline
            printf 'struct:(typedef):%d\n' "$line_num"
            continue
        fi

        # Named struct (no typedef, no semicolon on same line = definition)
        if [[ "$line" =~ ^[[:space:]]*struct[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\{ ]]; then
            printf 'struct:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Enum
        if [[ "$line" =~ ^[[:space:]]*(typedef[[:space:]]+)?enum[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'enum:%s:%d\n' "${BASH_REMATCH[2]}" "$line_num"
            continue
        fi

        # Function definition: type name( ... ) {
        # Heuristic: line starts with identifier(s), has parens, ends with { or just has (
        # Skip lines with semicolons (declarations) and lines starting with keywords
        if [[ "$line" != *";"* ]] && [[ "$line" != *"#"* ]] && [[ "$line" != *"typedef"* ]]; then
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_*[:space:]]*[[:space:]+*])?([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\( ]]; then
                local prefix="${BASH_REMATCH[1]}"
                local name="${BASH_REMATCH[2]}"
                # Skip keywords that are not function names
                case "$name" in
                    if|else|while|for|switch|return|sizeof|typedef|struct|enum|union|class|do) continue ;;
                esac
                # Skip if prefix contains keywords indicating non-function
                case "$prefix" in
                    *struct*|*enum*|*typedef*|*class*) continue ;;
                esac
                # Must have opening brace on this line or next indication of body
                if [[ "$line" == *"{"* ]] || [[ "$line" == *")"* ]]; then
                    printf 'function:%s:%d\n' "$name" "$line_num"
                    continue
                fi
            fi
        fi

    done < "$file"
}

# =============================================================================
# RUBY EXTRACTOR
# =============================================================================

# Extract symbols from a Ruby file
# Output: type:name:line_number per line
symbols_ruby() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Skip comment lines
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == '#'* ]] && continue

        # Module
        if [[ "$line" =~ ^[[:space:]]*module[[:space:]]+([a-zA-Z_][a-zA-Z0-9_:]*) ]]; then
            printf 'module:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Class
        if [[ "$line" =~ ^[[:space:]]*class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_:]*) ]]; then
            printf 'class:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # Method definition
        if [[ "$line" =~ ^[[:space:]]*def[[:space:]]+([a-zA-Z_][a-zA-Z0-9_?!=]*) ]]; then
            printf 'method:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
            continue
        fi

        # attr_accessor, attr_reader, attr_writer
        if [[ "$line" =~ ^[[:space:]]*(attr_accessor|attr_reader|attr_writer)[[:space:]]+(.+) ]]; then
            local attrs="${BASH_REMATCH[2]}"
            # Parse :symbol_name entries
            while [[ "$attrs" =~ :([a-zA-Z_][a-zA-Z0-9_]*) ]]; do
                printf 'attribute:%s:%d\n' "${BASH_REMATCH[1]}" "$line_num"
                attrs="${attrs#*"${BASH_REMATCH[0]}"}"
            done
            continue
        fi

    done < "$file"
}

# =============================================================================
# JAVA/KOTLIN EXTRACTOR
# =============================================================================

# Extract symbols from a Java file
# Output: type:name:line_number per line
symbols_java() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local line_num=0
    local in_block_comment=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( line_num++ ))

        # Handle block comments
        if [[ $in_block_comment -eq 1 ]]; then
            [[ "$line" == *"*/"* ]] && in_block_comment=0
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*/\* ]] && [[ "$line" != *"*/"* ]]; then
            in_block_comment=1
            continue
        fi

        # Skip single-line comments
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" == //* ]] && continue

        # Enum
        if [[ "$line" =~ ^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|protected[[:space:]]+)?(static[[:space:]]+)?enum[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'enum:%s:%d\n' "${BASH_REMATCH[3]}" "$line_num"
            continue
        fi

        # Interface
        if [[ "$line" =~ ^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|protected[[:space:]]+)?(static[[:space:]]+)?interface[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'interface:%s:%d\n' "${BASH_REMATCH[3]}" "$line_num"
            continue
        fi

        # Class
        if [[ "$line" =~ ^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|protected[[:space:]]+)?(abstract[[:space:]]+)?(static[[:space:]]+)?class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            printf 'class:%s:%d\n' "${BASH_REMATCH[4]}" "$line_num"
            continue
        fi

        # Method: visibility? modifiers? return_type name(
        # Skip lines with 'class', 'interface', 'enum' (already handled)
        if [[ "$line" != *"class "* ]] && [[ "$line" != *"interface "* ]] && [[ "$line" != *"enum "* ]]; then
            if [[ "$line" =~ ^[[:space:]]*(public|private|protected)[[:space:]]+(static[[:space:]]+)?(final[[:space:]]+)?(abstract[[:space:]]+)?(synchronized[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_<>,[:space:]?]*)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\( ]]; then
                local name="${BASH_REMATCH[7]}"
                # Skip if name is a type keyword
                case "$name" in
                    if|else|while|for|switch|return|new|throw|try|catch) continue ;;
                esac
                printf 'method:%s:%d\n' "$name" "$line_num"
                continue
            fi
        fi

    done < "$file"
}

# =============================================================================
# UNIVERSAL ENTRY POINTS
# =============================================================================

# Extract symbols from a file (auto-detects language)
# Usage: symbols_extract "file_path" [--type functions|classes|exports|all]
# Output: type:name:line_number per line
symbols_extract() {
    local file="$1"
    shift
    local type_filter="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) type_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -f "$file" ]] || return 1

    local lang
    lang=$(symbols_detect_language "$file")

    local output
    case "$lang" in
        python)     output=$(symbols_python "$file") ;;
        typescript|javascript) output=$(symbols_typescript "$file") ;;
        go)         output=$(symbols_go "$file") ;;
        rust)       output=$(symbols_rust "$file") ;;
        bash)       output=$(symbols_bash "$file") ;;
        c|cpp)      output=$(symbols_c "$file") ;;
        ruby)       output=$(symbols_ruby "$file") ;;
        java|kotlin) output=$(symbols_java "$file") ;;
        *)          return 1 ;;
    esac

    # Apply type filter
    [[ -z "$output" ]] && return 0
    if [[ "$type_filter" == "all" ]]; then
        printf '%s\n' "$output"
    else
        printf '%s\n' "$output" | grep "^${type_filter}:" || true
    fi
}

# Extract symbols as JSON
# Output: {"file":"path","language":"lang","symbols":[...]}
symbols_extract_json() {
    local file="$1"
    shift
    local type_filter="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) type_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -f "$file" ]] || return 1

    local lang
    lang=$(symbols_detect_language "$file")

    local symbols
    symbols=$(symbols_extract "$file" --type "$type_filter")

    local escaped_file
    escaped_file=$(_symbols_json_escape "$file")

    printf '{"file":"%s","language":"%s","symbols":[' "$escaped_file" "$lang"

    local first=1
    local sym_type sym_name sym_line sig
    while IFS=: read -r sym_type sym_name sym_line; do
        [[ -z "$sym_type" ]] && continue
        [[ $first -eq 0 ]] && printf ','
        first=0

        # Get signature for this line
        sig=""
        if [[ -f "$file" ]] && [[ -n "$sym_line" ]]; then
            sig=$(sed -n "${sym_line}p" "$file" 2>/dev/null)
            sig="${sig#"${sig%%[![:space:]]*}"}"
            sig="${sig%"${sig##*[![:space:]]}"}"
            sig=$(_symbols_json_escape "$sig")
        fi

        printf '{"type":"%s","name":"%s","line":%s,"signature":"%s"}' \
            "$sym_type" "$(_symbols_json_escape "$sym_name")" "$sym_line" "$sig"
    done <<< "$symbols"

    printf ']}\n'
}

# Extract symbols from multiple files in a directory
# Usage: symbols_extract_dir "dir_path" [--extensions "py,ts,go"] [--type all]
# Output: JSON array of per-file symbol data
symbols_extract_dir() {
    local dir="$1"
    shift
    local extensions="py,ts,js,go,rs,sh,c,cpp,rb,java,kt"
    local type_filter="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --extensions) extensions="$2"; shift 2 ;;
            --type) type_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -d "$dir" ]] || return 1

    # Build find expression for extensions
    local find_args=()
    local IFS=','
    local first_ext=1
    for ext in $extensions; do
        if [[ $first_ext -eq 1 ]]; then
            find_args+=(-name "*.${ext}")
            first_ext=0
        else
            find_args+=(-o -name "*.${ext}")
        fi
    done

    printf '['
    local first_file=1
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Skip common non-source directories
        [[ "$file" == *node_modules* ]] && continue
        [[ "$file" == *__pycache__* ]] && continue
        [[ "$file" == */.git/* ]] && continue
        [[ "$file" == */vendor/* ]] && continue
        [[ "$file" == */target/* ]] && continue

        local result
        result=$(symbols_extract_json "$file" --type "$type_filter" 2>/dev/null)
        [[ -z "$result" ]] && continue

        [[ $first_file -eq 0 ]] && printf ','
        first_file=0
        printf '%s' "$result"
    done < <(find "$dir" -type f \( "${find_args[@]}" \) 2>/dev/null | sort)

    printf ']\n'
}

# =============================================================================
# ANALYSIS FUNCTIONS
# =============================================================================

# Get a quick outline of a file (type + name only, indented)
# Output: indented outline
symbols_outline() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local symbols
    symbols=$(symbols_extract "$file")
    [[ -z "$symbols" ]] && return 0

    local sym_type sym_name sym_line
    while IFS=: read -r sym_type sym_name sym_line; do
        [[ -z "$sym_type" ]] && continue
        case "$sym_type" in
            class|struct|module|interface|trait|impl|enum)
                printf '%s %s\n' "$sym_type" "$sym_name"
                ;;
            method|attribute)
                printf '  %s %s\n' "$sym_type" "$sym_name"
                ;;
            *)
                printf '%s %s\n' "$sym_type" "$sym_name"
                ;;
        esac
    done <<< "$symbols"
}

# Count symbols by type
# Output: JSON {"functions":N,"classes":N,...,"total":N}
symbols_count() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local symbols
    symbols=$(symbols_extract "$file")

    local functions=0 classes=0 methods=0 interfaces=0 exports=0
    local structs=0 enums=0 constants=0 modules=0 total=0

    local sym_type sym_name sym_line
    while IFS=: read -r sym_type sym_name sym_line; do
        [[ -z "$sym_type" ]] && continue
        (( total++ ))
        case "$sym_type" in
            function)  (( functions++ )) ;;
            class)     (( classes++ )) ;;
            method)    (( methods++ )) ;;
            interface) (( interfaces++ )) ;;
            export)    (( exports++ )) ;;
            struct)    (( structs++ )) ;;
            enum)      (( enums++ )) ;;
            constant|static|macro) (( constants++ )) ;;
            module|trait|impl) (( modules++ )) ;;
        esac
    done <<< "$symbols"

    printf '{"functions":%d,"classes":%d,"methods":%d,"interfaces":%d,"exports":%d,"structs":%d,"enums":%d,"constants":%d,"modules":%d,"total":%d}\n' \
        "$functions" "$classes" "$methods" "$interfaces" "$exports" \
        "$structs" "$enums" "$constants" "$modules" "$total"
}

# Find a specific symbol across files in a directory
# Output: file:line for each match
symbols_find() {
    local symbol_name="$1"
    local dir="${2:-.}"
    local type_filter="any"

    if [[ $# -ge 2 ]]; then
        shift 2
    elif [[ $# -ge 1 ]]; then
        shift 1
    fi
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) type_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -d "$dir" ]] || return 1
    [[ -z "$symbol_name" ]] && return 1

    local extensions="py,ts,js,go,rs,sh,c,cpp,rb,java,kt"
    local find_args=()
    local IFS=','
    local first_ext=1
    for ext in $extensions; do
        if [[ $first_ext -eq 1 ]]; then
            find_args+=(-name "*.${ext}")
            first_ext=0
        else
            find_args+=(-o -name "*.${ext}")
        fi
    done

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ "$file" == *node_modules* ]] && continue
        [[ "$file" == *__pycache__* ]] && continue

        local symbols
        symbols=$(symbols_extract "$file" 2>/dev/null)
        [[ -z "$symbols" ]] && continue

        local sym_type sym_name sym_line
        while IFS=: read -r sym_type sym_name sym_line; do
            [[ -z "$sym_name" ]] && continue
            if [[ "$sym_name" == "$symbol_name" ]]; then
                if [[ "$type_filter" == "any" ]] || [[ "$sym_type" == "$type_filter" ]]; then
                    printf '%s:%s\n' "$file" "$sym_line"
                fi
            fi
        done <<< "$symbols"
    done < <(find "$dir" -type f \( "${find_args[@]}" \) 2>/dev/null | sort)
}

# Get function/method signatures (with params)
# Output: one signature per line
symbols_signatures() {
    local file="$1"
    shift
    local public_only=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --public-only) public_only=1; shift ;;
            *) shift ;;
        esac
    done

    [[ -f "$file" ]] || return 1

    local symbols
    symbols=$(symbols_extract "$file")
    [[ -z "$symbols" ]] && return 0

    local sym_type sym_name sym_line
    while IFS=: read -r sym_type sym_name sym_line; do
        [[ -z "$sym_type" ]] && continue
        # Only functions and methods have meaningful signatures
        case "$sym_type" in
            function|method) ;;
            *) continue ;;
        esac

        # Skip private symbols if --public-only
        if [[ $public_only -eq 1 ]]; then
            [[ "$sym_name" == _* ]] && continue
            # Check if the line contains private/protected markers
            local sig_line
            sig_line=$(sed -n "${sym_line}p" "$file" 2>/dev/null)
            [[ "$sig_line" == *"private "* ]] && continue
            [[ "$sig_line" == *"protected "* ]] && continue
        fi

        # Extract the signature line
        local sig
        sig=$(sed -n "${sym_line}p" "$file" 2>/dev/null)
        sig="${sig#"${sig%%[![:space:]]*}"}"
        # Trim trailing brace/colon
        sig="${sig%\{*}"
        sig="${sig%:*}"
        sig="${sig%"${sig##*[![:space:]]}"}"
        # Remove decorators if present
        [[ "$sig" == @* ]] && continue

        printf '%s\n' "$sig"
    done <<< "$symbols"
}

# Get the public API of a file (exported/public symbols only)
# Output: JSON array of public symbols with signatures
symbols_public_api() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local lang
    lang=$(symbols_detect_language "$file")

    local symbols
    symbols=$(symbols_extract "$file")
    [[ -z "$symbols" ]] && { printf '[]\n'; return 0; }

    printf '['
    local first=1
    local sym_type sym_name sym_line

    while IFS=: read -r sym_type sym_name sym_line; do
        [[ -z "$sym_type" ]] && continue

        local is_public=0
        local sig_line
        sig_line=$(sed -n "${sym_line}p" "$file" 2>/dev/null)

        case "$lang" in
            python)
                # Public = not starting with underscore
                [[ "$sym_name" != _* ]] && is_public=1
                ;;
            typescript|javascript)
                # Public = has export keyword
                [[ "$sig_line" == *export* ]] && is_public=1
                [[ "$sym_type" == "export" ]] && is_public=1
                ;;
            go)
                # Public = starts with uppercase
                [[ "$sym_name" =~ ^[A-Z] ]] && is_public=1
                ;;
            rust)
                # Public = has pub keyword
                [[ "$sig_line" == *pub* ]] && is_public=1
                ;;
            java|kotlin)
                # Public = has public keyword
                [[ "$sig_line" == *public* ]] && is_public=1
                ;;
            ruby)
                # Simplified: methods before 'private' keyword are public
                is_public=1
                [[ "$sym_name" == _* ]] && is_public=0
                ;;
            bash)
                # All functions are "public" in bash unless prefixed with _
                [[ "$sym_name" != _* ]] && is_public=1
                ;;
        esac

        [[ $is_public -eq 0 ]] && continue

        local sig="${sig_line#"${sig_line%%[![:space:]]*}"}"
        sig="${sig%"${sig##*[![:space:]]}"}"

        [[ $first -eq 0 ]] && printf ','
        first=0
        printf '{"type":"%s","name":"%s","line":%s,"signature":"%s"}' \
            "$sym_type" "$(_symbols_json_escape "$sym_name")" "$sym_line" "$(_symbols_json_escape "$sig")"
    done <<< "$symbols"

    printf ']\n'
}

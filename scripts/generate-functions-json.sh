#!/usr/bin/env bash
# =============================================================================
# generate-functions-json.sh - Machine-readable FUNCTIONS.json registry generator
# =============================================================================
# Description: Parses all lib/*.sh files and extracts library metadata, public
#              function signatures, parameter info, and behavioral heuristics
#              into a structured JSON registry.
# =============================================================================
set -euo pipefail

# Optionally source MAINFRAME for logging (non-critical, script works standalone)
if [[ -f "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" 2>/dev/null || true
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Project version (from common.sh MAINFRAME_VERSION)
PROJECT_VERSION="5.0.0"

# Output defaults
OUTPUT_PATH="$PROJECT_ROOT/FUNCTIONS.json"
COMPACT=0

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate FUNCTIONS.json registry from lib/*.sh files.

Options:
    --output PATH    Output file path (default: PROJECT_ROOT/FUNCTIONS.json)
                     Use '--output -' to write to stdout
    --compact        Minified JSON output (no indentation)
    -h, --help       Show this help message

Examples:
    $(basename "$0")
    $(basename "$0") --output /tmp/functions.json
    $(basename "$0") --output - --compact | jq .
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ -z "${2:-}" ]] && { echo "Error: --output requires a path argument" >&2; exit 1; }
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --compact)
            COMPACT=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage
            ;;
    esac
done

# =============================================================================
# JSON HELPERS (standalone, no MAINFRAME dependency)
# =============================================================================

# Escape a string for JSON output
_json_escape() {
    local str="$1"
    local result=""
    local i char

    for ((i = 0; i < ${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')   result+='\"' ;;
            $'\\') result+='\\' ;;
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

# Print a JSON string value (with quotes)
_json_str() {
    printf '"%s"' "$(_json_escape "$1")"
}

# Indentation helper
_indent=""
_indent_step="  "

_push_indent() {
    _indent="${_indent}${_indent_step}"
}

_pop_indent() {
    _indent="${_indent#"$_indent_step"}"
}

_nl() {
    if [[ $COMPACT -eq 0 ]]; then
        printf '\n%s' "$_indent"
    fi
}

_sep() {
    # Separator between key:value (space after colon in pretty mode)
    if [[ $COMPACT -eq 0 ]]; then
        printf ' '
    fi
}

# =============================================================================
# LIBRARY METADATA EXTRACTION
# =============================================================================

# Extract the Description: field from a library header
_extract_description() {
    local file="$1"
    local desc=""
    local line

    # Read the header block (first 20 lines)
    local lineno=0
    while IFS= read -r line && [[ $lineno -lt 20 ]]; do
        lineno=$((lineno + 1))
        if [[ "$line" =~ ^#[[:space:]]*Description:[[:space:]]*(.+) ]]; then
            desc="${BASH_REMATCH[1]}"
            # Check for continuation lines (Description spanning multiple # lines)
            # Continuation lines are indented to align with text after "Description: "
            # Pattern: "#" followed by 13+ spaces then text (aligns under Description text)
            while IFS= read -r line && [[ $lineno -lt 25 ]]; do
                lineno=$((lineno + 1))
                # Strip the leading # and check indent depth
                if [[ "$line" =~ ^#(.+) ]]; then
                    local after_hash="${BASH_REMATCH[1]}"
                    local stripped="${after_hash#"${after_hash%%[![:space:]]*}"}"
                    local indent_len=$(( ${#after_hash} - ${#stripped} ))
                    # Continuation requires 13+ spaces of indent (aligns with Description text)
                    if [[ $indent_len -ge 13 && -n "$stripped" ]]; then
                        desc="$desc $stripped"
                    else
                        break
                    fi
                else
                    break
                fi
            done
            break
        fi
    done < "$file"

    # Trim trailing whitespace
    desc="${desc%"${desc##*[![:space:]]}"}"
    printf '%s' "$desc"
}

# Extract the Version: field from a library header
_extract_version() {
    local file="$1"
    local version=""
    local line lineno=0

    while IFS= read -r line && [[ $lineno -lt 20 ]]; do
        lineno=$((lineno + 1))
        if [[ "$line" =~ ^#[[:space:]]*Version:[[:space:]]*(.+) ]]; then
            version="${BASH_REMATCH[1]}"
            # Trim trailing whitespace
            version="${version%"${version##*[![:space:]]}"}"
            break
        fi
    done < "$file"

    printf '%s' "$version"
}

# =============================================================================
# FUNCTION EXTRACTION
# =============================================================================

# Extract description comment block immediately above a function definition.
# Collects consecutive # comment lines (skipping @-annotations and Usage: lines
# which are handled separately). Multi-line descriptions are joined.
_extract_func_description() {
    local file="$1"
    local func_line_num="$2"
    local desc=""
    local -a comment_lines=()
    local line

    # Read lines above the function definition
    local target_start=$((func_line_num - 1))

    # Collect consecutive comment lines above the function (backwards)
    local -a file_lines=()
    mapfile -t file_lines < "$file"

    local idx=$((target_start - 1))  # 0-indexed, so func is at target_start-1
    while [[ $idx -ge 0 ]]; do
        line="${file_lines[$idx]}"
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*(.*) ]]; then
            local comment_text="${BASH_REMATCH[1]}"
            # Skip section dividers (===)
            if [[ "$comment_text" =~ ^=+ ]]; then
                break
            fi
            # Skip empty comment lines at the boundary
            if [[ -z "$comment_text" && ${#comment_lines[@]} -eq 0 ]]; then
                break
            fi
            comment_lines=("$comment_text" "${comment_lines[@]}")
            idx=$((idx - 1))
        elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
            # Empty line breaks the comment block
            break
        else
            break
        fi
    done

    # Now extract description from comment_lines:
    # Skip @-annotations, Usage: lines, Example: lines
    # The description is the first non-annotation, non-usage, non-empty lines
    if [[ ${#comment_lines[@]} -eq 0 ]]; then
        printf '%s' ""
        return 0
    fi
    for cline in "${comment_lines[@]}"; do
        # Skip annotations
        if [[ "$cline" =~ ^@ ]]; then
            continue
        fi
        # Skip Usage/Example lines
        if [[ "$cline" =~ ^Usage: ]] || [[ "$cline" =~ ^Example: ]]; then
            continue
        fi
        # Skip Returns: lines
        if [[ "$cline" =~ ^Returns: ]]; then
            continue
        fi
        # Skip empty lines after description started
        if [[ -z "$cline" ]]; then
            if [[ -n "$desc" ]]; then
                # End of description paragraph
                break
            fi
            continue
        fi
        # This is description text
        if [[ -n "$desc" ]]; then
            desc="$desc $cline"
        else
            desc="$cline"
        fi
    done

    # Trim trailing period and whitespace for consistency
    desc="${desc%"${desc##*[![:space:]]}"}"
    printf '%s' "$desc"
}

# Extract parameters from the function body.
# Looks for: local var="$1", local var="${1:-default}", local var="$2", etc.
# Returns lines of: position|name|required|default
_extract_func_params() {
    local file="$1"
    local func_start="$2"  # 1-indexed line number of function definition

    local -a file_lines=()
    mapfile -t file_lines < "$file"

    local idx=$((func_start))  # Skip the function definition line itself (0-indexed: func_start-1, so body starts at func_start)
    local brace_depth=0
    local found_open=0
    local -a params=()
    local -A seen_positions=()

    # Check the function definition line for braces
    local func_line="${file_lines[$((func_start - 1))]}"
    if [[ "$func_line" == *"{"* ]]; then
        found_open=1
        local fl_opens="${func_line//[^\{]/}"
        local fl_closes="${func_line//[^\}]/}"
        brace_depth=$((${#fl_opens} - ${#fl_closes}))
        # If function is a one-liner (braces balance on same line), nothing to scan
        if [[ $brace_depth -le 0 ]]; then
            return 0
        fi
    fi

    while [[ $idx -lt ${#file_lines[@]} ]]; do
        local line="${file_lines[$idx]}"

        if [[ $found_open -eq 0 ]]; then
            if [[ "$line" == *"{"* ]]; then
                found_open=1
                local init_opens="${line//[^\{]/}"
                local init_closes="${line//[^\}]/}"
                brace_depth=$((${#init_opens} - ${#init_closes}))
                if [[ $brace_depth -le 0 ]]; then
                    break
                fi
            fi
            idx=$((idx + 1))
            continue
        fi

        # Track brace depth
        local opens="${line//[^\{]/}"
        local closes="${line//[^\}]/}"
        brace_depth=$((brace_depth + ${#opens} - ${#closes}))

        if [[ $brace_depth -le 0 ]]; then
            break
        fi

        # Only look at local declarations in the first level
        # Pattern: local var="$N" or local var="${N:-default}" or local var="${N}"
        if [[ "$line" =~ local[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)=\"?\$\{?([0-9]+)(:-([^}\"]*))?\}?\"? ]]; then
            local param_name="${BASH_REMATCH[1]}"
            local position="${BASH_REMATCH[2]}"
            local has_default="${BASH_REMATCH[3]}"
            local default_val="${BASH_REMATCH[4]}"

            # Skip if we already captured this position
            if [[ -z "${seen_positions[$position]:-}" ]]; then
                seen_positions[$position]=1
                local required="true"
                local default_out="null"
                if [[ -n "$has_default" ]]; then
                    required="false"
                    if [[ -n "$default_val" ]]; then
                        default_out="$default_val"
                    else
                        default_out=""
                    fi
                fi
                params+=("${position}|${param_name}|${required}|${default_out}")
            fi
        fi

        # Also handle: local var="$@" or local var=("$@") - skip these (variadic)
        # And: local var="$*" - skip

        # Stop scanning params after ~30 lines into function body (optimization)
        if [[ $((idx - func_start)) -gt 30 ]]; then
            break
        fi

        idx=$((idx + 1))
    done

    # Sort by position and output
    if [[ ${#params[@]} -gt 0 ]]; then
        printf '%s\n' "${params[@]}" | sort -t'|' -k1 -n
    fi
}

# Check if function outputs to stdout (contains echo, printf to stdout, or cat)
_func_outputs_stdout() {
    local file="$1"
    local func_start="$2"

    local -a file_lines=()
    mapfile -t file_lines < "$file"

    local idx=$((func_start))
    local brace_depth=0
    local found_open=0

    local func_line="${file_lines[$((func_start - 1))]}"
    if [[ "$func_line" == *"{"* ]]; then
        found_open=1
        local fl_opens="${func_line//[^\{]/}"
        local fl_closes="${func_line//[^\}]/}"
        brace_depth=$((${#fl_opens} - ${#fl_closes}))
        if [[ $brace_depth -le 0 ]]; then
            # One-liner: check the function line itself for stdout output
            if [[ "$func_line" =~ (echo|printf)[[:space:]] && ! "$func_line" =~ \>\&2 && ! "$func_line" =~ printf[[:space:]]+-v ]]; then
                printf 'true'
                return 0
            fi
            printf 'false'
            return 0
        fi
    fi

    while [[ $idx -lt ${#file_lines[@]} ]]; do
        local line="${file_lines[$idx]}"

        if [[ $found_open -eq 0 ]]; then
            if [[ "$line" == *"{"* ]]; then
                found_open=1
                local init_opens="${line//[^\{]/}"
                local init_closes="${line//[^\}]/}"
                brace_depth=$((${#init_opens} - ${#init_closes}))
                if [[ $brace_depth -le 0 ]]; then
                    break
                fi
            fi
            idx=$((idx + 1))
            continue
        fi

        local opens="${line//[^\{]/}"
        local closes="${line//[^\}]/}"
        brace_depth=$((brace_depth + ${#opens} - ${#closes}))

        if [[ $brace_depth -le 0 ]]; then
            break
        fi

        # Check for stdout output (exclude redirected to stderr >&2)
        # Skip printf -v (writes to variable, not stdout)
        if [[ "$line" =~ printf[[:space:]]+-v[[:space:]] ]]; then
            idx=$((idx + 1))
            continue
        fi
        # echo/printf without >&2 redirect
        if [[ "$line" =~ (echo|printf)[[:space:]] && ! "$line" =~ \>\&2 ]]; then
            printf 'true'
            return 0
        fi
        # cat without redirect (heuristic: bare cat or cat file without >&2)
        if [[ "$line" =~ ^[[:space:]]*cat[[:space:]] && ! "$line" =~ \>\&2 ]]; then
            printf 'true'
            return 0
        fi

        idx=$((idx + 1))
    done

    printf 'false'
}

# Check if function has explicit return statements
_func_returns_status() {
    local file="$1"
    local func_start="$2"

    local -a file_lines=()
    mapfile -t file_lines < "$file"

    local idx=$((func_start))
    local brace_depth=0
    local found_open=0

    local func_line="${file_lines[$((func_start - 1))]}"
    if [[ "$func_line" == *"{"* ]]; then
        found_open=1
        local fl_opens="${func_line//[^\{]/}"
        local fl_closes="${func_line//[^\}]/}"
        brace_depth=$((${#fl_opens} - ${#fl_closes}))
        if [[ $brace_depth -le 0 ]]; then
            # One-liner: check for return on the function line itself
            if [[ "$func_line" =~ [[:space:]]return[[:space:]] || "$func_line" =~ [[:space:]]return\; ]]; then
                printf 'true'
                return 0
            fi
            printf 'false'
            return 0
        fi
    fi

    while [[ $idx -lt ${#file_lines[@]} ]]; do
        local line="${file_lines[$idx]}"

        if [[ $found_open -eq 0 ]]; then
            if [[ "$line" == *"{"* ]]; then
                found_open=1
                local init_opens="${line//[^\{]/}"
                local init_closes="${line//[^\}]/}"
                brace_depth=$((${#init_opens} - ${#init_closes}))
                if [[ $brace_depth -le 0 ]]; then
                    break
                fi
            fi
            idx=$((idx + 1))
            continue
        fi

        local opens="${line//[^\{]/}"
        local closes="${line//[^\}]/}"
        brace_depth=$((brace_depth + ${#opens} - ${#closes}))

        if [[ $brace_depth -le 0 ]]; then
            break
        fi

        # Check for explicit return
        if [[ "$line" =~ ^[[:space:]]*return[[:space:]] || "$line" =~ ^[[:space:]]*return$ ]]; then
            printf 'true'
            return 0
        fi

        idx=$((idx + 1))
    done

    printf 'false'
}

# =============================================================================
# MAIN GENERATION LOGIC
# =============================================================================

generate_json() {
    local total_libraries=0
    local total_functions=0
    local generated
    generated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    # Collect all library files (excluding common.sh loader)
    local -a lib_files=()
    for f in "$LIB_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local basename_f
        basename_f="$(basename "$f")"
        # Skip common.sh (it's the loader, not a standalone library in the same sense)
        [[ "$basename_f" == "common.sh" ]] && continue
        lib_files+=("$f")
    done

    # Sort library files
    local -a sorted_files=()
    while IFS= read -r f; do
        sorted_files+=("$f")
    done < <(printf '%s\n' "${lib_files[@]}" | sort)
    lib_files=("${sorted_files[@]}")

    # Start building JSON output
    printf '{'
    _push_indent
    _nl
    printf '"version":'; _sep; _json_str "$PROJECT_VERSION"
    printf ','
    _nl
    printf '"generated":'; _sep; _json_str "$generated"
    printf ','
    _nl
    printf '"libraries":'; _sep; printf '{'
    _push_indent

    local first_lib=1
    for lib_file in "${lib_files[@]}"; do
        local lib_basename
        lib_basename="$(basename "$lib_file")"
        local lib_name="${lib_basename%.sh}"

        local lib_desc
        lib_desc="$(_extract_description "$lib_file")"
        local lib_version
        lib_version="$(_extract_version "$lib_file")"

        # Find all public functions (not starting with _)
        local -a func_names=()
        local -a func_lines=()
        local lineno=0
        while IFS= read -r line; do
            lineno=$((lineno + 1))
            # Match: funcname() { or funcname () {
            if [[ "$line" =~ ^([a-zA-Z][a-zA-Z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{?[[:space:]]*$ ]]; then
                local fname="${BASH_REMATCH[1]}"
                func_names+=("$fname")
                func_lines+=("$lineno")
            fi
        done < "$lib_file"

        # Skip libraries with no public functions
        [[ ${#func_names[@]} -eq 0 ]] && continue

        total_libraries=$((total_libraries + 1))

        if [[ $first_lib -eq 0 ]]; then
            printf ','
        fi
        first_lib=0

        _nl
        _json_str "$lib_name"; printf ':'; _sep; printf '{'
        _push_indent
        _nl
        printf '"description":'; _sep
        if [[ -n "$lib_desc" ]]; then
            _json_str "$lib_desc"
        else
            printf 'null'
        fi
        printf ','
        _nl
        printf '"version":'; _sep
        if [[ -n "$lib_version" ]]; then
            _json_str "$lib_version"
        else
            printf 'null'
        fi
        printf ','
        _nl
        printf '"file":'; _sep; _json_str "lib/${lib_basename}"
        printf ','
        _nl
        printf '"functions":'; _sep; printf '{'
        _push_indent

        local first_func=1
        local fi_idx
        for fi_idx in "${!func_names[@]}"; do
            local fname="${func_names[$fi_idx]}"
            local fline="${func_lines[$fi_idx]}"

            total_functions=$((total_functions + 1))

            if [[ $first_func -eq 0 ]]; then
                printf ','
            fi
            first_func=0

            # Extract function metadata
            local fdesc
            fdesc="$(_extract_func_description "$lib_file" "$fline")"

            local outputs
            outputs="$(_func_outputs_stdout "$lib_file" "$fline")"

            local returns_status
            returns_status="$(_func_returns_status "$lib_file" "$fline")"

            # Extract parameters
            local -a param_data=()
            while IFS= read -r pline; do
                [[ -n "$pline" ]] && param_data+=("$pline")
            done < <(_extract_func_params "$lib_file" "$fline")

            _nl
            _json_str "$fname"; printf ':'; _sep; printf '{'
            _push_indent
            _nl
            printf '"description":'; _sep
            if [[ -n "$fdesc" ]]; then
                _json_str "$fdesc"
            else
                printf 'null'
            fi
            printf ','
            _nl
            printf '"params":'; _sep; printf '['

            if [[ ${#param_data[@]} -gt 0 ]]; then
                _push_indent
                local first_param=1
                for pentry in "${param_data[@]}"; do
                    IFS='|' read -r pos pname preq pdefault <<< "$pentry"

                    if [[ $first_param -eq 0 ]]; then
                        printf ','
                    fi
                    first_param=0

                    _nl
                    printf '{'
                    _push_indent
                    _nl
                    printf '"name":'; _sep; _json_str "$pname"
                    printf ','
                    _nl
                    printf '"position":'; _sep; printf '%s' "$pos"
                    printf ','
                    _nl
                    printf '"required":'; _sep; printf '%s' "$preq"
                    printf ','
                    _nl
                    printf '"default":'; _sep
                    if [[ "$pdefault" == "null" ]]; then
                        printf 'null'
                    else
                        _json_str "$pdefault"
                    fi
                    _pop_indent
                    _nl
                    printf '}'
                done
                _pop_indent
                _nl
            fi

            printf ']'
            printf ','
            _nl
            printf '"outputs":'; _sep; printf '%s' "$outputs"
            printf ','
            _nl
            printf '"returns_status":'; _sep; printf '%s' "$returns_status"
            _pop_indent
            _nl
            printf '}'
        done

        _pop_indent
        _nl
        printf '}'  # end functions
        _pop_indent
        _nl
        printf '}'  # end library
    done

    _pop_indent
    _nl
    printf '}'  # end libraries
    printf ','
    _nl
    printf '"total_libraries":'; _sep; printf '%d' "$total_libraries"
    printf ','
    _nl
    printf '"total_functions":'; _sep; printf '%d' "$total_functions"
    _pop_indent
    _nl
    printf '}'  # end root
    printf '\n'
}

# =============================================================================
# ENTRY POINT
# =============================================================================

main() {
    # Verify lib directory exists
    if [[ ! -d "$LIB_DIR" ]]; then
        echo "Error: Library directory not found: $LIB_DIR" >&2
        exit 1
    fi

    # Check for lib files
    local lib_count
    lib_count=$(find "$LIB_DIR" -maxdepth 1 -name "*.sh" ! -name "common.sh" -type f | wc -l)
    if [[ $lib_count -eq 0 ]]; then
        echo "Error: No library files found in $LIB_DIR" >&2
        exit 1
    fi

    if [[ "$OUTPUT_PATH" == "-" ]]; then
        # Write to stdout
        generate_json
    else
        # Write to file
        local output_dir
        output_dir="$(dirname "$OUTPUT_PATH")"
        if [[ ! -d "$output_dir" ]]; then
            mkdir -p "$output_dir"
        fi

        generate_json > "$OUTPUT_PATH"
        echo "Generated $OUTPUT_PATH" >&2
    fi
}

main

#!/usr/bin/env bash
# =============================================================================
# introspect.sh - Runtime Introspection for AI Agents
# =============================================================================
# Description: Provides runtime discovery of MAINFRAME functions and capabilities.
#              AI agents can query function signatures, descriptions, and examples.
# Version: 1.0.0
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_INTROSPECT_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_INTROSPECT_LOADED=1

# =============================================================================
# Global State
# =============================================================================

declare -g _INTROSPECT_META_LOADED=0
declare -g _INTROSPECT_META_JSON=""
declare -gA _INTROSPECT_FUNC_CACHE=()

# =============================================================================
# Internal Functions
# =============================================================================

# Load FUNCTIONS.json into memory (lazy)
_introspect_load_meta() {
    [[ $_INTROSPECT_META_LOADED -eq 1 ]] && return 0

    local meta_file="${MAINFRAME_ROOT:-$HOME/.mainframe}/FUNCTIONS.json"

    if [[ ! -f "$meta_file" ]]; then
        echo "Error: FUNCTIONS.json not found at $meta_file" >&2
        return 1
    fi

    _INTROSPECT_META_JSON=$(<"$meta_file")
    _INTROSPECT_META_LOADED=1
    return 0
}

# Simple JSON string extraction (no jq dependency)
# Usage: _introspect_json_get "$json" "key"
_introspect_json_get() {
    local json="$1"
    local key="$2"

    # Simple extraction for top-level string values
    local pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try numeric/boolean values
    pattern="\"$key\"[[:space:]]*:[[:space:]]*([^,}\]]+)"
    if [[ "$json" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}" | tr -d ' '
        return 0
    fi

    return 1
}

# Extract array values (simple extraction for examples)
# Usage: _introspect_json_array "$json" "key"
_introspect_json_array() {
    local json="$1"
    local key="$2"

    local pattern="\"$key\"[[:space:]]*:[[:space:]]*\[([^\]]*)\]"
    if [[ "$json" =~ $pattern ]]; then
        local array_content="${BASH_REMATCH[1]}"
        # Remove quotes and commas, print one per line
        echo "$array_content" | sed 's/"//g' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        return 0
    fi

    return 1
}

# Find function metadata in FUNCTIONS.json
_introspect_find_function() {
    local func_name="$1"

    # Check cache first
    if [[ -n "${_INTROSPECT_FUNC_CACHE[$func_name]:-}" ]]; then
        printf '%s' "${_INTROSPECT_FUNC_CACHE[$func_name]}"
        return 0
    fi

    _introspect_load_meta || return 1

    # Use grep to find the function block (more reliable than regex for large JSON)
    local in_function=0
    local brace_count=0
    local func_json=""
    local line

    while IFS= read -r line; do
        if [[ $in_function -eq 0 ]]; then
            if [[ "$line" =~ \"$func_name\"[[:space:]]*:[[:space:]]*\{ ]]; then
                in_function=1
                brace_count=1
                func_json="{"
                continue
            fi
        else
            func_json+="$line"

            # Count braces
            local open="${line//[^\{]/}"
            local close="${line//[^\}]/}"
            brace_count=$((brace_count + ${#open} - ${#close}))

            if [[ $brace_count -eq 0 ]]; then
                # Found complete function block
                _INTROSPECT_FUNC_CACHE[$func_name]="$func_json"
                printf '%s' "$func_json"
                return 0
            fi
        fi
    done <<< "$_INTROSPECT_META_JSON"

    return 1
}

# =============================================================================
# Public API
# =============================================================================

# mainframe_describe - Get full documentation for a function
# Usage: mainframe_describe <function_name> [--format json|human]
mainframe_describe() {
    local func_name="$1"
    local format="${2:-human}"

    [[ -z "$func_name" ]] && {
        echo "Usage: mainframe_describe <function_name> [--format json|human]" >&2
        return 1
    }

    [[ "$2" == "--format" ]] && format="$3"

    local func_json
    func_json=$(_introspect_find_function "$func_name") || {
        echo "Error: Function '$func_name' not found" >&2
        return 1
    }

    local description signature returns idempotent pure
    description=$(_introspect_json_get "$func_json" "description")
    signature=$(_introspect_json_get "$func_json" "signature")
    returns=$(_introspect_json_get "$func_json" "returns")
    idempotent=$(_introspect_json_get "$func_json" "idempotent")
    pure=$(_introspect_json_get "$func_json" "pure")

    case "$format" in
        json)
            printf '{"function":"%s","description":"%s","signature":"%s","returns":"%s","idempotent":%s,"pure":%s}\n' \
                "$func_name" "$description" "$signature" "$returns" "${idempotent:-false}" "${pure:-false}"
            ;;
        human|*)
            echo "Function: $func_name"
            echo ""
            echo "Description:"
            echo "  $description"
            echo ""
            echo "Signature:"
            echo "  $signature"
            echo ""
            echo "Returns: $returns"
            echo ""
            echo "Properties:"
            echo "  Idempotent: ${idempotent:-false}"
            echo "  Pure: ${pure:-false}"

            # Extract and display examples if available
            local examples
            examples=$(_introspect_json_array "$func_json" "examples")
            if [[ -n "$examples" ]]; then
                echo ""
                echo "Examples:"
                while IFS= read -r example; do
                    [[ -n "$example" ]] && echo "  $example"
                done <<< "$examples"
            fi
            ;;
    esac
}

# mainframe_signature - Get just the function signature
# Usage: mainframe_signature <function_name>
mainframe_signature() {
    local func_name="$1"

    [[ -z "$func_name" ]] && {
        echo "Usage: mainframe_signature <function_name>" >&2
        return 1
    }

    local func_json
    func_json=$(_introspect_find_function "$func_name") || {
        echo "Error: Function '$func_name' not found" >&2
        return 1
    }

    _introspect_json_get "$func_json" "signature"
    echo
}

# mainframe_capabilities - List available categories and counts
# Usage: mainframe_capabilities [category] [--format json|human]
mainframe_capabilities() {
    local category="${1:-}"
    local format="human"

    [[ "$1" == "--format" ]] && { category=""; format="$2"; }
    [[ "$2" == "--format" ]] && format="$3"

    _introspect_load_meta || return 1

    # Extract version and stats
    local version total_functions total_libraries
    version=$(_introspect_json_get "$_INTROSPECT_META_JSON" "version")
    total_functions=$(_introspect_json_get "$_INTROSPECT_META_JSON" "total_functions")
    total_libraries=$(_introspect_json_get "$_INTROSPECT_META_JSON" "total_libraries")

    # Get stats from the stats block
    local stats_pattern='"stats"[[:space:]]*:[[:space:]]*\{([^}]+)\}'
    if [[ "$_INTROSPECT_META_JSON" =~ $stats_pattern ]]; then
        local stats_block="${BASH_REMATCH[1]}"
        [[ -z "$total_functions" ]] && total_functions=$(_introspect_json_get "{$stats_block}" "total_functions")
        [[ -z "$total_libraries" ]] && total_libraries=$(_introspect_json_get "{$stats_block}" "total_libraries")
    fi

    case "$format" in
        json)
            printf '{"version":"%s","total_functions":%s,"total_libraries":%s}\n' \
                "$version" "${total_functions:-0}" "${total_libraries:-0}"
            ;;
        human|*)
            echo "MAINFRAME Capabilities"
            echo "======================"
            echo ""
            echo "Version: $version"
            echo "Total Functions: ${total_functions:-unknown}"
            echo "Total Libraries: ${total_libraries:-unknown}"
            echo ""
            echo "Use 'mainframe_describe <function>' for details"
            echo "Use 'mainframe_search <query>' to find functions"
            ;;
    esac
}

# mainframe_search - Search for functions by keyword
# Usage: mainframe_search <query> [--limit N]
mainframe_search() {
    local query="$1"
    local limit="${2:-10}"

    [[ "$2" == "--limit" ]] && limit="$3"

    [[ -z "$query" ]] && {
        echo "Usage: mainframe_search <query> [--limit N]" >&2
        return 1
    }

    _introspect_load_meta || return 1

    # Convert query to lowercase for case-insensitive search
    local query_lower="${query,,}"

    # Search through function names and descriptions
    local count=0
    local func_name description

    # Extract function names using grep
    while IFS= read -r func_name; do
        [[ -z "$func_name" ]] && continue
        [[ $count -ge $limit ]] && break

        # Check if function name matches
        local func_lower="${func_name,,}"
        if [[ "$func_lower" == *"$query_lower"* ]]; then
            local func_json
            func_json=$(_introspect_find_function "$func_name") 2>/dev/null || continue
            description=$(_introspect_json_get "$func_json" "description")
            printf '%-30s %s\n' "$func_name" "$description"
            ((count++))
        fi
    done < <(grep -oE '"[a-z_][a-z0-9_]*"[[:space:]]*:[[:space:]]*\{[[:space:]]*"description"' "${MAINFRAME_ROOT:-$HOME/.mainframe}/FUNCTIONS.json" 2>/dev/null | \
             grep -oE '"[a-z_][a-z0-9_]*"' | tr -d '"' | sort -u)

    [[ $count -eq 0 ]] && echo "No functions found matching '$query'"
}

# mainframe_version - Show MAINFRAME version info
# Usage: mainframe_version [--format json|human]
mainframe_version() {
    local format="${1:-human}"
    [[ "$1" == "--format" ]] && format="$2"

    _introspect_load_meta || return 1

    local version generated
    version=$(_introspect_json_get "$_INTROSPECT_META_JSON" "version")
    generated=$(_introspect_json_get "$_INTROSPECT_META_JSON" "generated")

    case "$format" in
        json)
            printf '{"version":"%s","generated":"%s"}\n' "$version" "$generated"
            ;;
        human|*)
            echo "MAINFRAME v${version}"
            echo "Generated: $generated"
            ;;
    esac
}

# =============================================================================
# Module Exports
# =============================================================================

declare -ga _INTROSPECT_EXPORTS=(
    mainframe_describe
    mainframe_signature
    mainframe_capabilities
    mainframe_search
    mainframe_version
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_INTROSPECT_EXPORTS[@]}" 2>/dev/null || true
fi

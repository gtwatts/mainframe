#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/registry.sh - Function Scanner and Catalog System
# =============================================================================
# Description: Automated function discovery, metadata extraction, and catalog
#              generation for the MAINFRAME library ecosystem. Scans bash source
#              files, extracts docstrings, and maintains a searchable registry.
# Version: 1.0.0
# Requires: Bash 4.0+, grep, awk
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_REGISTRY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_REGISTRY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Registry cache directory
MAINFRAME_REGISTRY_DIR="${MAINFRAME_REGISTRY_DIR:-$HOME/.mainframe/registry}"

# Cache TTL in seconds (default 1 hour)
MAINFRAME_REGISTRY_TTL="${MAINFRAME_REGISTRY_TTL:-3600}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Main registry: associative array keyed by function name
declare -gA _REGISTRY_FUNCTIONS=()

# Library metadata: associative array keyed by library name
declare -gA _REGISTRY_LIBRARIES=()

# Category index: comma-separated function names per category
declare -gA _REGISTRY_CATEGORIES=()

# Library index: comma-separated function names per library
declare -gA _REGISTRY_BY_LIBRARY=()

# Statistics
declare -gi _REGISTRY_TOTAL_FUNCTIONS=0
declare -gi _REGISTRY_TOTAL_LIBRARIES=0
declare -g _REGISTRY_LAST_SCAN=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Delegate to centralized logging (with fallback for standalone testing)
_registry_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "registry" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[registry] %s: %s\n' "$level" "$*" >&2
        :  # Ensure return 0 even when quiet mode suppresses output
    fi
}

# Get epoch seconds
_registry_epoch() {
    local ts
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    elif printf -v ts '%(%s)T' -1 2>/dev/null && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}

# Get ISO timestamp
_registry_timestamp() {
    if date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; then
        :
    else
        printf '%s' "$(date +%Y-%m-%dT%H:%M:%S)Z"
    fi
}

# Escape JSON string (basic)
_registry_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Initialize registry directory
_registry_init_dir() {
    if [[ ! -d "$MAINFRAME_REGISTRY_DIR" ]]; then
        mkdir -p "$MAINFRAME_REGISTRY_DIR" 2>/dev/null || {
            _registry_log error "Cannot create registry directory: $MAINFRAME_REGISTRY_DIR"
            return 1
        }
    fi
    return 0
}

# =============================================================================
# DOCSTRING PARSING
# =============================================================================

# @name: _registry_parse_docstring
# @description: Parse function docstrings from a block of comment lines
# @param block: string - The comment block preceding a function
# @returns: JSON object with parsed metadata
_registry_parse_docstring() {
    local block="$1"
    local name="" description="" category="" since="" deprecated=""
    local -a params=() examples=()
    local returns_type="" returns_desc=""

    # Process line by line
    local line key value
    while IFS= read -r line; do
        # Strip leading # and whitespace
        line="${line#\#}"
        line="${line#"${line%%[![:space:]]*}"}"

        # Parse @tag: value format OR @tag value: format (for @param)
        if [[ "$line" =~ ^@([a-z_]+):[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            case "$key" in
                name)
                    name="$value"
                    ;;
                description|desc)
                    description="$value"
                    ;;
                param)
                    # Format: name: type - Description
                    params+=("$value")
                    ;;
                returns|return)
                    # Format: type - Description
                    if [[ "$value" =~ ^([^-]+)-[[:space:]]*(.*)$ ]]; then
                        returns_type="${BASH_REMATCH[1]}"
                        returns_type="${returns_type%"${returns_type##*[![:space:]]}"}"
                        returns_desc="${BASH_REMATCH[2]}"
                    else
                        returns_type="$value"
                    fi
                    ;;
                example)
                    examples+=("$value")
                    ;;
                category)
                    category="$value"
                    ;;
                since)
                    since="$value"
                    ;;
                deprecated)
                    deprecated="$value"
                    ;;
            esac
        # Handle @param name: type - desc format (no colon after @param)
        elif [[ "$line" =~ ^@param[[:space:]]+(.*)$ ]]; then
            params+=("${BASH_REMATCH[1]}")
        # Handle @example value format (no colon)
        elif [[ "$line" =~ ^@example[[:space:]]+(.*)$ ]]; then
            examples+=("${BASH_REMATCH[1]}")
        # Handle @returns type - desc format (no colon)
        elif [[ "$line" =~ ^@returns?[[:space:]]+(.*)$ ]]; then
            local value="${BASH_REMATCH[1]}"
            if [[ "$value" =~ ^([^-]+)-[[:space:]]*(.*)$ ]]; then
                returns_type="${BASH_REMATCH[1]}"
                returns_type="${returns_type%"${returns_type##*[![:space:]]}"}"
                returns_desc="${BASH_REMATCH[2]}"
            else
                returns_type="$value"
            fi
        # Handle @idempotent marker (no colon)
        elif [[ "$line" =~ ^@idempotent$ ]]; then
            # Mark as idempotent (handled later)
            :
        # Handle plain description line (no tag)
        elif [[ -n "$line" && -z "$description" && ! "$line" =~ ^@ ]]; then
            description="$line"
        fi
    done <<< "$block"

    # Build params JSON array
    local params_json="["
    local first=true
    local param_name param_type param_desc
    for param in "${params[@]}"; do
        $first || params_json+=","
        first=false

        # Parse: name: type - Description
        if [[ "$param" =~ ^([^:]+):[[:space:]]*([^-]+)-[[:space:]]*(.*)$ ]]; then
            param_name="${BASH_REMATCH[1]}"
            param_name="${param_name%"${param_name##*[![:space:]]}"}"
            param_type="${BASH_REMATCH[2]}"
            param_type="${param_type%"${param_type##*[![:space:]]}"}"
            param_desc="${BASH_REMATCH[3]}"
            params_json+="{\"name\":\"$(_registry_json_escape "$param_name")\","
            params_json+="\"type\":\"$(_registry_json_escape "$param_type")\","
            params_json+="\"description\":\"$(_registry_json_escape "$param_desc")\"}"
        elif [[ "$param" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
            # Just name: type
            param_name="${BASH_REMATCH[1]}"
            param_name="${param_name%"${param_name##*[![:space:]]}"}"
            param_type="${BASH_REMATCH[2]}"
            params_json+="{\"name\":\"$(_registry_json_escape "$param_name")\","
            params_json+="\"type\":\"$(_registry_json_escape "$param_type")\"}"
        else
            # Just name or description
            params_json+="{\"name\":\"$(_registry_json_escape "$param")\"}"
        fi
    done
    params_json+="]"

    # Build examples JSON array
    local examples_json="["
    first=true
    for ex in "${examples[@]}"; do
        $first || examples_json+=","
        first=false
        examples_json+="\"$(_registry_json_escape "$ex")\""
    done
    examples_json+="]"

    # Output JSON
    printf '{'
    printf '"name":"%s",' "$(_registry_json_escape "$name")"
    printf '"description":"%s",' "$(_registry_json_escape "$description")"
    printf '"params":%s,' "$params_json"
    printf '"returns":{"type":"%s","description":"%s"},' \
        "$(_registry_json_escape "$returns_type")" "$(_registry_json_escape "$returns_desc")"
    printf '"examples":%s,' "$examples_json"
    printf '"category":"%s",' "$(_registry_json_escape "$category")"
    printf '"since":"%s",' "$(_registry_json_escape "$since")"
    printf '"deprecated":"%s"' "$(_registry_json_escape "$deprecated")"
    printf '}'
}

# =============================================================================
# CORE SCANNING FUNCTIONS
# =============================================================================

# @name: registry_scan
# @description: Scan a single library file and extract function metadata
# @param file: string - Path to the library file to scan
# @returns: Number of functions found
# @example: registry_scan "lib/json.sh"
# @category: registry
# @since: v1.0
registry_scan() {
    local file="$1"

    if [[ -z "$file" ]]; then
        _registry_log error "registry_scan: file path required"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        _registry_log error "registry_scan: file not found: $file"
        return 1
    fi

    local library_name
    library_name=$(basename "$file" .sh)

    _registry_log debug "Scanning library: $library_name"

    local line_num=0
    local function_count=0
    local in_docstring=false
    local docstring_buffer=""
    local current_line=""
    local func_name=""
    local library_funcs=""

    # Clear previous entries for this library
    local old_funcs="${_REGISTRY_BY_LIBRARY[$library_name]:-}"
    local old_func
    if [[ -n "$old_funcs" ]]; then
        IFS=',' read -ra old_func_array <<< "$old_funcs"
        for old_func in "${old_func_array[@]}"; do
            unset "_REGISTRY_FUNCTIONS[$old_func]"
        done
    fi
    _REGISTRY_BY_LIBRARY["$library_name"]=""

    while IFS= read -r current_line || [[ -n "$current_line" ]]; do
        (( ++line_num )) || true

        # Check for docstring start (comment line)
        if [[ "$current_line" =~ ^[[:space:]]*#[[:space:]]*@ ]]; then
            in_docstring=true
            docstring_buffer+="${current_line}"$'\n'
        elif [[ "$in_docstring" == true && "$current_line" =~ ^[[:space:]]*# ]]; then
            # Continue docstring
            docstring_buffer+="${current_line}"$'\n'
        elif [[ "$current_line" =~ ^[[:space:]]*(function[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\) ]]; then
            # Function definition found
            func_name="${BASH_REMATCH[2]}"

            # Skip internal functions (starting with _)
            if [[ "$func_name" != _* ]]; then
                local metadata
                if [[ -n "$docstring_buffer" ]]; then
                    metadata=$(_registry_parse_docstring "$docstring_buffer")
                else
                    # Basic extraction without docstring
                    metadata="{\"name\":\"$func_name\",\"description\":\"\",\"params\":[],\"returns\":{\"type\":\"\",\"description\":\"\"},\"examples\":[],\"category\":\"\",\"since\":\"\",\"deprecated\":\"\"}"
                fi

                # Add library and line_number to metadata
                local full_metadata
                full_metadata="${metadata%\}}"
                full_metadata+=",\"library\":\"${library_name}.sh\","
                full_metadata+="\"line_number\":$line_num}"

                # Store in registry
                _REGISTRY_FUNCTIONS["$func_name"]="$full_metadata"

                # Add to library index
                if [[ -n "$library_funcs" ]]; then
                    library_funcs+=","
                fi
                library_funcs+="$func_name"

                # Add to category index
                local cat
                if [[ "$metadata" =~ \"category\":\"([^\"]+)\" ]]; then
                    cat="${BASH_REMATCH[1]}"
                    if [[ -n "$cat" ]]; then
                        if [[ -n "${_REGISTRY_CATEGORIES[$cat]:-}" ]]; then
                            _REGISTRY_CATEGORIES["$cat"]+=","
                        fi
                        _REGISTRY_CATEGORIES["$cat"]+="$func_name"
                    fi
                fi

                (( ++function_count )) || true
                _registry_log debug "Found function: $func_name (line $line_num)"
            fi

            # Reset docstring
            in_docstring=false
            docstring_buffer=""
        else
            # Not a docstring or function - reset
            if [[ ! "$current_line" =~ ^[[:space:]]*# ]]; then
                in_docstring=false
                docstring_buffer=""
            fi
        fi
    done < "$file"

    # Store library metadata
    _REGISTRY_BY_LIBRARY["$library_name"]="$library_funcs"
    _REGISTRY_LIBRARIES["$library_name"]="{\"file\":\"$file\",\"function_count\":$function_count}"

    _registry_log info "Scanned $library_name: $function_count functions"

    printf '%d' "$function_count"
}

# @name: registry_scan_all
# @description: Scan all libraries in the lib/ directory
# @returns: Total number of functions found across all libraries
# @example: registry_scan_all
# @category: registry
# @since: v1.0
registry_scan_all() {
    local lib_dir="${MAINFRAME_ROOT:-$HOME/.mainframe}/lib"

    if [[ ! -d "$lib_dir" ]]; then
        _registry_log error "Library directory not found: $lib_dir"
        return 1
    fi

    _registry_log info "Scanning all libraries in $lib_dir"

    local total=0
    local count=0
    local lib_file

    # Clear existing data
    _REGISTRY_FUNCTIONS=()
    _REGISTRY_LIBRARIES=()
    _REGISTRY_CATEGORIES=()
    _REGISTRY_BY_LIBRARY=()
    _REGISTRY_TOTAL_FUNCTIONS=0
    _REGISTRY_TOTAL_LIBRARIES=0

    for lib_file in "$lib_dir"/*.sh; do
        [[ -f "$lib_file" ]] || continue

        # Skip common.sh (it's the loader, not a function library)
        [[ "$(basename "$lib_file")" == "common.sh" ]] && continue

        # Call registry_scan and capture output via process substitution
        # This preserves array modifications in the current shell
        local _prev_count=${#_REGISTRY_FUNCTIONS[@]}
        registry_scan "$lib_file" >/dev/null
        local _new_count=${#_REGISTRY_FUNCTIONS[@]}
        count=$((_new_count - _prev_count))
        (( total += count )) || true
        (( ++_REGISTRY_TOTAL_LIBRARIES )) || true
    done

    _REGISTRY_TOTAL_FUNCTIONS=$total
    _REGISTRY_LAST_SCAN=$(_registry_timestamp)

    _registry_log info "Scan complete: $total functions in $_REGISTRY_TOTAL_LIBRARIES libraries"

    printf '%d' "$total"
}

# =============================================================================
# QUERY FUNCTIONS
# =============================================================================

# @name: registry_get_function
# @description: Get metadata for a specific function by name
# @param name: string - The function name to look up
# @returns: JSON object with function metadata, or empty on not found
# @example: registry_get_function "json_object"
# @category: registry
# @since: v1.0
registry_get_function() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _registry_log error "registry_get_function: function name required"
        return 1
    fi

    local metadata="${_REGISTRY_FUNCTIONS[$name]:-}"

    if [[ -z "$metadata" ]]; then
        _registry_log debug "Function not found: $name"
        return 1
    fi

    printf '%s\n' "$metadata"
}

# @name: registry_list_by_category
# @description: List all functions in a specific category
# @param category: string - The category name (e.g., "validation", "json")
# @returns: JSON array of function metadata objects
# @example: registry_list_by_category "validation"
# @category: registry
# @since: v1.0
registry_list_by_category() {
    local category="$1"

    if [[ -z "$category" ]]; then
        _registry_log error "registry_list_by_category: category name required"
        return 1
    fi

    local funcs="${_REGISTRY_CATEGORIES[$category]:-}"

    if [[ -z "$funcs" ]]; then
        printf '[]\n'
        return 0
    fi

    printf '['
    local first=true
    local func_name
    IFS=',' read -ra func_array <<< "$funcs"
    for func_name in "${func_array[@]}"; do
        local metadata="${_REGISTRY_FUNCTIONS[$func_name]:-}"
        if [[ -n "$metadata" ]]; then
            $first || printf ','
            first=false
            printf '%s' "$metadata"
        fi
    done
    printf ']\n'
}

# @name: registry_list_by_library
# @description: List all functions from a specific library file
# @param library: string - The library name (with or without .sh extension)
# @returns: JSON array of function metadata objects
# @example: registry_list_by_library "json.sh"
# @category: registry
# @since: v1.0
registry_list_by_library() {
    local library="$1"

    if [[ -z "$library" ]]; then
        _registry_log error "registry_list_by_library: library name required"
        return 1
    fi

    # Strip .sh extension if present
    library="${library%.sh}"

    local funcs="${_REGISTRY_BY_LIBRARY[$library]:-}"

    if [[ -z "$funcs" ]]; then
        printf '[]\n'
        return 0
    fi

    printf '['
    local first=true
    local func_name
    IFS=',' read -ra func_array <<< "$funcs"
    for func_name in "${func_array[@]}"; do
        local metadata="${_REGISTRY_FUNCTIONS[$func_name]:-}"
        if [[ -n "$metadata" ]]; then
            $first || printf ','
            first=false
            printf '%s' "$metadata"
        fi
    done
    printf ']\n'
}

# @name: registry_search
# @description: Search functions by name or description pattern
# @param pattern: string - Search pattern (glob or substring)
# @returns: JSON array of matching function metadata objects
# @example: registry_search "json"
# @category: registry
# @since: v1.0
# Search registry functions by description keyword (prints matching function names)
registry_search() {
    local pattern="$1"

    if [[ -z "$pattern" ]]; then
        _registry_log error "registry_search: search pattern required"
        return 1
    fi

    # Convert to lowercase for case-insensitive search
    local pattern_lower="${pattern,,}"

    printf '['
    local first=true
    local func_name metadata name_lower desc_lower

    for func_name in "${!_REGISTRY_FUNCTIONS[@]}"; do
        metadata="${_REGISTRY_FUNCTIONS[$func_name]}"
        name_lower="${func_name,,}"

        # Search in function name
        if [[ "$name_lower" == *"$pattern_lower"* ]]; then
            $first || printf ','
            first=false
            printf '%s' "$metadata"
            continue
        fi

        # Search in description
        if [[ "$metadata" =~ \"description\":\"([^\"]+)\" ]]; then
            desc_lower="${BASH_REMATCH[1],,}"
            if [[ "$desc_lower" == *"$pattern_lower"* ]]; then
                $first || printf ','
                first=false
                printf '%s' "$metadata"
            fi
        fi
    done
    printf ']\n'
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# @name: registry_export
# @description: Export the full registry to a JSON file
# @param file: string - Output file path
# @returns: 0 on success, 1 on failure
# @example: registry_export "functions.json"
# @category: registry
# @since: v1.0
registry_export() {
    local file="$1"

    if [[ -z "$file" ]]; then
        _registry_log error "registry_export: output file path required"
        return 1
    fi

    local timestamp
    timestamp=$(_registry_timestamp)

    # Build libraries object
    local libs_json="{"
    local first=true
    local lib_name lib_funcs func_list func_name

    for lib_name in "${!_REGISTRY_BY_LIBRARY[@]}"; do
        $first || libs_json+=","
        first=false

        lib_funcs="${_REGISTRY_BY_LIBRARY[$lib_name]}"
        func_list="{"
        local func_first=true

        if [[ -n "$lib_funcs" ]]; then
            IFS=',' read -ra func_array <<< "$lib_funcs"
            for func_name in "${func_array[@]}"; do
                local metadata="${_REGISTRY_FUNCTIONS[$func_name]:-}"
                if [[ -n "$metadata" ]]; then
                    $func_first || func_list+=","
                    func_first=false
                    func_list+="\"$func_name\":$metadata"
                fi
            done
        fi
        func_list+="}"

        # Get library file path
        local lib_meta="${_REGISTRY_LIBRARIES[$lib_name]:-}"
        local lib_file="lib/${lib_name}.sh"
        local lib_count=0
        if [[ "$lib_meta" =~ \"function_count\":([0-9]+) ]]; then
            lib_count="${BASH_REMATCH[1]}"
        fi

        libs_json+="\"$lib_name\":{"
        libs_json+="\"file\":\"$lib_file\","
        libs_json+="\"function_count\":$lib_count,"
        libs_json+="\"functions\":$func_list"
        libs_json+="}"
    done
    libs_json+="}"

    # Build categories array
    local cats_json="["
    first=true
    for cat in "${!_REGISTRY_CATEGORIES[@]}"; do
        $first || cats_json+=","
        first=false
        cats_json+="\"$cat\""
    done
    cats_json+="]"

    # Build full export
    {
        printf '{\n'
        printf '  "version": "1.0.0",\n'
        printf '  "generated": "%s",\n' "$timestamp"
        printf '  "stats": {\n'
        printf '    "total_functions": %d,\n' "$_REGISTRY_TOTAL_FUNCTIONS"
        printf '    "total_libraries": %d,\n' "$_REGISTRY_TOTAL_LIBRARIES"
        printf '    "categories": %s\n' "$cats_json"
        printf '  },\n'
        printf '  "libraries": %s\n' "$libs_json"
        printf '}\n'
    } > "$file"

    _registry_log info "Exported registry to $file"
    return 0
}

# =============================================================================
# STATISTICS
# =============================================================================

# @name: registry_stats
# @description: Get statistics about the registry
# @returns: JSON object with statistics
# @example: registry_stats
# @category: registry
# @since: v1.0
registry_stats() {
    local cats_count=0
    local cat
    for cat in "${!_REGISTRY_CATEGORIES[@]}"; do
        (( ++cats_count )) || true
    done

    printf '{'
    printf '"total_functions":%d,' "$_REGISTRY_TOTAL_FUNCTIONS"
    printf '"total_libraries":%d,' "$_REGISTRY_TOTAL_LIBRARIES"
    printf '"total_categories":%d,' "$cats_count"
    printf '"last_scan":"%s",' "$_REGISTRY_LAST_SCAN"
    printf '"categories":{'

    local first=true
    for cat in "${!_REGISTRY_CATEGORIES[@]}"; do
        local funcs="${_REGISTRY_CATEGORIES[$cat]}"
        local count=0
        if [[ -n "$funcs" ]]; then
            IFS=',' read -ra func_array <<< "$funcs"
            count=${#func_array[@]}
        fi
        $first || printf ','
        first=false
        printf '"%s":%d' "$cat" "$count"
    done

    printf '},'
    printf '"libraries":{'

    first=true
    for lib in "${!_REGISTRY_BY_LIBRARY[@]}"; do
        local funcs="${_REGISTRY_BY_LIBRARY[$lib]}"
        local count=0
        if [[ -n "$funcs" ]]; then
            IFS=',' read -ra func_array <<< "$funcs"
            count=${#func_array[@]}
        fi
        $first || printf ','
        first=false
        printf '"%s":%d' "$lib" "$count"
    done

    printf '}'
    printf '}\n'
}

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

# @name: registry_save_cache
# @description: Save registry to disk cache for faster subsequent loads
# @returns: 0 on success, 1 on failure
# @example: registry_save_cache
# @category: registry
# @since: v1.0
registry_save_cache() {
    _registry_init_dir || return 1

    local cache_file="$MAINFRAME_REGISTRY_DIR/registry.cache"

    # Save each associative array
    {
        printf 'REGISTRY_VERSION=1\n'
        printf 'REGISTRY_TIMESTAMP=%s\n' "$(_registry_epoch)"
        printf 'TOTAL_FUNCTIONS=%d\n' "$_REGISTRY_TOTAL_FUNCTIONS"
        printf 'TOTAL_LIBRARIES=%d\n' "$_REGISTRY_TOTAL_LIBRARIES"
        printf 'LAST_SCAN=%s\n' "$_REGISTRY_LAST_SCAN"

        # Functions
        printf 'BEGIN_FUNCTIONS\n'
        for key in "${!_REGISTRY_FUNCTIONS[@]}"; do
            printf '%s\t%s\n' "$key" "${_REGISTRY_FUNCTIONS[$key]}"
        done
        printf 'END_FUNCTIONS\n'

        # Libraries
        printf 'BEGIN_LIBRARIES\n'
        for key in "${!_REGISTRY_LIBRARIES[@]}"; do
            printf '%s\t%s\n' "$key" "${_REGISTRY_LIBRARIES[$key]}"
        done
        printf 'END_LIBRARIES\n'

        # Categories
        printf 'BEGIN_CATEGORIES\n'
        for key in "${!_REGISTRY_CATEGORIES[@]}"; do
            printf '%s\t%s\n' "$key" "${_REGISTRY_CATEGORIES[$key]}"
        done
        printf 'END_CATEGORIES\n'

        # By Library
        printf 'BEGIN_BY_LIBRARY\n'
        for key in "${!_REGISTRY_BY_LIBRARY[@]}"; do
            printf '%s\t%s\n' "$key" "${_REGISTRY_BY_LIBRARY[$key]}"
        done
        printf 'END_BY_LIBRARY\n'
    } > "$cache_file"

    _registry_log info "Saved registry cache"
    return 0
}

# @name: registry_load_cache
# @description: Load registry from disk cache if available and not expired
# @returns: 0 if cache loaded, 1 if cache missing or expired
# @example: registry_load_cache
# @category: registry
# @since: v1.0
registry_load_cache() {
    local cache_file="$MAINFRAME_REGISTRY_DIR/registry.cache"

    if [[ ! -f "$cache_file" ]]; then
        _registry_log debug "No cache file found"
        return 1
    fi

    # Check TTL
    local cache_time current_time
    cache_time=$(grep -m1 '^REGISTRY_TIMESTAMP=' "$cache_file" 2>/dev/null | cut -d= -f2)
    current_time=$(_registry_epoch)

    if [[ -n "$cache_time" ]]; then
        local age=$((current_time - cache_time))
        if ((age > MAINFRAME_REGISTRY_TTL)); then
            _registry_log debug "Cache expired (age: ${age}s, TTL: ${MAINFRAME_REGISTRY_TTL}s)"
            return 1
        fi
    fi

    # Clear existing data
    _REGISTRY_FUNCTIONS=()
    _REGISTRY_LIBRARIES=()
    _REGISTRY_CATEGORIES=()
    _REGISTRY_BY_LIBRARY=()

    local section=""
    local line key value

    while IFS= read -r line; do
        case "$line" in
            TOTAL_FUNCTIONS=*)
                _REGISTRY_TOTAL_FUNCTIONS="${line#*=}"
                ;;
            TOTAL_LIBRARIES=*)
                _REGISTRY_TOTAL_LIBRARIES="${line#*=}"
                ;;
            LAST_SCAN=*)
                _REGISTRY_LAST_SCAN="${line#*=}"
                ;;
            BEGIN_FUNCTIONS)
                section="functions"
                ;;
            END_FUNCTIONS)
                section=""
                ;;
            BEGIN_LIBRARIES)
                section="libraries"
                ;;
            END_LIBRARIES)
                section=""
                ;;
            BEGIN_CATEGORIES)
                section="categories"
                ;;
            END_CATEGORIES)
                section=""
                ;;
            BEGIN_BY_LIBRARY)
                section="by_library"
                ;;
            END_BY_LIBRARY)
                section=""
                ;;
            *)
                if [[ -n "$section" && "$line" == *$'\t'* ]]; then
                    key="${line%%$'\t'*}"
                    value="${line#*$'\t'}"

                    case "$section" in
                        functions)
                            _REGISTRY_FUNCTIONS["$key"]="$value"
                            ;;
                        libraries)
                            _REGISTRY_LIBRARIES["$key"]="$value"
                            ;;
                        categories)
                            _REGISTRY_CATEGORIES["$key"]="$value"
                            ;;
                        by_library)
                            _REGISTRY_BY_LIBRARY["$key"]="$value"
                            ;;
                    esac
                fi
                ;;
        esac
    done < "$cache_file"

    _registry_log info "Loaded registry from cache"
    return 0
}

# @name: registry_clear_cache
# @description: Clear the registry disk cache
# @returns: 0 on success
# @example: registry_clear_cache
# @category: registry
# @since: v1.0
registry_clear_cache() {
    local cache_file="$MAINFRAME_REGISTRY_DIR/registry.cache"

    if [[ -f "$cache_file" ]]; then
        rm -f "$cache_file"
        _registry_log info "Cleared registry cache"
    fi

    return 0
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# @name: registry_list_categories
# @description: List all available categories
# @returns: JSON array of category names
# @example: registry_list_categories
# @category: registry
# @since: v1.0
registry_list_categories() {
    printf '['
    local first=true
    for cat in "${!_REGISTRY_CATEGORIES[@]}"; do
        $first || printf ','
        first=false
        printf '"%s"' "$cat"
    done
    printf ']\n'
}

# @name: registry_list_libraries
# @description: List all scanned libraries
# @returns: JSON array of library names
# @example: registry_list_libraries
# @category: registry
# @since: v1.0
# List all libraries in the registry (one library name per line)
registry_list_libraries() {
    printf '['
    local first=true
    for lib in "${!_REGISTRY_BY_LIBRARY[@]}"; do
        $first || printf ','
        first=false
        printf '"%s"' "$lib"
    done
    printf ']\n'
}

# @name: registry_function_exists
# @description: Check if a function is registered
# @param name: string - Function name to check
# @returns: 0 if exists, 1 if not
# @example: registry_function_exists "json_object" && echo "Found"
# @category: registry
# @since: v1.0
registry_function_exists() {
    local name="$1"
    [[ -n "${_REGISTRY_FUNCTIONS[$name]:-}" ]]
}

# @name: registry_count
# @description: Get count of registered functions
# @returns: Integer count
# @example: count=$(registry_count)
# @category: registry
# @since: v1.0
registry_count() {
    printf '%d' "${#_REGISTRY_FUNCTIONS[@]}"
}

# @name: registry_list_all
# @description: List all registered function names
# @returns: Newline-separated list of function names
# @example: registry_list_all | head -20
# @category: registry
# @since: v1.0
registry_list_all() {
    for func in "${!_REGISTRY_FUNCTIONS[@]}"; do
        printf '%s\n' "$func"
    done | sort
}


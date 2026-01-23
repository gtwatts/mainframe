#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/parsers.sh - Format Parsers
# =============================================================================
# Description: Pure-bash parsers for common formats: CSV, key-value configs,
#              INI files, URLs, and semantic versions. All output JSON for
#              AI agent consumption.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PARSERS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PARSERS_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_parsers_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# =============================================================================
# CSV PARSING
# =============================================================================

# @pre: line is a CSV-formatted string
# @post: populates PARSE_CSV_FIELDS array with parsed values
# @idempotent: yes
# @returns: 0 on success, 1 on parse error
#
# Parse a single CSV line into the global array PARSE_CSV_FIELDS.
# Handles quoted fields with commas and escaped quotes.
# Uses a global array to avoid subshell overhead.
#
# Usage: parse_csv_line '"John","Doe","New York"'
#        echo "${PARSE_CSV_FIELDS[0]}"  # John
# Example: parse_csv_line "a,b,c" && echo "${#PARSE_CSV_FIELDS[@]}"  # 3
parse_csv_line() {
    local line="$1"
    PARSE_CSV_FIELDS=()

    if [[ -z "$line" ]]; then
        return 0
    fi

    local i=0 len=${#line}
    local field="" in_quotes=false

    while (( i < len )); do
        local ch="${line:$i:1}"

        if [[ "$in_quotes" == "true" ]]; then
            if [[ "$ch" == '"' ]]; then
                # Check for escaped quote (double quote)
                if (( i + 1 < len )) && [[ "${line:$((i+1)):1}" == '"' ]]; then
                    field+='"'
                    i=$((i + 2))
                    continue
                fi
                in_quotes=false
            else
                field+="$ch"
            fi
        else
            if [[ "$ch" == '"' ]]; then
                in_quotes=true
            elif [[ "$ch" == ',' ]]; then
                PARSE_CSV_FIELDS+=("$field")
                field=""
            else
                field+="$ch"
            fi
        fi
        i=$((i + 1))
    done

    # Add last field
    PARSE_CSV_FIELDS+=("$field")
    return 0
}

# @pre: line is a CSV-formatted string
# @post: prints JSON array of field values
# @idempotent: yes
# @returns: 0
#
# Parse a CSV line and return as JSON array.
#
# Usage: json=$(parse_csv_json '"John","30","NYC"')
# Output: ["John","30","NYC"]
parse_csv_json() {
    local line="$1"
    parse_csv_line "$line" || return 1

    local json="["
    local first=true
    for field in "${PARSE_CSV_FIELDS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        local escaped
        escaped=$(_parsers_escape "$field")
        json+="\"$escaped\""
    done
    json+="]"

    printf '%s' "$json"
}

# =============================================================================
# KEY-VALUE PARSING
# =============================================================================

# @pre: input is key=value or key: value format (one per line)
# @post: prints JSON object with parsed key-value pairs
# @idempotent: yes
# @returns: 0
#
# Parse key-value pairs from input. Supports = and : separators,
# strips whitespace, ignores comments (# and ;) and blank lines.
#
# Usage: result=$(parse_key_value < config.txt)
# Usage: result=$(parse_key_value "key1=val1\nkey2=val2")
# Example: echo "host=localhost\nport=5432" | parse_key_value
parse_key_value() {
    local input=""
    if [[ $# -gt 0 ]]; then
        input="$1"
    else
        input=$(cat)
    fi

    if [[ -z "$input" ]]; then
        printf '{}'
        return 0
    fi

    local json="{"
    local first=true
    local line key value

    while IFS= read -r line; do
        # Skip empty lines and comments
        line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        [[ "$line" == ";"* ]] && continue

        # Parse key=value or key: value
        if [[ "$line" == *"="* ]]; then
            key="${line%%=*}"
            value="${line#*=}"
        elif [[ "$line" == *": "* ]]; then
            key="${line%%: *}"
            value="${line#*: }"
        elif [[ "$line" == *":"* ]]; then
            key="${line%%:*}"
            value="${line#*:}"
        else
            continue
        fi

        # Trim whitespace from key and value
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        # Remove surrounding quotes from value
        if [[ "$value" == '"'*'"' ]]; then
            value="${value#\"}"
            value="${value%\"}"
        elif [[ "$value" == "'"*"'" ]]; then
            value="${value#\'}"
            value="${value%\'}"
        fi

        [[ -z "$key" ]] && continue

        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi

        local escaped_key escaped_value
        escaped_key=$(_parsers_escape "$key")
        escaped_value=$(_parsers_escape "$value")
        json+="\"$escaped_key\":\"$escaped_value\""

    done <<< "$input"

    json+="}"
    printf '%s' "$json"
}

# =============================================================================
# INI FILE PARSING
# =============================================================================

# @pre: input is INI-formatted text with [sections]
# @post: prints nested JSON object with sections as keys
# @idempotent: yes
# @returns: 0
#
# Parse an INI file into nested JSON. Sections become top-level keys,
# with key-value pairs as nested objects.
#
# Usage: result=$(parse_ini < config.ini)
# Example: parse_ini "[database]\nhost=localhost\nport=5432"
parse_ini() {
    local input=""
    if [[ $# -gt 0 ]]; then
        input="$1"
    else
        input=$(cat)
    fi

    if [[ -z "$input" ]]; then
        printf '{}'
        return 0
    fi

    local json="{"
    local current_section=""
    local section_json=""
    local first_section=true
    local first_in_section=true
    local line key value

    while IFS= read -r line; do
        # Trim whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        [[ "$line" == ";"* ]] && continue

        # Check for section header
        if [[ "$line" == "["*"]" ]]; then
            # Close previous section
            if [[ -n "$current_section" ]]; then
                section_json+="}"
                if [[ "$first_section" == "true" ]]; then
                    first_section=false
                else
                    json+=","
                fi
                local escaped_section
                escaped_section=$(_parsers_escape "$current_section")
                json+="\"$escaped_section\":$section_json"
            fi

            # Start new section
            current_section="${line#[}"
            current_section="${current_section%]}"
            section_json="{"
            first_in_section=true
            continue
        fi

        # Parse key=value within section
        if [[ "$line" == *"="* ]]; then
            key="${line%%=*}"
            value="${line#*=}"
        elif [[ "$line" == *": "* ]]; then
            key="${line%%: *}"
            value="${line#*: }"
        else
            continue
        fi

        # Trim
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        [[ -z "$key" ]] && continue

        # If no section yet, use "_global"
        if [[ -z "$current_section" ]]; then
            current_section="_global"
            section_json="{"
            first_in_section=true
        fi

        if [[ "$first_in_section" == "true" ]]; then
            first_in_section=false
        else
            section_json+=","
        fi

        local escaped_key escaped_value
        escaped_key=$(_parsers_escape "$key")
        escaped_value=$(_parsers_escape "$value")
        section_json+="\"$escaped_key\":\"$escaped_value\""

    done <<< "$input"

    # Close last section
    if [[ -n "$current_section" ]]; then
        section_json+="}"
        if [[ "$first_section" == "true" ]]; then
            first_section=false
        else
            json+=","
        fi
        local escaped_section
        escaped_section=$(_parsers_escape "$current_section")
        json+="\"$escaped_section\":$section_json"
    fi

    json+="}"
    printf '%s' "$json"
}

# =============================================================================
# URL PARSING
# =============================================================================

# @pre: url is a string (may or may not have scheme)
# @post: prints JSON object with URL components
# @idempotent: yes
# @returns: 0
#
# Parse a URL into its components: scheme, user, password, host, port, path, query, fragment.
# Returns a JSON object.
#
# Usage: result=$(parse_url "https://user:pass@host.com:8080/path?query=1#frag")
# Example: parse_url "http://localhost:3000/api/v1"
parse_url() {
    local url="$1"

    if [[ -z "$url" ]]; then
        printf '{"error":"empty url"}'
        return 1
    fi

    local scheme="" userinfo="" host="" port="" path="" query="" fragment=""

    # Extract fragment
    if [[ "$url" == *"#"* ]]; then
        fragment="${url##*#}"
        url="${url%#*}"
    fi

    # Extract query
    if [[ "$url" == *"?"* ]]; then
        query="${url##*\?}"
        url="${url%\?*}"
    fi

    # Extract scheme
    if [[ "$url" == *"://"* ]]; then
        scheme="${url%%://*}"
        url="${url#*://}"
    fi

    # Extract path
    if [[ "$url" == *"/"* ]]; then
        path="/${url#*/}"
        url="${url%%/*}"
    fi

    # Extract userinfo (user:pass@)
    if [[ "$url" == *"@"* ]]; then
        userinfo="${url%%@*}"
        url="${url#*@}"
    fi

    # Extract port
    if [[ "$url" == *":"* ]]; then
        local maybe_port="${url##*:}"
        if [[ "$maybe_port" =~ ^[0-9]+$ ]]; then
            port="$maybe_port"
            host="${url%:*}"
        else
            host="$url"
        fi
    else
        host="$url"
    fi

    # Build JSON
    local json="{"
    local first=true

    _add_field() {
        local key="$1" val="$2"
        [[ -z "$val" ]] && return
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        local escaped_val
        escaped_val=$(_parsers_escape "$val")
        json+="\"$key\":\"$escaped_val\""
    }

    _add_field "scheme" "$scheme"
    _add_field "host" "$host"
    [[ -n "$port" ]] && { if [[ "$first" == "true" ]]; then first=false; else json+=","; fi; json+="\"port\":$port"; }
    _add_field "path" "$path"
    _add_field "query" "$query"
    _add_field "fragment" "$fragment"

    # Parse userinfo
    if [[ -n "$userinfo" ]]; then
        local user="" pass=""
        if [[ "$userinfo" == *":"* ]]; then
            user="${userinfo%%:*}"
            pass="${userinfo#*:}"
        else
            user="$userinfo"
        fi
        _add_field "user" "$user"
        _add_field "password" "$pass"
    fi

    json+="}"
    printf '%s' "$json"

    unset -f _add_field
}

# =============================================================================
# SEMANTIC VERSION PARSING
# =============================================================================

# @pre: version is a semver-like string
# @post: prints JSON object with parsed components
# @idempotent: yes
# @returns: 0 on valid semver, 1 on invalid
#
# Parse a semantic version string into its components.
# Supports: major.minor.patch[-prerelease][+build]
#
# Usage: result=$(parse_semver "1.2.3-beta.1+build.456")
# Example: parse_semver "2.0.0"
parse_semver() {
    local version="$1"

    if [[ -z "$version" ]]; then
        printf '{"error":"empty version"}'
        return 1
    fi

    # Strip leading 'v' if present
    version="${version#v}"
    version="${version#V}"

    local major="" minor="" patch="" prerelease="" build=""

    # Extract build metadata (+...)
    if [[ "$version" == *"+"* ]]; then
        build="${version##*+}"
        version="${version%+*}"
    fi

    # Extract prerelease (-...)
    if [[ "$version" == *"-"* ]]; then
        prerelease="${version#*-}"
        version="${version%%-*}"
    fi

    # Parse major.minor.patch
    IFS='.' read -r major minor patch <<< "$version"

    # Validate
    if [[ ! "$major" =~ ^[0-9]+$ ]]; then
        printf '{"error":"invalid major version","input":"%s"}' "$major"
        return 1
    fi

    # Default minor and patch to 0
    [[ -z "$minor" ]] && minor="0"
    [[ -z "$patch" ]] && patch="0"

    if [[ ! "$minor" =~ ^[0-9]+$ ]] || [[ ! "$patch" =~ ^[0-9]+$ ]]; then
        printf '{"error":"invalid version components"}'
        return 1
    fi

    local json
    json="{\"major\":$major,\"minor\":$minor,\"patch\":$patch"

    if [[ -n "$prerelease" ]]; then
        local escaped_pre
        escaped_pre=$(_parsers_escape "$prerelease")
        json+=",\"prerelease\":\"$escaped_pre\""
    fi

    if [[ -n "$build" ]]; then
        local escaped_build
        escaped_build=$(_parsers_escape "$build")
        json+=",\"build\":\"$escaped_build\""
    fi

    json+=",\"string\":\"$major.$minor.$patch"
    [[ -n "$prerelease" ]] && json+="-$prerelease"
    [[ -n "$build" ]] && json+="+$build"
    json+="\"}"

    printf '%s' "$json"
}

# @pre: v1 and v2 are semver strings
# @post: prints -1, 0, or 1
# @idempotent: yes
# @returns: 0
#
# Compare two semantic versions. Returns:
#   -1 if v1 < v2
#    0 if v1 == v2
#    1 if v1 > v2
#
# Usage: cmp=$(semver_compare "1.2.3" "1.3.0")
# Example: [[ $(semver_compare "$current" "$required") -ge 0 ]] && echo "OK"
semver_compare() {
    local v1="$1" v2="$2"

    # Strip leading v
    v1="${v1#v}"; v1="${v1#V}"
    v2="${v2#v}"; v2="${v2#V}"

    # Strip prerelease/build for comparison
    local v1_core="${v1%%[-+]*}"
    local v2_core="${v2%%[-+]*}"

    local major1 minor1 patch1
    local major2 minor2 patch2

    IFS='.' read -r major1 minor1 patch1 <<< "$v1_core"
    IFS='.' read -r major2 minor2 patch2 <<< "$v2_core"

    major1="${major1:-0}"; minor1="${minor1:-0}"; patch1="${patch1:-0}"
    major2="${major2:-0}"; minor2="${minor2:-0}"; patch2="${patch2:-0}"

    if (( major1 > major2 )); then printf '1'; return 0; fi
    if (( major1 < major2 )); then printf -- '-1'; return 0; fi
    if (( minor1 > minor2 )); then printf '1'; return 0; fi
    if (( minor1 < minor2 )); then printf -- '-1'; return 0; fi
    if (( patch1 > patch2 )); then printf '1'; return 0; fi
    if (( patch1 < patch2 )); then printf -- '-1'; return 0; fi

    printf '0'
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/burl_ai.sh - Advanced AI-Native HTTP Features
# =============================================================================
# Description: AI-agent-specific HTTP features beyond standard curl/HTTP
#              including pagination autopilot, request chaining, schema
#              validation, rate limit management, response diffing, templates,
#              OAuth2 helpers, and streaming progress downloads.
#
# Dependencies: http.sh, output.sh, json.sh, cache.sh (optional)
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_BURL_AI_LOADED:-}" ]] && return 0
readonly _MAINFRAME_BURL_AI_LOADED=1

# =============================================================================
# AUTO-SOURCE DEPENDENCIES
# =============================================================================

_BURL_AI_LIB_DIR="${BASH_SOURCE[0]%/*}"

# Source http.sh if not already loaded
if ! declare -F http_get &>/dev/null; then
    if [[ -f "${_BURL_AI_LIB_DIR}/http.sh" ]]; then
        source "${_BURL_AI_LIB_DIR}/http.sh"
    else
        printf 'burl_ai.sh: required dependency http.sh not found\n' >&2
        return 1
    fi
fi

# Source output.sh if not already loaded
if ! declare -F output_json_object &>/dev/null; then
    if [[ -f "${_BURL_AI_LIB_DIR}/output.sh" ]]; then
        source "${_BURL_AI_LIB_DIR}/output.sh"
    fi
fi

# Source json.sh if not already loaded
if ! declare -F json_object &>/dev/null; then
    if [[ -f "${_BURL_AI_LIB_DIR}/json.sh" ]]; then
        source "${_BURL_AI_LIB_DIR}/json.sh"
    fi
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default pagination limits
BURL_AI_MAX_PAGES="${BURL_AI_MAX_PAGES:-10}"
BURL_AI_PAGE_DELAY="${BURL_AI_PAGE_DELAY:-0}"

# Rate limit state directory
BURL_AI_RATE_LIMIT_DIR="${BURL_AI_RATE_LIMIT_DIR:-${TMPDIR:-/tmp}/burl_rate_limits}"

# Response cache directory
BURL_AI_CACHE_DIR="${BURL_AI_CACHE_DIR:-${TMPDIR:-/tmp}/burl_cache}"

# Template registry
declare -gA _BURL_AI_TEMPLATES=()

# OAuth2 token cache
declare -gA _BURL_AI_OAUTH_TOKENS=()
declare -gA _BURL_AI_OAUTH_EXPIRY=()

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_burl_ai_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[burl_ai] %s: %s\n' "$level" "$*" >&2
    fi
}

_burl_ai_now() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        printf '%s' "$EPOCHSECONDS"
    else
        date +%s
    fi
}

_burl_ai_sha256() {
    local input="$1"
    if type -p sha256sum &>/dev/null; then
        printf '%s' "$input" | sha256sum | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 256 | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha256 | awk '{print $NF}'
    else
        # Fallback: simple hash using bash
        printf '%s' "$input" | cksum | cut -d' ' -f1
    fi
}

# =============================================================================
# 1. PAGINATION AUTOPILOT
# =============================================================================

# Internal: Detect pagination type from response
# @param $1 - response body
# @param $2 - response headers
# Returns: "link_header" | "json_field" | "none"
_burl_detect_pagination() {
    local body="$1"
    local headers="$2"

    # Check for Link header (RFC 5988)
    if [[ "$headers" =~ [Ll]ink:.*rel=\"?next\"? ]]; then
        printf 'link_header'
        return 0
    fi

    # Check for common JSON pagination fields
    local pagination_fields=("next_page" "nextPage" "next_url" "nextUrl" "next" "links.next" "paging.next")

    for field in "${pagination_fields[@]}"; do
        # Simple check for field presence in JSON
        if [[ "$body" =~ \"${field}\"[[:space:]]*:[[:space:]]*\" ]]; then
            printf 'json_field:%s' "$field"
            return 0
        fi
    done

    # Check for cursor-based pagination
    if [[ "$body" =~ \"cursor\"[[:space:]]*:[[:space:]]*\" ]] || \
       [[ "$body" =~ \"next_cursor\"[[:space:]]*:[[:space:]]*\" ]]; then
        printf 'json_field:cursor'
        return 0
    fi

    # Check for offset/page pagination
    if [[ "$body" =~ \"total_pages\"[[:space:]]*: ]] || \
       [[ "$body" =~ \"totalPages\"[[:space:]]*: ]]; then
        printf 'json_field:page'
        return 0
    fi

    printf 'none'
}

# Internal: Extract next page URL from response
# @param $1 - response body
# @param $2 - response headers
# @param $3 - pagination type
# @param $4 - current URL (for relative URLs)
_burl_next_page_url() {
    local body="$1"
    local headers="$2"
    local pagination_type="$3"
    local current_url="$4"

    case "$pagination_type" in
        link_header)
            # Extract URL from Link header with rel="next"
            local link_header
            link_header=$(printf '%s' "$headers" | grep -i '^Link:' | head -1)

            # Parse: <url>; rel="next" or <url>; rel=next
            if [[ "$link_header" =~ \<([^>]+)\>[^,]*rel=\"?next\"? ]]; then
                local url="${BASH_REMATCH[1]}"
                # Handle relative URLs
                if [[ ! "$url" =~ ^https?:// ]]; then
                    url_parse "$current_url"
                    if [[ "$url" =~ ^/ ]]; then
                        url="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${url}"
                    else
                        url="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${URL_PATH%/*}/${url}"
                    fi
                fi
                printf '%s' "$url"
                return 0
            fi
            ;;

        json_field:*)
            local field="${pagination_type#json_field:}"
            local next_url=""

            # Extract URL from JSON field
            case "$field" in
                cursor|next_cursor)
                    # Cursor-based: need to build URL with cursor parameter
                    local cursor
                    if [[ "$body" =~ \"next_cursor\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                        cursor="${BASH_REMATCH[1]}"
                    elif [[ "$body" =~ \"cursor\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                        cursor="${BASH_REMATCH[1]}"
                    fi

                    if [[ -n "$cursor" && "$cursor" != "null" ]]; then
                        url_parse "$current_url"
                        if [[ -n "$URL_QUERY" ]]; then
                            next_url="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${URL_PATH}?${URL_QUERY}&cursor=${cursor}"
                        else
                            next_url="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${URL_PATH}?cursor=${cursor}"
                        fi
                    fi
                    ;;

                page)
                    # Page-based pagination
                    local current_page total_pages
                    if [[ "$body" =~ \"page\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                        current_page="${BASH_REMATCH[1]}"
                    fi
                    if [[ "$body" =~ \"total_pages\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                        total_pages="${BASH_REMATCH[1]}"
                    elif [[ "$body" =~ \"totalPages\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                        total_pages="${BASH_REMATCH[1]}"
                    fi

                    if [[ -n "$current_page" && -n "$total_pages" ]] && \
                       [[ $current_page -lt $total_pages ]]; then
                        local next_page=$((current_page + 1))
                        url_parse "$current_url"
                        # Update or add page parameter
                        local new_query="${URL_QUERY}"
                        if [[ "$new_query" =~ page=[0-9]+ ]]; then
                            new_query="${new_query/page=*([0-9])/page=${next_page}}"
                        elif [[ -n "$new_query" ]]; then
                            new_query="${new_query}&page=${next_page}"
                        else
                            new_query="page=${next_page}"
                        fi
                        next_url="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${URL_PATH}?${new_query}"
                    fi
                    ;;

                *)
                    # Direct URL field (next, next_url, next_page, etc.)
                    local pattern="\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\""
                    if [[ "$body" =~ $pattern ]]; then
                        next_url="${BASH_REMATCH[1]}"
                        # Handle relative URLs
                        if [[ -n "$next_url" && ! "$next_url" =~ ^https?:// ]]; then
                            url_parse "$current_url"
                            if [[ "$next_url" =~ ^/ ]]; then
                                next_url="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${next_url}"
                            else
                                next_url="${URL_SCHEME}://${URL_HOST}:${URL_PORT}${URL_PATH%/*}/${next_url}"
                            fi
                        fi
                    fi
                    ;;
            esac

            [[ -n "$next_url" ]] && printf '%s' "$next_url"
            return 0
            ;;
    esac

    return 1
}

# Automatically follow pagination through Link headers or JSON fields
# @param $1 - URL
# @param $2 - max pages (default: 10)
# @param $3 - pagination strategy: "link_header" | "json_field" | "auto"
# Returns: {"ok":true,"data":{"pages":N,"total_records":N,"records":[...]}}
burl_paginate() {
    local url="$1"
    local max_pages="${2:-$BURL_AI_MAX_PAGES}"
    local strategy="${3:-auto}"

    if [[ -z "$url" ]]; then
        json_object \
            "ok:bool=false" \
            "error=url_required" \
            "suggestion=Provide a URL as the first argument"
        return 1
    fi

    local -a all_records=()
    local page_count=0
    local total_records=0
    local current_url="$url"
    local pagination_type=""

    while [[ $page_count -lt $max_pages && -n "$current_url" ]]; do
        # Fetch the page
        local response
        response=$(http_json_get "$current_url")

        if ! http_is_success "$response"; then
            local status
            status=$(http_status "$response")
            json_object \
                "ok:bool=false" \
                "error=http_error" \
                "status:number=$status" \
                "page:number=$((page_count + 1))" \
                "url=$current_url"
            return 1
        fi

        local body headers
        body=$(http_body "$response")
        headers=$(http_headers "$response")

        page_count=$((page_count + 1))

        # Extract records from this page
        # Try common patterns: "data", "results", "items", or root array
        local page_records=""
        if [[ "$body" =~ \"data\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
            page_records="${BASH_REMATCH[1]}"
        elif [[ "$body" =~ \"results\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
            page_records="${BASH_REMATCH[1]}"
        elif [[ "$body" =~ \"items\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
            page_records="${BASH_REMATCH[1]}"
        elif [[ "$body" =~ ^\[.*\]$ ]]; then
            # Root is an array
            page_records="${body:1:${#body}-2}"
        fi

        # Count records in this page (rough estimate by counting objects)
        if [[ -n "$page_records" ]]; then
            local count=0
            local tmp="$page_records"
            while [[ "$tmp" =~ \{[^}]*\} ]]; do
                count=$((count + 1))
                tmp="${tmp#*\}}"
            done
            total_records=$((total_records + count))

            # Accumulate records
            if [[ ${#all_records[@]} -eq 0 ]]; then
                all_records+=("$page_records")
            else
                all_records+=(",$page_records")
            fi
        fi

        # Detect pagination type on first page if auto
        if [[ "$strategy" == "auto" && -z "$pagination_type" ]]; then
            pagination_type=$(_burl_detect_pagination "$body" "$headers")
        elif [[ "$strategy" != "auto" ]]; then
            pagination_type="$strategy"
        fi

        # Get next page URL
        if [[ "$pagination_type" == "none" ]]; then
            break
        fi

        local next_url
        next_url=$(_burl_next_page_url "$body" "$headers" "$pagination_type" "$current_url")

        if [[ -z "$next_url" || "$next_url" == "$current_url" ]]; then
            break
        fi

        current_url="$next_url"

        # Optional delay between pages
        if [[ "$BURL_AI_PAGE_DELAY" -gt 0 ]]; then
            sleep "$BURL_AI_PAGE_DELAY"
        fi
    done

    # Build combined records array
    local combined_records="[${all_records[*]}]"

    json_object \
        "ok:bool=true" \
        "data:raw={\"pages\":$page_count,\"total_records\":$total_records,\"records\":$combined_records}"
}

# =============================================================================
# 2. REQUEST CHAINING
# =============================================================================

# Internal: Parse chain DSL
# Simple format: step1 -> step2 -> step3
# Each step: METHOD URL [body] [headers]
_burl_parse_chain() {
    local dsl="$1"
    # Returns JSON representation of chain
    # This is a simplified parser - full implementation would use proper JSON
    printf '%s' "$dsl"
}

# Internal: Execute a single chain step
# @param $1 - step spec (JSON)
# @param $2 - context (accumulated variables)
_burl_execute_step() {
    local step_spec="$1"
    local context="$2"

    # Extract step properties
    local method url body

    # Parse method
    if [[ "$step_spec" =~ \"method\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        method="${BASH_REMATCH[1]}"
    else
        method="GET"
    fi

    # Parse URL
    if [[ "$step_spec" =~ \"url\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
    fi

    # Parse body
    if [[ "$step_spec" =~ \"body\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        body="${BASH_REMATCH[1]}"
    fi

    # Variable substitution from context
    # Replace ${var} patterns with values from context
    local var_pattern='\$\{([^}]+)\}'
    while [[ "$url" =~ $var_pattern ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value=""

        # Extract value from context JSON
        if [[ "$context" =~ \"$var_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            var_value="${BASH_REMATCH[1]}"
        fi

        url="${url//\$\{$var_name\}/$var_value}"
    done

    if [[ -n "$body" ]]; then
        while [[ "$body" =~ $var_pattern ]]; do
            local var_name="${BASH_REMATCH[1]}"
            local var_value=""

            if [[ "$context" =~ \"$var_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                var_value="${BASH_REMATCH[1]}"
            fi

            body="${body//\$\{$var_name\}/$var_value}"
        done
    fi

    # Execute the request
    local response
    case "${method^^}" in
        GET)
            response=$(http_json_get "$url")
            ;;
        POST)
            response=$(http_json_post "$url" "$body")
            ;;
        PUT)
            response=$(http_json_put "$url" "$body")
            ;;
        PATCH)
            response=$(http_json_patch "$url" "$body")
            ;;
        DELETE)
            response=$(http_delete "$url")
            ;;
        *)
            response=$(http_request "$method" "$url" "$body")
            ;;
    esac

    printf '%s' "$response"
}

# Execute multiple dependent requests with variable passing
# @param $1 - chain specification (JSON)
# Returns: {"ok":true,"data":{"steps":[...],"final_result":{...}}}
burl_chain() {
    local chain_spec="$1"

    if [[ -z "$chain_spec" ]]; then
        json_object \
            "ok:bool=false" \
            "error=chain_spec_required" \
            "suggestion=Provide a chain specification JSON"
        return 1
    fi

    # Parse steps array
    # Format: {"steps":[{"method":"POST","url":"/auth","body":"{}","save":"token"},...]}"

    local context="{}"
    local -a step_results=()
    local step_index=0
    local final_result=""

    # Extract steps array (simplified parsing)
    local steps_json=""
    if [[ "$chain_spec" =~ \"steps\"[[:space:]]*:[[:space:]]*\[([^\]]+)\] ]]; then
        steps_json="${BASH_REMATCH[1]}"
    else
        json_object \
            "ok:bool=false" \
            "error=invalid_chain_format" \
            "suggestion=Chain spec must have a steps array"
        return 1
    fi

    # Split steps (simplistic - assumes no nested arrays in step objects)
    local current_step=""
    local brace_depth=0
    local i

    for ((i=0; i<${#steps_json}; i++)); do
        local char="${steps_json:i:1}"

        case "$char" in
            '{')
                brace_depth=$((brace_depth + 1))
                current_step+="$char"
                ;;
            '}')
                brace_depth=$((brace_depth - 1))
                current_step+="$char"

                if [[ $brace_depth -eq 0 ]]; then
                    # Execute this step
                    step_index=$((step_index + 1))

                    local step_response
                    step_response=$(_burl_execute_step "$current_step" "$context")

                    local status body
                    status=$(http_status "$step_response")
                    body=$(http_body "$step_response")

                    # Check for save directive
                    local save_as=""
                    if [[ "$current_step" =~ \"save\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                        save_as="${BASH_REMATCH[1]}"
                    fi

                    # Extract value to save (try common patterns)
                    if [[ -n "$save_as" ]]; then
                        local save_value=""

                        # Try to extract from common response patterns
                        if [[ "$body" =~ \"${save_as}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                            save_value="${BASH_REMATCH[1]}"
                        elif [[ "$body" =~ \"access_token\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                            save_value="${BASH_REMATCH[1]}"
                        elif [[ "$body" =~ \"token\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                            save_value="${BASH_REMATCH[1]}"
                        elif [[ "$body" =~ \"id\"[[:space:]]*:[[:space:]]*\"?([^,\"}]+)\"? ]]; then
                            save_value="${BASH_REMATCH[1]}"
                        fi

                        # Update context
                        if [[ -n "$save_value" ]]; then
                            if [[ "$context" == "{}" ]]; then
                                context="{\"${save_as}\":\"${save_value}\"}"
                            else
                                context="${context%\}},\"${save_as}\":\"${save_value}\"}"
                            fi
                        fi
                    fi

                    # Store step result
                    local step_result
                    step_result=$(json_object \
                        "step:number=$step_index" \
                        "status:number=$status" \
                        "body=$body")
                    step_results+=("$step_result")

                    # Check for failure
                    if ! http_is_success "$step_response"; then
                        json_object \
                            "ok:bool=false" \
                            "error=step_failed" \
                            "step:number=$step_index" \
                            "status:number=$status" \
                            "body=$body"
                        return 1
                    fi

                    final_result="$body"
                    current_step=""
                fi
                ;;
            *)
                if [[ $brace_depth -gt 0 ]]; then
                    current_step+="$char"
                fi
                ;;
        esac
    done

    # Build steps array
    local steps_array="["
    local first=true
    for result in "${step_results[@]}"; do
        $first || steps_array+=","
        first=false
        steps_array+="$result"
    done
    steps_array+="]"

    json_object \
        "ok:bool=true" \
        "data:raw={\"steps\":$steps_array,\"final_result\":$final_result,\"context\":$context}"
}

# =============================================================================
# 3. SCHEMA VALIDATION
# =============================================================================

# Internal: Check type of a JSON value
# @param $1 - value
# @param $2 - expected type (string|number|boolean|object|array|null)
_burl_check_type() {
    local value="$1"
    local expected="$2"

    case "$expected" in
        string)
            [[ "$value" =~ ^\".*\"$ ]]
            ;;
        number)
            [[ "$value" =~ ^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$ ]]
            ;;
        boolean)
            [[ "$value" == "true" || "$value" == "false" ]]
            ;;
        object)
            [[ "$value" =~ ^\{.*\}$ ]]
            ;;
        array)
            [[ "$value" =~ ^\[.*\]$ ]]
            ;;
        null)
            [[ "$value" == "null" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Validate response against expected schema
# @param $1 - response body (JSON)
# @param $2 - schema (simplified JSON schema)
# Returns: {"ok":true,"data":{"valid":true}} or {"ok":false,"error":"schema_mismatch","details":[...]}
burl_validate_schema() {
    local body="$1"
    local schema="$2"

    if [[ -z "$body" ]]; then
        json_object \
            "ok:bool=false" \
            "error=body_required"
        return 1
    fi

    if [[ -z "$schema" ]]; then
        json_object \
            "ok:bool=false" \
            "error=schema_required"
        return 1
    fi

    local -a validation_errors=()

    # Extract required fields from schema
    local required_fields=""
    if [[ "$schema" =~ \"required\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
        required_fields="${BASH_REMATCH[1]}"
    fi

    # Check required fields
    if [[ -n "$required_fields" ]]; then
        # Parse required fields (comma-separated quoted strings)
        local field_pattern='"([^"]+)"'
        local remaining="$required_fields"

        while [[ "$remaining" =~ $field_pattern ]]; do
            local field="${BASH_REMATCH[1]}"

            # Check if field exists in body
            if ! [[ "$body" =~ \"$field\"[[:space:]]*: ]]; then
                validation_errors+=("\"missing_required_field:$field\"")
            fi

            remaining="${remaining#*\"$field\"}"
        done
    fi

    # Extract properties schema
    local properties=""
    if [[ "$schema" =~ \"properties\"[[:space:]]*:[[:space:]]*\{([^}]+)\} ]]; then
        properties="${BASH_REMATCH[1]}"
    fi

    # Validate property types
    if [[ -n "$properties" ]]; then
        # Parse each property: "field":{"type":"string"}
        local prop_pattern='"([^"]+)"[[:space:]]*:[[:space:]]*\{[^}]*"type"[[:space:]]*:[[:space:]]*"([^"]+)"[^}]*\}'
        local remaining="$properties"

        while [[ "$remaining" =~ $prop_pattern ]]; do
            local field="${BASH_REMATCH[1]}"
            local expected_type="${BASH_REMATCH[2]}"

            # Extract actual value from body
            local value_pattern="\"$field\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[0-9.eE+-]+|true|false|null|\{[^}]*\}|\[[^\]]*\])"

            if [[ "$body" =~ $value_pattern ]]; then
                local actual_value="${BASH_REMATCH[1]}"

                if ! _burl_check_type "$actual_value" "$expected_type"; then
                    validation_errors+=("\"type_mismatch:${field}:expected_${expected_type}\"")
                fi
            fi

            remaining="${remaining#*\"$field\"*\}}"
        done
    fi

    # Return result
    if [[ ${#validation_errors[@]} -eq 0 ]]; then
        json_object \
            "ok:bool=true" \
            "data:raw={\"valid\":true,\"errors\":[]}"
    else
        local errors_array="[${validation_errors[*]}]"
        errors_array="${errors_array// /,}"

        json_object \
            "ok:bool=false" \
            "error=schema_mismatch" \
            "details:raw=$errors_array"
        return 1
    fi
}

# =============================================================================
# 4. RATE LIMIT MANAGEMENT
# =============================================================================

# Internal: Parse rate limit headers from response
# @param $1 - response headers
_burl_parse_rate_headers() {
    local headers="$1"

    local remaining=-1
    local limit=-1
    local reset=-1
    local retry_after=-1

    # Common rate limit header patterns
    # X-RateLimit-Remaining, X-Rate-Limit-Remaining, RateLimit-Remaining
    if [[ "$headers" =~ [Xx]-?[Rr]ate-?[Ll]imit-[Rr]emaining:[[:space:]]*([0-9]+) ]]; then
        remaining="${BASH_REMATCH[1]}"
    fi

    # X-RateLimit-Limit, X-Rate-Limit-Limit, RateLimit-Limit
    if [[ "$headers" =~ [Xx]-?[Rr]ate-?[Ll]imit-[Ll]imit:[[:space:]]*([0-9]+) ]]; then
        limit="${BASH_REMATCH[1]}"
    fi

    # X-RateLimit-Reset, X-Rate-Limit-Reset, RateLimit-Reset
    if [[ "$headers" =~ [Xx]-?[Rr]ate-?[Ll]imit-[Rr]eset:[[:space:]]*([0-9]+) ]]; then
        reset="${BASH_REMATCH[1]}"
    fi

    # Retry-After header
    if [[ "$headers" =~ [Rr]etry-[Aa]fter:[[:space:]]*([0-9]+) ]]; then
        retry_after="${BASH_REMATCH[1]}"
    fi

    printf '{"remaining":%d,"limit":%d,"reset":%d,"retry_after":%d}' \
        "$remaining" "$limit" "$reset" "$retry_after"
}

# Internal: Determine if we should wait based on rate limits
# @param $1 - URL (for domain-based tracking)
_burl_rate_limit_wait() {
    local url="$1"

    url_parse "$url"
    local domain="$URL_HOST"

    local state_file="${BURL_AI_RATE_LIMIT_DIR}/${domain//\//_}"

    if [[ ! -f "$state_file" ]]; then
        return 0  # No rate limit info, proceed
    fi

    local state
    state=$(<"$state_file")

    local remaining reset
    if [[ "$state" =~ \"remaining\"[[:space:]]*:[[:space:]]*([0-9-]+) ]]; then
        remaining="${BASH_REMATCH[1]}"
    fi
    if [[ "$state" =~ \"reset\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        reset="${BASH_REMATCH[1]}"
    fi

    local now
    now=$(_burl_ai_now)

    if [[ "$remaining" -le 0 && "$reset" -gt "$now" ]]; then
        local wait_time=$((reset - now))
        printf '%d' "$wait_time"
        return 1
    fi

    return 0
}

# Track and respect rate limits across requests
# @param $1 - URL (for rate limit tracking)
# Returns: {"ok":true,"data":{"remaining":N,"reset_at":"ISO8601","can_request":bool}}
burl_rate_limit_status() {
    local url="$1"

    if [[ -z "$url" ]]; then
        json_object \
            "ok:bool=false" \
            "error=url_required"
        return 1
    fi

    mkdir -p "$BURL_AI_RATE_LIMIT_DIR" 2>/dev/null

    url_parse "$url"
    local domain="$URL_HOST"

    local state_file="${BURL_AI_RATE_LIMIT_DIR}/${domain//\//_}"

    local remaining=-1
    local limit=-1
    local reset=0
    local can_request="true"

    if [[ -f "$state_file" ]]; then
        local state
        state=$(<"$state_file")

        if [[ "$state" =~ \"remaining\"[[:space:]]*:[[:space:]]*([0-9-]+) ]]; then
            remaining="${BASH_REMATCH[1]}"
        fi
        if [[ "$state" =~ \"limit\"[[:space:]]*:[[:space:]]*([0-9-]+) ]]; then
            limit="${BASH_REMATCH[1]}"
        fi
        if [[ "$state" =~ \"reset\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            reset="${BASH_REMATCH[1]}"
        fi

        local now
        now=$(_burl_ai_now)

        if [[ "$remaining" -le 0 && "$reset" -gt "$now" ]]; then
            can_request="false"
        elif [[ "$reset" -le "$now" ]]; then
            # Reset time has passed, limits should be refreshed
            remaining="$limit"
        fi
    fi

    # Convert reset timestamp to ISO8601
    local reset_iso=""
    if [[ "$reset" -gt 0 ]]; then
        reset_iso=$(date -d "@$reset" -Iseconds 2>/dev/null || date -r "$reset" -Iseconds 2>/dev/null || printf '%d' "$reset")
    fi

    json_object \
        "ok:bool=true" \
        "data:raw={\"remaining\":$remaining,\"limit\":$limit,\"reset_at\":\"$reset_iso\",\"can_request\":$can_request}"
}

# Update rate limit tracking after a request
# @param $1 - URL
# @param $2 - response headers
_burl_update_rate_limits() {
    local url="$1"
    local headers="$2"

    mkdir -p "$BURL_AI_RATE_LIMIT_DIR" 2>/dev/null

    url_parse "$url"
    local domain="$URL_HOST"

    local state_file="${BURL_AI_RATE_LIMIT_DIR}/${domain//\//_}"

    local rate_info
    rate_info=$(_burl_parse_rate_headers "$headers")

    printf '%s' "$rate_info" > "$state_file"
}

# =============================================================================
# 5. RESPONSE DIFFING
# =============================================================================

# Compare response to cached previous
# @param $1 - URL
# @param $2 - current response
# Returns: {"ok":true,"data":{"changed":bool,"diff":{"added":[],"removed":[],"modified":[]}}}
burl_diff_response() {
    local url="$1"
    local current_response="$2"

    if [[ -z "$url" || -z "$current_response" ]]; then
        json_object \
            "ok:bool=false" \
            "error=url_and_response_required"
        return 1
    fi

    mkdir -p "$BURL_AI_CACHE_DIR" 2>/dev/null

    local url_hash
    url_hash=$(_burl_ai_sha256 "$url")
    local cache_file="${BURL_AI_CACHE_DIR}/${url_hash}.response"

    local changed="false"
    local -a added=()
    local -a removed=()
    local -a modified=()

    if [[ -f "$cache_file" ]]; then
        local previous_response
        previous_response=$(<"$cache_file")

        if [[ "$current_response" != "$previous_response" ]]; then
            changed="true"

            # Extract keys from both responses for comparison
            local current_keys previous_keys

            # Simple key extraction (top-level only)
            while [[ "$current_response" =~ \"([^\"]+)\"[[:space:]]*: ]]; do
                local key="${BASH_REMATCH[1]}"
                current_keys+="$key "
                current_response="${current_response#*\"$key\":}"
            done

            current_response="$2"  # Reset

            while [[ "$previous_response" =~ \"([^\"]+)\"[[:space:]]*: ]]; do
                local key="${BASH_REMATCH[1]}"
                previous_keys+="$key "
                previous_response="${previous_response#*\"$key\":}"
            done

            previous_response=$(<"$cache_file")  # Reset

            # Find added keys
            for key in $current_keys; do
                if [[ ! " $previous_keys " =~ " $key " ]]; then
                    added+=("\"$key\"")
                fi
            done

            # Find removed keys
            for key in $previous_keys; do
                if [[ ! " $current_keys " =~ " $key " ]]; then
                    removed+=("\"$key\"")
                fi
            done

            # Find modified values (keys present in both)
            for key in $current_keys; do
                if [[ " $previous_keys " =~ " $key " ]]; then
                    # Extract values
                    local curr_val prev_val
                    local val_pattern="\"$key\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[0-9.eE+-]+|true|false|null)"

                    [[ "$2" =~ $val_pattern ]] && curr_val="${BASH_REMATCH[1]}"
                    [[ "$(<"$cache_file")" =~ $val_pattern ]] && prev_val="${BASH_REMATCH[1]}"

                    if [[ "$curr_val" != "$prev_val" ]]; then
                        modified+=("\"$key\"")
                    fi
                fi
            done
        fi
    else
        changed="true"  # No previous response = everything is "new"
    fi

    # Cache current response
    printf '%s' "$2" > "$cache_file"

    # Build diff object
    local added_array="[${added[*]}]"
    local removed_array="[${removed[*]}]"
    local modified_array="[${modified[*]}]"

    added_array="${added_array// /,}"
    removed_array="${removed_array// /,}"
    modified_array="${modified_array// /,}"

    json_object \
        "ok:bool=true" \
        "data:raw={\"changed\":$changed,\"diff\":{\"added\":$added_array,\"removed\":$removed_array,\"modified\":$modified_array}}"
}

# =============================================================================
# 6. REQUEST TEMPLATES
# =============================================================================

# Register a template
# @param $1 - name
# @param $2 - template spec (JSON)
burl_template_register() {
    local name="$1"
    local spec="$2"

    if [[ -z "$name" || -z "$spec" ]]; then
        json_object \
            "ok:bool=false" \
            "error=name_and_spec_required"
        return 1
    fi

    _BURL_AI_TEMPLATES["$name"]="$spec"

    json_object \
        "ok:bool=true" \
        "data:raw={\"registered\":\"$name\"}"
}

# Load and use pre-configured request templates
# @param $1 - template name
# @param $@ - variable substitutions (key=value)
# Returns: Executes request and returns USOP response
burl_template() {
    local name="$1"
    shift

    if [[ -z "$name" ]]; then
        json_object \
            "ok:bool=false" \
            "error=template_name_required"
        return 1
    fi

    local spec="${_BURL_AI_TEMPLATES[$name]:-}"

    if [[ -z "$spec" ]]; then
        json_object \
            "ok:bool=false" \
            "error=template_not_found" \
            "name=$name"
        return 1
    fi

    # Apply variable substitutions
    for sub in "$@"; do
        local key="${sub%%=*}"
        local value="${sub#*=}"
        spec="${spec//\{\{$key\}\}/$value}"
        spec="${spec//\$\{$key\}/$value}"
    done

    # Extract request properties
    local method="GET"
    local url=""
    local body=""
    local -a headers=()

    if [[ "$spec" =~ \"method\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        method="${BASH_REMATCH[1]}"
    fi

    if [[ "$spec" =~ \"url\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        url="${BASH_REMATCH[1]}"
    fi

    if [[ "$spec" =~ \"body\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        body="${BASH_REMATCH[1]}"
    fi

    # Execute the request
    local response
    case "${method^^}" in
        GET)
            response=$(http_json_get "$url" "${headers[@]}")
            ;;
        POST)
            response=$(http_json_post "$url" "$body" "${headers[@]}")
            ;;
        PUT)
            response=$(http_json_put "$url" "$body" "${headers[@]}")
            ;;
        *)
            response=$(http_request "$method" "$url" "$body" "${headers[@]}")
            ;;
    esac

    local status body_out
    status=$(http_status "$response")
    body_out=$(http_body "$response")

    if http_is_success "$response"; then
        json_object \
            "ok:bool=true" \
            "data:raw=$body_out"
    else
        json_object \
            "ok:bool=false" \
            "error=request_failed" \
            "status:number=$status" \
            "body=$body_out"
        return 1
    fi
}

# =============================================================================
# 7. OAUTH2 HELPER
# =============================================================================

# Manage OAuth2 token lifecycle
# @param $1 - token endpoint
# @param $2 - client_id
# @param $3 - client_secret
# @param $4 - scope (optional)
# Returns: {"ok":true,"data":{"access_token":"...","expires_in":N}}
burl_oauth2_token() {
    local token_endpoint="$1"
    local client_id="$2"
    local client_secret="$3"
    local scope="${4:-}"

    if [[ -z "$token_endpoint" || -z "$client_id" || -z "$client_secret" ]]; then
        json_object \
            "ok:bool=false" \
            "error=token_endpoint_client_id_secret_required"
        return 1
    fi

    # Check cache first
    local cache_key="${client_id}:${token_endpoint}"
    local cached_token="${_BURL_AI_OAUTH_TOKENS[$cache_key]:-}"
    local cached_expiry="${_BURL_AI_OAUTH_EXPIRY[$cache_key]:-0}"
    local now
    now=$(_burl_ai_now)

    if [[ -n "$cached_token" && "$cached_expiry" -gt "$now" ]]; then
        json_object \
            "ok:bool=true" \
            "data:raw={\"access_token\":\"$cached_token\",\"expires_in\":$((cached_expiry - now)),\"cached\":true}"
        return 0
    fi

    # Build token request body
    local body="grant_type=client_credentials&client_id=$(url_encode "$client_id")&client_secret=$(url_encode "$client_secret")"

    if [[ -n "$scope" ]]; then
        body+="&scope=$(url_encode "$scope")"
    fi

    # Request token
    local response
    response=$(http_post "$token_endpoint" "$body" "Content-Type: application/x-www-form-urlencoded")

    if ! http_is_success "$response"; then
        local status
        status=$(http_status "$response")
        json_object \
            "ok:bool=false" \
            "error=token_request_failed" \
            "status:number=$status"
        return 1
    fi

    local response_body
    response_body=$(http_body "$response")

    # Extract token and expiry
    local access_token=""
    local expires_in=3600

    if [[ "$response_body" =~ \"access_token\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        access_token="${BASH_REMATCH[1]}"
    fi

    if [[ "$response_body" =~ \"expires_in\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        expires_in="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$access_token" ]]; then
        json_object \
            "ok:bool=false" \
            "error=no_access_token_in_response" \
            "body=$response_body"
        return 1
    fi

    # Cache token (with 60 second buffer before expiry)
    _BURL_AI_OAUTH_TOKENS["$cache_key"]="$access_token"
    _BURL_AI_OAUTH_EXPIRY["$cache_key"]=$((now + expires_in - 60))

    json_object \
        "ok:bool=true" \
        "data:raw={\"access_token\":\"$access_token\",\"expires_in\":$expires_in,\"cached\":false}"
}

# Auto-refresh OAuth2 token if needed and make request
# @param $1 - URL
# @param $2 - method (GET/POST/etc)
# @param $3 - body (optional)
# @param $4 - token endpoint
# @param $5 - client_id
# @param $6 - client_secret
burl_oauth2_request() {
    local url="$1"
    local method="${2:-GET}"
    local body="${3:-}"
    local token_endpoint="$4"
    local client_id="$5"
    local client_secret="$6"

    # Get or refresh token
    local token_result
    token_result=$(burl_oauth2_token "$token_endpoint" "$client_id" "$client_secret")

    local token_ok
    if [[ "$token_result" =~ \"ok\"[[:space:]]*:[[:space:]]*true ]]; then
        token_ok=true
    else
        printf '%s' "$token_result"
        return 1
    fi

    local access_token
    if [[ "$token_result" =~ \"access_token\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        access_token="${BASH_REMATCH[1]}"
    fi

    # Make authenticated request
    local response
    local auth_header="Authorization: Bearer $access_token"

    case "${method^^}" in
        GET)
            response=$(http_get "$url" "$auth_header")
            ;;
        POST)
            response=$(http_json_post "$url" "$body" "$auth_header")
            ;;
        PUT)
            response=$(http_json_put "$url" "$body" "$auth_header")
            ;;
        DELETE)
            response=$(http_delete "$url" "$auth_header")
            ;;
        *)
            response=$(http_request "$method" "$url" "$body" "$auth_header")
            ;;
    esac

    local status response_body
    status=$(http_status "$response")
    response_body=$(http_body "$response")

    if http_is_success "$response"; then
        json_object \
            "ok:bool=true" \
            "data:raw=$response_body"
    else
        json_object \
            "ok:bool=false" \
            "error=request_failed" \
            "status:number=$status" \
            "body=$response_body"
        return 1
    fi
}

# =============================================================================
# 8. STREAMING PROGRESS
# =============================================================================

# Download with progress updates
# @param $1 - URL
# @param $2 - output file
# @param $3 - callback function (receives progress JSON)
# Emits: {"progress":0.5,"bytes":1024,"total":2048,"eta_seconds":5}
burl_download_progress() {
    local url="$1"
    local output="$2"
    local callback="${3:-}"

    if [[ -z "$url" || -z "$output" ]]; then
        json_object \
            "ok:bool=false" \
            "error=url_and_output_required"
        return 0  # USOP pattern: always return 0, use ok:false for errors
    fi

    # First, get content length via HEAD request
    local head_response
    head_response=$(http_head "$url")

    local total_bytes=0
    local content_length_header
    content_length_header=$(http_header_get "$head_response" "Content-Length")

    if [[ -n "$content_length_header" && "$content_length_header" =~ ^[0-9]+$ ]]; then
        total_bytes="$content_length_header"
    fi

    # Check if we have curl for proper progress download
    if command -v curl &>/dev/null; then
        local start_time
        start_time=$(_burl_ai_now)

        # Use curl with progress meter
        local tmpfile
        tmpfile=$(mktemp)

        curl -sL "$url" -o "$tmpfile" 2>/dev/null &
        local curl_pid=$!

        # Monitor progress
        local downloaded=0
        local last_size=0

        while kill -0 "$curl_pid" 2>/dev/null; do
            if [[ -f "$tmpfile" ]]; then
                downloaded=$(stat -c %s "$tmpfile" 2>/dev/null || stat -f %z "$tmpfile" 2>/dev/null || echo 0)
            fi

            if [[ "$downloaded" -gt "$last_size" ]]; then
                local progress=0
                local eta_seconds=0

                if [[ "$total_bytes" -gt 0 ]]; then
                    progress=$(echo "scale=2; $downloaded / $total_bytes" | bc 2>/dev/null || echo "0")

                    local elapsed=$(($(_burl_ai_now) - start_time))
                    if [[ "$elapsed" -gt 0 && "$downloaded" -gt 0 ]]; then
                        local rate=$((downloaded / elapsed))
                        if [[ "$rate" -gt 0 ]]; then
                            eta_seconds=$(((total_bytes - downloaded) / rate))
                        fi
                    fi
                fi

                local progress_json
                progress_json=$(json_object \
                    "progress=$progress" \
                    "bytes:number=$downloaded" \
                    "total:number=$total_bytes" \
                    "eta_seconds:number=$eta_seconds")

                if [[ -n "$callback" ]] && declare -F "$callback" &>/dev/null; then
                    "$callback" "$progress_json"
                fi

                last_size="$downloaded"
            fi

            sleep 0.5
        done

        wait "$curl_pid"
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            mv "$tmpfile" "$output"

            local final_size
            final_size=$(stat -c %s "$output" 2>/dev/null || stat -f %z "$output" 2>/dev/null || echo 0)

            json_object \
                "ok:bool=true" \
                "data:raw={\"path\":\"$output\",\"bytes\":$final_size}"
        else
            rm -f "$tmpfile"
            json_object \
                "ok:bool=false" \
                "error=download_failed" \
                "exit_code:number=$exit_code"
            return 1
        fi
    else
        # Fallback to http.sh download (no progress)
        if http_download "$url" "$output"; then
            local final_size
            final_size=$(stat -c %s "$output" 2>/dev/null || stat -f %z "$output" 2>/dev/null || echo 0)

            json_object \
                "ok:bool=true" \
                "data:raw={\"path\":\"$output\",\"bytes\":$final_size,\"progress_unavailable\":true}"
        else
            json_object \
                "ok:bool=false" \
                "error=download_failed"
            return 1
        fi
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

BURL_AI_EXPORTS=(
    # Pagination Autopilot
    burl_paginate
    # Request Chaining
    burl_chain
    # Schema Validation
    burl_validate_schema
    # Rate Limit Management
    burl_rate_limit_status
    # Response Diffing
    burl_diff_response
    # Request Templates
    burl_template
    burl_template_register
    # OAuth2 Helper
    burl_oauth2_token
    burl_oauth2_request
    # Streaming Progress
    burl_download_progress
)

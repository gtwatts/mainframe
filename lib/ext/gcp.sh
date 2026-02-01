#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ext/gcp.sh - Google Cloud Platform CLI Wrapper Functions (OPTIONAL)
# =============================================================================
# Description: Convenience wrappers for gcloud CLI operations
# Requires: gcloud CLI (https://cloud.google.com/sdk/docs/install)
# Status: Production - Core GCP operations with structured JSON output
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_EXT_GCP_LOADED:-}" ]] && return 0
readonly _MAINFRAME_EXT_GCP_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if gcloud CLI is available
_gcp_has_cli() {
    command -v gcloud &>/dev/null
}

# Require gcloud CLI or return error JSON
_gcp_require_cli() {
    if ! _gcp_has_cli; then
        printf '{"success":false,"error":"gcloud CLI not installed","hint":"Install from https://cloud.google.com/sdk/docs/install"}'
        return 1
    fi
    return 0
}

# Check if gsutil is available (bundled with gcloud SDK)
_gcp_has_gsutil() {
    command -v gsutil &>/dev/null
}

# Escape string for JSON output
_gcp_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# =============================================================================
# AVAILABILITY & CONFIGURATION
# =============================================================================

# Check if gcloud CLI is available and configured
# Usage: gcp_configured
# Returns: 0 if gcloud CLI is installed and has active configuration, 1 otherwise
# Output: JSON with configuration status
# @idempotent
gcp_configured() {
    _gcp_require_cli || return 1

    local account project
    account=$(gcloud config get-value account 2>/dev/null)
    project=$(gcloud config get-value project 2>/dev/null)

    if [[ -z "$account" ]]; then
        printf '{"success":false,"error":"No active account configured","hint":"Run gcloud auth login"}'
        return 1
    fi

    printf '{"success":true,"data":{"account":"%s","project":"%s","configured":true}}' \
        "$(_gcp_json_escape "$account")" "$(_gcp_json_escape "${project:-}")"
}

# Get or set current project
# Usage: gcp_project [project_id]
# Returns: JSON with current or newly set project
# @idempotent (when reading)
gcp_project() {
    _gcp_require_cli || return 1

    local project_id="${1:-}"

    if [[ -n "$project_id" ]]; then
        # Set project
        if gcloud config set project "$project_id" &>/dev/null; then
            printf '{"success":true,"data":{"project":"%s","action":"set"}}' \
                "$(_gcp_json_escape "$project_id")"
        else
            printf '{"success":false,"error":"Failed to set project","project":"%s"}' \
                "$(_gcp_json_escape "$project_id")"
            return 1
        fi
    else
        # Get current project
        local current
        current=$(gcloud config get-value project 2>/dev/null)

        if [[ -z "$current" ]]; then
            printf '{"success":false,"error":"No project configured","hint":"Run gcloud config set project PROJECT_ID"}'
            return 1
        fi

        printf '{"success":true,"data":{"project":"%s"}}' "$(_gcp_json_escape "$current")"
    fi
}

# Get or set current region
# Usage: gcp_region [region]
# Returns: JSON with current or newly set region
# @idempotent (when reading)
gcp_region() {
    _gcp_require_cli || return 1

    local region="${1:-}"

    if [[ -n "$region" ]]; then
        # Set region
        if gcloud config set compute/region "$region" &>/dev/null; then
            printf '{"success":true,"data":{"region":"%s","action":"set"}}' \
                "$(_gcp_json_escape "$region")"
        else
            printf '{"success":false,"error":"Failed to set region","region":"%s"}' \
                "$(_gcp_json_escape "$region")"
            return 1
        fi
    else
        # Get current region
        local current
        current=$(gcloud config get-value compute/region 2>/dev/null)

        if [[ -z "$current" ]]; then
            printf '{"success":true,"data":{"region":null,"hint":"Run gcloud config set compute/region REGION"}}'
        else
            printf '{"success":true,"data":{"region":"%s"}}' "$(_gcp_json_escape "$current")"
        fi
    fi
}

# =============================================================================
# CLOUD STORAGE HELPERS
# =============================================================================

# List Cloud Storage buckets
# Usage: gcp_storage_list [prefix]
# Returns: JSON array of bucket names
# @idempotent
gcp_storage_list() {
    _gcp_require_cli || return 1

    local prefix="${1:-}"
    local buckets

    if _gcp_has_gsutil; then
        if [[ -n "$prefix" ]]; then
            buckets=$(gsutil ls 2>/dev/null | grep -E "^gs://${prefix}" | sed 's|gs://||;s|/$||')
        else
            buckets=$(gsutil ls 2>/dev/null | sed 's|gs://||;s|/$||')
        fi
    else
        # Fallback to gcloud storage
        buckets=$(gcloud storage buckets list --format="value(name)" 2>/dev/null) || {
            printf '{"success":false,"error":"Failed to list Cloud Storage buckets"}'
            return 1
        }
        [[ -n "$prefix" ]] && buckets=$(printf '%s' "$buckets" | grep "^${prefix}")
    fi

    if [[ -z "$buckets" ]]; then
        printf '{"success":true,"data":[]}'
        return 0
    fi

    # Convert to JSON array
    local json_array="["
    local first=true
    while IFS= read -r bucket; do
        [[ -z "$bucket" ]] && continue
        $first || json_array+=","
        first=false
        json_array+="\"$(_gcp_json_escape "$bucket")\""
    done <<< "$buckets"
    json_array+="]"

    printf '{"success":true,"data":%s}' "$json_array"
}

# Upload file to Cloud Storage
# Usage: gcp_storage_upload "local_path" "gs://bucket/path"
# Returns: USOP JSON result
gcp_storage_upload() {
    _gcp_require_cli || return 1

    local source="$1"
    local destination="$2"

    [[ -z "$source" || -z "$destination" ]] && {
        printf '{"success":false,"error":"Source and destination required"}'
        return 1
    }

    [[ ! -f "$source" ]] && {
        printf '{"success":false,"error":"Source file not found","source":"%s"}' \
            "$(_gcp_json_escape "$source")"
        return 1
    }

    # Ensure destination starts with gs://
    [[ "$destination" != gs://* ]] && destination="gs://$destination"

    local copy_result=0
    if _gcp_has_gsutil; then
        gsutil cp "$source" "$destination" &>/dev/null || copy_result=1
    else
        gcloud storage cp "$source" "$destination" &>/dev/null || copy_result=1
    fi

    if [[ $copy_result -eq 0 ]]; then
        printf '{"success":true,"data":{"source":"%s","destination":"%s","action":"upload"}}' \
            "$(_gcp_json_escape "$source")" "$(_gcp_json_escape "$destination")"
    else
        printf '{"success":false,"error":"Upload failed","source":"%s","destination":"%s"}' \
            "$(_gcp_json_escape "$source")" "$(_gcp_json_escape "$destination")"
        return 1
    fi
}

# Download file from Cloud Storage
# Usage: gcp_storage_download "gs://bucket/path" "local_path"
# Returns: USOP JSON result
gcp_storage_download() {
    _gcp_require_cli || return 1

    local source="$1"
    local destination="$2"

    [[ -z "$source" || -z "$destination" ]] && {
        printf '{"success":false,"error":"Source and destination required"}'
        return 1
    }

    # Ensure source starts with gs://
    [[ "$source" != gs://* ]] && source="gs://$source"

    local copy_result=0
    if _gcp_has_gsutil; then
        gsutil cp "$source" "$destination" &>/dev/null || copy_result=1
    else
        gcloud storage cp "$source" "$destination" &>/dev/null || copy_result=1
    fi

    if [[ $copy_result -eq 0 ]]; then
        printf '{"success":true,"data":{"source":"%s","destination":"%s","action":"download"}}' \
            "$(_gcp_json_escape "$source")" "$(_gcp_json_escape "$destination")"
    else
        printf '{"success":false,"error":"Download failed","source":"%s","destination":"%s"}' \
            "$(_gcp_json_escape "$source")" "$(_gcp_json_escape "$destination")"
        return 1
    fi
}

# =============================================================================
# COMPUTE ENGINE HELPERS
# =============================================================================

# List Compute Engine instances
# Usage: gcp_compute_list [zone]
# Returns: JSON array of instance info
# @idempotent
gcp_compute_list() {
    _gcp_require_cli || return 1

    local zone="${1:-}"
    local args=("compute" "instances" "list" "--format=json")

    [[ -n "$zone" ]] && args+=("--zones=$zone")

    local result
    result=$(gcloud "${args[@]}" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list Compute Engine instances"}'
        return 1
    }

    # If result is empty or null, return empty array
    if [[ -z "$result" || "$result" == "[]" ]]; then
        printf '{"success":true,"data":[]}'
        return 0
    fi

    printf '{"success":true,"data":%s}' "$result"
}

# Get Compute Engine instance status
# Usage: gcp_compute_status "instance_name" [zone]
# Returns: JSON with instance status
# @idempotent
gcp_compute_status() {
    _gcp_require_cli || return 1

    local instance_name="$1"
    local zone="${2:-}"

    [[ -z "$instance_name" ]] && {
        printf '{"success":false,"error":"Instance name required"}'
        return 1
    }

    local args=("compute" "instances" "describe" "$instance_name" "--format=json")
    [[ -n "$zone" ]] && args+=("--zone=$zone")

    local result
    result=$(gcloud "${args[@]}" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to get instance status","instance":"%s"}' \
            "$(_gcp_json_escape "$instance_name")"
        return 1
    }

    # Extract key fields for simplified response
    local status name zone_val machine_type
    status=$(printf '%s' "$result" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    name=$(printf '%s' "$result" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    zone_val=$(printf '%s' "$result" | grep -o '"zone"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    machine_type=$(printf '%s' "$result" | grep -o '"machineType"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)

    # Extract just the zone name from the full URL
    zone_val="${zone_val##*/}"
    machine_type="${machine_type##*/}"

    printf '{"success":true,"data":{"name":"%s","status":"%s","zone":"%s","machine_type":"%s"}}' \
        "$(_gcp_json_escape "$name")" \
        "$(_gcp_json_escape "$status")" \
        "$(_gcp_json_escape "$zone_val")" \
        "$(_gcp_json_escape "$machine_type")"
}

# =============================================================================
# CLOUD FUNCTIONS HELPERS
# =============================================================================

# List Cloud Functions
# Usage: gcp_functions_list [region]
# Returns: JSON array of function info
# @idempotent
gcp_functions_list() {
    _gcp_require_cli || return 1

    local region="${1:-}"
    local args=("functions" "list" "--format=json")

    [[ -n "$region" ]] && args+=("--regions=$region")

    local result
    result=$(gcloud "${args[@]}" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list Cloud Functions"}'
        return 1
    }

    # If result is empty or null, return empty array
    if [[ -z "$result" || "$result" == "[]" ]]; then
        printf '{"success":true,"data":[]}'
        return 0
    fi

    printf '{"success":true,"data":%s}' "$result"
}

# Invoke Cloud Function
# Usage: gcp_functions_invoke "function_name" [data_json] [region]
# Returns: USOP JSON with function response
gcp_functions_invoke() {
    _gcp_require_cli || return 1

    local function_name="$1"
    local data="${2:-{}}"
    local region="${3:-}"

    [[ -z "$function_name" ]] && {
        printf '{"success":false,"error":"Function name required"}'
        return 1
    }

    local args=("functions" "call" "$function_name" "--data=$data")
    [[ -n "$region" ]] && args+=("--region=$region")

    local output
    output=$(gcloud "${args[@]}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Extract the result - gcloud functions call outputs result in a specific format
        local response
        response="$(_gcp_json_escape "$output")"
        printf '{"success":true,"data":{"function":"%s","response":"%s"}}' \
            "$(_gcp_json_escape "$function_name")" "$response"
    else
        printf '{"success":false,"error":"Function invocation failed","function":"%s","details":"%s"}' \
            "$(_gcp_json_escape "$function_name")" "$(_gcp_json_escape "$output")"
        return 1
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_EXT_GCP_EXPORTS=(
    # Availability & Configuration
    gcp_configured
    gcp_project
    gcp_region
    # Cloud Storage
    gcp_storage_list
    gcp_storage_upload
    gcp_storage_download
    # Compute Engine
    gcp_compute_list
    gcp_compute_status
    # Cloud Functions
    gcp_functions_list
    gcp_functions_invoke
)

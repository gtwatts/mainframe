#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ext/gcp.sh - Google Cloud CLI Wrapper Functions (OPTIONAL)
# =============================================================================
# Description: Convenience wrappers for Google Cloud (gcloud) CLI operations
# Requires: gcloud CLI (https://cloud.google.com/sdk/gcloud)
# Status: STUB - Framework for future expansion
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
        printf '{"success":false,"error":"gcloud CLI not installed","hint":"Install from https://cloud.google.com/sdk/gcloud"}'
        return 1
    fi
    return 0
}

# =============================================================================
# AVAILABILITY & IDENTITY
# =============================================================================

# Check if gcloud CLI is available and configured
# Usage: gcp_available
# Returns: 0 if gcloud CLI is installed and authenticated, 1 otherwise
# @idempotent
gcp_available() {
    _gcp_has_cli || return 1
    # Verify authentication
    gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .
}

# Get current GCP project ID
# Usage: gcp_project
# Returns: Project ID string
# @idempotent
gcp_project() {
    _gcp_require_cli || return 1
    gcloud config get-value project 2>/dev/null
}

# Get current GCP region
# Usage: gcp_region
# Returns: Region string (e.g., "us-central1")
# @idempotent
gcp_region() {
    _gcp_require_cli || return 1
    gcloud config get-value compute/region 2>/dev/null || echo "${CLOUDSDK_COMPUTE_REGION:-us-central1}"
}

# Get caller identity as JSON (USOP format)
# Usage: gcp_whoami
# Returns: JSON with account, project, and region
# @idempotent
gcp_whoami() {
    _gcp_require_cli || return 1

    local account project region
    account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)

    [[ -z "$account" ]] && {
        printf '{"success":false,"error":"No active GCP account","hint":"Run gcloud auth login"}'
        return 1
    }

    project=$(gcp_project)
    region=$(gcp_region)

    printf '{"success":true,"data":{"account":"%s","project":"%s","region":"%s"}}' \
        "$account" "$project" "$region"
}

# =============================================================================
# GCS (GOOGLE CLOUD STORAGE) HELPERS
# =============================================================================

# List GCS buckets
# Usage: gcp_gcs_list [prefix]
# Returns: JSON array of bucket names
gcp_gcs_list() {
    _gcp_require_cli || return 1

    local prefix="${1:-}"
    local buckets

    buckets=$(gcloud storage buckets list --format="value(name)" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list GCS buckets"}'
        return 1
    }

    # Filter by prefix if provided
    [[ -n "$prefix" ]] && buckets=$(echo "$buckets" | grep "^${prefix}")

    if [[ -z "$buckets" ]]; then
        printf '{"success":true,"data":[]}'
        return 0
    fi

    # Convert to JSON array
    local json_array="["
    local first=true
    while IFS= read -r bucket; do
        $first || json_array+=","
        first=false
        json_array+="\"$bucket\""
    done <<< "$buckets"
    json_array+="]"

    printf '{"success":true,"data":%s}' "$json_array"
}

# Copy file to/from GCS
# Usage: gcp_gcs_cp "source" "destination"
# Returns: USOP JSON result
gcp_gcs_cp() {
    _gcp_require_cli || return 1

    local source="$1"
    local dest="$2"

    [[ -z "$source" || -z "$dest" ]] && {
        printf '{"success":false,"error":"Source and destination required"}'
        return 1
    }

    if gcloud storage cp "$source" "$dest" &>/dev/null; then
        printf '{"success":true,"data":{"source":"%s","destination":"%s"}}' "$source" "$dest"
    else
        printf '{"success":false,"error":"GCS copy failed","source":"%s","destination":"%s"}' "$source" "$dest"
        return 1
    fi
}

# =============================================================================
# COMPUTE ENGINE HELPERS
# =============================================================================

# List Compute Engine instances
# Usage: gcp_compute_list [zone]
# Returns: JSON array of instance info
gcp_compute_list() {
    _gcp_require_cli || return 1

    local zone="${1:-}"
    local zone_args=()

    [[ -n "$zone" ]] && zone_args=(--zones="$zone")

    local result
    result=$(gcloud compute instances list "${zone_args[@]}" \
        --format="json(name,zone.basename(),status,machineType.basename())" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list Compute Engine instances"}'
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# Start Compute Engine instance
# Usage: gcp_compute_start "instance_name" "zone"
# Returns: USOP JSON result
gcp_compute_start() {
    _gcp_require_cli || return 1

    local instance_name="$1"
    local zone="$2"

    [[ -z "$instance_name" ]] && {
        printf '{"success":false,"error":"Instance name required"}'
        return 1
    }

    # Use default zone if not provided
    [[ -z "$zone" ]] && zone=$(gcloud config get-value compute/zone 2>/dev/null)

    [[ -z "$zone" ]] && {
        printf '{"success":false,"error":"Zone required (set default with gcloud config set compute/zone)"}'
        return 1
    }

    if gcloud compute instances start "$instance_name" --zone="$zone" &>/dev/null; then
        printf '{"success":true,"data":{"instance":"%s","zone":"%s","action":"start"}}' "$instance_name" "$zone"
    else
        printf '{"success":false,"error":"Failed to start instance","instance":"%s","zone":"%s"}' "$instance_name" "$zone"
        return 1
    fi
}

# Stop Compute Engine instance
# Usage: gcp_compute_stop "instance_name" "zone"
# Returns: USOP JSON result
gcp_compute_stop() {
    _gcp_require_cli || return 1

    local instance_name="$1"
    local zone="$2"

    [[ -z "$instance_name" ]] && {
        printf '{"success":false,"error":"Instance name required"}'
        return 1
    }

    # Use default zone if not provided
    [[ -z "$zone" ]] && zone=$(gcloud config get-value compute/zone 2>/dev/null)

    [[ -z "$zone" ]] && {
        printf '{"success":false,"error":"Zone required (set default with gcloud config set compute/zone)"}'
        return 1
    }

    if gcloud compute instances stop "$instance_name" --zone="$zone" &>/dev/null; then
        printf '{"success":true,"data":{"instance":"%s","zone":"%s","action":"stop"}}' "$instance_name" "$zone"
    else
        printf '{"success":false,"error":"Failed to stop instance","instance":"%s","zone":"%s"}' "$instance_name" "$zone"
        return 1
    fi
}

# =============================================================================
# CLOUD FUNCTIONS HELPERS (STUB)
# =============================================================================

# List Cloud Functions
# Usage: gcp_functions_list [region]
# Returns: JSON array of function info
gcp_functions_list() {
    _gcp_require_cli || return 1

    local region="${1:-}"
    local region_args=()

    [[ -n "$region" ]] && region_args=(--regions="$region")

    local result
    result=$(gcloud functions list "${region_args[@]}" \
        --format="json(name,status,runtime,entryPoint)" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list Cloud Functions"}'
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_EXT_GCP_EXPORTS=(
    # Availability & Identity
    gcp_available
    gcp_project
    gcp_region
    gcp_whoami
    # GCS
    gcp_gcs_list
    gcp_gcs_cp
    # Compute Engine
    gcp_compute_list
    gcp_compute_start
    gcp_compute_stop
    # Cloud Functions
    gcp_functions_list
)

#!/usr/bin/env bash
# =============================================================================
# UACP Memory Exchange - Reference Implementation
# =============================================================================
# This file demonstrates the Universal AI CLI Protocol memory exchange format
# and shows how MAINFRAME can integrate with multiple AI CLIs.
# =============================================================================

# Source MAINFRAME
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# =============================================================================
# UACP v1.0 Memory Export/Import
# =============================================================================

uacp_memory_export() {
    local session_id="${1:-$AWM_SESSION_ID}"
    
    [[ -z "$session_id" ]] && {
        output_error "E_NO_SESSION" "No AWM session ID provided"
        return 1
    }
    
    # Build UACP-compliant memory object
    local checkpoints discoveries metadata
    
    # Get checkpoints from AWM
    checkpoints=$(awm_export_checkpoints "$session_id" 2>/dev/null || echo "[]")
    
    # Get discoveries from AWM
    discoveries=$(awm_export_discoveries "$session_id" 2>/dev/null || echo "[]")
    
    # Get session metadata
    metadata=$(json_object \
        "session_id=$session_id" \
        "origin_cli=${UACP_CLI_TYPE:-mainframe}" \
        "exported_at=$(now_iso)" \
        "version=1.0.0" \
        "token_estimate=$(awm_token_estimate 2>/dev/null || echo "0")"
    )
    
    # Build complete UACP memory envelope
    json_object \
        "uacp_version=1.0.0" \
        "metadata:raw=$metadata" \
        "memory:raw=$(json_object \
            "checkpoints:raw=$checkpoints" \
            "discoveries:raw=$discoveries" \
            "context_window:raw=$(json_object \
                "max_tokens=${UACP_MAX_TOKENS:-128000}" \
                "used_tokens=$(awm_token_estimate 2>/dev/null || echo "0")"
            )"
        )"
}

uacp_memory_import() {
    local uacp_data="$1"
    local target_namespace="${2:-uacp-import}"
    
    # Validate UACP format
    local version
    version=$(json_get "$uacp_data" "uacp_version" 2>/dev/null)
    
    [[ "$version" != "1.0.0" ]] && {
        output_error "E_UACP_VERSION" "Unsupported UACP version: $version"
        return 1
    }
    
    # Create new session for imported memory
    local origin_cli new_session_id
    origin_cli=$(json_get "$uacp_data" "metadata.origin_cli" 2>/dev/null || echo "unknown")
    new_session_id=$(awm_init "uacp-${origin_cli}-$(uuid)")
    
    # Import checkpoints
    local checkpoints checkpoint_count
    checkpoints=$(json_get "$uacp_data" "memory.checkpoints" 2>/dev/null || echo "[]")
    checkpoint_count=$(json_array_length "$checkpoints" 2>/dev/null || echo "0")
    
    if [[ "$checkpoint_count" -gt 0 ]]; then
        # Iterate through checkpoints and restore
        for ((i=0; i<checkpoint_count; i++)); do
            local checkpoint
            checkpoint=$(json_array_get "$checkpoints" "$i" 2>/dev/null)
            [[ -z "$checkpoint" ]] && continue
            
            local key value
            key=$(json_get "$checkpoint" "key" 2>/dev/null)
            value=$(json_get "$checkpoint" "value" 2>/dev/null)
            
            [[ -n "$key" ]] && awm_checkpoint "$key" "$value"
        done
    fi
    
    # Import discoveries
    local discoveries discovery_count
    discoveries=$(json_get "$uacp_data" "memory.discoveries" 2>/dev/null || echo "[]")
    discovery_count=$(json_array_length "$discoveries" 2>/dev/null || echo "0")
    
    if [[ "$discovery_count" -gt 0 ]]; then
        for ((i=0; i<discovery_count; i++)); do
            local discovery
            discovery=$(json_array_get "$discoveries" "$i" 2>/dev/null)
            [[ -z "$discovery" ]] && continue
            
            local content
            content=$(json_get "$discovery" "content" 2>/dev/null)
            [[ -n "$content" ]] && awm_discovery "$content"
        done
    fi
    
    # Return new session ID
    output_success "$new_session_id" "uacp_import"
}

uacp_validate() {
    local data="$1"
    
    # Check required fields
    local version
    version=$(json_get "$data" "uacp_version" 2>/dev/null)
    [[ -z "$version" ]] && return 1
    
    local metadata
    metadata=$(json_get "$data" "metadata" 2>/dev/null)
    [[ -z "$metadata" ]] && return 1
    
    return 0
}

# =============================================================================
# Cross-CLI Handoff Functions
# =============================================================================

uacp_handoff_export() {
    local session_id="${1:-$AWM_SESSION_ID}"
    local target_cli="$2"  # e.g., "kimi-cli", "claude-code"
    
    [[ -z "$target_cli" ]] && {
        output_error "E_MISSING_ARG" "Target CLI type required"
        return 1
    }
    
    # Export with handoff metadata
    local memory_data handoff_data
    memory_data=$(uacp_memory_export "$session_id")
    
    handoff_data=$(json_object \
        "uacp_version=1.0.0" \
        "handoff:raw=$(json_object \
            "from_cli=${UACP_CLI_TYPE:-mainframe}" \
            "to_cli=$target_cli" \
            "timestamp=$(now_iso)" \
            "handoff_id=$(uuid)"
        )" \
        "memory:raw=$(json_get "$memory_data" "memory")" \
        "metadata:raw=$(json_get "$memory_data" "metadata")"
    )
    
    printf '%s' "$handoff_data"
}

uacp_handoff_import() {
    local handoff_data="$1"
    
    # Validate handoff format
    local handoff_meta from_cli to_cli
    handoff_meta=$(json_get "$handoff_data" "handoff" 2>/dev/null)
    [[ -z "$handoff_meta" ]] && {
        output_error "E_INVALID_HANDOFF" "Invalid handoff data format"
        return 1
    }
    
    from_cli=$(json_get "$handoff_meta" "from_cli" 2>/dev/null)
    to_cli=$(json_get "$handoff_meta" "to_cli" 2>/dev/null)
    
    # Log handoff
    log_info "Importing handoff from $from_cli to $to_cli"
    
    # Import memory
    local memory_data
    memory_data=$(json_object \
        "uacp_version=$(json_get "$handoff_data" "uacp_version")" \
        "metadata:raw=$(json_get "$handoff_data" "metadata")" \
        "memory:raw=$(json_get "$handoff_data" "memory")"
    )
    
    uacp_memory_import "$memory_data" "handoff-${from_cli}"
}

# =============================================================================
# Capability Negotiation
# =============================================================================

declare -gA UACP_MAINFRAME_CAPS=(
    ["bash_execution"]="full"
    ["file_operations"]="full"
    ["json_processing"]="full"
    ["http_client"]="full"
    ["awm_storage"]="full"
    ["agent_coordination"]="full"
    ["validation"]="full"
    ["crypto"]="full"
    ["parallel_processing"]="full"
    ["structured_output"]="full"
)

uacp_capability_negotiate() {
    local cli_type="$1"
    shift
    local requested_capabilities=("$@")
    
    local result_caps=()
    
    for cap in "${requested_capabilities[@]}"; do
        local level="${UACP_MAINFRAME_CAPS[$cap]:-none}"
        if [[ "$level" != "none" ]]; then
            result_caps+=("$(json_object \
                "capability=$cap" \
                "level=$level" \
                "provided_by=mainframe"
            )")
        fi
    done
    
    # Return capability agreement
    json_object \
        "cli_type=$cli_type" \
        "capabilities:raw=$(json_array "${result_caps[@]}")" \
        "negotiated_at=$(now_iso)"
}

# =============================================================================
# Example Usage
# =============================================================================

example_export_for_claude() {
    header "Example: Export AWM Session for Claude Code"
    
    # Initialize a session
    awm_init "example-task"
    awm_checkpoint "current_step" "5"
    awm_discovery "Found API endpoint at /api/v2"
    awm_log "progress" "Processing batch 3 of 10"
    
    # Export for Claude Code
    local uacp_data
    uacp_data=$(uacp_handoff_export "$AWM_SESSION_ID" "claude-code")
    
    echo "UACP Export Data:"
    json_pretty "$uacp_data"
    
    # Save to file for transfer
    local export_file="/tmp/uacp_export_$(uuid).json"
    json_pretty "$uacp_data" > "$export_file"
    echo ""
    echo "Saved to: $export_file"
    
    awm_close
}

example_import_from_kimi() {
    header "Example: Import UACP Data from Kimi CLI"
    
    # Simulated Kimi CLI export
    local simulated_kimi_export
    simulated_kimi_export='{
        "uacp_version": "1.0.0",
        "metadata": {
            "session_id": "kimi-abc123",
            "origin_cli": "kimi-cli",
            "exported_at": "2026-02-04T10:30:00Z",
            "version": "1.0.0"
        },
        "memory": {
            "checkpoints": [
                {"key": "feature_branch", "value": "feature/auth-redesign", "timestamp": 1738675800},
                {"key": "tests_passing", "value": "42/45", "timestamp": 1738675860}
            ],
            "discoveries": [
                {"content": "Auth middleware needs refactoring", "priority": "high", "timestamp": 1738675820},
                {"content": "JWT secret should be in env vars", "priority": "critical", "timestamp": 1738675840}
            ],
            "context_window": {
                "max_tokens": 128000,
                "used_tokens": 45000
            }
        }
    }'
    
    echo "Simulated Kimi CLI export:"
    json_pretty "$simulated_kimi_export"
    echo ""
    
    # Import into MAINFRAME AWM
    local new_session
    new_session=$(uacp_memory_import "$simulated_kimi_export" "kimi-import")
    
    echo "Imported to new session: $new_session"
    echo ""
    echo "Current AWM state:"
    awm_summary | json_pretty
}

# Run examples if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    header "UACP Memory Exchange Examples"
    
    example_export_for_claude
    echo ""
    example_import_from_kimi
fi

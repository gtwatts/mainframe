#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ext/terraform.sh - Terraform CLI Wrapper Functions (OPTIONAL)
# =============================================================================
# Description: Convenience wrappers for Terraform CLI operations with JSON output
# Requires: terraform CLI (https://www.terraform.io/downloads)
# Status: Production - Infrastructure as Code workflow automation
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_EXT_TERRAFORM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_EXT_TERRAFORM_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if Terraform CLI is available
_tf_has_cli() {
    command -v terraform &>/dev/null
}

# Require Terraform CLI or return error JSON
_tf_require_cli() {
    if ! _tf_has_cli; then
        printf '{"success":false,"error":"Terraform CLI not installed","hint":"Install from https://www.terraform.io/downloads"}'
        return 1
    fi
    return 0
}

# Escape string for JSON
_tf_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# =============================================================================
# DETECTION & VERSION
# =============================================================================

# Detect if directory contains Terraform files
# Usage: tf_detect [directory]
# Returns: JSON with detection result and file count
# @idempotent
tf_detect() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        printf '{"success":false,"error":"Directory not found","directory":"%s"}' "$(_tf_json_escape "$dir")"
        return 1
    fi

    local tf_files
    tf_files=$(find "$dir" -maxdepth 1 -name "*.tf" -type f 2>/dev/null | wc -l)
    tf_files="${tf_files// /}"

    local tfvars_files
    tfvars_files=$(find "$dir" -maxdepth 1 -name "*.tfvars" -type f 2>/dev/null | wc -l)
    tfvars_files="${tfvars_files// /}"

    local has_tf=false
    [[ "$tf_files" -gt 0 ]] && has_tf=true

    local has_state=false
    [[ -f "$dir/terraform.tfstate" || -f "$dir/.terraform/terraform.tfstate" ]] && has_state=true

    local has_lock=false
    [[ -f "$dir/.terraform.lock.hcl" ]] && has_lock=true

    local initialized=false
    [[ -d "$dir/.terraform" ]] && initialized=true

    printf '{"success":true,"data":{"is_terraform_dir":%s,"tf_files":%d,"tfvars_files":%d,"has_state":%s,"has_lock":%s,"initialized":%s,"directory":"%s"}}' \
        "$has_tf" "$tf_files" "$tfvars_files" "$has_state" "$has_lock" "$initialized" "$(_tf_json_escape "$dir")"
}

# Get Terraform version
# Usage: tf_version
# Returns: JSON with version info
# @idempotent
tf_version() {
    _tf_require_cli || return 1

    local version_output
    local exit_code

    version_output=$(terraform version -json 2>/dev/null)
    exit_code=$?

    if [[ $exit_code -eq 0 && -n "$version_output" ]]; then
        # Terraform 0.13+ supports -json flag
        printf '{"success":true,"data":%s}' "$version_output"
    else
        # Fallback for older versions
        local version
        version=$(terraform version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
        if [[ -n "$version" ]]; then
            printf '{"success":true,"data":{"terraform_version":"%s"}}' "$version"
        else
            printf '{"success":false,"error":"Failed to get Terraform version"}'
            return 1
        fi
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize Terraform working directory
# Usage: tf_init [directory] [options...]
# Options: -upgrade, -reconfigure, -backend=false, -backend-config="KEY=VALUE"
# Returns: JSON with init result
tf_init() {
    _tf_require_cli || return 1

    local dir="."
    local opts=()

    # Parse arguments
    for arg in "$@"; do
        if [[ -d "$arg" && "${arg:0:1}" != "-" ]]; then
            dir="$arg"
        else
            opts+=("$arg")
        fi
    done

    local output
    local exit_code

    # Change to directory and run init
    output=$(cd "$dir" && terraform init -no-color "${opts[@]}" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        printf '{"success":true,"data":{"message":"Terraform initialized successfully","directory":"%s"}}' \
            "$(_tf_json_escape "$dir")"
    else
        printf '{"success":false,"error":"Terraform init failed","exit_code":%d,"output":"%s","directory":"%s"}' \
            "$exit_code" "$(_tf_json_escape "$output")" "$(_tf_json_escape "$dir")"
        return 1
    fi
}

# =============================================================================
# PLAN & APPLY
# =============================================================================

# Run terraform plan with JSON output
# Usage: tf_plan [directory] [options...]
# Options: -var="KEY=VALUE", -var-file=FILE, -out=FILE, -target=RESOURCE
# Returns: JSON with plan summary
tf_plan() {
    _tf_require_cli || return 1

    local dir="."
    local opts=()
    local plan_file=""

    # Parse arguments
    for arg in "$@"; do
        if [[ -d "$arg" && "${arg:0:1}" != "-" ]]; then
            dir="$arg"
        elif [[ "$arg" == -out=* ]]; then
            plan_file="${arg#-out=}"
            opts+=("$arg")
        else
            opts+=("$arg")
        fi
    done

    local output
    local exit_code

    # Run plan with JSON output
    output=$(cd "$dir" && terraform plan -json -no-color "${opts[@]}" 2>&1)
    exit_code=$?

    # Parse the JSON output to extract summary
    local add=0 change=0 destroy=0
    local has_changes=false

    # Look for the planned_change messages
    while IFS= read -r line; do
        if [[ "$line" =~ \"@level\":\"info\" && "$line" =~ \"type\":\"planned_change\" ]]; then
            has_changes=true
            if [[ "$line" =~ \"action\":\"create\" ]]; then
                ((add++)) || true
            elif [[ "$line" =~ \"action\":\"update\" ]]; then
                ((change++)) || true
            elif [[ "$line" =~ \"action\":\"delete\" ]]; then
                ((destroy++)) || true
            fi
        fi
        # Also check for change_summary
        if [[ "$line" =~ \"type\":\"change_summary\" ]]; then
            # Extract counts from change_summary if present
            local adds changes destroys
            adds=$(echo "$line" | grep -oE '"add":[0-9]+' | cut -d: -f2)
            changes=$(echo "$line" | grep -oE '"change":[0-9]+' | cut -d: -f2)
            destroys=$(echo "$line" | grep -oE '"remove":[0-9]+' | cut -d: -f2)
            [[ -n "$adds" ]] && add=$adds
            [[ -n "$changes" ]] && change=$changes
            [[ -n "$destroys" ]] && destroy=$destroys
        fi
    done <<< "$output"

    if [[ $exit_code -eq 0 ]]; then
        printf '{"success":true,"data":{"has_changes":%s,"add":%d,"change":%d,"destroy":%d,"directory":"%s"' \
            "$has_changes" "$add" "$change" "$destroy" "$(_tf_json_escape "$dir")"
        [[ -n "$plan_file" ]] && printf ',"plan_file":"%s"' "$(_tf_json_escape "$plan_file")"
        printf '}}'
    elif [[ $exit_code -eq 2 ]]; then
        # Exit code 2 means changes required but plan succeeded
        printf '{"success":true,"data":{"has_changes":true,"add":%d,"change":%d,"destroy":%d,"directory":"%s"' \
            "$add" "$change" "$destroy" "$(_tf_json_escape "$dir")"
        [[ -n "$plan_file" ]] && printf ',"plan_file":"%s"' "$(_tf_json_escape "$plan_file")"
        printf '}}'
    else
        printf '{"success":false,"error":"Terraform plan failed","exit_code":%d,"directory":"%s"}' \
            "$exit_code" "$(_tf_json_escape "$dir")"
        return 1
    fi
}

# Run terraform apply
# Usage: tf_apply [directory] [options...]
# Options: -auto-approve, -var="KEY=VALUE", -var-file=FILE, -target=RESOURCE, PLAN_FILE
# Returns: JSON with apply result
tf_apply() {
    _tf_require_cli || return 1

    local dir="."
    local opts=()
    local plan_file=""

    # Parse arguments
    for arg in "$@"; do
        if [[ -d "$arg" && "${arg:0:1}" != "-" ]]; then
            dir="$arg"
        elif [[ -f "$arg" && "${arg:0:1}" != "-" ]]; then
            plan_file="$arg"
        else
            opts+=("$arg")
        fi
    done

    local output
    local exit_code

    # Build command
    local cmd_args=(-json -no-color "${opts[@]}")
    [[ -n "$plan_file" ]] && cmd_args+=("$plan_file")

    output=$(cd "$dir" && terraform apply "${cmd_args[@]}" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Count resources from apply output
        local add=0 change=0 destroy=0
        while IFS= read -r line; do
            if [[ "$line" =~ \"type\":\"apply_complete\" ]]; then
                local adds changes destroys
                adds=$(echo "$line" | grep -oE '"add":[0-9]+' | cut -d: -f2)
                changes=$(echo "$line" | grep -oE '"change":[0-9]+' | cut -d: -f2)
                destroys=$(echo "$line" | grep -oE '"remove":[0-9]+' | cut -d: -f2)
                [[ -n "$adds" ]] && add=$adds
                [[ -n "$changes" ]] && change=$changes
                [[ -n "$destroys" ]] && destroy=$destroys
            fi
        done <<< "$output"

        printf '{"success":true,"data":{"message":"Apply complete","add":%d,"change":%d,"destroy":%d,"directory":"%s"}}' \
            "$add" "$change" "$destroy" "$(_tf_json_escape "$dir")"
    else
        printf '{"success":false,"error":"Terraform apply failed","exit_code":%d,"directory":"%s"}' \
            "$exit_code" "$(_tf_json_escape "$dir")"
        return 1
    fi
}

# Run terraform destroy
# Usage: tf_destroy [directory] [options...]
# Options: -auto-approve, -var="KEY=VALUE", -var-file=FILE, -target=RESOURCE
# Returns: JSON with destroy result
tf_destroy() {
    _tf_require_cli || return 1

    local dir="."
    local opts=()

    # Parse arguments
    for arg in "$@"; do
        if [[ -d "$arg" && "${arg:0:1}" != "-" ]]; then
            dir="$arg"
        else
            opts+=("$arg")
        fi
    done

    local output
    local exit_code

    # shellcheck disable=SC2034  # output used conditionally
    output=$(cd "$dir" && terraform destroy -json -no-color "${opts[@]}" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        printf '{"success":true,"data":{"message":"Destroy complete","directory":"%s"}}' \
            "$(_tf_json_escape "$dir")"
    else
        printf '{"success":false,"error":"Terraform destroy failed","exit_code":%d,"directory":"%s"}' \
            "$exit_code" "$(_tf_json_escape "$dir")"
        return 1
    fi
}

# =============================================================================
# STATE OPERATIONS
# =============================================================================

# List resources in Terraform state
# Usage: tf_state_list [directory] [address...]
# Returns: JSON array of resource addresses
# @idempotent
tf_state_list() {
    _tf_require_cli || return 1

    local dir="."
    local addresses=()

    # Parse arguments
    for arg in "$@"; do
        if [[ -d "$arg" && "${arg:0:1}" != "-" && ${#addresses[@]} -eq 0 ]]; then
            dir="$arg"
        else
            addresses+=("$arg")
        fi
    done

    local output
    local exit_code

    output=$(cd "$dir" && terraform state list "${addresses[@]}" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Convert newline-separated list to JSON array
        local json_array="["
        local first=true
        while IFS= read -r resource; do
            [[ -z "$resource" ]] && continue
            $first || json_array+=","
            first=false
            json_array+="\"$(_tf_json_escape "$resource")\""
        done <<< "$output"
        json_array+="]"

        printf '{"success":true,"data":{"resources":%s,"count":%d,"directory":"%s"}}' \
            "$json_array" "$(echo "$output" | grep -c . 2>/dev/null || echo 0)" "$(_tf_json_escape "$dir")"
    else
        # Empty state returns exit code 0 but we handle other errors
        if [[ "$output" =~ "No state file" || "$output" =~ "does not exist" ]]; then
            printf '{"success":true,"data":{"resources":[],"count":0,"directory":"%s","note":"No state file found"}}' \
                "$(_tf_json_escape "$dir")"
        else
            printf '{"success":false,"error":"Failed to list state","exit_code":%d,"output":"%s","directory":"%s"}' \
                "$exit_code" "$(_tf_json_escape "$output")" "$(_tf_json_escape "$dir")"
            return 1
        fi
    fi
}

# =============================================================================
# OUTPUTS
# =============================================================================

# Get Terraform outputs as JSON
# Usage: tf_output [directory] [output_name]
# Returns: JSON with outputs
# @idempotent
tf_output() {
    _tf_require_cli || return 1

    local dir="."
    local output_name=""

    # Parse arguments
    for arg in "$@"; do
        if [[ -d "$arg" && "${arg:0:1}" != "-" ]]; then
            dir="$arg"
        elif [[ "${arg:0:1}" != "-" && -z "$output_name" ]]; then
            output_name="$arg"
        fi
    done

    local output
    local exit_code

    if [[ -n "$output_name" ]]; then
        output=$(cd "$dir" && terraform output -json "$output_name" 2>&1)
    else
        output=$(cd "$dir" && terraform output -json 2>&1)
    fi
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Wrap in success envelope
        if [[ -n "$output" && "$output" != "{}" ]]; then
            printf '{"success":true,"data":%s}' "$output"
        else
            printf '{"success":true,"data":{}}'
        fi
    else
        if [[ "$output" =~ "No outputs found" || "$output" =~ "not found" ]]; then
            printf '{"success":true,"data":{},"note":"No outputs defined"}'
        else
            printf '{"success":false,"error":"Failed to get outputs","exit_code":%d,"output":"%s","directory":"%s"}' \
                "$exit_code" "$(_tf_json_escape "$output")" "$(_tf_json_escape "$dir")"
            return 1
        fi
    fi
}

# =============================================================================
# VALIDATION & FORMATTING
# =============================================================================

# Validate Terraform configuration
# Usage: tf_validate [directory]
# Returns: JSON with validation result
# @idempotent
tf_validate() {
    _tf_require_cli || return 1

    local dir="${1:-.}"

    local output
    local exit_code

    output=$(cd "$dir" && terraform validate -json 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Parse the JSON output for valid status
        if [[ "$output" =~ \"valid\":true ]]; then
            printf '{"success":true,"data":{"valid":true,"directory":"%s"}}' "$(_tf_json_escape "$dir")"
        else
            # Extract error details from JSON
            printf '{"success":true,"data":%s}' "$output"
        fi
    else
        printf '{"success":false,"error":"Validation failed","exit_code":%d,"output":"%s","directory":"%s"}' \
            "$exit_code" "$(_tf_json_escape "$output")" "$(_tf_json_escape "$dir")"
        return 1
    fi
}

# Check Terraform formatting
# Usage: tf_fmt_check [directory]
# Returns: JSON with format check result
# @idempotent
tf_fmt_check() {
    _tf_require_cli || return 1

    local dir="${1:-.}"

    local output
    local exit_code

    output=$(cd "$dir" && terraform fmt -check -recursive -diff 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        printf '{"success":true,"data":{"formatted":true,"directory":"%s"}}' "$(_tf_json_escape "$dir")"
    elif [[ $exit_code -eq 3 ]]; then
        # Exit code 3 means there are files that need formatting
        local unformatted_files="["
        local first=true
        while IFS= read -r file; do
            [[ -z "$file" || "$file" =~ ^[+-] || "$file" =~ ^@@ ]] && continue
            $first || unformatted_files+=","
            first=false
            unformatted_files+="\"$(_tf_json_escape "$file")\""
        done <<< "$output"
        unformatted_files+="]"

        printf '{"success":true,"data":{"formatted":false,"unformatted_files":%s,"directory":"%s"}}' \
            "$unformatted_files" "$(_tf_json_escape "$dir")"
    else
        printf '{"success":false,"error":"Format check failed","exit_code":%d,"output":"%s","directory":"%s"}' \
            "$exit_code" "$(_tf_json_escape "$output")" "$(_tf_json_escape "$dir")"
        return 1
    fi
}

# =============================================================================
# WORKSPACE OPERATIONS
# =============================================================================

# List Terraform workspaces
# Usage: tf_workspace_list [directory]
# Returns: JSON with workspace list
# @idempotent
tf_workspace_list() {
    _tf_require_cli || return 1

    local dir="${1:-.}"

    local output
    local exit_code

    output=$(cd "$dir" && terraform workspace list 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local workspaces="["
        local current=""
        local first=true

        while IFS= read -r line; do
            # Remove leading/trailing whitespace
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" ]] && continue

            # Check for current workspace marker (line starts with "* ")
            local ws_name="$line"
            if [[ "$line" == \** ]]; then
                # Remove the "* " prefix and trim again
                ws_name="${line#\*}"
                ws_name="${ws_name#"${ws_name%%[![:space:]]*}"}"
                current="$ws_name"
            fi

            $first || workspaces+=","
            first=false
            workspaces+="\"$(_tf_json_escape "$ws_name")\""
        done <<< "$output"
        workspaces+="]"

        printf '{"success":true,"data":{"workspaces":%s,"current":"%s","directory":"%s"}}' \
            "$workspaces" "$(_tf_json_escape "$current")" "$(_tf_json_escape "$dir")"
    else
        printf '{"success":false,"error":"Failed to list workspaces","exit_code":%d,"output":"%s","directory":"%s"}' \
            "$exit_code" "$(_tf_json_escape "$output")" "$(_tf_json_escape "$dir")"
        return 1
    fi
}

# Select Terraform workspace
# Usage: tf_workspace_select "workspace_name" [directory]
# Returns: JSON with selection result
tf_workspace_select() {
    _tf_require_cli || return 1

    local workspace="$1"
    local dir="${2:-.}"

    if [[ -z "$workspace" ]]; then
        printf '{"success":false,"error":"Workspace name required"}'
        return 1
    fi

    local output
    local exit_code

    output=$(cd "$dir" && terraform workspace select "$workspace" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        printf '{"success":true,"data":{"workspace":"%s","directory":"%s"}}' \
            "$(_tf_json_escape "$workspace")" "$(_tf_json_escape "$dir")"
    else
        # Check if workspace doesn't exist
        if [[ "$output" =~ "doesn't exist" || "$output" =~ "does not exist" ]]; then
            printf '{"success":false,"error":"Workspace does not exist","workspace":"%s","directory":"%s"}' \
                "$(_tf_json_escape "$workspace")" "$(_tf_json_escape "$dir")"
        else
            printf '{"success":false,"error":"Failed to select workspace","exit_code":%d,"output":"%s","directory":"%s"}' \
                "$exit_code" "$(_tf_json_escape "$output")" "$(_tf_json_escape "$dir")"
        fi
        return 1
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# shellcheck disable=SC2034  # Used by MAINFRAME lazy loading system
MAINFRAME_EXT_TERRAFORM_EXPORTS=(
    # Detection & Version
    tf_detect
    tf_version
    # Initialization
    tf_init
    # Plan & Apply
    tf_plan
    tf_apply
    tf_destroy
    # State
    tf_state_list
    # Outputs
    tf_output
    # Validation & Formatting
    tf_validate
    tf_fmt_check
    # Workspaces
    tf_workspace_list
    tf_workspace_select
)

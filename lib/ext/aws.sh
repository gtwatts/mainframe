#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ext/aws.sh - AWS CLI Wrapper Functions (OPTIONAL)
# =============================================================================
# Description: Convenience wrappers for AWS CLI operations
# Requires: aws CLI (https://aws.amazon.com/cli/)
# Status: STUB - Framework for future expansion
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_EXT_AWS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_EXT_AWS_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if AWS CLI is available
_aws_has_cli() {
    command -v aws &>/dev/null
}

# Require AWS CLI or return error JSON
_aws_require_cli() {
    if ! _aws_has_cli; then
        printf '{"success":false,"error":"AWS CLI not installed","hint":"Install from https://aws.amazon.com/cli/"}'
        return 1
    fi
    return 0
}

# =============================================================================
# AVAILABILITY & IDENTITY
# =============================================================================

# Check if AWS CLI is available and configured
# Usage: aws_available
# Returns: 0 if aws CLI is installed and configured, 1 otherwise
# @idempotent
aws_available() {
    _aws_has_cli || return 1
    # Verify credentials are configured
    aws sts get-caller-identity &>/dev/null
}

# Get current AWS account ID
# Usage: aws_account_id
# Returns: Account ID (12-digit string)
# @idempotent
aws_account_id() {
    _aws_require_cli || return 1
    aws sts get-caller-identity --query 'Account' --output text 2>/dev/null
}

# Get current AWS region
# Usage: aws_region
# Returns: Region string (e.g., "us-east-1")
# @idempotent
aws_region() {
    _aws_require_cli || return 1
    aws configure get region 2>/dev/null || echo "${AWS_DEFAULT_REGION:-us-east-1}"
}

# Get caller identity as JSON (USOP format)
# Usage: aws_whoami
# Returns: JSON with account, user ARN, and region
# @idempotent
aws_whoami() {
    _aws_require_cli || return 1

    local identity region
    identity=$(aws sts get-caller-identity --output json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to get caller identity","hint":"Run aws configure"}'
        return 1
    }

    region=$(aws_region)

    # Extract fields and build USOP response
    local account arn user_id
    account=$(echo "$identity" | grep -o '"Account"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    arn=$(echo "$identity" | grep -o '"Arn"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    user_id=$(echo "$identity" | grep -o '"UserId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

    printf '{"success":true,"data":{"account":"%s","arn":"%s","user_id":"%s","region":"%s"}}' \
        "$account" "$arn" "$user_id" "$region"
}

# =============================================================================
# S3 HELPERS
# =============================================================================

# List S3 buckets
# Usage: aws_s3_list [prefix]
# Returns: JSON array of bucket names
aws_s3_list() {
    _aws_require_cli || return 1

    local prefix="${1:-}"
    local buckets

    if [[ -n "$prefix" ]]; then
        buckets=$(aws s3 ls 2>/dev/null | awk '{print $3}' | grep "^${prefix}")
    else
        buckets=$(aws s3 ls 2>/dev/null | awk '{print $3}')
    fi

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

# Copy file to/from S3
# Usage: aws_s3_cp "source" "destination"
# Returns: USOP JSON result
aws_s3_cp() {
    _aws_require_cli || return 1

    local source="$1"
    local dest="$2"

    [[ -z "$source" || -z "$dest" ]] && {
        printf '{"success":false,"error":"Source and destination required"}'
        return 1
    }

    if aws s3 cp "$source" "$dest" &>/dev/null; then
        printf '{"success":true,"data":{"source":"%s","destination":"%s"}}' "$source" "$dest"
    else
        printf '{"success":false,"error":"S3 copy failed","source":"%s","destination":"%s"}' "$source" "$dest"
        return 1
    fi
}

# Sync local directory with S3
# Usage: aws_s3_sync "source" "destination" [--delete]
# Returns: USOP JSON result
aws_s3_sync() {
    _aws_require_cli || return 1

    local source="$1"
    local dest="$2"
    local delete_flag="${3:-}"

    [[ -z "$source" || -z "$dest" ]] && {
        printf '{"success":false,"error":"Source and destination required"}'
        return 1
    }

    local cmd_args=("$source" "$dest")
    [[ "$delete_flag" == "--delete" ]] && cmd_args+=("--delete")

    if aws s3 sync "${cmd_args[@]}" &>/dev/null; then
        printf '{"success":true,"data":{"source":"%s","destination":"%s","delete":%s}}' \
            "$source" "$dest" "$([[ "$delete_flag" == "--delete" ]] && echo "true" || echo "false")"
    else
        printf '{"success":false,"error":"S3 sync failed"}'
        return 1
    fi
}

# =============================================================================
# EC2 HELPERS
# =============================================================================

# List EC2 instances
# Usage: aws_ec2_list [state]
# Returns: JSON array of instance info
aws_ec2_list() {
    _aws_require_cli || return 1

    local state="${1:-}"
    local filter_args=()

    [[ -n "$state" ]] && filter_args=(--filters "Name=instance-state-name,Values=$state")

    local result
    result=$(aws ec2 describe-instances "${filter_args[@]}" \
        --query 'Reservations[].Instances[].{id:InstanceId,type:InstanceType,state:State.Name,name:Tags[?Key==`Name`].Value|[0]}' \
        --output json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list EC2 instances"}'
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# Start EC2 instance
# Usage: aws_ec2_start "instance_id"
# Returns: USOP JSON result
aws_ec2_start() {
    _aws_require_cli || return 1

    local instance_id="$1"
    [[ -z "$instance_id" ]] && {
        printf '{"success":false,"error":"Instance ID required"}'
        return 1
    }

    if aws ec2 start-instances --instance-ids "$instance_id" &>/dev/null; then
        printf '{"success":true,"data":{"instance_id":"%s","action":"start"}}' "$instance_id"
    else
        printf '{"success":false,"error":"Failed to start instance","instance_id":"%s"}' "$instance_id"
        return 1
    fi
}

# Stop EC2 instance
# Usage: aws_ec2_stop "instance_id"
# Returns: USOP JSON result
aws_ec2_stop() {
    _aws_require_cli || return 1

    local instance_id="$1"
    [[ -z "$instance_id" ]] && {
        printf '{"success":false,"error":"Instance ID required"}'
        return 1
    }

    if aws ec2 stop-instances --instance-ids "$instance_id" &>/dev/null; then
        printf '{"success":true,"data":{"instance_id":"%s","action":"stop"}}' "$instance_id"
    else
        printf '{"success":false,"error":"Failed to stop instance","instance_id":"%s"}' "$instance_id"
        return 1
    fi
}

# =============================================================================
# LAMBDA HELPERS
# =============================================================================

# List Lambda functions
# Usage: aws_lambda_list
# Returns: JSON array of function info
aws_lambda_list() {
    _aws_require_cli || return 1

    local result
    result=$(aws lambda list-functions \
        --query 'Functions[].{name:FunctionName,runtime:Runtime,memory:MemorySize,timeout:Timeout}' \
        --output json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list Lambda functions"}'
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# Invoke Lambda function
# Usage: aws_lambda_invoke "function_name" [payload_json]
# Returns: USOP JSON with function response
aws_lambda_invoke() {
    _aws_require_cli || return 1

    local function_name="$1"
    local payload="${2:-{}}"

    [[ -z "$function_name" ]] && {
        printf '{"success":false,"error":"Function name required"}'
        return 1
    }

    local output_file
    output_file=$(mktemp)

    local status_code
    status_code=$(aws lambda invoke \
        --function-name "$function_name" \
        --payload "$payload" \
        --cli-binary-format raw-in-base64-out \
        "$output_file" \
        --query 'StatusCode' \
        --output text 2>/dev/null)

    if [[ "$status_code" == "200" ]]; then
        local response
        response=$(cat "$output_file")
        rm -f "$output_file"
        printf '{"success":true,"data":{"function":"%s","status_code":%s,"response":%s}}' \
            "$function_name" "$status_code" "$response"
    else
        rm -f "$output_file"
        printf '{"success":false,"error":"Lambda invocation failed","function":"%s","status_code":"%s"}' \
            "$function_name" "$status_code"
        return 1
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_EXT_AWS_EXPORTS=(
    # Availability & Identity
    aws_available
    aws_account_id
    aws_region
    aws_whoami
    # S3
    aws_s3_list
    aws_s3_cp
    aws_s3_sync
    # EC2
    aws_ec2_list
    aws_ec2_start
    aws_ec2_stop
    # Lambda
    aws_lambda_list
    aws_lambda_invoke
)

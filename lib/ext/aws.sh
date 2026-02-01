#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ext/aws.sh - AWS CLI Wrapper Functions (OPTIONAL)
# =============================================================================
# Description: Convenience wrappers for AWS CLI operations
# Requires: aws CLI (https://aws.amazon.com/cli/)
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

# Escape string for JSON
# Usage: _aws_json_escape "string"
_aws_json_escape() {
    local str="$1"
    # Escape backslash, double quote, and control characters
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# =============================================================================
# AVAILABILITY & IDENTITY
# =============================================================================

# Check if AWS CLI is available and configured
# Usage: aws_configured
# Returns: JSON with configuration status
# Example: aws_configured
#   {"success":true,"data":{"configured":true,"arn":"arn:aws:iam::123:user/admin",...}}
# @idempotent
aws_configured() {
    if ! _aws_has_cli; then
        printf '{"success":true,"data":{"configured":false,"error":"AWS CLI not installed"}}'
        return 0
    fi

    local identity
    identity=$(aws sts get-caller-identity --output json 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$identity")
        printf '{"success":true,"data":{"configured":false,"error":"%s"}}' "$escaped_error"
        return 0
    fi

    # Extract fields
    local account arn user_id
    account=$(printf '%s' "$identity" | grep -o '"Account"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    arn=$(printf '%s' "$identity" | grep -o '"Arn"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    user_id=$(printf '%s' "$identity" | grep -o '"UserId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

    printf '{"success":true,"data":{"configured":true,"arn":"%s","account":"%s","user_id":"%s"}}' \
        "$arn" "$account" "$user_id"
}

# Check if AWS CLI is available and configured (legacy function)
# Usage: aws_available
# Returns: 0 if aws CLI is installed and configured, 1 otherwise
# @idempotent
aws_available() {
    _aws_has_cli || return 1
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

# Get or set current AWS region
# Usage: aws_region [new_region]
# Returns: JSON with region info or region string (backward compatible)
# Example: aws_region
#   {"success":true,"data":{"region":"us-east-1"}}
# Example: aws_region us-west-2
#   {"success":true,"data":{"region":"us-west-2","previous":"us-east-1"}}
# @idempotent (when reading)
aws_region() {
    local new_region="$1"

    if ! _aws_has_cli; then
        if [[ -n "$new_region" ]]; then
            printf '{"success":false,"error":"AWS CLI not installed"}'
            return 1
        fi
        # Return default region for backward compatibility
        printf '%s' "${AWS_DEFAULT_REGION:-us-east-1}"
        return 0
    fi

    local current_region
    current_region=$(aws configure get region 2>/dev/null || printf '%s' "${AWS_DEFAULT_REGION:-us-east-1}")

    if [[ -n "$new_region" ]]; then
        # Set new region
        if aws configure set region "$new_region" 2>/dev/null; then
            printf '{"success":true,"data":{"region":"%s","previous":"%s"}}' \
                "$new_region" "$current_region"
        else
            printf '{"success":false,"error":"Failed to set region"}'
            return 1
        fi
    else
        # Get current region - return JSON for consistency
        printf '{"success":true,"data":{"region":"%s"}}' "$current_region"
    fi
}

# Get caller identity as JSON (USOP format)
# Usage: aws_whoami
# Returns: JSON with account, user ARN, and region
# @idempotent
aws_whoami() {
    _aws_require_cli || return 1

    local identity
    identity=$(aws sts get-caller-identity --output json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to get caller identity","hint":"Run aws configure"}'
        return 1
    }

    # Get region without JSON wrapper
    local region
    region=$(aws configure get region 2>/dev/null || printf '%s' "${AWS_DEFAULT_REGION:-us-east-1}")

    # Extract fields
    local account arn user_id
    account=$(printf '%s' "$identity" | grep -o '"Account"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    arn=$(printf '%s' "$identity" | grep -o '"Arn"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    user_id=$(printf '%s' "$identity" | grep -o '"UserId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

    printf '{"success":true,"data":{"account":"%s","arn":"%s","user_id":"%s","region":"%s"}}' \
        "$account" "$arn" "$user_id" "$region"
}

# =============================================================================
# S3 HELPERS
# =============================================================================

# List S3 buckets or objects in a bucket
# Usage: aws_s3_list [bucket] [prefix]
# Returns: JSON array of bucket names or objects
# Example: aws_s3_list
#   {"success":true,"data":["bucket1","bucket2"]}
# Example: aws_s3_list my-bucket
#   {"success":true,"data":{"bucket":"my-bucket","objects":[...]}}
# Example: aws_s3_list my-bucket "logs/"
#   {"success":true,"data":{"bucket":"my-bucket","prefix":"logs/","objects":[...]}}
aws_s3_list() {
    _aws_require_cli || return 1

    local bucket="$1"
    local prefix="$2"

    if [[ -z "$bucket" ]]; then
        # List all buckets
        local buckets
        buckets=$(aws s3 ls 2>/dev/null | awk '{print $3}')

        if [[ -z "$buckets" ]]; then
            printf '{"success":true,"data":[]}'
            return 0
        fi

        # Convert to JSON array
        local json_array="["
        local first=true
        while IFS= read -r b; do
            [[ -z "$b" ]] && continue
            $first || json_array+=","
            first=false
            json_array+="\"$b\""
        done <<< "$buckets"
        json_array+="]"

        printf '{"success":true,"data":%s}' "$json_array"
    else
        # List objects in bucket
        local cmd_args=("s3api" "list-objects-v2" "--bucket" "$bucket" "--output" "json")
        [[ -n "$prefix" ]] && cmd_args+=("--prefix" "$prefix")

        local result
        result=$(aws "${cmd_args[@]}" 2>&1)
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            local escaped_error
            escaped_error=$(_aws_json_escape "$result")
            printf '{"success":false,"error":"%s"}' "$escaped_error"
            return 1
        fi

        # Extract Contents array or use empty array
        local objects="[]"
        if [[ "$result" =~ \"Contents\" ]]; then
            # Parse the Contents array from the response
            objects=$(printf '%s' "$result" | \
                sed -n '/"Contents"/,/^[[:space:]]*\]/p' | \
                sed '1s/.*"Contents"[[:space:]]*://' | \
                sed 's/,[[:space:]]*"[A-Za-z]*":.*//')
            # Fallback if parsing fails
            [[ -z "$objects" || "$objects" == "null" ]] && objects="[]"
        fi

        if [[ -n "$prefix" ]]; then
            printf '{"success":true,"data":{"bucket":"%s","prefix":"%s","objects":%s}}' \
                "$bucket" "$prefix" "$objects"
        else
            printf '{"success":true,"data":{"bucket":"%s","objects":%s}}' \
                "$bucket" "$objects"
        fi
    fi
}

# Upload file to S3
# Usage: aws_s3_upload local_path s3_path [content_type]
# Returns: USOP JSON result
# Example: aws_s3_upload ./file.txt s3://my-bucket/path/file.txt
#   {"success":true,"data":{"source":"./file.txt","destination":"s3://my-bucket/path/file.txt"}}
aws_s3_upload() {
    _aws_require_cli || return 1

    local local_path="$1"
    local s3_path="$2"
    local content_type="$3"

    [[ -z "$local_path" ]] && {
        printf '{"success":false,"error":"Local path required"}'
        return 1
    }

    [[ -z "$s3_path" ]] && {
        printf '{"success":false,"error":"S3 path required"}'
        return 1
    }

    [[ ! -f "$local_path" ]] && {
        printf '{"success":false,"error":"Local file not found: %s"}' "$local_path"
        return 1
    }

    local cmd_args=("s3" "cp" "$local_path" "$s3_path")
    [[ -n "$content_type" ]] && cmd_args+=("--content-type" "$content_type")

    local result
    result=$(aws "${cmd_args[@]}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s"}' "$escaped_error"
        return 1
    fi

    printf '{"success":true,"data":{"source":"%s","destination":"%s"}}' "$local_path" "$s3_path"
}

# Download file from S3
# Usage: aws_s3_download s3_path local_path
# Returns: USOP JSON result
# Example: aws_s3_download s3://my-bucket/path/file.txt ./file.txt
#   {"success":true,"data":{"source":"s3://my-bucket/path/file.txt","destination":"./file.txt"}}
aws_s3_download() {
    _aws_require_cli || return 1

    local s3_path="$1"
    local local_path="$2"

    [[ -z "$s3_path" ]] && {
        printf '{"success":false,"error":"S3 path required"}'
        return 1
    }

    [[ -z "$local_path" ]] && {
        printf '{"success":false,"error":"Local path required"}'
        return 1
    }

    local result
    result=$(aws s3 cp "$s3_path" "$local_path" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s"}' "$escaped_error"
        return 1
    fi

    printf '{"success":true,"data":{"source":"%s","destination":"%s"}}' "$s3_path" "$local_path"
}

# Copy file to/from S3 (legacy alias)
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

    local result
    result=$(aws s3 cp "$source" "$dest" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s","source":"%s","destination":"%s"}' "$escaped_error" "$source" "$dest"
        return 1
    fi

    printf '{"success":true,"data":{"source":"%s","destination":"%s"}}' "$source" "$dest"
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

    local result
    result=$(aws s3 sync "${cmd_args[@]}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s"}' "$escaped_error"
        return 1
    fi

    printf '{"success":true,"data":{"source":"%s","destination":"%s","delete":%s}}' \
        "$source" "$dest" "$([[ "$delete_flag" == "--delete" ]] && echo "true" || echo "false")"
}

# =============================================================================
# EC2 HELPERS
# =============================================================================

# List EC2 instances
# Usage: aws_ec2_list [state]
# Returns: JSON array of instance info
# Example: aws_ec2_list
#   {"success":true,"data":[{"id":"i-123","type":"t2.micro","state":"running","name":"MyServer"}]}
# Example: aws_ec2_list running
#   {"success":true,"data":[...],"filter":"running"}
aws_ec2_list() {
    _aws_require_cli || return 1

    local state="$1"
    local filter_args=()

    [[ -n "$state" ]] && filter_args=(--filters "Name=instance-state-name,Values=$state")

    local result
    result=$(aws ec2 describe-instances "${filter_args[@]}" \
        --query 'Reservations[].Instances[].{id:InstanceId,type:InstanceType,state:State.Name,name:Tags[?Key==`Name`].Value|[0]}' \
        --output json 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s"}' "$escaped_error"
        return 1
    fi

    if [[ -n "$state" ]]; then
        printf '{"success":true,"data":%s,"filter":"%s"}' "$result" "$state"
    else
        printf '{"success":true,"data":%s}' "$result"
    fi
}

# Get EC2 instance status
# Usage: aws_ec2_status instance_id
# Returns: JSON with instance status details
# Example: aws_ec2_status i-1234567890abcdef0
#   {"success":true,"data":{"instance_id":"i-1234...","state":"running","instance_type":"t2.micro",...}}
aws_ec2_status() {
    _aws_require_cli || return 1

    local instance_id="$1"

    [[ -z "$instance_id" ]] && {
        printf '{"success":false,"error":"Instance ID required"}'
        return 1
    }

    local result
    result=$(aws ec2 describe-instances --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].{state:State.Name,instance_type:InstanceType,public_ip:PublicIpAddress,private_ip:PrivateIpAddress,launch_time:LaunchTime,name:Tags[?Key==`Name`].Value|[0]}' \
        --output json 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s"}' "$escaped_error"
        return 1
    fi

    # Extract fields from result
    local state instance_type public_ip private_ip launch_time name
    state=$(printf '%s' "$result" | grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    instance_type=$(printf '%s' "$result" | grep -o '"instance_type"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    public_ip=$(printf '%s' "$result" | grep -o '"public_ip"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    private_ip=$(printf '%s' "$result" | grep -o '"private_ip"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    launch_time=$(printf '%s' "$result" | grep -o '"launch_time"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    name=$(printf '%s' "$result" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

    # Handle null values
    [[ -z "$public_ip" ]] && public_ip="null" || public_ip="\"$public_ip\""
    [[ -z "$name" ]] && name="null" || name="\"$name\""
    [[ -z "$private_ip" ]] && private_ip="null" || private_ip="\"$private_ip\""
    [[ -z "$launch_time" ]] && launch_time="null" || launch_time="\"$launch_time\""

    printf '{"success":true,"data":{"instance_id":"%s","state":"%s","instance_type":"%s","public_ip":%s,"private_ip":%s,"launch_time":%s,"name":%s}}' \
        "$instance_id" "$state" "$instance_type" "$public_ip" "$private_ip" "$launch_time" "$name"
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

    local result
    result=$(aws ec2 start-instances --instance-ids "$instance_id" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s","instance_id":"%s"}' "$escaped_error" "$instance_id"
        return 1
    fi

    printf '{"success":true,"data":{"instance_id":"%s","action":"start"}}' "$instance_id"
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

    local result
    result=$(aws ec2 stop-instances --instance-ids "$instance_id" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s","instance_id":"%s"}' "$escaped_error" "$instance_id"
        return 1
    fi

    printf '{"success":true,"data":{"instance_id":"%s","action":"stop"}}' "$instance_id"
}

# =============================================================================
# LAMBDA HELPERS
# =============================================================================

# List Lambda functions
# Usage: aws_lambda_list
# Returns: JSON array of function info
# Example: aws_lambda_list
#   {"success":true,"data":[{"name":"my-func","runtime":"python3.9","memory":128,"timeout":30}]}
aws_lambda_list() {
    _aws_require_cli || return 1

    local result
    result=$(aws lambda list-functions \
        --query 'Functions[].{name:FunctionName,runtime:Runtime,memory:MemorySize,timeout:Timeout}' \
        --output json 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s"}' "$escaped_error"
        return 1
    fi

    printf '{"success":true,"data":%s}' "$result"
}

# Invoke Lambda function
# Usage: aws_lambda_invoke "function_name" [payload_json]
# Returns: USOP JSON with function response
# Example: aws_lambda_invoke my-function '{"key":"value"}'
#   {"success":true,"data":{"function":"my-function","status_code":200,"response":{...}}}
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

    local result
    result=$(aws lambda invoke \
        --function-name "$function_name" \
        --payload "$payload" \
        --cli-binary-format raw-in-base64-out \
        "$output_file" \
        --output json 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        rm -f "$output_file"
        local escaped_error
        escaped_error=$(_aws_json_escape "$result")
        printf '{"success":false,"error":"%s","function":"%s"}' "$escaped_error" "$function_name"
        return 1
    fi

    # Extract status code
    local status_code
    status_code=$(printf '%s' "$result" | grep -o '"StatusCode"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
    [[ -z "$status_code" ]] && status_code="0"

    # Read response from output file
    local response
    if [[ -f "$output_file" ]]; then
        response=$(cat "$output_file")
        rm -f "$output_file"
    else
        response="null"
    fi

    # Validate response is JSON, escape if not
    if [[ -n "$response" && ! "$response" =~ ^[[:space:]]*[\{\[] ]]; then
        local escaped_response
        escaped_response=$(_aws_json_escape "$response")
        response="\"$escaped_response\""
    fi

    printf '{"success":true,"data":{"function":"%s","status_code":%s,"response":%s}}' \
        "$function_name" "$status_code" "$response"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_EXT_AWS_EXPORTS=(
    # Availability & Identity
    aws_configured
    aws_available
    aws_account_id
    aws_region
    aws_whoami
    # S3
    aws_s3_list
    aws_s3_upload
    aws_s3_download
    aws_s3_cp
    aws_s3_sync
    # EC2
    aws_ec2_list
    aws_ec2_status
    aws_ec2_start
    aws_ec2_stop
    # Lambda
    aws_lambda_list
    aws_lambda_invoke
)

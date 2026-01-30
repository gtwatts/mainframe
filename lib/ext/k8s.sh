#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/ext/k8s.sh - Kubernetes CLI Wrapper Functions (OPTIONAL)
# =============================================================================
# Description: Convenience wrappers for kubectl CLI operations
# Requires: kubectl CLI (https://kubernetes.io/docs/tasks/tools/)
# Status: STUB - Framework for future expansion
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_EXT_K8S_LOADED:-}" ]] && return 0
readonly _MAINFRAME_EXT_K8S_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if kubectl is available
_k8s_has_cli() {
    command -v kubectl &>/dev/null
}

# Require kubectl CLI or return error JSON
_k8s_require_cli() {
    if ! _k8s_has_cli; then
        printf '{"success":false,"error":"kubectl not installed","hint":"Install from https://kubernetes.io/docs/tasks/tools/"}'
        return 1
    fi
    return 0
}

# Get namespace argument (uses default if not specified)
_k8s_ns_arg() {
    local ns="$1"
    [[ -n "$ns" ]] && echo "-n $ns" || echo ""
}

# =============================================================================
# AVAILABILITY & CONTEXT
# =============================================================================

# Check if kubectl is available and can connect to cluster
# Usage: k8s_available
# Returns: 0 if kubectl is installed and cluster is accessible, 1 otherwise
# @idempotent
k8s_available() {
    _k8s_has_cli || return 1
    # Verify cluster connectivity
    kubectl cluster-info &>/dev/null
}

# Get current Kubernetes context
# Usage: k8s_context
# Returns: Current context name
# @idempotent
k8s_context() {
    _k8s_require_cli || return 1
    kubectl config current-context 2>/dev/null
}

# Get current or default namespace
# Usage: k8s_namespace
# Returns: Current namespace (default if not set)
# @idempotent
k8s_namespace() {
    _k8s_require_cli || return 1
    local ns
    ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
    echo "${ns:-default}"
}

# Get cluster info as JSON (USOP format)
# Usage: k8s_whoami
# Returns: JSON with context, namespace, and cluster info
# @idempotent
k8s_whoami() {
    _k8s_require_cli || return 1

    local context namespace cluster server
    context=$(k8s_context) || {
        printf '{"success":false,"error":"No Kubernetes context configured","hint":"Run kubectl config use-context"}'
        return 1
    }

    namespace=$(k8s_namespace)
    cluster=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2>/dev/null)
    server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)

    printf '{"success":true,"data":{"context":"%s","namespace":"%s","cluster":"%s","server":"%s"}}' \
        "$context" "$namespace" "$cluster" "$server"
}

# List available contexts
# Usage: k8s_contexts
# Returns: JSON array of context names
k8s_contexts() {
    _k8s_require_cli || return 1

    local contexts
    contexts=$(kubectl config get-contexts -o name 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list contexts"}'
        return 1
    }

    if [[ -z "$contexts" ]]; then
        printf '{"success":true,"data":[]}'
        return 0
    fi

    # Convert to JSON array
    local json_array="["
    local first=true
    while IFS= read -r ctx; do
        $first || json_array+=","
        first=false
        json_array+="\"$ctx\""
    done <<< "$contexts"
    json_array+="]"

    printf '{"success":true,"data":%s}' "$json_array"
}

# =============================================================================
# POD HELPERS
# =============================================================================

# List pods
# Usage: k8s_pods [namespace] [label_selector]
# Returns: JSON array of pod info
k8s_pods() {
    _k8s_require_cli || return 1

    local namespace="${1:-}"
    local selector="${2:-}"
    local args=()

    [[ -n "$namespace" ]] && args+=(-n "$namespace")
    [[ -n "$selector" ]] && args+=(-l "$selector")

    local result
    result=$(kubectl get pods "${args[@]}" -o json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list pods"}'
        return 1
    }

    # Extract relevant fields
    local pods
    pods=$(echo "$result" | kubectl neat 2>/dev/null || echo "$result")

    printf '{"success":true,"data":%s}' "$pods"
}

# Get pod logs
# Usage: k8s_pod_logs "pod_name" [namespace] [container] [lines]
# Returns: USOP JSON with log output
k8s_pod_logs() {
    _k8s_require_cli || return 1

    local pod_name="$1"
    local namespace="${2:-}"
    local container="${3:-}"
    local lines="${4:-100}"

    [[ -z "$pod_name" ]] && {
        printf '{"success":false,"error":"Pod name required"}'
        return 1
    }

    local args=("$pod_name")
    [[ -n "$namespace" ]] && args+=(-n "$namespace")
    [[ -n "$container" ]] && args+=(-c "$container")
    args+=(--tail="$lines")

    local logs
    logs=$(kubectl logs "${args[@]}" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to get pod logs","pod":"%s"}' "$pod_name"
        return 1
    }

    # Escape logs for JSON (basic escaping)
    logs="${logs//\\/\\\\}"
    logs="${logs//\"/\\\"}"
    logs="${logs//$'\n'/\\n}"
    logs="${logs//$'\t'/\\t}"

    printf '{"success":true,"data":{"pod":"%s","lines":%d,"logs":"%s"}}' \
        "$pod_name" "$lines" "$logs"
}

# Execute command in pod
# Usage: k8s_pod_exec "pod_name" "command" [namespace] [container]
# Returns: USOP JSON with command output
k8s_pod_exec() {
    _k8s_require_cli || return 1

    local pod_name="$1"
    local cmd="$2"
    local namespace="${3:-}"
    local container="${4:-}"

    [[ -z "$pod_name" || -z "$cmd" ]] && {
        printf '{"success":false,"error":"Pod name and command required"}'
        return 1
    }

    local args=("$pod_name")
    [[ -n "$namespace" ]] && args+=(-n "$namespace")
    [[ -n "$container" ]] && args+=(-c "$container")
    args+=(-- sh -c "$cmd")

    local output
    output=$(kubectl exec "${args[@]}" 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to execute command","pod":"%s","command":"%s"}' "$pod_name" "$cmd"
        return 1
    }

    # Escape output for JSON
    output="${output//\\/\\\\}"
    output="${output//\"/\\\"}"
    output="${output//$'\n'/\\n}"

    printf '{"success":true,"data":{"pod":"%s","command":"%s","output":"%s"}}' \
        "$pod_name" "$cmd" "$output"
}

# =============================================================================
# DEPLOYMENT HELPERS
# =============================================================================

# List deployments
# Usage: k8s_deployments [namespace]
# Returns: JSON array of deployment info
k8s_deployments() {
    _k8s_require_cli || return 1

    local namespace="${1:-}"
    local args=()

    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    local result
    result=$(kubectl get deployments "${args[@]}" -o json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list deployments"}'
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# Scale deployment
# Usage: k8s_scale "deployment_name" "replicas" [namespace]
# Returns: USOP JSON result
k8s_scale() {
    _k8s_require_cli || return 1

    local deployment="$1"
    local replicas="$2"
    local namespace="${3:-}"

    [[ -z "$deployment" || -z "$replicas" ]] && {
        printf '{"success":false,"error":"Deployment name and replicas required"}'
        return 1
    }

    # Validate replicas is a number
    [[ ! "$replicas" =~ ^[0-9]+$ ]] && {
        printf '{"success":false,"error":"Replicas must be a non-negative integer"}'
        return 1
    }

    local args=(deployment "$deployment" --replicas="$replicas")
    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    if kubectl scale "${args[@]}" &>/dev/null; then
        printf '{"success":true,"data":{"deployment":"%s","replicas":%d,"namespace":"%s"}}' \
            "$deployment" "$replicas" "${namespace:-default}"
    else
        printf '{"success":false,"error":"Failed to scale deployment","deployment":"%s"}' "$deployment"
        return 1
    fi
}

# Restart deployment (rollout restart)
# Usage: k8s_restart "deployment_name" [namespace]
# Returns: USOP JSON result
k8s_restart() {
    _k8s_require_cli || return 1

    local deployment="$1"
    local namespace="${2:-}"

    [[ -z "$deployment" ]] && {
        printf '{"success":false,"error":"Deployment name required"}'
        return 1
    }

    local args=(deployment "$deployment")
    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    if kubectl rollout restart "${args[@]}" &>/dev/null; then
        printf '{"success":true,"data":{"deployment":"%s","action":"restart","namespace":"%s"}}' \
            "$deployment" "${namespace:-default}"
    else
        printf '{"success":false,"error":"Failed to restart deployment","deployment":"%s"}' "$deployment"
        return 1
    fi
}

# =============================================================================
# SERVICE HELPERS
# =============================================================================

# List services
# Usage: k8s_services [namespace]
# Returns: JSON array of service info
k8s_services() {
    _k8s_require_cli || return 1

    local namespace="${1:-}"
    local args=()

    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    local result
    result=$(kubectl get services "${args[@]}" -o json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list services"}'
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# Get service endpoints
# Usage: k8s_service_endpoints "service_name" [namespace]
# Returns: USOP JSON with endpoint info
k8s_service_endpoints() {
    _k8s_require_cli || return 1

    local service_name="$1"
    local namespace="${2:-}"

    [[ -z "$service_name" ]] && {
        printf '{"success":false,"error":"Service name required"}'
        return 1
    }

    local args=("endpoints" "$service_name")
    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    local result
    result=$(kubectl get "${args[@]}" -o json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to get service endpoints","service":"%s"}' "$service_name"
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# =============================================================================
# CONFIGMAP & SECRET HELPERS (STUB)
# =============================================================================

# List configmaps
# Usage: k8s_configmaps [namespace]
# Returns: JSON array of configmap names
k8s_configmaps() {
    _k8s_require_cli || return 1

    local namespace="${1:-}"
    local args=()

    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    local result
    result=$(kubectl get configmaps "${args[@]}" -o json 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list configmaps"}'
        return 1
    }

    printf '{"success":true,"data":%s}' "$result"
}

# List secrets (names only, not values)
# Usage: k8s_secrets [namespace]
# Returns: JSON array of secret names
k8s_secrets() {
    _k8s_require_cli || return 1

    local namespace="${1:-}"
    local args=()

    [[ -n "$namespace" ]] && args+=(-n "$namespace")

    local names
    names=$(kubectl get secrets "${args[@]}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) || {
        printf '{"success":false,"error":"Failed to list secrets"}'
        return 1
    }

    if [[ -z "$names" ]]; then
        printf '{"success":true,"data":[]}'
        return 0
    fi

    # Convert space-separated to JSON array
    local json_array="["
    local first=true
    for name in $names; do
        $first || json_array+=","
        first=false
        json_array+="\"$name\""
    done
    json_array+="]"

    printf '{"success":true,"data":%s}' "$json_array"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_EXT_K8S_EXPORTS=(
    # Availability & Context
    k8s_available
    k8s_context
    k8s_namespace
    k8s_whoami
    k8s_contexts
    # Pods
    k8s_pods
    k8s_pod_logs
    k8s_pod_exec
    # Deployments
    k8s_deployments
    k8s_scale
    k8s_restart
    # Services
    k8s_services
    k8s_service_endpoints
    # ConfigMaps & Secrets
    k8s_configmaps
    k8s_secrets
)

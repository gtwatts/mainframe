#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/k8s.sh - Kubernetes Helper Functions
# =============================================================================
# Description: Kubernetes operations via kubectl CLI with sane defaults
# Requires: kubectl CLI (not Kubernetes SDK/API)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_K8S_LOADED:-}" ]] && return 0
readonly _MAINFRAME_K8S_LOADED=1

# =============================================================================
# GLOBAL STATE
# =============================================================================

# Track port-forward PIDs for cleanup
declare -ga _K8S_PORT_FORWARD_PIDS=()

# Current namespace override (use this instead of -n flag everywhere)
declare -g _K8S_NAMESPACE=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if kubectl CLI is available
_k8s_has_cli() {
    command -v kubectl &>/dev/null
}

# Build namespace flag if set
_k8s_ns_flag() {
    if [[ -n "${_K8S_NAMESPACE:-}" ]]; then
        printf '%s' "-n ${_K8S_NAMESPACE}"
    fi
}

# Run kubectl with namespace if set
_k8s_cmd() {
    local ns_flag
    ns_flag=$(_k8s_ns_flag)
    if [[ -n "$ns_flag" ]]; then
        kubectl $ns_flag "$@"
    else
        kubectl "$@"
    fi
}

# =============================================================================
# CONTEXT/NAMESPACE OPERATIONS
# =============================================================================

# Switch to a different kubectl context
# Usage: k8s::context "prod-cluster"
# Returns: 0 on success, 1 on failure
k8s::context() {
    local context="$1"
    [[ -z "$context" ]] && return 1
    _k8s_has_cli || return 1

    kubectl config use-context "$context" &>/dev/null
}

# Get current kubectl context
# Usage: k8s::current_context
# Returns: Current context name
k8s::current_context() {
    _k8s_has_cli || return 1
    kubectl config current-context 2>/dev/null
}

# List all available contexts
# Usage: k8s::contexts
# Returns: Newline-separated list of context names
k8s::contexts() {
    _k8s_has_cli || return 1
    kubectl config get-contexts -o name 2>/dev/null
}

# Set namespace for subsequent operations (module-level state)
# Usage: k8s::namespace "my-app"
# Returns: 0 on success
k8s::namespace() {
    local namespace="$1"
    [[ -z "$namespace" ]] && return 1
    _K8S_NAMESPACE="$namespace"
}

# Clear namespace override (use default from context)
# Usage: k8s::namespace_clear
k8s::namespace_clear() {
    _K8S_NAMESPACE=""
}

# Get current namespace (from module state or context default)
# Usage: k8s::current_namespace
# Returns: Current namespace name
k8s::current_namespace() {
    _k8s_has_cli || return 1
    
    # Return module-level override if set
    if [[ -n "${_K8S_NAMESPACE:-}" ]]; then
        printf '%s\n' "$_K8S_NAMESPACE"
        return 0
    fi
    
    # Get from current context
    kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || printf 'default'
}

# List all namespaces
# Usage: k8s::namespaces
# Returns: Newline-separated list of namespace names
k8s::namespaces() {
    _k8s_has_cli || return 1
    kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n'
}

# =============================================================================
# POD OPERATIONS
# =============================================================================

# Wait for a resource to be ready
# Usage: k8s::wait_ready "deployment/my-app" [--timeout 300]
# Arguments:
#   resource - Resource to wait for (e.g., deployment/my-app, pod/my-pod)
#   --timeout - Timeout in seconds (default: 300)
# Returns: 0 when ready, 1 on timeout
k8s::wait_ready() {
    local resource="$1"
    shift
    local timeout=300
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd wait --for=condition=ready "$resource" --timeout="${timeout}s" 2>/dev/null
}

# List pods matching a label selector
# Usage: k8s::pods "app=my-app"
# Arguments:
#   selector - Label selector (optional, lists all if not provided)
# Returns: Newline-separated list of pod names
k8s::pods() {
    local selector="${1:-}"
    _k8s_has_cli || return 1
    
    if [[ -n "$selector" ]]; then
        _k8s_cmd get pods -l "$selector" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n'
    else
        _k8s_cmd get pods -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n'
    fi
}

# Get pod status
# Usage: k8s::pod_status "my-pod"
# Returns: Status string (Running, Pending, Succeeded, Failed, Unknown)
k8s::pod_status() {
    local pod="$1"
    [[ -z "$pod" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Check if pod is running
# Usage: k8s::pod_running "my-pod"
# Returns: 0 if running, 1 if not
k8s::pod_running() {
    local pod="$1"
    [[ -z "$pod" ]] && return 1
    
    local status
    status=$(k8s::pod_status "$pod") || return 1
    [[ "$status" == "Running" ]]
}

# Get container logs from a pod
# Usage: k8s::logs "my-pod" [--all-containers] [--follow] [--tail N] [--container NAME]
# Arguments:
#   pod - Pod name
#   --all-containers - Get logs from all containers
#   --follow - Follow log output
#   --tail N - Number of lines from end (default: all)
#   --container NAME - Specific container name
# Returns: Log output
k8s::logs() {
    local pod="$1"
    shift
    local all_containers=false
    local follow=false
    local tail=""
    local container=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all-containers)
                all_containers=true
                shift
                ;;
            --follow|-f)
                follow=true
                shift
                ;;
            --tail)
                tail="$2"
                shift 2
                ;;
            --container|-c)
                container="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$pod" ]] && return 1
    _k8s_has_cli || return 1
    
    local cmd_args=()
    $all_containers && cmd_args+=(--all-containers)
    $follow && cmd_args+=(-f)
    [[ -n "$tail" ]] && cmd_args+=(--tail "$tail")
    [[ -n "$container" ]] && cmd_args+=(-c "$container")
    
    _k8s_cmd logs "$pod" "${cmd_args[@]}" 2>&1
}

# Execute command in a pod
# Usage: k8s::exec "my-pod" -- bash
# Arguments:
#   pod - Pod name
#   --container NAME - Specific container (optional)
#   -- command args - Command to execute (after --)
# Returns: Exit code of executed command
k8s::exec() {
    local pod="$1"
    shift
    local container=""
    local cmd_start=false
    local cmd_args=()
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        if $cmd_start; then
            cmd_args+=("$1")
            shift
            continue
        fi
        case "$1" in
            --container|-c)
                container="$2"
                shift 2
                ;;
            --)
                cmd_start=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$pod" ]] && return 1
    [[ ${#cmd_args[@]} -eq 0 ]] && return 1
    _k8s_has_cli || return 1
    
    local kubectl_args=()
    [[ -n "$container" ]] && kubectl_args+=(-c "$container")
    
    _k8s_cmd exec "$pod" "${kubectl_args[@]}" -- "${cmd_args[@]}"
}

# Execute interactive command in a pod
# Usage: k8s::exec_it "my-pod" -- bash
# Same as k8s::exec but with -it flags
k8s::exec_it() {
    local pod="$1"
    shift
    local container=""
    local cmd_start=false
    local cmd_args=()
    
    while [[ $# -gt 0 ]]; do
        if $cmd_start; then
            cmd_args+=("$1")
            shift
            continue
        fi
        case "$1" in
            --container|-c)
                container="$2"
                shift 2
                ;;
            --)
                cmd_start=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$pod" ]] && return 1
    [[ ${#cmd_args[@]} -eq 0 ]] && return 1
    _k8s_has_cli || return 1
    
    local kubectl_args=(-it)
    [[ -n "$container" ]] && kubectl_args+=(-c "$container")
    
    _k8s_cmd exec "${kubectl_args[@]}" "$pod" -- "${cmd_args[@]}"
}

# =============================================================================
# PORT FORWARDING
# =============================================================================

# Start port forwarding to a service/pod
# Usage: k8s::port_forward "svc/my-service" 8080:80
# Arguments:
#   resource - Resource to forward to (e.g., svc/my-service, pod/my-pod)
#   ports - Port mapping (local:remote)
# Returns: 0 on success, stores PID for cleanup
k8s::port_forward() {
    local resource="$1"
    local ports="$2"
    
    [[ -z "$resource" || -z "$ports" ]] && return 1
    _k8s_has_cli || return 1
    
    # Start port-forward in background
    local ns_flag
    ns_flag=$(_k8s_ns_flag)
    if [[ -n "$ns_flag" ]]; then
        kubectl $ns_flag port-forward "$resource" "$ports" &>/dev/null &
    else
        kubectl port-forward "$resource" "$ports" &>/dev/null &
    fi
    
    local pid=$!
    _K8S_PORT_FORWARD_PIDS+=("$pid")
    
    # Brief pause to ensure it started
    sleep 0.5
    
    # Verify it's running
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Stop all port forwards started by this module
# Usage: k8s::port_forward_stop
# Returns: 0 on success
k8s::port_forward_stop() {
    local pid
    for pid in "${_K8S_PORT_FORWARD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    _K8S_PORT_FORWARD_PIDS=()
}

# Get list of active port-forward PIDs
# Usage: k8s::port_forward_pids
# Returns: Space-separated list of PIDs
k8s::port_forward_pids() {
    printf '%s\n' "${_K8S_PORT_FORWARD_PIDS[*]}"
}

# =============================================================================
# SECRETS/CONFIGMAPS
# =============================================================================

# Get a value from a secret
# Usage: k8s::secret_get "my-secret" "key"
# Arguments:
#   secret - Secret name
#   key - Key within the secret
# Returns: Decoded secret value
k8s::secret_get() {
    local secret="$1"
    local key="$2"
    
    [[ -z "$secret" || -z "$key" ]] && return 1
    _k8s_has_cli || return 1
    
    local encoded
    encoded=$(_k8s_cmd get secret "$secret" -o jsonpath="{.data.${key}}" 2>/dev/null) || return 1
    
    if [[ -n "$encoded" ]]; then
        printf '%s' "$encoded" | base64 -d
    fi
}

# Set/update a secret value
# Usage: k8s::secret_set "my-secret" "key" "value"
# Arguments:
#   secret - Secret name
#   key - Key to set
#   value - Value to set
# Returns: 0 on success
k8s::secret_set() {
    local secret="$1"
    local key="$2"
    local value="$3"
    
    [[ -z "$secret" || -z "$key" ]] && return 1
    _k8s_has_cli || return 1
    
    # Check if secret exists
    if _k8s_cmd get secret "$secret" &>/dev/null; then
        # Patch existing secret
        local encoded
        encoded=$(printf '%s' "$value" | base64 -w0)
        _k8s_cmd patch secret "$secret" -p "{\"data\":{\"${key}\":\"${encoded}\"}}" &>/dev/null
    else
        # Create new secret
        _k8s_cmd create secret generic "$secret" --from-literal="${key}=${value}" &>/dev/null
    fi
}

# Delete a secret
# Usage: k8s::secret_delete "my-secret"
# Returns: 0 on success
k8s::secret_delete() {
    local secret="$1"
    [[ -z "$secret" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd delete secret "$secret" &>/dev/null
}

# List secrets
# Usage: k8s::secrets
# Returns: Newline-separated list of secret names
k8s::secrets() {
    _k8s_has_cli || return 1
    _k8s_cmd get secrets -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n'
}

# Get a value from a configmap
# Usage: k8s::configmap_get "my-config" "key"
# Arguments:
#   configmap - ConfigMap name
#   key - Key within the configmap
# Returns: ConfigMap value
k8s::configmap_get() {
    local configmap="$1"
    local key="$2"
    
    [[ -z "$configmap" || -z "$key" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get configmap "$configmap" -o jsonpath="{.data.${key}}" 2>/dev/null
}

# Set/update a configmap value
# Usage: k8s::configmap_set "my-config" "key" "value"
# Arguments:
#   configmap - ConfigMap name
#   key - Key to set
#   value - Value to set
# Returns: 0 on success
k8s::configmap_set() {
    local configmap="$1"
    local key="$2"
    local value="$3"
    
    [[ -z "$configmap" || -z "$key" ]] && return 1
    _k8s_has_cli || return 1
    
    # Check if configmap exists
    if _k8s_cmd get configmap "$configmap" &>/dev/null; then
        # Patch existing configmap
        _k8s_cmd patch configmap "$configmap" -p "{\"data\":{\"${key}\":\"${value}\"}}" &>/dev/null
    else
        # Create new configmap
        _k8s_cmd create configmap "$configmap" --from-literal="${key}=${value}" &>/dev/null
    fi
}

# Delete a configmap
# Usage: k8s::configmap_delete "my-config"
# Returns: 0 on success
k8s::configmap_delete() {
    local configmap="$1"
    [[ -z "$configmap" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd delete configmap "$configmap" &>/dev/null
}

# List configmaps
# Usage: k8s::configmaps
# Returns: Newline-separated list of configmap names
k8s::configmaps() {
    _k8s_has_cli || return 1
    _k8s_cmd get configmaps -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n'
}

# =============================================================================
# ROLLOUT MANAGEMENT
# =============================================================================

# Get rollout status
# Usage: k8s::rollout_status "deployment/my-app"
# Arguments:
#   resource - Deployment/StatefulSet/DaemonSet to check
# Returns: Rollout status output
k8s::rollout_status() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd rollout status "$resource" 2>&1
}

# Restart a deployment (triggers rolling update)
# Usage: k8s::rollout_restart "deployment/my-app"
# Arguments:
#   resource - Deployment/StatefulSet/DaemonSet to restart
# Returns: 0 on success
k8s::rollout_restart() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd rollout restart "$resource" &>/dev/null
}

# Undo last rollout
# Usage: k8s::rollout_undo "deployment/my-app" [--to-revision N]
# Arguments:
#   resource - Deployment/StatefulSet/DaemonSet to rollback
#   --to-revision N - Specific revision to rollback to
# Returns: 0 on success
k8s::rollout_undo() {
    local resource="$1"
    shift
    local revision=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to-revision)
                revision="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    if [[ -n "$revision" ]]; then
        _k8s_cmd rollout undo "$resource" --to-revision="$revision" &>/dev/null
    else
        _k8s_cmd rollout undo "$resource" &>/dev/null
    fi
}

# Pause a rollout
# Usage: k8s::rollout_pause "deployment/my-app"
# Returns: 0 on success
k8s::rollout_pause() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd rollout pause "$resource" &>/dev/null
}

# Resume a paused rollout
# Usage: k8s::rollout_resume "deployment/my-app"
# Returns: 0 on success
k8s::rollout_resume() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd rollout resume "$resource" &>/dev/null
}

# Get rollout history
# Usage: k8s::rollout_history "deployment/my-app"
# Returns: Rollout history
k8s::rollout_history() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd rollout history "$resource" 2>&1
}

# =============================================================================
# RESOURCE QUERIES
# =============================================================================

# Get container image for a deployment/pod
# Usage: k8s::get_image "deployment/my-app" [--container NAME]
# Arguments:
#   resource - Resource to query
#   --container NAME - Specific container (default: first)
# Returns: Image name:tag
k8s::get_image() {
    local resource="$1"
    shift
    local container=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --container|-c)
                container="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    local jsonpath
    if [[ -n "$container" ]]; then
        # Get specific container image
        if [[ "$resource" == pod/* ]]; then
            jsonpath="{.spec.containers[?(@.name==\"${container}\")].image}"
        else
            jsonpath="{.spec.template.spec.containers[?(@.name==\"${container}\")].image}"
        fi
    else
        # Get first container image
        if [[ "$resource" == pod/* ]]; then
            jsonpath='{.spec.containers[0].image}'
        else
            jsonpath='{.spec.template.spec.containers[0].image}'
        fi
    fi
    
    _k8s_cmd get "$resource" -o jsonpath="$jsonpath" 2>/dev/null
}

# Get replica count for a deployment
# Usage: k8s::get_replicas "deployment/my-app"
# Returns: Number of replicas
k8s::get_replicas() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get "$resource" -o jsonpath='{.spec.replicas}' 2>/dev/null
}

# Get ready replica count for a deployment
# Usage: k8s::get_ready_replicas "deployment/my-app"
# Returns: Number of ready replicas
k8s::get_ready_replicas() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get "$resource" -o jsonpath='{.status.readyReplicas}' 2>/dev/null
}

# Scale a deployment
# Usage: k8s::scale "deployment/my-app" 3
# Arguments:
#   resource - Deployment to scale
#   replicas - Target replica count
# Returns: 0 on success
k8s::scale() {
    local resource="$1"
    local replicas="$2"
    
    [[ -z "$resource" || -z "$replicas" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd scale "$resource" --replicas="$replicas" &>/dev/null
}

# Get events for a resource
# Usage: k8s::get_events [--for "pod/my-pod"] [--limit N]
# Arguments:
#   --for - Resource to get events for (optional)
#   --limit N - Maximum number of events
# Returns: Event list
k8s::get_events() {
    local resource=""
    local limit=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --for)
                resource="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    _k8s_has_cli || return 1
    
    local cmd_args=()
    if [[ -n "$resource" ]]; then
        cmd_args+=(--for "$resource")
    fi
    
    local output
    output=$(_k8s_cmd get events "${cmd_args[@]}" --sort-by='.lastTimestamp' 2>/dev/null)
    
    if [[ -n "$limit" && -n "$output" ]]; then
        printf '%s\n' "$output" | head -n "$((limit + 1))"
    else
        printf '%s\n' "$output"
    fi
}

# Get resource as JSON
# Usage: k8s::get_json "deployment/my-app"
# Returns: JSON representation of resource
k8s::get_json() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get "$resource" -o json 2>/dev/null
}

# Get resource as YAML
# Usage: k8s::get_yaml "deployment/my-app"
# Returns: YAML representation of resource
k8s::get_yaml() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get "$resource" -o yaml 2>/dev/null
}

# =============================================================================
# RESOURCE MANAGEMENT
# =============================================================================

# Apply a manifest file or stdin
# Usage: k8s::apply "manifest.yaml" or echo "$yaml" | k8s::apply -
# Returns: 0 on success
k8s::apply() {
    local file="$1"
    [[ -z "$file" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd apply -f "$file" &>/dev/null
}

# Delete a resource
# Usage: k8s::delete "deployment/my-app"
# Returns: 0 on success
k8s::delete() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd delete "$resource" &>/dev/null
}

# Check if a resource exists
# Usage: k8s::exists "deployment/my-app"
# Returns: 0 if exists, 1 if not
k8s::exists() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get "$resource" &>/dev/null
}

# =============================================================================
# SERVICE OPERATIONS
# =============================================================================

# Get service cluster IP
# Usage: k8s::service_ip "my-service"
# Returns: Cluster IP address
k8s::service_ip() {
    local service="$1"
    [[ -z "$service" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get service "$service" -o jsonpath='{.spec.clusterIP}' 2>/dev/null
}

# Get service external IP (for LoadBalancer type)
# Usage: k8s::service_external_ip "my-service"
# Returns: External IP address or "pending"
k8s::service_external_ip() {
    local service="$1"
    [[ -z "$service" ]] && return 1
    _k8s_has_cli || return 1
    
    local ip
    ip=$(_k8s_cmd get service "$service" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    
    if [[ -z "$ip" ]]; then
        # Try hostname instead (AWS ELB)
        ip=$(_k8s_cmd get service "$service" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    fi
    
    if [[ -z "$ip" ]]; then
        printf 'pending'
    else
        printf '%s' "$ip"
    fi
}

# Get service ports
# Usage: k8s::service_ports "my-service"
# Returns: Port mappings (port:targetPort)
k8s::service_ports() {
    local service="$1"
    [[ -z "$service" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd get service "$service" -o jsonpath='{range .spec.ports[*]}{.port}:{.targetPort} {end}' 2>/dev/null
}

# =============================================================================
# LABELS & ANNOTATIONS
# =============================================================================

# Add/update label on a resource
# Usage: k8s::label "deployment/my-app" "env=production"
# Returns: 0 on success
k8s::label() {
    local resource="$1"
    local label="$2"
    
    [[ -z "$resource" || -z "$label" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd label "$resource" "$label" --overwrite &>/dev/null
}

# Remove label from a resource
# Usage: k8s::label_remove "deployment/my-app" "env"
# Returns: 0 on success
k8s::label_remove() {
    local resource="$1"
    local label="$2"
    
    [[ -z "$resource" || -z "$label" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd label "$resource" "${label}-" &>/dev/null
}

# Add/update annotation on a resource
# Usage: k8s::annotate "deployment/my-app" "description=My App"
# Returns: 0 on success
k8s::annotate() {
    local resource="$1"
    local annotation="$2"
    
    [[ -z "$resource" || -z "$annotation" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd annotate "$resource" "$annotation" --overwrite &>/dev/null
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if kubectl is configured and can connect
# Usage: k8s::ready
# Returns: 0 if kubectl can connect to cluster
k8s::ready() {
    _k8s_has_cli || return 1
    kubectl cluster-info &>/dev/null
}

# Get kubectl version
# Usage: k8s::version
# Returns: kubectl client version
k8s::version() {
    _k8s_has_cli || return 1
    kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4
}

# Get cluster version
# Usage: k8s::cluster_version
# Returns: Kubernetes server version
k8s::cluster_version() {
    _k8s_has_cli || return 1
    kubectl version -o json 2>/dev/null | grep -A1 '"serverVersion"' | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4
}

# Describe a resource (detailed info)
# Usage: k8s::describe "deployment/my-app"
# Returns: Detailed resource description
k8s::describe() {
    local resource="$1"
    [[ -z "$resource" ]] && return 1
    _k8s_has_cli || return 1
    
    _k8s_cmd describe "$resource" 2>&1
}

# Run cleanup on exit (port forwards)
# Usage: k8s::cleanup_on_exit
# Note: Call this at script start to auto-cleanup port forwards
k8s::cleanup_on_exit() {
    trap 'k8s::port_forward_stop' EXIT INT TERM
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_K8S_EXPORTS=(
    # Context/Namespace
    k8s::context
    k8s::current_context
    k8s::contexts
    k8s::namespace
    k8s::namespace_clear
    k8s::current_namespace
    k8s::namespaces
    # Pod operations
    k8s::wait_ready
    k8s::pods
    k8s::pod_status
    k8s::pod_running
    k8s::logs
    k8s::exec
    k8s::exec_it
    # Port forwarding
    k8s::port_forward
    k8s::port_forward_stop
    k8s::port_forward_pids
    # Secrets/ConfigMaps
    k8s::secret_get
    k8s::secret_set
    k8s::secret_delete
    k8s::secrets
    k8s::configmap_get
    k8s::configmap_set
    k8s::configmap_delete
    k8s::configmaps
    # Rollout management
    k8s::rollout_status
    k8s::rollout_restart
    k8s::rollout_undo
    k8s::rollout_pause
    k8s::rollout_resume
    k8s::rollout_history
    # Resource queries
    k8s::get_image
    k8s::get_replicas
    k8s::get_ready_replicas
    k8s::scale
    k8s::get_events
    k8s::get_json
    k8s::get_yaml
    # Resource management
    k8s::apply
    k8s::delete
    k8s::exists
    # Service operations
    k8s::service_ip
    k8s::service_external_ip
    k8s::service_ports
    # Labels & Annotations
    k8s::label
    k8s::label_remove
    k8s::annotate
    # Utility
    k8s::ready
    k8s::version
    k8s::cluster_version
    k8s::describe
    k8s::cleanup_on_exit
)

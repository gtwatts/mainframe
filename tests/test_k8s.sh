#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/tests/test_k8s.sh - Kubernetes Library Test Suite
# =============================================================================
# Description: Tests for k8s.sh functions
# Usage: ./tests/test_k8s.sh
# Note: Tests use mocked kubectl when real cluster not available
# =============================================================================

set -euo pipefail

# Get script directory and source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the k8s library
source "$PROJECT_ROOT/lib/k8s.sh"

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass() {
    ((TESTS_PASSED++)) || true
    ((TESTS_RUN++)) || true
    printf "${GREEN}[PASS]${NC} %s\n" "$1"
}

fail() {
    ((TESTS_FAILED++)) || true
    ((TESTS_RUN++)) || true
    printf "${RED}[FAIL]${NC} %s - %s\n" "$1" "$2"
}

skip() {
    ((TESTS_SKIPPED++)) || true
    printf "${YELLOW}[SKIP]${NC} %s - %s\n" "$1" "$2"
}

info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected '$expected', got '$actual'"
    fi
}

assert_true() {
    local test_name="$1"
    shift

    if "$@"; then
        pass "$test_name"
    else
        fail "$test_name" "condition was false"
    fi
}

assert_false() {
    local test_name="$1"
    shift

    if ! "$@"; then
        pass "$test_name"
    else
        fail "$test_name" "condition was true"
    fi
}

assert_contains() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$actual" == *"$expected"* ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected to contain '$expected', got '$actual'"
    fi
}

assert_not_empty() {
    local actual="$1"
    local test_name="$2"
    
    if [[ -n "$actual" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected non-empty value"
    fi
}

# =============================================================================
# MOCK KUBECTL SETUP
# =============================================================================

MOCK_DIR=""
ORIGINAL_PATH="$PATH"

setup_mock_kubectl() {
    MOCK_DIR=$(mktemp -d)
    
    # Create mock kubectl script
    cat > "$MOCK_DIR/kubectl" << 'MOCK_KUBECTL'
#!/bin/bash
# Mock kubectl for testing

# Global mock responses
case "$*" in
    "config current-context")
        echo "test-cluster"
        ;;
    "config get-contexts -o name")
        echo -e "test-cluster\nprod-cluster\ndev-cluster"
        ;;
    "config use-context"*)
        exit 0
        ;;
    "config view --minify --output jsonpath={..namespace}")
        echo "default"
        ;;
    "get namespaces -o jsonpath={.items[*].metadata.name}")
        echo "default kube-system my-namespace"
        ;;
    *"get pods"*"-l app=my-app"*)
        echo "my-app-pod-1 my-app-pod-2"
        ;;
    *"get pods -o jsonpath"*)
        echo "pod-1 pod-2 pod-3"
        ;;
    *"get pod my-pod -o jsonpath={.status.phase}")
        echo "Running"
        ;;
    *"get pod stopped-pod -o jsonpath={.status.phase}")
        echo "Succeeded"
        ;;
    *"wait --for=condition=ready"*)
        exit 0
        ;;
    *"logs my-pod"*)
        echo "2024-01-01 Log line 1"
        echo "2024-01-01 Log line 2"
        ;;
    *"exec my-pod -- echo test")
        echo "test"
        ;;
    *"get secret my-secret -o jsonpath={.data.password}")
        # base64 encoded "secretvalue"
        echo "c2VjcmV0dmFsdWU="
        ;;
    *"get secret my-secret")
        exit 0
        ;;
    *"patch secret"*)
        exit 0
        ;;
    *"create secret generic"*)
        exit 0
        ;;
    *"delete secret"*)
        exit 0
        ;;
    *"get secrets -o jsonpath"*)
        echo "secret-1 secret-2"
        ;;
    *"get configmap my-config -o jsonpath={.data.key}")
        echo "configvalue"
        ;;
    *"get configmap my-config")
        exit 0
        ;;
    *"patch configmap"*)
        exit 0
        ;;
    *"create configmap"*)
        exit 0
        ;;
    *"delete configmap"*)
        exit 0
        ;;
    *"get configmaps -o jsonpath"*)
        echo "config-1 config-2"
        ;;
    *"rollout status"*)
        echo "deployment \"my-app\" successfully rolled out"
        ;;
    *"rollout restart"*)
        exit 0
        ;;
    *"rollout undo"*)
        exit 0
        ;;
    *"rollout pause"*)
        exit 0
        ;;
    *"rollout resume"*)
        exit 0
        ;;
    *"rollout history"*)
        echo "deployment.apps/my-app"
        echo "REVISION  CHANGE-CAUSE"
        echo "1         Initial deployment"
        echo "2         Updated image"
        ;;
    *"get deployment/my-app -o jsonpath={.spec.template.spec.containers[0].image}")
        echo "my-app:v1.2.3"
        ;;
    *"get deployment/my-app -o jsonpath={.spec.replicas}")
        echo "3"
        ;;
    *"get deployment/my-app -o jsonpath={.status.readyReplicas}")
        echo "3"
        ;;
    *"scale"*"--replicas="*)
        exit 0
        ;;
    *"get events"*)
        echo "LAST SEEN   TYPE      REASON    OBJECT           MESSAGE"
        echo "5m          Normal    Pulled    pod/my-pod       Successfully pulled image"
        echo "5m          Normal    Created   pod/my-pod       Created container"
        ;;
    *"get deployment/my-app -o json")
        echo '{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"name":"my-app"}}'
        ;;
    *"get deployment/my-app -o yaml")
        echo "apiVersion: apps/v1"
        echo "kind: Deployment"
        echo "metadata:"
        echo "  name: my-app"
        ;;
    *"apply -f"*)
        exit 0
        ;;
    *"delete deployment/my-app")
        exit 0
        ;;
    *"get deployment/my-app"*)
        exit 0
        ;;
    *"get deployment/nonexistent"*)
        exit 1
        ;;
    *"get service my-service -o jsonpath={.spec.clusterIP}")
        echo "10.0.0.100"
        ;;
    *"get service my-service -o jsonpath={.status.loadBalancer.ingress[0].ip}")
        echo "203.0.113.50"
        ;;
    *"get service my-service -o jsonpath="*"range"*"port"*)
        echo "80:8080 443:8443 "
        ;;
    *"label"*"--overwrite")
        exit 0
        ;;
    *"label"*"-")
        exit 0
        ;;
    *"annotate"*"--overwrite")
        exit 0
        ;;
    "cluster-info")
        echo "Kubernetes control plane is running at https://127.0.0.1:6443"
        ;;
    "version --client -o json")
        echo '{"clientVersion":{"gitVersion":"v1.29.0"}}'
        ;;
    "version -o json")
        echo '{"serverVersion":{"gitVersion":"v1.29.0"}}'
        ;;
    *"describe deployment/my-app")
        echo "Name:                   my-app"
        echo "Namespace:              default"
        echo "Replicas:               3 desired | 3 updated | 3 total | 3 available"
        ;;
    *"port-forward"*)
        # Simulate background process
        sleep 60 &
        echo $!
        ;;
    *)
        # Default: succeed silently
        exit 0
        ;;
esac
MOCK_KUBECTL
    
    chmod +x "$MOCK_DIR/kubectl"
    
    # Prepend mock directory to PATH
    export PATH="$MOCK_DIR:$PATH"
}

teardown_mock_kubectl() {
    if [[ -n "$MOCK_DIR" && -d "$MOCK_DIR" ]]; then
        rm -rf "$MOCK_DIR"
    fi
    export PATH="$ORIGINAL_PATH"
}

# =============================================================================
# CHECK KUBECTL AVAILABILITY
# =============================================================================

KUBECTL_AVAILABLE=false
CLUSTER_AVAILABLE=false

if command -v kubectl &>/dev/null; then
    KUBECTL_AVAILABLE=true
    if kubectl cluster-info &>/dev/null 2>&1; then
        CLUSTER_AVAILABLE=true
        info "Kubernetes cluster is available - using real kubectl for tests"
    else
        info "kubectl found but no cluster - using mock kubectl"
    fi
else
    info "kubectl not found - using mock kubectl"
fi

# Set up mock kubectl for tests (unless real cluster available)
if ! $CLUSTER_AVAILABLE; then
    setup_mock_kubectl
fi

# =============================================================================
# CONTEXT/NAMESPACE TESTS
# =============================================================================

test_current_context() {
    local ctx
    ctx=$(k8s::current_context)
    assert_not_empty "$ctx" "k8s::current_context returns value"
}

test_contexts() {
    local contexts
    contexts=$(k8s::contexts)
    assert_not_empty "$contexts" "k8s::contexts returns list"
}

test_namespace_set_get() {
    k8s::namespace "test-namespace"
    local ns
    ns=$(k8s::current_namespace)
    assert_eq "test-namespace" "$ns" "k8s::namespace sets namespace"
    
    k8s::namespace_clear
    # After clear, should return context default
    ns=$(k8s::current_namespace)
    assert_not_empty "$ns" "k8s::namespace_clear resets to default"
}

# =============================================================================
# POD OPERATION TESTS
# =============================================================================

test_pods() {
    local pods
    pods=$(k8s::pods "app=my-app")
    assert_not_empty "$pods" "k8s::pods returns pods for selector"
}

test_pod_status() {
    local status
    status=$(k8s::pod_status "my-pod")
    assert_eq "Running" "$status" "k8s::pod_status returns status"
}

test_pod_running() {
    assert_true "k8s::pod_running my-pod" k8s::pod_running "my-pod"
}

test_wait_ready() {
    # Should succeed with mock
    assert_true "k8s::wait_ready deployment/my-app" k8s::wait_ready "deployment/my-app" --timeout 10
}

test_logs() {
    local logs
    logs=$(k8s::logs "my-pod")
    assert_contains "Log line" "$logs" "k8s::logs returns log output"
}

test_exec() {
    local result
    result=$(k8s::exec "my-pod" -- echo test)
    assert_eq "test" "$result" "k8s::exec executes command"
}

# =============================================================================
# SECRET/CONFIGMAP TESTS
# =============================================================================

test_secret_get() {
    local value
    value=$(k8s::secret_get "my-secret" "password")
    assert_eq "secretvalue" "$value" "k8s::secret_get decodes secret"
}

test_secret_set() {
    assert_true "k8s::secret_set existing" k8s::secret_set "my-secret" "newkey" "newvalue"
}

test_secrets_list() {
    local secrets
    secrets=$(k8s::secrets)
    assert_not_empty "$secrets" "k8s::secrets lists secrets"
}

test_configmap_get() {
    local value
    value=$(k8s::configmap_get "my-config" "key")
    assert_eq "configvalue" "$value" "k8s::configmap_get returns value"
}

test_configmap_set() {
    assert_true "k8s::configmap_set" k8s::configmap_set "my-config" "newkey" "newvalue"
}

test_configmaps_list() {
    local configmaps
    configmaps=$(k8s::configmaps)
    assert_not_empty "$configmaps" "k8s::configmaps lists configmaps"
}

# =============================================================================
# ROLLOUT TESTS
# =============================================================================

test_rollout_status() {
    local status
    status=$(k8s::rollout_status "deployment/my-app")
    assert_contains "rolled out" "$status" "k8s::rollout_status shows status"
}

test_rollout_restart() {
    assert_true "k8s::rollout_restart" k8s::rollout_restart "deployment/my-app"
}

test_rollout_undo() {
    assert_true "k8s::rollout_undo" k8s::rollout_undo "deployment/my-app"
}

test_rollout_history() {
    local history
    history=$(k8s::rollout_history "deployment/my-app")
    assert_contains "REVISION" "$history" "k8s::rollout_history shows revisions"
}

# =============================================================================
# RESOURCE QUERY TESTS
# =============================================================================

test_get_image() {
    local image
    image=$(k8s::get_image "deployment/my-app")
    assert_eq "my-app:v1.2.3" "$image" "k8s::get_image returns image"
}

test_get_replicas() {
    local replicas
    replicas=$(k8s::get_replicas "deployment/my-app")
    assert_eq "3" "$replicas" "k8s::get_replicas returns count"
}

test_get_ready_replicas() {
    local ready
    ready=$(k8s::get_ready_replicas "deployment/my-app")
    assert_eq "3" "$ready" "k8s::get_ready_replicas returns ready count"
}

test_scale() {
    assert_true "k8s::scale" k8s::scale "deployment/my-app" 5
}

test_get_events() {
    local events
    events=$(k8s::get_events)
    assert_not_empty "$events" "k8s::get_events returns events"
}

test_get_json() {
    local json
    json=$(k8s::get_json "deployment/my-app")
    assert_contains "apiVersion" "$json" "k8s::get_json returns JSON"
}

test_get_yaml() {
    local yaml
    yaml=$(k8s::get_yaml "deployment/my-app")
    assert_contains "apiVersion" "$yaml" "k8s::get_yaml returns YAML"
}

# =============================================================================
# RESOURCE MANAGEMENT TESTS
# =============================================================================

test_exists() {
    assert_true "k8s::exists deployment/my-app" k8s::exists "deployment/my-app"
}

test_not_exists() {
    assert_false "k8s::exists deployment/nonexistent" k8s::exists "deployment/nonexistent"
}

test_apply() {
    # Create temp manifest
    local manifest
    manifest=$(mktemp)
    echo "apiVersion: v1" > "$manifest"
    echo "kind: ConfigMap" >> "$manifest"
    echo "metadata:" >> "$manifest"
    echo "  name: test-config" >> "$manifest"
    
    assert_true "k8s::apply" k8s::apply "$manifest"
    rm -f "$manifest"
}

test_delete() {
    assert_true "k8s::delete" k8s::delete "deployment/my-app"
}

# =============================================================================
# SERVICE TESTS
# =============================================================================

test_service_ip() {
    local ip
    ip=$(k8s::service_ip "my-service")
    assert_contains "10." "$ip" "k8s::service_ip returns cluster IP"
}

test_service_external_ip() {
    local ip
    ip=$(k8s::service_external_ip "my-service")
    assert_not_empty "$ip" "k8s::service_external_ip returns IP"
}

test_service_ports() {
    local ports
    ports=$(k8s::service_ports "my-service")
    assert_contains "80" "$ports" "k8s::service_ports returns ports"
}

# =============================================================================
# LABEL/ANNOTATION TESTS
# =============================================================================

test_label() {
    assert_true "k8s::label" k8s::label "deployment/my-app" "env=production"
}

test_label_remove() {
    assert_true "k8s::label_remove" k8s::label_remove "deployment/my-app" "env"
}

test_annotate() {
    assert_true "k8s::annotate" k8s::annotate "deployment/my-app" "description=Test"
}

# =============================================================================
# UTILITY TESTS
# =============================================================================

test_ready() {
    assert_true "k8s::ready" k8s::ready
}

test_version() {
    local version
    version=$(k8s::version)
    assert_contains "v1" "$version" "k8s::version returns version"
}

test_describe() {
    local desc
    desc=$(k8s::describe "deployment/my-app")
    assert_contains "Name:" "$desc" "k8s::describe shows details"
}

# =============================================================================
# PORT FORWARD TESTS
# =============================================================================

test_port_forward_cleanup() {
    # Test port forward PID tracking
    _K8S_PORT_FORWARD_PIDS=()
    
    # Start a dummy port forward (mock just creates background sleep)
    if k8s::port_forward "svc/my-service" "8080:80"; then
        local pids
        pids=$(k8s::port_forward_pids)
        assert_not_empty "$pids" "k8s::port_forward tracks PID"
        
        # Clean up
        k8s::port_forward_stop
        pids=$(k8s::port_forward_pids)
        assert_eq "" "$pids" "k8s::port_forward_stop clears PIDs"
    else
        skip "port_forward" "mock did not start background process"
    fi
}

# =============================================================================
# MODULE EXPORTS TEST
# =============================================================================

test_exports() {
    local count=${#MAINFRAME_K8S_EXPORTS[@]}
    if ((count > 50)); then
        pass "Module exports ${count} functions"
    else
        fail "Module exports" "expected > 50 exports, got $count"
    fi
}

# =============================================================================
# RUN TESTS
# =============================================================================

info "Running Kubernetes library tests..."
echo ""

# Context/Namespace
info "Context/Namespace tests"
test_current_context
test_contexts
test_namespace_set_get

# Pod operations
info "Pod operation tests"
test_pods
test_pod_status
test_pod_running
test_wait_ready
test_logs
test_exec

# Secrets/ConfigMaps
info "Secret/ConfigMap tests"
test_secret_get
test_secret_set
test_secrets_list
test_configmap_get
test_configmap_set
test_configmaps_list

# Rollout management
info "Rollout tests"
test_rollout_status
test_rollout_restart
test_rollout_undo
test_rollout_history

# Resource queries
info "Resource query tests"
test_get_image
test_get_replicas
test_get_ready_replicas
test_scale
test_get_events
test_get_json
test_get_yaml

# Resource management
info "Resource management tests"
test_exists
test_not_exists
test_apply
test_delete

# Services
info "Service tests"
test_service_ip
test_service_external_ip
test_service_ports

# Labels/Annotations
info "Label/Annotation tests"
test_label
test_label_remove
test_annotate

# Utilities
info "Utility tests"
test_ready
test_version
test_describe

# Port forwarding
info "Port forward tests"
test_port_forward_cleanup

# Module
info "Module tests"
test_exports

# =============================================================================
# CLEANUP AND SUMMARY
# =============================================================================

# Cleanup mock kubectl
if ! $CLUSTER_AVAILABLE; then
    teardown_mock_kubectl
fi

echo ""
echo "============================================="
echo "Test Results"
echo "============================================="
echo -e "Total:   ${TESTS_RUN}"
echo -e "Passed:  ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed:  ${RED}${TESTS_FAILED}${NC}"
echo -e "Skipped: ${YELLOW}${TESTS_SKIPPED}${NC}"
echo "============================================="

if ((TESTS_FAILED > 0)); then
    exit 1
fi

exit 0

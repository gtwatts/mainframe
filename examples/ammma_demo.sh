#!/usr/bin/env bash
# =============================================================================
# AMMA V3 Demo Script
# =============================================================================
# Demonstrates the Advanced Multi-tier Memory Architecture features
# =============================================================================

set -euo pipefail

# Source AMMA libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ammma.sh"
source "${SCRIPT_DIR}/../lib/ammma_tiers.sh"
source "${SCRIPT_DIR}/../lib/ammma_consolidate.sh"
source "${SCRIPT_DIR}/../lib/ammma_mesh.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# =============================================================================
# DEMO: Basic Initialization
# =============================================================================

print_header "DEMO 1: Initializing AMMA V3 Memory System"

# Initialize AMMA with session and namespace
status=$(ammma_init --session "demo-session-$(date +%s)" --agent "demo-agent" --namespace "demo-project")
print_success "AMMA initialized"
echo "Status: $status" | jq .

# =============================================================================
# DEMO: Creating Memories
# =============================================================================

print_header "DEMO 2: Creating Different Memory Types"

# Episodic memory: Recording an event
ep1=$(ammma_episode_log \
    --content "Discovered that ChromaDB requires specific embedding dimensions" \
    --type "discovery" \
    --importance "high" \
    --tags '["vectordb","chromadb","embedding"]')
print_success "Created episodic memory: $ep1"

# Another episodic memory
ep2=$(ammma_episode_log \
    --content "Successfully deployed FastAPI application to production" \
    --type "achievement" \
    --importance "critical")
print_success "Created episodic memory: $ep2"

# Episodic memory: Decision
ep3=$(ammma_episode_log \
    --content "Chose PostgreSQL over MySQL for ACID compliance requirements" \
    --type "decision" \
    --importance "high")
print_success "Created episodic memory: $ep3"

# Declarative memory: Storing a fact
fact1=$(ammma_fact_store \
    --subject "Mainframe AMMA" \
    --predicate "supports" \
    --object "five memory tiers" \
    --confidence 0.99 \
    --source "documentation")
print_success "Created declarative memory: $fact1"

# Another fact
fact2=$(ammma_fact_store \
    --subject "API rate limit" \
    --predicate "is" \
    --object "100 requests per minute" \
    --confidence 0.95 \
    --source "api_docs")
print_success "Created declarative memory: $fact2"

# Procedural memory: Learning a pattern
pat1=$(ammma_pattern_learn \
    --name "fastapi-error-handling" \
    --trigger "fastapi AND error AND production" \
    --steps '["define_exceptions","add_handlers","test_thoroughly"]' \
    --importance "high")
print_success "Created procedural memory: $pat1"

print_info "Total memories created. Current statistics:"
ammma_stats | jq .

# =============================================================================
# DEMO: Attention Mechanism
# =============================================================================

print_header "DEMO 3: Attention Window"

print_info "Current attention window (memories in focus):"
ammma_attention_get | jq .

# =============================================================================
# DEMO: Memory Retrieval
# =============================================================================

print_header "DEMO 4: Semantic Memory Retrieval"

print_info "Retrieving memories about 'FastAPI':"
results=$(ammma_retrieve "FastAPI" --limit 5)
echo "$results" | jq '.results | length'

print_info "Retrieving memories about 'database':"
results=$(ammma_retrieve "database" --limit 5)
echo "$results" | jq '.results | length'

# =============================================================================
# DEMO: Context Building
# =============================================================================

print_header "DEMO 5: Building Context for LLM"

print_info "Building context package with max 2000 tokens:"
context=$(ammma_context_build --max-tokens 2000)
echo "$context" | jq '{
    session_id: .session_id,
    max_tokens: .max_tokens,
    memory_count: (.memories | length),
    metadata: .metadata
}'

# =============================================================================
# DEMO: Tier Management
# =============================================================================

print_header "DEMO 6: Automatic Tier Management"

print_info "Before tier management:"
ammma_tier_stats | jq .

print_info "Running tier management cycle..."
tier_result=$(ammma_tier_manage)
echo "$tier_result" | jq .

print_info "After tier management:"
ammma_tier_stats | jq .

# =============================================================================
# DEMO: Memory Consolidation
# =============================================================================

print_header "DEMO 7: Memory Consolidation"

print_info "Running memory consolidation (dry-run):"
consol_result=$(ammma_consolidate --dry-run)
echo "$consol_result" | jq .

# Now actually run consolidation
print_info "Running actual consolidation:"
consol_result=$(ammma_consolidate)
echo "$consol_result" | jq .

# =============================================================================
# DEMO: Memory Mesh (Cross-Agent Sharing)
# =============================================================================

print_header "DEMO 8: Memory Mesh - Cross-Agent Sharing"

# Initialize mesh
mesh_status=$(ammma_mesh_init --namespace "demo-mesh")
print_success "Mesh initialized"
echo "$mesh_status" | jq .

# Publish a memory to the mesh
print_info "Publishing memory to mesh:"
msg_id=$(ammma_mesh_publish "$ep1" --scope team)
print_success "Published with message ID: $msg_id"

# Query the mesh
print_info "Querying mesh for 'ChromaDB':"
mesh_results=$(ammma_mesh_query "ChromaDB" --scope team)
echo "$mesh_results" | jq '. | length'

# Subscribe to a topic
print_info "Subscribing to 'discoveries' topic:"
ammma_mesh_subscribe "discoveries" _handle_discovery
print_success "Subscribed successfully"

# Handler function for discoveries
_handle_discovery() {
    local message="$1"
    print_info "Received discovery: $(echo "$message" | jq -r '.id')"
}

# Poll for messages
print_info "Polling for messages:"
ammma_mesh_poll

# Show mesh statistics
print_info "Mesh statistics:"
ammma_mesh_stats | jq .

# =============================================================================
# DEMO: Inheritance
# =============================================================================

print_header "DEMO 9: Context Inheritance"

print_info "Preparing inheritance package for child agent:"
inheritance=$(ammma_mesh_inherit_prepare --filter high --max-memories 10)
echo "$inheritance" | jq '{
    parent_session: .parent_session,
    parent_agent: .parent_agent,
    filter: .filter,
    count: .count
}'

# =============================================================================
# DEMO: Advanced Features
# =============================================================================

print_header "DEMO 10: Advanced Features"

# Show current statistics
print_info "Final system statistics:"
cat <<EOF | jq -s '.[0] * .[1] * .[2]' <(ammma_stats) <(ammma_tier_stats) <(ammma_mesh_stats)
EOF

print_header "DEMO COMPLETE"

echo ""
echo -e "${GREEN}AMMA V3 Demonstration Complete!${NC}"
echo ""
echo "Summary:"
echo "  - Initialized multi-tier memory system"
echo "  - Created episodic, declarative, and procedural memories"
echo "  - Demonstrated attention mechanism"
echo "  - Retrieved memories with semantic search"
echo "  - Built context for LLM consumption"
echo "  - Ran automatic tier management"
echo "  - Performed memory consolidation"
echo "  - Used memory mesh for cross-agent sharing"
echo "  - Demonstrated context inheritance"
echo ""

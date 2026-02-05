#!/usr/bin/env bash
# =============================================================================
# UAP v2 Example Usage
# =============================================================================
# This example demonstrates the Universal Agent Protocol v2 features
# =============================================================================

# Source the libraries
source "${0%/*}/../lib/json.sh"
source "${0%/*}/../lib/uap_v2.sh"

# Disable heartbeat for cleaner output in this example
export UAP_V2_NO_HEARTBEAT=1
export MAINFRAME_QUIET=1

echo "═══════════════════════════════════════════════════════════════"
echo "  UAP v2 Example: Multi-Agent System"
echo "═══════════════════════════════════════════════════════════════"

# -----------------------------------------------------------------------------
# Agent A: Code Reviewer
# -----------------------------------------------------------------------------
echo ""
echo "▶ Registering Code Reviewer agent..."
uap_v2_register "code-reviewer" \
    --capabilities "code.review,security.scan" \
    --schema '{"review":{"file":"string","strict":"boolean"},"scan":{"target":"string"}}'

echo "  ✓ Code Reviewer registered with capabilities: code.review, security.scan"

# -----------------------------------------------------------------------------
# Agent B: Orchestrator
# -----------------------------------------------------------------------------
echo ""
echo "▶ Registering Orchestrator agent..."
uap_v2_register "orchestrator" \
    --capabilities "deploy,monitor"

echo "  ✓ Orchestrator registered with capabilities: deploy, monitor"

# -----------------------------------------------------------------------------
# Discovery: Find agents with code review capability
# -----------------------------------------------------------------------------
echo ""
echo "▶ Discovering agents with 'code.review' capability..."
CODE_AGENTS=$(uap_v2_discover "code.review")
echo "  Found: $CODE_AGENTS"

# Extract first agent
REVIEWER=$(echo "$CODE_AGENTS" | grep -o '"[^"]*"' | head -1 | tr -d '"')
echo "  Using reviewer: $REVIEWER"

# -----------------------------------------------------------------------------
# Schema inspection
# -----------------------------------------------------------------------------
echo ""
echo "▶ Inspecting schema for 'review' method..."
SCHEMA=$(uap_v2_schema "$REVIEWER" "review")
echo "  Schema: $SCHEMA"

# -----------------------------------------------------------------------------
# Synchronous RPC call (will timeout since no listener, but demonstrates format)
# -----------------------------------------------------------------------------
echo ""
echo "▶ Example: Synchronous RPC call format"
echo "  Command: uap_v2_call \"$REVIEWER\" \"review\" --arg file=\"auth.ts\" --arg strict=true --timeout 300"
echo "  (Would send RPC request to $REVIEWER)"

# -----------------------------------------------------------------------------
# Health check
# -----------------------------------------------------------------------------
echo ""
echo "▶ System Health Check..."
HEALTH=$(uap_v2_health_check)
echo "  Health: $HEALTH"

# -----------------------------------------------------------------------------
# List all agents
# -----------------------------------------------------------------------------
echo ""
echo "▶ All Registered Agents:"
uap_v2_list_agents | python3 -m json.tool 2>/dev/null || uap_v2_list_agents

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
echo ""
echo "▶ Cleanup..."
uap_v2_unregister "code-reviewer"
uap_v2_unregister "orchestrator"
echo "  ✓ All agents unregistered"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Example Complete"
echo "═══════════════════════════════════════════════════════════════"

# Mainframe Multi-Agent Interoperability Analysis & Enhancement Proposals

## Executive Summary

Mainframe currently provides a robust file-based IPC system for multi-agent coordination within a single host environment. This analysis evaluates the current architecture against the goal of becoming a **universal runtime for ALL agentic CLI tools** across Claude Code, Kimi CLI, Google CLI, Cursor AI, Aider, OpenCode, and custom agent frameworks.

---

## 1. Current Integration Architecture Assessment

### 1.1 Strengths

| Component | Assessment | Score |
|-----------|------------|-------|
| **File-based IPC (lib/agent.sh)** | Mature, uses flock for atomicity, FIFO ordering, heartbeats | ⭐⭐⭐⭐⭐ |
| **Agent Registration** | Capability-based discovery, JSON status, heartbeat pruning | ⭐⭐⭐⭐⭐ |
| **Messaging** | P2P, broadcast, pub/sub topics, async receive | ⭐⭐⭐⭐⭐ |
| **Synchronization** | Barriers, signals, work queues, resource locking | ⭐⭐⭐⭐⭐ |
| **Context Management** | Persistent sessions, snapshots, versioning (lib/agent_context.sh) | ⭐⭐⭐⭐⭐ |
| **Execution Safety** | Command allowlisting, undo transactions, recovery (lib/agent_exec.sh) | ⭐⭐⭐⭐⭐ |
| **Format Bridge** | JSON↔CSV↔YAML↔XML conversion (lib/bridge.sh) | ⭐⭐⭐⭐⭐ |
| **Skills System** | Claude Code, Kimi CLI, Cursor, Aider, Vercel AI SDK | ⭐⭐⭐⭐⭐ |

### 1.2 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MAINFRAME AGENT ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  SKILLS LAYER          │ Claude │ Kimi │ Cursor │ Aider │ Vercel │ OpenCode│
│  (Platform Adapters)   │  Code  │ CLI  │   AI   │       │ AI SDK │ (gap)   │
├───────────────────────┬┴────────┴──────┴────────┴───────┴────────┴─────────┤
│  UNIFIED API          │ lib/common.sh - 4,000+ pure bash functions         │
├───────────────────────┼────────────────────────────────────────────────────┤
│  AGENT EXECUTION      │ lib/agent_exec.sh - Safe execution pipeline        │
│  (Safety & Recovery)  │ • Command allowlist/blocklist                      │
│                       │ • Guard checks → Contract validation → Execute     │
│                       │ • Undo/compensating transactions                   │
│                       │ • Recovery playbooks with pattern matching         │
├───────────────────────┼────────────────────────────────────────────────────┤
│  AGENT CONTEXT        │ lib/agent_context.sh - Persistent state            │
│  (State Management)   │ • Session lifecycle (init/load/save/close)         │
│                       │ • Snapshots with versioning                        │
│                       │ • Import/export/merge capabilities                 │
├───────────────────────┼────────────────────────────────────────────────────┤
│  AGENT COMMUNICATION  │ lib/agent.sh - File-based IPC                      │
│  (IPC Layer)          │ • Registration with capabilities                   │
│                       │ • Messaging: P2P, broadcast, pub/sub               │
│                       │ • Work queues with FIFO atomic pop                 │
│                       │ • Barriers, signals, resource locking              │
│                       │ │ lib/agent_comm.sh - Alternative IPC API          │
├───────────────────────┼────────────────────────────────────────────────────┤
│  DATA BRIDGE          │ lib/bridge.sh - Format conversion                  │
│  (Interoperability)   │ • Auto-detect: JSON, CSV, YAML, XML, INI, NDJSON   │
│                       │ • Bidirectional conversion between all formats     │
│                       │ • Schema extraction from data                      │
├───────────────────────┼────────────────────────────────────────────────────┤
│  PERSISTENCE          │ ${TMPDIR}/mainframe-${UID}/agents/                 │
│  (File System)        │ • Registry: agent dirs with capabilities, heartbeat│
│                       │ • Inbox/Outbox: Message queues per agent           │
│                       │ • Shared State: key-value store                    │
│                       │ • Contexts: $HOME/.mainframe/contexts/             │
└───────────────────────┴────────────────────────────────────────────────────┘
```

### 1.3 Current Limitations for Cross-Platform Use

| Limitation | Impact | Severity |
|------------|--------|----------|
| **Host-local only** | Agents on different machines cannot communicate | 🔴 Critical |
| **Bash-only consumers** | Non-bash agents need wrappers to use IPC | 🔴 Critical |
| **No standard protocol** | Other CLI tools don't understand Mainframe's IPC format | 🔴 Critical |
| **Process-based discovery** | Uses PID for liveness; doesn't work for containerized agents | 🟡 High |
| **No authentication** | Any process can register as any agent | 🟡 High |
| **Single-user scope** | IPC is per-UID; no cross-user coordination | 🟡 Medium |
| **No message encryption** | Sensitive data in messages is plaintext | 🟡 Medium |
| **Limited observability** | No centralized logging/metrics for agent interactions | 🟡 Medium |

---

## 2. Platform-Specific Integration Strategies

### 2.1 Current Platform Support Matrix

| Platform | Skill Format | Location | Auto-Load | Multi-Agent | Status |
|----------|-------------|----------|-----------|-------------|--------|
| **Claude Code** | SKILL.md | `~/.claude/skills/` | ✅ Yes | ✅ Native | ✅ Complete |
| **Kimi CLI** | SKILL.md | `~/.claude/skills/` | ✅ Yes | ✅ Native | ✅ Complete |
| **Cursor AI** | .mdc | `.cursor/rules/` | ✅ Yes | ❌ No | ✅ Complete |
| **Aider** | CONVENTIONS.md | `.aider.conf.yml` | ⚠️ Manual | ❌ No | ✅ Complete |
| **Vercel AI SDK** | system-prompt.md | Load in code | ⚠️ Manual | ⚠️ Custom | ✅ Complete |
| **Google CLI** | None | N/A | ❌ No | ❌ No | ❌ Missing |
| **OpenCode** | None | N/A | ❌ No | ❌ No | ❌ Missing |
| **Custom Agents** | Template | Create from example | ⚠️ Manual | ⚠️ Custom | ⚠️ Partial |

### 2.2 Platform-Specific Integration Strategies

#### A. Claude Code (Anthropic) - ✅ CURRENT
```yaml
Current: SKILL.md in ~/.claude/skills/mainframe-bash/
Integration: Native skill system with automatic activation
Messaging: Can use mainframe agent IPC via bash subprocess
Enhancement: Add MCP (Model Context Protocol) server mode
```

**Recommended Enhancements:**
1. **MCP Server Mode**: Create `lib/mcp_server.sh` that exposes Mainframe functions as MCP tools
2. **Agent Presence Bridge**: Claude Code can publish its presence to Mainframe registry
3. **Context Sync**: Bidirectional sync between Claude's context and Mainframe AWM

#### B. Kimi CLI (Moonshot AI) - ✅ CURRENT
```yaml
Current: SKILL.md (nearly identical to Claude Code)
Integration: Native skill system
Messaging: Same capabilities as Claude Code
Enhancement: Consolidate with Claude skill, add Kimi-specific extensions
```

**Recommended Enhancements:**
1. **Unified Skill Base**: Merge Claude and Kimi skills into common base
2. **Kimi Extensions**: Add Kimi-specific context management features
3. **Cross-CLI Bridge**: Enable Claude↔Kimi direct messaging

#### C. Google CLI (Google AI) - ❌ MISSING
```yaml
Current: No skill file
Integration Path: Similar to Claude/Kimi skill format
Estimated Effort: Low (adapt existing skill)
```

**Recommended Implementation:**
```bash
# skills/google-cli/SKILL.md
---
name: mainframe-bash
description: "Use when writing bash scripts..."
---
# (Content similar to claude-code/SKILL.md)
```

#### D. Cursor AI - ✅ CURRENT
```yaml
Current: .mdc rule file in skills/cursor/
Integration: Cursor's rule system for project/global context
Enhancement: Add Cursor-specific agent coordination
```

**Recommended Enhancements:**
1. **Composer Integration**: Enable Cursor Composer to spawn Mainframe agents
2. **Multi-Agent Mode**: Cursor can orchestrate Mainframe agent swarms
3. **Chat-to-Agent Bridge**: Convert Cursor chat messages to agent IPC

#### E. Aider - ✅ CURRENT
```yaml
Current: CONVENTIONS.md and .aider.conf.yml
Integration: Aider's conventions system
Enhancement: Add Aider-specific multi-file editing coordination
```

**Recommended Enhancements:**
1. **Edit Coordination**: Use agent IPC for coordinating multi-file edits
2. **Context Sharing**: Share Aider's repository map via Mainframe context
3. **Undo Coordination**: Link Aider's undo with Mainframe compensating transactions

#### F. OpenCode (SaaS Inc) - ❌ MISSING
```yaml
Current: No skill file
Integration Path: OpenCode's instruction system
Estimated Effort: Medium (need to research OpenCode's format)
```

**Recommended Implementation:**
Research OpenCode's agent instruction format and create corresponding skill file.

#### G. Custom Agent Frameworks - ⚠️ PARTIAL
```yaml
Current: Vercel AI SDK skill provides system prompt
Integration: Can use as system prompt in custom agents
Enhancement: Create SDK/bindings for popular frameworks
```

**Recommended Enhancements:**
1. **Python SDK**: `pip install mainframe-agents` - Python bindings for IPC
2. **TypeScript SDK**: `npm install @mainframe/agents` - TS/JS bindings
3. **Go SDK**: Go bindings for high-performance agents
4. **Rust SDK**: Rust bindings for systems-level agents

---

## 3. Cross-Platform Enhancement Proposals

### Proposal 1: Universal Agent Protocol (UAP) - STANDARDIZED MESSAGE FORMAT

**Problem**: Each CLI tool has its own way of representing agent identity, capabilities, and messages.

**Solution**: Define a JSON-based protocol that all agents can use, with format bridges for platform-specific representations.

```json
// UAP Message Envelope (universal-agent-protocol v1)
{
  "uap_version": "1.0",
  "message_id": "uuid-v4",
  "timestamp": "2026-02-05T06:05:09.379Z",
  "sender": {
    "agent_id": "claude-code-instance-1",
    "platform": "claude-code",
    "version": "0.1.20",
    "capabilities": ["bash", "file_edit", "web_search"],
    "endpoint": "unix:///tmp/mainframe/claude-1.sock"
  },
  "recipient": {
    "agent_id": "kimi-cli-instance-1",
    "platform": "kimi-cli",
    "routing_key": "compute"
  },
  "message_type": "task_request",
  "payload": {
    "task": "analyze_code",
    "parameters": {"file": "src/main.py"},
    "priority": "normal",
    "deadline": "2026-02-05T07:00:00Z"
  },
  "metadata": {
    "correlation_id": "parent-task-123",
    "ttl": 300,
    "encryption": "none"
  }
}
```

**Implementation:**
```bash
# lib/uap.sh - Universal Agent Protocol
uap_encode_message() { ... }
uap_decode_message() { ... }
uap_validate_message() { ... }
uap_route_message() { ... }
```

**Impact**: Enables Claude, Kimi, Google CLI, and custom agents to communicate seamlessly.

---

### Proposal 2: Agent Gateway Service - NETWORK BRIDGE

**Problem**: File-based IPC is limited to single-host, single-user.

**Solution**: Optional gateway daemon that bridges local IPC to network transport.

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  Claude Code    │      │  Mainframe       │      │  Kimi CLI       │
│  (Local)        │◄────►│  Agent Gateway   │◄────►│  (Remote/Docker)│
│                 │ IPC  │                  │ WS   │                 │
│  agent_send()   │      │  • WebSocket     │      │  agent_receive()│
│                 │      │  • gRPC          │      │                 │
└─────────────────┘      │  • MQTT          │      └─────────────────┘
                         │  • NATS          │
                         └──────────────────┘
                                   │
                         ┌─────────┴──────────┐
                         │  Redis / RabbitMQ  │
                         │  (Message Bus)     │
                         └────────────────────┘
```

**Implementation:**
```bash
# bin/mainframe-gateway
# Starts gateway daemon
mainframe gateway start --transport websocket --port 7474

# lib/gateway.sh - Client library
source "${MAINFRAME_ROOT}/lib/gateway.sh"
gateway_connect "ws://gateway.internal:7474"
gateway_register
msg=$(gateway_receive 10)
```

**Impact**: Enables multi-host agent swarms, containerized agents, cloud deployments.

---

### Proposal 3: Multi-Platform Agent Discovery Service

**Problem**: `agent_discover()` only finds local bash agents.

**Solution**: Pluggable discovery backends.

```bash
# Current: File-based discovery
agent_discover "compute"  # Only finds local agents

# Enhanced: Multi-backend discovery
export AGENT_DISCOVERY_BACKENDS="local,consul,etcd,kubernetes"
agent_discover "compute"  # Finds agents across all backends
```

**Backends:**
| Backend | Use Case | Implementation |
|---------|----------|----------------|
| `local` | Single-host | Current file-based |
| `consul` | Service mesh | HashiCorp Consul integration |
| `etcd` | Kubernetes | CoreOS etcd for k8s-native |
| `kubernetes` | K8s clusters | Native pod/service discovery |
| `mdns` | Local network | Bonjour/Avahi for LAN discovery |
| `redis` | Distributed | Redis pub/sub for registration |

**Implementation:**
```bash
# lib/discovery.sh
source "${MAINFRAME_ROOT}/lib/discovery.sh"

discovery_register_backend "consul" "consul_register" "consul_discover"
discovery_register_backend "k8s" "k8s_register" "k8s_discover"

# Unified API works across all backends
agents=$(discovery_find "capability=compute&platform=claude-code")
```

---

### Proposal 4: Standardized Capability Ontology

**Problem**: Each platform describes capabilities differently (e.g., "bash" vs "shell" vs "command_execution").

**Solution**: Standardized capability taxonomy.

```yaml
# capabilities.yaml - Standardized capability ontology
capability_ontology:
  version: "1.0"
  
  core:
    code_generation:
      - code.write
      - code.read
      - code.edit
      - code.analyze
    shell_execution:
      - shell.bash
      - shell.zsh
      - shell.powershell
    file_operations:
      - file.read
      - file.write
      - file.delete
      - file.search
      
  languages:
    python: [python.write, python.analyze, python.test]
    typescript: [typescript.write, typescript.analyze, typescript.test]
    rust: [rust.write, rust.analyze, rust.test]
    go: [go.write, go.analyze, go.test]
    
  platforms:
    claude_code: [anthropic.web_search, anthropic.computer_use]
    kimi_cli: [moonshot.code_review, moonshot.documentation]
    
  infrastructure:
    docker: [docker.build, docker.run, docker.compose]
    kubernetes: [k8s.deploy, k8s.logs, k8s.exec]
    aws: [aws.s3, aws.lambda, aws.ec2]
```

**Implementation:**
```bash
# lib/capability.sh enhancements
capability_normalize "bash"        # Returns: shell.bash
capability_match "shell.bash" "bash"  # Returns: true (fuzzy match)
capability_expand "python"         # Returns: python.write python.analyze python.test
```

---

### Proposal 5: Agent Lifecycle Management API

**Problem**: No standardized way to manage agent lifecycle across platforms.

**Solution**: Unified lifecycle API with platform adapters.

```bash
# lib/agent_lifecycle.sh

# Spawn a new agent instance
agent_spawn \
  --platform claude-code \
  --name "analyzer-1" \
  --capabilities "python.analyze,code.read" \
  --context "$(ctx_export_json)" \
  --timeout 3600

# Monitor agent health
agent_health "analyzer-1"  # Returns: healthy|degraded|unhealthy

# Graceful shutdown
agent_terminate "analyzer-1" --graceful --timeout 30

# Force kill
agent_kill "analyzer-1"

# Get agent logs
agent_logs "analyzer-1" --follow --since 5m
```

**Platform Adapters:**
```bash
# lib/adapters/claude_adapter.sh
claude_spawn() { 
  # Launch Claude Code in headless mode
  claude --headless --name "$1" --capabilities "$2"
}

claude_health() {
  # Check if Claude process is responsive
  pgrep -f "claude.*$1" && echo "healthy" || echo "unhealthy"
}

# lib/adapters/kimi_adapter.sh
kimi_spawn() {
  # Launch Kimi CLI with parameters
  kimi --agent-name "$1" --mode headless
}

# lib/adapters/generic_adapter.sh
# For custom agents via stdin/stdout protocol
generic_spawn() {
  # Launch agent with UAP protocol over stdio
  "$AGENT_BINARY" --protocol uap --name "$1"
}
```

---

### Proposal 6: Shared Memory Spaces with Access Control

**Problem**: `agent_state_set/get` has no access control or namespacing.

**Solution**: Namespaced shared memory with RBAC.

```bash
# lib/shared_memory.sh

# Create a shared memory namespace
shm_create "project-alpha" \
  --owner "claude-code-instance-1" \
  --permissions "rw:claude-*;r:kimi-*;rw:aider-*"

# Write with namespace
shm_set "project-alpha" "api_key" "$API_KEY" --encrypt

# Read with namespace
value=$(shm_get "project-alpha" "api_key" --decrypt)

# Subscribe to changes
shm_watch "project-alpha" "config.*" "on_config_change"

# List accessible namespaces
shm_list --accessible
```

**Storage Backends:**
| Backend | Use Case | Persistence |
|---------|----------|-------------|
| `file` | Single-host | Disk |
| `redis` | Multi-host | Memory + optional disk |
| `etcd` | Distributed | Disk |
| `sqlite` | Embedded | Disk |
| `memory` | Ephemeral | None |

---

### Proposal 7: Inter-Agent RPC Mechanism

**Problem**: Current messaging is async; no request/response pattern with typed interfaces.

**Solution**: RPC layer with service definitions.

```bash
# lib/agent_rpc.sh

# Define a service (in shell or external schema)
cat > /tmp/code_analysis.svc << 'EOF'
service CodeAnalysis {
  rpc AnalyzeFile(FileRequest) returns (AnalysisResult);
  rpc GetSuggestions(CodeSnippet) returns (SuggestionList);
  rpc Refactor(RefactorRequest) returns (RefactorResult);
}
EOF

# Register service implementation
rpc_register_service "CodeAnalysis" "code_analysis_handler"

# Call remote service
result=$(rpc_call \
  --agent "kimi-cli-instance-1" \
  --service "CodeAnalysis" \
  --method "AnalyzeFile" \
  --input '{"file": "src/main.py"}' \
  --timeout 30)

# Async call with callback
rpc_call_async \
  --agent "kimi-cli-instance-1" \
  --service "CodeAnalysis" \
  --method "AnalyzeFile" \
  --input '{}' \
  --callback "on_analysis_complete"
```

**Type System:**
```bash
# JSON Schema validation for RPC messages
rpc_validate_input "CodeAnalysis.AnalyzeFile" "$input_json"
```

---

### Proposal 8: Workflow Orchestration DSL

**Problem**: Complex multi-agent workflows require custom scripting.

**Solution**: Declarative workflow definition.

```yaml
# workflows/code-review.yaml
workflow:
  name: "Multi-Agent Code Review"
  version: "1.0"
  
  agents:
    analyzer:
      platform: claude-code
      capabilities: [python.analyze]
      count: 2  # Spawn 2 analyzers for parallel work
    
    reviewer:
      platform: kimi-cli
      capabilities: [code.review]
      depends_on: [analyzer]
    
    documenter:
      platform: aider
      capabilities: [documentation.write]
      depends_on: [reviewer]
  
  steps:
    - name: "Analyze Code"
      parallel: true
      agent: analyzer
      input:
        files: "{{ workflow.input.files }}"
      output: analysis_results
    
    - name: "Review Findings"
      agent: reviewer
      input:
        analyses: "{{ steps.analyze_code.output }}"
      output: review_comments
    
    - name: "Update Docs"
      agent: documenter
      input:
        review: "{{ steps.review_findings.output }}"
      
  on_failure:
    - action: notify
      channel: slack
      message: "Code review workflow failed"
    - action: rollback
      step: "Update Docs"
```

**Execution:**
```bash
# lib/workflow.sh

# Run workflow
workflow_run "workflows/code-review.yaml" \
  --input '{"files": ["src/*.py"]}' \
  --watch

# Get workflow status
workflow_status "workflow-uuid"

# Cancel workflow
workflow_cancel "workflow-uuid"
```

---

### Proposal 9: Cross-Platform Context Propagation

**Problem**: Agent context (lib/agent_context.sh) doesn't transfer between platforms.

**Solution**: Context serialization format that all platforms can consume.

```bash
# lib/context_propagation.sh

# Export context for cross-platform transfer
ctx_export_crossplatform \
  --format "mainframe-v1" \
  --include "session_id,data,metadata" \
  --compress \
  > /tmp/context.mfctx

# Import context from another platform
ctx_import_crossplatform "/tmp/context.mfctx" \
  --validate \
  --merge_strategy "overlay"

# Automatic context propagation
export AGENT_AUTO_PROPAGATE_CONTEXT=1
agent_spawn --inherit_context
```

**Context Format:**
```json
{
  "mfctx_version": "1.0",
  "session_id": "uuid",
  "export_platform": "claude-code",
  "export_timestamp": "2026-02-05T06:05:09Z",
  "data": {...},
  "metadata": {...},
  "snapshots": [...],
  "checksum": "sha256:..."
}
```

---

### Proposal 10: Unified Observability & Telemetry

**Problem**: No centralized view of multi-agent interactions.

**Solution**: OpenTelemetry-compatible observability.

```bash
# lib/otel_agents.sh

# Initialize tracing
otel_init \
  --service_name "mainframe-agent-swarm" \
  --exporter "otlp-http" \
  --endpoint "http://jaeger:4318"

# Automatic instrumentation of agent operations
export AGENT_TRACE_ENABLED=1

# Manual span creation
otel_span_start "analyze_code"
  # ... analysis work ...
otel_span_end "analyze_code"

# Log correlation
otel_log "Processing file: $file" \
  --attributes "file=$file,agent=analyzer-1"

# Metrics
otel_counter_add "agent.messages.sent" 1 \
  --attributes "platform=claude-code"
otel_histogram_record "agent.task.duration" 5.3 \
  --attributes "task_type=code_review"
```

**Visualization:**
```
┌─────────────────────────────────────────────────────────────┐
│  Agent Interaction Trace                                      │
├─────────────────────────────────────────────────────────────┤
│  [Claude Code]───────►[Task Queue]───────►[Kimi CLI]        │
│       │                                          │          │
│       │         15ms              8ms            │          │
│       │◄───────[Result]◄──────────[Analysis]─────┘          │
│       │                                                      │
│       └───────►[Aider] (3ms)                                │
│                   │                                          │
│                   └───────►[Complete]                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Implementation Roadmap

### Phase 1: Foundation (Immediate)
- [ ] Create missing skill files (Google CLI, OpenCode)
- [ ] Refactor Claude/Kimi skills to share common base
- [ ] Add MCP server mode for Claude Code

### Phase 2: Protocol Standardization (1-2 months)
- [ ] Implement UAP v1 (Proposal 1)
- [ ] Create format bridge adapters for each platform
- [ ] Add capability ontology (Proposal 4)

### Phase 3: Network Expansion (2-3 months)
- [ ] Build Agent Gateway Service (Proposal 2)
- [ ] Implement multi-backend discovery (Proposal 3)
- [ ] Add network transport options (WebSocket, gRPC)

### Phase 4: Advanced Features (3-4 months)
- [ ] Workflow Orchestration DSL (Proposal 8)
- [ ] Inter-Agent RPC (Proposal 7)
- [ ] Shared Memory with RBAC (Proposal 6)

### Phase 5: Ecosystem (4-6 months)
- [ ] Python/TypeScript SDKs
- [ ] Kubernetes operator
- [ ] Web UI for agent monitoring
- [ ] Plugin marketplace

---

## 5. Summary: Path to Universal Runtime

### Current State
Mainframe is a **mature single-host agent coordination platform** with:
- ✅ Robust file-based IPC
- ✅ Comprehensive bash function library
- ✅ Skills for 5+ AI platforms
- ✅ Safety and execution guardrails

### Target State
**Universal Runtime for Agentic CLI Tools**:
- 🎯 Seamless communication between Claude, Kimi, Google CLI, Cursor, Aider, OpenCode
- 🎯 Network-distributed agent swarms
- 🎯 Standardized protocols and capability discovery
- 🎯 Multi-language SDKs
- 🎯 Enterprise-grade observability

### Critical Success Factors
1. **Protocol Adoption**: Get buy-in from platform vendors
2. **Performance**: Maintain <10ms latency for local IPC
3. **Security**: End-to-end encryption for network transport
4. **Ergonomics**: Simple APIs that don't require deep bash knowledge
5. **Documentation**: Comprehensive guides for each platform

---

*Analysis completed: 2026-02-05*
*Proposals designed for incremental implementation with backward compatibility*

# MAINFRAME 10-Phase Strategic Roadmap

> Multi-AI Council Review | February 2026 | v8.0-v10.0 Planning

## Executive Summary

This roadmap was developed through multi-agent orchestration review (Grok, Gemini, GLM 4.7) analyzing MAINFRAME's current state (4,500+ functions, 135 libraries) against AI agent framework requirements. The 10 phases are prioritized by consensus to maximize developer value while building on existing capabilities.

**Current State (v7.3)**: Advanced Orchestration complete with AWM, multi-agent teams, MCP/LSP, property testing, benchmarks, and developer pain point libraries.

**Target State (v10.0)**: Full AI Agent Runtime with LLM integration, RAG support, enterprise security, and edge deployment capabilities.

---

## Phase Overview

| Phase | Name | Priority | Est. Effort | Dependencies |
|-------|------|----------|-------------|--------------|
| 1 | LLM Integration Core | Critical | 6 weeks | None |
| 2 | Tool Registry | Critical | 4 weeks | Phase 1 |
| 3 | Vector DB & RAG | High | 5 weeks | Phase 1 |
| 4 | Async Patterns | High | 5 weeks | None |
| 5 | Security Hardening v2 | High | 4 weeks | Phase 4 |
| 6 | State Management | Medium | 3 weeks | Phase 4, 5 |
| 7 | Observability | Medium | 4 weeks | Phase 6 |
| 8 | Developer Experience v2 | Medium | 4 weeks | All prior |
| 9 | Enterprise Features | Lower | 5 weeks | Phase 5, 7 |
| 10 | Edge Deployment | Lower | 4 weeks | Phase 8 |

---

## Phase 1: LLM Integration Core (v8.0)

**Priority**: CRITICAL | **Consensus Rank**: #1

### Rationale
All AI models agree this is the foundation. MAINFRAME has HTTP capabilities but lacks LLM-specific primitives. Without tokenizers, streaming, and function calling, agents cannot effectively interact with modern LLMs.

### Deliverables

#### 1.1 Tokenizer Library (`lib/llm_tokens.sh`)
```bash
# Token counting for context management
llm_count_tokens "text" "gpt-4"           # Returns token count
llm_estimate_cost "text" "claude-3"       # Returns estimated cost
llm_truncate_to_tokens "text" 4000 "gpt-4" # Truncate to fit
llm_split_chunks "text" 2000 "gpt-4"      # Split into chunks
```

#### 1.2 Streaming Response Handler (`lib/llm_stream.sh`)
```bash
# Process LLM responses as they arrive
llm_stream_start "https://api.openai.com/v1/chat/completions"
llm_stream_on_token "callback_function"   # Per-token callback
llm_stream_on_complete "final_callback"   # Completion callback
llm_stream_cancel                          # Cancel in-flight request
```

#### 1.3 Function Calling Primitives (`lib/llm_functions.sh`)
```bash
# Parse and execute LLM function calls
llm_parse_tool_call "$response"           # Extract tool invocation
llm_validate_tool_args "$schema" "$args"  # Validate arguments
llm_execute_tool "$tool_name" "$args"     # Execute and return
llm_format_tool_result "$result"          # Format for LLM
```

#### 1.4 Provider Wrappers
- OpenAI API wrapper (`llm_openai_*`)
- Anthropic Claude wrapper (`llm_anthropic_*`)
- Local/Ollama wrapper (`llm_ollama_*`)
- Generic provider interface

### Success Metrics
- [ ] Token counting within 5% of provider counts
- [ ] Streaming latency < 100ms first token
- [ ] Support for 4 major LLM providers
- [ ] 95%+ test coverage

---

## Phase 2: Tool Registry & Schema Generation (v8.1)

**Priority**: CRITICAL | **Consensus Rank**: #2

### Rationale
With 4,500+ functions, MAINFRAME is useless to LLMs without describable schemas. Auto-generating JSON schemas from docstrings unlocks the entire library for AI consumption.

### Deliverables

#### 2.1 Function Scanner (`lib/registry.sh`)
```bash
# Scan and catalog functions
registry_scan "lib/json.sh"              # Scan single library
registry_scan_all                         # Scan all libraries
registry_get_function "json_object"       # Get function metadata
registry_list_by_category "validation"    # Filter by category
```

#### 2.2 Schema Generator (`lib/registry_schema.sh`)
```bash
# Generate LLM-compatible schemas
registry_to_openai_schema "json_object"  # OpenAI function format
registry_to_anthropic_schema "json_*"    # Anthropic tool format
registry_to_openapi "lib/validation.sh"  # Full OpenAPI spec
registry_export_all "tools.json"         # Export all schemas
```

#### 2.3 Docstring Standards
```bash
# Standard function documentation format
# @name: json_object
# @description: Create a JSON object from key=value pairs
# @param key_values: string[] - Key=value pairs (type hints: :number, :bool)
# @returns: string - JSON object
# @example: json_object "name=John" "age:number=30"
# @category: json
# @since: v1.0
```

#### 2.4 Live Registry Server
- MCP tool exposure with auto-generated schemas
- Dynamic function discovery
- Version-aware schema caching

### Success Metrics
- [ ] 100% of exported functions have valid schemas
- [ ] Schema generation < 5 seconds for full library
- [ ] OpenAI/Anthropic format compatibility verified
- [ ] MCP integration tested with Claude

---

## Phase 3: Vector Database & RAG Support (v8.2)

**Priority**: HIGH | **Consensus Rank**: #3

### Rationale
Long-term memory and retrieval-augmented generation are essential for effective AI agents. MAINFRAME's AWM provides session memory but lacks semantic search and persistent knowledge retrieval.

### Deliverables

#### 3.1 Embedding Generation (`lib/embeddings.sh`)
```bash
# Generate embeddings for text
embed_text "content" "openai"            # Via OpenAI API
embed_text "content" "ollama"            # Via local Ollama
embed_batch "file.txt" "openai"          # Batch embedding
embed_similarity "$vec1" "$vec2"          # Cosine similarity
```

#### 3.2 Vector Database Wrappers (`lib/vectordb.sh`)
```bash
# Universal vector DB interface
vectordb_init "chromadb" "http://localhost:8000"
vectordb_upsert "$collection" "$id" "$text" "$embedding"
vectordb_search "$collection" "$query" --top-k 5
vectordb_delete "$collection" "$id"
```

#### 3.3 Supported Backends
- ChromaDB (primary, local-first)
- Pinecone (cloud)
- Weaviate (self-hosted)
- Qdrant (lightweight)
- SQLite-vec (zero dependency fallback)

#### 3.4 RAG Pipeline (`lib/rag.sh`)
```bash
# End-to-end RAG operations
rag_ingest "documents/" "my_collection"  # Ingest documents
rag_query "What is X?" --collection "my_collection"
rag_augment_prompt "$prompt" "$context"  # Inject context
rag_rerank "$results" "$query"           # Rerank results
```

### Success Metrics
- [ ] Support 5 vector database backends
- [ ] RAG query latency < 500ms (local)
- [ ] Document chunking with overlap
- [ ] Hybrid search (vector + BM25)

---

## Phase 4: Async & Concurrency Patterns (v8.3)

**Priority**: HIGH | **Consensus Rank**: #4

### Rationale
Bash is synchronous, but AI agents need non-blocking operations. Implementing futures/promises enables parallel tool execution without rewriting core logic.

### Deliverables

#### 4.1 Future/Promise Library (`lib/futures.sh`)
```bash
# Non-blocking execution
future_id=$(future_run "long_running_command")
future_status "$future_id"               # pending/running/done/failed
future_await "$future_id"                # Block until complete
future_result "$future_id"               # Get result
future_cancel "$future_id"               # Cancel execution
```

#### 4.2 Parallel Execution (`lib/parallel.sh`)
```bash
# Execute multiple commands in parallel
parallel_map "process_item" "${items[@]}"
parallel_race "cmd1" "cmd2" "cmd3"       # First to complete wins
parallel_all "cmd1" "cmd2" "cmd3"        # Wait for all
parallel_any "cmd1" "cmd2" "cmd3"        # Any success = success
```

#### 4.3 Non-Blocking I/O (`lib/async_io.sh`)
```bash
# Async network operations
async_http_get "$url" --callback "on_response"
async_file_read "$path" --callback "on_data"
async_wait_any                           # Event loop tick
async_run_loop                           # Main event loop
```

#### 4.4 Coordination Primitives
- Semaphores (`semaphore_acquire`, `semaphore_release`)
- Barriers (`barrier_wait`)
- Channels (`channel_send`, `channel_recv`)
- Mutex locks (`mutex_lock`, `mutex_unlock`)

### Success Metrics
- [ ] 10x throughput improvement for I/O-bound tasks
- [ ] Race condition-free coordination
- [ ] Graceful cancellation support
- [ ] Memory-efficient for 100+ concurrent operations

---

## Phase 5: Security Hardening v2 (v8.4)

**Priority**: HIGH | **Consensus Rank**: #5

### Rationale
As MAINFRAME agents gain autonomy, security becomes critical. Secrets management, sandboxing, and policy guardrails prevent catastrophic failures from hallucinated commands.

### Deliverables

#### 5.1 Secrets Management (`lib/secrets.sh`)
```bash
# Secure secret retrieval
secret_get "API_KEY"                     # Priority: env > .env > vault
secret_set "API_KEY" "value" --backend vault
secret_rotate "API_KEY"                  # Rotate with audit
secret_list --backend aws                # List from AWS SM
```

#### 5.2 Supported Secret Backends
- Environment variables (default)
- `.env` files (encrypted at rest)
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- 1Password CLI

#### 5.3 Sandboxing (`lib/sandbox.sh`)
```bash
# Safe execution environment
sandbox_exec "rm -rf /tmp/test"          # Sandboxed execution
sandbox_dry_run "dangerous_command"      # Preview only
sandbox_allow "write:/tmp/*"             # Grant permission
sandbox_deny "network:*"                 # Block network
```

#### 5.4 Policy Guardrails (`lib/policy.sh`)
```bash
# Policy-as-code enforcement
policy_check "destructive_action" "$agent_id"
policy_load "/etc/mainframe/policy.yaml"
policy_audit "$action" "$result"         # Audit log
policy_require_approval "$action"        # Human-in-loop
```

#### 5.5 Dry Run Mode
- Global `AGENT_DRY_RUN=1` flag
- All destructive operations return preview
- Configurable action allowlists

### Success Metrics
- [ ] Zero plaintext secrets in memory
- [ ] Policy violations blocked 100%
- [ ] Audit log for all sensitive operations
- [ ] Sandbox escape prevention verified

---

## Phase 6: State Management (v8.5)

**Priority**: MEDIUM | **Consensus Rank**: #6

### Rationale
Agents need persistent context across function calls and sessions. Passing variables is fragile; a proper state object pattern is needed.

### Deliverables

#### 6.1 Context Object Pattern (`lib/context.sh`)
```bash
# Agent state management
ctx_init "agent-session-123"             # Initialize context
ctx_set "current_task" "research"        # Set state
ctx_get "current_task"                   # Get state
ctx_save                                 # Persist to disk
ctx_restore "agent-session-123"          # Restore from disk
```

#### 6.2 State Serialization
```bash
# Serialize complex state
state_snapshot "$ctx_id"                 # Full state dump
state_diff "$ctx_id" "$prev_snapshot"    # State diff
state_rollback "$ctx_id" "$snapshot"     # Rollback to point
state_export "$ctx_id" "state.json"      # Export for debugging
```

#### 6.3 Cross-Session Memory
- Automatic state persistence on exit
- Recovery on crash/restart
- State versioning with history
- Merge strategies for concurrent access

#### 6.4 Integration with AWM
- Bridge to existing AWM tier system
- Hot → Warm → Cold migration
- Semantic compression for old state

### Success Metrics
- [ ] State survives process restart
- [ ] < 10ms state access latency
- [ ] Conflict resolution for concurrent writes
- [ ] Integration with AWM tiers

---

## Phase 7: Observability & Tracing (v8.6)

**Priority**: MEDIUM | **Consensus Rank**: #7

### Rationale
Debugging complex agent behavior in bash is difficult. OpenTelemetry integration enables modern observability with traces, metrics, and structured logs.

### Deliverables

#### 7.1 Structured Logging (`lib/structured_log.sh`)
```bash
# JSON-formatted logging
slog_info "Processing task" task_id="123" duration_ms=50
slog_error "Failed to connect" error="timeout" retry=3
slog_set_level "DEBUG"                   # Set log level
slog_output "/var/log/agent.jsonl"       # Output destination
```

#### 7.2 OpenTelemetry Integration (`lib/otel.sh`)
```bash
# Distributed tracing
otel_trace_start "process_request"       # Start span
otel_trace_add_event "queried_db"        # Add event
otel_trace_set_attribute "user_id" "123" # Add attribute
otel_trace_end                           # End span
otel_export "jaeger"                     # Export to backend
```

#### 7.3 Metrics Collection (`lib/metrics.sh`)
```bash
# Prometheus-compatible metrics
metrics_counter_inc "requests_total"
metrics_gauge_set "active_agents" 5
metrics_histogram_observe "response_time" 0.234
metrics_export                           # Prometheus format
```

#### 7.4 Crash Dump Integration
- Automatic state dump on crash
- Stack trace with variable values
- Integration with `forensics.sh`
- Remote crash reporting (opt-in)

### Success Metrics
- [ ] Trace propagation across function calls
- [ ] Export to Jaeger/Zipkin/Grafana
- [ ] Prometheus metrics endpoint
- [ ] Crash dumps with full context

---

## Phase 8: Developer Experience v2 (v9.0)

**Priority**: MEDIUM | **Consensus Rank**: #8

### Rationale
Adoption depends on DX. A CLI scaffolding tool, interactive debugger, and enhanced IDE support will accelerate developer productivity.

### Deliverables

#### 8.1 CLI Scaffolding Tool
```bash
mainframe new agent my-agent             # Scaffold agent project
mainframe new tool my-tool               # Scaffold tool
mainframe new workflow my-workflow       # Scaffold workflow
mainframe generate schema lib/mylib.sh   # Generate schemas
mainframe doctor                         # Health check
```

#### 8.2 Interactive Debugger
```bash
# Step-through debugging
export MAINFRAME_DEBUG=1
mainframe debug my-agent.sh              # Launch debugger
# Commands: step, next, continue, break, watch, print
```

#### 8.3 IDE Integration
- VS Code extension with autocomplete
- Neovim plugin (beyond current LSP)
- JetBrains plugin
- Syntax highlighting for MAINFRAME patterns

#### 8.4 Documentation Generator
```bash
mainframe docs generate                  # Generate from source
mainframe docs serve                     # Local doc server
mainframe docs search "json"             # Search docs
```

### Success Metrics
- [ ] New agent scaffold in < 30 seconds
- [ ] Debugger step-through working
- [ ] VS Code extension with 50+ completions
- [ ] Auto-generated API docs

---

## Phase 9: Enterprise Features (v9.5)

**Priority**: LOWER | **Consensus Rank**: #9

### Rationale
Enterprise adoption requires RBAC, audit logging, and compliance features. These are critical for production but secondary to core functionality.

### Deliverables

#### 9.1 Role-Based Access Control (`lib/rbac.sh`)
```bash
# Access control
rbac_define_role "agent-reader" "read:*"
rbac_assign_role "$agent_id" "agent-reader"
rbac_check_permission "$agent_id" "write:secrets"
rbac_audit_access "$agent_id" "$resource"
```

#### 9.2 Audit Logging (`lib/audit.sh`)
```bash
# Compliance audit trail
audit_log "$action" "$actor" "$resource" "$result"
audit_query --actor "$agent_id" --since "2026-01-01"
audit_export "audit.csv" --format csv
audit_sign "$log_file"                   # Cryptographic signature
```

#### 9.3 Compliance Frameworks
- SOC 2 audit trail support
- GDPR data handling hooks
- HIPAA PHI protection markers
- Custom compliance policies

#### 9.4 Multi-Tenancy
- Tenant isolation
- Resource quotas
- Cross-tenant audit
- Tenant-specific policies

### Success Metrics
- [ ] RBAC prevents unauthorized access 100%
- [ ] Audit logs tamper-evident
- [ ] SOC 2 controls documented
- [ ] Multi-tenant isolation verified

---

## Phase 10: Edge Deployment (v10.0)

**Priority**: LOWER | **Consensus Rank**: #10

### Rationale
Edge deployment enables MAINFRAME agents on constrained devices. This is a specialization step after core functionality is complete.

### Deliverables

#### 10.1 Static Binary Builder
```bash
mainframe build static my-agent.sh       # Create static binary
mainframe build minimal my-agent.sh      # Minimal deps only
mainframe build --target arm64           # Cross-compile
```

#### 10.2 Minimal Container Images
```dockerfile
# Ultra-minimal MAINFRAME container
FROM mainframe/runtime:minimal
COPY my-agent.sh /agent/
ENTRYPOINT ["mainframe", "run", "/agent/my-agent.sh"]
# Result: < 20MB image
```

#### 10.3 Edge Runtime
- ARM64/ARM32 support
- Reduced memory footprint (< 64MB)
- Offline operation mode
- Local-only LLM support (Ollama)

#### 10.4 Distribution
- apt/yum packages
- Homebrew formula
- Single curl install
- Snap/Flatpak packages

### Success Metrics
- [ ] Static binary < 5MB
- [ ] Container image < 20MB
- [ ] ARM64 support verified
- [ ] Works offline with local LLM

---

## Implementation Timeline

```
2026 Q1: Phase 1-2 (LLM Integration, Tool Registry)
2026 Q2: Phase 3-4 (Vector DB, Async Patterns)
2026 Q3: Phase 5-6 (Security v2, State Management)
2026 Q4: Phase 7-8 (Observability, DX v2)
2027 Q1: Phase 9-10 (Enterprise, Edge)
```

---

## Resource Requirements

| Phase | Libraries | Functions (Est.) | Tests (Est.) |
|-------|-----------|------------------|--------------|
| 1 | 4 | 80 | 200 |
| 2 | 2 | 40 | 100 |
| 3 | 3 | 60 | 150 |
| 4 | 4 | 100 | 250 |
| 5 | 4 | 80 | 200 |
| 6 | 2 | 40 | 100 |
| 7 | 3 | 60 | 150 |
| 8 | 2 | 40 | 100 |
| 9 | 3 | 60 | 150 |
| 10 | 2 | 40 | 100 |
| **Total** | **29** | **600** | **1,500** |

**End State**: ~5,100 functions | 164 libraries | 11,800+ tests

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Bash performance limits | Focus on I/O optimization, use subprocesses for CPU-intensive work |
| LLM API changes | Abstract provider layer, version-pinned schemas |
| Security vulnerabilities | Third-party security audit at Phase 5 completion |
| Adoption challenges | Strong documentation, example agents, community building |
| Scope creep | Strict phase gates, MVP per phase |

---

## Council Participants

This roadmap was synthesized from multi-AI review:

- **Grok (xAI)**: Emphasized LLM integration, resilience patterns, ecosystem bridges
- **Gemini (Google)**: Stressed security, niche focus, observability
- **GLM 4.7 (Z.AI)**: Prioritized async patterns, tool registry, "OS vs Library" mindset

**Key Consensus**: Transform MAINFRAME from "A Library" to "An Agent Runtime"

---

## Next Steps

1. Validate roadmap with community feedback
2. Create GitHub milestones for each phase
3. Begin Phase 1 implementation (LLM Integration Core)
4. Establish monthly progress reviews

---

*Generated: February 1, 2026*
*Review Cycle: Quarterly*
*Maintainer: MAINFRAME Core Team*

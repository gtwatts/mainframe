# MAINFRAME Roadmap

> The AI-Native Bash Runtime - v7.3

This roadmap outlines planned features and improvements for MAINFRAME. Items are organized by priority and status.

**Current Stats**: 4,350+ functions | 129 libraries | 9,870+ tests | Pure Bash + Bindings

---

## In Progress

### v7.3 - Advanced Orchestration (Current)

- [x] **Function Discovery CLI** (implemented)
  - [x] `mainframe fzf` - Interactive fuzzy search via fzf
  - [x] `mainframe fzf <library>` - Filter by library
  - [x] `mainframe explore` - TUI browser via dialog/whiptail
  - [x] Preview pane with function signatures
- [x] **Security hardening of eval sites** (8 critical, 4 high, 3 medium fixed)
  - [x] events.sh - Callback validation, subprocess isolation
  - [x] pipe.sh - Command validation, pattern blocking
  - [x] streams.sh - Expression subprocess isolation
  - [x] testing.sh - Variable/function name validation, printf -v
  - [x] idempotent.sh - bash -c isolation for check commands
- [x] **TOCTOU race condition fixes** in atomic operations
  - [x] ensure_line - flock-based atomic check-and-append
  - [x] ensure_symlink - temp-link + rename pattern
  - [x] ensure_file - temp-file + atomic rename
- [x] **Telemetry System** (`lib/telemetry.sh`)
  - [x] Opt-in with `MAINFRAME_TELEMETRY=1`
  - [x] Local aggregation to `~/.mainframe/telemetry/`
  - [x] Functions: telemetry_enabled, telemetry_init, telemetry_track, telemetry_flush, telemetry_report
  - [x] No PII collection, privacy-first design
- [x] **New ext/ Libraries** (6 libraries, 62 functions)
  - [x] `ext/go.sh` - Go project analysis (10 functions)
  - [x] `ext/rust.sh` - Rust/Cargo project analysis (10 functions)
  - [x] `ext/terraform.sh` - Terraform CLI wrapper (12 functions)
  - [x] `ext/aws.sh` - AWS CLI wrapper with structured output (10 functions)
  - [x] `ext/gcp.sh` - GCP CLI wrapper with gsutil fallback (10 functions)
  - [x] All USOP-compliant with comprehensive tests
- [ ] Test coverage expansion (52.3% → 80% target) - 9,600+ tests (in progress)
- [ ] Distributed task scheduling across multiple hosts
- [ ] Agent capability negotiation protocol
- [x] **Language Bindings** (`bindings/`)
  - [x] Python package (`pip install mainframe-bash`) - 126 tests
  - [x] Node.js/Bun package (`npm install mainframe-bash`) - 142 tests
  - [x] Subprocess wrapper pattern with USOP JSON parsing
  - [x] Full type hints (Python) and TypeScript definitions
- [ ] Orchestration metrics and dashboards

---

## Planned

### Additional Libraries

**Priority: Low**

- `ansible.sh` - Ansible integration

### Testing Improvements

**Priority: Medium**

- Property-based testing with bash
- Mutation testing for coverage gaps
- Performance regression testing
- Automated benchmark tracking

### Documentation

**Priority: Low**

- Video tutorials
- Interactive playground (WebAssembly bash)
- More AI agent integration examples
- AWM usage patterns cookbook

---

## Completed

### v7.2 - Multi-Agent Team Orchestration

**Major milestone: Complete orchestration system for coordinated agent teams**

- [x] **Multi-Agent Orchestration** (`lib/orchestrate.sh`)
  - [x] Team lifecycle management (`orch_team_register`, `orch_team_dissolve`)
  - [x] Agent spawning with TMUX windows (`orch_agent_spawn`, `orch_agent_terminate`)
  - [x] Sub-agent delegation with limits (`orch_subagent_spawn`, `orch_subagent_list`)
  - [x] Task distribution with priority queues (`orch_task_assign`, `orch_task_complete`)
  - [x] Redis pub/sub for real-time coordination
  - [x] File-based fallback when Redis unavailable
  - [x] USOP v4 message protocol (`orch_message_create`, `orch_message_send`)
  - [x] Health monitoring with heartbeats (`orch_agent_heartbeat`, `orch_agent_healthy`)
  - [x] Stale agent pruning (`orch_prune_stale`)
  - [x] Failed agent recovery with task re-queuing (`orch_agent_recover`)
  - [x] Discovery broadcasting for knowledge sharing
  - [x] Graceful shutdown with cleanup (`orch_shutdown`)
- [x] **Predefined Team Types**: default, research, implementation, review, testing
- [x] **Agent Status Tracking**: pending, initializing, ready, busy, blocked, completed, failed, terminated
- [x] **Task Status Tracking**: queued, assigned, running, completed, failed, cancelled
- [x] 80 exported functions and constants
- [x] Full documentation in `docs/ORCHESTRATION.md`

### v7.1 - Security Hardening

- [x] **Capability-based security model** (`lib/capability.sh`)
  - [x] Capability token format: `cap://domain/action/resource`
  - [x] Grant, revoke, and check capabilities
  - [x] Wildcard pattern matching
  - [x] Capability profiles: minimal, readonly, developer, network, admin
  - [x] Guarded operations: `cap_read_file`, `cap_write_file`, `cap_exec`, `cap_env_get`
  - [x] Audit logging with JSON export
  - [x] Capability delegation for agent handoffs
  - [x] 38 unit tests

### v6.1 - Multi-Agent Coordination

**Major milestone: Infinite agent memory with tiered storage and inter-agent protocols**

- [x] **AWM v2 - Infinite Memory Architecture** (`awm_*.sh`)
  - [x] Storage abstraction layer (`awm_storage.sh`) - Unified interface for file/Redis/ChromaDB
  - [x] Auto-detection with graceful fallback (no dependencies required)
  - [x] Context streaming engine (`awm_stream.sh`) - Prevent context overflow
  - [x] Memory pointer system - Store large data, pass references (7x token reduction)
  - [x] Semantic chunking for code, prose, JSON, markdown
  - [x] Dynamic token budget based on model detection
  - [x] Pre-rot threshold management (compress at 75% capacity)
- [x] **Agent Communication Protocol** (`awm_protocol.sh`)
  - [x] USOP v4 message envelope for agent-to-agent messaging
  - [x] Agent cards for capability discovery
  - [x] Message types: request, response, discovery, handoff, heartbeat
  - [x] contextId for session continuity across agent boundaries
  - [x] Handoff protocol for sub-agent delegation with context inheritance
- [x] **Tiered Memory Manager** (`awm_tiers.sh`)
  - [x] Hot tier (in-memory, fastest)
  - [x] Warm tier (file/Redis, 1hr TTL)
  - [x] Cold tier (persistent archive with semantic search)
  - [x] Automatic promotion/eviction based on access patterns
  - [x] Importance-based retention (critical items never evicted)
- [x] 50 new unit tests for AWM v2 components

### v6.0 - Agent Working Memory

**Major milestone: Persistent memory for AI agents outside context window**

- [x] **Agent Working Memory (AWM)** - Full external memory system (`awm.sh`)
  - [x] Session lifecycle management (`awm_init`, `awm_resume`, `awm_close`)
  - [x] Key-value checkpoints (`awm_checkpoint`, `awm_get`)
  - [x] Discovery logging (`awm_discovery`, `awm_list_discoveries`)
  - [x] Sub-agent inheritance model (`awm_context_for`)
  - [x] Namespace isolation for concurrent agents
  - [x] Token budget estimation
  - [x] Automatic compression of old entries
  - [x] Session summary generation (`awm_summary`)
- [x] **bURL library** - AI-native HTTP client (`burl.sh`)
  - [x] Automatic retry with exponential backoff
  - [x] USOP-formatted responses
  - [x] Request/response logging
  - [x] Header management
- [x] **MCP Server** - Model Context Protocol integration (`mcp/`)
  - [x] Direct function exposure to AI agents
  - [x] Structured JSON request/response
  - [x] Function metadata and documentation via MCP
  - [x] Integration with Claude, GPT, and LLM tooling ecosystems
- [x] **LSP Server** - Language Server Protocol support (`lsp/`)
  - [x] IDE integration (VS Code, Neovim, etc.)
  - [x] Function completion and documentation
  - [x] Signature help and hover info
- [x] **Bun package manager support** (`bun.sh`)
  - [x] Bun detection and version checking
  - [x] Package management wrappers
  - [x] Script execution helpers
- [x] **Agent execution library** (`agent.sh`)
  - [x] Agent spawn primitives
  - [x] Execution context management
  - [x] Retry with backoff
- [x] CI/CD working on all platforms (Linux, macOS, Windows WSL)
- [x] 117 libraries (up from 114)
- [x] 4,003 functions (up from 3,400+)
- [x] 6,538 tests (up from 5,500+)

### v5.0 - AI Agent Runtime

- [x] Agent Safety library (`agent_safety.sh`)
- [x] Agent Communication library (`agent_comm.sh`)
- [x] USOP - Universal Structured Output Protocol
- [x] Idempotent operations (`ensure_*` functions)
- [x] Atomic file operations with rollback
- [x] Memoization/caching (`cache.sh`)
- [x] Lazy loading engine
- [x] Context budget management (`context.sh`)
- [x] Diff/patch operations for surgical editing (`diff.sh`)

### v4.0 - Language Analysis

- [x] TypeScript analysis (`typescript.sh`)
  - [x] Import graph analysis
  - [x] Circular dependency detection
  - [x] Breaking change detection
  - [x] Bundle size estimation
- [x] Python analysis (`python.sh`)
  - [x] Import analysis
  - [x] Framework detection
  - [x] Dependency management
  - [x] Code metrics

### v3.0 - AI Optimization

- [x] Idempotent operations library (`idempotent.sh`)
- [x] Atomic operations library (`atomic.sh`)
- [x] Observability/tracing library (`observe.sh`)
- [x] Project detection library (`project.sh`)
- [x] Design-by-Contract library (`contract.sh`)
- [x] Performance/feature gates library (`perf.sh`)
- [x] Network scanning library (`netscan.sh`)
- [x] Parser library (`parsers.sh`)

### v2.0 - Extended Libraries

- [x] DateTime operations (`datetime.sh`)
- [x] HTTP client - pure bash (`http.sh`)
- [x] CSV parsing (`csv.sh`)
- [x] Git helpers (`git.sh`)
- [x] Cryptography (`crypto.sh`)
- [x] Process management (`proc.sh`)
- [x] Path manipulation (`path.sh`)
- [x] Validation & sanitization (`validation.sh`)
- [x] Environment management (`env.sh`)
- [x] Docker/Compose helpers (`docker.sh`)

### v1.0 - Core Libraries

- [x] String operations (`pure-string.sh`)
- [x] Array operations (`pure-array.sh`)
- [x] JSON generation (`json.sh`)
- [x] File operations (`pure-file.sh`)
- [x] ANSI colors (`ansi.sh`)
- [x] Logging (`log.sh`)
- [x] CLI utilities (`cli.sh`)

---

## Contributing

Have ideas for the roadmap?

- **[Discussions](https://github.com/gtwatts/mainframe/discussions)** - Share ideas
- **[Feature Requests](https://github.com/gtwatts/mainframe/issues/new?template=feature_request.yml)** - Formal proposals

---

*Last updated: February 2026*

# MAINFRAME Roadmap

> The AI-Native Bash Runtime - v6.0

This roadmap outlines planned features and improvements for MAINFRAME. Items are organized by priority and status.

**Current Stats**: 4,003 functions | 117 libraries | 6,538 tests | Pure Bash

---

## In Progress

### v6.1 - Multi-Agent Coordination

- [ ] Formalized message passing protocol between concurrent agents
- [ ] AWM namespace-based collaborative task execution
- [ ] Agent handoff primitives for long-running tasks
- [ ] Shared discovery broadcasting

### Security Hardening

- [ ] Security audit of remaining `eval` sites
- [ ] TOCTOU race condition fixes in atomic operations
- [ ] Capability-based security model (fine-grained permissions)

---

## Planned

### Semantic Memory Layer

**Priority: High**

Integration with vector databases for semantic search over AWM session history.

Features:
- Semantic search over past discoveries
- Context-aware retrieval of relevant session history
- Automatic summarization of session patterns
- Integration with ChromaDB/Qdrant/Pinecone

### Function Discovery CLI

**Priority: Medium**

Interactive fuzzy finder for exploring available functions.

```bash
# Proposed commands
mainframe fzf              # Interactive fuzzy search all functions
mainframe fzf json         # Fuzzy search within json.sh
mainframe fzf --preview    # Show function signature and docs
mainframe explore          # TUI for browsing libraries
```

Features:
- fzf-based interactive search
- Preview pane with function signature and examples
- Filter by library, category, or keyword
- Copy function name or usage example to clipboard

### Telemetry & Analytics

**Priority: Low**

Opt-in telemetry to understand function usage patterns and guide development.

Features:
- Track which functions are called most frequently
- Identify unused or underutilized functions
- Surface common error patterns
- Guide deprecation decisions
- Completely opt-in with `MAINFRAME_TELEMETRY=1`

Privacy:
- No PII collection
- Local aggregation option
- Anonymous usage stats only
- Open-source telemetry implementation

---

## Future Considerations

### Language Bindings

- Python bindings (`pip install mainframe-bash`)
- Node.js bindings (`npm install mainframe-bash`)
- Direct function calls without subprocess overhead

### Additional Libraries

- `aws.sh` - AWS CLI wrapper with structured output
- `gcp.sh` - GCP CLI wrapper
- `terraform.sh` - Terraform workflow helpers
- `ansible.sh` - Ansible integration
- `go.sh` - Go project analysis (like typescript.sh/python.sh)
- `rust.sh` - Rust project analysis

### Testing Improvements

- Property-based testing with bash
- Mutation testing for coverage gaps
- Performance regression testing
- Automated benchmark tracking

### Documentation

- Video tutorials
- Interactive playground (WebAssembly bash)
- More AI agent integration examples
- AWM usage patterns cookbook

---

## Completed

### v6.0 - Agent Working Memory (Current)

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

*Last updated: January 2026*

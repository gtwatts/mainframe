# MAINFRAME Roadmap

> The AI-Native Bash Runtime

This roadmap outlines planned features and improvements for MAINFRAME. Items are organized by priority and status.

---

## In Progress

### v5.1 - Agent Runtime Hardening

- [ ] Security audit of remaining `eval` sites
- [ ] TOCTOU race condition fixes in atomic operations
- [ ] Performance optimization for subshell-heavy functions

---

## Planned

### MCP Server Integration

**Priority: High**

An MCP (Model Context Protocol) server that exposes MAINFRAME functions directly to AI agents, reducing the source/function-call friction.

Benefits:
- AI agents can call MAINFRAME functions without sourcing bash files
- Structured JSON request/response built-in
- Better integration with Claude, GPT, and other LLM tooling ecosystems
- Function metadata and documentation exposed via MCP

```
# Proposed usage
mcp__mainframe__json_object(key="value", typed="number:42")
mcp__mainframe__ensure_dir(path="/app/data")
mcp__mainframe__validate_path_safe(path="/user/input", base="/allowed")
```

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

**Priority: Medium**

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

### Testing Improvements

- Property-based testing with bash
- Mutation testing for coverage gaps
- Performance regression testing

### Documentation

- Video tutorials
- Interactive playground (WebAssembly bash)
- More AI agent integration examples

---

## Completed

### v5.0 - AI Agent Runtime (Current)

- [x] Agent Safety library (`agent_safety.sh`)
- [x] Agent Communication library (`agent_comm.sh`)
- [x] USOP - Universal Structured Output Protocol
- [x] Idempotent operations (`ensure_*` functions)
- [x] Atomic file operations
- [x] Memoization/caching
- [x] Lazy loading engine

### v4.0 - Language Analysis

- [x] TypeScript analysis (`typescript.sh`)
- [x] Python analysis (`python.sh`)

### v3.0 - AI Optimization

- [x] Idempotent operations library
- [x] Atomic operations library
- [x] Observability/tracing library
- [x] Project detection library
- [x] Design-by-Contract library

### v2.0 - Extended Libraries

- [x] DateTime operations
- [x] HTTP client (pure bash)
- [x] CSV parsing
- [x] Git helpers
- [x] Cryptography
- [x] Process management
- [x] Path manipulation
- [x] Validation & sanitization
- [x] Environment management
- [x] Docker/Compose helpers

---

## Contributing

Have ideas for the roadmap? 

- **[Discussions](https://github.com/gtwatts/mainframe/discussions)** - Share ideas
- **[Feature Requests](https://github.com/gtwatts/mainframe/issues/new?template=feature_request.yml)** - Formal proposals

---

*Last updated: January 2026*

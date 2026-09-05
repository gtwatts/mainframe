# Support

## Getting Help

### Documentation

- **[README](../README.md)** - Quick start and overview
- **[INSTALL.md](../INSTALL.md)** - Detailed installation guide
- **[FUNCTIONS.json](../FUNCTIONS.json)** - Generated function and library inventory
- **[CHEATSHEET.md](../CHEATSHEET.md)** - Human-oriented function reference
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - How to contribute
- **[Documentation index](../docs/README.md)** - Versioned guides and evidence

### Community

- **[GitHub Discussions](https://github.com/gtwatts/mainframe/discussions)** - Ask questions, share ideas
- **[Issues](https://github.com/gtwatts/mainframe/issues)** - Report bugs, request features

### Quick Answers

| Question | Resource |
|----------|----------|
| How do I install MAINFRAME? | [Quick Install](../README.md#quick-install) |
| What functions are available? | [CHEATSHEET.md](../CHEATSHEET.md) |
| How do I use a specific function? | Search CHEATSHEET.md or ask in Discussions |
| Found a bug? | [Open an Issue](https://github.com/gtwatts/mainframe/issues/new?template=bug_report.yml) |
| Have a feature idea? | [Feature Request](https://github.com/gtwatts/mainframe/issues/new?template=feature_request.yml) |
| Want to contribute? | [CONTRIBUTING.md](../CONTRIBUTING.md) |

## For AI Agent Developers

If you're building autonomous systems that use MAINFRAME:

1. **Reviewed routes** - Start with the [MCP interface](../mcp/README.md) and [host onboarding](../docs/ONBOARDING.md); check exact coverage before claiming enforcement
2. **Structured Output** - Follow the selected interface's documented input and result contract
3. **Recovery** - Test interrupted work and retry behavior for the exact operation
4. **Validation** - Always validate untrusted input before use
5. **Working Memory** - Use AWM (Agent Working Memory) for persistent state across sessions

## Response Time

| Channel | Expected Response |
|---------|-------------------|
| Discussions | Community-driven; response time varies |
| Bug Reports | Maintainer triage as capacity allows; include a minimal reproduction |
| Security Issues | See [SECURITY.md](../SECURITY.md) |

---

*Building for a safe and accurate agentic future.*

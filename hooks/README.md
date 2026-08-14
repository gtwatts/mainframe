# MAINFRAME hooks

`agent-gateway.sh` is MAINFRAME's host-facing pre-tool policy hook. It reads a
Codex, Claude Code, GitHub Copilot CLI, or Gemini CLI payload from standard input
and applies the canonical destructive-command gate from
`lib/agent_safety.sh`.

For diagnostic payload checks, use the CLI entry point:

```bash
mainframe agent-hook --format auto
```

Do not place that diagnostic command directly in host configuration. Managed
Codex, Claude Code, Copilot, and Gemini hooks contain a commit-stable
`/bin/bash -p` bootstrap. `mainframe launch` supplies absolute, reviewed Bash,
a supported system/package-manager `jq`, the installed gateway and safety
policy, and a four-digest SHA-256 seal to the host process. Before every hook
call, the bootstrap verifies those four byte identities. Starting the host
directly without all five launch values makes the hook fail closed.

Safe and non-shell calls return `{}` with exit code 0. Denied or malformed
shell calls return exit code 2 with a reason on standard error. The supported
hosts interpret that result as a pre-execution denial.

Project activation, policy tiers, audit behavior, host schemas, and the threat
boundary are documented in [the Agent Gateway guide](../docs/AGENT_GATEWAY.md).
The seal detects straightforward sequential replacement after launch, but a
user-owned installation is not a sandbox or tamper-proof against a hostile
same-UID process. That threat requires an OS/root-protected installation or
separation with another user, a container, or a VM.

`dispatcher.sh` is retained for compatibility with the older generic hook
directories. It is not the enforcement entry point and should not be used as
a substitute for the managed privileged bootstrap in an AI host's pre-tool
configuration.

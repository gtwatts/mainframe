# MAINFRAME for Pi

Shell policy, reliable task checkpoints, and execution evidence for Pi.

MAINFRAME is a native Pi package. It checks shell commands before execution,
keeps explicit project progress across sessions, and shows whether the running
Pi session has the expected integration loaded.

**10.3.1 is a Pi-focused source build.** Local runtime verification is separate
from public immutable release certification and cross-platform support.

[![Pi checks](https://img.shields.io/github/actions/workflow/status/gtwatts/mainframe/pi.yml?branch=main&label=Pi%20checks)](https://github.com/gtwatts/mainframe/actions/workflows/pi.yml)

## Start with your installed Pi

From an installed MAINFRAME runtime:

```bash
mainframe version
mainframe setup --project .
mainframe setup --project . --proof
mainframe setup --project . --dry-run
```

These commands inspect the installation, exercise private temporary state, and
preview the exact Pi settings changes. After reviewing the preview, apply setup:

```bash
mainframe setup --project . --yes
```

Inside Pi:

```text
/reload
/mainframe doctor
```

See [installation and recovery](INSTALL.md) for source installation, runtime
verification, rollback, and removal.

## What Mainframe adds

**Shell policy.** Pi Bash calls pass through the verified classifier. Known
destructive commands are blocked with a reason. Reviewed function calls use
closed argument contracts, bounded execution, and correlated evidence. A
classification that matches no rule does not prove downstream effects are safe.

**Task continuity.** Pi explicitly saves and retrieves project checkpoints,
discoveries, progress, and handoffs through `mainframe_awm`. Memory is untrusted
reference data, never authorization. AWM holds task state; Pi session history
holds the conversation, and personal knowledge tools such as Obsidian keep
their own role.

**Visible readiness.** The `/mainframe` command and badge distinguish package
files from the integration loaded in Pi. A local verification receipt belongs
to the exact runtime and Mainframe files tested. Changed files require fresh
verification.

## Understand the status

Pi exposes seven Mainframe tools:

| Tool | Purpose |
| --- | --- |
| `mainframe_status` | Inspect the current runtime and integration |
| `mainframe_awm` | Save and recover explicit project task state |
| `mainframe_bash_safety_check` | Explain a command's policy classification without executing it |
| `mainframe_search` | Find optional toolbox functions |
| `mainframe_help` | Inspect a function's contract |
| `mainframe_exec` | Invoke a reviewed function, or request confirmation for a legacy function |
| `mainframe_install_commands` | Show installation and verification guidance |

Use Pi's ordinary coding tools for ordinary work. Before stopping a task, save
its progress, decisions, verification results, and next step through project
AWM. A new session retrieves that checkpoint explicitly. Concurrent writes can
return a conflict: re-read state and retry with a new request rather than assume
every parallel update succeeded. A recovered invocation does not replay lost
raw output; its durable outcome and a fresh read establish what happened.

| Check | What it establishes |
| --- | --- |
| `mainframe doctor` | Installation files, dependencies, and shell identity |
| `mainframe setup --project . --proof` | An isolated invocation, checkpoint round trip, and one policy canary |
| `mainframe status` | Offline Pi package and compatibility diagnosis |
| `/mainframe doctor` inside Pi | Integration and tools loaded in that session |
| `mainframe release readiness` | Checked-in publication evidence, separate from local operation |

## Scope

Pi is the only actively supported coding-agent integration. Codex, Claude Code,
Copilot, Gemini, Cursor, and other adapters are frozen compatibility material.
Use `mainframe legacy` for existing integrations and recovery.

The broad Bash catalog remains available for existing scripts and optional
discovery. New Pi workflows use the small reviewed execution surface. Function
count is not a readiness measure. Standalone MCP, LSP, language bindings, and
old orchestration are outside this release's active scope.

MAINFRAME is not an OS sandbox. The shell gate does not protect native Pi
`write`/`edit` tools, arbitrary extensions, hostile same-user processes, or
unobserved shell routes. See [security boundaries](SECURITY.md).

## Development

Requirements: Bash 4.4+, jq, Python 3.10+, Node.js suitable for your installed Pi,
and Git for a source checkout.

```bash
make test-deps
bash scripts/test-pi-core.sh
```

Core checks exercise shell policy, project memory, durable execution, Pi
integration contracts, and product commands. Verify the actual installed Pi
runtime separately before claiming local support.

For repeatable concurrency and crash-boundary testing in disposable state:

```bash
python3 -B scripts/dev/stress-durable-core.py "$PWD" --workers 8 --rounds 2
```

See the [initial local acceptance report](docs/testing/PI_LOCAL_ACCEPTANCE_2026-09-24.md)
for the recovery defect found in the first Pi-focused build, and the
[10.3.1 source validation](docs/testing/PI_10_3_1_SOURCE_VALIDATION_2026-09-24.md)
for the fixes, regression results, and installed acceptance requirements.
Passing source tests is not a substitute for testing the installed package.

- [Active scope and acceptance criteria](docs/PI_PRODUCT_PLAN.md)
- [Pi workflow](skills/pi/SKILL.md)
- [Task memory cookbook](docs/AWM_COOKBOOK.md)
- [Reviewed execution contracts](docs/STABLE_CORE.md)
- [Documentation index](docs/README.md)
- [Historical overview](docs/legacy/README-10.2.md)

Licensed under the [MIT License](LICENSE).

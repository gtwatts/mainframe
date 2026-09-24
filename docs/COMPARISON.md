# Why MAINFRAME for Pi

**Shell policy and explicit task continuity for your Pi sessions.**

MAINFRAME adds a local shell-policy check, durable project checkpoints,
optional reviewed shell helpers, and execution evidence to Pi. It does not
replace Pi's coding tools, permissions, conversation history, or your OS
isolation. Pi is the sole actively supported coding-agent integration.

## What it adds to Pi

- **Shell policy outside the prompt.** The loaded extension classifies Pi Bash
  calls using the verified shared policy and blocks configured destructive
  patterns. A missing or mismatched policy fails closed.
- **Task state outside the conversation.** Explicit AWM discoveries, progress,
  and handoffs can be retrieved by a fresh session. Memory is untrusted
  reference data, never authorization or an automatic transcript archive.
- **Optional reviewed helpers.** Search, inspect a function's contract, then
  use a bounded invocation when that function fits the task. Ordinary coding
  should continue through Pi's ordinary tools.
- **Evidence beyond files on disk.** Installation, configuration, resolution,
  loading, execution, and verification are different states. The in-session
  doctor reports the Pi process you are actually using.

These are mechanisms, not measured productivity improvements. MAINFRAME does
not claim to make a model smarter or establish a general speed, accuracy, or
token-saving advantage. Comparative outcomes require a published evaluation
with its environment and limitations. See the
[claims policy](CLAIMS_AND_BENCHMARKS.md).

## Where its protection stops

MAINFRAME is defense in depth. Its shell classifier is a bounded lexical
policy, not a complete interpreter or an OS sandbox. A `low` result means no
configured rule matched; it does not prove downstream commands are harmless.

The gate does not protect native Pi `write`/`edit` tools, arbitrary third-party
extensions, unobserved shell routes, or hostile processes running as the same
user. Keep Pi's native controls enabled. Use a container, VM, or restricted
account when code must not reach unrelated files, credentials, processes, or
networks. Consult the [security boundary](../SECURITY.md) before running
untrusted code.

## Evaluate it locally

Start from an installed MAINFRAME runtime with read-only inspection:

```bash
mainframe version
mainframe setup --project .
mainframe pi status --json
mainframe pi doctor
mainframe setup --project . --dry-run
```

Review the settings preview before a human applies setup with explicit
consent. Follow the [installation and recovery guide](../INSTALL.md), then
reload or restart Pi and run:

```text
/mainframe doctor
```

The external CLI does not start Pi and cannot establish what an existing
session loaded. A `LOCAL_VERIFIED` result is bound to the local runtime and
Mainframe files that were exercised, not a public-release or cross-platform
certificate. Changed files and old running sessions require fresh checks.
See [status meanings](../README.md#understand-the-status).

For optional helper discovery:

```bash
mainframe search 'create json object'
mainframe help json_object
```

Search and help are inspection paths, not prerequisites for every Pi command.
For a disposable invocation and checkpoint round trip, use:

```bash
mainframe setup --project . --proof
```

That proof creates private temporary state and removes it afterward; it does
not replace a real Pi session check. For task continuity, explicitly save a
checkpoint through `mainframe_awm`, then retrieve and verify it in a fresh
session. Record what succeeded and what remains instead of treating a saved
checkpoint as proof that the task is complete.

## When it fits

MAINFRAME is useful when you want an inspectable shell-policy layer and
explicit task handoffs in Pi, and are willing to verify the exact local
integration. It is not a substitute for isolation, human review, backups, or
Pi's own coding workflow.

Other-agent adapters and standalone MCP/LSP/binding material are frozen
compatibility references, not additional active products. The
[current integration matrix](INTEGRATION_MATRIX.md) separates Pi mechanisms
from historical certification; the [README scope](../README.md#scope) defines
the current support boundary.

Start with the [current Pi overview](../README.md#start-with-your-installed-pi).
Local operation and public immutable release availability are separate claims.

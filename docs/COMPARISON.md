# Why MAINFRAME

**Your coding agents may change. Your safety policy and working memory should
not have to start over each time.**

MAINFRAME is a user-owned local control layer for supported shell-capable
coding agents. It adds durable handoffs, pre-execution shell guardrails,
discoverable structured functions, and readiness evidence without replacing
the agent, the user's Bash or zsh workflow, or the host's native controls.

The shortest mental model is:

- **Seatbelt:** classify supported shell routes and deny configured destructive
  patterns before they execute.
- **Notebook:** preserve discoveries, checkpoints, progress, and bounded
  handoffs outside an agent conversation.
- **Toolbox:** let an agent search and invoke registered functions through a
  small structured surface instead of continually rebuilding shell glue.

MAINFRAME does not change a model's weights or reasoning ability. It improves
the operating environment available to that model.

## The gap MAINFRAME fills

Modern coding-agent hosts may already provide permissions, hooks, memory, or
an operating-system sandbox. Those features remain valuable and should stay
enabled. The practical problem is that their configuration, state, semantics,
and evidence are specific to each host.

MAINFRAME supplies one local layer the user can inspect and retain across the
supported hosts:

1. **A policy outside the prompt.** “Be careful” is advice. A supported native
   pre-tool hook can make a configured denial before the shell action runs.
2. **Memory outside the context window.** Agent Working Memory stores explicit
   project discoveries and handoffs in private local state that a fresh
   process can retrieve.
3. **An interface outside ad hoc shell text.** Registry search, help,
   structured results, and bounded invocation give agents a more predictable
   substrate than inventing every operation from scratch.
4. **Proof outside installation success.** Doctor, setup, protection status,
   compatibility manifests, and exact-archive evidence distinguish “files are
   present” from “this supported integration is ready.”

## How the layers differ

These layers solve different problems and are strongest together.

| Layer | Primary job | Durable cross-session handoff | Semantic shell guardrail | Host isolation |
|---|---|---:|---:|---:|
| Plain Bash or zsh | Execute commands as the user | Manual | No | No |
| Coding-agent native controls | Apply that host's permissions, hooks, memory, or sandbox | Host-specific | Host-specific | Host-specific |
| MAINFRAME | Carry user-owned policy, AWM, structured tools, and evidence across supported hosts | Yes | On explicitly supported and activated routes | No |
| Container, VM, or separate OS user | Bound filesystem, process, and network authority | No | No | Yes |

MAINFRAME is defense in depth. Use a container, VM, restricted account, and the
agent host's native sandbox when the workload needs an operating-system
boundary. MAINFRAME is not a boundary against malicious code or another
hostile process running as the same user.

## What “safer” means

For an explicitly onboarded, supported route, MAINFRAME can:

- normalize and classify a shell action through one generated policy;
- block configured high-risk and critical patterns before execution;
- fail closed when the policy, protected Bash, or required dependency cannot
  be authenticated;
- require a human terminal for MAINFRAME and Pi lifecycle mutations;
- preserve unrelated host configuration during activation and removal; and
- record bounded decision metadata without putting raw command text into the
  default Pi audit record.

It does **not** mean that every dangerous command is detectable, every shell
route is intercepted, a low-risk label proves a command is harmless, or a
same-user hostile process is contained. The exact security boundary is in
[SECURITY.md](../SECURITY.md).

## What “better” means

MAINFRAME does not claim that an underlying model becomes generally smarter,
faster, or more accurate. It gives supported agents better operational
conditions:

- explicit discoveries and decisions survive context loss;
- fresh sessions can resume from a bounded handoff;
- long tasks can checkpoint progress instead of reconstructing it from chat;
- registered functions provide inspectable help and structured output; and
- the same project memory and policy concepts remain available when the user
  changes supported agent hosts.

The deterministic harness proves these mechanisms execute. A real-provider
comparative study is still required before claiming a measured improvement in
agent outcomes. See [Agent Impact Evaluation](AGENT_IMPACT_EVALUATION.md) and
[Claims and Benchmarks](CLAIMS_AND_BENCHMARKS.md).

## Pi: the native first-party experience

Pi is MAINFRAME's most integrated current path. The first-party package adds a
focused tool surface, the `mainframe` skill and slash command, Agent Working
Memory, canonical Bash-policy classification, a protected Bash wrapper, and
transactional lifecycle management.

Start outside Pi with read-only diagnosis and a no-write preview:

```bash
mainframe pi status
mainframe pi doctor
mainframe pi install --dry-run
```

After reviewing the preview, a person may activate it from that external
terminal:

```bash
mainframe pi install --yes
```

Reload or restart Pi, then prove the live process rather than merely the files
on disk:

```text
/mainframe doctor
```

External `mainframe pi doctor` never starts Pi and cannot claim that a running
Pi process loaded the package. Compatibility is exact by MAINFRAME version, Pi
package and version, and platform; unknown combinations remain unverified. See
[Pi compatibility](COMPATIBILITY.md#pi-package) for the current
matrix.

## Other supported coding-agent hosts

MAINFRAME also has explicit-consent project onboarding and native shell-policy
adapters for OpenAI Codex, Claude Code, GitHub Copilot CLI, and Gemini CLI.
Discovery does not select a host or modify the project:

```bash
mainframe setup --project .
```

The report provides an exact dry-run command for each candidate. After a user
chooses and onboards one host, readiness remains independently inspectable:

```bash
mainframe protect status --project .
mainframe launch HOST --project . --dry-run
```

Support is versioned and route-specific. A host name in the repository is not
a universal claim about every client version, installation layout, platform,
or tool route. See the [integration matrix](INTEGRATION_MATRIX.md).

## A two-minute local evaluation

Start with the commands that cannot write project or agent configuration:

```bash
mainframe doctor
mainframe setup --project .
mainframe pi doctor                 # when Pi is installed
mainframe protect status --project .
```

Then inspect the two mechanisms that distinguish MAINFRAME from a raw shell:

```bash
mainframe search 'create json object'
mainframe help validate_path_safe

sid=$(mainframe awm init evaluation --namespace local-demo)
mainframe awm discovery --session "$sid" \
  'MAINFRAME handoff evaluation started' --importance high
mainframe awm summary --session "$sid"
```

The AWM commands intentionally create private local MAINFRAME state; the
doctor, setup, status, search, and help commands are inspection paths.

## When MAINFRAME is a good fit

Use MAINFRAME when:

- coding agents run commands on a real macOS or Linux workstation;
- work spans long sessions, context resets, or multiple supported agents;
- the user wants a reviewable policy in addition to a host's native controls;
- predictable structured shell functions reduce repeated glue code; or
- activation, readiness, and removal need explicit evidence.

Use stronger isolation instead when:

- the repository or generated code may be malicious;
- secrets or unrelated host data must be inaccessible by construction;
- arbitrary child processes must be contained; or
- the exact agent, version, platform, or execution route is not certified.

## The product promise

The defensible promise is not “MAINFRAME makes agents safe.” It is:

> **MAINFRAME helps users trust supported local coding agents with more work by
> giving those agents guardrails, continuity, structured tools, and proof.**

Installation availability and public release status are intentionally stated
in one place: [Install and prove it works](../README.md#install-and-prove-it-works).

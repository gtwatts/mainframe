# Enforced Agent Gateway

MAINFRAME's Agent Gateway gives supported coding-agent hosts one policy entry
point for shell commands. It runs before the host executes a shell tool,
classifies the command with MAINFRAME's canonical destructive-command rules,
and blocks denied calls with the host's pre-tool denial exit code.

## Activate it

Activation is explicit, project-scoped, merge-safe, and reversible:

```bash
mainframe activate codex --project . --enforce
mainframe activate claude-code --project . --enforce
mainframe activate copilot --project . --enforce
mainframe activate gemini --project . --enforce
```

Use `--dry-run` first to inspect the files that would change. Deactivation
removes only the exact MAINFRAME hook entries and the marked instruction block:

```bash
mainframe deactivate claude-code --project . --enforce
```

The generated configurations use the hosts' native project hook locations:

| Host | Event and shell matcher | Project file |
|---|---|---|
| OpenAI Codex | `PreToolUse` / `Bash` | `.codex/hooks.json` |
| Claude Code | `PreToolUse` / `Bash` | `.claude/settings.json` |
| GitHub Copilot CLI | `preToolUse` / `bash` | `.github/hooks/mainframe.json` |
| Gemini CLI | `BeforeTool` / `run_shell_command` | `.gemini/settings.json` |

The generated hook does not call `mainframe` or resolve a launcher from
`PATH`. Project configuration stores one machine-independent command shaped
like this:

```text
/bin/bash -p -c '<validate four paths and seal; invoke the bound gateway>' mainframe-agent-hook <format>
```

Here `mainframe-agent-hook` is Bash's `$0` label, not a command resolved from
`PATH`.

The system `/bin/bash` starts in privileged mode before consulting inherited
Bash startup state. The bootstrap accepts five launch values: absolute
`MAINFRAME_AGENT_BASH`, `MAINFRAME_AGENT_JQ`, `MAINFRAME_AGENT_GATEWAY`, and
`MAINFRAME_AGENT_SAFETY` paths, plus `MAINFRAME_AGENT_SEAL`. The seal contains
four lowercase SHA-256 digests in that order. The bootstrap replaces `PATH`
with the system path, hashes every bound file and compares it with the seal,
starts the bound Bash with `--noprofile --norc -p`, and normalizes every
gateway failure to the host's blocking exit code.

`mainframe launch <host>` resolves and validates those machine-local paths,
requires `jq` to come from a supported system or package-manager installation,
rejects project-controlled dependencies, computes the four-digest seal,
exports the five values only for the selected host process, and rechecks them
immediately before `exec`. Supported resolved `jq` locations are the system
paths, `/usr/local/bin`, Homebrew or Linuxbrew Cellar, and the Nix store. A
direct host start without all five values therefore fails closed when the
configured hook is invoked. Use `mainframe launch` for sessions intended to be
protected.

For `launch`, the public CLI also removes `BASH_ENV`, `ENV`, Node.js passive
loader/module-search variables, Perl startup/library variables, and every
`LD_*`/`DYLD_*` variable before loading runtime helpers. The launch library
repeats that scrub before sensitive helpers, Node-backed package
authentication, and host exec. This starts only after the initial `/bin/bash`
interpreter and its operating-system loader are running, so it cannot undo code
loaded before MAINFRAME's first instruction.

Inspect every adapter and its local dependencies without changing the project:

```bash
mainframe protect status --project .
# Or one adapter: mainframe protect status codex --project .
```

Status requires the exact generated hook object, the `/bin/bash -p` bootstrap,
an absolute Bash 4.4+ executable, a supported system/package-manager `jq`, and
the installed gateway and safety-policy files. It also reports the four-file
runtime seal. The generated hook has no MAINFRAME-on-`PATH` requirement. Status
exits nonzero when requested static enforcement is missing or invalid. It
cannot prove that an already-running host loaded the file.

These are project-scoped files and may be committed. Their command is stable
across machines, but every user must install MAINFRAME and start the host with
`mainframe launch` so the four local paths and seal are present. Otherwise the
configured hook intentionally fails closed. Coordinate before sharing the
configuration. For local-only protection, keep the hook changes in a local
checkout or worktree and do not commit them; always inspect `git status` after
activation.

Codex adds a separate trust gate: project hooks load only in a trusted
`.codex/` layer, and non-managed commands are skipped until their current hash
is reviewed. After activation, start Codex with `mainframe launch codex`, use
`/hooks` to review and trust the exact MAINFRAME entry, and then run a
disposable canary. Do not use a direct `codex` invocation for a session meant
to be protected.

## Policy

The default block tier is `medium`: critical, high-risk, and externally visible
or hard-to-reverse medium operations are denied. This includes destructive
filesystem patterns, force pushes, package publication, and service-schedule
mutation. To use a narrower policy, launch the host with `high` or `critical`:

```bash
mainframe launch claude-code --policy high
# Or: mainframe launch claude-code --policy critical
```

Valid tiers are `critical`, `high`, and `medium`. Invalid configuration fails
closed.

The gateway recognizes the native payload fields used by the supported hosts,
including Copilot's JSON-encoded `toolArgs`. It also rejects malformed JSON,
missing shell commands, unavailable `jq`, classifier errors, and audit-log
failures rather than silently allowing the call.

The v10.2 classifier is an ordered 43-rule lexical policy. Its JavaScript
distribution is a two-file contract: `security/gate-rules.json` declares the
input view for each regex and identifies the shipped
`security/gate-normalizer.mjs`, whose exported classifier must run before rule
matching. `scripts/export-gate-rules.py --verify` currently proves 183
Bash/JavaScript parity cases.

The runtime-mutation rule reserves MAINFRAME source updates, non-dry-run
release upgrades, explicit `--yes` operations, and Homebrew upgrade/uninstall
for a human terminal. Read-only status and upgrade dry-runs remain available to
the agent. This is a trust-preservation boundary: an agent cannot authorize a
replacement or removal of the policy runtime that is evaluating its commands.

A `low` classification means only that none of those lexical rules matched the
bounded normalized command. It does not prove that an invoked script, alias,
build tool, interpreter, network service, or other downstream effect is safe.
It is one gateway policy result, not a general authorization or containment
claim.

## Audit trail and privacy

Each successfully parsed and evaluated allow or deny decision is appended as
JSONL. Preflight failures such as an unsupported Bash, missing `jq`, malformed
JSON, or an audit path that cannot be initialized may terminate before a log
is available, so those denials may have no audit record. By default the file
is:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/mainframe/agent-gateway.jsonl
```

Set `MAINFRAME_AGENT_AUDIT_LOG` to choose another file. MAINFRAME creates the
file with mode `0600`, refuses a symbolic-link log target, and records only
decision metadata: host, event, tool, risk, rule, and decision. It does not log
the command text, because shell inputs can contain credentials or private data.
This is private local evidence for troubleshooting, not a tamper-proof or
transactional security ledger.

## Integrity boundary

The four-file seal catches straightforward sequential replacement after a
protected host has launched: if bound Bash, `jq`, the gateway, or its safety
policy bytes change, the next hook invocation fails closed before sourcing or
executing the changed file. The seal covers those four files only, not their
dynamic libraries or other transitive runtime dependencies. It does not turn a
user-owned MAINFRAME install into a sandbox or make it tamper-proof against a
hostile process with the same UID. Such a process can target the user-owned launcher, project hook
configuration, environment, or race a check and use. Hostile same-UID race
resistance requires an OS/root-protected installation or process separation
with a dedicated user, container, or VM.

Likewise, the launch-time passive-loader scrub protects only processes started
after the scrub. The initial interpreter/loader boundary precedes MAINFRAME
code and remains outside that guarantee.

## Diagnostic adapter probes without executing a command

The lower-level `mainframe agent-hook` command is useful for checking payload
parsing and policy behavior. It is a diagnostic adapter path through the CLI;
it does not reproduce the privileged host bootstrap, prove launch-time absolute
bindings, or show that a native host loaded the hook. It is not the hardened
host boundary.

The adapter only classifies its JSON input; it never executes the embedded
shell command. This probe should exit 2 and record a denied decision:

```bash
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"terraform destroy -auto-approve"}}' \
  | mainframe agent-hook --format claude
test "$?" -eq 2
```

A benign probe should emit `{}` and exit 0:

```bash
printf '%s' '{"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"git status --short"}}' \
  | mainframe agent-hook --format gemini
```

After activation, start the host with `mainframe launch`, inspect its hook UI or
diagnostics, and run a controlled canary in a disposable project. A
source-level configuration file does not by itself prove that the launched
host loaded it.

Use these evidence labels when reporting support:

| Level | Evidence |
|---|---|
| Configured | The exact native hook object is present and `mainframe protect status` is ready. |
| Adapter verified | A native-shaped synthetic payload reaches the installed gateway and is denied before any command runs. |
| Host discovered | The installed host reports that it loaded the hook. |
| Execution certified | A fixture model makes the installed host request a harmless sentinel command; the host reports denial, the private audit records it, and the sentinel never runs. |

The cross-platform repository gate currently proves **Adapter verified** for
Codex, Claude Code, Copilot CLI, and Gemini CLI from an installed release
archive. All four also have separate paired-control native-host certifiers.
Their CI jobs are configured to launch the pinned published CLIs against an
installed MAINFRAME archive on Linux and macOS and upload per-platform
evidence. Gemini uses first-party fake responses; Codex 0.146.0 uses a
loopback-only Responses fixture without an external model credential; Claude
Code 2.1.220 uses loopback Messages with one fixed synthetic bearer and no user
or real Anthropic credential; and Copilot 1.0.78 uses offline loopback Chat
Completions without a GitHub or provider credential. These proofs cover only
their exact pinned runtime paths, not desktop apps, npm launch paths excluded
by the evidence, GitHub.com agents, IDE extensions, or live-provider inference.

Run any native-host gate with:

```bash
npm ci --prefix scripts/dev/native-host \
  --ignore-scripts --no-audit --no-fund
scripts/dev/certify-native-host.sh gemini
scripts/dev/certify-native-host.sh codex
scripts/dev/certify-native-host.sh claude
scripts/dev/certify-native-host.sh copilot
```

These commands self-admit the current native process before provider-fixture
work. Darwin runs refuse Rosetta or mixed Apple-Silicon/x86 identity. The
selected Bash, Node runtime, and native host executable must contain the
admitted Mach-O or ELF architecture, must not be group- or other-writable, and
must retain the same pathname-byte binding through evidence generation. The
privileged gateway Bash and jq are admitted and rechecked independently using
the private read-only validator snapshot. This
does not prove physical Linux hardware, exclude virtualization, or isolate the
run from another process under the same local account.

The Codex certifier passes `--dangerously-bypass-hook-trust` only to automate
the already-vetted generated hook in its disposable workspace. That flag skips
Codex's persisted hook-trust requirement for the invocation; it does not
bypass MAINFRAME's deny decision or make unreviewed hooks safe. User activation
must still review and trust the exact MAINFRAME hook through Codex's `/hooks`
UI.

Codex 0.146.0's `--ignore-user-config` also suppresses the project
`.codex/hooks.json`. The certifier uses an empty isolated `CODEX_HOME` instead;
users must not expect MAINFRAME enforcement when launching Codex with that
flag.

Copilot prompt mode loads repository hooks only after the project is trusted.
Its certifier uses a fresh `COPILOT_HOME` containing only the exact disposable
project in `trustedFolders` and otherwise follows the default hook-loading path;
it does not force an internal hook feature flag. Users must complete Copilot's
normal project-trust workflow and run a controlled canary after activation.

Claude's certifier invokes the pinned optional-package native binary directly;
it does not certify npm postinstall, `.bin/claude`, or `cli-wrapper.cjs`. Print
mode disables Claude's workspace-trust verification, so interactive users must
still complete Claude's normal trust workflow and run a controlled canary.
The fixed synthetic bearer is accepted only by the loopback fixture; it is not
a user credential or proof of a hard network sandbox.

See [Native Host Execution Certification](NATIVE_HOST_CERTIFICATION.md) for
the paired control, enforced evidence schema, reproduction steps, and exact
limits. The Codex contract requires one control execution, zero protected
executions, and exactly one `codex / PreToolUse / Bash / high /
terraform-destroy / deny` audit tuple.
The Copilot contract requires the same execution counts and exactly one
`copilot / PreToolUse / bash / high / terraform-destroy / deny` tuple.
The Claude contract requires the same execution counts and exactly one
`claude / PreToolUse / Bash / high / terraform-destroy / deny` tuple.

A green CI artifact certifies its pinned host executable, archive digest, and
platform; source commit metadata is informational unless the release gate
binds that digest to the published artifact. The workflow defines separate
Codex, Claude, and Copilot lanes and requires Gemini, Codex, Claude, and
Copilot evidence before
a tagged release build, but this documentation does not claim that a newly
added lane is already green remotely or that a public release contains it. The
presence of the harness alone does not certify anything. `protect status`
deliberately keeps runtime loading `UNVERIFIED` for the user's current process.

`mainframe launch <host>` authenticates pinned host artifacts and verifies
static project configuration. It also binds exact absolute Bash, supported
system/package-manager `jq`, gateway, and safety-policy paths plus their
four-digest SHA-256 seal for the privileged hook bootstrap. For npm-wrapper
candidates it accepts Node.js only from a supported system, package-manager, or
version-manager layout, then hashes and rechecks Node plus
`hash-package-tree.mjs` around authentication and before exec. Arbitrary PATH
shims are rejected, but a user-managed Node installation is not an external
trust anchor. Python is not a launch dependency, and `hash-package-tree.py`
remains a developer certifier. Launch deliberately leaves runtime hook loading
and managed-instruction ingestion `UNVERIFIED`. A gateway call can be
reproduced by another same-user process, so a local receipt alone is not
presented as proof that a native host loaded the hook.

## Threat boundary

The Agent Gateway is an enforcement hook, not an operating-system sandbox.
It protects calls that a supported host routes through the configured pre-tool
event. It cannot constrain another process, an unconfigured host, a disabled
hook, direct terminal commands, or a host that fails to deliver the hook.
Commands that pass still run with the host process's user and filesystem
permissions. The current classifier covers POSIX shell tools on macOS and
Linux; PowerShell calls fail closed until a native PowerShell policy exists.

Host timeout behavior also matters. In particular, Copilot documents command
hook errors as fail-closed for `preToolUse`, but hook timeouts as fail-open.
Keep the local gateway available and fast, verify activation in the installed
host, and use OS isolation or least-privilege credentials where a true security
boundary is required.

Current host references:

- [Codex hooks](https://developers.openai.com/codex/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [GitHub Copilot hooks](https://docs.github.com/en/copilot/reference/hooks-reference)
- [Gemini CLI hooks](https://geminicli.com/docs/hooks/reference/)

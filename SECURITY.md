# Security Policy

## MAINFRAME Security Philosophy

MAINFRAME is designed as an **AI-Native Bash Runtime** where security is foundational, not an afterthought. AI agents controlling computer systems through bash commands must operate within strict safety boundaries.

### Core Security Principles

1. **Avoid Dynamic Execution by Default** - Reviewed exceptions are documented in the generated eval audit
2. **Validate Agent-Facing Boundaries** - Inputs are checked before guarded system operations
3. **Structured Errors** - USOP-enabled operations return parseable errors for agent correction
4. **Auditable Operations** - Agent execution paths can emit traceable decision logs
5. **Fail Closed at Safety Gates** - Guarded operations reject failed validation
6. **Defense in Depth** - Multiple layers of validation and sanitization

## Supported Versions

| Version | Supported          | Security Updates |
| ------- | ------------------ | ---------------- |
| 10.1.x  | :white_check_mark: | Active           |
| 10.0.x  | :white_check_mark: | Security only    |
| < 10.0  | :x:                | End of life      |

## Reporting a Vulnerability

We take security vulnerabilities seriously, especially given MAINFRAME's role in AI agent automation.

### How to Report

1. **DO NOT** open a public issue for security vulnerabilities
2. Use [GitHub Security Advisories](https://github.com/gtwatts/mainframe/security/advisories/new) (preferred)
3. Or email security concerns to the repository owner
4. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact (especially for AI agent scenarios)
   - Affected functions/libraries
   - Suggested fix (if any)

### What to Expect

| Severity | Response Time | Fix Timeline |
|----------|---------------|--------------|
| **Critical** (RCE, privilege escalation) | 24 hours | 24-72 hours |
| **High** (data exposure, unsafe execution) | 48 hours | 7 days |
| **Medium** (input validation bypass) | 7 days | 14 days |
| **Low** (minor issues) | 14 days | Next release |

### Scope

Security issues we're particularly concerned about:

| Category | Examples | Impact |
|----------|----------|--------|
| **Command Injection** | Unsanitized input passed to commands | Full system compromise |
| **Path Traversal** | Bypassing `path_is_safe` validation | Unauthorized file access |
| **TOCTOU Races** | Time-of-check to time-of-use | Race condition exploits |
| **Unsafe Deserialization** | JSON parsing that executes code | Arbitrary code execution |
| **Privilege Escalation** | Agent operations gaining unintended access | System compromise |
| **Information Disclosure** | Leaking sensitive data in errors/logs | Data breach |

### Out of Scope

- Issues requiring physical access to the machine
- Social engineering attacks
- Denial of service (unless trivially exploitable)
- Issues in external dependencies (report to their maintainers)
- Theoretical vulnerabilities without proof of concept

## Security Features

### Threat Model

MAINFRAME's safety layers are designed for a specific threat model.
Understanding it matters for deciding how much to trust each layer.

**In scope (what we defend against):**

| Threat | Defense |
|--------|---------|
| AI agent **mistakes** (wrong flags, wrong paths, hallucinated commands) | Destructive-command gate, risk scoring, profile tiers, path confinement |
| Supported coding-agent shell calls before execution | Explicit Codex, Claude Code, Copilot CLI, and Gemini CLI pre-tool Agent Gateway activation |
| **Silent failures** that cascade into bad agent decisions | Structured errors (USOP), audit trails, fail-closed validation |
| **Accidental** destructive operations (`rm -rf` wrong dir, `dd` to wrong device) | Destructive tier (system profile required), enforced risk threshold with approval flow |
| Path traversal **in tool input** (`../`, encoded variants, symlink escapes) | Canonicalized path validation, boundary-aware containment |
| Registry response substitution during an explicitly requested managed-host download | Closed `registry.npmjs.org` HTTPS URLs, no redirects/proxies/credentials, exact SHA-512 SRI and package identity, bounded descriptor-safe extraction |
| Lost agent context leading to repeated/redundant dangerous work | AWM checkpoints, discoveries, audit replay |

**Out of scope (what we do NOT defend against):**

| Threat | Why |
|--------|-----|
| An **adversarial** AI actively trying to bypass the gate | String-level gates are inherently evadable (variable indirection, encoding, interpreter escapes like `python -c`). The gate catches *accidents*, not *attacks*. |
| Malicious code executed *by* the agent (supply-chain compromise of tools) | Out of scope for a command gate; see `lib/tirith*.sh` for supply-chain scanning |
| Privilege escalation via setuid/kernel exploits | MAINFRAME runs as the invoking user; OS-level isolation (containers, VMs, separate users) is the correct control |
| Host compromise in general | If the host is compromised, in-process guardrails are meaningless |
| Shell calls from unconfigured hosts, direct terminals, or PowerShell | The current Agent Gateway covers configured POSIX shell hooks on macOS/Linux only |
| A configured hook that the host has not trusted or loaded | Static config is not runtime proof; restart the host, use its native hook diagnostics, and run a disposable canary. Codex also requires exact-hash review in `/hooks`. |
| Effects hidden behind delegated runtimes (`npm run`, `make`, scripts, aliases, interpreters) | The gate recognizes shell command forms; it cannot prove the behavior of every downstream program. Treat it as an accidental-risk guardrail, not adversarial containment. |
| Passive code loaded before MAINFRAME starts | `mainframe launch` scrubs inherited language-runtime and dynamic-loader hooks after entry, but the initial `/bin/bash` interpreter and its OS loader have already started by then. |
| Hostile same-UID mutation or race against a user-owned MAINFRAME install | The four-file launch seal detects straightforward sequential replacement of Bash, `jq`, gateway, and policy bytes, but not their dynamic-library closure. A peer process with the same UID can target the launcher, project configuration, environment, or check/use window. Use OS/root protection or process separation for that threat. |
| Mutation by another principal authorized to write the selected Homebrew prefix | Homebrew's stable `opt` paths are deliberately mutable package-manager aliases. MAINFRAME places every authorized writer to that prefix inside the trusted package-manager boundary, including for Pi package code loaded after activation. Use a private, non-shared Homebrew prefix or the owner-private release-archive install when that trust is unacceptable. |
| A malicious package already authorized by the trusted host manifest and package lock | SRI proves exact byte identity, not that the reviewed trust root chose benign bytes. Protect and review MAINFRAME release inputs; use OS isolation for hostile vendor code. |

**Rule of thumb:** MAINFRAME reduces accidental risk for an
honest-but-fallible agent; it does not make the agent intrinsically safe. For
an adversarial workload, run the agent in an OS-level sandbox (container, VM,
or dedicated low-privilege user) *in addition* to MAINFRAME.

### Privileged host-launch boundary

`mainframe launch` binds absolute Bash, `jq`, gateway, and safety-policy paths
plus a seal containing the four corresponding SHA-256 digests. `jq` must
resolve from a supported system or package-manager installation; project and
arbitrary user `PATH` wrappers are rejected. The machine-independent
`/bin/bash -p` hook bootstrap uses fixed system hash tools to verify all four
files before every gateway invocation. Missing bindings, a malformed seal, or
a byte mismatch fails closed. Direct host starts do not receive the five launch
values and therefore fail closed when the configured hook runs.

This closes straightforward sequential post-launch replacement; it is not a
same-UID tamper-proof boundary. MAINFRAME is normally installed with user-owned
files, and the four-file seal does not authenticate loaded dynamic libraries or
other transitive dependencies. An actively hostile peer process can race
check-to-use or modify other user-controlled inputs. Strong hostile-race
resistance requires an OS/root-protected installation, a dedicated
lower-privilege user, or isolation in a container or VM.

For npm-wrapper hosts, launch accepts Node.js only from supported system,
package-manager, or version-manager layouts and hashes and rechecks both Node
and `hash-package-tree.mjs` around package-tree authentication and before exec.
This rejects arbitrary PATH shims and detects sequential replacement. A
user-owned version-manager Node remains self-anchored rather than authenticated
against an external release identity.

For the `launch` command, the public CLI removes `BASH_ENV`, `ENV`, Node.js
preload/module-search/coverage/history hooks, `PERL5OPT`, `PERL5LIB`, `PERLLIB`,
and every `LD_*`/`DYLD_*` variable before loading the common runtime. The launch
library repeats the scrub before sensitive helpers, Node-backed authentication,
and final host exec while preserving ordinary host configuration and
credentials. This closes inherited passive loaders after entry; it cannot
retroactively protect the initial interpreter or OS loader. Invoke MAINFRAME
through a trusted executable and use a stronger isolation boundary when that
initial process is not trusted.

### Managed host acquisition and payload boundary

Managed install requires one explicit source:

```text
mainframe host install HOST (--download | --package-dir DIR) [--dry-run | --yes] [--json]
```

No install contacts the network unless `--download` is present. That flag
authorizes anonymous direct HTTPS requests only for the exact package names,
versions, canonical `registry.npmjs.org` URLs, and SHA-512 SRI values selected
from MAINFRAME's trusted host manifest and package lock. The downloader rejects
redirects, alternate hosts or ports, credentials, cookies, proxy overrides,
encoded URL variations, non-public peers, unexpected response encodings,
oversized bodies, integrity mismatches, and pre-existing destination names. It
does not invoke npm or inherit npm registry configuration.

Downloaded bytes enter a private mode-`0700` ephemeral workspace through an
exclusive no-follow file descriptor that is immediately unlinked before the
first request. No downloaded archive pathname is published or reopened. After
the streaming SRI check, the helper rewinds and independently re-verifies SRI,
then performs bounded extraction from that same stable anonymous descriptor.
The extractor enforces compressed, expanded, member-count, member-size, path,
and archive-type bounds and requires the exact package name and version. The
offline source separately requires single-link regular archive files and uses
one stable descriptor per archive. Package lifecycle scripts and vendor
launchers or binaries are never executed during acquisition or assembly.

`--download --dry-run` performs that real network acquisition plus complete
staged-payload authentication, then removes the workspace and publishes
nothing. `--download --yes` performs the same verification before atomic
publication. `--package-dir` remains strictly offline and subjects the supplied
exact basenames to the same SRI, extraction, package-identity, full-tree, and
entry-point checks. `--json` never prompts; an actionable request requires
`--dry-run` or `--yes`, while a safe no-op, refusal, or validation error may
return before the consent boundary.
Once atomic publication becomes possible, interruption or helper failure emits
no install success. Human output directs the operator to
`mainframe host status HOST --runtime managed`; JSON reports the proved or
uncertain mutation state before any retry.
Neither source changes `PATH`, shell profiles, global packages, host settings,
or project files.

The resulting receipt and deterministic bundle ID bind the exact MAINFRAME
version, host, platform, package set, host manifest, package lock, complete
payload tree, and direct-native executable. This detects later drift but is not
a publisher signature or an OS isolation boundary. A malicious same-UID process
or malicious byte set already approved by the trusted lock remains outside this
boundary.

### Managed host quarantine recovery boundary

`mainframe host remove HOST --yes` preselects a generated
`removed.<18-lowercase-hex>` ID before entering the atomic move window. Success
returns that ID after moving one authenticated current generation into
owner-only same-filesystem quarantine. If interruption or helper failure makes
the mutation outcome uncertain, the human error returns the same `Recovery ID`
and JSON retains it as `quarantine_id`; the ID alone does not claim that the
slot was created. Inspect managed status before an exact-ID dry run. Recovery
is explicit and exact:

```text
mainframe host restore HOST --quarantine-id removed.<18-hex> [--dry-run | --yes] [--json]
```

Restore is offline and accepts no path, pattern, mutable alias, implicit newest
entry, or stale host/version/platform/bundle selection. Before mutation and
again under the shared lifecycle lock, it requires a missing active target,
private symlink-free source ancestry, no nested mount, an exact one-generation
slot, the same source filesystem identity, and complete current receipt/tree/
executable authentication. Publication uses the reviewed descriptor-relative
kernel no-replace rename. It preserves the generation inode, refuses every
occupied active target, and emits success only after final authentication and
explicit lock release.

The consumed quarantine slot remains empty. Version 1 deliberately has no
durable slot-to-target transaction record, so a process death or helper failure
after rename may be reported only as `changed: null` and
`mutation_state: "uncertain"`. A retry refuses the occupied target rather than
claiming an unprovable idempotent success. Operators must inspect
`mainframe host status HOST --runtime managed`; restore never attempts an
automatic reverse move. As elsewhere, the lifecycle lock coordinates
MAINFRAME processes but is not protection against a malicious process already
running as the same user.

### Release install and upgrade boundary

The versioned bootstrap verifies one exact archive checksum record, rejects
unsafe archive types and paths, and requires complete inner-manifest coverage.
It writes a mode-`0600` local receipt only after the installed CLI link,
managed bytes, version, and doctor check pass. The install root is mode `0700`.
The receipt detects later path or managed-byte drift and binds the archive and
manifest digests; it is not a cryptographic publisher signature. Because the
archive and checksum are delivered from the same GitHub release origin, their
pairing provides integrity and consistency, not an independent authenticity
channel.

Bootstrap placement is recoverable across tested process interruption. A
private journal binds the exact archive, manifest, install-root inode, and CLI
link inode; retry accepts only the same versioned command and refuses a
replaced path even when its visible link target is unchanged. Optional
shell-profile and agent-discovery writes remain outside the receipt boundary,
so a failure there is reported as a receipt-backed partial success with a
separate retry command.

Transactional release upgrade accepts an explicit stable version only. It
verifies the active receipt and managed runtime before download, then verifies
the outer checksum, archive structure, complete inner manifest, and candidate
health around cutover. Unmanaged files are preserved only outside managed
runtime surfaces when regular, non-executable, stable, and collision-free.
Links, special files, nested mounts, and unmanaged code fail closed. The old
runtime remains in a private transaction directory; rollback and copied-script
recovery are covered for ordinary errors and tested process interruption,
including `SIGKILL` around rename boundaries.

Upgrade is not a concurrent-state protocol: all agents and shells using the
installation must be stopped, and cutover requires
`--confirm-agents-stopped`. Filesystem durability barriers reduce incomplete
write exposure, but MAINFRAME does not claim recovery from arbitrary storage
hardware failure, filesystem corruption, or full-machine power loss. Keep the
printed journal and transaction directory until the new runtime is verified or
recovery completes.

AWM state is local-user private, not a sandbox or authorization service.
Canonical storage uses `0700` directories and `0600` files and rejects session,
checkpoint, relative-root, and symbolic-link path escapes. Custom `AWM_ROOT`
values must be absolute and have no symbolic-link ancestor. Any process running
as the same OS user can still read or change that user's AWM state; namespaces
are organizational only. Concurrent log appends, compression, and
category-index updates preserve acknowledged entries, but they do not protect
against a malicious process running as that same user. File-backed concurrency
is a same-host, local-filesystem guarantee: MAINFRAME uses `flock` on Linux and
BSD `lockf` on macOS so locks are released by the kernel after a process crash.
When neither primitive exists, the portable `mkdir` fallback refuses automatic
stale-lock breaking because pathname-based recovery has an ABA race; it times
out fail-closed and reports the exact lock directory for manual inspection.

### Defense Layers (in order of evaluation)

1. **Host pre-tool enforcement** (`mainframe agent-hook`) - after explicit
   activation, supported hosts can route configured POSIX shell calls through
   a blocking hook before execution. Protected launch seals and verifies the
   absolute Bash, `jq`, gateway, and safety-policy files; gateway or seal errors
   fail closed. Host timeout behavior remains host-defined. See
   [the Agent Gateway boundary](docs/AGENT_GATEWAY.md).
2. **Destructive-command gate** (`agent_gate_classify`) - 42 canonical lexical
   rules (critical/high/medium/low). JavaScript consumers must ship
   `security/gate-rules.json` with its declared
   `security/gate-normalizer.mjs` and call the exported classifier so each rule
   receives its required raw or executable-marker input.
3. **Profile policy** (`agent_validate_command`) - destructive/system/network/
   write tiers checked BEFORE command existence (policy is host-independent).
4. **Selected path confinement** (`AGENT_SAFE_BASE`) - guarded file helpers
   and supported command/flag forms validate canonical targets. For compatibility,
   plain `rm` without recursive+force and nonrecursive permission changes are
   not path-confined. This is not a guarantee for every filesystem mutation.
5. **Risk threshold** (`agent_safe_exec`) - commands scoring at or above
   `AGENT_RISK_THRESHOLD` block unless approved (`AGENT_APPROVED=1` one-shot
   or a registered approval callback). Gate matches floor the score.
6. **Audit** - general library logs use a private per-user temporary directory,
   owner-only files and private rotation/clear. Command strings and callback
   arguments are redacted by default; `AGENT_AUDIT_INCLUDE_COMMANDS=1` explicitly
   opts into raw diagnostic details. Custom audit detail values remain the
   caller's responsibility. Redacted records support counts, not command-level
   false-positive correlation. The gateway retains its validated descriptor.
   Local logs are troubleshooting evidence, not a tamper-proof security ledger.

Path-qualified executables use the same basename policy and risk rules as bare
names, while execution retains the actual supplied path and argv. Basename
classification does not authenticate a binary or cover renamed tools and hidden
script effects. A symlink helper confines the link's directory entry; its target
may be relative or outside the base. That reference grants no write permission,
and guarded appends still reject referents outside the base. An existing outward
link can therefore be repaired without granting authority over its old target.

`low` is a lexical no-match result: after bounded resolution and normalization,
none of the 43 ordered patterns matched. It does not establish command
semantics, inspect arbitrary scripts or delegated programs, or prove that
execution is safe. A gateway may allow that tier under its selected block
policy, but the label is not a general authorization; profile policy, path
confinement, least privilege, review, and OS isolation remain separate
controls.

### Agent Safety Library (`lib/agent_safety.sh`)

Safe command execution for AI agents:

```bash
source lib/agent_safety.sh

# Safe command dispatch - no eval, whitelisted commands only
agent_safe_exec "ls" "-la" "/safe/path"

# Command validation before execution
agent_validate_command "git" "status" || die 1 "Command not allowed"

# Idempotent operations - safe to retry
agent_ensure_dir "/path/to/dir"
agent_ensure_file "/path/to/file" "content"

# Full audit logging
agent_audit_log "created" "/path/to/file"
```

### Validation Library (`lib/validation.sh`)

Input validation and sanitization:

```bash
source lib/validation.sh

# Path validation - prevents directory traversal
validate_path_safe "$user_input" "/allowed/base" || die 1 "Path traversal detected"

# Command safety - detects injection attempts
validate_command_safe "$cmd" || die 1 "Injection detected"

# Shell argument sanitization
safe_arg=$(sanitize_shell_arg "$untrusted_input")

# Build properly escaped commands
safe_cmd=$(build_safe_command "grep" "$pattern" "$file")
```

### USOP (Universal Structured Output Protocol)

Structured errors for AI self-correction:

```bash
source lib/output.sh
export MAINFRAME_OUTPUT=json

# Errors include machine-parseable details
output_error "E_PATH_TRAVERSAL" "Path traversal detected" "Use absolute paths within allowed directory"
# {"ok":false,"error":{"code":"E_PATH_TRAVERSAL","msg":"Path traversal detected","suggestion":"Use absolute paths within allowed directory"}}
```

### Atomic Operations (`lib/atomic.sh`)

Safe file operations with rollback:

```bash
source lib/atomic.sh

# Atomic write - temp file then rename, prevents partial writes
atomic_write "/important/file" "content"

# Checkpoint before risky operations
file_checkpoint "/config/file"

# Rollback if something goes wrong
file_rollback "/config/file"
```

## Security Best Practices for AI Agents

### Always Validate External Input

```bash
# GOOD: Validate before use
validate_path_safe "$user_path" "/allowed" || exit 1
validate_int "$user_count" 1 100 || exit 1

# BAD: Direct use of untrusted input
cd "$user_path"  # Path traversal risk
```

### Use Safe Command Execution

```bash
# GOOD: Safe dispatch
agent_safe_exec "ls" "-la" "$validated_path"

# BAD: String concatenation
eval "ls -la $user_input"  # Command injection
```

### Handle Errors Gracefully

```bash
# GOOD: Structured error handling
if ! result=$(some_operation 2>&1); then
    output_error "E_OPERATION_FAILED" "Operation failed" "Check permissions"
    exit 1
fi

# BAD: Ignoring errors
some_operation || true  # Silent failure
```

### Use Idempotent Operations

```bash
# GOOD: Safe to retry
ensure_dir "/path/to/dir"
ensure_file "/path/to/file" "content"

# BAD: Fails on retry
mkdir "/path/to/dir"  # Fails if exists
```

### Log Security-Relevant Operations

```bash
# Enable audit logging
export AGENT_AUDIT_LOG="/var/log/agent_audit.log"

# Operations are automatically logged
agent_safe_exec "chmod" "755" "/path/to/script"
# Logged: [timestamp] EXEC chmod 755 /path/to/script -> success
```

## Known Security Considerations

### Eval Usage and Trust Boundaries

MAINFRAME minimizes but cannot completely eliminate `eval`. This section documents all `eval` usage and the expected trust levels for callers.

#### Trust Levels

| Level | Description | Example Sources |
|-------|-------------|-----------------|
| **TRUSTED** | Library-internal calls, hardcoded strings | Other MAINFRAME functions |
| **VALIDATED** | User input that has passed validation | Post-`validate_command_safe()` input |
| **UNTRUSTED** | Raw user input, AI prompts, external data | Direct user input, file contents |

#### Current Eval Locations

| Library | Function | Trust Required | Purpose | Mitigation |
|---------|----------|----------------|---------|------------|
| `stream.sh` | `stream_process` | VALIDATED | Pipeline command execution | Caller must validate |
| `streams.sh` | `stream_map` | VALIDATED | Lazy stream transformation | Caller must validate |
| `compose.sh` | `compose()` | TRUSTED | Function composition | Internal use only |
| `cli.sh` | `cli_dispatch` | VALIDATED | Dynamic function dispatch | Command name whitelist |
| `template.sh` | `template_render` | VALIDATED | Variable expansion | Sandboxed context |
| `procsub.sh` | `procsub_eval` | VALIDATED | Process substitution | Caller must validate |
| `sandbox.sh` | `sandbox_exec` | VALIDATED | Profile-based execution | Profile args validated |
| `compat.sh` | `compat_setup_gnu_tools` | TRUSTED | Wrapper function creation | Internal array source |
| `agent_exec.sh` | `agent_retry` | VALIDATED | Retry with command | Caller must validate |

#### Caller Responsibilities

**When calling functions that use eval internally:**

1. **Always validate input first:**
   ```bash
   # CORRECT: Validate before passing to stream functions
   validate_command_safe "$user_cmd" || die 1 "Invalid command"
   stream_map "$user_cmd" < input.txt

   # WRONG: Passing unvalidated input
   stream_map "$user_cmd" < input.txt  # Command injection risk!
   ```

2. **Use MAINFRAME sanitization:**
   ```bash
   # Sanitize shell arguments
   safe_arg=$(sanitize_shell_arg "$untrusted")

   # Build safe commands
   safe_cmd=$(build_safe_command "grep" "$pattern" "$file")
   ```

3. **Prefer non-eval alternatives when available:**
   ```bash
   # PREFERRED: Direct function call
   json_object "key=$value"

   # AVOID: eval-based dynamic dispatch
   eval "json_$operation \"$args\""
   ```

#### Safe Mode (Future)

We plan to add `MAINFRAME_SAFE_MODE=1` which will:
- Reject commands containing shell metacharacters in stream functions
- Require explicit `--allow-eval` flag for eval-using functions
- Log all eval operations for audit

We actively work to eliminate or sandbox remaining `eval` usage.

### Race Conditions

Some operations have inherent TOCTOU windows:

- File existence checks before writes
- Lock acquisition

Use atomic operations (`atomic_write`, `with_lock`) where possible.

## Security Acknowledgments

We gratefully acknowledge security researchers who help keep MAINFRAME safe:

*No acknowledgments yet - be the first!*

---

*MAINFRAME: Building for a safe and accurate agentic future.*

**[Report a Vulnerability](https://github.com/gtwatts/mainframe/security/advisories/new)** | **[Security Best Practices](#security-best-practices-for-ai-agents)**

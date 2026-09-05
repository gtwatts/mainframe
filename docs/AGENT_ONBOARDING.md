# Agent onboarding: from installed files to a working session

Start with Mainframe's existing diagnostics, prove a small local operation,
then verify the agent route you intend to use. This guide prioritizes Codex
and Pi. It adds no installer, permission system, or readiness badge.

The commands below describe the **10.2.0 source candidate**, not a published
release. Use [INSTALL.md](../INSTALL.md) for installation and recovery and
[COMPATIBILITY.md](COMPATIBILITY.md) for exact supported tuples. Record the
runtime path and artifact identity: two installations can both report 10.2.0
while containing different files.

## 1. Find the runtime you are actually using

Run these from your project in your normal terminal. These are diagnostics;
they do not install packages, change profiles, or configure an agent.

```sh
command -v mainframe
mainframe version
mainframe shell status --json
mainframe doctor
mainframe setup --project .
```

`shell status` compares `selected_cli_resolved`, `active_root`, inherited
environment, and Bash/zsh profile state. `doctor` reports the actual **Bash
engine**, OS/architecture, library health, and shell identity. `setup` reports
host/package signals and next commands without executing discovered agents or
choosing a host for you. Read the fields as well as the process exit code.

If `mainframe` is absent, follow the installation guide. If shell status says
`reload-required`, open a fresh terminal or restart the parent application and
check again. If it says `repair-required`, inspect
`mainframe shell repair --dry-run` before applying the documented repair.
A source checkout that is not selected on PATH can report `not-selected`;
that is not evidence that the installed CLI is broken. Do not mix checkout
diagnostics with installed-runtime results.

| Dependency | Requirement for this path |
|---|---|
| Execution engine | Bash **4.4+**, with 5.x recommended. macOS Bash 3.2 can bootstrap the CLI but cannot execute the libraries. |
| Calling shell | Bash or zsh. A zsh caller invokes the CLI's supported Bash engine; do not source Bash libraries directly into zsh. |
| JSON | `jq` from a supported system/package-manager location. The project does not declare a numeric minimum here. |
| Durable CLI and Pi diagnostics | Protected fixed-location Python **3.9+** with the required standard library. |
| MCP | Python **>=3.10,<3.15**, matching Mainframe runtime/package binding, and the pinned MCP SDK; see [MCP installation](../mcp/README.md). |
| Managed host lifecycle | Python **3.10+** for install/remove/restore. Node.js is needed for applicable npm-wrapper routes; use the selected host's exact compatibility record. |
| Installation utilities | Git for source installs; curl, tar, and a SHA-256 implementation for the release bootstrap. |

No claim is made that every external command wrapped by Mainframe is installed.
Discover functions with `mainframe search <topic>` and inspect signatures with
`mainframe help <function>`. The discovery catalog is broader than the reviewed
invocation surface; a search result does not grant execution authority.

## 2. Prove first use without touching project memory

```sh
mainframe setup --project . --proof
```

This existing proof uses private temporary state: a fixed pure invocation,
an **ephemeral untrusted session** checkpoint retrieved by a fresh Bash
process, and a shell classifier canary that is never executed. It reports
cleanup before success. It does not establish project-memory provenance,
live agent loading, or interception. See [the full onboarding
contract](ONBOARDING.md#what-success-proves).

A restricted agent execution environment can deny the local Unix socket used
by the durable executor. A native-terminal pass and a restricted-task failure
are different evidence. If the proof fails, retain its exit code and diagnostic,
check `doctor`, and reproduce the same harmless command in your normal terminal;
do not disable Mainframe policy or turn a failed result into a success claim.

### Optional: inspect a structured call and project-memory handoff

Run this complete block in Bash or zsh after the diagnostics above. It creates
a disposable project and private state, uses only public CLI routes, and
removes its demonstration directory on exit. Each CLI call runs in a separate
process. It creates no mapping for your real project. The control-plane
supervisor may retain empty per-ledger directories under its private system
temporary root; this is not a claim of zero filesystem residue.

```sh
(
  set -eu
  mf_demo_cli=$(command -v mainframe)
  case "$mf_demo_cli" in /*) ;; *) echo 'Select an installed CLI first' >&2; exit 1;; esac
  mf_demo_dir=$(mktemp -d /tmp/mainframe-onboarding.XXXXXX)
  mf_demo_dir=$(cd -P -- "$mf_demo_dir" && pwd -P)
  trap 'rm -rf -- "$mf_demo_dir"' EXIT
  umask 077
  mkdir "$mf_demo_dir/home" "$mf_demo_dir/state" "$mf_demo_dir/config" "$mf_demo_dir/project"
  cd "$mf_demo_dir/project"
  mf_demo() {
    env -i HOME="$mf_demo_dir/home" PATH="$PATH" \
      XDG_CONFIG_HOME="$mf_demo_dir/config" XDG_STATE_HOME="$mf_demo_dir/state" \
      MAINFRAME_QUIET=1 "$mf_demo_cli" "$@"
  }

  mf_demo invoke mf:std:pure-string:to_lower \
    --input-json '{"value":"HELLO Agent"}' --format control-plane-json-v1 \
    > "$mf_demo_dir/call.json"
  jq -e '.ok == true and .result.outcome == "succeeded" and
    .result.result_available == true and .result.broker_envelope.exit_code == 0 and
    (.result.broker_envelope.stdout_b64 | @base64d) == "hello agent\n"' \
    "$mf_demo_dir/call.json"
  jq '.result | {run_id, call_id, decision_id, evidence_id, outcome}' "$mf_demo_dir/call.json"

  mf_demo awm project ensure --project .
  mf_demo awm project checkpoint --project . onboarding-proof 'hello agent' --importance high
  test "$(mf_demo awm project get --project . onboarding-proof)" = 'hello agent'
  mf_demo awm project context --project . onboarding-proof --tokens 400 --format json
  mf_demo awm project handoff prepare --project . next-agent --tokens 400 --format json
)
```

For structured invocation, outer `ok: true` means the request was handled;
check `result.outcome`, result availability, and the broker result too. The
example checks the actual returned bytes. The IDs correlate the operation's
records; they are not credentials or approval grants.

The memory readback demonstrates local continuity across processes, and the
handoff creates an export for inspection. No second agent consumes it in this
demo and nothing synchronizes to another machine. Treat memory content as
untrusted, non-authorizing data, including entries labeled `untrusted_legacy`.
Use [the AWM protocol](ONBOARDING.md#the-awm-protocol-agents-receive) for real
project work, with `--discover-root` when you intend to share the worktree's
mapping. Never fall back to direct storage writes when the public route fails.

## 3. Verify the agent route separately

### Codex

Two distinct routes need separate evidence:

* **MCP tools:** use the matching, runtime-bound package described in
  [mcp/README.md](../mcp/README.md). Run its exact absolute executable with
  `--mainframe-root /absolute/runtime/root --check`. A passing check proves
  package/runtime admission; a saved MCP configuration proves only configuration.
  Inspect the current task's actual tool inventory, then make a harmless
  `mainframe_json_string` call with a dummy `value`. Verify the returned value
  and kernel IDs. If tools are absent after a configuration change, start a
  fresh task/session and inspect again; do not assume existing sessions gained
  tools. A test with an explicit server override proves that override, not the
  default saved configuration.
* **Native shell hook:** inspect `mainframe host status codex --json`, preview
  `mainframe setup --project . --host codex --dry-run`, and follow the
  [onboarding flow](ONBOARDING.md). After authorized setup, inspect
  `mainframe protect status codex --project .` and
  `mainframe launch codex --project . --dry-run`. Launch through Mainframe,
  review and trust the exact hook/hash in Codex `/hooks`, then complete the
  [native host check](ONBOARDING.md#finish-in-the-native-host) in a disposable
  project. Static preflight cannot perform this native trust action for you.

The selected managed host may differ from the Codex application or the first
`codex` on PATH. Exact compatibility is intentional; do not substitute a newer
version string for artifact verification. MCP success does not establish the
native shell hook or coverage of all native edit/network/process tools.

### Pi

```sh
mainframe pi status
mainframe pi doctor
mainframe setup --project . --host pi
```

These remain offline and read-only. Follow their next action and the dedicated
[Pi package flow](ONBOARDING.md#pi-uses-a-dedicated-package-flow), rather than
using Codex's project-hook setup. Package changes require `/reload` or restart
inside Pi, followed by `/mainframe doctor`. Only that in-process check can
report `READY`; canonical files on disk cannot prove the extension loaded.
Inspect the seven tools and the reported hook/runtime identity. A new package
version or unlisted platform remains unverified even if its files are present.

For both agents, ordinary diagnostics need no additional Mainframe approval.
Applying integration/lifecycle changes follows the existing preview and
confirmation contract; Pi lifecycle confirmation belongs in a human terminal.
Do not ask repeatedly for an already authorized routine action.

## 4. Keep the readiness claim precise

| State | Evidence needed |
|---|---|
| Installed | Exact runtime path/version plus verified payload identity. |
| Configured / saved | Expected managed entries exist and point at that runtime. |
| Compatible | Exact selected host/package/platform passes its compatibility checks. |
| Live | The running agent exposes and successfully uses the intended route. |
| Enforced | A native route actually delivers the controlled request and honors its denial; state the routes tested. |
| Released | Published artifact and required release evidence match; local passes do not establish this. |

Brokered contracts, lexical shell accident prevention, and trusted direct
library execution are separate domains. Mainframe is not OS containment and
does not make arbitrary adversarial execution safe. Uncovered routes remain
unverified. The [readiness checklist](AGENT_READINESS_CHECKLIST.md) gives a
repeatable report format and the dated four-cell validation matrix.

## 5. Update and recover with the existing lifecycle

Use [INSTALL.md](../INSTALL.md) for the installation type's update, upgrade,
transaction, and recovery rules. Review dry-run output and stop affected
agents before an actual runtime cutover. Keep the runtime and MCP package
binding matched. Re-run diagnostics and live-agent checks after switching.

Project deactivation and managed-host exact-ID remove/restore are documented
under [Inspect changes and roll back](ONBOARDING.md#inspect-changes-and-roll-back)
and [Managed host payloads](MANAGED_HOST_PAYLOADS.md). Pi restore is available
only when its receipt says `restore_available=true`, using the exact backup ID.
There is no generic managed-host update/prune command. Preserve unrelated
edits when recovering shell or agent configuration; a whole-file backup may
predate later user changes. Recovery does not imply cross-machine memory sync.

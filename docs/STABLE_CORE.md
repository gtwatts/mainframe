# Stable Kernel and Stable Public-Core Export Set

Status: **Frozen and brokered in the unpublished 10.2 source candidate —
Phase 0 (P0-5).** Changes to this set follow the same
policy discipline as `config/function-export-policy.json`: additions,
removals, or ownership changes require an explicit, reviewed policy update.
Governing plan: [`A_PLUS_PLUS_PLAN.md`](A_PLUS_PLUS_PLAN.md) ("Freeze the
stable-core export set and bind each exposed name to a canonical manifest
ID"; exit gates: *zero public collisions in the stable core* and *a default
MCP surface of no more than 32 curated tools*).
Machine-readable membership source:
[`config/stable-core.json`](../config/stable-core.json). Reviewed invocation
source: [`config/invocation-policy.json`](../config/invocation-policy.json).

## 1. Stable kernel

The bootstrap kernel is the minimal trusted core every profile loads:

| File | Role |
|---|---|
| `lib/common.sh` | Loader (tier/profile resolution, library sourcing) |
| `lib/output.sh` | Structured output / USOP primitives |
| `lib/errors.sh` | Error taxonomy and handling |
| `lib/hints.sh` | Error hints |
| `lib/ansi.sh` | Terminal primitives |

**Kernel contract** (per the plan, "Trusted bootstrap kernel"): the kernel
loads libraries, resolves the manifest, renders output, and enforces policy.
It must not contain network clients, package managers, domain-specific
helpers, or caller-controlled dynamic evaluation.

## 2. Stable public-core export set

26 exports (below the 32-tool MCP default-surface cap), each bound to exactly
one canonical manifest ID via `MANIFEST.json` `name_index`. **Zero public
collisions:** no export in this set appears in
`config/function-export-policy.json`'s collision registry, and a
generation-time assertion keeps it that way.

The default effect contract is **`read-pure-only`**: tools may transform or
validate caller-provided data, sanitize paths, and render structured output.
They may not execute commands, create or modify files, call the network, or
mutate process or system state. Producing the tool response, including a
validation failure, is the only intended observable effect.

| Area | Exports |
|---|---|
| JSON | `json_get`, `json_object`, `json_array`, `json_escape`, `json_string`, `json_merge`, `json_valid` |
| Validation | `validate_email`, `validate_url`, `validate_path`, `validate_json`, `validate_int`, `validate_regex`, `validate_semver` |
| Path safety | `path_sanitize` |
| Strings | `trim_left`, `trim_right`, `to_upper`, `to_lower`, `is_empty`, `is_numeric` |
| Arrays | `array_join`, `array_contains` |
| Output/USOP | `output_success`, `output_json`, `usop_error_validation` |

The safety floor deliberately excludes these unbrokered side effects:

| Effect | Excluded from the default tier |
|---|---|
| Arbitrary command execution | `usop_exec` |
| Direct filesystem mutation | `ensure_dir`, `ensure_file`, `atomic_write`, `atomic_append`, `atomic_replace` |

Those functions remain available elsewhere in MAINFRAME's broad shell
library, but they are not reachable through the public MCP executable. Use a
purpose-built reviewed adapter or the human-confirmed Pi route when an agent
needs effects beyond this safety floor.

## 3. Surface behavior

- **MCP is stable-core-only** (`config/stable-core.json` →
  `mcp.default_tier`), so every public MCP session advertises exactly these 26
  tools and delegates their closed named inputs by canonical ID to `mainframe
  invoke`. Legacy tier environment configuration is rejected before protocol
  startup.
- **Pi:** `mainframe_exec` resolves a stable-core Bash name through the
  canonical manifest, maps its positional public arguments through the
  reviewed call shape, and delegates to `mainframe invoke`. A non-stable-core
  function stays on Pi's guarded legacy path and requires Pi's human
  confirmation UI. Progress and result metadata retain only argument counts,
  encoded-input size, and stable field names—not raw argument values.
- **Node.js and Python bindings:** canonical-ID calls and public function-name
  calls resolve the same reviewed contracts and delegate to `mainframe
  invoke`. Their raw Bash execution methods remain explicitly trusted,
  unbrokered escape hatches for application-owned code.
- **Profiles:** manifest generation marks exports in this config with the
  `stable-core` profile; `full` still covers every installed export and
  `core` retains the broader legacy closure.
- **Parity:** `scripts/check-owner-parity.py` asserts the stable-core set
  has zero collisions, at most 32 members, all present in `name_index`,
  and that the MCP `stable-core` tier closure equals this set exactly.

## 4. Invocation boundary

For every member, `config/invocation-policy.json` records exactly one reviewed
closed-object schema, ordered scalar/spread argv mapping, result kind, one
`pure` or `read` effect, an empty capability set, and time/output bounds. The
generator rejects a missing or extra canonical ID and merges the reviewed
metadata into only the stable-core manifest exports.

`mainframe invoke` accepts canonical IDs, not Bash names or executable names.
It verifies owner parity and platform, rejects unknown fields and unreviewed
contracts, then starts a clean protected Bash child with a fixed helper
`PATH`, user configuration disabled, and a library set fixed to `core` plus the
reviewed owner module. Timeout or output overflow terminates the child process
group; normal completion and broker termination also tear down surviving
descendants. Input is read through EOF into a binary-safe bounded file, with
duplicate keys, literal NUL, trailing data, and oversize requests denied. A
private JSONL audit records metadata and input length, never input values; an
unavailable or unsafe audit target denies execution. Adapters use a strict
`broker-json-v1` envelope and recheck identity, bounds, status/exit coherence,
and result-kind semantics.

This is a bounded execution and audit boundary for cooperative local agents.
It does not isolate the process with operating-system sandboxing or defend a
user-owned installation from a hostile same-user process.

## 5. Freeze rules

1. The 32-tool limit is a ceiling, not a target. Every addition requires an
   explicit policy review and must satisfy the `read-pure-only` contract.
2. A side-effecting export may enter the default tier only after a reviewed,
   fail-closed effect and workspace-authorization broker exists for it.
3. A name that acquires a collision (a new policy entry) is automatically
   ejected at the next manifest generation — the zero-collision assertion
   fails the build until the set is updated.
4. Renames are never performed silently; they follow release governance
   with explicit operator approval.

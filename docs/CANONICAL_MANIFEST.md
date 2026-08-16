# Canonical Manifest Schema and Stable-Core Invocation Contract

Status: **Phase 0 canonical derivation plus the reviewed stable-core broker
landed in the unpublished 10.2 source candidate.** `MANIFEST.json` is generated
from `FUNCTIONS.json`, `config/function-export-policy.json`, and the exact
26-export `config/invocation-policy.json` sidecar by
`scripts/generate-manifest.py`; `--verify` proves the manifest is current and
the registry regenerates byte-identically. The general loader graph, broker
contracts outside stable-core, and pack signing remain Phase 1+.
Audience: MAINFRAME maintainers and adapter authors (runtime loader, MCP, LSP, bindings, docs)
Governing plan: [`A_PLUS_PLUS_PLAN.md`](A_PLUS_PLUS_PLAN.md), pillar "One versioned manifest"

## 1. Problem statement

Before Phase 0, MAINFRAME's function identity was not canonical. The current
candidate adds a deterministic, provisional owner map and uses it for the
reviewed stable-core broker path; the broader surface migration is incomplete:

- `FUNCTIONS.json` (the generated registry) records **4,475 registrations**
  but only **4,406 unique names**: **76 collisions** (67 public, 9 private per
  the approved policy).
- A collision means two or more libraries register the same Bash name
  (e.g. `abs` in `functional` and `pure-util`, `agent_broadcast` in `agent`
  and `agent_comm`). Each surface that exposes MAINFRAME functions — runtime
  loader, MCP server, LSP, language bindings, documentation — can resolve a
  colliding name to a **different owner**, or describe a different call shape
  for it.
- Several broader artifacts and compatibility surfaces still have independent
  generation or legacy execution paths. Until they all consume the manifest,
  parity must be tested rather than assumed.

Phase 0 precedent (already landed): WS1 made MCP invocation deny-by-default
against the registry; WS4 made `FUNCTIONS.json` the single clearly named
source for product-state counts. WS2 extends the same principle from *counts*
and *invocation* to *identity*: one manifest, one owner per name, everything
else generated.

## 2. Definitions

| Term | Meaning |
|---|---|
| **Registration** | One library's record of a function it defines. 4,475 exist today. |
| **Unique name** | A distinct Bash-visible function name. 4,406 exist today. |
| **Collision** | A unique name with more than one registration. 76 exist today. |
| **Owner** | The single module a canonical ID binds a name to. |
| **Canonical ID** | The stable, globally unique identifier for an export (see §4). |
| **Pack** | The current logical classification of related modules; independently signed distribution packs remain future work (see §6). |
| **Profile** | A named manifest closure (`stable-core`, `core`, or `full` in the current candidate). |

## 3. Schema

Every current canonical export value has these generated base fields. The
canonical ID is the key in the top-level `exports` object, rather than a
duplicate field inside the value:

| Field | Type | Required | Meaning |
|---|---|---|---|
| canonical-ID key | string (canonical ID, §4) | yes | Stable symbol ID. Never reused or recycled. |
| `name` | string, `^[a-z_][a-z0-9_]*$` | yes | Globally unique public Bash name (same charset rule as the WS1 invocation gate). |
| `owner` | string (module ID) | yes | Exactly one owning module, e.g. `pure-string`. |
| `summary` | string | yes | One-line description (feeds docs/MCP/LSP). |
| `params` | array of param objects | yes | Ordered registry metadata with name, position, required state, and default. Broker adapters use the reviewed `input_schema` and `call_shape` instead. |
| `result` | object | yes | Result contract: `{kind: "stdout"\|"none"\|"exit"}` in the current generated candidate. |
| `effects` | array of enum | yes | Provisional registry-derived effect metadata; the reviewed stable-core subset narrows this below. |
| `dependencies` | array of module IDs | yes | Currently generated as an empty array; a validated loader graph remains future work. |
| `platforms` | array of enum | yes | `linux` and `macos` in the current candidate. Exact release evidence remains platform-specific. |
| `stability` | enum | yes | `stable`, `beta`, `experimental`, `deprecated`. |
| `aliases` | array of strings | yes | Additional names that may eventually resolve to this ID; currently generated empty. |
| `pack` | string | yes | Owning current pack (`core`, `std`, `agent`, `data`, `network`, `devops`, or `security`). |
| `profiles` | array of strings | yes | Current closures containing this export: `stable-core`, `core`, and/or `full`. |
| `ownership` | string | yes | `provisional` while ownership is derived from registry plus collision policy/probe. |
| `signature`, `idempotent`, `bash_identifier` | mixed | yes | Compatibility and adapter metadata retained from the generated registry. |

The 26 stable-core exports have an additional reviewed invocation contract.
The complete, closed source is `config/invocation-policy.json`; the generator
requires its canonical-ID set to equal the stable-core closure exactly and
merges these fields into only those manifest exports:

| Field | Contract |
|---|---|
| `contract_status` | Exactly `reviewed`. |
| `input_schema` | Closed JSON object; properties are strings or string arrays, with typed defaults for every optional field. |
| `call_shape` | Ordered `argv` mapping; string fields are `scalar`, string arrays are `spread`, and every input field is consumed exactly once. |
| `result` | One reviewed kind: `stdout`, `exit`, or `none`. |
| `effects` | Exactly one of `pure` or `read`. |
| `capabilities` | Empty for the current stable-core set. |
| `timeout_ms` / `output_limit` | Per-contract positive execution bounds. |

No default or registry guess can make another export broker-invocable. A
missing, extra, malformed, or unreviewed contract fails manifest generation.

The manifest file (`MANIFEST.json`, deterministically generated and included in
release-payload checksum coverage) carries:

```json
{
  "manifest_version": 1,
  "generated": "<UTC ISO-8601>",
  "stats": { "exports": 0, "registrations": 0, "modules": 0, "packs": 0 },
  "modules": { "<module-id>": { "pack": "...", "category": "...", "file": "lib/....sh", "registrations": 0 } },
  "exports": { "<canonical-id>": { "...fields from §3..." } },
  "name_index": { "<unique-name>": "<canonical-id>" }
}
```

`name_index` is the owner-parity oracle: **one name maps to exactly one
canonical ID**, and every surface must resolve names through it.

## 4. Canonical ID format

```text
mf:<pack>:<module>:<name>
```

Example canonical ID: `mf:data:json:json_get`.

```bash
mainframe invoke mf:data:json:json_get \
  --input-json '{"json":"{\"name\":\"Ada\"}","key":"name"}'
```

Rationale:

- **Pack-scoped**: identity survives a function moving between modules in the
  same pack only when the ID changes deliberately (a breaking change, recorded
  in release notes).
- **Collision-proof by construction**: two modules cannot mint the same ID
  without minting the same `(pack, module, name)` triple, which the generator
  rejects.
- **Bash-safe**: IDs never appear as Bash identifiers; `name` remains the only
  Bash-visible identifier, and it is unique across the manifest.

## 5. Ownership and collision rules

1. Every export has exactly one `owner` module. The generator fails the build
   if two modules claim the same `name` or the same `id`.
2. **Public stable-core collisions: zero tolerance.** A name in a `stable`
   export in pack `core` or `std` may not collide with any other export.
   (Current state: 67 public collisions — these are resolved into exactly one
   owner each during migration, §8. The later array-family migration is the
   first module-prefixed alternate-name tranche.)
3. **Private/internal collisions** (names prefixed `_`) are tolerated only
   within a single module's file and are never exported, indexed, or invoked.
4. Where two registrations of one public name both must remain reachable, the
   non-owner registration is exposed only through its own distinct canonical
   ID and a distinct unique `name` (a rename, which requires the release
   governance process and is out of Phase 0 scope).
5. Adapters (runtime loader, MCP, LSP, bindings, docs, completion) **must not**
   choose an owner or infer a call shape. They consume `name_index` and
   `exports` verbatim. An adapter that cannot resolve a name through
   `name_index` must treat it as unknown (the WS1 deny-by-default rule).

## 6. Packs and profiles

Packs per the plan: `core` (loader, manifest, output, policy, audit,
invocation), `std`, `agent`, `data`, `network`, `devops`, `security`,
`experimental`. Each pack has its own manifest fragment, compatibility
constraints, tests, checksums, and release provenance; the top-level
`MANIFEST.json` is the deterministic merge of installed pack fragments.

Profiles are **named manifest closures**:

- `full` = every installed pack compatible with the current host (§3
  `platforms`), nothing more, nothing less.
- `core` = the bootstrap kernel closure; it contains no network clients,
  package managers, domain helpers, or caller-controlled dynamic evaluation.
- Lazy loading covers 100% of manifest exports on demand.

## 7. Owner-parity target and current gate

For every profile closure `P` in `{default, core, full, lazy}` and every
surface `S` in `{runtime, MCP, LSP, nodejs binding, python binding, docs}`:

> The set of names `S` exposes under `P` equals the manifest's closure for
> `P`, and every exposed name resolves to the same canonical ID as
> `name_index`.

The current Phase 0 parity gate verifies canonical ownership, the exact
26-export stable-core closure, its MCP default-tier closure, and the reviewed
contract sidecar. Complete profile-by-profile parity across every surface in
the statement above remains a migration target.

## 8. Generation and migration path

1. **Manifest fragments from source annotations.** Each `lib/*.sh` gains (or
   keeps) machine-readable export annotations; the generator merges them into
   pack fragments, then `MANIFEST.json`. Until annotations exist, the
   generator derives fragments from the current `FUNCTIONS.json` plus the
   approved collision policy, marking derived ownership `provisional`. The
   reviewed stable-core invocation fields come only from the closed
   `config/invocation-policy.json` sidecar.
2. **Collision resolution.** For each of the 67 public collisions, the
   approved policy records the chosen owner; the generator emits exactly one
   `name_index` entry and, where required, schedules (not performs) the
   distinct-name migration for the non-owner registration.
3. **Target: everything downstream is generated.** `FUNCTIONS.json`, lazy indices,
   profile closures, MCP tool schemas, LSP metadata, shell completion,
   documentation, and binding metadata are build artifacts of the manifest.
   Checked-in artifacts must be reproducible byte-for-byte (LC_ALL=C sort,
   codepoint-safe escaping — both fixed in WS4). The stable-core broker, Pi,
   MCP, and source-candidate Node.js/Python binding paths have migrated;
   broader surfaces remain staged work.
4. **Back-compat.** `FUNCTIONS.json` keeps its current shape (including
   `stats.unique_functions`/`registrations` from WS4). Consumers migrate at
   their own pace; verification already proves that the current registry
   regenerates byte-identically from the checked manifest.

## 9. Current non-goals and limits

- The landed broker covers exactly the 26 reviewed stable-core contracts. It
  does not broker the broader legacy `core` or `full` surfaces, implement the
  general loader graph, or sign packs.
- The broker is a bounded local process boundary, not an operating-system
  sandbox and not protection against a hostile process running as the same
  user.
- Candidate source and local tests are not a public 10.2 release or final
  cross-platform evidence. Intel macOS and Linux require their own exact
  candidate proof before those claims can be promoted.
- **No unreviewed public renames.** Alternate names require the compatibility
  governance, loader-matrix evidence, and migration notes demonstrated by the
  array-family tranche.

## 10. Open questions

1. Annotation format in `lib/*.sh`: header block vs sidecar `.manifest` files
   (sidecars avoid parsing Bash; headers keep identity next to code).
2. Checksum algorithm agility: `sha256` now; record algorithm in the checksum
   string (`sha256:...`) to allow future migration.
3. Whether `aliases` participate in `name_index` (current position: no —
   aliases resolve through the export record so parity stays single-valued).
4. Evolution rules for the current `broker-json-v1` wire envelope relative to
   future `manifest_version` changes.

## 11. Landed stable-core broker behavior

The human-facing API is:

```text
mainframe invoke <canonical-id> --input-json '<closed-object>'
mainframe invoke <canonical-id> --input-json -
```

Adapters select `--profile stable-core --format broker-json-v1 --caller NAME`.
Before the broad runtime loads, the CLI resolves a trusted `jq`, verifies the
manifest and owner mapping, validates the reviewed contract and closed input,
and constructs argv only from `call_shape`. The selected owner function then
runs in a clean, protected Bash child with a fixed helper `PATH` and user
configuration disabled. Time and combined-output limits cover the child
process group, and completion/signal cleanup denies surviving descendants.
The broker reads JSON through EOF into a bounded binary-safe file and rejects
duplicate keys, literal NUL, trailing data, and oversized requests. Each
decision produces a private JSONL audit record containing identity, caller,
status, duration, bounds outcomes, and input byte count, but not input values.
An unavailable or unsafe audit target fails closed.

Pi `mainframe_exec`, the public MCP runner, and the source-candidate
Node.js/Python binding APIs delegate by canonical ID to this broker. MCP is
fixed to the 26 reviewed stable-core contracts and rejects legacy tier
configuration. Pi's human-confirmed non-stable-core route remains a guarded
legacy/unbrokered compatibility path.

## Appendix A — worked example

Current registry (excerpt):

```json
"libraries": {
  "json": { "functions": { "json_object": { "description": "...", "pure": true } } },
  "functional": { "functions": { "abs": { "...": "owner candidate A" } } },
  "pure-util":  { "functions": { "abs": { "...": "owner candidate B" } } }
}
```

Current generated manifest (abbreviated):

```json
"exports": {
  "mf:data:json:json_object": {
    "name": "json_object", "owner": "json", "stability": "stable",
    "effects": ["pure"], "pack": "data",
    "profiles": ["stable-core", "core", "full"],
    "contract_status": "reviewed",
    "input_schema": {
      "type": "object",
      "properties": {"pairs": {"type": "array", "items": {"type": "string"}, "default": []}},
      "required": [], "additionalProperties": false
    },
    "call_shape": {"kind": "argv", "arguments": [{"field": "pairs", "mode": "spread"}]},
    "result": {"kind": "stdout"}, "capabilities": [],
    "timeout_ms": 5000, "output_limit": 65536
  },
  "mf:std:functional:abs": {
    "name": "abs", "owner": "functional", "profiles": ["full"], "...": "..."
  }
},
"name_index": {
  "json_object": "mf:data:json:json_object",
  "abs": "mf:std:functional:abs"
}
```

The non-owner `pure-util` registration remains in the lossless registration
inventory for compatibility, but it does not receive a `name_index` entry.
Giving it a distinct public name is deferred and would require release
governance. Stable-core avoids this case entirely: its 26 names have zero
collisions and every broker adapter consumes the reviewed canonical owner.

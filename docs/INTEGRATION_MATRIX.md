# Mainframe for Pi: integration and evidence

Pi is the sole active coding-agent integration. Other-host adapters, standalone
MCP/LSP tooling, and the broad shell catalog remain compatibility implementation,
not additional supported coding-agent products. The previous multi-host matrix
is preserved as a [historical 10.2 reference](legacy/INTEGRATION_MATRIX-10.2.md).

## Current source inventory

`FUNCTIONS.json` records **4,401 unique functions, 4,470 registrations, and
192 libraries**. This is a generated source inventory, not a promise that every
function is loaded, reviewed, or suitable for a Pi task. Pi exposes seven
Mainframe tools and a bounded reviewed execution route.

| Pi surface | Mechanism | Evidence boundary |
|---|---|---|
| Package | `package.json` selects `skills/pi/extensions/mainframe.ts` and the Pi skill | Files on disk prove installation, not loading in a running session |
| Lifecycle | `mainframe pi status`, `install`, and `remove` preserve receipted ownership and unrelated settings | Explicit human consent is required for changes; use a new Pi session after an update |
| Shell policy | The extension verifies `security/gate-rules.json` and `security/gate-normalizer.mjs` before classification | A missing or mismatched gate fails closed; native Pi write/edit tools and arbitrary extensions are outside this shell boundary |
| Shared classifier | 44 ordered rules with per-rule input metadata | `python3 scripts/export-gate-rules.py --verify` checks 265 Bash/JavaScript parity cases; `low` means lexical no-match, not safe execution |
| Reviewed execution | Canonical function ownership, bounded arguments, and explicit approval boundaries | Ordinary coding remains on Pi's normal tools; catalog search is not a prerequisite for every command |
| Project checkpoints | Explicit Mainframe AWM session, progress, context, and handoff operations | Durable local task data; not automatic transcript storage or an external trust authority |
| Runtime status | `/mainframe doctor` inside Pi | `LOCAL_VERIFIED` is exact local runtime evidence, distinct from installed/configured/resolved/loaded state and public certification |

## Reproduce current evidence

```bash
bash scripts/test-pi-core.sh
python3 scripts/export-gate-rules.py --verify
mainframe release readiness --json
```

Run `/mainframe doctor` in the Pi session that will do the work. A previous
session can retain an older extension even after files are updated. The
[local acceptance report](testing/PI_LOCAL_ACCEPTANCE_2026-09-24.md) records a
dated run and its limits; it must not substitute for rerunning the current tree.

## Publication remains separate

`config/pi-compatibility.json` preserves historical exact-version certificates.
Only records naming the current Mainframe version can satisfy current release
coverage; old records are never promoted by changing the package version.
Offline readiness reports neither successful remote CI nor a public immutable
release or Homebrew channel. Broader historical host matrices do not certify Pi.

The strict control-plane promotion contract also requires fresh content-bound
receipts. Passing local Pi tests alone does not satisfy that separate publication
gate. See the [claims policy](CLAIMS_AND_BENCHMARKS.md).

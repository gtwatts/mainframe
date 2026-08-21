# Security Hardening Review: MAINFRAME control-plane execution authority

## Evidence Basis

We reviewed one source collection at target revision `ce0069e0e41c44ceae019e917da74c39efda587e`. Source drift was **present**: the collected control-plane and durable-invocation work includes bytes and files outside that revision. The exact collection, hashes, observed evidence, and evidence limitations are in [context.md](context.md). The machine-readable assessment is [hardening.json](hardening.json).

This is a design portfolio, not a completion or release attestation. In particular, collected tests expose a durable-envelope/transient-envelope mismatch, and the MCP and Pi adapters still show caller-specific invocation handling.

## Constraints

The hardening boundary is stable-core execution authority. We require one kernel-owned durable identity and policy chain; metadata-only ledger and Evidence; bounded owner-private transient input/result channels; no durable raw input, stdout, or stderr; and at-most-once behavior that may return `result_available=false` rather than re-execute a terminal call.

We do not broaden shell interception into a claim about host-native file, network, process, or MCP routes. We also do not describe the current supervised subprocess as an operating-system sandbox.

## Opportunity Portfolio

| Opportunity | Evidence | Options | Recommendation | Proposal |
|---|---|---|---|---|
| Centralize stable-core execution authority | Kernel identity/metadata receipts, transient transport, fixed supervisor, pending MCP/Pi callers, and source/test drift (`E001`-`E012`) | 1. Caller-local sequencing; 2. Per-request supervised kernel; 3. Owner-private daemon | Select Option 2 under the current balanced constraints; implementation remains in progress | [Centralize execution authority](proposals/centralize-execution-authority.md) |

The baseline has the lowest immediate latency and migration cost, but cannot make reservation, execution, and Evidence one trusted crash boundary. The selected option adds per-request durability and supervision while keeping raw values transient. Its deliberate tradeoff is that an interrupted caller or consumed result can leave a durable terminal receipt with no replayable raw result. The future daemon could centralize concurrency and lifecycle further, but is not supported by current need or implementation evidence.

## Recommendation Summary

Proceed with the [supervised-kernel implementation plan](implementation/supervised-kernel.md) as an incremental migration. Treat its status as **in progress** until all callers use the kernel-owned route, old direct seams fail closed, ledger privacy is proven, at-most-once crash cases pass, and one clean source revision passes the complete gate.

The architecture should prefer privacy and non-duplication over raw-result availability: persist outcome, identity, byte counts, and hashes; return raw output only through a bounded consume-once channel; and report `result_available=false` on a terminal retry when that channel is unavailable.

## Next Decisions

1. Reconcile the old durable `broker_envelope` tests with metadata-only `broker_receipt` Evidence and transient result delivery.
2. Complete the public CLI/Bash bridge, then migrate MCP and Pi without maintaining caller-local authority logic.
3. Define deletion timing and user-facing semantics for unconsumed or lost transient results.
4. Decide the same-user attacker boundary for transient files and cancellation sockets.
5. Defer a daemon until measured concurrency, latency, or lifecycle requirements justify the operational cost.

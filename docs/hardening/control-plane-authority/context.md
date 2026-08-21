# Analysis Context: Control-plane execution authority

## Scope

This portfolio evaluates one hardening opportunity: `centralize-execution-authority`. It asks where stable-core invocation identity, policy, execution, cancellation, and Evidence should be owned. It does not review arbitrary host-native file, network, process, or MCP routes, and it does not claim that an instruction-only adapter enforces those routes.

The local source root used for this analysis was `/Users/gordonwatts/Documents/Projects/mainframe`.

## Revision And Drift

- Target revision: `ce0069e0e41c44ceae019e917da74c39efda587e`.
- Collection time: `2026-08-21T00:08:24Z`.
- Source drift: **present**. Several control-plane and test files in this collection were not entries in the target revision, and tracked adapter/CLI files had worktree bytes that differed from their target-revision blobs. This portfolio therefore describes the collected source, not a clean commit, release, installed product, or completed implementation.
- Validation status: source inspection only for this portfolio. Pending implementation tests were not treated as passing evidence.

## Source Collection

The collection digest is `eeb2a638331c545ccfc20964ed1695d36046464712456c4e9cac50c9d668953d` over the following newline-terminated records in the displayed order. Each record is `sha256`, byte count, and repository-relative path.

```text
b64c0192abf06f496c3de78b931d5036897187f2a699caa2d23ac6833ad9f26d  116852  bin/mainframe
a635062fc6bfdc88f79f0e79645cd669002e2bfd7cff3b27d90d416b3dd9d7ad  44908  lib/invoke.sh
ded1944450a527119ed3644bdd5bd938e003c89b39447c471dc907212b08bdf1  19227  lib/durable_invoke.sh
b050aa6d62592508ed8659ba9b045065c5496cbba4e0c029d6cc264452e911f0  24100  control_plane/mainframe_control_plane/cli.py
158da04dcc782490e92b892125fa109c95ea644c72591e2efd1e79ac6548b54d  19667  control_plane/mainframe_control_plane/contracts.py
2feb68868910c1f0b9d436d46a60d37e289071f994a08f3d8c4d96bc8360787a  19917  control_plane/mainframe_control_plane/executor.py
e8d4e439b151c998d5b96945409af93afb8007f25112551b294713a9e94fbfb0  102347  control_plane/mainframe_control_plane/kernel.py
44288d1551c4ad091e62ee996825889effd44e8508d2a38f18eba908cd07f3b2  7222  control_plane/mainframe_control_plane/transient.py
cdb1f652c0f39a78aae0c218d206fd8a2473bc883cd9fead0fe440645e7a2b61  5801  control_plane/mainframe_control_plane/worker.py
ea192ff05fb1682f4ffc80949abc9677e6d69b985a49f144b6ea4cc4529de7be  26979  mcp/src/mainframe_mcp/executor.py
f4e438abc15d8bc041f69841bb7c72723e046da69972daf866bf8a302f907f05  8379  mcp/src/mainframe_mcp/server.py
28146dfd31890f8e4b4d0872c28db76017ea03b0be85c765cdec786d5766e8d8  136309  skills/pi/extensions/mainframe.ts
a402ee210fd2ea265001915c4a402c13e0967082a036201a07e7b3c64e0079b8  26997  config/host-capabilities.json
e2994d594b51b2d10840ac79b91acd2da914db699f79224654e83521c32d5066  8029  tests/durable_invocation.bats
e9a8da96202854a7e02de02bb68ad7ee16d8f68f3701db5ed2091d336b75a79f  6848  tests/control_plane/test_stable_core.py
84b1619ceed3e27f8a7fbf252cefa4e305ee3408df5060adfb7a0d032672a237  8287  tests/control_plane/test_supervised_executor.py
```

## Evidence Inventory

| ID | Kind | Collected source observation |
|---|---|---|
| E001 | Observed | `bin/mainframe:251-263,583-630,2855-2860` exposes a fixed hidden broker adapter and routes the public stable-core invocation toward a durable bridge while failing closed before the broad legacy dispatch. These are changing worktree bytes, not completion proof. |
| E002 | Observed | `lib/durable_invoke.sh:48-66,124-138,177-235,238-350` bounds and cleans temporary input/output transport around the control-plane CLI. It remains pending source and cannot establish installed behavior. |
| E003 | Observed | `control_plane/mainframe_control_plane/kernel.py:170-185,307-348,475-493,675-731,1860-1899,1979-2067,2475-2577` models canonical identity and input metadata, writes a metadata receipt, supports a transient result sink, and recovers a lost running call as interrupted without re-execution. |
| E004 | Observed | `control_plane/mainframe_control_plane/transient.py:1-15,31-116,119-198` implements bounded owner-private, consume-once files for raw input and the broker envelope, bound to the durable request. Raw values are excluded from the append-only ledger by design. |
| E005 | Observed | `control_plane/mainframe_control_plane/executor.py:57-104,179-285,289-454` fixes executable/argv/environment, uses an owner-private cancellation socket, isolates a process group, enforces bounds/deadlines, and keeps captured stdout/stderr transient. It is process supervision, not an operating-system sandbox. |
| E006 | Observed | `control_plane/mainframe_control_plane/worker.py:47-139` acquires a per-correlation lock, consumes staged input, drives policy and execution, publishes a transient result, and refuses to retry a running or terminal call. |
| E007 | Observed | `control_plane/mainframe_control_plane/cli.py:245-317,347-433` reports `result_available`, binds retries to the reservation, stages input, supervises a detached worker, and recovers an unresponsive running call instead of invoking it again. A completed retry can intentionally lack the raw result. |
| E008 | Observed | `mcp/src/mainframe_mcp/executor.py:623-726`, `mcp/src/mainframe_mcp/server.py:65-132,172-210`, and `skills/pi/extensions/mainframe.ts:2487-2567` retain caller-specific invocation, unverified correlation, or broker-envelope handling. Their durable kernel migration is not established by this collection. |
| E009 | Observed | `config/host-capabilities.json:44-65,69-124,143-215` distinguishes instruction/configured/enforced/live/released evidence and limits host interception claims. Shell-only evidence does not prove non-shell enforcement. |
| E010 | Observed | `tests/control_plane/test_stable_core.py:147` still expects a durable `broker_envelope`, while the collected kernel writes `broker_receipt`; `tests/control_plane/test_supervised_executor.py:78` exercises the foreground envelope. This is direct evidence of source/test drift, not a passing gate. |
| E011 | Inferred | Caller-local sequencing cannot make reservation, execution, and Evidence atomic across a crash boundary because authority remains split across independent processes. This inference follows from E001, E002, and E008. |
| E012 | Inferred | An owner-private daemon could centralize lifecycle and backpressure further, but it would add service lifecycle, upgrade, cross-platform, and isolation work not demonstrated in the collection. |

## Evidence Limits

The source shows the selected architecture taking shape, but source shape is not runtime proof. We have not used these artifacts to claim a clean-checkout pass, an installed route, a live MCP or Pi migration, a released artifact, host-wide non-shell interception, or strong worker sandboxing. Tests that name the desired behavior are implementation targets until they pass against one stable source collection.

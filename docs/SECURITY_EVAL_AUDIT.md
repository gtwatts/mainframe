# Eval Usage Security Audit

_Generated 2026-07-21 by scripts/generate-eval-audit.sh — do not edit by hand._

SECURITY.md states "No Eval by Default". This document is the authoritative
inventory of every `eval` call site in `lib/`, with its input source and
risk classification, so the claim stays honest and auditable.

## Summary

- **112** call sites across **45** libraries
- Policy: `lib/agent_safety.sh` uses a callback whitelist (no eval) for
  agent-facing execution. The sites below live in DSL/functional
  composition libraries and legacy tooling.

## Call Sites

| File | Line | Category | Input source | Risk |
|------|-----:|----------|--------------|------|
| lib/agent_context.sh | 248 | trap management | internal | low |
| lib/agent_loop.sh | 425 | string execution | caller-controlled | review |
| lib/atomic.sh | 240 | string execution | caller-controlled | review |
| lib/benchmark.sh | 116 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/benchmark.sh | 424 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/benchmark.sh | 82 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/cache.sh | 1385 | string execution | caller-controlled | review |
| lib/cache.sh | 1388 | dynamic function generation | internal (generated name) | low-ish (name must be validated) |
| lib/cache.sh | 1452 | string execution | caller-controlled | review |
| lib/codesearch.sh | 505 | string execution | caller-controlled | review |
| lib/common.sh | 372 | trap management | internal | low |
| lib/common.sh | 376 | trap management | internal | low |
| lib/compat.sh | 1082 | string execution | caller-controlled | review |
| lib/contract.sh | 125 | string execution | caller-controlled | review |
| lib/contract.sh | 167 | string execution | caller-controlled | review |
| lib/contract.sh | 208 | string execution | caller-controlled | review |
| lib/error.sh | 259 | string execution | caller-controlled | review |
| lib/error.sh | 376 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/error.sh | 417 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/fluent.sh | 1172 | string execution | caller-controlled | review |
| lib/fluent.sh | 788 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/forensics.sh | 131 | trap management | internal | low |
| lib/forensics.sh | 135 | trap management | internal | low |
| lib/functional.sh | 428 | string execution | caller-controlled | review |
| lib/functional.sh | 449 | string execution | caller-controlled | review |
| lib/functional.sh | 470 | string execution | caller-controlled | review |
| lib/functional.sh | 647 | string execution | caller-controlled | review |
| lib/generate.sh | 770 | string execution | caller-controlled | review |
| lib/generate.sh | 771 | string execution | caller-controlled | review |
| lib/graph.sh | 409 | string execution | caller-controlled | review |
| lib/graph.sh | 819 | string execution | caller-controlled | review |
| lib/graph.sh | 834 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/guard.sh | 406 | variable assignment | internal | low |
| lib/guard.sh | 419 | variable assignment | internal | low |
| lib/heal.sh | 1367 | string execution | caller-controlled | review |
| lib/heal.sh | 195 | string execution | caller-controlled | review |
| lib/heal.sh | 310 | string execution | caller-controlled | review |
| lib/heal.sh | 317 | string execution | caller-controlled | review |
| lib/heal.sh | 348 | string execution | caller-controlled | review |
| lib/health.sh | 310 | string execution | caller-controlled | review |
| lib/health.sh | 314 | string execution | caller-controlled | review |
| lib/health.sh | 498 | string execution | caller-controlled | review |
| lib/health.sh | 502 | string execution | caller-controlled | review |
| lib/idempotent.sh | 376 | string execution | caller-controlled | review |
| lib/lazy.sh | 79 | string execution | caller-controlled | review |
| lib/lazy.sh | 81 | dynamic function generation | internal (generated name) | low-ish (name must be validated) |
| lib/meta.sh | 178 | string execution | caller-controlled | review |
| lib/meta.sh | 431 | string execution | caller-controlled | review |
| lib/otel.sh | 674 | string execution | caller-controlled | review |
| lib/parallel_v2.sh | 274 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/parallel_v2.sh | 423 | string execution | caller-controlled | review |
| lib/parallel_v2.sh | 531 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/parallel_v2.sh | 814 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/parallel_v2.sh | 947 | string execution | caller-controlled | review |
| lib/parallel_v2.sh | 949 | string execution | caller-controlled | review |
| lib/parallel_v2.sh | 973 | string execution | caller-controlled | review |
| lib/parallel.sh | 1119 | string execution | caller-controlled | review |
| lib/parallel.sh | 1251 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/parallel.sh | 430 | string execution | caller-controlled | review |
| lib/parallel.sh | 431 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/parallel.sh | 562 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/parallel.sh | 660 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/parallel.sh | 757 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/perf.sh | 296 | string execution | caller-controlled | review |
| lib/perf.sh | 303 | string execution | caller-controlled | review |
| lib/perf.sh | 410 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/pipe.sh | 45 | string execution | caller-controlled | review |
| lib/pipe.sh | 46 | string execution | caller-controlled | review |
| lib/proc.sh | 581 | string execution | caller-controlled | review |
| lib/procsub.sh | 29 | string execution | caller-controlled | review |
| lib/procsub.sh | 48 | string execution | caller-controlled | review |
| lib/property_test.sh | 508 | string execution | caller-controlled | review |
| lib/property_test.sh | 533 | string execution | caller-controlled | review |
| lib/proptest.sh | 238 | string execution | caller-controlled | review |
| lib/proptest.sh | 458 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/proptest.sh | 607 | string execution | caller-controlled | review |
| lib/proptest.sh | 718 | string execution | caller-controlled | review |
| lib/proptest.sh | 730 | string execution | caller-controlled | review |
| lib/proptest.sh | 816 | string execution | caller-controlled | review |
| lib/rag.sh | 833 | string execution | caller-controlled | review |
| lib/sandbox.sh | 494 | string execution | caller-controlled | review |
| lib/secrets.sh | 453 | string execution | caller-controlled | review |
| lib/secrets.sh | 491 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/secrets.sh | 578 | string execution | caller-controlled | review |
| lib/secrets.sh | 600 | string execution | caller-controlled | review |
| lib/secrets.sh | 603 | dynamic function generation | internal (generated name) | low-ish (name must be validated) |
| lib/secrets.sh | 627 | string execution | caller-controlled | review |
| lib/secrets.sh | 655 | dynamic function generation | internal (generated name) | low-ish (name must be validated) |
| lib/service.sh | 321 | string execution | caller-controlled | review |
| lib/service.sh | 344 | string execution | caller-controlled | review |
| lib/stream.sh | 26 | string execution | caller-controlled | review |
| lib/streaming.sh | 1007 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/streaming.sh | 52 | string execution | caller-controlled | review |
| lib/streaming.sh | 60 | string execution | caller-controlled | review |
| lib/streams.sh | 1587 | string execution | caller-controlled | review |
| lib/streams.sh | 162 | string execution | caller-controlled | review |
| lib/streams.sh | 166 | string execution | caller-controlled | review |
| lib/streams.sh | 174 | string execution | caller-controlled | review |
| lib/taskgraph.sh | 167 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/testing.sh | 113 | string execution | caller-controlled | review |
| lib/testing.sh | 426 | string execution | caller-controlled | review |
| lib/testing.sh | 454 | string execution | caller-controlled | review |
| lib/tirith_hook.sh | 154 | trap management | internal | low |
| lib/tirith_inject.sh | 247 | string execution | caller-controlled | review |
| lib/tirith.sh | 409 | string execution | caller-controlled | review |
| lib/tirith.sh | 417 | string execution | caller-controlled | review |
| lib/trace.sh | 122 | string execution | caller-controlled | review |
| lib/trace.sh | 413 | trap management | internal | low |
| lib/verify.sh | 245 | string execution | caller-controlled | review |
| lib/verify.sh | 247 | string execution | caller-controlled | review |
| lib/workflow.sh | 767 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |
| lib/workflow.sh | 851 | string execution | CALLER-CONTROLLED | HIGH if unvalidated input reaches it |

## Policy

1. **New code must not add eval call sites** without updating this audit
   (CI drift check will flag it).
2. CALLER-CONTROLLED string execution sites are tech debt: each needs
   either an allowlist at the boundary or a migration to the callback
   whitelist pattern used by `agent_safety.sh`.
3. Dynamic function generation sites must validate the generated name
   (alphanumeric + underscore only).

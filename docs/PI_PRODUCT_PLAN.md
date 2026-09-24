# MAINFRAME for Pi: active product plan

Decision: September 24, 2026. Pi is Mainframe's only active coding-agent target.
This supersedes the broad scope in CONTROL_PLANE_PLAN.md and earlier inventories.

## User outcome

Install one Pi package, see whether shell protection is active, preserve a task
checkpoint across restart, and inspect blocked, failed, timed-out, or cancelled
execution.

## Acceptance criteria

1. Known gate bypasses and sibling syntax have regression coverage in Bash and
   Pi's normalizer. Benign quoted file-authoring heredocs remain usable.
2. Project memory preserves exact values and absolute expiry. Delayed execution
   cannot renew retention; recovery reaches a terminal state.
3. Durable execution enforces deadlines, private ledger boundaries and size caps,
   and cleans up owned process groups exactly once.
4. Runtime verification uses the installed Pi SDK and files. Installation,
   configuration, loading, execution, and verified behavior remain distinct.
5. Installation is recoverable. Unrelated Pi settings and the prior runtime are
   preserved. A fresh Pi session loads the intended package.
6. Installation health, one policy canary, local verification, and publication
   readiness have distinct labels.

## Active and frozen surfaces

Active: Pi extension/skill, shell policy, reviewed invocation, task memory,
runtime verification, setup, status, and recovery.

Frozen: every other coding-agent adapter, standalone MCP/LSP, bindings,
orchestration, and new Bash catalog growth. Legacy code is preserved for
existing users and recovery.

AWM stores task progress and handoffs; Pi owns conversation history; Obsidian
and other personal knowledge tools retain their own scope. Retrieved memory
does not grant instruction or execution authority.

## Evidence boundaries

The first local target is the operator's actual Linux Pi installation. Other
Pi versions/platforms require their own execution evidence. Local receipts
are bound to tested files and do not certify an upstream or public release.

Shell policy is not an OS sandbox. Native file writes/edits, arbitrary
extensions, hostile same-user processes, and unobserved routes are outside
the shell gate. Add features only when they improve a demonstrated Pi task.

# Mainframe for Pi: local acceptance, September 24, 2026

## Scope and verdict

Tested the installed, unpublished Mainframe 10.3.0 source build from commit
`45ad38b3e04768b7ddaa2eb4eb07f1bc17f31250` on Linux x86-64 with glibc,
Pi `@earendil-works/pi-coding-agent` 0.87.0 and Node 22.22.0.

This is local acceptance evidence, not a public release certificate, a claim
of flawless behavior, an agent-quality comparison, or cross-platform support.
Stress testing found a crash-recovery defect. Publication remains blocked by
that runtime defect and the metadata/evidence issues below.

## Release-blocking runtime finding

A fault-injected process exit immediately after project-memory Evidence is
persisted, but before memory aggregate creation and Run finalization, leaves
the invocation stuck. The installed public CLI did not recover it across three
fresh attempts. Durable state remained `call=succeeded`, `run=active`, one
Evidence record and zero memory aggregates.

The lead independently reproduced this against the installed build. The same
window failed both rounds of the broader stress run. No loss of acknowledged
checkpoint bytes was demonstrated; the proven defect is unfinished durable
bookkeeping and replay that cannot reach a terminal result.

`control_plane/mainframe_control_plane/memory_worker.py:82` returns early for
terminal calls without checking whether their Run still needs finalization.
`memory.py:1044` withholds a terminal public result until the Run is closed.
The existing recovery path in `memory.py:1233` can finalize a terminal call,
but the worker's early return bypasses it.

The proposed fix is narrow: allow the worker to recover an incompletely
finalized terminal call through the existing input-validated invocation path,
while preserving exactly-once effects and consumed transient-result behavior.
Add a public-CLI crash/replay regression, then install a new candidate and
rerun both ordinary and fault-injection acceptance. No fix was applied during
this testing-only pass.

The older `LOCAL_VERIFIED` receipt still matches the installed bytes and its
nine covered checks. It did not cover this newly discovered crash window and
must not be interpreted as overall release readiness.

## Completed checks

| Area | Result |
| --- | --- |
| Core acceptance | 469 passed, 2 skipped, 0 failures |
| Shell-policy parity | 265 cases matched between Bash and JavaScript |
| Installed native Pi repetitions | Five runs passed all nine check groups each |
| Installation lifecycle | Four cases passed, including an independent rerun |
| Packed distribution | Offline packing, closure checks, private extraction, native discovery, nine native checks, and removal passed |
| Real model-driven Pi workflow | Two fresh sessions completed 26 tool calls with no tool errors |
| Installed durable-core stress | 210 public invocations; 12 of 14 scenario runs passed; the same crash window failed twice |
| Fresh shell | Installation doctor passed |
| First-run proof | Invocation, checkpoint continuity, temporary-state cleanup, and classification canary passed |

Core total: 2 Node tests, 98 Python control-plane tests, 215 safety tests,
111 Pi tests, and 43 doctor/uninstall/setup tests. The two skipped cases require
an unavailable historical Pi 0.84.2 payload or a retired direct-project-storage
route. The actual installed Pi and replacement durable route were exercised
separately. Export-policy and runtime-closure checks also passed.

## Durable memory and registry stress

Seven scenario types were run twice against the installed build, with eight
parallel callers or writers in the concurrency scenarios:

- All 26 reviewed registry contracts returned the expected semantic JSON/text
  output or exit status. All 11 predicates returned exit 1 for their false
  case. Five invalid schemas or aliases were rejected without ledger writes.
- Eight callers sharing one request produced one checkpoint execution and one
  transient raw result delivery. Input substitution was rejected.
- Newline-only values, quotes, tabs, Unicode and a 24,576-byte value round-tripped
  exactly. Invalid sizes/NULs were rejected. Closed sessions remained readable
  and rejected writes.
- Eight simultaneous distinct writes produced one immediate success and seven
  explicit concurrency conflicts per round. Acknowledged values were retained;
  all conflicts recovered with fresh requests. This is safe conflict reporting,
  not automatic conflict-free parallel writing.
- Real timeout and cancellation tests passed three of each per round, with
  12 fixture processes reaped each round. Only the slow adapter was a fixture;
  the policy, durable ledger, supervisor, and cancellation path were installed
  production code.
- Delayed execution did not renew reserved TTL, an expired reservation failed
  without committing a checkpoint, and corrupted checkpoint bytes were rejected
  rather than returned or hidden behind a default.
- Crashes before execution evidence reported recovery required. Crashes after
  evidence persistence exposed the release-blocking defect described above.

## Real Pi coding and continuation

The Pi Bridge skill was used to start fresh native sessions with the user's
configured provider/model and extensions, rather than substitute a mock model.
Work was confined to a disposable, dependency-free JavaScript project and its
Mainframe project memory. Both owned test sessions were closed afterward;
unrelated running sessions were not interrupted.

1. Confirmed the installed package supplied the Mainframe command, skill, seven
   effective tools, and three hooks. The live doctor reported `LOCAL_VERIFIED`.
2. Started with five failing tests. Pi implemented the fixture function using
   its normal edit tool and passed all five through protected Bash. The supplied
   tests remained unchanged in this phase.
3. Pi searched the execution registry, inspected a reviewed pure function, and
   invoked it through `mainframe_exec`. Its JSON-string output was correct.
4. Pi initialized project AWM and saved a completion checkpoint and next step.
5. Closed that session and started a new session without its conversation
   history. Its first tool call retrieved the checkpoint. The recovered value
   matched all 711 characters exactly.
6. The new session added the requested idempotence test, passed all six tests,
   classified a harmless command as allowed and a destructive example as
   blocked without executing the latter, and saved a new checkpoint.

The lead independently reran the fixture tests and inspected the saved Pi
session records. Those records also provided evidence for early events that
the bounded bridge event buffer had evicted. No missing live events were
treated as proof of success.

## Installed lifecycle coverage

Disposable settings directories covered spaces in paths, dry-run preservation,
idempotent install/removal, reinstall, unrelated settings and package
preservation, receipted missing-source migration, alias and object-source
deduplication, malformed JSON, lock contention, and insecure receipt rejection.
Native Pi discovery verified exactly one package extension and seven tools.

Manual GNU tar extraction under this machine's `002` umask creates implicit
group-writable directories. Mainframe correctly rejects them without changing
settings. The same archive extracted under `077` installed and passed native
verification. This is a packaging/setup prerequisite, not permission to weaken
the trust check.

## Publication blockers and remaining limits

- Public claim validation fails on stale 43-rule and 183-case claims versus
  the current 44 rules and 265 cases. Some matches are historical material;
  fix current claims and historical-document handling rather than rewrite
  history as newly verified behavior.
- Control-plane release-integrity receipts and historical Pi certification
  rows still identify 10.2.0. They must not be relabeled as new certification.
- The general release check stops at `FUNCTIONS.lsp.json` identifying 10.2.0.
  Later release-check stages were not reached.
- No built release candidate exists in `dist/`, so candidate verification
  cannot pass yet.
- External offline Pi doctor remains compatibility-unverified because the
  existing Pi package manifest's permissions fail its stricter metadata
  check. Its original mode was preserved to retain Pi's own installation
  fingerprint. In-process local verification passed separately.
- Native TUI rendering, human confirmation screens, other operating systems,
  unlisted Pi versions, and prolonged production workloads were not certified.
  One small live coding fixture is not a productivity or general quality study.
- Mainframe is not an OS sandbox. Native file tools, other extensions, and
  hostile same-user processes remain outside its shell gate.

No GitHub upload, release, or public metadata change was performed. The next
publication phase must finish Pi-only positioning and reconcile the release
checks with honest Pi-specific evidence, then rerun the final candidate checks.

## Reusable commands

Set `MAINFRAME_INSTALLED_ROOT` and `MAINFRAME_PI_BIN` to the absolute paths of
the installed Mainframe build and Pi launcher under test.

```bash
bash scripts/test-pi-core.sh

node "$MAINFRAME_INSTALLED_ROOT/scripts/dev/verify-pi-runtime.mjs" \
  "$MAINFRAME_PI_BIN"

MAINFRAME_INSTALLED_ROOT="$MAINFRAME_INSTALLED_ROOT" \
MAINFRAME_PI_BIN="$MAINFRAME_PI_BIN" \
  node --test tests/pi_installed_lifecycle.test.mjs

python3 scripts/dev/stress-durable-core.py "$MAINFRAME_INSTALLED_ROOT" \
  --workers 8 --rounds 2

# This focused regression currently exits 1 on the installed build.
python3 -B scripts/dev/stress-durable-core.py "$MAINFRAME_INSTALLED_ROOT" \
  --rounds 1 --scenario real_adapter_crash_boundaries
```

The stress and lifecycle harnesses use private disposable state. They do not
modify live Pi settings or issue new runtime-verification receipts. No
production source changes were made during this testing-only pass. The
reproduced recovery defect still requires a fix and a fresh installed retest.

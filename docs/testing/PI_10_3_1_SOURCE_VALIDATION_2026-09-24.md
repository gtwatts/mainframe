# Mainframe 10.3.1 source validation

Date: September 24, 2026. Platform: Linux x86-64 with glibc. Native Pi under
test: `@earendil-works/pi-coding-agent` 0.87.0, Node 22.22.0.

## Scope

This report follows the [10.3.0 installed acceptance failure](PI_LOCAL_ACCEPTANCE_2026-09-24.md).
It records fixes and source-candidate validation, not a completed installation,
public release, cross-platform certificate, or claim that all bugs are found.
The previously installed build is not changed by these tests.

## Confirmed defects fixed

1. A project-memory worker returned early when a ToolCall was terminal, even
   when a crash had left its Run active and aggregate unfinished. The worker
   now validates exact transient input and enters the existing locked
   finalization path. This does not execute the adapter again or reconstruct
   lost transient output.
2. Pi cancellation could leave TERM-resistant descendants alive after their
   leader exited and closed its streams. Cancelled completion now kills the
   remaining owned process group before settling.
3. Capture overflow sent only TERM and could wait for the ordinary long
   timeout. Both output streams now use bounded cancellation escalation.
4. Metadata generation exceeded Linux's per-argument size limit while passing
   the full registry to jq and truncated the previous output. It now reads
   the manifest from a file and atomically replaces output after success.

The release-readiness diagnostic also now distinguishes historical Pi
certificates from current coverage. Historical records cannot make a new
release appear certified, and malformed or future-version records are rejected.

## Completed verification

| Check | Result |
| --- | --- |
| Full Pi source suite | 480 passed, 2 skipped, exit 0 |
| Bash/JavaScript classifier parity | All 265 corpus cases matched |
| Public project-memory integration | 15 passed, including 4 new regression methods with multiple subcases |
| Durable stress | 14 scenario runs passed, 212 public invocations, 8 workers, 2 rounds |
| Pi process supervision | 8 passed, independently rerun |
| Final native SDK probe | All 9 check groups passed, no live receipt written |
| Owner/metadata parity | 22 passed, including full-registry generation and failed-generation preservation |
| Claim receipt authority tests | 27 passed |
| Historical claim-count scope | 9 passed |
| Offline release-readiness tests | 9 passed |
| Issue templates | YAML parsed successfully |

The full source suite comprises 9 Node tests, 102 Python control-plane tests,
215 safety tests, 111 Pi tests, and 43 doctor/uninstall/setup tests. The two
skips require an unavailable historical Pi 0.84.2 package or a retired direct
project-storage route. The installed Pi SDK and replacement durable route were
tested separately. The focused rows overlap the full suite and must not be
added together as a unique-test count.

The public-worker regressions cover terminal success, ordinary failure,
recovery-required results, exact-input rejection before and after finalization,
and four-way recovery after Evidence, aggregate creation, and Run closure.
Evidence and aggregates remain single, adapter execution does not repeat, and
raw checkpoint and handoff contents remain absent from the durable ledger.

The real-adapter stress reproduces crash boundaries in subprocesses. Other
scenarios cover all 26 reviewed contracts, false predicates, malformed input,
byte boundaries, session closure, absolute TTL, corruption, concurrency,
timeouts, cancellation, and cleanup. Distinct concurrent writes can report
explicit conflicts; the harness re-reads and retries fresh requests. It does
not claim automatic conflict-free concurrent writes. Timeout/cancellation
stress uses a slow fixture adapter with the real supervisor and ledger.

The final native probe uses the actual installed Pi SDK with disposable
settings and projects. It verifies seven tools, hooks, protected execution,
cancellation, and a checkpoint across fresh sessions. It does not run model
inference or certify TUI rendering, human confirmation screens, arbitrary
extensions, or independently detached process sessions.

## Remaining acceptance and publication work

- Install a preserved, immutable local candidate and repeat installed lifecycle,
  stress, and native checks before selecting it in the user's Pi settings.
- Generate fresh content-bound source-claim receipts. Existing old receipts
  remain historical and still block strict public-claim validation.
- Assemble and verify the distribution candidate. No tagged release is claimed.
- Obtain exact current-version platform/CI evidence before broader release
  certification. Offline readiness remains `NOT_READY`, not a failed local
  runtime test.

The live Pi installation fingerprint was rechecked and remained unchanged.
No Mainframe installation, public push, or GitHub metadata change was performed
as part of this source-validation checkpoint.

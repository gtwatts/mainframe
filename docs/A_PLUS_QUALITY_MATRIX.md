# MAINFRAME A+ Quality Matrix

Updated: 2026-03-08

This document defines what "A+ grade" means for MAINFRAME in operational terms.
A+ is not "the tests happened to pass once." It means the repo has strict, repeatable
quality gates that contributors and CI both run the same way.

## Grade Definition

| Dimension | A+ bar | Concrete gate | Current state |
| --- | --- | --- | --- |
| Correctness | Full Bats matrix is green end to end | `./tests/run_bats_suite.sh --scope all` exits `0` | Green locally on 2026-03-08 |
| CI parity | Local and CI use the same canonical test entrypoint | `make test` and GitHub Actions both route through the same runner | Implemented in this pass |
| Cross-platform | Linux and macOS are both hard gates, not best-effort | CI jobs fail on any regression on either platform | Workflow updated; pending remote CI run |
| Known failures | No tolerated failure thresholds | No "acceptable failure count" logic in CI | Implemented in this pass |
| Lint discipline | ShellCheck is release-blocking | `lint` job must pass | Already present |
| Contributor DX | The way to run the suite is obvious and accurate in docs | README, CONTRIBUTING, tests docs all point to the same commands | Improved in this pass |
| Release hygiene | Release depends on strict quality gates | Release job waits for lint + Linux + macOS matrix | Implemented in this pass |
| Maintainability | Test selection logic has one source of truth | Suite discovery lives in one script instead of duplicated file lists | Implemented in this pass |

## What Counts As A+ For MAINFRAME

MAINFRAME earns an A+ when all of the following are true at the same time:

1. `make test` runs the full Bats matrix, not a partial subset.
2. The full Bats matrix passes locally through `tests/run_bats_suite.sh --scope all`.
3. GitHub Actions runs the same matrix on Linux and macOS with no tolerated failures.
4. Release automation is gated on those same strict checks.
5. Contributor-facing docs point to the same commands CI uses.

## Current Assessment

| Area | Grade now | Why |
| --- | --- | --- |
| Local correctness | A | Full local Bats matrix is green. |
| Local developer workflow | A | `make test` is upgraded to the real suite gate. |
| CI design | A- | Workflow is now aligned with the real suite, but needs an actual GitHub run to prove it. |
| Cross-platform confidence | A- | Full macOS matrix is green locally; GitHub macOS still needs fresh confirmation. |
| Overall | A | The repo now has A-grade local verification and A+ quality gates defined. A+ is achieved once the updated Linux and macOS CI runs are green. |

## Next A+ Steps

1. Run the updated GitHub Actions workflow and require green Linux and macOS matrix results.
2. Keep `tests/run_bats_suite.sh` as the only place that defines suite membership.
3. Refuse new platform-specific allowance thresholds unless they are temporary, documented, and tracked to removal.

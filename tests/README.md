# MAINFRAME Test Suites — Layout and Health

There are **two test trees** in this repository:

| Tree | Files | CI status | Health |
|------|-------|-----------|--------|
| `tests/unit/` (+ `tests/lib/`) | 73+ | Runs in CI (bats matrix jobs) | Canonical tree |
| `tests/*.bats` (flat) | 80+ | Safety suites run via zero-tolerance `test-safety` job | Healthy as of the platform-integration merge |

**Current state (2026-07-21): full local `--scope all` run = 169 files,
10,259 tests, ZERO failures.**

The flat tree drifted out of CI coverage historically, which is how the
Phase 1 safety gaps shipped unnoticed. The safety-relevant flat suites now
run in CI via the zero-tolerance `test-safety` job on both platforms.

## Safety-critical suites (zero tolerance, both platforms)

`agent_safety`, `security_gate`, `validation`, `confirm`, `dryrun`, `atomic`

## Historical note — resolved by the platform-integration merge

Before the AWM-consolidation merge (2026-07), the flat tree had ~600
failures, and five suites were quarantined here for architectural reasons
(in-memory shell state incompatible with `$()` invocation; dead APIs).
**Upstream rewrote those libraries and suites**; all now pass:

- `secrets.bats` 16/16 (dead `secret_init` API removed; `secrets_v2.bats`
  adds 18 more against the current API)
- `immutable.bats` 102/102
- `agent_comm.bats` 55/55
- `compose.bats` 83/83
- `observe.bats` 63/63
- `output.bats` 15/15

## Lessons encoded in the fixed suites

These bug classes were found and fixed during the hardening rounds; the
fixes are load-bearing — do not regress them:

- **Function-scope sourcing**: libs must use `declare -gA/-ga` for top-level
  arrays, or the arrays vanish when the lib is sourced inside a function
  (test helpers, lazy loaders).
- **errexit arithmetic**: `((x++))` / `((x += y))` as bare statements abort
  under `set -e`/bats when the value is 0. Use `((++x))` or `|| true`.
- **Command substitution**: state mutations inside `$(...)` die in the
  subshell. File-backed state (AWM pattern) or direct calls for mutators;
  `$()` only for pure readers.
- **GNU-isms**: `sha256sum`, `du -sb`, `tar --absolute-names`, GNU sed
  `\+`, `sed -i` (no arg), `realpath -m`, `stat -c` all break on stock
  macOS. Use the shims (`_mainframe_sha256`, `file_mode`, BRE-safe sed).
- **Dot-directory finds**: `! -path "*/\.*"` drops everything when the
  project itself lives under a dot directory. Exclude dot-components
  relative to the project root.
- **Spawned daemons**: background processes must detach inherited traps and
  close inherited fds beyond stdio, or they die on the caller's first
  non-zero command / hang the caller's pipe reader.
- **bats `run`**: assertions on shell variables must call functions
  directly (run's subshell discards them); expected-failure commands need
  `|| true` guards or `run` (bats test bodies run under errexit).

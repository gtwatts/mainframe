# MAINFRAME Test Suites — Layout and Health

There are **two test trees** in this repository, and they are not equivalent:

| Tree | Files | CI status | Health |
|------|-------|-----------|--------|
| `tests/unit/` (+ `tests/lib/`) | 73 | Runs in CI (ubuntu + macOS jobs) | Canonical tree |
| `tests/*.bats` (flat) | 82 | **Not referenced by any CI job historically** | Mixed; see below |

The flat tree drifted out of CI coverage, which is exactly how the safety
gaps fixed in the Phase 1 hardening shipped unnoticed. As of the Phase 2/3
round, the safety-relevant flat suites run in CI via the zero-tolerance
`test-safety` job.

## Flat-tree suites wired into CI (zero tolerance, both platforms)

`agent_safety`, `security_gate`, `validation`, `confirm`, `dryrun`, `atomic`

## Flat-tree suites fixed and healthy locally (not yet in CI)

- `cli` (94/94) — fixed `((i++))` errexit aborts and negative-value option parsing
- `cache` (78/78) — fixed test-model bugs (file-based counters, subshell-safe assertions)
- `checkpoint` (41/41) — fixed GNU-only `tar --absolute-names`, missing
  json_escape dependency (fallback shim added), `((x++))` errexit aborts in
  prune, plus test bugs (sed portability, unguarded expected-failure calls,
  pretty-JSON grep patterns, untestable null-byte case marked skip)
- `agent_loop` (27/27) — fixed the lib ignoring a pre-set AGENT_LOOP_DIR
  (tests had silently polluted ~/.mainframe/agent_loops), agent processes
  inheriting caller trap/errexit machinery and dying on their first benign
  non-zero command, and agents leaking inherited fds (bats output pipes)
  which hung the suite reader at EOF; plus `|| true` guards on
  expected-failure captures
- `csv`, `fuzzy` (105/112), `resilience` (73/79), `fluent` (148/148)

## Quarantined suites (structural redesign required — do not "fix" by hacking tests)

These suites fail because the **libraries' architecture is incompatible with
how the tests (and any `$()` caller) must invoke them**: state is kept in
shell variables, but the API is designed around `x=$(fn ...)` command
substitution, which runs every function in a subshell that discards all
state mutations. Making these pass requires file-backed state (the AWM
pattern), i.e. a storage-layer redesign, not test edits.

- `tests/secrets.bats` (~0/178) — tests a **dead API**: `secret_init` no longer
  exists; lib/secrets.sh now exposes `secret_register/secret_get/secret_list`.
  Needs a new suite written against the current API.
- `tests/immutable.bats` (23/102) — `imap_create` etc. return IDs via stdout
  while storing data in shell arrays; the arrays die in the `$()` subshell.
  Note: `declare -gA` scoping and time-based IDs were fixed in Phase 3; the
  remaining failure is the storage architecture.
- `tests/agent_comm.bats` (24/55) — `AGENT_RESULT=$(agent_init ...)` loses
  `AGENT_ID` in the subshell; registry writes target a path built from an
  empty ID.
- `tests/compose.bats` (39/83) — `composed=$(compose f g)` defines the composed
  function via `eval` inside a subshell; it never exists in the caller.
- `tests/observe.bats` (44/63) — OTel trace context (`_OTEL_TRACE_CTX`) is set
  via `trace_id=$(otel_trace_start ...)` in a subshell and is empty for every
  subsequent span call.
- `tests/output.bats` (92/114) — **V2 API drift**: `output_json_string` was
  replaced by `output_json_string_kv`, `MAINFRAME_OUTPUT` default changed
  text -> raw, and the `output_success` envelope format changed. Needs a
  suite rewrite against the current API (or a deliberate API compat shim).

### Redesign notes (for whoever picks these up)

- Follow the AWM storage pattern: file-backed state under a session dir with
  atomic writes and JSONL formats. Shell-variable state only for caching.
- Public APIs that must mutate state cannot be called via command
  substitution; either return values on stdout AND persist state to files,
  or take a nameref result parameter and document "do not use $()".
- `tests/secrets.bats` should be rewritten from scratch against the current
  secrets API; the old suite has no salvageable value.

## Flat-tree suites with remaining unexplored failures

`imap` (subset of immutable) — see `tests/` TAP output for details; not yet
triaged.

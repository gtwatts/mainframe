# Contributing to Mainframe for Pi

Mainframe focuses on Pi Coding Agent: shell policy, explicit project task
checkpoints, reliable execution, and evidence that describes what actually ran.
Other coding-agent adapters, standalone MCP/LSP integrations, and broad toolbox
expansion are outside active product development. Existing compatibility code
remains available; do not remove it or promise renewed support incidentally.

## Our Mission

Make ordinary Pi coding work more dependable. Priorities are correct shell
classification, recoverable project memory, bounded cancellation, clear status,
and predictable installation and rollback. Mainframe is not an OS sandbox;
native Pi write/edit and other extension tools are outside its shell gate.

Read the [product scope](docs/PI_PRODUCT_PLAN.md), [Pi workflow](skills/pi/SKILL.md),
and [security boundaries](SECURITY.md) before proposing a change.

## Current project facts

- `VERSION` is the product-version source.
- `FUNCTIONS.json` is the generated function and library inventory.
- `bash scripts/test-pi-core.sh` is the active Pi source suite.
- `.github/workflows/pi.yml` runs source contracts on Linux and macOS.
- The broad Bash matrix is retained for explicit compatibility work, not the
  default Pi acceptance target.
- Bash 4.4+ is required.

## Code of Conduct

Be excellent to each other. We're building tools for the future of AI-human collaboration.

## How Can I Contribute?

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/gtwatts/mainframe/issues)
2. Use the bug report template
3. Include Mainframe, Pi package, Node, Bash, and operating-system versions
4. Provide a minimal reproduction example
5. Describe the affected Pi workflow and redact secrets and private memory

### Suggesting Features

Start with a concrete Pi workflow, not a function-count or multi-harness goal.
Please include:

| Question | Why It Matters |
|----------|----------------|
| **Use case** | How would this improve a Pi coding task? |
| **Safety** | Does it prevent or enable dangerous operations? |
| **Pure bash** | Can it be done without external tools? |
| **Idempotency** | Is it safe to run multiple times? |
| **Output** | Does it return structured JSON? |

### Pull Requests

1. **Fork** the repo
2. **Create a branch** (`git checkout -b feature/amazing-function`)
3. **Write a regression first** in the relevant Bash, Python, or Node suite
4. **Follow the style guide** (below)
5. **Run ShellCheck** (`shellcheck lib/your_library.sh`)
6. **Run Pi source checks** (`bash scripts/test-pi-core.sh`) and affected focused tests
7. **Submit PR** with the template filled out

## Style Guide

### Function Naming

```bash
# GOOD - descriptive, lowercase, underscores
trim_string()
array_contains()
json_object()
agent_safe_exec()
awm_checkpoint()

# BAD
TrimString()    # No camelCase
trim-string()   # No hyphens in function names
ts()            # Too short, unclear
```

### Public API Compatibility

Read [Public API Compatibility](docs/API_COMPATIBILITY.md) before adding,
renaming, or deprecating a public function.

- Every public name has one canonical defining library. Never rely on loader
  order to select an implementation.
- Prefix library-specific functions with the module name. Reserve unprefixed
  names for established core primitives.
- Preserve multiple historical call shapes under one name only when dispatch
  is deterministic and every form has regression coverage.
- Deprecated names are wrappers around the canonical function. They preserve
  arguments, output, and status, warn once to stderr, and honor
  `MAINFRAME_COMPAT_WARNINGS=0`.
- A deprecated function remains for at least two documented releases and is
  not removed before the next major release.
- Annotate aliases with `@deprecated:`, `@alias-for:`, and `@remove:` in
  addition to the normal `@since:` metadata.
- Add source-level public functions to `MAINFRAME_<MODULE>_EXPORTS`.
  Membership declares public API; it does not by itself require `export -f`.
  Export a function to child Bash processes only when subprocess propagation
  is intentional and tested.
- The public-name collision set is a ratchet: a contribution may resolve an
  existing collision but must not add a new one or change the canonical owner
  across supported loader modes.

### Function Structure

```bash
# Brief description of what the function does
# Designed for AI agent use - explain safety considerations
#
# Arguments:
#   $1 - Description of first argument
#   $2 - Description of second argument (optional, default: "value")
#
# Returns:
#   0 on success, 1 on failure
#
# Outputs:
#   JSON to stdout (if MAINFRAME_OUTPUT=json)
#   Plain text otherwise
#
# Example:
#   result=$(function_name "input")
#   # {"ok":true,"data":"result"}
function_name() {
    local arg1="$1"
    local arg2="${2:-default}"

    # Validate inputs (AI agents may pass unexpected values)
    [[ -z "$arg1" ]] && { output_error "E_MISSING_ARG" "arg1 required"; return 1; }

    # Implementation
    local result="..."

    # Return structured output
    output_success "$result"
}
# Add function_name to MAINFRAME_<MODULE>_EXPORTS below. Use export -f only
# when child Bash processes are part of the documented API.
```

### Pure Bash Requirements

MAINFRAME prioritizes **Bash implementations for core primitives**:

```bash
# GOOD - Pure bash (faster, no dependencies)
to_lower() {
    printf '%s\n' "${1,,}"
}

# AVOID - External dependency (may not exist)
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}
```

External commands are acceptable for explicit integrations when:
1. The library's purpose is to wrap that host tool.
2. A Bash implementation would be incomplete or unsafe.
3. The requirement and failure behavior are documented and tested.

### Safety Requirements

For agent-facing functions:

```bash
# GOOD - Validate inputs, prevent injection
agent_safe_exec() {
    local cmd="$1"
    shift

    # Whitelist check
    [[ " ${ALLOWED_COMMANDS[*]} " =~ " $cmd " ]] || {
        output_error "E_FORBIDDEN" "Command not allowed: $cmd"
        return 1
    }

    # Execute safely (no eval)
    command "$cmd" "$@"
}

# BAD - unvalidated dynamic execution
run_command() {
    eval "$1"  # NEVER DO THIS
}

# Reviewed dynamic execution is an exception. It must validate its input,
# document why safer dispatch is insufficient, and appear in the eval audit.
```

### Idempotency

Functions should be safe to run multiple times:

```bash
# GOOD - Idempotent
ensure_dir() {
    [[ -d "$1" ]] && return 0
    mkdir -p "$1"
}

# BAD - Fails on retry
create_dir() {
    mkdir "$1"  # Fails if exists
}
```

### Structured Output

Support both JSON and plain text output:

```bash
my_function() {
    local result="success"

    if [[ "${MAINFRAME_OUTPUT:-text}" == "json" ]]; then
        json_object "ok:bool=true" "data=$result"
    else
        echo "$result"
    fi
}
```

## Testing

### Test Layers

Mainframe uses [BATS](https://github.com/bats-core/bats-core) for Bash behavior,
Python tests for durable control-plane contracts, and Node tests for the Pi
extension. Match the test to the changed layer. Source checks do not prove an
installed package is loaded in a live Pi session.

### Test File Structure

Library unit tests live in `tests/unit/`; Pi contracts also live directly under
`tests/`, with durable-kernel tests in `tests/control_plane/`:

```
tests/
  unit/
    pure-string.bats
    pure-array.bats
    json.bats
    awm.bats
    ...
  integration/
    full-workflow.bats
    ...
```

### Writing Tests

```bash
#!/usr/bin/env bats
# tests/unit/your_library.bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
    # Load the library
    source "${BATS_TEST_DIRNAME}/../../lib/your_library.sh"
}

@test "function_name returns expected result" {
    result=$(function_name "input")
    [ "$result" = "expected" ]
}

@test "function_name handles empty input" {
    run function_name ""
    [ "$status" -eq 1 ]  # Should fail gracefully
}

@test "function_name returns JSON when MAINFRAME_OUTPUT=json" {
    export MAINFRAME_OUTPUT=json
    result=$(function_name "input")
    [[ "$result" == *'"ok":true'* ]]
}
```

### Running Tests

```bash
# Install pinned repository test helpers, then run active source checks
make test-deps
bash scripts/test-pi-core.sh

# Run disposable concurrency, recovery, and retention checks
python3 -B scripts/dev/stress-durable-core.py "$PWD" --workers 8 --rounds 2

# Run unit + contract tests
./tests/run_bats_suite.sh --scope unit

# Run specific test file
./tests/bats/bin/bats tests/unit/your_library.bats

# Broader compatibility tests, when the change explicitly affects that scope
./tests/run_bats_suite.sh --scope all

# Run with verbose output
./tests/bats/bin/bats -t tests/unit/your_library.bats
```

### Test Coverage

- Aim for comprehensive coverage of all code paths
- Test both success and failure cases
- Test edge cases (empty input, special characters, large data)
- Test JSON output mode if applicable
- Test idempotency where relevant

## Agent Working Memory (AWM) Contributions

Pi project AWM stores explicit task checkpoints, discoveries, progress, and
handoffs through the durable control plane. It does not automatically remember
every conversation. Retrieved content is untrusted data, not authorization.
Pi history and personal-knowledge plugins retain their separate roles.

Pi project operations must use the durable route in `lib/durable_awm.sh` and
`control_plane/mainframe_control_plane/`. Do not add a direct-write fallback
around reservations, locks, receipts, or evidence. The low-level patterns below
are storage-maintenance references, not a replacement for that route.

### AWM Guidelines

When contributing to AWM (`lib/awm.sh`):

1. **Minimize context cost**: Every read operation should be efficient
2. **Atomic operations**: Use `_awm_atomic_write` for file writes
3. **Concurrent safety**: Use `_awm_locked_append` for shared logs
4. **JSON output**: All data structures should be JSON for parseability
5. **Token awareness**: Include token estimates for read operations

### AWM Function Pattern

```bash
# @pre: active session
# @post: describe state changes
# @idempotent: yes/no - explain behavior on retry
# @returns: return code and output description
#
# Description of what the function does.
# Include AI agent use case.
#
# Usage: awm_function "arg"
# Example: result=$(awm_function "value")
awm_function() {
    local arg="$1"

    if [[ -z "$_AWM_SESSION_ID" ]]; then
        _awm_log error "awm_function: no active session"
        return 1
    fi

    # Implementation with atomic writes
    _awm_atomic_write "$file" "$content"
}
```

### AWM Tests

AWM tests should verify:
- Session lifecycle (init, resume, close)
- Data persistence across function calls
- Crash recovery without duplicate adapter execution
- Exact replay, conflicts, and fresh retries
- Retention, byte limits, and sensitive-content exclusion from the ledger
- Cancellation, timeout cleanup, and concurrent access safety

## Library Organization

This table maps the retained Bash catalog for maintenance. It is not an active
roadmap or a promise of Pi support for every library.

| Library | Purpose | Add functions here if... |
|---------|---------|-------------------------|
| **Core** | | |
| `pure-string.sh` | String manipulation | Text processing |
| `pure-array.sh` | Array operations | Working with bash arrays |
| `pure-file.sh` | File operations | File I/O |
| `json.sh` | JSON generation | Creating/parsing JSON |
| **Agent Infrastructure** | | |
| `awm.sh` | Agent Working Memory | Session persistence, state inheritance |
| `agent_safety.sh` | Safe execution | Command dispatch, validation |
| `agent_comm.sh` | Multi-agent | Agent coordination, messaging |
| `output.sh` | USOP | Structured output envelopes |
| `validation.sh` | Input validation | Sanitization, path safety |
| **Operations** | | |
| `idempotent.sh` | Retry-safe ops | `ensure_*` functions |
| `atomic.sh` | Safe file ops | Atomic writes, checkpoints |
| `observe.sh` | Observability | Tracing, logging |
| `context.sh` | Token budgeting | Context window management |
| `diff.sh` | Surgical editing | File patches, search-replace |
| `cache.sh` | Memoization | Performance optimization |
| **Utilities** | | |
| `datetime.sh` | Date/time | Date arithmetic, formatting |
| `http.sh` | HTTP client | GET/POST without curl/wget |
| `csv.sh` | CSV parsing | RFC 4180 CSV handling |
| `git.sh` | Git helpers | Branch, commit, status info |
| `crypto.sh` | Cryptography | Hashing, encoding, tokens |

## Continuous Integration

The active Pi workflow runs source contracts on pull requests and configured
branches. The older broad workflow is manual-only compatibility coverage.

| Job | Description |
|-----|-------------|
| **Pi source contracts, Linux** | `bash scripts/test-pi-core.sh` |
| **Pi source contracts, macOS** | The same source suite on macOS |

### CI Requirements

Before your PR can be merged:
- [ ] ShellCheck passes with no new warnings
- [ ] Active Pi source contracts pass on supported CI platforms
- [ ] Changed installed-runtime behavior has separate native Pi evidence
- [ ] Skips, unavailable platforms, and untested UI behavior are disclosed

### Local CI Simulation

```bash
# Run ShellCheck
shellcheck -x lib/your_library.sh

# Run the active source suite CI uses
bash scripts/test-pi-core.sh
```

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add array_shuffle function
fix: handle empty string in trim_string
docs: update README with agent examples
test: add tests for json_object edge cases
perf: optimize array_unique using associative arrays
security: add input validation to agent_safe_exec
fix(awm): preserve checkpoint evidence across Pi restart
```

## Review Checklist

Before submitting, verify:

- [ ] ShellCheck passes with no warnings
- [ ] Pi source checks and the affected focused tests pass
- [ ] New behavior has regression coverage in the appropriate test layer
- [ ] Public functions are listed in `MAINFRAME_<MODULE>_EXPORTS`
- [ ] No new public-name collision or loader-order-dependent owner is introduced
- [ ] Aliases include migration annotations, warning coverage, and a removal floor
- [ ] CHEATSHEET.md updated (for new public functions)
- [ ] No `eval` used (or justified and security-reviewed)
- [ ] Works on Bash 4.4+
- [ ] Platform and installed-Pi claims match the evidence actually collected
- [ ] No unrelated system packages, settings, or integrations were changed

## Questions?

- **General questions**: [Discussions](https://github.com/gtwatts/mainframe/discussions)
- **Bug reports**: [Issues](https://github.com/gtwatts/mainframe/issues)
- **Feature ideas**: [Feature Request](https://github.com/gtwatts/mainframe/issues/new?template=feature_request.yml)

---

Contributions should make Pi workflows dependable without overstating the
protection boundary or verification results.

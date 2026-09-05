# Contributing to MAINFRAME

Help coding agents work more safely and reliably in native shells. We welcome
small, reproducible improvements from people using MAINFRAME, building agent
integrations, or testing its limits.

## Our Mission

MAINFRAME brings policy checks, reviewed tools, and durable project memory to
coding-agent workflows. Our goal is fewer mistakes and interruptions with
less repeated setup. Protection applies to documented routes; MAINFRAME is
not an OS sandbox or a guarantee against damage.

The [control-plane roadmap](docs/CONTROL_PLANE_PLAN.md) owns implementation
order and readiness evidence. The [open-source growth plan](docs/OPEN_SOURCE_GROWTH_PLAN.md)
adds contributor work packages, pilot criteria, and distribution milestones.
Prefer completing a useful supported workflow over adding another library.

## Choose a first contribution

| Starting point | A useful small submission |
|---|---|
| You tried MAINFRAME | A sanitized reproduction of one install, discovery, update, or recovery problem |
| You know Bash or zsh | One CLI caller fixture with exact shell/runtime versions and expected output |
| You build an agent adapter | One contract test for structured results, denial, or unsupported-host reporting |
| You write documentation | One corrected example or a short demo tied to an exact commit and tested route |
| You use project memory | One interrupted-task or fresh-session handoff reproduction |

See [work packages](docs/OPEN_SOURCE_GROWTH_PLAN.md#work-packages), or browse
[good first issues](https://github.com/gtwatts/mainframe/labels/good%20first%20issue)
and [help wanted](https://github.com/gtwatts/mainframe/labels/help%20wanted).
These labels are entry points, not a promise that a task is currently open.
For a substantial change, agree the use case, owner, paths, dependencies, and
acceptance criteria in an issue before implementation. A documentation correction
can go straight to a focused PR.

## Current project facts

- `VERSION` is the product-version source.
- `FUNCTIONS.json` is the generated function and library inventory.
- `./tests/run_bats_suite.sh --scope all` is the supported Bash suite.
- Bash 4.4+ is required.
- Priority caller cells are macOS/Bash, macOS/zsh, Linux/Bash, and Linux/zsh.
  Bash libraries execute in Bash 4.4+; zsh CLI use does not prove native zsh
  sourcing. Report the cells you actually tested and leave the others unverified.

## Code of Conduct

Be excellent to each other. We're building tools for the future of AI-human collaboration.

## How Can I Contribute?

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/gtwatts/mainframe/issues)
2. Use the bug report template
3. Include MAINFRAME commit/version, agent version, calling shell, and actual Bash runtime version
4. Provide a minimal reproduction example
5. Note if the bug affects AI agent behavior

Remove credentials, private paths, prompts, and project contents from reports.
For vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of opening a
public issue. For ordinary failures, include the expected successful operation
as well as what failed; unnecessary denials matter too.

### Suggesting Features

Start with a recurring user problem and a way to measure the improvement:

| Question | Why It Matters |
|----------|----------------|
| **Use case** | How would an AI agent use this? |
| **Safety** | Does it prevent or enable dangerous operations? |
| **Pure bash** | Can it be done without external tools? |
| **Idempotency** | Is it safe to run multiple times? |
| **Output** | Does it return structured JSON? |

### Pull Requests

1. **Fork** the repo
2. **Create a branch** (`git checkout -b feature/amazing-function`)
3. **Write tests first** (BATS tests in `tests/unit/`)
4. **Follow the style guide** (below)
5. **Run ShellCheck** (`shellcheck lib/your_library.sh`)
6. **Run tests locally** (`./tests/run_bats_suite.sh --scope all`)
7. **Submit PR** with the template filled out

Use the focused tests for your change during development. Before requesting
merge, report the required checks and exact commit they ran against. A skipped
or blocked CI lane is not a pass. Documentation-only work needs working links,
accurate commands, and scoped claims; it does not need invented behavior tests.

### Working with coding agents

Give each agent a bounded task: problem, owned paths, allowed effects,
dependencies, acceptance criteria, and reviewer. Check for existing work before
editing shared files. Keep implementation, installed-host validation, release,
and external outreach as separate actions with their own authorization.

AI-assisted PRs are welcome. The human submitter must understand the diff,
reproduce its checks, and respond to review. Report material tool limitations
and untested cells. Do not paste generated success claims in place of evidence.

For first-use reproduction, follow [Agent onboarding](docs/AGENT_ONBOARDING.md)
and record the [readiness checklist](docs/AGENT_READINESS_CHECKLIST.md).

For adapters, start with the [adapter model](docs/CONTROL_PLANE_PLAN.md#adapter-model),
[API compatibility contract](docs/API_COMPATIBILITY.md),
[host evidence](docs/INTEGRATION_MATRIX.md), and the
[MCP interface](mcp/README.md). Test valid work, denial, unavailable support,
argument/result contracts, and failure recovery without a permissive fallback.
Discovery through an instruction file is distinct from runtime enforcement.

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

### BATS Framework

MAINFRAME uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System). Every new function needs BATS tests.

### Test File Structure

Tests are organized in `tests/unit/` with one test file per library:

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
# Run the full Bats matrix
./tests/run_bats_suite.sh --scope all

# Run unit + contract tests
./tests/run_bats_suite.sh --scope unit

# Run specific test file
./tests/bats/bin/bats tests/unit/your_library.bats

# Run integration tests
./tests/run_bats_suite.sh --scope integration

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

AWM is MAINFRAME's persistent external memory system for AI agents. It enables:
- Session persistence across context limits
- Sub-agent state inheritance
- Discovery tracking and compression
- Token budget estimation

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
- Sub-agent inheritance
- Token estimation accuracy
- Compression behavior
- Concurrent access safety

## Library Organization

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

All PRs run through GitHub Actions CI:

| Job | Description |
|-----|-------------|
| **Lint** | ShellCheck on all `.sh` files |
| **Linux Bats Matrix** | Full BATS matrix via `tests/run_bats_suite.sh --scope all` |
| **macOS Bats Matrix** | Full cross-platform verification via the same runner |

### CI Requirements

Before your PR can be merged:
- [ ] ShellCheck passes with no new warnings
- [ ] The full Linux Bats matrix passes
- [ ] The full macOS Bats matrix passes

### Local CI Simulation

```bash
# Run ShellCheck
shellcheck -x lib/your_library.sh

# Run the same full suite CI uses
./tests/run_bats_suite.sh --scope all
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
feat(awm): add session inheritance for sub-agents
```

## Review Checklist

Before submitting, verify:

- [ ] ShellCheck passes with no warnings
- [ ] All tests pass (`./tests/run_bats_suite.sh --scope all`)
- [ ] New functions have BATS tests
- [ ] Public functions are listed in `MAINFRAME_<MODULE>_EXPORTS`
- [ ] No new public-name collision or loader-order-dependent owner is introduced
- [ ] Aliases include migration annotations, warning coverage, and a removal floor
- [ ] CHEATSHEET.md updated (for new public functions)
- [ ] No `eval` used (or justified and security-reviewed)
- [ ] Works on Bash 4.4+
- [ ] Works on both Linux and macOS (if applicable)

## Questions?

- **General questions**: [Discussions](https://github.com/gtwatts/mainframe/discussions)
- **Bug reports**: [Issues](https://github.com/gtwatts/mainframe/issues)
- **Feature ideas**: [Feature Request](https://github.com/gtwatts/mainframe/issues/new?template=feature_request.yml)

---

**Building for a safe and accurate agentic future.**

*"Mainframe can make a computer do anything short of tap dance."*

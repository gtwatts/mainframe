# Contributing to MAINFRAME

```
+============================================================================+
|  BUILDING THE AI-NATIVE BASH RUNTIME                                       |
|  4,000+ functions | 117 libraries | 6,500+ tests                           |
|  Every contribution makes AI agents safer and more accurate                |
+============================================================================+
```

Thank you for considering contributing to MAINFRAME! We're building a safe, efficient runtime for AI agents that control computer systems through bash.

## Our Mission

**AI agents control computers through bash. MAINFRAME makes that safe, accurate, and efficient.**

Every function you contribute helps AI agents:
- Execute commands safely (no accidental `rm -rf /`)
- Get first-time correctness (structured output, clear errors)
- Save tokens (one function call vs. 15 lines of fragile bash)
- Maintain persistent memory across sessions (Agent Working Memory)

## Quick Stats

| Metric | Count |
|--------|-------|
| Libraries | 117 |
| Functions | 4,000+ |
| Tests | 6,500+ |
| Bash Version | 4.0+ |

## Code of Conduct

Be excellent to each other. We're building tools for the future of AI-human collaboration.

## How Can I Contribute?

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/gtwatts/mainframe/issues)
2. Use the bug report template
3. Include your bash version (`bash --version`)
4. Provide a minimal reproduction example
5. Note if the bug affects AI agent behavior

### Suggesting Features

New function ideas are welcome! Please include:

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
6. **Run tests locally** (`./tests/bats/bin/bats tests/unit/`)
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
export -f function_name
```

### Pure Bash Requirements

MAINFRAME prioritizes **pure bash** solutions:

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

Only use external tools when:
1. Pure bash is impossible (e.g., HTTPS requires openssl)
2. Performance difference is >10x
3. It's clearly documented and optional

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

# BAD - Injection risk
run_command() {
    eval "$1"  # NEVER DO THIS
}
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
# Run all unit tests
./tests/bats/bin/bats tests/unit/

# Run specific test file
./tests/bats/bin/bats tests/unit/your_library.bats

# Run integration tests
./tests/bats/bin/bats tests/integration/

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
| **Unit Tests** | BATS tests in `tests/unit/` |
| **Integration Tests** | BATS tests in `tests/integration/` |
| **macOS Compatibility** | Cross-platform verification |

### CI Requirements

Before your PR can be merged:
- [ ] ShellCheck passes with no new warnings
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] macOS compatibility tests pass (within threshold)

### Local CI Simulation

```bash
# Run ShellCheck
shellcheck -x lib/your_library.sh

# Run all tests
./tests/bats/bin/bats tests/unit/ tests/integration/
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
- [ ] All tests pass (`./tests/bats/bin/bats tests/unit/`)
- [ ] New functions have BATS tests
- [ ] Functions are exported (`export -f function_name`)
- [ ] CHEATSHEET.md updated (for new public functions)
- [ ] No `eval` used (or justified and security-reviewed)
- [ ] Works on Bash 4.0+
- [ ] Works on both Linux and macOS (if applicable)

## Questions?

- **General questions**: [Discussions](https://github.com/gtwatts/mainframe/discussions)
- **Bug reports**: [Issues](https://github.com/gtwatts/mainframe/issues)
- **Feature ideas**: [Feature Request](https://github.com/gtwatts/mainframe/issues/new?template=feature_request.yml)

---

**Building for a safe and accurate agentic future.**

*"Mainframe can make a computer do anything short of tap dance."*

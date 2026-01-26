# Contributing to MAINFRAME

```
╔══════════════════════════════════════════════════════════════════╗
║  BUILDING THE AI-NATIVE BASH RUNTIME                             ║
║  Every contribution makes AI agents safer and more accurate      ║
╚══════════════════════════════════════════════════════════════════╝
```

Thank you for considering contributing to MAINFRAME! We're building a safe, efficient runtime for AI agents that control computer systems through bash.

## Our Mission

**AI agents control computers through bash. MAINFRAME makes that safe, accurate, and efficient.**

Every function you contribute helps AI agents:
- Execute commands safely (no accidental `rm -rf /`)
- Get first-time correctness (structured output, clear errors)
- Save tokens (one function call vs. 15 lines of fragile bash)

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
3. **Write tests first** (BATS tests in `tests/`)
4. **Follow the style guide** (below)
5. **Run ShellCheck** (`shellcheck lib/your_library.sh`)
6. **Submit PR** with the template filled out

## Style Guide

### Function Naming

```bash
# GOOD - descriptive, lowercase, underscores
trim_string()
array_contains()
json_object()
agent_safe_exec()

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

Every new function needs BATS tests:

```bash
@test "function_name returns expected result" {
    source lib/your_library.sh
    result=$(function_name "input")
    [ "$result" = "expected" ]
}

@test "function_name handles empty input" {
    source lib/your_library.sh
    run function_name ""
    [ "$status" -eq 1 ]  # Should fail gracefully
}

@test "function_name returns JSON when MAINFRAME_OUTPUT=json" {
    source lib/your_library.sh
    export MAINFRAME_OUTPUT=json
    result=$(function_name "input")
    [[ "$result" == *'"ok":true'* ]]
}
```

Run tests:
```bash
./tests/bats/bin/bats tests/
# Or specific test file
./tests/bats/bin/bats tests/your_test.bats
```

## Library Organization

| Library | Purpose | Add functions here if... |
|---------|---------|-------------------------|
| **Core** | | |
| `pure-string.sh` | String manipulation | Text processing |
| `pure-array.sh` | Array operations | Working with bash arrays |
| `pure-file.sh` | File operations | File I/O |
| `json.sh` | JSON generation | Creating/parsing JSON |
| **Agent Safety** | | |
| `agent_safety.sh` | Safe execution | Command dispatch, validation |
| `agent_comm.sh` | Multi-agent | Agent coordination, messaging |
| `output.sh` | USOP | Structured output envelopes |
| `validation.sh` | Input validation | Sanitization, path safety |
| **Infrastructure** | | |
| `idempotent.sh` | Retry-safe ops | `ensure_*` functions |
| `atomic.sh` | Safe file ops | Atomic writes, checkpoints |
| `observe.sh` | Observability | Tracing, logging |
| **Utilities** | | |
| `datetime.sh` | Date/time | Date arithmetic, formatting |
| `http.sh` | HTTP client | GET/POST without curl/wget |
| `csv.sh` | CSV parsing | RFC 4180 CSV handling |
| `git.sh` | Git helpers | Branch, commit, status info |
| `crypto.sh` | Cryptography | Hashing, encoding, tokens |

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add array_shuffle function
fix: handle empty string in trim_string
docs: update README with agent examples
test: add tests for json_object edge cases
perf: optimize array_unique using associative arrays
security: add input validation to agent_safe_exec
```

## Review Checklist

Before submitting, verify:

- [ ] ShellCheck passes with no warnings
- [ ] All tests pass (`./tests/bats/bin/bats tests/`)
- [ ] New functions have BATS tests
- [ ] Functions are exported (`export -f function_name`)
- [ ] CHEATSHEET.md updated (for new public functions)
- [ ] No `eval` used (or justified and security-reviewed)
- [ ] Works on Bash 4.0+

## Questions?

- **General questions**: [Discussions](https://github.com/gtwatts/mainframe/discussions)
- **Bug reports**: [Issues](https://github.com/gtwatts/mainframe/issues)
- **Feature ideas**: [Feature Request](https://github.com/gtwatts/mainframe/issues/new?template=feature_request.yml)

---

**Building for a safe and accurate agentic future.**

*"Knowing Your Shell is half the battle."*

# Contributing to MAINFRAME

```
╔══════════════════════════════════════════════════════════════════╗
║ ★ ★ ★  WELCOME TO THE G.I. JOE TEAM, SOLDIER!                    ║
╚══════════════════════════════════════════════════════════════════╝
```

First off, thank you for considering contributing to MAINFRAME! Every contribution helps make Claude Code and other AI coding assistants more powerful.

## Code of Conduct

Be excellent to each other. We're all here to make bash scripting better.

## How Can I Contribute?

### Reporting Bugs

- Check if the bug has already been reported in Issues
- Use the bug report template
- Include your bash version (`bash --version`)
- Provide a minimal reproduction example

### Suggesting Features

New function ideas are welcome! Please include:
- **Use case**: How would Claude Code use this?
- **Pure bash**: Can it be done without external tools?
- **Performance**: Is it faster than the alternative?

### Pull Requests

1. **Fork** the repo
2. **Create a branch** (`git checkout -b feature/amazing-function`)
3. **Write tests** (BATS tests in `tests/`)
4. **Follow the style guide** (below)
5. **Submit PR** with clear description

## Style Guide

### Function Naming

```bash
# Good - descriptive, lowercase, underscores
trim_string()
array_contains()
json_object()

# Bad
TrimString()    # No camelCase
trim-string()   # No hyphens in function names
ts()            # Too short, unclear
```

### Function Structure

```bash
# Function description
# Arguments:
#   $1 - Description of first argument
#   $2 - Description of second argument (optional)
# Returns:
#   0 on success, 1 on failure
# Outputs:
#   Writes result to stdout
function_name() {
    local arg1="$1"
    local arg2="${2:-default}"

    # Implementation
}
```

### Pure Bash Requirements

MAINFRAME prioritizes **pure bash** solutions:

```bash
# GOOD - Pure bash
to_lower() {
    printf '%s\n' "${1,,}"
}

# AVOID - External dependency
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}
```

Only use external tools when:
1. Pure bash is impossible
2. Performance is significantly better
3. It's clearly documented

### Testing

Every new function needs a BATS test:

```bash
@test "function_name does what it should" {
    result=$(function_name "input")
    [ "$result" = "expected" ]
}

@test "function_name handles edge cases" {
    result=$(function_name "")
    [ "$result" = "" ]
}
```

Run tests:
```bash
bats tests/
```

## Library Organization

| Library | Purpose | Add functions here if... |
|---------|---------|-------------------------|
| `pure-string.sh` | String manipulation | Text processing without sed/awk |
| `pure-array.sh` | Array operations | Working with bash arrays |
| `pure-file.sh` | File operations | File I/O without cat/head/tail |
| `pure-util.sh` | Utilities | General helpers (UUID, timestamps) |
| `json.sh` | JSON generation | Creating/parsing JSON |
| `async.sh` | Async operations | Background jobs, parallel execution |
| `ansi.sh` | Terminal UI | Colors, formatting, progress bars |
| `semver.sh` | Versioning | Semantic version handling |
| `common.sh` | Core utilities | Logging, errors, validation |

## Commit Messages

Follow conventional commits:

```
feat: add array_shuffle function
fix: handle empty string in trim_string
docs: update README with new examples
test: add tests for json_object
perf: optimize array_unique by 3x
```

## Questions?

Open an issue with the `question` label.

---

**YO JOE!**

*"Knowing Your Shell is half the battle."*

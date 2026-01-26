# Security Policy

## MAINFRAME Security Philosophy

MAINFRAME is designed as an **AI-Native Bash Runtime** where security is foundational, not an afterthought. AI agents controlling computer systems through bash commands must operate within strict safety boundaries.

### Core Security Principles

1. **No Eval by Default** - Command execution uses safe dispatch patterns, not `eval`
2. **Validate Before Execute** - All inputs validated before any system operation
3. **Structured Errors** - Errors return JSON for AI self-correction, not ambiguous text
4. **Audit Everything** - All agent operations can be logged for traceability
5. **Fail Safely** - Operations fail closed, never fail open
6. **Defense in Depth** - Multiple layers of validation and sanitization

## Supported Versions

| Version | Supported          | Security Updates |
| ------- | ------------------ | ---------------- |
| 5.x     | :white_check_mark: | Active           |
| 4.x     | :white_check_mark: | Security only    |
| 3.x     | :white_check_mark: | Security only    |
| < 3.0   | :x:                | End of life      |

## Reporting a Vulnerability

We take security vulnerabilities seriously, especially given MAINFRAME's role in AI agent automation.

### How to Report

1. **DO NOT** open a public issue for security vulnerabilities
2. Use [GitHub Security Advisories](https://github.com/gtwatts/mainframe/security/advisories/new) (preferred)
3. Or email security concerns to the repository owner
4. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact (especially for AI agent scenarios)
   - Affected functions/libraries
   - Suggested fix (if any)

### What to Expect

| Severity | Response Time | Fix Timeline |
|----------|---------------|--------------|
| **Critical** (RCE, privilege escalation) | 24 hours | 24-72 hours |
| **High** (data exposure, unsafe execution) | 48 hours | 7 days |
| **Medium** (input validation bypass) | 7 days | 14 days |
| **Low** (minor issues) | 14 days | Next release |

### Scope

Security issues we're particularly concerned about:

| Category | Examples | Impact |
|----------|----------|--------|
| **Command Injection** | Unsanitized input passed to commands | Full system compromise |
| **Path Traversal** | Bypassing `path_is_safe` validation | Unauthorized file access |
| **TOCTOU Races** | Time-of-check to time-of-use | Race condition exploits |
| **Unsafe Deserialization** | JSON parsing that executes code | Arbitrary code execution |
| **Privilege Escalation** | Agent operations gaining unintended access | System compromise |
| **Information Disclosure** | Leaking sensitive data in errors/logs | Data breach |

### Out of Scope

- Issues requiring physical access to the machine
- Social engineering attacks
- Denial of service (unless trivially exploitable)
- Issues in external dependencies (report to their maintainers)
- Theoretical vulnerabilities without proof of concept

## Security Features

### Agent Safety Library (`lib/agent_safety.sh`)

Safe command execution for AI agents:

```bash
source lib/agent_safety.sh

# Safe command dispatch - no eval, whitelisted commands only
agent_safe_exec "ls" "-la" "/safe/path"

# Command validation before execution
agent_validate_command "git" "status" || die 1 "Command not allowed"

# Idempotent operations - safe to retry
agent_ensure_dir "/path/to/dir"
agent_ensure_file "/path/to/file" "content"

# Full audit logging
agent_audit_log "created" "/path/to/file"
```

### Validation Library (`lib/validation.sh`)

Input validation and sanitization:

```bash
source lib/validation.sh

# Path validation - prevents directory traversal
validate_path_safe "$user_input" "/allowed/base" || die 1 "Path traversal detected"

# Command safety - detects injection attempts
validate_command_safe "$cmd" || die 1 "Injection detected"

# Shell argument sanitization
safe_arg=$(sanitize_shell_arg "$untrusted_input")

# Build properly escaped commands
safe_cmd=$(build_safe_command "grep" "$pattern" "$file")
```

### USOP (Universal Structured Output Protocol)

Structured errors for AI self-correction:

```bash
source lib/output.sh
export MAINFRAME_OUTPUT=json

# Errors include machine-parseable details
output_error "E_PATH_TRAVERSAL" "Path traversal detected" "Use absolute paths within allowed directory"
# {"ok":false,"error":{"code":"E_PATH_TRAVERSAL","msg":"Path traversal detected","suggestion":"Use absolute paths within allowed directory"}}
```

### Atomic Operations (`lib/atomic.sh`)

Safe file operations with rollback:

```bash
source lib/atomic.sh

# Atomic write - temp file then rename, prevents partial writes
atomic_write "/important/file" "content"

# Checkpoint before risky operations
file_checkpoint "/config/file"

# Rollback if something goes wrong
file_rollback "/config/file"
```

## Security Best Practices for AI Agents

### Always Validate External Input

```bash
# GOOD: Validate before use
validate_path_safe "$user_path" "/allowed" || exit 1
validate_int "$user_count" 1 100 || exit 1

# BAD: Direct use of untrusted input
cd "$user_path"  # Path traversal risk
```

### Use Safe Command Execution

```bash
# GOOD: Safe dispatch
agent_safe_exec "ls" "-la" "$validated_path"

# BAD: String concatenation
eval "ls -la $user_input"  # Command injection
```

### Handle Errors Gracefully

```bash
# GOOD: Structured error handling
if ! result=$(some_operation 2>&1); then
    output_error "E_OPERATION_FAILED" "Operation failed" "Check permissions"
    exit 1
fi

# BAD: Ignoring errors
some_operation || true  # Silent failure
```

### Use Idempotent Operations

```bash
# GOOD: Safe to retry
ensure_dir "/path/to/dir"
ensure_file "/path/to/file" "content"

# BAD: Fails on retry
mkdir "/path/to/dir"  # Fails if exists
```

### Log Security-Relevant Operations

```bash
# Enable audit logging
export AGENT_AUDIT_LOG="/var/log/agent_audit.log"

# Operations are automatically logged
agent_safe_exec "chmod" "755" "/path/to/script"
# Logged: [timestamp] EXEC chmod 755 /path/to/script -> success
```

## Known Security Considerations

### Eval Usage

MAINFRAME minimizes but cannot completely eliminate `eval`. Current `eval` usage:

| Location | Purpose | Mitigation |
|----------|---------|------------|
| `cli.sh` | Dynamic function dispatch | Validated command names only |
| `template.sh` | Variable expansion | Sandboxed context |

We actively work to eliminate or sandbox remaining `eval` usage.

### Race Conditions

Some operations have inherent TOCTOU windows:

- File existence checks before writes
- Lock acquisition

Use atomic operations (`atomic_write`, `with_lock`) where possible.

## Security Acknowledgments

We gratefully acknowledge security researchers who help keep MAINFRAME safe:

*No acknowledgments yet - be the first!*

---

*MAINFRAME: Building for a safe and accurate agentic future.*

**[Report a Vulnerability](https://github.com/gtwatts/mainframe/security/advisories/new)** | **[Security Best Practices](#security-best-practices-for-ai-agents)**

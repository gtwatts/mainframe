# Verification Functions

Command Verification Engine - static analysis and validation for bash commands without execution. Detects errors, typos, dangerous patterns, and estimates resource usage.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Public API (verify.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `verify_command` | `verify_command "cmd_string"` | Verify a single command for typos, dangerous patterns, undefined variables, command existence, and style issues. Returns JSON: `{valid, issues[], suggestions[], meta{}}` |
| `verify_pipeline` | `verify_pipeline "cmd1 \| cmd2"` | Verify a pipeline with pipeline-specific checks (useless cat, multiple greps, data flow). Returns JSON with per-stage and pipeline-level issues. |
| `verify_estimate` | `verify_estimate "cmd"` | Estimate resource usage (time, memory, confidence) based on command profiles. Returns JSON: `{estimates{time_s, memory_mb, confidence}, meta{}}` |
| `verify_suggest_fix` | `verify_suggest_fix "error_output"` | Suggest fixes based on error patterns (command not found, permission denied, no such file, syntax error). Returns JSON: `{fixes[], confidence, meta{}}` |
| `verify_and_heal` | `verify_and_heal "cmd"` | Verify a command and return auto-healed version if issues found. Returns JSON: `{valid, original, healed, issues, meta{was_modified}}` |

---

## Issue Types

| Type | Severity | Description |
|------|----------|-------------|
| `typo` | error | Common command typos (e.g., `sl` -> `ls`, `gti` -> `git`) |
| `dangerous` | critical/warning | Destructive patterns (`rm -rf /`, fork bombs, `curl \| bash`) |
| `undefined` | warning | Unquoted or undefined variables |
| `syntax` | error | Command not found in PATH |
| `style` | style | Backtick substitution, non-portable echo flags |
| `performance` | info | Useless cat, multiple greps, awk after grep |

---

## Usage Examples

```bash
# Check for typos
result=$(verify_command "sl -la")
# {"valid":false,"issues":[{"type":"typo","severity":"error","msg":"Possible typo: 'sl' -> did you mean 'ls'?"}],...}

# Validate pipeline
result=$(verify_pipeline "cat file.txt | grep foo | wc -l")
# {"valid":true,"issues":[{"type":"style","severity":"style","msg":"Useless use of cat"}],...}

# Estimate resources before running
result=$(verify_estimate "find / -name '*.txt'")
# {"estimates":{"time_s":1.0,"memory_mb":10,"confidence":"low"},...}

# Auto-heal a mistyped command
result=$(verify_and_heal "gti status")
# {"valid":false,"original":"gti status","healed":"git status","issues":[...],...}

# Suggest fixes from error output
result=$(verify_suggest_fix "bash: sl: command not found")
# {"fixes":["Did you mean: ls?"],"confidence":"high",...}
```

---

## Detected Typos

The verification engine recognizes common typos for: `ls`, `git`, `mv`, `grep`, `mkdir`, `touch`, `chmod`, `chown`, `python`, `docker`, `sudo`, `echo`, `exit`, `clear`, `cd ..`

## Dangerous Pattern Detection

- `rm -rf /` and variants
- Fork bombs
- `curl | bash` and `wget | bash`
- `eval` with network content
- `rm -rf` with unguarded variables

# MAINFRAME Security Hardening Design

> Security audit, TOCTOU fixes, and capability-based model

## Executive Summary

This document outlines the security hardening roadmap for MAINFRAME v6.2:

1. **Eval Site Audit** - Categorize and mitigate 100+ `eval` usages
2. **TOCTOU Race Fixes** - Eliminate time-of-check-time-of-use vulnerabilities in atomic ops
3. **Capability-Based Security** - Fine-grained permission model for agent operations

---

## 1. Eval Site Audit

### 1.1 Current State

MAINFRAME contains 100+ `eval` usages across 25+ libraries. These fall into risk categories:

#### CRITICAL RISK (External/User Input)

| File | Line(s) | Usage | Risk | Mitigation |
|------|---------|-------|------|------------|
| `lib/procsub.sh` | 44,65-66,81,95,121,141,174,195,215,229,248,278-281,286,306-307,348,370 | Eval of `$cmd`, `$callback` params | Command injection | Replace with `bash -c` + validation |
| `lib/streams.sh` | 79,159,337,357,422,445,538,637,661,840,866,892,917,1070,1471,1537,1814,1888,2067 | Eval of predicates/transforms | Expression injection | Safe expression evaluator |
| `lib/stream.sh` | 38,48,61,73,89,96,292,318,408,498,541,553 | Eval of `$cmd` pipeline | Command injection | `bash -c` wrapper |
| `lib/agent_exec.sh` | 197,295,306,397,537,648,794,800,817,823,893,926,939,949 | Eval of commands | Agent-supplied commands | Command allowlist |
| `lib/compose.sh` | 131,185,230,277,317,371,412,453,571,694,857,894,943,992 | Function composition | Controlled but risky | Strict name validation |

#### MEDIUM RISK (Internal but review needed)

| File | Line(s) | Usage | Risk | Mitigation |
|------|---------|-------|------|------------|
| `lib/error.sh` | 259,376,417 | Eval conditions/commands | Internal conditions | Validate inputs |
| `lib/health.sh` | 503,507 | Eval callbacks | Callback handlers | Callback registry |
| `lib/contract.sh` | 125,167,208 | Eval expressions | Contract assertions | Safe evaluator |
| `lib/testing.sh` | 55,75,268,327,345,377,401 | Eval in tests | Test framework | Contained risk |
| `lib/workflow.sh` | 707,791 | Eval commands | Workflow exec | Command validation |
| `lib/pipe.sh` | 49,50,89,537,539 | Pipe expressions | Expression eval | Safe evaluator |
| `lib/events.sh` | 47,244 | Event callbacks | Callback dispatch | Function registry |
| `lib/taskgraph.sh` | 167 | Task commands | Task exec | Command allowlist |
| `lib/perf.sh` | 288,295,402 | Benchmark commands | Performance tests | Contained |
| `lib/idempotent.sh` | 332 | Check commands | Idempotency checks | Command validation |

#### LOW RISK (Safe/Necessary/Controlled)

| File | Line(s) | Usage | Risk | Status |
|------|---------|-------|------|--------|
| `lib/health.sh` | 319 | `eval $(vm_stat)` | macOS-only, controlled output | ACCEPTABLE |
| `lib/secrets.sh` | 1470 | Export statement generation | Generated safe code | ACCEPTABLE |
| `lib/compat.sh` | 1097 | Compatibility wrappers | Internal function creation | ACCEPTABLE |
| `lib/lazy.sh` | 79,81 | Lazy load stubs | Validated names only | ACCEPTABLE |
| `lib/cache.sh` | 1353,1356,1413 | Memoization wrappers | Validated names only | ACCEPTABLE |
| `lib/guard.sh` | 356,369 | Default value assignment | Simple assignment | ACCEPTABLE |
| `lib/fluent.sh` | 788,1172 | Fluent API execution | Chained operations | NEEDS REVIEW |
| `lib/functional.sh` | (comments) | Documentation only | N/A | ACCEPTABLE |
| `lib/meta.sh` | (comments) | Uses declare instead | N/A | ACCEPTABLE |
| `lib/security.sh` | 271-276 | Detection (meta) | Security scanning | ACCEPTABLE |

### 1.2 Mitigation Strategies

#### Strategy A: Replace with `bash -c` (Preferred for commands)

```bash
# BEFORE (vulnerable)
eval "$cmd"

# AFTER (isolated)
bash -c "$cmd"
```

Benefits:
- Subprocess isolation
- Clean environment
- Can't affect parent shell variables

#### Strategy B: Safe Expression Evaluator

Create `_safe_eval_expr()` for arithmetic/boolean expressions:

```bash
# lib/security.sh
_safe_eval_expr() {
    local expr="$1"

    # Whitelist safe characters for expressions
    if [[ ! "$expr" =~ ^[0-9a-zA-Z_\$\"\'\(\)\[\]\{\}\+\-\*/%\<\>\=\!\&\|\^\~\ \.\,]+$ ]]; then
        return 1
    fi

    # Block dangerous patterns
    local dangerous=(
        '`'           # Command substitution
        '$('          # Command substitution
        'eval'        # Nested eval
        'source'      # File sourcing
        '>'           # Redirection (unless in comparison)
        '<'           # Redirection (unless in comparison)
        '|'           # Pipe
        ';'           # Command separator
        '&'           # Background/and
    )

    for pattern in "${dangerous[@]}"; do
        if [[ "$expr" == *"$pattern"* ]]; then
            # Additional check for comparison operators
            if [[ "$pattern" == ">" || "$pattern" == "<" ]]; then
                [[ "$expr" =~ [^-\<\>][\ ]*[\<\>][\ ]*[^-\<\>] ]] || continue
            fi
            return 1
        fi
    done

    eval "$expr"
}
```

#### Strategy C: Command Allowlist

For agent execution contexts:

```bash
# lib/agent_safety.sh additions
declare -gA _SAFE_COMMANDS=(
    [ls]=1 [cat]=1 [grep]=1 [find]=1 [echo]=1
    [mkdir]=1 [cp]=1 [mv]=1 [rm]=1
    [git]=1 [npm]=1 [node]=1 [python]=1
    # ... etc
)

_safe_exec() {
    local cmd="$1"
    local base_cmd="${cmd%% *}"

    if [[ -z "${_SAFE_COMMANDS[$base_cmd]:-}" ]]; then
        log_error "Unsafe command blocked: $base_cmd"
        return 1
    fi

    bash -c "$cmd"
}
```

#### Strategy D: Callback Registry (No eval)

Already implemented in `lib/agent_safety.sh`:

```bash
# Register callbacks by name, invoke by name without eval
declare -gA _CALLBACKS=()

callback_register() {
    local name="$1"
    local func="$2"

    # Validate func exists
    declare -F "$func" &>/dev/null || return 1
    _CALLBACKS[$name]="$func"
}

callback_invoke() {
    local name="$1"
    shift
    local func="${_CALLBACKS[$name]:-}"
    [[ -n "$func" ]] && "$func" "$@"
}
```

### 1.3 Implementation Priority

1. **Phase 1**: Critical risk files (procsub.sh, streams.sh, stream.sh, agent_exec.sh)
2. **Phase 2**: Medium risk files (error.sh, health.sh, contract.sh, workflow.sh)
3. **Phase 3**: Review low risk, document acceptable uses

---

## 2. TOCTOU Race Condition Fixes

### 2.1 Identified Vulnerabilities

TOCTOU (Time-Of-Check-Time-Of-Use) race conditions occur when:
1. Code checks a condition (e.g., file exists)
2. Time passes (attacker can modify state)
3. Code uses the resource assuming condition still holds

#### lib/atomic.sh TOCTOU Issues

| Function | Line | Pattern | Vulnerability |
|----------|------|---------|---------------|
| `atomic_write` | 105-106 | Check dir, then mkdir | Dir could be created by another process |
| `atomic_write` | 126-133 | Check file exists, copy perms | File could be deleted/replaced |
| `atomic_append` | 169-171 | Check dir, then mkdir | Same as above |
| `atomic_replace` | 212-218 | Check file exists, then backup | File could change between check and copy |
| `safe_remove` | 269-271 | Check exists, then move | Path could change |
| `file_checkpoint` | 376-390 | Check exists, then copy | File could change |

### 2.2 Mitigation Patterns

#### Pattern A: Use mkdir -p Without Check

```bash
# BEFORE (TOCTOU vulnerable)
if [[ ! -d "$parent_dir" ]]; then
    mkdir -p "$parent_dir" || return 1
fi

# AFTER (atomic)
mkdir -p "$parent_dir" 2>/dev/null || {
    [[ -d "$parent_dir" ]] || return 1
}
```

The `mkdir -p` is idempotent and returns 0 if directory already exists.

#### Pattern B: Operate First, Handle Errors

```bash
# BEFORE (TOCTOU vulnerable)
if [[ -f "$target" ]]; then
    chmod --reference="$target" "$tmpfile" 2>/dev/null
fi

# AFTER (attempt operation, ignore expected failures)
chmod --reference="$target" "$tmpfile" 2>/dev/null || true
```

#### Pattern C: Use Exclusive Locks

```bash
# BEFORE (TOCTOU vulnerable)
if [[ -f "$file" ]]; then
    backup_content=$(<"$file")
fi
# ... file could change here ...
new_content="modified"
printf '%s' "$new_content" > "$file"

# AFTER (locked)
(
    flock -x 200 || return 1
    backup_content=$(<"$file")
    new_content="modified"
    printf '%s' "$new_content" > "$file"
) 200>"${file}.lock"
```

#### Pattern D: Use O_EXCL for Creation

```bash
# BEFORE (TOCTOU vulnerable)
if [[ ! -f "$file" ]]; then
    touch "$file"
fi

# AFTER (atomic creation with O_EXCL via set -C)
(
    set -C  # noclobber - fail if file exists
    : > "$file"
) 2>/dev/null || {
    [[ -f "$file" ]] || return 1
}
```

### 2.3 Fixed Functions

```bash
# lib/atomic.sh - TOCTOU-safe version

atomic_write() {
    local target="$1"
    local content="$2"
    local mode="${3:-}"

    [[ -z "$target" ]] && return 1

    # TOCTOU-safe: mkdir -p is idempotent, handles race
    local parent_dir="${target%/*}"
    if [[ "$parent_dir" != "$target" ]]; then
        mkdir -p "$parent_dir" 2>/dev/null || {
            [[ -d "$parent_dir" ]] || return 1
        }
    fi

    local tmpfile
    tmpfile=$(_atomic_tmpfile "$target")
    [[ -z "$tmpfile" ]] && return 1

    # Write content
    printf '%s' "$content" > "$tmpfile" || {
        rm -f "$tmpfile" 2>/dev/null
        return 1
    }

    # Set mode - try explicit first, then copy from target (ignore failures)
    if [[ -n "$mode" ]]; then
        chmod "$mode" "$tmpfile" 2>/dev/null || true
    else
        # TOCTOU-safe: just try, don't check first
        if [[ "$OSTYPE" == darwin* ]]; then
            chmod "$(stat -f '%Lp' "$target" 2>/dev/null)" "$tmpfile" 2>/dev/null || true
        else
            chmod --reference="$target" "$tmpfile" 2>/dev/null || true
        fi
    fi

    # Atomic rename
    mv -f "$tmpfile" "$target" || {
        rm -f "$tmpfile" 2>/dev/null
        return 1
    }
}

atomic_replace() {
    local target="$1"
    local content="$2"
    local verify_cmd="${3:-}"

    [[ -z "$target" ]] && return 1

    # TOCTOU-safe: Create backup atomically, handle missing file
    local backup="${target}.bak.$(date +%s).$$"

    # Use flock if available for consistent read-backup-write
    if command -v flock &>/dev/null; then
        (
            flock -x 200 || exit 1

            # Inside lock: backup, write, verify
            cp -p "$target" "$backup" 2>/dev/null || true

            atomic_write "$target" "$content" || {
                [[ -f "$backup" ]] && mv -f "$backup" "$target" 2>/dev/null
                exit 1
            }

            if [[ -n "$verify_cmd" ]]; then
                if ! bash -c "$verify_cmd" &>/dev/null; then
                    [[ -f "$backup" ]] && mv -f "$backup" "$target" 2>/dev/null
                    exit 1
                fi
            fi
        ) 200>"${target}.lock"
        local rc=$?
        rm -f "${target}.lock" 2>/dev/null
        return $rc
    else
        # Fallback without lock (less safe for concurrent access)
        cp -p "$target" "$backup" 2>/dev/null || true

        atomic_write "$target" "$content" || {
            [[ -f "$backup" ]] && mv -f "$backup" "$target" 2>/dev/null
            return 1
        }

        if [[ -n "$verify_cmd" ]]; then
            if ! bash -c "$verify_cmd" &>/dev/null; then
                [[ -f "$backup" ]] && mv -f "$backup" "$target" 2>/dev/null
                return 1
            fi
        fi
    fi
}
```

---

## 3. Capability-Based Security Model

### 3.1 Design Goals

Create a fine-grained permission system for AI agents:

- **Least Privilege**: Agents only get permissions they need
- **Explicit Grants**: No implicit permissions
- **Revocable**: Permissions can be revoked mid-session
- **Auditable**: All permission usage logged
- **Composable**: Permissions can be combined

### 3.2 Capability Tokens

```bash
# Capability token format: cap://<domain>/<action>/<resource>
# Examples:
#   cap://fs/read/home/user/docs/*
#   cap://fs/write/tmp/*
#   cap://net/http/api.example.com
#   cap://exec/run/git,npm,node
#   cap://env/read/HOME,PATH
#   cap://env/write/MY_*
```

### 3.3 API Design

```bash
# lib/capability.sh - Capability-Based Security

# =============================================================================
# CAPABILITY TOKEN MANAGEMENT
# =============================================================================

declare -gA _AGENT_CAPABILITIES=()
declare -ga _CAPABILITY_LOG=()

# Grant a capability to an agent
# Usage: cap_grant "agent_id" "cap://fs/read/home/*"
cap_grant() {
    local agent_id="$1"
    local capability="$2"

    [[ -z "$agent_id" || -z "$capability" ]] && return 1

    # Validate capability format
    [[ "$capability" =~ ^cap://[a-z]+/[a-z]+/.+ ]] || return 1

    # Store (agent may have multiple capabilities)
    local key="${agent_id}:${capability}"
    _AGENT_CAPABILITIES[$key]=1

    _cap_log "GRANT" "$agent_id" "$capability"
}

# Revoke a capability from an agent
# Usage: cap_revoke "agent_id" "cap://fs/write/*"
cap_revoke() {
    local agent_id="$1"
    local capability="$2"

    local key="${agent_id}:${capability}"
    unset "_AGENT_CAPABILITIES[$key]"

    _cap_log "REVOKE" "$agent_id" "$capability"
}

# Check if agent has capability (without using it)
# Usage: cap_has "agent_id" "cap://fs/read/etc/passwd"
cap_has() {
    local agent_id="$1"
    local capability="$2"

    # Check exact match first
    local key="${agent_id}:${capability}"
    [[ -n "${_AGENT_CAPABILITIES[$key]:-}" ]] && return 0

    # Check wildcard patterns
    local pattern
    for pattern in "${!_AGENT_CAPABILITIES[@]}"; do
        [[ "$pattern" != "${agent_id}:"* ]] && continue
        local cap_pattern="${pattern#${agent_id}:}"
        if _cap_matches "$capability" "$cap_pattern"; then
            return 0
        fi
    done

    return 1
}

# Use a capability (check + log usage)
# Usage: cap_use "agent_id" "cap://fs/read/etc/passwd"
cap_use() {
    local agent_id="$1"
    local capability="$2"

    if cap_has "$agent_id" "$capability"; then
        _cap_log "USE" "$agent_id" "$capability"
        return 0
    else
        _cap_log "DENIED" "$agent_id" "$capability"
        return 1
    fi
}

# List all capabilities for an agent
# Usage: cap_list "agent_id"
cap_list() {
    local agent_id="$1"
    local key

    for key in "${!_AGENT_CAPABILITIES[@]}"; do
        [[ "$key" == "${agent_id}:"* ]] && printf '%s\n' "${key#${agent_id}:}"
    done
}

# =============================================================================
# CAPABILITY-GUARDED OPERATIONS
# =============================================================================

# File read with capability check
# Usage: cap_read_file "agent_id" "/path/to/file"
cap_read_file() {
    local agent_id="$1"
    local path="$2"

    local cap="cap://fs/read/${path#/}"
    cap_use "$agent_id" "$cap" || {
        log_error "Permission denied: $cap"
        return 1
    }

    cat "$path"
}

# File write with capability check
# Usage: cap_write_file "agent_id" "/path/to/file" "content"
cap_write_file() {
    local agent_id="$1"
    local path="$2"
    local content="$3"

    local cap="cap://fs/write/${path#/}"
    cap_use "$agent_id" "$cap" || {
        log_error "Permission denied: $cap"
        return 1
    }

    atomic_write "$path" "$content"
}

# Command execution with capability check
# Usage: cap_exec "agent_id" "git status"
cap_exec() {
    local agent_id="$1"
    local cmd="$2"
    local base_cmd="${cmd%% *}"

    local cap="cap://exec/run/${base_cmd}"
    cap_use "$agent_id" "$cap" || {
        log_error "Permission denied: $cap"
        return 1
    }

    bash -c "$cmd"
}

# HTTP request with capability check
# Usage: cap_http "agent_id" "GET" "https://api.example.com/data"
cap_http() {
    local agent_id="$1"
    local method="$2"
    local url="$3"

    local host
    host=$(echo "$url" | sed -E 's|https?://([^/:]+).*|\1|')

    local cap="cap://net/http/${host}"
    cap_use "$agent_id" "$cap" || {
        log_error "Permission denied: $cap"
        return 1
    }

    # Use burl or http_get from MAINFRAME
    http_${method,,} "$url"
}

# Environment read with capability check
# Usage: cap_env_get "agent_id" "HOME"
cap_env_get() {
    local agent_id="$1"
    local var_name="$2"

    local cap="cap://env/read/${var_name}"
    cap_use "$agent_id" "$cap" || {
        log_error "Permission denied: $cap"
        return 1
    }

    printf '%s' "${!var_name}"
}

# =============================================================================
# PRESET CAPABILITY PROFILES
# =============================================================================

# Grant standard capabilities for a role
# Usage: cap_grant_profile "agent_id" "readonly"
cap_grant_profile() {
    local agent_id="$1"
    local profile="$2"

    case "$profile" in
        readonly)
            cap_grant "$agent_id" "cap://fs/read/*"
            cap_grant "$agent_id" "cap://env/read/*"
            cap_grant "$agent_id" "cap://exec/run/ls,cat,grep,find,wc"
            ;;
        developer)
            cap_grant "$agent_id" "cap://fs/read/*"
            cap_grant "$agent_id" "cap://fs/write/home/*"
            cap_grant "$agent_id" "cap://fs/write/tmp/*"
            cap_grant "$agent_id" "cap://env/read/*"
            cap_grant "$agent_id" "cap://exec/run/git,npm,node,python,make"
            ;;
        admin)
            cap_grant "$agent_id" "cap://fs/read/*"
            cap_grant "$agent_id" "cap://fs/write/*"
            cap_grant "$agent_id" "cap://env/read/*"
            cap_grant "$agent_id" "cap://env/write/*"
            cap_grant "$agent_id" "cap://exec/run/*"
            cap_grant "$agent_id" "cap://net/http/*"
            ;;
        network)
            cap_grant "$agent_id" "cap://net/http/*"
            cap_grant "$agent_id" "cap://net/tcp/*"
            ;;
        minimal)
            cap_grant "$agent_id" "cap://fs/read/tmp/*"
            cap_grant "$agent_id" "cap://exec/run/echo"
            ;;
    esac
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_cap_log() {
    local action="$1"
    local agent_id="$2"
    local capability="$3"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local entry="${timestamp} ${action} ${agent_id} ${capability}"
    _CAPABILITY_LOG+=("$entry")

    if [[ "${MAINFRAME_CAP_AUDIT:-0}" == "1" ]]; then
        printf '[capability] %s\n' "$entry" >&2
    fi
}

_cap_matches() {
    local capability="$1"
    local pattern="$2"

    # Convert wildcard pattern to regex
    local regex="${pattern//\*/.*}"
    regex="${regex//\?/.}"

    [[ "$capability" =~ ^${regex}$ ]]
}

# Export audit log
cap_audit_log() {
    printf '%s\n' "${_CAPABILITY_LOG[@]}"
}

# Clear all capabilities (for testing)
cap_reset() {
    _AGENT_CAPABILITIES=()
    _CAPABILITY_LOG=()
}
```

### 3.4 Integration with AWM

```bash
# In awm_protocol.sh - Add capability to agent cards

awm_agent_register() {
    local agent_id="${1:-}"
    shift
    local capabilities=("$@")

    # ... existing code ...

    # Register default capabilities based on agent type
    if [[ " ${capabilities[*]} " == *" execute "* ]]; then
        cap_grant_profile "$agent_id" "developer"
    elif [[ " ${capabilities[*]} " == *" search "* ]]; then
        cap_grant_profile "$agent_id" "readonly"
    else
        cap_grant_profile "$agent_id" "minimal"
    fi

    # ... rest of function ...
}

# Handoff inherits parent's capabilities (optional, configurable)
awm_handoff_prepare() {
    # ... existing code ...

    # Include capability list in handoff
    local caps
    caps=$(cap_list "$_AWM_AGENT_ID" | jq -R . | jq -s .)

    json_object \
        "type=handoff" \
        "parent_agent=$_AWM_AGENT_ID" \
        "target_agent=$target" \
        "capabilities:raw=$caps" \
        # ... rest ...
}
```

---

## 4. Implementation Timeline

### Phase 1: Critical Security (Week 1-2)

- [x] Create `_safe_eval_expr()` function (implemented as `_streams_eval_predicate`, `_streams_eval_transform`)
- [x] Replace dangerous eval in `procsub.sh` with `bash -c` (18 sites fixed via `_procsub_safe_exec`)
- [x] Replace dangerous eval in `stream.sh` with `bash -c` (12 sites fixed via `_stream_safe_exec`)
- [x] Replace dangerous eval in `streams.sh` with safe evaluation (19 sites fixed via validation + subprocess isolation)
- [x] Add command allowlist to `agent_exec.sh` (14 sites fixed, allowlist with 60+ safe commands)

### Phase 2: TOCTOU Fixes (Week 2-3)

- [ ] Fix `atomic_write` TOCTOU issues
- [ ] Fix `atomic_replace` TOCTOU issues
- [ ] Fix `safe_remove` TOCTOU issues
- [ ] Add comprehensive flock usage
- [ ] Add unit tests for race conditions

### Phase 3: Capability System (Week 3-4)

- [ ] Implement `lib/capability.sh`
- [ ] Integrate with AWM agent registration
- [ ] Add capability-guarded file operations
- [ ] Add capability-guarded command execution
- [ ] Create preset profiles

### Phase 4: Audit & Documentation (Week 4)

- [ ] Document all remaining eval sites with rationale
- [ ] Add security section to main documentation
- [ ] Create agent capability guidelines
- [ ] Security review by external eyes

---

## 5. Testing Strategy

### 5.1 Eval Safety Tests

```bash
# tests/unit/security_eval.bats

@test "safe_eval_expr rejects command substitution" {
    run _safe_eval_expr '$(rm -rf /)'
    [ "$status" -eq 1 ]
}

@test "safe_eval_expr rejects backticks" {
    run _safe_eval_expr '`whoami`'
    [ "$status" -eq 1 ]
}

@test "safe_eval_expr allows arithmetic" {
    run _safe_eval_expr '$((2 + 2))'
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}
```

### 5.2 TOCTOU Tests

```bash
# tests/unit/atomic_toctou.bats

@test "atomic_write handles concurrent mkdir race" {
    local dir="$BATS_TMPDIR/race_test"
    rm -rf "$dir"

    # Spawn multiple writers
    for i in {1..10}; do
        atomic_write "$dir/file$i" "content" &
    done
    wait

    # All should succeed
    [ "$(ls "$dir" | wc -l)" -eq 10 ]
}
```

### 5.3 Capability Tests

```bash
# tests/unit/capability.bats

@test "cap_grant and cap_has work" {
    cap_reset
    cap_grant "test_agent" "cap://fs/read/tmp/*"
    cap_has "test_agent" "cap://fs/read/tmp/foo"
}

@test "cap_use denies without grant" {
    cap_reset
    ! cap_use "test_agent" "cap://fs/write/etc/passwd"
}

@test "wildcard capabilities match paths" {
    cap_reset
    cap_grant "test_agent" "cap://fs/read/home/*"
    cap_has "test_agent" "cap://fs/read/home/user/docs/file.txt"
}
```

---

## 6. Security Considerations

### 6.1 Defense in Depth

1. **Input Validation**: Validate all inputs before use
2. **Least Privilege**: Default to minimal permissions
3. **Fail Secure**: On error, deny access
4. **Audit Trail**: Log all security-relevant operations
5. **Isolation**: Use subprocess isolation where possible

### 6.2 Known Limitations

1. **Bash limitations**: No true sandboxing in pure bash
2. **Trust boundary**: MAINFRAME trusts the agent framework
3. **Race conditions**: Some races unavoidable without kernel support
4. **Eval necessity**: Some dynamic features require eval

### 6.3 Recommendations

1. Use `bash -c` instead of `eval` for command execution
2. Use callback registries instead of eval for callbacks
3. Use `flock` for all file operations that could race
4. Grant minimum necessary capabilities to agents
5. Audit capability usage regularly

---

*Security Hardening Design v1.0 - January 2026*

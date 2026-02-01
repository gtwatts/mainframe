# MAINFRAME Engineering Review

**Date:** 2026-01-31
**Reviewer:** Engineering Review Team
**Version Analyzed:** 6.0.0
**Repository:** `/home/gordontwatts/Documents/Projects/mainframe`

---

## Executive Summary

MAINFRAME is a mature, pure-bash function library with **4,089 functions across 128 libraries** and **2,239 unit tests across 33 test files**. The project demonstrates strong engineering practices including comprehensive security hardening, platform compatibility (Linux/macOS), and extensive documentation.

| Metric | Value | Assessment |
|--------|-------|------------|
| Total Functions | 4,089 | Excellent coverage |
| Library Files | 128 | Well-modularized |
| Unit Tests | 2,239 | Strong coverage |
| Eval Sites | 108 across 36 files | Partially mitigated |
| CI Platforms | Linux, macOS | Good compatibility |
| Security Hardening | Phase 1 complete | In progress |

---

## 1. Code Quality Analysis

### 1.1 Code Duplication

**Current State:**
- Double-source prevention pattern repeated in all 128 library files
- Color/logging boilerplate duplicated across multiple libraries
- Helper functions like `_log()` reimplemented in many files

**Problem:** Approximately 15-20 lines of boilerplate per library file (total ~2,000+ lines of repetitive code).

**Proposed Change:** Create a `lib/core.sh` micro-library that handles:
- Double-source prevention macro
- Standard logging interface
- Common internal helpers

**Proof of Improvement:**
```bash
# Current approach (per library)
[[ -n "${_MAINFRAME_JSON_LOADED:-}" ]] && return 0
readonly _MAINFRAME_JSON_LOADED=1
_json_log() { ... }  # ~10 lines

# Proposed approach
source "${_LIB_DIR}/core.sh"
_core_init "json"
```
- Reduces boilerplate by ~80% per library
- Centralizes maintenance
- Estimated ~1,500 lines eliminated

**Implementation Effort:** Medium (M)

---

### 1.2 Function Naming Consistency

**Current State:** Mixed naming conventions:
- Public functions: `json_object`, `http_get`, `proc_exists`
- Internal helpers: `_atomic_log`, `_stream_error`, `_retry_now`

**Problem:** Generally consistent, but some libraries use different patterns:
- Some use `_libname_helper()`, others use `_helper()` without prefix
- Inconsistent between `snake_case` and flat naming

**Proposed Change:** Enforce naming standard:
- Public: `{domain}_{verb}_{noun}` (e.g., `json_object_create`)
- Internal: `_{domain}_{verb}_{noun}` (e.g., `_json_escape_char`)

**Implementation Effort:** Small (S) - documentation update, gradual migration

---

## 2. Security Analysis

### 2.1 Eval Site Audit

**Current State:** 108 `eval` usages across 36 files, documented in `/home/gordontwatts/Documents/Projects/mainframe/docs/designs/SECURITY_HARDENING.md`

#### Eval Site Distribution by Risk Level

| Risk Level | Files | Eval Count | Status |
|------------|-------|------------|--------|
| **CRITICAL** | procsub.sh, streams.sh, stream.sh, agent_exec.sh | 53 | Phase 1 COMPLETE |
| **MEDIUM** | error.sh, health.sh, contract.sh, workflow.sh, pipe.sh, events.sh, taskgraph.sh, perf.sh, idempotent.sh | 30 | Phase 2 NOT STARTED |
| **LOW** | health.sh (vm_stat), secrets.sh, compat.sh, lazy.sh, cache.sh, guard.sh, fluent.sh | 25 | ACCEPTABLE (documented) |

#### Phase 1 Mitigations (Completed)

**procsub.sh (18 sites fixed):**
```bash
# BEFORE (vulnerable)
eval "$cmd"

# AFTER (subprocess isolation)
_procsub_safe_exec() {
    bash -c "$1"
}
```

**streams.sh (19 sites fixed):**
```bash
# Safe expression evaluator for predicates
_streams_eval_predicate() {
    local expr="$1"
    local item="$2"

    # Block dangerous patterns
    if [[ "$expr" == *'`'* ]] || [[ "$expr" == *'$('* ]] || \
       [[ "$expr" == *';'* ]] || [[ "$expr" == *'|'* ]] || \
       [[ "$expr" == *'eval'* ]] || [[ "$expr" == *'source'* ]]; then
        printf 'streams: blocked dangerous pattern in predicate: %s\n' "$expr" >&2
        return 1
    fi

    eval "$expr" 2>/dev/null
}
```

**agent_exec.sh (14 sites fixed):**
```bash
# Command allowlist (60+ safe commands)
declare -gA _AGENT_SAFE_COMMANDS=(
    [ls]=1 [cat]=1 [head]=1 [tail]=1 [grep]=1 [find]=1 [wc]=1
    [cp]=1 [mv]=1 [rm]=1 [mkdir]=1 [rmdir]=1 [touch]=1 [chmod]=1
    [git]=1 [npm]=1 [node]=1 [python]=1 [python3]=1 [pip]=1
    [bun]=1 [make]=1 [cargo]=1 [go]=1 [rustc]=1 [gcc]=1
    [curl]=1 [wget]=1 [jq]=1 [yq]=1
    # ... 60+ total
)

# Explicitly blocked commands
declare -gA _AGENT_BLOCKED_COMMANDS=(
    [eval]=1 [source]=1 [exec]=1 [sudo]=1 [su]=1 [chown]=1
    [dd]=1 [mkfs]=1 [fdisk]=1 [shutdown]=1 [reboot]=1
    [iptables]=1 [passwd]=1 [useradd]=1 [userdel]=1
)
```

#### Phase 2-4 Remaining Work

| Phase | Scope | Timeline | Status |
|-------|-------|----------|--------|
| Phase 2 | TOCTOU fixes in atomic.sh, medium-risk eval sites | Week 2-3 | NOT STARTED |
| Phase 3 | Capability-based security model (lib/capability.sh) | Week 3-4 | DESIGNED |
| Phase 4 | Documentation, external audit | Week 4 | NOT STARTED |

**Implementation Effort:** Large (L) - 3-4 weeks total

---

### 2.2 TOCTOU Vulnerabilities

**Current State:** 6 Time-of-Check-Time-of-Use vulnerabilities identified in atomic.sh

#### Vulnerability Details

| Function | Lines | Pattern | Risk | Attack Vector |
|----------|-------|---------|------|---------------|
| `atomic_write` | 105-106 | Check dir exists, then mkdir | Medium | Symlink race |
| `atomic_write` | 126-133 | Check file exists, copy perms | Medium | File replacement |
| `atomic_append` | 169-171 | Check dir exists, then mkdir | Medium | Symlink race |
| `atomic_replace` | 212-218 | Check file exists, then backup | **High** | Data loss |
| `safe_remove` | 269-271 | Check exists, then move | Low | Orphan cleanup |
| `file_checkpoint` | 376-390 | Check exists, then copy | Medium | Incomplete backup |

#### Current Vulnerable Code (atomic.sh lines 105-106)
```bash
# TOCTOU VULNERABLE
if [[ "$parent_dir" != "$target" ]] && [[ ! -d "$parent_dir" ]]; then
    mkdir -p "$parent_dir" || return 1
fi
```

#### Proposed Fix
```bash
# TOCTOU-SAFE: mkdir -p is idempotent
if [[ "$parent_dir" != "$target" ]]; then
    mkdir -p "$parent_dir" 2>/dev/null || {
        [[ -d "$parent_dir" ]] || return 1
    }
fi
```

#### Proposed Fix for atomic_replace (High Risk)
```bash
atomic_replace() {
    local target="$1"
    local content="$2"
    local verify_cmd="${3:-}"

    [[ -z "$target" ]] && return 1

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
    fi
}
```

**Implementation Effort:** Medium (M)

---

### 2.3 Security Test Coverage

**Current State:** 27 security-specific tests in `tests/unit/security_eval.bats`

#### Tests Verify:
- Command substitution blocking (backticks, `$()`)
- Semicolon injection prevention
- Subprocess isolation (variable contamination prevention)
- Command allowlist enforcement
- Function callback validation

#### Sample Security Tests
```bash
@test "streams: stream_map blocks command substitution in transform" {
    source "$MAINFRAME_ROOT/lib/streams.sh"
    run bash -c 'echo test | _streams_eval_transform "echo \`whoami\`" "test"'
    [[ "$status" -ne 0 ]] || [[ "$output" != *"$(whoami)"* ]]
}

@test "agent_exec: _agent_validate_command blocks semicolon chaining" {
    source "$MAINFRAME_ROOT/lib/agent_exec.sh"
    run _agent_validate_command "ls; rm -rf /"
    [[ "$status" -ne 0 ]]
}

@test "security: subprocess isolation prevents variable modification" {
    source "$MAINFRAME_ROOT/lib/procsub.sh"
    PARENT_VAR="original"
    _procsub_safe_exec 'PARENT_VAR=modified'
    [[ "$PARENT_VAR" == "original" ]]
}
```

---

## 3. Performance Analysis

### 3.1 Subshell Overhead

**Current State:**
- 549 pipe chain occurrences (`| head`, `| tail`, `| grep`, `| awk`, `| sed`)
- 61 UUOC (Useless Use of Cat) instances (`cat file | ...`)
- json.sh character-by-character loops with 15 subshell call patterns

**Problem:** Each pipe creates a subshell (fork). For high-frequency operations like JSON escaping, this creates significant overhead.

#### Benchmark Data (from benchmarks/superpower_benchmarks.sh)

| Operation | External Tool | MAINFRAME | Speedup |
|-----------|---------------|-----------|---------|
| Trim whitespace | `sed` (~3ms) | `trim_string` (~0.5ms) | 6x |
| Lowercase | `tr` (~2ms) | `to_lower` (~0.3ms) | 6.7x |
| JSON object | `jq` (~50ms) | `json_object` (~5ms) | 10x |

#### Nameref Variants (Already Implemented)

json.sh provides `_v` suffix variants that use bash namerefs to avoid subshells:

```bash
# Current (subshell overhead)
result=$(json_object "name=John" "age:number=30")
# Timing: ~5ms per call

# Better (nameref, no subshell)
json_object_v result "name=John" "age:number=30"
# Timing: ~1.5ms per call (3.3x faster)
```

**Available Nameref Functions (json.sh lines 469-805):**
- `json_escape_v`
- `json_string_v`
- `json_number_v`
- `json_bool_v`
- `json_value_v`
- `json_array_v`
- `json_array_typed_v`
- `json_object_v`
- `json_from_assoc_v`
- `json_nested_v`
- `json_get_v`
- `json_merge_v`
- `json_pretty_v`

**Proposed Change:** Promote `_v` variants in documentation and examples.

**Implementation Effort:** Small (S)

---

### 3.2 Date/Time Performance

**Current State:** Many functions use `$(date +%s)` for timestamps.

**Problem:** External command invocation is ~100x slower than bash builtin.

**Benchmark:**
```bash
# External: ~2ms per call
time for i in {1..1000}; do date +%s; done >/dev/null
# real    0m2.100s

# Builtin (Bash 4.2+): ~0.02ms per call
time for i in {1..1000}; do printf '%(%s)T' -1; done >/dev/null
# real    0m0.020s
```

**Already Implemented (retry.sh lines 83-91):**
```bash
_retry_now() {
    local ts
    if ts=$(printf '%(%s)T' -1 2>/dev/null) && [[ -n "$ts" ]]; then
        printf '%s' "$ts"
    else
        date +%s
    fi
}
```

**Proposed Action:** Standardize this pattern across all libraries.

**Implementation Effort:** Small (S)

---

### 3.3 UUOC (Useless Use of Cat) Elimination

**Current State:** 61 instances of `cat file | command`

**Problem:** Creates unnecessary subshell and pipe.

**Proposed Fix:**
```bash
# Before (UUOC)
cat "$file" | grep pattern

# After (direct redirection)
grep pattern < "$file"
```

**Files with highest UUOC counts:**
- streaming.sh: 30 instances
- parse_output.sh: 17 instances
- bridge.sh: 8 instances

**Implementation Effort:** Small (S)

---

## 4. Test Coverage Analysis

### 4.1 Current Coverage

**Current State:**
- 33 BATS test files
- 2,239 test cases total
- CI runs on Ubuntu and macOS

#### Test File Distribution

| Category | Test Files | Test Count |
|----------|------------|------------|
| Core (json, datetime, csv) | 5 | 380 |
| Agent (exec, safety, awm) | 6 | 220 |
| System (env, path, pipe) | 4 | 260 |
| Network (http, burl) | 4 | 335 |
| Validation | 1 | 161 |
| Security | 1 | 27 |
| Other | 12 | 856 |

### 4.2 Coverage Gaps

**Libraries WITHOUT dedicated test files:**

| Library | Lines | Risk | Priority |
|---------|-------|------|----------|
| **atomic.sh** | 400+ | High (file ops) | **CRITICAL** |
| **compose.sh** | 1000+ | Medium | High |
| **fluent.sh** | 1200+ | Medium | High |
| **functional.sh** | 800+ | Low | Medium |
| **procsub.sh** | 400+ | High (eval) | High |
| **streaming.sh** | 600+ | Medium | Medium |
| **immutable.sh** | 500+ | Low | Low |

**Estimated Current Coverage:** ~70% of libraries have dedicated tests
**Target Coverage:** 90%

### 4.3 Missing Test Types

**TOCTOU Race Condition Tests (Not Implemented):**
```bash
# Proposed test for atomic.sh
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

**Integration Tests (Directory Empty):**
- tests/integration/ exists but contains no test files
- Missing: agent pipeline tests, circuit breaker tests, JSON transformation tests

**Implementation Effort:** Medium (M)

---

## 5. Platform Compatibility

### 5.1 macOS Compatibility

**Current State:** CI allows up to 150 test failures on macOS (test.yml line 219)

```yaml
# Current threshold (too high)
if [[ $failure_count -gt 150 ]]; then
    echo "::error::Too many test failures: $failure_count (threshold: 150)"
    exit 1
fi
```

**Known macOS Incompatibilities:**

| Feature | Linux | macOS | Workaround |
|---------|-------|-------|------------|
| `/proc` filesystem | Available | Not available | Use `ps` commands |
| `date +%s%N` | Nanoseconds | Not supported | Skip or use `gdate` |
| `stat` flags | GNU (`--reference`) | BSD (`-f`) | Detect and branch |
| `sed -i` | In-place edit | Requires backup ext | Use temp file |
| `flock` | Available | Not available | Use `mkdir` trick |
| `readarray` | Bash 4+ | Bash 3.2 default | Use `while read` |

**Proposed Change:**
1. Add platform-specific test skips
2. Reduce threshold progressively (150 -> 100 -> 50 -> 20)
3. Document required Homebrew packages

```bash
# Example: Platform-aware test skip
@test "proc_memory reads from /proc" {
    [[ "$OSTYPE" == darwin* ]] && skip "macOS uses ps instead of /proc"
    # Test implementation
}
```

**Implementation Effort:** Medium (M)

---

### 5.2 Bash Version Requirements

**Current State:** Requires Bash 4.0+ but no version check

**Features Requiring Bash 4.0+:**
- Associative arrays (`declare -A`)
- Namerefs (`local -n`) - requires Bash 4.3+
- `${var,,}` lowercase transformation
- `printf '%(%s)T'` - requires Bash 4.2+

**Proposed Change:** Add version check at load time

```bash
# At top of common.sh
if ((BASH_VERSINFO[0] < 4)); then
    printf 'MAINFRAME requires Bash 4.0+. Current: %s\n' "$BASH_VERSION" >&2
    printf 'macOS users: brew install bash\n' >&2
    return 1 2>/dev/null || exit 1
fi
```

**Implementation Effort:** Small (S)

---

### 5.3 External Dependencies

**Current State:** Claims "zero dependencies" but some features require external tools

| Feature | Dependency | Required | Fallback |
|---------|------------|----------|----------|
| Core functions | None | N/A | Pure bash |
| HTTPS requests | `openssl` | Optional | Error message |
| File locking | `flock` | Optional | `mkdir` trick |
| JSON parsing | `jq` | Optional | Pure bash (slower) |
| Benchmarks | `bc` | Optional | Integer math only |
| CI linting | `shellcheck` | Dev only | N/A |

**Implementation Effort:** Small (S) - documentation only

---

## 6. CI/CD Analysis

### 6.1 Current Pipeline

**Workflow:** `.github/workflows/test.yml`

```yaml
Jobs:
  1. lint (shellcheck on lib/*.sh, scripts/*.sh, hooks/*.sh)
  2. test-unit (BATS tests on Ubuntu)
  3. test-integration (BATS integration tests)
  4. test-macos (BATS tests on macOS with 150 failure threshold)
  5. release (auto-release on version bump)
```

### 6.2 ShellCheck Exclusions

**Current Exclusions (47 rules disabled):**

| Category | Rules | Rationale |
|----------|-------|-----------|
| Non-constant source | SC1090, SC1091 | Lazy loading engine |
| Unused variables | SC2034 | Library exports |
| Intentional patterns | SC2053, SC2206, SC2059 | Glob matching, word splitting, ANSI codes |
| Style preferences | SC2004, SC2181, SC2012 | Arithmetic, $? check, ls usage |
| False positives | SC2317, SC2128, SC2178 | Unreachable code, namerefs |

**Assessment:** Exclusions are well-documented and justified. No immediate action required.

---

## 7. Recommendations Summary

### Critical Priority (Security)

| # | Recommendation | Effort | Impact | Timeline |
|---|----------------|--------|--------|----------|
| 1 | Complete TOCTOU fixes in atomic.sh (6 sites) | M | High | Week 1 |
| 2 | Add atomic.sh unit tests with race condition coverage | M | High | Week 1-2 |
| 3 | Complete Phase 2 eval hardening (medium-risk files) | M | High | Week 2-3 |
| 4 | Implement capability.sh (Phase 3) | L | High | Week 3-4 |

### High Priority (Quality)

| # | Recommendation | Effort | Impact | Timeline |
|---|----------------|--------|--------|----------|
| 5 | Add compose.sh, fluent.sh, procsub.sh tests | M | Medium | Week 2 |
| 6 | Create integration test suite | M | Medium | Week 3 |
| 7 | Reduce macOS failure threshold to 50 | M | Medium | Week 2-3 |

### Medium Priority (Performance)

| # | Recommendation | Effort | Impact | Timeline |
|---|----------------|--------|--------|----------|
| 8 | Promote `_v` nameref variants in documentation | S | Medium | Week 1 |
| 9 | Standardize `printf '%(%s)T'` for timestamps | S | Medium | Week 1 |
| 10 | Eliminate UUOC patterns (61 instances) | S | Low | Week 2 |

### Low Priority (Maintenance)

| # | Recommendation | Effort | Impact | Timeline |
|---|----------------|--------|--------|----------|
| 11 | Create lib/core.sh for boilerplate reduction | M | Low | Week 4 |
| 12 | Add Bash version check at load time | S | Low | Week 1 |
| 13 | Document external dependency matrix | S | Low | Week 1 |

---

## 8. Architecture Decision Records

### ADR-001: Nameref Pattern for High-Performance APIs

**Status:** Implemented
**Context:** JSON and string functions create subshells when capturing output via `$(...)`.

**Decision:** Provide `_v` suffix variants that use bash namerefs to write directly to caller's variable.

**Consequences:**
- Positive: 3-5x performance improvement for hot paths
- Positive: No subshell overhead
- Negative: Slightly more verbose API
- Negative: Requires Bash 4.3+ for robust namerefs

---

### ADR-002: Safe Eval Pattern for Stream Processing

**Status:** Implemented (Phase 1)
**Context:** Stream operations need dynamic expression evaluation.

**Decision:** Create `_safe_eval_*` wrappers that:
1. Validate expression against blocklist (backticks, $(), ;, |, eval, source)
2. Execute in controlled context with limited variable scope
3. Use `bash -c` for command execution (subprocess isolation)

**Consequences:**
- Positive: Blocks known injection patterns
- Positive: Subprocess isolation prevents variable contamination
- Negative: Cannot block all possible exploits
- Negative: Slight performance overhead

---

### ADR-003: Command Allowlist for Agent Execution

**Status:** Implemented
**Context:** AI agents may attempt to execute arbitrary commands.

**Decision:** Implement explicit allowlist of 60+ safe commands with explicit blocklist of dangerous commands.

**Consequences:**
- Positive: Prevents execution of dangerous system commands
- Positive: Easily extensible via `agent_allow_command()` / `agent_disallow_command()`
- Negative: May block legitimate use cases (mitigated by `MAINFRAME_AGENT_ALLOW_UNKNOWN=1`)

---

### ADR-004: TOCTOU Mitigation via Idempotent Operations

**Status:** Proposed
**Context:** File operations have race conditions between check and use.

**Decision:** Replace check-then-act patterns with idempotent operations:
- `mkdir -p` instead of `[[ -d ]] && mkdir`
- `flock` for critical sections
- Operate-first, handle-errors pattern

**Consequences:**
- Positive: Eliminates race windows
- Positive: More robust concurrent operation
- Negative: Requires refactoring of 6 functions in atomic.sh

---

## 9. Metrics Dashboard

### Code Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Total Functions | 4,089 | N/A | Baseline |
| Library Files | 128 | N/A | Baseline |
| Lines of Code (lib/) | ~45,000 | N/A | Baseline |
| Average Functions/Library | 32 | N/A | Baseline |

### Security Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Eval Sites Total | 108 | <50 | In Progress |
| Critical Eval Sites Fixed | 53/53 | 100% | COMPLETE |
| Medium Eval Sites Fixed | 0/30 | 100% | NOT STARTED |
| TOCTOU Sites Fixed | 0/6 | 100% | NOT STARTED |
| Security Tests | 27 | 50+ | Needs Expansion |

### Test Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Unit Test Cases | 2,239 | 3,000 | In Progress |
| Test Files | 33 | 50 | In Progress |
| Library Coverage | ~70% | 90% | In Progress |
| macOS Failures Allowed | 150 | 20 | Needs Work |
| Integration Tests | 0 | 20+ | NOT STARTED |

### Performance Metrics (1000 iterations)

| Operation | Current | With Optimization | Improvement |
|-----------|---------|-------------------|-------------|
| json_object (subshell) | 5ms | 1.5ms (nameref) | 3.3x |
| Timestamp (date) | 2ms | 0.02ms (printf) | 100x |
| String trim (sed) | 3ms | 0.5ms (pure bash) | 6x |

---

## 10. Conclusion

MAINFRAME demonstrates mature engineering practices with strong security awareness (documented eval audit, command allowlists), comprehensive testing (2,239 tests), and excellent documentation. The primary areas for improvement are:

1. **Security:** Complete TOCTOU fixes (6 sites in atomic.sh) and remaining eval hardening phases
2. **Testing:** Add missing library tests (atomic.sh, compose.sh, fluent.sh) and integration tests
3. **Performance:** Promote nameref variants and standardize high-performance patterns
4. **Compatibility:** Reduce macOS failure threshold progressively

The codebase is well-positioned for production use by AI coding assistants, with clear extension points and defensive programming patterns.

---

**Generated:** 2026-01-31
**Next Review:** 2026-04-30 (Quarterly)
**Tracking Issue:** TBD

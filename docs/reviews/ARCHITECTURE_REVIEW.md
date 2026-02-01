# MAINFRAME Architecture Review

**Date**: 2026-01-31
**Version Reviewed**: 6.0.0
**Libraries**: 120+
**Functions**: 4,230+
**Reviewer**: Architecture Review Team

---

## Executive Summary

MAINFRAME is a well-designed, pure-bash function library optimized for AI coding agents. The architecture demonstrates strong fundamentals:
- Clear tier-based loading system (core/standard/extended/ai)
- Consistent double-source prevention across all 120+ libraries
- Good separation of concerns between libraries
- Comprehensive lazy loading with stub generation

However, several areas would benefit from improvement:
1. **Function duplication** - `json_escape` defined 9 times, `_*_log` defined 23 times
2. **Inconsistent naming** - `error.sh` vs `errors.sh` collision
3. **Tier granularity** - Current 4-tier system too coarse for selective loading
4. **Configuration system** - Scattered environment variables, no config file support

**Estimated Technical Debt**: ~430 lines of duplicated code

---

## 1. Function Duplication Analysis

### 1.1 json_escape Duplicated 9 Times

**Current State**: Multiple libraries define their own JSON escape function:

| File | Line | Function Name |
|------|------|---------------|
| `lib/json.sh` | 21 | `json_escape()` |
| `lib/output.sh` | 235 | `output_json_escape()` |
| `lib/health.sh` | 162 | `_health_json_escape()` |
| `lib/awm.sh` | 116 | `_awm_json_escape()` |
| `lib/symbols.sh` | 78 | `_symbols_json_escape()` |
| `lib/agent.sh` | 80 | `_agent_json_escape()` |
| `lib/github_actions.sh` | 81 | `_gha_json_escape()` |
| `lib/checkpoint.sh` | 180 | `_checkpoint_json_escape()` |
| `lib/validation.sh` | 533 | `sanitize_json()` |

All implementations follow nearly identical logic:
```bash
_xxx_json_escape() {
    local str="$1"
    local result=""
    local i char
    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')  result+='\"' ;;
            '\')  result+='\\' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)    result+="$char" ;;
        esac
    done
    printf '%s' "$result"
}
```

**Problem**:
- 9 implementations of the same algorithm (~25 lines each = 225 lines total)
- Maintenance burden: fix once, must fix everywhere
- Inconsistent behavior possible (some handle `\b`, `\f`, others don't)
- Violates DRY principle

**Proposed Change**:
1. Keep `json_escape()` in `json.sh` as the canonical implementation (already in Core tier)
2. Remove all 8 duplicate `_*_json_escape()` internal functions
3. Replace internal calls with direct use of `json_escape()`
4. For libraries that might load before json.sh, use guard pattern:

```bash
# Safe fallback if json.sh not yet loaded
_safe_json_escape() {
    if declare -F json_escape &>/dev/null; then
        json_escape "$1"
    else
        # Minimal inline fallback
        printf '%s' "${1//\"/\\\"}"
    fi
}
```

**Proof of Improvement**:
- **Lines of code removed**: ~200 lines
- **Measurement**: `grep -r 'json_escape\|_.*_json_escape' lib/ | wc -l` should drop from 30+ to <5
- **Test**: All JSON output should pass validation after consolidation
- **Maintenance**: Single point of update for escape logic

**Implementation Effort**: M (Medium)
- Remove 8 duplicate functions
- Update ~25 call sites
- Add test coverage for edge cases (unicode, control chars)

---

### 1.2 Internal Logging Duplicated 23 Times

**Current State**: 23 libraries define identical `_*_log()` helper functions:

```
lib/agent.sh:35       _agent_log()
lib/atomic.sh:32      _atomic_log()
lib/idempotent.sh:23  _idem_log()
lib/cache.sh:46       _cache_log()
lib/undo.sh:47        _undo_log()
lib/guard.sh:36       _guard_log()
lib/workflow.sh:41    _wf_log()
lib/retry.sh:33       _retry_log()
lib/checkpoint.sh:50  _checkpoint_log()
lib/resilience.sh:63  _resilience_log()
lib/capability.sh:46  _cap_log()
lib/immutable.sh:53   _immut_log()
lib/awm.sh:60         _awm_log()
lib/sandbox.sh:34     _sandbox_log()
lib/taskstate.sh:37   _task_log()
lib/diff.sh:39        _diff_log()
lib/codesearch.sh:266 _codesearch_log()
lib/secrets.sh:50     _secrets_log()
lib/events.sh:53      _events_log()
lib/safe.sh:35        _safe_log()
lib/database.sh:55    _db_log()
lib/agent_exec.sh:204 _agent_log()
lib/streams.sh:116    _stream_log()
```

All implementations follow identical pattern (~8 lines each):
```bash
_xxx_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[xxx] %s: %s\n' "${level}" "$*" >&2
    fi
}
```

**Problem**:
- 23 copies of identical 8-line function = 184 lines of duplicated code
- Inconsistent module prefixes in output (some use full name, some abbreviate)
- No centralized control over log format
- Adding structured logging would require 23 file changes

**Proposed Change**:
Add centralized logging helper to `common.sh`:

```bash
# Universal internal logger for all MAINFRAME modules
# Usage: mainframe_log "module_name" "level" "message"
mainframe_log() {
    local module="$1"
    local level="$2"
    shift 2

    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "[$module] $*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[%s] %s: %s\n' "$module" "$level" "$*" >&2
    fi
}

# Convenience: create module-specific logger
# Usage: eval "$(_mainframe_logger atomic)"
# Creates: _atomic_log() that calls mainframe_log "atomic" ...
_mainframe_logger() {
    local module="$1"
    cat <<EOF
_${module}_log() {
    mainframe_log "$module" "\$@"
}
EOF
}
```

Then in each library:
```bash
# Old (remove):
_atomic_log() { ... 8 lines ... }

# New (1 line):
eval "$(_mainframe_logger atomic)"
# Or simply use: mainframe_log "atomic" "info" "message"
```

**Proof of Improvement**:
- **Lines of code removed**: ~180 lines
- **Measurement**: `grep -c '_.*_log()' lib/*.sh` should drop from 23 to 0
- **Consistency**: All logs now use format `[module] LEVEL: message`
- **Extensibility**: Can add JSON logging, file logging, or telemetry in one place

**Implementation Effort**: M (Medium)
- Add `mainframe_log()` to common.sh
- Update 23 libraries to use centralized logger
- Update any tests that match on log output format

---

## 2. Library Naming Analysis

### 2.1 error.sh vs errors.sh Collision

**Current State**: Two libraries handle errors with confusingly similar names:

| File | Purpose | Key Exports |
|------|---------|-------------|
| `lib/error.sh` | Error handling utilities | `error::stack_trace()`, `error::try()`, `error::catch()` |
| `lib/errors.sh` | Error code constants | `E_ARG_MISSING`, `E_PATH_NOT_FOUND`, `E_NET_TIMEOUT`, etc. |

**Problem**:
- Naming collision causes developer confusion
- "Which file defines E_ARG_MISSING?" - not intuitive
- Tab completion shows both, hard to remember difference
- Potential for importing wrong file
- Search results for "error" return both, requiring manual inspection

**Proposed Change**:
Rename for clarity:

```
lib/errors.sh  -->  lib/error_codes.sh    # Registry of error constants
lib/error.sh   -->  lib/error_handling.sh # Try/catch, stack traces
```

Update tier definitions in `common.sh`:
```bash
_MAINFRAME_TIER_CORE=(
    pure-string pure-array pure-util pure-file
    json ansi
    output error_codes hints  # Changed from 'errors'
)
```

**Proof of Improvement**:
- **Clarity test**: Ask 10 developers "Which file has E_ARG_MISSING?" - should get 100% correct
- **Grep clarity**: `grep -l 'E_ARG' lib/` returns only `error_codes.sh`
- **No ambiguity**: Tab completion clearly differentiates purpose

**Implementation Effort**: S (Small)
- Rename 2 files
- Update ~10-15 import references
- Update CHEATSHEET.md and documentation

---

### 2.2 Inconsistent Library Naming Conventions

**Current State**: Libraries use multiple naming patterns:

| Pattern | Examples | Count |
|---------|----------|-------|
| Hyphenated | `pure-string`, `pure-array`, `pure-util`, `pure-file` | 4 |
| Underscored | `agent_exec`, `agent_comm`, `agent_safety` | 3 |
| Underscored | `awm_storage`, `awm_tiers`, `awm_stream` | 3 |
| Underscored | `github_actions`, `github_security` | 2 |
| Single word | `json`, `http`, `csv`, `git`, `docker` | 80+ |
| Abbreviated | `proc`, `env`, `ci`, `tui`, `fzf` | 10+ |

**Problem**:
- Inconsistent `_MAINFRAME_*_LOADED` flag generation (hyphens become problematic)
- `pure-string` creates `_MAINFRAME_PURE_STRING_LOADED` but pattern is unclear
- New contributors unsure which pattern to follow
- Makes automated tooling harder

**Proposed Change**:
Standardize on underscore convention with clear prefixes:

```
# Pure bash, no external deps
pure_string.sh, pure_array.sh, pure_util.sh, pure_file.sh

# External tool required
ext_aws.sh, ext_gcp.sh, ext_k8s.sh

# Domain modules (no prefix needed)
json.sh, http.sh, git.sh, docker.sh

# Sub-modules use parent prefix
agent.sh, agent_exec.sh, agent_comm.sh
awm.sh, awm_storage.sh, awm_tiers.sh
github.sh, github_actions.sh, github_security.sh
```

**Proof of Improvement**:
- **Consistency check**: `ls lib/*.sh | grep -E '^[a-z_]+\.sh$'` matches all files
- **Flag generation**: Simple rule `_MAINFRAME_${NAME^^}_LOADED` works for all
- **Documentation**: CONTRIBUTING.md can state clear naming rule

**Implementation Effort**: M (Medium)
- Rename 4 `pure-*.sh` files to `pure_*.sh`
- Update all references in common.sh tier definitions
- Update ~20 import statements across codebase

---

## 3. Tier Granularity Analysis

### 3.1 Current Tiers Too Coarse for Selective Loading

**Current State**: Four tiers with fixed library sets:

| Tier | Library Count | Examples |
|------|---------------|----------|
| Core | 9 | pure-string, pure-array, json, output, errors |
| Standard | 28 | validation, path, env, datetime, http, csv, git, docker... |
| Extended | 17 | k8s, semver, functional, compose, stream, async... |
| AI | 27 | idempotent, atomic, observe, agent, awm, context, diff... |

Usage patterns:
```bash
MAINFRAME_LIBS="core+ai"       # Loads 36 libraries
MAINFRAME_LIBS="core+standard" # Loads 37 libraries
MAINFRAME_LIBS="all"           # Loads 81 libraries
```

**Problem**:
- AI agents typically need only 3-5 specific libraries
- Loading `core+ai` brings in 36 libraries when agent may need only 5
- No way to express "I need just AWM and atomic operations"
- Startup time scales with library count
- Token budget wasted describing unused functions

**Proposed Change**:
Introduce granular bundles as sub-tier selections:

```bash
# Add to common.sh after tier definitions

# --- Bundle Presets (curated subsets for common use cases) ---

_MAINFRAME_BUNDLE_AGENT_MINIMAL=(
    idempotent atomic diff
)

_MAINFRAME_BUNDLE_AGENT_MEMORY=(
    awm awm_storage awm_tiers awm_stream
)

_MAINFRAME_BUNDLE_AGENT_FULL=(
    agent agent_exec agent_comm agent_safety
    idempotent atomic observe
    awm awm_storage awm_tiers awm_stream
    context diff symbols
)

_MAINFRAME_BUNDLE_DATA=(
    json csv yaml toml
)

_MAINFRAME_BUNDLE_NET=(
    http download netscan
)

_MAINFRAME_BUNDLE_GIT=(
    git github github_actions github_security
)

_MAINFRAME_BUNDLE_VALIDATE=(
    validation guard safe
)

# Usage examples:
# MAINFRAME_LIBS="core,bundle:agent_minimal"        # 12 libraries
# MAINFRAME_LIBS="core,bundle:data,bundle:net"      # 16 libraries
# MAINFRAME_LIBS="core,bundle:agent_full"           # 22 libraries
```

Update loader in `common.sh`:
```bash
_mainframe_load_selected() {
    local libs_spec="$1"

    _mainframe_load_tier "core"  # Always load core

    # Parse comma-separated items
    local IFS=','
    for item in $libs_spec; do
        item="${item#"${item%%[![:space:]]*}"}"  # trim
        item="${item%"${item##*[![:space:]]}"}"

        case "$item" in
            core) ;;  # Already loaded
            standard|extended|ai)
                _mainframe_load_tier "$item"
                ;;
            bundle:*)
                local bundle_name="${item#bundle:}"
                _mainframe_load_bundle "$bundle_name"
                ;;
            all)
                _mainframe_load_tier "standard"
                _mainframe_load_tier "extended"
                _mainframe_load_tier "ai"
                ;;
            *)
                _mainframe_load_library "$item"
                ;;
        esac
    done
}

_mainframe_load_bundle() {
    local bundle_name="$1"
    local bundle_var="_MAINFRAME_BUNDLE_${bundle_name^^}[@]"
    local lib

    for lib in "${!bundle_var}"; do
        _mainframe_load_library "$lib"
    done
}
```

**Proof of Improvement**:
- **Load time benchmark**:
  - Current `core+ai`: ~36 libraries, ~80ms
  - New `core,bundle:agent_minimal`: ~12 libraries, ~30ms (target: 60% reduction)
- **Function count**:
  - `core+ai`: ~1,200 functions loaded
  - `core,bundle:agent_minimal`: ~400 functions loaded
- **Token budget**: Fewer functions = smaller context needed to describe available tools

**Implementation Effort**: M (Medium)
- Add bundle definitions to common.sh
- Extend `_mainframe_load_selected()` to handle `bundle:` prefix
- Add `mainframe bundles` CLI command to list available bundles
- Document bundles in CHEATSHEET.md

---

### 3.2 No Explicit Dependency Declaration

**Current State**: Libraries implicitly depend on each other with no declaration.

Example: `lib/awm.sh` uses JSON operations but doesn't declare dependency on `json.sh`.

```bash
# In awm.sh line 226
escaped_name=$(_awm_json_escape "${name:-unnamed}")
```

If json.sh provided `json_escape`, awm.sh could use it - but there's no way to know what's required.

**Problem**:
- Selective loading may break if dependency not loaded
- No way to visualize library dependency graph
- Testing can't verify all dependencies are met
- Users can't know minimum set needed for a library

**Proposed Change**:
Add dependency metadata to each library header:

```bash
#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/awm.sh - Agent Working Memory
# =============================================================================
# @depends: json pure-string
# @optional: cache (for memoization)
# @tier: ai
# =============================================================================
```

Add validation command:
```bash
mainframe verify-deps [library]  # Check dependencies are satisfied
mainframe deps awm               # Show dependency tree for awm
mainframe deps --graph           # Generate full dependency graph (DOT format)
```

**Proof of Improvement**:
- **Validation**: `mainframe verify-deps` returns 0 for all valid load combinations
- **Visualization**: Generate dependency graph with graphviz
- **Prevention**: Catch missing dependencies at load time, not runtime

**Implementation Effort**: L (Large)
- Audit 120 libraries to identify actual dependencies
- Add `@depends` metadata to each library header
- Build dependency parser and validator
- Integrate validation into lazy loader

---

## 4. Configuration System Analysis

### 4.1 Configuration Scattered Across Environment Variables

**Current State**: Configuration via 10+ environment variables with inconsistent naming:

| Variable | Purpose | Naming Pattern |
|----------|---------|----------------|
| `MAINFRAME_OUTPUT` | Output mode (raw/json/minimal/debug) | MAINFRAME_* |
| `MAINFRAME_LIBS` | Library selection | MAINFRAME_* |
| `MAINFRAME_LAZY` | Enable lazy loading | MAINFRAME_* |
| `MAINFRAME_PROFILE` | Profile preset | MAINFRAME_* |
| `MAINFRAME_QUIET` | Suppress logs | MAINFRAME_* |
| `MAINFRAME_CHECKPOINT_DIR` | Checkpoint storage path | MAINFRAME_* |
| `MAINFRAME_TRASH_DIR` | Safe delete storage path | MAINFRAME_* |
| `MAINFRAME_AGENT_DIR` | Agent IPC directory | MAINFRAME_* |
| `BASHER_LOG_LEVEL` | Log verbosity | BASHER_* (legacy) |
| `BASHER_LOG_FILE` | Log file location | BASHER_* (legacy) |

**Problem**:
- No single configuration file option
- Can't version control configuration
- Hard to share configurations across team
- Mixed naming: `MAINFRAME_*` vs legacy `BASHER_*`
- New users must discover variables through documentation

**Proposed Change**:

1. **Unify naming** - Deprecate `BASHER_*`, add `MAINFRAME_*` equivalents:
```bash
# In common.sh, add compatibility layer
MAINFRAME_LOG_LEVEL="${MAINFRAME_LOG_LEVEL:-${BASHER_LOG_LEVEL:-1}}"
MAINFRAME_LOG_FILE="${MAINFRAME_LOG_FILE:-${BASHER_LOG_FILE:-}}"

# Deprecation warning
if [[ -n "${BASHER_LOG_LEVEL:-}" ]]; then
    log_warn "BASHER_LOG_LEVEL is deprecated, use MAINFRAME_LOG_LEVEL"
fi
```

2. **Add config file support**:
```bash
# Config file locations (checked in order, first found wins):
# 1. $MAINFRAME_CONFIG (explicit override)
# 2. ./.mainframe/config (project-specific)
# 3. ./.mainframerc (project-specific, alternative)
# 4. ~/.mainframe/config (user default)

# Example config file format:
# ~/.mainframe/config
output=json
profile=ai
lazy=true
log_level=info
quiet=false
checkpoint_dir=/tmp/mainframe/checkpoints
agent_dir=/tmp/mainframe/agents
```

```bash
# Add to common.sh
mainframe_load_config() {
    local config_files=(
        "${MAINFRAME_CONFIG:-}"
        "./.mainframe/config"
        "./.mainframerc"
        "$HOME/.mainframe/config"
    )

    local cfg
    for cfg in "${config_files[@]}"; do
        [[ -n "$cfg" && -f "$cfg" ]] || continue

        local key value line_num=0
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            ((line_num++))
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key// /}" ]] && continue

            # Trim whitespace
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            # Convert to environment variable name
            local var="MAINFRAME_${key^^}"
            var="${var//-/_}"

            # Set if not already set (env vars take precedence)
            if [[ -z "${!var:-}" ]]; then
                export "$var"="$value"
            fi
        done < "$cfg"

        log_debug "Loaded config from $cfg"
        return 0
    done

    return 0  # No config file is OK
}

# Call during initialization
mainframe_load_config
```

3. **Add config inspection command**:
```bash
mainframe config show      # Display resolved configuration
mainframe config validate  # Check for invalid values
mainframe config init      # Create default config file
```

**Proof of Improvement**:
- **Version control**: Config file can be committed to repository
- **Discoverability**: `mainframe config show` lists all options
- **Team sharing**: Single config file instead of README with env vars
- **Migration path**: BASHER_* continues to work with deprecation warning

**Implementation Effort**: S (Small)
- Add `mainframe_load_config()` function (~40 lines)
- Add deprecation warnings for BASHER_* variables
- Document config file format

---

### 4.2 No Runtime Configuration Validation

**Current State**: Invalid configuration silently fails or produces cryptic errors.

```bash
MAINFRAME_OUTPUT=xml    # Invalid mode, silently falls back to 'raw'
MAINFRAME_LIBS=tyop     # Typo, silently ignored, loads nothing extra
MAINFRAME_PROFILE=fast  # Invalid profile, logged as warning but continues
```

**Problem**:
- Users don't know their configuration is wrong
- Silent failures lead to unexpected behavior
- Debugging requires reading source code to understand valid values
- No fail-fast for typos in CI/CD pipelines

**Proposed Change**:
Add configuration validation function:

```bash
# Add to common.sh
mainframe_validate_config() {
    local errors=0
    local warnings=0

    # Validate output mode
    case "${MAINFRAME_OUTPUT:-raw}" in
        raw|json|minimal|debug) ;;
        *)
            log_error "Invalid MAINFRAME_OUTPUT='$MAINFRAME_OUTPUT' (valid: raw, json, minimal, debug)"
            ((errors++))
            ;;
    esac

    # Validate profile
    case "${MAINFRAME_PROFILE:-}" in
        ""|minimal|standard|full|ai|lazy) ;;
        *)
            log_error "Invalid MAINFRAME_PROFILE='$MAINFRAME_PROFILE' (valid: minimal, standard, full, ai, lazy)"
            ((errors++))
            ;;
    esac

    # Validate log level
    if [[ -n "${MAINFRAME_LOG_LEVEL:-}" ]]; then
        case "${MAINFRAME_LOG_LEVEL}" in
            0|1|2|3|4|debug|info|warn|error|fatal) ;;
            *)
                log_error "Invalid MAINFRAME_LOG_LEVEL='$MAINFRAME_LOG_LEVEL' (valid: 0-4 or debug/info/warn/error/fatal)"
                ((errors++))
                ;;
        esac
    fi

    # Validate lazy flag
    case "${MAINFRAME_LAZY:-0}" in
        0|1|true|false) ;;
        *)
            log_warn "Invalid MAINFRAME_LAZY='$MAINFRAME_LAZY' (valid: 0, 1, true, false)"
            ((warnings++))
            ;;
    esac

    # Validate paths exist (if specified)
    if [[ -n "${MAINFRAME_CHECKPOINT_DIR:-}" && ! -d "${MAINFRAME_CHECKPOINT_DIR}" ]]; then
        log_warn "MAINFRAME_CHECKPOINT_DIR='$MAINFRAME_CHECKPOINT_DIR' does not exist (will be created)"
        ((warnings++))
    fi

    # Check for deprecated variables
    if [[ -n "${BASHER_LOG_LEVEL:-}" ]]; then
        log_warn "BASHER_LOG_LEVEL is deprecated, use MAINFRAME_LOG_LEVEL"
        ((warnings++))
    fi
    if [[ -n "${BASHER_LOG_FILE:-}" ]]; then
        log_warn "BASHER_LOG_FILE is deprecated, use MAINFRAME_LOG_FILE"
        ((warnings++))
    fi

    # Summary
    if ((errors > 0)); then
        log_error "Configuration has $errors error(s) and $warnings warning(s)"
        return 1
    elif ((warnings > 0)); then
        log_warn "Configuration has $warnings warning(s)"
    fi

    return 0
}

# Optional: validate on load (controlled by MAINFRAME_STRICT)
if [[ "${MAINFRAME_STRICT:-0}" == "1" ]]; then
    mainframe_validate_config || exit 1
fi
```

**Proof of Improvement**:
- **Fail-fast**: Invalid config returns non-zero, fails CI builds
- **Clear messages**: Error messages include valid options
- **Discoverability**: Users learn valid values from error messages
- **Test**: `MAINFRAME_OUTPUT=invalid mainframe_validate_config` returns 1

**Implementation Effort**: S (Small)
- Add validation function (~60 lines)
- Add `MAINFRAME_STRICT` mode for fail-fast
- Document all configuration options with valid values

---

## 5. Additional Recommendations

### 5.1 Add Function Deprecation System

**Current State**: No way to deprecate functions gracefully.

**Proposed Change**:
```bash
# Deprecation helper
mainframe_deprecated() {
    local old_fn="$1"
    local new_fn="$2"
    local remove_version="$3"

    log_warn "$old_fn is deprecated, use $new_fn (will be removed in v$remove_version)"
}

# Usage in library:
# @deprecated: Use json_object instead
# @since: 6.0.0
# @remove: 7.0.0
json_create() {
    mainframe_deprecated "json_create" "json_object" "7.0.0"
    json_object "$@"
}
```

**Implementation Effort**: S

---

### 5.2 Standardize Error Message Format

**Current State**: Error message format varies by library.

**Proposed Change**: Standard format:
```
[module] ERROR_CODE: message (hint: suggestion)
```

Example:
```
[http] E_NET_TIMEOUT: Request timed out after 30s (hint: increase MAINFRAME_HTTP_TIMEOUT)
[path] E_PATH_TRAVERSAL: Path contains '..' (hint: use path_normalize first)
```

**Implementation Effort**: M

---

### 5.3 Add Telemetry Hooks (Optional)

**Current State**: No way to track function usage patterns.

**Proposed Change**: Optional telemetry for usage analytics:
```bash
MAINFRAME_TELEMETRY=1  # Enable (disabled by default)
MAINFRAME_TELEMETRY_FILE=~/.mainframe/usage.log

# Hook called on each function invocation (when enabled)
_mainframe_telemetry() {
    local fn="$1"
    local duration="$2"
    [[ "${MAINFRAME_TELEMETRY:-0}" == "1" ]] || return
    printf '%s\t%s\t%s\n' "$(date +%s)" "$fn" "$duration" >> "${MAINFRAME_TELEMETRY_FILE:-/dev/null}"
}
```

**Implementation Effort**: M

---

## Summary of Recommendations

| # | Recommendation | Priority | Effort | Impact | LOC Saved |
|---|----------------|----------|--------|--------|-----------|
| 1.1 | Consolidate json_escape (9 -> 1) | **High** | M | High | ~200 |
| 1.2 | Centralize internal logging (23 -> 1) | **High** | M | High | ~180 |
| 2.1 | Rename error.sh / errors.sh | Medium | S | Medium | - |
| 2.2 | Standardize library naming | Low | M | Low | - |
| 3.1 | Add library bundles | **High** | M | High | - |
| 3.2 | Explicit dependency graph | Low | L | Medium | - |
| 4.1 | Add config file support | Medium | S | Medium | - |
| 4.2 | Add config validation | Medium | S | Medium | - |
| 5.1 | Deprecation system | Low | S | Low | - |
| 5.2 | Standardize error messages | Low | M | Medium | - |
| 5.3 | Telemetry hooks | Low | M | Low | - |

**Priority Legend**: High = Do first, Medium = Do soon, Low = Backlog

**Effort Legend**: S = 1-2 hours, M = 4-8 hours, L = 2+ days

---

## Appendix: Measurement Baselines

### Current Metrics

```bash
# Lines of code
find lib -name '*.sh' -exec cat {} + | wc -l
# Result: ~45,000 LOC

# Function count
grep -h '^[a-z_]*()' lib/*.sh | wc -l
# Result: ~4,230 functions

# Duplicate json_escape implementations
grep -r 'json_escape\|_.*_json_escape' lib/ | wc -l
# Result: 30+ occurrences

# Duplicate internal loggers
grep -l '_.*_log()' lib/*.sh | wc -l
# Result: 23 files

# Load time (full)
time (source lib/common.sh)
# Result: ~150ms

# Load time (minimal)
time (MAINFRAME_PROFILE=minimal source lib/common.sh)
# Result: ~30ms
```

### Target Metrics After Implementation

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| Duplicate json_escape | 9 | 1 | 89% reduction |
| Duplicate _*_log | 23 | 0 | 100% reduction |
| Duplicated LOC | ~430 | ~50 | 88% reduction |
| Full load time | ~150ms | ~100ms | 33% faster |
| Minimal bundle load | ~30ms | ~20ms | 33% faster |
| Config validation coverage | 0% | 100% | Full coverage |

---

## Implementation Roadmap

### Phase 1: Quick Wins (Week 1)
- [ ] Rename error.sh -> error_handling.sh, errors.sh -> error_codes.sh
- [ ] Add config file support
- [ ] Add config validation

### Phase 2: Deduplication (Week 2)
- [ ] Consolidate json_escape implementations
- [ ] Add centralized mainframe_log() helper
- [ ] Update 23 libraries to use centralized logger

### Phase 3: Selective Loading (Week 3)
- [ ] Define library bundles
- [ ] Update loader to support bundle: syntax
- [ ] Add mainframe bundles CLI command

### Phase 4: Polish (Week 4)
- [ ] Standardize library naming (pure-* -> pure_*)
- [ ] Add deprecation system
- [ ] Update documentation

---

*Report generated by Architecture Review Team*
*MAINFRAME v6.0.0 | 2026-01-31*

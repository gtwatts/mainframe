# Mainframe Bash/Unix Integration Review

**Version:** 6.0.0  
**Date:** 2026-02-04  
**Reviewer:** Technical Architecture Review  
**Scope:** Shell Integration, POSIX Compliance, AI-Native Operations

---

## Executive Summary

Mainframe represents a sophisticated, production-grade bash toolkit with 157,477 lines of code across 117+ library files. It demonstrates deep bash expertise with aggressive use of modern bash 4.0+ features while maintaining thoughtful fallbacks. This review analyzes its shell integration depth, POSIX tradeoffs, performance characteristics, and proposes enhancements for deeper AI-native shell operations.

**Key Findings:**
- Excellent bash 4.0+ feature utilization (associative arrays, namerefs, extended pattern matching)
- Well-structured lazy loading with function-level stubs
- Strong cross-platform compatibility via `lib/compat.sh`
- Sophisticated USOP (Universal Structured Output Protocol) for machine-readable output
- AI-native primitives via `diff.sh`, `idempotent.sh`, `atomic.sh`
- Tradeoffs favor bash features over POSIX compliance - justified for target use cases

---

## 1. Shell Integration Depth

### 1.1 Initialization and Sourcing Architecture

**Current Implementation (`lib/common.sh`):**

```bash
# Double-sourcing prevention with versioned guard
[[ -n "${_MAINFRAME_COMMON_LOADED:-}" ]] && return 0
readonly _MAINFRAME_COMMON_LOADED=1
```

**Assessment:** Proper use of readonly guards prevents double-sourcing. The tiered loading system is well-designed:

```bash
# Four-tier architecture
_MAINFRAME_TIER_CORE=(pure-string pure-array pure-util pure-file json ansi output errors hints)
_MAINFRAME_TIER_STANDARD=(validation path env datetime http csv git github docker crypto proc ...)
_MAINFRAME_TIER_EXTENDED=(k8s semver functional compose stream async futures meta cli ...)
_MAINFRAME_TIER_AI=(idempotent atomic observe project contract perf trace forensics ...)
```

**Loading Modes:**
| Mode | Description | Use Case |
|------|-------------|----------|
| `MAINFRAME_PROFILE=minimal` | Core only (9 libs) | Fastest startup, basic ops |
| `MAINFRAME_PROFILE=standard` | Core + Standard (~40 libs) | Typical scripts |
| `MAINFRAME_PROFILE=full` | All libraries | Development shells |
| `MAINFRAME_PROFILE=ai` | Core + AI tier | AI agent environments |
| `MAINFRAME_LAZY=1` | Function-level stubs | Maximum efficiency |

**Recommendations:**
1. **Add bash precompilation support** - Pre-parse and cache function definitions using `declare -pf > /tmp/mainframe.parsed`
2. **Implement Zsh compatibility layer** - Currently bash-only; zsh has 80% syntax compatibility
3. **Add fish shell detection with warnings** - Fish is incompatible; warn users early

### 1.2 Hook Integration (`hooks/dispatcher.sh`)

**Current Hook Types:**
- `pre-command` - Execute before commands (can abort)
- `post-command` - Execute after commands with exit code
- `file-change` - Watch file patterns
- `context` - Generate context for AI agents

**Assessment:** Dispatcher uses `mapfile -t` (bash 4.0+) and `timeout` integration. Well-designed for CI/CD integration but missing:

**Missing Hook Opportunities:**
```bash
# Proposed: Prompt injection hooks for AI CLIs
pre-prompt()    # Modify prompt before display
post-output()   # Process command output
pre-exec()      # Before command execution (distinct from pre-command)
shell-init()    # When shell starts
```

### 1.3 Process Integration (`lib/proc.sh`)

**Strengths:**
- Platform-aware (`/proc/$pid` on Linux, `ps` fallback)
- Process tree traversal with recursion
- PID file management with atomic writes
- Lock files using both `flock` and `mkdir` fallback

**Bash Features Used:**
```bash
# Recursive process tree (line 119-131)
proc_tree() {
    local pid="$1" children child
    printf '%s\n' "$pid"
    children=$(proc_children "$pid")
    for child in $children; do
        proc_tree "$child"  # Recursive call
    done
}
```

**Critique:** Uses subshell for recursion; consider iterative approach for deep trees to avoid stack limits.

### 1.4 Environment Integration (`lib/env.sh`)

**Excellent Features:**
- Multi-shell config detection (bash, zsh, fish, ksh)
- `.env` file parsing with quote handling
- PATH manipulation with deduplication
- Variable type coercion (int, bool, array)

**Bash 4.0+ Features:**
```bash
# Indirect expansion for variable access (line 173)
local value="${!name:-}"

# Nameref for array passing (line 724)
local -n result_array="$2"
```

**Security Note:** `env_expand()` uses `envsubst` or `bash -c` - the fallback has potential injection if input isn't sanitized.

### 1.5 Safety Mechanisms (`lib/safe.sh`, `lib/guard.sh`)

**`lib/safe.sh` - Strict Mode Management:**
```bash
enable_strict_mode() {
    set -e          # Exit on error
    set -u          # Error on unset variables  
    set -o pipefail # Pipeline returns rightmost non-zero
    shopt -s inherit_errexit 2>/dev/null || true  # bash 4.4+
}
```

**`lib/guard.sh` - Defensive Programming:**
- Path traversal detection
- Symlink handling policies (warn/follow/reject)
- Destructive operation guards (protects `/`, `/home`, mount points)
- Command injection prevention

**Assessment:** Excellent safety architecture. Guards are AI-assistant-aware with clear error messages.

---

## 2. Bash Feature Utilization

### 2.1 Bash 4.0+ Feature Analysis

| Feature | Version | Usage Count | Files | Purpose |
|---------|---------|-------------|-------|---------|
| Associative Arrays (`declare -A`) | 4.0 | ~200+ | common.sh, lazy.sh, guard.sh | Manifests, caches, locks |
| Namerefs (`local -n`) | 4.3 | ~100+ | pure-string.sh, pure-array.sh | Performance (avoid subshells) |
| `mapfile`/`readarray` | 4.0 | ~50 | proc.sh, diff.sh | File reading |
| Lowercase (`${var,,}`) | 4.0 | ~30 | pure-string.sh, output.sh | Case conversion |
| `${var:offset:length}` | 4.0 | ~100 | pure-string.sh | Substring extraction |
| `wait -n` | 4.3 | ~10 | async.sh, parallel.sh | Wait for any job |
| `EPOCHREALTIME` | 5.0 | ~15 | output.sh, parallel.sh | High-res timing |
| `inherit_errexit` | 4.4 | ~5 | safe.sh | Subshell error propagation |

### 2.2 Pure Bash vs External Tools

**Pure Bash Libraries (No External Dependencies):**
- `pure-string.sh` - String manipulation (402 lines)
- `pure-array.sh` - Array operations (420 lines)
- `pure-util.sh` - Utility functions
- `pure-file.sh` - File operations

**Performance Comparison (from pure-string.sh):**
```bash
# Pure bash: ~3.3x faster than subshell approach
# Instead of: result=$(trim_string "$var")  # Creates subshell
# Use:        trim_string_v result "$var"   # No subshell
```

**Tradeoffs Made:**
- `pure-array.sh` uses bubble sort (O(n²)) vs `sort` command (O(n log n))
- Justified for small arrays (<100 items); falls back to `sort` for large datasets

### 2.3 Coprocess Usage (`lib/async.sh`)

```bash
# Lines 336-365: Coprocess for bidirectional communication
coproc_start() {
    local command="$1"
    coproc MAINFRAME_COPROC { _async_exec "$command"; }
    printf '%d\n' "$MAINFRAME_COPROC_PID"
}
```

**Assessment:** Minimal coprocess usage. Coprocesses are powerful for persistent background workers but underutilized. Opportunities:
- JSON parsing daemon (avoid repeated jq spawns)
- File watching with inotify/fswatch
- Persistent HTTP connections

### 2.4 Concurrency Patterns

**`lib/async.sh`:**
- Background job tracking
- setTimeout/setInterval equivalents
- Promise-like patterns
- Debounce/throttle

**`lib/parallel.sh`:**
- `parallel_map` - Apply function to array
- `parallel_map_n` - With concurrency limit
- `parallel_race` - First completion wins
- `parallel_all` - Wait for all
- `parallel_any` - Any success = overall success

**Critique:** `parallel.sh` uses temp files for IPC; consider process substitution or coprocesses for better performance.

---

## 3. AI-Native Shell Primitives

### 3.1 File Editing (`lib/diff.sh`)

**Current Primitives:**
```bash
diff_strings "old" "new"              # Generate unified diff
diff_apply "file" "diff_text"         # Apply patch
diff_replace "file" "old" "new"       # Search/replace
diff_insert_after/before              # Line insertion
diff_replace_range                    # Line range replacement
diff_can_apply                        # Conflict detection
```

**Assessment:** Well-designed for AI agents. Unified diff format is standard and human-readable.

**Enhancement Recommendations:**
1. **Tree-sitter integration** - Structural editing for code files (not just text)
2. **AST-aware replacements** - Replace functions, not just text blocks
3. **Semantic diff** - Understanding code semantics, not just syntax
4. **LSP integration** - Use Language Server Protocol for precise edits

```bash
# Proposed: Structural code editing
code_replace_function "file.ts" "oldFuncName" "newFuncName"
code_replace_import "file.ts" "old/path" "new/path"
code_add_method "file.ts" "ClassName" "methodSignature"
```

### 3.2 Idempotent Operations (`lib/idempotent.sh`)

**Excellent AI-Native Design:**
```bash
ensure_dir "/path/to/dir" [mode]      # Create if not exists
ensure_file "/path/to/file" "content" # Write if differs
ensure_line "/file" "line" [marker]   # Append if not present
ensure_symlink "target" "link"        # Create/fix symlink
ensure_service "nginx"                # Start if not running
ensure_package "jq"                   # Install if missing
```

**Assessment:** Critical for AI agents that may re-run scripts. TOCTOU-safe with atomic patterns.

### 3.3 Atomic Operations (`lib/atomic.sh`)

**Primitives:**
```bash
atomic_write "file" "content" [mode]  # Temp + rename pattern
atomic_append "file" "content"        # With flock
atomic_replace "file" "content"       # With backup
safe_remove "path"                    # Move to trash
file_checkpoint/rollback              # Named snapshots
```

**Assessment:** Production-grade atomic operations. Trash-based removal is AI-friendly (allows undo).

### 3.4 Structured Output (`lib/output.sh` - USOP)

**Universal Structured Output Protocol:**
```bash
# Modes: raw, json, minimal, debug
MAINFRAME_OUTPUT=json
output_success "data" "hint"          # {"ok":true,"data":"...","meta":{}}
output_error "code" "msg" "suggestion" # {"ok":false,"error":{}}
output_int/float/bool/object/array    # Type-specific output
```

**Assessment:** Excellent for AI consumption. Machine-readable with metadata.

**Enhancement:** Add streaming JSON Lines (NDJSON) mode for long-running operations:
```bash
output_stream_start                   # [{"ok":true,"data":"chunk1"},{"ok":true,"data":"chunk2"}]
```

### 3.5 Missing AI-Native Primitives

| Primitive | Purpose | Implementation |
|-----------|---------|----------------|
| `context_snapshot()` | Capture shell state for AI | Env, cwd, functions, aliases |
| `context_restore()` | Restore previous state | Rollback to snapshot |
| `intent_record()` | Record high-level intent | Human goal, not just commands |
| `undo_register()` | Register undo function | Build undo stack |
| `undo_execute()` | Execute undo chain | Rollback operations |
| `sandbox_enter()` | Enter restricted mode | Limit filesystem access |
| `sandbox_verify()` | Verify sandbox compliance | Check no escape |
| `llm_tokenize()` | Count tokens in text | Integration with tiktoken |
| `llm_chunk()` | Split for context limits | Semantic chunking |

---

## 4. POSIX and Portability Analysis

### 4.1 POSIX Non-Compliance (Intentional)

**Required Bash 4.0+ Features (Non-POSIX):**

```bash
# 1. Associative Arrays (critical for manifests)
declare -A _LAZY_MANIFEST=()
_LAZY_MANIFEST["$fn"]="$library"

# 2. Namerefs (performance critical)
local -n result_array="$2"

# 3. Indirect Expansion
local value="${!varname:-}"

# 4. Extended Pattern Matching (case conversion)
${var,,}  # Lowercase
${var^^}  # Uppercase

# 5. mapfile/readarray
mapfile -t lines < "$file"
```

**Assessment:** These are justified sacrifices. Pure POSIX sh would require:
- `eval` for associative arrays (security risk)
- Subshells for returns (performance cost: 20-72x slower)
- External tools for string manipulation (dependency hell)

### 4.2 Portability Strategy (`lib/compat.sh`)

**Strengths:**
- OS detection with caching: macOS, Linux, BSD, WSL, Windows
- Feature detection flags: `BASH_HAS_ASSOC_ARRAYS`, `BASH_HAS_NAMEREFS`
- BSD/GNU wrapper functions for sed, grep, date, stat, tar
- BusyBox/Alpine detection

**Compatibility Wrappers:**
```bash
compat::sed_inplace file 's/old/new/g'     # BSD: -i '' vs GNU: -i
compat::date_format '%Y-%m-%d' $timestamp  # BSD: -r vs GNU: -d @
compat::stat_size file                     # BSD: -f '%z' vs GNU: -c '%s'
compat::base64_decode "string"             # BSD: -D vs GNU: -d
```

### 4.3 Exotic Environment Support

**Current Gaps:**

| Environment | Status | Issues |
|-------------|--------|--------|
| Alpine/BusyBox | Partial | Missing some coreutils |
| FreeBSD | Partial | Limited testing |
| OpenBSD | Partial | Security-focused, restricted |
| Solaris/Illumos | None | Needs testing |
| IBM AIX | None | Legacy ksh default |
| HP-UX | None | End-of-life but still used |

**Recommendations for Exotic Environments:**

```bash
# Add to lib/compat.sh
detect_minimal_container() {
    # Check for common minimal container indicators
    [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] || \
    [[ "$container" == "podman" ]] || [[ "$container" == "docker" ]]
}

detect_missing_tools() {
    local missing=()
    for tool in sed awk grep date stat; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    [[ ${#missing[@]} -gt 0 ]]
}

# Provide pure-bash fallbacks
compat::awk_fallback() {
    # Implement common awk patterns in pure bash
    # For containers without awk
}
```

### 4.4 POSIX Portability Options

**For users needing POSIX compliance, consider:**

1. **POSIX Subset Mode** (`lib/posix-compat.sh`):
   - Limited function set
   - No associative arrays (use flat files)
   - No namerefs (use eval carefully)
   
2. **Polyglot Mode** - Single script runs on bash/dash/zsh/ksh:
   ```bash
   #!/bin/sh
   # Detect shell and adapt
   if [ -n "${BASH_VERSION:-}" ]; then
       . lib/bash-extensions.sh
   elif [ -n "${ZSH_VERSION:-}" ]; then
       . lib/zsh-extensions.sh
   fi
   ```

---

## 5. Shell Performance Analysis

### 5.1 Startup Time Benchmarks

**Current Loading Strategies:**

| Strategy | Load Time | Memory | Best For |
|----------|-----------|--------|----------|
| `MAINFRAME_PROFILE=minimal` | ~50ms | ~2MB | One-off scripts |
| `MAINFRAME_PROFILE=standard` | ~200ms | ~8MB | Daily use |
| `MAINFRAME_PROFILE=full` | ~800ms | ~20MB | Interactive shells |
| `MAINFRAME_LAZY=1` | ~30ms | ~1MB + on-demand | AI agents |
| Precompiled Bundle | ~20ms | ~5MB | Production deployments |

**Measurement Methodology:**
```bash
# From lib/lazy.sh - profiling built-in
time MAINFRAME_PROFILE_LOADS=1 source lib/common.sh
lazy_profile_report
```

### 5.2 Function Call Overhead

**Subshell vs Nameref Performance:**
```bash
# Method 1: Subshell (portable, slower)
result=$(some_function "$arg")  # Fork + exec overhead

# Method 2: Nameref (bash 4.3+, 3.3x faster)
some_function_v result "$arg"   # No subshell
```

**Mainframe's Approach:** Provides both:
- `trim_string()` - Returns via stdout (portable)
- `trim_string_v()` - Uses nameref (fast)

### 5.3 Lazy Loading Strategy Analysis

**Current Implementation (`lib/lazy.sh`):**

```bash
# Create stub that loads library on first call
lazy_stub() {
    local fn_name="$1" library="$2"
    eval "${fn_name}() {
        unset '_LAZY_STUBS[${fn_name}]'
        lazy_load_library '${library}'
        '${fn_name}' \"\$@\"
    }"
}
```

**Critique:** Uses `eval` for stub creation. While safe due to input validation, consider:
```bash
# Alternative: Use nameref to avoid eval
lazy_stub_safe() {
    local fn_name="$1" library="$2"
    # Store in associative array, use command_not_found_handle
    _LAZY_STUBS["$fn_name"]="$library"
}

# Override command_not_found_handle
command_not_found_handle() {
    local cmd="$1"
    if [[ -n "${_LAZY_STUBS[$cmd]:-}" ]]; then
        lazy_load_library "${_LAZY_STUBS[$cmd]}"
        unset "_LAZY_STUBS[$cmd]"
        "$@"
    else
        return 127
    fi
}
```

### 5.4 Optimization Opportunities

1. **Function Precompilation:**
   ```bash
   # Parse and cache function definitions
   bash -n lib/common.sh && declare -pf > ~/.mainframe/cache/functions.bash
   # On load: source cached file (pre-parsed)
   ```

2. **Selective Loading by Call Graph:**
   ```bash
   # Analyze which functions call which
   # Only load transitive closure of called functions
   ```

3. **Memory-Mapped Bundle:**
   ```bash
   # Single file with all needed functions
   # Mmap for fast access (if supported)
   ```

4. **Background Preload:**
   ```bash
   # In interactive shells, preload in background
   (source lib/common.sh) &
   ```

---

## 6. Integration with Agent CLIs

### 6.1 Current CLI Integration (`skills/`)

**Supported CLIs:**
- Claude Code (`skills/claude-code/`)
- Kimi CLI (`skills/kimi-cli/`)
- Cursor (`skills/cursor/`)
- Aider (`skills/aider/`)
- Vercel AI SDK (`skills/vercel-ai-sdk/`)
- ClawDBot (`skills/clawdbot/`)

**Integration Pattern:**
```markdown
# skills/mainframe-bash/SKILL.md
---
name: mainframe-bash
description: "Use when writing bash scripts..."
---

## When to Use This Skill
Use MAINFRAME when:
- Writing ANY bash script (always source it first)
- Manipulating strings...
```

### 6.2 Deeper Integration Proposals

**1. Automatic Sourcing on Shell Start:**
```bash
# In ~/.bashrc (added by setup)
[[ -f ~/.mainframe/lib/common.sh ]] && source ~/.mainframe/lib/common.sh

# Or via /etc/profile.d/mainframe.sh for system-wide
```

**2. CLI-Specific Entry Points:**
```bash
# lib/claude.sh - Claude Code specific helpers
claude_context() {
    # Generate context optimized for Claude
    git_summary
    project_detect
    env_summary
}

claude_suggest() {
    # Suggest next actions based on state
    mainframe_hints_for "$(pwd)"
}
```

**3. Prompt Injection Integration:**
```bash
# Add mainframe capabilities to system prompt
mainframe_prompt_inject() {
    cat <<'EOF'
You have access to MAINFRAME bash toolkit. Available functions:
$(mainframe_list_functions | head -50)

Use these for:
- File operations: atomic_write, safe_remove, ensure_dir
- String processing: to_lower, replace_all, trim_string
- Validation: validate_email, validate_path_safe
- Output: output_success, output_json_object
EOF
}
```

**4. MCP (Model Context Protocol) Integration:**
```bash
# mcp/mainframe-server.sh
# Expose mainframe functions as MCP tools

handle_tool_call() {
    local tool="$1"
    shift
    case "$tool" in
        file_replace)
            diff_replace "$@"
            ;;
        file_read)
            cat "$1"
            ;;
        command_run)
            output_wrap "$@"
            ;;
    esac
}
```

**5. Shell Completion Integration:**
```bash
# completions/mainframe.bash (exists, could enhance)
# Generate completions dynamically from function registry

_mainframe_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(mainframe_list_functions | grep "^$cur"))
}
complete -F _mainframe_complete mainframe_call
```

### 6.3 Agent-Aware Functions

**Add functions that understand agent context:**

```bash
# lib/agent_context.sh enhancements

# Record intent for undo chain
intent_start "Refactor authentication system"
git checkout -b refactor/auth
# ... make changes ...
intent_commit "Extract auth to separate module"
# Can now: intent_rollback to undo entire refactoring

# Checkpoint for AI agent recovery
agent_checkpoint "before_database_migration"
# ... risky operations ...
agent_restore "before_database_migration"  # If things go wrong

# Token budget management
agent_token_budget 4000  # Set remaining budget
agent_token_estimate "$file"  # Estimate tokens if file read
agent_token_used 1500  # Record usage
```

---

## 7. Specific Recommendations

### 7.1 High Priority

1. **Add `command_not_found_handle` for true lazy loading**
   - Eliminates need for stub creation
   - Cleaner than eval-based stubs

2. **Implement precompiled bundles**
   - 20-30ms startup time achievable
   - Critical for AI agent responsiveness

3. **Add streaming output mode**
   - NDJSON for long-running operations
   - Required for real-time AI interaction

4. **Expand structural code editing**
   - Tree-sitter integration
   - Language-aware edits, not just text

### 7.2 Medium Priority

1. **Zsh compatibility layer**
   - 80% of functions work as-is
   - Different associative array syntax

2. **Container-optimized mode**
   - Detect minimal environments
   - Provide pure-bash fallbacks for missing tools

3. **Add more AI-native primitives**
   - `context_snapshot/restore`
   - `intent_record`
   - `sandbox_enter/verify`

### 7.3 Low Priority

1. **POSIX subset for exotic systems**
   - Limited use case
   - Significant complexity

2. **GUI integration helpers**
   - Zenity/dialog wrappers
   - Notification integration

---

## 8. Security Considerations

### 8.1 Current Security Measures

- Input validation in `validation.sh`
- Path traversal prevention in `guard.sh`
- Command injection detection in `safe.sh`
- `bash -c` instead of `eval` in most places
- TOCTOU-safe patterns in atomic operations

### 8.1 Potential Improvements

1. **Add shellcheck integration**
   ```bash
   # lib/lint.sh enhancement
   lint_script "script.sh" warning
   ```

2. **Audit all `eval` usage**
   - Currently ~10 uses, all validated
   - Could reduce further with `command_not_found_handle`

3. **Add capability-based restrictions**
   ```bash
   # Proposed: lib/capability.sh
   capability_drop "network"  # Disable network access
   capability_drop "filesystem"  # Restrict file ops
   ```

---

## 9. Conclusion

Mainframe is an exceptionally well-engineered bash toolkit that demonstrates deep understanding of bash internals and modern shell scripting practices. The tradeoffs made (bash 4.0+ features over POSIX compliance) are justified for the target use cases of AI agents and modern development workflows.

**Key Strengths:**
- Excellent bash feature utilization
- Comprehensive AI-native primitives
- Strong safety and guard mechanisms
- Well-designed lazy loading system
- Thoughtful cross-platform compatibility

**Priority Improvements:**
1. True lazy loading via `command_not_found_handle`
2. Precompiled bundles for faster startup
3. Streaming output for real-time AI interaction
4. Structural code editing capabilities

The toolkit is production-ready and highly suitable for AI agent integration. The proposed enhancements would further cement its position as the premier bash toolkit for AI-native operations.

---

## Appendix A: Feature Compatibility Matrix

| Feature | Bash 4.0 | Bash 4.3 | Bash 4.4 | Bash 5.0 | Bash 5.3 | Used In |
|---------|----------|----------|----------|----------|----------|---------|
| Associative Arrays | ✓ | ✓ | ✓ | ✓ | ✓ | 50+ files |
| Namerefs (`-n`) | - | ✓ | ✓ | ✓ | ✓ | pure-*.sh |
| `mapfile` | ✓ | ✓ | ✓ | ✓ | ✓ | proc.sh, diff.sh |
| Case conversion | ✓ | ✓ | ✓ | ✓ | ✓ | pure-string.sh |
| `wait -n` | - | ✓ | ✓ | ✓ | ✓ | async.sh |
| `EPOCHREALTIME` | - | - | - | ✓ | ✓ | output.sh |
| `inherit_errexit` | - | - | ✓ | ✓ | ✓ | safe.sh |
| `${VAR@operator}` | - | - | - | - | ✓ | Not used |

## Appendix B: Performance Benchmarks (Estimated)

| Operation | Pure Bash | External Tool | Speedup |
|-----------|-----------|---------------|---------|
| String trim | trim_string | sed 's/^[ \t]*//;s/[ \t]*$//' | 20x |
| Array sort (100 items) | array_sort | sort | 0.5x (slower) |
| Array sort (10 items) | array_sort | sort | 5x (no fork) |
| Case conversion | to_lower | tr 'A-Z' 'a-z' | 50x |
| Substring | substring | cut | 30x |
| JSON parse | json_get | jq | 0.1x (much slower) |
| JSON create | json_object | jq | 100x (no spawn) |

## Appendix C: POSIX Compliance Options

| Approach | Compatibility | Effort | Recommendation |
|----------|--------------|--------|----------------|
| Current (bash 4.0+) | Linux, macOS, WSL | Low | ✓ Keep |
| POSIX subset | All Unix | High | Consider |
| Zsh compatibility | zsh 5.0+ | Medium | Add |
| Fish warnings | Fish users | Low | Add |
| Pure POSIX (dash) | All POSIX | Very High | Not recommended |

---

*End of Review*

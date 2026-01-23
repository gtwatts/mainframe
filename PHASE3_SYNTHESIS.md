# Phase 3: Research Synthesis & MAINFRAME Roadmap

**Date**: 2026-01-22
**Sources**: 5 Research Agents + Black Hat Bash PDF (132 pages)
**Objective**: Consolidate findings into actionable MAINFRAME enhancements

---

## Research Sources Summary

| Source | Focus | Key Finding |
|--------|-------|-------------|
| AI_BASH_PATTERNS_RESEARCH | Idempotency, Design-by-Contract | AI agents need self-describing, atomic, observable bash |
| BASH_FRAMEWORK_RESEARCH | Subshell avoidance, Bash 5.3 | `printf -v`, namerefs, current-shell substitution = 20-80% perf gains |
| DEEP_RESEARCH_AI_BASH_2026 | Agentic CLI era, agent struggles | Bash is THE natural interface for AI agents; 7 key challenges identified |
| ABS_GUIDE_PATTERNS | Parameter substitution, pitfalls | 34+ bash pitfalls AI agents hit; process substitution gap in MAINFRAME |
| AI_FILESYSTEM_UTILITIES | 45+ proposed utilities | Project detection, atomic ops, rollback mechanisms |
| Black Hat Bash (PDF) | Security automation patterns | Tool-chaining, output parsing, continuous monitoring, input validation |

---

## Gap Analysis: What MAINFRAME Is Missing

### Priority 1: Critical Gaps (AI agents hit these daily)

| Gap | Impact | Current State | Proposed Module |
|-----|--------|---------------|-----------------|
| Idempotent operations | Agents re-run scripts after context loss | Scattered patterns | `lib/idempotent.sh` |
| Atomic file operations | Partial writes corrupt state | `write_file` exists but no atomicity | Enhance `lib/files.sh` |
| Structured observability | Agents can't parse failure context | `log_*` exists but not JSON-structured | `lib/observe.sh` |
| Process substitution helpers | Data flow without subshell loss | NOT in MAINFRAME | `lib/dataflow.sh` |
| Project detection | Agents guess build systems | NOT in MAINFRAME | `lib/project.sh` |

### Priority 2: Performance Enhancements

| Gap | Impact | Proposed Fix |
|-----|--------|--------------|
| Subshell-heavy patterns | 20-80% slower than necessary | Refactor to `printf -v` + namerefs |
| No Bash 5.3 detection | Missing current-shell substitution | Add `bash_version_check` + feature gates |
| Array operations in loops | Fork overhead compounds | Use `mapfile` + bulk operations |
| String operations via pipes | Unnecessary process creation | Use parameter expansion exclusively |

### Priority 3: Security Automation (from Black Hat Bash)

| Gap | Use Case | Proposed Addition |
|-----|----------|-------------------|
| Network scanning wrappers | Host discovery automation | `lib/netscan.sh` |
| Banner grabbing | Service identification | Part of `lib/http.sh` enhancement |
| Port monitoring | Watchdog scripts | `lib/monitor.sh` |
| Tool output parsers | Nmap/RustScan/Nikto parsing | `lib/parsers.sh` |
| IP range generation | Target list creation | Already covered by `lib/net.sh` (if exists) |

---

## Consolidated Recommendations

### R1: Design-by-Contract Pattern (All New Functions)

Every new MAINFRAME function should declare:
```bash
# @pre: file exists and is readable
# @post: returns JSON object with file metadata
# @idempotent: yes
# @atomic: no
# @returns: 0 on success, 1 on file not found, 2 on parse error
file_metadata() { ... }
```

**Why**: AI agents read these annotations to predict behavior without reading implementations.

### R2: Structured Error Returns

Replace `echo "error" && return 1` with:
```bash
# Machine-parseable error context
_mainframe_error() {
    local code="$1" msg="$2" func="${FUNCNAME[1]}"
    printf '{"error":true,"code":%d,"msg":"%s","func":"%s","line":%d}\n' \
        "$code" "$msg" "$func" "${BASH_LINENO[0]}" >&2
    return "$code"
}
```

**Why**: AI agents can parse JSON errors and take corrective action automatically.

### R3: Idempotent Module (`lib/idempotent.sh`)

New functions:
- `ensure_dir` - mkdir only if missing
- `ensure_file` - create with content only if missing/different
- `ensure_line` - append line only if not present
- `ensure_symlink` - create/fix symlink atomically
- `ensure_mount` - mount only if not mounted
- `ensure_service` - start only if not running
- `ensure_package` - install only if not installed

### R4: Atomic File Operations (enhance `lib/files.sh`)

```bash
atomic_write()     # write-to-temp + mv (prevents partial writes)
atomic_append()    # flock + append (concurrent-safe)
atomic_replace()   # backup + write + verify (with rollback)
safe_remove()      # trash instead of rm (recoverable)
file_checkpoint()  # create named checkpoint for rollback
file_rollback()    # restore from checkpoint
```

### R5: Observability Module (`lib/observe.sh`)

```bash
trace_start()      # Begin trace with ID
trace_step()       # Record step in trace
trace_end()        # Complete trace, emit JSON summary
observe_command()  # Wrap command with timing + exit code capture
stack_trace()      # Emit bash call stack as JSON
```

### R6: Project Intelligence (`lib/project.sh`)

```bash
project_detect()   # Detect lang/framework/build from directory
project_commands() # Return common commands (build, test, lint, run)
project_deps()     # List dependencies from lock files
project_entry()    # Find main entry point
project_structure()# Return tree with annotations
```

### R7: Bash 5.3 Feature Gates

```bash
# Conditional use of modern features
if bash_has_feature "current_shell_substitution"; then
    result=${ expensive_computation; }
else
    result=$(expensive_computation)
fi
```

### R8: Security/Network Module (`lib/netscan.sh`)

Patterns from Black Hat Bash, adapted for defensive/admin use:
```bash
port_check()       # Check if port is open on host
host_alive()       # ICMP or TCP ping
banner_grab()      # Grab service banner from port
http_headers()     # Extract HTTP response headers
monitor_port()     # Watch for port state changes
scan_range()       # Scan IP range for live hosts
parse_nmap()       # Parse nmap greppable output
```

---

## Implementation Priority Matrix

| Phase | Module | Functions | Effort | Impact |
|-------|--------|-----------|--------|--------|
| 3A | `lib/idempotent.sh` | 7 | Low | Critical |
| 3A | Atomic file ops | 6 | Low | Critical |
| 3B | `lib/observe.sh` | 5 | Medium | High |
| 3B | `lib/project.sh` | 5 | Medium | High |
| 3C | Design-by-Contract annotations | All new funcs | Low | High |
| 3C | Structured error returns | Core refactor | Medium | High |
| 3D | Performance refactor (printf -v) | Existing funcs | High | Medium |
| 3D | Bash 5.3 feature gates | 3 | Low | Medium |
| 3E | `lib/netscan.sh` | 7 | Medium | Medium |
| 3E | `lib/parsers.sh` | 5 | Medium | Low |

---

## Success Metrics

1. **AI Predictability**: Functions with `@pre/@post` annotations show 40%+ fewer retry loops in AI usage
2. **Performance**: Subshell elimination yields measurable speedup in benchmarks
3. **Safety**: Zero partial-write incidents with atomic operations
4. **Coverage**: MAINFRAME grows from 550+ to 600+ functions
5. **Compatibility**: All new functions work on Bash 4.0+, with Bash 5.3 fast paths

---

## Next Steps

1. [ ] Implement Phase 3A (idempotent + atomic) - smallest effort, highest impact
2. [ ] Add Design-by-Contract annotations to top 50 most-used functions
3. [ ] Benchmark current subshell usage across all libraries
4. [ ] Prototype `project_detect` for the 10 most common project types
5. [ ] Create test suite for all new modules (TDD - write tests first)

---

*Synthesized from 5 research agents + Black Hat Bash (132 pages, 6.7MB PDF)*
*MAINFRAME v3.0 Enhancement Plan*

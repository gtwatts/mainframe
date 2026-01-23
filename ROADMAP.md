# MAINFRAME v4.0 Roadmap: AI-First Bash Standard Library

> Master Implementation Plan synthesized from 10 Review Agents + 3 Ideation Agents + Multi-AI Consensus

## Executive Summary

MAINFRAME is uniquely positioned as the **only AI-first bash standard library** with zero competitors in this space. Current state: 1,151 functions across 45 libraries, scoring A- (93/100) on code quality. The path to "100x AI productivity tool" requires 6 major architectural improvements prioritized by the multi-AI consensus (Grok, Gemini, GLM, DeepSeek).

**Multi-AI Debate Winner**: Universal Structured JSON Output is the foundational architectural decision - "it's the interface that enables everything else."

---

## Priority 1: Universal Structured Output Protocol (USOP) [CRITICAL]

**Consensus**: 4/4 AI models + all review agents agree this is foundational.

### New Modules
- `lib/output.sh` (~400 lines) - Core USOP envelope system
- `lib/errors.sh` (~200 lines) - Standardized error code registry + recovery suggestions
- `lib/hints.sh` (~150 lines) - Function hint database for "what to call next"

### Key Design
```bash
# Environment variable controls output mode
MAINFRAME_OUTPUT=json  # raw | json | minimal | debug

# Universal envelope
{"ok": true, "data": <result>, "meta": {"elapsed_ms": 42}, "hint": "next_function"}

# Error envelope with recovery
{"ok": false, "error": {"code": "E_PATH_NOT_FOUND", "msg": "...", "suggestion": "use file_exists first"}}
```

### Success Criteria
- Backward compatible (raw mode = current behavior)
- <15% overhead in json mode
- 80%+ functions adopt by v4.0
- All errors include actionable `suggestion` field

---

## Priority 2: Lazy Loading Module System [CRITICAL]

**Finding**: Current source time 50-150ms, loading all 45 libraries. Only 4-7 needed per script.

### Implementation
```bash
# Selective loading via environment variable
export MAINFRAME_LIBS='json,validation,path'  # Only load these

# Core tier (always loaded): common, pure-string, pure-array, json, validation, path, output
# Standard tier (on-demand): datetime, http, csv, git, docker, crypto
# Extended tier (lazy): k8s, semver, tui, netscan, parsers, functional
```

### Expected Results
- Source time: 50-150ms → 10-15ms (70-80% faster)
- Token savings: 27.8k → 8.9k tokens for documentation load (68% reduction)
- Agent only loads functions it will actually use

---

## Priority 3: Caching & Memoization System [HIGH]

### New Module: `lib/cache.sh` (~1200 lines)

Core capabilities:
- **Function memoization** with TTL: `memoize --ttl 300 http_get "$url"`
- **Content-addressable store**: Deduplication via SHA-256
- **Dependency-aware invalidation**: `memoize --invalidate-on package.json npm list`
- **Session cache**: In-memory + persistent across shells
- **Analytics**: Hit/miss tracking, LRU eviction
- **Smart preloading**: Pattern-based cache warming

### Key API
```bash
memoize [--ttl SECONDS] [--invalidate-on FILE...] FUNCTION [ARGS...]
cache_invalidate PATTERN
cache_stats [--json]
session_cache_set KEY VALUE
session_cache_get KEY [DEFAULT]
cache_warm "project-type=node"
```

---

## Priority 4: Safety Rails & Sandbox System [HIGH]

**Security Finding**: 80+ `eval` instances, TOCTOU in path validation, temp file insecurity.

### New Modules (8 total)
- `lib/scope.sh` - Filesystem/network/command boundaries
- `lib/dryrun.sh` - Preview destructive operations
- `lib/risk.sh` - Quantify danger (0-10 scale)
- `lib/undo.sh` - Automatic inverse operation recording
- `lib/limits.sh` - Resource consumption caps
- `lib/confirm.sh` - Human/orchestrator approval gates
- `lib/safewrap.sh` - Transparent command wrapping
- `lib/safecontext.sh` - Context profiles (dev/staging/prod)

### Key Design
```bash
# Enable safety system
mainframe_safety_init
mainframe_scope_set filesystem "$PWD:/tmp"
mainframe_limit_files 100
mainframe_limit_writes "10MB"

# Risk scoring
mainframe_risk_score "rm" "/etc/hosts"  # → 10 (CRITICAL)
mainframe_risk_score "rm" "/tmp/file"   # → 3 (LOW)

# Dry-run mode
MAINFRAME_DRY_RUN=1 ./deploy.sh  # Plan without execution
mainframe_plan_show               # Review plan
mainframe_plan_execute --confirm  # Execute with approval

# Undo
mainframe_undo --steps 3          # Reverse last 3 operations
```

---

## Priority 5: Security Hardening [HIGH]

### Critical Fixes
1. **Refactor eval usage** (80+ sites) → Use command arrays, whitelist commands
2. **Fix TOCTOU in validate_path_safe** → Use `realpath -e` + string prefix checking
3. **Secure temp files** → `umask 077` + trap cleanup + MAINFRAME_TMPDIR
4. **Fix /dev/tcp injection** → Strict hostname validation (RFC 1123)
5. **Fix Docker/K8s injection** → Use `--` separator, escape arguments
6. **Add AI-safe wrappers** → `ai_safe_exec`, `MAINFRAME_AI_MODE=1`
7. **Security audit logging** → Append-only `MAINFRAME_AUDIT_LOG`
8. **Separate security contracts** → Can't disable via `MAINFRAME_CONTRACTS_ENABLED=0`

---

## Priority 6: Documentation & Token Efficiency [MEDIUM]

### Critical Actions
1. **Complete CHEATSHEET.md** - Add 200+ v3.0 Phase 3 functions
2. **Create FUNCTIONS.json** - Machine-readable function index (8k token savings)
3. **Create DECISION_TREES.md** - "I want to do X, use function Y"
4. **Create ERRORS.json** - Structured error catalog for AI recovery
5. **Create mainframe quickref <library>** - Targeted lookup command
6. **Add @returns-type annotations** - To all 1,151 functions

---

## Priority 7: Test Coverage Expansion [MEDIUM]

**Finding**: 729 tests for 1,151 functions (0.63:1 ratio). 31/45 libraries have NO tests.

### Critical Missing Tests
- json.sh (33 functions, ZERO tests)
- datetime.sh (45 functions)
- http.sh (35 functions)
- csv.sh (34 functions)
- git.sh (52 functions)
- docker.sh (57 functions)
- async.sh (26 functions)
- functional.sh (56 functions)

### Additional Needs
- Bash version matrix testing (4.0, 4.2, 4.4, 5.0, 5.1, 5.2)
- Fuzzing tests for parsers
- Concurrent access tests
- Performance regression benchmarks
- Security-focused tests (injection, traversal)

---

## Priority 8: Agent Communication Protocol [LOW]

### New Module: `lib/agent.sh`
- `agent_register` - Register agent with name/capabilities
- `agent_send` / `agent_receive` - JSON message passing
- `agent_broadcast` - Multi-agent coordination
- `agent_barrier` - Synchronization point
- `agent_work_queue` - Task distribution

---

## Priority 9: Workflow Orchestration [LOW]

### New Module: `lib/workflow.sh`
- `workflow_define` - DAG-based workflow definition
- `workflow_step` - Add step with dependencies
- `workflow_run` - Execute workflow
- `workflow_visualize` - Generate Mermaid diagram
- Aligns with LangGraph/CrewAI patterns

---

## Implementation Phases

### Phase 4A: Foundation (Builds 1-3)
1. `lib/output.sh` - USOP core implementation
2. `lib/errors.sh` - Error registry
3. `lib/hints.sh` - Hint database
4. Lazy loading in `common.sh`
5. `mainframe quickref` command

### Phase 4B: Intelligence (Builds 4-6)
6. `lib/cache.sh` - Memoization system
7. `lib/scope.sh` + `lib/risk.sh` - Safety foundations
8. `lib/dryrun.sh` + `lib/undo.sh` - Plan-and-apply
9. FUNCTIONS.json generation
10. CHEATSHEET.md completion

### Phase 4C: Protection (Builds 7-9)
11. `lib/limits.sh` + `lib/confirm.sh` - Resource limits & gates
12. `lib/safewrap.sh` + `lib/safecontext.sh` - Transparent safety
13. Security hardening (eval refactor, TOCTOU fix)
14. DECISION_TREES.md
15. ERRORS.json catalog

### Phase 4D: Ecosystem (Builds 10-12)
16. `lib/agent.sh` - Multi-agent communication
17. `lib/workflow.sh` - DAG workflows
18. Test coverage expansion (target 80%+)
19. Bash version matrix CI
20. AI agent integration guides

---

## Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Functions | 1,151 | 1,500+ |
| Libraries | 45 | 55+ |
| Test coverage | 12-15% | 80%+ |
| Source time | 50-150ms | 10-15ms |
| Doc tokens | 27.8k | 8.9k |
| Security vulns | 80+ eval | 0 eval |
| Error recovery | 0% | 95%+ |

---

## Competitive Position

**MAINFRAME is the ONLY AI-first bash standard library.** No competitor exists:
- Bash-OO: Too complex, OO abstractions
- Bashible: Domain-specific DSL
- Pure Bash Bible: Reference only, not installable
- stdlib.sh: Outdated, minimal

**Unique Moats**: Zero dependencies, Phase 3 AI libraries, 20-72x performance, structured output, safety rails, function discovery.

**Positioning**: "Stop letting AI reinvent bash. Give it MAINFRAME."

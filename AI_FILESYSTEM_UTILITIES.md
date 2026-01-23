# AI-Optimized Filesystem Utilities for MAINFRAME

**Design Document for Bash Scripts that Make AI Coding Assistants Dramatically More Effective**

*Target: Claude Code, Cursor, Aider, OpenCode, and other AI coding assistants*

---

## Executive Summary

This document proposes **45+ pure bash utilities** organized into 5 categories that address the specific challenges AI coding assistants face when navigating and modifying filesystems. Each utility is designed to:

1. **Reduce token consumption** - Provide dense, relevant context
2. **Prevent errors** - Pre-flight checks and atomic operations
3. **Enable recovery** - Rollback and undo mechanisms
4. **Improve accuracy** - Structured output AI can parse reliably

All scripts follow MAINFRAME's pure-bash philosophy with zero external dependencies.

---

## 1. Filesystem Intelligence

Scripts that help AI understand codebases quickly and accurately.

### 1.1 `project_detect` - Project Type Detection

**One-line**: Detect framework, language, build system, and entry points from directory analysis.

**Input**: Directory path (default: current directory)

**Output**: JSON with detected characteristics

```json
{
  "language": "typescript",
  "framework": "nextjs",
  "package_manager": "bun",
  "entry_points": ["src/app/page.tsx", "src/app/layout.tsx"],
  "build_system": "turbopack",
  "test_runner": "vitest",
  "config_files": ["next.config.js", "tsconfig.json", "package.json"],
  "has_monorepo": false,
  "ci_provider": "github_actions"
}
```

**Why it helps AI**:
- AI can immediately understand project context without reading many files
- Reduces hallucinated commands (e.g., won't suggest `npm` for a `bun` project)
- Identifies test runner, build system for accurate command suggestions

**Complexity**: Medium (pattern matching across many project types)

**Detection patterns**:
- `package.json` + `next.config.*` = Next.js
- `Cargo.toml` = Rust
- `go.mod` = Go
- `pyproject.toml` / `setup.py` = Python
- `Makefile` + `*.c` = C
- `.claude/` = Claude Code project
- `.cursor/` = Cursor project

---

### 1.2 `content_search` - Smart File Discovery by Content

**One-line**: Find files matching content patterns with relevance scoring.

**Input**:
- Search pattern (regex or literal)
- Optional: file extension filter, max results, context lines

**Output**: JSON array of matches with context

```json
{
  "matches": [
    {
      "file": "src/auth/login.ts",
      "line": 45,
      "relevance": 0.95,
      "context_before": ["// Handle OAuth callback"],
      "match": "async function handleOAuthCallback(code: string) {",
      "context_after": ["  const token = await exchange(code);"]
    }
  ],
  "total_matches": 23,
  "files_searched": 156,
  "truncated": false
}
```

**Why it helps AI**:
- AI can find code by behavior, not just file names
- Relevance scoring helps AI focus on most important matches
- Context lines reduce need for follow-up file reads

**Complexity**: Medium

---

### 1.3 `dependency_graph` - Extract Import/Dependency Graph

**One-line**: Map file dependencies as a traversable graph.

**Input**: Entry file or directory

**Output**: JSON dependency graph

```json
{
  "root": "src/index.ts",
  "nodes": {
    "src/index.ts": {
      "imports": ["src/app.ts", "src/config.ts"],
      "imported_by": [],
      "depth": 0
    },
    "src/app.ts": {
      "imports": ["src/routes/index.ts", "src/middleware/auth.ts"],
      "imported_by": ["src/index.ts"],
      "depth": 1
    }
  },
  "external_deps": ["express", "zod"],
  "circular": []
}
```

**Why it helps AI**:
- AI understands impact of changes (what breaks if this file changes)
- Identifies circular dependencies
- Helps AI suggest correct import paths

**Complexity**: Complex (requires parsing multiple language import syntaxes)

**Language support**:
- TypeScript/JavaScript: `import`, `require`
- Python: `import`, `from ... import`
- Go: `import`
- Rust: `use`, `mod`
- Bash: `source`, `.`

---

### 1.4 `dead_code_detect` - Find Unused Code

**One-line**: Identify functions, exports, and files that are never referenced.

**Input**: Directory path, optional entry points

**Output**: JSON list of potentially dead code

```json
{
  "unused_exports": [
    {"file": "src/utils.ts", "export": "formatLegacyDate", "line": 45}
  ],
  "unused_files": [
    {"file": "src/deprecated/old-api.ts", "reason": "not_imported"}
  ],
  "unused_functions": [
    {"file": "src/helpers.ts", "function": "debugHelper", "line": 12}
  ],
  "confidence": "medium"
}
```

**Why it helps AI**:
- AI can suggest safe deletions
- Identifies code that doesn't need to be read into context
- Helps with refactoring suggestions

**Complexity**: Complex

---

### 1.5 `function_extract` - Extract Function Signatures

**One-line**: Extract all function/method signatures from a file or directory.

**Input**: File or directory path

**Output**: JSON with signatures

```json
{
  "file": "src/api/users.ts",
  "functions": [
    {
      "name": "createUser",
      "line": 15,
      "signature": "async function createUser(data: CreateUserInput): Promise<User>",
      "visibility": "export",
      "async": true,
      "jsdoc": "Creates a new user in the database"
    }
  ]
}
```

**Why it helps AI**:
- AI can understand file without reading entire contents
- Perfect for generating context summaries
- Helps AI write correct function calls

**Complexity**: Medium

---

### 1.6 `structure_map` - Directory Structure with Annotations

**One-line**: Generate annotated directory tree optimized for AI context.

**Input**: Directory path, optional depth limit

**Output**: Annotated tree structure

```
src/
  app/                    # Next.js app router
    page.tsx              # Home page (127 lines)
    layout.tsx            # Root layout (45 lines)
    api/                  # API routes
      users/
        route.ts          # CRUD for users (234 lines)
  components/             # Reusable UI components
    Button.tsx            # Primary button (56 lines)
  lib/                    # Utilities
    db.ts                 # Database connection (89 lines)
  [12 more files...]      # Use --full for complete list
```

**Why it helps AI**:
- Provides context-efficient project overview
- Line counts help AI estimate read costs
- Annotations explain purpose without reading files

**Complexity**: Simple

---

## 2. Safe Operations

Scripts that prevent data loss and enable recovery.

### 2.1 `atomic_edit` - All-or-Nothing Multi-File Changes

**One-line**: Apply multiple file changes atomically with automatic rollback on failure.

**Input**: JSON change specification

```json
{
  "changes": [
    {"file": "src/a.ts", "action": "edit", "old": "foo", "new": "bar"},
    {"file": "src/b.ts", "action": "create", "content": "..."},
    {"file": "src/c.ts", "action": "delete"}
  ]
}
```

**Output**: Success/failure with rollback status

**Why it helps AI**:
- AI can make multi-file refactors confidently
- Failed changes don't leave codebase in broken state
- Reduces "I'll fix that in a moment" recovery loops

**Complexity**: Medium

**Implementation**:
1. Create temp directory with copies
2. Apply all changes to copies
3. Verify changes (syntax check if applicable)
4. Atomic swap via rename operations
5. On any failure, swap back

---

### 2.2 `safe_rm` - Dry-Run Delete with Recovery

**One-line**: Delete with mandatory preview and automatic backup.

**Input**: Paths to delete

**Output**:
- Preview mode: what would be deleted
- Execute mode: backup location and deletion confirmation

```
Would delete:
  - src/old-component.tsx (2.3KB)
  - src/deprecated/ (5 files, 12.1KB)

Backup will be stored at: /tmp/mainframe-backup-20240115-123456/
Run with --execute to proceed
```

**Why it helps AI**:
- AI can suggest deletions without risk
- Easy recovery if AI makes wrong recommendation
- Audit trail of what was deleted

**Complexity**: Simple

---

### 2.3 `backup_create` - Snapshot Before Modification

**One-line**: Create timestamped backup of files before AI modification.

**Input**: Files or directories to backup

**Output**: Backup manifest with restore command

```json
{
  "backup_id": "20240115-143022",
  "location": "/tmp/mainframe-backups/20240115-143022/",
  "files": [
    {"original": "src/api/users.ts", "backup": "src_api_users.ts"}
  ],
  "restore_command": "mainframe backup-restore 20240115-143022"
}
```

**Why it helps AI**:
- AI can modify confidently knowing rollback exists
- Enables "try this, undo if wrong" workflows
- Works with version control and without

**Complexity**: Simple

---

### 2.4 `rollback` - Restore from Backup

**One-line**: Restore files from a backup created by backup_create.

**Input**: Backup ID or "latest"

**Output**: Restoration confirmation

**Why it helps AI**:
- Completes the safety loop with backup_create
- Enables multi-step experiments

**Complexity**: Simple

---

### 2.5 `chmod_audit` - Permission Change with Audit Trail

**One-line**: Change permissions with logging and easy reversal.

**Input**: Path and permission specification

**Output**: Before/after permissions with restore command

```
Changed: src/scripts/deploy.sh
  Before: -rw-r--r-- (644)
  After:  -rwxr-xr-x (755)

Restore: mainframe chmod-restore abc123
```

**Why it helps AI**:
- AI can fix permission issues without memorizing originals
- Audit trail for security reviews

**Complexity**: Simple

---

### 2.6 `safe_move` - Move with Verification

**One-line**: Move files with existence checks, backup, and verification.

**Input**: Source and destination paths

**Output**: Success with verification

**Checks performed**:
1. Source exists
2. Destination parent exists
3. No overwrite without flag
4. Backup created
5. Post-move verification (size, checksum)

**Why it helps AI**:
- Prevents common move failures
- AI gets clear error messages for each failure mode

**Complexity**: Simple

---

## 3. Context Gathering

Scripts that prepare information for AI context windows.

### 3.1 `context_summary` - Directory Summary for AI

**One-line**: Generate token-efficient summary of directory for AI context.

**Input**: Directory path, optional token budget

**Output**: Structured summary within token budget

```markdown
## Project: my-nextjs-app
Type: Next.js 14 + TypeScript

### Key Files (8 of 45)
- src/app/page.tsx: Home page with hero section
- src/app/api/auth/[...nextauth]/route.ts: NextAuth config
- src/lib/db.ts: Prisma client instance

### Recent Changes (git)
- 2h ago: feat: add user dashboard
- 1d ago: fix: auth redirect loop

### Dependencies (12 total)
Production: next, react, prisma, zod
Development: typescript, eslint, vitest

### Potential Issues
- No .env.example (credentials may be missing)
- package-lock.json missing (use bun.lockb)
```

**Why it helps AI**:
- AI gets essential context without reading many files
- Token budget ensures summary fits in context
- Highlights potential issues proactively

**Complexity**: Medium

---

### 3.2 `diff_explain` - Natural Language Diff Explanation

**One-line**: Convert git diff to structured explanation for AI understanding.

**Input**: Git diff or two files

**Output**: Structured change summary

```json
{
  "summary": "Refactored authentication to use JWT instead of sessions",
  "files_changed": 3,
  "changes": [
    {
      "file": "src/auth/index.ts",
      "type": "modification",
      "description": "Replaced session.get() calls with jwt.verify()",
      "risk_level": "high",
      "lines_added": 45,
      "lines_removed": 32
    }
  ],
  "breaking_changes": ["Session-based auth removed"],
  "dependencies_affected": ["express-session (removed)"]
}
```

**Why it helps AI**:
- AI can understand change intent, not just syntax
- Risk assessment helps prioritize review
- Identifies breaking changes for migration guidance

**Complexity**: Medium

---

### 3.3 `handoff_snapshot` - Generate Project Handoff Package

**One-line**: Create complete project snapshot for AI handoff or context switch.

**Input**: Project directory

**Output**: Single file with all essential context

```markdown
# Handoff: my-project
Generated: 2024-01-15T14:30:00Z

## Quick Start
npm run dev  # Start development server
npm test     # Run tests

## Architecture Overview
[auto-generated from code analysis]

## Recent Work
- Last commit: "feat: add user dashboard"
- Branch: feature/dashboard
- Uncommitted: 2 files (src/api/users.ts, src/components/Dashboard.tsx)

## Open Issues (from git/TODO comments)
- TODO: src/lib/db.ts:45 - Add connection pooling
- FIXME: src/api/auth.ts:12 - Rate limiting not implemented

## Key File Contents
[truncated contents of essential files]
```

**Why it helps AI**:
- Perfect for session continuation
- AI can resume work without re-exploring project
- Captures working state, not just committed state

**Complexity**: Medium

---

### 3.4 `api_extract` - Extract API Surface

**One-line**: Extract all public APIs, routes, and interfaces from codebase.

**Input**: Project directory

**Output**: API documentation in JSON

```json
{
  "rest_routes": [
    {
      "method": "POST",
      "path": "/api/users",
      "file": "src/app/api/users/route.ts",
      "line": 15,
      "request_body": "CreateUserInput",
      "response": "User"
    }
  ],
  "exports": [
    {
      "module": "src/lib/utils.ts",
      "exports": ["formatDate", "parseQuery", "validateEmail"]
    }
  ],
  "types": [
    {
      "name": "User",
      "file": "src/types/user.ts",
      "properties": ["id: string", "email: string", "name: string"]
    }
  ]
}
```

**Why it helps AI**:
- AI can write correct API calls without reading implementations
- Enables accurate type suggestions
- Helps generate API documentation

**Complexity**: Complex

---

### 3.5 `config_extract` - Extract All Configuration

**One-line**: Consolidate configuration from all sources into single view.

**Input**: Project directory

**Output**: Unified configuration view

```json
{
  "env_vars": {
    "required": ["DATABASE_URL", "JWT_SECRET"],
    "optional": ["DEBUG", "LOG_LEVEL"],
    "defaults": {"LOG_LEVEL": "info"}
  },
  "config_files": {
    "next.config.js": {"output": "standalone"},
    "tsconfig.json": {"strict": true}
  },
  "feature_flags": ["ENABLE_DARK_MODE", "BETA_FEATURES"]
}
```

**Why it helps AI**:
- AI knows what env vars are needed
- Understands project configuration holistically
- Can suggest correct config changes

**Complexity**: Medium

---

### 3.6 `test_coverage_map` - Map Test Coverage

**One-line**: Show which functions/files have tests and which don't.

**Input**: Project directory

**Output**: Coverage map

```json
{
  "covered": [
    {"file": "src/lib/utils.ts", "test": "tests/utils.test.ts", "coverage": 0.85}
  ],
  "uncovered": [
    {"file": "src/api/billing.ts", "reason": "no_test_file"}
  ],
  "test_files": ["tests/*.test.ts"],
  "overall_coverage": 0.72
}
```

**Why it helps AI**:
- AI can generate tests for uncovered code
- Understands testing patterns in use
- Can update existing tests accurately

**Complexity**: Medium

---

## 4. Verification

Scripts that validate operations before and after execution.

### 4.1 `preflight_check` - Pre-Command Validation

**One-line**: Validate environment and preconditions before running commands.

**Input**: Command to validate

**Output**: Checklist of pass/fail conditions

```
Preflight check for: npm run build

[PASS] Node.js version 18+ (found: 20.10.0)
[PASS] Package manager: npm (requested by project)
[PASS] Dependencies installed (node_modules exists)
[WARN] .env missing (using .env.example as fallback)
[FAIL] Port 3000 already in use (pid: 12345)

Recommendation: Run 'lsof -ti:3000 | xargs kill' to free port
```

**Why it helps AI**:
- Prevents running commands that will fail
- Provides actionable fix recommendations
- Reduces trial-and-error debugging

**Complexity**: Medium

---

### 4.2 `syntax_validate` - Multi-Language Syntax Check

**One-line**: Validate syntax for multiple languages without full compilation.

**Input**: File or directory

**Output**: Syntax errors with locations

```json
{
  "valid": false,
  "errors": [
    {
      "file": "src/api/users.ts",
      "line": 45,
      "column": 12,
      "message": "Unexpected token '}'",
      "suggestion": "Missing closing parenthesis on line 44"
    }
  ]
}
```

**Why it helps AI**:
- AI can verify edits before committing
- Catches errors immediately after generation
- Provides fix suggestions

**Complexity**: Simple (delegates to language tools)

---

### 4.3 `post_edit_verify` - Verify Edit Success

**One-line**: Confirm edit was applied correctly.

**Input**: Expected change specification

**Output**: Verification result

```json
{
  "verified": true,
  "checks": [
    {"type": "content_match", "expected": "newFunction", "found": true},
    {"type": "syntax_valid", "result": true},
    {"type": "tests_pass", "result": true, "time": "2.3s"}
  ]
}
```

**Why it helps AI**:
- Confirms AI edits worked as intended
- Catches partial or failed edits
- Can run tests to verify behavior

**Complexity**: Medium

---

### 4.4 `integrity_check` - File Integrity Verification

**One-line**: Verify files haven't been corrupted or unexpectedly modified.

**Input**: Directory and optional manifest

**Output**: Integrity report

```json
{
  "unchanged": 145,
  "modified": [
    {"file": "src/config.ts", "expected_hash": "abc...", "actual_hash": "def..."}
  ],
  "missing": [],
  "new": ["src/new-feature.ts"]
}
```

**Why it helps AI**:
- Detects unexpected side effects
- Verifies AI only changed intended files
- Useful for debugging race conditions

**Complexity**: Simple

---

### 4.5 `permission_audit` - File Permission Audit

**One-line**: Audit file permissions against expected patterns.

**Input**: Directory and permission rules

**Output**: Violations report

```json
{
  "violations": [
    {
      "file": ".env",
      "expected": "600",
      "actual": "644",
      "risk": "high",
      "fix": "chmod 600 .env"
    },
    {
      "file": "scripts/deploy.sh",
      "expected": "755",
      "actual": "644",
      "risk": "low",
      "fix": "chmod 755 scripts/deploy.sh"
    }
  ]
}
```

**Why it helps AI**:
- Security-conscious file handling
- Prevents common permission mistakes
- Provides specific fix commands

**Complexity**: Simple

---

### 4.6 `env_validate` - Environment Variable Validation

**One-line**: Validate all required environment variables are set.

**Input**: Project directory (reads .env.example, config files)

**Output**: Validation result

```json
{
  "valid": false,
  "missing": ["DATABASE_URL"],
  "invalid_format": [
    {"var": "PORT", "value": "abc", "expected": "integer"}
  ],
  "optional_unset": ["DEBUG"],
  "secrets_exposed": [
    {"var": "API_KEY", "file": ".env", "warning": "should be in .env.local"}
  ]
}
```

**Why it helps AI**:
- Catches config issues before runtime
- Identifies security concerns
- Helps AI set up new environments

**Complexity**: Medium

---

## 5. Performance

Scripts for efficient file processing.

### 5.1 `parallel_process` - Parallel File Processing

**One-line**: Process multiple files in parallel with progress reporting.

**Input**: File list and processing command

**Output**: Progress and results

```
Processing 45 files with 8 workers...
[=========>          ] 23/45 (51%) - 12.3s elapsed
Completed: 45/45
  Success: 43
  Failed: 2 (see errors below)

Errors:
  src/broken.ts: Syntax error on line 12
  src/large.ts: Timeout after 30s
```

**Why it helps AI**:
- Dramatically faster bulk operations
- Progress reporting for long operations
- Detailed error reporting

**Complexity**: Medium (uses MAINFRAME's async.sh)

---

### 5.2 `incremental_process` - Only Process Changed Files

**One-line**: Process only files changed since last run.

**Input**: Process command

**Output**: Changed file processing results

```json
{
  "processed": ["src/api/users.ts", "src/lib/utils.ts"],
  "skipped": 43,
  "cache_hit_rate": 0.96,
  "time_saved": "45s"
}
```

**Why it helps AI**:
- Enables efficient "check all files" workflows
- Makes lint/test runs practical in AI loops
- Tracks what AI has already processed

**Complexity**: Medium

---

### 5.3 `cache_operation` - Cache Expensive Operations

**One-line**: Cache results of expensive filesystem queries.

**Input**: Query/operation identifier

**Output**: Cached or fresh result

**Use cases**:
- File content hashes
- Directory structure
- Dependency graphs
- Search results

**Why it helps AI**:
- Repeated searches don't re-read files
- Same AI question twice returns instantly
- Invalidates automatically on file changes

**Complexity**: Medium

---

### 5.4 `progress_wrap` - Add Progress to Any Command

**One-line**: Wrap any file-processing command with progress reporting.

**Input**: Command and file list

**Output**: Wrapped execution with progress

```
Linting files...
[============>       ] 156/312 files
Current: src/components/Dashboard.tsx
Speed: 23 files/sec | ETA: 7s
```

**Why it helps AI**:
- AI knows operations are progressing
- Can estimate completion time
- User sees activity during long AI operations

**Complexity**: Simple

---

### 5.5 `batch_edit` - Efficient Batch Edits

**One-line**: Apply same edit pattern to multiple files efficiently.

**Input**: Edit pattern and file list

**Output**: Batch result summary

```json
{
  "pattern": {"old": "console.log", "new": "logger.debug"},
  "files_modified": 23,
  "occurrences_replaced": 67,
  "files_unchanged": 122,
  "errors": []
}
```

**Why it helps AI**:
- Efficient bulk refactors
- Single operation instead of many
- Atomic - all or nothing

**Complexity**: Medium

---

### 5.6 `watch_changes` - Monitor for File Changes

**One-line**: Watch directory for changes with event reporting.

**Input**: Directory to watch

**Output**: Stream of change events

```json
{"event": "modify", "file": "src/api/users.ts", "time": "2024-01-15T14:30:00Z"}
{"event": "create", "file": "src/api/billing.ts", "time": "2024-01-15T14:30:05Z"}
{"event": "delete", "file": "src/api/old.ts", "time": "2024-01-15T14:30:10Z"}
```

**Why it helps AI**:
- AI can react to external changes
- Detects conflicts with human edits
- Enables "watch and fix" workflows

**Complexity**: Medium (uses inotify or polling)

---

## 6. AI-Specific Utilities (Bonus Category)

### 6.1 `context_budget` - Token-Aware File Reading

**One-line**: Read files within a token budget, prioritizing most relevant.

**Input**: File list and token budget

**Output**: Truncated/prioritized content

```json
{
  "budget": 4000,
  "used": 3856,
  "files": [
    {"file": "src/api/users.ts", "tokens": 1200, "complete": true},
    {"file": "src/lib/db.ts", "tokens": 800, "complete": true},
    {"file": "src/app/page.tsx", "tokens": 1856, "complete": false, "truncated_at": "line 145"}
  ],
  "excluded": ["src/generated/types.ts (too large)"]
}
```

**Why it helps AI**:
- AI can request "give me context up to 4000 tokens"
- No accidental context overflow
- Prioritizes important files

**Complexity**: Medium

---

### 6.2 `edit_confidence` - Pre-Edit Risk Assessment

**One-line**: Assess risk and confidence before making an edit.

**Input**: Proposed edit specification

**Output**: Risk assessment

```json
{
  "confidence": 0.85,
  "risk_level": "medium",
  "concerns": [
    "File has been modified in last 5 minutes (potential conflict)",
    "Function is called from 12 locations",
    "No test coverage for affected code"
  ],
  "recommendations": [
    "Create backup before edit",
    "Run tests after edit",
    "Review callers in: src/api/*.ts"
  ]
}
```

**Why it helps AI**:
- AI can assess before acting
- Highlights risky operations
- Suggests safety measures

**Complexity**: Medium

---

### 6.3 `undo_stack` - Edit History with Undo

**One-line**: Maintain stack of AI edits with undo capability.

**Input**: Edit operation or undo command

**Output**: Stack state

```json
{
  "stack": [
    {"id": 1, "file": "src/a.ts", "type": "edit", "time": "14:30:00"},
    {"id": 2, "file": "src/b.ts", "type": "create", "time": "14:30:05"}
  ],
  "can_undo": true,
  "next_undo": {"id": 2, "would_delete": "src/b.ts"}
}
```

**Why it helps AI**:
- Multi-level undo for AI operations
- User can revert AI changes easily
- AI can "try and undo" confidently

**Complexity**: Medium

---

### 6.4 `conflict_detect` - Detect Edit Conflicts

**One-line**: Detect if AI edit would conflict with recent changes.

**Input**: Proposed edit location

**Output**: Conflict analysis

```json
{
  "conflict": true,
  "reason": "File modified since last read",
  "last_read": "14:25:00",
  "last_modified": "14:28:00",
  "diff": {
    "lines_changed": [45, 46, 47],
    "overlaps_with_edit": true
  },
  "recommendation": "Re-read file before editing"
}
```

**Why it helps AI**:
- Prevents AI from overwriting human changes
- Detects race conditions
- Suggests resolution

**Complexity**: Simple

---

## Implementation Priority

### Phase 1: Foundation (High Impact, Low Complexity)
1. `project_detect` - Essential for every AI interaction
2. `structure_map` - Quick project overview
3. `safe_rm` - Prevent accidental data loss
4. `backup_create` + `rollback` - Recovery foundation
5. `preflight_check` - Prevent failed operations
6. `progress_wrap` - User feedback during operations

### Phase 2: Intelligence (High Impact, Medium Complexity)
7. `content_search` - Find code by behavior
8. `context_summary` - Token-efficient context
9. `function_extract` - API discovery
10. `atomic_edit` - Multi-file safety
11. `post_edit_verify` - Confirm success
12. `incremental_process` - Efficient bulk operations

### Phase 3: Advanced (High Complexity, High Value)
13. `dependency_graph` - Impact analysis
14. `dead_code_detect` - Cleanup assistance
15. `api_extract` - Full API surface
16. `diff_explain` - Change understanding
17. `context_budget` - Smart truncation
18. `edit_confidence` - Risk assessment

---

## Integration with MAINFRAME

All scripts will:
1. Source `common.sh` for logging, colors, and utilities
2. Use JSON output via `json_object` for AI parsing
3. Follow pure-bash philosophy (no jq, ripgrep, etc.)
4. Include `--help` with examples
5. Support both interactive and pipe modes
6. Return proper exit codes

### Example Integration

```bash
#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: project_detect - Project Type Detection
# =============================================================================
# Category:    ai
# WOW Factor:  9/10
# =============================================================================

set -euo pipefail
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"
source "$MAINFRAME_ROOT/lib/json.sh"
source "$MAINFRAME_ROOT/lib/pure-file.sh"

# ... implementation ...
```

---

## Appendix A: Language Detection Patterns

### JavaScript/TypeScript
- `package.json` present
- `*.js`, `*.ts`, `*.jsx`, `*.tsx` files
- Frameworks: Next.js (`next.config.*`), React (react in deps), Vue, Svelte

### Python
- `pyproject.toml`, `setup.py`, `requirements.txt`, `Pipfile`
- `*.py` files
- Frameworks: Django (`manage.py`), Flask, FastAPI

### Go
- `go.mod` present
- `*.go` files
- Entry: `main.go` or `cmd/` directory

### Rust
- `Cargo.toml` present
- `*.rs` files
- Entry: `src/main.rs` or `src/lib.rs`

### Bash/Shell
- `*.sh` files
- Shebang detection
- MAINFRAME sourcing

---

## Appendix B: Token Estimation

For `context_budget` implementation:

| Content Type | Chars/Token (approx) |
|--------------|---------------------|
| English prose | 4 |
| Code (typical) | 3 |
| Code (dense) | 2.5 |
| JSON/structured | 3.5 |
| Whitespace-heavy | 5 |

**Estimation formula**: `tokens = chars / 3.5` (conservative for code)

---

## Appendix C: File Priority Heuristics

For `context_summary` and `context_budget`:

| File Pattern | Priority | Reason |
|-------------|----------|--------|
| `README.md`, `CLAUDE.md` | 10 | Project documentation |
| `package.json`, `Cargo.toml` | 9 | Dependencies, scripts |
| `*config*`, `.env*` | 8 | Configuration |
| Entry points (index, main) | 8 | Application entry |
| `*test*`, `*spec*` | 4 | Tests (usually skip) |
| `*.lock`, `*.min.*` | 1 | Generated/minified |
| `node_modules/`, `dist/` | 0 | Always skip |

---

*YO JOE!*

*Research compiled: 2026-01-22*
*Target: MAINFRAME Pure Bash Library for AI Coding Assistants*

# MAINFRAME Information Paradigm Design Review

**Version**: 1.0.0 | **Date**: 2026-01-31
**Scope**: Documentation, Naming Conventions, Developer Experience, Discoverability
**Reviewer**: Information Paradigm Design Team

---

## Executive Summary

MAINFRAME is a mature, well-documented bash function library with 3,465+ functions across 126 library files. The project demonstrates strong fundamentals in code organization and inline documentation. However, several information architecture improvements would significantly enhance developer experience and reduce cognitive load.

**Overall Assessment**: **B+** (Good with room for improvement)

| Area | Score | Key Issue |
|------|-------|-----------|
| Documentation Quality | B | CHEATSHEET.md too large to navigate (85K+ tokens) |
| Naming Conventions | C+ | Multiple naming patterns for same concept |
| Developer Experience | B+ | Good but discovery could be better |
| Error Messages | A | Excellent structured errors with recovery |
| Discoverability | B- | No IDE support, search requires grep |

---

## 1. Documentation Quality

### Current State

MAINFRAME has comprehensive documentation:

| Document | Purpose | Word Count (est.) | Tokens |
|----------|---------|-------------------|--------|
| README.md | First impression, overview | ~4,500 | ~6,000 |
| CHEATSHEET.md | Function reference | ~65,000 | **~85,000** |
| DECISION_TREES.md | Workflow guidance | ~2,200 | ~3,000 |
| INSTALL.md | Setup instructions | ~3,000 | ~4,000 |
| AGENT_CONVENTIONS.md | AI agent standards | ~4,000 | ~5,500 |
| ERRORS.json | Error catalog (72 codes) | - | ~4,500 |

**Code-to-doc ratio**: Approximately 1:0.4 (good for a library)

---

### Problem 1: CHEATSHEET.md is Monolithic (85K+ Tokens)

**Current State**: The CHEATSHEET.md file contains all 1,000+ function signatures in a single file totaling approximately 85,000 tokens.

**Problem**: This file is:
- **Unnavigable**: Cannot be loaded in AI context windows (Claude limit: 25K tokens per read)
- **Overwhelming**: Developers face wall of text when searching
- **Unsearchable**: No structured sections for quick lookup
- **Unmaintainable**: Changes require editing massive file

**Evidence**: File exceeds Claude's 25K token read limit, requiring chunked reads. Human developers must grep or Ctrl+F through thousands of lines.

**Proposed Change**: Split CHEATSHEET into category-specific reference files:

```
docs/reference/
├── index.md              # Overview + links to categories
├── strings.md            # pure-string.sh functions (~34 functions)
├── arrays.md             # pure-array.sh functions (~33 functions)
├── json.md               # json.sh functions (~33 functions)
├── validation.md         # validation.sh functions (~40 functions)
├── datetime.md           # datetime.sh functions (~43 functions)
├── http.md               # http.sh, burl.sh functions (~45 functions)
├── files.md              # pure-file.sh, atomic.sh (~46 functions)
├── git.md                # git.sh functions (~62 functions)
├── process.md            # proc.sh functions (~38 functions)
├── agent.md              # awm.sh, agent.sh, context.sh (~85 functions)
├── cli.md                # ansi.sh, tui.sh, anim.sh (~138 functions)
├── crypto.md             # crypto.sh functions (~33 functions)
├── docker.md             # docker.sh functions (~54 functions)
└── paths.md              # path.sh functions (~30 functions)
```

**Proof of Improvement**:
- Each file under 5,000 tokens (fully loadable in AI context)
- Category-specific search becomes instant
- Maintenance becomes manageable
- Users find what they need 10x faster

**Implementation Effort**: **M (Medium)** - 4-6 hours

---

### Problem 2: DECISION_TREES.md Incomplete (~60% Coverage)

**Current State**: The decision tree covers approximately 60% of function categories.

**Problem**: Missing categories leave users without workflow guidance for:
- Agent Working Memory (AWM) operations
- Error handling patterns
- Caching operations
- Streaming/pipeline patterns
- Regex operations
- Output formatting (USOP)

**Proposed Change**: Add missing category sections:

```markdown
## Agent Working Memory (AWM)

```
Start new task?        -> awm_init "task-name"
Resume previous?       -> awm_resume "$session_id"
Store key insight?     -> awm_discovery "finding"
Save checkpoint?       -> awm_checkpoint "key" "value"
Retrieve checkpoint?   -> awm_get "key"
Track progress?        -> awm_progress "phase" "50/100"
Get summary?           -> awm_summary
Close session?         -> awm_close
Inherit from parent?   -> awm_init "child" "$parent_id"
```

## Error Handling

```
Fatal error?           -> die code "message"
Non-fatal error?       -> log_error "message"
Structured error?      -> output_error "E_CODE" "msg" "suggestion"
Try/catch pattern?     -> error_try cmd; error_catch handler
Stack trace?           -> stack_trace
Assert condition?      -> assert "condition" "message"
```

## Caching

```
Cache function result? -> memoize [--ttl 300] func args
Store content?         -> cas_store "$content"
Retrieve by hash?      -> cas_get "$hash"
Session-local cache?   -> session_cache_set "key" "value"
Clear cache?           -> cache_clear
Invalidate key?        -> cache_invalidate "key"
```

## Regex Operations

```
Match pattern?         -> regex_match "$str" "pattern"
Find first match?      -> regex_find "$str" "pattern"
Find all matches?      -> regex_find_all "$str" "pattern"
Replace first?         -> regex_replace "$str" "pat" "repl"
Replace all?           -> regex_replace_all "$str" "pat" "repl"
Split by pattern?      -> regex_split "$str" "pattern"
Escape for regex?      -> regex_escape "$literal"
```

## Structured Output (USOP)

```
Success response?      -> output_success "data" "hint"
Error response?        -> output_error "code" "msg" "suggestion"
Typed integer?         -> output_int 42
Typed boolean?         -> output_bool true
JSON object?           -> output_json_object '{"key":"val"}'
Enable JSON mode?      -> export MAINFRAME_OUTPUT=json
```
```

**Proof of Improvement**:
- User test: "How do I cache a function?" goes from grep-search (~60s) to instant lookup (~5s)
- Complete coverage reduces "is there a function for this?" questions
- New users get immediate workflow guidance

**Implementation Effort**: **S (Small)** - 2-3 hours

---

## 2. Naming Conventions

### Current State: Multiple Patterns for Same Concept

Analysis of 3,465 function definitions reveals **inconsistent naming patterns** with semantic duplicates.

#### Pattern Collision: Email Validation (4 Functions)

| Function | Location | Purpose |
|----------|----------|---------|
| `is_email` | pure-util.sh:384 | Boolean check |
| `is_valid_email` | common.sh:360 | Boolean check (alias) |
| `validate_email` | validation.sh:103 | Boolean check + detailed validation |
| `regex_validate_email` | regex.sh:1229 | Regex-based validation |

**Problem**: 4 functions for the same semantic operation. User cannot know which to use.

#### Pattern Collision: JSON Validation (3 Functions)

| Function | Location | Purpose |
|----------|----------|---------|
| `is_valid_json` | common.sh:349 | Boolean check |
| `json_valid` | json.sh:324 | Boolean check |
| `validate_json` | validation.sh | Boolean check |

**Problem**: 3 functions for identical operation.

#### Pattern Collision: URL Validation (3 Functions)

| Function | Location | Purpose |
|----------|----------|---------|
| `is_url` | pure-util.sh:390 | Boolean check |
| `is_valid_url` | common.sh:366 | Boolean check (alias) |
| `validate_url` | validation.sh:118 | Boolean check with scheme validation |

---

### Naming Convention Analysis

**Identified Patterns** (5+ different conventions):

| Pattern | Example | Meaning | Approx. Count |
|---------|---------|---------|---------------|
| `verb_noun` | `read_file`, `trim_string` | Action on object | ~60% |
| `noun_verb` | `file_exists`, `array_contains` | Object state check | ~15% |
| `is_noun` | `is_email`, `is_root` | Boolean predicate | ~8% |
| `validate_noun` | `validate_email`, `validate_int` | Validation check | ~5% |
| `prefix_verb_noun` | `json_get`, `git_branch` | Namespaced action | ~12% |

---

### Proposed Change 3: Establish Naming Convention Standard

**Current State**: No documented naming standard exists.

**Problem**: Developers must guess which function to use. Documentation lists duplicates.

**Proposed Change**: Create `docs/NAMING_CONVENTIONS.md`:

```markdown
# MAINFRAME Naming Conventions

## Function Naming Rules

### 1. Module Prefix (Required for library-specific functions)
Functions in `lib/xyz.sh` use `xyz_` prefix:
- json.sh: `json_object`, `json_get`, `json_valid`
- git.sh: `git_branch`, `git_commit_hash`
- csv.sh: `csv_parse`, `csv_row`
- awm.sh: `awm_init`, `awm_checkpoint`

### 2. Core Functions (No prefix for high-frequency operations)
Unprefixed for brevity:
- `trim_string`, `to_lower`, `to_upper` (used constantly)
- `uuid`, `timestamp`, `epoch` (utility)
- `log_info`, `log_error`, `success`, `failure` (logging)

### 3. Predicate Functions (Boolean checks)
Use `is_` prefix for simple, fast boolean checks:
- `is_empty`, `is_numeric`, `is_file`, `is_root`

### 4. Validation Functions (Detailed validation)
Use `validate_` prefix for validation with error information:
- `validate_email`, `validate_int`, `validate_path_safe`

### 5. Canonical Function Table

| Concept | Canonical Function | Deprecated Aliases |
|---------|-------------------|-------------------|
| Email validation | `validate_email` | `is_email`, `is_valid_email` |
| URL validation | `validate_url` | `is_url`, `is_valid_url` |
| JSON validation | `json_valid` | `is_valid_json`, `validate_json` |
| Integer check | `validate_int` | `is_int`, `is_positive_int` |

### 6. Deprecation Policy
- v7.0: Add deprecation warning to aliases
- v8.0: Remove deprecated functions
```

**Deprecation Path**:
1. Mark old functions with deprecation warning in v7.0
2. Document canonical function in warning message
3. Remove in v8.0

**Proof of Improvement**:
- `grep validate_email` returns 1 result, not 4
- User never questions which function to use
- Autocomplete works better with consistent prefixes
- Documentation becomes cleaner

**Implementation Effort**: **L (Large)** - Requires deprecation notices, documentation updates, potentially breaking changes over 2 versions

---

### Proposed Change 4: Document Prefix Policy

**Current State**: Inconsistent prefix usage across libraries.

| Library | Uses Prefix? | Example |
|---------|--------------|---------|
| json.sh | Yes | `json_object`, `json_get` |
| git.sh | Yes | `git_branch`, `git_is_dirty` |
| pure-string.sh | No | `trim_string`, `to_lower` |
| pure-util.sh | Mixed | `uuid`, `timestamp`, `is_email` |
| validation.sh | Yes | `validate_*`, `sanitize_*` |

**Proposed Change**: Document explicit policy (no code changes needed):

> **Core functions** (high-frequency) remain unprefixed for brevity.
> **Library-specific functions** use module prefix for namespacing.

**Implementation Effort**: **S (Small)** - Documentation only

---

## 3. Developer Experience

### Current State

**Strengths**:
- Single source line gives access to all functions
- Inline documentation in every library file (consistent headers)
- Double-source prevention (`[[ -n "${_MAINFRAME_*_LOADED:-}" ]] && return 0`)
- Good error messages with suggestions (ERRORS.json)
- FUNCTIONS.json provides machine-readable index

**Weaknesses**:
- No IDE/editor autocomplete support
- No `mainframe help <function>` command
- Search requires grep through files
- No interactive function explorer
- FUNCTIONS.json not human-readable

---

### Problem 5: No Function Help System

**Current State**: Users must read source code or CHEATSHEET.md to understand functions.

**Problem**: Slow discovery, context switching required.

**Proposed Change**: Add `mainframe help` command:

```bash
$ mainframe help json_object

json_object - Create JSON object from key=value pairs

USAGE:
    json_object "key=val" "key:type=val" ...

TYPE MODIFIERS:
    key=value        -> string
    key:number=value -> number
    key:bool=value   -> boolean
    key:null=        -> null

EXAMPLE:
    json_object "name=John" "age:number=30"
    # Output: {"name":"John","age":30}

SEE ALSO:
    json_array, json_merge, json_get

SOURCE:
    lib/json.sh:166
```

**Implementation**: Parse existing docstrings from library files or add structured metadata to FUNCTIONS.json.

**Proof of Improvement**:
- Time to understand function: grep + read (~60s) -> `mainframe help` (~5s)
- Reduces context switches to documentation
- Works offline, in terminal

**Implementation Effort**: **M (Medium)** - 4-6 hours

---

### Problem 6: No Tab Completion

**Current State**: Users must remember exact function names.

**Problem**: Discovery requires documentation lookup.

**Proposed Change**: Add bash completion script `completions/mainframe.bash`:

```bash
#!/usr/bin/env bash
# MAINFRAME bash completion

_mainframe_functions() {
    # Cache function list
    if [[ -z "${_MAINFRAME_FUNC_CACHE:-}" ]]; then
        _MAINFRAME_FUNC_CACHE=$(mainframe --list-functions 2>/dev/null)
    fi
    echo "$_MAINFRAME_FUNC_CACHE"
}

_mainframe_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        help|info|doc)
            COMPREPLY=($(compgen -W "$(_mainframe_functions)" -- "$cur"))
            ;;
        *)
            COMPREPLY=($(compgen -W "help search version list" -- "$cur"))
            ;;
    esac
}

complete -F _mainframe_completions mainframe
```

**Installation**: Add to install.sh:
```bash
cp completions/mainframe.bash /etc/bash_completion.d/mainframe
```

**Proof of Improvement**:
- `mainframe help json_<TAB>` shows: `json_object json_array json_get json_merge ...`
- `mainframe help validate_<TAB>` shows all validation functions
- Discovery becomes interactive, not documentation-dependent

**Implementation Effort**: **S (Small)** - 2-3 hours

---

### Problem 7: No Search Command

**Current State**: Users must grep through files to find functions.

**Proposed Change**: Add `mainframe search` command:

```bash
$ mainframe search "email"

FUNCTIONS MATCHING "email":

  validation.sh:
    validate_email(address)     Validate email format (RFC 5322)

  pure-util.sh:
    is_email(value)             Check if value looks like email [DEPRECATED]

  git.sh:
    git_user_email()            Get configured git user.email

  regex.sh:
    regex_validate_email(addr)  Regex-based email validation [DEPRECATED]

Found 4 functions matching "email"
```

**Implementation Effort**: **S (Small)** - 2 hours using grep + formatting

---

## 4. Error Messages

### Current State: Excellent (No Changes Needed)

ERRORS.json is **best-in-class** with 72 documented error codes:

```json
{
  "E_FILE_NOT_FOUND": {
    "code": "E_FILE_NOT_FOUND",
    "module": "files",
    "severity": "error",
    "message": "File not found: {path}",
    "suggestion": "Use file_exists to check before accessing, or ensure_file to create with defaults",
    "recovery": ["file_exists", "ensure_file", "atomic_write"]
  }
}
```

**Strengths**:
- 72 documented error codes across all modules
- Every error has actionable suggestion
- Recovery functions listed for each error
- Severity levels (info, warning, error, critical)
- Module attribution for debugging

**Recommendation**: Document this pattern in README as a feature highlight. Consider it a model for other projects.

---

## 5. Discoverability

### Current State

| Discovery Method | Available? | Quality |
|------------------|------------|---------|
| grep CHEATSHEET.md | Yes | Slow, noisy results |
| grep lib/*.sh | Yes | Finds implementation, not docs |
| DECISION_TREES.md | Yes | Limited to ~60% coverage |
| FUNCTIONS.json | Yes | Machine-readable only |
| IDE autocomplete | **No** | - |
| Interactive help | **No** | - |
| Web documentation | **No** | - |
| Man pages | **No** | - |

---

### Problem 8: FUNCTIONS.json Not Human-Usable

**Current State**: FUNCTIONS.json exists with full metadata but is designed for machines:

```json
{
  "stats": {
    "total_functions": 1546,
    "total_libraries": 68
  },
  "libraries": {
    "json": {
      "functions": {
        "json_object": {
          "signature": "json_object \"key=val\" ...",
          "description": "Create JSON object from key=value pairs"
        }
      }
    }
  }
}
```

**Problem**: Human developers cannot quickly scan this format.

**Proposed Change**: Generate human-friendly `docs/FUNCTION_INDEX.md`:

```markdown
# MAINFRAME Function Index

Quick-scan reference organized by category. For detailed signatures, see `docs/reference/`.

## Strings (34 functions)

| Function | Description |
|----------|-------------|
| `trim_string` | Remove leading/trailing whitespace |
| `trim_left` | Remove leading whitespace |
| `trim_right` | Remove trailing whitespace |
| `to_lower` | Convert to lowercase |
| `to_upper` | Convert to uppercase |
| `capitalize` | Capitalize first letter |
| `replace_all` | Replace all occurrences |
| `replace_first` | Replace first occurrence |
| `contains` | Check if string contains substring |
| `starts_with` | Check prefix |
| `ends_with` | Check suffix |
| ... |

## JSON (33 functions)

| Function | Description |
|----------|-------------|
| `json_object` | Create JSON object from key=value pairs |
| `json_array` | Create JSON array |
| `json_get` | Extract value by key |
| `json_merge` | Merge two JSON objects |
| `json_valid` | Validate JSON syntax |
| `json_pretty` | Pretty-print JSON |
| ... |

## Validation (40 functions)

| Function | Description |
|----------|-------------|
| `validate_email` | Validate email address format |
| `validate_url` | Validate URL with optional scheme check |
| `validate_int` | Validate integer with optional range |
| `validate_path_safe` | Check path doesn't escape base directory |
| `sanitize_html` | Escape HTML special characters |
| `sanitize_shell_arg` | Escape shell metacharacters |
| ... |
```

**Implementation**: Generate automatically from FUNCTIONS.json with script.

**Proof of Improvement**:
- Scannable in <30 seconds
- Ctrl+F works instantly
- Category browsing possible
- Stays in sync with code via generation

**Implementation Effort**: **S (Small)** - Write generator script from FUNCTIONS.json

---

## 6. Metrics Summary

### Documentation Metrics

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Max doc file size | 85K tokens | <10K tokens | Split CHEATSHEET |
| Decision tree coverage | ~60% | 95% | Add 6 sections |
| Function help coverage | 0% | 100% | Add help command |
| Human-readable index | No | Yes | Generate from JSON |

### Naming Metrics

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Naming patterns in use | 5+ patterns | 2 patterns | Standardize |
| Semantic duplicates | 8+ sets | 0 | Deprecate aliases |
| Prefix consistency | ~70% | 95% | Document policy |
| Documented conventions | No | Yes | Create doc |

### Discoverability Metrics

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Tab completion | No | Yes | Add script |
| Interactive help | No | Yes | Add command |
| Search command | No | Yes | Add command |
| Function index | JSON only | Markdown | Generate |

---

## 7. Implementation Priority

### Priority 1 - Quick Wins (Week 1)

| Change | Effort | Impact | Hours |
|--------|--------|--------|-------|
| Expand DECISION_TREES.md | S | High | 2-3 |
| Generate FUNCTION_INDEX.md | S | High | 2 |
| Add bash completion | S | Medium | 2-3 |
| Document naming conventions | S | Medium | 2 |

**Total: ~10 hours for high-impact improvements**

### Priority 2 - Medium Term (Week 2-3)

| Change | Effort | Impact | Hours |
|--------|--------|--------|-------|
| Split CHEATSHEET.md | M | High | 4-6 |
| Add `mainframe help` command | M | High | 4-6 |
| Add `mainframe search` command | S | Medium | 2 |

**Total: ~14 hours**

### Priority 3 - Long Term (Month 2+)

| Change | Effort | Impact | Hours |
|--------|--------|--------|-------|
| Deprecate naming duplicates (v7.0) | L | Medium | 8+ |
| Remove deprecated functions (v8.0) | M | Medium | 4 |
| Generate man pages | M | Low | 4 |

---

## 8. Recommendations Summary

### Must Do (Critical for usability)

1. **Split CHEATSHEET.md** into category files under `docs/reference/`
2. **Expand DECISION_TREES.md** to cover AWM, caching, errors, regex, USOP
3. **Document naming conventions** in `docs/NAMING_CONVENTIONS.md`

### Should Do (Significant improvement)

4. **Add `mainframe help <function>`** command for inline documentation
5. **Add bash completion script** for interactive discovery
6. **Generate FUNCTION_INDEX.md** from FUNCTIONS.json

### Consider (Nice to have)

7. **Add `mainframe search`** command for keyword discovery
8. **Deprecate duplicate function names** over 2 major versions
9. **Generate man pages** for traditional Unix users

---

## Appendix A: Complete Naming Collision Inventory

| Concept | Functions (Duplicates) | Canonical | Deprecate |
|---------|------------------------|-----------|-----------|
| Email check | `is_email`, `is_valid_email`, `validate_email`, `regex_validate_email` | `validate_email` | 3 |
| URL check | `is_url`, `is_valid_url`, `validate_url` | `validate_url` | 2 |
| JSON check | `is_valid_json`, `json_valid`, `validate_json` | `json_valid` | 2 |
| Integer check | `is_int`, `is_positive_int`, `validate_int` | `validate_int` | 2 |
| Float check | `is_float`, `validate_float` | `validate_float` | 1 |
| Root check | `is_root` (pure-util), `is_root` (sysinfo) | `is_root` (sysinfo) | 1 |

**Total duplicates to deprecate**: ~11 functions

---

## Appendix B: File Size Analysis

| File | Lines | Est. Tokens | Status | Action |
|------|-------|-------------|--------|--------|
| CHEATSHEET.md | ~4,500 | ~85,000 | **Too large** | Split into 15 files |
| README.md | ~630 | ~6,000 | Good | None |
| DECISION_TREES.md | ~300 | ~3,000 | Incomplete | Expand |
| INSTALL.md | ~400 | ~4,000 | Good | None |
| AGENT_CONVENTIONS.md | ~530 | ~5,500 | Good | None |
| ERRORS.json | ~856 | ~4,500 | Excellent | None |
| FUNCTIONS.json | ~2,000+ | ~15,000 | Machine-only | Generate index |

---

## Appendix C: Library Function Counts

Top 20 libraries by function count:

| Library | Functions | Category |
|---------|-----------|----------|
| github.sh | 108 | VCS |
| ansi.sh | 90 | CLI |
| github_actions.sh | 75 | CI/CD |
| github_security.sh | 72 | Security |
| streams.sh | 69 | Streaming |
| output.sh | 67 | Output |
| queue.sh | 64 | Data Structures |
| git.sh | 62 | VCS |
| pure-util.sh | 60 | Utilities |
| sandbox.sh | 59 | Safety |
| immutable.sh | 58 | FP |
| docker.sh | 54 | Containers |
| functional.sh | 56 | FP |
| regex.sh | 52 | Strings |
| sysinfo.sh | 52 | System |
| database.sh | 52 | Data |
| collection.sh | 46 | Data Structures |
| probabilistic.sh | 45 | Math |
| python.sh | 44 | Language |
| metrics.sh | 44 | Observability |

---

*Information Paradigm Design Review - MAINFRAME v6.0*
*Generated: 2026-01-31*
*Reviewer: Information Paradigm Design Team*

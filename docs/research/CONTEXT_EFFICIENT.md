# MAINFRAME - Context-Efficient Integration

This guide helps you integrate MAINFRAME without contributing to context rot.

## The Golden Rule

**Don't read MAINFRAME source code into context. Just use the functions.**

MAINFRAME loads into BASH, not into the AI's context window. The AI only needs to know:
1. How to source it
2. What functions exist (names only)
3. Basic usage patterns

## Minimal CLAUDE.md Entry (Recommended)

Add this compact block to your `~/.claude/CLAUDE.md`:

```markdown
## MAINFRAME (Bash)
`source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"`
Functions: trim_string, to_lower, to_upper, json_object, json_array, uuid, timestamp, array_unique, array_join, progress_bar, is_valid_email, semver_bump_*
```

**That's it.** ~50 tokens. The AI can discover more functions by trying them.

## What NOT to Do

```markdown
# BAD - Don't do this in CLAUDE.md
## MAINFRAME
Here are all 400 functions with descriptions:
- trim_string(str) - Trims whitespace from both ends...
- trim_left(str) - Trims whitespace from left...
- trim_right(str) - Trims whitespace from right...
[... 397 more entries ...]
```

This wastes 5,000+ tokens and contributes to context rot.

## What NOT to Ask Your AI

- ❌ "Read all the MAINFRAME source files"
- ❌ "Show me every function in MAINFRAME"
- ❌ "Dump the contents of common.sh"

## What TO Ask Your AI

- ✅ "Use MAINFRAME to generate JSON" (AI tries `json_object`)
- ✅ "Is there a MAINFRAME function for X?" (AI tries it)
- ✅ "Write a script using MAINFRAME" (AI sources and uses)

## Discovery Over Documentation

Let the AI discover functions by trying them:

```bash
# AI tries: json_object name="test"
# Works? Great. Doesn't exist? AI adapts.
```

This is more context-efficient than pre-loading all documentation.

## Cheat Sheet (For Human Reference, Not AI Context)

Keep this for YOUR reference. Don't paste into AI prompts.

| Category | Key Functions |
|----------|---------------|
| Strings | trim_string, to_lower, to_upper, replace_all |
| Arrays | array_unique, array_join, array_contains |
| JSON | json_object, json_array, json_nested |
| Utils | uuid, timestamp, random_string |
| Validation | is_valid_email, is_valid_url |
| UI | progress_bar, success, failure, header |

## Session Hygiene

1. **Start of session**: AI reads CLAUDE.md (includes minimal MAINFRAME entry)
2. **During session**: AI uses functions without re-reading docs
3. **If stuck**: AI can `source ... && type function_name` to check if it exists
4. **Never**: Dump full source code into context

## The Math

| Approach | Tokens | Context Impact |
|----------|--------|----------------|
| Minimal CLAUDE.md entry | ~50 | Negligible |
| Function cheat sheet | ~200 | Low |
| Full documentation | ~2,000 | Medium |
| All source code | ~15,000 | HIGH (context rot) |

**Recommendation**: Use the ~50 token approach. Let AI discover the rest.

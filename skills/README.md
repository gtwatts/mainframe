# MAINFRAME Skills for AI Coding Assistants

Pre-built instruction files that teach AI coding assistants about MAINFRAME's 1,100+ pure bash functions.

## Supported Platforms

| Platform | Directory | Format | Install |
|----------|-----------|--------|---------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `claude-code/` | SKILL.md | Symlink to `~/.claude/skills/` |
| [Cursor](https://cursor.com) | `cursor/` | .mdc | Copy to `.cursor/rules/` |
| [Aider](https://aider.chat) | `aider/` | CONVENTIONS.md | Reference in `.aider.conf.yml` |
| [Vercel AI SDK](https://ai-sdk.dev) | `vercel-ai-sdk/` | System prompt | Load in agent config |

## Quick Install

### Claude Code

```bash
# Symlink the skill (one-time setup)
ln -s ~/.mainframe/skills/claude-code ~/.claude/skills/mainframe-bash
```

The skill auto-activates when Claude Code detects bash scripting tasks.

### Cursor

```bash
# Copy to your project's Cursor rules
mkdir -p .cursor/rules
cp ~/.mainframe/skills/cursor/mainframe.mdc .cursor/rules/

# Or for global use, add to ~/.cursor/rules/
```

### Aider

```bash
# Option 1: Copy to project
cp ~/.mainframe/skills/aider/CONVENTIONS.md .
cp ~/.mainframe/skills/aider/.aider.conf.yml .

# Option 2: Global config (~/.aider.conf.yml)
echo 'read: ~/.mainframe/skills/aider/CONVENTIONS.md' >> ~/.aider.conf.yml
```

### Vercel AI SDK / Custom Agents

```typescript
import { readFileSync } from 'fs';

// Load as system prompt
const system = readFileSync(
  `${process.env.HOME}/.mainframe/skills/vercel-ai-sdk/system-prompt.md`,
  'utf-8'
);
```

### Any Other AI Assistant

Point your AI at the project's `CLAUDE.md` file (in the repo root) which contains the full MAINFRAME function reference and usage patterns.

## What Each Skill Does

Each skill file teaches the AI:

1. **How to source MAINFRAME** - The one-liner that loads everything
2. **Function categories** - JSON, strings, arrays, validation, crypto, git, etc.
3. **Replacement table** - Which MAINFRAME function replaces which external tool
4. **Common patterns** - Script templates, error handling, JSON generation
5. **Rules** - When to use MAINFRAME vs. external tools

## Creating Skills for Other Platforms

If your AI coding assistant supports custom instructions, create a file that includes:

```
When writing bash scripts, source MAINFRAME first:
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

Use MAINFRAME's 1,100+ functions instead of jq, sed, awk, cat.
Full reference: ~/.mainframe/CHEATSHEET.md
```

Pull requests welcome for additional platform support.

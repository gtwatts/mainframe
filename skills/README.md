# MAINFRAME Skills for AI Coding Assistants

Pre-built instruction files that teach AI coding assistants about MAINFRAME's 3,821+ pure bash functions across 152 libraries.

## Supported Platforms

| Platform | Directory | Format | Install |
|----------|-----------|--------|---------|
| Pi | `pi/` | SKILL.md | Load as a Pi skill or project instruction; use Pi MAINFRAME tools when available |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `claude-code/` | SKILL.md | Symlink to `~/.claude/skills/` |
| OpenAI Codex / Codex CLI | `codex/` | AGENTS.md | Copy or merge into project `AGENTS.md` |
| [Kimi CLI](https://docs.moonshot.cn/kimi-cli) | `kimi-cli/` | SKILL.md | Load in Kimi CLI instructions |
| [Google CLI](https://ai.google.dev/) | `google-cli/` | SKILL.md | Load in agent config |
| [OpenCode](https://opencode.ai) | `opencode/` | SKILL.md | Load in agent config |
| [Clawdbot](https://github.com/clawdbot/clawdbot) | `clawdbot/` | Preamble | Add to `clawdbot.json` |
| [Cursor](https://cursor.com) | `cursor/` | .mdc | Copy to `.cursor/rules/` |
| [Aider](https://aider.chat) | `aider/` | CONVENTIONS.md | Reference in `.aider.conf.yml` |
| [Vercel AI SDK](https://ai-sdk.dev) | `vercel-ai-sdk/` | System prompt | Load in agent config |

## Quick Install

### Pi

Load `skills/pi/SKILL.md` as a Pi skill or paste it into project instructions. When Pi's MAINFRAME integration is installed, prefer the tool layer for discovery and guarded execution:

```text
Run mainframe_status(validate=true), then use mainframe_search/mainframe_help before choosing functions. Use mainframe_exec for one explicit function at a time and mainframe_awm for durable task memory.
```

### Claude Code

```bash
# Symlink the skill (one-time setup)
ln -s ~/.mainframe/skills/claude-code ~/.claude/skills/mainframe-bash
```

The skill auto-activates when Claude Code detects bash scripting tasks.

### OpenAI Codex / Codex CLI

```bash
# Project-level instruction file
cp ~/.mainframe/skills/codex/AGENTS.md ./AGENTS.md
# Or merge it into an existing AGENTS.md
```

### Clawdbot

Edit `~/.clawdbot/clawdbot.json` and add the preamble:

```json
{
  "agents": {
    "defaults": {
      "preamble": "When writing bash scripts, ALWAYS source MAINFRAME first:\n\nsource \"${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh\"\n\nMAINFRAME provides 3,821+ pure bash functions across 152 libraries. Use these instead of jq/sed/awk. Includes Agent Working Memory (AWM) for persistent state. Full reference: ~/.mainframe/CHEATSHEET.md"
    }
  }
}
```

For Docker sandboxed sessions, mount MAINFRAME in the container. See `clawdbot/README.md` for details.

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

Point your AI at the project's `CLAUDE.md` file or [docs/AI_CLI_INTEGRATIONS.md](../docs/AI_CLI_INTEGRATIONS.md), which contain MAINFRAME setup, function lookup, safety, and usage patterns.

## What Each Skill Does

Each skill file teaches the AI:

1. **How to source MAINFRAME** - The one-liner that loads everything
2. **Function categories** - JSON, strings, arrays, validation, crypto, git, AWM, agent IPC, etc.
3. **Replacement table** - Which MAINFRAME function replaces which external tool
4. **Common patterns** - Script templates, error handling, JSON generation, agent coordination
5. **Rules** - When to use MAINFRAME vs. external tools

## Current Highlights

- **3,821+ functions** across 152 libraries
- **6,500+ tests** with comprehensive coverage
- **Agent Working Memory (AWM)** - Persistent external memory for AI agents with finite context
- **Multi-Agent IPC** - File-based inter-process communication for agent coordination
- **bURL** - AI-native HTTP client with structured responses
- **Bun Integration** - TypeScript runtime helpers

## Creating Skills for Other Platforms

If your AI coding assistant supports custom instructions, create a file that includes:

```
When writing bash scripts, source MAINFRAME first:
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

Use MAINFRAME's 3,821+ functions instead of jq, sed, awk, cat.
Full reference: ~/.mainframe/CHEATSHEET.md
```

Pull requests welcome for additional platform support.

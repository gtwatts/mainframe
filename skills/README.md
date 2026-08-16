# MAINFRAME Skills for AI Coding Assistants

Pre-built instruction files that teach AI coding assistants how to use MAINFRAME's generated Bash function registry.

## Supported Platforms

| Platform | Directory | Format | Install |
|----------|-----------|--------|---------|
| Pi | `pi/` plus root `package.json` | Native package + SKILL.md | Human terminal: `mainframe pi install --dry-run`, then `mainframe pi install --yes` |
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

Install the first-party package from the installed MAINFRAME root. The dry-run
reports legacy and project-local collisions without changing files:

```bash
mainframe pi status
mainframe pi install --dry-run
mainframe pi install --yes
```

Run `--yes` yourself from an external terminal; the package deliberately gives
Pi only status and dry-run lifecycle guidance. Then use `/reload` in Pi (or
restart it) and run `/mainframe doctor`. Prefer the tool layer for discovery
and guarded execution:

```text
Run mainframe_status(validate=true), then use mainframe_search/mainframe_help before choosing functions. Use mainframe_exec for one explicit function at a time and mainframe_awm for durable task memory. Non-stable-core execution requires an actual Pi confirmation.
```

If the first live doctor fails after migration and install printed
`restore_available=true`, use its exact `backup_id` with `mainframe pi restore
--backup-id ID --dry-run`, review it, then run the same command with `--yes`.
Restore refuses backup paths, recency aliases, unsupported backup shapes, and
post-install drift.

Before uninstalling MAINFRAME, detach its managed package source from your
terminal with `mainframe pi remove --dry-run`, then `mainframe pi remove --yes`.
Removal preserves unrelated Pi settings and migration backups.

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
      "preamble": "When writing bash scripts, ALWAYS source MAINFRAME first:\n\nsource \"${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh\"\n\nMAINFRAME provides a generated registry of Bash functions and libraries. Use these instead of jq/sed/awk. Includes Agent Working Memory (AWM) for persistent state. Full reference: ~/.mainframe/CHEATSHEET.md"
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

- **Generated function registry** - current inventory without copied static counts
- **Cross-platform Bats suite** - run the current suite for commit-specific evidence
- **Agent Working Memory (AWM)** - Persistent external memory for AI agents with finite context
- **Multi-Agent IPC** - File-based inter-process communication for agent coordination
- **bURL** - AI-native HTTP client with structured responses
- **Bun Integration** - TypeScript runtime helpers

## Creating Skills for Other Platforms

If your AI coding assistant supports custom instructions, create a file that includes:

```
When writing bash scripts, source MAINFRAME first:
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

Use an appropriate MAINFRAME function before reimplementing a shell helper or spawning an external process.
Full reference: ~/.mainframe/CHEATSHEET.md
```

Pull requests welcome for additional platform support.

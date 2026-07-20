# MAINFRAME for AI CLI and Coding Agents

MAINFRAME is a bash runtime and function library for AI tools that control computers through shell commands. This guide explains how to make MAINFRAME visible to Claude Code, OpenAI Codex, Pi, Cursor, Aider, OpenCode, Kimi, Google AI CLI, and custom agent software.

Current registry stats from `FUNCTIONS.json`: **3,821+ public functions** across **152 libraries**.

---

## Universal setup

Install MAINFRAME once per machine:

```bash
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe
~/.mainframe/install.sh
```

Or use the one-line installer:

```bash
curl -fsSL https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh | bash
```

Then make it easy for agents and shells to discover:

```bash
export MAINFRAME_ROOT="$HOME/.mainframe"
export PATH="$MAINFRAME_ROOT/bin:$PATH"
```

Verify:

```bash
mainframe doctor
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" && uuid
```

Every generated bash script should start with:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Platform support matrix

| Tool / platform | Project artifact | Recommended install / instruction path |
|---|---|---|
| **Pi** | `skills/pi/SKILL.md` | Load as a Pi skill or paste into project instructions; use Pi's MAINFRAME tools when available. |
| **Claude Code** | `skills/claude-code/SKILL.md`, `CLAUDE.md` | Symlink `~/.mainframe/skills/claude-code` into `~/.claude/skills/mainframe-bash`; keep `CLAUDE.md` in repositories. |
| **OpenAI Codex / Codex CLI** | `skills/codex/AGENTS.md` | Copy or symlink to project `AGENTS.md`, or include in global Codex instructions. |
| **Cursor** | `skills/cursor/mainframe.mdc` | Copy to `.cursor/rules/mainframe.mdc`. |
| **Aider** | `skills/aider/CONVENTIONS.md` and `.aider.conf.yml` | Add `read: ~/.mainframe/skills/aider/CONVENTIONS.md` to Aider config. |
| **OpenCode** | `skills/opencode/SKILL.md` | Load as OpenCode custom/project instructions. |
| **Kimi CLI** | `skills/kimi-cli/SKILL.md` | Load as Kimi CLI project/system instructions. |
| **Google AI CLI** | `skills/google-cli/SKILL.md` | Load as Google AI CLI project/system instructions. |
| **Clawdbot** | `skills/clawdbot/preamble.md` | Add to `~/.clawdbot/clawdbot.json` preamble. |
| **Vercel AI SDK / custom agents** | `skills/vercel-ai-sdk/system-prompt.md` | Read the file into the model/system prompt. |
| **Any CLI agent** | This guide | Add the generic instruction snippet below to its system/project prompt. |

---

## Pi integration

Pi can use MAINFRAME in two complementary ways:

1. **Tool-aware mode** through Pi integration tools, when installed in Pi:
   - `mainframe_status` verifies installation, registry stats, CLI path, and optional doctor/count checks.
   - `mainframe_search` discovers functions by name, category, library, or description.
   - `mainframe_help` returns exact registry details for one function.
   - `mainframe_exec` executes one explicitly named MAINFRAME function with bounded timeout and guardrails.
   - `mainframe_awm` manages Agent Working Memory sessions, checkpoints, discoveries, progress, handoffs, and summaries.
   - `mainframe_bash_safety_check` classifies shell commands before execution.

   These are Pi integration tools around MAINFRAME; they are not shell functions that exist inside `lib/common.sh`.

2. **Bash/source mode** for scripts and terminals:

   ```bash
   source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
   mainframe quickref json
   json_object "tool=pi" "runtime=mainframe"
   ```

Recommended Pi operator prompt:

```text
Use MAINFRAME for bash work. First run mainframe_status(validate=true). Prefer mainframe_search/mainframe_help before inventing function names. For direct execution, call mainframe_exec with one explicit function name and bounded timeout. Use mainframe_awm for durable task memory. For scripts, source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" at the top.
```

See `skills/pi/SKILL.md` for the reusable Pi skill text.

---

## Claude Code

Install the Claude skill:

```bash
mkdir -p ~/.claude/skills
ln -s ~/.mainframe/skills/claude-code ~/.claude/skills/mainframe-bash
```

For project-level instructions, keep or copy `CLAUDE.md` into the repository root. Minimum instruction:

````markdown
## Bash with MAINFRAME

When writing bash scripts, source MAINFRAME first:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

Use MAINFRAME functions for JSON, validation, path safety, arrays, strings, HTTP, git helpers, and Agent Working Memory. Prefer `mainframe quickref <topic>` or `FUNCTIONS.json` for exact signatures.
````

---

## OpenAI Codex / Codex CLI

Codex-style coding agents commonly use repository instruction files such as `AGENTS.md`. Install the MAINFRAME Codex instructions:

```bash
cp ~/.mainframe/skills/codex/AGENTS.md ./AGENTS.md
# or combine that file with your existing AGENTS.md
```

Minimum `AGENTS.md` section:

````markdown
## Bash with MAINFRAME

For bash scripts, source MAINFRAME first:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

Prefer MAINFRAME primitives over ad-hoc `jq`/`sed`/`awk` pipelines when writing portable agent scripts. Use AWM (`awm_init`, `awm_checkpoint`, `awm_discovery`, `awm_context_for`) for durable task memory.
````

See `skills/codex/AGENTS.md` for a fuller Codex-ready version.

---

## Cursor

```bash
mkdir -p .cursor/rules
cp ~/.mainframe/skills/cursor/mainframe.mdc .cursor/rules/mainframe.mdc
```

Cursor will include the rule when editing the project. For global usage, add the same rule to your global Cursor rules directory.

---

## Aider

Project-local setup:

```bash
cp ~/.mainframe/skills/aider/CONVENTIONS.md ./CONVENTIONS.md
printf 'read: CONVENTIONS.md\n' >> .aider.conf.yml
```

Global setup:

```bash
printf 'read: ~/.mainframe/skills/aider/CONVENTIONS.md\n' >> ~/.aider.conf.yml
```

---

## OpenCode, Kimi CLI, Google AI CLI, and other instruction-driven tools

Most CLI coding agents have a system prompt, project instructions file, or reusable skill/preamble field. Use the matching file when available:

```text
skills/opencode/SKILL.md
skills/kimi-cli/SKILL.md
skills/google-cli/SKILL.md
```

If the tool has no MAINFRAME-specific adapter yet, paste this generic instruction:

```text
When writing or reviewing bash, use MAINFRAME. Source it at the top of generated scripts with:
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

Prefer MAINFRAME functions for JSON, strings, arrays, validation, path safety, file operations, git helpers, retries, atomic writes, and Agent Working Memory. Check exact function names with `mainframe quickref <topic>` or `FUNCTIONS.json`. Do not perform destructive, external, financial, or account-changing actions without explicit human approval.
```

---

## Custom agents and SDKs

For agent frameworks that you control:

1. Include `skills/vercel-ai-sdk/system-prompt.md` or this guide in the agent's system prompt.
2. Mount or install MAINFRAME at `~/.mainframe` inside the agent runtime/container.
3. Expose `MAINFRAME_ROOT` and add `bin/` to `PATH`.
4. If the agent executes shell commands, add a safety gate before high-risk commands.
5. If the agent runs long tasks, initialize AWM and record checkpoints/discoveries.

Example TypeScript prompt loading:

```ts
import { readFileSync } from "node:fs";

const mainframePrompt = readFileSync(
  `${process.env.HOME}/.mainframe/skills/vercel-ai-sdk/system-prompt.md`,
  "utf8"
);
```

---

## Agent safety conventions

- Prefer read-only discovery commands before mutating commands.
- Prefer `atomic_write`, `diff_replace`, `ensure_dir`, validation functions, and dry-run flags for file work.
- Do not ask agents to parse fragile free-form output when MAINFRAME can emit JSON/structured output.
- Treat `bash` as powerful and risky: explicit approval is required for destructive, irreversible, external account-changing, spending, publishing, deployment, or email actions.
- In multi-agent workflows, use AWM for persistent state and handoffs instead of relying on conversation history inheritance.

---

## Smoke test for any agent

After adding instructions, ask the agent:

```text
Write a portable bash script that creates a UUID, validates an email argument, and prints JSON without jq.
```

A MAINFRAME-aware answer should include:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
validate_email "$email" || die 1 "Invalid email"
json_object "id=$(uuid)" "email=$email"
```

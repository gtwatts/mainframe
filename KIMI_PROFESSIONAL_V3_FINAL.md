# Kimi Professional V3 - The Ultimate Hybrid
## Synthesis of Kimi CLI + Claude Code + Gemini CLI

**Version**: 3.0 Final  
**Date**: 2026-02-05  
**Analysis**: Multi-Agent Investigation of 3 Major AI Coding CLIs

---

## Executive Summary

**Kimi Professional V3** represents the synthesis of the best features from three major AI coding CLIs:

| Source | Key Contribution |
|--------|-----------------|
| **Kimi CLI** | Open-core foundation, MCP/ACP protocols, Agent Flow, Dual-mode shell |
| **Claude Code** | Hook system, confidence scoring, 7-phase workflows, review agents |
| **Gemini CLI** | Policy engine, checkpointing, TOML commands, sandboxing, skills |

### V3 Differentiators
- **Only** AI CLI with Policy Engine + Hook System + Checkpointing
- **Only** AI CLI with Agent Flow + 7-Phase Workflows + Skills
- **Only** AI CLI with MCP + A2A + ACP protocols
- **Only** AI CLI with Dual-Mode Shell + Sandboxing

---

## Part 1: Architecture Synthesis

### 1.1 Four-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KIMI PROFESSIONAL V3                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  LAYER 1: PRESENTATION (UI/UX)                                      │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐│   │
│  │  │  Shell UI    │ │   Web UI     │ │  ACP Bridge  │ │  Print Mode  ││   │
│  │  │  (Ink/React) │ │  (Browser)   │ │   (IDE)      │ │  (Scripting) ││   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘│   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                      │                                       │
│  ┌───────────────────────────────────┼────────────────────────────────────┐│
│  │  LAYER 2: ORCHESTRATION           │                                    ││
│  │                                   │                                    ││
│  │  ┌──────────────┐  ┌──────────────┼──────────────┐  ┌──────────────┐  ││
│  │  │ Policy Engine│  │ Hook System  │  Checkpoint  │  │  KimiSoul    │  ││
│  │  │ (TOML Rules) │  │ (9 Events)   │  │  Manager   │  │ (Core Loop)  │  ││
│  │  └──────────────┘  └──────────────┘ └──────────────┘  └──────────────┘  ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ ││
│  │  │ LaborMarket  │  │  FlowRunner  │  │  A2A Client  │  │  MCP Manager │ ││
│  │  │(Subagents)   │  │(Mermaid/D2)  │  │(Remote Ags)  │  │(Ext. Tools)  │ ││
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ ││
│  └────────────────────────────────────────────────────────────────────────┘│
│                                      │                                      │
│  ┌───────────────────────────────────┼────────────────────────────────────┐│
│  │  LAYER 3: CAPABILITIES            │                                    ││
│  │                                   │                                    ││
│  │  ┌──────────────┐ ┌──────────────┐┌──────────────┐ ┌──────────────┐   ││
│  │  │ Built-in     │ │  Review      ││   Custom     │ │   Skills     │   ││
│  │  │ Tools (15+)  │ │  Agents (8)  ││  Commands    │ │  (Dynamic)   │   ││
│  │  └──────────────┘ └──────────────┘└──────────────┘ └──────────────┘   ││
│  │  ┌──────────────┐ ┌──────────────┐┌──────────────┐ ┌──────────────┐   ││
│  │  │ Git Suite    │ │   Sandbox    ││  Memory      │ │  Todos       │   ││
│  │  │ (Native)     │ │ (Multi-meth) ││  System      │ │  (Visual)    │   ││
│  │  └──────────────┘ └──────────────┘└──────────────┘ └──────────────┘   ││
│  └────────────────────────────────────────────────────────────────────────┘│
│                                      │                                      │
│  ┌───────────────────────────────────┼────────────────────────────────────┐│
│  │  LAYER 4: EXTENSIONS              │                                    ││
│  │                                   │                                    ││
│  │  ┌──────────────┐ ┌──────────────┐┌──────────────┐ ┌──────────────┐   ││
│  │  │   Plugins    │ │   Agents     ││   Skills     │ │   Hooks      │   ││
│  │  │  (Manifest)  │ │ (YAML/MD)    ││ (SKILL.md)   │ │  (JSON/TOML) │   ││
│  │  └──────────────┘ └──────────────┘└──────────────┘ └──────────────┘   ││
│  │  ┌──────────────┐ ┌──────────────┐┌──────────────┐                    ││
│  │  │ MCP Servers  │ │ A2A Servers  ││  Policies    │                    ││
│  │  │  (Config)    │ │  (Remote)    ││  (TOML)      │                    ││
│  │  └──────────────┘ └──────────────┘└──────────────┘                    ││
│  └────────────────────────────────────────────────────────────────────────┘│
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Configuration Hierarchy

```
Configuration Precedence (high to low):

┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. SESSION (Runtime flags, --model, --yolo)                                │
│    ├─ Command line arguments                                               │
│    └─ Environment variables                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. PROJECT (.kimi/settings.toml + .kimi/ directory)                        │
│    ├─ .kimi/settings.toml         # Project settings                       │
│    ├─ .kimi/commands/*.toml       # Project commands                       │
│    ├─ .kimi/agents/*.md           # Project subagents                      │
│    ├─ .kimi/skills/*/             # Project skills                         │
│    ├─ .kimi/policies/*.toml       # Project policies                       │
│    ├─ .kimi/hooks.json            # Project hooks                          │
│    └─ AGENTS.md                   # Project context (Kimi compat)          │
│    └─ GEMINI.md                   # Project context (Gemini compat)        │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. USER (~/.kimi/ directory)                                               │
│    ├─ ~/.kimi/settings.toml       # User preferences                       │
│    ├─ ~/.kimi/commands/*.toml     # Personal commands                      │
│    ├─ ~/.kimi/agents/*.md         # Personal agents                        │
│    ├─ ~/.kimi/skills/*/           # Personal skills                        │
│    ├─ ~/.kimi/policies/*.toml     # Personal policies                      │
│    └─ ~/.kimi/GEMINI.md           # User memories                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ 4. SYSTEM (/etc/kimi/ on Linux, admin policies)                            │
│    └─ System-wide policies (enterprise)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ 5. DEFAULTS (Built-in)                                                     │
│    └─ Factory defaults                                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: Unique V3 Features

### 2.1 Policy Engine (From Gemini CLI)

**TOML-Based Fine-Grained Control:**

```toml
# ~/.kimi/policies/my-rules.toml

# Allow git status without prompting
[[rule]]
toolName = "Shell"
commandPrefix = "git status"
decision = "allow"
priority = 100

# Ask for confirmation on git push
[[rule]]
toolName = "Shell"
commandPrefix = "git push"
decision = "ask_user"
priority = 200

# Block dangerous commands
[[rule]]
toolName = "Shell"
commandRegex = "rm.*-rf|dd.*if=|mkfs"
decision = "deny"
priority = 500
deny_message = "Destructive operations are blocked by policy"

# MCP server wildcard
[[rule]]
mcpName = "untrusted-server"
decision = "deny"
priority = 1000
```

**Priority Formula:**
```
final_priority = tier_base + (toml_priority / 1000)
├─ Admin Tier: 3.x (system-wide, root-owned)
├─ User Tier:  2.x (~/.kimi/policies/)
└─ Default:    1.x (built-in)
```

**Integration with Approval Modes:**
- `default` - Normal approval flow
- `auto_edit` - Allow edit operations without prompt
- `yolo` - Allow all (emergency only)

### 2.2 Checkpointing System (From Gemini CLI)

**Shadow Git Repository:**

```bash
# Automatic checkpoint on every file modification
~/.kimi/history/<project_hash>/  # Shadow git repo
├─ .git/                         # Git metadata
├─ <snapshots>/                  # File states
└─ metadata.json                 # Conversation state
```

**Commands:**
```bash
/rewind              # Interactive rewind (Esc+Esc shortcut)
/restore             # List and restore checkpoints
/restore <name>      # Restore specific checkpoint
```

**Rewind Options:**
- Rewind conversation + revert files
- Rewind conversation only
- Revert files only

### 2.3 Custom Commands (From Gemini CLI)

**TOML Command Definition:**

```toml
# .kimi/commands/git/commit.toml
name = "commit"
description = "Generate conventional commit message from staged changes"

prompt = """
Generate a Conventional Commit message for these changes:

```diff
!{git diff --staged}
```

Follow the format: <type>(<scope>): <description>
Types: feat, fix, docs, style, refactor, test, chore
"""
```

**Advanced Features:**
```toml
# .kimi/commands/review.toml
name = "review"
description = "Review code with best practices"

prompt = """
Review {{args}} using our best practices:

@{docs/best-practices.md}

Focus on:
1. Security vulnerabilities
2. Performance issues  
3. Code clarity
"""
```

**Syntax:**
- `{{args}}` - Argument injection (auto-escaped in shell contexts)
- `!{command}` - Shell command execution with confirmation
- `@{path}` - File/directory injection (respects .gitignore)

### 2.4 Hook System (From Claude Code)

**Event Types:**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "name": "load-context",
        "type": "prompt",
        "prompt": "Read AGENTS.md and summarize project conventions"
      }
    ],
    "PreToolUse": [
      {
        "name": "security-check",
        "matcher": "Shell(rm|dd|mkfs)",
        "type": "command",
        "command": "${KIMI_PLUGIN_ROOT}/hooks/security-check.py"
      }
    ],
    "Stop": [
      {
        "name": "require-tests",
        "enabled": false,
        "action": "block",
        "condition": "transcript not contains 'pytest|npm test'"
      }
    ]
  }
}
```

**Rule-Based Hooks (Hookify-Style):**

```markdown
---
name: block-dangerous-rm
enabled: true
event: Shell
pattern: rm\s+-rf
action: block
---

🛑 **Destructive Operation Detected!**

This command could delete important files. Operation blocked.
```

### 2.5 Subagent Framework (Synthesis)

**Definition Format:**

```markdown
---
name: security-auditor
description: |
  Specialized security vulnerability detection.
  Use when: "Check for security issues", "Audit authentication"
kind: local
tools:
  - ReadFile
  - Grep
  - Shell
model: kimi-pro
temperature: 0.2
max_turns: 15
color: red
---

You are a ruthless Security Auditor. Focus on:
1. SQL Injection
2. XSS vulnerabilities
3. Hardcoded credentials
4. Unsafe file operations

Report findings with confidence scores (0-100).
```

**Remote Agents (A2A Protocol):**

```markdown
---
kind: remote
name: github-assistant
agent_card_url: https://github.com/agents/card
---
```

**Management Commands:**
```bash
/agents list              # Show all agents
/agents enable <name>     # Enable agent
/agents disable <name>    # Disable agent
/agents refresh           # Reload agent definitions
```

### 2.6 Memory System (From Gemini CLI)

**Hierarchical Context Loading:**

```
AGENTS.md / GEMINI.md
├── @./shared/conventions.md
├── @./shared/architecture.md
└── @../company-standards.md
```

**Save Memory Tool:**
```python
# Persist facts across sessions
save_memory(fact="User prefers Python over TypeScript")
# Appends to ~/.kimi/GEMINI.md
```

**Memory Structure:**
```markdown
# ~/.kimi/GEMINI.md

## User Preferences

### Kimi Added Memories
- User prefers Python over TypeScript
- User likes detailed explanations with code examples
- User's preferred testing framework is pytest
```

---

## Part 3: Professional Tool Suite

### 3.1 Git Tool Suite (Enhanced)

| Command | Description |
|---------|-------------|
| `/commit` | AI-generated commit message from staged changes |
| `/commit-push-pr` | Full workflow: branch → commit → push → PR |
| `/clean_gone` | Remove branches deleted on remote |
| `/pr-status` | Show PR status in prompt footer |
| `/code-review` | Automated PR review with GitHub comments |

**Native Git Tool:**
```python
class Git(Tool):
    # Operations with intelligent analysis
    - status(): Enhanced with AI summary
    - diff(): Change categorization
    - commit(): Conventional commit generation
    - blame(): Line attribution with context
    - log(): Semantic search
    - branch(): Conflict prediction
```

### 3.2 Review Agents (From Claude Code)

| Agent | Focus | Output |
|-------|-------|--------|
| `code-reviewer` | General quality, standards | Confidence 0-100 |
| `silent-failure-hunter` | Error handling gaps | Severity rating |
| `pr-test-analyzer` | Behavioral coverage | Gap score 1-10 |
| `comment-analyzer` | Comment accuracy | Accuracy check |
| `type-design-analyzer` | Type system design | 4× ratings 1-10 |
| `code-simplifier` | Post-implementation polish | Complexity score |
| `security-auditor` | Vulnerability scanning | CVSS scoring |
| `performance-analyzer` | Bottleneck detection | Impact rating |

**Confidence Scoring:**
```
0-25  → False positive (filtered)
26-50 → Minor nitpick (filtered)
51-75 → Valid, low-impact (filtered by default)
76-90 → Important (reported)
91-100→ Critical (reported immediately)
```

### 3.3 Sandboxing (From Gemini CLI)

**Multi-Method Support:**

```bash
# macOS Seatbelt (native)
gemini -s --seatbelt-profile=permissive-open

# Docker/Podman
gemini -s --sandbox=docker

# Configuration
{
  "tools": {
    "sandbox": "docker",
    "sandboxProfile": "permissive-open"
  }
}
```

**Profiles:**
- `permissive-open` - Write restrictions, network allowed (default)
- `permissive-closed` - Write restrictions, no network
- `restrictive-open` - Strict restrictions, network allowed
- `restrictive-closed` - Maximum restrictions

### 3.4 7-Phase Workflow (From Claude Code)

```
/feature-dev "Add user authentication"

Phase 1: Discovery
├── Clarify requirements
└── Create todo list

Phase 2: Codebase Exploration
├── Launch 2-3 code-explorer agents
├── Each explores different aspects
└── Aggregate key files

Phase 3: Clarifying Questions
├── Present organized questions
├── Cover edge cases, error handling
└── WAIT FOR USER ANSWERS

Phase 4: Architecture Design
├── Launch 2-3 code-architect agents
├── Different approaches presented
└── Get user approval

Phase 5: Implementation
├── Follow chosen architecture
└── Update todos as progress

Phase 6: Quality Review
├── Launch 3 code-reviewer agents
├── Consolidate by severity
└── Present disposition options

Phase 7: Summary
├── Mark todos complete
├── Document decisions
└── Suggest next steps
```

---

## Part 4: Feature Comparison Matrix

### 4.1 Core Features

| Feature | Kimi CLI | Claude Code | Gemini CLI | **Kimi Pro V3** |
|---------|----------|-------------|------------|-----------------|
| **Open Source** | ✅ | ❌ | ✅ | ✅ Core |
| **MCP Support** | ✅ | ✅ | ✅ | ✅ Enhanced |
| **ACP Support** | ✅ | ❌ | ❌ | ✅ |
| **A2A Support** | ❌ | ❌ | ✅ | ✅ |
| **Dual-Mode Shell** | ✅ | ❌ | ❌ | ✅ |
| **Agent Flow** | ✅ | ❌ | ❌ | ✅ |

### 4.2 Security & Control

| Feature | Kimi CLI | Claude Code | Gemini CLI | **Kimi Pro V3** |
|---------|----------|-------------|------------|-----------------|
| **Policy Engine** | ❌ | ❌ | ✅ TOML | ✅ TOML |
| **Hook System** | ❌ | ✅ | ❌ | ✅ Full |
| **Checkpointing** | ❌ | ⚠️ Basic | ✅ Git | ✅ Git |
| **Sandboxing** | ❌ | ❌ | ✅ Multi | ✅ Multi |
| **Approval Modes** | ✅ YOLO | ✅ Modes | ✅ Modes | ✅ All |

### 4.3 Developer Experience

| Feature | Kimi CLI | Claude Code | Gemini CLI | **Kimi Pro V3** |
|---------|----------|-------------|------------|-----------------|
| **Git Commands** | ❌ Shell | ⚠️ Plugins | ⚠️ Basic | ✅ Native |
| **Review Agents** | ❌ | ✅ 6 | ❌ | ✅ 8+ |
| **Custom Commands** | ❌ | ⚠️ Limited | ✅ TOML | ✅ TOML |
| **Subagents** | ⚠️ Basic | ✅ | ✅ YAML | ✅ Full |
| **Confidence Scoring** | ❌ | ✅ | ❌ | ✅ |
| **7-Phase Workflow** | ❌ | ✅ | ❌ | ✅ |

### 4.4 Context & Memory

| Feature | Kimi CLI | Claude Code | Gemini CLI | **Kimi Pro V3** |
|---------|----------|-------------|------------|-----------------|
| **Modular Context** | ❌ | ⚠️ `/memory` | ✅ @import | ✅ @import |
| **Cross-Session Memory** | ❌ | ❌ | ✅ save_memory | ✅ |
| **Skills System** | ✅ | ⚠️ Basic | ✅ | ✅ Unified |
| **Hierarchical Settings** | ⚠️ Basic | ⚠️ Basic | ✅ | ✅ |

---

## Part 5: Implementation Roadmap

### Phase 1: Foundation (Months 1-2)

**Core Infrastructure:**
- [ ] Unified extension system (plugins/agents/skills/hooks)
- [ ] Hierarchical settings (User/Project/System)
- [ ] Policy engine (TOML-based, 3-tier)
- [ ] Checkpointing system (shadow git)

**Git Foundation:**
- [ ] Native Git Tool
- [ ] `/commit` command
- [ ] `/commit-push-pr` command

### Phase 2: Developer Workflow (Months 3-4)

**Review System:**
- [ ] code-reviewer agent with confidence scoring
- [ ] silent-failure-hunter agent
- [ ] `/code-review` command

**Feature Development:**
- [ ] code-explorer agent
- [ ] code-architect agent
- [ ] `/feature-dev` 7-phase workflow

**Custom Commands:**
- [ ] TOML command system
- [ ] `{{args}}`, `!{shell}`, `@{file}` syntax

### Phase 3: Advanced Features (Months 5-6)

**Quality Assurance:**
- [ ] pr-test-analyzer agent
- [ ] comment-analyzer agent
- [ ] type-design-analyzer agent
- [ ] security-auditor agent

**Memory & Context:**
- [ ] Memory import processor (`@file`)
- [ ] save_memory tool
- [ ] Skills auto-activation

### Phase 4: Enterprise & Ecosystem (Months 7-8)

**Enterprise:**
- [ ] Admin policies (system-wide)
- [ ] Audit logging
- [ ] SAML/SSO integration

**Ecosystem:**
- [ ] A2A protocol support
- [ ] Plugin marketplace
- [ ] VS Code extension

---

## Part 6: Configuration Reference

### 6.1 Settings File

```toml
# ~/.kimi/settings.toml or .kimi/settings.toml

[general]
default_model = "kimi-pro"
auto_compact_threshold = 0.85
spinner_verbs = ["Thinking", "Analyzing", "Cooking"]
approval_mode = "default"  # default | auto_edit | yolo

[git]
commit_style = "conventional"  # conventional | simple | detailed
auto_signoff = false

[review]
confidence_threshold = 80
auto_comment = false

[tools]
sandbox = "docker"  # docker | podman | seatbelt | none
sandbox_profile = "permissive-open"

[checkpointing]
enabled = true

[experimental]
enableAgents = true
enableA2A = false

[memory]
max_import_depth = 5
```

### 6.2 Project Structure

```
project/
├── .kimi/
│   ├── settings.toml
│   ├── commands/
│   │   ├── git/
│   │   │   └── commit.toml
│   │   └── review.toml
│   ├── agents/
│   │   └── security-auditor.md
│   ├── skills/
│   │   └── frontend/
│   │       └── SKILL.md
│   ├── policies/
│   │   └── project-rules.toml
│   └── hooks.json
├── AGENTS.md              # Kimi compatibility
├── GEMINI.md              # Gemini compatibility
└── src/
```

---

## Part 7: Migration Guide

### From Kimi CLI
1. **Settings**: `~/.kimi/config.toml` → `~/.kimi/settings.toml`
2. **Skills**: Convert to new plugin format
3. **Commands**: Most slash commands remain compatible
4. **Sessions**: Automatic migration

### From Claude Code
1. **Plugins**: Convert `.claude-plugin/` to `.kimi-plugin/`
2. **Hooks**: Claude hooks.json → Kimi hooks.json (compatible)
3. **Commands**: Convert frontmatter commands to TOML
4. **CLAUDE.md**: Fully supported

### From Gemini CLI
1. **Settings**: `settings.json` → `settings.toml`
2. **Commands**: TOML format identical
3. **Agents**: YAML frontmatter identical
4. **GEMINI.md**: Fully supported with `@import`

---

## Appendix: Complete Command Reference

### Built-in Commands
```
/help, /model, /clear, /compact
/context, /usage, /sessions
/commit, /commit-push-pr, /clean_gone, /pr-status
/code-review, /feature-dev
/rewind, /restore, /checkpoint
/agents, /skills, /commands
/skill:*, /flow:*
```

### Tool Inventory (15+)
```
Shell, ReadFile, WriteFile, StrReplaceFile
Grep, Glob, ReadMediaFile
SearchWeb, FetchURL
Git (native)
Task, CreateSubagent, SetTodoList
Think, save_memory, write_todos
```

---

**Document End**

*Kimi Professional V3: The synthesis of open-core philosophy, sophisticated agent orchestration, and developer-first UX.*

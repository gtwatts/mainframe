# Kimi Professional V4 - The Ultimate Synthesis
## Best of Kimi CLI + Claude Code + Gemini CLI + OpenAI Codex

**Version**: 4.0 Ultimate  
**Date**: 2026-02-05  
**Analysis**: 4 Major AI Coding CLIs Analyzed via Multi-Agent Swarm

---

## Executive Summary

**Kimi Professional V4** is the ultimate synthesis of the best features from all four major AI coding CLIs:

| Source | Key Contribution |
|--------|-----------------|
| **Kimi CLI** | Open-core foundation, MCP/ACP/Agent Flow, Dual-mode shell, Subagent architecture |
| **Claude Code** | Hook system, confidence scoring, 7-phase workflows, review agents |
| **Gemini CLI** | Policy engine (TOML), checkpointing, TOML commands, `@import`, sandboxing |
| **OpenAI Codex** | Patch-based editing, multi-provider (10+), hierarchical AGENTS.md, Rust core |

### V4 Ultimate Differentiators
- **Only** AI CLI with **Policy Engine + Hook System + Checkpointing + Patch-based Editing**
- **Only** AI CLI with **MCP + A2A + ACP + Multi-Provider** (10+ LLM backends)
- **Only** AI CLI with **Agent Flow + 7-Phase Workflows + Skills + Subagents**
- **Only** AI CLI with **Dual-Mode Shell + Sandboxing + Stream Chunking**

---

## Part 1: The Ultimate Architecture

### 1.1 Five-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      KIMI PROFESSIONAL V4 - ULTIMATE                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  LAYER 1: PRESENTATION (Multi-Frontend)                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │  TUI (Ratatui│ │   Web UI     │ │  ACP Bridge  │ │  Headless    │           │
│  │  /Ink)       │ │  (Browser)   │ │   (IDE)      │ │  (CI/Script) │           │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘           │
│  ┌──────────────┐ ┌──────────────┐                                              │
│  │ Stream       │ │ Notifications│                                              │
│  │ Chunking     │ │ (OSC9/Bell)  │                                              │
│  └──────────────┘ └──────────────┘                                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  LAYER 2: ORCHESTRATION (The Brain)                                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ Policy Engine│ │ Hook System  │ │ Checkpoint   │ │ KimiSoul     │           │
│  │ (TOML 3-Tier)│ │ (10+ Events) │ │  Manager     │ │ (Core Loop)  │           │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘           │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ LaborMarket  │ │ FlowRunner   │ │ A2A Client   │ │ MCP Manager  │           │
│  │ (Subagents)  │ │ (Mermaid/D2) │ │(Remote Ags)  │ │(Ext. Tools)  │           │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  LAYER 3: TOOLS & AGENTS (Capabilities)                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ apply_patch  │ │ Shell        │ │ Git          │ │ Web Search   │           │
│  │ (Unified     │ │ (Sandboxed)  │ │ (Native)     │ │ & Fetch      │           │
│  │  Diff)       │ │              │ │              │ │              │           │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘           │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ 8+ Review    │ │ update_plan  │ │ File Ops     │ │ save_memory  │           │
│  │ Agents       │ │ (Progress)   │ │ (Read/Write) │ │ (Cross-Sess) │           │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  LAYER 4: EXTENSIONS (Ecosystem)                                                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ Plugins      │ │ Agents       │ │ Skills       │ │ Commands     │           │
│  │ (Manifest)   │ │ (YAML/MD)    │ │ (SKILL.md)   │ │ (TOML)       │           │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘           │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │ MCP Servers  │ │ A2A Servers  │ │ Policies     │ │ Hooks        │           │
│  │ (10+ types)  │ │ (Remote)     │ │ (TOML)       │ │ (JSON/TOML)  │           │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  LAYER 5: PROVIDERS (LLM Backends)                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ Kimi     │ │ OpenAI   │ │ Azure    │ │ Anthropic│ │ Gemini   │              │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ Ollama   │ │ Mistral  │ │ DeepSeek │ │ xAI      │ │ Groq     │              │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘              │
│  ┌──────────┐ ┌──────────┐                                                       │
│  │ OpenRouter│ │ ArceeAI  │                                                       │
│  └──────────┘ └──────────┘                                                       │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Configuration Hierarchy (Ultimate)

```
Precedence (high to low):

┌─────────────────────────────────────────────────────────────────────────────────┐
│ 1. SESSION (Runtime)                                                            │
│    ├─ CLI flags: --model, --approval-mode, --yolo                              │
│    ├─ Environment: KIMI_API_KEY, OPENAI_API_KEY, etc.                          │
│    └─ Temp overrides                                                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 2. PROJECT (.kimi/ + AGENTS.md/GEMINI.md)                                      │
│    ├─ .kimi/settings.toml         # Project settings                           │
│    ├─ .kimi/commands/*.toml       # Project commands                           │
│    ├─ .kimi/agents/*.md           # Project subagents                          │
│    ├─ .kimi/skills/*/             # Project skills                             │
│    ├─ .kimi/policies/*.toml       # Project policies                           │
│    ├─ AGENTS.md                   # Kimi context (hierarchical)                │
│    └─ GEMINI.md                   # Gemini context (@import support)           │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 3. USER (~/.kimi/)                                                              │
│    ├─ ~/.kimi/settings.toml       # User preferences                           │
│    ├─ ~/.kimi/commands/*.toml     # Personal commands                          │
│    ├─ ~/.kimi/agents/*.md         # Personal agents                            │
│    ├─ ~/.kimi/GEMINI.md           # User memories                              │
│    └─ ~/.kimi/config.json/toml    # Provider configs                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 4. SYSTEM (/etc/kimi/ on Linux, admin policies)                                │
│    └─ System-wide policies (enterprise)                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 5. DEFAULTS (Built-in)                                                          │
│    └─ Factory defaults + built-in providers                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: V4 Ultimate Exclusive Features

### 2.1 apply_patch Tool (From Codex)

**Why Patch-Based Editing?**

| Concern | Solution |
|---------|----------|
| Reviewability | Patches are human-readable before application |
| Atomicity | Multi-file changes are all-or-nothing |
| Sandbox compatibility | Patch application runs inside sandbox |
| Undo capability | Patches can be reversed |
| Conflict detection | Context lines enable fuzzy matching |

**Patch Format:**
```
*** Begin Patch
*** Add File: src/utils.py
+def helper():
+    return "Hello"
*** Update File: src/app.py
@@ def main():
-    print("Hi")
+    print("Hello!")
*** Delete File: obsolete.txt
*** End Patch
```

**Usage:**
```python
# Tool call
apply_patch(patch="""
*** Begin Patch
*** Update File: config.yaml
@@ port: 8080
-  debug: true
+  debug: false
*** End Patch
""")
```

### 2.2 Multi-Provider Architecture (From Codex)

**10+ Provider Support:**

```toml
# ~/.kimi/config.toml
[providers.openai]
name = "OpenAI"
base_url = "https://api.openai.com/v1"
env_key = "OPENAI_API_KEY"

[providers.gemini]
name = "Google Gemini"
base_url = "https://generativelanguage.googleapis.com/v1beta"
env_key = "GEMINI_API_KEY"

[providers.ollama]
name = "Ollama"
base_url = "http://localhost:11434/v1"
env_key = "OLLAMA_API_KEY"

[providers.kimi]
name = "Kimi"
base_url = "https://api.moonshot.cn/v1"
env_key = "KIMI_API_KEY"

# Also supported: Azure, OpenRouter, Mistral, DeepSeek, xAI, Groq, ArceeAI
```

**CLI Usage:**
```bash
kimi --provider kimi --model kimi-pro
kimi --provider ollama --model codellama
kimi --provider openai --model gpt-4.1
```

### 2.3 Hierarchical AGENTS.md (From Codex + Gemini)

**Scope & Precedence:**
```
Repo Root AGENTS.md
├── Subfolder AGENTS.md (overrides parent for that subtree)
├── CWD AGENTS.md (highest precedence for current work)
└── User ~/.kimi/AGENTS.md (personal preferences)
```

**Import Support (Gemini-style):**
```markdown
# AGENTS.md
@./shared/conventions.md
@./shared/testing-standards.md

## Project Specific
- Use Python 3.11+
- Prefer pytest for testing
```

### 2.4 Stream Chunking (From Codex)

**Two-Gear System:**

| Mode | Behavior | Trigger |
|------|----------|---------|
| **Smooth** | One line per ~8.3ms tick | Normal load |
| **CatchUp** | Batch-drain entire backlog | `queued_lines >= 8` OR `oldest_age >= 120ms` |

**Hysteresis:**
- Enter CatchUp: Queue depth or age exceeds thresholds
- Exit CatchUp: Stay below BOTH thresholds for 250ms hold
- Prevents mode flapping

### 2.5 Double-Press Exit (From Codex)

**Exit Flow:**
```
Ctrl+C (first press)
    ↓
Show hint: "ctrl + c again to quit" (1-second window)
    ↓
If work active: Submit Interrupt
    ↓
Ctrl+C (second press within 1s)
    ↓
Graceful shutdown-first exit
```

**Modal-Aware:** Active popups consume Ctrl+C first (dismiss, don't quit)

---

## Part 3: Feature Comparison Matrix

### 3.1 Core Capabilities

| Feature | Kimi | Claude | Gemini | Codex | **V4 Ultimate** |
|---------|------|--------|--------|-------|-----------------|
| **Open Source** | ✅ | ❌ | ✅ | ✅ | ✅ Core |
| **MCP Support** | ✅ | ✅ | ✅ | ✅ | ✅ Enhanced |
| **ACP Support** | ✅ | ❌ | ❌ | ❌ | ✅ |
| **A2A Support** | ❌ | ❌ | ✅ | ❌ | ✅ |
| **Multi-Provider** | ⚠️ | ❌ | ❌ | ✅ 10+ | ✅ 10+ |
| **Dual-Mode Shell** | ✅ | ❌ | ❌ | ❌ | ✅ |
| **Agent Flow** | ✅ | ❌ | ❌ | ❌ | ✅ |

### 3.2 Security & Control

| Feature | Kimi | Claude | Gemini | Codex | **V4 Ultimate** |
|---------|------|--------|--------|-------|-----------------|
| **Policy Engine** | ❌ | ❌ | ✅ TOML | ⚠️ | ✅ TOML |
| **Hook System** | ❌ | ✅ | ❌ | ❌ | ✅ Full |
| **Checkpointing** | ❌ | ⚠️ | ✅ Git | ⚠️ Ghost | ✅ Git |
| **Sandboxing** | ❌ | ❌ | ✅ | ✅ | ✅ Multi |
| **Patch-based Edit** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **ZDR Support** | ❌ | ❌ | ❌ | ✅ | ✅ |

### 3.3 Developer Experience

| Feature | Kimi | Claude | Gemini | Codex | **V4 Ultimate** |
|---------|------|--------|--------|-------|-----------------|
| **Git Commands** | ❌ Shell | ✅ | ⚠️ Basic | ❌ | ✅ Native |
| **Review Agents** | ❌ | ✅ 6 | ❌ | ❌ | ✅ 8+ |
| **Custom Commands** | ❌ | ⚠️ | ✅ TOML | ⚠️ | ✅ TOML |
| **Subagents** | ⚠️ Basic | ✅ | ✅ | ❌ | ✅ Full |
| **Confidence Scoring** | ❌ | ✅ | ❌ | ❌ | ✅ |
| **7-Phase Workflow** | ❌ | ✅ | ❌ | ❌ | ✅ |
| **Stream Chunking** | ❌ | ❌ | ❌ | ✅ | ✅ |

### 3.4 Context & Memory

| Feature | Kimi | Claude | Gemini | Codex | **V4 Ultimate** |
|---------|------|--------|--------|-------|-----------------|
| **Hierarchical Context** | ❌ | ⚠️ | ✅ @import | ✅ AGENTS.md | ✅ Both |
| **Cross-Session Memory** | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Skills System** | ✅ | ⚠️ | ✅ | ✅ | ✅ Unified |
| **Hierarchical Settings** | ⚠️ | ⚠️ | ✅ | ✅ | ✅ |

---

## Part 4: Complete Tool Suite

### 4.1 Core Tools (15+)

```python
# File Operations
ReadFile, WriteFile, StrReplaceFile  # Traditional
apply_patch                           # Patch-based (NEW)
Glob, Grep, ReadMediaFile

# Shell & Execution
Shell (sandboxed)                     # With Seatbell/Docker/Landlock

# Web & Search
SearchWeb, FetchURL

# Git (NEW - Native)
Git.status(), Git.diff(), Git.commit()
Git.log(), Git.blame(), Git.branch()

# Planning & Tracking
update_plan                           # Progress tracking
SetTodoList, save_memory              # Cross-session memory

# Agent Management
Task, CreateSubagent                  # Subagent spawning
```

### 4.2 Review Agents (8+)

| Agent | Focus | From |
|-------|-------|------|
| `code-reviewer` | General quality, standards | Claude |
| `silent-failure-hunter` | Error handling gaps | Claude |
| `pr-test-analyzer` | Behavioral coverage | Claude |
| `comment-analyzer` | Comment accuracy | Claude |
| `type-design-analyzer` | Type system design | Claude |
| `code-simplifier` | Post-implementation polish | Claude |
| `security-auditor` | Vulnerability scanning | Kimi |
| `performance-analyzer` | Bottleneck detection | Kimi |

### 4.3 Commands (25+)

```bash
# Core
/help, /model, /clear, /compact, /context, /usage, /sessions

# Git Workflow (NEW)
/commit, /commit-push-pr, /clean_gone, /pr-status, /code-review

# State Management (NEW)
/rewind, /restore, /checkpoint
/agents list/enable/disable/refresh

# Feature Development
/feature-dev                        # 7-phase workflow
/plan, /review

# Navigation
/skill:*, /flow:*

# Exit
/quit, /exit, /logout, /new
```

---

## Part 5: Implementation Roadmap

### Phase 1: Foundation (Months 1-2)

**Core Infrastructure:**
- [ ] Unified extension system (plugins/agents/skills/hooks/policies)
- [ ] Hierarchical settings (Session/Project/User/System)
- [ ] Policy engine (TOML-based, 3-tier)
- [ ] Multi-provider abstraction (10+ providers)

**Git & Patch:**
- [ ] Native Git Tool
- [ ] `apply_patch` tool (unified diff format)
- [ ] `/commit`, `/commit-push-pr` commands

### Phase 2: Developer Experience (Months 3-4)

**Review & Workflow:**
- [ ] 8 review agents with confidence scoring
- [ ] `/code-review` command
- [ ] `/feature-dev` 7-phase workflow
- [ ] `update_plan` tool

**UX Improvements:**
- [ ] Stream chunking (Smooth/CatchUp modes)
- [ ] Double-press exit (Ctrl+C)
- [ ] Preamble message standards

### Phase 3: Advanced Features (Months 5-6)

**Context & Memory:**
- [ ] Checkpointing system (shadow git)
- [ ] Hierarchical AGENTS.md with @import
- [ ] `save_memory` tool
- [ ] Skills auto-activation

**TOML Commands:**
- [ ] Custom command system
- [ ] `{{args}}`, `!{shell}`, `@{file}` syntax

### Phase 4: Enterprise & Ecosystem (Months 7-8)

**Enterprise:**
- [ ] Admin policies (system-wide)
- [ ] SAML/SSO integration
- [ ] Audit logging
- [ ] ZDR (Zero Data Retention) support

**Ecosystem:**
- [ ] A2A protocol support
- [ ] MCP server marketplace
- [ ] Plugin distribution

---

## Part 6: Configuration Reference

### 6.1 Ultimate Settings File

```toml
# ~/.kimi/settings.toml or .kimi/settings.toml

[general]
default_model = "kimi-pro"
default_provider = "kimi"
approval_mode = "suggest"  # suggest | auto-edit | full-auto
auto_compact_threshold = 0.85
spinner_verbs = ["Thinking", "Analyzing", "Cooking"]
stream_chunking = true

[ui]
double_press_exit = true
notifications = true
show_preambles = true

[git]
commit_style = "conventional"  # conventional | simple | detailed
auto_signoff = false
ghost_commits = true

[review]
confidence_threshold = 80
auto_comment = false

[providers.kimi]
name = "Kimi"
base_url = "https://api.moonshot.cn/v1"
env_key = "KIMI_API_KEY"

[providers.openai]
name = "OpenAI"
base_url = "https://api.openai.com/v1"
env_key = "OPENAI_API_KEY"

[providers.gemini]
name = "Gemini"
base_url = "https://generativelanguage.googleapis.com/v1beta"
env_key = "GEMINI_API_KEY"

[sandbox]
enabled = true
method = "auto"  # auto | seatbelt | docker | landlock | none
profile = "permissive-open"
network_in_full_auto = false

[checkpointing]
enabled = true
shadow_repo_path = "~/.kimi/history/"

[memory]
max_import_depth = 5
auto_save_facts = true

[experimental]
enableAgents = true
enableA2A = false
stream_chunking = true
```

---

## Part 7: Migration Guide

### From Kimi CLI
1. **Settings**: `~/.kimi/config.toml` → `~/.kimi/settings.toml`
2. **AGENTS.md**: Add hierarchical support with @import
3. **Commands**: Most slash commands remain compatible
4. **Sessions**: Automatic migration

### From Claude Code
1. **Plugins**: Convert `.claude-plugin/` to `.kimi-plugin/`
2. **Hooks**: Directly compatible (hooks.json)
3. **Agents**: Frontmatter format compatible
4. **CLAUDE.md**: Fully supported

### From Gemini CLI
1. **Settings**: `settings.json` → `settings.toml`
2. **Commands**: TOML format identical
3. **Agents**: YAML frontmatter identical
4. **GEMINI.md**: Fully supported with @import

### From OpenAI Codex
1. **Config**: Direct TOML compatibility
2. **Providers**: Same provider registry format
3. **AGENTS.md**: Hierarchical loading identical
4. **Patch format**: `apply_patch` tool compatible

---

## Appendix: Ultimate Feature Summary

### Unique to V4 (No Other CLI Has These Combinations)

1. **Policy + Hook + Checkpoint + Patch**: Complete control & safety
2. **MCP + A2A + ACP + Multi-Provider**: Universal protocol support
3. **Agent Flow + 7-Phase + Skills + Subagents**: Multi-level orchestration
4. **Dual-Mode + Sandboxing + Stream Chunking**: Ultimate UX
5. **Hierarchical AGENTS.md + @import + Cross-Session Memory**: Context mastery
6. **10+ LLM Providers**: True vendor independence
7. **Rust Core + Zero Dependencies**: Performance & distribution

### Complete Command Inventory (40+)

```
# Core
/help, /model, /clear, /compact, /context, /usage, /sessions, /debug

# Git Workflow
/commit, /commit-push-pr, /clean_gone, /pr-status, /code-review

# State Management
/rewind, /restore, /checkpoint
/agents list/enable/disable/refresh
/skills list/activate/deactivate
/commands list

# Feature Development
/feature-dev, /plan, /review, /refactor

# Navigation & Control
/skill:*, /flow:*, /provider:*

# Session
/new, /fork, /teleport, /rename

# Exit
/quit, /exit, /logout
```

### Complete Tool Inventory (20+)

```
# File Operations
ReadFile, WriteFile, StrReplaceFile, apply_patch
Glob, Grep, ReadMediaFile

# Execution
Shell (sandboxed), Git (native)

# Web
SearchWeb, FetchURL

# Planning
update_plan, SetTodoList

# Memory
save_memory, load_context

# Agents
Task, CreateSubagent

# System
Think, configure_settings
```

---

**Document End**

*Kimi Professional V4 Ultimate: The synthesis of everything great about AI coding CLIs. The only CLI you'll ever need.*

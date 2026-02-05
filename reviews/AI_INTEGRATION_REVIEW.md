# MAINFRAME AI CLI Integration Review

> **Critical Analysis for Becoming THE Standard AI Bash Runtime**  
> Version: 1.0.0 | Date: 2026-02-04 | Status: Strategic Assessment

---

## Executive Summary

MAINFRAME has established itself as a leading AI-native bash runtime with 4,500+ functions, comprehensive MCP (Model Context Protocol) integration, and multi-platform skill support. This review analyzes current integration states across Claude Code, Kimi CLI, and Google CLI ecosystems, identifying gaps and proposing a **Universal AI CLI Protocol (UACP)** that positions MAINFRAME as the definitive standard for AI-agent bash runtimes.

### Key Findings

| Platform | Current Status | Integration Depth | Gap Severity |
|----------|---------------|-------------------|--------------|
| **Claude Code** | ✅ Production | Full MCP + Skill | Low |
| **Kimi CLI** | ✅ Production | Full Skill | Low |
| **Google CLI** | ❌ Missing | None | **Critical** |
| **Cursor** | ✅ Production | Rules File | Medium |
| **Aider** | ✅ Production | Conventions File | Medium |
| **Vercel AI SDK** | ✅ Production | System Prompt | Low |

### Strategic Recommendations

1. **Immediate**: Build Google CLI integration (gcloud + Gemini Code Assist)
2. **Short-term**: Implement Universal AI CLI Protocol (UACP) v1
3. **Medium-term**: Cross-CLI AWM (Agent Working Memory) synchronization
4. **Long-term**: AI CLI consortium standardization push

---

## 1. Current Integration State

### 1.1 Skills Directory Structure

```
skills/
├── README.md                    # Platform integration guide
├── claude-code/
│   └── SKILL.md                 # Claude Code skill (752 lines)
├── kimi-cli/
│   └── SKILL.md                 # Kimi CLI skill (768 lines)
├── cursor/
│   └── mainframe.mdc            # Cursor rules file
├── aider/
│   ├── CONVENTIONS.md           # Aider conventions
│   └── .aider.conf.yml          # Aider config
├── clawdbot/
│   └── README.md                # Clawdbot preamble
└── vercel-ai-sdk/
    └── system-prompt.md         # Vercel AI SDK system prompt
```

### 1.2 MCP Integration

**Current Implementation** (`mcp/`):

| Component | Purpose | Lines |
|-----------|---------|-------|
| `server.py` | MCP protocol handler | 98 |
| `tool_registry.py` | FUNCTIONS.json parser | 141 |
| `executor.py` | Bash subprocess execution | ~100 |
| `mainframe-mcp-server` | Executable wrapper | - |

**MCP Tool Exposure**:
- **Core Tier**: ~300 essential functions
- **Full Tier**: 4,000+ functions
- **Prefix**: `mainframe_` (e.g., `mainframe_json_object`)
- **Transport**: stdio (current), HTTP/SSE (future)

### 1.3 CLAUDE.md Analysis

**Current CLAUDE.md** provides:
- Platform support matrix (5 platforms)
- Library overview by category
- Essential patterns with code examples
- Function lookup commands
- Reference file index

**Strengths**:
- Clear, concise instructions
- Immediate value proposition
- Easy copy-paste patterns

**Gaps**:
- No automatic sourcing mechanism
- No dynamic function injection
- No context-aware hints

---

## 2. Claude Code Deep Integration

### 2.1 Current State

**Strengths**:
- Full SKILL.md integration (`~/.claude/skills/mainframe-bash`)
- MCP server for tool access
- Automatic skill activation on bash tasks

**Claude Code Architecture**:
```
Claude Code
    ├── Skill System (SKILL.md)
    │   └── Auto-loads for bash tasks
    ├── MCP Client
    │   └── Connects to mainframe-mcp-server
    └── Bash Execution
        └── Sources common.sh automatically
```

### 2.2 Proposed Enhancements

#### 2.2.1 Automatic AWM Session Management

**Problem**: Claude Code sessions don't automatically use AWM for persistence.

**Solution**: `claude-code-awm-bridge`

```bash
#!/usr/bin/env bash
# ~/.claude/hooks/awm-bridge.sh

# Auto-initialize AWM for each Claude Code session
export AWM_SESSION_ID="$(awm_init "claude-$(date +%s)")"
export AWM_NAMESPACE="claude-code"

# Hook into Claude Code's context loading
awm_checkpoint "claude_context_loaded" "$(date -Iseconds)"

# On session end, export summary
function _claude_awm_cleanup() {
    awm_export "${HOME}/.claude/sessions/${AWM_SESSION_ID}.md"
    awm_close
}
trap _claude_awm_cleanup EXIT
```

**Implementation**:
```python
# mcp/claude_awm_bridge.py
"""Bridge between Claude Code and MAINFRAME AWM."""

import os
from typing import Optional

class ClaudeAWMBridge:
    """Automatically manages AWM sessions for Claude Code."""
    
    def __init__(self):
        self.session_id: Optional[str] = None
        self.namespace = "claude-code"
    
    def init_session(self, task_name: str) -> str:
        """Initialize AWM session for current Claude task."""
        import subprocess
        result = subprocess.run(
            ["bash", "-c", f'source $MAINFRAME_ROOT/lib/awm.sh && awm_init "{task_name}"'],
            capture_output=True,
            text=True
        )
        self.session_id = result.stdout.strip()
        os.environ["AWM_SESSION_ID"] = self.session_id
        return self.session_id
    
    def get_context_injection(self) -> str:
        """Get AWM summary for Claude context window."""
        if not self.session_id:
            return ""
        result = subprocess.run(
            ["bash", "-c", f'source $MAINFRAME_ROOT/lib/awm.sh && awm_summary'],
            capture_output=True,
            text=True
        )
        return f"\n[AWM Session: {self.session_id}]\n{result.stdout}\n"
```

#### 2.2.2 Enhanced MCP Integration

**Current**: Basic tool exposure

**Proposed**: Context-aware function discovery

```python
# mcp/claude_enhanced_server.py

@mcp.tool()
def mainframe_smart_complete(partial: str, context: str) -> str:
    """Smart function completion based on context.
    
    Args:
        partial: Partial function name or description
        context: Current code context for relevance scoring
    """
    # Use embeddings to find most relevant functions
    relevant = registry.find_relevant(context, top_k=5)
    return json.dumps([{
        "name": f["name"],
        "signature": f["signature"],
        "relevance": f["score"]
    } for f in relevant])

@mcp.tool()
def mainframe_context_inject(awm_session: str) -> str:
    """Inject AWM session state into Claude context."""
    return awm_bridge.get_context_for_session(awm_session)
```

#### 2.2.3 Claude Code Native Hooks

**Proposed `.claude/hooks/` integration**:

```yaml
# .claude/mainframe.yaml
hooks:
  pre_task:
    - source: $MAINFRAME_ROOT/lib/common.sh
    - awm_init "claude-task-${CLAUDE_TASK_ID}"
  
  post_task:
    - awm_export "${CLAUDE_SESSION_DIR}/awm-summary.md"
    - awm_close
  
  on_error:
    - awm_log "errors" "${CLAUDE_ERROR_MESSAGE}"
    - forensics_capture  # Auto-capture error context
  
  context_enrichment:
    - mainframe quickref --search "${CLAUDE_CONTEXT_QUERY}"
```

---

## 3. Kimi CLI Integration

### 3.1 Current State

**Strengths**:
- Full SKILL.md support
- Agent spec system for customization
- ACP (Agent Communication Protocol) integration
- MCP client support

**Kimi CLI Architecture**:
```
Kimi CLI v1.7.0
    ├── Agent System
    │   ├── agents/default/agent.yaml    # Base agent spec
    │   ├── agents/default/system.md     # System prompt
    │   └── AgentSpec (YAML-based)
    ├── ACP Server
    │   ├── Single-session: run_acp()
    │   └── Multi-session: acp_main()
    ├── MCP Client
    │   └── acp_mcp_servers_to_mcp_config()
    └── Skills
        └── ~/.claude/skills/ (shared with Claude Code)
```

### 3.2 Kimi CLI Agent Specification

**Current Agent Spec** (`agents/default/agent.yaml`):
```yaml
version: 1
agent:
  name: ""
  system_prompt_path: ./system.md
  system_prompt_args:
    ROLE_ADDITIONAL: ""
  tools:
    - "kimi_cli.tools.shell:Shell"
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.web:SearchWeb"
  subagents:
    coder:
      path: ./sub.yaml
      description: "Good at general software engineering tasks."
```

### 3.3 Proposed Kimi CLI Enhancements

#### 3.3.1 Native MAINFRAME Agent Extension

```yaml
# ~/.kimi/agents/mainframe/agent.yaml
version: 1
agent:
  extend: default
  name: "mainframe-agent"
  system_prompt_path: ./system.md
  system_prompt_args:
    ROLE_ADDITIONAL: |
      You have access to MAINFRAME - 4,500+ pure bash functions.
      Always source MAINFRAME first: source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
  tools:
    - "kimi_cli.tools.shell:Shell"
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.file:WriteFile"
    # Add MAINFRAME-specific tools via MCP
    - "mcp:mainframe"
  mcp_servers:
    - name: mainframe
      command: ~/.mainframe/mcp/mainframe-mcp-server
      env:
        MAINFRAME_ROOT: ~/.mainframe
        MAINFRAME_MCP_TIER: core
```

#### 3.3.2 Automatic Context Window Management

**Kimi CLI Context Template Variables**:
```markdown
# Current system.md template variables:
# ${KIMI_NOW} - Current ISO timestamp
# ${KIMI_WORK_DIR} - Working directory
# ${KIMI_WORK_DIR_LS} - Directory listing
# ${KIMI_AGENTS_MD} - Project AGENTS.md content

# PROPOSED additions:
# ${MAINFRAME_QUICKREF} - Relevant function quick reference
# ${AWM_SESSION_SUMMARY} - Current AWM session state
# ${MAINFRAME_CONTEXT} - Project-specific MAINFRAME hints
```

**Implementation**:
```python
# skills/kimi-cli/context_provider.py

class MainframeContextProvider:
    """Provides MAINFRAME context for Kimi CLI templates."""
    
    def get_template_vars(self, work_dir: str) -> dict:
        """Generate template variables for Kimi CLI."""
        vars = {}
        
        # Relevant function quick reference
        vars["MAINFRAME_QUICKREF"] = self._get_relevant_functions(work_dir)
        
        # AWM session summary
        vars["AWM_SESSION_SUMMARY"] = self._get_awm_summary()
        
        # Project-specific hints
        vars["MAINFRAME_CONTEXT"] = self._get_project_hints(work_dir)
        
        return vars
    
    def _get_relevant_functions(self, work_dir: str) -> str:
        """Detect project type and suggest relevant functions."""
        # Use project.sh detection
        project_type = project_detect(work_dir)
        
        hints = {
            "python": ["py_file_imports", "py_summary", "venv_activate"],
            "typescript": ["ts_file_imports", "ts_import_cost", "bun_run"],
            "go": ["go_mod_tidy", "go_build", "go_test"],
        }
        
        return self._format_hints(hints.get(project_type["language"], []))
```

#### 3.3.3 Kimi CLI AWM Hooks

```python
# ~/.kimi/hooks/awm.py

import subprocess
from kimi_cli.hooks import PrePromptHook, PostResponseHook

class MainframeAWMHook(PrePromptHook, PostResponseHook):
    """Integrate MAINFRAME AWM with Kimi CLI."""
    
    def pre_prompt(self, context: dict) -> dict:
        """Inject AWM state before each prompt."""
        session_id = context.get("awm_session")
        if session_id:
            summary = subprocess.run(
                ["bash", "-c", 
                 f"source $MAINFRAME_ROOT/lib/awm.sh && awm_resume {session_id} && awm_summary"],
                capture_output=True, text=True
            )
            context["system_prompt_append"] = f"\n[AWM State]\n{summary.stdout}"
        return context
    
    def post_response(self, context: dict, response: str) -> str:
        """Store discoveries in AWM after each response."""
        if "discovery:" in response.lower():
            discovery = self._extract_discovery(response)
            subprocess.run(
                ["bash", "-c",
                 f"source $MAINFRAME_ROOT/lib/awm.sh && awm_discovery '{discovery}'"]
            )
        return response
```

---

## 4. Google CLI Integration

### 4.1 Current State

**Gap**: No Google CLI integration exists.

**Google CLI Ecosystem**:
| Tool | Purpose | Integration Potential |
|------|---------|----------------------|
| `gcloud` | Google Cloud management | High - cloud deployment |
| `gemini` | Gemini CLI (if exists) | High - direct AI integration |
| `firebase` | Firebase management | Medium - mobile deployment |
| `gsutil` | Cloud Storage | Medium - via ext/gcp.sh |

### 4.2 Proposed Google CLI Integration

#### 4.2.1 gcloud + MAINFRAME Bridge

```bash
#!/usr/bin/env bash
# ~/.mainframe/skills/google-cli/gcloud-bridge.sh

# Integrate MAINFRAME with gcloud CLI
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
source "${MAINFRAME_ROOT}/lib/ext/gcp.sh"

# Function: Auto-configure gcloud with MAINFRAME
gcp_mainframe_init() {
    local project_id="$1"
    
    # Validate project
    validate_project_id "$project_id" || die 1 "Invalid project ID"
    
    # Configure gcloud
    gcloud config set project "$project_id"
    
    # Store in AWM
    awm_init "gcp-${project_id}"
    awm_checkpoint "gcp_project" "$project_id"
    awm_checkpoint "gcp_configured" "$(now_iso)"
    
    output_success "gcloud configured for ${project_id}"
}

# Function: Deploy with MAINFRAME validation
gcp_mainframe_deploy() {
    local service="$1"
    local source="${2:-.}"
    
    # Validate source
    validate_path_safe "$source" "$(pwd)" || die 1 "Invalid source path"
    
    # Run pre-deploy checks
    gcp_validate_service_yaml "$source" || die 1 "Service YAML invalid"
    
    # Deploy
    gcloud run deploy "$service" --source="$source"
    
    # Log to AWM
    awm_log "deployments" "Deployed ${service} at $(now_iso)"
}
```

#### 4.2.2 Gemini Code Assist Integration

**Assuming Gemini Code Assist follows similar patterns**:

```yaml
# ~/.mainframe/skills/google-cli/gemini-integration.yaml
name: mainframe-bash
description: MAINFRAME integration for Gemini Code Assist

# Context injection
preamble: |
  When writing bash scripts in Google Cloud environments, source MAINFRAME:
  source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
  
  For GCP operations, use MAINFRAME's gcp.sh wrappers:
  - gcp_project_list    # List projects
  - gcp_service_enable  # Enable APIs
  - gcp_deploy_function # Deploy Cloud Function

# Tool integration
tools:
  - name: mainframe_function_discovery
    description: Find relevant MAINFRAME functions
    command: mainframe quickref --search
  
  - name: mainframe_awm_checkpoint
    description: Store state in Agent Working Memory
    command: awm_checkpoint
```

#### 4.2.3 Google Cloud Shell Integration

```bash
# ~/.mainframe/skills/google-cli/cloud-shell-init.sh

# Auto-install MAINFRAME in Cloud Shell
if [[ -n "$CLOUD_SHELL" ]]; then
    if [[ ! -d "$HOME/.mainframe" ]]; then
        git clone https://github.com/gtwatts/mainframe.git ~/.mainframe
    fi
    
    # Auto-source in Cloud Shell
    echo 'source "$HOME/.mainframe/lib/common.sh"' >> ~/.bashrc
    
    # Configure AWM for Cloud Shell
    export AWM_ROOT="$HOME/.mainframe/awm"
    export AWM_NAMESPACE="cloud-shell"
fi
```

---

## 5. Universal AI CLI Protocol (UACP)

### 5.1 Protocol Vision

**Goal**: A common interface that works across all AI CLIs, enabling:
- Standardized memory exchange
- Cross-CLI agent handoff
- Unified observability
- Capability negotiation

### 5.2 UACP Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Universal AI CLI Protocol                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Claude Code │  │  Kimi CLI   │  │ Google CLI  │   ...        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                     │
│         └────────────────┼────────────────┘                     │
│                          │                                      │
│                    ┌─────┴─────┐                                │
│                    │  UACP     │                                │
│                    │  Bridge   │                                │
│                    └─────┬─────┘                                │
│                          │                                      │
│         ┌────────────────┼────────────────┐                     │
│         │                │                │                     │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐             │
│  │    AWM      │  │   MCP       │  │   Skills    │             │
│  │   Memory    │  │   Tools     │  │   Registry  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 UACP Specification v1.0

#### 5.3.1 Standardized Memory Exchange Format

```typescript
// uacp/memory.schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "UACP Memory Exchange",
  "type": "object",
  "properties": {
    "version": { "const": "1.0.0" },
    "session": {
      "type": "object",
      "properties": {
        "id": { "type": "string" },
        "origin_cli": { "enum": ["claude-code", "kimi-cli", "google-cli", "cursor", "aider"] },
        "created_at": { "type": "string", "format": "date-time" },
        "expires_at": { "type": "string", "format": "date-time" }
      }
    },
    "checkpoints": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "key": { "type": "string" },
          "value": {},
          "timestamp": { "type": "string", "format": "date-time" },
          "ttl": { "type": "number" }
        }
      }
    },
    "discoveries": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "content": { "type": "string" },
          "priority": { "enum": ["low", "normal", "high", "critical"] },
          "tags": { "type": "array", "items": { "type": "string" } }
        }
      }
    },
    "context_window": {
      "type": "object",
      "properties": {
        "max_tokens": { "type": "number" },
        "used_tokens": { "type": "number" },
        "compression_ratio": { "type": "number" }
      }
    }
  }
}
```

#### 5.3.2 CLI-Agnostic Agent Orchestration

```python
# uacp/orchestrator.py

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional, List, Dict, Any

@dataclass
class UACPAgent:
    """CLI-agnostic agent representation."""
    id: str
    cli_type: str  # "claude-code", "kimi-cli", etc.
    capabilities: List[str]
    memory_session: Optional[str]
    status: str  # "idle", "busy", "blocked", "error"

class UACPAdapter(ABC):
    """Abstract adapter for AI CLI integration."""
    
    @abstractmethod
    def spawn_agent(self, task: str, context: Dict[str, Any]) -> UACPAgent:
        """Spawn a new agent in this CLI."""
        pass
    
    @abstractmethod
    def inject_context(self, agent_id: str, context: str) -> bool:
        """Inject context into running agent."""
        pass
    
    @abstractmethod
    def extract_memory(self, agent_id: str) -> Dict[str, Any]:
        """Extract memory from agent in UACP format."""
        pass

class ClaudeCodeAdapter(UACPAdapter):
    """Claude Code UACP adapter."""
    
    def spawn_agent(self, task: str, context: Dict[str, Any]) -> UACPAgent:
        # Use TMUX window + Claude Code
        window_id = orch_agent_spawn("uacp-task", task)
        return UACPAgent(
            id=window_id,
            cli_type="claude-code",
            capabilities=["bash", "edit", "web_search"],
            memory_session=None,
            status="initializing"
        )
    
    def extract_memory(self, agent_id: str) -> Dict[str, Any]:
        # Export AWM session
        return awm_export_to_uacp(agent_id)

class KimiCLIAdapter(UACPAdapter):
    """Kimi CLI UACP adapter."""
    
    def spawn_agent(self, task: str, context: Dict[str, Any]) -> UACPAgent:
        # Use Kimi's subagent system
        from kimi_cli.agentspec import load_agent_spec
        # ... spawn via Kimi agent spec
```

### 5.4 UACP Implementation in MAINFRAME

```bash
#!/usr/bin/env bash
# lib/uacp.sh - Universal AI CLI Protocol implementation

# =============================================================================
# UACP Core Functions
# =============================================================================

uacp_version() {
    printf '1.0.0'
}

uacp_memory_export() {
    local session_id="${1:-$AWM_SESSION_ID}"
    local format="${2:-json}"
    
    # Export AWM session in UACP format
    local session_data
    session_data=$(awm_export_json "$session_id")
    
    # Transform to UACP schema
    json_object \
        "version=1.0.0" \
        "session:raw=$(uacp_session_object "$session_id")" \
        "checkpoints:raw=$(awm_get_checkpoints "$session_id")" \
        "discoveries:raw=$(awm_get_discoveries "$session_id")"
}

uacp_memory_import() {
    local uacp_data="$1"
    local target_namespace="${2:-$UACP_DEFAULT_NAMESPACE}"
    
    # Validate UACP format
    if ! uacp_validate "$uacp_data"; then
        output_error "E_UACP_INVALID" "Invalid UACP data format"
        return 1
    fi
    
    # Import into AWM
    local session_id
    session_id=$(awm_init "uacp-import-$(uuid)")
    
    # Restore checkpoints
    json_get "$uacp_data" "checkpoints" | while read -r checkpoint; do
        local key=$(json_get "$checkpoint" "key")
        local value=$(json_get "$checkpoint" "value")
        awm_checkpoint "$key" "$value"
    done
    
    printf '%s' "$session_id"
}

uacp_capability_negotiate() {
    local cli_type="$1"
    shift
    local requested_capabilities=("$@")
    
    # Define MAINFRAME capabilities
    declare -A MAINFRAME_CAPS=(
        ["bash_execution"]="full"
        ["file_operations"]="full"
        ["json_processing"]="full"
        ["http_client"]="full"
        ["awm_storage"]="full"
        ["agent_coordination"]="full"
        ["validation"]="full"
        ["crypto"]="full"
    )
    
    # Negotiate based on CLI capabilities
    case "$cli_type" in
        claude-code)
            MAINFRAME_CAPS["web_search"]="full"
            MAINFRAME_CAPS["edit_files"]="full"
            ;;
        kimi-cli)
            MAINFRAME_CAPS["parallel_tools"]="full"
            MAINFRAME_CAPS["media_processing"]="full"
            ;;
    esac
    
    # Return intersection
    for cap in "${requested_capabilities[@]}"; do
        if [[ -n "${MAINFRAME_CAPS[$cap]}" ]]; then
            json_object "capability=$cap" "level=${MAINFRAME_CAPS[$cap]}"
        fi
    done
}
```

---

## 6. Prompt Engineering Integration

### 6.1 Dynamic Function Discovery

**Current**: Static skill files

**Proposed**: Context-aware function injection

```python
# lib/prompt_inject.py

class MainframePromptInjector:
    """Inject relevant MAINFRAME functions into AI prompts dynamically."""
    
    def __init__(self):
        self.registry = ToolRegistry()
        self.embeddings = None  # Lazy-load embedding model
    
    def inject_for_context(self, user_query: str, project_context: dict) -> str:
        """Generate function reference for current context."""
        
        # Detect intent from query
        intent = self._detect_intent(user_query)
        
        # Find relevant functions
        relevant = self._find_relevant_functions(intent, project_context)
        
        # Generate prompt section
        return self._format_function_hints(relevant)
    
    def _detect_intent(self, query: str) -> str:
        """Detect user intent using simple keyword matching."""
        intents = {
            "json": ["json", "parse", "serialize"],
            "file": ["file", "read", "write", "edit"],
            "validation": ["validate", "check", "verify"],
            "http": ["http", "api", "request", "curl"],
            "process": ["process", "parallel", "async"],
        }
        
        query_lower = query.lower()
        for intent, keywords in intents.items():
            if any(kw in query_lower for kw in keywords):
                return intent
        return "general"
    
    def _find_relevant_functions(self, intent: str, context: dict) -> list:
        """Find functions relevant to intent."""
        
        intent_mappings = {
            "json": ["json_object", "json_array", "json_get", "json_merge"],
            "file": ["read_file", "atomic_write", "diff_replace"],
            "validation": ["validate_email", "validate_url", "validate_path_safe"],
            "http": ["http_get", "http_post", "http_json_get"],
            "process": ["parallel", "parallel_limit", "retry"],
        }
        
        return intent_mappings.get(intent, [])
    
    def _format_function_hints(self, functions: list) -> str:
        """Format function hints for prompt injection."""
        hints = ["## Available MAINFRAME Functions\n"]
        
        for func_name in functions[:10]:  # Limit to top 10
            func = self.registry.get_function(func_name)
            if func:
                hints.append(f"- `{func['signature']}` - {func['description']}")
        
        hints.append("\nSource MAINFRAME: `source $MAINFRAME_ROOT/lib/common.sh`")
        
        return "\n".join(hints)
```

### 6.2 Automatic Documentation Injection

```bash
#!/usr/bin/env bash
# lib/prompt_docs.sh

# Generate context-aware documentation snippets
prompt_docs_for_task() {
    local task_type="$1"
    local project_dir="${2:-.}"
    
    case "$task_type" in
        "json-processing")
            cat <<-'EOF'
### JSON Operations
```bash
# Create JSON object
json_object "name=John" "age:number=30"

# Create array
json_array "a" "b" "c"

# Extract value
json_get '{"name":"John"}' "name"

# Merge objects
json_merge '{"a":1}' '{"b":2}'
```
EOF
            ;;
        
        "file-editing")
            cat <<-'EOF'
### File Editing (AI Agent Primary)
```bash
# Surgical text replacement
diff_replace "file.ts" "old_text" "new_text"

# Insert after match
diff_insert_after "file.ts" "pattern" "new_line"

# Delete lines
diff_delete_lines "file.ts" "pattern"
```
EOF
            ;;
        
        "project-analysis")
            # Auto-detect project type
            local project_type
            project_type=$(project_detect "$project_dir")
            
            case "$(json_get "$project_type" "language")" in
                "python")
                    cat <<-'EOF'
### Python Analysis
```bash
# Extract imports
py_file_imports "app/main.py"

# Dependency graph
py_import_graph "."

# Framework detection
py_framework_detect "."
```
EOF
                    ;;
                "typescript")
                    cat <<-'EOF'
### TypeScript Analysis
```bash
# Extract imports
ts_file_imports "src/index.ts"

# Bundle size
ts_import_cost "express" "."

# Breaking changes
ts_breaking_changes "v1.d.ts" "v2.d.ts"
```
EOF
                    ;;
            esac
            ;;
    esac
}
```

### 6.3 Context-Aware Hint System

```bash
#!/usr/bin/env bash
# lib/hints.sh - Enhanced version

# Context-aware hint generation
hints_for_project() {
    local project_dir="${1:-.}"
    
    local hints=()
    
    # Detect project characteristics
    if [[ -f "$project_dir/package.json" ]]; then
        hints+=("Use 'ts_import_cost' to analyze bundle size")
        hints+=("Use 'bun_run' for TypeScript execution")
    fi
    
    if [[ -f "$project_dir/requirements.txt" ]] || [[ -f "$project_dir/pyproject.toml" ]]; then
        hints+=("Use 'py_summary' for project health overview")
        hints+=("Use 'py_file_imports' to analyze dependencies")
    fi
    
    if [[ -d "$project_dir/.git" ]]; then
        hints+=("Use 'git_summary' for quick repo status")
        hints+=("Use 'git_files_changed' to see modified files")
    fi
    
    # Generate JSON hints
    json_object \
        "project_dir=$project_dir" \
        "hints:raw=$(json_array "${hints[@]}")" \
        "generated=$(now_iso)"
}

# Inject hints into prompt
hints_inject_prompt() {
    local original_prompt="$1"
    local project_dir="${2:-.}"
    
    # Get relevant hints
    local hints_json
    hints_json=$(hints_for_project "$project_dir")
    
    # Extract hint array
    local hints_array
    hints_array=$(json_get "$hints_json" "hints")
    
    # Build injection
    local injection="\n[MAINFRAME Hints for this project]\n"
    for hint in $(json_get_array_items "$hints_array"); do
        injection+="- $hint\n"
    done
    
    # Append to prompt
    printf '%s%s' "$original_prompt" "$injection"
}
```

---

## 7. Real-Time Collaboration

### 7.1 Multi-CLI State Sharing

**Vision**: Multiple AI CLIs sharing MAINFRAME state seamlessly

```
Scenario: Code Review Pipeline

┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Claude Code  │───→│   MAINFRAME  │←───│  Kimi CLI    │
│   (Author)   │    │    AWM Hub   │    │  (Reviewer)  │
└──────────────┘    └──────────────┘    └──────────────┘
       │                    │                    │
       │  awm_checkpoint     │    awm_resume      │
       │  "feature-branch"   │←───"feature-branch"│
       │                    │                    │
       │  awm_discovery      │    awm_get         │
       │  "API changed"      │───→"API changed"   │
       │                    │                    │
```

### 7.2 Cross-CLI Agent Handoff

```bash
#!/usr/bin/env bash
# lib/handoff.sh

# Export agent state for handoff to different CLI
handoff_export() {
    local session_id="${1:-$AWM_SESSION_ID}"
    local target_cli="$2"  # claude-code, kimi-cli, google-cli
    
    # Gather session data
    local session_data
    session_data=$(awm_export_json "$session_id")
    
    # Add handoff metadata
    json_object \
        "version=1.0.0" \
        "source_cli=mainframe" \
        "target_cli=$target_cli" \
        "session:raw=$session_data" \
        "exported_at=$(now_iso)" \
        "token_estimate=$(awm_token_estimate)"
}

# Import agent state from another CLI
handoff_import() {
    local handoff_data="$1"
    local source_cli
    source_cli=$(json_get "$handoff_data" "source_cli")
    
    # Create new session with inherited data
    local new_session
    new_session=$(awm_init "handoff-${source_cli}-$(uuid)")
    
    # Import checkpoints
    local checkpoints
    checkpoints=$(json_get "$handoff_data" "session.checkpoints")
    
    # ... restore checkpoints
    
    printf '%s' "$new_session"
}

# Handoff via shared storage (Redis, file, cloud)
handoff_publish() {
    local session_id="$1"
    local channel="$2"
    
    # Use orchestrate.sh pub/sub
    orch_message_broadcast "$channel" "$(handoff_export "$session_id" "any")"
}

handoff_subscribe() {
    local channel="$1"
    local callback="$2"
    
    # Subscribe to handoff channel
    orch_message_subscribe "$channel" "$callback"
}
```

### 7.3 Unified Observability

```python
# uacp/observability.py

from dataclasses import dataclass
from typing import Dict, List, Optional
from datetime import datetime

@dataclass
class AgentSpan:
    """Cross-CLI trace span."""
    trace_id: str
    span_id: str
    parent_span_id: Optional[str]
    cli_type: str  # claude-code, kimi-cli, etc.
    agent_id: str
    operation: str
    start_time: datetime
    end_time: Optional[datetime]
    attributes: Dict[str, str]
    
class UnifiedObserver:
    """Unified observability across AI CLIs."""
    
    def __init__(self, backend: str = "file"):
        self.backend = backend
        self.spans: List[AgentSpan] = []
    
    def start_span(
        self,
        cli_type: str,
        agent_id: str,
        operation: str,
        parent_span: Optional[str] = None
    ) -> str:
        """Start a new trace span."""
        span = AgentSpan(
            trace_id=self._generate_trace_id(),
            span_id=self._generate_span_id(),
            parent_span_id=parent_span,
            cli_type=cli_type,
            agent_id=agent_id,
            operation=operation,
            start_time=datetime.utcnow(),
            end_time=None,
            attributes={}
        )
        self.spans.append(span)
        return span.span_id
    
    def end_span(self, span_id: str, attributes: Dict[str, str] = None):
        """End a trace span."""
        for span in self.spans:
            if span.span_id == span_id:
                span.end_time = datetime.utcnow()
                if attributes:
                    span.attributes.update(attributes)
                break
    
    def get_trace(self, trace_id: str) -> List[AgentSpan]:
        """Get all spans for a trace."""
        return [s for s in self.spans if s.trace_id == trace_id]
    
    def export_to_otel(self) -> dict:
        """Export traces to OpenTelemetry format."""
        # Convert to OTel JSON format
        return {
            "resourceSpans": [{
                "resource": {
                    "attributes": [{
                        "key": "service.name",
                        "value": {"stringValue": "mainframe-agents"}
                    }]
                },
                "scopeSpans": [{
                    "scope": {"name": "uacp"},
                    "spans": [self._span_to_otel(s) for s in self.spans]
                }]
            }]
        }
```

---

## 8. Implementation Roadmap

### 8.1 Phase 1: Foundation (Weeks 1-4)

**Priority: Critical**

| Task | Effort | Deliverable |
|------|--------|-------------|
| Google CLI research | 3 days | Architecture doc |
| UACP spec v0.1 | 5 days | Spec document |
| lib/uacp.sh implementation | 5 days | Core protocol lib |
| Enhanced MCP server | 5 days | mcp/server_v2.py |

**Success Criteria**:
- [ ] UACP specification published
- [ ] Basic cross-CLI memory exchange working
- [ ] Enhanced MCP with context awareness

### 8.2 Phase 2: CLI Integration (Weeks 5-8)

**Priority: High**

| Task | Effort | Deliverable |
|------|--------|-------------|
| Claude Code AWM bridge | 5 days | `mcp/claude_awm_bridge.py` |
| Kimi CLI native agent | 5 days | `skills/kimi-cli/agent.yaml` |
| Google CLI integration | 10 days | `skills/google-cli/` |
| Handoff system | 5 days | `lib/handoff.sh` |

**Success Criteria**:
- [ ] Claude Code auto-AWM working
- [ ] Kimi CLI native MAINFRAME agent
- [ ] Google CLI basic integration
- [ ] Cross-CLI handoff functional

### 8.3 Phase 3: Intelligence (Weeks 9-12)

**Priority: Medium**

| Task | Effort | Deliverable |
|------|--------|-------------|
| Dynamic function discovery | 5 days | `lib/prompt_inject.py` |
| Context-aware hints | 5 days | `lib/hints.sh` enhanced |
| Unified observability | 5 days | `uacp/observability.py` |
| Capability negotiation | 5 days | Protocol extension |

**Success Criteria**:
- [ ] Functions auto-suggested by context
- [ ] Project-specific hints working
- [ ] Cross-CLI observability dashboard

### 8.4 Phase 4: Standardization (Weeks 13-16)

**Priority: Medium**

| Task | Effort | Deliverable |
|------|--------|-------------|
| UACP spec v1.0 | 5 days | RFC document |
| Reference implementation | 10 days | Complete lib set |
| Documentation | 5 days | Full guide |
| Community outreach | Ongoing | Blog posts, talks |

**Success Criteria**:
- [ ] UACP v1.0 published as RFC
- [ ] Reference implementation complete
- [ ] Community adoption started

---

## 9. Example Integration Code

### 9.1 Complete Claude Code Integration

```python
# ~/.claude/mcp.json (enhanced)
{
  "mcpServers": {
    "mainframe": {
      "command": "~/.mainframe/mcp/mainframe-mcp-server",
      "env": {
        "MAINFRAME_ROOT": "~/.mainframe",
        "MAINFRAME_MCP_TIER": "full",
        "MAINFRAME_AWM_AUTO": "1",
        "MAINFRAME_CONTEXT_INJECT": "1"
      }
    },
    "mainframe-awm": {
      "command": "~/.mainframe/mcp/claude-awm-bridge.py",
      "env": {
        "AWM_NAMESPACE": "claude-code"
      }
    }
  }
}
```

```bash
# ~/.claude/hooks/mainframe.sh

# Auto-source MAINFRAME
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Auto-initialize AWM for this Claude session
if [[ -z "$AWM_SESSION_ID" ]]; then
    export AWM_SESSION_ID=$(awm_init "claude-$(date +%s)")
    export AWM_NAMESPACE="claude-code"
    echo "[MAINFRAME] AWM session initialized: $AWM_SESSION_ID"
fi

# Context enrichment hook
_claude_context_hook() {
    local query="$1"
    
    # Inject relevant functions
    relevant=$(mainframe quickref --search "$query" | head -5)
    if [[ -n "$relevant" ]]; then
        echo -e "\n[MAINFRAME Functions for '$query']\n$relevant"
    fi
    
    # Inject AWM summary
    echo -e "\n[AWM Session Summary]\n$(awm_summary)"
}
```

### 9.2 Complete Kimi CLI Integration

```yaml
# ~/.kimi/agents/mainframe/agent.yaml
version: 1
agent:
  extend: default
  name: mainframe-coder
  system_prompt_path: ./system.md
  system_prompt_args:
    ROLE_ADDITIONAL: |
      You are enhanced with MAINFRAME - 4,500+ pure bash functions.
      
      CRITICAL RULES:
      1. ALWAYS source MAINFRAME first in bash scripts
      2. NEVER use jq, sed, awk when MAINFRAME has equivalent
      3. Use AWM for persistence across turns
      
      TEMPLATE VARIABLES:
      - ${MAINFRAME_CONTEXT}: Project-specific hints
      - ${AWM_STATE}: Current AWM session state
  
  tools:
    - "kimi_cli.tools.shell:Shell"
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.file:WriteFile"
  
  mcp_servers:
    - name: mainframe-core
      command: ~/.mainframe/mcp/mainframe-mcp-server
      env:
        MAINFRAME_MCP_TIER: core
    
    - name: mainframe-awm
      command: ~/.mainframe/mcp/kimi-awm-bridge.py
```

```markdown
# ~/.kimi/agents/mainframe/system.md

You are Kimi Code CLI with MAINFRAME enhancement.

${ROLE_ADDITIONAL}

## MAINFRAME Quick Reference

### Most Used Functions
- `json_object "key=val"` - Create JSON without jq
- `diff_replace "file" "old" "new"` - Surgical file editing
- `validate_path_safe "$path" "/base"` - Security validation
- `awm_checkpoint "key" "val"` - Persist state
- `parallel "cmd1" "cmd2"` - Parallel execution

### Project Context
${MAINFRAME_CONTEXT}

### Current AWM State
${AWM_STATE}
```

### 9.3 Complete Google CLI Integration

```bash
#!/usr/bin/env bash
# ~/.mainframe/skills/google-cli/install.sh

# Google CLI Integration Installer

set -e

MAINFRAME_ROOT="${MAINFRAME_ROOT:-$HOME/.mainframe}"

echo "Installing MAINFRAME Google CLI integration..."

# 1. Install gcloud functions
cp "$MAINFRAME_ROOT/skills/google-cli/gcp-functions.sh" \
   "$MAINFRAME_ROOT/lib/ext/gcp-enhanced.sh"

# 2. Install Gemini integration (if available)
if command -v gemini &>/dev/null; then
    cp "$MAINFRAME_ROOT/skills/google-cli/gemini-skill.yaml" \
       ~/.gemini/skills/mainframe.yaml
fi

# 3. Configure Cloud Shell
if [[ -n "$CLOUD_SHELL" ]]; then
    echo "source '$MAINFRAME_ROOT/lib/common.sh'" >> ~/.bashrc
fi

# 4. Set up gcloud hooks
mkdir -p ~/.config/gcloud/hooks
ln -sf "$MAINFRAME_ROOT/skills/google-cli/gcloud-hook.sh" \
       ~/.config/gcloud/hooks/mainframe.sh

echo "Google CLI integration complete!"
```

```python
# ~/.mainframe/skills/google-cli/gemini_bridge.py

"""Bridge between Gemini Code Assist and MAINFRAME."""

import os
import subprocess
from typing import Optional, Dict, Any

class GeminiMainframeBridge:
    """Integrate MAINFRAME with Gemini Code Assist."""
    
    def __init__(self):
        self.mainframe_root = os.environ.get(
            'MAINFRAME_ROOT',
            os.path.expanduser('~/.mainframe')
        )
    
    def get_preamble(self, project_dir: str) -> str:
        """Generate Gemini preamble with MAINFRAME context."""
        
        # Detect project type
        project_info = self._detect_project(project_dir)
        
        preamble = f"""
You are Gemini Code Assist with MAINFRAME enhancement.

## MAINFRAME Access
Source MAINFRAME at the start of bash scripts:
```bash
source "${self.mainframe_root}/lib/common.sh"
```

## Project Context
Language: {project_info['language']}
Framework: {project_info['framework']}

## Recommended Functions
"""
        
        # Add project-specific recommendations
        if project_info['language'] == 'python':
            preamble += """
- `py_file_imports "app/main.py"` - Extract imports
- `py_summary "."` - Project health
- `venv_activate ".venv"` - Activate virtualenv
"""
        elif project_info['language'] == 'typescript':
            preamble += """
- `ts_file_imports "src/index.ts"` - Extract imports
- `ts_import_cost "express" "."` - Bundle size
- `bun_run "build"` - Build project
"""
        
        return preamble
    
    def _detect_project(self, project_dir: str) -> Dict[str, str]:
        """Detect project type using MAINFRAME."""
        result = subprocess.run(
            ['bash', '-c', 
             f'source {self.mainframe_root}/lib/common.sh && '
             f'project_detect "{project_dir}"'],
            capture_output=True,
            text=True
        )
        # Parse JSON output
        import json
        return json.loads(result.stdout)
```

---

## 10. Conclusion

### 10.1 Current Position

MAINFRAME is well-positioned as the leading AI-native bash runtime:

| Strength | Evidence |
|----------|----------|
| Function coverage | 4,500+ functions, 135 libraries |
| Test quality | 10,300+ tests, property-based testing |
| Platform support | 5+ AI CLIs supported |
| MCP integration | Production-ready server |
| AWM innovation | First-class agent memory |

### 10.2 Critical Gaps

1. **Google CLI**: No integration exists (highest priority)
2. **Dynamic injection**: Static skills only (prompt engineering opportunity)
3. **Cross-CLI collaboration**: Limited handoff mechanisms
4. **Standardization**: No industry-wide protocol

### 10.3 Path to Standard

To become THE standard AI bash runtime, MAINFRAME should:

1. **Execute Phase 1-2 roadmap** (8 weeks)
2. **Publish UACP as RFC** (open standard)
3. **Drive industry adoption** (partnerships, talks)
4. **Maintain quality leadership** (continue test/perf focus)

### 10.4 Success Metrics

| Metric | Current | 6-Month Target |
|--------|---------|----------------|
| Supported CLIs | 5 | 8 |
| Cross-CLI handoffs | 0/day | 100/day |
| AWM sessions/day | Unknown | 10,000 |
| UACP adoptions | 0 | 3 implementations |

---

## Appendices

### A. Reference Links

- MAINFRAME Repository: https://github.com/gtwatts/mainframe
- MCP Specification: https://modelcontextprotocol.io
- Kimi CLI: https://github.com/moonshot-ai/kimi-cli
- Claude Code: https://docs.anthropic.com/en/docs/claude-code

### B. Glossary

| Term | Definition |
|------|------------|
| **AWM** | Agent Working Memory - MAINFRAME's persistent external memory |
| **MCP** | Model Context Protocol - Anthropic's tool protocol |
| **UACP** | Universal AI CLI Protocol - Proposed cross-CLI standard |
| **USOP** | Universal Structured Output Protocol - MAINFRAME's JSON output format |
| **SKILL.md** | Claude Code's skill format |
| **ACP** | Agent Communication Protocol - Kimi CLI's protocol |

### C. Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-04 | Initial comprehensive review |

---

*"MAINFRAME can make a computer do anything short of tap dance."*

**End of Document**

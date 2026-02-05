# MAINFRAME Function Cheatsheet

**Quick Reference for AI Coding Assistants**

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Category Reference Files

For detailed function signatures and examples, see the focused reference files:

| Category | File | Description |
|----------|------|-------------|
| **Core** | [docs/reference/core.md](docs/reference/core.md) | Strings, arrays, utils, files, common functions |
| **JSON** | [docs/reference/json.md](docs/reference/json.md) | JSON creation, parsing, USOP output, format bridge |
| **DateTime** | [docs/reference/datetime.md](docs/reference/datetime.md) | Date/time parsing, formatting, arithmetic |
| **HTTP** | [docs/reference/http.md](docs/reference/http.md) | HTTP client, downloads, network scanning |
| **CSV** | [docs/reference/csv.md](docs/reference/csv.md) | CSV parsing, reading, writing, format parsers |
| **Git** | [docs/reference/git.md](docs/reference/git.md) | Git repository operations |
| **GitHub** | [docs/reference/github.md](docs/reference/github.md) | GitHub API, Actions, Security |
| **Validation** | [docs/reference/validation.md](docs/reference/validation.md) | Input validation, sanitization, regex |
| **Process** | [docs/reference/process.md](docs/reference/process.md) | Process management, async, retry, timeout |
| **Docker** | [docs/reference/docker.md](docs/reference/docker.md) | Docker container/image management |
| **Crypto** | [docs/reference/crypto.md](docs/reference/crypto.md) | Cryptographic functions, hashing, encoding |
| **TUI** | [docs/reference/tui.md](docs/reference/tui.md) | Terminal UI, animations, colors |
| **Agent** | [docs/reference/agent.md](docs/reference/agent.md) | AI agent primitives: idempotent, atomic, diff, context |
| **Orchestration** | [docs/ORCHESTRATION.md](docs/ORCHESTRATION.md) | Multi-agent team coordination, TMUX, Redis pub/sub |
| **V10 Verification** | [docs/reference/verify.md](docs/reference/verify.md) | Pre-execution command verification |
| **V10 Intent** | [docs/reference/intent.md](docs/reference/intent.md) | Natural language to bash translation |
| **V10 Healing** | [docs/reference/heal.md](docs/reference/heal.md) | Self-healing error recovery |
| **V10 Prediction** | [docs/reference/predict.md](docs/reference/predict.md) | Resource prediction before execution |
| **V10 Graph** | [docs/reference/graph.md](docs/reference/graph.md) | DAG workflow execution |
| **V10 Temporal** | [docs/reference/temporal.md](docs/reference/temporal.md) | SQL-like history queries |
| **AWM** | [docs/reference/awm.md](docs/reference/awm.md) | Agent Working Memory |
| **Embeddings** | [docs/reference/embeddings.md](docs/reference/embeddings.md) | Embedding generation, semantic search |
| **RAG** | [docs/reference/rag.md](docs/reference/rag.md) | Retrieval-Augmented Generation pipeline |
| **Advanced** | [docs/reference/advanced.md](docs/reference/advanced.md) | Streaming, testing, sandbox, events, cloud |

---

## Most Common Functions

### JSON Creation
```bash
json_object name=John age:number=30 active:bool=true
# {"name":"John","age":30,"active":true}
```

### Validation
```bash
validate_email "$email" || die 1 "Invalid email"
validate_int "$port" 1 65535 || die 1 "Invalid port"
```

### Idempotent Operations
```bash
ensure_dir "/opt/myapp/logs" "0755"
ensure_file "/etc/app.conf" "key=value" "0644"
ensure_command "jq" || exit 1
```

### Surgical File Editing
```bash
diff_replace "config.ts" 'PORT = 3000' 'PORT = 8080' --backup
```

### Context Budget
```bash
context_budget_init --max-tokens 128000 --reserve 8000
context_budget_fits $(context_file_tokens "$file") && cat "$file"
```

### LLM Token Estimation & Cost
```bash
tokens=$(llm_count_tokens "$text" "gpt-4-turbo")
cost=$(llm_estimate_cost "$text" "claude-3-opus" input)
chunks=$(llm_split_chunks "$long_doc" 2000 "gpt-4" --overlap 100)
```

### Caching
```bash
result=$(memoize --ttl 300 http_get "https://api.example.com/data")
```

### Embeddings & Semantic Search
```bash
# Generate embedding (uses Ollama by default)
vec=$(embed_text "search query" "ollama")

# Calculate similarity between vectors
similarity=$(embed_similarity "$vec1" "$vec2")

# Get dimensions for provider
dims=$(embed_dimensions "openai")  # 1536
```

### RAG Pipeline
```bash
# Initialize RAG collection
rag_init "documents" --backend sqlite-vec --provider local

# Ingest documents (file, directory, or text)
rag_ingest "docs/" --collection "docs" --recursive
rag_ingest_file "readme.md" --collection "docs"
rag_ingest_text "Content to index" --id "doc1"

# Search and query
result=$(rag_search "search query" --top-k 5)
result=$(rag_query "How do I X?" --collection "docs")

# Chunk text for ingestion
chunks=$(rag_chunk_text "$text" --size 500 --overlap 50 --strategy sentence)

# Context augmentation
prompt=$(rag_augment_prompt "Question?" context_array)

# Collection stats
rag_stats "docs" --json
```

---

## V10 AI-Native Runtime

### Verification - Catch Errors Before Execution
```bash
# Check command for issues
result=$(verify_command "sl -la")
# Returns: {"valid":false,"issues":[{"type":"typo","suggestion":"ls -la"}]}

# Validate pipeline
verify_pipeline "cat file.txt | grep foo | wc -l"
# Returns: {"valid":true,"issues":[{"type":"style","message":"Useless use of cat"}]}

# Estimate resources
verify_estimate "find / -name '*.log'"
# Returns: {"estimates":{"time_s":45,"memory_mb":128,"confidence":"medium"}}
```

### Intent - Natural Language to Bash
```bash
# Parse natural language to structured intent
intent=$(intent_parse "find Python files modified today")
# Returns: {"action":"find","target":"files","type":"python","time":"today"}

# Convert intent to bash
bash_cmd=$(intent_to_bash "$intent")
# Returns: "find . -name '*.py' -mtime -1 -type f"

# Explain what code does
intent_explain "find . -name '*.py' -mtime -1"
# Returns: "Finds Python files modified in the last 24 hours"
```

### Healing - Self-Healing Execution
```bash
# Wrap commands with auto-healing
heal_wrap "deploy_to_prod.sh"
# Auto-retries, diagnoses errors, suggests fixes

# Diagnose errors
heal_diagnose "Permission denied"
# Returns: {"category":"permission","suggestions":[{"action":"sudo ...","confidence":0.95}]}

# Auto-fix common issues
heal_auto_fix "$error_output" --dry-run
```

### Prediction - Know Before You Run
```bash
# Predict resource usage
predict_resources "npm install"
# Returns: {"time_s":30,"memory_mb":512,"cpu_percent":60,"risk":"low"}

# Predict success probability
predict_success "docker build -t myapp ."
# Returns: 0.85 (85% chance of success)

# Get all predictions
predict_all "find /var -name '*.log'"
# Returns: {"time_s":45,"memory_mb":128,"risk":"medium","success_prob":0.92}
```

### Graph - Workflow Execution
```bash
# Define a workflow
graph_define "deploy"
graph_add_task "test" "npm test"
graph_add_task "build" "npm build"
graph_add_task "deploy" "rsync dist/ server:"
graph_add_dep "deploy" "build"
graph_add_dep "build" "test"

# Execute with auto-parallelization
graph_execute "deploy" --parallel 4

# Visualize
graph_visualize "deploy"
# Shows ASCII flowchart
```

### Temporal - Query Your History
```bash
# SQL-like queries
temporal_query "SELECT command, AVG(duration) FROM history WHERE exit_code = 0 GROUP BY command"

# Pattern detection
temporal_detect_pattern "commands that fail on Monday mornings"

# Anomaly detection
temporal_anomaly_detect
# Returns: "You usually use pytest, but today using python -m pytest"
```

### Agent Loop - Persistent Agents
```bash
# Start a background agent
agent_loop_start "refactor-auth" --goal "Refactor auth module" --priority 5

# Check status
agent_loop_status "refactor-auth"
# Returns: {"status":"running","elapsed":"2h15m","progress":"67%"}

# Pause/resume
agent_loop_pause "refactor-auth"
agent_loop_resume "refactor-auth" --context "focus on JWT"
```

---

## Function Lookup

```bash
mainframe quickref json      # List json.sh functions
mainframe quickref validate  # List validation.sh functions
mainframe quickref --search "hash"  # Search all functions
```

---

## Important Rules

1. **Do not read MAINFRAME source** - use functions directly
2. **Check reference files** for exact signatures
3. **Zero dependencies** - pure bash (openssl for HTTPS)
4. **Bash 4.0+ required**

---

## Reference Files

- **[docs/reference/README.md](docs/reference/README.md)** - Full category index
- **FUNCTIONS.json** - Machine-readable function index
- **DECISION_TREES.md** - "I need X" workflow guidance
- **ERRORS.json** - Error codes and recovery

---

*3,821+ functions | 152 libraries | Zero dependencies | 20-72x faster*

**YO JOE!**

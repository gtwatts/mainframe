# Intent Functions

Natural language to bash translation, command risk classification, intent verification, and safety analysis. Rule-based (no LLM required).

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## V10 Intent Parsing (intent.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `intent_parse` | `intent_parse "natural language" [--json]` | Parse natural language to structured intent. Returns action, target, pattern, time, path. |
| `intent_to_bash` | `intent_to_bash "intent_json" [--safe] [--json]` | Convert intent JSON to executable bash command. `--safe` adds guard checks. |
| `intent_explain` | `intent_explain "bash_code" [--json] [--verbose]` | Explain what bash code does in plain English with risk assessment. |
| `intent_complete` | `intent_complete "partial" [--json] [--max N]` | Auto-complete suggestions for partial commands or natural language. |

---

## Risk Classification

| Function | Signature | Description |
|----------|-----------|-------------|
| `intent_classify` | `intent_classify "command" [--json]` | Classify a command by risk level (0-4). Returns risk level as exit code. |
| `intent_verify` | `intent_verify "intent" "command" [--strict] [--base-path P] [--json]` | Verify command matches declared intent with path boundary checks. |
| `intent_sandbox_recommend` | `intent_sandbox_recommend "command" [--json]` | Recommend sandbox settings (dry_run, network, timeout, paths) based on risk. |
| `intent_dry_run` | `intent_dry_run "command" [--json]` | Simulate command execution without side effects. Shows operations and affected targets. |
| `intent_estimate_cost` | `intent_estimate_cost "command" [--json]` | Estimate I/O, CPU, and time impact for a command. |
| `intent_suggest_safer` | `intent_suggest_safer "command" [--json]` | Suggest safer alternatives to risky commands. |
| `intent_batch_verify` | `intent_batch_verify "cmd1" "cmd2" ... [--json] [--stop-on-critical]` | Verify multiple commands in batch. Returns aggregate safety assessment. |

---

## Risk Levels

| Level | Value | Label | Description |
|-------|-------|-------|-------------|
| `INTENT_RISK_SAFE` | 0 | safe | Read-only, reversible operations |
| `INTENT_RISK_LOW` | 1 | low | Minor side effects, easily reversible |
| `INTENT_RISK_MEDIUM` | 2 | medium | Moderate side effects, recoverable |
| `INTENT_RISK_HIGH` | 3 | high | Significant changes, hard to reverse |
| `INTENT_RISK_CRITICAL` | 4 | critical | Destructive, irreversible, privileged |

---

## Usage Examples

```bash
# Parse natural language
intent_parse "find all Python files modified today" --json
# {"action":"find","target":"files","operation":"list","path":".","pattern":"*.py","time":"today","file_type":"python"}

# Convert to bash
intent_to_bash '{"action":"find","pattern":"*.py","time":"today"}' --safe
# find . -name '*.py' -type f -mtime -1

# Classify risk
intent_classify "rm -rf /tmp/cache" --json
# {"command":"rm -rf /tmp/cache","risk":3,"risk_label":"high","reasons":[...]}

# Verify intent matches command
intent_verify "delete temp files" "rm -rf /tmp/cache" --json
# {"verified":true,"confidence":0.9,...}

# Explain code
intent_explain "find . -name '*.py' -mtime -1" --json
# {"summary":"Search for files matching criteria","details":[...],"risk":0}

# Dry run
intent_dry_run "rm -rf /tmp/old" --json
# {"dry_run":true,"operations":["delete"],"would_affect":["/tmp/old"],"risk":3}

# Batch verify
echo -e "ls -la\nrm -rf /tmp" | intent_batch_verify --json
# {"total":2,"max_risk":3,"summary":{"safe":1,"high":1},...}
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MAINFRAME_INTENT_STRICT` | `0` | Require explicit approval for medium+ risk |
| `MAINFRAME_INTENT_RULES` | `~/.mainframe/intent_rules.json` | Custom rules file path |
| `MAINFRAME_INTENT_BLOCKED` | (empty) | Comma-separated blocked command patterns |

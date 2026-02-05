# Temporal Functions

SQL-like temporal database for command history analysis - queries, pattern detection, anomaly detection, and prediction. Supports SQLite (fast) and pure Bash (fallback) backends.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Data Recording (temporal.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `temporal_record` | `temporal_record --cwd "$PWD" --command "$cmd" --exit_code $code --duration_ms $ms [--output_lines N] [--session_id "..."] [--git_branch "..."]` | Record a command execution with metadata. Automatically sanitizes secrets and trims old entries. |

---

## Query Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `temporal_query` | `temporal_query "SQL_query"` | Execute SQL-like query against history. Supports time expressions (`today`, `yesterday`, `2 hours ago`). |
| `temporal_select` | `temporal_select "columns" --from "history" --where "conditions" [--order "col"] [--limit N]` | Structured query interface with named parameters. |
| `temporal_aggregate` | `temporal_aggregate "AVG(duration_ms)" [--group_by "command"]` | Run aggregate queries (AVG, COUNT, SUM, etc.) with optional grouping. |

---

## Pattern Detection

| Function | Signature | Description |
|----------|-----------|-------------|
| `temporal_detect_pattern` | `temporal_detect_pattern "description"` | Detect patterns: command sequences, time-based patterns, failure patterns. Description keywords trigger different detectors. |
| `temporal_find_similar` | `temporal_find_similar "command"` | Find similar commands in history using Jaro-Winkler fuzzy matching. |
| `temporal_frequency_analysis` | `temporal_frequency_analysis` | Analyze command frequency, average duration, and success rate for top commands. |

---

## Anomaly Detection

| Function | Signature | Description |
|----------|-----------|-------------|
| `temporal_anomaly_detect` | `temporal_anomaly_detect [--sensitivity low\|medium\|high]` | Detect anomalies in recent behavior (unusual commands in directory, timing deviations). |
| `temporal_outliers` | `temporal_outliers ["metric"]` | Find statistical outliers (>2 std dev) in duration or other metrics over last 7 days. |

---

## Prediction

| Function | Signature | Description |
|----------|-----------|-------------|
| `temporal_predict_success` | `temporal_predict_success "command"` | Predict success probability based on historical success rate for similar commands. |
| `temporal_predict_duration` | `temporal_predict_duration "command"` | Predict execution duration based on historical averages with standard deviation. |
| `temporal_recommend` | `temporal_recommend "goal"` | Recommend commands for a goal based on what works in the current directory. |

---

## Statistics and Maintenance

| Function | Signature | Description |
|----------|-----------|-------------|
| `temporal_stats` | `temporal_stats` | Get module statistics: backend, total entries, unique commands, date range, storage path. |
| `temporal_clear` | `temporal_clear --confirm` | Clear all temporal data. Requires `--confirm` flag. |

---

## Usage Examples

```bash
# Record a command execution
temporal_record --cwd "$PWD" --command "npm test" --exit_code 0 --duration_ms 12500

# SQL-like queries
temporal_query "SELECT command, AVG(duration_ms) FROM history WHERE exit_code = 0 GROUP BY command"

# Structured select
temporal_select "command, duration_ms" --from "history" --where "exit_code = 0" --order "duration_ms DESC" --limit 10

# Detect command sequences
temporal_detect_pattern "commands that often run together"
# {"patterns":["git add -> git commit -> git push"],"type":"sequence","confidence":0.85}

# Find similar commands
temporal_find_similar "git comit"
# {"target":"git comit","similar":[{"command":"git commit","count":42}]}

# Anomaly detection
temporal_anomaly_detect --sensitivity high
# {"anomalies":["You usually use 'pytest' in this directory but recently used 'python -m pytest'"],...}

# Predict success
temporal_predict_success "docker build ."
# {"success_probability":0.92,"confidence":"high","similar_past_commands":35}

# Predict duration
temporal_predict_duration "npm install"
# {"predicted_ms":45000,"stddev_ms":12000,"confidence":"medium","based_on":8}

# Get recommendations
temporal_recommend "deploy the app"
# {"goal":"deploy the app","goal_type":"deploy","recommendations":[...]}

# Module stats
temporal_stats
# {"backend":"sqlite","total_entries":1523,"unique_commands":89,...}
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TEMPORAL_ROOT` | `~/.mainframe/temporal` | Storage root for temporal data |
| `TEMPORAL_MAX_ENTRIES` | `10000` | Maximum entries (auto-trims oldest) |
| `TEMPORAL_CACHE_TTL` | `60` | Query cache TTL in seconds |
| `TEMPORAL_ANOMALY_SENSITIVITY` | `medium` | Anomaly detection sensitivity (low/medium/high) |
| `TEMPORAL_BACKEND` | `auto` | Backend preference: auto, sqlite, bash |

## Backends

| Backend | Requirements | Features |
|---------|-------------|----------|
| `sqlite` | sqlite3 in PATH | Full SQL queries, WAL mode, indexes, aggregates |
| `bash` | None (pure bash) | Basic queries, TSV storage, simple filtering |

Auto-detection selects SQLite when available, falling back to pure Bash.

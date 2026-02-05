# Temporal Database Module

The `temporal.sh` module provides SQL-like temporal queries, pattern detection, anomaly detection, and prediction for command execution history.

## Overview

- **Backend Support**: SQLite (fast) with graceful fallback to pure Bash
- **Storage**: Command history with metadata (duration, exit code, cwd, etc.)
- **USOP Compliant**: All functions return structured JSON output

## Quick Start

```bash
source "$MAINFRAME_ROOT/lib/temporal.sh"

# Record a command execution
temporal_record \
    --cwd "$PWD" \
    --command "npm test" \
    --exit_code 0 \
    --duration_ms 4500

# Query history
result=$(temporal_query "SELECT * FROM history WHERE exit_code = 0")

# Get predictions
result=$(temporal_predict_success "npm test")
```

## Data Model

Each command execution stores:
```json
{
  "id": "uuid",
  "timestamp": "2024-01-15T10:30:00Z",
  "cwd": "/home/user/project",
  "command": "npm test",
  "exit_code": 0,
  "duration_ms": 4500,
  "output_lines": 150,
  "output_size_bytes": 45000,
  "env_hash": "sha256ofrelevantenv",
  "system_load": {"cpu": 45, "mem": 60},
  "session_id": "ammma_session_abc",
  "git_branch": "feature/auth",
  "success": true
}
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TEMPORAL_ROOT` | `~/.mainframe/temporal` | Storage directory |
| `TEMPORAL_MAX_ENTRIES` | 10000 | Auto-trim threshold |
| `TEMPORAL_BACKEND` | `auto` | Backend preference (auto/sqlite/bash) |
| `TEMPORAL_ANOMALY_SENSITIVITY` | `medium` | Anomaly detection threshold |

## API Reference

### Data Storage

#### `temporal_record`
Record a command execution.

```bash
temporal_record \
    --cwd "$PWD" \
    --command "npm test" \
    --exit_code 0 \
    --duration_ms 4500 \
    [--output_lines N] \
    [--output_size_bytes N] \
    [--session_id "..."] \
    [--git_branch "..."]
```

### Querying

#### `temporal_query`
Execute SQL-like query.

```bash
temporal_query "SELECT command, AVG(duration_ms) FROM history WHERE exit_code = 0"
```

#### `temporal_select`
Structured select interface.

```bash
temporal_select "columns" --from "history" --where "conditions" --limit 10
```

#### `temporal_aggregate`
Aggregate functions with grouping.

```bash
temporal_aggregate "AVG(duration_ms)" --group_by "command"
```

### Pattern Detection

#### `temporal_detect_pattern`
Detect patterns in command history.

```bash
# Find common command sequences
temporal_detect_pattern "commands that often run together"

# Returns: {"patterns": [...], "type": "sequence", "confidence": 0.85}
```

#### `temporal_find_similar`
Find similar commands.

```bash
temporal_find_similar "pytest"
# Returns: {"target": "pytest", "similar": [{"command": "...", "count": N}]}
```

#### `temporal_frequency_analysis`
Analyze command frequency.

```bash
temporal_frequency_analysis
# Returns: [{"command": "...", "frequency": N, "avg_duration": M}]
```

### Anomaly Detection

#### `temporal_anomaly_detect`
Detect unusual behavior.

```bash
temporal_anomaly_detect [--sensitivity low|medium|high]
```

#### `temporal_outliers`
Find duration outliers.

```bash
temporal_outliers "duration_ms"
```

### Prediction

#### `temporal_predict_success`
Predict command success probability.

```bash
temporal_predict_success "npm test"
# Returns: {"success_probability": 0.85, "confidence": "high", ...}
```

#### `temporal_predict_duration`
Predict command duration.

```bash
temporal_predict_duration "docker build"
# Returns: {"predicted_ms": 45000, "confidence": 0.80, ...}
```

#### `temporal_recommend`
Recommend commands for a goal.

```bash
temporal_recommend "deploy the app"
# Returns: {"goal": "...", "recommendations": [...]}
```

### Utilities

#### `temporal_stats`
Get database statistics.

```bash
temporal_stats
```

#### `temporal_clear`
Clear all temporal data.

```bash
temporal_clear --confirm
```

## Query Language

The module supports SQL-like syntax:

```bash
# Simple queries
temporal_query "SELECT * FROM history WHERE exit_code = 0"
temporal_query "SELECT command, COUNT(*) FROM history GROUP BY command"

# Time-based
temporal_query "SELECT * WHERE timestamp > '2 hours ago'"
temporal_query "SELECT * WHERE cwd LIKE '%/mainframe'"

# Aggregations
temporal_query "SELECT AVG(duration_ms) FROM history"
```

## Examples

See `examples/temporal_demo.sh` for a complete working example.

## Performance

| Backend | Query 10K commands | Notes |
|---------|-------------------|-------|
| SQLite | <100ms | Requires sqlite3 CLI |
| Bash | <2s | Pure bash, always works |

## Testing

```bash
bash tests/temporal_test.sh
```

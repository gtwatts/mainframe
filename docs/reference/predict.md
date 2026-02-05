# Prediction Functions

Command execution prediction engine - predicts resource usage, risk levels, success probability, and execution duration using command profiling, pattern analysis, and historical data.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Public API (predict.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `predict_resources` | `predict_resources "command"` | Predict time, memory, CPU, disk usage, and scalability. Uses command profiles blended with historical data from temporal.sh. |
| `predict_risk` | `predict_risk "command"` | Assess risk level (0-10) with categorization (low/medium/high/critical), reasons, and confirmation/block thresholds. |
| `predict_success` | `predict_success "command"` | Predict success probability (0.0-1.0) based on historical success rate, risk level, and command patterns. |
| `predict_duration` | `predict_duration "command"` | Predict execution time with min/max range and confidence level. Blends profile data with historical averages. |
| `predict_all` | `predict_all "command"` | Run all predictions (resources, risk, success, duration) and return combined JSON. |

---

## Risk Categories

| Score | Category | Description |
|-------|----------|-------------|
| 8-10 | critical | `rm -rf /`, fork bombs, disk format, filesystem wipe |
| 6-7 | high | Recursive deletion, sudo, kill -9, service stops, SSH key ops |
| 3-5 | medium | Package installs, find, eval, git force push, in-place sed |
| 0-2 | low | Read-only operations, simple commands |

---

## Command Profiles

Built-in resource profiles for 100+ commands including:

- **Read-only**: ls, cat, grep, wc, head, tail, echo, pwd, date
- **File operations**: cp, mv, rm, mkdir, chmod, dd
- **Search**: find, locate, updatedb
- **Archives**: tar, gzip, zip, bzip2, xz
- **Version control**: git (clone, push, pull, status, log)
- **Build systems**: make, cmake, gcc, cargo, go, javac, python, node
- **Package managers**: npm, pip, yarn, bun, gem, bundle
- **Containers**: docker (build, run, compose), kubectl, helm
- **Databases**: mysql, psql, mongo, redis-cli, sqlite3
- **Test runners**: pytest, jest, mocha, vitest, cypress, playwright

---

## Usage Examples

```bash
# Predict resources
predict_resources "npm install"
# {"command":"npm install","time_seconds":60.0,"memory_mb":300,"cpu_percent":60,"disk_usage":"medium","confidence":"medium"}

# Assess risk
predict_risk "rm -rf /tmp/cache"
# {"command":"rm -rf /tmp/cache","risk_category":"high","risk_score":6,"reasons":["Recursive deletion"],...}

# Predict success
predict_success "docker build -t myapp ."
# {"command":"docker build -t myapp .","probability":0.85,"confidence":"medium","factors":[...]}

# Predict duration
predict_duration "find / -name '*.log'"
# {"command":"find / -name '*.log'","predicted_seconds":10.0,"min_seconds":5.0,"max_seconds":20.0,"confidence":"medium"}

# All predictions at once
predict_all "cargo build --release"
# {"command":"cargo build --release","resources":{...},"risk":{...},"success":{...},"duration":{...}}
```

---

## Confidence Levels

| Level | Description | Source |
|-------|-------------|--------|
| `high` | 10+ historical samples, strong data | Historical data primary |
| `medium` | 3-10 samples or known command profile | Blended profile + history |
| `low` | Unknown command or fewer than 3 samples | Profile estimate only |

## Profile Adjustments

Predictions are adjusted based on command arguments:
- **Recursive flags** (`-r`, `-R`, `--recursive`): 5x time multiplier
- **Root filesystem paths** (`find /`): 10x time multiplier
- **Parallel flags** (`-P`, `--parallel`): 0.3x time, 3x CPU
- **Wildcard patterns**: 2x time multiplier
- **Exec operations** (`find -exec`): 3x additional multiplier

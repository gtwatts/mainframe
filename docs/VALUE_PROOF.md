# MAINFRAME v6.0 Value Proof: Measurable Token & Speed Savings

> **Historical research only — not current product evidence.**
>
> This v6.0 draft is retained for repository provenance. Its benchmark figures,
> function and test counts, token/productivity percentages, sample claims, and
> agent-outcome conclusions were not validated under the current
> [claims policy](CLAIMS_AND_BENCHMARKS.md). Do not use them as release,
> compatibility, or marketing claims.
>
> Original draft subtitle: “Quantified evidence that MAINFRAME speeds up
> production and saves tokens.”

## Executive Summary

| Metric | Without MAINFRAME | With MAINFRAME | Improvement |
|--------|-------------------|----------------|-------------|
| **Lines of code per task** | 15-25 lines | 1-3 lines | **85-95% reduction** |
| **Tokens per bash task** | 150-300 tokens | 20-60 tokens | **70-80% savings** |
| **First-run success rate** | ~65-70% | ~95%+ | **+25-30%** |
| **Execution speed** | Baseline | 20-72x faster | **Significant** |
| **Context window efficiency** | N/A | AWM external memory | **Unlimited state** |

**MAINFRAME v6.0**: 4,000+ functions | 117 libraries | 6,500+ tests | Agent Working Memory

---

## Token Savings: Side-by-Side Comparisons

### Example 1: JSON Object Creation

**Without MAINFRAME** (~180 tokens):
```bash
# AI assistant must write this from scratch
create_json() {
    local name="$1"
    local age="$2"
    local active="$3"

    # Manual string building with escaping
    local json="{"
    json+="\"name\":\"$(echo "$name" | sed 's/"/\\"/g')\","
    json+="\"age\":$age,"
    json+="\"active\":$active"
    json+="}"
    echo "$json"
}

result=$(create_json "John Doe" 30 true)
```

**With MAINFRAME** (~25 tokens):
```bash
source "$MAINFRAME_ROOT/lib/common.sh"
json_object "name=John Doe" "age:number=30" "active:bool=true"
```

**Token Savings: ~155 tokens (86%)**

---

### Example 2: Array Manipulation (Unique + Sort + Join)

**Without MAINFRAME** (~200 tokens):
```bash
# Remove duplicates, sort, and join array
items=("banana" "apple" "cherry" "apple" "date" "banana")

# Manual deduplication
declare -A seen
unique=()
for item in "${items[@]}"; do
    if [[ -z "${seen[$item]:-}" ]]; then
        seen[$item]=1
        unique+=("$item")
    fi
done

# Sort using process substitution
IFS=$'\n' sorted=($(printf "%s\n" "${unique[@]}" | sort))
unset IFS

# Join with comma
result=""
for i in "${!sorted[@]}"; do
    [[ $i -gt 0 ]] && result+=","
    result+="${sorted[$i]}"
done
echo "$result"
```

**With MAINFRAME** (~40 tokens):
```bash
source "$MAINFRAME_ROOT/lib/common.sh"
items=("banana" "apple" "cherry" "apple" "date" "banana")
array_join "," $(array_sort $(array_unique "${items[@]}"))
```

**Token Savings: ~160 tokens (80%)**

---

### Example 3: HTTP Request with Retry and Timeout

**Without MAINFRAME** (~280 tokens):
```bash
# HTTP GET with retry logic, timeout, and error handling
max_retries=3
timeout_seconds=10
url="https://api.example.com/data"
delay=1

for ((attempt=1; attempt<=max_retries; attempt++)); do
    echo "Attempt $attempt of $max_retries..."

    response=$(curl -sf --max-time "$timeout_seconds" "$url" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "Success: $response"
        break
    fi

    echo "Failed with exit code $exit_code"

    if [[ $attempt -lt $max_retries ]]; then
        echo "Waiting ${delay}s before retry..."
        sleep "$delay"
        delay=$((delay * 2))  # Exponential backoff
    else
        echo "All attempts failed"
        exit 1
    fi
done
```

**With MAINFRAME** (~50 tokens):
```bash
source "$MAINFRAME_ROOT/lib/common.sh"
retry --max-attempts 3 --backoff exponential -- \
    http_get "https://api.example.com/data"
```

**Token Savings: ~230 tokens (82%)**

---

### Example 4: Date Arithmetic

**Without MAINFRAME** (~150 tokens):
```bash
# Add 7 days to current date, format as ISO
current=$(date +%s)
seven_days=$((7 * 24 * 60 * 60))
future=$((current + seven_days))

# Format as ISO-8601
if [[ "$OSTYPE" == "darwin"* ]]; then
    result=$(date -r "$future" +%Y-%m-%dT%H:%M:%S%z)
else
    result=$(date -d "@$future" +%Y-%m-%dT%H:%M:%S%z)
fi
echo "$result"
```

**With MAINFRAME** (~30 tokens):
```bash
source "$MAINFRAME_ROOT/lib/common.sh"
date_add $(now) "7d" | format_iso
```

**Token Savings: ~120 tokens (80%)**

---

### Example 5: Path Validation (Security Critical)

**Without MAINFRAME** (~220 tokens):
```bash
# Validate user-provided path is safe (no traversal)
validate_path() {
    local path="$1"
    local base="$2"

    # Normalize paths
    local real_base=$(cd "$base" && pwd -P)
    local real_path=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")

    # Check if starts with base
    if [[ "$real_path" != "$real_base"* ]]; then
        echo "Error: Path traversal detected" >&2
        return 1
    fi

    # Check for dangerous characters
    if [[ "$path" =~ [[:cntrl:]] ]] || [[ "$path" == *".."* ]]; then
        echo "Error: Dangerous path characters" >&2
        return 1
    fi

    return 0
}

validate_path "$user_input" "/safe/base"
```

**With MAINFRAME** (~35 tokens):
```bash
source "$MAINFRAME_ROOT/lib/common.sh"
validate_path_safe "$user_input" "/safe/base" || {
    log_error "Path validation failed"
    exit 1
}
```

**Token Savings: ~185 tokens (84%)**

---

## Aggregate Token Savings

| Task Category | Avg Without | Avg With | Savings |
|---------------|-------------|----------|---------|
| JSON operations | 180 tokens | 25 tokens | **86%** |
| Array manipulation | 200 tokens | 40 tokens | **80%** |
| HTTP/Network | 280 tokens | 50 tokens | **82%** |
| Date/Time | 150 tokens | 30 tokens | **80%** |
| Path validation | 220 tokens | 35 tokens | **84%** |
| String operations | 120 tokens | 20 tokens | **83%** |
| Process management | 180 tokens | 40 tokens | **78%** |
| Environment handling | 140 tokens | 25 tokens | **82%** |
| **AVERAGE** | **184 tokens** | **33 tokens** | **82%** |

---

## Speed Benchmarks

From `benchmarks/superpower_benchmarks.sh` and library tests:

| Operation | External Tool | MAINFRAME | Speedup |
|-----------|---------------|-----------|---------|
| String trim | `sed` | `trim_string` | **36x faster** |
| JSON creation | `jq` | `json_object` | **72x faster** |
| Array unique | `sort -u` | `array_unique` | **20x faster** |
| Path normalize | multiple cmds | `path_normalize` | **45x faster** |
| Base64 encode | `base64` command | `base64_encode` | **28x faster** |

### Why So Fast?

1. **Zero subprocess overhead** - Pure bash means no fork/exec
2. **No external binary loading** - `jq`, `sed`, `awk` each add ~5-15ms startup
3. **Native bash data structures** - Associative arrays, indexed arrays built-in
4. **Compiled builtins** - `${var//pattern/replacement}` is native C code

---

## Success Rate Improvement

### Common Failure Modes Prevented

| Failure Type | Without MAINFRAME | With MAINFRAME | Prevention Rate |
|--------------|-------------------|----------------|-----------------|
| Unquoted paths with spaces | 95% fail | 0% fail | **100%** |
| Word splitting issues | 80% fail | 0% fail | **100%** |
| Missing error handling | 70% silent fail | 5% fail | **93%** |
| JSON syntax errors | 60% malformed | 2% malformed | **97%** |
| Network timeout hangs | 40% hang | 0% hang | **100%** |
| Path traversal vulnerabilities | 85% vulnerable | 0% vulnerable | **100%** |

### Measured First-Run Success Rate

Based on 500 bash task samples:

| Approach | First Run Success | Requires Retry |
|----------|-------------------|----------------|
| AI-generated raw bash | 68% | 32% |
| MAINFRAME functions | 96% | 4% |
| **Improvement** | **+28%** | **-28%** |

---

## Real-World Impact: AI Assistant Productivity

### Scenario: Build a CLI Tool

**Without MAINFRAME** - AI must:
1. Write argument parsing (~50 tokens)
2. Write validation logic (~80 tokens)
3. Write JSON output handling (~60 tokens)
4. Write error handling (~40 tokens)
5. Debug failures, retry 2-3 times (~150 tokens)

**Total: ~380 tokens, 3-4 attempts**

**With MAINFRAME** - AI writes:
```bash
source "$MAINFRAME_ROOT/lib/common.sh"
validate_args "$@"
result=$(json_object "status=success" "data:object=$output")
echo "$result"
```

**Total: ~60 tokens, 1 attempt**

### Token Savings per Session

| Session Type | Without | With MAINFRAME | Savings |
|--------------|---------|----------------|---------|
| Simple script | 500 tokens | 150 tokens | 70% |
| Complex automation | 2,000 tokens | 500 tokens | 75% |
| Error debugging | 800 tokens | 100 tokens | 88% |
| **Daily average** | **3,300 tokens** | **750 tokens** | **77%** |

---

## How to Verify These Claims

### 1. Run Token Comparison Test

```bash
# Compare token counts for equivalent functionality
./tests/token_comparison.sh
```

### 2. Run Speed Benchmarks

```bash
./tests/benchmark.sh
# Results in: benchmark_results/benchmark_*.md
```

### 3. Run Success Rate Test

```bash
# Test MAINFRAME functions vs raw bash equivalents
./tests/bats/bin/bats tests/unit/
# Should show 6,500+ tests passing
```

### 4. Measure Real Usage

Track your own sessions:
- Count tokens spent on bash tasks with/without MAINFRAME
- Track first-run success vs retry needed
- Note time spent debugging vs productive coding

---

## Agent Working Memory (AWM) Value

**The hidden cost of context window churn:**

| Scenario | Without AWM | With AWM | Savings |
|----------|-------------|----------|---------|
| **Session resume** | Re-explain everything (~500 tokens) | `awm_resume "$sid"` (50 tokens) | **90%** |
| **Sub-agent handoff** | Copy/paste context (~1000 tokens) | `awm_inherit "$parent"` (20 tokens) | **98%** |
| **Progress tracking** | Manual state management (~200 tokens) | `awm_progress` (10 tokens) | **95%** |
| **Discovery retention** | Lost at context limit | Persisted forever | **Infinite** |

AWM enables **truly autonomous multi-turn agent workflows** by storing state outside the context window.

---

## Conclusion

MAINFRAME provides **measurable, quantifiable value**:

| Metric | Value |
|--------|-------|
| **Token savings per bash task** | 70-85% (avg 82%) |
| **Lines of code reduction** | 85-95% |
| **Speed improvement** | 20-72x faster |
| **First-run success rate** | 68% → 96% (+28%) |
| **Daily token savings** | ~2,500 tokens |
| **Functions available** | 4,000+ |
| **Test coverage** | 6,500+ tests |

### ROI Calculation

If you spend $0.01 per 1K tokens and average 10 bash tasks/day:

- **Without MAINFRAME**: 184 tokens × 10 tasks × 1.3 retries = 2,392 tokens/day
- **With MAINFRAME**: 33 tokens × 10 tasks × 1.04 retries = 343 tokens/day
- **Daily savings**: 2,049 tokens = **$0.02/day** or **~$7.50/year**

The real value isn't just cost - it's **time saved** and **frustration avoided**.

With AWM, the value compounds: agents maintain state across sessions, sub-agents inherit discoveries, and context windows are used efficiently.

---

*"Knowing your shell is half the battle."* **YO JOE!**

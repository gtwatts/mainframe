# MAINFRAME v6.0 Pipeline Paradigms

> "The power of the shell is in the pipe." - Doug McIlroy

This document covers the lethal shell pipeline patterns available in MAINFRAME v6.0.

**MAINFRAME v6.0**: 4,000+ functions | 117 libraries | 6,500+ tests

## Philosophy

Every function follows the Unix philosophy:
1. **Read from stdin OR args** - Functions accept input either way
2. **Write to stdout** - Output is always pipeable
3. **Do one thing well** - Functions are composable primitives
4. **Fail silently or clearly** - Predictable error handling

## Quick Reference

### Basic Pipeline (pipe.sh)

| Function | Purpose | Example |
|----------|---------|---------|
| `pipe_map` | Transform each line | `\| pipe_map 'tr a-z A-Z'` |
| `pipe_filter` | Keep matching lines | `\| pipe_filter '^[0-9]'` |
| `pipe_reject` | Remove matching lines | `\| pipe_reject 'error'` |
| `pipe_reduce` | Accumulate to single value | `\| pipe_reduce 'expr $acc + $line' 0` |
| `pipe_take` | First N lines | `\| pipe_take 10` |
| `pipe_drop` | Skip first N lines | `\| pipe_drop 5` |
| `pipe_unique` | Remove duplicates | `\| pipe_unique` |
| `pipe_field` | Extract column | `\| pipe_field 2 ':'` |
| `pipe_join` | Join lines with delimiter | `\| pipe_join ','` |
| `pipe_split` | Split line to multiple | `\| pipe_split ','` |

### Advanced Stream (stream.sh)

| Function | Purpose | Example |
|----------|---------|---------|
| `stream_records` | Process multi-line records | `\| stream_records '---' 'wc -l'` |
| `stream_blocks` | Fixed-size line blocks | `\| stream_blocks 3 'paste -sd,'` |
| `stream_window` | Sliding window | `\| stream_window 5 1` |
| `stream_fanout` | Parallel processing | `\| stream_fanout 'cmd1' 'cmd2'` |
| `stream_group_by` | Group and aggregate | `\| stream_group_by 1 ':' 'sum'` |

---

## Paradigm Matrix

### 1. Filter → Transform → Aggregate

The most common pattern:

```bash
# Count unique error types from log
cat /var/log/app.log \
  | pipe_filter 'ERROR' \
  | pipe_field 3 ' ' \
  | pipe_unique \
  | pipe_count
```

### 2. Extract → Enrich → Output

Pull data, add context, format:

```bash
# Extract IPs, add geolocation, format as CSV
cat access.log \
  | pipe_field 1 ' ' \
  | pipe_unique \
  | pipe_map 'geoiplookup {}' \
  | pipe_wrap '"' '"' \
  | pipe_join ','
```

### 3. Split → Process → Merge

Divide work, process in parallel:

```bash
# Process chunks in parallel
cat huge_file.txt \
  | stream_blocks 1000 'process_chunk.sh' \
  | pipe_join $'\n'
```

### 4. Window → Analyze → Alert

Streaming analytics:

```bash
# Detect anomalies in sliding window
tail -f metrics.log \
  | pipe_field 2 ' ' \
  | stream_window 10 1 \
  | pipe_map 'calculate_stddev' \
  | pipe_filter '^[3-9]' \
  | pipe_prepend 'ALERT: '
```

### 5. State Machine

Track state through stream:

```bash
# Parse nested JSON-like structure
cat data.txt \
  | stream_depth '{' '}' \
  | pipe_filter '^[2-9]' \  # Only depth 2+
  | pipe_field 2
```

---

## Lethal Combinations

### Log Analysis Pipeline

```bash
# Top 10 error sources with context
cat /var/log/*.log \
  | pipe_filter 'ERROR|FATAL' \
  | pipe_field 1-3 ' ' \
  | pipe_group_count \
  | stream_top 10 1 $'\t' \
  | pipe_number 1 '%2d. '
```

### Data Transformation Matrix

```bash
# CSV to JSON array
cat data.csv \
  | pipe_drop 1 \                        # Skip header
  | pipe_map 'echo "{\"name\":\"$(cut -d, -f1 <<<\$line)\",\"value\":$(cut -d, -f2 <<<\$line)}"' \
  | pipe_wrap '' ',' \
  | pipe_join '' \
  | pipe_wrap '[' ']'
```

### Real-time Monitoring

```bash
# Monitor file changes with rate limiting
inotifywait -m /path -e create,modify \
  | pipe_field 3 ' ' \
  | stream_debounce 2 \
  | pipe_map 'process_file'
```

### Parallel Processing with Aggregation

```bash
# Process files in parallel, merge results
find . -name "*.log" \
  | stream_distribute 4 'analyze_log.sh' \
  | stream_merge /dev/stdin \
  | pipe_unique \
  | pipe_count
```

---

## Pattern Recipes

### Recipe: Extract Email Addresses

```bash
cat document.txt | stream_extract '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
```

### Recipe: Sum Column in CSV

```bash
cat data.csv | pipe_field 3 ',' | pipe_sum
```

### Recipe: Filter and Paginate

```bash
cat large_file.txt | pipe_filter 'pattern' | pipe_drop $((PAGE * 20)) | pipe_take 20
```

### Recipe: Group by Hour

```bash
cat access.log \
  | pipe_field 4 ' ' \
  | pipe_map 'cut -c1-14' \
  | pipe_group_count \
  | pipe_sort -k2
```

### Recipe: JSON Lines to CSV

```bash
cat data.jsonl \
  | pipe_map 'jq -r "[.name, .value] | @csv"' \
  | pipe_prepend 'name,value' --once
```

### Recipe: Diff Two Commands

```bash
diff <(cmd1 | pipe_sort) <(cmd2 | pipe_sort) | pipe_filter '^[<>]'
```

### Recipe: Retry with Backoff

```bash
stream_retry 3 'curl -sf https://api.example.com/data'
```

---

## Composition Patterns

### The Tee Pattern (Inspect Without Breaking)

```bash
cat data.txt \
  | pipe_peek '[DEBUG]' \
  | pipe_map 'process' \
  | pipe_peek '[RESULT]'
```

### The Branch Pattern (Route by Condition)

```bash
cat mixed_data.txt | stream_branch '^ERROR' errors.txt success.txt
```

### The Fan-Out Pattern (Multiple Outputs)

```bash
echo "data" | stream_fanout \
  'wc -c > /tmp/size.txt' \
  'md5sum > /tmp/hash.txt' \
  'gzip > /tmp/data.gz'
```

### The Accumulator Pattern

```bash
# Running total
cat numbers.txt | pipe_reduce 'echo $((acc + line))' 0
```

### The Session Pattern (Group by Gaps)

```bash
# Group events separated by blank lines
cat events.log | stream_paragraphs 'process_session'
```

---

## Performance Tips

1. **Use native bash when possible** - `pipe_upper` is faster than `| tr a-z A-Z` for small data
2. **Buffer for large streams** - `stream_buffer 1000` reduces syscalls
3. **Parallelize CPU-bound work** - `stream_distribute` for heavy processing
4. **Early filtering** - `pipe_filter` first to reduce downstream volume
5. **Avoid subshells in hot loops** - Prefer parameter expansion over command substitution

---

## Debugging Pipelines

### Inspect at any point:

```bash
cat data | cmd1 | pipe_peek | cmd2 | pipe_peek | cmd3
```

### Count at each stage:

```bash
cat data | tee >(wc -l >&2) | cmd1 | tee >(wc -l >&2) | cmd2
```

### Assert non-empty:

```bash
cat data | cmd1 | pipe_assert_nonempty "Stage 1 produced no output"
```

---

---

## AWM Pipeline Integration

Agent Working Memory (AWM) integrates with pipelines for persistent logging:

```bash
# Log pipeline progress to AWM
cat large_file.txt \
  | pipe_filter 'pattern' \
  | tee >(wc -l | xargs -I{} awm_progress "filter" {} 0) \
  | pipe_map 'process' \
  | tee >(awm_log "info" "Processing complete")
```

```bash
# Checkpoint intermediate results
session_id=$(awm_init)
result=$(cat data.csv | pipe_field 2 ',' | pipe_sum)
awm_checkpoint "sum_result" "$result"
```

---

## See Also

- `lib/pipe.sh` - Core pipeline functions
- `lib/stream.sh` - Advanced streaming paradigms
- `lib/csv.sh` - CSV-specific processing
- `lib/json.sh` - JSON generation
- `lib/awm.sh` - Agent Working Memory for persistent state

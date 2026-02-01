# MAINFRAME Benchmarks

Performance benchmark suites for MAINFRAME library functions.

## Quick Start

```bash
# Run JSON function benchmarks
./json_functions.bench.sh [iterations] [output_dir]

# Run validation function benchmarks
./validation_functions.bench.sh [iterations] [output_dir]
```

## Available Suites

| Suite | Description | Functions Tested |
|-------|-------------|------------------|
| `json_functions.bench.sh` | JSON library performance | json_object, json_array, json_escape, json_pretty, etc. |
| `validation_functions.bench.sh` | Validation library performance | validate_email, validate_url, sanitize_*, etc. |

## Output Format

Results are saved as JSON files with the following structure:

```json
{
  "name": "json_object_simple",
  "iterations": 100,
  "warmup": 5,
  "stats": {
    "mean_ms": 12.5,
    "median_ms": 11.0,
    "stddev_ms": 2.3,
    "min_ms": 9.0,
    "max_ms": 22.0,
    "p95_ms": 16.2,
    "p99_ms": 18.5,
    "outliers": 1,
    "ci_lower_ms": 11.2,
    "ci_upper_ms": 13.8
  },
  "timestamp": "2026-02-01T12:00:00Z",
  "platform": "Linux 6.x"
}
```

## Regression Testing

Compare current results against a baseline:

```bash
# Run benchmarks and save as new baseline
./json_functions.bench.sh 100 ./baseline

# Later, compare against baseline
source ../lib/benchmark.sh
benchmark_check_regressions ./results ./baseline
```

## Using the Benchmark Library

```bash
source lib/benchmark.sh

# Run a single benchmark
benchmark "my_function" 'my_function arg1 arg2' 100

# Generate report
benchmark_report text     # or: json, markdown

# Save results
benchmark_save "my_function" results/my_function.json

# Compare to baseline
benchmark_compare "my_function" baseline/my_function.json
```

## Creating Custom Benchmarks

Create a new benchmark file following this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${SCRIPT_DIR}/.."

source "$MAINFRAME_ROOT/lib/common.sh"
source "$MAINFRAME_ROOT/lib/benchmark.sh"

ITERATIONS="${1:-100}"
OUTPUT_DIR="${2:-$SCRIPT_DIR/results}"
mkdir -p "$OUTPUT_DIR"

# Run benchmarks
result=$(benchmark "my_bench" 'my_function args' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/my_bench.json"
benchmark_report text
```

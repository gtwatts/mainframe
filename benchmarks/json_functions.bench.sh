#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/benchmarks/json_functions.bench.sh - JSON Library Benchmarks
# =============================================================================
# Description: Performance benchmarks for lib/json.sh functions
#              Tests json_object, json_array, json_escape, json_pretty
# Usage: ./json_functions.bench.sh [iterations] [output_dir]
# =============================================================================

set -euo pipefail

# Determine paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${SCRIPT_DIR}/.."

# Source libraries
source "$MAINFRAME_ROOT/lib/common.sh"
source "$MAINFRAME_ROOT/lib/benchmark.sh"

# Configuration
ITERATIONS="${1:-100}"
OUTPUT_DIR="${2:-$SCRIPT_DIR/results}"
mkdir -p "$OUTPUT_DIR"

echo "JSON Functions Benchmark Suite"
echo "=============================="
echo "Iterations: $ITERATIONS"
echo "Output: $OUTPUT_DIR"
echo ""

# =============================================================================
# BENCHMARK: json_object (simple)
# =============================================================================
echo "Running: json_object_simple..."
result=$(benchmark "json_object_simple" 'json_object "name=John" "age:number=30"' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_object_simple.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_object (complex)
# =============================================================================
echo "Running: json_object_complex..."
result=$(benchmark "json_object_complex" \
    'json_object "name=John Doe" "age:number=30" "active:bool=true" "score:number=95.5" "city=New York"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_object_complex.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_object_v (nameref variant)
# =============================================================================
echo "Running: json_object_v..."
result=$(benchmark "json_object_v" \
    'json_object_v out "name=John" "age:number=30"; unset out' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_object_v.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_array (small)
# =============================================================================
echo "Running: json_array_small..."
result=$(benchmark "json_array_small" 'json_array "a" "b" "c"' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_array_small.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_array (large)
# =============================================================================
echo "Running: json_array_large..."
result=$(benchmark "json_array_large" \
    'json_array "item1" "item2" "item3" "item4" "item5" "item6" "item7" "item8" "item9" "item10"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_array_large.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_array_v (nameref variant)
# =============================================================================
echo "Running: json_array_v..."
result=$(benchmark "json_array_v" \
    'json_array_v out "a" "b" "c" "d" "e"; unset out' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_array_v.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_escape (simple)
# =============================================================================
echo "Running: json_escape_simple..."
result=$(benchmark "json_escape_simple" 'json_escape "hello world"' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_escape_simple.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_escape (special chars)
# =============================================================================
echo "Running: json_escape_special..."
# shellcheck disable=SC2016
result=$(benchmark "json_escape_special" \
    'json_escape "hello \"world\" with\nnewlines\tand\ttabs"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_escape_special.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_string
# =============================================================================
echo "Running: json_string..."
result=$(benchmark "json_string" 'json_string "hello world"' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_string.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_number
# =============================================================================
echo "Running: json_number..."
result=$(benchmark "json_number" 'json_number 12345.6789' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_number.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_bool
# =============================================================================
echo "Running: json_bool..."
result=$(benchmark "json_bool" 'json_bool true' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_bool.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_value (auto-detect)
# =============================================================================
echo "Running: json_value_auto..."
result=$(benchmark "json_value_auto" 'json_value "42"' "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_value_auto.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_pretty (small)
# =============================================================================
echo "Running: json_pretty_small..."
result=$(benchmark "json_pretty_small" \
    'json_pretty "{\"a\":1,\"b\":2}"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_pretty_small.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_pretty (nested)
# =============================================================================
echo "Running: json_pretty_nested..."
result=$(benchmark "json_pretty_nested" \
    'json_pretty "{\"outer\":{\"inner\":{\"deep\":true},\"array\":[1,2,3]}}"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_pretty_nested.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_valid
# =============================================================================
echo "Running: json_valid..."
result=$(benchmark "json_valid" \
    'json_valid "{\"name\":\"John\",\"values\":[1,2,3]}"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_valid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_get
# =============================================================================
echo "Running: json_get..."
result=$(benchmark "json_get" \
    'json_get "{\"name\":\"John\",\"age\":30}" "name"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_get.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_merge
# =============================================================================
echo "Running: json_merge..."
result=$(benchmark "json_merge" \
    'json_merge "{\"a\":1}" "{\"b\":2}" "{\"c\":3}"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_merge.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: json_nested
# =============================================================================
echo "Running: json_nested..."
result=$(benchmark "json_nested" \
    'json_nested "a.b.c.d" "value"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/json_nested.json"
benchmark_report text
echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo "=============================="
echo "Benchmark Complete"
echo "Results saved to: $OUTPUT_DIR"
echo ""

# List results
echo "Result files:"
ls -la "$OUTPUT_DIR"/*.json 2>/dev/null || echo "(none)"

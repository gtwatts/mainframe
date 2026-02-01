#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/benchmarks/validation_functions.bench.sh - Validation Library Benchmarks
# =============================================================================
# Description: Performance benchmarks for lib/validation.sh functions
#              Tests validate_email, validate_url, sanitize_*, etc.
# Usage: ./validation_functions.bench.sh [iterations] [output_dir]
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

echo "Validation Functions Benchmark Suite"
echo "====================================="
echo "Iterations: $ITERATIONS"
echo "Output: $OUTPUT_DIR"
echo ""

# =============================================================================
# BENCHMARK: validate_email (valid)
# =============================================================================
echo "Running: validate_email_valid..."
result=$(benchmark "validate_email_valid" \
    'validate_email "user@example.com"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_email_valid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_email (invalid)
# =============================================================================
echo "Running: validate_email_invalid..."
result=$(benchmark "validate_email_invalid" \
    'validate_email "not-an-email" || true' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_email_invalid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_url (valid)
# =============================================================================
echo "Running: validate_url_valid..."
result=$(benchmark "validate_url_valid" \
    'validate_url "https://example.com/path/to/resource?query=1"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_url_valid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_url (invalid)
# =============================================================================
echo "Running: validate_url_invalid..."
result=$(benchmark "validate_url_invalid" \
    'validate_url "not-a-url" || true' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_url_invalid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_int (valid)
# =============================================================================
echo "Running: validate_int_valid..."
result=$(benchmark "validate_int_valid" \
    'validate_int "42"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_int_valid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_int (with range)
# =============================================================================
echo "Running: validate_int_range..."
result=$(benchmark "validate_int_range" \
    'validate_int "50" 1 100' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_int_range.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_float
# =============================================================================
echo "Running: validate_float..."
result=$(benchmark "validate_float" \
    'validate_float "3.14159"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_float.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_uuid
# =============================================================================
echo "Running: validate_uuid..."
result=$(benchmark "validate_uuid" \
    'validate_uuid "550e8400-e29b-41d4-a716-446655440000"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_uuid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_ipv4 (valid)
# =============================================================================
echo "Running: validate_ipv4_valid..."
result=$(benchmark "validate_ipv4_valid" \
    'validate_ipv4 "192.168.1.100"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_ipv4_valid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_ipv4 (invalid)
# =============================================================================
echo "Running: validate_ipv4_invalid..."
result=$(benchmark "validate_ipv4_invalid" \
    'validate_ipv4 "256.256.256.256" || true' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_ipv4_invalid.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_date
# =============================================================================
echo "Running: validate_date..."
result=$(benchmark "validate_date" \
    'validate_date "2024-01-15"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_date.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_time
# =============================================================================
echo "Running: validate_time..."
result=$(benchmark "validate_time" \
    'validate_time "14:30:00"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_time.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_semver
# =============================================================================
echo "Running: validate_semver..."
result=$(benchmark "validate_semver" \
    'validate_semver "1.2.3-beta.1+build.456"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_semver.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_domain
# =============================================================================
echo "Running: validate_domain..."
result=$(benchmark "validate_domain" \
    'validate_domain "subdomain.example.com"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_domain.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_hex
# =============================================================================
echo "Running: validate_hex..."
result=$(benchmark "validate_hex" \
    'validate_hex "deadbeef1234"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_hex.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_bool
# =============================================================================
echo "Running: validate_bool..."
result=$(benchmark "validate_bool" \
    'validate_bool "yes"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_bool.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_path_safe
# =============================================================================
echo "Running: validate_path_safe..."
result=$(benchmark "validate_path_safe" \
    'validate_path_safe "/home/user/documents/file.txt"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_path_safe.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_filename
# =============================================================================
echo "Running: validate_filename..."
result=$(benchmark "validate_filename" \
    'validate_filename "document.pdf"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_filename.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: sanitize_shell_arg
# =============================================================================
echo "Running: sanitize_shell_arg..."
result=$(benchmark "sanitize_shell_arg" \
    'sanitize_shell_arg "hello; rm -rf /"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/sanitize_shell_arg.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: sanitize_filename
# =============================================================================
echo "Running: sanitize_filename..."
result=$(benchmark "sanitize_filename" \
    'sanitize_filename "file<>name|with*bad?chars"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/sanitize_filename.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: sanitize_html
# =============================================================================
echo "Running: sanitize_html..."
result=$(benchmark "sanitize_html" \
    'sanitize_html "<script>alert(1)</script>"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/sanitize_html.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: sanitize_sql
# =============================================================================
echo "Running: sanitize_sql..."
result=$(benchmark "sanitize_sql" \
    "sanitize_sql \"O'Brien's data\"" \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/sanitize_sql.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_command_safe
# =============================================================================
echo "Running: validate_command_safe..."
result=$(benchmark "validate_command_safe" \
    'validate_command_safe "ls -la /home/user"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_command_safe.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_port
# =============================================================================
echo "Running: validate_port..."
result=$(benchmark "validate_port" \
    'validate_port "8080"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_port.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_mac
# =============================================================================
echo "Running: validate_mac..."
result=$(benchmark "validate_mac" \
    'validate_mac "00:1A:2B:3C:4D:5E"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_mac.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_cidr
# =============================================================================
echo "Running: validate_cidr..."
result=$(benchmark "validate_cidr" \
    'validate_cidr "192.168.1.0/24"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_cidr.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_base64
# =============================================================================
echo "Running: validate_base64..."
result=$(benchmark "validate_base64" \
    'validate_base64 "SGVsbG8gV29ybGQh"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_base64.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: regex_match (email)
# =============================================================================
echo "Running: regex_match_email..."
result=$(benchmark "regex_match_email" \
    'regex_match email "user@example.com"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/regex_match_email.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: regex_match (url)
# =============================================================================
echo "Running: regex_match_url..."
result=$(benchmark "regex_match_url" \
    'regex_match url "https://example.com/path"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/regex_match_url.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_length
# =============================================================================
echo "Running: validate_length..."
result=$(benchmark "validate_length" \
    'validate_length "hello world" 1 50' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_length.json"
benchmark_report text
echo ""

# =============================================================================
# BENCHMARK: validate_enum
# =============================================================================
echo "Running: validate_enum..."
result=$(benchmark "validate_enum" \
    'validate_enum "medium" "small" "medium" "large"' \
    "$ITERATIONS")
printf '%s\n' "$result" > "$OUTPUT_DIR/validate_enum.json"
benchmark_report text
echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo "====================================="
echo "Benchmark Complete"
echo "Results saved to: $OUTPUT_DIR"
echo ""

# List results
echo "Result files:"
ls -la "$OUTPUT_DIR"/*.json 2>/dev/null || echo "(none)"

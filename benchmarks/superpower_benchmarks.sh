#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Superpower Benchmarks
# =============================================================================
# Quantified proof that MAINFRAME multiplies Claude Code's capabilities
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Source the pure/core surface under test. A full common.sh load intentionally
# includes higher-tier libraries with overlapping legacy APIs, which would make
# this benchmark measure whichever implementation happened to load last.
_BENCHMARK_MAINFRAME_LIBS_WAS_SET="${MAINFRAME_LIBS+x}"
_BENCHMARK_MAINFRAME_LIBS="${MAINFRAME_LIBS-}"
MAINFRAME_LIBS=core source "$MAINFRAME_ROOT/lib/common.sh"
if [[ -n "$_BENCHMARK_MAINFRAME_LIBS_WAS_SET" ]]; then
    MAINFRAME_LIBS="$_BENCHMARK_MAINFRAME_LIBS"
else
    unset MAINFRAME_LIBS
fi
source "$MAINFRAME_ROOT/lib/pure-string.sh"
source "$MAINFRAME_ROOT/lib/pure-array.sh"
source "$MAINFRAME_ROOT/lib/pure-util.sh"
source "$MAINFRAME_ROOT/lib/pure-file.sh"
source "$MAINFRAME_ROOT/lib/json.sh"
source "$MAINFRAME_ROOT/lib/semver.sh"
source "$MAINFRAME_ROOT/lib/ansi.sh"
source "$MAINFRAME_ROOT/lib/async.sh"

# =============================================================================
# BENCHMARK UTILITIES
# =============================================================================

ITERATIONS="${ITERATIONS:-1000}"
RESULTS=()
BENCHMARK_TEMP_FILE="$(mktemp "${TMPDIR:-/tmp}/mainframe-benchmark.XXXXXX")"
export BENCHMARK_TEMP_FILE
trap 'rm -f -- "$BENCHMARK_TEMP_FILE"' EXIT INT TERM

capture_command() {
    local output_var="$1"
    local cmd="$2"
    local captured status

    set +e
    captured=$(eval "$cmd" 2>&1)
    status=$?
    set -e

    printf -v "$output_var" '%s' "$captured"
    return "$status"
}

benchmark() {
    local name="$1"
    local cmd="$2"
    local start end elapsed

    start=$(date +%s%N)
    for ((i=0; i<ITERATIONS; i++)); do
        eval "$cmd" >/dev/null 2>&1
    done
    end=$(date +%s%N)

    elapsed=$(( (end - start) / 1000000 ))  # milliseconds
    printf '%s: %d ms (%d iterations)\n' "$name" "$elapsed" "$ITERATIONS"
    RESULTS+=("$name:$elapsed")
}

compare() {
    local name="$1"
    local external_cmd="$2"
    local mainframe_cmd="$3"
    local expected="${4-}"
    local ext_output mf_output ext_time mf_time speedup

    printf '\n%b=== %s ===%b\n' "$CLR_BOLD$CLR_CYAN" "$name" "$CLR_RESET"

    if ! capture_command ext_output "$external_cmd"; then
        printf 'Benchmark setup failed for external command: %s\n%s\n' \
            "$external_cmd" "$ext_output" >&2
        return 1
    fi

    if ! capture_command mf_output "$mainframe_cmd"; then
        printf 'Benchmark setup failed for MAINFRAME command: %s\n%s\n' \
            "$mainframe_cmd" "$mf_output" >&2
        return 1
    fi

    if [[ -n "${4+x}" ]]; then
        if [[ "$ext_output" != "$expected" ]]; then
            printf 'External command produced an unexpected result.\nExpected: <%s>\nActual:   <%s>\n' \
                "$expected" "$ext_output" >&2
            return 1
        fi
        if [[ "$mf_output" != "$expected" ]]; then
            printf 'MAINFRAME command produced an unexpected result.\nExpected: <%s>\nActual:   <%s>\n' \
                "$expected" "$mf_output" >&2
            return 1
        fi
    fi

    # External tool
    start=$(date +%s%N)
    for ((i=0; i<ITERATIONS; i++)); do
        eval "$external_cmd" >/dev/null 2>&1
    done
    end=$(date +%s%N)
    ext_time=$(( (end - start) / 1000000 ))

    # MAINFRAME
    start=$(date +%s%N)
    for ((i=0; i<ITERATIONS; i++)); do
        eval "$mainframe_cmd" >/dev/null 2>&1
    done
    end=$(date +%s%N)
    mf_time=$(( (end - start) / 1000000 ))

    printf 'External tool: %d ms\n' "$ext_time"
    printf 'MAINFRAME:     %d ms\n' "$mf_time"

    # Report the measured direction honestly; not every pure Bash operation is
    # faster than a shell builtin or external implementation.
    if [[ $mf_time -eq 0 || $ext_time -eq 0 ]]; then
        printf 'Performance ratio unavailable at this iteration count\n'
    elif [[ $ext_time -ge $mf_time ]]; then
        speedup=$((ext_time * 10 / mf_time))
        printf 'MAINFRAME speedup: %d.%dx\n' "$((speedup / 10))" "$((speedup % 10))"
    else
        speedup=$((mf_time * 10 / ext_time))
        printf 'MAINFRAME slowdown: %d.%dx\n' "$((speedup / 10))" "$((speedup % 10))"
    fi

}

header "MAINFRAME SUPERPOWER BENCHMARKS"
printf 'Iterations per test: %d\n\n' "$ITERATIONS"

# =============================================================================
# BENCHMARK 1: STRING OPERATIONS
# =============================================================================

subheader "String Operations"

# Trim whitespace
compare "Trim Whitespace" \
    'echo "  hello world  " | sed "s/^[[:space:]]*//;s/[[:space:]]*$//"' \
    'trim_string "  hello world  "' \
    'hello world'

# Lowercase
compare "Lowercase Conversion" \
    'echo "HELLO WORLD" | tr "[:upper:]" "[:lower:]"' \
    'to_lower "HELLO WORLD"' \
    'hello world'

# String replacement
compare "String Replace All" \
    'echo "hello world hello" | sed "s/hello/hi/g"' \
    'replace_all "hello world hello" "hello" "hi"' \
    'hi world hi'

# =============================================================================
# BENCHMARK 2: ARRAY OPERATIONS
# =============================================================================

subheader "Array Operations"

# Array unique
compare "Array Unique" \
    'echo -e "a\nb\na\nc\nb" | sort -u' \
    'array_unique "a" "b" "a" "c" "b"' \
    $'a\nb\nc'

# Array join
compare "Array Join" \
    'arr=("a" "b" "c"); (IFS=,; echo "${arr[*]}")' \
    'array_join "," "a" "b" "c"' \
    'a,b,c'

# =============================================================================
# BENCHMARK 3: JSON GENERATION
# =============================================================================

subheader "JSON Generation"

# Simple object - external requires jq or complex escaping
compare "JSON Object Creation" \
    'printf "{\"name\":\"John\",\"age\":30}"' \
    'json_object name="John" age:number=30' \
    '{"name":"John","age":30}'

# JSON array
compare "JSON Array Creation" \
    'printf "[\"a\",\"b\",\"c\"]"' \
    'json_array "a" "b" "c"' \
    '["a","b","c"]'

# =============================================================================
# BENCHMARK 4: FILE OPERATIONS
# =============================================================================

subheader "File Operations"

# Create test file
printf 'line1\nline2\nline3\nline4\nline5\n' > "$BENCHMARK_TEMP_FILE"

compare "Read File Head (3 lines)" \
    'head -3 "$BENCHMARK_TEMP_FILE"' \
    'file_head 3 "$BENCHMARK_TEMP_FILE"' \
    $'line1\nline2\nline3'

compare "Count Lines" \
    'lines=$(wc -l < "$BENCHMARK_TEMP_FILE"); printf "%d" "$lines"' \
    'file_lines "$BENCHMARK_TEMP_FILE"' \
    '5'

compare "Get Basename" \
    'basename /path/to/some/file.txt' \
    'path_basename /path/to/some/file.txt' \
    'file.txt'

# =============================================================================
# BENCHMARK 5: UTILITY FUNCTIONS
# =============================================================================

subheader "Utility Functions"

compare "Generate Timestamp" \
    'date "+%Y-%m-%d %H:%M:%S"' \
    'timestamp'

compare "Get Epoch" \
    'date +%s' \
    'epoch'

# =============================================================================
# BENCHMARK PROFILE SUMMARY
# =============================================================================

header "BENCHMARK PROFILE SUMMARY"

# Count functions available
string_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/pure-string.sh" 2>/dev/null || echo 0)
array_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/pure-array.sh" 2>/dev/null || echo 0)
util_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/pure-util.sh" 2>/dev/null || echo 0)
file_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/pure-file.sh" 2>/dev/null || echo 0)
json_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/json.sh" 2>/dev/null || echo 0)
semver_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/semver.sh" 2>/dev/null || echo 0)
ansi_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/ansi.sh" 2>/dev/null || echo 0)
async_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/async.sh" 2>/dev/null || echo 0)
common_funcs=$(grep -c '^[a-z_]*()' "$MAINFRAME_ROOT/lib/common.sh" 2>/dev/null || echo 0)

total_funcs=$((string_funcs + array_funcs + util_funcs + file_funcs + json_funcs + semver_funcs + ansi_funcs + async_funcs + common_funcs))

printf '\n%bFunction definitions scanned in this profile:%b\n' "$CLR_BOLD" "$CLR_RESET"
printf '  pure-string.sh:  %3d functions\n' "$string_funcs"
printf '  pure-array.sh:   %3d functions\n' "$array_funcs"
printf '  pure-util.sh:    %3d functions\n' "$util_funcs"
printf '  pure-file.sh:    %3d functions\n' "$file_funcs"
printf '  json.sh:         %3d functions\n' "$json_funcs"
printf '  semver.sh:       %3d functions\n' "$semver_funcs"
printf '  ansi.sh:         %3d functions\n' "$ansi_funcs"
printf '  async.sh:        %3d functions\n' "$async_funcs"
printf '  common.sh:       %3d functions\n' "$common_funcs"
printf '  %b─────────────────────────%b\n' "$CLR_DIM" "$CLR_RESET"
printf '  %bTOTAL:           %3d definitions%b\n' "$CLR_GREEN$CLR_BOLD" "$total_funcs" "$CLR_RESET"

printf '\nThe per-operation results above are the evidence. This script does not\n'
printf 'calculate an aggregate capability, productivity, or performance multiplier.\n'
printf 'Definition counts include internal helpers and are not the product registry.\n\n'

success "Benchmarks completed successfully."

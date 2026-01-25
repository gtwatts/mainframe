#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/parse_output.sh - Universal Test/Build/Lint Output Parsers
# =============================================================================
# Description: Structured JSON parsing of common tool outputs. Eliminates
#              per-agent regex hacking of compiler and test runner output.
# Version: 1.0.0
# =============================================================================
# LIMITATIONS (regex-based parsing):
#   - Cannot parse interleaved multi-process output reliably
#   - Cannot handle ANSI escape codes in all cases (stripped best-effort)
#   - TAP nested subtests (TAP version 14) not fully supported
#   - JUnit XML only parsed if xmllint or similar is available
#   - Multiline error messages may be truncated at 500 chars
#   - Duration parsing assumes common locale formats (., not ,)
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PARSE_OUTPUT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PARSE_OUTPUT_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Strip ANSI escape codes from input
_po_strip_ansi() {
    # Strip ANSI escape sequences: CSI (ESC [) and SS2/SS3 (ESC ( and ESC ))
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b[(][0-9;]*[a-zA-Z]//g'
}

# Escape a string for JSON embedding
_po_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Build a test result JSON object
_po_test_json() {
    local total="${1:-0}" passed="${2:-0}" failed="${3:-0}" skipped="${4:-0}" duration_ms="${5:-0}"
    shift 5
    local failures_json="${1:-[]}"
    printf '{"total":%d,"passed":%d,"failed":%d,"skipped":%d,"duration_ms":%d,"failures":%s}' \
        "$total" "$passed" "$failed" "$skipped" "$duration_ms" "$failures_json"
}

# Build a single failure entry
_po_failure_entry() {
    local test="$1" message="$2" file="${3:-}" line="${4:-0}"
    printf '{"test":"%s","message":"%s","file":"%s","line":%s}' \
        "$(_po_json_escape "$test")" \
        "$(_po_json_escape "$message")" \
        "$(_po_json_escape "$file")" \
        "${line:-0}"
}

# Build a compiler error entry
_po_compiler_entry() {
    local level="$1" message="$2" file="${3:-}" line="${4:-0}" column="${5:-0}" code="${6:-}"
    printf '{"level":"%s","message":"%s","file":"%s","line":%s,"column":%s,"code":"%s"}' \
        "$(_po_json_escape "$level")" \
        "$(_po_json_escape "$message")" \
        "$(_po_json_escape "$file")" \
        "${line:-0}" \
        "${column:-0}" \
        "$(_po_json_escape "$code")"
}

# Build a lint issue entry
_po_lint_entry() {
    local level="$1" rule="$2" message="$3" file="${4:-}" line="${5:-0}" column="${6:-0}" fix="${7:-false}"
    printf '{"level":"%s","rule":"%s","message":"%s","file":"%s","line":%s,"column":%s,"fix_available":%s}' \
        "$(_po_json_escape "$level")" \
        "$(_po_json_escape "$rule")" \
        "$(_po_json_escape "$message")" \
        "$(_po_json_escape "$file")" \
        "${line:-0}" \
        "${column:-0}" \
        "$fix"
}

# Join array entries with commas
_po_join_array() {
    local IFS=','
    printf '[%s]' "$*"
}

# Extract a JSON array value by key from single-line JSON
# Uses balanced bracket matching via awk
_po_extract_array() {
    local key="$1" json="$2"
    printf '%s' "$json" | awk -v k="\"${key}\":" '
    {
        idx = index($0, k)
        if (idx == 0) { print "[]"; exit }
        rest = substr($0, idx + length(k))
        depth = 0; result = ""
        for (i = 1; i <= length(rest); i++) {
            c = substr(rest, i, 1)
            if (c == "[") depth++
            if (depth > 0) result = result c
            if (c == "]") { depth--; if (depth == 0) break }
        }
        if (result == "") print "[]"
        else print result
    }'
}

# =============================================================================
# FORMAT DETECTION
# =============================================================================

# Detect what kind of output this is
# Reads stdin, outputs format name
parse_detect_format() {
    local input
    input=$(cat | _po_strip_ansi)

    # Jest/Vitest
    if printf '%s' "$input" | grep -qE '(Test Suites:|Tests:.*passed|PASS.*\.test\.|FAIL.*\.test\.)'; then
        printf 'jest'
        return 0
    fi

    # pytest
    if printf '%s' "$input" | grep -qE '(=+ (FAILURES|ERRORS|short test summary|test session starts) =+|[0-9]+ passed in [0-9]|failed.*pytest|\.py::[A-Za-z])'; then
        printf 'pytest'
        return 0
    fi

    # go test
    if printf '%s' "$input" | grep -qE '(^=== RUN|^--- (PASS|FAIL)|^(ok|FAIL)\s+[a-z])'; then
        printf 'go_test'
        return 0
    fi

    # BATS
    if printf '%s' "$input" | grep -qE '(^(ok|not ok) [0-9]+|^1\.\.[0-9]+)'; then
        printf 'bats'
        return 0
    fi

    # TAP (generic - after BATS check)
    if printf '%s' "$input" | grep -qE '^TAP version'; then
        printf 'tap'
        return 0
    fi

    # ShellCheck (check before GCC since format is similar)
    if printf '%s' "$input" | grep -qE '(SC[0-9]{4}|^In .* line [0-9]+:)'; then
        printf 'shellcheck'
        return 0
    fi

    # ESLint
    if printf '%s' "$input" | grep -qE '([0-9]+:[0-9]+\s+(error|warning)\s+.+\s+[a-z/-]+$|problems? \([0-9]+ errors?)'; then
        printf 'eslint'
        return 0
    fi

    # rustc
    if printf '%s' "$input" | grep -qE '^error\[E[0-9]+\]'; then
        printf 'rust'
        return 0
    fi

    # TypeScript (tsc)
    if printf '%s' "$input" | grep -qE '\([0-9]+,[0-9]+\): error TS[0-9]+'; then
        printf 'typescript'
        return 0
    fi

    # GCC/Clang
    if printf '%s' "$input" | grep -qE '[^:]+:[0-9]+:[0-9]+: (error|warning|note):'; then
        printf 'gcc'
        return 0
    fi

    # pylint (requires .py file extension to disambiguate from other tools)
    if printf '%s' "$input" | grep -qE '\.py:[0-9]+:[0-9]+: [CEFRW][0-9]{4}:'; then
        printf 'pylint'
        return 0
    fi

    # golangci-lint
    if printf '%s' "$input" | grep -qE '\.go:[0-9]+:[0-9]+: .+ \([a-z]+\)$'; then
        printf 'golint'
        return 0
    fi

    printf 'generic'
}

# =============================================================================
# AUTO-DETECTION DISPATCHER
# =============================================================================

# Parse output with format auto-detection or explicit format
# Usage: echo "output" | parse_output [--format auto|jest|pytest|...]
parse_output() {
    local format="auto"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local input
    input=$(cat)

    if [[ "$format" == "auto" ]]; then
        format=$(printf '%s' "$input" | parse_detect_format)
    fi

    case "$format" in
        jest)       printf '%s' "$input" | parse_jest ;;
        pytest)     printf '%s' "$input" | parse_pytest ;;
        go_test|go) printf '%s' "$input" | parse_go_test ;;
        bats)       printf '%s' "$input" | parse_bats ;;
        tap)        printf '%s' "$input" | parse_tap ;;
        gcc)        printf '%s' "$input" | parse_gcc ;;
        rust)       printf '%s' "$input" | parse_rust ;;
        typescript) printf '%s' "$input" | parse_typescript_compiler ;;
        go_build)   printf '%s' "$input" | parse_go_build ;;
        eslint)     printf '%s' "$input" | parse_eslint ;;
        shellcheck) printf '%s' "$input" | parse_shellcheck ;;
        pylint)     printf '%s' "$input" | parse_pylint ;;
        golint)     printf '%s' "$input" | parse_golint ;;
        generic)    printf '%s' "$input" | parse_generic_test ;;
        *)          printf '%s' "$input" | parse_generic_test ;;
    esac
}

# =============================================================================
# TEST OUTPUT PARSERS
# =============================================================================

# Parse Jest/Vitest output
parse_jest() {
    local input
    input=$(cat | _po_strip_ansi)
    local total=0 passed=0 failed=0 skipped=0 duration_ms=0
    local -a failures=()

    # Parse summary line: "Tests:  X failed, Y skipped, Z passed, W total"
    local summary_line
    summary_line=$(printf '%s\n' "$input" | grep -E '^\s*Tests:' | tail -1)
    if [[ -n "$summary_line" ]]; then
        local f p s t
        f=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
        p=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
        s=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+')
        t=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ total' | grep -oE '[0-9]+')
        [[ -n "$f" ]] && failed=$f
        [[ -n "$p" ]] && passed=$p
        [[ -n "$s" ]] && skipped=$s
        [[ -n "$t" ]] && total=$t
    fi

    # If no total from summary, compute it
    if [[ $total -eq 0 ]]; then
        total=$((passed + failed + skipped))
    fi

    # Parse duration: "Time:  X.XXX s" or "Time:  Xms"
    local time_line
    time_line=$(printf '%s\n' "$input" | grep -E '^\s*Time:' | tail -1)
    if [[ -n "$time_line" ]]; then
        local time_val
        time_val=$(printf '%s' "$time_line" | grep -oE '[0-9]+\.[0-9]+\s*s' | grep -oE '[0-9]+\.[0-9]+')
        if [[ -n "$time_val" ]]; then
            duration_ms=$(awk "BEGIN {printf \"%d\", $time_val * 1000}")
        else
            time_val=$(printf '%s' "$time_line" | grep -oE '[0-9]+\s*ms' | grep -oE '[0-9]+')
            [[ -n "$time_val" ]] && duration_ms=$time_val
        fi
    fi

    # Parse failure blocks (between lines starting with bullet)
    local in_failure=0
    local current_test="" current_message="" current_file="" current_line=0
    while IFS= read -r line; do
        # Failure block start: "  ● test name" or "  ● Suite > test name"
        if [[ "$line" =~ ^[[:space:]]*●[[:space:]]*(.+)$ ]]; then
            # Save previous failure
            if [[ $in_failure -eq 1 && -n "$current_test" ]]; then
                failures+=("$(_po_failure_entry "$current_test" "$current_message" "$current_file" "$current_line")")
            fi
            in_failure=1
            current_test="${BASH_REMATCH[1]}"
            current_message=""
            current_file=""
            current_line=0
        elif [[ $in_failure -eq 1 ]]; then
            # Look for file reference: "at Object.<anonymous> (file:line:col)"
            local _re_file='([^[:space:](]+\.(ts|js|tsx|jsx)):([0-9]+)'
            if [[ "$line" =~ $_re_file ]]; then
                [[ -z "$current_file" ]] && current_file="${BASH_REMATCH[1]}"
                [[ $current_line -eq 0 ]] && current_line="${BASH_REMATCH[3]}"
            fi
            # Capture error message (first non-empty content line)
            local trimmed
            trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
            if [[ -z "$current_message" && -n "$trimmed" && ! "$trimmed" =~ ^(at |●) ]]; then
                current_message="$trimmed"
            fi
        fi
    done <<< "$input"

    # Save last failure
    if [[ $in_failure -eq 1 && -n "$current_test" ]]; then
        failures+=("$(_po_failure_entry "$current_test" "$current_message" "$current_file" "$current_line")")
    fi

    local failures_json
    if [[ ${#failures[@]} -gt 0 ]]; then
        failures_json=$(_po_join_array "${failures[@]}")
    else
        failures_json="[]"
    fi

    _po_test_json "$total" "$passed" "$failed" "$skipped" "$duration_ms" "$failures_json"
}

# Parse pytest output
parse_pytest() {
    local input
    input=$(cat | _po_strip_ansi)
    local total=0 passed=0 failed=0 skipped=0 duration_ms=0
    local -a failures=()

    # Parse summary line: "X passed, Y failed, Z skipped in Ns"
    # or "=== X passed in Ns ==="
    local summary_line
    summary_line=$(printf '%s\n' "$input" | grep -E '(passed|failed|error)' | grep -E 'in [0-9]' | tail -1)
    if [[ -n "$summary_line" ]]; then
        local f p s e
        f=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
        p=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
        s=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+')
        e=$(printf '%s' "$summary_line" | grep -oE '[0-9]+ error' | grep -oE '[0-9]+')
        [[ -n "$f" ]] && failed=$f
        [[ -n "$p" ]] && passed=$p
        [[ -n "$s" ]] && skipped=$s
        [[ -n "$e" ]] && failed=$((failed + e))

        # Duration: "in X.XXs"
        local dur
        dur=$(printf '%s' "$summary_line" | grep -oE 'in [0-9]+\.[0-9]+s' | grep -oE '[0-9]+\.[0-9]+')
        if [[ -n "$dur" ]]; then
            duration_ms=$(awk "BEGIN {printf \"%d\", $dur * 1000}")
        fi
    fi

    total=$((passed + failed + skipped))

    # Parse FAILED lines: "FAILED path/test.py::TestClass::test_name - reason"
    while IFS= read -r line; do
        if [[ "$line" =~ ^FAILED[[:space:]]+([^[:space:]]+)::([^[:space:]]+) ]]; then
            local fpath="${BASH_REMATCH[1]}"
            local fname="${BASH_REMATCH[2]}"
            local fmessage=""
            if [[ "$line" =~ -[[:space:]]+(.+)$ ]]; then
                fmessage="${BASH_REMATCH[1]}"
            fi
            local fline=0
            # Try to find line number from traceback
            local tline
            tline=$(printf '%s\n' "$input" | grep -A2 "$fname" | grep -oE "${fpath}:[0-9]+" | head -1 | grep -oE '[0-9]+$')
            [[ -n "$tline" ]] && fline=$tline
            failures+=("$(_po_failure_entry "$fname" "$fmessage" "$fpath" "$fline")")
        fi
    done <<< "$input"

    # If no FAILED lines found, try short test summary
    if [[ ${#failures[@]} -eq 0 && $failed -gt 0 ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ([^[:space:]]+\.py)::([^[:space:]]+) ]]; then
                local fpath="${BASH_REMATCH[1]}"
                local fname="${BASH_REMATCH[2]}"
                failures+=("$(_po_failure_entry "$fname" "" "$fpath" "0")")
            fi
        done <<< "$(printf '%s\n' "$input" | grep -E '(FAILED|ERROR).*\.py::')"
    fi

    local failures_json
    if [[ ${#failures[@]} -gt 0 ]]; then
        failures_json=$(_po_join_array "${failures[@]}")
    else
        failures_json="[]"
    fi

    _po_test_json "$total" "$passed" "$failed" "$skipped" "$duration_ms" "$failures_json"
}

# Parse go test output
parse_go_test() {
    local input
    input=$(cat | _po_strip_ansi)
    local total=0 passed=0 failed=0 skipped=0 duration_ms=0
    local -a failures=()

    while IFS= read -r line; do
        # --- PASS: TestName (0.01s)
        if [[ "$line" =~ ^---[[:space:]]+PASS:[[:space:]]+([^[:space:]]+)[[:space:]]+\(([0-9.]+)s\) ]]; then
            ((passed++))
            local dur="${BASH_REMATCH[2]}"
            duration_ms=$((duration_ms + $(awk "BEGIN {printf \"%d\", $dur * 1000}")))
        # --- FAIL: TestName (0.01s)
        elif [[ "$line" =~ ^---[[:space:]]+FAIL:[[:space:]]+([^[:space:]]+)[[:space:]]+\(([0-9.]+)s\) ]]; then
            ((failed++))
            local tname="${BASH_REMATCH[1]}"
            local dur="${BASH_REMATCH[2]}"
            duration_ms=$((duration_ms + $(awk "BEGIN {printf \"%d\", $dur * 1000}")))
            # Look for error message in surrounding context
            local msg=""
            local tfile="" tline=0
            local context
            context=$(printf '%s\n' "$input" | grep -B5 -F -e "--- FAIL: $tname" | head -5)
            # file_test.go:42: error message
            local fref
            fref=$(printf '%s\n' "$context" | grep -oE '[a-zA-Z_]+\.go:[0-9]+:' | tail -1)
            if [[ -n "$fref" ]]; then
                tfile=$(printf '%s' "$fref" | cut -d: -f1)
                tline=$(printf '%s' "$fref" | cut -d: -f2)
            fi
            msg=$(printf '%s\n' "$context" | grep -E '\.go:[0-9]+:' | tail -1 | sed 's/.*\.go:[0-9]*:[[:space:]]*//')
            failures+=("$(_po_failure_entry "$tname" "$msg" "$tfile" "$tline")")
        # --- SKIP: TestName (0.00s)
        elif [[ "$line" =~ ^---[[:space:]]+SKIP: ]]; then
            ((skipped++))
        fi
    done <<< "$input"

    total=$((passed + failed + skipped))

    # Also check for package-level duration: "ok  package  0.123s"
    local pkg_dur
    pkg_dur=$(printf '%s\n' "$input" | grep -oE '^(ok|FAIL)\s+\S+\s+[0-9.]+s' | tail -1 | grep -oE '[0-9]+\.[0-9]+')
    if [[ -n "$pkg_dur" ]]; then
        duration_ms=$(awk "BEGIN {printf \"%d\", $pkg_dur * 1000}")
    fi

    local failures_json
    if [[ ${#failures[@]} -gt 0 ]]; then
        failures_json=$(_po_join_array "${failures[@]}")
    else
        failures_json="[]"
    fi

    _po_test_json "$total" "$passed" "$failed" "$skipped" "$duration_ms" "$failures_json"
}

# Parse BATS output (TAP format)
parse_bats() {
    local input
    input=$(cat | _po_strip_ansi)
    local total=0 passed=0 failed=0 skipped=0 duration_ms=0
    local -a failures=()

    # Check for plan line: "1..N"
    local plan_line
    plan_line=$(printf '%s\n' "$input" | grep -oE '^1\.\.[0-9]+' | head -1)
    if [[ -n "$plan_line" ]]; then
        total="${plan_line#1..}"
    fi

    local current_test=""
    while IFS= read -r line; do
        # "ok N description" or "ok N - description"
        if [[ "$line" =~ ^ok[[:space:]]+([0-9]+)[[:space:]]+(.*)$ ]]; then
            local desc="${BASH_REMATCH[2]}"
            desc="${desc#- }"
            if [[ "$desc" =~ \#[[:space:]]*(skip|SKIP) ]]; then
                ((skipped++))
            else
                ((passed++))
            fi
        # "not ok N description"
        elif [[ "$line" =~ ^not[[:space:]]+ok[[:space:]]+([0-9]+)[[:space:]]+(.*)$ ]]; then
            ((failed++))
            current_test="${BASH_REMATCH[2]}"
            current_test="${current_test#- }"
            local ffile="" fline=0 fmsg=""
            # Look ahead for diagnostic comments
            local diag
            diag=$(printf '%s\n' "$input" | grep -A5 "^not ok ${BASH_REMATCH[1]} " | grep '^#' | head -3)
            # Parse "# (in test file path, line N)"
            if [[ "$diag" =~ \(in[[:space:]]test[[:space:]]file[[:space:]]([^,]+),[[:space:]]*line[[:space:]]*([0-9]+)\) ]]; then
                ffile="${BASH_REMATCH[1]}"
                fline="${BASH_REMATCH[2]}"
            fi
            # Parse "# message" lines for error message
            fmsg=$(printf '%s\n' "$diag" | grep -v '(in test file' | sed 's/^#[[:space:]]*//' | head -1)
            failures+=("$(_po_failure_entry "$current_test" "$fmsg" "$ffile" "$fline")")
        fi
    done <<< "$input"

    # If no plan line found, compute total
    if [[ $total -eq 0 ]]; then
        total=$((passed + failed + skipped))
    fi

    # Duration: look for timing info (some BATS output includes it)
    local dur_line
    dur_line=$(printf '%s\n' "$input" | grep -oE '[0-9]+ tests.*in [0-9]+' | tail -1)
    if [[ "$dur_line" =~ in[[:space:]]+([0-9]+) ]]; then
        duration_ms=$((${BASH_REMATCH[1]} * 1000))
    fi

    local failures_json
    if [[ ${#failures[@]} -gt 0 ]]; then
        failures_json=$(_po_join_array "${failures[@]}")
    else
        failures_json="[]"
    fi

    _po_test_json "$total" "$passed" "$failed" "$skipped" "$duration_ms" "$failures_json"
}

# Parse TAP (Test Anything Protocol) format
parse_tap() {
    # TAP and BATS share the same core format
    parse_bats
}

# Parse generic/unknown test runner output (best-effort)
parse_generic_test() {
    local input
    input=$(cat | _po_strip_ansi)
    local total=0 passed=0 failed=0 skipped=0 duration_ms=0
    local -a failures=()

    # Try common patterns
    # "N tests, N failures"
    local tests_line
    tests_line=$(printf '%s\n' "$input" | grep -iE '[0-9]+ tests?' | tail -1)
    if [[ -n "$tests_line" ]]; then
        local t
        t=$(printf '%s' "$tests_line" | grep -oE '[0-9]+ tests?' | head -1 | grep -oE '[0-9]+')
        [[ -n "$t" ]] && total=$t
    fi

    # Count PASS/FAIL/OK/ERROR lines
    passed=$(printf '%s\n' "$input" | grep -ciE '^\s*(PASS|OK|ok|PASSED|pass)\b' || true)
    failed=$(printf '%s\n' "$input" | grep -ciE '^\s*(FAIL|FAILED|ERROR|not ok|FAILURE)\b' || true)
    skipped=$(printf '%s\n' "$input" | grep -ciE '^\s*(SKIP|SKIPPED|PENDING)\b' || true)

    if [[ $total -eq 0 ]]; then
        total=$((passed + failed + skipped))
    fi

    # Collect failure lines
    while IFS= read -r line; do
        if [[ "$line" =~ (FAIL|FAILED|ERROR|FAILURE)[[:space:]]*:?[[:space:]]*(.+) ]]; then
            local msg="${BASH_REMATCH[2]}"
            local ffile="" fline=0
            if [[ "$msg" =~ ([^[:space:]]+\.[a-z]+):([0-9]+) ]]; then
                ffile="${BASH_REMATCH[1]}"
                fline="${BASH_REMATCH[2]}"
            fi
            failures+=("$(_po_failure_entry "$msg" "" "$ffile" "$fline")")
        fi
    done <<< "$input"

    local failures_json
    if [[ ${#failures[@]} -gt 0 ]]; then
        failures_json=$(_po_join_array "${failures[@]}")
    else
        failures_json="[]"
    fi

    _po_test_json "$total" "$passed" "$failed" "$skipped" "$duration_ms" "$failures_json"
}

# =============================================================================
# BUILD/COMPILER OUTPUT PARSERS
# =============================================================================

# Parse GCC/Clang compiler output
parse_gcc() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a errors=()

    while IFS= read -r line; do
        # Pattern: file:line:col: level: message
        if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+):[[:space:]]*(error|warning|note):[[:space:]]*(.+)$ ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local col="${BASH_REMATCH[3]}"
            local level="${BASH_REMATCH[4]}"
            local msg="${BASH_REMATCH[5]}"
            local code=""
            # Extract warning flag: [-Wfoo-bar]
            if [[ "$msg" =~ \[(-W[a-zA-Z0-9_-]+)\]$ ]]; then
                code="${BASH_REMATCH[1]}"
                msg="${msg% \[*\]}"
            fi
            errors+=("$(_po_compiler_entry "$level" "$msg" "$file" "$ln" "$col" "$code")")
            if [[ "$level" == "error" ]]; then
                ((error_count++))
            elif [[ "$level" == "warning" ]]; then
                ((warning_count++))
            fi
        fi
    done <<< "$input"

    local errors_json
    if [[ ${#errors[@]} -gt 0 ]]; then
        errors_json=$(_po_join_array "${errors[@]}")
    else
        errors_json="[]"
    fi

    printf '{"errors":%s,"error_count":%d,"warning_count":%d}' \
        "$errors_json" "$error_count" "$warning_count"
}

# Parse rustc compiler output
parse_rust() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a errors=()

    local current_level="" current_code="" current_msg="" current_file="" current_line=0 current_col=0

    while IFS= read -r line; do
        # "error[E0001]: message" or "warning[...]: message" or "error: message"
        if [[ "$line" =~ ^(error|warning)(\[([A-Z][0-9]+)\])?:[[:space:]]*(.+)$ ]]; then
            # Save previous entry
            if [[ -n "$current_level" ]]; then
                errors+=("$(_po_compiler_entry "$current_level" "$current_msg" "$current_file" "$current_line" "$current_col" "$current_code")")
                if [[ "$current_level" == "error" ]]; then ((error_count++)); fi
                if [[ "$current_level" == "warning" ]]; then ((warning_count++)); fi
            fi
            current_level="${BASH_REMATCH[1]}"
            current_code="${BASH_REMATCH[3]}"
            current_msg="${BASH_REMATCH[4]}"
            current_file=""
            current_line=0
            current_col=0
        # "  --> file:line:col"
        elif [[ "$line" =~ ^[[:space:]]*--\>[[:space:]]*([^:]+):([0-9]+):([0-9]+) ]]; then
            current_file="${BASH_REMATCH[1]}"
            current_line="${BASH_REMATCH[2]}"
            current_col="${BASH_REMATCH[3]}"
        fi
    done <<< "$input"

    # Save last entry
    if [[ -n "$current_level" ]]; then
        errors+=("$(_po_compiler_entry "$current_level" "$current_msg" "$current_file" "$current_line" "$current_col" "$current_code")")
        if [[ "$current_level" == "error" ]]; then ((error_count++)); fi
        if [[ "$current_level" == "warning" ]]; then ((warning_count++)); fi
    fi

    local errors_json
    if [[ ${#errors[@]} -gt 0 ]]; then
        errors_json=$(_po_join_array "${errors[@]}")
    else
        errors_json="[]"
    fi

    printf '{"errors":%s,"error_count":%d,"warning_count":%d}' \
        "$errors_json" "$error_count" "$warning_count"
}

# Parse TypeScript compiler (tsc) output
parse_typescript_compiler() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a errors=()

    local _re_ts='^([^(]+)\(([0-9]+),([0-9]+)\):[[:space:]]*(error|warning)[[:space:]]+(TS[0-9]+):[[:space:]]*(.+)$'
    while IFS= read -r line; do
        # Pattern: file(line,col): error TSxxxx: message
        if [[ "$line" =~ $_re_ts ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local col="${BASH_REMATCH[3]}"
            local level="${BASH_REMATCH[4]}"
            local code="${BASH_REMATCH[5]}"
            local msg="${BASH_REMATCH[6]}"
            errors+=("$(_po_compiler_entry "$level" "$msg" "$file" "$ln" "$col" "$code")")
            if [[ "$level" == "error" ]]; then
                error_count=$((error_count + 1))
            elif [[ "$level" == "warning" ]]; then
                warning_count=$((warning_count + 1))
            fi
        fi
    done <<< "$input"

    local errors_json
    if [[ ${#errors[@]} -gt 0 ]]; then
        errors_json=$(_po_join_array "${errors[@]}")
    else
        errors_json="[]"
    fi

    printf '{"errors":%s,"error_count":%d,"warning_count":%d}' \
        "$errors_json" "$error_count" "$warning_count"
}

# Parse go build output
parse_go_build() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a errors=()

    while IFS= read -r line; do
        # Pattern: ./file.go:line:col: message
        if [[ "$line" =~ ^\.?/?([^:]+\.go):([0-9]+):([0-9]+):[[:space:]]*(.+)$ ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local col="${BASH_REMATCH[3]}"
            local msg="${BASH_REMATCH[4]}"
            errors+=("$(_po_compiler_entry "error" "$msg" "$file" "$ln" "$col" "")")
            ((error_count++))
        # Pattern: file.go:line: message (no column)
        elif [[ "$line" =~ ^\.?/?([^:]+\.go):([0-9]+):[[:space:]]*(.+)$ ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local msg="${BASH_REMATCH[3]}"
            errors+=("$(_po_compiler_entry "error" "$msg" "$file" "$ln" "0" "")")
            ((error_count++))
        fi
    done <<< "$input"

    local errors_json
    if [[ ${#errors[@]} -gt 0 ]]; then
        errors_json=$(_po_join_array "${errors[@]}")
    else
        errors_json="[]"
    fi

    printf '{"errors":%s,"error_count":%d,"warning_count":%d}' \
        "$errors_json" "$error_count" "$warning_count"
}

# Parse generic compiler output (best-effort)
parse_generic_compiler() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a errors=()

    while IFS= read -r line; do
        local level="error" file="" ln=0 col=0 msg="" code=""

        # Try file:line:col: level: message
        if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+):[[:space:]]*(error|warning|note):[[:space:]]*(.+)$ ]]; then
            file="${BASH_REMATCH[1]}"
            ln="${BASH_REMATCH[2]}"
            col="${BASH_REMATCH[3]}"
            level="${BASH_REMATCH[4]}"
            msg="${BASH_REMATCH[5]}"
        # Try file:line: error: message
        elif [[ "$line" =~ ^([^:]+):([0-9]+):[[:space:]]*(error|warning):[[:space:]]*(.+)$ ]]; then
            file="${BASH_REMATCH[1]}"
            ln="${BASH_REMATCH[2]}"
            level="${BASH_REMATCH[3]}"
            msg="${BASH_REMATCH[4]}"
        # Try "error:" or "Error:" prefix
        elif [[ "$line" =~ ^[[:space:]]*(error|Error|ERROR):[[:space:]]*(.+)$ ]]; then
            level="error"
            msg="${BASH_REMATCH[2]}"
        else
            continue
        fi

        errors+=("$(_po_compiler_entry "$level" "$msg" "$file" "$ln" "$col" "$code")")
        if [[ "$level" == "error" ]]; then
            ((error_count++))
        elif [[ "$level" == "warning" ]]; then
            ((warning_count++))
        fi
    done <<< "$input"

    local errors_json
    if [[ ${#errors[@]} -gt 0 ]]; then
        errors_json=$(_po_join_array "${errors[@]}")
    else
        errors_json="[]"
    fi

    printf '{"errors":%s,"error_count":%d,"warning_count":%d}' \
        "$errors_json" "$error_count" "$warning_count"
}

# =============================================================================
# LINT OUTPUT PARSERS
# =============================================================================

# Parse ESLint output (default formatter)
parse_eslint() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a issues=()
    local current_file=""

    while IFS= read -r line; do
        # File header: absolute or relative path on its own line
        if [[ "$line" =~ ^(/[^[:space:]]+|[a-zA-Z]:\\[^[:space:]]+|\.?/?[a-zA-Z][^[:space:]]*)$ && ! "$line" =~ ^[0-9] ]]; then
            current_file="$line"
        # Issue line: "  line:col  error|warning  message  rule-name"
        elif [[ "$line" =~ ^[[:space:]]*([0-9]+):([0-9]+)[[:space:]]+(error|warning)[[:space:]]+(.+)[[:space:]]+([a-zA-Z@][a-zA-Z0-9/_@-]+)$ ]]; then
            local ln="${BASH_REMATCH[1]}"
            local col="${BASH_REMATCH[2]}"
            local level="${BASH_REMATCH[3]}"
            local msg="${BASH_REMATCH[4]}"
            local rule="${BASH_REMATCH[5]}"
            # Trim trailing spaces from message
            msg=$(printf '%s' "$msg" | sed 's/[[:space:]]*$//')
            issues+=("$(_po_lint_entry "$level" "$rule" "$msg" "$current_file" "$ln" "$col" "false")")
            if [[ "$level" == "error" ]]; then
                ((error_count++))
            elif [[ "$level" == "warning" ]]; then
                ((warning_count++))
            fi
        fi
    done <<< "$input"

    local issues_json
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json=$(_po_join_array "${issues[@]}")
    else
        issues_json="[]"
    fi

    printf '{"issues":%s,"error_count":%d,"warning_count":%d}' \
        "$issues_json" "$error_count" "$warning_count"
}

# Parse ShellCheck output
parse_shellcheck() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a issues=()

    while IFS= read -r line; do
        # GCC format: file:line:col: level: message [SCxxxx]
        if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+):[[:space:]]*(error|warning|note|info|style):[[:space:]]*(.*)[[:space:]]\[(SC[0-9]+)\]$ ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local col="${BASH_REMATCH[3]}"
            local level="${BASH_REMATCH[4]}"
            local msg="${BASH_REMATCH[5]}"
            local rule="${BASH_REMATCH[6]}"
            # Normalize style/note/info to warning
            [[ "$level" == "style" || "$level" == "note" || "$level" == "info" ]] && level="info"
            issues+=("$(_po_lint_entry "$level" "$rule" "$msg" "$file" "$ln" "$col" "false")")
            if [[ "$level" == "error" ]]; then
                ((error_count++))
            else
                ((warning_count++))
            fi
        # Alternative format: "In file line N:" + "^-- SCxxxx (level): message"
        elif [[ "$line" =~ ^In[[:space:]]+(.+)[[:space:]]+line[[:space:]]+([0-9]+): ]]; then
            local sc_file="${BASH_REMATCH[1]}"
            local sc_line="${BASH_REMATCH[2]}"
            # Look for the SC code in subsequent lines
            local sc_detail
            sc_detail=$(printf '%s\n' "$input" | grep -A3 "^In ${sc_file} line ${sc_line}:" | grep -E '\^--.*SC[0-9]+' | head -1)
            local _re_sc='(SC[0-9]+)[[:space:]]*\(([^)]+)\):[[:space:]]*(.+)$'
            if [[ "$sc_detail" =~ $_re_sc ]]; then
                local rule="${BASH_REMATCH[1]}"
                local level="${BASH_REMATCH[2]}"
                local msg="${BASH_REMATCH[3]}"
                [[ "$level" == "style" || "$level" == "note" || "$level" == "info" ]] && level="info"
                issues+=("$(_po_lint_entry "$level" "$rule" "$msg" "$sc_file" "$sc_line" "0" "false")")
                if [[ "$level" == "error" ]]; then
                    error_count=$((error_count + 1))
                else
                    warning_count=$((warning_count + 1))
                fi
            fi
        fi
    done <<< "$input"

    local issues_json
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json=$(_po_join_array "${issues[@]}")
    else
        issues_json="[]"
    fi

    printf '{"issues":%s,"error_count":%d,"warning_count":%d}' \
        "$issues_json" "$error_count" "$warning_count"
}

# Parse pylint output
parse_pylint() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a issues=()

    while IFS= read -r line; do
        # Pattern: file:line:col: CODE: message (category)
        # Or: file:line:col: CODE (category) message
        if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+):[[:space:]]*([A-Z][0-9]+):[[:space:]]*(.+)$ ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local col="${BASH_REMATCH[3]}"
            local code="${BASH_REMATCH[4]}"
            local msg="${BASH_REMATCH[5]}"
            local level="warning"
            # Map pylint codes to levels: E=error, W=warning, C=convention, R=refactor
            case "${code:0:1}" in
                E|F) level="error"; error_count=$((error_count + 1)) ;;
                W)   level="warning"; warning_count=$((warning_count + 1)) ;;
                C|R) level="info"; warning_count=$((warning_count + 1)) ;;
            esac
            issues+=("$(_po_lint_entry "$level" "$code" "$msg" "$file" "$ln" "$col" "false")")
        fi
    done <<< "$input"

    local issues_json
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json=$(_po_join_array "${issues[@]}")
    else
        issues_json="[]"
    fi

    printf '{"issues":%s,"error_count":%d,"warning_count":%d}' \
        "$issues_json" "$error_count" "$warning_count"
}

# Parse golangci-lint output
parse_golint() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a issues=()

    while IFS= read -r line; do
        # Pattern: file.go:line:col: message (linter-name)
        if [[ "$line" =~ ^([^:]+\.go):([0-9]+):([0-9]+):[[:space:]]*(.+)[[:space:]]+\(([a-z][a-z0-9_-]+)\)$ ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local col="${BASH_REMATCH[3]}"
            local msg="${BASH_REMATCH[4]}"
            local rule="${BASH_REMATCH[5]}"
            local level="warning"
            ((warning_count++))
            issues+=("$(_po_lint_entry "$level" "$rule" "$msg" "$file" "$ln" "$col" "false")")
        # Pattern without column: file.go:line: message (linter-name)
        elif [[ "$line" =~ ^([^:]+\.go):([0-9]+):[[:space:]]*(.+)[[:space:]]+\(([a-z][a-z0-9_-]+)\)$ ]]; then
            local file="${BASH_REMATCH[1]}"
            local ln="${BASH_REMATCH[2]}"
            local msg="${BASH_REMATCH[3]}"
            local rule="${BASH_REMATCH[4]}"
            local level="warning"
            ((warning_count++))
            issues+=("$(_po_lint_entry "$level" "$rule" "$msg" "$file" "$ln" "0" "false")")
        fi
    done <<< "$input"

    local issues_json
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json=$(_po_join_array "${issues[@]}")
    else
        issues_json="[]"
    fi

    printf '{"issues":%s,"error_count":%d,"warning_count":%d}' \
        "$issues_json" "$error_count" "$warning_count"
}

# Parse generic linter output (best-effort)
parse_generic_lint() {
    local input
    input=$(cat | _po_strip_ansi)
    local error_count=0 warning_count=0
    local -a issues=()

    while IFS= read -r line; do
        local level="warning" rule="" msg="" file="" ln=0 col=0

        # Try file:line:col: level: message
        if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+):[[:space:]]*(error|warning|info|note):[[:space:]]*(.+)$ ]]; then
            file="${BASH_REMATCH[1]}"
            ln="${BASH_REMATCH[2]}"
            col="${BASH_REMATCH[3]}"
            level="${BASH_REMATCH[4]}"
            msg="${BASH_REMATCH[5]}"
        # Try file:line: message
        elif [[ "$line" =~ ^([^:]+):([0-9]+):[[:space:]]*(.+)$ ]]; then
            file="${BASH_REMATCH[1]}"
            ln="${BASH_REMATCH[2]}"
            msg="${BASH_REMATCH[3]}"
        else
            continue
        fi

        issues+=("$(_po_lint_entry "$level" "$rule" "$msg" "$file" "$ln" "$col" "false")")
        if [[ "$level" == "error" ]]; then
            ((error_count++))
        else
            ((warning_count++))
        fi
    done <<< "$input"

    local issues_json
    if [[ ${#issues[@]} -gt 0 ]]; then
        issues_json=$(_po_join_array "${issues[@]}")
    else
        issues_json="[]"
    fi

    printf '{"issues":%s,"error_count":%d,"warning_count":%d}' \
        "$issues_json" "$error_count" "$warning_count"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Extract just the failures/errors from parsed output
# Reads parse_output JSON from stdin, outputs only failures array
parse_failures_only() {
    local input
    input=$(cat)

    # Try "failures" key (test output)
    local extracted
    extracted=$(_po_extract_array "failures" "$input")
    if [[ -n "$extracted" && "$extracted" != "[]" ]]; then
        printf '%s' "$extracted"
        return 0
    fi

    # Try "errors" key (compiler output)
    extracted=$(_po_extract_array "errors" "$input")
    if [[ -n "$extracted" && "$extracted" != "[]" ]]; then
        printf '%s' "$extracted"
        return 0
    fi

    # Try "issues" key (lint output)
    extracted=$(_po_extract_array "issues" "$input")
    if [[ -n "$extracted" && "$extracted" != "[]" ]]; then
        printf '%s' "$extracted"
        return 0
    fi

    printf '[]'
}

# Count total errors across parsed output
# Reads stdin, outputs integer
parse_error_count() {
    local input
    input=$(cat)

    # Check "failed" (test output)
    local count
    count=$(printf '%s' "$input" | grep -oE '"failed":[0-9]+' | grep -oE '[0-9]+')
    if [[ -n "$count" && "$count" -gt 0 ]]; then
        printf '%d' "$count"
        return 0
    fi

    # Check "error_count" (compiler/lint output)
    count=$(printf '%s' "$input" | grep -oE '"error_count":[0-9]+' | grep -oE '[0-9]+')
    if [[ -n "$count" && "$count" -gt 0 ]]; then
        printf '%d' "$count"
        return 0
    fi

    printf '0'
}

# Check if output indicates success (0 failures)
# Reads stdin, returns 0 if no failures
parse_is_success() {
    local count
    count=$(cat | parse_error_count)
    [[ "$count" -eq 0 ]]
}

# Format parsed output as human-readable summary
# Reads parsed JSON from stdin, outputs 1-2 line summary
parse_summary() {
    local input
    input=$(cat)

    # Test output format (has "total" and "passed" keys)
    if printf '%s' "$input" | grep -q '"passed"'; then
        local total passed failed skipped
        total=$(printf '%s' "$input" | grep -oE '"total":[0-9]+' | grep -oE '[0-9]+')
        passed=$(printf '%s' "$input" | grep -oE '"passed":[0-9]+' | grep -oE '[0-9]+')
        failed=$(printf '%s' "$input" | grep -oE '"failed":[0-9]+' | grep -oE '[0-9]+')
        skipped=$(printf '%s' "$input" | grep -oE '"skipped":[0-9]+' | grep -oE '[0-9]+')
        total="${total:-0}"; passed="${passed:-0}"; failed="${failed:-0}"; skipped="${skipped:-0}"

        if [[ $failed -eq 0 ]]; then
            printf 'PASS: %d/%d tests passed' "$passed" "$total"
            [[ $skipped -gt 0 ]] && printf ' (%d skipped)' "$skipped"
        else
            printf 'FAIL: %d/%d tests failed' "$failed" "$total"
            # Extract file:line from failures
            local locations
            locations=$(printf '%s' "$input" | grep -oE '"file":"[^"]*"' | sed 's/"file":"//;s/"//' | head -3)
            if [[ -n "$locations" ]]; then
                local loc_list
                loc_list=$(printf '%s' "$locations" | tr '\n' ', ' | sed 's/,$//')
                printf ' (%s)' "$loc_list"
            fi
        fi
        printf '\n'
        return 0
    fi

    # Lint output format (has "issues" key - check before compiler)
    if printf '%s' "$input" | grep -q '"issues"'; then
        local ec wc
        ec=$(printf '%s' "$input" | grep -oE '"error_count":[0-9]+' | grep -oE '[0-9]+')
        wc=$(printf '%s' "$input" | grep -oE '"warning_count":[0-9]+' | grep -oE '[0-9]+')
        ec="${ec:-0}"; wc="${wc:-0}"
        local total_issues=$((ec + wc))

        if [[ $total_issues -eq 0 ]]; then
            printf 'LINT: clean\n'
        else
            printf 'LINT: %d issues (%d errors, %d warnings)\n' "$total_issues" "$ec" "$wc"
        fi
        return 0
    fi

    # Compiler output format (has "errors" and "error_count" keys)
    if printf '%s' "$input" | grep -q '"error_count"'; then
        local ec wc
        ec=$(printf '%s' "$input" | grep -oE '"error_count":[0-9]+' | grep -oE '[0-9]+')
        wc=$(printf '%s' "$input" | grep -oE '"warning_count":[0-9]+' | grep -oE '[0-9]+')
        ec="${ec:-0}"; wc="${wc:-0}"

        if [[ $ec -eq 0 && $wc -eq 0 ]]; then
            printf 'BUILD: clean (0 errors, 0 warnings)\n'
        elif [[ $ec -eq 0 ]]; then
            printf 'BUILD: %d warnings\n' "$wc"
        else
            printf 'BUILD FAILED: %d errors, %d warnings\n' "$ec" "$wc"
        fi
        return 0
    fi

    printf 'UNKNOWN: unable to parse output format\n'
}

# Extract file:line references from parsed output (for editor integration)
# Reads stdin, outputs "file:line" pairs (one per line)
parse_locations() {
    local input
    input=$(cat)

    # Extract from failures array
    local files lines
    files=$(printf '%s' "$input" | grep -oE '"file":"[^"]*"' | sed 's/"file":"//;s/"//')
    lines=$(printf '%s' "$input" | grep -oE '"line":[0-9]+' | grep -oE '[0-9]+')

    if [[ -n "$files" ]]; then
        paste <(printf '%s\n' "$files") <(printf '%s\n' "$lines") | while IFS=$'\t' read -r f l; do
            if [[ -n "$f" && "$l" -gt 0 ]]; then
                printf '%s:%s\n' "$f" "$l"
            elif [[ -n "$f" ]]; then
                printf '%s\n' "$f"
            fi
        done
    fi
}

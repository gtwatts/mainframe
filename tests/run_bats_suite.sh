#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS_BIN="${BATS_BIN:-$SCRIPT_DIR/bats/bin/bats}"

detect_bats_shell() {
    if [[ -x /opt/homebrew/bin/bash ]]; then
        printf '/opt/homebrew/bin/bash'
    elif [[ -x /usr/local/bin/bash ]]; then
        printf '/usr/local/bin/bash'
    else
        command -v bash
    fi
}

usage() {
    cat <<'EOF'
Usage: tests/run_bats_suite.sh [--scope all|unit|top|integration] [bats args...]

Scopes:
  all          Run the full Bats matrix (default)
  unit         Run tests/unit plus tests/lib contract suites
  top          Run top-level tests/*.bats suites
  integration  Run tests/integration suites

Examples:
  tests/run_bats_suite.sh --scope all
  tests/run_bats_suite.sh --scope unit --formatter tap
  tests/run_bats_suite.sh --scope integration --timing
EOF
}

collect_tests() {
    case "$1" in
        all)
            find "$SCRIPT_DIR/unit" "$SCRIPT_DIR/lib" "$SCRIPT_DIR/integration" -type f -name '*.bats' -print
            find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.bats' -print
            ;;
        unit)
            find "$SCRIPT_DIR/unit" "$SCRIPT_DIR/lib" -type f -name '*.bats' -print
            ;;
        top|top-level|top_level)
            find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.bats' -print
            ;;
        integration)
            find "$SCRIPT_DIR/integration" -type f -name '*.bats' -print
            ;;
        *)
            printf 'Unknown scope: %s\n' "$1" >&2
            return 1
            ;;
    esac | LC_ALL=C sort
}

scope="all"
declare -a bats_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -ge 2 ]] || {
                printf '--scope requires a value\n' >&2
                exit 2
            }
            scope="$2"
            shift 2
            ;;
        --scope=*)
            scope="${1#*=}"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            bats_args+=("$1")
            shift
            ;;
    esac
done

if [[ ! -x "$BATS_BIN" ]]; then
    printf 'BATS not found at %s. Run `make test-deps` first.\n' "$BATS_BIN" >&2
    exit 1
fi

if [[ -z "${BATS_TEST_SHELL:-}" ]]; then
    BATS_TEST_SHELL="$(detect_bats_shell)"
    export BATS_TEST_SHELL
fi

manifest="$(mktemp "${TMPDIR:-/tmp}/mainframe-bats.XXXXXX")"
trap 'rm -f "$manifest"' EXIT

collect_tests "$scope" > "$manifest"

if [[ ! -s "$manifest" ]]; then
    printf 'No test files found for scope=%s\n' "$scope" >&2
    exit 1
fi

declare -a test_files=()
while IFS= read -r test_file; do
    test_files+=("$test_file")
done < "$manifest"

printf 'Running Bats scope=%s (%d files) with shell=%s\n' \
    "$scope" "${#test_files[@]}" "$BATS_TEST_SHELL" >&2

for test_file in "${test_files[@]}"; do
    printf '==> %s\n' "$test_file" >&2
    "$BATS_BIN" --print-output-on-failure "${bats_args[@]}" "$test_file"
done

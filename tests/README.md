# Basher Test Suite

This directory contains the comprehensive test suite for Basher using [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Directory Structure

```
tests/
├── unit/               # Unit tests for individual scripts
│   ├── data/           # Data transformation script tests
│   ├── agent/          # Agent orchestration tests
│   ├── git/            # Git workflow tests
│   ├── file/           # File operation tests
│   ├── api/            # API/webhook tests
│   └── dev/            # Developer utility tests
├── integration/        # Integration tests
│   ├── workflows/      # End-to-end workflow tests
│   └── hooks/          # Hook system tests
├── fixtures/           # Test data files
│   ├── json/           # Sample JSON files
│   ├── csv/            # Sample CSV files
│   ├── yaml/           # Sample YAML files
│   └── xml/            # Sample XML files
├── helpers/            # Test helper functions
│   ├── setup.bash      # Common setup functions
│   ├── assertions.bash # Custom assertions
│   └── mocks.bash      # Mock functions
├── bats/               # BATS core (git submodule)
├── bats-support/       # BATS support library (git submodule)
├── bats-assert/        # BATS assertion library (git submodule)
├── bats-file/          # BATS file assertions (git submodule)
└── run_bats_suite.sh   # Canonical Bats test runner
```

## Prerequisites

```bash
# Install BATS and helpers (handled by make)
make test-deps

# Or manually:
git submodule update --init --recursive
```

## Running Tests

```bash
# Run all tests
make test

# Run the same full Bats matrix directly
./tests/run_bats_suite.sh --scope all

# Run unit + contract suites
./tests/run_bats_suite.sh --scope unit

# Run top-level suites in tests/*.bats
./tests/run_bats_suite.sh --scope top

# Run integration suites
./tests/run_bats_suite.sh --scope integration

# Run specific test file
bats tests/unit/data/json-to-csv.bats

# Run tests matching pattern
bats tests/unit/data/*.bats

# Run with verbose output
bats --verbose-run tests/unit/

# Run with timing
bats --timing tests/unit/

# Generate TAP output for CI
./tests/run_bats_suite.sh --scope all --formatter tap > results.tap
```

## Test Naming Convention

- Test files: `{script-name}.bats`
- Test names: Descriptive sentences
- Example: `json-to-csv.bats`

```bash
@test "json-to-csv converts simple array to CSV" {
    # test code
}

@test "json-to-csv handles nested objects with flattening" {
    # test code
}

@test "json-to-csv fails gracefully on invalid JSON" {
    # test code
}
```

## Writing Tests

### Basic Test Structure

```bash
#!/usr/bin/env bats

load '../helpers/setup'
load '../helpers/assertions'

setup() {
    # Run before each test
    common_setup
    TEST_DIR="$(temp_make)"
}

teardown() {
    # Run after each test
    temp_del "$TEST_DIR"
}

@test "script does expected thing" {
    run json-to-csv fixtures/json/simple.json
    assert_success
    assert_output --partial "expected output"
}

@test "script fails on invalid input" {
    run json-to-csv "not-a-file.json"
    assert_failure
    assert_output --partial "not found"
}
```

### Using Fixtures

```bash
@test "processes fixture file correctly" {
    local input="$BATS_TEST_DIRNAME/../fixtures/json/users.json"
    local expected="$BATS_TEST_DIRNAME/../fixtures/csv/users.csv"

    run json-to-csv "$input"
    assert_success
    assert_output "$(cat "$expected")"
}
```

### Mocking Commands

```bash
load '../helpers/mocks'

@test "handles curl failure gracefully" {
    # Mock curl to fail
    mock_command curl 'echo "Connection refused"; exit 1'

    run http-request "https://example.com/api"
    assert_failure
    assert_output --partial "Connection refused"

    unmock_command curl
}
```

### Testing with Stdin

```bash
@test "reads JSON from stdin" {
    run bash -c 'echo '\''{"a": 1}'\'' | json-to-csv'
    assert_success
    assert_output "a"$'\n'"1"
}
```

## Custom Assertions

Defined in `helpers/assertions.bash`:

```bash
# Assert output is valid JSON
assert_valid_json() {
    jq empty <<< "$output"
}

# Assert output is valid CSV
assert_valid_csv() {
    # Uses csvkit to validate
    csvclean -n <<< "$output"
}

# Assert file exists with content
assert_file_contains() {
    local file="$1"
    local content="$2"
    assert_file_exists "$file"
    grep -q "$content" "$file"
}

# Assert exit code
assert_exit_code() {
    local expected="$1"
    assert_equal "$status" "$expected"
}
```

## Coverage Requirements

| Category | Required Coverage |
|----------|-------------------|
| Library functions | 90% |
| Core scripts | 80% |
| Utility scripts | 70% |
| Hooks | 60% |

## CI/CD Integration

Tests run automatically on:
- Every push to `main`
- Every pull request
- Nightly scheduled runs

See `.github/workflows/test.yml` for details.

## Performance Testing

```bash
# Run performance tests
make test-perf

# Benchmark specific script
hyperfine --warmup 3 'json-to-csv large-file.json'
```

## Debugging Failed Tests

```bash
# Run single test with debug output
BASHER_LOG_LEVEL=0 bats --verbose-run tests/unit/data/json-to-csv.bats

# Keep test artifacts
BATS_TEST_KEEP_TEMPS=1 bats tests/unit/data/json-to-csv.bats

# Step through test
bash -x scripts/data/json-to-csv input.json
```

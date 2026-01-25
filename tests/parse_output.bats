#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Parse Output Library Tests
# =============================================================================
# Tests for lib/parse_output.sh - Universal test/build/lint output parsers
# =============================================================================

load 'test_helper'

setup() {
    source_lib "parse_output"
    TEST_DIR=$(create_test_dir "parse_output")
    mkdir -p "$TEST_DIR/fixtures"
    _create_fixtures
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# FIXTURE CREATION
# =============================================================================

_create_fixtures() {
    # Jest output - passing
    cat > "$TEST_DIR/fixtures/jest_pass.txt" << 'EOF'
 PASS  src/utils.test.ts
  Utils
    ✓ should add numbers (3 ms)
    ✓ should subtract numbers (1 ms)
    ✓ should multiply (1 ms)

Test Suites: 1 passed, 1 total
Tests:       3 passed, 3 total
Snapshots:   0 total
Time:        1.234 s
EOF

    # Jest output - with failures
    cat > "$TEST_DIR/fixtures/jest_fail.txt" << 'EOF'
 FAIL  src/auth.test.ts
  ● AuthService > should validate token

    expect(received).toBe(expected)

    Expected: true
    Received: false

      at Object.<anonymous> (src/auth.test.ts:42:18)

  ● AuthService > should reject expired token

    TypeError: Cannot read property 'exp' of undefined

      at Object.<anonymous> (src/auth.test.ts:58:12)

 PASS  src/utils.test.ts

Test Suites: 1 failed, 1 passed, 2 total
Tests:       2 failed, 1 skipped, 5 passed, 8 total
Snapshots:   0 total
Time:        3.456 s
EOF

    # pytest output - passing
    cat > "$TEST_DIR/fixtures/pytest_pass.txt" << 'EOF'
============================= test session starts ==============================
collected 12 items

tests/test_auth.py ......                                              [ 50%]
tests/test_users.py ......                                             [100%]

============================== 12 passed in 2.34s ==============================
EOF

    # pytest output - with failures
    cat > "$TEST_DIR/fixtures/pytest_fail.txt" << 'EOF'
============================= test session starts ==============================
collected 10 items

tests/test_auth.py ...F..                                              [ 60%]
tests/test_users.py ..F.                                               [100%]

=================================== FAILURES ===================================
FAILED tests/test_auth.py::TestAuth::test_login - AssertionError: expected 200
FAILED tests/test_users.py::TestUsers::test_create - ValueError: invalid email

=========================== short test summary info ============================
FAILED tests/test_auth.py::TestAuth::test_login
FAILED tests/test_users.py::TestUsers::test_create
========================= 2 failed, 8 passed in 1.56s =========================
EOF

    # go test output - with failures
    cat > "$TEST_DIR/fixtures/go_test_fail.txt" << 'EOF'
=== RUN   TestAdd
--- PASS: TestAdd (0.01s)
=== RUN   TestSubtract
--- PASS: TestSubtract (0.00s)
=== RUN   TestDivide
    math_test.go:42: expected 5.0, got 0.0
--- FAIL: TestDivide (0.01s)
=== RUN   TestMultiply
--- PASS: TestMultiply (0.00s)
FAIL	example.com/math	0.123s
EOF

    # go test output - all passing
    cat > "$TEST_DIR/fixtures/go_test_pass.txt" << 'EOF'
=== RUN   TestAdd
--- PASS: TestAdd (0.01s)
=== RUN   TestSubtract
--- PASS: TestSubtract (0.02s)
ok  	example.com/math	0.050s
EOF

    # BATS output - with failures
    cat > "$TEST_DIR/fixtures/bats_fail.txt" << 'EOF'
1..5
ok 1 should parse strings
ok 2 should handle empty input
not ok 3 should validate email
# (in test file tests/validate.bats, line 28)
#   `assert_equal "true" "$result"' failed
ok 4 should trim whitespace
not ok 5 should reject invalid
# (in test file tests/validate.bats, line 45)
#   expected empty string
EOF

    # BATS output - all passing
    cat > "$TEST_DIR/fixtures/bats_pass.txt" << 'EOF'
1..4
ok 1 should parse JSON
ok 2 should create objects
ok 3 should handle arrays
ok 4 should escape strings
EOF

    # GCC output
    cat > "$TEST_DIR/fixtures/gcc.txt" << 'EOF'
main.c:10:5: error: use of undeclared identifier 'x'
    int y = x + 1;
            ^
main.c:15:12: warning: unused variable 'z' [-Wunused-variable]
    int z = 42;
        ^
util.c:8:3: note: declared here
EOF

    # rustc output
    cat > "$TEST_DIR/fixtures/rustc.txt" << 'EOF'
error[E0382]: use of moved value: `s`
  --> src/main.rs:5:20
   |
5  |     let s2 = s;
   |              - value moved here
6  |     println!("{}", s);
   |                    ^ value used here after move

warning[W0001]: unused import
  --> src/main.rs:1:5
   |
1  | use std::io;
   |     ^^^^^^^
EOF

    # TypeScript tsc output
    cat > "$TEST_DIR/fixtures/tsc.txt" << 'EOF'
src/index.ts(10,5): error TS2322: Type 'string' is not assignable to type 'number'.
src/index.ts(15,12): error TS2304: Cannot find name 'foo'.
src/utils.ts(3,1): warning TS6133: 'x' is declared but its value is never read.
EOF

    # ESLint output
    cat > "$TEST_DIR/fixtures/eslint.txt" << 'EOF'
/home/user/project/src/index.ts
  2:10  error    'foo' is defined but never used   no-unused-vars
  5:1   warning  Unexpected console statement      no-console
  8:15  error    Missing semicolon                 semi

/home/user/project/src/utils.ts
  12:5  warning  'x' is assigned but never used    no-unused-vars

4 problems (2 errors, 2 warnings)
EOF

    # ShellCheck output (GCC format)
    cat > "$TEST_DIR/fixtures/shellcheck.txt" << 'EOF'
script.sh:10:3: warning: Use 'cd ... || exit' in case cd fails. [SC2164]
script.sh:15:8: error: Double quote to prevent globbing and word splitting. [SC2086]
script.sh:22:1: note: Use $(...) notation instead of legacy backticks. [SC2006]
EOF

    # pylint output
    cat > "$TEST_DIR/fixtures/pylint.txt" << 'EOF'
app/main.py:5:0: C0114: Missing module docstring (missing-module-docstring)
app/main.py:12:4: E0602: Undefined variable 'undefined_var' (undefined-variable)
app/main.py:18:0: W0611: Unused import os (unused-import)
app/utils.py:3:0: R0903: Too few public methods (1/2) (too-few-public-methods)
EOF

    # golangci-lint output
    cat > "$TEST_DIR/fixtures/golint.txt" << 'EOF'
main.go:10:2: S1000: should use for range instead of for { select {} } (gosimple)
main.go:15:5: unused variable 'x' (deadcode)
util.go:8:12: error return value not checked (errcheck)
EOF

    # Empty output
    cat > "$TEST_DIR/fixtures/empty.txt" << 'EOF'
EOF

    # go build output
    cat > "$TEST_DIR/fixtures/go_build.txt" << 'EOF'
./main.go:10:5: undefined: foo
./main.go:15:12: cannot use x (variable of type string) as type int
./util.go:3:8: imported and not used: "fmt"
EOF
}

# =============================================================================
# FORMAT DETECTION TESTS
# =============================================================================

@test "parse_detect_format: detects Jest output" {
    result=$(cat "$TEST_DIR/fixtures/jest_pass.txt" | parse_detect_format)
    assert_equal "jest" "$result"
}

@test "parse_detect_format: detects pytest output" {
    result=$(cat "$TEST_DIR/fixtures/pytest_pass.txt" | parse_detect_format)
    assert_equal "pytest" "$result"
}

@test "parse_detect_format: detects go test output" {
    result=$(cat "$TEST_DIR/fixtures/go_test_pass.txt" | parse_detect_format)
    assert_equal "go_test" "$result"
}

@test "parse_detect_format: detects BATS output" {
    result=$(cat "$TEST_DIR/fixtures/bats_pass.txt" | parse_detect_format)
    assert_equal "bats" "$result"
}

@test "parse_detect_format: detects GCC output" {
    result=$(cat "$TEST_DIR/fixtures/gcc.txt" | parse_detect_format)
    assert_equal "gcc" "$result"
}

@test "parse_detect_format: detects ShellCheck output" {
    result=$(cat "$TEST_DIR/fixtures/shellcheck.txt" | parse_detect_format)
    assert_equal "shellcheck" "$result"
}

@test "parse_detect_format: detects ESLint output" {
    result=$(cat "$TEST_DIR/fixtures/eslint.txt" | parse_detect_format)
    assert_equal "eslint" "$result"
}

@test "parse_detect_format: detects rustc output" {
    result=$(cat "$TEST_DIR/fixtures/rustc.txt" | parse_detect_format)
    assert_equal "rust" "$result"
}

@test "parse_detect_format: detects TypeScript tsc output" {
    result=$(cat "$TEST_DIR/fixtures/tsc.txt" | parse_detect_format)
    assert_equal "typescript" "$result"
}

@test "parse_detect_format: detects pylint output" {
    result=$(cat "$TEST_DIR/fixtures/pylint.txt" | parse_detect_format)
    assert_equal "pylint" "$result"
}

@test "parse_detect_format: detects golangci-lint output" {
    result=$(cat "$TEST_DIR/fixtures/golint.txt" | parse_detect_format)
    assert_equal "golint" "$result"
}

@test "parse_detect_format: returns generic for unknown input" {
    result=$(echo "some random text" | parse_detect_format)
    assert_equal "generic" "$result"
}

# =============================================================================
# JEST PARSER TESTS
# =============================================================================

@test "parse_jest: parses passing output" {
    result=$(cat "$TEST_DIR/fixtures/jest_pass.txt" | parse_jest)
    assert_contains "$result" '"total":3'
    assert_contains "$result" '"passed":3'
    assert_contains "$result" '"failed":0'
    assert_contains "$result" '"failures":[]'
}

@test "parse_jest: parses failure output with counts" {
    result=$(cat "$TEST_DIR/fixtures/jest_fail.txt" | parse_jest)
    assert_contains "$result" '"total":8'
    assert_contains "$result" '"passed":5'
    assert_contains "$result" '"failed":2'
    assert_contains "$result" '"skipped":1'
}

@test "parse_jest: extracts failure details" {
    result=$(cat "$TEST_DIR/fixtures/jest_fail.txt" | parse_jest)
    assert_contains "$result" '"test":"AuthService > should validate token"'
    assert_contains "$result" 'src/auth.test.ts'
}

@test "parse_jest: parses duration" {
    result=$(cat "$TEST_DIR/fixtures/jest_fail.txt" | parse_jest)
    assert_contains "$result" '"duration_ms":3456'
}

@test "parse_jest: handles empty input" {
    result=$(echo "" | parse_jest)
    assert_contains "$result" '"total":0'
    assert_contains "$result" '"failures":[]'
}

# =============================================================================
# PYTEST PARSER TESTS
# =============================================================================

@test "parse_pytest: parses passing output" {
    result=$(cat "$TEST_DIR/fixtures/pytest_pass.txt" | parse_pytest)
    assert_contains "$result" '"passed":12'
    assert_contains "$result" '"failed":0'
    assert_contains "$result" '"total":12'
}

@test "parse_pytest: parses failure output" {
    result=$(cat "$TEST_DIR/fixtures/pytest_fail.txt" | parse_pytest)
    assert_contains "$result" '"failed":2'
    assert_contains "$result" '"passed":8'
    assert_contains "$result" '"total":10'
}

@test "parse_pytest: extracts failure names" {
    result=$(cat "$TEST_DIR/fixtures/pytest_fail.txt" | parse_pytest)
    assert_contains "$result" 'test_login'
    assert_contains "$result" 'test_create'
}

@test "parse_pytest: parses duration" {
    result=$(cat "$TEST_DIR/fixtures/pytest_pass.txt" | parse_pytest)
    assert_contains "$result" '"duration_ms":2340'
}

# =============================================================================
# GO TEST PARSER TESTS
# =============================================================================

@test "parse_go_test: parses passing output" {
    result=$(cat "$TEST_DIR/fixtures/go_test_pass.txt" | parse_go_test)
    assert_contains "$result" '"passed":2'
    assert_contains "$result" '"failed":0'
    assert_contains "$result" '"total":2'
}

@test "parse_go_test: parses failure output" {
    result=$(cat "$TEST_DIR/fixtures/go_test_fail.txt" | parse_go_test)
    assert_contains "$result" '"passed":3'
    assert_contains "$result" '"failed":1'
    assert_contains "$result" '"total":4'
}

@test "parse_go_test: extracts failure test name" {
    result=$(cat "$TEST_DIR/fixtures/go_test_fail.txt" | parse_go_test)
    assert_contains "$result" '"test":"TestDivide"'
}

@test "parse_go_test: extracts file reference" {
    result=$(cat "$TEST_DIR/fixtures/go_test_fail.txt" | parse_go_test)
    assert_contains "$result" 'math_test.go'
}

# =============================================================================
# BATS PARSER TESTS
# =============================================================================

@test "parse_bats: parses passing output" {
    result=$(cat "$TEST_DIR/fixtures/bats_pass.txt" | parse_bats)
    assert_contains "$result" '"total":4'
    assert_contains "$result" '"passed":4'
    assert_contains "$result" '"failed":0'
}

@test "parse_bats: parses failure output" {
    result=$(cat "$TEST_DIR/fixtures/bats_fail.txt" | parse_bats)
    assert_contains "$result" '"total":5'
    assert_contains "$result" '"passed":3'
    assert_contains "$result" '"failed":2'
}

@test "parse_bats: extracts failure file and line" {
    result=$(cat "$TEST_DIR/fixtures/bats_fail.txt" | parse_bats)
    assert_contains "$result" 'tests/validate.bats'
    assert_contains "$result" '"line":28'
}

# =============================================================================
# GCC PARSER TESTS
# =============================================================================

@test "parse_gcc: parses errors and warnings" {
    result=$(cat "$TEST_DIR/fixtures/gcc.txt" | parse_gcc)
    assert_contains "$result" '"error_count":1'
    assert_contains "$result" '"warning_count":1'
}

@test "parse_gcc: extracts error details" {
    result=$(cat "$TEST_DIR/fixtures/gcc.txt" | parse_gcc)
    assert_contains "$result" '"file":"main.c"'
    assert_contains "$result" '"line":10'
    assert_contains "$result" '"column":5'
    assert_contains "$result" "use of undeclared identifier"
}

@test "parse_gcc: extracts warning flag code" {
    result=$(cat "$TEST_DIR/fixtures/gcc.txt" | parse_gcc)
    assert_contains "$result" '"-Wunused-variable"'
}

# =============================================================================
# RUST PARSER TESTS
# =============================================================================

@test "parse_rust: parses errors and warnings" {
    result=$(cat "$TEST_DIR/fixtures/rustc.txt" | parse_rust)
    assert_contains "$result" '"error_count":1'
    assert_contains "$result" '"warning_count":1'
}

@test "parse_rust: extracts error code" {
    result=$(cat "$TEST_DIR/fixtures/rustc.txt" | parse_rust)
    assert_contains "$result" '"code":"E0382"'
}

@test "parse_rust: extracts file location" {
    result=$(cat "$TEST_DIR/fixtures/rustc.txt" | parse_rust)
    assert_contains "$result" '"file":"src/main.rs"'
    assert_contains "$result" '"line":5'
}

# =============================================================================
# TYPESCRIPT COMPILER TESTS
# =============================================================================

@test "parse_typescript_compiler: parses errors" {
    result=$(cat "$TEST_DIR/fixtures/tsc.txt" | parse_typescript_compiler)
    assert_contains "$result" '"error_count":2'
    assert_contains "$result" '"warning_count":1'
}

@test "parse_typescript_compiler: extracts TS error codes" {
    result=$(cat "$TEST_DIR/fixtures/tsc.txt" | parse_typescript_compiler)
    assert_contains "$result" '"code":"TS2322"'
    assert_contains "$result" '"code":"TS2304"'
}

# =============================================================================
# ESLINT PARSER TESTS
# =============================================================================

@test "parse_eslint: parses errors and warnings" {
    result=$(cat "$TEST_DIR/fixtures/eslint.txt" | parse_eslint)
    assert_contains "$result" '"error_count":2'
    assert_contains "$result" '"warning_count":2'
}

@test "parse_eslint: extracts rule names" {
    result=$(cat "$TEST_DIR/fixtures/eslint.txt" | parse_eslint)
    assert_contains "$result" '"rule":"no-unused-vars"'
    assert_contains "$result" '"rule":"no-console"'
    assert_contains "$result" '"rule":"semi"'
}

@test "parse_eslint: associates issues with correct files" {
    result=$(cat "$TEST_DIR/fixtures/eslint.txt" | parse_eslint)
    assert_contains "$result" '/home/user/project/src/index.ts'
    assert_contains "$result" '/home/user/project/src/utils.ts'
}

# =============================================================================
# SHELLCHECK PARSER TESTS
# =============================================================================

@test "parse_shellcheck: parses all severity levels" {
    result=$(cat "$TEST_DIR/fixtures/shellcheck.txt" | parse_shellcheck)
    assert_contains "$result" '"error_count":1'
    assert_contains "$result" '"warning_count":2'
}

@test "parse_shellcheck: extracts SC codes" {
    result=$(cat "$TEST_DIR/fixtures/shellcheck.txt" | parse_shellcheck)
    assert_contains "$result" '"rule":"SC2164"'
    assert_contains "$result" '"rule":"SC2086"'
}

# =============================================================================
# PYLINT PARSER TESTS
# =============================================================================

@test "parse_pylint: parses error levels correctly" {
    result=$(cat "$TEST_DIR/fixtures/pylint.txt" | parse_pylint)
    assert_contains "$result" '"error_count":1'
}

@test "parse_pylint: extracts pylint codes" {
    result=$(cat "$TEST_DIR/fixtures/pylint.txt" | parse_pylint)
    assert_contains "$result" '"rule":"E0602"'
    assert_contains "$result" '"rule":"C0114"'
}

# =============================================================================
# GO BUILD PARSER TESTS
# =============================================================================

@test "parse_go_build: parses build errors" {
    result=$(cat "$TEST_DIR/fixtures/go_build.txt" | parse_go_build)
    assert_contains "$result" '"error_count":3'
}

@test "parse_go_build: extracts file and line" {
    result=$(cat "$TEST_DIR/fixtures/go_build.txt" | parse_go_build)
    assert_contains "$result" '"file":"main.go"'
    assert_contains "$result" '"line":10'
}

# =============================================================================
# GOLINT PARSER TESTS
# =============================================================================

@test "parse_golint: parses lint issues" {
    result=$(cat "$TEST_DIR/fixtures/golint.txt" | parse_golint)
    assert_contains "$result" '"warning_count":3'
}

@test "parse_golint: extracts linter names as rules" {
    result=$(cat "$TEST_DIR/fixtures/golint.txt" | parse_golint)
    assert_contains "$result" '"rule":"gosimple"'
    assert_contains "$result" '"rule":"errcheck"'
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "parse_error_count: returns failed count from test output" {
    result=$(cat "$TEST_DIR/fixtures/jest_fail.txt" | parse_jest | parse_error_count)
    assert_equal "2" "$result"
}

@test "parse_error_count: returns 0 for passing tests" {
    result=$(cat "$TEST_DIR/fixtures/jest_pass.txt" | parse_jest | parse_error_count)
    assert_equal "0" "$result"
}

@test "parse_is_success: returns 0 for passing tests" {
    cat "$TEST_DIR/fixtures/jest_pass.txt" | parse_jest | parse_is_success
}

@test "parse_is_success: returns non-zero for failures" {
    ! (cat "$TEST_DIR/fixtures/jest_fail.txt" | parse_jest | parse_is_success)
}

@test "parse_summary: formats passing test summary" {
    result=$(cat "$TEST_DIR/fixtures/bats_pass.txt" | parse_bats | parse_summary)
    assert_contains "$result" "PASS: 4/4 tests passed"
}

@test "parse_summary: formats failing test summary" {
    result=$(cat "$TEST_DIR/fixtures/bats_fail.txt" | parse_bats | parse_summary)
    assert_contains "$result" "FAIL: 2/5 tests failed"
}

@test "parse_summary: formats build failure summary" {
    result=$(cat "$TEST_DIR/fixtures/gcc.txt" | parse_gcc | parse_summary)
    assert_contains "$result" "BUILD FAILED: 1 errors"
}

@test "parse_summary: formats clean lint summary" {
    result=$(echo '{"issues":[],"error_count":0,"warning_count":0}' | parse_summary)
    assert_contains "$result" "LINT: clean"
}

@test "parse_locations: extracts file:line pairs" {
    result=$(cat "$TEST_DIR/fixtures/gcc.txt" | parse_gcc | parse_locations)
    assert_contains "$result" "main.c:10"
    assert_contains "$result" "main.c:15"
}

@test "parse_output: auto-detects and parses jest" {
    result=$(cat "$TEST_DIR/fixtures/jest_pass.txt" | parse_output --format auto)
    assert_contains "$result" '"passed":3'
}

@test "parse_output: accepts explicit format" {
    result=$(cat "$TEST_DIR/fixtures/gcc.txt" | parse_output --format gcc)
    assert_contains "$result" '"error_count":1'
}

@test "parse_failures_only: extracts failures array" {
    result=$(cat "$TEST_DIR/fixtures/jest_fail.txt" | parse_jest | parse_failures_only)
    assert_contains "$result" '"test":'
}

@test "parse_failures_only: returns empty array for no failures" {
    result=$(cat "$TEST_DIR/fixtures/jest_pass.txt" | parse_jest | parse_failures_only)
    assert_equal "[]" "$result"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "parse_jest: handles empty input gracefully" {
    result=$(echo "" | parse_jest)
    assert_contains "$result" '"total":0'
    assert_contains "$result" '"passed":0'
    assert_contains "$result" '"failed":0'
}

@test "parse_gcc: handles empty input gracefully" {
    result=$(echo "" | parse_gcc)
    assert_contains "$result" '"error_count":0'
    assert_contains "$result" '"errors":[]'
}

@test "parse_eslint: handles empty input gracefully" {
    result=$(echo "" | parse_eslint)
    assert_contains "$result" '"error_count":0'
    assert_contains "$result" '"issues":[]'
}

@test "parse_generic_test: handles unknown test output" {
    local input="PASS test_one
PASS test_two
FAIL test_three: expected 5 got 3
3 tests, 1 failure"
    result=$(printf '%s' "$input" | parse_generic_test)
    assert_contains "$result" '"failed":'
    assert_contains "$result" '"passed":'
}

@test "parse_generic_compiler: handles unknown compiler output" {
    local input="src/foo.c:10:5: error: something went wrong
src/bar.c:20:1: warning: unused variable"
    result=$(printf '%s' "$input" | parse_generic_compiler)
    assert_contains "$result" '"error_count":1'
    assert_contains "$result" '"warning_count":1'
}

@test "parse_bats: handles skipped tests" {
    local input="1..3
ok 1 test one
ok 2 test two # skip reason
ok 3 test three"
    result=$(printf '%s' "$input" | parse_bats)
    assert_contains "$result" '"total":3'
    assert_contains "$result" '"passed":2'
    assert_contains "$result" '"skipped":1'
}

@test "parse_summary: formats lint issues summary" {
    result=$(echo '{"issues":[{"level":"error"}],"error_count":2,"warning_count":5}' | parse_summary)
    assert_contains "$result" "LINT: 7 issues (2 errors, 5 warnings)"
}

@test "parse_summary: formats build with warnings only" {
    result=$(echo '{"errors":[],"error_count":0,"warning_count":3}' | parse_summary)
    assert_contains "$result" "BUILD: 3 warnings"
}

@test "parse_go_test: parses package-level duration" {
    result=$(cat "$TEST_DIR/fixtures/go_test_pass.txt" | parse_go_test)
    assert_contains "$result" '"duration_ms":50'
}

@test "parse_locations: returns empty for no locations" {
    result=$(echo '{"total":3,"passed":3,"failed":0,"skipped":0,"duration_ms":100,"failures":[]}' | parse_locations)
    [[ -z "$result" ]]
}

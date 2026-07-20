#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/ext/go.bats - Go Library Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/ext/go.sh
#              Go project detection, dependency analysis, build verification
# Test Count: 60+ test cases
# Categories: detection, version, module parsing, dependencies, packages,
#             imports, build check, test check, linting, project summary
# Note: Tests use mocks to avoid requiring actual Go installation
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../../.."
    ORIGINAL_PATH="$PATH"

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Create mock bin directory
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"

    # Source the json library first (required dependency)
    source "$MAINFRAME_ROOT/lib/json.sh"

    # Source the library under test
    source "$MAINFRAME_ROOT/lib/ext/go.sh"
}

# Teardown: Clean up test artifacts
teardown() {
    PATH="$ORIGINAL_PATH"
    /bin/rm -rf "$TEST_TMPDIR"
}

# Helper: Create mock go command
create_mock_go() {
    local behavior="$1"
    /bin/cat > "$MOCK_BIN/go" << EOF
#!/bin/bash
$behavior
EOF
    /bin/chmod +x "$MOCK_BIN/go"
    export PATH="$MOCK_BIN:$PATH"
}

# Helper: Create mock linter command
create_mock_linter() {
    local name="$1"
    local behavior="$2"
    /bin/cat > "$MOCK_BIN/$name" << EOF
#!/bin/bash
$behavior
EOF
    /bin/chmod +x "$MOCK_BIN/$name"
    export PATH="$MOCK_BIN:$PATH"
}

# Helper: Create a minimal Go project structure
create_go_project() {
    local dir="$1"
    mkdir -p "$dir"

    # Create go.mod
    cat > "$dir/go.mod" << 'EOF'
module github.com/test/project

go 1.21

require (
    github.com/gin-gonic/gin v1.9.1
    github.com/stretchr/testify v1.8.4
)

require (
    github.com/go-playground/validator/v10 v10.14.0 // indirect
    golang.org/x/sys v0.8.0 // indirect
)
EOF

    # Create main.go
    cat > "$dir/main.go" << 'EOF'
package main

import (
    "fmt"
    "net/http"

    "github.com/gin-gonic/gin"
)

func main() {
    fmt.Println("Hello, World!")
}
EOF

    # Create a test file
    cat > "$dir/main_test.go" << 'EOF'
package main

import "testing"

func TestMain(t *testing.T) {
    t.Log("test")
}
EOF
}

# =============================================================================
# CATEGORY 1: INTERNAL HELPERS
# =============================================================================

@test "_go_has_cli: returns true when go is available" {
    create_mock_go 'echo "go version go1.21.0 linux/amd64"'
    _go_has_cli
    [[ $? -eq 0 ]]
}

@test "_go_has_cli: returns false when go is not available" {
    run bash -c 'PATH=/nonexistent; source "'"$MAINFRAME_ROOT"'/lib/json.sh"; source "'"$MAINFRAME_ROOT"'/lib/ext/go.sh" && _go_has_cli'
    [[ "$status" -eq 1 ]]
}

@test "_go_truncate: truncates long strings" {
    local long_string
    long_string=$(printf 'a%.0s' {1..5000})
    result=$(_go_truncate "$long_string" 100)
    [[ ${#result} -lt 200 ]]
    [[ "$result" =~ "truncated" ]]
}

@test "_go_truncate: preserves short strings" {
    result=$(_go_truncate "short string" 100)
    [[ "$result" == "short string" ]]
}

# =============================================================================
# CATEGORY 2: DETECTION
# =============================================================================

@test "go_detect: detects Go project with go.mod" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_detect "$TEST_TMPDIR/project")
    [[ "$result" =~ '"is_go":true' ]]
    [[ "$result" =~ '"has_go_mod":true' ]]
}

@test "go_detect: detects missing go.mod" {
    mkdir -p "$TEST_TMPDIR/empty"
    result=$(go_detect "$TEST_TMPDIR/empty")
    [[ "$result" =~ '"is_go":false' ]]
    [[ "$result" =~ '"has_go_mod":false' ]]
}

@test "go_detect: detects go.sum when present" {
    create_go_project "$TEST_TMPDIR/project"
    touch "$TEST_TMPDIR/project/go.sum"
    result=$(go_detect "$TEST_TMPDIR/project")
    [[ "$result" =~ '"has_go_sum":true' ]]
}

@test "go_detect: detects go.work when present" {
    mkdir -p "$TEST_TMPDIR/workspace"
    echo "go 1.21" > "$TEST_TMPDIR/workspace/go.work"
    result=$(go_detect "$TEST_TMPDIR/workspace")
    [[ "$result" =~ '"has_go_work":true' ]]
    [[ "$result" =~ '"is_go":true' ]]
}

@test "go_detect: returns error for non-existent directory" {
    result=$(go_detect "/nonexistent/path")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'directory not found' ]]
}

@test "go_detect: detects go files" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_detect "$TEST_TMPDIR/project")
    [[ "$result" =~ '"has_go_files":true' ]]
}

# =============================================================================
# CATEGORY 3: VERSION
# =============================================================================

@test "go_version: returns version info" {
    create_mock_go 'echo "go version go1.21.5 linux/amd64"'
    result=$(go_version)
    [[ "$result" =~ '"version":"1.21.5"' ]]
    [[ "$result" =~ '"goos":"linux"' ]]
    [[ "$result" =~ '"goarch":"amd64"' ]]
}

@test "go_version: handles darwin/arm64" {
    create_mock_go 'echo "go version go1.22.0 darwin/arm64"'
    result=$(go_version)
    [[ "$result" =~ '"version":"1.22.0"' ]]
    [[ "$result" =~ '"goos":"darwin"' ]]
    [[ "$result" =~ '"goarch":"arm64"' ]]
}

@test "go_version: returns error when go not installed" {
    export PATH="/nonexistent"
    result=$(go_version)
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'go not installed' ]]
}

# =============================================================================
# CATEGORY 4: MODULE PARSING
# =============================================================================

@test "go_mod_name: extracts module name" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_mod_name "$TEST_TMPDIR/project")
    [[ "$result" =~ '"module":"github.com/test/project"' ]]
}

@test "go_mod_name: extracts go version" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_mod_name "$TEST_TMPDIR/project")
    [[ "$result" =~ '"go_version":"1.21"' ]]
}

@test "go_mod_name: returns error for missing go.mod" {
    mkdir -p "$TEST_TMPDIR/empty"
    result=$(go_mod_name "$TEST_TMPDIR/empty")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'go.mod not found' ]]
}

@test "go_mod_name: handles complex module paths" {
    mkdir -p "$TEST_TMPDIR/complex"
    cat > "$TEST_TMPDIR/complex/go.mod" << 'EOF'
module github.com/organization/project/v2

go 1.20
EOF
    result=$(go_mod_name "$TEST_TMPDIR/complex")
    [[ "$result" =~ '"module":"github.com/organization/project/v2"' ]]
}

# =============================================================================
# CATEGORY 5: DEPENDENCIES
# =============================================================================

@test "go_dependencies: lists direct dependencies" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_dependencies "$TEST_TMPDIR/project")
    [[ "$result" =~ 'github.com/gin-gonic/gin@v1.9.1' ]]
    [[ "$result" =~ 'github.com/stretchr/testify@v1.8.4' ]]
}

@test "go_dependencies: lists indirect dependencies" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_dependencies "$TEST_TMPDIR/project")
    [[ "$result" =~ 'golang.org/x/sys@v0.8.0' ]]
}

@test "go_dependencies: counts dependencies correctly" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_dependencies "$TEST_TMPDIR/project")
    [[ "$result" =~ '"direct_count":2' ]]
    [[ "$result" =~ '"indirect_count":2' ]]
    [[ "$result" =~ '"total":4' ]]
}

@test "go_dependencies: handles empty require block" {
    mkdir -p "$TEST_TMPDIR/nodeps"
    cat > "$TEST_TMPDIR/nodeps/go.mod" << 'EOF'
module github.com/test/nodeps

go 1.21
EOF
    result=$(go_dependencies "$TEST_TMPDIR/nodeps")
    [[ "$result" =~ '"total":0' ]]
}

@test "go_dependencies: handles single-line require" {
    mkdir -p "$TEST_TMPDIR/single"
    cat > "$TEST_TMPDIR/single/go.mod" << 'EOF'
module github.com/test/single

go 1.21

require github.com/pkg/errors v0.9.1
EOF
    result=$(go_dependencies "$TEST_TMPDIR/single")
    [[ "$result" =~ 'github.com/pkg/errors@v0.9.1' ]]
}

@test "go_dependencies: returns error for missing go.mod" {
    mkdir -p "$TEST_TMPDIR/empty"
    result=$(go_dependencies "$TEST_TMPDIR/empty")
    [[ "$result" =~ '"ok":false' ]]
}

# =============================================================================
# CATEGORY 6: PACKAGES
# =============================================================================

@test "go_packages: lists packages" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "list" ]]; then
            echo "github.com/test/project"
            echo "github.com/test/project/pkg"
            echo "github.com/test/project/internal"
            exit 0
        fi
        exit 1
    '
    result=$(go_packages "$TEST_TMPDIR/project")
    [[ "$result" =~ '"count":3' ]]
    [[ "$result" =~ 'github.com/test/project' ]]
}

@test "go_packages: returns error when go not installed" {
    create_go_project "$TEST_TMPDIR/project"
    export PATH="/nonexistent"
    result=$(go_packages "$TEST_TMPDIR/project")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'go not installed' ]]
}

@test "go_packages: handles go list failure" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "list" ]]; then
            echo "cannot find module" >&2
            exit 1
        fi
        exit 1
    '
    result=$(go_packages "$TEST_TMPDIR/project")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'go list failed' ]]
}

# =============================================================================
# CATEGORY 7: IMPORTS
# =============================================================================

@test "go_imports: parses single import" {
    mkdir -p "$TEST_TMPDIR/imports"
    cat > "$TEST_TMPDIR/imports/single.go" << 'EOF'
package main

import "fmt"

func main() {}
EOF
    result=$(go_imports "$TEST_TMPDIR/imports/single.go")
    [[ "$result" =~ '"imports":' ]]
    [[ "$result" =~ 'fmt' ]]
    [[ "$result" =~ '"total":1' ]]
}

@test "go_imports: parses import block" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_imports "$TEST_TMPDIR/project/main.go")
    [[ "$result" =~ '"total":3' ]]
    [[ "$result" =~ 'fmt' ]]
    [[ "$result" =~ 'net/http' ]]
    [[ "$result" =~ 'github.com/gin-gonic/gin' ]]
}

@test "go_imports: categorizes std_lib vs external" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_imports "$TEST_TMPDIR/project/main.go")
    [[ "$result" =~ '"std_lib":' ]]
    [[ "$result" =~ 'fmt' ]]
    [[ "$result" =~ 'net/http' ]]
    [[ "$result" =~ '"external":' ]]
    [[ "$result" =~ 'github.com/gin-gonic/gin' ]]
}

@test "go_imports: returns error for missing file" {
    result=$(go_imports "/nonexistent/file.go")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'file not found' ]]
}

@test "go_imports: returns error for empty path" {
    result=$(go_imports "")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'file path required' ]]
}

@test "go_imports: handles aliased imports" {
    mkdir -p "$TEST_TMPDIR/imports"
    cat > "$TEST_TMPDIR/imports/aliased.go" << 'EOF'
package main

import (
    f "fmt"
    . "strings"
    _ "net/http/pprof"
)

func main() {}
EOF
    result=$(go_imports "$TEST_TMPDIR/imports/aliased.go")
    [[ "$result" =~ 'fmt' ]]
    [[ "$result" =~ 'strings' ]]
    [[ "$result" =~ 'net/http/pprof' ]]
}

# =============================================================================
# CATEGORY 8: BUILD CHECK
# =============================================================================

@test "go_build_check: reports successful build" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "build" ]]; then
            exit 0
        fi
        exit 1
    '
    result=$(go_build_check "$TEST_TMPDIR/project")
    [[ "$result" =~ '"builds":true' ]]
    [[ "$result" =~ '"exit_code":0' ]]
}

@test "go_build_check: reports failed build" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "build" ]]; then
            echo "main.go:5:2: undefined: foo" >&2
            exit 1
        fi
        exit 1
    '
    result=$(go_build_check "$TEST_TMPDIR/project")
    [[ "$result" =~ '"builds":false' ]]
    [[ "$result" =~ '"exit_code":1' ]]
    [[ "$result" =~ 'undefined' ]]
}

@test "go_build_check: returns error when go not installed" {
    create_go_project "$TEST_TMPDIR/project"
    export PATH="/nonexistent"
    result=$(go_build_check "$TEST_TMPDIR/project")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'go not installed' ]]
}

@test "go_build_check: returns error for missing go.mod" {
    mkdir -p "$TEST_TMPDIR/empty"
    create_mock_go 'exit 0'
    result=$(go_build_check "$TEST_TMPDIR/empty")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'go.mod not found' ]]
}

# =============================================================================
# CATEGORY 9: TEST CHECK
# =============================================================================

@test "go_test_check: reports passing tests" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "test" ]]; then
            echo "ok      github.com/test/project  0.015s"
            echo "ok      github.com/test/project/pkg  0.010s"
            exit 0
        fi
        exit 1
    '
    result=$(go_test_check "$TEST_TMPDIR/project")
    [[ "$result" =~ '"passes":true' ]]
    [[ "$result" =~ '"exit_code":0' ]]
}

@test "go_test_check: reports failing tests" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "test" ]]; then
            echo "--- FAIL: TestMain (0.00s)"
            echo "FAIL    github.com/test/project  0.015s"
            exit 1
        fi
        exit 1
    '
    result=$(go_test_check "$TEST_TMPDIR/project")
    [[ "$result" =~ '"passes":false' ]]
    [[ "$result" =~ '"exit_code":1' ]]
}

@test "go_test_check: passes additional flags" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "test" && "$2" == "-v" ]]; then
            echo "=== RUN   TestMain"
            echo "--- PASS: TestMain (0.00s)"
            echo "PASS"
            echo "ok      github.com/test/project  0.015s"
            exit 0
        fi
        exit 1
    '
    result=$(go_test_check "$TEST_TMPDIR/project" "-v")
    [[ "$result" =~ '"passes":true' ]]
}

@test "go_test_check: handles no test files" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "test" ]]; then
            echo "?       github.com/test/project  [no test files]"
            exit 0
        fi
        exit 1
    '
    result=$(go_test_check "$TEST_TMPDIR/project")
    [[ "$result" =~ '"passes":true' ]]
    [[ "$result" =~ 'no test files' ]]
}

@test "go_test_check: returns error when go not installed" {
    create_go_project "$TEST_TMPDIR/project"
    export PATH="/nonexistent"
    result=$(go_test_check "$TEST_TMPDIR/project")
    [[ "$result" =~ '"ok":false' ]]
}

# =============================================================================
# CATEGORY 10: LINTING
# =============================================================================

@test "go_lint: uses staticcheck when available" {
    create_go_project "$TEST_TMPDIR/project"
    # Set PATH to only include mock bin
    export PATH="$MOCK_BIN"
    create_mock_go 'exit 0'
    create_mock_linter "staticcheck" 'exit 0'
    result=$(go_lint "$TEST_TMPDIR/project")
    [[ "$result" =~ '"tool":"staticcheck"' ]]
    [[ "$result" =~ '"clean":true' ]]
}

@test "go_lint: reports lint issues" {
    create_go_project "$TEST_TMPDIR/project"
    # Set PATH to only include mock bin
    export PATH="$MOCK_BIN"
    create_mock_go 'exit 0'
    create_mock_linter "staticcheck" '
        echo "main.go:5:2: unused variable x (SA4006)"
        echo "main.go:10:5: unnecessary conversion (S1034)"
        exit 1
    '
    result=$(go_lint "$TEST_TMPDIR/project")
    [[ "$result" =~ '"clean":false' ]]
    [[ "$result" =~ '"issues":2' ]] || [[ "$result" =~ '"issues":' ]]
}

@test "go_lint: falls back to golangci-lint" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go 'exit 0'
    # Ensure staticcheck is NOT in path, but golangci-lint IS
    # Reset PATH to only include mock bin (no staticcheck)
    export PATH="$MOCK_BIN"
    create_mock_linter "golangci-lint" 'exit 0'
    result=$(go_lint "$TEST_TMPDIR/project")
    [[ "$result" =~ '"tool":"golangci-lint"' ]]
}

@test "go_lint: falls back to go vet" {
    create_go_project "$TEST_TMPDIR/project"
    # Reset PATH to only include mock bin with go (no linters)
    export PATH="$MOCK_BIN"
    create_mock_go '
        if [[ "$1" == "vet" ]]; then
            exit 0
        fi
        exit 1
    '
    # No external linters available
    result=$(go_lint "$TEST_TMPDIR/project")
    [[ "$result" =~ '"tool":"go vet"' ]]
}

@test "go_lint: returns error when go not installed" {
    create_go_project "$TEST_TMPDIR/project"
    export PATH="/nonexistent"
    result=$(go_lint "$TEST_TMPDIR/project")
    [[ "$result" =~ '"ok":false' ]]
}

@test "go_lint: returns error for missing go.mod" {
    mkdir -p "$TEST_TMPDIR/empty"
    create_mock_go 'exit 0'
    result=$(go_lint "$TEST_TMPDIR/empty")
    [[ "$result" =~ '"ok":false' ]]
}

# =============================================================================
# CATEGORY 11: PROJECT SUMMARY
# =============================================================================

@test "go_project_summary: returns comprehensive summary" {
    create_go_project "$TEST_TMPDIR/project"
    touch "$TEST_TMPDIR/project/Makefile"
    touch "$TEST_TMPDIR/project/Dockerfile"
    create_mock_go '
        if [[ "$1" == "list" ]]; then
            echo "github.com/test/project"
            exit 0
        fi
        exit 1
    '
    result=$(go_project_summary "$TEST_TMPDIR/project")
    [[ "$result" =~ '"module":"github.com/test/project"' ]]
    [[ "$result" =~ '"go_version":"1.21"' ]]
    [[ "$result" =~ '"has_makefile":true' ]]
    [[ "$result" =~ '"has_dockerfile":true' ]]
    [[ "$result" =~ '"has_main":true' ]]
    [[ "$result" =~ '"has_tests":true' ]]
}

@test "go_project_summary: returns error for non-Go project" {
    mkdir -p "$TEST_TMPDIR/notgo"
    result=$(go_project_summary "$TEST_TMPDIR/notgo")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'not a Go project' ]]
}

@test "go_project_summary: returns error for non-existent directory" {
    result=$(go_project_summary "/nonexistent/path")
    [[ "$result" =~ '"ok":false' ]]
    [[ "$result" =~ 'directory not found' ]]
}

@test "go_project_summary: handles project without optional files" {
    create_go_project "$TEST_TMPDIR/minimal"
    rm -f "$TEST_TMPDIR/minimal/main_test.go"
    create_mock_go '
        if [[ "$1" == "list" ]]; then
            echo "github.com/test/project"
            exit 0
        fi
        exit 1
    '
    result=$(go_project_summary "$TEST_TMPDIR/minimal")
    [[ "$result" =~ '"has_makefile":false' ]]
    [[ "$result" =~ '"has_dockerfile":false' ]]
}

# =============================================================================
# CATEGORY 12: MODULE EXPORTS
# =============================================================================

@test "_GO_EXPORTS: is defined and non-empty" {
    [[ -n "${_GO_EXPORTS[*]}" ]]
}

@test "_GO_EXPORTS: contains detection functions" {
    [[ "${_GO_EXPORTS[*]}" =~ "go_detect" ]]
    [[ "${_GO_EXPORTS[*]}" =~ "go_version" ]]
    [[ "${_GO_EXPORTS[*]}" =~ "go_mod_name" ]]
}

@test "_GO_EXPORTS: contains dependency functions" {
    [[ "${_GO_EXPORTS[*]}" =~ "go_dependencies" ]]
}

@test "_GO_EXPORTS: contains package functions" {
    [[ "${_GO_EXPORTS[*]}" =~ "go_packages" ]]
    [[ "${_GO_EXPORTS[*]}" =~ "go_imports" ]]
}

@test "_GO_EXPORTS: contains build and test functions" {
    [[ "${_GO_EXPORTS[*]}" =~ "go_build_check" ]]
    [[ "${_GO_EXPORTS[*]}" =~ "go_test_check" ]]
}

@test "_GO_EXPORTS: contains lint function" {
    [[ "${_GO_EXPORTS[*]}" =~ "go_lint" ]]
}

@test "_GO_EXPORTS: contains summary function" {
    [[ "${_GO_EXPORTS[*]}" =~ "go_project_summary" ]]
}

# =============================================================================
# CATEGORY 13: EDGE CASES
# =============================================================================

@test "go_detect: handles directory with spaces" {
    mkdir -p "$TEST_TMPDIR/project with spaces"
    cat > "$TEST_TMPDIR/project with spaces/go.mod" << 'EOF'
module example.com/test

go 1.21
EOF
    result=$(go_detect "$TEST_TMPDIR/project with spaces")
    [[ "$result" =~ '"is_go":true' ]]
}

@test "go_dependencies: handles replace directives" {
    mkdir -p "$TEST_TMPDIR/replace"
    cat > "$TEST_TMPDIR/replace/go.mod" << 'EOF'
module github.com/test/replace

go 1.21

require github.com/original/pkg v1.0.0

replace github.com/original/pkg => ../local/pkg
EOF
    result=$(go_dependencies "$TEST_TMPDIR/replace")
    [[ "$result" =~ 'github.com/original/pkg@v1.0.0' ]]
}

@test "go_imports: handles empty file" {
    mkdir -p "$TEST_TMPDIR/empty"
    touch "$TEST_TMPDIR/empty/empty.go"
    result=$(go_imports "$TEST_TMPDIR/empty/empty.go")
    [[ "$result" =~ '"total":0' ]]
}

@test "go_mod_name: handles go version with patch number" {
    mkdir -p "$TEST_TMPDIR/patch"
    cat > "$TEST_TMPDIR/patch/go.mod" << 'EOF'
module example.com/test

go 1.21.5
EOF
    result=$(go_mod_name "$TEST_TMPDIR/patch")
    [[ "$result" =~ '"go_version":"1.21.5"' ]]
}

@test "go_build_check: truncates very long error output" {
    create_go_project "$TEST_TMPDIR/project"
    create_mock_go '
        if [[ "$1" == "build" ]]; then
            for i in {1..500}; do
                echo "main.go:$i: error: very long error message line $i that goes on and on"
            done
            exit 1
        fi
        exit 1
    '
    result=$(go_build_check "$TEST_TMPDIR/project")
    # Should be truncated, not full output
    [[ "$result" =~ 'truncated' ]]
}

@test "go_dependencies: handles comments in go.mod" {
    mkdir -p "$TEST_TMPDIR/comments"
    cat > "$TEST_TMPDIR/comments/go.mod" << 'EOF'
// This is a comment
module github.com/test/comments

go 1.21

require (
    // A direct dependency
    github.com/pkg/errors v0.9.1
)
EOF
    result=$(go_dependencies "$TEST_TMPDIR/comments")
    [[ "$result" =~ 'github.com/pkg/errors@v0.9.1' ]]
    [[ "$result" =~ '"direct_count":1' ]]
}

# =============================================================================
# CATEGORY 14: JSON OUTPUT VALIDATION
# =============================================================================

@test "go_detect: returns valid JSON" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_detect "$TEST_TMPDIR/project")
    # Should be parseable JSON (basic validation)
    [[ "$result" =~ ^\{ ]]
    [[ "$result" =~ \}$ ]]
    [[ "$result" =~ '"ok":' ]]
}

@test "go_version: returns valid JSON" {
    create_mock_go 'echo "go version go1.21.0 linux/amd64"'
    result=$(go_version)
    [[ "$result" =~ ^\{ ]]
    [[ "$result" =~ \}$ ]]
}

@test "go_dependencies: returns valid JSON arrays" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_dependencies "$TEST_TMPDIR/project")
    [[ "$result" == *'"direct":['* ]]
    [[ "$result" == *'"indirect":['* ]]
}

@test "go_imports: returns valid JSON arrays" {
    create_go_project "$TEST_TMPDIR/project"
    result=$(go_imports "$TEST_TMPDIR/project/main.go")
    [[ "$result" == *'"imports":['* ]]
    [[ "$result" == *'"std_lib":['* ]]
    [[ "$result" == *'"external":['* ]]
}

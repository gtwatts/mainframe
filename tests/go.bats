#!/usr/bin/env bats

# =============================================================================
# Tests for MAINFRAME/lib/go.sh
# =============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/go.sh"
    FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures/go_project"
}

# =============================================================================
# go_is_project
# =============================================================================

@test "go_is_project returns 0 for Go project" {
    go_is_project "$FIXTURE_DIR"
}

@test "go_is_project returns 1 for non-Go dir" {
    run go_is_project "/tmp"
    [[ $status -ne 0 ]]
}

@test "go_is_project handles missing directory" {
    run go_is_project "/nonexistent"
    [[ $status -ne 0 ]]
}

# =============================================================================
# go_source_dir
# =============================================================================

@test "go_source_dir returns project root when no cmd/" {
    local result
    result=$(go_source_dir "$FIXTURE_DIR")
    [[ "$result" == "$FIXTURE_DIR" ]]
}

# =============================================================================
# go_file_imports
# =============================================================================

@test "go_file_imports extracts grouped imports" {
    local result
    result=$(go_file_imports "$FIXTURE_DIR/main.go")
    echo "$result" | grep -q "fmt"
    echo "$result" | grep -q "net/http"
}

@test "go_file_imports extracts third-party imports" {
    local result
    result=$(go_file_imports "$FIXTURE_DIR/main.go")
    echo "$result" | grep -q "github.com/gin-gonic/gin"
    echo "$result" | grep -q "github.com/lib/pq"
}

@test "go_file_imports extracts single-line imports" {
    local result
    result=$(go_file_imports "$FIXTURE_DIR/main.go")
    echo "$result" | grep -q "os"
}

@test "go_file_imports handles missing file" {
    run go_file_imports "/nonexistent/file.go"
    [[ $status -ne 0 ]]
}

@test "go_file_imports returns correct count" {
    local count
    count=$(go_file_imports "$FIXTURE_DIR/main.go" | wc -l)
    [[ $count -eq 5 ]]
}

# =============================================================================
# go_import_frequency
# =============================================================================

@test "go_import_frequency lists packages by count" {
    local result
    result=$(go_import_frequency "$FIXTURE_DIR")
    [[ -n "$result" ]]
}

# =============================================================================
# go_import_graph
# =============================================================================

@test "go_import_graph produces file:imports format" {
    local result
    result=$(go_import_graph "$FIXTURE_DIR")
    echo "$result" | grep -q "main.go:"
}

# =============================================================================
# go_module_info
# =============================================================================

@test "go_module_info extracts module name" {
    local result
    result=$(go_module_info "$FIXTURE_DIR")
    [[ "$result" == *"module=github.com/example/myapp"* ]]
}

@test "go_module_info extracts go version" {
    local result
    result=$(go_module_info "$FIXTURE_DIR")
    [[ "$result" == *"go_version=1.21"* ]]
}

@test "go_module_info counts requirements" {
    local result
    result=$(go_module_info "$FIXTURE_DIR")
    [[ "$result" == *"require_count=5"* ]]
}

@test "go_module_info fails for non-go dir" {
    run go_module_info "/tmp"
    [[ $status -ne 0 ]]
}

# =============================================================================
# go_dep_count
# =============================================================================

@test "go_dep_count separates direct and indirect" {
    local result
    result=$(go_dep_count "$FIXTURE_DIR")
    [[ "$result" == *"direct="* ]]
    [[ "$result" == *"indirect="* ]]
}

@test "go_dep_count counts direct deps correctly" {
    local result direct
    result=$(go_dep_count "$FIXTURE_DIR")
    direct=$(echo "$result" | grep -oP '^direct=\K[0-9]+|(?<=,)direct=\K[0-9]+' | head -1)
    [[ -z "$direct" ]] && direct=$(echo "$result" | sed 's/,.*//' | sed 's/direct=//')
    [[ $direct -eq 3 ]]
}

@test "go_dep_count counts indirect deps correctly" {
    local result indirect
    result=$(go_dep_count "$FIXTURE_DIR")
    indirect=$(echo "$result" | sed 's/.*indirect=//')
    [[ $indirect -eq 2 ]]
}

# =============================================================================
# go_function_count
# =============================================================================

@test "go_function_count counts functions" {
    local count
    count=$(go_function_count "$FIXTURE_DIR")
    [[ $count -ge 4 ]]
}

# =============================================================================
# go_interface_count
# =============================================================================

@test "go_interface_count counts interfaces" {
    local count
    count=$(go_interface_count "$FIXTURE_DIR")
    [[ $count -eq 2 ]]
}

# =============================================================================
# go_struct_count
# =============================================================================

@test "go_struct_count counts structs" {
    local count
    count=$(go_struct_count "$FIXTURE_DIR")
    [[ $count -eq 1 ]]
}

# =============================================================================
# go_loc
# =============================================================================

@test "go_loc counts non-blank non-comment lines" {
    local count
    count=$(go_loc "$FIXTURE_DIR")
    [[ $count -gt 20 ]]
}

# =============================================================================
# go_test_coverage
# =============================================================================

@test "go_test_coverage finds test files" {
    local result
    result=$(go_test_coverage "$FIXTURE_DIR")
    [[ "$result" == *"test_files=1"* ]]
}

@test "go_test_coverage counts test functions" {
    local result funcs
    result=$(go_test_coverage "$FIXTURE_DIR")
    funcs=$(echo "$result" | grep -oP 'test_functions=\K[0-9]+')
    [[ $funcs -eq 2 ]]
}

# =============================================================================
# go_summary
# =============================================================================

@test "go_summary produces valid JSON" {
    local result
    result=$(go_summary "$FIXTURE_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *'"module":'* ]]
    [[ "$result" == *'"functions":'* ]]
}

@test "go_summary includes all metrics" {
    local result
    result=$(go_summary "$FIXTURE_DIR")
    [[ "$result" == *'"go_version":'* ]]
    [[ "$result" == *'"interfaces":'* ]]
    [[ "$result" == *'"structs":'* ]]
    [[ "$result" == *'"loc":'* ]]
    [[ "$result" == *'"dependencies":'* ]]
    [[ "$result" == *'"tests":'* ]]
}

@test "go_summary fails for non-Go project" {
    local result
    result=$(go_summary "/tmp")
    [[ "$result" == *'"error"'* ]]
}

# =============================================================================
# go_circular_deps
# =============================================================================

@test "go_circular_deps detects A<->B cycle" {
    local circular_dir="${BATS_TEST_DIRNAME}/fixtures/go_project_circular"
    local result
    result=$(go_circular_deps "$circular_dir")
    [[ "$result" == *"pkg_a"* ]]
    [[ "$result" == *"pkg_b"* ]]
    [[ "$result" == *"<->"* ]]
}

@test "go_circular_deps returns empty for non-circular project" {
    local result
    result=$(go_circular_deps "$FIXTURE_DIR" 2>/dev/null || true)
    [[ -z "$result" ]]
}

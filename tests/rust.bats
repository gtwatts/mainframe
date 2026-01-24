#!/usr/bin/env bats

# =============================================================================
# Tests for MAINFRAME/lib/rust.sh
# =============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/rust.sh"
    FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures/rust_project"
}

# =============================================================================
# rust_is_project
# =============================================================================

@test "rust_is_project returns 0 for Rust project" {
    rust_is_project "$FIXTURE_DIR"
}

@test "rust_is_project returns 1 for non-Rust dir" {
    run rust_is_project "/tmp"
    [[ $status -ne 0 ]]
}

# =============================================================================
# rust_source_dir
# =============================================================================

@test "rust_source_dir finds src/ directory" {
    local result
    result=$(rust_source_dir "$FIXTURE_DIR")
    [[ "$result" == *"/src" ]]
}

# =============================================================================
# rust_parse_cargo
# =============================================================================

@test "rust_parse_cargo extracts package name" {
    local result
    result=$(rust_parse_cargo "$FIXTURE_DIR")
    [[ "$result" == *"name=myapp"* ]]
}

@test "rust_parse_cargo extracts version" {
    local result
    result=$(rust_parse_cargo "$FIXTURE_DIR")
    [[ "$result" == *"version=0.1.0"* ]]
}

@test "rust_parse_cargo extracts edition" {
    local result
    result=$(rust_parse_cargo "$FIXTURE_DIR")
    [[ "$result" == *"edition=2021"* ]]
}

@test "rust_parse_cargo fails for non-Rust dir" {
    run rust_parse_cargo "/tmp"
    [[ $status -ne 0 ]]
}

# =============================================================================
# rust_dep_count
# =============================================================================

@test "rust_dep_count counts regular dependencies" {
    local result regular
    result=$(rust_dep_count "$FIXTURE_DIR")
    regular=$(echo "$result" | grep -oP 'regular=\K[0-9]+')
    [[ $regular -eq 4 ]]
}

@test "rust_dep_count counts dev dependencies" {
    local result dev
    result=$(rust_dep_count "$FIXTURE_DIR")
    dev=$(echo "$result" | grep -oP 'dev=\K[0-9]+')
    [[ $dev -eq 2 ]]
}

@test "rust_dep_count counts build dependencies" {
    local result build
    result=$(rust_dep_count "$FIXTURE_DIR")
    build=$(echo "$result" | grep -oP 'build=\K[0-9]+')
    [[ $build -eq 1 ]]
}

# =============================================================================
# rust_file_imports
# =============================================================================

@test "rust_file_imports extracts simple use statements" {
    local result
    result=$(rust_file_imports "$FIXTURE_DIR/src/main.rs")
    echo "$result" | grep -q "std::io"
    echo "$result" | grep -q "std::collections::HashMap"
}

@test "rust_file_imports extracts crate imports" {
    local result
    result=$(rust_file_imports "$FIXTURE_DIR/src/main.rs")
    echo "$result" | grep -q "tokio::runtime::Runtime"
}

@test "rust_file_imports handles nested braces" {
    local result
    result=$(rust_file_imports "$FIXTURE_DIR/src/main.rs")
    echo "$result" | grep -q "serde::Serialize"
    echo "$result" | grep -q "serde::Deserialize"
}

@test "rust_file_imports extracts nested path imports" {
    local result
    result=$(rust_file_imports "$FIXTURE_DIR/src/main.rs")
    echo "$result" | grep -q "axum"
}

@test "rust_file_imports handles missing file" {
    run rust_file_imports "/nonexistent/file.rs"
    [[ $status -ne 0 ]]
}

@test "rust_file_imports returns correct count" {
    local count
    count=$(rust_file_imports "$FIXTURE_DIR/src/main.rs" | wc -l)
    [[ $count -ge 6 ]]
}

# =============================================================================
# rust_import_frequency
# =============================================================================

@test "rust_import_frequency lists modules by count" {
    local result
    result=$(rust_import_frequency "$FIXTURE_DIR")
    [[ -n "$result" ]]
}

# =============================================================================
# rust_unsafe_count
# =============================================================================

@test "rust_unsafe_count finds unsafe blocks" {
    local result blocks
    result=$(rust_unsafe_count "$FIXTURE_DIR")
    # We have unsafe fn and unsafe impl in main.rs
    [[ "$result" == *"functions="* ]]
}

@test "rust_unsafe_count finds unsafe functions" {
    local result funcs
    result=$(rust_unsafe_count "$FIXTURE_DIR")
    funcs=$(echo "$result" | grep -oP 'functions=\K[0-9]+')
    [[ $funcs -ge 1 ]]
}

@test "rust_unsafe_count finds unsafe impls" {
    local result impls
    result=$(rust_unsafe_count "$FIXTURE_DIR")
    impls=$(echo "$result" | grep -oP 'impls=\K[0-9]+')
    [[ $impls -ge 1 ]]
}

# =============================================================================
# rust_function_count
# =============================================================================

@test "rust_function_count counts functions" {
    local count
    count=$(rust_function_count "$FIXTURE_DIR")
    [[ $count -ge 5 ]]
}

# =============================================================================
# rust_trait_count
# =============================================================================

@test "rust_trait_count counts traits" {
    local count
    count=$(rust_trait_count "$FIXTURE_DIR")
    [[ $count -ge 1 ]]
}

# =============================================================================
# rust_struct_count
# =============================================================================

@test "rust_struct_count counts structs" {
    local count
    count=$(rust_struct_count "$FIXTURE_DIR")
    [[ $count -ge 2 ]]
}

# =============================================================================
# rust_impl_count
# =============================================================================

@test "rust_impl_count counts impl blocks" {
    local count
    count=$(rust_impl_count "$FIXTURE_DIR")
    [[ $count -ge 2 ]]
}

# =============================================================================
# rust_enum_count
# =============================================================================

@test "rust_enum_count counts enums" {
    local count
    count=$(rust_enum_count "$FIXTURE_DIR")
    [[ $count -eq 0 ]]
}

# =============================================================================
# rust_loc
# =============================================================================

@test "rust_loc counts non-blank lines" {
    local count
    count=$(rust_loc "$FIXTURE_DIR")
    [[ $count -gt 30 ]]
}

# =============================================================================
# rust_test_coverage
# =============================================================================

@test "rust_test_coverage finds test functions" {
    local result funcs
    result=$(rust_test_coverage "$FIXTURE_DIR")
    funcs=$(echo "$result" | grep -oP 'test_functions=\K[0-9]+')
    [[ $funcs -eq 3 ]]
}

@test "rust_test_coverage finds test modules" {
    local result mods
    result=$(rust_test_coverage "$FIXTURE_DIR")
    mods=$(echo "$result" | grep -oP 'test_modules=\K[0-9]+')
    [[ $mods -eq 1 ]]
}

# =============================================================================
# rust_summary
# =============================================================================

@test "rust_summary produces valid JSON" {
    local result
    result=$(rust_summary "$FIXTURE_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *'"name":'* ]]
}

@test "rust_summary includes all metrics" {
    local result
    result=$(rust_summary "$FIXTURE_DIR")
    [[ "$result" == *'"version":'* ]]
    [[ "$result" == *'"edition":'* ]]
    [[ "$result" == *'"functions":'* ]]
    [[ "$result" == *'"traits":'* ]]
    [[ "$result" == *'"structs":'* ]]
    [[ "$result" == *'"unsafe":'* ]]
    [[ "$result" == *'"dependencies":'* ]]
    [[ "$result" == *'"tests":'* ]]
}

@test "rust_summary fails for non-Rust project" {
    local result
    result=$(rust_summary "/tmp")
    [[ "$result" == *'"error"'* ]]
}

@test "rust_summary shows correct package name" {
    local result
    result=$(rust_summary "$FIXTURE_DIR")
    [[ "$result" == *'"name":"myapp"'* ]]
}

# =============================================================================
# rust_import_graph
# =============================================================================

@test "rust_import_graph produces file:imports output" {
    local result
    result=$(rust_import_graph "$FIXTURE_DIR")
    echo "$result" | grep -q "src/main.rs:"
}

@test "rust_import_graph lists all files with imports" {
    local count
    count=$(rust_import_graph "$FIXTURE_DIR" | wc -l)
    [[ $count -ge 1 ]]
}

@test "rust_import_graph handles empty project" {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "${tmpdir}/src"
    touch "${tmpdir}/src/lib.rs"
    touch "${tmpdir}/Cargo.toml"
    run rust_import_graph "$tmpdir"
    [[ -z "$output" ]]
    rm -rf "$tmpdir"
}

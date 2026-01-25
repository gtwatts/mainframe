#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: TOML Parser Library Tests
# =============================================================================
# Tests for lib/toml.sh - TOML parsing, key access, sections, JSON conversion
# =============================================================================

load 'test_helper'

setup() {
    source_lib "toml"
    FIXTURES="${BATS_TEST_DIRNAME}/fixtures/toml"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "toml_parse: returns error for missing file" {
    run toml_parse "/nonexistent/file.toml"
    [[ $status -eq 1 ]]
    [[ "$output" == *"file not found"* ]]
}

@test "toml_parse: returns error for empty path" {
    run toml_parse ""
    [[ $status -eq 1 ]]
    [[ "$output" == *"no file specified"* ]]
}

@test "toml_get: returns 1 for missing key" {
    run toml_get "$FIXTURES/simple.toml" "nonexistent"
    [[ $status -eq 1 ]]
}

@test "toml_has: returns 1 for missing key" {
    run toml_has "$FIXTURES/simple.toml" "nonexistent"
    [[ $status -eq 1 ]]
}

# =============================================================================
# SIMPLE KEY-VALUE TESTS
# =============================================================================

@test "toml_parse: parses simple string value" {
    local result
    result=$(toml_parse "$FIXTURES/simple.toml")
    assert_contains "$result" "title=My Application"
}

@test "toml_parse: parses boolean value" {
    local result
    result=$(toml_parse "$FIXTURES/simple.toml")
    assert_contains "$result" "debug=true"
}

@test "toml_parse: parses integer value" {
    local result
    result=$(toml_parse "$FIXTURES/simple.toml")
    assert_contains "$result" "port=8080"
}

@test "toml_parse: parses float value" {
    local result
    result=$(toml_parse "$FIXTURES/simple.toml")
    assert_contains "$result" "rate=3.14"
}

@test "toml_get: retrieves simple string value" {
    local result
    result=$(toml_get "$FIXTURES/simple.toml" "title")
    assert_equal "My Application" "$result"
}

@test "toml_get: retrieves integer value" {
    local result
    result=$(toml_get "$FIXTURES/simple.toml" "port")
    assert_equal "8080" "$result"
}

@test "toml_has: returns 0 for existing key" {
    toml_has "$FIXTURES/simple.toml" "title"
}

@test "toml_has: returns 0 for nested key" {
    toml_has "$FIXTURES/cargo.toml" "package.name"
}

# =============================================================================
# SECTION/TABLE TESTS
# =============================================================================

@test "toml_parse: parses sections with dot notation" {
    local result
    result=$(toml_parse "$FIXTURES/cargo.toml")
    assert_contains "$result" "package.name=my-rust-app"
    assert_contains "$result" "package.version=0.1.0"
    assert_contains "$result" "package.edition=2021"
}

@test "toml_sections: lists all sections" {
    local result
    result=$(toml_sections "$FIXTURES/cargo.toml")
    assert_contains "$result" "package"
    assert_contains "$result" "dependencies"
    assert_contains "$result" "dev-dependencies"
    assert_contains "$result" "profile.release"
}

@test "toml_sections: lists array table sections" {
    local result
    result=$(toml_sections "$FIXTURES/cargo.toml")
    assert_contains "$result" "bin"
}

@test "toml_get_section: returns section key-value pairs" {
    local result
    result=$(toml_get_section "$FIXTURES/cargo.toml" "package")
    assert_contains "$result" "name=my-rust-app"
    assert_contains "$result" "version=0.1.0"
    assert_contains "$result" "edition=2021"
}

@test "toml_get_section: returns nested section" {
    local result
    result=$(toml_get_section "$FIXTURES/cargo.toml" "profile.release")
    assert_contains "$result" "opt-level=3"
    assert_contains "$result" "lto=true"
}

# =============================================================================
# INLINE TABLE TESTS
# =============================================================================

@test "toml_parse: parses inline tables" {
    local result
    result=$(toml_parse "$FIXTURES/cargo.toml")
    assert_contains "$result" "dependencies.serde.version=1.0"
}

@test "toml_parse: parses inline table with features array" {
    local result
    result=$(toml_parse "$FIXTURES/cargo.toml")
    assert_contains "$result" "dependencies.serde.features="
}

@test "toml_parse: parses simple dependency value" {
    local result
    result=$(toml_parse "$FIXTURES/cargo.toml")
    assert_contains "$result" "dependencies.reqwest=0.11"
}

# =============================================================================
# ARRAY TESTS
# =============================================================================

@test "toml_parse: parses inline arrays" {
    local result
    result=$(toml_parse "$FIXTURES/simple.toml")
    # simple.toml doesn't have arrays, check cargo.toml
    result=$(toml_parse "$FIXTURES/cargo.toml")
    assert_contains "$result" "package.keywords="
}

@test "toml_get_array: returns array elements" {
    local result
    result=$(toml_get_array "$FIXTURES/cargo.toml" "package.keywords")
    assert_contains "$result" "cli"
    assert_contains "$result" "async"
    assert_contains "$result" "web"
}

@test "toml_get_array: returns multiline array elements" {
    local result
    result=$(toml_get_array "$FIXTURES/multiline.toml" "items")
    assert_contains "$result" "first"
    assert_contains "$result" "second"
    assert_contains "$result" "third"
}

@test "toml_get_array: returns numeric array elements" {
    local result
    result=$(toml_get_array "$FIXTURES/multiline.toml" "numbers")
    assert_contains "$result" "1"
    assert_contains "$result" "5"
}

@test "toml_get_array: returns 1 for non-existent key" {
    run toml_get_array "$FIXTURES/simple.toml" "nonexistent"
    [[ $status -eq 1 ]]
}

# =============================================================================
# ARRAY OF TABLES TESTS
# =============================================================================

@test "toml_parse: parses array of tables with indices" {
    local result
    result=$(toml_parse "$FIXTURES/cargo.toml")
    assert_contains "$result" "bin[0].name=myapp"
    assert_contains "$result" "bin[1].name=myutil"
}

@test "toml_parse: parses array of tables paths" {
    local result
    result=$(toml_parse "$FIXTURES/cargo.toml")
    assert_contains "$result" "bin[0].path=src/main.rs"
    assert_contains "$result" "bin[1].path=src/util.rs"
}

# =============================================================================
# MULTILINE STRING TESTS
# =============================================================================

@test "toml_parse: parses multiline basic strings" {
    local result
    result=$(toml_parse "$FIXTURES/multiline.toml")
    # The multiline string should be captured
    assert_contains "$result" "description="
}

@test "toml_get: retrieves value from section after multiline" {
    local result
    result=$(toml_get "$FIXTURES/multiline.toml" "server.host")
    assert_equal "localhost" "$result"
}

# =============================================================================
# DOTTED KEYS TESTS
# =============================================================================

@test "toml_parse: parses dotted keys" {
    local result
    result=$(toml_parse "$FIXTURES/dotted_keys.toml")
    assert_contains "$result" "fruit.apple.color=red"
    assert_contains "$result" "fruit.apple.taste=sweet"
    assert_contains "$result" "fruit.orange.color=orange"
}

@test "toml_parse: parses quoted keys" {
    local result
    result=$(toml_parse "$FIXTURES/dotted_keys.toml")
    assert_contains "$result" "quoted key=special value"
}

@test "toml_parse: parses nested section with dots" {
    local result
    result=$(toml_parse "$FIXTURES/dotted_keys.toml")
    assert_contains "$result" "server.tls.enabled=true"
    assert_contains "$result" "server.tls.cert=/path/to/cert.pem"
}

# =============================================================================
# KEYS FUNCTION TESTS
# =============================================================================

@test "toml_keys: lists all keys" {
    local result
    result=$(toml_keys "$FIXTURES/simple.toml")
    assert_contains "$result" "title"
    assert_contains "$result" "version"
    assert_contains "$result" "debug"
    assert_contains "$result" "port"
}

@test "toml_keys: lists nested keys" {
    local result
    result=$(toml_keys "$FIXTURES/cargo.toml")
    assert_contains "$result" "package.name"
    assert_contains "$result" "package.version"
}

# =============================================================================
# JSON CONVERSION TESTS
# =============================================================================

@test "toml_to_json: converts simple values" {
    local result
    result=$(toml_to_json "$FIXTURES/simple.toml")
    assert_contains "$result" '"title":"My Application"'
    assert_contains "$result" '"port":8080'
    assert_contains "$result" '"debug":true'
}

@test "toml_to_json: converts float values" {
    local result
    result=$(toml_to_json "$FIXTURES/simple.toml")
    assert_contains "$result" '"rate":3.14'
}

@test "toml_to_json: returns valid JSON structure" {
    local result
    result=$(toml_to_json "$FIXTURES/simple.toml")
    assert_starts_with "$result" "{"
    assert_ends_with "$result" "}"
}

@test "toml_to_json: returns empty object for empty input" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '' > "$tmpfile"
    local result
    result=$(toml_to_json "$tmpfile")
    assert_equal "{}" "$result"
    rm -f "$tmpfile"
}

# =============================================================================
# PYPROJECT.TOML TESTS (real-world)
# =============================================================================

@test "toml_get: reads pyproject project.name" {
    local result
    result=$(toml_get "$FIXTURES/pyproject.toml" "project.name")
    assert_equal "my-python-app" "$result"
}

@test "toml_get: reads pyproject project.version" {
    local result
    result=$(toml_get "$FIXTURES/pyproject.toml" "project.version")
    assert_equal "2.1.0" "$result"
}

@test "toml_get: reads pyproject requires-python" {
    local result
    result=$(toml_get "$FIXTURES/pyproject.toml" "project.requires-python")
    assert_equal ">=3.9" "$result"
}

@test "toml_get_section: reads pyproject tool.black section" {
    local result
    result=$(toml_get_section "$FIXTURES/pyproject.toml" "tool.black")
    assert_contains "$result" "line-length=88"
}

@test "toml_get_section: reads pyproject build-system" {
    local result
    result=$(toml_get_section "$FIXTURES/pyproject.toml" "build-system")
    assert_contains "$result" "build-backend=setuptools.build_meta"
}

@test "toml_get_array: reads pyproject dependencies" {
    local result
    result=$(toml_get_array "$FIXTURES/pyproject.toml" "project.dependencies")
    assert_contains "$result" "requests>=2.28"
    assert_contains "$result" "click>=8.0"
    assert_contains "$result" "pydantic>=2.0"
}

# =============================================================================
# CARGO.TOML TESTS (real-world)
# =============================================================================

@test "toml_get: reads cargo package description" {
    local result
    result=$(toml_get "$FIXTURES/cargo.toml" "package.description")
    assert_equal "A sample Rust application" "$result"
}

@test "toml_get_array: reads cargo workspace members" {
    local result
    result=$(toml_get_array "$FIXTURES/cargo.toml" "workspace.members")
    assert_contains "$result" "crates/core"
    assert_contains "$result" "crates/cli"
}

@test "toml_get: reads cargo profile release opt-level" {
    local result
    result=$(toml_get "$FIXTURES/cargo.toml" "profile.release.opt-level")
    assert_equal "3" "$result"
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "toml_parse: handles comments correctly" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '# Full line comment\nkey = "value" # inline comment\n' > "$tmpfile"
    local result
    result=$(toml_parse "$tmpfile")
    assert_contains "$result" "key=value"
    rm -f "$tmpfile"
}

@test "toml_parse: handles empty file" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '' > "$tmpfile"
    local result
    result=$(toml_parse "$tmpfile")
    [[ -z "$result" ]]
    rm -f "$tmpfile"
}

@test "toml_parse: skips blank lines" {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'a = 1\n\n\nb = 2\n' > "$tmpfile"
    local result
    result=$(toml_parse "$tmpfile")
    assert_contains "$result" "a=1"
    assert_contains "$result" "b=2"
    rm -f "$tmpfile"
}

@test "toml_parse: handles literal strings (single quotes)" {
    local tmpfile
    tmpfile=$(mktemp)
    # Literal strings don't process escapes, so single backslashes stay as-is
    printf "path = 'C:\\Users\\docs'\n" > "$tmpfile"
    local result
    result=$(toml_parse "$tmpfile")
    assert_contains "$result" 'path=C:\Users\docs'
    rm -f "$tmpfile"
}

@test "toml_sections: returns 1 for missing file" {
    run toml_sections "/nonexistent"
    [[ $status -eq 1 ]]
}

@test "toml_get_array: reads authors array" {
    local result
    result=$(toml_get_array "$FIXTURES/cargo.toml" "package.authors")
    assert_contains "$result" "Alice <alice@example.com>"
    assert_contains "$result" "Bob <bob@example.com>"
}

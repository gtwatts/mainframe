#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Rust/Cargo Project Analysis Library Tests
# =============================================================================
# Comprehensive tests for lib/ext/rust.sh (10 functions)
# Covers: detection, Cargo.toml parsing, build checks, clippy, fmt
# Tests use mocking to work without rustc/cargo installed
# =============================================================================

load '../../test_helper.bash'

setup() {
    # Source json.sh first (dependency)
    source_lib "json"
    # Source the rust library
    source "$MAINFRAME_ROOT/lib/ext/rust.sh"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "rust")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"

    # Restore mocked functions
    unset -f rustc 2>/dev/null || true
    unset -f cargo 2>/dev/null || true
    unset -f rustfmt 2>/dev/null || true
    unset -f _rust_has_rustc 2>/dev/null || true
    unset -f _rust_has_cargo 2>/dev/null || true
    unset -f _rust_has_clippy 2>/dev/null || true
    unset -f _rust_has_rustfmt 2>/dev/null || true
}

# =============================================================================
# MOCK HELPERS
# =============================================================================

# Mock rustc as unavailable
mock_rustc_unavailable() {
    _rust_has_rustc() { return 1; }
}

# Mock cargo as unavailable
mock_cargo_unavailable() {
    _rust_has_cargo() { return 1; }
}

# Mock rustfmt as unavailable
mock_rustfmt_unavailable() {
    _rust_has_rustfmt() { return 1; }
}

# Mock clippy as unavailable
mock_clippy_unavailable() {
    _rust_has_clippy() { return 1; }
}

# Mock rustc as available
mock_rustc_available() {
    _rust_has_rustc() { return 0; }
    rustc() {
        case "$1" in
            --version)
                if [[ "$2" == "--verbose" ]]; then
                    cat << 'EOF'
rustc 1.75.0 (82e1608df 2023-12-21)
binary: rustc
commit-hash: 82e1608dfa6e0b5569232559e3d385fea5a93112
commit-date: 2023-12-21
host: x86_64-unknown-linux-gnu
release: 1.75.0
LLVM version: 17.0.6
EOF
                else
                    echo "rustc 1.75.0 (82e1608df 2023-12-21)"
                fi
                ;;
            *)
                echo "rustc mock: $*"
                ;;
        esac
    }
}

# Mock cargo as available
mock_cargo_available() {
    _rust_has_cargo() { return 0; }
    cargo() {
        case "$1" in
            --version)
                echo "cargo 1.75.0 (1d8b05cdd 2023-11-20)"
                ;;
            check)
                echo "    Checking my_crate v0.1.0"
                echo "    Finished dev [unoptimized + debuginfo] target(s) in 0.50s"
                return 0
                ;;
            test)
                cat << 'EOF'
   Compiling my_crate v0.1.0
    Finished test [unoptimized + debuginfo] target(s) in 1.50s
     Running unittests src/lib.rs

running 5 tests
test tests::test_add ... ok
test tests::test_sub ... ok
test tests::test_mul ... ok
test tests::test_div ... FAILED
test tests::test_mod ... ignored

test result: FAILED. 3 passed; 1 failed; 1 ignored; 0 measured; 0 filtered out
EOF
                return 1
                ;;
            clippy)
                echo "    Checking my_crate v0.1.0"
                echo "warning: unused variable: \`x\`"
                echo "warning: unused variable: \`y\`"
                echo "    Finished dev [unoptimized + debuginfo] target(s) in 0.30s"
                return 0
                ;;
            fmt)
                if [[ "$2" == "--" && "$3" == "--check" ]]; then
                    echo "Diff in /path/to/file1.rs at line 10:"
                    echo "Diff in /path/to/file2.rs at line 20:"
                    return 1
                fi
                return 0
                ;;
            *)
                echo "cargo mock: $*"
                return 0
                ;;
        esac
    }
}

# Mock clippy as available
mock_clippy_available() {
    mock_cargo_available
    _rust_has_clippy() { return 0; }
}

# Mock rustfmt as available
mock_rustfmt_available() {
    _rust_has_rustfmt() { return 0; }
    mock_cargo_available
}

# Mock cargo check with errors
mock_cargo_check_failure() {
    mock_cargo_available
    cargo() {
        case "$1" in
            check)
                cat << 'EOF'
error[E0425]: cannot find value `x` in this scope
 --> src/lib.rs:5:5
  |
5 |     x
  |     ^ not found in this scope

error: aborting due to previous error
EOF
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    }
}

# Mock cargo test all passing
mock_cargo_test_success() {
    mock_cargo_available
    cargo() {
        case "$1" in
            test)
                cat << 'EOF'
   Compiling my_crate v0.1.0
    Finished test [unoptimized + debuginfo] target(s) in 1.00s
     Running unittests src/lib.rs

running 10 tests
test tests::test_one ... ok
test tests::test_two ... ok

test result: ok. 10 passed; 0 failed; 2 ignored; 0 measured; 0 filtered out
EOF
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
}

# Mock fmt check passing
mock_fmt_check_success() {
    mock_rustfmt_available
    cargo() {
        case "$1" in
            fmt)
                # No output means everything is formatted
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
}

# =============================================================================
# HELPER: Validate USOP JSON format
# =============================================================================

assert_usop_ok() {
    local json="$1"
    local message="${2:-USOP should have ok:true}"

    if [[ "$json" != *'"ok":true'* ]]; then
        printf 'FAIL: %s\nJSON: %s\n' "$message" "$json" >&2
        return 1
    fi
}

assert_usop_error() {
    local json="$1"
    local message="${2:-USOP should have ok:false}"

    if [[ "$json" != *'"ok":false'* ]]; then
        printf 'FAIL: %s\nJSON: %s\n' "$message" "$json" >&2
        return 1
    fi
}

assert_usop_has_data() {
    local json="$1"
    local key="$2"
    local message="${3:-USOP should contain key: $key}"

    if [[ "$json" != *"\"$key\""* ]]; then
        printf 'FAIL: %s\nJSON: %s\n' "$message" "$json" >&2
        return 1
    fi
}

# =============================================================================
# rust_detect TESTS
# =============================================================================

@test "rust_detect returns JSON" {
    local result
    result=$(rust_detect "$TEST_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "rust_detect returns ok:true for valid directory" {
    local result
    result=$(rust_detect "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_detect returns error for nonexistent directory" {
    local result
    result=$(rust_detect "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "rust_detect returns is_rust:false for empty directory" {
    local result
    result=$(rust_detect "$TEST_DIR")
    [[ "$result" == *'"is_rust":false'* ]]
}

@test "rust_detect returns is_rust:true with Cargo.toml" {
    echo '[package]' > "$TEST_DIR/Cargo.toml"
    echo 'name = "test"' >> "$TEST_DIR/Cargo.toml"
    local result
    result=$(rust_detect "$TEST_DIR")
    [[ "$result" == *'"is_rust":true'* ]]
    [[ "$result" == *'"has_cargo_toml":true'* ]]
}

@test "rust_detect detects has_cargo_lock" {
    echo '[package]' > "$TEST_DIR/Cargo.toml"
    touch "$TEST_DIR/Cargo.lock"
    local result
    result=$(rust_detect "$TEST_DIR")
    [[ "$result" == *'"has_cargo_lock":true'* ]]
}

@test "rust_detect detects workspace" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[workspace]
members = ["crates/*"]
EOF
    local result
    result=$(rust_detect "$TEST_DIR")
    [[ "$result" == *'"is_workspace":true'* ]]
}

@test "rust_detect uses current directory by default" {
    cd "$TEST_DIR"
    echo '[package]' > Cargo.toml
    echo 'name = "test"' >> Cargo.toml
    local result
    result=$(rust_detect)
    [[ "$result" == *'"is_rust":true'* ]]
}

# =============================================================================
# rust_version TESTS
# =============================================================================

@test "rust_version returns error when rustc not installed" {
    mock_rustc_unavailable
    local result
    result=$(rust_version)
    assert_usop_error "$result"
    [[ "$result" == *'"error":"rustc not installed"'* ]]
}

@test "rust_version returns ok:true when rustc available" {
    mock_rustc_available
    local result
    result=$(rust_version)
    assert_usop_ok "$result"
}

@test "rust_version returns version string" {
    mock_rustc_available
    local result
    result=$(rust_version)
    [[ "$result" == *'"version":"1.75.0"'* ]]
}

@test "rust_version returns channel" {
    mock_rustc_available
    local result
    result=$(rust_version)
    [[ "$result" == *'"channel":"stable"'* ]]
}

@test "rust_version returns host" {
    mock_rustc_available
    local result
    result=$(rust_version)
    [[ "$result" == *'"host":"x86_64-unknown-linux-gnu"'* ]]
}

@test "rust_version returns llvm_version" {
    mock_rustc_available
    local result
    result=$(rust_version)
    assert_usop_has_data "$result" "llvm_version"
}

@test "rust_version detects nightly channel" {
    _rust_has_rustc() { return 0; }
    rustc() {
        echo "rustc 1.77.0-nightly (abc123 2024-01-15)"
    }
    local result
    result=$(rust_version)
    [[ "$result" == *'"channel":"nightly"'* ]]
}

@test "rust_version detects beta channel" {
    _rust_has_rustc() { return 0; }
    rustc() {
        echo "rustc 1.76.0-beta.1 (def456 2024-01-10)"
    }
    local result
    result=$(rust_version)
    [[ "$result" == *'"channel":"beta"'* ]]
}

# =============================================================================
# rust_crate_name TESTS
# =============================================================================

@test "rust_crate_name returns error without Cargo.toml" {
    local result
    result=$(rust_crate_name "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_crate_name returns ok:true with Cargo.toml" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "my_crate"
version = "0.1.0"
edition = "2021"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_crate_name extracts name" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "awesome_lib"
version = "1.0.0"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"name":"awesome_lib"'* ]]
}

@test "rust_crate_name extracts version" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "2.5.3"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"version":"2.5.3"'* ]]
}

@test "rust_crate_name extracts edition" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
edition = "2021"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"edition":"2021"'* ]]
}

@test "rust_crate_name defaults edition to 2015" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"edition":"2015"'* ]]
}

@test "rust_crate_name extracts authors" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
authors = "Test Author <test@example.com>"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    assert_usop_has_data "$result" "authors"
}

@test "rust_crate_name extracts description" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
description = "A test crate"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"description":"A test crate"'* ]]
}

@test "rust_crate_name extracts license" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
license = "MIT"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"license":"MIT"'* ]]
}

# =============================================================================
# rust_dependencies TESTS
# =============================================================================

@test "rust_dependencies returns error without Cargo.toml" {
    local result
    result=$(rust_dependencies "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_dependencies returns ok:true with Cargo.toml" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_dependencies "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_dependencies returns empty arrays without deps" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_dependencies "$TEST_DIR")
    [[ "$result" == *'"dependencies":[]'* ]]
    [[ "$result" == *'"dev_dependencies":[]'* ]]
}

@test "rust_dependencies parses dependencies" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[dependencies]
serde = "1.0"
tokio = { version = "1.0", features = ["full"] }
EOF
    local result
    result=$(rust_dependencies "$TEST_DIR")
    [[ "$result" == *'"dependencies":'* ]]
    [[ "$result" == *'serde'* ]]
    [[ "$result" == *'tokio'* ]]
}

@test "rust_dependencies parses dev-dependencies" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[dev-dependencies]
criterion = "0.5"
proptest = "1.0"
EOF
    local result
    result=$(rust_dependencies "$TEST_DIR")
    [[ "$result" == *'"dev_dependencies":'* ]]
    [[ "$result" == *'criterion'* ]]
    [[ "$result" == *'proptest'* ]]
}

@test "rust_dependencies parses build-dependencies" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[build-dependencies]
cc = "1.0"
EOF
    local result
    result=$(rust_dependencies "$TEST_DIR")
    [[ "$result" == *'"build_dependencies":'* ]]
    [[ "$result" == *'cc'* ]]
}

@test "rust_dependencies returns total count" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[dependencies]
serde = "1.0"
tokio = "1.0"

[dev-dependencies]
criterion = "0.5"
EOF
    local result
    result=$(rust_dependencies "$TEST_DIR")
    assert_usop_has_data "$result" "total"
}

# =============================================================================
# rust_features TESTS
# =============================================================================

@test "rust_features returns error without Cargo.toml" {
    local result
    result=$(rust_features "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_features returns ok:true with Cargo.toml" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_features "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_features returns empty array without features" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_features "$TEST_DIR")
    [[ "$result" == *'"features":[]'* ]]
}

@test "rust_features parses feature names" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[features]
default = ["std"]
std = []
async = ["tokio"]
EOF
    local result
    result=$(rust_features "$TEST_DIR")
    [[ "$result" == *'"features":'* ]]
    [[ "$result" == *'default'* ]]
    [[ "$result" == *'std'* ]]
    [[ "$result" == *'async'* ]]
}

@test "rust_features extracts default features" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[features]
default = ["std", "async"]
std = []
async = []
EOF
    local result
    result=$(rust_features "$TEST_DIR")
    assert_usop_has_data "$result" "default"
}

# =============================================================================
# rust_build_check TESTS
# =============================================================================

@test "rust_build_check returns error when cargo not installed" {
    mock_cargo_unavailable
    local result
    result=$(rust_build_check "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"cargo not installed"'* ]]
}

@test "rust_build_check returns error for nonexistent directory" {
    mock_cargo_available
    local result
    result=$(rust_build_check "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "rust_build_check returns error without Cargo.toml" {
    mock_cargo_available
    local result
    result=$(rust_build_check "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_build_check returns ok:true with Cargo.toml" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_build_check "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_build_check returns success:true on success" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_build_check "$TEST_DIR")
    [[ "$result" == *'"success":true'* ]]
}

@test "rust_build_check returns success:false on failure" {
    mock_cargo_check_failure
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_build_check "$TEST_DIR")
    [[ "$result" == *'"success":false'* ]]
}

@test "rust_build_check returns warnings count" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_build_check "$TEST_DIR")
    assert_usop_has_data "$result" "warnings"
}

@test "rust_build_check returns errors count" {
    mock_cargo_check_failure
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_build_check "$TEST_DIR")
    assert_usop_has_data "$result" "errors"
}

@test "rust_build_check returns output" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_build_check "$TEST_DIR")
    assert_usop_has_data "$result" "output"
}

@test "rust_build_check returns exit_code" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_build_check "$TEST_DIR")
    assert_usop_has_data "$result" "exit_code"
}

# =============================================================================
# rust_test_check TESTS
# =============================================================================

@test "rust_test_check returns error when cargo not installed" {
    mock_cargo_unavailable
    local result
    result=$(rust_test_check "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"cargo not installed"'* ]]
}

@test "rust_test_check returns error for nonexistent directory" {
    mock_cargo_available
    local result
    result=$(rust_test_check "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "rust_test_check returns error without Cargo.toml" {
    mock_cargo_available
    local result
    result=$(rust_test_check "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_test_check returns ok:true with Cargo.toml" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_test_check returns success:true when tests pass" {
    mock_cargo_test_success
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    [[ "$result" == *'"success":true'* ]]
}

@test "rust_test_check returns success:false when tests fail" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    [[ "$result" == *'"success":false'* ]]
}

@test "rust_test_check returns passed count" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    [[ "$result" == *'"passed":3'* ]]
}

@test "rust_test_check returns failed count" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    [[ "$result" == *'"failed":1'* ]]
}

@test "rust_test_check returns ignored count" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    [[ "$result" == *'"ignored":1'* ]]
}

@test "rust_test_check returns total count" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    assert_usop_has_data "$result" "total"
}

@test "rust_test_check returns output" {
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_test_check "$TEST_DIR")
    assert_usop_has_data "$result" "output"
}

# =============================================================================
# rust_clippy TESTS
# =============================================================================

@test "rust_clippy returns error when clippy not installed" {
    mock_clippy_unavailable
    local result
    result=$(rust_clippy "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"clippy not installed'* ]]
}

@test "rust_clippy returns error for nonexistent directory" {
    mock_clippy_available
    local result
    result=$(rust_clippy "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "rust_clippy returns error without Cargo.toml" {
    mock_clippy_available
    local result
    result=$(rust_clippy "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_clippy returns ok:true with Cargo.toml" {
    mock_clippy_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_clippy "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_clippy returns success status" {
    mock_clippy_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_clippy "$TEST_DIR")
    [[ "$result" == *'"success":true'* ]]
}

@test "rust_clippy returns warnings count" {
    mock_clippy_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_clippy "$TEST_DIR")
    assert_usop_has_data "$result" "warnings"
}

@test "rust_clippy returns errors count" {
    mock_clippy_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_clippy "$TEST_DIR")
    assert_usop_has_data "$result" "errors"
}

@test "rust_clippy returns output" {
    mock_clippy_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_clippy "$TEST_DIR")
    assert_usop_has_data "$result" "output"
}

# =============================================================================
# rust_fmt_check TESTS
# =============================================================================

@test "rust_fmt_check returns error when rustfmt not installed" {
    mock_rustfmt_unavailable
    local result
    result=$(rust_fmt_check "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"rustfmt not installed'* ]]
}

@test "rust_fmt_check returns error for nonexistent directory" {
    mock_rustfmt_available
    local result
    result=$(rust_fmt_check "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "rust_fmt_check returns error without Cargo.toml" {
    mock_rustfmt_available
    local result
    result=$(rust_fmt_check "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_fmt_check returns ok:true with Cargo.toml" {
    mock_rustfmt_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_fmt_check "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_fmt_check returns formatted:true when code is formatted" {
    mock_fmt_check_success
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_fmt_check "$TEST_DIR")
    [[ "$result" == *'"formatted":true'* ]]
}

@test "rust_fmt_check returns formatted:false when code needs formatting" {
    mock_rustfmt_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_fmt_check "$TEST_DIR")
    [[ "$result" == *'"formatted":false'* ]]
}

@test "rust_fmt_check returns files_need_formatting count" {
    mock_rustfmt_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_fmt_check "$TEST_DIR")
    assert_usop_has_data "$result" "files_need_formatting"
}

@test "rust_fmt_check returns output" {
    mock_rustfmt_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_fmt_check "$TEST_DIR")
    assert_usop_has_data "$result" "output"
}

# =============================================================================
# rust_project_summary TESTS
# =============================================================================

@test "rust_project_summary returns error for nonexistent directory" {
    local result
    result=$(rust_project_summary "/nonexistent/path/12345")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"directory not found"'* ]]
}

@test "rust_project_summary returns error without Cargo.toml" {
    local result
    result=$(rust_project_summary "$TEST_DIR")
    assert_usop_error "$result"
    [[ "$result" == *'"error":"Cargo.toml not found"'* ]]
}

@test "rust_project_summary returns ok:true with Cargo.toml" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    local result
    result=$(rust_project_summary "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "rust_project_summary returns name" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "awesome_project"
version = "1.0.0"
EOF
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"name":"awesome_project"'* ]]
}

@test "rust_project_summary returns version" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "2.3.4"
EOF
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"version":"2.3.4"'* ]]
}

@test "rust_project_summary returns edition" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
edition = "2021"
EOF
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"edition":"2021"'* ]]
}

@test "rust_project_summary detects bin type with main.rs" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    mkdir -p "$TEST_DIR/src"
    touch "$TEST_DIR/src/main.rs"
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"type":"bin"'* ]]
}

@test "rust_project_summary detects lib type with lib.rs" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    mkdir -p "$TEST_DIR/src"
    touch "$TEST_DIR/src/lib.rs"
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"type":"lib"'* ]]
}

@test "rust_project_summary detects bin+lib type" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    mkdir -p "$TEST_DIR/src"
    touch "$TEST_DIR/src/main.rs"
    touch "$TEST_DIR/src/lib.rs"
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"type":"bin+lib"'* ]]
}

@test "rust_project_summary detects workspace" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[workspace]
members = ["crates/*"]
EOF
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"is_workspace":true'* ]]
}

@test "rust_project_summary returns deps_count" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[dependencies]
serde = "1.0"
tokio = "1.0"
EOF
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"deps_count":2'* ]]
}

@test "rust_project_summary returns dev_deps_count" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"

[dev-dependencies]
criterion = "0.5"
proptest = "1.0"
mockall = "0.12"
EOF
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"dev_deps_count":3'* ]]
}

@test "rust_project_summary detects clippy.toml" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    touch "$TEST_DIR/clippy.toml"
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"has_clippy_toml":true'* ]]
}

@test "rust_project_summary detects .clippy.toml" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    touch "$TEST_DIR/.clippy.toml"
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"has_clippy_toml":true'* ]]
}

@test "rust_project_summary detects rustfmt.toml" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    touch "$TEST_DIR/rustfmt.toml"
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"has_rustfmt_toml":true'* ]]
}

@test "rust_project_summary detects Cargo.lock" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF
    touch "$TEST_DIR/Cargo.lock"
    local result
    result=$(rust_project_summary "$TEST_DIR")
    [[ "$result" == *'"has_cargo_lock":true'* ]]
}

# =============================================================================
# EDGE CASES & INTEGRATION TESTS
# =============================================================================

@test "all functions return valid JSON" {
    mock_rustc_available
    mock_cargo_available
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "test"
version = "0.1.0"
EOF

    local funcs=(
        "rust_detect"
        "rust_version"
    )

    for func in "${funcs[@]}"; do
        local result
        result=$($func "$TEST_DIR" 2>/dev/null || $func 2>/dev/null)
        [[ "$result" == "{"* ]] || { echo "FAIL: $func did not return JSON"; return 1; }
        [[ "$result" == *"}" ]] || { echo "FAIL: $func JSON not closed"; return 1; }
    done
}

@test "project functions work with current directory" {
    cd "$TEST_DIR"
    cat > Cargo.toml << 'EOF'
[package]
name = "cwd_test"
version = "0.1.0"
EOF
    local result
    result=$(rust_detect)
    [[ "$result" == *'"is_rust":true'* ]]
}

@test "Cargo.toml with complex dependencies" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "complex_crate"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
tokio = { version = "1.0", features = ["full", "rt-multi-thread"] }
clap = { version = "4.0", default-features = false, features = ["std", "derive"] }
uuid = { version = "1.0", features = ["v4", "serde"] }

[dev-dependencies]
criterion = { version = "0.5", features = ["html_reports"] }

[build-dependencies]
cc = "1.0"
EOF
    local result
    result=$(rust_dependencies "$TEST_DIR")
    assert_usop_ok "$result"
}

@test "USOP format consistency across all error responses" {
    mock_rustc_unavailable
    mock_cargo_unavailable

    local result

    # All these should return ok:false with error field
    result=$(rust_version)
    [[ "$result" == *'"ok":false'* ]] && [[ "$result" == *'"error":'* ]]

    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"ok":false'* ]] && [[ "$result" == *'"error":'* ]]

    result=$(rust_dependencies "$TEST_DIR")
    [[ "$result" == *'"ok":false'* ]] && [[ "$result" == *'"error":'* ]]
}

@test "handles Cargo.toml with workspace members" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[workspace]
members = [
    "crates/core",
    "crates/cli",
    "crates/utils"
]

[workspace.package]
version = "0.1.0"
edition = "2021"
license = "MIT"
EOF
    local result
    result=$(rust_detect "$TEST_DIR")
    [[ "$result" == *'"is_workspace":true'* ]]
}

@test "handles Cargo.toml with inline tables" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "inline_test"
version = "0.1.0"

[dependencies]
serde = { version = "1", features = ["derive"] }
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    [[ "$result" == *'"name":"inline_test"'* ]]
}

@test "handles quotes in Cargo.toml values" {
    cat > "$TEST_DIR/Cargo.toml" << 'EOF'
[package]
name = "quoted_test"
version = "0.1.0"
description = "A crate with \"quotes\" in description"
EOF
    local result
    result=$(rust_crate_name "$TEST_DIR")
    assert_usop_ok "$result"
}


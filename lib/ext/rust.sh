#!/usr/bin/env bash
# shellcheck disable=SC2155
# =============================================================================
# MAINFRAME/lib/ext/rust.sh - Rust/Cargo Project Analysis Library
# =============================================================================
# Description: Rust project detection, Cargo.toml parsing, build checks,
#              clippy/fmt integration, and AI agent helpers. Provides
#              structured JSON output via USOP pattern for machine parsing.
#
# Version: 1.0.0
# Requires: Bash 4.0+
# Dependencies: json.sh, toml.sh (auto-loaded)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_RUST_LOADED:-}" ]] && return 0
readonly _MAINFRAME_RUST_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Get library directory for sourcing dependencies
_RUST_LIB_DIR="${BASH_SOURCE[0]%/*}"
_RUST_LIB_DIR="${_RUST_LIB_DIR%/ext}"

# Lazy-load json.sh if json_object is not available
if ! declare -F json_object &>/dev/null; then
    if [[ -f "${_RUST_LIB_DIR}/json.sh" ]]; then
        source "${_RUST_LIB_DIR}/json.sh"
    fi
fi

# Lazy-load toml.sh if toml_get is not available
if ! declare -F toml_get &>/dev/null; then
    if [[ -f "${_RUST_LIB_DIR}/toml.sh" ]]; then
        source "${_RUST_LIB_DIR}/toml.sh"
    fi
fi

# =============================================================================
# CONSTANTS
# =============================================================================

# Maximum output length for command output (prevents context bloat)
readonly _RUST_MAX_OUTPUT_CHARS=4000

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if rustc CLI is available
_rust_has_rustc() {
    command -v rustc &>/dev/null
}

# Check if cargo CLI is available
_rust_has_cargo() {
    command -v cargo &>/dev/null
}

# Check if clippy is available
_rust_has_clippy() {
    _rust_has_cargo && cargo clippy --version &>/dev/null 2>&1
}

# Check if rustfmt is available
_rust_has_rustfmt() {
    command -v rustfmt &>/dev/null
}

# Truncate string to max length with ellipsis
# Usage: _rust_truncate "string" [max_chars]
_rust_truncate() {
    local str="$1"
    local max="${2:-$_RUST_MAX_OUTPUT_CHARS}"

    if [[ ${#str} -gt $max ]]; then
        printf '%s... [truncated %d chars]' "${str:0:$max}" "$((${#str} - max))"
    else
        printf '%s' "$str"
    fi
}

# Parse a simple value from Cargo.toml using regex
# Usage: _rust_cargo_get "Cargo.toml content" "key"
_rust_cargo_get() {
    local content="$1"
    local key="$2"
    local value=""

    # Try to match key = "value" pattern
    if [[ "$content" =~ ${key}[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        value="${BASH_REMATCH[1]}"
    # Try key = 'value' pattern
    elif [[ "$content" =~ ${key}[[:space:]]*=[[:space:]]*\'([^\']+)\' ]]; then
        value="${BASH_REMATCH[1]}"
    # Try key = value (unquoted, for numbers/booleans)
    elif [[ "$content" =~ ${key}[[:space:]]*=[[:space:]]*([^[:space:]\#\[]+) ]]; then
        value="${BASH_REMATCH[1]}"
    fi

    printf '%s' "$value"
}

# Extract a TOML section content
# Usage: _rust_get_section "content" "section_name"
_rust_get_section() {
    local content="$1"
    local section="$2"
    local in_section=false
    local section_content=""

    while IFS= read -r line; do
        # Check for section header
        if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
            local current_section="${BASH_REMATCH[1]}"
            if [[ "$current_section" == "$section" ]]; then
                in_section=true
                continue
            elif $in_section; then
                # New section started, we're done
                break
            fi
        elif $in_section; then
            section_content+="$line"$'\n'
        fi
    done <<< "$content"

    printf '%s' "$section_content"
}

# Parse dependencies from a TOML section
# Usage: _rust_parse_deps "section_content"
_rust_parse_deps() {
    local content="$1"
    local -a deps=()

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Match: name = "version" or name = { version = "x", ... }
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*= ]]; then
            local dep_name="${BASH_REMATCH[1]}"
            deps+=("$dep_name")
        fi
    done <<< "$content"

    # Output as JSON array
    local first=true
    printf '['
    for dep in "${deps[@]}"; do
        $first || printf ','
        first=false
        printf '"%s"' "$dep"
    done
    printf ']'
}

# Parse features from Cargo.toml
# Usage: _rust_parse_features "content"
_rust_parse_features() {
    local content="$1"
    local features_section
    features_section=$(_rust_get_section "$content" "features")

    local -a features=()

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Match: feature_name = [...]
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*= ]]; then
            local feature_name="${BASH_REMATCH[1]}"
            features+=("$feature_name")
        fi
    done <<< "$features_section"

    # Output as JSON array
    local first=true
    printf '['
    for feat in "${features[@]}"; do
        $first || printf ','
        first=false
        printf '"%s"' "$feat"
    done
    printf ']'
}

# =============================================================================
# DETECTION & ENVIRONMENT
# =============================================================================

# @idempotent Detect if directory is a Rust/Cargo project
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"is_rust":bool,"has_cargo_toml":bool,"has_cargo_lock":bool,"is_workspace":bool}}
#
# Detects if a directory contains a Rust project by checking for Cargo.toml.
# Also detects workspace configurations.
#
# Usage: rust_detect [directory]
# Example: rust_detect /path/to/project
rust_detect() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    local is_rust="false"
    local has_cargo_toml="false"
    local has_cargo_lock="false"
    local is_workspace="false"

    # Check for Cargo.toml
    if [[ -f "$dir/Cargo.toml" ]]; then
        has_cargo_toml="true"
        is_rust="true"

        # Check if it's a workspace
        local cargo_content
        cargo_content=$(<"$dir/Cargo.toml")
        if [[ "$cargo_content" == *"[workspace]"* ]]; then
            is_workspace="true"
        fi
    fi

    # Check for Cargo.lock
    [[ -f "$dir/Cargo.lock" ]] && has_cargo_lock="true"

    local data
    json_object_v data \
        "is_rust:bool=$is_rust" \
        "has_cargo_toml:bool=$has_cargo_toml" \
        "has_cargo_lock:bool=$has_cargo_lock" \
        "is_workspace:bool=$is_workspace"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent Get rustc version info
# @return {"ok":true,"data":{"version":"1.75.0","channel":"stable","host":"x86_64-unknown-linux-gnu"}}
#
# Returns detailed version information for the installed Rust compiler.
#
# Usage: rust_version
# Example: result=$(rust_version)
rust_version() {
    if ! _rust_has_rustc; then
        json_object \
            "ok:bool=false" \
            "error=rustc not installed"
        return 0
    fi

    local version_output
    version_output=$(rustc --version --verbose 2>/dev/null)

    local version="" channel="" host="" release="" llvm_version=""

    # Parse version info
    if [[ "$version_output" =~ rustc[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        version="${BASH_REMATCH[1]}"
    fi

    # Detect channel from version string
    if [[ "$version_output" =~ -nightly ]]; then
        channel="nightly"
    elif [[ "$version_output" =~ -beta ]]; then
        channel="beta"
    else
        channel="stable"
    fi

    # Parse host
    if [[ "$version_output" =~ host:[[:space:]]*([^[:space:]]+) ]]; then
        host="${BASH_REMATCH[1]}"
    fi

    # Parse release
    if [[ "$version_output" =~ release:[[:space:]]*([^[:space:]]+) ]]; then
        release="${BASH_REMATCH[1]}"
    fi

    # Parse LLVM version
    if [[ "$version_output" =~ LLVM[[:space:]]+version:[[:space:]]*([0-9]+\.[0-9]+) ]]; then
        llvm_version="${BASH_REMATCH[1]}"
    fi

    local data
    json_object_v data \
        "version=$version" \
        "channel=$channel" \
        "host=$host" \
        "release=$release" \
        "llvm_version=$llvm_version"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent Get crate name from Cargo.toml
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"name":"crate_name","version":"0.1.0","edition":"2021"}}
#
# Extracts the crate name, version, and edition from Cargo.toml.
#
# Usage: rust_crate_name [directory]
# Example: rust_crate_name /path/to/project
rust_crate_name() {
    local dir="${1:-.}"
    local cargo_file="$dir/Cargo.toml"

    if [[ ! -f "$cargo_file" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local cargo_content
    cargo_content=$(<"$cargo_file")

    local name version edition authors description license

    name=$(_rust_cargo_get "$cargo_content" "name")
    version=$(_rust_cargo_get "$cargo_content" "version")
    edition=$(_rust_cargo_get "$cargo_content" "edition")
    authors=$(_rust_cargo_get "$cargo_content" "authors")
    description=$(_rust_cargo_get "$cargo_content" "description")
    license=$(_rust_cargo_get "$cargo_content" "license")

    # Default edition if not specified
    [[ -z "$edition" ]] && edition="2015"

    local data
    json_object_v data \
        "name=$name" \
        "version=$version" \
        "edition:string=$edition" \
        "authors=$authors" \
        "description=$description" \
        "license=$license"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent List dependencies from Cargo.toml
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"dependencies":[...],"dev_dependencies":[...],"build_dependencies":[...]}}
#
# Lists all dependencies from Cargo.toml organized by type.
#
# Usage: rust_dependencies [directory]
# Example: rust_dependencies /path/to/project
rust_dependencies() {
    local dir="${1:-.}"
    local cargo_file="$dir/Cargo.toml"

    if [[ ! -f "$cargo_file" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local cargo_content
    cargo_content=$(<"$cargo_file")

    # Parse each dependency section
    local deps_section dev_deps_section build_deps_section
    deps_section=$(_rust_get_section "$cargo_content" "dependencies")
    dev_deps_section=$(_rust_get_section "$cargo_content" "dev-dependencies")
    build_deps_section=$(_rust_get_section "$cargo_content" "build-dependencies")

    local deps_json dev_deps_json build_deps_json
    deps_json=$(_rust_parse_deps "$deps_section")
    dev_deps_json=$(_rust_parse_deps "$dev_deps_section")
    build_deps_json=$(_rust_parse_deps "$build_deps_section")

    # Count total dependencies
    local total=0
    # Count array elements by removing brackets and commas
    local deps_stripped="${deps_json//[\[\]\"]/}"
    local dev_deps_stripped="${dev_deps_json//[\[\]\"]/}"
    local build_deps_stripped="${build_deps_json//[\[\]\"]/}"

    [[ -n "$deps_stripped" ]] && total=$((total + $(echo "$deps_stripped" | tr ',' '\n' | wc -l)))
    [[ -n "$dev_deps_stripped" ]] && total=$((total + $(echo "$dev_deps_stripped" | tr ',' '\n' | wc -l)))
    [[ -n "$build_deps_stripped" ]] && total=$((total + $(echo "$build_deps_stripped" | tr ',' '\n' | wc -l)))

    local data
    printf -v data '{"dependencies":%s,"dev_dependencies":%s,"build_dependencies":%s,"total":%d}' \
        "$deps_json" "$dev_deps_json" "$build_deps_json" "$total"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent List features from Cargo.toml
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"features":[...],"default":[...]}}
#
# Lists all features defined in Cargo.toml.
#
# Usage: rust_features [directory]
# Example: rust_features /path/to/project
rust_features() {
    local dir="${1:-.}"
    local cargo_file="$dir/Cargo.toml"

    if [[ ! -f "$cargo_file" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local cargo_content
    cargo_content=$(<"$cargo_file")

    local features_json
    features_json=$(_rust_parse_features "$cargo_content")

    # Try to extract default features
    local default_features="[]"
    if [[ "$cargo_content" =~ default[[:space:]]*=[[:space:]]*\[([^\]]*)\] ]]; then
        local default_content="${BASH_REMATCH[1]}"
        # Parse the array content
        local -a defaults=()
        while [[ "$default_content" =~ \"([^\"]+)\" ]]; do
            defaults+=("${BASH_REMATCH[1]}")
            default_content="${default_content#*\"${BASH_REMATCH[1]}\"}"
        done
        # Build JSON array
        local first=true
        default_features='['
        for d in "${defaults[@]}"; do
            $first || default_features+=','
            first=false
            default_features+="\"$d\""
        done
        default_features+=']'
    fi

    local data
    printf -v data '{"features":%s,"default":%s}' "$features_json" "$default_features"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# BUILD & CHECK OPERATIONS
# =============================================================================

# @pre rust_detect returns is_rust=true
# Check if project builds (cargo check)
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"success":bool,"warnings":N,"errors":N,"output":"..."}}
#
# Runs cargo check to verify the project compiles without errors.
#
# Usage: rust_build_check [directory]
# Example: rust_build_check /path/to/project
rust_build_check() {
    local dir="${1:-.}"

    if ! _rust_has_cargo; then
        json_object \
            "ok:bool=false" \
            "error=cargo not installed"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/Cargo.toml" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    output=$(cd "$dir" && cargo check --message-format=short 2>&1)
    exit_code=$?

    local truncated_output
    truncated_output=$(_rust_truncate "$output")

    # Count warnings and errors
    local warnings=0 errors=0
    warnings=$(echo "$output" | grep -c "warning:" || echo "0")
    errors=$(echo "$output" | grep -c "error\[" || echo "0")

    local success="false"
    [[ $exit_code -eq 0 ]] && success="true"

    local data
    json_object_v data \
        "success:bool=$success" \
        "warnings:number=$warnings" \
        "errors:number=$errors" \
        "exit_code:number=$exit_code" \
        "output=$truncated_output"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @pre rust_detect returns is_rust=true
# Run tests (cargo test)
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"success":bool,"passed":N,"failed":N,"ignored":N,"output":"..."}}
#
# Runs cargo test and parses the results.
#
# Usage: rust_test_check [directory]
# Example: rust_test_check /path/to/project
rust_test_check() {
    local dir="${1:-.}"

    if ! _rust_has_cargo; then
        json_object \
            "ok:bool=false" \
            "error=cargo not installed"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/Cargo.toml" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    output=$(cd "$dir" && cargo test 2>&1)
    exit_code=$?

    local truncated_output
    truncated_output=$(_rust_truncate "$output")

    # Parse test results: "test result: ok. X passed; Y failed; Z ignored"
    local passed=0 failed=0 ignored=0

    if [[ "$output" =~ ([0-9]+)[[:space:]]+passed ]]; then
        passed="${BASH_REMATCH[1]}"
    fi
    if [[ "$output" =~ ([0-9]+)[[:space:]]+failed ]]; then
        failed="${BASH_REMATCH[1]}"
    fi
    if [[ "$output" =~ ([0-9]+)[[:space:]]+ignored ]]; then
        ignored="${BASH_REMATCH[1]}"
    fi

    local success="false"
    [[ $exit_code -eq 0 ]] && success="true"

    local total=$((passed + failed + ignored))

    local data
    json_object_v data \
        "success:bool=$success" \
        "passed:number=$passed" \
        "failed:number=$failed" \
        "ignored:number=$ignored" \
        "total:number=$total" \
        "exit_code:number=$exit_code" \
        "output=$truncated_output"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @pre rust_detect returns is_rust=true
# Run clippy linter
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"success":bool,"warnings":N,"errors":N,"output":"..."}}
#
# Runs cargo clippy to check for common mistakes and improvements.
#
# Usage: rust_clippy [directory]
# Example: rust_clippy /path/to/project
rust_clippy() {
    local dir="${1:-.}"

    if ! _rust_has_clippy; then
        json_object \
            "ok:bool=false" \
            "error=clippy not installed (run: rustup component add clippy)"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/Cargo.toml" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    output=$(cd "$dir" && cargo clippy --message-format=short 2>&1)
    exit_code=$?

    local truncated_output
    truncated_output=$(_rust_truncate "$output")

    # Count warnings and errors
    local warnings=0 errors=0
    warnings=$(echo "$output" | grep -c "warning:" || echo "0")
    errors=$(echo "$output" | grep -c "error\[" || echo "0")

    local success="false"
    [[ $exit_code -eq 0 ]] && success="true"

    local data
    json_object_v data \
        "success:bool=$success" \
        "warnings:number=$warnings" \
        "errors:number=$errors" \
        "exit_code:number=$exit_code" \
        "output=$truncated_output"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @pre rust_detect returns is_rust=true
# Check code formatting
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"formatted":bool,"files_need_formatting":N,"output":"..."}}
#
# Runs cargo fmt --check to verify code is properly formatted.
#
# Usage: rust_fmt_check [directory]
# Example: rust_fmt_check /path/to/project
rust_fmt_check() {
    local dir="${1:-.}"

    if ! _rust_has_rustfmt; then
        json_object \
            "ok:bool=false" \
            "error=rustfmt not installed (run: rustup component add rustfmt)"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/Cargo.toml" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    output=$(cd "$dir" && cargo fmt -- --check 2>&1)
    exit_code=$?

    local truncated_output
    truncated_output=$(_rust_truncate "$output")

    # Count files that need formatting (lines starting with "Diff in")
    local files_need_formatting=0
    files_need_formatting=$(echo "$output" | grep -c "^Diff in" || echo "0")

    local formatted="false"
    [[ $exit_code -eq 0 ]] && formatted="true"

    local data
    json_object_v data \
        "formatted:bool=$formatted" \
        "files_need_formatting:number=$files_need_formatting" \
        "exit_code:number=$exit_code" \
        "output=$truncated_output"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# AI AGENT HELPERS
# =============================================================================

# @idempotent Get comprehensive project summary for AI context
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"name":"proj","version":"0.1.0","edition":"2021","type":"bin|lib","deps_count":N}}
#
# Provides a comprehensive summary of a Rust project for AI agent context.
#
# Usage: rust_project_summary [directory]
# Example: rust_project_summary /path/to/project
rust_project_summary() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/Cargo.toml" ]]; then
        json_object \
            "ok:bool=false" \
            "error=Cargo.toml not found" \
            "path=$dir"
        return 0
    fi

    local cargo_content
    cargo_content=$(<"$dir/Cargo.toml")

    # Extract basic metadata
    local name version edition
    name=$(_rust_cargo_get "$cargo_content" "name")
    version=$(_rust_cargo_get "$cargo_content" "version")
    edition=$(_rust_cargo_get "$cargo_content" "edition")
    [[ -z "$edition" ]] && edition="2015"

    # Determine project type (bin, lib, or both)
    local project_type="lib"
    if [[ -f "$dir/src/main.rs" ]]; then
        project_type="bin"
    fi
    if [[ -f "$dir/src/lib.rs" ]] && [[ -f "$dir/src/main.rs" ]]; then
        project_type="bin+lib"
    fi
    if [[ "$cargo_content" == *"[[bin]]"* ]]; then
        project_type="bin"
    fi

    # Check for workspace
    local is_workspace="false"
    [[ "$cargo_content" == *"[workspace]"* ]] && is_workspace="true"

    # Count dependencies
    local deps_section dev_deps_section
    deps_section=$(_rust_get_section "$cargo_content" "dependencies")
    dev_deps_section=$(_rust_get_section "$cargo_content" "dev-dependencies")

    local deps_count=0 dev_deps_count=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[a-zA-Z0-9_-]+[[:space:]]*= ]] && ((deps_count++))
    done <<< "$deps_section"

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[a-zA-Z0-9_-]+[[:space:]]*= ]] && ((dev_deps_count++))
    done <<< "$dev_deps_section"

    # Check for common tooling
    local has_clippy_toml="false" has_rustfmt_toml="false" has_cargo_lock="false"
    [[ -f "$dir/clippy.toml" || -f "$dir/.clippy.toml" ]] && has_clippy_toml="true"
    [[ -f "$dir/rustfmt.toml" || -f "$dir/.rustfmt.toml" ]] && has_rustfmt_toml="true"
    [[ -f "$dir/Cargo.lock" ]] && has_cargo_lock="true"

    local data
    printf -v data '{"name":"%s","version":"%s","edition":"%s","type":"%s","is_workspace":%s,"deps_count":%d,"dev_deps_count":%d,"has_clippy_toml":%s,"has_rustfmt_toml":%s,"has_cargo_lock":%s}' \
        "$name" "$version" "$edition" "$project_type" "$is_workspace" "$deps_count" "$dev_deps_count" "$has_clippy_toml" "$has_rustfmt_toml" "$has_cargo_lock"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_RUST_EXPORTS=(
    # Detection & Environment
    rust_detect
    rust_version
    rust_crate_name
    # Project Analysis
    rust_dependencies
    rust_features
    # Build & Check
    rust_build_check
    rust_test_check
    rust_clippy
    rust_fmt_check
    # AI Agent Helpers
    rust_project_summary
)

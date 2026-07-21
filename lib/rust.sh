#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/rust.sh - Rust Project Analysis (No Toolchain Required)
# =============================================================================
# Description: Static analysis of Rust projects using pure bash. Extracts use
#              statements, parses Cargo.toml, detects unsafe blocks, and provides
#              project health metrics without requiring rustc or cargo.
# Version: 1.0.0
# Requires: Bash 4.0+
#
# LIMITATIONS (regex-based parsing, not AST):
#   - Cannot resolve re-exports (pub use) across crate boundaries
#   - Cannot detect macro-generated imports or cfg-conditional code
#   - Cargo.toml parsing handles simple TOML only (not inline tables)
#   - Cannot follow mod.rs/mod declarations for file resolution
#   - Cannot detect feature-gated dependencies
#   - Multi-line block comments (/* */) are not stripped from LOC counts
#   - Nested use groups (use std::{io::{self, Read}}) partially handled
#   - Workspace member glob patterns are not expanded
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

[[ -n "${_MAINFRAME_RUST_LOADED:-}" ]] && return 0
readonly _MAINFRAME_RUST_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _rust_escape_json STRING
# Escape a string for safe JSON embedding
_rust_escape_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

# _rust_kv_value RECORD KEY
# Extract a value from a comma-separated key=value record
_rust_kv_value() {
    local record="$1"
    local key="$2"
    local value

    value="${record#*"${key}="}"
    [[ "$value" != "$record" ]] || return 1
    value="${value%%,*}"
    printf '%s\n' "$value"
}

# _rust_grep_count PATTERN FILE
# Count regex matches while remaining safe under set -e and BSD grep
_rust_grep_count() {
    local pattern="$1"
    local file="$2"
    local count

    count=$(grep -cE "$pattern" "$file" 2>/dev/null || true)
    printf '%s\n' "${count:-0}"
}

# _rust_non_comment_count FILE PATTERN
# Count matches after stripping single-line comments
_rust_non_comment_count() {
    local file="$1"
    local pattern="$2"
    local count

    count=$(sed 's|//.*||' "$file" 2>/dev/null | grep -cE "$pattern" || true)
    printf '%s\n' "${count:-0}"
}

# _rust_loc_count FILE
# Count non-blank, non-comment lines in a Rust file
_rust_loc_count() {
    local file="$1"
    local count

    count=$(sed '/\/\*/,/\*\//d' "$file" 2>/dev/null | grep -cvE '^\s*$|^\s*//' || true)
    printf '%s\n' "${count:-0}"
}

# _rust_find_files DIR
# Find all .rs source files excluding target/ and hidden directories
_rust_find_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    # Exclude dot-directories INSIDE the project only: a naive
    # ! -path "*/\.*" also excludes everything when the project itself
    # lives under a dot directory (e.g. ~/.mainframe).
    local f rel
    while IFS= read -r f; do
        rel="${f#$dir/}"
        [[ "$rel" == .* || "$rel" == */.* ]] && continue
        printf '%s\n' "$f"
    done < <(find "$dir" -type f -name "*.rs" ! -path "*/target/*" 2>/dev/null)
}

# _rust_find_src_files DIR
# Find source files only (no tests)
_rust_find_src_files() {
    local dir="$1"
    local src_dir
    src_dir=$(rust_source_dir "$dir") || return 1
    find "$src_dir" -type f -name "*.rs" \
        ! -path "*/target/*" \
        ! -name "*test*" 2>/dev/null
}

# =============================================================================
# PROJECT DETECTION
# =============================================================================

# rust_is_project DIR
# Check if directory is a Rust project (has Cargo.toml)
rust_is_project() {
    local dir="${1:-.}"
    [[ -f "${dir}/Cargo.toml" ]]
}

# rust_source_dir DIR
# Find the source directory (src/)
rust_source_dir() {
    local dir="${1:-.}"

    if [[ -d "${dir}/src" ]]; then
        echo "${dir}/src"
        return 0
    fi

    # Workspace: check for members
    if [[ -f "${dir}/Cargo.toml" ]]; then
        echo "$dir"
        return 0
    fi

    return 1
}

# =============================================================================
# CARGO.TOML PARSING
# =============================================================================

# rust_parse_cargo DIR
# Parse Cargo.toml for package metadata
# Output: "name=X,version=Y,edition=Z"
rust_parse_cargo() {
    local dir="${1:-.}"
    local manifest="${dir}/Cargo.toml"
    [[ -f "$manifest" ]] || return 1

    local name="" version="" edition=""
    local in_package=0

    while IFS= read -r line; do
        # Section headers
        if [[ "$line" =~ ^\[package\] ]]; then
            in_package=1
            continue
        elif [[ "$line" =~ ^\[.*\] ]]; then
            in_package=0
            continue
        fi

        if [[ $in_package -eq 1 ]]; then
            if [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^version[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
                version="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^edition[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
                edition="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$manifest"

    echo "name=${name},version=${version},edition=${edition}"
}

# rust_dep_count DIR
# Count dependencies by category
# Output: "regular=N,dev=N,build=N"
rust_dep_count() {
    local dir="${1:-.}"
    local manifest="${dir}/Cargo.toml"
    [[ -f "$manifest" ]] || return 1

    local regular=0 dev=0 build=0
    local current_section=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^\[dependencies\]$ ]]; then
            current_section="reg"
            continue
        elif [[ "$line" =~ ^\[dev-dependencies\]$ ]]; then
            current_section="dev"
            continue
        elif [[ "$line" =~ ^\[build-dependencies\]$ ]]; then
            current_section="build"
            continue
        elif [[ "$line" =~ ^\[.*\]$ ]]; then
            current_section=""
            continue
        fi

        # Count dependency entries (lines starting with alphanumeric)
        if [[ -n "$current_section" && "$line" =~ ^[a-zA-Z0-9_-]+[[:space:]]*= ]]; then
            case "$current_section" in
                reg)   regular=$((regular + 1)) ;;
                dev)   dev=$((dev + 1)) ;;
                build) build=$((build + 1)) ;;
            esac
        fi
    done < "$manifest"

    echo "regular=${regular},dev=${dev},build=${build}"
}

# =============================================================================
# IMPORT ANALYSIS
# =============================================================================

# rust_file_imports FILE
# Extract use statements from a Rust file
# Handles: simple, nested {}, aliased (as), glob (*)
# Output: one import path per line
rust_file_imports() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    while IFS= read -r line; do
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*//.* ]] && continue

        # Match use statements
        if [[ "$line" =~ ^[[:space:]]*(pub[[:space:]]+)?use[[:space:]]+ ]]; then
            # Extract path after 'use' and before ';'
            local path="${line#*use }"
            path="${path%;*}"
            path="${path#pub use }"
            path="${path// /}"

            # Handle nested braces: use std::{io, fs, path::PathBuf}
            if [[ "$path" == *"{"*"}"* ]]; then
                local prefix="${path%%\{*}"
                prefix="${prefix%::}"
                local inner="${path#*\{}"
                inner="${inner%\}*}"

                # Split by comma
                IFS=',' read -ra parts <<< "$inner"
                for part in "${parts[@]}"; do
                    part="${part// /}"
                    # Handle self
                    if [[ "$part" == "self" ]]; then
                        echo "$prefix"
                    elif [[ -n "$part" ]]; then
                        # Remove 'as alias' suffix
                        part="${part%% as *}"
                        echo "${prefix}::${part}"
                    fi
                done
            else
                # Simple or aliased import
                path="${path%% as *}"
                echo "$path"
            fi
        fi
    done < "$file"
}

# rust_import_frequency DIR
# List most-used crates/modules across the project
# Output: "COUNT PATH" sorted by frequency
rust_import_frequency() {
    local dir="${1:-.}"
    local tmpfile
    tmpfile=$(mktemp)

    while IFS= read -r file; do
        rust_file_imports "$file" >> "$tmpfile"
    done < <(_rust_find_files "$dir")

    sort "$tmpfile" | uniq -c | sort -rn
    rm -f "$tmpfile"
}

# rust_import_graph DIR
# Build file-to-imports mapping
# Output: "file:import1,import2,..."
rust_import_graph() {
    local dir="${1:-.}"

    while IFS= read -r file; do
        local rel="${file#$dir/}"
        local imports
        imports=$(rust_file_imports "$file" | tr '\n' ',' | sed 's/,$//')
        [[ -n "$imports" ]] && echo "${rel}:${imports}"
    done < <(_rust_find_files "$dir")
}

# =============================================================================
# CODE METRICS
# =============================================================================

# rust_unsafe_count DIR
# Count unsafe blocks, functions, and impl blocks
# Output: "blocks=N,functions=N,impls=N"
rust_unsafe_count() {
    local dir="${1:-.}"
    local blocks=0 funcs=0 impls=0

    while IFS= read -r file; do
        local b f i
        b=$(_rust_non_comment_count "$file" 'unsafe\s*\{')
        f=$(_rust_non_comment_count "$file" 'unsafe\s+fn\s')
        i=$(_rust_non_comment_count "$file" 'unsafe\s+impl\s')

        blocks=$((blocks + b))
        funcs=$((funcs + f))
        impls=$((impls + i))
    done < <(_rust_find_files "$dir")

    echo "blocks=${blocks},functions=${funcs},impls=${impls}"
}

# rust_function_count DIR
# Count function definitions
rust_function_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local c
        c=$(_rust_grep_count '^\s*(pub(\s*\(.*\))?\s+)?(async\s+)?fn\s+\w+' "$file")
        count=$((count + c))
    done < <(_rust_find_files "$dir")

    echo "$count"
}

# rust_trait_count DIR
# Count trait definitions
rust_trait_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local c
        c=$(_rust_grep_count '^\s*(pub(\s*\(.*\))?\s+)?trait\s+\w+' "$file")
        count=$((count + c))
    done < <(_rust_find_files "$dir")

    echo "$count"
}

# rust_struct_count DIR
# Count struct definitions
rust_struct_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local c
        c=$(_rust_grep_count '^\s*(pub(\s*\(.*\))?\s+)?struct\s+\w+' "$file")
        count=$((count + c))
    done < <(_rust_find_files "$dir")

    echo "$count"
}

# rust_impl_count DIR
# Count impl blocks
rust_impl_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local c
        c=$(_rust_grep_count '^\s*impl(<.*>)?\s+(\w+::)*\w+' "$file")
        count=$((count + c))
    done < <(_rust_find_files "$dir")

    echo "$count"
}

# rust_enum_count DIR
# Count enum definitions
rust_enum_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local c
        c=$(_rust_grep_count '^\s*(pub(\s*\(.*\))?\s+)?enum\s+\w+' "$file")
        count=$((count + c))
    done < <(_rust_find_files "$dir")

    echo "$count"
}

# rust_loc DIR
# Lines of code (excluding blanks, single-line comments, and block comments)
rust_loc() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local c
        c=$(_rust_loc_count "$file")
        count=$((count + c))
    done < <(_rust_find_files "$dir")

    echo "$count"
}

# rust_test_coverage DIR
# Count test functions and test modules
# Output: "test_functions=N,test_modules=N"
rust_test_coverage() {
    local dir="${1:-.}"
    local test_funcs=0 test_mods=0

    while IFS= read -r file; do
        local f m
        f=$(_rust_grep_count '^\s*#\[test\]' "$file")
        m=$(_rust_grep_count '^\s*#\[cfg\(test\)\]' "$file")
        test_funcs=$((test_funcs + f))
        test_mods=$((test_mods + m))
    done < <(_rust_find_files "$dir")

    echo "test_functions=${test_funcs},test_modules=${test_mods}"
}

# =============================================================================
# SUMMARY
# =============================================================================

# NOTE: Each metric function independently calls _rust_find_files. For large
# projects, consider caching the file list externally and using xargs.

# rust_summary DIR
# Generate JSON project health overview
rust_summary() {
    local dir="${1:-.}"

    if ! rust_is_project "$dir"; then
        printf '{"error":"not a Rust project"}'
        return 0
    fi

    local cargo functions traits structs enums impls loc tests deps unsafe_info
    cargo=$(rust_parse_cargo "$dir")
    functions=$(rust_function_count "$dir")
    traits=$(rust_trait_count "$dir")
    structs=$(rust_struct_count "$dir")
    enums=$(rust_enum_count "$dir")
    impls=$(rust_impl_count "$dir")
    loc=$(rust_loc "$dir")
    tests=$(rust_test_coverage "$dir")
    deps=$(rust_dep_count "$dir")
    unsafe_info=$(rust_unsafe_count "$dir")

    local name version edition
    name=$(_rust_kv_value "$cargo" "name")
    version=$(_rust_kv_value "$cargo" "version")
    edition=$(_rust_kv_value "$cargo" "edition")

    local regular dev build
    regular=$(_rust_kv_value "$deps" "regular")
    dev=$(_rust_kv_value "$deps" "dev")
    build=$(_rust_kv_value "$deps" "build")

    local test_funcs test_mods
    test_funcs=$(_rust_kv_value "$tests" "test_functions")
    test_mods=$(_rust_kv_value "$tests" "test_modules")

    local unsafe_blocks unsafe_fns unsafe_impls
    unsafe_blocks=$(_rust_kv_value "$unsafe_info" "blocks")
    unsafe_fns=$(_rust_kv_value "$unsafe_info" "functions")
    unsafe_impls=$(_rust_kv_value "$unsafe_info" "impls")

    local file_count
    file_count=$(_rust_find_files "$dir" | wc -l)

    printf '{"name":"%s",' "$(_rust_escape_json "${name:-unknown}")"
    printf '"version":"%s",' "$(_rust_escape_json "${version:-0.0.0}")"
    printf '"edition":"%s",' "$(_rust_escape_json "${edition:-2021}")"
    printf '"files":%d,' "${file_count:-0}"
    printf '"functions":%d,' "${functions:-0}"
    printf '"traits":%d,' "${traits:-0}"
    printf '"structs":%d,' "${structs:-0}"
    printf '"enums":%d,' "${enums:-0}"
    printf '"impls":%d,' "${impls:-0}"
    printf '"loc":%d,' "${loc:-0}"
    printf '"unsafe":{"blocks":%d,"functions":%d,"impls":%d},' \
        "${unsafe_blocks:-0}" "${unsafe_fns:-0}" "${unsafe_impls:-0}"
    printf '"dependencies":{"regular":%d,"dev":%d,"build":%d},' \
        "${regular:-0}" "${dev:-0}" "${build:-0}"
    printf '"tests":{"functions":%d,"modules":%d}}' \
        "${test_funcs:-0}" "${test_mods:-0}"
}

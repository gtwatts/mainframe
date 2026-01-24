#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/go.sh - Go Project Analysis (No Runtime Required)
# =============================================================================
# Description: Static analysis of Go projects using pure bash. Extracts imports,
#              builds dependency graphs, detects circular dependencies, and
#              provides project health metrics without requiring the Go toolchain.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# LIMITATIONS (regex-based parsing, not AST):
#   - Cannot parse build constraint tags (//go:build, +build)
#   - Cannot detect conditional compilation or OS-specific files beyond naming
#   - Cannot resolve dot-imports (. "pkg") or blank imports (_ "pkg") semantics
#   - Multi-line block comments (/* */) are not stripped from LOC counts
#   - Cannot follow interface implementations across packages
#   - Cannot detect cgo imports or generated code
#   - Circular dependency detection is limited to direct A<->B cycles
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

[[ -n "${_MAINFRAME_GO_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GO_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _go_escape_json STRING
# Escape a string for safe JSON embedding
_go_escape_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

# _go_find_files DIR
# Find all .go files excluding vendor and hidden directories
_go_find_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    find "$dir" -type f -name "*.go" \
        ! -path "*/vendor/*" \
        ! -path "*/\.*" \
        ! -path "*/_[!_]*" \
        ! -name "*_test.go" 2>/dev/null
}

# _go_find_all_files DIR
# Find all .go files including tests
_go_find_all_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    find "$dir" -type f -name "*.go" \
        ! -path "*/vendor/*" \
        ! -path "*/\.*" 2>/dev/null
}

# _go_find_test_files DIR
# Find test files only
_go_find_test_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    find "$dir" -type f -name "*_test.go" \
        ! -path "*/vendor/*" 2>/dev/null
}

# =============================================================================
# PROJECT DETECTION
# =============================================================================

# go_is_project DIR
# Check if directory is a Go project (has go.mod)
go_is_project() {
    local dir="${1:-.}"
    [[ -f "${dir}/go.mod" ]]
}

# go_source_dir DIR
# Determine the main source directory
go_source_dir() {
    local dir="${1:-.}"

    # Check for cmd/ layout
    if [[ -d "${dir}/cmd" ]]; then
        echo "${dir}/cmd"
        return 0
    fi

    # Check for internal/ layout
    if [[ -d "${dir}/internal" ]]; then
        echo "${dir}"
        return 0
    fi

    # Default: project root
    if go_is_project "$dir"; then
        echo "$dir"
        return 0
    fi

    return 1
}

# =============================================================================
# IMPORT ANALYSIS
# =============================================================================

# go_file_imports FILE
# Extract import paths from a Go file (handles single and grouped imports)
# Output: one import path per line
go_file_imports() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local in_block=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip inline comments
        local clean="${line%%//*}"

        # Detect import block start
        if [[ "$clean" =~ ^[[:space:]]*import[[:space:]]*\( ]]; then
            in_block=1
            continue
        fi

        # Detect import block end
        if [[ $in_block -eq 1 && "$clean" =~ ^[[:space:]]*\) ]]; then
            in_block=0
            continue
        fi

        # Single-line import
        if [[ $in_block -eq 0 && "$clean" =~ ^[[:space:]]*import[[:space:]]+ ]]; then
            if [[ "$clean" =~ \"([^\"]+)\" ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
            continue
        fi

        # Inside import block
        if [[ $in_block -eq 1 ]]; then
            if [[ "$clean" =~ \"([^\"]+)\" ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
        fi
    done < "$file"
}

# go_import_frequency DIR
# List most-used packages across the project
# Output: "COUNT PACKAGE" sorted by frequency
go_import_frequency() {
    local dir="${1:-.}"
    local tmpfile
    tmpfile=$(mktemp)

    while IFS= read -r file; do
        go_file_imports "$file" >> "$tmpfile"
    done < <(_go_find_files "$dir")

    sort "$tmpfile" | uniq -c | sort -rn
    rm -f "$tmpfile"
}

# go_import_graph DIR
# Build file-to-imports mapping
# Output: "file:import1,import2,..."
go_import_graph() {
    local dir="${1:-.}"

    while IFS= read -r file; do
        local rel="${file#$dir/}"
        local imports
        imports=$(go_file_imports "$file" | tr '\n' ',' | sed 's/,$//')
        [[ -n "$imports" ]] && echo "${rel}:${imports}"
    done < <(_go_find_files "$dir")
}

# go_circular_deps DIR
# Detect circular dependencies between packages
# Output: "pkg_a <-> pkg_b" for each cycle found
go_circular_deps() {
    local dir="${1:-.}"
    local module
    module=$(go_module_info "$dir" | grep -oP 'module=\K[^,]+' 2>/dev/null)
    [[ -z "$module" ]] && return 1

    declare -A pkg_imports

    # Build package import map
    while IFS= read -r file; do
        local pkg_dir
        pkg_dir=$(dirname "${file#$dir/}")
        [[ "$pkg_dir" == "." ]] && pkg_dir=""

        while IFS= read -r imp; do
            # Only track internal imports
            if [[ "$imp" == "${module}/"* ]]; then
                local dep="${imp#$module/}"
                pkg_imports["$pkg_dir"]+=" $dep"
            fi
        done < <(go_file_imports "$file")
    done < <(_go_find_files "$dir")

    # Check for cycles (A imports B, B imports A)
    local found=0
    local -A reported
    for src in "${!pkg_imports[@]}"; do
        local -a dep_list
        read -ra dep_list <<< "${pkg_imports[$src]}"
        for dep in "${dep_list[@]}"; do
            if [[ -n "${pkg_imports[$dep]:-}" ]]; then
                local back_deps="${pkg_imports[$dep]}"
                if [[ " $back_deps " == *" $src "* ]]; then
                    local key
                    if [[ "$src" < "$dep" ]]; then
                        key="${src}|${dep}"
                    else
                        key="${dep}|${src}"
                    fi
                    if [[ -z "${reported[$key]:-}" ]]; then
                        echo "${src} <-> ${dep}"
                        reported["$key"]=1
                        found=1
                    fi
                fi
            fi
        done
    done

    return $((1 - found))
}

# =============================================================================
# MODULE INFO
# =============================================================================

# go_module_info DIR
# Parse go.mod for module name and Go version
# Output: "module=NAME,go_version=VERSION,require_count=N"
go_module_info() {
    local dir="${1:-.}"
    local mod_file="${dir}/go.mod"
    [[ -f "$mod_file" ]] || return 1

    local module="" go_version="" require_count=0
    local in_require=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^module[[:space:]]+(.+)$ ]]; then
            module="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^go[[:space:]]+(.+)$ ]]; then
            go_version="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^require[[:space:]]*\( ]]; then
            in_require=1
        elif [[ $in_require -eq 1 && "$line" =~ ^\) ]]; then
            in_require=0
        elif [[ $in_require -eq 1 && "$line" =~ ^[[:space:]]+[a-zA-Z] ]]; then
            ((require_count++))
        elif [[ "$line" =~ ^require[[:space:]]+[a-zA-Z] ]]; then
            ((require_count++))
        fi
    done < "$mod_file"

    echo "module=${module},go_version=${go_version},require_count=${require_count}"
}

# go_dep_count DIR
# Count direct and indirect dependencies
# Output: "direct=N,indirect=N"
go_dep_count() {
    local dir="${1:-.}"
    local mod_file="${dir}/go.mod"
    [[ -f "$mod_file" ]] || return 1

    local direct=0 indirect=0
    local in_require=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^require[[:space:]]*\( ]]; then
            in_require=1
            continue
        fi
        if [[ $in_require -eq 1 && "$line" =~ ^\) ]]; then
            in_require=0
            continue
        fi
        if [[ $in_require -eq 1 && "$line" =~ ^[[:space:]]+[a-zA-Z] ]]; then
            if [[ "$line" == *"// indirect"* ]]; then
                ((indirect++))
            else
                ((direct++))
            fi
        fi
        if [[ "$line" =~ ^require[[:space:]]+[a-zA-Z] ]]; then
            ((direct++))
        fi
    done < "$mod_file"

    echo "direct=${direct},indirect=${indirect}"
}

# =============================================================================
# CODE METRICS
# =============================================================================

# go_function_count DIR
# Count function definitions (including methods)
go_function_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local file_count
        file_count=$(grep -cE '^func\s+' "$file" 2>/dev/null || echo 0)
        ((count += file_count))
    done < <(_go_find_files "$dir")

    echo "$count"
}

# go_interface_count DIR
# Count interface definitions
go_interface_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local file_count
        file_count=$(grep -cE '^type\s+\w+\s+interface\s*\{' "$file" 2>/dev/null || echo 0)
        ((count += file_count))
    done < <(_go_find_files "$dir")

    echo "$count"
}

# go_struct_count DIR
# Count struct definitions
go_struct_count() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local file_count
        file_count=$(grep -cE '^type\s+\w+\s+struct\s*\{' "$file" 2>/dev/null || echo 0)
        ((count += file_count))
    done < <(_go_find_files "$dir")

    echo "$count"
}

# go_loc DIR
# Count lines of code (excluding blank lines, // comments, and /* */ blocks)
go_loc() {
    local dir="${1:-.}"
    local count=0

    while IFS= read -r file; do
        local file_count
        file_count=$(sed '/\/\*/,/\*\//d' "$file" 2>/dev/null | grep -cvE '^\s*$|^\s*//' || echo 0)
        ((count += file_count))
    done < <(_go_find_files "$dir")

    echo "$count"
}

# go_test_coverage DIR
# Count test files and test functions
# Output: "test_files=N,test_functions=N"
go_test_coverage() {
    local dir="${1:-.}"
    local test_files=0 test_funcs=0

    while IFS= read -r file; do
        ((test_files++))
        local funcs
        funcs=$(grep -cE '^func\s+Test' "$file" 2>/dev/null || echo 0)
        ((test_funcs += funcs))
    done < <(_go_find_test_files "$dir")

    echo "test_files=${test_files},test_functions=${test_funcs}"
}

# =============================================================================
# SUMMARY
# =============================================================================

# go_summary DIR
# Generate JSON project health overview
# NOTE: Each metric function independently calls _go_find_files. For large
# projects, consider caching the file list externally and using xargs.
go_summary() {
    local dir="${1:-.}"

    if ! go_is_project "$dir"; then
        printf '{"error":"not a Go project"}'
        return 0
    fi

    local info functions interfaces structs loc tests deps
    info=$(go_module_info "$dir")
    functions=$(go_function_count "$dir")
    interfaces=$(go_interface_count "$dir")
    structs=$(go_struct_count "$dir")
    loc=$(go_loc "$dir")
    tests=$(go_test_coverage "$dir")
    deps=$(go_dep_count "$dir")

    local module go_version require_count
    module=$(echo "$info" | grep -oP 'module=\K[^,]+')
    go_version=$(echo "$info" | grep -oP 'go_version=\K[^,]+')
    require_count=$(echo "$info" | grep -oP 'require_count=\K[0-9]+')

    local direct indirect
    direct=$(echo "$deps" | grep -oP 'direct=\K[0-9]+')
    indirect=$(echo "$deps" | grep -oP 'indirect=\K[0-9]+')

    local test_files test_functions
    test_files=$(echo "$tests" | grep -oP 'test_files=\K[0-9]+')
    test_functions=$(echo "$tests" | grep -oP 'test_functions=\K[0-9]+')

    local file_count
    file_count=$(_go_find_all_files "$dir" | wc -l)

    printf '{"module":"%s",' "$(_go_escape_json "${module:-unknown}")"
    printf '"go_version":"%s",' "$(_go_escape_json "${go_version:-unknown}")"
    printf '"files":%d,' "${file_count:-0}"
    printf '"functions":%d,' "${functions:-0}"
    printf '"interfaces":%d,' "${interfaces:-0}"
    printf '"structs":%d,' "${structs:-0}"
    printf '"loc":%d,' "${loc:-0}"
    printf '"dependencies":{"direct":%d,"indirect":%d},' "${direct:-0}" "${indirect:-0}"
    printf '"tests":{"files":%d,"functions":%d}}' "${test_files:-0}" "${test_functions:-0}"
}

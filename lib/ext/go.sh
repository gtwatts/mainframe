#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2086
# =============================================================================
# MAINFRAME/lib/ext/go.sh - Go Project Analysis Library for AI Coding Agents
# =============================================================================
# Description: Go project detection, dependency analysis, build verification,
#              test execution, and linting. Provides structured JSON output
#              via USOP pattern for machine parsing.
#
# Version: 1.0.0
# Requires: Bash 4.0+
# Dependencies: json.sh (auto-loaded)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GO_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GO_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Get library directory for sourcing dependencies
_GO_LIB_DIR="${BASH_SOURCE[0]%/*}"

# Lazy-load json.sh if json_object is not available
if ! declare -F json_object &>/dev/null; then
    if [[ -f "${_GO_LIB_DIR}/../json.sh" ]]; then
        source "${_GO_LIB_DIR}/../json.sh"
    fi
fi

# =============================================================================
# CONSTANTS
# =============================================================================

# Maximum output length for command output (prevents context bloat)
readonly _GO_MAX_OUTPUT_CHARS=4000

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if go CLI is available
_go_has_cli() {
    command -v go &>/dev/null
}

# Truncate string to max length with ellipsis
# Usage: _go_truncate "string" [max_chars]
_go_truncate() {
    local str="$1"
    local max="${2:-$_GO_MAX_OUTPUT_CHARS}"

    if [[ ${#str} -gt $max ]]; then
        printf '%s... [truncated %d chars]' "${str:0:$max}" "$((${#str} - max))"
    else
        printf '%s' "$str"
    fi
}

# Execute go command and capture output
# Usage: _go_exec result_var exit_code_var command [args...]
_go_exec() {
    local -n __ge_output=$1
    local -n __ge_exit=$2
    shift 2

    local stdout_file stderr_file
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/go_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/go_err.XXXXXX")

    go "$@" >"$stdout_file" 2>"$stderr_file"
    __ge_exit=$?

    # Combine stdout and stderr, truncate if needed
    local combined
    combined=$(<"$stdout_file")
    if [[ -s "$stderr_file" ]]; then
        combined+=$'\n'$(<"$stderr_file")
    fi
    __ge_output=$(_go_truncate "$combined")

    rm -f "$stdout_file" "$stderr_file"
}

# =============================================================================
# DETECTION & ENVIRONMENT
# =============================================================================

# @idempotent Detect if directory is a Go project
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"is_go":bool,"has_go_mod":bool,"has_go_sum":bool,"has_go_work":bool}}
#
# Detects if a directory contains a Go project by checking for
# go.mod, go.sum, go.work, or .go files.
#
# Usage: go_detect [directory]
# Example: go_detect /path/to/project
go_detect() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    local is_go="false"
    local has_go_mod="false"
    local has_go_sum="false"
    local has_go_work="false"
    local has_go_files="false"

    # Check for go.mod (primary indicator)
    if [[ -f "$dir/go.mod" ]]; then
        has_go_mod="true"
        is_go="true"
    fi

    # Check for go.sum
    if [[ -f "$dir/go.sum" ]]; then
        has_go_sum="true"
    fi

    # Check for go.work (workspace mode)
    if [[ -f "$dir/go.work" ]]; then
        has_go_work="true"
        is_go="true"
    fi

    # Check for any .go files
    if compgen -G "$dir/*.go" > /dev/null 2>&1 || \
       find "$dir" -maxdepth 3 -name "*.go" -type f 2>/dev/null | head -1 | grep -q .; then
        has_go_files="true"
        # Only mark as Go project if we have go files and go.mod
        [[ "$has_go_mod" == "true" ]] && is_go="true"
    fi

    local data
    json_object_v data \
        "is_go:bool=$is_go" \
        "has_go_mod:bool=$has_go_mod" \
        "has_go_sum:bool=$has_go_sum" \
        "has_go_work:bool=$has_go_work" \
        "has_go_files:bool=$has_go_files"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent Get Go version
# @return {"ok":true,"data":{"version":"1.21.0","goos":"linux","goarch":"amd64"}}
#
# Returns Go version and platform information.
#
# Usage: go_version
# Example: result=$(go_version)
go_version() {
    if ! _go_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=go not installed"
        return 0
    fi

    local version_output
    version_output=$(go version 2>/dev/null)

    # Parse version: "go version go1.21.0 linux/amd64"
    local version=""
    local goos=""
    local goarch=""

    if [[ "$version_output" =~ go([0-9]+\.[0-9]+\.?[0-9]*) ]]; then
        version="${BASH_REMATCH[1]}"
    fi

    if [[ "$version_output" =~ ([a-z]+)/([a-z0-9]+)$ ]]; then
        goos="${BASH_REMATCH[1]}"
        goarch="${BASH_REMATCH[2]}"
    fi

    local data
    json_object_v data \
        "version=$version" \
        "goos=$goos" \
        "goarch=$goarch"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent Get module name from go.mod
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"module":"github.com/user/project","go_version":"1.21"}}
#
# Parses go.mod to extract module name and Go version requirement.
#
# Usage: go_mod_name [directory]
# Example: go_mod_name /path/to/project
go_mod_name() {
    local dir="${1:-.}"
    local go_mod="$dir/go.mod"

    if [[ ! -f "$go_mod" ]]; then
        json_object \
            "ok:bool=false" \
            "error=go.mod not found" \
            "path=$dir"
        return 0
    fi

    local module_name=""
    local go_ver=""

    # Parse module name (first line starting with "module ")
    while IFS= read -r line; do
        if [[ "$line" =~ ^module[[:space:]]+([^[:space:]]+) ]]; then
            module_name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^go[[:space:]]+([0-9]+\.[0-9]+\.?[0-9]*) ]]; then
            go_ver="${BASH_REMATCH[1]}"
        fi
    done < "$go_mod"

    local data
    json_object_v data \
        "module=$module_name" \
        "go_version:string=$go_ver"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# DEPENDENCY ANALYSIS
# =============================================================================

# @idempotent List dependencies from go.mod
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"direct":["pkg@version"],"indirect":["pkg@version"],"total":N}}
#
# Parses go.mod to extract direct and indirect dependencies.
#
# Usage: go_dependencies [directory]
# Example: go_dependencies /path/to/project
go_dependencies() {
    local dir="${1:-.}"
    local go_mod="$dir/go.mod"

    if [[ ! -f "$go_mod" ]]; then
        json_object \
            "ok:bool=false" \
            "error=go.mod not found" \
            "path=$dir"
        return 0
    fi

    local -a direct_deps=()
    local -a indirect_deps=()
    local in_require_block=false

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*// ]] && continue

        # Check for require block start
        if [[ "$line" =~ ^require[[:space:]]*\( ]]; then
            in_require_block=true
            continue
        fi

        # Check for block end
        if [[ "$line" =~ ^\) ]]; then
            in_require_block=false
            continue
        fi

        # Parse single-line require
        if [[ "$line" =~ ^require[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local ver="${BASH_REMATCH[2]}"
            if [[ "$line" =~ //[[:space:]]*indirect ]]; then
                indirect_deps+=("${pkg}@${ver}")
            else
                direct_deps+=("${pkg}@${ver}")
            fi
            continue
        fi

        # Parse dependency inside require block
        if $in_require_block && [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local ver="${BASH_REMATCH[2]}"
            if [[ "$line" =~ //[[:space:]]*indirect ]]; then
                indirect_deps+=("${pkg}@${ver}")
            else
                direct_deps+=("${pkg}@${ver}")
            fi
        fi
    done < "$go_mod"

    local direct_json indirect_json
    direct_json=$(json_array "${direct_deps[@]}")
    indirect_json=$(json_array "${indirect_deps[@]}")

    local total=$((${#direct_deps[@]} + ${#indirect_deps[@]}))

    local data
    printf -v data '{"direct":%s,"indirect":%s,"direct_count":%d,"indirect_count":%d,"total":%d}' \
        "$direct_json" "$indirect_json" "${#direct_deps[@]}" "${#indirect_deps[@]}" "$total"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# PACKAGE ANALYSIS
# =============================================================================

# @idempotent List packages in project
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"packages":["./pkg1","./pkg2"],"count":N}}
#
# Lists all Go packages in the project using go list.
#
# Usage: go_packages [directory]
# Example: go_packages /path/to/project
go_packages() {
    local dir="${1:-.}"

    if ! _go_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=go not installed"
        return 0
    fi

    if [[ ! -f "$dir/go.mod" ]]; then
        json_object \
            "ok:bool=false" \
            "error=go.mod not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    output=$(cd "$dir" && go list ./... 2>&1)
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        json_object \
            "ok:bool=false" \
            "error=go list failed" \
            "exit_code:number=$exit_code" \
            "output=$(_go_truncate "$output")"
        return 0
    fi

    # Convert output to array
    local -a packages=()
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && packages+=("$pkg")
    done <<< "$output"

    local packages_json
    packages_json=$(json_array "${packages[@]}")

    local data
    printf -v data '{"packages":%s,"count":%d}' "$packages_json" "${#packages[@]}"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent Analyze imports for a file
# @param $1 - Go file path (required)
# @return {"ok":true,"data":{"imports":["fmt","net/http"],"std_lib":["fmt"],"external":["github.com/..."]}}
#
# Parses import statements from a Go source file.
#
# Usage: go_imports file.go
# Example: go_imports main.go
go_imports() {
    local file="$1"

    if [[ -z "$file" ]]; then
        json_object \
            "ok:bool=false" \
            "error=file path required"
        return 0
    fi

    if [[ ! -f "$file" ]]; then
        json_object \
            "ok:bool=false" \
            "error=file not found" \
            "file=$file"
        return 0
    fi

    local -a all_imports=()
    local -a std_lib=()
    local -a external=()
    local in_import_block=false

    while IFS= read -r line; do
        # Single-line import
        if [[ "$line" =~ ^import[[:space:]]+\"([^\"]+)\" ]]; then
            all_imports+=("${BASH_REMATCH[1]}")
            continue
        fi

        # Import block start
        if [[ "$line" =~ ^import[[:space:]]*\( ]]; then
            in_import_block=true
            continue
        fi

        # Import block end
        if [[ "$line" =~ ^\) ]]; then
            in_import_block=false
            continue
        fi

        # Parse import inside block (with optional alias)
        if $in_import_block && [[ "$line" =~ \"([^\"]+)\" ]]; then
            all_imports+=("${BASH_REMATCH[1]}")
        fi
    done < "$file"

    # Categorize imports: standard library vs external
    for imp in "${all_imports[@]}"; do
        # Standard library packages don't contain dots in the first path segment
        local first_segment="${imp%%/*}"
        if [[ ! "$first_segment" =~ \. ]]; then
            std_lib+=("$imp")
        else
            external+=("$imp")
        fi
    done

    local all_json std_json ext_json
    all_json=$(json_array "${all_imports[@]}")
    std_json=$(json_array "${std_lib[@]}")
    ext_json=$(json_array "${external[@]}")

    local data
    printf -v data '{"imports":%s,"std_lib":%s,"external":%s,"total":%d}' \
        "$all_json" "$std_json" "$ext_json" "${#all_imports[@]}"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# BUILD & TEST
# =============================================================================

# @pre go_detect returns is_go=true
# Check if project builds successfully
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"builds":bool,"exit_code":N,"output":"..."}}
#
# Runs go build to verify the project compiles without errors.
#
# Usage: go_build_check [directory]
# Example: go_build_check /path/to/project
go_build_check() {
    local dir="${1:-.}"

    if ! _go_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=go not installed"
        return 0
    fi

    if [[ ! -f "$dir/go.mod" ]]; then
        json_object \
            "ok:bool=false" \
            "error=go.mod not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    # Use -o /dev/null to avoid creating binary
    output=$(cd "$dir" && go build -o /dev/null ./... 2>&1)
    exit_code=$?

    local builds="true"
    [[ $exit_code -ne 0 ]] && builds="false"

    local data
    json_object_v data \
        "builds:bool=$builds" \
        "exit_code:number=$exit_code" \
        "output=$(_go_truncate "$output")"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @pre go_detect returns is_go=true
# Check if tests pass
# @param $1 - optional: directory path (default: current directory)
# @param $2 - optional: additional flags (e.g., "-v", "-race")
# @return {"ok":true,"data":{"passes":bool,"exit_code":N,"output":"..."}}
#
# Runs go test to verify all tests pass.
#
# Usage: go_test_check [directory] [flags]
# Example: go_test_check /path/to/project "-v"
go_test_check() {
    local dir="${1:-.}"
    local flags="${2:-}"

    if ! _go_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=go not installed"
        return 0
    fi

    if [[ ! -f "$dir/go.mod" ]]; then
        json_object \
            "ok:bool=false" \
            "error=go.mod not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    if [[ -n "$flags" ]]; then
        output=$(cd "$dir" && go test $flags ./... 2>&1)
    else
        output=$(cd "$dir" && go test ./... 2>&1)
    fi
    exit_code=$?

    local passes="true"
    [[ $exit_code -ne 0 ]] && passes="false"

    # Try to extract test stats from output
    local passed=0 failed=0 skipped=0
    if [[ "$output" =~ ok[[:space:]]+[^[:space:]]+[[:space:]]+([0-9.]+)s ]]; then
        # Count ok lines for passed packages
        passed=$(echo "$output" | grep -c "^ok" || true)
    fi
    if [[ "$output" =~ FAIL ]]; then
        failed=$(echo "$output" | grep -c "^FAIL" || true)
    fi
    if [[ "$output" =~ \[no\ test\ files\] ]]; then
        skipped=$(echo "$output" | grep -c '\[no test files\]' || true)
    fi

    local data
    printf -v data '{"passes":%s,"exit_code":%d,"passed_packages":%d,"failed_packages":%d,"skipped_packages":%d,"output":"%s"}' \
        "$passes" "$exit_code" "$passed" "$failed" "$skipped" "$(json_escape "$(_go_truncate "$output")")"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# LINTING
# =============================================================================

# @pre go_detect returns is_go=true
# Run linter (golint, staticcheck, or go vet as fallback)
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"tool":"staticcheck","clean":bool,"issues":N,"output":"..."}}
#
# Runs available Go linter. Tries staticcheck first, then golangci-lint,
# then golint, falls back to go vet.
#
# Usage: go_lint [directory]
# Example: go_lint /path/to/project
go_lint() {
    local dir="${1:-.}"

    if ! _go_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=go not installed"
        return 0
    fi

    if [[ ! -f "$dir/go.mod" ]]; then
        json_object \
            "ok:bool=false" \
            "error=go.mod not found" \
            "path=$dir"
        return 0
    fi

    local tool=""
    local output=""
    local exit_code=0

    # Try linters in order of preference
    if command -v staticcheck &>/dev/null; then
        tool="staticcheck"
        output=$(cd "$dir" && staticcheck ./... 2>&1)
        exit_code=$?
    elif command -v golangci-lint &>/dev/null; then
        tool="golangci-lint"
        output=$(cd "$dir" && golangci-lint run ./... 2>&1)
        exit_code=$?
    elif command -v golint &>/dev/null; then
        tool="golint"
        output=$(cd "$dir" && golint ./... 2>&1)
        exit_code=$?
        # golint returns 0 even with issues, check output
        [[ -n "$output" ]] && exit_code=1
    else
        # Fall back to go vet
        tool="go vet"
        output=$(cd "$dir" && go vet ./... 2>&1)
        exit_code=$?
    fi

    local clean="true"
    [[ $exit_code -ne 0 || -n "$output" ]] && clean="false"

    # Count issues (rough estimate based on newlines in output)
    local issues=0
    if [[ -n "$output" ]]; then
        issues=$(echo "$output" | grep -c ":" || true)
    fi

    local data
    json_object_v data \
        "tool=$tool" \
        "clean:bool=$clean" \
        "issues:number=$issues" \
        "exit_code:number=$exit_code" \
        "output=$(_go_truncate "$output")"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# AI AGENT HELPERS
# =============================================================================

# @idempotent Get project summary for AI context
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"module":"name","go_version":"1.21","packages":N,"deps":N}}
#
# Provides a comprehensive summary of a Go project for AI agent context.
#
# Usage: go_project_summary [directory]
# Example: go_project_summary /path/to/project
go_project_summary() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    # Get detection info
    local detect_result
    detect_result=$(go_detect "$dir")
    local is_go
    is_go=$(echo "$detect_result" | grep -o '"is_go":[^,}]*' | cut -d: -f2)

    if [[ "$is_go" != "true" ]]; then
        json_object \
            "ok:bool=false" \
            "error=not a Go project" \
            "path=$dir"
        return 0
    fi

    # Get module info
    local mod_result
    mod_result=$(go_mod_name "$dir")
    local module_name go_ver
    module_name=$(echo "$mod_result" | grep -o '"module":"[^"]*"' | cut -d'"' -f4)
    go_ver=$(echo "$mod_result" | grep -o '"go_version":"[^"]*"' | cut -d'"' -f4)

    # Get dependency count
    local deps_result
    deps_result=$(go_dependencies "$dir")
    local total_deps direct_deps
    total_deps=$(echo "$deps_result" | grep -o '"total":[0-9]*' | cut -d: -f2)
    direct_deps=$(echo "$deps_result" | grep -o '"direct_count":[0-9]*' | cut -d: -f2)

    # Get package count (if go is available)
    local pkg_count=0
    if _go_has_cli; then
        local pkg_result
        pkg_result=$(go_packages "$dir")
        pkg_count=$(echo "$pkg_result" | grep -o '"count":[0-9]*' | cut -d: -f2)
    fi

    # Check for common files/features
    local has_makefile="false"
    local has_dockerfile="false"
    local has_main="false"
    local has_tests="false"

    [[ -f "$dir/Makefile" || -f "$dir/makefile" ]] && has_makefile="true"
    [[ -f "$dir/Dockerfile" || -f "$dir/dockerfile" ]] && has_dockerfile="true"
    [[ -f "$dir/main.go" ]] && has_main="true"
    compgen -G "$dir/*_test.go" > /dev/null 2>&1 && has_tests="true"
    find "$dir" -maxdepth 3 -name "*_test.go" -type f 2>/dev/null | head -1 | grep -q . && has_tests="true"

    local data
    printf -v data '{"module":"%s","go_version":"%s","package_count":%d,"direct_deps":%d,"total_deps":%d,"has_makefile":%s,"has_dockerfile":%s,"has_main":%s,"has_tests":%s}' \
        "$module_name" "$go_ver" "${pkg_count:-0}" "${direct_deps:-0}" "${total_deps:-0}" \
        "$has_makefile" "$has_dockerfile" "$has_main" "$has_tests"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_GO_EXPORTS=(
    # Detection & Environment
    go_detect
    go_version
    go_mod_name
    # Dependency Analysis
    go_dependencies
    # Package Analysis
    go_packages
    go_imports
    # Build & Test
    go_build_check
    go_test_check
    # Linting
    go_lint
    # AI Agent Helpers
    go_project_summary
)

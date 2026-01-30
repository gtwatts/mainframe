#!/usr/bin/env bash
# shellcheck disable=SC2155
# =============================================================================
# MAINFRAME/lib/bun.sh - Bun.js Runtime Helper Library for AI Coding Agents
# =============================================================================
# Description: Bun.js runtime detection, package management, script execution,
#              workspace/monorepo support, and AI agent helpers. Provides
#              structured JSON output via USOP pattern for machine parsing.
#
# Version: 1.0.0
# Requires: Bash 4.0+
# Dependencies: json.sh (auto-loaded)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_BUN_LOADED:-}" ]] && return 0
readonly _MAINFRAME_BUN_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Get library directory for sourcing dependencies
_BUN_LIB_DIR="${BASH_SOURCE[0]%/*}"

# Lazy-load json.sh if json_object is not available
if ! declare -F json_object &>/dev/null; then
    if [[ -f "${_BUN_LIB_DIR}/json.sh" ]]; then
        source "${_BUN_LIB_DIR}/json.sh"
    fi
fi

# =============================================================================
# CONSTANTS
# =============================================================================

# Maximum output length for command output (prevents context bloat)
readonly _BUN_MAX_OUTPUT_CHARS=4000

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if bun CLI is available
_bun_has_cli() {
    command -v bun &>/dev/null
}

# Truncate string to max length with ellipsis
# Usage: _bun_truncate "string" [max_chars]
_bun_truncate() {
    local str="$1"
    local max="${2:-$_BUN_MAX_OUTPUT_CHARS}"

    if [[ ${#str} -gt $max ]]; then
        printf '%s... [truncated %d chars]' "${str:0:$max}" "$((${#str} - max))"
    else
        printf '%s' "$str"
    fi
}

# Execute bun command and capture output
# Usage: _bun_exec result_var exit_code_var command [args...]
_bun_exec() {
    local -n __be_output=$1
    local -n __be_exit=$2
    shift 2

    local stdout_file stderr_file
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/bun_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/bun_err.XXXXXX")

    bun "$@" >"$stdout_file" 2>"$stderr_file"
    __be_exit=$?

    # Combine stdout and stderr, truncate if needed
    local combined
    combined=$(<"$stdout_file")
    if [[ -s "$stderr_file" ]]; then
        combined+=$'\n'$(<"$stderr_file")
    fi
    __be_output=$(_bun_truncate "$combined")

    rm -f "$stdout_file" "$stderr_file"
}

# Parse version from bun --version output
# Usage: _bun_parse_version "1.1.0"
_bun_parse_version() {
    local version_str="$1"
    # Remove any leading 'v' or 'bun ' prefix and trailing whitespace
    version_str="${version_str#v}"
    version_str="${version_str#bun }"
    version_str="${version_str%% *}"
    printf '%s' "$version_str"
}

# =============================================================================
# DETECTION & ENVIRONMENT
# =============================================================================

# @idempotent Check if bun is installed
# @return {"ok":true,"data":{"installed":bool,"version":"x.y.z","path":"/path/to/bun"}}
#
# Detects if Bun.js runtime is installed and available in PATH.
# Returns installation status, version, and binary path.
#
# Usage: bun_detect
# Example: result=$(bun_detect)
bun_detect() {
    if ! _bun_has_cli; then
        json_object \
            "ok:bool=true" \
            "data:raw={\"installed\":false,\"version\":null,\"path\":null}"
        return 0
    fi

    local bun_path version
    bun_path=$(command -v bun)
    version=$(_bun_parse_version "$(bun --version 2>/dev/null)")

    local data
    json_object_v data \
        "installed:bool=true" \
        "version=$version" \
        "path=$bun_path"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent Get bun version info
# @return {"ok":true,"data":{"version":"1.1.0","revision":"abc123"}}
#
# Returns detailed version information for the installed Bun runtime.
#
# Usage: bun_version
# Example: result=$(bun_version)
bun_version() {
    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

    local version revision
    version=$(_bun_parse_version "$(bun --version 2>/dev/null)")

    # Try to get revision from bun --revision (may not exist in all versions)
    revision=$(bun --revision 2>/dev/null | head -1)
    [[ -z "$revision" ]] && revision="unknown"

    local data
    json_object_v data \
        "version=$version" \
        "revision=$revision"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @idempotent Check if current directory is a bun project
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"is_bun":bool,"has_lockfile":bool,"has_bunfig":bool}}
#
# Detects if a directory contains a Bun.js project by checking for
# bun.lockb (binary lockfile), bun.lock (text lockfile), or bunfig.toml.
#
# Usage: bun_is_project [directory]
# Example: bun_is_project /path/to/project
bun_is_project() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    local is_bun="false"
    local has_lockfile="false"
    local has_bunfig="false"
    local has_package_json="false"

    # Check for package.json (required for any JS project)
    [[ -f "$dir/package.json" ]] && has_package_json="true"

    # Check for bun lockfiles (binary or text format)
    if [[ -f "$dir/bun.lockb" ]] || [[ -f "$dir/bun.lock" ]]; then
        has_lockfile="true"
        is_bun="true"
    fi

    # Check for bunfig.toml configuration
    if [[ -f "$dir/bunfig.toml" ]]; then
        has_bunfig="true"
        is_bun="true"
    fi

    local data
    json_object_v data \
        "is_bun:bool=$is_bun" \
        "has_lockfile:bool=$has_lockfile" \
        "has_bunfig:bool=$has_bunfig" \
        "has_package_json:bool=$has_package_json"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# PACKAGE MANAGEMENT
# =============================================================================

# @pre bun_detect returns installed=true
# Install dependencies (equivalent to bun install)
# @param $1 - optional: specific package to install
# @param $2 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"packages_installed":N,"time_ms":N}}
#
# Runs bun install to install project dependencies. If a package name
# is provided, installs that specific package.
#
# Usage: bun_install [package] [directory]
# Example: bun_install
# Example: bun_install express /path/to/project
bun_install() {
    local package="${1:-}"
    local dir="${2:-.}"

    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    local start_ms end_ms duration_ms
    start_ms=$(date +%s%3N 2>/dev/null || echo "0")

    local output exit_code
    (
        cd "$dir" || exit 1
        if [[ -n "$package" ]]; then
            bun add "$package" 2>&1
        else
            bun install 2>&1
        fi
    )
    exit_code=$?
    output=$(_bun_truncate "$(
        cd "$dir" || exit 1
        if [[ -n "$package" ]]; then
            bun add "$package" 2>&1
        else
            bun install 2>&1
        fi
    )")

    end_ms=$(date +%s%3N 2>/dev/null || echo "0")
    duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    if [[ $exit_code -ne 0 ]]; then
        json_object \
            "ok:bool=false" \
            "error=install failed" \
            "exit_code:number=$exit_code" \
            "output=$output"
        return 0
    fi

    # Count installed packages from output (bun outputs package count)
    local pkg_count=0
    if [[ "$output" =~ ([0-9]+)[[:space:]]+packages? ]]; then
        pkg_count="${BASH_REMATCH[1]}"
    fi

    local data
    json_object_v data \
        "packages_installed:number=$pkg_count" \
        "time_ms:number=$duration_ms" \
        "output=$output"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# @pre bun_is_project returns is_bun=true
# Add a package
# @param $1 - package name (required)
# @param $2 - optional: --dev, --peer, --optional
# @param $3 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"package":"name","version":"x.y.z"}}
#
# Adds a package to the project. Supports dev, peer, and optional dependencies.
#
# Usage: bun_add package [--dev|--peer|--optional] [directory]
# Example: bun_add express
# Example: bun_add typescript --dev
bun_add() {
    local package="${1:-}"
    local flag="${2:-}"
    local dir="${3:-.}"

    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

    if [[ -z "$package" ]]; then
        json_object \
            "ok:bool=false" \
            "error=package name required"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    local add_args=("add" "$package")

    # Handle dependency type flags
    case "$flag" in
        --dev|-D)      add_args+=("--dev") ;;
        --peer)        add_args+=("--peer") ;;
        --optional)    add_args+=("--optional") ;;
    esac

    output=$(_bun_truncate "$(cd "$dir" && bun "${add_args[@]}" 2>&1)")
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        json_object \
            "ok:bool=false" \
            "error=add failed" \
            "package=$package" \
            "exit_code:number=$exit_code" \
            "output=$output"
        return 0
    fi

    # Try to extract version from output or package.json
    local version="unknown"
    if [[ -f "$dir/package.json" ]]; then
        # Look for package in dependencies or devDependencies
        local pkg_json
        pkg_json=$(<"$dir/package.json")
        if [[ "$pkg_json" =~ \"$package\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            version="${BASH_REMATCH[1]}"
        fi
    fi

    local data
    json_object_v data \
        "package=$package" \
        "version=$version" \
        "flag=$flag"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# Remove a package
# @param $1 - package name (required)
# @param $2 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"removed":"name"}}
#
# Removes a package from the project.
#
# Usage: bun_remove package [directory]
# Example: bun_remove lodash
bun_remove() {
    local package="${1:-}"
    local dir="${2:-.}"

    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

    if [[ -z "$package" ]]; then
        json_object \
            "ok:bool=false" \
            "error=package name required"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    local output exit_code
    output=$(_bun_truncate "$(cd "$dir" && bun remove "$package" 2>&1)")
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        json_object \
            "ok:bool=false" \
            "error=remove failed" \
            "package=$package" \
            "exit_code:number=$exit_code" \
            "output=$output"
        return 0
    fi

    local data
    json_object_v data \
        "removed=$package"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# List installed packages
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"dependencies":[...],"devDependencies":[...]}}
#
# Lists all installed packages from package.json.
#
# Usage: bun_list [directory]
# Example: bun_list /path/to/project
bun_list() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/package.json" ]]; then
        json_object \
            "ok:bool=false" \
            "error=package.json not found" \
            "path=$dir"
        return 0
    fi

    local pkg_json deps dev_deps
    pkg_json=$(<"$dir/package.json")

    # Extract dependencies as JSON arrays
    # Simple extraction - get keys from dependencies object
    local deps_array="[]"
    local dev_deps_array="[]"

    # Extract dependencies section
    local deps_section=""
    if [[ "$pkg_json" =~ \"dependencies\"[[:space:]]*:[[:space:]]*\{([^\}]*)\} ]]; then
        deps_section="${BASH_REMATCH[1]}"
    fi

    # Extract devDependencies section
    local dev_deps_section=""
    if [[ "$pkg_json" =~ \"devDependencies\"[[:space:]]*:[[:space:]]*\{([^\}]*)\} ]]; then
        dev_deps_section="${BASH_REMATCH[1]}"
    fi

    # Build arrays of package names
    local -a deps_list=()
    local -a dev_deps_list=()

    # Parse dependencies
    while [[ "$deps_section" =~ \"([^\"]+)\" ]]; do
        deps_list+=("${BASH_REMATCH[1]}")
        deps_section="${deps_section#*\"${BASH_REMATCH[1]}\"}"
        # Skip the version part
        deps_section="${deps_section#*:}"
        deps_section="${deps_section#*\"}"
        deps_section="${deps_section#*\"}"
    done

    # Parse devDependencies
    while [[ "$dev_deps_section" =~ \"([^\"]+)\" ]]; do
        dev_deps_list+=("${BASH_REMATCH[1]}")
        dev_deps_section="${dev_deps_section#*\"${BASH_REMATCH[1]}\"}"
        dev_deps_section="${dev_deps_section#*:}"
        dev_deps_section="${dev_deps_section#*\"}"
        dev_deps_section="${dev_deps_section#*\"}"
    done

    # Build JSON arrays
    deps_array=$(json_array "${deps_list[@]}")
    dev_deps_array=$(json_array "${dev_deps_list[@]}")

    local data
    printf -v data '{"dependencies":%s,"devDependencies":%s,"total":%d}' \
        "$deps_array" "$dev_deps_array" "$((${#deps_list[@]} + ${#dev_deps_list[@]}))"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# @pre bun_is_project
# Run a script from package.json
# @param $1 - script name (required)
# @param $@ - additional args
# @return {"ok":true,"data":{"script":"name","exit_code":N,"output":"..."}}
#
# Executes a script defined in package.json using bun run.
#
# Usage: bun_run script_name [args...]
# Example: bun_run dev
# Example: bun_run test --watch
bun_run() {
    local script="${1:-}"
    shift
    local args=("$@")

    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

    if [[ -z "$script" ]]; then
        json_object \
            "ok:bool=false" \
            "error=script name required"
        return 0
    fi

    local output exit_code
    local stdout_file stderr_file
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/bun_run_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/bun_run_err.XXXXXX")

    bun run "$script" "${args[@]}" >"$stdout_file" 2>"$stderr_file"
    exit_code=$?

    local combined
    combined=$(<"$stdout_file")
    if [[ -s "$stderr_file" ]]; then
        combined+=$'\n'$(<"$stderr_file")
    fi
    output=$(_bun_truncate "$combined")

    rm -f "$stdout_file" "$stderr_file"

    local success="true"
    [[ $exit_code -ne 0 ]] && success="false"

    local data
    json_object_v data \
        "script=$script" \
        "exit_code:number=$exit_code" \
        "output=$output"

    json_object \
        "ok:bool=$success" \
        "data:raw=$data"
}

# Execute a TypeScript/JavaScript file directly
# @param $1 - file path (required)
# @param $@ - args
# @return {"ok":true,"data":{"file":"path","exit_code":N,"output":"..."}}
#
# Runs a TypeScript or JavaScript file directly using Bun's runtime.
#
# Usage: bun_exec file.ts [args...]
# Example: bun_exec src/index.ts
bun_exec() {
    local file="${1:-}"
    shift
    local args=("$@")

    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

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

    local output exit_code
    local stdout_file stderr_file
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/bun_exec_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/bun_exec_err.XXXXXX")

    bun "$file" "${args[@]}" >"$stdout_file" 2>"$stderr_file"
    exit_code=$?

    local combined
    combined=$(<"$stdout_file")
    if [[ -s "$stderr_file" ]]; then
        combined+=$'\n'$(<"$stderr_file")
    fi
    output=$(_bun_truncate "$combined")

    rm -f "$stdout_file" "$stderr_file"

    local success="true"
    [[ $exit_code -ne 0 ]] && success="false"

    local data
    json_object_v data \
        "file=$file" \
        "exit_code:number=$exit_code" \
        "output=$output"

    json_object \
        "ok:bool=$success" \
        "data:raw=$data"
}

# Run bun test
# @param $@ - optional test file patterns
# @return {"ok":true,"data":{"passed":N,"failed":N,"skipped":N}}
#
# Runs Bun's built-in test runner with optional file patterns.
#
# Usage: bun_test [patterns...]
# Example: bun_test
# Example: bun_test src/**/*.test.ts
bun_test() {
    local patterns=("$@")

    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

    local output exit_code
    local stdout_file stderr_file
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/bun_test_out.XXXXXX")
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/bun_test_err.XXXXXX")

    if [[ ${#patterns[@]} -gt 0 ]]; then
        bun test "${patterns[@]}" >"$stdout_file" 2>"$stderr_file"
    else
        bun test >"$stdout_file" 2>"$stderr_file"
    fi
    exit_code=$?

    local combined
    combined=$(<"$stdout_file")
    if [[ -s "$stderr_file" ]]; then
        combined+=$'\n'$(<"$stderr_file")
    fi
    output=$(_bun_truncate "$combined")

    rm -f "$stdout_file" "$stderr_file"

    # Parse test results from output
    local passed=0 failed=0 skipped=0 total=0

    # Look for patterns like "X pass" "Y fail" "Z skip"
    if [[ "$output" =~ ([0-9]+)[[:space:]]+pass ]]; then
        passed="${BASH_REMATCH[1]}"
    fi
    if [[ "$output" =~ ([0-9]+)[[:space:]]+fail ]]; then
        failed="${BASH_REMATCH[1]}"
    fi
    if [[ "$output" =~ ([0-9]+)[[:space:]]+skip ]]; then
        skipped="${BASH_REMATCH[1]}"
    fi

    total=$((passed + failed + skipped))

    local success="true"
    [[ $exit_code -ne 0 ]] && success="false"

    local data
    json_object_v data \
        "passed:number=$passed" \
        "failed:number=$failed" \
        "skipped:number=$skipped" \
        "total:number=$total" \
        "exit_code:number=$exit_code" \
        "output=$output"

    json_object \
        "ok:bool=$success" \
        "data:raw=$data"
}

# =============================================================================
# WORKSPACE/MONOREPO SUPPORT
# =============================================================================

# @idempotent Detect workspace configuration
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"is_workspace":bool,"packages":["pkg1","pkg2"]}}
#
# Detects if the project uses Bun workspaces by checking package.json
# for a workspaces field.
#
# Usage: bun_workspace_detect [directory]
# Example: bun_workspace_detect /path/to/monorepo
bun_workspace_detect() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/package.json" ]]; then
        json_object \
            "ok:bool=true" \
            "data:raw={\"is_workspace\":false,\"packages\":[]}"
        return 0
    fi

    local pkg_json
    pkg_json=$(<"$dir/package.json")

    local is_workspace="false"
    local -a packages=()

    # Check for workspaces field
    if [[ "$pkg_json" =~ \"workspaces\" ]]; then
        is_workspace="true"

        # Extract workspace patterns
        if [[ "$pkg_json" =~ \"workspaces\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
            local ws_content="${BASH_REMATCH[1]}"

            # Parse workspace patterns
            while [[ "$ws_content" =~ \"([^\"]+)\" ]]; do
                local pattern="${BASH_REMATCH[1]}"
                ws_content="${ws_content#*\"$pattern\"}"

                # Expand glob patterns to find actual packages
                local glob_pattern="$dir/${pattern%/*}"
                if [[ -d "$glob_pattern" ]]; then
                    local pkg_dir
                    for pkg_dir in "$glob_pattern"/*/; do
                        if [[ -f "${pkg_dir}package.json" ]]; then
                            local pkg_name="${pkg_dir%/}"
                            pkg_name="${pkg_name##*/}"
                            packages+=("$pkg_name")
                        fi
                    done
                fi
            done
        fi
    fi

    local packages_json
    packages_json=$(json_array "${packages[@]}")

    local data
    printf -v data '{"is_workspace":%s,"packages":%s}' "$is_workspace" "$packages_json"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# Run command in specific workspace package
# @param $1 - package name (filter)
# @param $2 - command
# @param $3 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"package":"name","command":"cmd","output":"..."}}
#
# Runs a command in a specific workspace package using --filter.
#
# Usage: bun_workspace_run package command [directory]
# Example: bun_workspace_run @myorg/api "run build"
bun_workspace_run() {
    local package="${1:-}"
    local command="${2:-}"
    local dir="${3:-.}"

    if ! _bun_has_cli; then
        json_object \
            "ok:bool=false" \
            "error=bun not installed"
        return 0
    fi

    if [[ -z "$package" ]]; then
        json_object \
            "ok:bool=false" \
            "error=package name required"
        return 0
    fi

    if [[ -z "$command" ]]; then
        json_object \
            "ok:bool=false" \
            "error=command required"
        return 0
    fi

    local output exit_code
    output=$(_bun_truncate "$(cd "$dir" && bun --filter "$package" $command 2>&1)")
    exit_code=$?

    local success="true"
    [[ $exit_code -ne 0 ]] && success="false"

    local data
    json_object_v data \
        "package=$package" \
        "command=$command" \
        "exit_code:number=$exit_code" \
        "output=$output"

    json_object \
        "ok:bool=$success" \
        "data:raw=$data"
}

# List all workspace packages with paths
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"packages":[{"name":"pkg","path":"./packages/pkg"}]}}
#
# Lists all packages in a workspace with their names and relative paths.
#
# Usage: bun_workspace_list [directory]
# Example: bun_workspace_list /path/to/monorepo
bun_workspace_list() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/package.json" ]]; then
        json_object \
            "ok:bool=true" \
            "data:raw={\"packages\":[]}"
        return 0
    fi

    local pkg_json
    pkg_json=$(<"$dir/package.json")

    local -a pkg_entries=()

    # Check for workspaces field and extract patterns
    if [[ "$pkg_json" =~ \"workspaces\"[[:space:]]*:[[:space:]]*\[([^\]]*)\] ]]; then
        local ws_content="${BASH_REMATCH[1]}"

        # Parse workspace patterns
        while [[ "$ws_content" =~ \"([^\"]+)\" ]]; do
            local pattern="${BASH_REMATCH[1]}"
            ws_content="${ws_content#*\"$pattern\"}"

            # Expand glob patterns
            local base_dir="${pattern%/*}"
            local search_dir="$dir/$base_dir"

            if [[ -d "$search_dir" ]]; then
                local pkg_dir
                for pkg_dir in "$search_dir"/*/; do
                    if [[ -f "${pkg_dir}package.json" ]]; then
                        local pkg_path="${pkg_dir%/}"
                        local rel_path="${pkg_path#$dir/}"

                        # Read package name from package.json
                        local inner_pkg_json
                        inner_pkg_json=$(<"${pkg_dir}package.json")
                        local pkg_name=""
                        if [[ "$inner_pkg_json" =~ \"name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                            pkg_name="${BASH_REMATCH[1]}"
                        else
                            pkg_name="${pkg_path##*/}"
                        fi

                        # Build JSON entry
                        local entry
                        json_object_v entry \
                            "name=$pkg_name" \
                            "path=$rel_path"
                        pkg_entries+=("$entry")
                    fi
                done
            fi
        done
    fi

    # Build packages array
    local packages_json="["
    local first=true
    for entry in "${pkg_entries[@]}"; do
        $first || packages_json+=","
        first=false
        packages_json+="$entry"
    done
    packages_json+="]"

    local data
    printf -v data '{"packages":%s}' "$packages_json"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# AI AGENT HELPERS
# =============================================================================

# @idempotent Get project summary for AI context
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"name":"proj","type":"app|lib","scripts":[...],"deps_count":N}}
#
# Provides a comprehensive summary of a Bun project for AI agent context.
# Includes project name, type, available scripts, and dependency counts.
#
# Usage: bun_project_summary [directory]
# Example: bun_project_summary /path/to/project
bun_project_summary() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        json_object \
            "ok:bool=false" \
            "error=directory not found" \
            "path=$dir"
        return 0
    fi

    if [[ ! -f "$dir/package.json" ]]; then
        json_object \
            "ok:bool=false" \
            "error=package.json not found" \
            "path=$dir"
        return 0
    fi

    local pkg_json
    pkg_json=$(<"$dir/package.json")

    # Extract project name
    local name="unknown"
    if [[ "$pkg_json" =~ \"name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    fi

    # Determine project type (app vs lib)
    local type="app"
    if [[ "$pkg_json" =~ \"main\" ]] || [[ "$pkg_json" =~ \"exports\" ]]; then
        type="lib"
    fi
    if [[ "$pkg_json" =~ \"bin\" ]]; then
        type="cli"
    fi

    # Extract scripts
    local -a scripts_list=()
    if [[ "$pkg_json" =~ \"scripts\"[[:space:]]*:[[:space:]]*\{([^\}]*)\} ]]; then
        local scripts_section="${BASH_REMATCH[1]}"
        while [[ "$scripts_section" =~ \"([^\"]+)\"[[:space:]]*: ]]; do
            scripts_list+=("${BASH_REMATCH[1]}")
            scripts_section="${scripts_section#*\"${BASH_REMATCH[1]}\"}"
            scripts_section="${scripts_section#*:}"
            scripts_section="${scripts_section#*\"}"
            scripts_section="${scripts_section#*\"}"
        done
    fi

    # Count dependencies
    local deps_count=0 dev_deps_count=0

    if [[ "$pkg_json" =~ \"dependencies\"[[:space:]]*:[[:space:]]*\{([^\}]*)\} ]]; then
        local deps_section="${BASH_REMATCH[1]}"
        while [[ "$deps_section" =~ \"[^\"]+\" ]]; do
            ((deps_count++))
            deps_section="${deps_section#*\"}"
            deps_section="${deps_section#*\"}"
        done
        deps_count=$((deps_count / 2))  # Each dep has key and value
    fi

    if [[ "$pkg_json" =~ \"devDependencies\"[[:space:]]*:[[:space:]]*\{([^\}]*)\} ]]; then
        local dev_section="${BASH_REMATCH[1]}"
        while [[ "$dev_section" =~ \"[^\"]+\" ]]; do
            ((dev_deps_count++))
            dev_section="${dev_section#*\"}"
            dev_section="${dev_section#*\"}"
        done
        dev_deps_count=$((dev_deps_count / 2))
    fi

    # Check for Bun-specific features
    local is_bun_project="false"
    [[ -f "$dir/bun.lockb" ]] || [[ -f "$dir/bun.lock" ]] || [[ -f "$dir/bunfig.toml" ]] && is_bun_project="true"

    local scripts_json
    scripts_json=$(json_array "${scripts_list[@]}")

    local data
    printf -v data '{"name":"%s","type":"%s","is_bun_project":%s,"scripts":%s,"deps_count":%d,"dev_deps_count":%d}' \
        "$name" "$type" "$is_bun_project" "$scripts_json" "$deps_count" "$dev_deps_count"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# Parse bunfig.toml if present
# @param $1 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"config":{...}}} or {"ok":true,"data":{"config":null}}
#
# Reads and parses bunfig.toml configuration file if present.
# Returns null config if file doesn't exist.
#
# Usage: bun_config [directory]
# Example: bun_config /path/to/project
bun_config() {
    local dir="${1:-.}"
    local config_file="$dir/bunfig.toml"

    if [[ ! -f "$config_file" ]]; then
        json_object \
            "ok:bool=true" \
            "data:raw={\"config\":null,\"exists\":false}"
        return 0
    fi

    # Read bunfig.toml and parse basic key-value pairs
    local config_content
    config_content=$(<"$config_file")

    # Build a simple JSON representation of common bunfig options
    local -A config_map
    local current_section=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Section headers
        if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key = value pairs
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # Remove quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            if [[ -n "$current_section" ]]; then
                config_map["${current_section}.${key}"]="$value"
            else
                config_map["$key"]="$value"
            fi
        fi
    done <<< "$config_content"

    # Build JSON config object
    local config_json="{"
    local first=true
    for key in "${!config_map[@]}"; do
        $first || config_json+=","
        first=false
        local escaped_value
        escaped_value=$(json_escape "${config_map[$key]}")
        config_json+="\"$key\":\"$escaped_value\""
    done
    config_json+="}"

    local data
    printf -v data '{"config":%s,"exists":true}' "$config_json"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# Get recommended commands for common tasks
# @param $1 - task type: "dev", "build", "test", "lint", "format"
# @param $2 - optional: directory path (default: current directory)
# @return {"ok":true,"data":{"task":"dev","command":"bun run dev","alternatives":[...]}}
#
# Suggests the best command for a given task based on available scripts
# and project configuration. Provides alternatives when applicable.
#
# Usage: bun_suggest_command task [directory]
# Example: bun_suggest_command dev
# Example: bun_suggest_command build /path/to/project
bun_suggest_command() {
    local task="${1:-}"
    local dir="${2:-.}"

    if [[ -z "$task" ]]; then
        json_object \
            "ok:bool=false" \
            "error=task type required" \
            "valid_tasks=dev,build,test,lint,format,start,install"
        return 0
    fi

    if [[ ! -f "$dir/package.json" ]]; then
        json_object \
            "ok:bool=false" \
            "error=package.json not found" \
            "path=$dir"
        return 0
    fi

    local pkg_json
    pkg_json=$(<"$dir/package.json")

    local command=""
    local -a alternatives=()

    # Check which scripts are available
    local has_script=""
    _check_script() {
        [[ "$pkg_json" =~ \"$1\"[[:space:]]*: ]]
    }

    case "$task" in
        dev)
            if _check_script "dev"; then
                command="bun run dev"
            elif _check_script "start:dev"; then
                command="bun run start:dev"
            elif _check_script "serve"; then
                command="bun run serve"
            elif _check_script "start"; then
                command="bun run start"
                alternatives+=("bun --hot src/index.ts")
            else
                command="bun --hot src/index.ts"
                alternatives+=("bun run src/index.ts")
            fi
            ;;
        build)
            if _check_script "build"; then
                command="bun run build"
            elif _check_script "compile"; then
                command="bun run compile"
            else
                command="bun build src/index.ts --outdir dist"
            fi
            ;;
        test)
            if _check_script "test"; then
                command="bun run test"
            else
                command="bun test"
            fi
            alternatives+=("bun test --watch")
            ;;
        lint)
            if _check_script "lint"; then
                command="bun run lint"
            elif _check_script "check"; then
                command="bun run check"
            else
                command="bunx eslint ."
                alternatives+=("bunx biome lint .")
            fi
            ;;
        format)
            if _check_script "format"; then
                command="bun run format"
            elif _check_script "fmt"; then
                command="bun run fmt"
            else
                command="bunx prettier --write ."
                alternatives+=("bunx biome format --write .")
            fi
            ;;
        start)
            if _check_script "start"; then
                command="bun run start"
            elif _check_script "serve"; then
                command="bun run serve"
            else
                command="bun src/index.ts"
            fi
            ;;
        install)
            command="bun install"
            alternatives+=("bun install --frozen-lockfile")
            ;;
        *)
            json_object \
                "ok:bool=false" \
                "error=unknown task type" \
                "task=$task" \
                "valid_tasks=dev,build,test,lint,format,start,install"
            return 0
            ;;
    esac

    local alternatives_json
    alternatives_json=$(json_array "${alternatives[@]}")

    local data
    json_object_v data \
        "task=$task" \
        "command=$command" \
        "alternatives:raw=$alternatives_json"

    json_object \
        "ok:bool=true" \
        "data:raw=$data"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# List of public functions for documentation
_BUN_EXPORTS=(
    # Detection & Environment
    bun_detect
    bun_version
    bun_is_project
    # Package Management
    bun_install
    bun_add
    bun_remove
    bun_list
    # Script Execution
    bun_run
    bun_exec
    bun_test
    # Workspace/Monorepo Support
    bun_workspace_detect
    bun_workspace_run
    bun_workspace_list
    # AI Agent Helpers
    bun_project_summary
    bun_config
    bun_suggest_command
)

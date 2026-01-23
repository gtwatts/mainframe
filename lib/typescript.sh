#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/typescript.sh - TypeScript Analysis Library
# =============================================================================
# Description: Pure bash TypeScript project analysis - import graphs, API diffs,
#              bundle size impact. Zero dependencies (grep/awk/find based).
# =============================================================================
# LIMITATIONS (regex-based parsing, not AST):
#   - Cannot resolve dynamic imports: import('./module')
#   - Cannot handle aliased paths without tsconfig.json resolution
#   - May false-positive on imports inside comments or string literals
#   - Cannot parse complex generics spanning multiple lines
#   - Does not handle declaration merging in .d.ts files
#   - Template literal imports are not detected
# For higher accuracy, use --tsc flag where supported (requires tsc installed)
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TS_LOADED=1

# =============================================================================
# PROJECT DETECTION
# =============================================================================

# Check if current directory is a TypeScript project
# Returns: 0 if TS project, 1 otherwise
ts_is_project() {
    local dir="${1:-.}"
    [[ -f "$dir/tsconfig.json" ]] && return 0
    # Check for .ts files (not .d.ts only)
    local ts_files
    ts_files=$(find "$dir" -maxdepth 3 -name "*.ts" -not -name "*.d.ts" \
        -not -path "*/node_modules/*" 2>/dev/null | head -1)
    [[ -n "$ts_files" ]]
}

# Get the source directory for a TS project
# Checks tsconfig.json rootDir, then common patterns
ts_source_dir() {
    local dir="${1:-.}"
    if [[ -f "$dir/tsconfig.json" ]]; then
        local root_dir
        root_dir=$(grep -o '"rootDir"[[:space:]]*:[[:space:]]*"[^"]*"' \
            "$dir/tsconfig.json" 2>/dev/null | head -1 | \
            sed 's/.*"rootDir"[[:space:]]*:[[:space:]]*"//;s/"//')
        [[ -n "$root_dir" ]] && printf '%s\n' "$dir/$root_dir" && return 0
    fi
    # Common source directories
    for src in "$dir/src" "$dir/lib" "$dir/source" "$dir"; do
        if [[ -d "$src" ]]; then
            printf '%s\n' "$src"
            return 0
        fi
    done
    printf '%s\n' "$dir"
}

# =============================================================================
# TYPEMINER - Import Graph Analysis
# =============================================================================

# Extract imports from a TypeScript file
# Output: one import path per line
ts_file_imports() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    # Match: import ... from 'module'
    # Match: import 'module' (side-effect)
    # Match: require('module')
    # Skip lines that look like comments
    grep -E "^[^/]*import\s|^[^/]*require\(" "$file" 2>/dev/null | \
        grep -oE "(from\s+['\"][^'\"]+['\"]|import\s+['\"][^'\"]+['\"]|require\(\s*['\"][^'\"]+['\"])" | \
        sed "s/from[[:space:]]*['\"]//;s/import[[:space:]]*['\"]//;s/require([[:space:]]*['\"]//;s/['\"].*$//" | \
        sort -u
}

# Count how often each module is imported across the project
# Output: count module (sorted by frequency, descending)
ts_import_frequency() {
    local dir="${1:-.}"
    local threshold="${2:-0}"

    ts_is_project "$dir" || { printf 'Not a TypeScript project\n' >&2; return 1; }

    find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | \
        grep -v "node_modules" | \
        grep -v "\.d\.ts$" | \
        while IFS= read -r file; do
            ts_file_imports "$file"
        done | \
        sort | uniq -c | sort -rn | \
        while read -r count module; do
            if [[ $count -gt $threshold ]]; then
                printf '%d\t%s\n' "$count" "$module"
            fi
        done
}

# Build an import dependency graph
# Output: source_file -> imported_module (one edge per line)
ts_import_graph() {
    local dir="${1:-.}"

    ts_is_project "$dir" || { printf 'Not a TypeScript project\n' >&2; return 1; }

    find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | \
        grep -v "node_modules" | \
        grep -v "\.d\.ts$" | \
        sort | \
        while IFS= read -r file; do
            local rel_file="${file#$dir/}"
            ts_file_imports "$file" | while IFS= read -r import; do
                printf '%s -> %s\n' "$rel_file" "$import"
            done
        done
}

# Detect circular dependencies in TypeScript imports
# Output: circular chains (file1 -> file2 -> file1)
ts_circular_deps() {
    local dir="${1:-.}"
    local max_depth="${2:-10}"

    ts_is_project "$dir" || { printf 'Not a TypeScript project\n' >&2; return 1; }

    # Build adjacency list
    local -A deps
    local -a files

    while IFS= read -r line; do
        local src="${line%% -> *}"
        local dst="${line##* -> }"
        # Only track relative imports (local files)
        if [[ "$dst" == ./* || "$dst" == ../* ]]; then
            deps["$src"]+="$dst "
            files+=("$src")
        fi
    done < <(ts_import_graph "$dir")

    # DFS for cycles
    local -A visited
    local -A in_stack
    local -a path

    _ts_dfs_cycle() {
        local node="$1"
        local depth="$2"

        [[ $depth -gt $max_depth ]] && return
        [[ -n "${in_stack[$node]:-}" ]] && {
            # Found cycle - print path from node to node
            local cycle_start=0
            local i
            for i in "${!path[@]}"; do
                if [[ "${path[$i]}" == "$node" ]]; then
                    cycle_start=$i
                    break
                fi
            done
            local result=""
            for ((i=cycle_start; i<${#path[@]}; i++)); do
                result+="${path[$i]} -> "
            done
            result+="$node"
            printf '%s\n' "$result"
            return
        }

        [[ -n "${visited[$node]:-}" ]] && return

        visited["$node"]=1
        in_stack["$node"]=1
        path+=("$node")

        local dep
        for dep in ${deps[$node]:-}; do
            # Resolve relative path
            local resolved
            resolved=$(cd "$(dirname "$dir/$node")" 2>/dev/null && \
                realpath --relative-to="$dir" "$dep.ts" 2>/dev/null || \
                printf '%s\n' "$dep")
            _ts_dfs_cycle "$resolved" $((depth + 1))
        done

        unset 'path[${#path[@]}-1]'
        unset 'in_stack[$node]'
    }

    # Get unique files
    local -A unique_files
    local f
    for f in "${files[@]}"; do
        unique_files["$f"]=1
    done

    for f in "${!unique_files[@]}"; do
        visited=()
        in_stack=()
        path=()
        _ts_dfs_cycle "$f" 0
    done | sort -u
}

# Find type-only imports that may pull in runtime code
# Output: file:line import (imports that should use 'import type')
ts_type_only_imports() {
    local dir="${1:-.}"

    ts_is_project "$dir" || { printf 'Not a TypeScript project\n' >&2; return 1; }

    find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | \
        grep -v "node_modules" | \
        grep -v "\.d\.ts$" | \
        while IFS= read -r file; do
            local rel_file="${file#$dir/}"
            # Find imports that import types but don't use 'import type'
            grep -n "^import " "$file" 2>/dev/null | \
                grep -v "import type " | \
                while IFS=: read -r line_num content; do
                    # Extract imported names
                    local names
                    names=$(printf '%s' "$content" | \
                        grep -oE '\{[^}]+\}' | tr -d '{}' | tr ',' '\n' | \
                        sed 's/[[:space:]]//g;s/ as .*//')
                    # Check if any imported name is only used as a type
                    local name
                    for name in $names; do
                        [[ -z "$name" ]] && continue
                        # Count usages excluding the import line and type annotations
                        local usage_count
                        usage_count=$(grep -c "\b$name\b" "$file" 2>/dev/null || echo 0)
                        local type_usage
                        type_usage=$(grep -cE ":\s*$name\b|<$name>|as\s+$name\b" "$file" 2>/dev/null || echo 0)
                        # If all usages are type-only (import + type annotations)
                        if [[ $usage_count -le $((type_usage + 1)) && $usage_count -gt 1 ]]; then
                            printf '%s:%d\t%s (type-only, consider: import type)\n' \
                                "$rel_file" "$line_num" "$name"
                        fi
                    done
                done
        done
}

# Calculate import depth (longest chain from entry point)
ts_import_depth() {
    local file="${1:-}"
    local dir="${2:-.}"
    local max_depth="${3:-20}"

    [[ -z "$file" ]] && { printf 'Usage: ts_import_depth <file> [dir]\n' >&2; return 1; }

    local -A visited
    local depth=0

    _ts_depth_walk() {
        local current="$1"
        local current_depth="$2"

        [[ $current_depth -gt $max_depth ]] && return
        [[ -n "${visited[$current]:-}" ]] && return
        visited["$current"]=1

        [[ $current_depth -gt $depth ]] && depth=$current_depth

        ts_file_imports "$dir/$current" | while IFS= read -r import; do
            if [[ "$import" == ./* || "$import" == ../* ]]; then
                local resolved
                resolved=$(cd "$(dirname "$dir/$current")" 2>/dev/null && \
                    realpath --relative-to="$dir" "$import.ts" 2>/dev/null || \
                    printf '%s\n' "$import")
                _ts_depth_walk "$resolved" $((current_depth + 1))
            fi
        done
    }

    _ts_depth_walk "$file" 0
    printf '%d\n' "$depth"
}

# =============================================================================
# TYPEDIFF - API Breaking Change Detection
# =============================================================================

# Extract public API surface from a .d.ts file or TypeScript file
# Output: sorted list of exported declarations
ts_api_extract() {
    local file="$1"
    [[ -f "$file" ]] || { printf 'File not found: %s\n' "$file" >&2; return 1; }

    grep -E "^export\s+(declare\s+)?(function|class|interface|type|const|let|var|enum|namespace|abstract)" \
        "$file" 2>/dev/null | \
        sed 's/^export[[:space:]]*declare[[:space:]]*//;s/^export[[:space:]]*//' | \
        # Normalize whitespace
        sed 's/[[:space:]]\+/ /g' | \
        sort
}

# Extract all exported names (just the identifiers)
ts_api_names() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    ts_api_extract "$file" | \
        sed -E 's/^(function|class|interface|type|const|let|var|enum|namespace|abstract class)[[:space:]]+//;s/[<(:{[:space:]].*//' | \
        sort -u
}

# Compare two API surfaces and show differences
# Output: +added, -removed, ~changed lines
ts_api_diff() {
    local old_file="$1"
    local new_file="$2"

    [[ -f "$old_file" ]] || { printf 'Old file not found: %s\n' "$old_file" >&2; return 1; }
    [[ -f "$new_file" ]] || { printf 'New file not found: %s\n' "$new_file" >&2; return 1; }

    local old_api new_api
    old_api=$(ts_api_extract "$old_file")
    new_api=$(ts_api_extract "$new_file")

    # Find additions, removals, and changes
    diff <(printf '%s\n' "$old_api") <(printf '%s\n' "$new_api") 2>/dev/null | \
        while IFS= read -r line; do
            case "$line" in
                "< "*) printf -- '-%s\n' "${line:2}" ;;
                "> "*) printf '+%s\n' "${line:2}" ;;
            esac
        done
}

# Detect breaking changes between two TypeScript API files
# Output: list of breaking changes with explanations
ts_breaking_changes() {
    local old_file="$1"
    local new_file="$2"

    [[ -f "$old_file" ]] || { printf 'Old file not found: %s\n' "$old_file" >&2; return 1; }
    [[ -f "$new_file" ]] || { printf 'New file not found: %s\n' "$new_file" >&2; return 1; }

    local breaking=0

    # Check for removed exports
    local old_names new_names
    old_names=$(ts_api_names "$old_file")
    new_names=$(ts_api_names "$new_file")

    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if ! printf '%s\n' "$new_names" | grep -qx "$name"; then
            printf 'BREAKING: Removed export: %s\n' "$name"
            breaking=1
        fi
    done <<< "$old_names"

    # Check for signature changes in remaining exports
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        # Only check names that exist in both
        if printf '%s\n' "$new_names" | grep -qx "$name"; then
            local old_sig new_sig
            old_sig=$(ts_api_extract "$old_file" | grep -E "(function|class|const|let|var)[[:space:]]+$name\b" | head -1)
            new_sig=$(ts_api_extract "$new_file" | grep -E "(function|class|const|let|var)[[:space:]]+$name\b" | head -1)
            if [[ -n "$old_sig" && -n "$new_sig" && "$old_sig" != "$new_sig" ]]; then
                # Check if parameters changed (potential break)
                local old_params new_params
                old_params=$(printf '%s' "$old_sig" | grep -oE '\([^)]*\)')
                new_params=$(printf '%s' "$new_sig" | grep -oE '\([^)]*\)')
                if [[ "$old_params" != "$new_params" ]]; then
                    printf 'BREAKING: Signature changed: %s\n' "$name"
                    printf '  old: %s\n' "$old_sig"
                    printf '  new: %s\n' "$new_sig"
                    breaking=1
                fi
            fi
        fi
    done <<< "$old_names"

    # Check for type -> interface or vice versa (breaking for some consumers)
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        local old_kind new_kind
        old_kind=$(ts_api_extract "$old_file" | grep -oE "^(type|interface|class|enum)[[:space:]]+$name\b" | head -1 | cut -d' ' -f1)
        new_kind=$(ts_api_extract "$new_file" | grep -oE "^(type|interface|class|enum)[[:space:]]+$name\b" | head -1 | cut -d' ' -f1)
        if [[ -n "$old_kind" && -n "$new_kind" && "$old_kind" != "$new_kind" ]]; then
            printf 'BREAKING: Kind changed: %s (%s -> %s)\n' "$name" "$old_kind" "$new_kind"
            breaking=1
        fi
    done <<< "$old_names"

    [[ $breaking -eq 0 ]] && printf 'No breaking changes detected\n'
    return $breaking
}

# Generate a summary of API changes suitable for changelogs
ts_api_summary() {
    local old_file="$1"
    local new_file="$2"

    [[ -f "$old_file" ]] || return 1
    [[ -f "$new_file" ]] || return 1

    local old_names new_names
    old_names=$(ts_api_names "$old_file")
    new_names=$(ts_api_names "$new_file")

    local added=0 removed=0 changed=0

    # Count additions
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        printf '%s\n' "$old_names" | grep -qx "$name" || ((added++))
    done <<< "$new_names"

    # Count removals
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        printf '%s\n' "$new_names" | grep -qx "$name" || ((removed++))
    done <<< "$old_names"

    # Count changes
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if printf '%s\n' "$new_names" | grep -qx "$name"; then
            local old_sig new_sig
            old_sig=$(ts_api_extract "$old_file" | grep "[[:space:]]$name\b" | head -1)
            new_sig=$(ts_api_extract "$new_file" | grep "[[:space:]]$name\b" | head -1)
            [[ "$old_sig" != "$new_sig" && -n "$old_sig" && -n "$new_sig" ]] && ((changed++))
        fi
    done <<< "$old_names"

    printf 'added=%d removed=%d changed=%d\n' "$added" "$removed" "$changed"

    # Suggest semver bump
    if [[ $removed -gt 0 ]]; then
        printf 'semver=major (breaking: %d removed exports)\n' "$removed"
    elif [[ $changed -gt 0 ]]; then
        printf 'semver=minor (non-breaking changes detected)\n'
    elif [[ $added -gt 0 ]]; then
        printf 'semver=minor (new exports added)\n'
    else
        printf 'semver=patch (no API changes)\n'
    fi
}

# =============================================================================
# IMPORTCOST - Bundle Size Impact Analysis
# =============================================================================

# Calculate the disk size of a node_modules package
# Output: size in bytes (or human-readable with -h flag)
ts_import_cost() {
    local module="$1"
    local dir="${2:-.}"
    local human="${3:-}"

    [[ -z "$module" ]] && { printf 'Usage: ts_import_cost <module> [dir] [-h]\n' >&2; return 1; }

    local mod_path="$dir/node_modules/$module"
    [[ -d "$mod_path" ]] || { printf '0\n'; return 1; }

    if [[ "$human" == "-h" ]]; then
        du -sh "$mod_path" 2>/dev/null | cut -f1
    else
        du -sb "$mod_path" 2>/dev/null | cut -f1
    fi
}

# Calculate the JS-only size (actual bundle impact)
ts_import_cost_js() {
    local module="$1"
    local dir="${2:-.}"

    [[ -z "$module" ]] && return 1

    local mod_path="$dir/node_modules/$module"
    [[ -d "$mod_path" ]] || { printf '0\n'; return 1; }

    find "$mod_path" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) \
        -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1
}

# Analyze all imports in a file and show their bundle cost
# Output: size_bytes module_name (sorted by size, descending)
ts_import_cost_file() {
    local file="$1"
    local dir="${2:-.}"

    [[ -f "$file" ]] || { printf 'File not found: %s\n' "$file" >&2; return 1; }

    ts_file_imports "$file" | \
        grep -v '^\.' | \
        while IFS= read -r module; do
            # Get the package name (handle scoped packages)
            local pkg
            if [[ "$module" == @* ]]; then
                pkg=$(printf '%s' "$module" | cut -d'/' -f1,2)
            else
                pkg=$(printf '%s' "$module" | cut -d'/' -f1)
            fi
            local size
            size=$(ts_import_cost_js "$pkg" "$dir")
            [[ -n "$size" && "$size" -gt 0 ]] && \
                printf '%s\t%s\n' "$size" "$pkg"
        done | sort -rn | uniq
}

# Get transitive dependency count for a package
ts_dep_count() {
    local module="$1"
    local dir="${2:-.}"

    local mod_path="$dir/node_modules/$module"
    [[ -d "$mod_path/node_modules" ]] || { printf '0\n'; return 0; }

    find "$mod_path/node_modules" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l
}

# Analyze the full project's import costs
# Output: total_js_bytes package_name dep_count (top N by size)
ts_bundle_analysis() {
    local dir="${1:-.}"
    local limit="${2:-20}"

    ts_is_project "$dir" || { printf 'Not a TypeScript project\n' >&2; return 1; }
    [[ -d "$dir/node_modules" ]] || { printf 'No node_modules found\n' >&2; return 1; }

    # Collect all imported packages across the project
    local -A all_imports

    find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | \
        grep -v "node_modules" | \
        grep -v "\.d\.ts$" | \
        while IFS= read -r file; do
            ts_file_imports "$file"
        done | \
        grep -v '^\.' | \
        while IFS= read -r module; do
            local pkg
            if [[ "$module" == @* ]]; then
                pkg=$(printf '%s' "$module" | cut -d'/' -f1,2)
            else
                pkg=$(printf '%s' "$module" | cut -d'/' -f1)
            fi
            printf '%s\n' "$pkg"
        done | sort -u | head -"$limit" | \
        while IFS= read -r pkg; do
            local js_size dep_count
            js_size=$(ts_import_cost_js "$pkg" "$dir")
            dep_count=$(ts_dep_count "$pkg" "$dir")
            [[ -n "$js_size" && "$js_size" -gt 0 ]] && \
                printf '%s\t%s\t%s\n' "$js_size" "$pkg" "$dep_count"
        done | sort -rn
}

# Find the heaviest packages that could be replaced
ts_heavy_imports() {
    local dir="${1:-.}"
    local threshold="${2:-1048576}"  # 1MB default

    ts_bundle_analysis "$dir" 100 | \
        while IFS=$'\t' read -r size pkg deps; do
            if [[ $size -gt $threshold ]]; then
                local human_size
                if [[ $size -gt 1073741824 ]]; then
                    human_size="$((size / 1073741824))GB"
                elif [[ $size -gt 1048576 ]]; then
                    human_size="$((size / 1048576))MB"
                else
                    human_size="$((size / 1024))KB"
                fi
                printf '%s\t%s\t(%s deps)\n' "$human_size" "$pkg" "$deps"
            fi
        done
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Count TypeScript files in a project
ts_file_count() {
    local dir="${1:-.}"
    find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | \
        grep -v "node_modules" | \
        grep -vc "\.d\.ts$"
}

# Count lines of TypeScript code
ts_loc() {
    local dir="${1:-.}"
    find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | \
        grep -v "node_modules" | \
        grep -v "\.d\.ts$" | \
        xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}'
}

# List all exported symbols across the project
ts_exports() {
    local dir="${1:-.}"

    find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | \
        grep -v "node_modules" | \
        grep -v "\.d\.ts$" | \
        while IFS= read -r file; do
            local rel="${file#$dir/}"
            grep -n "^export " "$file" 2>/dev/null | \
                while IFS=: read -r line_num content; do
                    printf '%s:%s\t%s\n' "$rel" "$line_num" "$content"
                done
        done
}

# Quick project health summary
ts_summary() {
    local dir="${1:-.}"

    ts_is_project "$dir" || { printf 'Not a TypeScript project\n' >&2; return 1; }

    local files loc imports circular
    files=$(ts_file_count "$dir")
    loc=$(ts_loc "$dir")
    imports=$(ts_import_frequency "$dir" | wc -l)
    circular=$(ts_circular_deps "$dir" 2>/dev/null | wc -l)

    printf 'files=%d loc=%d unique_imports=%d circular_deps=%d\n' \
        "$files" "$loc" "$imports" "$circular"
}

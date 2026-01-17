#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/path.sh - Pure Bash Path Manipulation
# =============================================================================
# Description: Cross-platform path operations without external tools
# Council Priority: #1 - "Path manipulation is Bash fundamental.
#                        95% of scripts fail on paths with spaces."
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PATH_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PATH_LOADED=1

# =============================================================================
# PATH NORMALIZATION
# =============================================================================

# Normalize path by resolving . and .. and collapsing multiple slashes
# Usage: path_normalize "/foo//bar/../baz"
# Returns: /foo/baz
path_normalize() {
    local path="$1"
    local result=""
    local -a parts=()
    local part

    # Handle empty path
    [[ -z "$path" ]] && { printf '%s\n' "."; return 0; }

    # Preserve leading slash for absolute paths
    local prefix=""
    [[ "$path" == /* ]] && prefix="/"

    # Remove trailing slashes (except for root)
    path="${path%"${path##*[!/]}"}"
    [[ -z "$path" ]] && path="/"

    # Split on / and process
    local IFS='/'
    read -ra parts <<< "$path"

    local -a stack=()
    for part in "${parts[@]}"; do
        # Skip empty parts (from multiple slashes) and current dir
        [[ -z "$part" || "$part" == "." ]] && continue

        if [[ "$part" == ".." ]]; then
            # Go up one level if possible
            if [[ ${#stack[@]} -gt 0 && "${stack[-1]}" != ".." ]]; then
                unset 'stack[-1]'
            elif [[ -z "$prefix" ]]; then
                # Relative path, keep the ..
                stack+=("$part")
            fi
            # For absolute paths, just skip .. at root level
        else
            stack+=("$part")
        fi
    done

    # Rebuild path
    if [[ ${#stack[@]} -eq 0 ]]; then
        result="${prefix:-.}"
    else
        local IFS='/'
        result="${prefix}${stack[*]}"
    fi

    printf '%s\n' "$result"
}

# Get absolute path (resolves to real filesystem path)
# Usage: path_absolute "relative/path"
# Returns: /current/working/dir/relative/path
path_absolute() {
    local path="$1"

    # Handle empty path
    [[ -z "$path" ]] && { pwd; return 0; }

    # Already absolute
    if [[ "$path" == /* ]]; then
        path_normalize "$path"
        return 0
    fi

    # Handle tilde expansion first
    if [[ "$path" == "~"* ]]; then
        path="${path/#\~/$HOME}"
        # After expansion, path is now absolute
        path_normalize "$path"
        return 0
    fi

    # Make relative path absolute
    local cwd
    cwd=$(pwd)
    path_normalize "${cwd}/${path}"
}

# Get relative path from base to target
# Usage: path_relative "/abs/path/to/file" "/abs/path"
# Returns: to/file
path_relative() {
    local target="$1"
    local base="${2:-$(pwd)}"

    # Normalize both paths
    target=$(path_normalize "$target")
    base=$(path_normalize "$base")

    # Ensure base ends without slash (except root)
    [[ "$base" != "/" ]] && base="${base%/}"

    # If target starts with base, strip it
    if [[ "$target" == "$base"/* ]]; then
        printf '%s\n' "${target#"$base"/}"
        return 0
    fi

    # If they're the same
    if [[ "$target" == "$base" ]]; then
        printf '%s\n' "."
        return 0
    fi

    # Build relative path using ..
    local -a target_parts=()
    local -a base_parts=()

    local IFS='/'
    read -ra target_parts <<< "$target"
    read -ra base_parts <<< "$base"

    # Find common prefix length
    local common=0
    local i
    for ((i=0; i < ${#base_parts[@]} && i < ${#target_parts[@]}; i++)); do
        [[ "${base_parts[i]}" != "${target_parts[i]}" ]] && break
        ((common++))
    done

    # Build result
    local result=""

    # Add .. for each remaining base component
    for ((i=common; i < ${#base_parts[@]}; i++)); do
        [[ -z "${base_parts[i]}" ]] && continue
        [[ -n "$result" ]] && result+="/"
        result+=".."
    done

    # Add remaining target components
    for ((i=common; i < ${#target_parts[@]}; i++)); do
        [[ -z "${target_parts[i]}" ]] && continue
        [[ -n "$result" ]] && result+="/"
        result+="${target_parts[i]}"
    done

    [[ -z "$result" ]] && result="."
    printf '%s\n' "$result"
}

# =============================================================================
# PATH COMPONENTS
# =============================================================================

# Get directory component of path
# Usage: path_dir "/foo/bar/baz.txt"
# Returns: /foo/bar
path_dir() {
    local path="$1"

    # Handle empty path
    [[ -z "$path" ]] && { printf '%s\n' "."; return 0; }

    # Remove trailing slashes
    path="${path%"${path##*[!/]}"}"
    [[ -z "$path" ]] && { printf '%s\n' "/"; return 0; }

    # No slash means current directory
    [[ "$path" != */* ]] && { printf '%s\n' "."; return 0; }

    # Remove everything after last slash
    local dir="${path%/*}"

    # Handle root
    [[ -z "$dir" ]] && dir="/"

    printf '%s\n' "$dir"
}

# Get filename component of path
# Usage: path_base "/foo/bar/baz.txt"
# Returns: baz.txt
path_base() {
    local path="$1"

    # Handle empty path
    [[ -z "$path" ]] && { printf '\n'; return 0; }

    # Remove trailing slashes
    path="${path%"${path##*[!/]}"}"
    [[ -z "$path" ]] && { printf '\n'; return 0; }

    printf '%s\n' "${path##*/}"
}

# Get file extension (last extension only)
# Usage: path_ext "/foo/bar.tar.gz"
# Returns: gz
path_ext() {
    local path="$1"
    local base="${path##*/}"

    # No extension if no dot or starts with dot (hidden file)
    [[ "$base" != *.* ]] && { printf '\n'; return 0; }
    [[ "$base" == .* && "${base#.}" != *.* ]] && { printf '\n'; return 0; }

    printf '%s\n' "${base##*.}"
}

# Get all extensions (for files like .tar.gz)
# Usage: path_ext_full "/foo/bar.tar.gz"
# Returns: tar.gz
path_ext_full() {
    local path="$1"
    local base="${path##*/}"

    # Skip leading dot for hidden files
    [[ "$base" == .* ]] && base="${base#.}"

    # No extension if no dot
    [[ "$base" != *.* ]] && { printf '\n'; return 0; }

    printf '%s\n' "${base#*.}"
}

# Get filename without extension (stem)
# Usage: path_stem "/foo/bar.tar.gz"
# Returns: bar.tar (single extension removed)
path_stem() {
    local path="$1"
    local base="${path##*/}"

    # Handle hidden files without additional extension
    if [[ "$base" == .* && "${base#.}" != *.* ]]; then
        printf '%s\n' "$base"
        return 0
    fi

    # No extension
    [[ "$base" != *.* ]] && { printf '%s\n' "$base"; return 0; }

    printf '%s\n' "${base%.*}"
}

# Get filename without all extensions
# Usage: path_stem_full "/foo/bar.tar.gz"
# Returns: bar
path_stem_full() {
    local path="$1"
    local base="${path##*/}"

    # Handle hidden files
    local hidden_prefix=""
    if [[ "$base" == .* ]]; then
        hidden_prefix="."
        base="${base#.}"
    fi

    # No extension
    [[ "$base" != *.* ]] && { printf '%s\n' "${hidden_prefix}${base}"; return 0; }

    printf '%s\n' "${hidden_prefix}${base%%.*}"
}

# =============================================================================
# PATH CONSTRUCTION
# =============================================================================

# Join path components safely
# Usage: path_join "/foo" "bar" "baz"
# Returns: /foo/bar/baz
path_join() {
    local result=""
    local part

    for part in "$@"; do
        # Skip empty parts
        [[ -z "$part" ]] && continue

        if [[ -z "$result" ]]; then
            result="$part"
        else
            # Remove trailing slash from result
            result="${result%/}"
            # Remove leading slash from part (unless result is empty/root)
            [[ "$result" != "/" ]] && part="${part#/}"
            result="${result}/${part}"
        fi
    done

    # Clean up any double slashes
    while [[ "$result" == *//* ]]; do
        result="${result//\/\//\/}"
    done

    printf '%s\n' "$result"
}

# Replace file extension
# Usage: path_replace_ext "/foo/bar.txt" "md"
# Returns: /foo/bar.md
path_replace_ext() {
    local path="$1"
    local new_ext="$2"
    local dir base stem

    dir=$(path_dir "$path")
    base="${path##*/}"

    # Handle files without extension
    if [[ "$base" != *.* ]] || [[ "$base" == .* && "${base#.}" != *.* ]]; then
        [[ -n "$new_ext" ]] && printf '%s\n' "${path}.${new_ext}" || printf '%s\n' "$path"
        return 0
    fi

    stem="${base%.*}"

    if [[ -n "$new_ext" ]]; then
        if [[ "$dir" == "." ]]; then
            printf '%s\n' "${stem}.${new_ext}"
        else
            printf '%s\n' "${dir}/${stem}.${new_ext}"
        fi
    else
        if [[ "$dir" == "." ]]; then
            printf '%s\n' "$stem"
        else
            printf '%s\n' "${dir}/${stem}"
        fi
    fi
}

# Add suffix before extension
# Usage: path_add_suffix "/foo/bar.txt" "_backup"
# Returns: /foo/bar_backup.txt
path_add_suffix() {
    local path="$1"
    local suffix="$2"
    local dir base stem ext

    dir=$(path_dir "$path")
    base="${path##*/}"

    # Handle files without extension
    if [[ "$base" != *.* ]] || [[ "$base" == .* && "${base#.}" != *.* ]]; then
        printf '%s\n' "${path}${suffix}"
        return 0
    fi

    ext="${base##*.}"
    stem="${base%.*}"

    if [[ "$dir" == "." ]]; then
        printf '%s\n' "${stem}${suffix}.${ext}"
    else
        printf '%s\n' "${dir}/${stem}${suffix}.${ext}"
    fi
}

# =============================================================================
# CROSS-PLATFORM
# =============================================================================

# Convert Windows path to Unix path
# Usage: path_to_unix "C:\Users\foo\file.txt"
# Returns: /c/Users/foo/file.txt
path_to_unix() {
    local path="$1"

    # Handle drive letter (C:\ or C:/)
    if [[ "$path" =~ ^([A-Za-z]):[\\/] ]]; then
        local drive="${BASH_REMATCH[1]}"
        drive="${drive,,}"  # Lowercase
        path="/${drive}${path:2}"
    fi

    # Convert backslashes to forward slashes
    path="${path//\\//}"

    printf '%s\n' "$path"
}

# Convert Unix path to Windows path
# Usage: path_to_windows "/c/Users/foo/file.txt"
# Returns: C:\Users\foo\file.txt
path_to_windows() {
    local path="$1"

    # Handle /c/... style paths (Git Bash, MSYS)
    if [[ "$path" =~ ^/([A-Za-z])/ ]]; then
        local drive="${BASH_REMATCH[1]}"
        drive="${drive^^}"  # Uppercase
        path="${drive}:${path:2}"
    fi

    # Convert forward slashes to backslashes
    path="${path//\//\\}"

    printf '%s\n' "$path"
}

# Detect path style
# Usage: path_style "/foo/bar" -> "unix"
# Usage: path_style "C:\foo" -> "windows"
path_style() {
    local path="$1"

    if [[ "$path" =~ ^[A-Za-z]:[\\/] ]]; then
        printf '%s\n' "windows"
    elif [[ "$path" == /* ]]; then
        printf '%s\n' "unix"
    elif [[ "$path" =~ \\\\ ]]; then
        printf '%s\n' "windows"
    else
        printf '%s\n' "relative"
    fi
}

# =============================================================================
# SAFETY
# =============================================================================

# Quote path for safe shell usage
# Usage: path_quote "/path with spaces/file"
# Returns: '/path with spaces/file' or path without quotes if safe
path_quote() {
    local path="$1"

    # If path contains no special characters, return as-is
    if [[ "$path" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        printf '%s\n' "$path"
        return 0
    fi

    # Use printf %q for proper escaping
    printf '%q\n' "$path"
}

# Check if path is safe (no directory traversal outside base)
# Usage: path_is_safe "/base" "/base/sub/file"
# Returns: 0 if safe, 1 if traversal detected
path_is_safe() {
    local base="$1"
    local path="$2"

    # Normalize both paths
    base=$(path_normalize "$base")
    path=$(path_normalize "$path")

    # Make path absolute if relative
    if [[ "$path" != /* ]]; then
        path="${base}/${path}"
        path=$(path_normalize "$path")
    fi

    # Ensure base ends with / for proper prefix check (except root)
    [[ "$base" != "/" ]] && base="${base}/"

    # Check if path starts with base
    [[ "$path" == "${base}"* || "$path" == "${base%/}" ]]
}

# Ensure parent directory exists (create if needed)
# Usage: path_ensure_dir "/foo/bar/baz/file.txt"
# Creates: /foo/bar/baz/
path_ensure_dir() {
    local path="$1"
    local dir

    dir=$(path_dir "$path")

    [[ "$dir" == "." || -d "$dir" ]] && return 0

    mkdir -p "$dir"
}

# Sanitize filename (remove unsafe characters)
# Usage: path_sanitize "my file: with <bad> chars?.txt"
# Returns: my_file_with_bad_chars.txt
path_sanitize() {
    local name="$1"
    local replacement="${2:-_}"

    # Use tr for reliable character replacement (handles special chars safely)
    # Replace: < > : " \ | ? *
    name=$(printf '%s' "$name" | tr '<>:"\|?*' "${replacement}${replacement}${replacement}${replacement}${replacement}${replacement}${replacement}${replacement}")

    # Replace control characters
    name=$(printf '%s' "$name" | tr '\000-\037' "$(printf '%0.s%s' {1..32} "$replacement" | cut -c1-32)")

    # Trim leading/trailing spaces using parameter expansion
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"

    # Collapse multiple replacements
    while [[ "$name" == *"${replacement}${replacement}"* ]]; do
        name="${name//${replacement}${replacement}/${replacement}}"
    done

    # Remove leading/trailing replacement chars
    name="${name#"$replacement"}"
    name="${name%"$replacement"}"

    printf '%s\n' "$name"
}

# =============================================================================
# EXPANSION
# =============================================================================

# Expand tilde to home directory
# Usage: path_expand_tilde "~/Documents"
# Returns: /home/user/Documents
path_expand_tilde() {
    local path="$1"

    # shellcheck disable=SC2088  # Intentional: matching literal tilde patterns for expansion
    case "$path" in
        "~")
            printf '%s\n' "$HOME"
            ;;
        "~/"*)
            printf '%s\n' "${HOME}${path:1}"
            ;;
        "~"*)
            # Handle ~username (requires getent or similar)
            local user="${path%%/*}"
            user="${user#\~}"
            local user_home
            if user_home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6); then
                printf '%s\n' "${user_home}${path#"~$user"}"
            else
                # Fallback: just return as-is
                printf '%s\n' "$path"
            fi
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

# Find common prefix of multiple paths
# Usage: path_common_prefix "/a/b/c" "/a/b/d" "/a/b/e"
# Returns: /a/b
path_common_prefix() {
    [[ $# -eq 0 ]] && { printf '\n'; return 0; }
    [[ $# -eq 1 ]] && { path_dir "$1"; return 0; }

    # Start with first path
    local prefix="$1"
    shift

    for path in "$@"; do
        # Find common prefix between current prefix and path
        local i=0
        local len=${#prefix}
        [[ ${#path} -lt $len ]] && len=${#path}

        while [[ $i -lt $len && "${prefix:i:1}" == "${path:i:1}" ]]; do
            ((i++))
        done

        prefix="${prefix:0:i}"
    done

    # Trim to last slash (don't return partial path component)
    if [[ "$prefix" == */* ]]; then
        prefix="${prefix%/*}"
        [[ -z "$prefix" ]] && prefix="/"
    else
        prefix=""
    fi

    printf '%s\n' "$prefix"
}

# =============================================================================
# PATH CHECKS
# =============================================================================

# Check if path is absolute
# Usage: path_is_absolute "/foo/bar" && echo "yes"
path_is_absolute() {
    [[ "$1" == /* ]]
}

# Check if path is relative
# Usage: path_is_relative "foo/bar" && echo "yes"
path_is_relative() {
    [[ "$1" != /* ]]
}

# Check if path contains parent reference (..)
# Usage: path_has_parent_ref "../foo" && echo "yes"
path_has_parent_ref() {
    local path="$1"
    [[ "$path" == ".." || "$path" == "../"* || "$path" == *"/.."/* || "$path" == *"/.." ]]
}

# Check if path is hidden (starts with .)
# Usage: path_is_hidden "/foo/.bar"
path_is_hidden() {
    local base="${1##*/}"
    [[ "$base" == .* ]]
}

# Check if two paths are equivalent (after normalization)
# Usage: path_equals "/foo/bar/../baz" "/foo/baz"
path_equals() {
    local path1 path2
    path1=$(path_normalize "$1")
    path2=$(path_normalize "$2")
    [[ "$path1" == "$path2" ]]
}

# Get path depth (number of components)
# Usage: path_depth "/foo/bar/baz"
# Returns: 3
path_depth() {
    local path="$1"

    # Normalize first
    path=$(path_normalize "$path")

    # Handle root
    [[ "$path" == "/" ]] && { printf '%d\n' 0; return 0; }

    # Remove leading slash for counting
    path="${path#/}"

    # Count slashes + 1
    local count=1
    local temp="${path//[^\/]/}"
    ((count += ${#temp}))

    printf '%d\n' "$count"
}

# Split path into array of components
# Usage: path_split "/foo/bar/baz" arr; echo "${arr[@]}"
path_split() {
    local path="$1"
    local -n result_array="$2"

    # Normalize first
    path=$(path_normalize "$path")

    # Clear result
    result_array=()

    # Handle root
    [[ "$path" == "/" ]] && return 0

    # Remove leading slash
    path="${path#/}"

    # Split
    local IFS='/'
    read -ra result_array <<< "$path"
}

# =============================================================================
# FILENAME UTILITIES
# =============================================================================

# Generate unique filename if exists
# Usage: path_unique "/foo/bar.txt"
# Returns: /foo/bar.txt if not exists, /foo/bar (1).txt if exists
path_unique() {
    local path="$1"

    [[ ! -e "$path" ]] && { printf '%s\n' "$path"; return 0; }

    local dir base stem ext counter=1
    dir=$(path_dir "$path")
    base="${path##*/}"

    if [[ "$base" == *.* && ! ( "$base" == .* && "${base#.}" != *.* ) ]]; then
        ext="${base##*.}"
        stem="${base%.*}"
    else
        ext=""
        stem="$base"
    fi

    while true; do
        if [[ -n "$ext" ]]; then
            if [[ "$dir" == "." ]]; then
                path="${stem} (${counter}).${ext}"
            else
                path="${dir}/${stem} (${counter}).${ext}"
            fi
        else
            if [[ "$dir" == "." ]]; then
                path="${stem} (${counter})"
            else
                path="${dir}/${stem} (${counter})"
            fi
        fi

        [[ ! -e "$path" ]] && break
        ((counter++))

        # Safety limit
        [[ $counter -gt 9999 ]] && { printf '%s\n' "$1"; return 1; }
    done

    printf '%s\n' "$path"
}

# Resolve symlinks to get real path
# Usage: path_resolve "/path/to/symlink"
# Returns: /actual/real/path
path_resolve() {
    local path="$1"
    local resolved="$path"
    local count=0

    # Follow symlinks (with loop detection)
    while [[ -L "$resolved" ]]; do
        local dir link
        dir=$(path_dir "$resolved")
        link=$(readlink "$resolved")

        # Make relative link absolute
        if [[ "$link" != /* ]]; then
            resolved="${dir}/${link}"
        else
            resolved="$link"
        fi

        resolved=$(path_normalize "$resolved")

        ((count++))
        [[ $count -gt 40 ]] && { printf '%s\n' "$path"; return 1; }  # Symlink loop
    done

    # Make absolute
    if [[ "$resolved" != /* ]]; then
        resolved="$(pwd)/${resolved}"
    fi

    path_normalize "$resolved"
}

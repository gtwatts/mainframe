#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/pure-file.sh - Pure Bash File Operations
# =============================================================================
# Description: File operations without external tools (cat, head, tail)
# Source: Inspired by Pure Bash Bible
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PURE_FILE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PURE_FILE_LOADED=1

# =============================================================================
# READING FILES
# =============================================================================

# Read entire file to variable
# Usage: read_file "/path/to/file"
read_file() {
    printf '%s\n' "$(<"$1")"
}

# Read file into array (one element per line)
# Usage: read_file_lines "/path/to/file" arr_name
read_file_lines() {
    local file="$1"
    local -n result_array="$2"
    mapfile -t result_array < "$file"
}

# Get first N lines of file
# Usage: file_head 10 "/path/to/file"
file_head() {
    local n="${1:-10}"
    local file="$2"
    local lines
    mapfile -tn "$n" lines < "$file"
    printf '%s\n' "${lines[@]}"
}

# Get last N lines of file
# Usage: file_tail 10 "/path/to/file"
file_tail() {
    local n="${1:-10}"
    local file="$2"
    local lines
    mapfile -tn 0 lines < "$file"
    printf '%s\n' "${lines[@]: -$n}"
}

# Get specific line range
# Usage: file_range 5 10 "/path/to/file"
file_range() {
    local start="$1"
    local end="$2"
    local file="$3"
    local lines
    mapfile -tn 0 lines < "$file"
    printf '%s\n' "${lines[@]:$((start-1)):$((end-start+1))}"
}

# Get single line by number
# Usage: file_line 5 "/path/to/file"
file_line() {
    local num="$1"
    local file="$2"
    local lines
    mapfile -tn "$num" lines < "$file"
    printf '%s\n' "${lines[-1]}"
}

# =============================================================================
# FILE INFORMATION
# =============================================================================

# Count lines in file
# Usage: file_lines "/path/to/file"
file_lines() {
    local lines
    mapfile -tn 0 lines < "$1"
    printf '%d\n' "${#lines[@]}"
}

# Count words in file
# Usage: file_words "/path/to/file"
file_words() {
    local content
    content=$(<"$1")
    local words=($content)
    printf '%d\n' "${#words[@]}"
}

# Count characters in file
# Usage: file_chars "/path/to/file"
file_chars() {
    local content
    content=$(<"$1")
    printf '%d\n' "${#content}"
}

# Get file size in bytes (using stat)
# Usage: file_size "/path/to/file"
file_size() {
    local file="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        stat -f%z "$file"
    else
        stat -c%s "$file"
    fi
}

# =============================================================================
# FILE CHECKS
# =============================================================================

# Check if file exists
# Usage: file_exists "/path/to/file" && echo "yes"
file_exists() {
    [[ -f "$1" ]]
}

# Check if directory exists
# Usage: dir_exists "/path/to/dir" && echo "yes"
dir_exists() {
    [[ -d "$1" ]]
}

# Check if file is empty
# Usage: file_empty "/path/to/file" && echo "empty"
file_empty() {
    [[ ! -s "$1" ]]
}

# Check if file is readable
# Usage: file_readable "/path/to/file" && echo "yes"
file_readable() {
    [[ -r "$1" ]]
}

# Check if file is writable
# Usage: file_writable "/path/to/file" && echo "yes"
file_writable() {
    [[ -w "$1" ]]
}

# Check if file is executable
# Usage: file_executable "/path/to/file" && echo "yes"
file_executable() {
    [[ -x "$1" ]]
}

# Check if path is symlink
# Usage: file_symlink "/path/to/file" && echo "yes"
file_symlink() {
    [[ -L "$1" ]]
}

# Check if file is newer than another
# Usage: file_newer "file1" "file2" && echo "file1 is newer"
file_newer() {
    [[ "$1" -nt "$2" ]]
}

# Check if file is older than another
# Usage: file_older "file1" "file2" && echo "file1 is older"
file_older() {
    [[ "$1" -ot "$2" ]]
}

# =============================================================================
# PATH OPERATIONS
# =============================================================================

# Get filename from path (pure bash basename)
# Usage: path_basename "/path/to/file.txt"
path_basename() {
    printf '%s\n' "${1##*/}"
}

# Get directory from path (pure bash dirname)
# Usage: path_dirname "/path/to/file.txt"
path_dirname() {
    local path="$1"
    [[ "$path" == */* ]] && printf '%s\n' "${path%/*}" || printf '%s\n' "."
}

# Get file extension
# Usage: path_extension "/path/to/file.txt"
path_extension() {
    local base="${1##*/}"
    [[ "$base" == *.* ]] && printf '%s\n' "${base##*.}" || printf '\n'
}

# Get filename without extension
# Usage: path_stem "/path/to/file.txt"
path_stem() {
    local base="${1##*/}"
    printf '%s\n' "${base%.*}"
}

# Remove trailing slashes
# Usage: path_normalize "/path/to/dir/"
path_normalize() {
    printf '%s\n' "${1%/}"
}

# Join path components
# Usage: path_join "/path" "to" "file.txt"
path_join() {
    local result=""
    for part in "$@"; do
        part="${part%/}"  # Remove trailing slash
        part="${part#/}"  # Remove leading slash (except first)
        if [[ -z "$result" ]]; then
            result="$part"
        else
            result="${result}/${part}"
        fi
    done
    printf '%s\n' "$result"
}

# Check if path is absolute
# Usage: path_is_absolute "/path/to/file" && echo "yes"
path_is_absolute() {
    [[ "$1" == /* ]]
}

# Check if path is relative
# Usage: path_is_relative "path/to/file" && echo "yes"
path_is_relative() {
    [[ "$1" != /* ]]
}

# =============================================================================
# FILE CREATION
# =============================================================================

# Create empty file (touch equivalent)
# Usage: file_touch "/path/to/file"
file_touch() {
    >"$1"
}

# Create file with content
# Usage: file_write "/path/to/file" "content"
file_write() {
    printf '%s\n' "$2" > "$1"
}

# Append content to file
# Usage: file_append "/path/to/file" "content"
file_append() {
    printf '%s\n' "$2" >> "$1"
}

# Create directory (mkdir -p equivalent)
# Usage: dir_create "/path/to/new/dir"
dir_create() {
    local dir="$1"
    local path=""
    local IFS='/'

    for part in $dir; do
        path="${path}/${part}"
        [[ -d "$path" ]] || mkdir "$path"
    done
}

# =============================================================================
# GLOB OPERATIONS
# =============================================================================

# Get files matching pattern
# Usage: glob_files "*.sh"
glob_files() {
    local pattern="$1"
    local files=()

    shopt -s nullglob
    files=($pattern)
    shopt -u nullglob

    printf '%s\n' "${files[@]}"
}

# Get directories in path
# Usage: glob_dirs "/path/to/search"
glob_dirs() {
    local path="${1:-.}"
    local dirs=()

    shopt -s nullglob
    for item in "$path"/*/; do
        dirs+=("${item%/}")
    done
    shopt -u nullglob

    printf '%s\n' "${dirs[@]}"
}

# Recursive file search by extension
# Usage: find_by_ext ".sh" "/path/to/search"
find_by_ext() {
    local ext="$1"
    local path="${2:-.}"

    shopt -s globstar nullglob
    printf '%s\n' "$path"/**/*"$ext"
    shopt -u globstar nullglob
}

# =============================================================================
# FILE CONTENT OPERATIONS
# =============================================================================

# Search for pattern in file (grep-like)
# Usage: file_grep "pattern" "/path/to/file"
file_grep() {
    local pattern="$1"
    local file="$2"
    local line_num=0

    while IFS= read -r line; do
        ((line_num++)) || true
        if [[ "$line" =~ $pattern ]]; then
            printf '%d:%s\n' "$line_num" "$line"
        fi
    done < "$file"
}

# Count pattern occurrences in file
# Usage: file_count_pattern "pattern" "/path/to/file"
file_count_pattern() {
    local pattern="$1"
    local file="$2"
    local count=0

    while IFS= read -r line; do
        if [[ "$line" =~ $pattern ]]; then
            ((count++)) || true
        fi
    done < "$file"

    printf '%d\n' "$count"
}

# Replace pattern in file content (returns modified content)
# Usage: file_replace "old" "new" "/path/to/file"
file_replace() {
    local old="$1"
    local new="$2"
    local file="$3"
    local content
    content=$(<"$file")
    printf '%s\n' "${content//$old/$new}"
}


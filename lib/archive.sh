#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/archive.sh - Archive and Compression Library
# =============================================================================
# Description: Comprehensive archive operations for tar, gzip, zip formats
#              with USOP JSON output, Design-by-Contract validation, and
#              safety features for AI coding agents.
# Version: 1.0.0
# Requires: Bash 4.0+, tar, gzip, zip/unzip (for zip operations)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ARCHIVE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ARCHIVE_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Auto-source dependencies if not already loaded
_ARCHIVE_LIB_DIR="${BASH_SOURCE[0]%/*}"

if ! declare -F json_object &>/dev/null; then
    [[ -f "${_ARCHIVE_LIB_DIR}/json.sh" ]] && source "${_ARCHIVE_LIB_DIR}/json.sh"
fi

if ! declare -F contract_require &>/dev/null; then
    [[ -f "${_ARCHIVE_LIB_DIR}/contract.sh" ]] && source "${_ARCHIVE_LIB_DIR}/contract.sh"
fi

if ! declare -F output_json_object &>/dev/null; then
    [[ -f "${_ARCHIVE_LIB_DIR}/output.sh" ]] && source "${_ARCHIVE_LIB_DIR}/output.sh"
fi

if ! declare -F validate_path_safe &>/dev/null; then
    [[ -f "${_ARCHIVE_LIB_DIR}/validation.sh" ]] && source "${_ARCHIVE_LIB_DIR}/validation.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default compression level (1-9, where 9 is maximum compression)
ARCHIVE_GZIP_LEVEL="${ARCHIVE_GZIP_LEVEL:-6}"

# Maximum extraction size limit in bytes (default: 1GB)
ARCHIVE_MAX_SIZE="${ARCHIVE_MAX_SIZE:-1073741824}"

# Enable/disable path safety checks
ARCHIVE_SAFE_MODE="${ARCHIVE_SAFE_MODE:-1}"

# =============================================================================
# TOOL DETECTION
# =============================================================================

# @pre: none
# @post: returns 0 if tar is available, 1 otherwise
# @idempotent: yes
_archive_has_tar() {
    type -p tar &>/dev/null
}

# @pre: none
# @post: returns 0 if gzip is available, 1 otherwise
# @idempotent: yes
_archive_has_gzip() {
    type -p gzip &>/dev/null
}

# @pre: none
# @post: returns 0 if zip is available, 1 otherwise
# @idempotent: yes
_archive_has_zip() {
    type -p zip &>/dev/null
}

# @pre: none
# @post: returns 0 if unzip is available, 1 otherwise
# @idempotent: yes
_archive_has_unzip() {
    type -p unzip &>/dev/null
}

# @pre: none
# @post: returns 0 if gunzip is available, 1 otherwise
# @idempotent: yes
_archive_has_gunzip() {
    type -p gunzip &>/dev/null
}

# @pre: none
# @post: returns 0 if zcat is available, 1 otherwise
# @idempotent: yes
_archive_has_zcat() {
    type -p zcat &>/dev/null
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_archive_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Get file size in bytes (portable)
# @pre: file exists
# @post: returns file size as integer
_archive_file_size() {
    local file="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        stat -f%z "$file" 2>/dev/null || echo "0"
    else
        stat -c%s "$file" 2>/dev/null || echo "0"
    fi
}

# Get file modification time as epoch
# @pre: file exists
# @post: returns mtime as epoch seconds
_archive_file_mtime() {
    local file="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        stat -f%m "$file" 2>/dev/null || echo "0"
    else
        stat -c%Y "$file" 2>/dev/null || echo "0"
    fi
}

# Count files in a tar archive
# @pre: archive exists and is readable
# @post: returns count of entries
_archive_tar_count() {
    local archive="$1"
    tar -tf "$archive" 2>/dev/null | wc -l | tr -d ' '
}

# =============================================================================
# TAR OPERATIONS
# =============================================================================

# Create tarball from paths
# @pre: output path is writable, source paths exist
# @post: tarball created at output path
# @returns: JSON envelope with success status
#
# Usage: tar_create output.tar path1 [path2 ...]
# Usage: tar_create output.tar.gz path1 [path2 ...]  # auto-detect compression
tar_create() {
    local output="$1"
    shift
    local -a paths=("$@")

    # Contract: require output path and at least one source
    if [[ -z "$output" ]]; then
        json_object "success:bool=false" "error=output path required" \
            "suggestion=Provide output archive path as first argument"
        return 1
    fi

    if [[ ${#paths[@]} -eq 0 ]]; then
        json_object "success:bool=false" "error=no source paths provided" \
            "suggestion=Provide at least one path to archive"
        return 1
    fi

    # Verify source paths exist
    local path
    for path in "${paths[@]}"; do
        if [[ ! -e "$path" ]]; then
            json_object "success:bool=false" "error=source path not found" \
                "path=$path" "suggestion=Verify the path exists"
            return 1
        fi
    done

    # Detect compression from extension
    local compress_flag=""
    case "$output" in
        *.tar.gz|*.tgz)  compress_flag="-z" ;;
        *.tar.bz2|*.tbz) compress_flag="-j" ;;
        *.tar.xz|*.txz)  compress_flag="-J" ;;
        *.tar)           compress_flag="" ;;
        *)
            json_object "success:bool=false" "error=unsupported archive extension" \
                "path=$output" "suggestion=Use .tar, .tar.gz, .tar.bz2, or .tar.xz"
            return 1
            ;;
    esac

    # Create the tarball
    local stderr_file
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/tar_err.XXXXXX")

    if tar $compress_flag -cf "$output" "${paths[@]}" 2>"$stderr_file"; then
        local size count
        size=$(_archive_file_size "$output")
        count=$(_archive_tar_count "$output")

        rm -f "$stderr_file"
        json_object "success:bool=true" "path=$output" "size:number=$size" \
            "file_count:number=$count" "action=created"
    else
        local err_msg
        err_msg=$(<"$stderr_file")
        rm -f "$stderr_file"
        json_object "success:bool=false" "error=tar creation failed" \
            "stderr=$err_msg" "suggestion=Check source paths and disk space"
        return 1
    fi
}

# Extract tarball to directory
# @pre: archive exists and is readable, destination is writable
# @post: archive contents extracted to destination
# @returns: JSON envelope with success status
#
# Usage: tar_extract archive.tar [destination]
# Usage: tar_extract archive.tar.gz /path/to/dest
tar_extract() {
    local archive="$1"
    local dest="${2:-.}"

    # Contract: archive must exist
    if [[ -z "$archive" ]]; then
        json_object "success:bool=false" "error=archive path required" \
            "suggestion=Provide archive path as first argument"
        return 1
    fi

    if [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=$archive" "suggestion=Verify the archive path exists"
        return 1
    fi

    # Safety check: verify no path traversal in archive
    if [[ "$ARCHIVE_SAFE_MODE" == "1" ]]; then
        if ! archive_path_safe "$archive"; then
            json_object "success:bool=false" "error=unsafe paths detected in archive" \
                "path=$archive" "suggestion=Archive contains path traversal sequences"
            return 1
        fi
    fi

    # Create destination if needed
    if [[ ! -d "$dest" ]]; then
        mkdir -p "$dest" || {
            json_object "success:bool=false" "error=cannot create destination" \
                "path=$dest" "suggestion=Check write permissions"
            return 1
        }
    fi

    # Detect compression from extension
    local compress_flag=""
    case "$archive" in
        *.tar.gz|*.tgz)  compress_flag="-z" ;;
        *.tar.bz2|*.tbz) compress_flag="-j" ;;
        *.tar.xz|*.txz)  compress_flag="-J" ;;
        *.tar)           compress_flag="" ;;
    esac

    # Extract
    local stderr_file
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/tar_err.XXXXXX")

    if tar $compress_flag -xf "$archive" -C "$dest" 2>"$stderr_file"; then
        local count
        count=$(_archive_tar_count "$archive")
        rm -f "$stderr_file"
        json_object "success:bool=true" "archive=$archive" "destination=$dest" \
            "file_count:number=$count" "action=extracted"
    else
        local err_msg
        err_msg=$(<"$stderr_file")
        rm -f "$stderr_file"
        json_object "success:bool=false" "error=tar extraction failed" \
            "stderr=$err_msg" "suggestion=Archive may be corrupted"
        return 1
    fi
}

# List tarball contents as JSON
# @pre: archive exists and is readable
# @post: returns JSON array of file entries
# @returns: JSON envelope with file list
#
# Usage: tar_list archive.tar
# Usage: tar_list archive.tar.gz --verbose
tar_list() {
    local archive="$1"
    local verbose="${2:-}"

    # Contract: archive must exist
    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}" "suggestion=Provide valid archive path"
        return 1
    fi

    # Detect compression
    local compress_flag=""
    case "$archive" in
        *.tar.gz|*.tgz)  compress_flag="-z" ;;
        *.tar.bz2|*.tbz) compress_flag="-j" ;;
        *.tar.xz|*.txz)  compress_flag="-J" ;;
    esac

    local -a entries=()
    local line

    if [[ "$verbose" == "--verbose" || "$verbose" == "-v" ]]; then
        # Verbose listing with permissions, size, date
        while IFS= read -r line; do
            entries+=("$line")
        done < <(tar $compress_flag -tvf "$archive" 2>/dev/null)
    else
        # Simple listing - just filenames
        while IFS= read -r line; do
            entries+=("$line")
        done < <(tar $compress_flag -tf "$archive" 2>/dev/null)
    fi

    local files_json
    files_json=$(json_array "${entries[@]}")

    json_object "success:bool=true" "archive=$archive" \
        "count:number=${#entries[@]}" "files:raw=$files_json"
}

# Append files to tarball (uncompressed only)
# @pre: archive exists and is uncompressed tar, files exist
# @post: files appended to archive
# @returns: JSON envelope with success status
#
# Usage: tar_append archive.tar file1 [file2 ...]
tar_append() {
    local archive="$1"
    shift
    local -a files=("$@")

    # Contract: uncompressed tar only
    if [[ -z "$archive" ]]; then
        json_object "success:bool=false" "error=archive path required"
        return 1
    fi

    if [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" "path=$archive"
        return 1
    fi

    case "$archive" in
        *.tar) ;; # OK
        *)
            json_object "success:bool=false" \
                "error=append only supported for uncompressed .tar archives" \
                "path=$archive" "suggestion=Decompress archive first"
            return 1
            ;;
    esac

    if [[ ${#files[@]} -eq 0 ]]; then
        json_object "success:bool=false" "error=no files to append"
        return 1
    fi

    # Verify files exist
    local f
    for f in "${files[@]}"; do
        if [[ ! -e "$f" ]]; then
            json_object "success:bool=false" "error=file not found" "path=$f"
            return 1
        fi
    done

    if tar -rf "$archive" "${files[@]}" 2>/dev/null; then
        local size count
        size=$(_archive_file_size "$archive")
        count=$(_archive_tar_count "$archive")
        json_object "success:bool=true" "archive=$archive" \
            "appended:number=${#files[@]}" "total_files:number=$count" \
            "size:number=$size"
    else
        json_object "success:bool=false" "error=tar append failed" \
            "suggestion=Check archive integrity and write permissions"
        return 1
    fi
}

# Extract single file from tarball
# @pre: archive exists, file path is valid
# @post: single file extracted
# @returns: JSON envelope with success status
#
# Usage: tar_extract_file archive.tar path/in/archive [destination]
tar_extract_file() {
    local archive="$1"
    local file_path="$2"
    local dest="${3:-.}"

    # Contract validation
    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    if [[ -z "$file_path" ]]; then
        json_object "success:bool=false" "error=file path required" \
            "suggestion=Specify the path of file to extract from archive"
        return 1
    fi

    # Create destination if needed
    [[ ! -d "$dest" ]] && mkdir -p "$dest"

    # Detect compression
    local compress_flag=""
    case "$archive" in
        *.tar.gz|*.tgz)  compress_flag="-z" ;;
        *.tar.bz2|*.tbz) compress_flag="-j" ;;
        *.tar.xz|*.txz)  compress_flag="-J" ;;
    esac

    if tar $compress_flag -xf "$archive" -C "$dest" "$file_path" 2>/dev/null; then
        json_object "success:bool=true" "archive=$archive" \
            "file=$file_path" "destination=$dest" "action=extracted"
    else
        json_object "success:bool=false" "error=file not found in archive" \
            "file=$file_path" "suggestion=Use tar_list to see available files"
        return 1
    fi
}

# Get tarball metadata
# @pre: archive exists
# @post: returns JSON with archive information
# @returns: JSON envelope with metadata
#
# Usage: tar_info archive.tar.gz
tar_info() {
    local archive="$1"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    local size mtime count format compression

    size=$(_archive_file_size "$archive")
    mtime=$(_archive_file_mtime "$archive")
    count=$(_archive_tar_count "$archive")

    case "$archive" in
        *.tar.gz|*.tgz)  compression="gzip"; format="tar.gz" ;;
        *.tar.bz2|*.tbz) compression="bzip2"; format="tar.bz2" ;;
        *.tar.xz|*.txz)  compression="xz"; format="tar.xz" ;;
        *.tar)           compression="none"; format="tar" ;;
        *)               compression="unknown"; format="unknown" ;;
    esac

    json_object "success:bool=true" "path=$archive" "format=$format" \
        "compression=$compression" "size:number=$size" \
        "file_count:number=$count" "mtime:number=$mtime"
}

# =============================================================================
# GZIP OPERATIONS
# =============================================================================

# Compress file with gzip
# @pre: input file exists
# @post: compressed file created (or replaced if --force)
# @returns: JSON envelope with success status
#
# Usage: gzip_compress file.txt
# Usage: gzip_compress file.txt output.gz
# Usage: gzip_compress file.txt --level 9
gzip_compress() {
    local input="$1"
    local output=""
    local level="$ARCHIVE_GZIP_LEVEL"
    shift

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --level|-l) level="$2"; shift 2 ;;
            --output|-o) output="$2"; shift 2 ;;
            *) output="$1"; shift ;;
        esac
    done

    # Contract: input must exist
    if [[ -z "$input" ]] || [[ ! -f "$input" ]]; then
        json_object "success:bool=false" "error=input file not found" \
            "path=${input:-}"
        return 1
    fi

    # Validate compression level
    if [[ ! "$level" =~ ^[1-9]$ ]]; then
        json_object "success:bool=false" "error=invalid compression level" \
            "level=$level" "suggestion=Use level 1-9"
        return 1
    fi

    # Default output path
    [[ -z "$output" ]] && output="${input}.gz"

    if gzip -c -"$level" "$input" > "$output" 2>/dev/null; then
        local input_size output_size ratio
        input_size=$(_archive_file_size "$input")
        output_size=$(_archive_file_size "$output")

        if [[ "$input_size" -gt 0 ]]; then
            ratio=$(awk "BEGIN {printf \"%.2f\", ($output_size / $input_size) * 100}")
        else
            ratio="0.00"
        fi

        json_object "success:bool=true" "input=$input" "output=$output" \
            "input_size:number=$input_size" "output_size:number=$output_size" \
            "ratio=$ratio%" "level:number=$level"
    else
        json_object "success:bool=false" "error=gzip compression failed" \
            "suggestion=Check input file and disk space"
        return 1
    fi
}

# Decompress gzip file
# @pre: input file exists and is gzip format
# @post: decompressed file created
# @returns: JSON envelope with success status
#
# Usage: gzip_decompress file.gz
# Usage: gzip_decompress file.gz output.txt
gzip_decompress() {
    local input="$1"
    local output="${2:-}"

    # Contract: input must exist
    if [[ -z "$input" ]] || [[ ! -f "$input" ]]; then
        json_object "success:bool=false" "error=input file not found" \
            "path=${input:-}"
        return 1
    fi

    # Default output: remove .gz extension
    if [[ -z "$output" ]]; then
        output="${input%.gz}"
        if [[ "$output" == "$input" ]]; then
            output="${input}.out"
        fi
    fi

    if gzip -cd "$input" > "$output" 2>/dev/null; then
        local input_size output_size
        input_size=$(_archive_file_size "$input")
        output_size=$(_archive_file_size "$output")

        json_object "success:bool=true" "input=$input" "output=$output" \
            "compressed_size:number=$input_size" "decompressed_size:number=$output_size"
    else
        json_object "success:bool=false" "error=gzip decompression failed" \
            "suggestion=File may not be valid gzip format"
        return 1
    fi
}

# Decompress .gz file in place
# @pre: input file exists and is gzip format
# @post: original .gz file replaced with decompressed content
# @returns: JSON envelope with success status
#
# Usage: gunzip_file file.gz
gunzip_file() {
    local input="$1"

    if [[ -z "$input" ]] || [[ ! -f "$input" ]]; then
        json_object "success:bool=false" "error=input file not found" \
            "path=${input:-}"
        return 1
    fi

    local output="${input%.gz}"
    if [[ "$output" == "$input" ]]; then
        json_object "success:bool=false" "error=file does not have .gz extension" \
            "path=$input"
        return 1
    fi

    local input_size
    input_size=$(_archive_file_size "$input")

    if gunzip -f "$input" 2>/dev/null; then
        local output_size
        output_size=$(_archive_file_size "$output")

        json_object "success:bool=true" "output=$output" \
            "compressed_size:number=$input_size" "decompressed_size:number=$output_size" \
            "action=decompressed_in_place"
    else
        json_object "success:bool=false" "error=gunzip failed" \
            "suggestion=File may not be valid gzip format"
        return 1
    fi
}

# Set/get gzip compression level
# @pre: level is 1-9 or empty (get current)
# @post: level set if provided
# @returns: JSON envelope with current level
#
# Usage: gzip_level          # Get current
# Usage: gzip_level 9        # Set to maximum
gzip_level() {
    local new_level="${1:-}"

    if [[ -z "$new_level" ]]; then
        json_object "success:bool=true" "level:number=$ARCHIVE_GZIP_LEVEL"
        return 0
    fi

    if [[ ! "$new_level" =~ ^[1-9]$ ]]; then
        json_object "success:bool=false" "error=invalid compression level" \
            "level=$new_level" "suggestion=Use level 1-9"
        return 1
    fi

    ARCHIVE_GZIP_LEVEL="$new_level"
    json_object "success:bool=true" "level:number=$ARCHIVE_GZIP_LEVEL" "action=set"
}

# Compress string with gzip
# @pre: string provided
# @post: returns base64-encoded compressed data
# @returns: JSON envelope with compressed data
#
# Usage: gzip_compress_string "hello world"
gzip_compress_string() {
    local input="$1"
    local level="${2:-$ARCHIVE_GZIP_LEVEL}"

    if [[ -z "$input" ]]; then
        json_object "success:bool=false" "error=input string required"
        return 1
    fi

    local compressed
    compressed=$(printf '%s' "$input" | gzip -c -"$level" 2>/dev/null | base64 | tr -d '\n')

    if [[ -n "$compressed" ]]; then
        local input_len="${#input}"
        local output_len="${#compressed}"
        json_object "success:bool=true" "data=$compressed" \
            "encoding=base64" "input_bytes:number=$input_len" \
            "output_bytes:number=$output_len"
    else
        json_object "success:bool=false" "error=compression failed"
        return 1
    fi
}

# Decompress base64-encoded gzip string
# @pre: base64 string provided
# @post: returns decompressed string
# @returns: JSON envelope with decompressed data
#
# Usage: gzip_decompress_string "H4sIAAAA..."
gzip_decompress_string() {
    local input="$1"

    if [[ -z "$input" ]]; then
        json_object "success:bool=false" "error=input string required"
        return 1
    fi

    local decompressed
    decompressed=$(printf '%s' "$input" | base64 -d 2>/dev/null | gzip -cd 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        json_object "success:bool=true" "data=$(_archive_escape "$decompressed")" \
            "bytes:number=${#decompressed}"
    else
        json_object "success:bool=false" "error=decompression failed" \
            "suggestion=Input may not be valid base64-encoded gzip"
        return 1
    fi
}

# =============================================================================
# ZIP OPERATIONS
# =============================================================================

# Create zip archive
# @pre: output path is writable, source paths exist
# @post: zip archive created
# @returns: JSON envelope with success status
#
# Usage: zip_create output.zip path1 [path2 ...]
# Usage: zip_create output.zip -r directory/
zip_create() {
    local output="$1"
    shift
    local -a paths=("$@")

    # Contract: need output and sources
    if [[ -z "$output" ]]; then
        json_object "success:bool=false" "error=output path required"
        return 1
    fi

    if [[ ${#paths[@]} -eq 0 ]]; then
        json_object "success:bool=false" "error=no source paths provided"
        return 1
    fi

    if ! _archive_has_zip; then
        json_object "success:bool=false" "error=zip command not found" \
            "suggestion=Install zip package"
        return 1
    fi

    # Verify sources exist
    local p
    for p in "${paths[@]}"; do
        # Skip flags like -r
        [[ "$p" == -* ]] && continue
        if [[ ! -e "$p" ]]; then
            json_object "success:bool=false" "error=source not found" "path=$p"
            return 1
        fi
    done

    local stderr_file
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/zip_err.XXXXXX")

    if zip -q "$output" "${paths[@]}" 2>"$stderr_file"; then
        local size count
        size=$(_archive_file_size "$output")
        count=$(unzip -l "$output" 2>/dev/null | tail -1 | awk '{print $2}')
        [[ -z "$count" || "$count" == "files" ]] && count=$(unzip -l "$output" 2>/dev/null | grep -c '^[ ]*[0-9]')

        rm -f "$stderr_file"
        json_object "success:bool=true" "path=$output" "size:number=$size" \
            "file_count:number=$count" "action=created"
    else
        local err_msg
        err_msg=$(<"$stderr_file")
        rm -f "$stderr_file"
        json_object "success:bool=false" "error=zip creation failed" \
            "stderr=$err_msg"
        return 1
    fi
}

# Extract zip archive
# @pre: archive exists, destination is writable
# @post: archive contents extracted
# @returns: JSON envelope with success status
#
# Usage: zip_extract archive.zip [destination]
zip_extract() {
    local archive="$1"
    local dest="${2:-.}"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    if ! _archive_has_unzip; then
        json_object "success:bool=false" "error=unzip command not found" \
            "suggestion=Install unzip package"
        return 1
    fi

    # Safety check
    if [[ "$ARCHIVE_SAFE_MODE" == "1" ]]; then
        if ! archive_path_safe "$archive"; then
            json_object "success:bool=false" "error=unsafe paths detected" \
                "path=$archive"
            return 1
        fi
    fi

    [[ ! -d "$dest" ]] && mkdir -p "$dest"

    local stderr_file
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/unzip_err.XXXXXX")

    if unzip -q -o "$archive" -d "$dest" 2>"$stderr_file"; then
        local count
        count=$(unzip -l "$archive" 2>/dev/null | tail -1 | awk '{print $2}')
        [[ -z "$count" || "$count" == "files" ]] && count=$(unzip -l "$archive" 2>/dev/null | grep -c '^[ ]*[0-9]')

        rm -f "$stderr_file"
        json_object "success:bool=true" "archive=$archive" "destination=$dest" \
            "file_count:number=$count" "action=extracted"
    else
        local err_msg
        err_msg=$(<"$stderr_file")
        rm -f "$stderr_file"
        json_object "success:bool=false" "error=unzip failed" "stderr=$err_msg"
        return 1
    fi
}

# List zip contents as JSON
# @pre: archive exists
# @post: returns JSON array of entries
# @returns: JSON envelope with file list
#
# Usage: zip_list archive.zip
zip_list() {
    local archive="$1"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    if ! _archive_has_unzip; then
        json_object "success:bool=false" "error=unzip command not found"
        return 1
    fi

    local -a entries=()
    local line

    while IFS= read -r line; do
        # unzip -l output: Length Date Time Name
        # Skip header and footer lines
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+ ]]; then
            local name
            name=$(echo "$line" | awk '{print $4}')
            [[ -n "$name" ]] && entries+=("$name")
        fi
    done < <(unzip -l "$archive" 2>/dev/null)

    local files_json
    files_json=$(json_array "${entries[@]}")

    json_object "success:bool=true" "archive=$archive" \
        "count:number=${#entries[@]}" "files:raw=$files_json"
}

# Add files to existing zip
# @pre: archive exists, files exist
# @post: files added to archive
# @returns: JSON envelope with success status
#
# Usage: zip_add archive.zip file1 [file2 ...]
zip_add() {
    local archive="$1"
    shift
    local -a files=("$@")

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        json_object "success:bool=false" "error=no files to add"
        return 1
    fi

    if ! _archive_has_zip; then
        json_object "success:bool=false" "error=zip command not found"
        return 1
    fi

    # Verify files
    local f
    for f in "${files[@]}"; do
        if [[ ! -e "$f" ]]; then
            json_object "success:bool=false" "error=file not found" "path=$f"
            return 1
        fi
    done

    if zip -q "$archive" "${files[@]}" 2>/dev/null; then
        local size
        size=$(_archive_file_size "$archive")
        json_object "success:bool=true" "archive=$archive" \
            "added:number=${#files[@]}" "size:number=$size"
    else
        json_object "success:bool=false" "error=zip add failed"
        return 1
    fi
}

# Remove file from zip
# @pre: archive exists, file path is in archive
# @post: file removed from archive
# @returns: JSON envelope with success status
#
# Usage: zip_remove archive.zip path/in/archive
zip_remove() {
    local archive="$1"
    local file_path="$2"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    if [[ -z "$file_path" ]]; then
        json_object "success:bool=false" "error=file path required"
        return 1
    fi

    if ! _archive_has_zip; then
        json_object "success:bool=false" "error=zip command not found"
        return 1
    fi

    if zip -dq "$archive" "$file_path" 2>/dev/null; then
        json_object "success:bool=true" "archive=$archive" \
            "removed=$file_path" "action=removed"
    else
        json_object "success:bool=false" "error=zip remove failed" \
            "file=$file_path" "suggestion=File may not exist in archive"
        return 1
    fi
}

# Create password-protected zip
# @pre: output path writable, sources exist, password provided
# @post: encrypted zip created
# @returns: JSON envelope with success status
#
# Usage: zip_password output.zip password path1 [path2 ...]
zip_password() {
    local output="$1"
    local password="$2"
    shift 2
    local -a paths=("$@")

    if [[ -z "$output" ]]; then
        json_object "success:bool=false" "error=output path required"
        return 1
    fi

    if [[ -z "$password" ]]; then
        json_object "success:bool=false" "error=password required"
        return 1
    fi

    if [[ ${#paths[@]} -eq 0 ]]; then
        json_object "success:bool=false" "error=no source paths provided"
        return 1
    fi

    if ! _archive_has_zip; then
        json_object "success:bool=false" "error=zip command not found"
        return 1
    fi

    if zip -q -P "$password" "$output" "${paths[@]}" 2>/dev/null; then
        local size
        size=$(_archive_file_size "$output")
        json_object "success:bool=true" "path=$output" "size:number=$size" \
            "encrypted:bool=true" "action=created"
    else
        json_object "success:bool=false" "error=zip creation failed"
        return 1
    fi
}

# Test zip integrity
# @pre: archive exists
# @post: integrity verified
# @returns: JSON envelope with test result
#
# Usage: zip_test archive.zip
zip_test() {
    local archive="$1"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    if ! _archive_has_unzip; then
        json_object "success:bool=false" "error=unzip command not found"
        return 1
    fi

    local stderr_file
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/unzip_test.XXXXXX")

    if unzip -t "$archive" >"$stderr_file" 2>&1; then
        rm -f "$stderr_file"
        json_object "success:bool=true" "archive=$archive" \
            "valid:bool=true" "action=tested"
    else
        local err_msg
        err_msg=$(<"$stderr_file")
        rm -f "$stderr_file"
        json_object "success:bool=false" "archive=$archive" \
            "valid:bool=false" "error=$err_msg"
        return 1
    fi
}

# =============================================================================
# ARCHIVE UTILITIES
# =============================================================================

# Detect archive type by magic bytes/extension
# @pre: path provided (file or string with extension)
# @post: returns detected format
# @returns: JSON envelope with format info
#
# Usage: archive_detect_type file.tar.gz
# Usage: archive_detect_type unknown_file
archive_detect_type() {
    local path="$1"

    if [[ -z "$path" ]]; then
        json_object "success:bool=false" "error=path required"
        return 1
    fi

    local format="unknown"
    local compression="unknown"

    # First try by extension
    case "$path" in
        *.tar.gz|*.tgz)   format="tar"; compression="gzip" ;;
        *.tar.bz2|*.tbz)  format="tar"; compression="bzip2" ;;
        *.tar.xz|*.txz)   format="tar"; compression="xz" ;;
        *.tar)            format="tar"; compression="none" ;;
        *.gz)             format="gzip"; compression="gzip" ;;
        *.bz2)            format="bzip2"; compression="bzip2" ;;
        *.xz)             format="xz"; compression="xz" ;;
        *.zip)            format="zip"; compression="deflate" ;;
        *.7z)             format="7z"; compression="lzma" ;;
        *.rar)            format="rar"; compression="rar" ;;
    esac

    # If file exists, check magic bytes
    if [[ -f "$path" && "$format" == "unknown" ]]; then
        local magic
        magic=$(head -c 6 "$path" 2>/dev/null | od -An -tx1 | tr -d ' ')

        case "$magic" in
            1f8b*)          format="gzip"; compression="gzip" ;;
            504b0304*)      format="zip"; compression="deflate" ;;
            425a*)          format="bzip2"; compression="bzip2" ;;
            fd377a585a00*)  format="xz"; compression="xz" ;;
            526172211a07*)  format="rar"; compression="rar" ;;
            377abcaf271c*)  format="7z"; compression="lzma" ;;
        esac

        # Check for tar (may be inside gzip)
        if [[ "$format" == "gzip" ]]; then
            local inner_magic
            inner_magic=$(gzip -cd "$path" 2>/dev/null | head -c 262 | tail -c 5 | od -An -tx1 | tr -d ' ')
            if [[ "$inner_magic" == "7573746172" ]]; then  # "ustar"
                format="tar"
            fi
        fi
    fi

    json_object "success:bool=true" "path=$path" "format=$format" \
        "compression=$compression"
}

# Auto-detect and extract any archive type
# @pre: archive exists
# @post: archive extracted to destination
# @returns: JSON envelope with success status
#
# Usage: archive_extract_auto archive.??? [destination]
archive_extract_auto() {
    local archive="$1"
    local dest="${2:-.}"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    # Detect type
    local type_info format compression
    type_info=$(archive_detect_type "$archive")
    format=$(echo "$type_info" | grep -o '"format":"[^"]*"' | cut -d'"' -f4)
    compression=$(echo "$type_info" | grep -o '"compression":"[^"]*"' | cut -d'"' -f4)

    case "$format" in
        tar)
            tar_extract "$archive" "$dest"
            ;;
        zip)
            zip_extract "$archive" "$dest"
            ;;
        gzip)
            local output="${archive%.gz}"
            [[ "$output" == "$archive" ]] && output="${archive}.out"
            gzip_decompress "$archive" "$dest/$output"
            ;;
        *)
            json_object "success:bool=false" "error=unsupported format" \
                "format=$format" "suggestion=Use tar_extract or zip_extract"
            return 1
            ;;
    esac
}

# Get estimated uncompressed size
# @pre: archive exists
# @post: returns size estimate
# @returns: JSON envelope with size info
#
# Usage: archive_size archive.tar.gz
archive_size() {
    local archive="$1"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    local compressed_size uncompressed_size format
    compressed_size=$(_archive_file_size "$archive")
    uncompressed_size=0

    # Detect format and get uncompressed size
    case "$archive" in
        *.tar.gz|*.tgz)
            # gzip stores original size in last 4 bytes (mod 2^32)
            if _archive_has_gzip; then
                uncompressed_size=$(gzip -l "$archive" 2>/dev/null | tail -1 | awk '{print $2}')
            fi
            format="tar.gz"
            ;;
        *.gz)
            if _archive_has_gzip; then
                uncompressed_size=$(gzip -l "$archive" 2>/dev/null | tail -1 | awk '{print $2}')
            fi
            format="gzip"
            ;;
        *.zip)
            if _archive_has_unzip; then
                uncompressed_size=$(unzip -l "$archive" 2>/dev/null | tail -1 | awk '{print $1}')
            fi
            format="zip"
            ;;
        *.tar)
            uncompressed_size=$compressed_size
            format="tar"
            ;;
        *)
            format="unknown"
            ;;
    esac

    [[ -z "$uncompressed_size" || "$uncompressed_size" == "0" ]] && uncompressed_size=$compressed_size

    json_object "success:bool=true" "path=$archive" "format=$format" \
        "compressed_size:number=$compressed_size" \
        "uncompressed_size:number=$uncompressed_size"
}

# Calculate compression ratio
# @pre: archive exists
# @post: returns ratio percentage
# @returns: JSON envelope with ratio
#
# Usage: archive_compress_ratio archive.tar.gz
archive_compress_ratio() {
    local archive="$1"

    local size_info compressed uncompressed
    size_info=$(archive_size "$archive")

    if echo "$size_info" | grep -q '"success":false'; then
        echo "$size_info"
        return 1
    fi

    compressed=$(echo "$size_info" | grep -o '"compressed_size":[0-9]*' | cut -d':' -f2)
    uncompressed=$(echo "$size_info" | grep -o '"uncompressed_size":[0-9]*' | cut -d':' -f2)

    local ratio savings
    if [[ "$uncompressed" -gt 0 ]]; then
        ratio=$(awk "BEGIN {printf \"%.2f\", ($compressed / $uncompressed) * 100}")
        savings=$(awk "BEGIN {printf \"%.2f\", 100 - ($compressed / $uncompressed) * 100}")
    else
        ratio="100.00"
        savings="0.00"
    fi

    json_object "success:bool=true" "path=$archive" \
        "compressed:number=$compressed" "uncompressed:number=$uncompressed" \
        "ratio=$ratio%" "savings=$savings%"
}

# Verify archive integrity
# @pre: archive exists
# @post: returns integrity status
# @returns: JSON envelope with verification result
#
# Usage: archive_verify archive.tar.gz
archive_verify() {
    local archive="$1"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    local valid="true"
    local format error_msg=""

    case "$archive" in
        *.tar.gz|*.tgz)
            format="tar.gz"
            if ! gzip -t "$archive" 2>/dev/null; then
                valid="false"
                error_msg="gzip checksum failed"
            elif ! tar -tzf "$archive" >/dev/null 2>&1; then
                valid="false"
                error_msg="tar structure invalid"
            fi
            ;;
        *.tar.bz2|*.tbz)
            format="tar.bz2"
            if ! bzip2 -t "$archive" 2>/dev/null; then
                valid="false"
                error_msg="bzip2 checksum failed"
            fi
            ;;
        *.tar)
            format="tar"
            if ! tar -tf "$archive" >/dev/null 2>&1; then
                valid="false"
                error_msg="tar structure invalid"
            fi
            ;;
        *.gz)
            format="gzip"
            if ! gzip -t "$archive" 2>/dev/null; then
                valid="false"
                error_msg="gzip checksum failed"
            fi
            ;;
        *.zip)
            format="zip"
            if ! unzip -t "$archive" >/dev/null 2>&1; then
                valid="false"
                error_msg="zip CRC check failed"
            fi
            ;;
        *)
            format="unknown"
            valid="unknown"
            ;;
    esac

    if [[ "$valid" == "true" ]]; then
        json_object "success:bool=true" "path=$archive" "format=$format" \
            "valid:bool=true"
    else
        json_object "success:bool=false" "path=$archive" "format=$format" \
            "valid:bool=false" "error=$error_msg"
        return 1
    fi
}

# Convert archive listing to JSON
# @pre: archive exists
# @post: returns detailed JSON listing
# @returns: JSON envelope with file details
#
# Usage: archive_to_json archive.tar.gz
archive_to_json() {
    local archive="$1"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        json_object "success:bool=false" "error=archive not found" \
            "path=${archive:-}"
        return 1
    fi

    local entries_json="["
    local first=true
    local line

    case "$archive" in
        *.tar*|*.tgz|*.tbz|*.txz)
            local compress_flag=""
            case "$archive" in
                *.tar.gz|*.tgz)  compress_flag="-z" ;;
                *.tar.bz2|*.tbz) compress_flag="-j" ;;
                *.tar.xz|*.txz)  compress_flag="-J" ;;
            esac

            while IFS= read -r line; do
                # Parse: -rw-r--r-- user/group size date time name
                local perms size name
                perms=$(echo "$line" | awk '{print $1}')
                size=$(echo "$line" | awk '{print $3}')
                name=$(echo "$line" | awk '{print $6}')

                [[ -z "$name" ]] && continue

                $first || entries_json+=","
                first=false

                entries_json+="{\"name\":\"$(_archive_escape "$name")\""
                entries_json+=",\"size\":$size"
                entries_json+=",\"permissions\":\"$perms\"}"
            done < <(tar $compress_flag -tvf "$archive" 2>/dev/null)
            ;;
        *.zip)
            while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]]*([0-9]+) ]]; then
                    local size name
                    size=$(echo "$line" | awk '{print $1}')
                    name=$(echo "$line" | awk '{print $4}')

                    [[ -z "$name" || "$name" == "Name" ]] && continue

                    $first || entries_json+=","
                    first=false

                    entries_json+="{\"name\":\"$(_archive_escape "$name")\""
                    entries_json+=",\"size\":$size}"
                fi
            done < <(unzip -l "$archive" 2>/dev/null)
            ;;
    esac

    entries_json+="]"

    local count
    count=$(echo "$entries_json" | grep -o '"name"' | wc -l | tr -d ' ')

    printf '{"success":true,"path":"%s","count":%d,"entries":%s}' \
        "$(_archive_escape "$archive")" "$count" "$entries_json"
}

# =============================================================================
# STREAMING OPERATIONS
# =============================================================================

# Create tarball and stream to stdout
# @pre: source paths exist
# @post: tar data written to stdout
# @returns: exit code (use stderr for errors)
#
# Usage: tar_stream_create path1 [path2 ...] | other_command
# Usage: tar_stream_create path1 --gzip | other_command
tar_stream_create() {
    local -a paths=()
    local compress=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gzip|-z) compress="-z"; shift ;;
            --bzip2|-j) compress="-j"; shift ;;
            --xz|-J) compress="-J"; shift ;;
            *) paths+=("$1"); shift ;;
        esac
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
        echo '{"error":"no paths provided"}' >&2
        return 1
    fi

    tar $compress -cf - "${paths[@]}" 2>/dev/null
}

# Extract tarball from stdin
# @pre: stdin contains tar data
# @post: files extracted to destination
# @returns: JSON envelope with success status
#
# Usage: cat archive.tar | tar_stream_extract [destination]
# Usage: some_command | tar_stream_extract --gzip /tmp/dest
tar_stream_extract() {
    local dest="."
    local compress=""
    local destination_seen=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gzip|-z) compress="-z"; shift ;;
            --bzip2|-j) compress="-j"; shift ;;
            --xz|-J) compress="-J"; shift ;;
            --help|-h)
                printf 'Usage: tar_stream_extract [--gzip|--bzip2|--xz] [destination]\n'
                return 0
                ;;
            --)
                shift
                if [[ $# -gt 1 ]]; then
                    echo '{"error":"multiple destinations provided"}' >&2
                    return 1
                fi
                if [[ $# -eq 1 ]]; then
                    dest="$1"
                    destination_seen=1
                    shift
                fi
                ;;
            -*)
                echo '{"error":"unsupported stream extraction option"}' >&2
                return 1
                ;;
            *)
                if [[ $destination_seen -eq 1 ]]; then
                    echo '{"error":"multiple destinations provided"}' >&2
                    return 1
                fi
                dest="$1"
                destination_seen=1
                shift
                ;;
        esac
    done

    [[ ! -d "$dest" ]] && mkdir -p "$dest"

    if tar $compress -xf - -C "$dest" 2>/dev/null; then
        json_object "success:bool=true" "destination=$dest" "action=extracted"
    else
        json_object "success:bool=false" "error=stream extraction failed"
        return 1
    fi
}

# Compress/decompress stream with gzip
# @pre: stdin contains data
# @post: compressed/decompressed data on stdout
# @returns: exit code
#
# Usage: cat file | gzip_stream compress
# Usage: cat file.gz | gzip_stream decompress
gzip_stream() {
    local mode="${1:-compress}"
    local level="${2:-$ARCHIVE_GZIP_LEVEL}"

    case "$mode" in
        compress|c)
            gzip -c -"$level" 2>/dev/null
            ;;
        decompress|d)
            gzip -cd 2>/dev/null
            ;;
        *)
            echo '{"error":"unknown mode, use compress or decompress"}' >&2
            return 1
            ;;
    esac
}

# =============================================================================
# SAFETY FUNCTIONS
# =============================================================================

# Check archive for path traversal vulnerabilities
# @pre: archive exists
# @post: returns safety status
# @returns: 0 if safe, 1 if unsafe paths detected
#
# Usage: archive_path_safe archive.tar.gz && echo "safe"
archive_path_safe() {
    local archive="$1"

    if [[ -z "$archive" ]] || [[ ! -f "$archive" ]]; then
        return 1
    fi

    local unsafe_found=0

    case "$archive" in
        *.tar*|*.tgz|*.tbz|*.txz)
            local compress_flag=""
            case "$archive" in
                *.tar.gz|*.tgz)  compress_flag="-z" ;;
                *.tar.bz2|*.tbz) compress_flag="-j" ;;
                *.tar.xz|*.txz)  compress_flag="-J" ;;
            esac

            # Check for .. or absolute paths
            if tar $compress_flag -tf "$archive" 2>/dev/null | grep -qE '^/|\.\.'; then
                unsafe_found=1
            fi
            ;;
        *.zip)
            if unzip -l "$archive" 2>/dev/null | grep -qE '^/|\.\.'; then
                unsafe_found=1
            fi
            ;;
    esac

    [[ $unsafe_found -eq 0 ]]
}

# Enforce maximum extraction size limit
# @pre: archive exists
# @post: returns whether size is within limit
# @returns: JSON envelope with size check result
#
# Usage: archive_size_limit archive.tar.gz [max_bytes]
archive_size_limit() {
    local archive="$1"
    local max_size="${2:-$ARCHIVE_MAX_SIZE}"

    local size_info uncompressed
    size_info=$(archive_size "$archive")

    if echo "$size_info" | grep -q '"success":false'; then
        echo "$size_info"
        return 1
    fi

    uncompressed=$(echo "$size_info" | grep -o '"uncompressed_size":[0-9]*' | cut -d':' -f2)

    if [[ "$uncompressed" -gt "$max_size" ]]; then
        json_object "success:bool=false" "path=$archive" \
            "uncompressed_size:number=$uncompressed" \
            "max_allowed:number=$max_size" \
            "error=archive exceeds size limit" \
            "suggestion=Increase ARCHIVE_MAX_SIZE or use smaller archive"
        return 1
    fi

    json_object "success:bool=true" "path=$archive" \
        "uncompressed_size:number=$uncompressed" \
        "max_allowed:number=$max_size" "within_limit:bool=true"
}

# Exclude files by pattern when creating archive
# @pre: patterns provided
# @post: returns tar exclude arguments
# @returns: exclude flags for tar command
#
# Usage: tar_flags=$(archive_exclude_pattern "*.log" "*.tmp")
#        tar -cf out.tar $tar_flags ./src
archive_exclude_pattern() {
    local -a patterns=("$@")
    local -a excludes=()

    for pattern in "${patterns[@]}"; do
        excludes+=("--exclude=$pattern")
    done

    printf '%s\n' "${excludes[@]}"
}

# =============================================================================
# NAMEREF VARIANTS (High Performance)
# =============================================================================

# Store tar_list result in variable
# @pre: archive exists
# @post: result stored in named variable
#
# Usage: tar_list_v result archive.tar
tar_list_v() {
    local -n __tlv_out=$1
    local archive="$2"

    __tlv_out=$(tar_list "$archive")
}

# Store tar_info result in variable
# @pre: archive exists
# @post: result stored in named variable
#
# Usage: tar_info_v result archive.tar.gz
tar_info_v() {
    local -n __tiv_out=$1
    local archive="$2"

    __tiv_out=$(tar_info "$archive")
}

# Store archive_detect_type result in variable
# @pre: path provided
# @post: result stored in named variable
#
# Usage: archive_detect_type_v result file.???
archive_detect_type_v() {
    local -n __adtv_out=$1
    local path="$2"

    __adtv_out=$(archive_detect_type "$path")
}

# Store archive_size result in variable
# @pre: archive exists
# @post: result stored in named variable
#
# Usage: archive_size_v result archive.tar.gz
archive_size_v() {
    local -n __asv_out=$1
    local archive="$2"

    __asv_out=$(archive_size "$archive")
}

# =============================================================================
# CHECK TOOLS AVAILABILITY
# =============================================================================

# Check available archive tools
# @pre: none
# @post: returns JSON with tool availability
# @returns: JSON envelope with tool status
#
# Usage: archive_check_tools
archive_check_tools() {
    local tar_ok gzip_ok zip_ok unzip_ok

    _archive_has_tar && tar_ok="true" || tar_ok="false"
    _archive_has_gzip && gzip_ok="true" || gzip_ok="false"
    _archive_has_zip && zip_ok="true" || zip_ok="false"
    _archive_has_unzip && unzip_ok="true" || unzip_ok="false"

    json_object "success:bool=true" \
        "tar:bool=$tar_ok" \
        "gzip:bool=$gzip_ok" \
        "zip:bool=$zip_ok" \
        "unzip:bool=$unzip_ok"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_ARCHIVE_EXPORTS=(
    # TAR operations
    tar_create
    tar_extract
    tar_list
    tar_append
    tar_extract_file
    tar_info
    # GZIP operations
    gzip_compress
    gzip_decompress
    gunzip_file
    gzip_level
    gzip_compress_string
    gzip_decompress_string
    # ZIP operations
    zip_create
    zip_extract
    zip_list
    zip_add
    zip_remove
    zip_password
    zip_test
    # Archive utilities
    archive_detect_type
    archive_extract_auto
    archive_size
    archive_compress_ratio
    archive_verify
    archive_to_json
    # Streaming
    tar_stream_create
    tar_stream_extract
    gzip_stream
    # Safety
    archive_path_safe
    archive_size_limit
    archive_exclude_pattern
    # Nameref variants
    tar_list_v
    tar_info_v
    archive_detect_type_v
    archive_size_v
    # Tools check
    archive_check_tools
)

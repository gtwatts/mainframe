#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/download.sh - Universal Download Helper
# =============================================================================
# Description: Universal download helper with multiple backend support and
#              fallback chain: burl -> curl -> wget -> fetch (BSD)
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_DOWNLOAD_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DOWNLOAD_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly DOWNLOAD_DEFAULT_TIMEOUT=30
readonly DOWNLOAD_DEFAULT_RETRIES=3
readonly DOWNLOAD_DEFAULT_PARALLEL=4

# Cached backend (set on first detection)
_DOWNLOAD_BACKEND=""

# =============================================================================
# BACKEND DETECTION
# =============================================================================

# @idempotent Check which download tool is available
# @return "burl", "curl", "wget", "fetch", or "none"
# Priority: burl (MAINFRAME native) -> curl -> wget -> fetch
download_backend() {
    # Return cached result if available
    if [[ -n "$_DOWNLOAD_BACKEND" ]]; then
        printf '%s' "$_DOWNLOAD_BACKEND"
        return 0
    fi

    # Check for burl (MAINFRAME native HTTP library)
    # burl is part of MAINFRAME's http.sh and provides pure bash HTTP
    if declare -F http_get &>/dev/null; then
        _DOWNLOAD_BACKEND="burl"
    elif command -v curl &>/dev/null; then
        _DOWNLOAD_BACKEND="curl"
    elif command -v wget &>/dev/null; then
        _DOWNLOAD_BACKEND="wget"
    elif command -v fetch &>/dev/null; then
        _DOWNLOAD_BACKEND="fetch"
    else
        _DOWNLOAD_BACKEND="none"
    fi

    printf '%s' "$_DOWNLOAD_BACKEND"
}

# Reset backend cache (useful for testing)
_download_reset_backend() {
    _DOWNLOAD_BACKEND=""
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Parse options JSON string
# Usage: _download_parse_options '{"timeout":30,"retries":3}'
# Sets: _DL_TIMEOUT, _DL_RETRIES, _DL_QUIET
_download_parse_options() {
    local opts="${1:-}"

    # Defaults
    _DL_TIMEOUT="$DOWNLOAD_DEFAULT_TIMEOUT"
    _DL_RETRIES="$DOWNLOAD_DEFAULT_RETRIES"
    _DL_QUIET=0

    if [[ -z "$opts" ]]; then
        return 0
    fi

    # Parse JSON options using json_get if available, otherwise regex
    if declare -F json_get &>/dev/null; then
        local val
        val=$(json_get "$opts" "timeout" 2>/dev/null)
        [[ -n "$val" && "$val" != "null" ]] && _DL_TIMEOUT="$val"

        val=$(json_get "$opts" "retries" 2>/dev/null)
        [[ -n "$val" && "$val" != "null" ]] && _DL_RETRIES="$val"

        val=$(json_get "$opts" "quiet" 2>/dev/null)
        [[ "$val" == "true" ]] && _DL_QUIET=1
    else
        # Fallback: simple regex extraction
        if [[ "$opts" =~ \"timeout\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            _DL_TIMEOUT="${BASH_REMATCH[1]}"
        fi
        if [[ "$opts" =~ \"retries\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            _DL_RETRIES="${BASH_REMATCH[1]}"
        fi
        if [[ "$opts" =~ \"quiet\"[[:space:]]*:[[:space:]]*true ]]; then
            _DL_QUIET=1
        fi
    fi
}

# Get filename from URL
# Usage: _download_filename_from_url "http://example.com/path/file.tar.gz"
_download_filename_from_url() {
    local url="$1"
    local filename

    # Remove query string and fragment
    filename="${url%%\?*}"
    filename="${filename%%#*}"

    # Extract basename
    filename="${filename##*/}"

    # Default to "download" if empty
    [[ -z "$filename" ]] && filename="download"

    printf '%s' "$filename"
}

# Get current time in milliseconds
_download_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        local seconds="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        frac="${frac}000"
        printf '%s%s' "$seconds" "${frac:0:3}"
    else
        local ns
        ns=$(date +%s%N 2>/dev/null)
        if [[ "$ns" =~ ^[0-9]+$ && ${#ns} -gt 6 ]]; then
            printf '%s' "${ns:0:${#ns}-6}"
        else
            printf '%s000' "$(date +%s)"
        fi
    fi
}

# =============================================================================
# BACKEND IMPLEMENTATIONS
# =============================================================================

# Internal: curl backend
# @param $1 - URL
# @param $2 - output file
# @param $3 - timeout
# @param $4 - quiet (0/1)
# @return exit code
_download_curl() {
    local url="$1"
    local output="$2"
    local timeout="$3"
    local quiet="$4"

    local -a curl_opts=(
        --fail
        --location
        --max-time "$timeout"
        --output "$output"
    )

    [[ "$quiet" -eq 1 ]] && curl_opts+=(--silent --show-error)

    curl "${curl_opts[@]}" "$url"
}

# Internal: curl backend (to stdout)
_download_curl_stdout() {
    local url="$1"
    local timeout="$2"

    curl --fail --location --max-time "$timeout" --silent "$url"
}

# Internal: curl backend (with progress callback)
_download_curl_progress() {
    local url="$1"
    local output="$2"
    local timeout="$3"
    local callback="$4"

    # Use curl's progress meter and parse it
    curl --fail --location --max-time "$timeout" \
        --progress-bar --output "$output" "$url" 2>&1 | \
    while IFS= read -r line; do
        # Parse curl progress output
        if [[ "$line" =~ ([0-9]+)% ]]; then
            local percent="${BASH_REMATCH[1]}"
            if [[ -n "$callback" ]]; then
                "$callback" "{\"percent\":$percent,\"url\":\"$url\"}"
            fi
        fi
    done

    return "${PIPESTATUS[0]}"
}

# Internal: curl backend (resume)
_download_curl_resume() {
    local url="$1"
    local output="$2"
    local timeout="$3"

    curl --fail --location --max-time "$timeout" \
        --continue-at - --output "$output" --silent --show-error "$url"
}

# Internal: wget backend
# @param $1 - URL
# @param $2 - output file
# @param $3 - timeout
# @param $4 - quiet (0/1)
# @return exit code
_download_wget() {
    local url="$1"
    local output="$2"
    local timeout="$3"
    local quiet="$4"

    local -a wget_opts=(
        --timeout="$timeout"
        --output-document="$output"
        --tries=1
    )

    [[ "$quiet" -eq 1 ]] && wget_opts+=(--quiet)

    wget "${wget_opts[@]}" "$url"
}

# Internal: wget backend (to stdout)
_download_wget_stdout() {
    local url="$1"
    local timeout="$2"

    wget --timeout="$timeout" --quiet --output-document=- "$url"
}

# Internal: wget backend (resume)
_download_wget_resume() {
    local url="$1"
    local output="$2"
    local timeout="$3"

    wget --timeout="$timeout" --continue --output-document="$output" --quiet "$url"
}

# Internal: burl backend (MAINFRAME native http.sh)
# @param $1 - URL
# @param $2 - output file
# @param $3 - timeout
# @param $4 - quiet (0/1)
# @return exit code
_download_burl() {
    local url="$1"
    local output="$2"
    local timeout="$3"
    local quiet="$4"

    # Set timeout for HTTP library
    local old_timeout="${HTTP_TIMEOUT:-}"
    HTTP_TIMEOUT="$timeout"

    local response
    response=$(http_get "$url" 2>/dev/null)
    local rc=$?

    # Restore timeout
    HTTP_TIMEOUT="$old_timeout"

    if [[ $rc -eq 0 ]] && http_is_success "$response" 2>/dev/null; then
        http_body "$response" > "$output"
        return 0
    fi

    return 1
}

# Internal: burl backend (to stdout)
_download_burl_stdout() {
    local url="$1"
    local timeout="$2"

    local old_timeout="${HTTP_TIMEOUT:-}"
    HTTP_TIMEOUT="$timeout"

    local response
    response=$(http_get "$url" 2>/dev/null)
    local rc=$?

    HTTP_TIMEOUT="$old_timeout"

    if [[ $rc -eq 0 ]] && http_is_success "$response" 2>/dev/null; then
        http_body "$response"
        return 0
    fi

    return 1
}

# Internal: fetch backend (BSD)
# @param $1 - URL
# @param $2 - output file
# @param $3 - timeout
# @param $4 - quiet (0/1)
# @return exit code
_download_fetch() {
    local url="$1"
    local output="$2"
    local timeout="$3"
    local quiet="$4"

    local -a fetch_opts=(
        --timeout "$timeout"
        --output "$output"
    )

    [[ "$quiet" -eq 1 ]] && fetch_opts+=(--quiet)

    fetch "${fetch_opts[@]}" "$url"
}

# Internal: fetch backend (to stdout)
_download_fetch_stdout() {
    local url="$1"
    local timeout="$2"

    fetch --timeout "$timeout" --quiet --output - "$url"
}

# =============================================================================
# PUBLIC API
# =============================================================================

# Download file from URL
# @param $1 - URL
# @param $2 - output file (optional, uses remote filename if omitted)
# @param $3 - options JSON (optional): {"timeout":30,"retries":3,"quiet":true}
# @return {"ok":true,"file":"path","size":N,"time_ms":N}
download() {
    local url="$1"
    local output="${2:-}"
    local options="${3:-}"

    # Validate URL
    if [[ -z "$url" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=URL required"
        else
            printf '{"ok":false,"error":"URL required"}'
        fi
        return 1
    fi

    # Determine output filename
    if [[ -z "$output" ]]; then
        output=$(_download_filename_from_url "$url")
    fi

    # Parse options
    _download_parse_options "$options"

    # Detect backend
    local backend
    backend=$(download_backend)

    if [[ "$backend" == "none" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=No download tool available (need curl, wget, or fetch)"
        else
            printf '{"ok":false,"error":"No download tool available"}'
        fi
        return 1
    fi

    # Start timing
    local start_ms end_ms duration_ms
    start_ms=$(_download_now_ms)

    # Download with retry
    local attempt=1
    local rc=1

    while [[ $attempt -le $_DL_RETRIES ]]; do
        case "$backend" in
            burl)
                _download_burl "$url" "$output" "$_DL_TIMEOUT" "$_DL_QUIET"
                rc=$?
                ;;
            curl)
                _download_curl "$url" "$output" "$_DL_TIMEOUT" "$_DL_QUIET"
                rc=$?
                ;;
            wget)
                _download_wget "$url" "$output" "$_DL_TIMEOUT" "$_DL_QUIET"
                rc=$?
                ;;
            fetch)
                _download_fetch "$url" "$output" "$_DL_TIMEOUT" "$_DL_QUIET"
                rc=$?
                ;;
        esac

        [[ $rc -eq 0 ]] && break

        ((attempt++))
        if [[ $attempt -le $_DL_RETRIES ]]; then
            sleep 1
        fi
    done

    # Calculate duration
    end_ms=$(_download_now_ms)
    duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    # Build response
    if [[ $rc -eq 0 && -f "$output" ]]; then
        local size
        if [[ "$OSTYPE" == darwin* ]]; then
            size=$(stat -f%z "$output" 2>/dev/null || echo 0)
        else
            size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        fi

        if declare -F json_object &>/dev/null; then
            json_object \
                "ok:bool=true" \
                "file=$output" \
                "size:number=$size" \
                "time_ms:number=$duration_ms" \
                "backend=$backend"
        else
            printf '{"ok":true,"file":"%s","size":%d,"time_ms":%d,"backend":"%s"}' \
                "$output" "$size" "$duration_ms" "$backend"
        fi
        return 0
    else
        if declare -F json_object &>/dev/null; then
            json_object \
                "ok:bool=false" \
                "error=Download failed after $_DL_RETRIES attempts" \
                "url=$url" \
                "backend=$backend"
        else
            printf '{"ok":false,"error":"Download failed","url":"%s"}' "$url"
        fi
        return 1
    fi
}

# Download to stdout
# @param $1 - URL
# @return File contents to stdout
download_stdout() {
    local url="$1"

    if [[ -z "$url" ]]; then
        printf 'Error: URL required\n' >&2
        return 1
    fi

    local backend
    backend=$(download_backend)

    case "$backend" in
        burl)
            _download_burl_stdout "$url" "$DOWNLOAD_DEFAULT_TIMEOUT"
            ;;
        curl)
            _download_curl_stdout "$url" "$DOWNLOAD_DEFAULT_TIMEOUT"
            ;;
        wget)
            _download_wget_stdout "$url" "$DOWNLOAD_DEFAULT_TIMEOUT"
            ;;
        fetch)
            _download_fetch_stdout "$url" "$DOWNLOAD_DEFAULT_TIMEOUT"
            ;;
        none)
            printf 'Error: No download tool available\n' >&2
            return 1
            ;;
    esac
}

# Download with progress
# @param $1 - URL
# @param $2 - output file
# @param $3 - callback function (receives progress JSON)
download_progress() {
    local url="$1"
    local output="$2"
    local callback="${3:-}"

    if [[ -z "$url" || -z "$output" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=URL and output file required"
        else
            printf '{"ok":false,"error":"URL and output file required"}'
        fi
        return 1
    fi

    local backend
    backend=$(download_backend)

    local start_ms end_ms duration_ms
    start_ms=$(_download_now_ms)

    local rc=1
    case "$backend" in
        curl)
            if [[ -n "$callback" ]]; then
                _download_curl_progress "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT" "$callback"
            else
                _download_curl "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT" 0
            fi
            rc=$?
            ;;
        wget|burl|fetch)
            # Progress not well supported, fall back to regular download
            download "$url" "$output"
            return $?
            ;;
        none)
            if declare -F json_object &>/dev/null; then
                json_object "ok:bool=false" "error=No download tool available"
            else
                printf '{"ok":false,"error":"No download tool available"}'
            fi
            return 1
            ;;
    esac

    end_ms=$(_download_now_ms)
    duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    if [[ $rc -eq 0 && -f "$output" ]]; then
        local size
        if [[ "$OSTYPE" == darwin* ]]; then
            size=$(stat -f%z "$output" 2>/dev/null || echo 0)
        else
            size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        fi

        if declare -F json_object &>/dev/null; then
            json_object \
                "ok:bool=true" \
                "file=$output" \
                "size:number=$size" \
                "time_ms:number=$duration_ms"
        else
            printf '{"ok":true,"file":"%s","size":%d,"time_ms":%d}' "$output" "$size" "$duration_ms"
        fi
        return 0
    else
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=Download failed" "url=$url"
        else
            printf '{"ok":false,"error":"Download failed","url":"%s"}' "$url"
        fi
        return 1
    fi
}

# Download multiple files in parallel
# @param $1 - file with URLs (one per line)
# @param $2 - output directory
# @param $3 - max parallel downloads (default: 4)
# @return {"ok":true,"downloaded":N,"failed":N,"files":[...]}
download_batch() {
    local url_file="$1"
    local output_dir="$2"
    local max_parallel="${3:-$DOWNLOAD_DEFAULT_PARALLEL}"

    # Validate inputs
    if [[ ! -f "$url_file" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=URL file not found" "file=$url_file"
        else
            printf '{"ok":false,"error":"URL file not found"}'
        fi
        return 1
    fi

    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            if declare -F json_object &>/dev/null; then
                json_object "ok:bool=false" "error=Cannot create output directory" "dir=$output_dir"
            else
                printf '{"ok":false,"error":"Cannot create output directory"}'
            fi
            return 1
        }
    fi

    local downloaded=0
    local failed=0
    local -a files=()
    local -a pids=()
    local -a urls=()

    # Read URLs
    while IFS= read -r url || [[ -n "$url" ]]; do
        # Skip empty lines and comments
        [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
        urls+=("$url")
    done < "$url_file"

    local total=${#urls[@]}
    local running=0
    local index=0

    # Process URLs with parallelism
    while [[ $index -lt $total || $running -gt 0 ]]; do
        # Start new downloads up to max_parallel
        while [[ $running -lt $max_parallel && $index -lt $total ]]; do
            local url="${urls[$index]}"
            local filename
            filename=$(_download_filename_from_url "$url")
            local output="${output_dir}/${filename}"

            # Avoid filename collisions
            local counter=1
            while [[ -f "$output" ]]; do
                local base="${filename%.*}"
                local ext="${filename##*.}"
                if [[ "$base" == "$ext" ]]; then
                    output="${output_dir}/${filename}_${counter}"
                else
                    output="${output_dir}/${base}_${counter}.${ext}"
                fi
                ((counter++))
            done

            # Start download in background
            (
                local backend
                backend=$(download_backend)
                local rc=1
                case "$backend" in
                    curl) _download_curl "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT" 1; rc=$? ;;
                    wget) _download_wget "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT" 1; rc=$? ;;
                    burl) _download_burl "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT" 1; rc=$? ;;
                    fetch) _download_fetch "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT" 1; rc=$? ;;
                esac
                exit $rc
            ) &
            pids+=($!)

            ((index++))
            ((running++))
        done

        # Wait for at least one to complete
        if [[ $running -gt 0 ]]; then
            local pid
            for i in "${!pids[@]}"; do
                pid="${pids[$i]}"
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid"
                    local rc=$?
                    if [[ $rc -eq 0 ]]; then
                        ((downloaded++))
                    else
                        ((failed++))
                    fi
                    unset 'pids[i]'
                    ((running--))
                fi
            done
            # Rebuild array to remove gaps
            pids=("${pids[@]}")
            sleep 0.1
        fi
    done

    # Collect downloaded files
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$output_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    # Build response
    local files_json="["
    local first=true
    for f in "${files[@]}"; do
        $first || files_json+=","
        first=false
        files_json+="\"$f\""
    done
    files_json+="]"

    if declare -F json_object &>/dev/null; then
        json_object \
            "ok:bool=true" \
            "downloaded:number=$downloaded" \
            "failed:number=$failed" \
            "total:number=$total" \
            "files:raw=$files_json"
    else
        printf '{"ok":true,"downloaded":%d,"failed":%d,"total":%d,"files":%s}' \
            "$downloaded" "$failed" "$total" "$files_json"
    fi

    [[ $failed -eq 0 ]]
}

# Resume interrupted download
# @param $1 - URL
# @param $2 - partial file
# @return {"ok":true,"resumed":true,"file":"path"}
download_resume() {
    local url="$1"
    local output="$2"

    if [[ -z "$url" || -z "$output" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=URL and output file required"
        else
            printf '{"ok":false,"error":"URL and output file required"}'
        fi
        return 1
    fi

    local backend
    backend=$(download_backend)

    local start_ms end_ms duration_ms
    start_ms=$(_download_now_ms)

    local rc=1
    local resumed=false

    # Check if partial file exists
    if [[ -f "$output" ]]; then
        resumed=true
    fi

    case "$backend" in
        curl)
            _download_curl_resume "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT"
            rc=$?
            ;;
        wget)
            _download_wget_resume "$url" "$output" "$DOWNLOAD_DEFAULT_TIMEOUT"
            rc=$?
            ;;
        burl|fetch)
            # Resume not supported, do full download
            resumed=false
            download "$url" "$output"
            return $?
            ;;
        none)
            if declare -F json_object &>/dev/null; then
                json_object "ok:bool=false" "error=No download tool available"
            else
                printf '{"ok":false,"error":"No download tool available"}'
            fi
            return 1
            ;;
    esac

    end_ms=$(_download_now_ms)
    duration_ms=$((end_ms - start_ms))
    [[ $duration_ms -lt 0 ]] && duration_ms=0

    if [[ $rc -eq 0 && -f "$output" ]]; then
        local size
        if [[ "$OSTYPE" == darwin* ]]; then
            size=$(stat -f%z "$output" 2>/dev/null || echo 0)
        else
            size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        fi

        if declare -F json_object &>/dev/null; then
            json_object \
                "ok:bool=true" \
                "resumed:bool=$resumed" \
                "file=$output" \
                "size:number=$size" \
                "time_ms:number=$duration_ms"
        else
            printf '{"ok":true,"resumed":%s,"file":"%s","size":%d,"time_ms":%d}' \
                "$resumed" "$output" "$size" "$duration_ms"
        fi
        return 0
    else
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=Download/resume failed" "url=$url"
        else
            printf '{"ok":false,"error":"Download/resume failed","url":"%s"}' "$url"
        fi
        return 1
    fi
}

# Verify downloaded file
# @param $1 - file path
# @param $2 - expected checksum (sha256)
# @return {"ok":true,"valid":true} or {"ok":false,"error":"checksum mismatch"}
download_verify() {
    local file="$1"
    local expected="$2"

    if [[ -z "$file" || -z "$expected" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=File path and expected checksum required"
        else
            printf '{"ok":false,"error":"File path and expected checksum required"}'
        fi
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=File not found" "file=$file"
        else
            printf '{"ok":false,"error":"File not found","file":"%s"}' "$file"
        fi
        return 1
    fi

    # Calculate checksum
    local actual=""

    if declare -F sha256_file &>/dev/null; then
        # Use MAINFRAME crypto.sh
        actual=$(sha256_file "$file")
    elif command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum &>/dev/null; then
        actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    elif command -v openssl &>/dev/null; then
        actual=$(openssl dgst -sha256 "$file" | awk '{print $NF}')
    else
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=No checksum tool available"
        else
            printf '{"ok":false,"error":"No checksum tool available"}'
        fi
        return 1
    fi

    # Compare (case-insensitive)
    if [[ "${actual,,}" == "${expected,,}" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=true" "valid:bool=true" "checksum=$actual"
        else
            printf '{"ok":true,"valid":true,"checksum":"%s"}' "$actual"
        fi
        return 0
    else
        if declare -F json_object &>/dev/null; then
            json_object \
                "ok:bool=false" \
                "valid:bool=false" \
                "error=Checksum mismatch" \
                "expected=$expected" \
                "actual=$actual"
        else
            printf '{"ok":false,"valid":false,"error":"Checksum mismatch","expected":"%s","actual":"%s"}' \
                "$expected" "$actual"
        fi
        return 1
    fi
}

# Download and extract archive
# @param $1 - URL
# @param $2 - output directory
# @return {"ok":true,"extracted_to":"path","files":N}
download_extract() {
    local url="$1"
    local output_dir="$2"

    if [[ -z "$url" || -z "$output_dir" ]]; then
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=URL and output directory required"
        else
            printf '{"ok":false,"error":"URL and output directory required"}'
        fi
        return 1
    fi

    # Create output directory
    mkdir -p "$output_dir" || {
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=Cannot create output directory"
        else
            printf '{"ok":false,"error":"Cannot create output directory"}'
        fi
        return 1
    }

    # Create temp file for download
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/download_extract.XXXXXX")

    # Determine filename from URL to detect archive type
    local filename
    filename=$(_download_filename_from_url "$url")

    # Download to temp file
    local result
    result=$(download "$url" "$tmpfile" '{"quiet":true}')

    if [[ ! -f "$tmpfile" || ! -s "$tmpfile" ]]; then
        rm -f "$tmpfile"
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=Download failed" "url=$url"
        else
            printf '{"ok":false,"error":"Download failed","url":"%s"}' "$url"
        fi
        return 1
    fi

    # Detect archive type and extract
    local extract_rc=1
    local extract_cmd=""

    case "$filename" in
        *.tar.gz|*.tgz)
            tar -xzf "$tmpfile" -C "$output_dir" 2>/dev/null
            extract_rc=$?
            extract_cmd="tar -xzf"
            ;;
        *.tar.bz2|*.tbz2)
            tar -xjf "$tmpfile" -C "$output_dir" 2>/dev/null
            extract_rc=$?
            extract_cmd="tar -xjf"
            ;;
        *.tar.xz|*.txz)
            tar -xJf "$tmpfile" -C "$output_dir" 2>/dev/null
            extract_rc=$?
            extract_cmd="tar -xJf"
            ;;
        *.tar)
            tar -xf "$tmpfile" -C "$output_dir" 2>/dev/null
            extract_rc=$?
            extract_cmd="tar -xf"
            ;;
        *.zip)
            if command -v unzip &>/dev/null; then
                unzip -q "$tmpfile" -d "$output_dir" 2>/dev/null
                extract_rc=$?
                extract_cmd="unzip"
            else
                rm -f "$tmpfile"
                if declare -F json_object &>/dev/null; then
                    json_object "ok:bool=false" "error=unzip not available"
                else
                    printf '{"ok":false,"error":"unzip not available"}'
                fi
                return 1
            fi
            ;;
        *.gz)
            if command -v gunzip &>/dev/null; then
                local out_name="${filename%.gz}"
                gunzip -c "$tmpfile" > "${output_dir}/${out_name}" 2>/dev/null
                extract_rc=$?
                extract_cmd="gunzip"
            else
                rm -f "$tmpfile"
                if declare -F json_object &>/dev/null; then
                    json_object "ok:bool=false" "error=gunzip not available"
                else
                    printf '{"ok":false,"error":"gunzip not available"}'
                fi
                return 1
            fi
            ;;
        *)
            # Unknown type, just move the file
            mv "$tmpfile" "${output_dir}/${filename}"
            extract_rc=$?
            extract_cmd="mv"
            ;;
    esac

    # Clean up temp file
    rm -f "$tmpfile"

    if [[ $extract_rc -eq 0 ]]; then
        # Count extracted files
        local file_count
        file_count=$(find "$output_dir" -type f 2>/dev/null | wc -l)
        file_count=$((file_count))  # Normalize whitespace

        if declare -F json_object &>/dev/null; then
            json_object \
                "ok:bool=true" \
                "extracted_to=$output_dir" \
                "files:number=$file_count" \
                "archive_type=$extract_cmd"
        else
            printf '{"ok":true,"extracted_to":"%s","files":%d,"archive_type":"%s"}' \
                "$output_dir" "$file_count" "$extract_cmd"
        fi
        return 0
    else
        if declare -F json_object &>/dev/null; then
            json_object "ok:bool=false" "error=Extraction failed" "type=$extract_cmd"
        else
            printf '{"ok":false,"error":"Extraction failed","type":"%s"}' "$extract_cmd"
        fi
        return 1
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

DOWNLOAD_EXPORTS=(
    # Backend detection
    download_backend
    # Core download
    download
    download_stdout
    download_progress
    # Batch operations
    download_batch
    # Resume support
    download_resume
    # Verification
    download_verify
    # Archive handling
    download_extract
    # Internal backends (for testing)
    _download_curl
    _download_wget
    _download_burl
    _download_fetch
)

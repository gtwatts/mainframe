#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/file/dedup-finder.sh - Duplicate File Finder
# =============================================================================
# Description: Finds duplicate files by content hash (SHA-256). Groups
#              duplicates, shows wasted space, and optionally removes copies.
# Version: 1.0.0
# Requires: Bash 4.0+, sha256sum
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
TARGET_DIR="."
MIN_SIZE=1        # Minimum file size in bytes
DRY_RUN=true      # Default to dry-run for safety
OUTPUT_FORMAT="text"  # text|json
DELETE_MODE="none"    # none|interactive|keep-oldest|keep-newest

usage() {
    cat <<EOF
Usage: dedup-finder.sh [options] [directory]

Find duplicate files by content hash.

Options:
    --min-size <bytes>   Minimum file size to check (default: 1)
    --delete <mode>      Deletion mode: interactive|keep-oldest|keep-newest
    --format <fmt>       Output: text|json (default: text)
    --execute            Actually delete (without this, only reports)
    -h, --help           Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --min-size) MIN_SIZE="$2"; shift 2 ;;
            --delete)   DELETE_MODE="$2"; shift 2 ;;
            --format)   OUTPUT_FORMAT="$2"; shift 2 ;;
            --execute)  DRY_RUN=false; shift ;;
            -h|--help)  usage ;;
            -*)         log_error "Unknown option: $1"; usage ;;
            *)          TARGET_DIR="$1"; shift ;;
        esac
    done
}

format_size() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.1fGB" "$(echo "$bytes / 1073741824" | bc -l)"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.1fMB" "$(echo "$bytes / 1048576" | bc -l)"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.1fKB" "$(echo "$bytes / 1024" | bc -l)"
    else
        printf "%dB" "$bytes"
    fi
}

main() {
    parse_args "$@"

    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Directory not found: $TARGET_DIR"
        exit 1
    fi

    log_info "Scanning: $TARGET_DIR (min size: ${MIN_SIZE}B)"

    # Phase 1: Group files by size (quick pre-filter)
    declare -A size_groups
    local total_files=0

    while IFS= read -r file; do
        local size
        size=$(stat -c%s "$file" 2>/dev/null) || continue
        [[ $size -lt $MIN_SIZE ]] && continue
        size_groups["$size"]+="$file"$'\n'
        ((total_files++))
    done < <(find "$TARGET_DIR" -type f ! -path '*/\.*' 2>/dev/null)

    log_info "Found $total_files files to analyze"

    # Phase 2: Hash files that share a size
    declare -A hash_groups
    local hashed=0

    for size in "${!size_groups[@]}"; do
        local files="${size_groups[$size]}"
        local file_count
        file_count=$(echo -n "$files" | grep -c '^')

        # Only hash if multiple files share the same size
        [[ $file_count -lt 2 ]] && continue

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local hash
            hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
            [[ -z "$hash" ]] && continue
            hash_groups["$hash"]+="$file"$'\n'
            ((hashed++))
        done <<< "$files"
    done

    log_info "Hashed $hashed candidate files"

    # Phase 3: Report duplicates
    local dup_groups=0
    local wasted_bytes=0
    local dup_count=0

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "["
        local first_group=1
    fi

    for hash in "${!hash_groups[@]}"; do
        local files="${hash_groups[$hash]}"
        local file_count
        file_count=$(echo -n "$files" | grep -c '^')

        [[ $file_count -lt 2 ]] && continue
        ((dup_groups++))

        # Get file size from first entry
        local first_file
        first_file=$(echo "$files" | head -1)
        local file_size
        file_size=$(stat -c%s "$first_file" 2>/dev/null)
        local group_waste=$(( file_size * (file_count - 1) ))
        wasted_bytes=$((wasted_bytes + group_waste))
        dup_count=$((dup_count + file_count - 1))

        if [[ "$OUTPUT_FORMAT" == "text" ]]; then
            echo ""
            echo "  Group #${dup_groups} [$(format_size "$file_size") each, ${file_count} copies, wasted: $(format_size "$group_waste")]"
            echo "  Hash: ${hash:0:16}..."
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                local mod_time
                mod_time=$(stat -c%Y "$file" 2>/dev/null)
                echo "    - $file ($(date -d @"$mod_time" '+%Y-%m-%d %H:%M' 2>/dev/null))"
            done <<< "$files"
        elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
            [[ $first_group -eq 0 ]] && echo ","
            first_group=0
            local file_array="["
            local first_file_json=1
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                [[ $first_file_json -eq 0 ]] && file_array+=","
                first_file_json=0
                file="${file//\\/\\\\}"
                file="${file//\"/\\\"}"
                file_array+="\"$file\""
            done <<< "$files"
            file_array+="]"
            printf '{"hash":"%s","size":%d,"count":%d,"files":%s}' \
                "$hash" "$file_size" "$file_count" "$file_array"
        fi

        # Handle deletion
        if [[ "$DELETE_MODE" != "none" && "$DRY_RUN" == false ]]; then
            local -a sorted_files=()
            while IFS= read -r f; do
                [[ -n "$f" ]] && sorted_files+=("$f")
            done <<< "$files"

            local keep_idx=0
            case "$DELETE_MODE" in
                keep-oldest)
                    # Sort by modification time, keep oldest
                    local oldest_time=999999999999
                    for i in "${!sorted_files[@]}"; do
                        local mt
                        mt=$(stat -c%Y "${sorted_files[$i]}" 2>/dev/null)
                        if [[ $mt -lt $oldest_time ]]; then
                            oldest_time=$mt
                            keep_idx=$i
                        fi
                    done
                    ;;
                keep-newest)
                    local newest_time=0
                    for i in "${!sorted_files[@]}"; do
                        local mt
                        mt=$(stat -c%Y "${sorted_files[$i]}" 2>/dev/null)
                        if [[ $mt -gt $newest_time ]]; then
                            newest_time=$mt
                            keep_idx=$i
                        fi
                    done
                    ;;
                interactive)
                    echo "  Keep which file? (enter number)"
                    for i in "${!sorted_files[@]}"; do
                        echo "    [$i] ${sorted_files[$i]}"
                    done
                    read -rp "  > " keep_idx
                    ;;
            esac

            for i in "${!sorted_files[@]}"; do
                [[ $i -eq $keep_idx ]] && continue
                rm -f "${sorted_files[$i]}"
                log_info "Deleted: ${sorted_files[$i]}"
            done
        fi
    done

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo ""
        echo "]"
    fi

    # Summary
    echo ""
    log_info "=== Summary ==="
    log_info "Duplicate groups: $dup_groups"
    log_info "Duplicate files: $dup_count"
    log_info "Wasted space: $(format_size $wasted_bytes)"

    if [[ "$DELETE_MODE" != "none" && "$DRY_RUN" == true ]]; then
        log_warn "Use --execute to actually delete files"
    fi
}

main "$@"

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/file/tree-export.sh - Directory Tree Exporter
# =============================================================================
# Description: Exports directory structure as tree, JSON, markdown, or YAML.
#              Supports depth limiting, gitignore respect, and size annotations.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
TARGET_DIR="."
MAX_DEPTH=10
OUTPUT_FORMAT="tree"  # tree|json|markdown|yaml
SHOW_SIZE=false
SHOW_HIDDEN=false
RESPECT_GITIGNORE=true
EXCLUDE_PATTERNS=()

usage() {
    cat <<EOF
Usage: tree-export.sh [options] [directory]

Export directory structure in various formats.

Options:
    --format <fmt>     Output: tree|json|markdown|yaml (default: tree)
    --depth <n>        Maximum depth (default: 10)
    --size             Show file sizes
    --hidden           Include hidden files
    --no-gitignore     Don't respect .gitignore
    --exclude <pat>    Exclude pattern (repeatable)
    -h, --help         Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)       OUTPUT_FORMAT="$2"; shift 2 ;;
            --depth)        MAX_DEPTH="$2"; shift 2 ;;
            --size)         SHOW_SIZE=true; shift ;;
            --hidden)       SHOW_HIDDEN=true; shift ;;
            --no-gitignore) RESPECT_GITIGNORE=false; shift ;;
            --exclude)      EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
            -h|--help)      usage ;;
            -*)             log_error "Unknown option: $1"; usage ;;
            *)              TARGET_DIR="$1"; shift ;;
        esac
    done
}

# Check if path matches any exclude pattern
is_excluded() {
    local path="$1"
    local name
    name=$(basename "$path")

    # Hidden files
    if [[ "$SHOW_HIDDEN" == false && "$name" == .* ]]; then
        return 0
    fi

    # Common excludes
    case "$name" in
        node_modules|.git|__pycache__|.DS_Store|target|vendor|dist|build)
            return 0 ;;
    esac

    # User patterns
    for pat in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$name" == $pat ]]; then
            return 0
        fi
    done

    return 1
}

format_file_size() {
    local size=$1
    if [[ $size -ge 1048576 ]]; then
        printf "%.1fM" "$(echo "$size / 1048576" | bc -l)"
    elif [[ $size -ge 1024 ]]; then
        printf "%.1fK" "$(echo "$size / 1024" | bc -l)"
    else
        printf "%dB" "$size"
    fi
}

# Tree format output
render_tree() {
    local dir="$1"
    local prefix="$2"
    local depth="$3"

    [[ $depth -gt $MAX_DEPTH ]] && return

    local entries=()
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        is_excluded "$entry" && continue
        entries+=("$entry")
    done < <(ls -1 "$dir" 2>/dev/null | sort)

    local count=${#entries[@]}
    local i=0

    for entry in "${entries[@]}"; do
        ((i++))
        local path="${dir}/${entry}"
        local connector="├── "
        local next_prefix="${prefix}│   "

        if [[ $i -eq $count ]]; then
            connector="└── "
            next_prefix="${prefix}    "
        fi

        local size_str=""
        if [[ "$SHOW_SIZE" == true && -f "$path" ]]; then
            local size
            size=$(stat -c%s "$path" 2>/dev/null)
            size_str=" ($(format_file_size "$size"))"
        fi

        if [[ -d "$path" ]]; then
            echo "${prefix}${connector}${entry}/"
            render_tree "$path" "$next_prefix" $((depth + 1))
        else
            echo "${prefix}${connector}${entry}${size_str}"
        fi
    done
}

# JSON format output
render_json() {
    local dir="$1"
    local depth="$2"
    local indent="$3"

    [[ $depth -gt $MAX_DEPTH ]] && echo "${indent}[]" && return

    local entries=()
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        is_excluded "$entry" && continue
        entries+=("$entry")
    done < <(ls -1 "$dir" 2>/dev/null | sort)

    echo "${indent}["
    local count=${#entries[@]}
    local i=0

    for entry in "${entries[@]}"; do
        ((i++))
        local path="${dir}/${entry}"
        local comma=""
        [[ $i -lt $count ]] && comma=","

        if [[ -d "$path" ]]; then
            echo "${indent}  {"
            echo "${indent}    \"name\": \"$entry\","
            echo "${indent}    \"type\": \"directory\","
            printf '%s' "${indent}    \"children\": "
            render_json "$path" $((depth + 1)) "${indent}    "
            echo "${indent}  }${comma}"
        else
            local size_field=""
            if [[ "$SHOW_SIZE" == true ]]; then
                local size
                size=$(stat -c%s "$path" 2>/dev/null)
                size_field=",\"size\":$size"
            fi
            echo "${indent}  {\"name\":\"$entry\",\"type\":\"file\"${size_field}}${comma}"
        fi
    done

    echo "${indent}]"
}

# Markdown format output
render_markdown() {
    local dir="$1"
    local depth="$2"

    [[ $depth -gt $MAX_DEPTH ]] && return

    local indent=""
    for ((d=0; d<depth; d++)); do
        indent+="  "
    done

    local entries=()
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        is_excluded "$entry" && continue
        entries+=("$entry")
    done < <(ls -1 "$dir" 2>/dev/null | sort)

    for entry in "${entries[@]}"; do
        local path="${dir}/${entry}"

        if [[ -d "$path" ]]; then
            echo "${indent}- **${entry}/**"
            render_markdown "$path" $((depth + 1))
        else
            local size_str=""
            if [[ "$SHOW_SIZE" == true ]]; then
                local size
                size=$(stat -c%s "$path" 2>/dev/null)
                size_str=" \`$(format_file_size "$size")\`"
            fi
            echo "${indent}- ${entry}${size_str}"
        fi
    done
}

# YAML format output
render_yaml() {
    local dir="$1"
    local depth="$2"

    [[ $depth -gt $MAX_DEPTH ]] && return

    local indent=""
    for ((d=0; d<depth; d++)); do
        indent+="  "
    done

    local entries=()
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        is_excluded "$entry" && continue
        entries+=("$entry")
    done < <(ls -1 "$dir" 2>/dev/null | sort)

    for entry in "${entries[@]}"; do
        local path="${dir}/${entry}"

        if [[ -d "$path" ]]; then
            echo "${indent}${entry}:"
            render_yaml "$path" $((depth + 1))
        else
            if [[ "$SHOW_SIZE" == true ]]; then
                local size
                size=$(stat -c%s "$path" 2>/dev/null)
                echo "${indent}${entry}: ${size}"
            else
                echo "${indent}- ${entry}"
            fi
        fi
    done
}

main() {
    parse_args "$@"

    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Directory not found: $TARGET_DIR"
        exit 1
    fi

    TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

    case "$OUTPUT_FORMAT" in
        tree)
            echo "$(basename "$TARGET_DIR")/"
            render_tree "$TARGET_DIR" "" 0
            ;;
        json)
            echo "{"
            echo "  \"name\": \"$(basename "$TARGET_DIR")\","
            echo "  \"type\": \"directory\","
            printf '  "children": '
            render_json "$TARGET_DIR" 0 "  "
            echo "}"
            ;;
        markdown)
            echo "# $(basename "$TARGET_DIR")"
            echo ""
            render_markdown "$TARGET_DIR" 0
            ;;
        yaml)
            echo "$(basename "$TARGET_DIR"):"
            render_yaml "$TARGET_DIR" 1
            ;;
        *)
            log_error "Unknown format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

main "$@"

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: JSON Deep Merge
# =============================================================================
# Description: Deep merge multiple JSON files with conflict resolution
# Category:    data
# WOW Factor:  9/10
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
#
# Deep merge JSON files with intelligent conflict handling:
# - Recursive object merging
# - Array concatenation or replacement
# - Conflict resolution strategies
# - Path-based overrides
# - Preserve or flatten structure
#
# Usage:
#   mainframe json-merge file1.json file2.json [file3.json ...]
#   mainframe json-merge --strategy=deep *.json
#   cat file.json | mainframe json-merge - override.json
#
# =============================================================================

set -euo pipefail

# Source MAINFRAME libraries
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="json-merge"
readonly SCRIPT_VERSION="1.0.0"

# Merge strategies
STRATEGY="${STRATEGY:-deep}"  # deep, shallow, replace
ARRAY_STRATEGY="${ARRAY_STRATEGY:-concat}"  # concat, replace, unique
CONFLICT_STRATEGY="${CONFLICT_STRATEGY:-last}"  # first, last, error
OUTPUT_FORMAT="${OUTPUT_FORMAT:-pretty}"  # pretty, compact

# =============================================================================
# JQ MERGE FUNCTIONS
# =============================================================================

# Deep merge function for jq - recursive reduce approach
readonly JQ_DEEP_MERGE='
def deepmerge:
  reduce .[] as $item ({};
    . as $acc | $item | to_entries | reduce .[] as $entry ($acc;
      if ($entry.value | type) == "object" and (.[$entry.key] | type) == "object"
      then .[$entry.key] = ([ .[$entry.key], $entry.value ] | deepmerge)
      elif ($entry.value | type) == "array" and (.[$entry.key] | type) == "array"
      then .[$entry.key] = (.[$entry.key] + $entry.value)
      else .[$entry.key] = $entry.value
      end
    )
  );
'

# Unique array merge - deduplicates arrays
readonly JQ_UNIQUE_MERGE='
def deepmerge_unique:
  reduce .[] as $item ({};
    . as $acc | $item | to_entries | reduce .[] as $entry ($acc;
      if ($entry.value | type) == "object" and (.[$entry.key] | type) == "object"
      then .[$entry.key] = ([ .[$entry.key], $entry.value ] | deepmerge_unique)
      elif ($entry.value | type) == "array" and (.[$entry.key] | type) == "array"
      then .[$entry.key] = ((.[$entry.key] + $entry.value) | unique)
      else .[$entry.key] = $entry.value
      end
    )
  );
'

# Replace array merge - arrays replace rather than concat
readonly JQ_REPLACE_MERGE='
def deepmerge_replace:
  reduce .[] as $item ({};
    . as $acc | $item | to_entries | reduce .[] as $entry ($acc;
      if ($entry.value | type) == "object" and (.[$entry.key] | type) == "object"
      then .[$entry.key] = ([ .[$entry.key], $entry.value ] | deepmerge_replace)
      else .[$entry.key] = $entry.value
      end
    )
  );
'

# =============================================================================
# MERGE OPERATIONS
# =============================================================================

validate_json() {
    local file="$1"

    if [[ "$file" == "-" ]]; then
        # Validate stdin (need to buffer it)
        return 0
    fi

    if [[ ! -f "$file" ]]; then
        die "$EXIT_NOINPUT" "File not found: $file"
    fi

    if ! jq empty "$file" 2>/dev/null; then
        die "$EXIT_DATAERR" "Invalid JSON: $file"
    fi
}

read_json() {
    local file="$1"

    if [[ "$file" == "-" ]]; then
        cat
    else
        cat "$file"
    fi
}

merge_two() {
    local json1="$1"
    local json2="$2"
    local merge_func
    local merge_call

    # Select merge function based on strategy
    case "$ARRAY_STRATEGY" in
        concat)
            merge_func="$JQ_DEEP_MERGE"
            merge_call="deepmerge"
            ;;
        unique)
            merge_func="$JQ_UNIQUE_MERGE"
            merge_call="deepmerge_unique"
            ;;
        replace)
            merge_func="$JQ_REPLACE_MERGE"
            merge_call="deepmerge_replace"
            ;;
        *)
            die "$EXIT_USAGE" "Unknown array strategy: $ARRAY_STRATEGY"
            ;;
    esac

    # Perform merge - using jq -s to slurp both JSON objects into array
    echo "[$json1, $json2]" | jq "$merge_func $merge_call"
}

merge_shallow() {
    local json1="$1"
    local json2="$2"

    # Simple top-level merge
    jq -n '$a + $b' \
        --argjson a "$json1" \
        --argjson b "$json2"
}

merge_files() {
    local files=("$@")
    local result=""

    if [[ ${#files[@]} -eq 0 ]]; then
        die "$EXIT_USAGE" "No files specified"
    fi

    # Validate all files first
    for file in "${files[@]}"; do
        validate_json "$file"
    done

    # Read first file
    result=$(read_json "${files[0]}")

    # Merge remaining files
    for ((i = 1; i < ${#files[@]}; i++)); do
        local next_json
        next_json=$(read_json "${files[$i]}")

        case "$STRATEGY" in
            deep)
                result=$(merge_two "$result" "$next_json")
                ;;
            shallow)
                result=$(merge_shallow "$result" "$next_json")
                ;;
            replace)
                result="$next_json"
                ;;
            *)
                die "$EXIT_USAGE" "Unknown strategy: $STRATEGY"
                ;;
        esac
    done

    # Output
    case "$OUTPUT_FORMAT" in
        pretty)
            echo "$result" | jq '.'
            ;;
        compact)
            echo "$result" | jq -c '.'
            ;;
        *)
            echo "$result"
            ;;
    esac
}

# =============================================================================
# ADVANCED OPERATIONS
# =============================================================================

merge_with_path() {
    # Merge into a specific path
    local base="$1"
    local patch="$2"
    local path="$3"

    jq --argjson patch "$patch" \
       "setpath(($path | split(\".\")); \$patch)" \
       <<< "$base"
}

diff_json() {
    # Show differences between two JSON objects
    local json1="$1"
    local json2="$2"

    jq -n '
    def diff(a; b):
      (a | keys) + (b | keys) | unique | map(
        . as $k |
        if (a[$k] | type) == "object" and (b[$k] | type) == "object"
        then {key: $k, diff: diff(a[$k]; b[$k])}
        elif a[$k] != b[$k]
        then {key: $k, left: a[$k], right: b[$k]}
        else empty
        end
      );
    diff($a; $b)
    ' --argjson a "$json1" --argjson b "$json2"
}

# =============================================================================
# MAIN
# =============================================================================

show_help() {
    cat << EOF
${CLR_BOLD}$SCRIPT_NAME${CLR_RESET} - Deep Merge JSON Files

${CLR_BOLD}Usage:${CLR_RESET}
  mainframe $SCRIPT_NAME [options] <file1.json> <file2.json> [...]
  cat base.json | mainframe $SCRIPT_NAME - overlay.json

${CLR_BOLD}Options:${CLR_RESET}
  -s, --strategy STRATEGY     Merge strategy: deep, shallow, replace (default: deep)
  -a, --array STRATEGY        Array strategy: concat, unique, replace (default: concat)
  -c, --compact               Output compact JSON
  -p, --pretty                Output pretty JSON (default)
  --diff                      Show diff instead of merge
  -o, --output FILE           Write to file instead of stdout
  -h, --help                  Show this help message

${CLR_BOLD}Strategies:${CLR_RESET}
  deep      Recursively merge objects, concat/unique arrays
  shallow   Only merge top-level keys
  replace   Later files completely replace earlier

${CLR_BOLD}Array Strategies:${CLR_RESET}
  concat    Concatenate arrays
  unique    Concatenate and deduplicate
  replace   Replace arrays entirely

${CLR_BOLD}Examples:${CLR_RESET}
  # Deep merge two files
  mainframe $SCRIPT_NAME config.json overrides.json

  # Merge with unique arrays
  mainframe $SCRIPT_NAME -a unique users1.json users2.json

  # Shallow merge
  mainframe $SCRIPT_NAME -s shallow base.json patch.json

  # From stdin
  curl -s https://api.example.com/config | mainframe $SCRIPT_NAME - local.json

  # Show differences
  mainframe $SCRIPT_NAME --diff old.json new.json

${CLR_DIM}YO JOE!${CLR_RESET}
EOF
}

main() {
    # Check for jq
    require_command jq

    local files=()
    local output_file=""
    local show_diff=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--strategy)
                STRATEGY="$2"
                shift 2
                ;;
            -a|--array)
                ARRAY_STRATEGY="$2"
                shift 2
                ;;
            -c|--compact)
                OUTPUT_FORMAT="compact"
                shift
                ;;
            -p|--pretty)
                OUTPUT_FORMAT="pretty"
                shift
                ;;
            --diff)
                show_diff=true
                shift
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                die "$EXIT_USAGE" "Unknown option: $1"
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#files[@]} -lt 2 ]]; then
        die "$EXIT_USAGE" "At least two files required"
    fi

    local result

    if [[ "$show_diff" == "true" ]]; then
        if [[ ${#files[@]} -ne 2 ]]; then
            die "$EXIT_USAGE" "Diff requires exactly two files"
        fi
        local json1 json2
        json1=$(read_json "${files[0]}")
        json2=$(read_json "${files[1]}")
        result=$(diff_json "$json1" "$json2")
    else
        result=$(merge_files "${files[@]}")
    fi

    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        success "Merged to $output_file"
    else
        echo "$result"
    fi
}

main "$@"

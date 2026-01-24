#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/git/pr-summary.sh - Pull Request Summary Generator
# =============================================================================
# Description: Generates comprehensive PR descriptions by analyzing commits,
#              categorizing changes, detecting breaking changes, and formatting
#              output as Markdown, plain text, or JSON.
# Version: 1.0.0
# Requires: Bash 4.0+, git
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
BASE_BRANCH="main"
OUTPUT_FORMAT="markdown"
COPY_CLIPBOARD=false

usage() {
    cat <<EOF
Usage: pr-summary.sh [options]

Generates a PR summary comparing current branch against base.

Options:
    --base <branch>    Base branch to compare (default: main)
    --format <fmt>     Output: markdown|plain|json (default: markdown)
    --clipboard        Copy output to clipboard
    -h, --help         Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)      BASE_BRANCH="$2"; shift 2 ;;
            --format)    OUTPUT_FORMAT="$2"; shift 2 ;;
            --clipboard) COPY_CLIPBOARD=true; shift ;;
            -h|--help)   usage ;;
            *)           log_error "Unknown option: $1"; usage ;;
        esac
    done
}

copy_to_clipboard() {
    local content="$1"
    if command -v xclip >/dev/null 2>&1; then
        echo "$content" | xclip -selection clipboard
    elif command -v pbcopy >/dev/null 2>&1; then
        echo "$content" | pbcopy
    elif command -v xsel >/dev/null 2>&1; then
        echo "$content" | xsel --clipboard --input
    else
        log_warn "No clipboard tool found (xclip/pbcopy/xsel)"
        return 1
    fi
    log_info "Copied to clipboard"
}

main() {
    parse_args "$@"

    # Verify git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository"
        exit 1
    fi

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
        log_error "Base branch '$BASE_BRANCH' not found"
        exit 1
    fi

    local merge_base
    merge_base=$(git merge-base "$BASE_BRANCH" HEAD 2>/dev/null)

    if [[ -z "$merge_base" ]]; then
        log_error "Cannot find merge base between $BASE_BRANCH and HEAD"
        exit 1
    fi

    # Collect commits
    local -a features=() fixes=() refactors=() docs=() tests=() chores=() breaking=()

    while IFS= read -r hash; do
        [[ -z "$hash" ]] && continue
        local subject
        subject=$(git log -1 --format=%s "$hash")
        local body
        body=$(git log -1 --format=%b "$hash")

        # Detect breaking changes
        if [[ "$subject" == *"!"* ]] || [[ "$body" == *"BREAKING CHANGE:"* ]]; then
            breaking+=("$subject")
        fi

        # Categorize - strip type prefix for cleaner display
        case "$subject" in
            feat*)     features+=("${subject#feat*: }") ;;
            fix*)      fixes+=("${subject#fix*: }") ;;
            refactor*) refactors+=("${subject#refactor*: }") ;;
            docs*)     docs+=("${subject#docs*: }") ;;
            test*)     tests+=("${subject#test*: }") ;;
            ci*|chore*) chores+=("${subject#*: }") ;;
            *)         chores+=("$subject") ;;
        esac
    done < <(git log --format=%H --no-merges "$merge_base..HEAD")

    # Stats
    local stat_line
    stat_line=$(git diff --shortstat "$merge_base..HEAD" 2>/dev/null | xargs)
    local files_changed additions deletions
    files_changed=$(echo "$stat_line" | grep -oP '\d+(?= file)' || echo "0")
    additions=$(echo "$stat_line" | grep -oP '\d+(?= insertion)' || echo "0")
    deletions=$(echo "$stat_line" | grep -oP '\d+(?= deletion)' || echo "0")

    # Test file changes
    local test_files_changed
    test_files_changed=$(git diff --name-only "$merge_base..HEAD" | grep -cE '(test|spec|_test)\.' || echo "0")

    # Generate output
    local output=""

    # Helper for JSON array output
    _json_arr() {
        local result="["
        local first=1
        local item
        for item in "$@"; do
            item="${item//\\/\\\\}"
            item="${item//\"/\\\"}"
            [[ $first -eq 0 ]] && result+=","
            result+="\"$item\""
            first=0
        done
        result+="]"
        echo "$result"
    }

    case "$OUTPUT_FORMAT" in
        markdown)
            output+="## PR Summary: \`$current_branch\` -> \`$BASE_BRANCH\`"$'\n\n'

            if [[ ${#breaking[@]} -gt 0 ]]; then
                output+="### Breaking Changes"$'\n'
                for msg in "${breaking[@]}"; do output+="- $msg"$'\n'; done
                output+=$'\n'
            fi
            if [[ ${#features[@]} -gt 0 ]]; then
                output+="### Features"$'\n'
                for msg in "${features[@]}"; do output+="- $msg"$'\n'; done
                output+=$'\n'
            fi
            if [[ ${#fixes[@]} -gt 0 ]]; then
                output+="### Bug Fixes"$'\n'
                for msg in "${fixes[@]}"; do output+="- $msg"$'\n'; done
                output+=$'\n'
            fi
            if [[ ${#refactors[@]} -gt 0 ]]; then
                output+="### Refactors"$'\n'
                for msg in "${refactors[@]}"; do output+="- $msg"$'\n'; done
                output+=$'\n'
            fi
            if [[ ${#tests[@]} -gt 0 ]]; then
                output+="### Tests"$'\n'
                for msg in "${tests[@]}"; do output+="- $msg"$'\n'; done
                output+=$'\n'
            fi
            if [[ ${#docs[@]} -gt 0 ]]; then
                output+="### Documentation"$'\n'
                for msg in "${docs[@]}"; do output+="- $msg"$'\n'; done
                output+=$'\n'
            fi
            if [[ ${#chores[@]} -gt 0 ]]; then
                output+="### Chores"$'\n'
                for msg in "${chores[@]}"; do output+="- $msg"$'\n'; done
                output+=$'\n'
            fi

            output+="### Stats"$'\n'
            output+="- Files changed: $files_changed"$'\n'
            output+="- Insertions: +$additions"$'\n'
            output+="- Deletions: -$deletions"$'\n'
            [[ $test_files_changed -gt 0 ]] && output+="- Test files updated: $test_files_changed"$'\n'
            ;;

        plain)
            output+="PR: $current_branch -> $BASE_BRANCH"$'\n'
            output+="================================="$'\n\n'
            [[ ${#features[@]} -gt 0 ]] && output+="FEATURES:"$'\n' && printf -v tmp '  %s\n' "${features[@]}" && output+="$tmp"$'\n'
            [[ ${#fixes[@]} -gt 0 ]] && output+="FIXES:"$'\n' && printf -v tmp '  %s\n' "${fixes[@]}" && output+="$tmp"$'\n'
            [[ ${#refactors[@]} -gt 0 ]] && output+="REFACTORS:"$'\n' && printf -v tmp '  %s\n' "${refactors[@]}" && output+="$tmp"$'\n'
            output+="STATS: $stat_line"$'\n'
            ;;

        json)
            output+="{"
            output+="\"source\":\"$current_branch\","
            output+="\"target\":\"$BASE_BRANCH\","
            output+="\"features\":$(_json_arr "${features[@]}"),"
            output+="\"fixes\":$(_json_arr "${fixes[@]}"),"
            output+="\"breaking\":$(_json_arr "${breaking[@]}"),"
            output+="\"files_changed\":$files_changed,"
            output+="\"additions\":$additions,"
            output+="\"deletions\":$deletions"
            output+="}"
            ;;

        *)
            log_error "Unknown format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac

    echo "$output"

    if [[ "$COPY_CLIPBOARD" == true ]]; then
        copy_to_clipboard "$output"
    fi
}

main "$@"

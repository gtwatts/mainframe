#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/git/smart-commit.sh - Intelligent Git Commit Helper
# =============================================================================
# Description: Analyzes staged changes to auto-generate conventional commit
#              messages. Detects change type from file patterns and diff content.
# Version: 1.0.0
# Requires: Bash 4.0+, git
# =============================================================================

set -o pipefail

source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Configuration
DRY_RUN=false
AMEND=false
CUSTOM_TYPE=""
CUSTOM_SCOPE=""
CUSTOM_MESSAGE=""

usage() {
    cat <<EOF
Usage: smart-commit.sh [options]

Analyzes staged changes to generate Conventional Commit messages.

Options:
    -t, --type <type>    Force commit type (feat/fix/docs/test/refactor/ci/chore)
    -s, --scope <scope>  Force commit scope
    -m, --message <msg>  Force commit message subject
    -d, --dry-run        Preview without committing
    -a, --amend          Amend the previous commit
    -h, --help           Show this help
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--type)    CUSTOM_TYPE="$2"; shift 2 ;;
            -s|--scope)   CUSTOM_SCOPE="$2"; shift 2 ;;
            -m|--message) CUSTOM_MESSAGE="$2"; shift 2 ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -a|--amend)   AMEND=true; shift ;;
            -h|--help)    usage ;;
            *)            log_error "Unknown option: $1"; usage ;;
        esac
    done
}

# Detect commit type from file path
# Returns priority score (lower = more specific)
detect_type_from_file() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    local base
    base=$(basename "$file")

    # CI/Build files
    if [[ "$dir" =~ \.github|\.gitlab-ci|jenkins ]] || \
       [[ "$base" =~ ^(Dockerfile|Makefile|Jenkinsfile|\.gitlab-ci\.yml)$ ]]; then
        echo "ci"; return
    fi

    # Test files
    if [[ "$dir" =~ tests?|spec|__tests__ ]] || \
       [[ "$base" =~ \.(test|spec)\. ]] || [[ "$base" =~ _test\. ]]; then
        echo "test"; return
    fi

    # Documentation
    if [[ "$base" =~ \.(md|rst|txt)$ ]] || [[ "$dir" =~ docs?|wiki ]]; then
        echo "docs"; return
    fi

    # Default: source code change
    echo "code"
}

# Analyze diff content for intent keywords
detect_type_from_diff() {
    local diff_content="$1"

    if echo "$diff_content" | grep -qiE 'fix(e[sd])?|bug|broken|crash|patch|hotfix'; then
        echo "fix"; return
    fi

    if echo "$diff_content" | grep -qiE 'refactor|clean.?up|optimize|reorganize|simplif'; then
        echo "refactor"; return
    fi

    echo ""
}

# Determine the most common scope from file paths
detect_scope() {
    local files="$1"
    local scope=""

    # Get the most common top-level directory
    scope=$(echo "$files" | xargs -I{} dirname {} | \
        sed 's|^\./||' | cut -d/ -f1 | \
        sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

    [[ "$scope" == "." ]] && scope=""
    echo "$scope"
}

# Generate a descriptive subject from the diff
generate_subject() {
    local commit_type="$1"
    local files="$2"
    local file_count
    file_count=$(echo "$files" | wc -l)

    case "$commit_type" in
        feat)     echo "add new functionality" ;;
        fix)      echo "resolve issue in $(echo "$files" | head -1 | xargs basename)" ;;
        docs)     echo "update documentation" ;;
        test)     echo "update test coverage" ;;
        refactor) echo "improve code structure" ;;
        ci)       echo "update CI configuration" ;;
        chore)    echo "perform maintenance" ;;
        *)        echo "update ${file_count} file(s)" ;;
    esac
}

main() {
    parse_args "$@"

    # Verify git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository"
        exit 1
    fi

    # Check for staged changes
    if [[ "$AMEND" == false ]] && git diff --cached --quiet; then
        log_error "No staged changes found. Use 'git add' first."
        exit 1
    fi

    # Get staged files
    local files
    files=$(git diff --cached --name-only --diff-filter=ACMR)

    if [[ -z "$files" && "$AMEND" == false ]]; then
        log_error "No modified files to analyze"
        exit 1
    fi

    log_info "Analyzing staged changes..."

    # Detect type
    local detected_type="chore"
    local type_counts=""

    if [[ -n "$CUSTOM_TYPE" ]]; then
        detected_type="$CUSTOM_TYPE"
    else
        # Check file-based type detection
        local file_types=""
        while IFS= read -r file; do
            file_types+="$(detect_type_from_file "$file")"$'\n'
        done <<< "$files"

        # Most common file type
        local dominant
        dominant=$(echo "$file_types" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

        case "$dominant" in
            ci|test|docs) detected_type="$dominant" ;;
            code)
                # Analyze diff for feat vs fix vs refactor
                local diff_content
                diff_content=$(git diff --cached --unified=0 2>/dev/null)
                local diff_type
                diff_type=$(detect_type_from_diff "$diff_content")
                detected_type="${diff_type:-feat}"
                ;;
        esac
    fi

    # Detect scope
    local scope=""
    if [[ -n "$CUSTOM_SCOPE" ]]; then
        scope="$CUSTOM_SCOPE"
    else
        scope=$(detect_scope "$files")
    fi

    # Generate subject
    local subject=""
    if [[ -n "$CUSTOM_MESSAGE" ]]; then
        subject="$CUSTOM_MESSAGE"
    else
        subject=$(generate_subject "$detected_type" "$files")
    fi

    # Build conventional commit string
    local commit_msg=""
    if [[ -n "$scope" ]]; then
        commit_msg="${detected_type}(${scope}): ${subject}"
    else
        commit_msg="${detected_type}: ${subject}"
    fi

    # Display
    echo ""
    log_info "Proposed commit message:"
    echo ""
    echo "  $commit_msg"
    echo ""

    # Dry run check
    if [[ "$DRY_RUN" == true ]]; then
        local cmd="git commit"
        [[ "$AMEND" == true ]] && cmd+=" --amend"
        cmd+=" -m \"$commit_msg\""
        log_info "[DRY RUN] Would execute: $cmd"
        exit 0
    fi

    # Confirm
    read -rp "Accept this message? [Y/n/e(dit)] " answer
    case "${answer,,}" in
        n|no)
            log_info "Commit aborted."
            exit 0
            ;;
        e|edit)
            read -rp "Enter commit message: " commit_msg
            ;;
    esac

    # Execute commit
    local git_args=("commit" "-m" "$commit_msg")
    [[ "$AMEND" == true ]] && git_args=("commit" "--amend" "-m" "$commit_msg")

    if git "${git_args[@]}"; then
        log_info "Commit created successfully."
    else
        log_error "Commit failed."
        exit 1
    fi
}

main "$@"

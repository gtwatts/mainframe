#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/diff.sh - Diff Generation and Patch Application Primitives
# =============================================================================
# Description: Surgical file editing for AI agents via unified diffs,
#              search-and-replace, and safe patch application. Enables agents
#              to make precise edits without dumping/rewriting entire files.
# Version: 1.0.0
# Requires: Bash 4.0+, diff (coreutils)
# =============================================================================
# LIMITATIONS:
#   - Binary file diffs are not supported
#   - Fuzz matching is line-offset only (not fuzzy string matching)
#   - Multiline old_text in diff_replace uses literal matching (no regex)
#   - Edit scripts are line-based only (no character-level granularity)
#   - Conflict detection relies on context line matching
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_DIFF_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DIFF_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default context lines for unified diff
MAINFRAME_DIFF_CONTEXT="${MAINFRAME_DIFF_CONTEXT:-3}"

# Default backup behavior
MAINFRAME_DIFF_BACKUP="${MAINFRAME_DIFF_BACKUP:-1}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_diff_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[diff] %s: %s\n' "${level}" "$*" >&2
    fi
}

# Generate a unique temporary filename in the same directory as target
_diff_tmpfile() {
    local target="$1"
    local dir
    dir="${target%/*}"
    [[ "$dir" == "$target" ]] && dir="."
    printf '%s/.mainframe_diff_%s_%s' "$dir" "$$" "$RANDOM"
}

# Create a backup of a file
# Usage: _diff_backup "file_path"
_diff_backup() {
    local file="$1"
    local backup_file="${file}.orig"

    if [[ -f "$file" ]]; then
        cp -p "$file" "$backup_file" 2>/dev/null || {
            _diff_log error "_diff_backup: failed to create backup of $file"
            return 1
        }
    fi
    return 0
}

# Count occurrences of a substring in text
# Usage: _diff_count_occurrences "text" "substring"
_diff_count_occurrences() {
    local text="$1"
    local substr="$2"
    local count=0

    if [[ -z "$substr" ]]; then
        printf '0'
        return
    fi

    local remaining="$text"
    while [[ "$remaining" == *"$substr"* ]]; do
        ((count++))
        remaining="${remaining#*"$substr"}"
    done

    printf '%d' "$count"
}

# =============================================================================
# DIFF GENERATION
# =============================================================================

# @pre: old_text and new_text are valid strings
# @post: unified diff output on stdout (empty if identical)
# @returns: 0 if different (diff produced), 1 if identical
#
# Generate unified diff between two strings.
# Uses temp files internally, cleans up after.
#
# Usage: diff_strings "old_text" "new_text" [--context N]
# Example: diff_strings "hello" "hello world"
diff_strings() {
    local old_text="$1"
    local new_text="$2"
    shift 2

    local context="$MAINFRAME_DIFF_CONTEXT"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --context) context="$2"; shift 2 ;;
            --context=*) context="${1#*=}"; shift ;;
            *) shift ;;
        esac
    done

    local tmp_old tmp_new
    tmp_old=$(mktemp "${TMPDIR:-/tmp}/mainframe_diff_old.XXXXXX")
    tmp_new=$(mktemp "${TMPDIR:-/tmp}/mainframe_diff_new.XXXXXX")

    printf '%s\n' "$old_text" > "$tmp_old"
    printf '%s\n' "$new_text" > "$tmp_new"

    local result
    result=$(diff -u --label "old" --label "new" -U "$context" "$tmp_old" "$tmp_new" 2>/dev/null)
    local rc=$?

    rm -f "$tmp_old" "$tmp_new"

    if [[ $rc -eq 0 ]]; then
        # Files are identical
        return 1
    fi

    printf '%s\n' "$result"
    return 0
}

# @pre: both files exist and are readable
# @post: unified diff output on stdout
# @returns: 0 if different, 1 if identical, 2 on error
#
# Generate unified diff between two files.
#
# Usage: diff_files "old_file" "new_file" [--context N]
diff_files() {
    local old_file="$1"
    local new_file="$2"
    shift 2

    local context="$MAINFRAME_DIFF_CONTEXT"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --context) context="$2"; shift 2 ;;
            --context=*) context="${1#*=}"; shift ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$old_file" ]]; then
        _diff_log error "diff_files: old file not found: $old_file"
        return 2
    fi
    if [[ ! -f "$new_file" ]]; then
        _diff_log error "diff_files: new file not found: $new_file"
        return 2
    fi

    local result
    result=$(diff -u -U "$context" "$old_file" "$new_file" 2>/dev/null)
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        return 1
    fi

    printf '%s\n' "$result"
    return 0
}

# @pre: file_path exists and is readable
# @post: unified diff showing what would change
# @returns: 0 if changes would occur, 1 if identical, 2 on error
#
# Generate diff between a file and new content (preview changes).
#
# Usage: diff_preview "file_path" "new_content"
diff_preview() {
    local file_path="$1"
    local new_content="$2"

    if [[ ! -f "$file_path" ]]; then
        _diff_log error "diff_preview: file not found: $file_path"
        return 2
    fi

    local old_content
    old_content=$(cat "$file_path")

    diff_strings "$old_content" "$new_content"
}

# @pre: old_text and new_text are valid strings
# @post: edit script on stdout (d=delete, a=add, c=change)
# @returns: 0 if edits exist, 1 if identical
#
# Generate a minimal line-based edit script.
# Output format: "dN" (delete line N), "aN:text" (add after N), "cN:text" (change N)
#
# Usage: diff_edit_script "old_text" "new_text"
diff_edit_script() {
    local old_text="$1"
    local new_text="$2"

    local tmp_old tmp_new
    tmp_old=$(mktemp "${TMPDIR:-/tmp}/mainframe_diff_old.XXXXXX")
    tmp_new=$(mktemp "${TMPDIR:-/tmp}/mainframe_diff_new.XXXXXX")

    printf '%s\n' "$old_text" > "$tmp_old"
    printf '%s\n' "$new_text" > "$tmp_new"

    # Use ed-style diff for edit script
    local result
    result=$(diff "$tmp_old" "$tmp_new" 2>/dev/null)
    local rc=$?

    rm -f "$tmp_old" "$tmp_new"

    if [[ $rc -eq 0 ]]; then
        return 1
    fi

    # Parse normal diff output into our edit script format
    local line
    local cmd_type="" line_num=""
    local src_start="" src_end=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9]+)(,([0-9]+))?([adc])([0-9]+)(,([0-9]+))?$ ]]; then
            src_start="${BASH_REMATCH[1]}"
            src_end="${BASH_REMATCH[3]:-$src_start}"
            cmd_type="${BASH_REMATCH[4]}"

            case "$cmd_type" in
                d)
                    local i
                    for ((i=src_start; i<=src_end; i++)); do
                        printf 'd%d\n' "$i"
                    done
                    ;;
                a)
                    # Lines following are added content
                    cmd_type="a"
                    line_num="$src_start"
                    ;;
                c)
                    # Lines following are replacement content
                    cmd_type="c"
                    line_num="$src_start"
                    ;;
            esac
        elif [[ "$line" == ">"* && "$cmd_type" == "a" ]]; then
            printf 'a%d:%s\n' "$line_num" "${line:2}"
        elif [[ "$line" == ">"* && "$cmd_type" == "c" ]]; then
            printf 'c%d:%s\n' "$line_num" "${line:2}"
            ((line_num++))
        elif [[ "$line" == "---" ]]; then
            # Separator between old and new in change blocks
            if [[ "$cmd_type" == "c" ]]; then
                line_num="$((${src_start:-1}))"
            fi
        fi
    done <<< "$result"

    return 0
}

# =============================================================================
# PATCH APPLICATION
# =============================================================================

# @pre: file_path exists and is readable, diff_text is valid unified diff
# @post: file is patched (or unchanged on dry-run/error)
# @returns: 0=applied, 1=conflict, 2=error
#
# Apply a unified diff to a file. Creates backup by default.
#
# Usage: diff_apply "file_path" "diff_text" [--backup] [--dry-run] [--fuzz N]
diff_apply() {
    local file_path="$1"
    local diff_text="$2"
    shift 2

    local do_backup="$MAINFRAME_DIFF_BACKUP"
    local dry_run=0
    local fuzz=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backup) do_backup=1; shift ;;
            --no-backup) do_backup=0; shift ;;
            --dry-run) dry_run=1; shift ;;
            --fuzz) fuzz="$2"; shift 2 ;;
            --fuzz=*) fuzz="${1#*=}"; shift ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$file_path" ]]; then
        _diff_log error "diff_apply: file not found: $file_path"
        return 2
    fi

    # Read the original file
    local original
    original=$(cat "$file_path")

    # Apply patch in memory
    local patched
    patched=$(diff_apply_string "$original" "$diff_text" "$fuzz")
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        return $rc
    fi

    # Dry run: just validate
    if [[ $dry_run -eq 1 ]]; then
        return 0
    fi

    # Create backup
    if [[ $do_backup -eq 1 ]]; then
        _diff_backup "$file_path" || return 2
    fi

    # Atomic write
    local tmpfile
    tmpfile=$(_diff_tmpfile "$file_path")
    printf '%s\n' "$patched" > "$tmpfile" || {
        rm -f "$tmpfile"
        _diff_log error "diff_apply: failed to write temp file"
        return 2
    }

    mv -f "$tmpfile" "$file_path" || {
        rm -f "$tmpfile"
        _diff_log error "diff_apply: failed to rename temp file"
        return 2
    }

    return 0
}

# @pre: original_text and diff_text are valid strings
# @post: patched text on stdout
# @returns: 0=success, 1=conflict
#
# Apply a unified diff to a string (pure in-memory).
#
# Usage: diff_apply_string "original_text" "diff_text" [fuzz]
diff_apply_string() {
    local original_text="$1"
    local diff_text="$2"
    local fuzz="${3:-0}"

    # Parse the original into an array of lines
    local -a orig_lines=()
    while IFS= read -r line; do
        orig_lines+=("$line")
    done <<< "$original_text"

    # Parse hunks from the unified diff
    local -a result_lines=()
    local orig_idx=0
    # Collect all hunks first
    local -a hunk_starts=() hunk_counts=() hunk_bodies=()
    local hunk_idx=-1

    while IFS= read -r line; do
        # Skip diff headers
        if [[ "$line" == "---"* ]] || [[ "$line" == "+++"* ]]; then
            continue
        fi

        # Parse hunk header
        if [[ "$line" =~ ^@@[[:space:]]+-([0-9]+)(,([0-9]+))?[[:space:]]+\+([0-9]+)(,([0-9]+))?[[:space:]]+@@(.*)$ ]]; then
            ((hunk_idx++))
            hunk_starts+=("${BASH_REMATCH[1]}")
            hunk_counts+=("${BASH_REMATCH[3]:-1}")
            hunk_bodies+=("")
            continue
        fi

        # Accumulate hunk body
        if [[ $hunk_idx -ge 0 ]]; then
            if [[ -n "${hunk_bodies[$hunk_idx]}" ]]; then
                hunk_bodies[$hunk_idx]+=$'\n'"$line"
            else
                hunk_bodies[$hunk_idx]="$line"
            fi
        fi
    done <<< "$diff_text"

    if [[ $hunk_idx -lt 0 ]]; then
        # No hunks found, output original
        printf '%s' "$original_text"
        return 0
    fi

    # Apply each hunk
    orig_idx=0
    local h
    for ((h=0; h<=hunk_idx; h++)); do
        local h_start="${hunk_starts[$h]}"
        local h_body="${hunk_bodies[$h]}"

        # Convert to 0-based index
        local target_idx=$((h_start - 1))

        # Fuzz: try offset adjustments if context doesn't match
        local applied=0
        local try_offset
        for ((try_offset=0; try_offset<=fuzz; try_offset++)); do
            local offsets=("$try_offset")
            [[ $try_offset -gt 0 ]] && offsets+=("-$try_offset")

            local off
            for off in "${offsets[@]}"; do
                local adj_target=$((target_idx + off))
                [[ $adj_target -lt 0 ]] && continue

                # Validate context lines at this position
                local context_ok=1
                local check_idx="$adj_target"
                while IFS= read -r hline; do
                    if [[ "$hline" == " "* ]]; then
                        local ctx_text="${hline:1}"
                        if [[ $check_idx -lt ${#orig_lines[@]} ]] && [[ "${orig_lines[$check_idx]}" == "$ctx_text" ]]; then
                            ((check_idx++))
                        else
                            context_ok=0
                            break
                        fi
                    elif [[ "$hline" == "-"* ]]; then
                        local del_text="${hline:1}"
                        if [[ $check_idx -lt ${#orig_lines[@]} ]] && [[ "${orig_lines[$check_idx]}" == "$del_text" ]]; then
                            ((check_idx++))
                        else
                            context_ok=0
                            break
                        fi
                    elif [[ "$hline" == "+"* ]]; then
                        : # additions don't consume original lines
                    fi
                done <<< "$h_body"

                if [[ $context_ok -eq 1 ]]; then
                    target_idx="$adj_target"
                    applied=1
                    break
                fi
            done
            [[ $applied -eq 1 ]] && break
        done

        if [[ $applied -eq 0 ]] && [[ $fuzz -eq 0 ]]; then
            # Verify context at original position
            local context_ok=1
            local check_idx="$target_idx"
            while IFS= read -r hline; do
                if [[ "$hline" == " "* ]]; then
                    local ctx_text="${hline:1}"
                    if [[ $check_idx -lt ${#orig_lines[@]} ]] && [[ "${orig_lines[$check_idx]}" == "$ctx_text" ]]; then
                        ((check_idx++))
                    else
                        context_ok=0
                        break
                    fi
                elif [[ "$hline" == "-"* ]]; then
                    local del_text="${hline:1}"
                    if [[ $check_idx -lt ${#orig_lines[@]} ]] && [[ "${orig_lines[$check_idx]}" == "$del_text" ]]; then
                        ((check_idx++))
                    else
                        context_ok=0
                        break
                    fi
                fi
            done <<< "$h_body"

            if [[ $context_ok -eq 0 ]]; then
                _diff_log error "diff_apply_string: context mismatch at line $((target_idx + 1))"
                return 1
            fi
        fi

        # Copy lines from orig up to the hunk start
        while [[ $orig_idx -lt $target_idx ]]; do
            result_lines+=("${orig_lines[$orig_idx]}")
            ((orig_idx++))
        done

        # Apply the hunk
        while IFS= read -r hline; do
            if [[ "$hline" == " "* ]]; then
                # Context line: keep it
                result_lines+=("${hline:1}")
                ((orig_idx++))
            elif [[ "$hline" == "-"* ]]; then
                # Deletion: skip the original line
                ((orig_idx++))
            elif [[ "$hline" == "+"* ]]; then
                # Addition: add new line
                result_lines+=("${hline:1}")
            fi
        done <<< "$h_body"
    done

    # Copy remaining lines
    while [[ $orig_idx -lt ${#orig_lines[@]} ]]; do
        result_lines+=("${orig_lines[$orig_idx]}")
        ((orig_idx++))
    done

    # Output result
    local i
    for ((i=0; i<${#result_lines[@]}; i++)); do
        if [[ $i -lt $((${#result_lines[@]} - 1)) ]]; then
            printf '%s\n' "${result_lines[$i]}"
        else
            printf '%s' "${result_lines[$i]}"
        fi
    done

    return 0
}

# @pre: file_path exists, diff_text is the diff that was previously applied
# @post: file is restored to pre-patch state
# @returns: 0=reversed, 1=conflict, 2=error
#
# Reverse-apply a diff (undo a patch).
# Swaps + and - lines in the diff then applies.
#
# Usage: diff_reverse "file_path" "diff_text"
diff_reverse() {
    local file_path="$1"
    local diff_text="$2"

    # Reverse the diff: swap + and - lines, swap hunk line numbers
    local reversed=""
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^@@[[:space:]]+-([0-9]+)(,([0-9]+))?[[:space:]]+\+([0-9]+)(,([0-9]+))?[[:space:]]+@@(.*)$ ]]; then
            # Swap the line numbers
            local old_start="${BASH_REMATCH[1]}"
            local old_count="${BASH_REMATCH[3]:-1}"
            local new_start="${BASH_REMATCH[4]}"
            local new_count="${BASH_REMATCH[6]:-1}"
            local remainder="${BASH_REMATCH[7]}"
            reversed+="@@ -${new_start},${new_count} +${old_start},${old_count} @@${remainder}"$'\n'
        elif [[ "$line" == "+"* && "$line" != "+++"* ]]; then
            reversed+="-${line:1}"$'\n'
        elif [[ "$line" == "-"* && "$line" != "---"* ]]; then
            reversed+="+${line:1}"$'\n'
        elif [[ "$line" == "---"* ]]; then
            reversed+="${line/---/+++}"$'\n'
        elif [[ "$line" == "+++"* ]]; then
            reversed+="${line/+++/---}"$'\n'
        else
            reversed+="$line"$'\n'
        fi
    done <<< "$diff_text"

    diff_apply "$file_path" "$reversed" --no-backup
}

# =============================================================================
# SEARCH-AND-REPLACE (Agent-Friendly Editing)
# =============================================================================

# @pre: file_path exists and is readable
# @post: first (or all) occurrence(s) of old_text replaced with new_text
# @returns: 0=replaced, 1=not found, 2=ambiguous (multiple without --all)
#
# Replace exact text in a file. Primary editing primitive for AI agents.
# Handles multiline text. Atomic write with optional backup.
#
# Usage: diff_replace "file_path" "old_text" "new_text" [--all] [--backup]
diff_replace() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    shift 3

    local replace_all=0
    local do_backup="$MAINFRAME_DIFF_BACKUP"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) replace_all=1; shift ;;
            --backup) do_backup=1; shift ;;
            --no-backup) do_backup=0; shift ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$file_path" ]]; then
        _diff_log error "diff_replace: file not found: $file_path"
        return 2
    fi

    if [[ -z "$old_text" ]]; then
        _diff_log error "diff_replace: old_text cannot be empty"
        return 2
    fi

    local content
    content=$(cat "$file_path")

    # Count occurrences
    local count
    count=$(_diff_count_occurrences "$content" "$old_text")

    if [[ $count -eq 0 ]]; then
        return 1
    fi

    if [[ $count -gt 1 ]] && [[ $replace_all -eq 0 ]]; then
        _diff_log error "diff_replace: $count matches found (ambiguous). Use --all to replace all."
        return 2
    fi

    # Perform replacement
    local result
    local _replace_flag=""
    [[ $replace_all -eq 1 ]] && _replace_flag="--all"
    result=$(diff_replace_string "$content" "$old_text" "$new_text" $_replace_flag)

    # Create backup
    if [[ $do_backup -eq 1 ]]; then
        _diff_backup "$file_path" || return 2
    fi

    # Atomic write
    local tmpfile
    tmpfile=$(_diff_tmpfile "$file_path")
    printf '%s' "$result" > "$tmpfile" || {
        rm -f "$tmpfile"
        return 2
    }

    mv -f "$tmpfile" "$file_path" || {
        rm -f "$tmpfile"
        return 2
    }

    return 0
}

# @pre: original, old_text, new_text are valid strings
# @post: modified text on stdout
# @returns: 0
#
# Replace text in a string. Handles multiline.
#
# Usage: diff_replace_string "original" "old_text" "new_text" [--all]
diff_replace_string() {
    local original="$1"
    local old_text="$2"
    local new_text="$3"
    local replace_all=0

    [[ "${4:-}" == "--all" ]] && replace_all=1

    if [[ $replace_all -eq 1 ]]; then
        # Replace all occurrences
        local result="$original"
        while [[ "$result" == *"$old_text"* ]]; do
            local before="${result%%"$old_text"*}"
            local after="${result#*"$old_text"}"
            result="${before}${new_text}${after}"
        done
        printf '%s' "$result"
    else
        # Replace first occurrence only
        if [[ "$original" == *"$old_text"* ]]; then
            local before="${original%%"$old_text"*}"
            local after="${original#*"$old_text"}"
            printf '%s' "${before}${new_text}${after}"
        else
            printf '%s' "$original"
        fi
    fi
}

# @pre: file_path exists, match_line found in file
# @post: new_text inserted after matching line
# @returns: 0=inserted, 1=match not found
#
# Insert text after a matching line in a file.
#
# Usage: diff_insert_after "file_path" "match_line" "new_text"
diff_insert_after() {
    local file_path="$1"
    local match_line="$2"
    local new_text="$3"

    if [[ ! -f "$file_path" ]]; then
        _diff_log error "diff_insert_after: file not found: $file_path"
        return 1
    fi

    local found=0
    local -a result_lines=()

    while IFS= read -r line; do
        result_lines+=("$line")
        if [[ "$line" == "$match_line" ]] && [[ $found -eq 0 ]]; then
            found=1
            # Add new text lines
            while IFS= read -r new_line; do
                result_lines+=("$new_line")
            done <<< "$new_text"
        fi
    done < "$file_path"

    if [[ $found -eq 0 ]]; then
        return 1
    fi

    # Write result
    local tmpfile
    tmpfile=$(_diff_tmpfile "$file_path")
    printf '%s\n' "${result_lines[@]}" > "$tmpfile" || {
        rm -f "$tmpfile"
        return 1
    }

    mv -f "$tmpfile" "$file_path" || {
        rm -f "$tmpfile"
        return 1
    }

    return 0
}

# @pre: file_path exists, match_line found in file
# @post: new_text inserted before matching line
# @returns: 0=inserted, 1=match not found
#
# Insert text before a matching line in a file.
#
# Usage: diff_insert_before "file_path" "match_line" "new_text"
diff_insert_before() {
    local file_path="$1"
    local match_line="$2"
    local new_text="$3"

    if [[ ! -f "$file_path" ]]; then
        _diff_log error "diff_insert_before: file not found: $file_path"
        return 1
    fi

    local found=0
    local -a result_lines=()

    while IFS= read -r line; do
        if [[ "$line" == "$match_line" ]] && [[ $found -eq 0 ]]; then
            found=1
            # Add new text lines before the match
            while IFS= read -r new_line; do
                result_lines+=("$new_line")
            done <<< "$new_text"
        fi
        result_lines+=("$line")
    done < "$file_path"

    if [[ $found -eq 0 ]]; then
        return 1
    fi

    # Write result
    local tmpfile
    tmpfile=$(_diff_tmpfile "$file_path")
    printf '%s\n' "${result_lines[@]}" > "$tmpfile" || {
        rm -f "$tmpfile"
        return 1
    }

    mv -f "$tmpfile" "$file_path" || {
        rm -f "$tmpfile"
        return 1
    }

    return 0
}

# @pre: file_path exists
# @post: lines matching pattern are removed
# @returns: 0=deleted, 1=no matches
#
# Delete lines matching a pattern from a file.
#
# Usage: diff_delete_lines "file_path" "pattern" [--regex]
diff_delete_lines() {
    local file_path="$1"
    local pattern="$2"
    shift 2

    local use_regex=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --regex) use_regex=1; shift ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$file_path" ]]; then
        _diff_log error "diff_delete_lines: file not found: $file_path"
        return 1
    fi

    local found=0
    local -a result_lines=()

    while IFS= read -r line; do
        local match=0
        if [[ $use_regex -eq 1 ]]; then
            [[ "$line" =~ $pattern ]] && match=1
        else
            [[ "$line" == *"$pattern"* ]] && match=1
        fi

        if [[ $match -eq 1 ]]; then
            found=1
        else
            result_lines+=("$line")
        fi
    done < "$file_path"

    if [[ $found -eq 0 ]]; then
        return 1
    fi

    # Write result
    local tmpfile
    tmpfile=$(_diff_tmpfile "$file_path")
    if [[ ${#result_lines[@]} -eq 0 ]]; then
        printf '' > "$tmpfile"
    else
        printf '%s\n' "${result_lines[@]}" > "$tmpfile"
    fi

    mv -f "$tmpfile" "$file_path" || {
        rm -f "$tmpfile"
        return 1
    }

    return 0
}

# @pre: file_path exists, start_line and end_line are valid
# @post: lines from start_line to end_line replaced with new_text
# @returns: 0=replaced, 1=error
#
# Replace a range of lines in a file (1-based line numbers).
#
# Usage: diff_replace_range "file_path" start_line end_line "new_text"
diff_replace_range() {
    local file_path="$1"
    local start_line="$2"
    local end_line="$3"
    local new_text="$4"

    if [[ ! -f "$file_path" ]]; then
        _diff_log error "diff_replace_range: file not found: $file_path"
        return 1
    fi

    if [[ $start_line -lt 1 ]] || [[ $end_line -lt $start_line ]]; then
        _diff_log error "diff_replace_range: invalid range $start_line-$end_line"
        return 1
    fi

    local -a result_lines=()
    local line_num=0
    local replaced=0

    while IFS= read -r line; do
        ((line_num++))
        if [[ $line_num -eq $start_line ]]; then
            # Insert new text
            if [[ -n "$new_text" ]]; then
                while IFS= read -r new_line; do
                    result_lines+=("$new_line")
                done <<< "$new_text"
            fi
            replaced=1
        elif [[ $line_num -gt $start_line ]] && [[ $line_num -le $end_line ]]; then
            # Skip lines in range
            continue
        else
            result_lines+=("$line")
        fi
    done < "$file_path"

    if [[ $replaced -eq 0 ]]; then
        _diff_log error "diff_replace_range: start_line $start_line exceeds file length"
        return 1
    fi

    # Write result
    local tmpfile
    tmpfile=$(_diff_tmpfile "$file_path")
    if [[ ${#result_lines[@]} -eq 0 ]]; then
        printf '' > "$tmpfile"
    else
        printf '%s\n' "${result_lines[@]}" > "$tmpfile"
    fi

    mv -f "$tmpfile" "$file_path" || {
        rm -f "$tmpfile"
        return 1
    }

    return 0
}

# =============================================================================
# CONFLICT DETECTION
# =============================================================================

# @pre: file_path exists, diff_text is unified diff
# @post: returns whether diff applies cleanly
# @returns: 0=clean, 1=conflicts exist
#
# Check if a diff can be cleanly applied.
#
# Usage: diff_can_apply "file_path" "diff_text"
diff_can_apply() {
    local file_path="$1"
    local diff_text="$2"

    if [[ ! -f "$file_path" ]]; then
        return 1
    fi

    local original
    original=$(cat "$file_path")

    diff_apply_string "$original" "$diff_text" >/dev/null 2>&1
}

# @pre: file_path exists, diff_text is unified diff
# @post: JSON array of conflict descriptions on stdout
# @returns: 0
#
# Show what conflicts would occur if diff were applied.
#
# Usage: diff_conflicts "file_path" "diff_text"
diff_conflicts() {
    local file_path="$1"
    local diff_text="$2"

    if [[ ! -f "$file_path" ]]; then
        printf '[{"line":0,"type":"error","message":"file not found: %s"}]' "$file_path"
        return 0
    fi

    local -a orig_lines=()
    while IFS= read -r line; do
        orig_lines+=("$line")
    done < "$file_path"

    local conflicts="["
    local first=1
    local hunk_num=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^@@[[:space:]]+-([0-9]+)(,([0-9]+))?[[:space:]]+\+([0-9]+)(,([0-9]+))?[[:space:]]+@@(.*)$ ]]; then
            ((hunk_num++))
            local h_start="${BASH_REMATCH[1]}"
            local check_idx=$((h_start - 1))
        elif [[ "$line" == " "* ]]; then
            local ctx="${line:1}"
            if [[ $check_idx -ge ${#orig_lines[@]} ]] || [[ "${orig_lines[$check_idx]:-}" != "$ctx" ]]; then
                [[ $first -eq 0 ]] && conflicts+=","
                first=0
                conflicts+="{\"line\":$((check_idx + 1)),\"type\":\"context_mismatch\",\"expected\":\"${ctx//\"/\\\"}\",\"actual\":\"${orig_lines[$check_idx]:-EOF}\"}"
            fi
            ((check_idx++))
        elif [[ "$line" == "-"* && "$line" != "---"* ]]; then
            local del="${line:1}"
            if [[ $check_idx -ge ${#orig_lines[@]} ]] || [[ "${orig_lines[$check_idx]:-}" != "$del" ]]; then
                [[ $first -eq 0 ]] && conflicts+=","
                first=0
                conflicts+="{\"line\":$((check_idx + 1)),\"type\":\"delete_mismatch\",\"expected\":\"${del//\"/\\\"}\",\"actual\":\"${orig_lines[$check_idx]:-EOF}\"}"
            fi
            ((check_idx++))
        fi
    done <<< "$diff_text"

    conflicts+="]"
    printf '%s' "$conflicts"
}

# @pre: file_path exists, old_text is non-empty
# @post: match count on stdout
# @returns: 0=unique, 1=not found, 2=multiple matches
#
# Validate that old_text exists exactly once in file.
#
# Usage: diff_validate_unique "file_path" "old_text"
diff_validate_unique() {
    local file_path="$1"
    local old_text="$2"

    if [[ ! -f "$file_path" ]]; then
        printf '0'
        return 1
    fi

    local content
    content=$(cat "$file_path")

    local count
    count=$(_diff_count_occurrences "$content" "$old_text")

    printf '%d' "$count"

    if [[ $count -eq 0 ]]; then
        return 1
    elif [[ $count -eq 1 ]]; then
        return 0
    else
        return 2
    fi
}

# =============================================================================
# DIFF ANALYSIS
# =============================================================================

# @pre: diff_text is a valid unified diff
# @post: JSON object with stats on stdout
# @returns: 0
#
# Count changes in a unified diff.
#
# Usage: diff_stats "diff_text"
# Output: {"additions":N,"deletions":N,"changes":N,"files":N}
diff_stats() {
    local diff_text="$1"

    local additions=0
    local deletions=0
    local files=0

    while IFS= read -r line; do
        if [[ "$line" == "+++"* ]]; then
            ((files++))
        elif [[ "$line" == "+"* && "$line" != "+++"* ]]; then
            ((additions++))
        elif [[ "$line" == "-"* && "$line" != "---"* ]]; then
            ((deletions++))
        fi
    done <<< "$diff_text"

    local changes=$((additions + deletions))
    printf '{"additions":%d,"deletions":%d,"changes":%d,"files":%d}' \
        "$additions" "$deletions" "$changes" "$files"
}

# @pre: diff_text is a valid unified diff
# @post: lines prefixed with + or - on stdout
# @returns: 0
#
# Extract just the changed lines from a diff.
#
# Usage: diff_changed_lines "diff_text"
diff_changed_lines() {
    local diff_text="$1"

    while IFS= read -r line; do
        if [[ "$line" == "+"* && "$line" != "+++"* ]]; then
            printf '%s\n' "$line"
        elif [[ "$line" == "-"* && "$line" != "---"* ]]; then
            printf '%s\n' "$line"
        fi
    done <<< "$diff_text"
}

# @pre: diff_text is a valid unified diff
# @post: affected line numbers on stdout (one per line)
# @returns: 0
#
# Get the line numbers affected by a diff (in the original file).
#
# Usage: diff_affected_lines "diff_text"
diff_affected_lines() {
    local diff_text="$1"

    local current_line=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^@@[[:space:]]+-([0-9]+)(,([0-9]+))?[[:space:]] ]]; then
            current_line="${BASH_REMATCH[1]}"
        elif [[ "$line" == " "* ]]; then
            ((current_line++))
        elif [[ "$line" == "-"* && "$line" != "---"* ]]; then
            printf '%d\n' "$current_line"
            ((current_line++))
        elif [[ "$line" == "+"* && "$line" != "+++"* ]]; then
            printf '%d\n' "$current_line"
            # Don't increment current_line for additions (they're new lines)
        fi
    done <<< "$diff_text"
}

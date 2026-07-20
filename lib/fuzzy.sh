#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/fuzzy.sh - Fuzzy String Matching Library
# =============================================================================
# Description: Comprehensive fuzzy string matching, edit distances, phonetic
#              encoding, and approximate search algorithms in pure bash.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================
#
# ALGORITHMS IMPLEMENTED:
#   - Levenshtein distance (edit distance)
#   - Damerau-Levenshtein (with transpositions)
#   - Hamming distance (same-length strings)
#   - Jaro similarity
#   - Jaro-Winkler similarity (prefix bonus)
#   - Longest Common Substring/Subsequence
#   - Fuzzy matching (fzf-style)
#   - N-gram similarity
#   - Soundex phonetic encoding
#   - Metaphone phonetic encoding
#   - Double Metaphone
#   - QWERTY keyboard distance
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_FUZZY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_FUZZY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Global fuzzy match threshold (0.0 - 1.0)
FUZZY_THRESHOLD="${FUZZY_THRESHOLD:-0.6}"

# Default algorithm for fuzzy operations
FUZZY_ALGORITHM="${FUZZY_ALGORITHM:-levenshtein}"

# Enable case-insensitive matching by default
FUZZY_CASE_INSENSITIVE="${FUZZY_CASE_INSENSITIVE:-1}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Minimum of two integers
_fuzzy_min() {
    (( $1 < $2 )) && printf '%d' "$1" || printf '%d' "$2"
}

# Minimum of three integers
_fuzzy_min3() {
    local a="$1" b="$2" c="$3"
    local min="$a"
    (( b < min )) && min="$b"
    (( c < min )) && min="$c"
    printf '%d' "$min"
}

# Maximum of two integers
_fuzzy_max() {
    (( $1 > $2 )) && printf '%d' "$1" || printf '%d' "$2"
}

# Normalize string for fuzzy matching
_fuzzy_normalize() {
    local str="$1"

    if [[ "$FUZZY_CASE_INSENSITIVE" == "1" ]]; then
        str="${str,,}"
    fi

    # Collapse whitespace
    str="${str//[$'\t\n\r']/ }"
    str="$(printf '%s' "$str" | tr -s ' ')"
    str="${str# }"
    str="${str% }"

    printf '%s' "$str"
}

# JSON escape helper
_fuzzy_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# =============================================================================
# EDIT DISTANCE ALGORITHMS
# =============================================================================

# @pre: s1 and s2 are valid strings
# @post: returns non-negative integer edit distance
# @idempotent: yes
# @returns: Levenshtein edit distance between two strings
#
# Calculate the Levenshtein distance (minimum single-character edits:
# insertions, deletions, or substitutions) to transform s1 into s2.
#
# Time Complexity: O(m*n) where m,n are string lengths
# Space Complexity: O(min(m,n)) using two-row optimization
#
# Usage: levenshtein_distance "kitten" "sitting"
# Output: 3
levenshtein_distance() {
    local s1="$1"
    local s2="$2"

    # Handle empty strings
    [[ -z "$s1" ]] && { printf '%d' "${#s2}"; return 0; }
    [[ -z "$s2" ]] && { printf '%d' "${#s1}"; return 0; }

    local len1="${#s1}"
    local len2="${#s2}"

    # Optimize: ensure s1 is the shorter string
    if (( len1 > len2 )); then
        local tmp="$s1"
        s1="$s2"
        s2="$tmp"
        tmp="$len1"
        len1="$len2"
        len2="$tmp"
    fi

    # Previous and current row
    local -a prev curr
    local i j cost

    # Initialize previous row
    for ((i = 0; i <= len1; i++)); do
        prev[i]=$i
    done

    # Fill in the matrix row by row
    for ((j = 1; j <= len2; j++)); do
        curr[0]=$j

        for ((i = 1; i <= len1; i++)); do
            if [[ "${s1:i-1:1}" == "${s2:j-1:1}" ]]; then
                cost=0
            else
                cost=1
            fi

            # min(deletion, insertion, substitution)
            curr[i]=$(_fuzzy_min3 $((prev[i] + 1)) $((curr[i-1] + 1)) $((prev[i-1] + cost)))
        done

        # Swap rows
        prev=("${curr[@]}")
    done

    printf '%d' "${prev[len1]}"
}

# @pre: s1 and s2 are valid strings
# @post: returns float in range [0.0, 1.0]
# @idempotent: yes
# @returns: Normalized Levenshtein similarity (1 - distance/max_len)
#
# Calculate similarity as a ratio. 1.0 = identical, 0.0 = completely different.
#
# Usage: levenshtein_similarity "hello" "hallo"
# Output: 0.8
levenshtein_similarity() {
    local s1="$1"
    local s2="$2"

    # Identical strings
    [[ "$s1" == "$s2" ]] && { printf '1.0'; return 0; }

    # Both empty
    [[ -z "$s1" && -z "$s2" ]] && { printf '1.0'; return 0; }

    local distance
    distance=$(levenshtein_distance "$s1" "$s2")

    local max_len
    max_len=$(_fuzzy_max "${#s1}" "${#s2}")

    # Calculate similarity: 1 - (distance / max_len)
    # Bash doesn't do floats, so we multiply by 1000 for precision
    local similarity
    similarity=$((1000 - (distance * 1000 / max_len)))

    # Format as decimal
    local int_part=$((similarity / 1000))
    local dec_part=$((similarity % 1000))

    printf '%d.%03d' "$int_part" "$dec_part"
}

# @pre: s1 and s2 are valid strings
# @post: returns non-negative integer distance
# @idempotent: yes
# @returns: Damerau-Levenshtein distance (with transpositions)
#
# Like Levenshtein but also counts transpositions of adjacent characters
# as a single edit (e.g., "ab" -> "ba" has distance 1, not 2).
#
# Usage: damerau_levenshtein "ca" "abc"
# Output: 2
damerau_levenshtein() {
    local s1="$1"
    local s2="$2"

    [[ -z "$s1" ]] && { printf '%d' "${#s2}"; return 0; }
    [[ -z "$s2" ]] && { printf '%d' "${#s1}"; return 0; }

    local len1="${#s1}"
    local len2="${#s2}"

    # Create 2D array using associative array
    declare -A d
    local i j cost

    # Initialize
    for ((i = 0; i <= len1; i++)); do
        d[$i,0]=$i
    done
    for ((j = 0; j <= len2; j++)); do
        d[0,$j]=$j
    done

    # Fill matrix
    for ((i = 1; i <= len1; i++)); do
        for ((j = 1; j <= len2; j++)); do
            if [[ "${s1:i-1:1}" == "${s2:j-1:1}" ]]; then
                cost=0
            else
                cost=1
            fi

            # Standard Levenshtein operations
            d[$i,$j]=$(_fuzzy_min3 \
                $((d[$((i-1)),$j] + 1)) \
                $((d[$i,$((j-1))] + 1)) \
                $((d[$((i-1)),$((j-1))] + cost)))

            # Transposition check
            if (( i > 1 && j > 1 )); then
                if [[ "${s1:i-1:1}" == "${s2:j-2:1}" && "${s1:i-2:1}" == "${s2:j-1:1}" ]]; then
                    local trans_cost=$((d[$((i-2)),$((j-2))] + cost))
                    (( trans_cost < d[$i,$j] )) && d[$i,$j]=$trans_cost
                fi
            fi
        done
    done

    printf '%d' "${d[$len1,$len2]}"
}

# @pre: s1 and s2 are strings of equal length
# @post: returns non-negative integer distance
# @idempotent: yes
# @returns: Hamming distance (positions where characters differ)
#
# Counts the number of positions at which the corresponding characters differ.
# Only valid for strings of equal length.
#
# Usage: hamming_distance "karolin" "kathrin"
# Output: 3
hamming_distance() {
    local s1="$1"
    local s2="$2"

    # Validate equal length
    if [[ "${#s1}" -ne "${#s2}" ]]; then
        printf '{"error":true,"msg":"strings must be equal length","len1":%d,"len2":%d}\n' \
            "${#s1}" "${#s2}" >&2
        return 1
    fi

    local distance=0
    local i

    for ((i = 0; i < ${#s1}; i++)); do
        [[ "${s1:i:1}" != "${s2:i:1}" ]] && ((distance++))
    done

    printf '%d' "$distance"
}

# @pre: s1 and s2 are valid strings
# @post: returns float in range [0.0, 1.0]
# @idempotent: yes
# @returns: Jaro similarity score
#
# Jaro similarity accounts for transpositions and matching characters
# within a specific window. Higher values indicate more similarity.
#
# Formula: jaro = (m/|s1| + m/|s2| + (m-t)/m) / 3
#   where m = matching chars, t = transpositions / 2
#
# Usage: jaro_distance "MARTHA" "MARHTA"
# Output: 0.944
jaro_distance() {
    local s1="$1"
    local s2="$2"

    [[ "$s1" == "$s2" ]] && { printf '1.000'; return 0; }

    local len1="${#s1}"
    local len2="${#s2}"

    [[ "$len1" -eq 0 || "$len2" -eq 0 ]] && { printf '0.000'; return 0; }

    # Calculate match window
    local match_window max_len
    max_len=$(_fuzzy_max "$len1" "$len2")
    match_window=$(( max_len / 2 - 1 ))
    (( match_window < 0 )) && match_window=0

    # Track matches
    local -a s1_matches s2_matches
    local i j

    for ((i = 0; i < len1; i++)); do
        s1_matches[i]=0
    done
    for ((j = 0; j < len2; j++)); do
        s2_matches[j]=0
    done

    local matches=0
    local transpositions=0

    # Find matches
    for ((i = 0; i < len1; i++)); do
        local start=$((i - match_window))
        local end=$((i + match_window + 1))
        (( start < 0 )) && start=0
        (( end > len2 )) && end=$len2

        for ((j = start; j < end; j++)); do
            if [[ "${s2_matches[j]}" -eq 0 && "${s1:i:1}" == "${s2:j:1}" ]]; then
                s1_matches[i]=1
                s2_matches[j]=1
                ((matches++))
                break
            fi
        done
    done

    [[ "$matches" -eq 0 ]] && { printf '0.000'; return 0; }

    # Count transpositions
    local k=0
    for ((i = 0; i < len1; i++)); do
        if [[ "${s1_matches[i]}" -eq 1 ]]; then
            while [[ "${s2_matches[k]}" -eq 0 ]]; do
                ((k++))
            done
            if [[ "${s1:i:1}" != "${s2:k:1}" ]]; then
                ((transpositions++))
            fi
            ((k++))
        fi
    done

    transpositions=$((transpositions / 2))

    # Calculate Jaro similarity (using integer math * 1000)
    local jaro
    jaro=$(( (matches * 1000 / len1 + matches * 1000 / len2 + (matches - transpositions) * 1000 / matches) / 3 ))

    local int_part=$((jaro / 1000))
    local dec_part=$((jaro % 1000))

    printf '%d.%03d' "$int_part" "$dec_part"
}

# @pre: s1 and s2 are valid strings
# @post: returns float in range [0.0, 1.0]
# @idempotent: yes
# @returns: Jaro-Winkler similarity (prefix-boosted)
#
# Jaro-Winkler adds a prefix bonus for strings that match from the start.
# The scaling factor (p) defaults to 0.1.
#
# Formula: jw = jaro + (prefix_len * p * (1 - jaro))
#
# Usage: jaro_winkler_distance "MARTHA" "MARHTA"
# Output: 0.961
jaro_winkler_distance() {
    local s1="$1"
    local s2="$2"
    local p="${3:-100}"  # Scale factor * 1000 (0.1 = 100)

    local jaro
    jaro=$(jaro_distance "$s1" "$s2")

    # Parse jaro as integer (multiply by 1000)
    local jaro_int
    jaro_int=$(printf '%s' "$jaro" | tr -d '.')

    # Calculate common prefix (max 4 characters)
    local prefix_len=0
    local max_prefix=4
    local i

    for ((i = 0; i < max_prefix && i < ${#s1} && i < ${#s2}; i++)); do
        if [[ "${s1:i:1}" == "${s2:i:1}" ]]; then
            ((prefix_len++))
        else
            break
        fi
    done

    # Calculate Jaro-Winkler: jw = jaro + (prefix * p * (1 - jaro))
    # Using integer math: jw_int = jaro_int + (prefix * p * (1000 - jaro_int) / 1000)
    local jw_int
    jw_int=$(( jaro_int + (prefix_len * p * (1000 - jaro_int) / 1000) ))

    local int_part=$((jw_int / 1000))
    local dec_part=$((jw_int % 1000))

    printf '%d.%03d' "$int_part" "$dec_part"
}

# =============================================================================
# LONGEST COMMON SUBSTRING/SUBSEQUENCE
# =============================================================================

# @pre: s1 and s2 are valid strings
# @post: returns the longest common substring
# @idempotent: yes
# @returns: Longest common contiguous substring
#
# Find the longest substring that appears in both strings.
#
# Usage: longest_common_substring "ABABC" "BABCA"
# Output: BABC
longest_common_substring() {
    local s1="$1"
    local s2="$2"

    [[ -z "$s1" || -z "$s2" ]] && { printf ''; return 0; }

    local len1="${#s1}"
    local len2="${#s2}"

    # Optimize: ensure s1 is the shorter string
    if (( len1 > len2 )); then
        local tmp="$s1"
        s1="$s2"
        s2="$tmp"
        tmp="$len1"
        len1="$len2"
        len2="$tmp"
    fi

    local -a prev curr
    local i j
    local max_len=0
    local end_idx=0

    # Initialize
    for ((i = 0; i <= len1; i++)); do
        prev[i]=0
        curr[i]=0
    done

    # Dynamic programming
    for ((j = 1; j <= len2; j++)); do
        for ((i = 1; i <= len1; i++)); do
            if [[ "${s1:i-1:1}" == "${s2:j-1:1}" ]]; then
                curr[i]=$((prev[i-1] + 1))
                if (( curr[i] > max_len )); then
                    max_len=${curr[i]}
                    end_idx=$i
                fi
            else
                curr[i]=0
            fi
        done
        prev=("${curr[@]}")
    done

    # Extract the substring
    if (( max_len > 0 )); then
        printf '%s' "${s1:end_idx-max_len:max_len}"
    fi
}

# @pre: s1 and s2 are valid strings
# @post: returns the longest common subsequence
# @idempotent: yes
# @returns: Longest common subsequence (not necessarily contiguous)
#
# Find the longest subsequence present in both strings.
#
# Usage: longest_common_subsequence "AGGTAB" "GXTXAYB"
# Output: GTAB
longest_common_subsequence() {
    local s1="$1"
    local s2="$2"

    [[ -z "$s1" || -z "$s2" ]] && { printf ''; return 0; }

    local len1="${#s1}"
    local len2="${#s2}"

    # Build LCS length matrix
    declare -A dp
    local i j

    for ((i = 0; i <= len1; i++)); do
        dp[$i,0]=0
    done
    for ((j = 0; j <= len2; j++)); do
        dp[0,$j]=0
    done

    for ((i = 1; i <= len1; i++)); do
        for ((j = 1; j <= len2; j++)); do
            if [[ "${s1:i-1:1}" == "${s2:j-1:1}" ]]; then
                dp[$i,$j]=$((dp[$((i-1)),$((j-1))] + 1))
            else
                local up="${dp[$((i-1)),$j]}"
                local left="${dp[$i,$((j-1))]}"
                dp[$i,$j]=$(_fuzzy_max "$up" "$left")
            fi
        done
    done

    # Backtrack to find the actual sequence
    local lcs=""
    i=$len1
    j=$len2

    while (( i > 0 && j > 0 )); do
        if [[ "${s1:i-1:1}" == "${s2:j-1:1}" ]]; then
            lcs="${s1:i-1:1}$lcs"
            ((i--))
            ((j--))
        elif (( dp[$((i-1)),$j] > dp[$i,$((j-1))] )); then
            ((i--))
        else
            ((j--))
        fi
    done

    printf '%s' "$lcs"
}

# @pre: s1 and s2 are valid strings
# @post: returns non-negative integer length
# @idempotent: yes
# @returns: Length of longest common subsequence
#
# More efficient than longest_common_subsequence when you only need length.
#
# Usage: lcs_length "AGGTAB" "GXTXAYB"
# Output: 4
lcs_length() {
    local s1="$1"
    local s2="$2"

    [[ -z "$s1" || -z "$s2" ]] && { printf '0'; return 0; }

    local len1="${#s1}"
    local len2="${#s2}"

    # Optimize: use shorter string for columns
    if (( len1 > len2 )); then
        local tmp="$s1"
        s1="$s2"
        s2="$tmp"
        tmp="$len1"
        len1="$len2"
        len2="$tmp"
    fi

    local -a prev curr
    local i j

    for ((i = 0; i <= len1; i++)); do
        prev[i]=0
    done

    for ((j = 1; j <= len2; j++)); do
        curr[0]=0
        for ((i = 1; i <= len1; i++)); do
            if [[ "${s1:i-1:1}" == "${s2:j-1:1}" ]]; then
                curr[i]=$((prev[i-1] + 1))
            else
                curr[i]=$(_fuzzy_max "${prev[i]}" "${curr[i-1]}")
            fi
        done
        prev=("${curr[@]}")
    done

    printf '%d' "${prev[len1]}"
}

# =============================================================================
# FUZZY MATCHING (FZF-STYLE)
# =============================================================================

# @pre: pattern and string are valid
# @post: returns 0 if pattern fuzzy-matches, 1 otherwise
# @idempotent: yes
# @returns: 0 if match, 1 if no match
#
# Check if pattern characters appear in order in the string (fzf-style).
# Pattern "abc" matches "a_b_c", "abc", "aXbYcZ", etc.
#
# Usage: fuzzy_match "abc" "a1b2c3" && echo "matches"
fuzzy_match() {
    local pattern="$1"
    local string="$2"

    [[ -z "$pattern" ]] && return 0
    [[ -z "$string" ]] && return 1

    # Normalize if case-insensitive
    if [[ "$FUZZY_CASE_INSENSITIVE" == "1" ]]; then
        pattern="${pattern,,}"
        string="${string,,}"
    fi

    local pi=0
    local si=0
    local plen="${#pattern}"
    local slen="${#string}"

    while (( pi < plen && si < slen )); do
        if [[ "${pattern:pi:1}" == "${string:si:1}" ]]; then
            ((pi++))
        fi
        ((si++))
    done

    (( pi == plen ))
}

# @pre: pattern and string are valid
# @post: returns non-negative integer score
# @idempotent: yes
# @returns: Fuzzy match score (higher = better match)
#
# Score based on consecutive matches, word boundaries, and positions.
# Uses fzf-style scoring algorithm.
#
# Usage: fuzzy_score "abc" "a_b_c"
# Output: 12
fuzzy_score() {
    local pattern="$1"
    local string="$2"

    [[ -z "$pattern" ]] && { printf '0'; return 0; }
    [[ -z "$string" ]] && { printf '0'; return 0; }

    local orig_string="$string"

    # Normalize if case-insensitive
    if [[ "$FUZZY_CASE_INSENSITIVE" == "1" ]]; then
        pattern="${pattern,,}"
        string="${string,,}"
    fi

    local pi=0
    local si=0
    local plen="${#pattern}"
    local slen="${#string}"

    local score=0
    local consecutive=0
    local prev_match=-2

    while (( pi < plen && si < slen )); do
        local pchar="${pattern:pi:1}"
        local schar="${string:si:1}"

        if [[ "$pchar" == "$schar" ]]; then
            # Base score for match
            ((score += 16))

            # Bonus for consecutive matches
            if (( prev_match == si - 1 )); then
                ((consecutive++))
                ((score += consecutive * 8))
            else
                consecutive=0
            fi

            # Bonus for matching at word boundary
            if (( si == 0 )); then
                ((score += 32))
            elif [[ "${string:si-1:1}" =~ [[:space:]_\-/\.] ]]; then
                ((score += 24))
            fi

            # Bonus for matching uppercase in camelCase
            if [[ "${orig_string:si:1}" =~ [A-Z] ]]; then
                ((score += 16))
            fi

            # Bonus for exact case match
            if [[ "$FUZZY_CASE_INSENSITIVE" == "1" ]]; then
                if [[ "${pattern:pi:1}" == "${orig_string:si:1}" ]]; then
                    ((score += 4))
                fi
            fi

            prev_match=$si
            ((pi++))
        fi
        ((si++))
    done

    # Penalty for unmatched pattern characters
    if (( pi < plen )); then
        printf '0'
        return 0
    fi

    # Bonus for shorter strings (more precise match)
    ((score += 100 - slen))

    # Ensure non-negative
    (( score < 0 )) && score=0

    printf '%d' "$score"
}

# @pre: pattern and string are valid
# @post: returns JSON array of matched positions
# @idempotent: yes
# @returns: Array of indices where pattern characters match
#
# Usage: fuzzy_match_positions "abc" "a1b2c3"
# Output: [0,2,4]
fuzzy_match_positions() {
    local pattern="$1"
    local string="$2"

    [[ -z "$pattern" ]] && { printf '[]'; return 0; }
    [[ -z "$string" ]] && { printf '[]'; return 0; }

    # Normalize if case-insensitive
    if [[ "$FUZZY_CASE_INSENSITIVE" == "1" ]]; then
        pattern="${pattern,,}"
        string="${string,,}"
    fi

    local -a positions
    local pi=0
    local si=0
    local plen="${#pattern}"
    local slen="${#string}"

    while (( pi < plen && si < slen )); do
        if [[ "${pattern:pi:1}" == "${string:si:1}" ]]; then
            positions+=("$si")
            ((pi++))
        fi
        ((si++))
    done

    # Return as JSON array
    printf '['
    local first=true
    for pos in "${positions[@]}"; do
        $first || printf ','
        first=false
        printf '%d' "$pos"
    done
    printf ']'
}

# @pre: pattern and string are valid
# @post: returns string with ANSI highlighting
# @idempotent: yes
# @returns: String with matched characters highlighted
#
# Usage: fuzzy_highlight "abc" "a1b2c3"
# Output: [a]1[b]2[c]3 (with ANSI codes)
fuzzy_highlight() {
    local pattern="$1"
    local string="$2"
    local highlight_start="${3:-\033[1;32m}"  # Bold green
    local highlight_end="${4:-\033[0m}"       # Reset

    [[ -z "$pattern" ]] && { printf '%s' "$string"; return 0; }
    [[ -z "$string" ]] && { printf ''; return 0; }

    local match_pattern="$pattern"
    local match_string="$string"

    # Normalize if case-insensitive
    if [[ "$FUZZY_CASE_INSENSITIVE" == "1" ]]; then
        match_pattern="${match_pattern,,}"
        match_string="${match_string,,}"
    fi

    local result=""
    local pi=0
    local si=0
    local plen="${#match_pattern}"
    local slen="${#string}"

    while (( si < slen )); do
        if (( pi < plen )) && [[ "${match_pattern:pi:1}" == "${match_string:si:1}" ]]; then
            result+="${highlight_start}${string:si:1}${highlight_end}"
            ((pi++))
        else
            result+="${string:si:1}"
        fi
        ((si++))
    done

    printf '%s' "$result"
}

# @pre: pattern and string are valid
# @post: returns 0 if fuzzy substring found, 1 otherwise
# @idempotent: yes
# @returns: 0 if pattern fuzzy-contained in string
#
# Like fuzzy_match but with threshold tolerance.
#
# Usage: fuzzy_contains "helo" "hello world"
fuzzy_contains() {
    local pattern="$1"
    local string="$2"
    local threshold="${3:-$FUZZY_THRESHOLD}"

    [[ -z "$pattern" ]] && return 0
    [[ -z "$string" ]] && return 1

    # First try exact fuzzy match
    if fuzzy_match "$pattern" "$string"; then
        return 0
    fi

    # Then try similarity threshold
    local sim
    sim=$(levenshtein_similarity "$pattern" "$string")

    # Compare using integer math (sim * 1000 vs threshold * 1000)
    local sim_int threshold_int
    sim_int=$(printf '%s' "$sim" | tr -d '.')
    threshold_int=$(printf '%s' "$threshold" | tr -d '.')

    # Pad threshold to 4 digits if needed
    while (( ${#threshold_int} < 4 )); do
        threshold_int+="0"
    done
    while (( ${#sim_int} < 4 )); do
        sim_int+="0"
    done

    (( sim_int >= threshold_int ))
}

# =============================================================================
# ARRAY/LIST OPERATIONS
# =============================================================================

# @pre: pattern is valid, remaining args are array elements
# @post: prints matching elements (one per line)
# @idempotent: yes
# @returns: Lines of matching items
#
# Filter an array by fuzzy pattern, returning all matches.
#
# Usage: fuzzy_filter "py" "python" "ruby" "php" "perl"
# Output: python
#         php
#         perl
fuzzy_filter() {
    local pattern="$1"
    shift
    local -a items=("$@")

    local item
    for item in "${items[@]}"; do
        if fuzzy_match "$pattern" "$item"; then
            printf '%s\n' "$item"
        fi
    done
}

# @pre: pattern is valid, remaining args are array elements
# @post: prints items sorted by match score (descending)
# @idempotent: yes
# @returns: Lines of sorted items
#
# Sort array elements by how well they match the pattern.
#
# Usage: fuzzy_sort "py" "python" "ruby" "php" "pypy"
fuzzy_sort() {
    local pattern="$1"
    shift
    local -a items=("$@")

    # Build score-item pairs
    local -a scored
    local item score

    for item in "${items[@]}"; do
        score=$(fuzzy_score "$pattern" "$item")
        # Pad score for proper sorting
        scored+=("$(printf '%010d\t%s' "$score" "$item")")
    done

    # Sort descending by score and extract items
    printf '%s\n' "${scored[@]}" | sort -t$'\t' -k1 -rn | cut -f2
}

# @pre: pattern is valid, remaining args are array elements
# @post: prints the best matching item
# @idempotent: yes
# @returns: Single best match (empty if none)
#
# Find the single best matching item in the array.
#
# Usage: fuzzy_best_match "python" "python3" "python2" "pypy" "jython"
fuzzy_best_match() {
    local pattern="$1"
    shift
    local -a items=("$@")

    local best_item=""
    local best_score=0
    local item score

    for item in "${items[@]}"; do
        if fuzzy_match "$pattern" "$item"; then
            score=$(fuzzy_score "$pattern" "$item")
            if (( score > best_score )); then
                best_score=$score
                best_item="$item"
            fi
        fi
    done

    [[ -n "$best_item" ]] && printf '%s\n' "$best_item"
}

# @pre: pattern valid, n is positive integer
# @post: prints top n matches as JSON array
# @idempotent: yes
# @returns: JSON array of {item, score} objects
#
# Find top N matches with their scores.
#
# Usage: fuzzy_top_n "py" 3 "python" "ruby" "php" "pypy"
# Output: [{"item":"python","score":150},{"item":"pypy","score":140}...]
fuzzy_top_n() {
    local pattern="$1"
    local n="$2"
    shift 2
    local -a items=("$@")

    # Build scored array
    local -a scored
    local item score

    for item in "${items[@]}"; do
        if fuzzy_match "$pattern" "$item"; then
            score=$(fuzzy_score "$pattern" "$item")
            scored+=("$(printf '%010d\t%s' "$score" "$item")")
        fi
    done

    # Sort and take top n
    printf '['
    local first=true
    local count=0

    while IFS=$'\t' read -r score item; do
        (( count >= n )) && break

        $first || printf ','
        first=false

        # Remove leading zeros from score
        score=$((10#$score))

        local escaped_item
        escaped_item=$(_fuzzy_escape_json "$item")
        printf '{"item":"%s","score":%d}' "$escaped_item" "$score"

        ((count++))
    done < <(printf '%s\n' "${scored[@]}" | sort -t$'\t' -k1 -rn)

    printf ']'
}

# @pre: pattern valid, threshold in [0,1]
# @post: prints matches above threshold
# @idempotent: yes
# @returns: Lines of matching items
#
# Find all matches above a similarity threshold.
#
# Usage: fuzzy_find_all "hello" 0.8 "hello" "hallo" "world"
fuzzy_find_all() {
    local pattern="$1"
    local threshold="${2:-$FUZZY_THRESHOLD}"
    shift 2
    local -a items=("$@")

    local item sim
    local threshold_int
    threshold_int=$(printf '%.0f' "$(echo "$threshold * 1000" | bc 2>/dev/null || echo "$((${threshold%.*}000))")")

    for item in "${items[@]}"; do
        sim=$(levenshtein_similarity "$pattern" "$item")
        local sim_int
        sim_int=$(printf '%s' "$sim" | tr -d '.')

        # Pad to same length
        while (( ${#sim_int} < 4 )); do
            sim_int+="0"
        done

        if (( sim_int >= threshold_int )); then
            printf '%s\n' "$item"
        fi
    done
}

# @pre: pattern valid, items provided
# @post: prints JSON array with rankings
# @idempotent: yes
# @returns: JSON array of {item, rank, score, similarity}
#
# Rank all items by match quality.
#
# Usage: fuzzy_rank "py" "python" "ruby" "php"
fuzzy_rank() {
    local pattern="$1"
    shift
    local -a items=("$@")

    # Build scored array
    local -a scored
    local item score sim

    for item in "${items[@]}"; do
        score=$(fuzzy_score "$pattern" "$item")
        sim=$(levenshtein_similarity "$pattern" "$item")
        scored+=("$(printf '%010d\t%s\t%s' "$score" "$sim" "$item")")
    done

    # Sort and output as JSON
    printf '['
    local first=true
    local rank=1

    while IFS=$'\t' read -r score sim item; do
        $first || printf ','
        first=false

        score=$((10#$score))

        local escaped_item
        escaped_item=$(_fuzzy_escape_json "$item")
        printf '{"item":"%s","rank":%d,"score":%d,"similarity":%s}' \
            "$escaped_item" "$rank" "$score" "$sim"

        ((rank++))
    done < <(printf '%s\n' "${scored[@]}" | sort -t$'\t' -k1 -rn)

    printf ']'
}

# =============================================================================
# APPROXIMATE SEARCH
# =============================================================================

# @pre: pattern and text are valid
# @post: returns JSON array of approximate matches
# @idempotent: yes
# @returns: JSON array of {match, position, distance}
#
# Search for approximate matches in text.
#
# Usage: fuzzy_search "helo" "hello world, hello again"
fuzzy_search() {
    local pattern="$1"
    local text="$2"
    local max_distance="${3:-2}"

    [[ -z "$pattern" || -z "$text" ]] && { printf '[]'; return 0; }

    local plen="${#pattern}"
    local tlen="${#text}"
    local -a results

    # Sliding window search
    local i window dist
    for ((i = 0; i <= tlen - plen; i++)); do
        window="${text:i:plen}"
        dist=$(levenshtein_distance "$pattern" "$window")

        if (( dist <= max_distance )); then
            local escaped_match
            escaped_match=$(_fuzzy_escape_json "$window")
            results+=("{\"match\":\"$escaped_match\",\"position\":$i,\"distance\":$dist}")
        fi
    done

    # Also check slightly longer windows for insertions
    for ((i = 0; i <= tlen - plen - 1; i++)); do
        window="${text:i:plen+1}"
        dist=$(levenshtein_distance "$pattern" "$window")

        if (( dist <= max_distance )); then
            local escaped_match
            escaped_match=$(_fuzzy_escape_json "$window")
            # Check if we already have this position
            local exists=false
            for r in "${results[@]}"; do
                [[ "$r" == *"\"position\":$i"* ]] && { exists=true; break; }
            done
            $exists || results+=("{\"match\":\"$escaped_match\",\"position\":$i,\"distance\":$dist}")
        fi
    done

    printf '['
    local first=true
    for r in "${results[@]}"; do
        $first || printf ','
        first=false
        printf '%s' "$r"
    done
    printf ']'
}

# @pre: pattern and lines are valid
# @post: prints matching lines
# @idempotent: yes
# @returns: Lines that fuzzy-match pattern
#
# Fuzzy grep through lines (from stdin or arguments).
#
# Usage: echo -e "foo\nbar\nbaz" | fuzzy_grep "ba"
fuzzy_grep() {
    local pattern="$1"
    shift

    if [[ $# -gt 0 ]]; then
        # Arguments provided
        local line
        for line in "$@"; do
            if fuzzy_match "$pattern" "$line"; then
                printf '%s\n' "$line"
            fi
        done
    else
        # Read from stdin
        local line
        while IFS= read -r line; do
            if fuzzy_match "$pattern" "$line"; then
                printf '%s\n' "$line"
            fi
        done
    fi
}

# @pre: pattern and string are valid
# @post: returns position or -1 if not found
# @idempotent: yes
# @returns: Index of best fuzzy match position
#
# Find approximate position of pattern in string.
#
# Usage: fuzzy_index_of "helo" "say hello"
# Output: 4
fuzzy_index_of() {
    local pattern="$1"
    local string="$2"
    local max_distance="${3:-2}"

    [[ -z "$pattern" || -z "$string" ]] && { printf '%d' -1; return 0; }

    local plen="${#pattern}"
    local slen="${#string}"
    local best_pos=-1
    local best_dist=$((max_distance + 1))

    local i window dist
    for ((i = 0; i <= slen - plen; i++)); do
        window="${string:i:plen}"
        dist=$(levenshtein_distance "$pattern" "$window")

        if (( dist < best_dist )); then
            best_dist=$dist
            best_pos=$i
        fi
    done

    if (( best_dist <= max_distance )); then
        printf '%d' "$best_pos"
    else
        printf '%d' -1
    fi
}

# =============================================================================
# PHONETIC MATCHING
# =============================================================================

# @pre: word is a non-empty string
# @post: returns 4-character Soundex code
# @idempotent: yes
# @returns: Soundex phonetic code (letter + 3 digits)
#
# Generate Soundex code for a word. Words that sound similar
# produce the same code.
#
# Usage: soundex "Robert"
# Output: R163
soundex() {
    local word="$1"

    [[ -z "$word" ]] && { printf ''; return 0; }

    # Convert to uppercase and remove non-alpha
    word="${word^^}"
    word="${word//[^A-Z]/}"

    [[ -z "$word" ]] && { printf ''; return 0; }

    # Keep first letter
    local result="${word:0:1}"
    local prev_code=""

    # Soundex encoding map
    local i char code
    for ((i = 0; i < ${#word}; i++)); do
        char="${word:i:1}"

        case "$char" in
            B|F|P|V) code="1" ;;
            C|G|J|K|Q|S|X|Z) code="2" ;;
            D|T) code="3" ;;
            L) code="4" ;;
            M|N) code="5" ;;
            R) code="6" ;;
            *) code="" ;;
        esac

        # Skip first letter (already in result) and duplicate codes
        if (( i > 0 )) && [[ -n "$code" && "$code" != "$prev_code" ]]; then
            result+="$code"
            [[ "${#result}" -ge 4 ]] && break
        fi

        prev_code="$code"
    done

    # Pad with zeros to length 4
    while [[ "${#result}" -lt 4 ]]; do
        result+="0"
    done

    printf '%s' "${result:0:4}"
}

# @pre: word is a non-empty string
# @post: returns Metaphone code
# @idempotent: yes
# @returns: Metaphone phonetic code
#
# Generate Metaphone code for a word. More accurate than Soundex
# for English pronunciation.
#
# Usage: metaphone "knight"
# Output: NT
metaphone() {
    local word="$1"

    [[ -z "$word" ]] && { printf ''; return 0; }

    # Convert to uppercase
    word="${word^^}"
    word="${word//[^A-Z]/}"

    [[ -z "$word" ]] && { printf ''; return 0; }

    local result=""
    local len="${#word}"
    local i=0

    # Handle initial letter combinations
    case "${word:0:2}" in
        KN|GN|PN|AE|WR) i=1 ;;
        WH) word="W${word:2}"; ;;
    esac

    if [[ "${word:0:1}" == "X" ]]; then
        word="S${word:1}"
    fi

    while (( i < len )); do
        local char="${word:i:1}"
        local next="${word:i+1:1}"
        local prev=""
        (( i > 0 )) && prev="${word:i-1:1}"

        case "$char" in
            A|E|I|O|U)
                # Vowels only at start
                (( i == 0 )) && result+="$char"
                ;;
            B)
                # B unless after M at end
                if [[ "$prev" != "M" || "$next" != "" ]]; then
                    result+="B"
                fi
                ;;
            C)
                # C -> S before E,I,Y; else K
                # CH -> X if not SCH
                if [[ "${word:i:2}" == "CH" ]]; then
                    result+="X"
                    ((i++))
                elif [[ "$next" =~ [EIY] ]]; then
                    result+="S"
                else
                    result+="K"
                fi
                ;;
            D)
                # DG -> J; else T
                if [[ "${word:i:2}" == "DG" && "${word:i+2:1}" =~ [EIY] ]]; then
                    result+="J"
                    ((i++))
                else
                    result+="T"
                fi
                ;;
            F) result+="F" ;;
            G)
                # Silent if before N,NED at end
                # GH -> F
                # G -> J before E,I,Y (unless GG)
                if [[ "$next" == "H" ]]; then
                    if [[ ! "${word:i+2:1}" =~ [AEIOU] ]]; then
                        ((i++))
                    else
                        result+="K"
                        ((i++))
                    fi
                elif [[ "$next" == "N" && "${word:i+2}" == "" ]]; then
                    : # Silent
                elif [[ "$next" =~ [EIY] && "$prev" != "G" ]]; then
                    result+="J"
                else
                    result+="K"
                fi
                ;;
            H)
                # H if before vowel and not after CGPST
                if [[ "$next" =~ [AEIOU] && ! "$prev" =~ [CGPST] ]]; then
                    result+="H"
                fi
                ;;
            J) result+="J" ;;
            K)
                # K unless after C
                [[ "$prev" != "C" ]] && result+="K"
                ;;
            L) result+="L" ;;
            M) result+="M" ;;
            N) result+="N" ;;
            P)
                # PH -> F; else P
                if [[ "$next" == "H" ]]; then
                    result+="F"
                    ((i++))
                else
                    result+="P"
                fi
                ;;
            Q) result+="K" ;;
            R) result+="R" ;;
            S)
                # SH -> X; else S
                if [[ "$next" == "H" ]]; then
                    result+="X"
                    ((i++))
                elif [[ "${word:i:3}" == "SIO" || "${word:i:3}" == "SIA" ]]; then
                    result+="X"
                else
                    result+="S"
                fi
                ;;
            T)
                # TH -> 0; TIO/TIA -> X; else T
                if [[ "$next" == "H" ]]; then
                    result+="0"
                    ((i++))
                elif [[ "${word:i:3}" == "TIO" || "${word:i:3}" == "TIA" ]]; then
                    result+="X"
                else
                    result+="T"
                fi
                ;;
            V) result+="F" ;;
            W)
                # W before vowel
                [[ "$next" =~ [AEIOU] ]] && result+="W"
                ;;
            X) result+="KS" ;;
            Y)
                # Y before vowel
                [[ "$next" =~ [AEIOU] ]] && result+="Y"
                ;;
            Z) result+="S" ;;
        esac

        ((i++))
    done

    printf '%s' "$result"
}

# @pre: word is a non-empty string
# @post: returns JSON with primary and alternate codes
# @idempotent: yes
# @returns: JSON object with primary and alternate Metaphone codes
#
# Generate Double Metaphone codes. Provides both primary and alternate
# encodings for words with multiple pronunciations.
#
# Usage: double_metaphone "smith"
# Output: {"primary":"SM0","alternate":"XMT"}
double_metaphone() {
    local word="$1"

    [[ -z "$word" ]] && { printf '{"primary":"","alternate":""}'; return 0; }

    # For simplicity, use Metaphone for primary and a variant for alternate
    local primary
    primary=$(metaphone "$word")

    # Generate alternate by applying different rules
    local alternate=""
    word="${word^^}"

    # Some common alternate encodings
    case "${word:0:2}" in
        PH) alternate="F${word:2}" ;;
        GH) alternate="${word:2}" ;;
        KN) alternate="N${word:2}" ;;
        WR) alternate="R${word:2}" ;;
        *) alternate="$word" ;;
    esac

    alternate=$(metaphone "$alternate")

    # If same, clear alternate
    [[ "$primary" == "$alternate" ]] && alternate=""

    printf '{"primary":"%s","alternate":"%s"}' "$primary" "$alternate"
}

# @pre: word1 and word2 are valid strings
# @post: returns 0 if phonetically similar, 1 otherwise
# @idempotent: yes
# @returns: 0 if sounds similar, 1 if not
#
# Check if two words sound similar using phonetic encoding.
#
# Usage: phonetic_match "Smith" "Smyth" && echo "similar"
phonetic_match() {
    local word1="$1"
    local word2="$2"
    local method="${3:-soundex}"

    local code1 code2

    case "$method" in
        soundex)
            code1=$(soundex "$word1")
            code2=$(soundex "$word2")
            ;;
        metaphone)
            code1=$(metaphone "$word1")
            code2=$(metaphone "$word2")
            ;;
        *)
            code1=$(soundex "$word1")
            code2=$(soundex "$word2")
            ;;
    esac

    [[ "$code1" == "$code2" ]]
}

# @pre: word1 and word2 are valid strings
# @post: returns float in range [0.0, 1.0]
# @idempotent: yes
# @returns: Phonetic similarity score
#
# Calculate phonetic similarity between two words.
#
# Usage: phonetic_distance "Smith" "Schmidt"
phonetic_distance() {
    local word1="$1"
    local word2="$2"

    local code1 code2
    code1=$(metaphone "$word1")
    code2=$(metaphone "$word2")

    levenshtein_similarity "$code1" "$code2"
}

# =============================================================================
# TYPO CORRECTION
# =============================================================================

# QWERTY keyboard layout for distance calculations
declare -gA _QWERTY_POS
_QWERTY_POS=(
    [q]="0,0" [w]="1,0" [e]="2,0" [r]="3,0" [t]="4,0" [y]="5,0" [u]="6,0" [i]="7,0" [o]="8,0" [p]="9,0"
    [a]="0,1" [s]="1,1" [d]="2,1" [f]="3,1" [g]="4,1" [h]="5,1" [j]="6,1" [k]="7,1" [l]="8,1"
    [z]="0,2" [x]="1,2" [c]="2,2" [v]="3,2" [b]="4,2" [n]="5,2" [m]="6,2"
)

# @pre: char1 and char2 are single characters
# @post: returns non-negative float distance
# @idempotent: yes
# @returns: Euclidean distance on QWERTY keyboard
#
# Calculate the physical distance between two keys on a QWERTY keyboard.
#
# Usage: keyboard_distance "q" "w"
# Output: 1.0
keyboard_distance() {
    local char1="${1,,}"
    local char2="${2,,}"

    # Same character
    [[ "$char1" == "$char2" ]] && { printf '0.0'; return 0; }

    # Get positions
    local pos1="${_QWERTY_POS[$char1]:-}"
    local pos2="${_QWERTY_POS[$char2]:-}"

    # Not on keyboard
    [[ -z "$pos1" || -z "$pos2" ]] && { printf '9.9'; return 0; }

    local x1="${pos1%,*}"
    local y1="${pos1#*,}"
    local x2="${pos2%,*}"
    local y2="${pos2#*,}"

    # Euclidean distance (integer math approximation)
    local dx=$((x1 - x2))
    local dy=$((y1 - y2))
    (( dx < 0 )) && dx=$((-dx))
    (( dy < 0 )) && dy=$((-dy))

    # Simple approximation: sqrt(dx^2 + dy^2) ~ max(dx,dy) + 0.4*min(dx,dy)
    local dist
    if (( dx > dy )); then
        dist=$((dx * 1000 + dy * 400))
    else
        dist=$((dy * 1000 + dx * 400))
    fi

    local int_part=$((dist / 1000))
    local dec_part=$((dist % 1000))

    printf '%d.%01d' "$int_part" "$((dec_part / 100))"
}

# @pre: word is a non-empty string
# @post: returns JSON array of candidate typos
# @idempotent: yes
# @returns: Array of likely typo variants
#
# Generate likely typo variants for a word (adjacent key errors,
# missing letters, swapped letters).
#
# Usage: typo_candidates "hello"
typo_candidates() {
    local word="$1"

    [[ -z "$word" ]] && { printf '[]'; return 0; }

    local -a candidates
    local len="${#word}"
    local i j

    word="${word,,}"

    # Deletion (missing a letter)
    for ((i = 0; i < len; i++)); do
        candidates+=("${word:0:i}${word:i+1}")
    done

    # Transposition (swapped adjacent letters)
    for ((i = 0; i < len - 1; i++)); do
        candidates+=("${word:0:i}${word:i+1:1}${word:i:1}${word:i+2}")
    done

    # Substitution (wrong key - adjacent on keyboard)
    local adjacent_keys
    declare -A adjacent_keys=(
        [q]="was" [w]="qase" [e]="wrd" [r]="etf" [t]="ryg" [y]="tuh" [u]="yij" [i]="uok" [o]="ipl" [p]="ol"
        [a]="qwsz" [s]="awedfxz" [d]="serfc" [f]="drtgv" [g]="ftyh" [h]="gyjn" [j]="hukm" [k]="jiol" [l]="kop"
        [z]="asx" [x]="zsd" [c]="xdf" [v]="cfg" [b]="vghn" [n]="bhjm" [m]="njk"
    )

    for ((i = 0; i < len; i++)); do
        local char="${word:i:1}"
        local adj="${adjacent_keys[$char]:-}"
        local a
        for ((j = 0; j < ${#adj}; j++)); do
            a="${adj:j:1}"
            candidates+=("${word:0:i}${a}${word:i+1}")
        done
    done

    # Insertion (extra letter)
    for ((i = 0; i <= len; i++)); do
        local prev_char="${word:i-1:1}"
        local next_char="${word:i:1}"
        local chars=""
        [[ -n "${adjacent_keys[$prev_char]:-}" ]] && chars+="${adjacent_keys[$prev_char]}"
        [[ -n "${adjacent_keys[$next_char]:-}" ]] && chars+="${adjacent_keys[$next_char]}"

        for ((j = 0; j < ${#chars}; j++)); do
            candidates+=("${word:0:i}${chars:j:1}${word:i}")
        done
    done

    # Deduplicate and output JSON
    printf '['
    local first=true
    local seen=""
    local c
    for c in "${candidates[@]}"; do
        [[ "$c" == "$word" ]] && continue
        [[ "$seen" == *"|$c|"* ]] && continue
        seen+="|$c|"

        $first || printf ','
        first=false
        printf '"%s"' "$c"
    done
    printf ']'
}

# @pre: typo is a non-empty string, dictionary is array
# @post: returns best suggestions
# @idempotent: yes
# @returns: JSON array of suggested corrections with scores
#
# Suggest corrections for a typo from a dictionary.
#
# Usage: typo_suggest "helo" "hello" "help" "hero" "world"
typo_suggest() {
    local typo="$1"
    shift
    local -a dictionary=("$@")

    [[ -z "$typo" ]] && { printf '[]'; return 0; }

    local -a suggestions
    local word dist

    for word in "${dictionary[@]}"; do
        dist=$(levenshtein_distance "$typo" "$word")

        # Only consider words within edit distance 2
        if (( dist <= 2 )); then
            suggestions+=("$(printf '%02d\t%s' "$dist" "$word")")
        fi
    done

    # Sort by distance and output JSON
    printf '['
    local first=true

    while IFS=$'\t' read -r dist word; do
        $first || printf ','
        first=false

        dist=$((10#$dist))
        local escaped_word
        escaped_word=$(_fuzzy_escape_json "$word")
        printf '{"word":"%s","distance":%d}' "$escaped_word" "$dist"
    done < <(printf '%s\n' "${suggestions[@]}" | sort -t$'\t' -k1 -n | head -5)

    printf ']'
}

# =============================================================================
# N-GRAM FUNCTIONS
# =============================================================================

# @pre: string is valid, n is positive integer
# @post: returns JSON array of n-grams
# @idempotent: yes
# @returns: Array of n-grams
#
# Generate n-grams (substrings of length n) from a string.
#
# Usage: ngrams "hello" 2
# Output: ["he","el","ll","lo"]
ngrams() {
    local string="$1"
    local n="${2:-3}"

    [[ -z "$string" ]] && { printf '[]'; return 0; }

    local len="${#string}"

    if (( len < n )); then
        printf '["%s"]' "$string"
        return 0
    fi

    printf '['
    local first=true
    local i

    for ((i = 0; i <= len - n; i++)); do
        $first || printf ','
        first=false

        local gram="${string:i:n}"
        local escaped_gram
        escaped_gram=$(_fuzzy_escape_json "$gram")
        printf '"%s"' "$escaped_gram"
    done

    printf ']'
}

# @pre: string is valid
# @post: returns JSON array of bigrams
# @idempotent: yes
# @returns: Array of 2-grams
#
# Generate bigrams (2-grams) from a string.
#
# Usage: bigrams "hello"
# Output: ["he","el","ll","lo"]
bigrams() {
    ngrams "$1" 2
}

# @pre: string is valid
# @post: returns JSON array of trigrams
# @idempotent: yes
# @returns: Array of 3-grams
#
# Generate trigrams (3-grams) from a string.
#
# Usage: trigrams "hello"
# Output: ["hel","ell","llo"]
trigrams() {
    ngrams "$1" 3
}

# @pre: s1 and s2 are valid strings
# @post: returns float in range [0.0, 1.0]
# @idempotent: yes
# @returns: N-gram based similarity (Jaccard coefficient)
#
# Calculate similarity based on shared n-grams using Jaccard coefficient.
# similarity = |intersection| / |union|
#
# Usage: ngram_similarity "hello" "hallo" 2
# Output: 0.400
ngram_similarity() {
    local s1="$1"
    local s2="$2"
    local n="${3:-2}"

    [[ "$s1" == "$s2" ]] && { printf '1.000'; return 0; }
    [[ -z "$s1" && -z "$s2" ]] && { printf '1.000'; return 0; }
    [[ -z "$s1" || -z "$s2" ]] && { printf '0.000'; return 0; }

    # Generate n-grams for both strings
    declare -A ngrams1 ngrams2
    local len1="${#s1}"
    local len2="${#s2}"
    local i gram

    # Extract n-grams from s1
    for ((i = 0; i <= len1 - n; i++)); do
        gram="${s1:i:n}"
        ngrams1["$gram"]=1
    done

    # Extract n-grams from s2
    for ((i = 0; i <= len2 - n; i++)); do
        gram="${s2:i:n}"
        ngrams2["$gram"]=1
    done

    # Calculate intersection and union
    local intersection=0
    local union=0

    # Count union from ngrams1
    for gram in "${!ngrams1[@]}"; do
        ((union++))
        if [[ -n "${ngrams2[$gram]:-}" ]]; then
            ((intersection++))
        fi
    done

    # Add ngrams2 unique items to union
    for gram in "${!ngrams2[@]}"; do
        if [[ -z "${ngrams1[$gram]:-}" ]]; then
            ((union++))
        fi
    done

    # Avoid division by zero
    (( union == 0 )) && { printf '0.000'; return 0; }

    # Calculate Jaccard coefficient
    local similarity=$((intersection * 1000 / union))

    local int_part=$((similarity / 1000))
    local dec_part=$((similarity % 1000))

    printf '%d.%03d' "$int_part" "$dec_part"
}

# =============================================================================
# UTILITIES
# =============================================================================

# @pre: string is valid
# @post: returns normalized string
# @idempotent: yes
# @returns: Lowercase, accent-removed, whitespace-normalized string
#
# Normalize a string for fuzzy matching.
#
# Usage: normalize_for_fuzzy "  Hello  World  "
# Output: hello world
normalize_for_fuzzy() {
    local str="$1"

    # Lowercase
    str="${str,,}"

    # Remove common accents (basic ASCII normalization)
    str="${str//[aaaaaa]/a}"
    str="${str//[eeee]/e}"
    str="${str//[iiii]/i}"
    str="${str//[ooooo]/o}"
    str="${str//[uuuu]/u}"
    str="${str//[nn]/n}"
    str="${str//[cc]/c}"

    # Collapse whitespace
    str="${str//[$'\t\n\r']/ }"
    str="$(printf '%s' "$str" | tr -s ' ')"
    str="${str# }"
    str="${str% }"

    printf '%s' "$str"
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# @pre: threshold is float in [0.0, 1.0]
# @post: global threshold updated
# @idempotent: yes
# @returns: 0 on success
#
# Set the global fuzzy match threshold.
#
# Usage: fuzzy_set_threshold 0.8
fuzzy_set_threshold() {
    local threshold="$1"

    # Validate range (using integer comparison)
    local t_int
    t_int=$(printf '%.0f' "$(echo "$threshold * 100" | bc 2>/dev/null || echo "${threshold%.*}00")")

    if (( t_int < 0 || t_int > 100 )); then
        printf '{"error":true,"msg":"threshold must be between 0.0 and 1.0"}\n' >&2
        return 1
    fi

    FUZZY_THRESHOLD="$threshold"
    return 0
}

# @pre: algorithm is valid algorithm name
# @post: global algorithm updated
# @idempotent: yes
# @returns: 0 on success, 1 on invalid algorithm
#
# Set the default fuzzy matching algorithm.
#
# Usage: fuzzy_set_algorithm "jaro_winkler"
fuzzy_set_algorithm() {
    local algorithm="$1"

    case "$algorithm" in
        levenshtein|damerau|hamming|jaro|jaro_winkler|ngram)
            FUZZY_ALGORITHM="$algorithm"
            return 0
            ;;
        *)
            printf '{"error":true,"msg":"unknown algorithm","valid":["levenshtein","damerau","hamming","jaro","jaro_winkler","ngram"]}\n' >&2
            return 1
            ;;
    esac
}

# @pre: none
# @post: prints library info as JSON
# @idempotent: yes
# @returns: JSON object with library metadata
#
# Get fuzzy library version and configuration.
#
# Usage: fuzzy_info
fuzzy_info() {
    printf '{"library":"fuzzy","version":"1.0.0","threshold":%s,"algorithm":"%s","case_insensitive":%s}' \
        "$FUZZY_THRESHOLD" \
        "$FUZZY_ALGORITHM" \
        "$( [[ "$FUZZY_CASE_INSENSITIVE" == "1" ]] && echo "true" || echo "false" )"
}

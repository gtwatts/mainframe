#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Fuzzy String Matching Library Tests
# =============================================================================
# Comprehensive test suite for lib/fuzzy.sh
# 80+ test cases covering all algorithms and edge cases
# =============================================================================

load 'test_helper'

setup() {
    source_lib "fuzzy"
    export FUZZY_CASE_INSENSITIVE=1
    export FUZZY_THRESHOLD=0.6
    TEST_DIR=$(create_test_dir "fuzzy")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# LEVENSHTEIN DISTANCE TESTS
# =============================================================================

@test "levenshtein_distance: identical strings have distance 0" {
    local result
    result=$(levenshtein_distance "hello" "hello")
    [ "$result" = "0" ]
}

@test "levenshtein_distance: empty string to non-empty" {
    local result
    result=$(levenshtein_distance "" "hello")
    [ "$result" = "5" ]
}

@test "levenshtein_distance: non-empty to empty" {
    local result
    result=$(levenshtein_distance "hello" "")
    [ "$result" = "5" ]
}

@test "levenshtein_distance: single insertion" {
    local result
    result=$(levenshtein_distance "hello" "helllo")
    [ "$result" = "1" ]
}

@test "levenshtein_distance: single deletion" {
    local result
    result=$(levenshtein_distance "hello" "helo")
    [ "$result" = "1" ]
}

@test "levenshtein_distance: single substitution" {
    local result
    result=$(levenshtein_distance "hello" "hallo")
    [ "$result" = "1" ]
}

@test "levenshtein_distance: classic kitten-sitting example" {
    local result
    result=$(levenshtein_distance "kitten" "sitting")
    [ "$result" = "3" ]
}

@test "levenshtein_distance: completely different strings" {
    local result
    result=$(levenshtein_distance "abc" "xyz")
    [ "$result" = "3" ]
}

@test "levenshtein_distance: case sensitivity" {
    local result
    result=$(levenshtein_distance "Hello" "hello")
    [ "$result" = "1" ]
}

@test "levenshtein_distance: handles special characters" {
    local result
    result=$(levenshtein_distance "hello-world" "hello_world")
    [ "$result" = "1" ]
}

# =============================================================================
# LEVENSHTEIN SIMILARITY TESTS
# =============================================================================

@test "levenshtein_similarity: identical strings return 1.0" {
    local result
    result=$(levenshtein_similarity "hello" "hello")
    [ "$result" = "1.0" ] || [ "$result" = "1.000" ]
}

@test "levenshtein_similarity: both empty returns 1.0" {
    local result
    result=$(levenshtein_similarity "" "")
    [ "$result" = "1.0" ] || [ "$result" = "1.000" ]
}

@test "levenshtein_similarity: completely different returns low score" {
    local result
    result=$(levenshtein_similarity "abc" "xyz")
    # 1 - 3/3 = 0.0
    [ "$result" = "0.000" ]
}

@test "levenshtein_similarity: one edit in 5 chars returns 0.8" {
    local result
    result=$(levenshtein_similarity "hello" "hallo")
    [ "$result" = "0.800" ]
}

@test "levenshtein_similarity: returns value between 0 and 1" {
    local result
    result=$(levenshtein_similarity "algorithm" "altruistic")
    # Result should be a decimal between 0 and 1
    [[ "$result" =~ ^0\.[0-9]+$ ]]
}

# =============================================================================
# DAMERAU-LEVENSHTEIN TESTS
# =============================================================================

@test "damerau_levenshtein: identical strings have distance 0" {
    local result
    result=$(damerau_levenshtein "hello" "hello")
    [ "$result" = "0" ]
}

@test "damerau_levenshtein: transposition counts as 1 edit" {
    local result
    result=$(damerau_levenshtein "ab" "ba")
    [ "$result" = "1" ]
}

@test "damerau_levenshtein: multiple transpositions" {
    local result
    result=$(damerau_levenshtein "abcd" "badc")
    [ "$result" = "2" ]
}

@test "damerau_levenshtein: transposition in longer string" {
    local result
    result=$(damerau_levenshtein "hello" "ehllo")
    [ "$result" = "1" ]
}

@test "damerau_levenshtein: regular levenshtein would give 2 for transposition" {
    local lev_result dam_result
    lev_result=$(levenshtein_distance "ab" "ba")
    dam_result=$(damerau_levenshtein "ab" "ba")
    # Levenshtein: 2 (delete a, insert a) or (sub a->b, sub b->a)
    # Damerau: 1 (transpose)
    [ "$lev_result" = "2" ]
    [ "$dam_result" = "1" ]
}

# =============================================================================
# HAMMING DISTANCE TESTS
# =============================================================================

@test "hamming_distance: identical strings have distance 0" {
    local result
    result=$(hamming_distance "hello" "hello")
    [ "$result" = "0" ]
}

@test "hamming_distance: one character different" {
    local result
    result=$(hamming_distance "hello" "hallo")
    [ "$result" = "1" ]
}

@test "hamming_distance: all characters different" {
    local result
    result=$(hamming_distance "abc" "xyz")
    [ "$result" = "3" ]
}

@test "hamming_distance: fails on different length strings" {
    run hamming_distance "hello" "hi"
    [ "$status" = "1" ]
    [[ "$output" == *"error"* ]]
}

@test "hamming_distance: classic karolin-kathrin example" {
    local result
    result=$(hamming_distance "karolin" "kathrin")
    [ "$result" = "3" ]
}

# =============================================================================
# JARO DISTANCE TESTS
# =============================================================================

@test "jaro_distance: identical strings return 1.0" {
    local result
    result=$(jaro_distance "hello" "hello")
    [[ "$result" =~ ^1\.0 ]]
}

@test "jaro_distance: completely different strings return 0" {
    local result
    result=$(jaro_distance "abc" "xyz")
    [ "$result" = "0.000" ]
}

@test "jaro_distance: classic MARTHA-MARHTA example" {
    local result
    result=$(jaro_distance "MARTHA" "MARHTA")
    # Expected: 0.944
    [[ "$result" =~ ^0\.9[0-9]+ ]]
}

@test "jaro_distance: empty strings" {
    local result
    result=$(jaro_distance "" "hello")
    [ "$result" = "0.000" ]
}

@test "jaro_distance: symmetric" {
    local result1 result2
    result1=$(jaro_distance "hello" "hallo")
    result2=$(jaro_distance "hallo" "hello")
    [ "$result1" = "$result2" ]
}

# =============================================================================
# JARO-WINKLER TESTS
# =============================================================================

@test "jaro_winkler_distance: identical strings return 1.0" {
    local result
    result=$(jaro_winkler_distance "hello" "hello")
    [[ "$result" =~ ^1\.0 ]]
}

@test "jaro_winkler_distance: prefix bonus increases score" {
    local jaro_result jw_result
    jaro_result=$(jaro_distance "hello" "hella")
    jw_result=$(jaro_winkler_distance "hello" "hella")
    # JW should be >= Jaro due to prefix bonus
    # Compare integer parts
    [[ "${jw_result%.*}" -ge "${jaro_result%.*}" ]]
}

@test "jaro_winkler_distance: MARTHA-MARHTA example" {
    local result
    result=$(jaro_winkler_distance "MARTHA" "MARHTA")
    # Expected: ~0.961
    [[ "$result" =~ ^0\.9[0-9]+ ]]
}

@test "jaro_winkler_distance: no common prefix gives same as jaro" {
    local jaro_result jw_result
    jaro_result=$(jaro_distance "abc" "xyz")
    jw_result=$(jaro_winkler_distance "abc" "xyz")
    [ "$jaro_result" = "$jw_result" ]
}

# =============================================================================
# LONGEST COMMON SUBSTRING TESTS
# =============================================================================

@test "longest_common_substring: finds exact match" {
    local result
    result=$(longest_common_substring "hello" "hello")
    [ "$result" = "hello" ]
}

@test "longest_common_substring: empty input returns empty" {
    local result
    result=$(longest_common_substring "" "hello")
    [ "$result" = "" ]
}

@test "longest_common_substring: classic ABABC-BABCA example" {
    local result
    result=$(longest_common_substring "ABABC" "BABCA")
    # Should find "BABC" or "ABC" (length 3 or 4)
    [[ "${#result}" -ge 3 ]]
}

@test "longest_common_substring: no common substring" {
    local result
    result=$(longest_common_substring "abc" "xyz")
    [ "$result" = "" ]
}

@test "longest_common_substring: partial match" {
    local result
    result=$(longest_common_substring "photograph" "geography")
    [ "$result" = "ograph" ]
}

# =============================================================================
# LONGEST COMMON SUBSEQUENCE TESTS
# =============================================================================

@test "longest_common_subsequence: identical strings" {
    local result
    result=$(longest_common_subsequence "hello" "hello")
    [ "$result" = "hello" ]
}

@test "longest_common_subsequence: empty input" {
    local result
    result=$(longest_common_subsequence "" "hello")
    [ "$result" = "" ]
}

@test "longest_common_subsequence: classic AGGTAB-GXTXAYB example" {
    local result
    result=$(longest_common_subsequence "AGGTAB" "GXTXAYB")
    [ "$result" = "GTAB" ]
}

@test "lcs_length: returns correct length" {
    local result
    result=$(lcs_length "AGGTAB" "GXTXAYB")
    [ "$result" = "4" ]
}

@test "lcs_length: empty strings return 0" {
    local result
    result=$(lcs_length "" "hello")
    [ "$result" = "0" ]
}

# =============================================================================
# FUZZY MATCH TESTS
# =============================================================================

@test "fuzzy_match: exact match succeeds" {
    fuzzy_match "hello" "hello"
}

@test "fuzzy_match: pattern in order matches" {
    fuzzy_match "abc" "a1b2c3"
}

@test "fuzzy_match: fzf-style matching" {
    fuzzy_match "hlo" "hello"
}

@test "fuzzy_match: empty pattern always matches" {
    fuzzy_match "" "anything"
}

@test "fuzzy_match: pattern not in order fails" {
    ! fuzzy_match "cba" "abc"
}

@test "fuzzy_match: pattern longer than string fails" {
    ! fuzzy_match "hello world" "hi"
}

@test "fuzzy_match: case insensitive by default" {
    fuzzy_match "ABC" "abcdef"
}

@test "fuzzy_match: case sensitive when disabled" {
    export FUZZY_CASE_INSENSITIVE=0
    ! fuzzy_match "ABC" "abcdef"
}

# =============================================================================
# FUZZY SCORE TESTS
# =============================================================================

@test "fuzzy_score: exact match has high score" {
    local result
    result=$(fuzzy_score "hello" "hello")
    [ "$result" -gt 50 ]
}

@test "fuzzy_score: no match returns 0" {
    local result
    result=$(fuzzy_score "xyz" "abc")
    [ "$result" = "0" ]
}

@test "fuzzy_score: consecutive matches score higher" {
    local score1 score2
    score1=$(fuzzy_score "abc" "abc")
    score2=$(fuzzy_score "abc" "a_b_c")
    [ "$score1" -gt "$score2" ]
}

@test "fuzzy_score: word boundary matches score higher" {
    local score1 score2
    score1=$(fuzzy_score "fb" "foo_bar")  # Matches at boundaries
    score2=$(fuzzy_score "fb" "foobar")   # Not at boundary
    # Both should have scores, boundary should be higher
    [ "$score1" -ge "$score2" ]
}

# =============================================================================
# FUZZY MATCH POSITIONS TESTS
# =============================================================================

@test "fuzzy_match_positions: returns correct positions" {
    local result
    result=$(fuzzy_match_positions "abc" "a1b2c3")
    [ "$result" = "[0,2,4]" ]
}

@test "fuzzy_match_positions: empty pattern returns empty array" {
    local result
    result=$(fuzzy_match_positions "" "hello")
    [ "$result" = "[]" ]
}

@test "fuzzy_match_positions: consecutive match" {
    local result
    result=$(fuzzy_match_positions "hel" "hello")
    [ "$result" = "[0,1,2]" ]
}

# =============================================================================
# FUZZY HIGHLIGHT TESTS
# =============================================================================

@test "fuzzy_highlight: highlights matched characters" {
    local result
    # Use visible markers instead of ANSI codes
    result=$(fuzzy_highlight "ab" "a1b2" "[" "]")
    [ "$result" = "[a]1[b]2" ]
}

@test "fuzzy_highlight: empty pattern returns original string" {
    local result
    result=$(fuzzy_highlight "" "hello")
    [ "$result" = "hello" ]
}

# =============================================================================
# FUZZY FILTER/SORT TESTS
# =============================================================================

@test "fuzzy_filter: filters matching items" {
    local result
    result=$(fuzzy_filter "py" "python" "ruby" "php" "perl")
    [[ "$result" == *"python"* ]]
    [[ "$result" != *"ruby"* ]]
}

@test "fuzzy_sort: sorts by match quality" {
    local result
    result=$(fuzzy_sort "py" "pypy" "python" "php" "ruby")
    # First line should be best match
    local first
    first=$(echo "$result" | head -1)
    [[ "$first" == "pypy" || "$first" == "python" ]]
}

@test "fuzzy_best_match: finds best match" {
    local result
    result=$(fuzzy_best_match "pythn" "python" "python3" "pypy")
    [[ "$result" == *"python"* ]]
}

@test "fuzzy_top_n: returns n results as JSON" {
    local result
    result=$(fuzzy_top_n "py" 2 "python" "pypy" "php" "ruby")
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
    [[ "$result" == *"item"* ]]
    [[ "$result" == *"score"* ]]
}

@test "fuzzy_rank: ranks all items" {
    local result
    result=$(fuzzy_rank "py" "python" "ruby")
    [[ "$result" == "["* ]]
    [[ "$result" == *"rank"* ]]
}

# =============================================================================
# APPROXIMATE SEARCH TESTS
# =============================================================================

@test "fuzzy_search: finds approximate matches" {
    local result
    result=$(fuzzy_search "helo" "hello world")
    [[ "$result" == *"hello"* ]] || [[ "$result" == *"match"* ]]
}

@test "fuzzy_search: returns positions" {
    local result
    result=$(fuzzy_search "test" "testing 123")
    [[ "$result" == *"position"* ]]
}

@test "fuzzy_grep: filters lines" {
    local result
    result=$(echo -e "foo\nbar\nbaz" | fuzzy_grep "ba")
    [[ "$result" == *"bar"* ]]
    [[ "$result" == *"baz"* ]]
    [[ "$result" != *"foo"* ]]
}

@test "fuzzy_index_of: finds position" {
    local result
    result=$(fuzzy_index_of "helo" "say hello")
    [ "$result" = "4" ]
}

@test "fuzzy_index_of: returns -1 when not found" {
    local result
    result=$(fuzzy_index_of "xyz" "hello world" 1)
    [ "$result" = "-1" ]
}

# =============================================================================
# SOUNDEX TESTS
# =============================================================================

@test "soundex: Robert example" {
    local result
    result=$(soundex "Robert")
    [ "$result" = "R163" ]
}

@test "soundex: Rupert sounds like Robert" {
    local s1 s2
    s1=$(soundex "Robert")
    s2=$(soundex "Rupert")
    [ "$s1" = "$s2" ]
}

@test "soundex: pads with zeros" {
    local result
    result=$(soundex "A")
    [ "${#result}" = "4" ]
    [ "$result" = "A000" ]
}

@test "soundex: handles empty string" {
    local result
    result=$(soundex "")
    [ "$result" = "" ]
}

@test "soundex: Smith example" {
    local result
    result=$(soundex "Smith")
    [ "$result" = "S530" ]
}

# =============================================================================
# METAPHONE TESTS
# =============================================================================

@test "metaphone: basic word" {
    local result
    result=$(metaphone "hello")
    [[ -n "$result" ]]
}

@test "metaphone: knight silent K" {
    local result
    result=$(metaphone "knight")
    [[ "$result" != K* ]]  # K should be dropped
}

@test "metaphone: phone PH->F" {
    local result
    result=$(metaphone "phone")
    [[ "$result" == F* ]]
}

@test "metaphone: handles empty string" {
    local result
    result=$(metaphone "")
    [ "$result" = "" ]
}

# =============================================================================
# DOUBLE METAPHONE TESTS
# =============================================================================

@test "double_metaphone: returns JSON with primary" {
    local result
    result=$(double_metaphone "smith")
    [[ "$result" == *"primary"* ]]
    [[ "$result" == *"alternate"* ]]
}

@test "double_metaphone: handles empty string" {
    local result
    result=$(double_metaphone "")
    [[ "$result" == *"primary"* ]]
}

# =============================================================================
# PHONETIC MATCHING TESTS
# =============================================================================

@test "phonetic_match: Smith and Smyth match" {
    phonetic_match "Smith" "Smyth"
}

@test "phonetic_match: Robert and Rupert match" {
    phonetic_match "Robert" "Rupert"
}

@test "phonetic_match: completely different words don't match" {
    ! phonetic_match "apple" "zebra"
}

@test "phonetic_distance: returns similarity score" {
    local result
    result=$(phonetic_distance "Smith" "Smyth")
    [[ "$result" =~ ^[0-1]\.[0-9]+ ]]
}

# =============================================================================
# KEYBOARD DISTANCE TESTS
# =============================================================================

@test "keyboard_distance: same key returns 0" {
    local result
    result=$(keyboard_distance "a" "a")
    [ "$result" = "0.0" ]
}

@test "keyboard_distance: adjacent keys" {
    local result
    result=$(keyboard_distance "q" "w")
    # Should be ~1.0
    [[ "$result" =~ ^[0-2]\.[0-9]+ ]]
}

@test "keyboard_distance: far apart keys" {
    local result
    result=$(keyboard_distance "q" "m")
    # Should be larger
    [[ "$result" =~ ^[3-9]\.[0-9]+ ]]
}

# =============================================================================
# TYPO FUNCTIONS TESTS
# =============================================================================

@test "typo_candidates: generates variants" {
    local result
    result=$(typo_candidates "hello")
    [[ "$result" == "["* ]]
    # Should include deletion variant
    [[ "$result" == *"helo"* ]]
}

@test "typo_suggest: suggests corrections" {
    local result
    result=$(typo_suggest "helo" "hello" "help" "hero" "world")
    [[ "$result" == "["* ]]
    [[ "$result" == *"hello"* ]]
}

@test "typo_suggest: returns distance in results" {
    local result
    result=$(typo_suggest "helo" "hello")
    [[ "$result" == *"distance"* ]]
}

# =============================================================================
# N-GRAM TESTS
# =============================================================================

@test "ngrams: generates correct bigrams" {
    local result
    result=$(ngrams "hello" 2)
    [ "$result" = '["he","el","ll","lo"]' ]
}

@test "ngrams: generates correct trigrams" {
    local result
    result=$(ngrams "hello" 3)
    [ "$result" = '["hel","ell","llo"]' ]
}

@test "bigrams: shorthand for n=2" {
    local result
    result=$(bigrams "hello")
    [ "$result" = '["he","el","ll","lo"]' ]
}

@test "trigrams: shorthand for n=3" {
    local result
    result=$(trigrams "hello")
    [ "$result" = '["hel","ell","llo"]' ]
}

@test "ngrams: handles string shorter than n" {
    local result
    result=$(ngrams "hi" 3)
    [ "$result" = '["hi"]' ]
}

@test "ngrams: empty string returns empty array" {
    local result
    result=$(ngrams "" 2)
    [ "$result" = "[]" ]
}

@test "ngram_similarity: identical strings return 1.0" {
    local result
    result=$(ngram_similarity "hello" "hello" 2)
    [[ "$result" =~ ^1\.0 ]]
}

@test "ngram_similarity: different strings return lower score" {
    local result
    result=$(ngram_similarity "hello" "world" 2)
    [[ "$result" =~ ^0\.[0-9]+ ]]
}

# =============================================================================
# UTILITY TESTS
# =============================================================================

@test "normalize_for_fuzzy: lowercases" {
    local result
    result=$(normalize_for_fuzzy "HELLO")
    [ "$result" = "hello" ]
}

@test "normalize_for_fuzzy: collapses whitespace" {
    local result
    result=$(normalize_for_fuzzy "  hello   world  ")
    [ "$result" = "hello world" ]
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

@test "fuzzy_set_threshold: sets valid threshold" {
    fuzzy_set_threshold 0.8
    [ "$FUZZY_THRESHOLD" = "0.8" ]
}

@test "fuzzy_set_threshold: rejects invalid threshold" {
    run fuzzy_set_threshold 1.5
    [ "$status" = "1" ]
}

@test "fuzzy_set_algorithm: sets valid algorithm" {
    fuzzy_set_algorithm "jaro_winkler"
    [ "$FUZZY_ALGORITHM" = "jaro_winkler" ]
}

@test "fuzzy_set_algorithm: rejects invalid algorithm" {
    run fuzzy_set_algorithm "invalid"
    [ "$status" = "1" ]
}

@test "fuzzy_info: returns JSON" {
    local result
    result=$(fuzzy_info)
    [[ "$result" == *"library"* ]]
    [[ "$result" == *"fuzzy"* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles unicode strings" {
    local result
    result=$(levenshtein_distance "cafe" "cafe")
    [ "$result" = "0" ]
}

@test "handles strings with numbers" {
    local result
    result=$(levenshtein_distance "test123" "test456")
    [ "$result" = "3" ]
}

@test "handles special characters" {
    local result
    result=$(levenshtein_distance "hello-world" "hello_world")
    [ "$result" = "1" ]
}

@test "handles very short strings" {
    local result
    result=$(levenshtein_distance "a" "b")
    [ "$result" = "1" ]
}

@test "handles single character strings" {
    local result
    result=$(levenshtein_similarity "a" "a")
    [ "$result" = "1.0" ] || [ "$result" = "1.000" ]
}

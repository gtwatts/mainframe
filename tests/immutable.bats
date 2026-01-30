#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Immutable Data Structures Tests
# =============================================================================
# Comprehensive tests for lib/immutable.sh (50+ functions)
# Covers: imap, ilist, iset, structural sharing, serialization
# =============================================================================

load 'test_helper'

setup() {
    source_lib "immutable"
    export MAINFRAME_QUIET=1
    export MAINFRAME_IMMUTABLE_JSON=0  # Use plain output for easier testing
    TEST_DIR=$(create_test_dir "immutable")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# IMAP_CREATE TESTS
# =============================================================================

@test "imap_create returns valid ID" {
    local id
    id=$(imap_create)
    [[ "$id" =~ ^imap_[0-9]+_[0-9]+$ ]]
}

@test "imap_create creates empty map" {
    local id
    id=$(imap_create)
    local size
    size=$(imap_size "$id")
    [ "$size" -eq 0 ]
}

@test "imap_create returns unique IDs" {
    local id1 id2
    id1=$(imap_create)
    id2=$(imap_create)
    [ "$id1" != "$id2" ]
}

# =============================================================================
# IMAP_FROM_PAIRS TESTS
# =============================================================================

@test "imap_from_pairs creates map with entries" {
    local id
    id=$(imap_from_pairs "name=John" "age=30")
    local size
    size=$(imap_size "$id")
    [ "$size" -eq 2 ]
}

@test "imap_from_pairs stores correct values" {
    local id
    id=$(imap_from_pairs "name=John" "city=NYC")
    local name city
    name=$(imap_get "$id" "name")
    city=$(imap_get "$id" "city")
    [ "$name" = "John" ]
    [ "$city" = "NYC" ]
}

@test "imap_from_pairs handles typed values" {
    local id
    id=$(imap_from_pairs "count:number=42" "active:bool=true")
    local count active
    count=$(imap_get "$id" "count")
    active=$(imap_get "$id" "active")
    [ "$count" = "42" ]
    [ "$active" = "true" ]
}

@test "imap_from_pairs handles empty value" {
    local id
    id=$(imap_from_pairs "empty=")
    local val
    val=$(imap_get "$id" "empty")
    [ "$val" = "" ]
}

# =============================================================================
# IMAP_SET TESTS
# =============================================================================

@test "imap_set returns new map ID" {
    local id1 id2
    id1=$(imap_create)
    id2=$(imap_set "$id1" "key" "value")
    [ "$id1" != "$id2" ]
}

@test "imap_set preserves original map" {
    local id1 id2
    id1=$(imap_from_pairs "a=1")
    id2=$(imap_set "$id1" "b" "2")

    # Original should still have only "a"
    local size1 size2
    size1=$(imap_size "$id1")
    size2=$(imap_size "$id2")
    [ "$size1" -eq 1 ]
    [ "$size2" -eq 2 ]
}

@test "imap_set updates existing key" {
    local id1 id2
    id1=$(imap_from_pairs "key=old")
    id2=$(imap_set "$id1" "key" "new")

    local old_val new_val
    old_val=$(imap_get "$id1" "key")
    new_val=$(imap_get "$id2" "key")
    [ "$old_val" = "old" ]
    [ "$new_val" = "new" ]
}

@test "imap_set fails without map_id" {
    run imap_set "" "key" "value"
    [ "$status" -ne 0 ]
}

@test "imap_set fails without key" {
    local id
    id=$(imap_create)
    run imap_set "$id" "" "value"
    [ "$status" -ne 0 ]
}

# =============================================================================
# IMAP_GET TESTS
# =============================================================================

@test "imap_get returns correct value" {
    local id
    id=$(imap_from_pairs "name=Alice")
    local val
    val=$(imap_get "$id" "name")
    [ "$val" = "Alice" ]
}

@test "imap_get returns empty for missing key" {
    local id
    id=$(imap_create)
    local val
    val=$(imap_get "$id" "nonexistent")
    [ "$val" = "" ]
}

@test "imap_get handles special characters" {
    local id
    id=$(imap_from_pairs "greeting=Hello World!")
    local val
    val=$(imap_get "$id" "greeting")
    [ "$val" = "Hello World!" ]
}

# =============================================================================
# IMAP_HAS TESTS
# =============================================================================

@test "imap_has returns 0 for existing key" {
    local id
    id=$(imap_from_pairs "exists=yes")
    imap_has "$id" "exists"
}

@test "imap_has returns 1 for missing key" {
    local id
    id=$(imap_create)
    ! imap_has "$id" "missing"
}

# =============================================================================
# IMAP_DELETE TESTS
# =============================================================================

@test "imap_delete returns new map without key" {
    local id1 id2
    id1=$(imap_from_pairs "a=1" "b=2")
    id2=$(imap_delete "$id1" "a")

    imap_has "$id1" "a"  # Original still has it
    ! imap_has "$id2" "a"  # New one doesn't
}

@test "imap_delete preserves other keys" {
    local id1 id2
    id1=$(imap_from_pairs "a=1" "b=2" "c=3")
    id2=$(imap_delete "$id1" "b")

    local val_a val_c
    val_a=$(imap_get "$id2" "a")
    val_c=$(imap_get "$id2" "c")
    [ "$val_a" = "1" ]
    [ "$val_c" = "3" ]
}

@test "imap_delete handles non-existent key" {
    local id1 id2
    id1=$(imap_from_pairs "a=1")
    id2=$(imap_delete "$id1" "nonexistent")

    local size
    size=$(imap_size "$id2")
    [ "$size" -eq 1 ]
}

# =============================================================================
# IMAP_KEYS, IMAP_VALUES, IMAP_ENTRIES TESTS
# =============================================================================

@test "imap_keys returns all keys" {
    local id
    id=$(imap_from_pairs "a=1" "b=2")
    local keys
    keys=$(imap_keys "$id" | sort)
    [ "$(echo "$keys" | head -1)" = "a" ]
    [ "$(echo "$keys" | tail -1)" = "b" ]
}

@test "imap_values returns all values" {
    local id
    id=$(imap_from_pairs "a=1" "b=2")
    local values
    values=$(imap_values "$id" | sort)
    [ "$(echo "$values" | head -1)" = "1" ]
    [ "$(echo "$values" | tail -1)" = "2" ]
}

@test "imap_entries returns key=value pairs" {
    local id
    id=$(imap_from_pairs "name=John")
    local entries
    entries=$(imap_entries "$id")
    [ "$entries" = "name=John" ]
}

# =============================================================================
# IMAP_SIZE, IMAP_IS_EMPTY TESTS
# =============================================================================

@test "imap_size returns correct count" {
    local id
    id=$(imap_from_pairs "a=1" "b=2" "c=3")
    local size
    size=$(imap_size "$id")
    [ "$size" -eq 3 ]
}

@test "imap_is_empty returns 0 for empty map" {
    local id
    id=$(imap_create)
    imap_is_empty "$id"
}

@test "imap_is_empty returns 1 for non-empty map" {
    local id
    id=$(imap_from_pairs "a=1")
    ! imap_is_empty "$id"
}

# =============================================================================
# IMAP_MERGE TESTS
# =============================================================================

@test "imap_merge combines two maps" {
    local id1 id2 merged
    id1=$(imap_from_pairs "a=1" "b=2")
    id2=$(imap_from_pairs "c=3" "d=4")
    merged=$(imap_merge "$id1" "$id2")

    local size
    size=$(imap_size "$merged")
    [ "$size" -eq 4 ]
}

@test "imap_merge second map wins on conflict" {
    local id1 id2 merged
    id1=$(imap_from_pairs "key=old")
    id2=$(imap_from_pairs "key=new")
    merged=$(imap_merge "$id1" "$id2")

    local val
    val=$(imap_get "$merged" "key")
    [ "$val" = "new" ]
}

# =============================================================================
# IMAP_MAP_VALUES TESTS
# =============================================================================

@test "imap_map_values transforms values" {
    _test_uppercase() {
        echo "${2^^}"
    }

    local id new_id
    id=$(imap_from_pairs "name=john" "city=nyc")
    new_id=$(imap_map_values "$id" "_test_uppercase")

    local name city
    name=$(imap_get "$new_id" "name")
    city=$(imap_get "$new_id" "city")
    [ "$name" = "JOHN" ]
    [ "$city" = "NYC" ]
}

# =============================================================================
# IMAP_FILTER TESTS
# =============================================================================

@test "imap_filter keeps matching entries" {
    _test_positive() {
        [[ "$2" -gt 0 ]]
    }

    local id filtered
    id=$(imap_from_pairs "a=-1" "b=5" "c=10")
    filtered=$(imap_filter "$id" "_test_positive")

    local size
    size=$(imap_size "$filtered")
    [ "$size" -eq 2 ]
    ! imap_has "$filtered" "a"
}

# =============================================================================
# IMAP_TO_JSON, IMAP_FROM_JSON TESTS
# =============================================================================

@test "imap_to_json creates valid JSON" {
    local id json
    id=$(imap_from_pairs "name=John")
    json=$(imap_to_json "$id")
    [ "$json" = '{"name":"John"}' ]
}

@test "imap_to_json handles empty map" {
    local id json
    id=$(imap_create)
    json=$(imap_to_json "$id")
    [ "$json" = '{}' ]
}

@test "imap_from_json parses JSON" {
    local id name
    id=$(imap_from_json '{"name":"Alice","age":"25"}')
    name=$(imap_get "$id" "name")
    [ "$name" = "Alice" ]
}

@test "imap round-trip preserves data" {
    local id1 json id2 val
    id1=$(imap_from_pairs "key=value")
    json=$(imap_to_json "$id1")
    id2=$(imap_from_json "$json")
    val=$(imap_get "$id2" "key")
    [ "$val" = "value" ]
}

# =============================================================================
# ILIST_CREATE TESTS
# =============================================================================

@test "ilist_create returns valid ID" {
    local id
    id=$(ilist_create)
    [[ "$id" =~ ^ilist_[0-9]+_[0-9]+$ ]]
}

@test "ilist_create creates empty list" {
    local id size
    id=$(ilist_create)
    size=$(ilist_size "$id")
    [ "$size" -eq 0 ]
}

# =============================================================================
# ILIST_FROM_ARRAY TESTS
# =============================================================================

@test "ilist_from_array creates list with elements" {
    local id size
    id=$(ilist_from_array "a" "b" "c")
    size=$(ilist_size "$id")
    [ "$size" -eq 3 ]
}

@test "ilist_from_array preserves order" {
    local id
    id=$(ilist_from_array "first" "second" "third")
    local first second third
    first=$(ilist_get "$id" 0)
    second=$(ilist_get "$id" 1)
    third=$(ilist_get "$id" 2)
    [ "$first" = "first" ]
    [ "$second" = "second" ]
    [ "$third" = "third" ]
}

# =============================================================================
# ILIST_APPEND, ILIST_PREPEND TESTS
# =============================================================================

@test "ilist_append adds to end" {
    local id1 id2
    id1=$(ilist_from_array "a" "b")
    id2=$(ilist_append "$id1" "c")

    local last
    last=$(ilist_get "$id2" 2)
    [ "$last" = "c" ]
}

@test "ilist_append preserves original" {
    local id1 id2
    id1=$(ilist_from_array "a")
    id2=$(ilist_append "$id1" "b")

    local size1 size2
    size1=$(ilist_size "$id1")
    size2=$(ilist_size "$id2")
    [ "$size1" -eq 1 ]
    [ "$size2" -eq 2 ]
}

@test "ilist_prepend adds to start" {
    local id1 id2
    id1=$(ilist_from_array "b" "c")
    id2=$(ilist_prepend "$id1" "a")

    local first
    first=$(ilist_get "$id2" 0)
    [ "$first" = "a" ]
}

@test "ilist_prepend shifts existing elements" {
    local id1 id2
    id1=$(ilist_from_array "x")
    id2=$(ilist_prepend "$id1" "y")

    local second
    second=$(ilist_get "$id2" 1)
    [ "$second" = "x" ]
}

# =============================================================================
# ILIST_GET TESTS
# =============================================================================

@test "ilist_get returns correct element" {
    local id val
    id=$(ilist_from_array "a" "b" "c")
    val=$(ilist_get "$id" 1)
    [ "$val" = "b" ]
}

@test "ilist_get handles negative index" {
    local id val
    id=$(ilist_from_array "a" "b" "c")
    val=$(ilist_get "$id" -1)
    [ "$val" = "c" ]
}

@test "ilist_get returns empty for out of bounds" {
    local id val
    id=$(ilist_from_array "a")
    val=$(ilist_get "$id" 10)
    [ "$val" = "" ]
}

# =============================================================================
# ILIST_SET TESTS
# =============================================================================

@test "ilist_set replaces element at index" {
    local id1 id2
    id1=$(ilist_from_array "a" "b" "c")
    id2=$(ilist_set "$id1" 1 "B")

    local val
    val=$(ilist_get "$id2" 1)
    [ "$val" = "B" ]
}

@test "ilist_set preserves original" {
    local id1 id2
    id1=$(ilist_from_array "a" "b")
    id2=$(ilist_set "$id1" 0 "A")

    local orig
    orig=$(ilist_get "$id1" 0)
    [ "$orig" = "a" ]
}

# =============================================================================
# ILIST_REMOVE TESTS
# =============================================================================

@test "ilist_remove removes element at index" {
    local id1 id2
    id1=$(ilist_from_array "a" "b" "c")
    id2=$(ilist_remove "$id1" 1)

    local size
    size=$(ilist_size "$id2")
    [ "$size" -eq 2 ]
}

@test "ilist_remove shifts remaining elements" {
    local id1 id2
    id1=$(ilist_from_array "a" "b" "c")
    id2=$(ilist_remove "$id1" 0)

    local first
    first=$(ilist_get "$id2" 0)
    [ "$first" = "b" ]
}

# =============================================================================
# ILIST_SLICE TESTS
# =============================================================================

@test "ilist_slice extracts range" {
    local id sliced
    id=$(ilist_from_array "a" "b" "c" "d" "e")
    sliced=$(ilist_slice "$id" 1 4)

    local size first last
    size=$(ilist_size "$sliced")
    first=$(ilist_get "$sliced" 0)
    last=$(ilist_get "$sliced" 2)
    [ "$size" -eq 3 ]
    [ "$first" = "b" ]
    [ "$last" = "d" ]
}

@test "ilist_slice handles negative indices" {
    local id sliced
    id=$(ilist_from_array "a" "b" "c" "d")
    sliced=$(ilist_slice "$id" -2)

    local size
    size=$(ilist_size "$sliced")
    [ "$size" -eq 2 ]
}

# =============================================================================
# ILIST_CONCAT TESTS
# =============================================================================

@test "ilist_concat combines two lists" {
    local id1 id2 combined
    id1=$(ilist_from_array "a" "b")
    id2=$(ilist_from_array "c" "d")
    combined=$(ilist_concat "$id1" "$id2")

    local size
    size=$(ilist_size "$combined")
    [ "$size" -eq 4 ]
}

@test "ilist_concat preserves order" {
    local id1 id2 combined
    id1=$(ilist_from_array "1" "2")
    id2=$(ilist_from_array "3" "4")
    combined=$(ilist_concat "$id1" "$id2")

    local third
    third=$(ilist_get "$combined" 2)
    [ "$third" = "3" ]
}

# =============================================================================
# ILIST_MAP TESTS
# =============================================================================

@test "ilist_map transforms elements" {
    _test_double() {
        echo $(($2 * 2))
    }

    local id mapped
    id=$(ilist_from_array 1 2 3)
    mapped=$(ilist_map "$id" "_test_double")

    local first second third
    first=$(ilist_get "$mapped" 0)
    second=$(ilist_get "$mapped" 1)
    third=$(ilist_get "$mapped" 2)
    [ "$first" -eq 2 ]
    [ "$second" -eq 4 ]
    [ "$third" -eq 6 ]
}

# =============================================================================
# ILIST_FILTER TESTS
# =============================================================================

@test "ilist_filter keeps matching elements" {
    _test_even() {
        [[ $(($2 % 2)) -eq 0 ]]
    }

    local id filtered
    id=$(ilist_from_array 1 2 3 4 5 6)
    filtered=$(ilist_filter "$id" "_test_even")

    local size
    size=$(ilist_size "$filtered")
    [ "$size" -eq 3 ]
}

# =============================================================================
# ILIST_REDUCE TESTS
# =============================================================================

@test "ilist_reduce accumulates values" {
    _test_sum() {
        echo $(($1 + $3))
    }

    local id result
    id=$(ilist_from_array 1 2 3 4 5)
    result=$(ilist_reduce "$id" "_test_sum" 0)
    [ "$result" -eq 15 ]
}

# =============================================================================
# ILIST_TO_JSON, ILIST_FROM_JSON TESTS
# =============================================================================

@test "ilist_to_json creates valid JSON array" {
    local id json
    id=$(ilist_from_array "a" "b" "c")
    json=$(ilist_to_json "$id")
    [ "$json" = '["a","b","c"]' ]
}

@test "ilist_from_json parses JSON array" {
    local id val
    id=$(ilist_from_json '["x","y","z"]')
    val=$(ilist_get "$id" 1)
    [ "$val" = "y" ]
}

# =============================================================================
# ISET_CREATE TESTS
# =============================================================================

@test "iset_create returns valid ID" {
    local id
    id=$(iset_create)
    [[ "$id" =~ ^iset_[0-9]+_[0-9]+$ ]]
}

@test "iset_create creates empty set" {
    local id size
    id=$(iset_create)
    size=$(iset_size "$id")
    [ "$size" -eq 0 ]
}

# =============================================================================
# ISET_FROM_ARRAY TESTS
# =============================================================================

@test "iset_from_array creates set with elements" {
    local id size
    id=$(iset_from_array "a" "b" "c")
    size=$(iset_size "$id")
    [ "$size" -eq 3 ]
}

@test "iset_from_array removes duplicates" {
    local id size
    id=$(iset_from_array "a" "b" "a" "c" "b")
    size=$(iset_size "$id")
    [ "$size" -eq 3 ]
}

# =============================================================================
# ISET_ADD TESTS
# =============================================================================

@test "iset_add returns new set with element" {
    local id1 id2
    id1=$(iset_create)
    id2=$(iset_add "$id1" "x")

    iset_has "$id2" "x"
}

@test "iset_add is idempotent for existing element" {
    local id1 id2
    id1=$(iset_from_array "x")
    id2=$(iset_add "$id1" "x")

    local size
    size=$(iset_size "$id2")
    [ "$size" -eq 1 ]
}

# =============================================================================
# ISET_REMOVE TESTS
# =============================================================================

@test "iset_remove returns new set without element" {
    local id1 id2
    id1=$(iset_from_array "a" "b" "c")
    id2=$(iset_remove "$id1" "b")

    ! iset_has "$id2" "b"
    iset_has "$id2" "a"
    iset_has "$id2" "c"
}

# =============================================================================
# ISET_HAS TESTS
# =============================================================================

@test "iset_has returns 0 for member" {
    local id
    id=$(iset_from_array "member")
    iset_has "$id" "member"
}

@test "iset_has returns 1 for non-member" {
    local id
    id=$(iset_from_array "a")
    ! iset_has "$id" "nonmember"
}

# =============================================================================
# ISET_UNION TESTS
# =============================================================================

@test "iset_union combines sets" {
    local id1 id2 union
    id1=$(iset_from_array "a" "b")
    id2=$(iset_from_array "c" "d")
    union=$(iset_union "$id1" "$id2")

    local size
    size=$(iset_size "$union")
    [ "$size" -eq 4 ]
}

@test "iset_union removes duplicates" {
    local id1 id2 union
    id1=$(iset_from_array "a" "b")
    id2=$(iset_from_array "b" "c")
    union=$(iset_union "$id1" "$id2")

    local size
    size=$(iset_size "$union")
    [ "$size" -eq 3 ]
}

# =============================================================================
# ISET_INTERSECT TESTS
# =============================================================================

@test "iset_intersect finds common elements" {
    local id1 id2 inter
    id1=$(iset_from_array "a" "b" "c")
    id2=$(iset_from_array "b" "c" "d")
    inter=$(iset_intersect "$id1" "$id2")

    local size
    size=$(iset_size "$inter")
    [ "$size" -eq 2 ]
    iset_has "$inter" "b"
    iset_has "$inter" "c"
}

# =============================================================================
# ISET_DIFFERENCE TESTS
# =============================================================================

@test "iset_difference finds unique elements" {
    local id1 id2 diff
    id1=$(iset_from_array "a" "b" "c")
    id2=$(iset_from_array "b" "c" "d")
    diff=$(iset_difference "$id1" "$id2")

    local size
    size=$(iset_size "$diff")
    [ "$size" -eq 1 ]
    iset_has "$diff" "a"
}

# =============================================================================
# ISET_IS_SUBSET TESTS
# =============================================================================

@test "iset_is_subset returns 0 for subset" {
    local id1 id2
    id1=$(iset_from_array "a" "b")
    id2=$(iset_from_array "a" "b" "c")
    iset_is_subset "$id1" "$id2"
}

@test "iset_is_subset returns 1 for non-subset" {
    local id1 id2
    id1=$(iset_from_array "a" "b" "x")
    id2=$(iset_from_array "a" "b" "c")
    ! iset_is_subset "$id1" "$id2"
}

@test "iset_is_subset empty set is subset of any" {
    local empty full
    empty=$(iset_create)
    full=$(iset_from_array "a" "b")
    iset_is_subset "$empty" "$full"
}

# =============================================================================
# IMMUT_FREEZE, IMMUT_IS_FROZEN, IMMUT_THAW TESTS
# =============================================================================

@test "immut_freeze marks structure as frozen" {
    local id
    id=$(imap_create)
    immut_freeze "$id" > /dev/null
    immut_is_frozen "$id"
}

@test "immut_is_frozen returns 1 for unfrozen" {
    local id
    id=$(imap_create)
    ! immut_is_frozen "$id"
}

@test "immut_thaw creates unfrozen copy" {
    local id frozen thawed
    id=$(imap_from_pairs "a=1")
    immut_freeze "$id" > /dev/null
    thawed=$(immut_thaw "$id")

    ! immut_is_frozen "$thawed"
}

# =============================================================================
# IMMUT_EQUALS TESTS
# =============================================================================

@test "immut_equals returns 0 for equal maps" {
    local id1 id2
    id1=$(imap_from_pairs "a=1" "b=2")
    id2=$(imap_from_pairs "a=1" "b=2")
    immut_equals "$id1" "$id2"
}

@test "immut_equals returns 1 for different maps" {
    local id1 id2
    id1=$(imap_from_pairs "a=1")
    id2=$(imap_from_pairs "a=2")
    ! immut_equals "$id1" "$id2"
}

@test "immut_equals returns 0 for equal lists" {
    local id1 id2
    id1=$(ilist_from_array "a" "b" "c")
    id2=$(ilist_from_array "a" "b" "c")
    immut_equals "$id1" "$id2"
}

@test "immut_equals returns 1 for different order" {
    local id1 id2
    id1=$(ilist_from_array "a" "b")
    id2=$(ilist_from_array "b" "a")
    ! immut_equals "$id1" "$id2"
}

@test "immut_equals returns 0 for equal sets" {
    local id1 id2
    id1=$(iset_from_array "a" "b")
    id2=$(iset_from_array "b" "a")  # Order doesn't matter for sets
    immut_equals "$id1" "$id2"
}

# =============================================================================
# IMMUT_HASH TESTS
# =============================================================================

@test "immut_hash returns same hash for equal structures" {
    local id1 id2 hash1 hash2
    id1=$(imap_from_pairs "a=1" "b=2")
    id2=$(imap_from_pairs "b=2" "a=1")  # Different order, same content
    hash1=$(immut_hash "$id1")
    hash2=$(immut_hash "$id2")
    [ "$hash1" = "$hash2" ]
}

@test "immut_hash returns different hash for different structures" {
    local id1 id2 hash1 hash2
    id1=$(imap_from_pairs "a=1")
    id2=$(imap_from_pairs "a=2")
    hash1=$(immut_hash "$id1")
    hash2=$(immut_hash "$id2")
    [ "$hash1" != "$hash2" ]
}

# =============================================================================
# IMMUT_TYPE, IMMUT_SIZE, IMMUT_IS_EMPTY TESTS
# =============================================================================

@test "immut_type returns map for imap" {
    local id type
    id=$(imap_create)
    type=$(immut_type "$id")
    [ "$type" = "map" ]
}

@test "immut_type returns list for ilist" {
    local id type
    id=$(ilist_create)
    type=$(immut_type "$id")
    [ "$type" = "list" ]
}

@test "immut_type returns set for iset" {
    local id type
    id=$(iset_create)
    type=$(immut_type "$id")
    [ "$type" = "set" ]
}

@test "immut_size works for all types" {
    local map list set
    map=$(imap_from_pairs "a=1" "b=2")
    list=$(ilist_from_array "x" "y")
    set=$(iset_from_array "p" "q" "r")

    [ "$(immut_size "$map")" -eq 2 ]
    [ "$(immut_size "$list")" -eq 2 ]
    [ "$(immut_size "$set")" -eq 3 ]
}

@test "immut_is_empty works for all types" {
    local empty_map empty_list empty_set
    empty_map=$(imap_create)
    empty_list=$(ilist_create)
    empty_set=$(iset_create)

    immut_is_empty "$empty_map"
    immut_is_empty "$empty_list"
    immut_is_empty "$empty_set"
}

# =============================================================================
# IMMUT_FREE TESTS
# =============================================================================

@test "immut_free cleans up structure" {
    local id
    id=$(imap_from_pairs "a=1")
    immut_free "$id"

    # After free, type should be unknown
    local type
    type=$(immut_type "$id")
    [ "$type" = "unknown" ]
}

# =============================================================================
# ITERATION HELPERS TESTS
# =============================================================================

@test "ilist_each outputs all elements" {
    local id count
    id=$(ilist_from_array "a" "b" "c")
    count=$(ilist_each "$id" | wc -l)
    [ "$count" -eq 3 ]
}

@test "imap_each outputs all entries" {
    local id count
    id=$(imap_from_pairs "x=1" "y=2")
    count=$(imap_each "$id" | wc -l)
    [ "$count" -eq 2 ]
}

@test "iset_each outputs all values" {
    local id count
    id=$(iset_from_array "p" "q" "r")
    count=$(iset_each "$id" | wc -l)
    [ "$count" -eq 3 ]
}

# =============================================================================
# COPY-ON-WRITE VERIFICATION
# =============================================================================

@test "imap operations never mutate original" {
    local orig
    orig=$(imap_from_pairs "a=1")

    imap_set "$orig" "b" "2" > /dev/null
    imap_delete "$orig" "a" > /dev/null

    # Original should be unchanged
    local size val
    size=$(imap_size "$orig")
    val=$(imap_get "$orig" "a")
    [ "$size" -eq 1 ]
    [ "$val" = "1" ]
}

@test "ilist operations never mutate original" {
    local orig
    orig=$(ilist_from_array "x")

    ilist_append "$orig" "y" > /dev/null
    ilist_prepend "$orig" "w" > /dev/null
    ilist_remove "$orig" 0 > /dev/null 2>&1 || true

    # Original should be unchanged
    local size val
    size=$(ilist_size "$orig")
    val=$(ilist_get "$orig" 0)
    [ "$size" -eq 1 ]
    [ "$val" = "x" ]
}

@test "iset operations never mutate original" {
    local orig
    orig=$(iset_from_array "a")

    iset_add "$orig" "b" > /dev/null
    iset_remove "$orig" "a" > /dev/null

    # Original should be unchanged
    local size
    size=$(iset_size "$orig")
    [ "$size" -eq 1 ]
    iset_has "$orig" "a"
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "imap handles empty string key" {
    local id
    id=$(imap_from_pairs "=empty_key_value")
    local val
    val=$(imap_get "$id" "")
    [ "$val" = "empty_key_value" ]
}

@test "ilist handles empty string value" {
    local id
    id=$(ilist_from_array "" "non-empty" "")
    local size
    size=$(ilist_size "$id")
    [ "$size" -eq 3 ]
}

@test "iset handles empty string value" {
    local id
    id=$(iset_from_array "" "a")
    iset_has "$id" ""
}

@test "structures handle special characters" {
    local id val
    id=$(imap_from_pairs "key=value with spaces and 'quotes'")
    val=$(imap_get "$id" "key")
    [ "$val" = "value with spaces and 'quotes'" ]
}

@test "structures handle newlines in values" {
    local id
    id=$(imap_create)
    local new_id
    new_id=$(imap_set "$id" "multiline" $'line1\nline2')
    local val
    val=$(imap_get "$new_id" "multiline")
    [[ "$val" == *$'\n'* ]]
}

# =============================================================================
# VERSION INFO
# =============================================================================

@test "immut_version outputs version info" {
    local version
    version=$(immut_version)
    [[ "$version" == *"immutable"* ]]
    [[ "$version" == *"v1.0.0"* ]]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Queue Module Tests
# =============================================================================
# Comprehensive tests for lib/queue.sh (50+ functions)
# Covers: Queue (FIFO), Stack (LIFO), Deque, Priority Queue, Ring Buffer
# =============================================================================

load 'test_helper'

setup() {
    source_lib "queue"
    export MAINFRAME_QUIET=1
    export QUEUE_CONTRACTS=1
    TEST_DIR=$(create_test_dir "queue")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# HELPER FUNCTIONS FOR TESTS
# =============================================================================

# Predicates for filtering
is_even() { (( $1 % 2 == 0 )); }
is_positive() { (( $1 > 0 )); }
always_true() { return 0; }
always_false() { return 1; }

# Callbacks for iteration
echo_item() { echo "item: $1"; }
count_callback() { ((test_count++)) || true; }

# =============================================================================
# QUEUE (FIFO) TESTS
# =============================================================================

@test "queue_create initializes empty queue" {
    queue_create q
    [ "${#q[@]}" -eq 0 ]
}

@test "queue_push adds element to back" {
    queue_create q
    queue_push q "first"
    queue_push q "second"
    [ "${q[0]}" = "first" ]
    [ "${q[1]}" = "second" ]
}

@test "queue_push multiple elements preserves order" {
    queue_create q
    queue_push q "a"
    queue_push q "b"
    queue_push q "c"
    [ "${#q[@]}" -eq 3 ]
    [ "${q[0]}" = "a" ]
    [ "${q[2]}" = "c" ]
}

@test "queue_pop removes and returns front element" {
    queue_create q
    queue_push q "first"
    queue_push q "second"
    local result
    queue_pop_v q result
    [ "$result" = "first" ]
    [ "${#q[@]}" -eq 1 ]
}

@test "queue_pop returns elements in FIFO order" {
    queue_create q
    queue_push q "1"
    queue_push q "2"
    queue_push q "3"
    local result
    queue_pop_v q result
    [ "$result" = "1" ]
    queue_pop_v q result
    [ "$result" = "2" ]
    queue_pop_v q result
    [ "$result" = "3" ]
}

@test "queue_pop fails on empty queue" {
    queue_create q
    run queue_pop q
    [ "$status" -eq 1 ]
}

@test "queue_pop_v stores value in variable" {
    queue_create q
    queue_push q "value"
    local result
    queue_pop_v q result
    [ "$result" = "value" ]
    [ "${#q[@]}" -eq 0 ]
}

@test "queue_peek returns front without removing" {
    queue_create q
    queue_push q "front"
    queue_push q "back"
    local result
    result=$(queue_peek q)
    [ "$result" = "front" ]
    [ "${#q[@]}" -eq 2 ]
}

@test "queue_peek_v stores value in variable" {
    queue_create q
    queue_push q "value"
    local result
    queue_peek_v q result
    [ "$result" = "value" ]
    [ "${#q[@]}" -eq 1 ]
}

@test "queue_peek_back returns back element" {
    queue_create q
    queue_push q "front"
    queue_push q "back"
    local result
    result=$(queue_peek_back q)
    [ "$result" = "back" ]
}

@test "queue_size returns correct count" {
    queue_create q
    [ "$(queue_size q)" = "0" ]
    queue_push q "a"
    [ "$(queue_size q)" = "1" ]
    queue_push q "b"
    [ "$(queue_size q)" = "2" ]
}

@test "queue_is_empty returns 0 for empty queue" {
    queue_create q
    queue_is_empty q
}

@test "queue_is_empty returns 1 for non-empty queue" {
    queue_create q
    queue_push q "item"
    run queue_is_empty q
    [ "$status" -eq 1 ]
}

@test "queue_clear removes all elements" {
    queue_create q
    queue_push q "a"
    queue_push q "b"
    queue_clear q
    [ "${#q[@]}" -eq 0 ]
}

@test "queue_to_array copies elements" {
    queue_create q
    queue_push q "1"
    queue_push q "2"
    local result
    queue_to_array q result
    [ "${#result[@]}" -eq 2 ]
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
}

@test "queue_from_array initializes from array" {
    local arr=(a b c)
    queue_create q
    queue_from_array q arr
    [ "${#q[@]}" -eq 3 ]
    [ "${q[0]}" = "a" ]
}

# =============================================================================
# STACK (LIFO) TESTS
# =============================================================================

@test "stack_create initializes empty stack" {
    stack_create s
    [ "${#s[@]}" -eq 0 ]
}

@test "stack_push adds element to top" {
    stack_create s
    stack_push s "first"
    stack_push s "second"
    [ "${s[1]}" = "second" ]
}

@test "stack_pop removes and returns top element" {
    stack_create s
    stack_push s "bottom"
    stack_push s "top"
    local result
    stack_pop_v s result
    [ "$result" = "top" ]
    [ "${#s[@]}" -eq 1 ]
}

@test "stack_pop returns elements in LIFO order" {
    stack_create s
    stack_push s "1"
    stack_push s "2"
    stack_push s "3"
    local result
    stack_pop_v s result
    [ "$result" = "3" ]
    stack_pop_v s result
    [ "$result" = "2" ]
    stack_pop_v s result
    [ "$result" = "1" ]
}

@test "stack_pop fails on empty stack" {
    stack_create s
    run stack_pop s
    [ "$status" -eq 1 ]
}

@test "stack_pop_v stores value in variable" {
    stack_create s
    stack_push s "value"
    local result
    stack_pop_v s result
    [ "$result" = "value" ]
}

@test "stack_peek returns top without removing" {
    stack_create s
    stack_push s "bottom"
    stack_push s "top"
    local result
    result=$(stack_peek s)
    [ "$result" = "top" ]
    [ "${#s[@]}" -eq 2 ]
}

@test "stack_peek_v stores value in variable" {
    stack_create s
    stack_push s "value"
    local result
    stack_peek_v s result
    [ "$result" = "value" ]
    [ "${#s[@]}" -eq 1 ]
}

@test "stack_size returns correct depth" {
    stack_create s
    [ "$(stack_size s)" = "0" ]
    stack_push s "a"
    stack_push s "b"
    [ "$(stack_size s)" = "2" ]
}

@test "stack_is_empty returns 0 for empty stack" {
    stack_create s
    stack_is_empty s
}

@test "stack_is_empty returns 1 for non-empty stack" {
    stack_create s
    stack_push s "item"
    run stack_is_empty s
    [ "$status" -eq 1 ]
}

@test "stack_clear removes all elements" {
    stack_create s
    stack_push s "a"
    stack_push s "b"
    stack_clear s
    [ "${#s[@]}" -eq 0 ]
}

@test "stack_reverse reverses order" {
    stack_create s
    stack_push s "1"
    stack_push s "2"
    stack_push s "3"
    stack_reverse s
    [ "${s[0]}" = "3" ]
    [ "${s[1]}" = "2" ]
    [ "${s[2]}" = "1" ]
}

@test "stack_reverse on single element" {
    stack_create s
    stack_push s "only"
    stack_reverse s
    [ "${s[0]}" = "only" ]
}

@test "stack_to_array copies elements" {
    stack_create s
    stack_push s "a"
    stack_push s "b"
    local result
    stack_to_array s result
    [ "${#result[@]}" -eq 2 ]
}

# =============================================================================
# DEQUE TESTS
# =============================================================================

@test "deque_create initializes empty deque" {
    deque_create d
    [ "${#d[@]}" -eq 0 ]
}

@test "deque_push_front adds to front" {
    deque_create d
    deque_push_front d "second"
    deque_push_front d "first"
    [ "${d[0]}" = "first" ]
    [ "${d[1]}" = "second" ]
}

@test "deque_push_back adds to back" {
    deque_create d
    deque_push_back d "first"
    deque_push_back d "second"
    [ "${d[0]}" = "first" ]
    [ "${d[1]}" = "second" ]
}

@test "deque_pop_front removes from front" {
    deque_create d
    deque_push_back d "front"
    deque_push_back d "back"
    local result
    deque_pop_front_v d result
    [ "$result" = "front" ]
    [ "${#d[@]}" -eq 1 ]
}

@test "deque_pop_front_v stores value in variable" {
    deque_create d
    deque_push_back d "value"
    local result
    deque_pop_front_v d result
    [ "$result" = "value" ]
}

@test "deque_pop_back removes from back" {
    deque_create d
    deque_push_back d "front"
    deque_push_back d "back"
    local result
    deque_pop_back_v d result
    [ "$result" = "back" ]
    [ "${#d[@]}" -eq 1 ]
}

@test "deque_pop_back_v stores value in variable" {
    deque_create d
    deque_push_back d "value"
    local result
    deque_pop_back_v d result
    [ "$result" = "value" ]
}

@test "deque_peek_front returns front without removing" {
    deque_create d
    deque_push_back d "front"
    deque_push_back d "back"
    local result
    result=$(deque_peek_front d)
    [ "$result" = "front" ]
    [ "${#d[@]}" -eq 2 ]
}

@test "deque_peek_back returns back without removing" {
    deque_create d
    deque_push_back d "front"
    deque_push_back d "back"
    local result
    result=$(deque_peek_back d)
    [ "$result" = "back" ]
    [ "${#d[@]}" -eq 2 ]
}

@test "deque_size returns correct count" {
    deque_create d
    [ "$(deque_size d)" = "0" ]
    deque_push_back d "a"
    deque_push_front d "b"
    [ "$(deque_size d)" = "2" ]
}

@test "deque_is_empty returns 0 for empty deque" {
    deque_create d
    deque_is_empty d
}

@test "deque_clear removes all elements" {
    deque_create d
    deque_push_back d "a"
    deque_push_back d "b"
    deque_clear d
    [ "${#d[@]}" -eq 0 ]
}

@test "deque_rotate_left moves front to back" {
    deque_create d
    deque_push_back d "1"
    deque_push_back d "2"
    deque_push_back d "3"
    deque_rotate_left d
    [ "${d[0]}" = "2" ]
    [ "${d[1]}" = "3" ]
    [ "${d[2]}" = "1" ]
}

@test "deque_rotate_left with count" {
    deque_create d
    deque_push_back d "1"
    deque_push_back d "2"
    deque_push_back d "3"
    deque_push_back d "4"
    deque_rotate_left d 2
    [ "${d[0]}" = "3" ]
    [ "${d[1]}" = "4" ]
    [ "${d[2]}" = "1" ]
    [ "${d[3]}" = "2" ]
}

@test "deque_rotate_right moves back to front" {
    deque_create d
    deque_push_back d "1"
    deque_push_back d "2"
    deque_push_back d "3"
    deque_rotate_right d
    [ "${d[0]}" = "3" ]
    [ "${d[1]}" = "1" ]
    [ "${d[2]}" = "2" ]
}

@test "deque_rotate_right with count" {
    deque_create d
    deque_push_back d "1"
    deque_push_back d "2"
    deque_push_back d "3"
    deque_push_back d "4"
    deque_rotate_right d 2
    [ "${d[0]}" = "3" ]
    [ "${d[1]}" = "4" ]
    [ "${d[2]}" = "1" ]
    [ "${d[3]}" = "2" ]
}

@test "deque works as queue (FIFO)" {
    deque_create d
    deque_push_back d "1"
    deque_push_back d "2"
    deque_push_back d "3"
    local result
    deque_pop_front_v d result
    [ "$result" = "1" ]
    deque_pop_front_v d result
    [ "$result" = "2" ]
    deque_pop_front_v d result
    [ "$result" = "3" ]
}

@test "deque works as stack (LIFO)" {
    deque_create d
    deque_push_back d "1"
    deque_push_back d "2"
    deque_push_back d "3"
    local result
    deque_pop_back_v d result
    [ "$result" = "3" ]
    deque_pop_back_v d result
    [ "$result" = "2" ]
    deque_pop_back_v d result
    [ "$result" = "1" ]
}

# =============================================================================
# PRIORITY QUEUE TESTS
# =============================================================================

@test "pqueue_create initializes empty priority queue" {
    pqueue_create pq
    [ "${#pq[@]}" -eq 0 ]
}

@test "pqueue_push adds element with priority" {
    pqueue_create pq
    pqueue_push pq 5 "medium"
    pqueue_push pq 10 "high"
    pqueue_push pq 1 "low"
    [ "${#pq[@]}" -eq 3 ]
}

@test "pqueue_push maintains sorted order by priority" {
    pqueue_create pq
    pqueue_push pq 5 "medium"
    pqueue_push pq 10 "high"
    pqueue_push pq 1 "low"
    # First element should be highest priority
    [ "${pq[0]}" = "10:high" ]
}

@test "pqueue_pop returns highest priority element" {
    pqueue_create pq
    pqueue_push pq 5 "medium"
    pqueue_push pq 10 "high"
    pqueue_push pq 1 "low"
    local result
    pqueue_pop_v pq result
    [ "$result" = "high" ]
}

@test "pqueue_pop returns elements in priority order" {
    pqueue_create pq
    pqueue_push pq 1 "low"
    pqueue_push pq 10 "high"
    pqueue_push pq 5 "medium"
    local result
    pqueue_pop_v pq result
    [ "$result" = "high" ]
    pqueue_pop_v pq result
    [ "$result" = "medium" ]
    pqueue_pop_v pq result
    [ "$result" = "low" ]
}

@test "pqueue_pop_v stores value in variable" {
    pqueue_create pq
    pqueue_push pq 10 "task"
    local result
    pqueue_pop_v pq result
    [ "$result" = "task" ]
}

@test "pqueue_peek returns highest priority without removing" {
    pqueue_create pq
    pqueue_push pq 5 "medium"
    pqueue_push pq 10 "high"
    local result
    result=$(pqueue_peek pq)
    [ "$result" = "high" ]
    [ "${#pq[@]}" -eq 2 ]
}

@test "pqueue_peek_priority returns priority value" {
    pqueue_create pq
    pqueue_push pq 42 "task"
    local result
    result=$(pqueue_peek_priority pq)
    [ "$result" = "42" ]
}

@test "pqueue_size returns correct count" {
    pqueue_create pq
    [ "$(pqueue_size pq)" = "0" ]
    pqueue_push pq 1 "a"
    pqueue_push pq 2 "b"
    [ "$(pqueue_size pq)" = "2" ]
}

@test "pqueue_is_empty returns 0 for empty priority queue" {
    pqueue_create pq
    pqueue_is_empty pq
}

@test "pqueue_clear removes all elements" {
    pqueue_create pq
    pqueue_push pq 1 "a"
    pqueue_push pq 2 "b"
    pqueue_clear pq
    [ "${#pq[@]}" -eq 0 ]
}

@test "pqueue_update_priority changes element priority" {
    pqueue_create pq
    pqueue_push pq 5 "task-a"
    pqueue_push pq 10 "task-b"
    # Initially task-b is first
    [ "$(pqueue_peek pq)" = "task-b" ]
    # Update task-a to higher priority
    pqueue_update_priority pq "task-a" 20
    [ "$(pqueue_peek pq)" = "task-a" ]
}

@test "pqueue_update_priority fails for non-existent element" {
    pqueue_create pq
    pqueue_push pq 5 "existing"
    run pqueue_update_priority pq "nonexistent" 10
    [ "$status" -eq 1 ]
}

@test "pqueue handles negative priorities" {
    pqueue_create pq
    pqueue_push pq -5 "very-low"
    pqueue_push pq 0 "zero"
    pqueue_push pq 5 "positive"
    local result
    pqueue_pop_v pq result
    [ "$result" = "positive" ]
    pqueue_pop_v pq result
    [ "$result" = "zero" ]
    pqueue_pop_v pq result
    [ "$result" = "very-low" ]
}

@test "pqueue handles equal priorities (stable)" {
    pqueue_create pq
    pqueue_push pq 5 "first"
    pqueue_push pq 5 "second"
    pqueue_push pq 5 "third"
    # All should be retrievable
    [ "${#pq[@]}" -eq 3 ]
    pqueue_pop pq >/dev/null
    pqueue_pop pq >/dev/null
    pqueue_pop pq >/dev/null
    [ "${#pq[@]}" -eq 0 ]
}

# =============================================================================
# RING BUFFER TESTS
# =============================================================================

@test "ring_create initializes empty ring buffer" {
    ring_create r r_meta 5
    [ "${r_meta[0]}" = "5" ]  # capacity
    [ "${r_meta[2]}" = "0" ]  # count
}

@test "ring_create fails with invalid capacity" {
    run ring_create r r_meta 0
    [ "$status" -eq 1 ]
}

@test "ring_push adds elements" {
    ring_create r r_meta 5
    ring_push r r_meta "a"
    ring_push r r_meta "b"
    [ "$(ring_size r r_meta)" = "2" ]
}

@test "ring_push overwrites oldest when full" {
    ring_create r r_meta 3
    ring_push r r_meta "1"
    ring_push r r_meta "2"
    ring_push r r_meta "3"
    ring_push r r_meta "4"  # Should overwrite "1"
    [ "$(ring_size r r_meta)" = "3" ]
    [ "$(ring_peek r r_meta)" = "2" ]  # "1" was overwritten
}

@test "ring_pop removes oldest element" {
    ring_create r r_meta 5
    ring_push r r_meta "first"
    ring_push r r_meta "second"
    local result
    ring_pop_v r r_meta result
    [ "$result" = "first" ]
    [ "$(ring_size r r_meta)" = "1" ]
}

@test "ring_pop fails on empty buffer" {
    ring_create r r_meta 5
    run ring_pop r r_meta
    [ "$status" -eq 1 ]
}

@test "ring_pop_v stores value in variable" {
    ring_create r r_meta 5
    ring_push r r_meta "value"
    local result
    ring_pop_v r r_meta result
    [ "$result" = "value" ]
}

@test "ring_peek returns oldest without removing" {
    ring_create r r_meta 5
    ring_push r r_meta "oldest"
    ring_push r r_meta "newest"
    local result
    result=$(ring_peek r r_meta)
    [ "$result" = "oldest" ]
    [ "$(ring_size r r_meta)" = "2" ]
}

@test "ring_size returns current count" {
    ring_create r r_meta 5
    [ "$(ring_size r r_meta)" = "0" ]
    ring_push r r_meta "a"
    ring_push r r_meta "b"
    [ "$(ring_size r r_meta)" = "2" ]
}

@test "ring_capacity returns max capacity" {
    ring_create r r_meta 10
    [ "$(ring_capacity r r_meta)" = "10" ]
}

@test "ring_is_empty returns 0 for empty buffer" {
    ring_create r r_meta 5
    ring_is_empty r r_meta
}

@test "ring_is_empty returns 1 for non-empty buffer" {
    ring_create r r_meta 5
    ring_push r r_meta "item"
    run ring_is_empty r r_meta
    [ "$status" -eq 1 ]
}

@test "ring_is_full returns 0 when at capacity" {
    ring_create r r_meta 2
    ring_push r r_meta "a"
    ring_push r r_meta "b"
    ring_is_full r r_meta
}

@test "ring_is_full returns 1 when not at capacity" {
    ring_create r r_meta 5
    ring_push r r_meta "a"
    run ring_is_full r r_meta
    [ "$status" -eq 1 ]
}

@test "ring_clear empties buffer preserving capacity" {
    ring_create r r_meta 5
    ring_push r r_meta "a"
    ring_push r r_meta "b"
    ring_clear r r_meta
    [ "$(ring_size r r_meta)" = "0" ]
    [ "$(ring_capacity r r_meta)" = "5" ]
}

@test "ring_to_array copies elements in FIFO order" {
    ring_create r r_meta 5
    ring_push r r_meta "1"
    ring_push r r_meta "2"
    ring_push r r_meta "3"
    local result
    ring_to_array r r_meta result
    [ "${#result[@]}" -eq 3 ]
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "3" ]
}

@test "ring buffer handles wraparound correctly" {
    ring_create r r_meta 3
    ring_push r r_meta "1"
    ring_push r r_meta "2"
    ring_push r r_meta "3"
    ring_pop r r_meta >/dev/null  # Remove "1"
    ring_push r r_meta "4"  # Add at wrapped position
    local result
    ring_to_array r r_meta result
    [ "${result[0]}" = "2" ]
    [ "${result[1]}" = "3" ]
    [ "${result[2]}" = "4" ]
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "queue_drain empties queue into array" {
    queue_create q
    queue_push q "a"
    queue_push q "b"
    queue_push q "c"
    local result
    queue_drain q result
    [ "${#result[@]}" -eq 3 ]
    [ "${#q[@]}" -eq 0 ]
}

@test "queue_each calls callback for each element" {
    queue_create q
    queue_push q "a"
    queue_push q "b"
    queue_push q "c"
    local output
    output=$(queue_each q echo_item)
    [[ "$output" == *"item: a"* ]]
    [[ "$output" == *"item: b"* ]]
    [[ "$output" == *"item: c"* ]]
}

@test "queue_each fails with invalid callback" {
    queue_create q
    queue_push q "item"
    run queue_each q nonexistent_function
    [ "$status" -eq 1 ]
}

@test "queue_filter keeps matching elements" {
    queue_create q
    queue_push q "2"
    queue_push q "3"
    queue_push q "4"
    queue_push q "5"
    queue_filter q is_even
    [ "${#q[@]}" -eq 2 ]
    [ "${q[0]}" = "2" ]
    [ "${q[1]}" = "4" ]
}

@test "queue_filter with no matches empties queue" {
    queue_create q
    queue_push q "1"
    queue_push q "3"
    queue_push q "5"
    queue_filter q is_even
    [ "${#q[@]}" -eq 0 ]
}

@test "queue_to_json serializes queue" {
    queue_create q
    queue_push q "a"
    queue_push q "b"
    queue_push q "c"
    local result
    result=$(queue_to_json q)
    [ "$result" = '["a","b","c"]' ]
}

@test "queue_to_json with empty queue" {
    queue_create q
    local result
    result=$(queue_to_json q)
    [ "$result" = '[]' ]
}

@test "queue_to_json escapes special characters" {
    queue_create q
    queue_push q 'say "hello"'
    local result
    result=$(queue_to_json q)
    [[ "$result" == *'\"hello\"'* ]]
}

@test "queue_from_json parses JSON array" {
    queue_create q
    queue_from_json q '["one","two","three"]'
    [ "${#q[@]}" -eq 3 ]
    [ "${q[0]}" = "one" ]
    [ "${q[1]}" = "two" ]
    [ "${q[2]}" = "three" ]
}

@test "queue_from_json with empty array" {
    queue_create q
    queue_from_json q '[]'
    [ "${#q[@]}" -eq 0 ]
}

@test "pqueue_to_json serializes priority queue" {
    pqueue_create pq
    pqueue_push pq 10 "high"
    pqueue_push pq 5 "medium"
    local result
    result=$(pqueue_to_json pq)
    [[ "$result" == *'"priority":10'* ]]
    [[ "$result" == *'"value":"high"'* ]]
}

# =============================================================================
# CONTRACT AND ERROR HANDLING TESTS
# =============================================================================

@test "contracts can be disabled for performance" {
    QUEUE_CONTRACTS=0
    queue_create q
    # Should not fail even when popping from empty queue
    queue_pop q 2>/dev/null || true
    QUEUE_CONTRACTS=1
}

@test "operations on empty structures fail gracefully" {
    queue_create q
    run queue_pop q
    [ "$status" -eq 1 ]

    stack_create s
    run stack_pop s
    [ "$status" -eq 1 ]

    deque_create d
    run deque_pop_front d
    [ "$status" -eq 1 ]
}

@test "pqueue_push fails with non-integer priority" {
    pqueue_create pq
    run pqueue_push pq "not-a-number" "value"
    [ "$status" -eq 1 ]
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "queue handles empty strings" {
    queue_create q
    queue_push q ""
    queue_push q "non-empty"
    [ "${#q[@]}" -eq 2 ]
    local result
    queue_pop_v q result
    [ "$result" = "" ]
}

@test "stack handles empty strings" {
    stack_create s
    stack_push s ""
    stack_push s "non-empty"
    local result
    stack_pop_v s result
    [ "$result" = "non-empty" ]
    stack_pop_v s result
    [ "$result" = "" ]
}

@test "queue handles special characters" {
    queue_create q
    queue_push q $'line1\nline2'
    queue_push q $'tab\there'
    [ "${#q[@]}" -eq 2 ]
}

@test "deque_rotate on single element is no-op" {
    deque_create d
    deque_push_back d "only"
    deque_rotate_left d
    [ "${d[0]}" = "only" ]
}

@test "deque_rotate on empty deque is safe" {
    deque_create d
    deque_rotate_left d
    deque_rotate_right d
    [ "${#d[@]}" -eq 0 ]
}

@test "stack_reverse on empty stack is safe" {
    stack_create s
    stack_reverse s
    [ "${#s[@]}" -eq 0 ]
}

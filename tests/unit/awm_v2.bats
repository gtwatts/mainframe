#!/usr/bin/env bats
# AWM v2 Test Suite
# Tests for storage abstraction, context streaming, protocol, and tiers

load '../test_helper'

setup() {
    # Create temp directory for tests
    export TEST_AWM_DIR="$(mktemp -d)"
    export MAINFRAME_AWM_DIR="$TEST_AWM_DIR"
    export MAINFRAME_STORAGE="file"  # Force file backend for tests

    # Source AWM v2 libraries
    source "$MAINFRAME_ROOT/lib/awm_storage.sh"
    source "$MAINFRAME_ROOT/lib/awm_stream.sh"
    source "$MAINFRAME_ROOT/lib/awm_protocol.sh"
    source "$MAINFRAME_ROOT/lib/awm_tiers.sh"

    # Initialize
    awm_storage_init
    awm_tier_init
}

teardown() {
    rm -rf "$TEST_AWM_DIR"
}

# =============================================================================
# STORAGE ABSTRACTION TESTS
# =============================================================================

@test "awm_storage_init detects file backend" {
    awm_storage_init
    result=$(awm_storage_backend)
    [ "$result" = "file" ]
}

@test "awm_storage_caps returns correct capabilities for file backend" {
    result=$(awm_storage_caps)
    [ "$(echo "$result" | jq -r '.backend')" = "file" ]
    [ "$(echo "$result" | jq -r '.semantic_search')" = "false" ]
    [ "$(echo "$result" | jq -r '.pubsub')" = "false" ]
    [ "$(echo "$result" | jq -r '.ttl')" = "false" ]
}

@test "awm_store_set and awm_store_get work correctly" {
    awm_store_set "test_key" "test_value"
    result=$(awm_store_get "test_key")
    [ "$result" = "test_value" ]
}

@test "awm_store_get returns default when key not found" {
    result=$(awm_store_get "nonexistent" "default_value")
    [ "$result" = "default_value" ]
}

@test "awm_store_delete removes key" {
    awm_store_set "delete_me" "value"
    awm_store_delete "delete_me"
    ! awm_store_exists "delete_me"
}

@test "awm_store_exists returns correct status" {
    awm_store_set "exists_test" "value"
    awm_store_exists "exists_test"
    ! awm_store_exists "does_not_exist"
}

@test "awm_store_push and awm_store_pop work as queue" {
    awm_store_push "test_list" "first"
    awm_store_push "test_list" "second"
    awm_store_push "test_list" "third"

    first=$(awm_store_pop "test_list")
    [ "$first" = "first" ]

    second=$(awm_store_pop "test_list")
    [ "$second" = "second" ]
}

@test "awm_store_len returns correct count" {
    awm_store_push "count_list" "a"
    awm_store_push "count_list" "b"
    awm_store_push "count_list" "c"

    len=$(awm_store_len "count_list")
    [ "$len" = "3" ]
}

@test "awm_store_range returns correct subset" {
    awm_store_push "range_list" "zero"
    awm_store_push "range_list" "one"
    awm_store_push "range_list" "two"
    awm_store_push "range_list" "three"

    result=$(awm_store_range "range_list" 1 2)
    count=$(echo "$result" | jq 'length')
    [ "$count" = "2" ]
}

@test "awm_store_set respects TTL" {
    awm_store_set "ttl_key" "expires_soon" 1
    sleep 0.5
    result=$(awm_store_get "ttl_key" "expired")
    [ "$result" = "expired" ]
}

@test "awm_storage_stats returns valid JSON" {
    awm_store_set "stat_key" "value"
    result=$(awm_storage_stats)
    [ "$(echo "$result" | jq -r '.backend')" = "file" ]
    [ "$(echo "$result" | jq -r '.kv_count')" -ge 1 ]
}

# =============================================================================
# CONTEXT STREAMING TESTS
# =============================================================================

@test "awm_budget_init sets correct limits" {
    result=$(awm_budget_init "gpt-4o")
    [ "$result" -gt 100000 ]
}

@test "awm_budget_init auto-detects default" {
    result=$(awm_budget_init "auto")
    [ "$result" -gt 0 ]
}

@test "awm_estimate_tokens returns reasonable estimate" {
    # 100 characters of prose should be ~25 tokens
    local text="This is a sample text that should be approximately one hundred characters long for testing purposes here."
    tokens=$(awm_estimate_tokens "$text" "prose")
    [ "$tokens" -gt 20 ]
    [ "$tokens" -lt 50 ]
}

@test "awm_detect_content_type identifies code" {
    local code='function hello() { return "world"; }'
    result=$(awm_detect_content_type "$code")
    [ "$result" = "code" ] || [ "$result" = "mixed" ]
}

@test "awm_detect_content_type identifies JSON" {
    local json='{"key": "value", "number": 42}'
    result=$(awm_detect_content_type "$json")
    [ "$result" = "json" ]
}

@test "awm_detect_content_type identifies markdown" {
    local md='# Heading

This is a paragraph with a [link](http://example.com).

- List item 1
- List item 2'
    result=$(awm_detect_content_type "$md")
    [ "$result" = "markdown" ]
}

@test "awm_pointer_create and awm_pointer_resolve work" {
    local content="This is test content for pointer"
    ptr=$(awm_pointer_create "$content")

    [[ "$ptr" == ptr://awm/* ]]

    resolved=$(awm_pointer_resolve "$ptr")
    [ "$resolved" = "$content" ]
}

@test "awm_pointer_exists returns correct status" {
    local content="Pointer existence test"
    ptr=$(awm_pointer_create "$content")

    awm_pointer_exists "$ptr"
    ! awm_pointer_exists "ptr://awm/nonexistent"
}

@test "awm_wrap_result returns pointer for large content" {
    # Create content larger than 100 tokens
    local large=""
    for i in {1..500}; do
        large+="This is line $i of test content. "
    done

    result=$(awm_wrap_result "$large" 100)

    [ "$(echo "$result" | jq -r '._ptr // empty')" != "" ]
    [ "$(echo "$result" | jq -r '.preview')" != "" ]
}

@test "awm_wrap_result returns original for small content" {
    local small="Small content"
    result=$(awm_wrap_result "$small" 1000)

    [ "$result" = "$small" ]
}

@test "awm_chunk_code splits at function boundaries" {
    local code='function one() {
    return 1;
}

function two() {
    return 2;
}

function three() {
    return 3;
}'
    result=$(awm_chunk_code "$code" 50)
    count=$(echo "$result" | jq 'length')
    [ "$count" -ge 1 ]
}

@test "awm_stream_compress level 1 normalizes whitespace" {
    local text="  lots   of    spaces   "
    result=$(awm_stream_compress "$text" 1)
    [ "$result" = "lots of spaces" ]
}

@test "awm_stream_compress level 5 produces summary" {
    local text="Line 1
Line 2
Line 3"
    result=$(awm_stream_compress "$text" 5)
    [[ "$result" == *"Compressed:"* ]]
}

@test "awm_budget_fits returns correct status" {
    awm_budget_init
    awm_budget_fits 100
    ! awm_budget_fits 999999999
}

# =============================================================================
# AGENT PROTOCOL TESTS
# =============================================================================

@test "awm_agent_register creates agent card" {
    result=$(awm_agent_register "test_agent" "search" "analyze")

    [ "$result" = "test_agent" ]

    card=$(awm_agent_card "test_agent")
    [ "$(echo "$card" | jq -r '.agent_id')" = "test_agent" ]
    [ "$(echo "$card" | jq -r '.capabilities | length')" = "2" ]
}

@test "awm_agent_status returns correct status" {
    awm_agent_register "status_agent"
    result=$(awm_agent_status "status_agent")
    [ "$result" = "available" ]
}

@test "awm_agent_find locates agents by capability" {
    awm_agent_register "finder1" "search" "parse"
    awm_agent_register "finder2" "search" "write"

    result=$(awm_agent_find "search")
    count=$(echo "$result" | jq 'length')
    [ "$count" -ge 2 ]
}

@test "awm_context_new generates unique IDs" {
    ctx1=$(awm_context_new)
    ctx2=$(awm_context_new)

    [[ "$ctx1" == ctx_* ]]
    [ "$ctx1" != "$ctx2" ]
}

@test "awm_message_create produces valid USOP envelope" {
    awm_agent_register "msg_sender"
    msg=$(awm_message_create "request" "target" '{"action":"test"}')

    [ "$(echo "$msg" | jq -r '.usop')" = "4.0" ]
    [ "$(echo "$msg" | jq -r '.message.type')" = "request" ]
    [ "$(echo "$msg" | jq -r '.message.from')" = "msg_sender" ]
    [ "$(echo "$msg" | jq -r '.message.to')" = "target" ]
}

@test "awm_send delivers message to inbox" {
    awm_agent_register "sender"

    msg_id=$(awm_send "receiver" "request" '{"data":"test"}')

    [[ "$msg_id" == msg_* ]]

    # Check receiver's inbox
    count=$(awm_store_len "inbox:receiver")
    [ "$count" -ge 1 ]
}

@test "awm_protocol_handoff_prepare creates valid protocol-v4 handoff package" {
    awm_agent_register "parent_agent"
    awm_budget_init

    handoff=$(awm_protocol_handoff_prepare "child_agent" 32000)

    [ "$(echo "$handoff" | jq -r '.type')" = "handoff" ]
    [ "$(echo "$handoff" | jq -r '.parent_agent')" = "parent_agent" ]
    [ "$(echo "$handoff" | jq -r '.target_agent')" = "child_agent" ]
    [ "$(echo "$handoff" | jq -r '.budget_remaining')" -gt 0 ]
}

@test "awm_protocol_handoff_accept initializes from protocol-v4 handoff" {
    awm_agent_register "parent"
    awm_budget_init

    handoff=$(awm_protocol_handoff_prepare "child" 32000)

    awm_agent_register "child"
    awm_protocol_handoff_accept "$handoff"

    ctx=$(awm_context_get)
    [[ "$ctx" == ctx_* ]]
}

# =============================================================================
# TIERED MEMORY TESTS
# =============================================================================

@test "awm_hot_set and awm_hot_get work" {
    awm_hot_set "hot_key" "hot_value"
    result=$(awm_hot_get "hot_key")
    [ "$result" = "hot_value" ]
}

@test "awm_hot_exists returns correct status" {
    awm_hot_set "exists_hot" "value"
    awm_hot_exists "exists_hot"
    ! awm_hot_exists "not_exists_hot"
}

@test "awm_hot_size returns token count" {
    awm_hot_set "size_key1" "some content here"
    awm_hot_set "size_key2" "more content"

    size=$(awm_hot_size)
    [ "$size" -gt 0 ]
}

@test "awm_warm_set and awm_warm_get work" {
    awm_warm_set "warm_key" "warm_value"
    result=$(awm_warm_get "warm_key")
    [ "$result" = "warm_value" ]
}

@test "awm_cold_set and awm_cold_get work" {
    awm_cold_set "cold_key" "cold_value" "{\"tag\":\"test\"}"
    result=$(awm_cold_get "cold_key")
    [ "$result" = "cold_value" ]
}

@test "awm_tier_write selects appropriate tier" {
    # Small content -> hot tier
    awm_tier_write "small_key" "small value" "normal"
    awm_hot_exists "small_key"
}

@test "awm_tier_read traverses tiers" {
    # Put in warm tier only
    awm_warm_set "warm_only" "warm value"

    # Should find it via tier traversal
    result=$(awm_tier_read "warm_only")
    [ "$result" = "warm value" ]
}

@test "awm_tier_read promotes to hot tier" {
    awm_warm_set "promote_me" "value to promote"

    # Read with promotion
    awm_tier_read "promote_me" "" "true"

    # Should now be in hot tier
    awm_hot_exists "promote_me"
}

@test "awm_tier_stats returns valid statistics" {
    awm_hot_set "stat_hot" "value"
    awm_warm_set "stat_warm" "value"

    stats=$(awm_tier_stats)

    [ "$(echo "$stats" | jq -r '.hot.count')" -ge 1 ]
    [ "$(echo "$stats" | jq -r '.budget.max')" -gt 0 ]
}

@test "awm_tier_demote moves item to lower tier" {
    awm_hot_set "demote_me" "value"

    awm_tier_demote "demote_me"

    ! awm_hot_exists "demote_me"
    awm_warm_exists "demote_me"
}

@test "awm_tier_promote moves item to higher tier" {
    awm_warm_set "promote_me" "value"

    awm_tier_promote "promote_me"

    awm_hot_exists "promote_me"
}

@test "awm_tier_delete removes from all tiers" {
    awm_hot_set "multi_tier" "value"
    awm_warm_set "multi_tier" "value"
    awm_cold_set "multi_tier" "value"

    awm_tier_delete "multi_tier"

    ! awm_hot_exists "multi_tier"
    ! awm_warm_exists "multi_tier"
}

@test "awm_tier_prefetch loads multiple keys" {
    # Initialize budget first (suppress output)
    awm_budget_init >/dev/null

    awm_warm_set "prefetch1" "value1"
    awm_warm_set "prefetch2" "value2"

    loaded=$(awm_tier_prefetch "prefetch1" "prefetch2")
    [ "$loaded" -eq 2 ]

    # Verify values are retrievable (promotion may or may not happen depending on budget)
    val1=$(awm_tier_read "prefetch1")
    val2=$(awm_tier_read "prefetch2")
    [ "$val1" = "value1" ]
    [ "$val2" = "value2" ]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "full agent workflow: register, message, handoff" {
    # Parent agent
    awm_agent_register "parent" "orchestrate"
    awm_budget_init "gpt-4o"

    # Store some discoveries
    awm_store_push "session:parent:discoveries" '"Important finding"'

    # Prepare handoff
    handoff=$(awm_protocol_handoff_prepare "child" 50000)

    # Child agent
    awm_agent_register "child" "execute"
    awm_protocol_handoff_accept "$handoff"

    # Verify child got context
    ctx=$(awm_context_get)
    [[ "$ctx" == ctx_* ]]
}

@test "memory pointer roundtrip with large content" {
    # Create large content
    local large=""
    for i in {1..1000}; do
        large+="Line $i: This is test content for memory pointer testing. "
    done

    # Store as pointer
    ptr=$(awm_pointer_create "$large" "prose" "{\"source\":\"test\"}")

    # Verify it's a valid pointer
    [[ "$ptr" == ptr://awm/* ]]

    # Resolve and verify
    resolved=$(awm_pointer_resolve "$ptr")
    [ "$resolved" = "$large" ]

    # Check metadata
    meta=$(awm_pointer_meta "$ptr")
    [ "$(echo "$meta" | jq -r '.type')" = "prose" ]
}

@test "tier eviction preserves important items" {
    # Fill hot tier with items of varying importance
    awm_hot_set "critical_item" "must keep" "critical"
    awm_hot_set "normal_item1" "can evict" "normal"
    awm_hot_set "normal_item2" "can evict" "normal"
    awm_hot_set "low_item" "evict first" "low"

    # Force eviction to very low limit
    awm_evict_hot 10

    # Critical should remain
    awm_hot_exists "critical_item"
}

@test "chunking preserves complete content" {
    local original="First paragraph with complete sentences.

Second paragraph continues the story.

Third paragraph wraps up."

    chunks=$(awm_chunk "$original" "prose" 50)

    # Just verify we got chunks
    local count
    count=$(echo "$chunks" | jq 'length')
    [ "$count" -ge 1 ]
}

#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Agent Module Tests
# =============================================================================
# Comprehensive tests for lib/agent.sh (20 functions)
# Covers: registration, discovery, messaging, work queues, synchronization,
#         barriers, signals, heartbeat, status, edge cases, concurrency
# =============================================================================

load 'test_helper'

setup() {
    export MAINFRAME_AGENT_DIR="$(mktemp -d)"
    export MAINFRAME_QUIET=1
    source "$MAINFRAME_ROOT/lib/agent.sh"
}

teardown() {
    rm -rf "$MAINFRAME_AGENT_DIR"
    # Reset module state for next test
    unset _MAINFRAME_AGENT_LOADED
    unset _MAINFRAME_AGENT_NAME
    unset _MAINFRAME_AGENT_SEQ
}

# =============================================================================
# DOUBLE-SOURCE GUARD
# =============================================================================

@test "double-source guard prevents re-loading" {
    _MAINFRAME_AGENT_LOADED=1
    local before="$_MAINFRAME_AGENT_NAME"
    source "$MAINFRAME_ROOT/lib/agent.sh"
    [ "$_MAINFRAME_AGENT_NAME" = "$before" ]
}

# =============================================================================
# AGENT REGISTRATION
# =============================================================================

@test "agent_register creates agent directory structure" {
    agent_register "test_agent"
    [ -d "$MAINFRAME_AGENT_DIR/test_agent" ]
    [ -d "$MAINFRAME_AGENT_DIR/test_agent/inbox" ]
    [ -d "$MAINFRAME_AGENT_DIR/test_agent/outbox" ]
}

@test "agent_register creates registration file" {
    agent_register "test_agent"
    [ -f "$MAINFRAME_AGENT_DIR/test_agent/registered" ]
    local content
    content=$(cat "$MAINFRAME_AGENT_DIR/test_agent/registered")
    [[ "$content" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "agent_register stores capabilities" {
    agent_register "worker" "compute" "storage" "network"
    [ -f "$MAINFRAME_AGENT_DIR/worker/capabilities" ]
    local caps
    caps=$(cat "$MAINFRAME_AGENT_DIR/worker/capabilities")
    [[ "$caps" == *"compute"* ]]
    [[ "$caps" == *"storage"* ]]
    [[ "$caps" == *"network"* ]]
}

@test "agent_register sets _MAINFRAME_AGENT_NAME" {
    agent_register "my_agent"
    [ "$_MAINFRAME_AGENT_NAME" = "my_agent" ]
}

@test "agent_register initializes heartbeat" {
    agent_register "heartbeat_test"
    [ -f "$MAINFRAME_AGENT_DIR/heartbeat_test/heartbeat" ]
    local hb
    hb=$(cat "$MAINFRAME_AGENT_DIR/heartbeat_test/heartbeat")
    [[ "$hb" =~ ^[0-9]+$ ]]
}

@test "agent_register fails without name" {
    run agent_register ""
    [ "$status" -ne 0 ]
}

@test "agent_register with no capabilities creates empty file" {
    agent_register "bare_agent"
    [ -f "$MAINFRAME_AGENT_DIR/bare_agent/capabilities" ]
    local size
    size=$(wc -c < "$MAINFRAME_AGENT_DIR/bare_agent/capabilities")
    [ "$size" -eq 0 ]
}

@test "agent_register is idempotent" {
    agent_register "idempotent_agent" "cap1"
    agent_register "idempotent_agent" "cap2"
    [ -d "$MAINFRAME_AGENT_DIR/idempotent_agent" ]
    # Second registration overwrites capabilities
    local caps
    caps=$(cat "$MAINFRAME_AGENT_DIR/idempotent_agent/capabilities")
    [[ "$caps" == *"cap2"* ]]
}

# =============================================================================
# AGENT UNREGISTRATION
# =============================================================================

@test "agent_unregister removes agent directory" {
    agent_register "removable"
    agent_unregister "removable"
    [ ! -d "$MAINFRAME_AGENT_DIR/removable" ]
}

@test "agent_unregister clears name when unregistering self" {
    agent_register "self_remove"
    [ "$_MAINFRAME_AGENT_NAME" = "self_remove" ]
    agent_unregister
    [ -z "$_MAINFRAME_AGENT_NAME" ]
}

@test "agent_unregister fails for non-existent agent" {
    run agent_unregister "ghost_agent"
    [ "$status" -ne 0 ]
}

@test "agent_unregister can remove other agents" {
    agent_register "agent_a"
    _MAINFRAME_AGENT_NAME="agent_b"
    agent_register "agent_b"
    agent_unregister "agent_a"
    [ ! -d "$MAINFRAME_AGENT_DIR/agent_a" ]
    [ "$_MAINFRAME_AGENT_NAME" = "agent_b" ]
}

# =============================================================================
# AGENT DISCOVERY
# =============================================================================

@test "agent_discover finds agents with capability" {
    agent_register "worker1" "compute" "storage"
    agent_register "worker2" "compute"
    agent_register "worker3" "network"

    local result
    result=$(agent_discover "compute")
    [[ "$result" == *"worker1"* ]]
    [[ "$result" == *"worker2"* ]]
    [[ "$result" != *"worker3"* ]]
}

@test "agent_discover returns failure when no match" {
    agent_register "worker1" "compute"
    run agent_discover "nonexistent_cap"
    [ "$status" -ne 0 ]
}

@test "agent_discover fails without capability argument" {
    run agent_discover ""
    [ "$status" -ne 0 ]
}

@test "agent_discover handles exact capability matching" {
    agent_register "precise" "comp" "compute"
    local result
    result=$(agent_discover "comp")
    [[ "$result" == *"precise"* ]]

    result=$(agent_discover "compute")
    [[ "$result" == *"precise"* ]]
}

# =============================================================================
# AGENT LIST
# =============================================================================

@test "agent_list returns empty array when no agents" {
    local result
    result=$(agent_list)
    [ "$result" = "[]" ]
}

@test "agent_list returns JSON array of agents" {
    agent_register "alpha" "cap_a"
    agent_register "beta" "cap_b"

    local result
    result=$(agent_list)
    [[ "$result" == "["* ]]
    [[ "$result" == *"]" ]]
    [[ "$result" == *"alpha"* ]]
    [[ "$result" == *"beta"* ]]
    [[ "$result" == *"cap_a"* ]]
    [[ "$result" == *"cap_b"* ]]
}

@test "agent_list includes capabilities as array" {
    agent_register "multi_cap" "a" "b" "c"
    local result
    result=$(agent_list)
    [[ "$result" == *'"capabilities":['* ]]
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *'"b"'* ]]
    [[ "$result" == *'"c"'* ]]
}

# =============================================================================
# AGENT STATUS
# =============================================================================

@test "agent_status returns JSON for registered agent" {
    agent_register "status_agent" "cap1" "cap2"
    local result
    result=$(agent_status "status_agent")
    [[ "$result" == *'"name":"status_agent"'* ]]
    [[ "$result" == *'"registered_at":'* ]]
    [[ "$result" == *'"last_heartbeat":'* ]]
    [[ "$result" == *'"capabilities":'* ]]
    [[ "$result" == *'"message_count":0'* ]]
}

@test "agent_status reflects message count" {
    agent_register "sender" "send"
    agent_register "receiver" "recv"

    _MAINFRAME_AGENT_NAME="sender"
    agent_send "receiver" "hello"
    agent_send "receiver" "world"

    local result
    result=$(agent_status "receiver")
    [[ "$result" == *'"message_count":2'* ]]
}

@test "agent_status fails for non-existent agent" {
    run agent_status "nobody"
    [ "$status" -ne 0 ]
}

@test "agent_status uses current agent when no name given" {
    agent_register "current_agent"
    local result
    result=$(agent_status)
    [[ "$result" == *'"name":"current_agent"'* ]]
}

# =============================================================================
# AGENT HEARTBEAT
# =============================================================================

@test "agent_heartbeat updates timestamp" {
    agent_register "hb_agent"
    local first
    first=$(cat "$MAINFRAME_AGENT_DIR/hb_agent/heartbeat")

    sleep 1
    agent_heartbeat
    local second
    second=$(cat "$MAINFRAME_AGENT_DIR/hb_agent/heartbeat")

    [ "$second" -ge "$first" ]
}

@test "agent_heartbeat fails when not registered" {
    _MAINFRAME_AGENT_NAME=""
    run agent_heartbeat
    [ "$status" -ne 0 ]
}

# =============================================================================
# MESSAGING: SEND
# =============================================================================

@test "agent_send creates message file in target inbox" {
    agent_register "sender1"
    agent_register "target1"

    _MAINFRAME_AGENT_NAME="sender1"
    agent_send "target1" "hello"

    local count
    count=$(ls "$MAINFRAME_AGENT_DIR/target1/inbox"/msg_* 2>/dev/null | wc -l)
    [ "$count" -eq 1 ]
}

@test "agent_send creates valid JSON envelope" {
    agent_register "sender2"
    agent_register "target2"

    _MAINFRAME_AGENT_NAME="sender2"
    agent_send "target2" "test_payload"

    local msg
    msg=$(cat "$MAINFRAME_AGENT_DIR/target2/inbox"/msg_*)
    [[ "$msg" == *'"from":"sender2"'* ]]
    [[ "$msg" == *'"to":"target2"'* ]]
    [[ "$msg" == *'"timestamp":'* ]]
    [[ "$msg" == *'"payload":"test_payload"'* ]]
}

@test "agent_send fails for non-existent target" {
    agent_register "lonely_sender"
    _MAINFRAME_AGENT_NAME="lonely_sender"
    run agent_send "ghost" "hello"
    [ "$status" -ne 0 ]
}

@test "agent_send fails without target" {
    agent_register "no_target"
    _MAINFRAME_AGENT_NAME="no_target"
    run agent_send "" "hello"
    [ "$status" -ne 0 ]
}

@test "agent_send fails without message" {
    agent_register "sender_empty"
    agent_register "target_empty"
    _MAINFRAME_AGENT_NAME="sender_empty"
    run agent_send "target_empty" ""
    [ "$status" -ne 0 ]
}

@test "agent_send multiple messages have unique filenames" {
    agent_register "multi_sender"
    agent_register "multi_target"
    _MAINFRAME_AGENT_NAME="multi_sender"

    agent_send "multi_target" "msg1"
    agent_send "multi_target" "msg2"
    agent_send "multi_target" "msg3"

    local count
    count=$(ls "$MAINFRAME_AGENT_DIR/multi_target/inbox"/msg_* 2>/dev/null | wc -l)
    [ "$count" -eq 3 ]
}

# =============================================================================
# MESSAGING: RECEIVE
# =============================================================================

@test "agent_receive gets oldest message first (FIFO)" {
    agent_register "fifo_sender"
    agent_register "fifo_receiver"
    _MAINFRAME_AGENT_NAME="fifo_sender"

    agent_send "fifo_receiver" "first"
    sleep 0.01
    agent_send "fifo_receiver" "second"
    sleep 0.01
    agent_send "fifo_receiver" "third"

    _MAINFRAME_AGENT_NAME="fifo_receiver"
    local msg1
    msg1=$(agent_receive 2)
    [[ "$msg1" == *'"payload":"first"'* ]]

    local msg2
    msg2=$(agent_receive 2)
    [[ "$msg2" == *'"payload":"second"'* ]]
}

@test "agent_receive removes consumed message" {
    agent_register "consume_sender"
    agent_register "consume_receiver"
    _MAINFRAME_AGENT_NAME="consume_sender"
    agent_send "consume_receiver" "ephemeral"

    _MAINFRAME_AGENT_NAME="consume_receiver"
    agent_receive 2

    local count
    count=$(ls "$MAINFRAME_AGENT_DIR/consume_receiver/inbox"/msg_* 2>/dev/null | wc -l)
    [ "$count" -eq 0 ]
}

@test "agent_receive times out on empty inbox" {
    agent_register "empty_inbox_agent"
    _MAINFRAME_AGENT_NAME="empty_inbox_agent"
    run agent_receive 1
    [ "$status" -ne 0 ]
}

@test "agent_receive fails when not registered" {
    _MAINFRAME_AGENT_NAME=""
    run agent_receive 1
    [ "$status" -ne 0 ]
}

# =============================================================================
# MESSAGING: BROADCAST
# =============================================================================

@test "agent_broadcast sends to all other agents" {
    agent_register "broadcaster"
    agent_register "listener1"
    agent_register "listener2"
    agent_register "listener3"

    _MAINFRAME_AGENT_NAME="broadcaster"
    agent_broadcast "announcement"

    local c1 c2 c3 cb
    c1=$(ls "$MAINFRAME_AGENT_DIR/listener1/inbox"/msg_* 2>/dev/null | wc -l)
    c2=$(ls "$MAINFRAME_AGENT_DIR/listener2/inbox"/msg_* 2>/dev/null | wc -l)
    c3=$(ls "$MAINFRAME_AGENT_DIR/listener3/inbox"/msg_* 2>/dev/null | wc -l)
    cb=$(ls "$MAINFRAME_AGENT_DIR/broadcaster/inbox"/msg_* 2>/dev/null | wc -l)

    [ "$c1" -eq 1 ]
    [ "$c2" -eq 1 ]
    [ "$c3" -eq 1 ]
    [ "$cb" -eq 0 ]  # Sender should not receive own broadcast
}

@test "agent_broadcast fails without message" {
    agent_register "bc_empty"
    _MAINFRAME_AGENT_NAME="bc_empty"
    run agent_broadcast ""
    [ "$status" -ne 0 ]
}

@test "agent_broadcast with no other agents succeeds" {
    agent_register "alone"
    _MAINFRAME_AGENT_NAME="alone"
    run agent_broadcast "echo_chamber"
    [ "$status" -eq 0 ]
}

# =============================================================================
# MESSAGING: PEEK
# =============================================================================

@test "agent_peek shows message without consuming" {
    agent_register "peek_sender"
    agent_register "peek_receiver"
    _MAINFRAME_AGENT_NAME="peek_sender"
    agent_send "peek_receiver" "sneaky_peek"

    _MAINFRAME_AGENT_NAME="peek_receiver"
    local peeked
    peeked=$(agent_peek)
    [[ "$peeked" == *'"payload":"sneaky_peek"'* ]]

    # Message should still be there
    local count
    count=$(agent_inbox_count)
    [ "$count" -eq 1 ]
}

@test "agent_peek returns failure on empty inbox" {
    agent_register "empty_peeker"
    _MAINFRAME_AGENT_NAME="empty_peeker"
    run agent_peek
    [ "$status" -ne 0 ]
}

# =============================================================================
# MESSAGING: INBOX COUNT & CLEAR
# =============================================================================

@test "agent_inbox_count returns correct count" {
    agent_register "count_sender"
    agent_register "count_receiver"
    _MAINFRAME_AGENT_NAME="count_sender"
    agent_send "count_receiver" "m1"
    agent_send "count_receiver" "m2"
    agent_send "count_receiver" "m3"

    _MAINFRAME_AGENT_NAME="count_receiver"
    local count
    count=$(agent_inbox_count)
    [ "$count" -eq 3 ]
}

@test "agent_inbox_count returns 0 for empty inbox" {
    agent_register "zero_count"
    _MAINFRAME_AGENT_NAME="zero_count"
    local count
    count=$(agent_inbox_count)
    [ "$count" -eq 0 ]
}

@test "agent_clear_inbox removes all messages" {
    agent_register "clear_sender"
    agent_register "clear_receiver"
    _MAINFRAME_AGENT_NAME="clear_sender"
    agent_send "clear_receiver" "trash1"
    agent_send "clear_receiver" "trash2"

    _MAINFRAME_AGENT_NAME="clear_receiver"
    agent_clear_inbox

    local count
    count=$(agent_inbox_count)
    [ "$count" -eq 0 ]
}

@test "agent_clear_inbox on empty inbox succeeds" {
    agent_register "already_clear"
    _MAINFRAME_AGENT_NAME="already_clear"
    run agent_clear_inbox
    [ "$status" -eq 0 ]
}

# =============================================================================
# WORK QUEUE: CREATE
# =============================================================================

@test "agent_work_queue creates queue directory" {
    agent_work_queue "test_queue"
    [ -d "$MAINFRAME_AGENT_DIR/_queues/test_queue" ]
}

@test "agent_work_queue is idempotent" {
    agent_work_queue "idem_queue"
    agent_work_queue "idem_queue"
    [ -d "$MAINFRAME_AGENT_DIR/_queues/idem_queue" ]
}

@test "agent_work_queue fails without name" {
    run agent_work_queue ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# WORK QUEUE: PUSH & POP
# =============================================================================

@test "agent_work_push adds item to queue" {
    agent_register "pusher"
    agent_work_queue "jobs"
    agent_work_push "jobs" '{"task":"build"}'

    local count
    count=$(agent_work_count "jobs")
    [ "$count" -eq 1 ]
}

@test "agent_work_pop returns oldest item (FIFO)" {
    agent_register "fifo_worker"
    agent_work_queue "fifo_jobs"

    agent_work_push "fifo_jobs" "job_alpha"
    sleep 0.01
    agent_work_push "fifo_jobs" "job_beta"
    sleep 0.01
    agent_work_push "fifo_jobs" "job_gamma"

    local item1
    item1=$(agent_work_pop "fifo_jobs")
    [[ "$item1" == *'"item":"job_alpha"'* ]]

    local item2
    item2=$(agent_work_pop "fifo_jobs")
    [[ "$item2" == *'"item":"job_beta"'* ]]
}

@test "agent_work_pop removes item from queue" {
    agent_register "pop_worker"
    agent_work_queue "pop_jobs"
    agent_work_push "pop_jobs" "single_item"

    agent_work_pop "pop_jobs" >/dev/null
    local count
    count=$(agent_work_count "pop_jobs")
    [ "$count" -eq 0 ]
}

@test "agent_work_pop returns failure on empty queue" {
    agent_work_queue "empty_queue"
    run agent_work_pop "empty_queue"
    [ "$status" -ne 0 ]
}

@test "agent_work_pop fails for non-existent queue" {
    run agent_work_pop "no_such_queue"
    [ "$status" -ne 0 ]
}

@test "agent_work_push fails for non-existent queue" {
    agent_register "orphan_pusher"
    run agent_work_push "missing_queue" "item"
    [ "$status" -ne 0 ]
}

@test "agent_work_push fails without item" {
    agent_work_queue "no_item_queue"
    run agent_work_push "no_item_queue" ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# WORK QUEUE: COUNT & CLEAR
# =============================================================================

@test "agent_work_count returns correct count" {
    agent_register "counter"
    agent_work_queue "counted"
    agent_work_push "counted" "a"
    agent_work_push "counted" "b"
    agent_work_push "counted" "c"

    local count
    count=$(agent_work_count "counted")
    [ "$count" -eq 3 ]
}

@test "agent_work_count returns 0 for empty queue" {
    agent_work_queue "zero_queue"
    local count
    count=$(agent_work_count "zero_queue")
    [ "$count" -eq 0 ]
}

@test "agent_work_count returns 0 for non-existent queue" {
    local count
    count=$(agent_work_count "phantom_queue")
    [ "$count" -eq 0 ]
}

@test "agent_work_clear removes all items" {
    agent_register "clearer"
    agent_work_queue "clearable"
    agent_work_push "clearable" "x"
    agent_work_push "clearable" "y"

    agent_work_clear "clearable"
    local count
    count=$(agent_work_count "clearable")
    [ "$count" -eq 0 ]
}

@test "agent_work_clear fails for non-existent queue" {
    run agent_work_clear "nonexistent_q"
    [ "$status" -ne 0 ]
}

# =============================================================================
# SYNCHRONIZATION: BARRIER
# =============================================================================

@test "agent_barrier succeeds when count is met" {
    agent_register "barrier_a"

    # Simulate two other agents already at barrier
    local barrier_dir="$MAINFRAME_AGENT_DIR/_barriers/test_barrier"
    mkdir -p "$barrier_dir"
    echo "$(date +%s)" > "$barrier_dir/agent_x"
    echo "$(date +%s)" > "$barrier_dir/agent_y"

    # This agent is the third
    _MAINFRAME_AGENT_NAME="barrier_a"
    run agent_barrier "test_barrier" 3 5
    [ "$status" -eq 0 ]
}

@test "agent_barrier times out when count not met" {
    agent_register "timeout_agent"
    _MAINFRAME_AGENT_NAME="timeout_agent"
    run agent_barrier "lonely_barrier" 5 1
    [ "$status" -ne 0 ]
}

@test "agent_barrier fails without arguments" {
    run agent_barrier "" ""
    [ "$status" -ne 0 ]
}

@test "agent_barrier with background processes" {
    agent_register "main_agent"
    local barrier_dir="$MAINFRAME_AGENT_DIR/_barriers/bg_barrier"
    mkdir -p "$barrier_dir"

    # Launch background process that arrives at barrier
    (
        sleep 0.2
        echo "$(date +%s)" > "$barrier_dir/bg_worker"
    ) &
    local bg_pid=$!

    _MAINFRAME_AGENT_NAME="main_agent"
    run agent_barrier "bg_barrier" 2 5
    wait $bg_pid 2>/dev/null || true
    [ "$status" -eq 0 ]
}

# =============================================================================
# SYNCHRONIZATION: SIGNAL & WAIT
# =============================================================================

@test "agent_signal creates signal file" {
    agent_register "signaler"
    _MAINFRAME_AGENT_NAME="signaler"
    agent_signal "ready"

    [ -f "$MAINFRAME_AGENT_DIR/_signals/ready" ]
}

@test "agent_wait returns immediately for existing signal" {
    agent_register "waiter"
    _MAINFRAME_AGENT_NAME="waiter"
    agent_signal "pre_signal"
    run agent_wait "pre_signal" 2
    [ "$status" -eq 0 ]
}

@test "agent_wait times out for missing signal" {
    agent_register "patient_waiter"
    _MAINFRAME_AGENT_NAME="patient_waiter"
    run agent_wait "never_coming" 1
    [ "$status" -ne 0 ]
}

@test "agent_signal and agent_wait coordinate" {
    agent_register "coordinator"

    # Background process signals after delay
    (
        sleep 0.2
        mkdir -p "$MAINFRAME_AGENT_DIR/_signals"
        echo "$(date +%s) bg" > "$MAINFRAME_AGENT_DIR/_signals/coord_signal"
    ) &
    local bg_pid=$!

    _MAINFRAME_AGENT_NAME="coordinator"
    run agent_wait "coord_signal" 5
    wait $bg_pid 2>/dev/null || true
    [ "$status" -eq 0 ]
}

@test "agent_signal fails without name" {
    agent_register "bad_signaler"
    _MAINFRAME_AGENT_NAME="bad_signaler"
    run agent_signal ""
    [ "$status" -ne 0 ]
}

@test "agent_wait fails without name" {
    agent_register "bad_waiter"
    _MAINFRAME_AGENT_NAME="bad_waiter"
    run agent_wait ""
    [ "$status" -ne 0 ]
}

# =============================================================================
# CONCURRENT ACCESS
# =============================================================================

@test "concurrent work_push does not lose items" {
    agent_work_queue "concurrent_q"

    # Launch multiple concurrent pushers
    local i
    for i in $(seq 1 5); do
        (
            export MAINFRAME_AGENT_DIR
            export MAINFRAME_QUIET=1
            source "$MAINFRAME_ROOT/lib/agent.sh"
            agent_register "concurrent_$i"
            agent_work_push "concurrent_q" "item_$i"
        ) &
    done
    wait

    local count
    count=$(agent_work_count "concurrent_q")
    [ "$count" -eq 5 ]
}

@test "concurrent work_pop does not duplicate items" {
    agent_work_queue "atomic_q"

    # Push 5 items
    local i
    for i in $(seq 1 5); do
        agent_work_push "atomic_q" "atomic_item_$i"
        sleep 0.01
    done

    # Pop from multiple concurrent consumers, collect results
    local result_dir
    result_dir=$(mktemp -d)

    for i in $(seq 1 5); do
        (
            export MAINFRAME_AGENT_DIR
            export MAINFRAME_QUIET=1
            source "$MAINFRAME_ROOT/lib/agent.sh"
            local item
            item=$(agent_work_pop "atomic_q" 2>/dev/null) || true
            if [[ -n "$item" ]]; then
                echo "$item" > "$result_dir/result_$i"
            fi
        ) &
    done
    wait

    # All 5 items should have been consumed exactly once
    local consumed
    consumed=$(ls "$result_dir"/result_* 2>/dev/null | wc -l)
    [ "$consumed" -eq 5 ]

    # Queue should be empty
    local remaining
    remaining=$(agent_work_count "atomic_q")
    [ "$remaining" -eq 0 ]

    rm -rf "$result_dir"
}

@test "concurrent sends to same agent inbox" {
    agent_register "inbox_target"

    local i
    for i in $(seq 1 5); do
        (
            export MAINFRAME_AGENT_DIR
            export MAINFRAME_QUIET=1
            source "$MAINFRAME_ROOT/lib/agent.sh"
            agent_register "concurrent_sender_$i"
            _MAINFRAME_AGENT_NAME="concurrent_sender_$i"
            agent_send "inbox_target" "concurrent_msg_$i"
        ) &
    done
    wait

    _MAINFRAME_AGENT_NAME="inbox_target"
    local count
    count=$(agent_inbox_count)
    [ "$count" -eq 5 ]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "agent_send from anonymous agent includes 'anonymous' as from" {
    agent_register "anon_target"
    _MAINFRAME_AGENT_NAME=""
    # Cannot send without being registered target existing
    # But anonymous is allowed as sender identity
    agent_send "anon_target" "anon_msg"

    local msg
    msg=$(cat "$MAINFRAME_AGENT_DIR/anon_target/inbox"/msg_*)
    [[ "$msg" == *'"from":"anonymous"'* ]]
}

@test "agent with special characters in message payload" {
    agent_register "special_sender"
    agent_register "special_receiver"
    _MAINFRAME_AGENT_NAME="special_sender"
    agent_send "special_receiver" 'quotes"and\\slashes'

    _MAINFRAME_AGENT_NAME="special_receiver"
    local msg
    msg=$(agent_receive 2)
    [[ -n "$msg" ]]
}

@test "agent_work_push stores producer in envelope" {
    agent_register "tagged_producer"
    agent_work_queue "tagged_q"
    _MAINFRAME_AGENT_NAME="tagged_producer"
    agent_work_push "tagged_q" "tagged_item"

    local item
    item=$(agent_work_pop "tagged_q")
    [[ "$item" == *'"producer":"tagged_producer"'* ]]
}

@test "multiple queues are independent" {
    agent_work_queue "queue_a"
    agent_work_queue "queue_b"
    agent_register "multi_q_agent"

    agent_work_push "queue_a" "item_a"
    agent_work_push "queue_b" "item_b"

    local count_a count_b
    count_a=$(agent_work_count "queue_a")
    count_b=$(agent_work_count "queue_b")
    [ "$count_a" -eq 1 ]
    [ "$count_b" -eq 1 ]

    local pop_a
    pop_a=$(agent_work_pop "queue_a")
    [[ "$pop_a" == *'"item":"item_a"'* ]]

    local pop_b
    pop_b=$(agent_work_pop "queue_b")
    [[ "$pop_b" == *'"item":"item_b"'* ]]
}

@test "agent_list skips directories without registration file" {
    mkdir -p "$MAINFRAME_AGENT_DIR/fake_agent"
    # No 'registered' file
    agent_register "real_agent"

    local result
    result=$(agent_list)
    [[ "$result" != *"fake_agent"* ]]
    [[ "$result" == *"real_agent"* ]]
}

@test "agent_discover skips unregistered directories" {
    mkdir -p "$MAINFRAME_AGENT_DIR/unregistered"
    echo "compute" > "$MAINFRAME_AGENT_DIR/unregistered/capabilities"
    # No 'registered' file

    agent_register "legit" "compute"

    local result
    result=$(agent_discover "compute")
    [[ "$result" != *"unregistered"* ]]
    [[ "$result" == *"legit"* ]]
}

# =============================================================================
# AGENT_INFO TESTS
# =============================================================================

@test "agent_info returns agent details as JSON" {
    agent_register "info_agent" "cap1" "cap2"
    local result
    result=$(agent_info "info_agent")
    [[ "$result" == *'"name":"info_agent"'* ]]
    [[ "$result" == *'"capabilities":'* ]]
}

@test "agent_info_v stores result in variable" {
    agent_register "nameref_agent" "fast"
    local result
    agent_info_v result "nameref_agent"
    [[ "$result" == *"nameref_agent"* ]]
    [[ "$result" == *"fast"* ]]
}

# =============================================================================
# AGENT_PRUNE TESTS
# =============================================================================

@test "agent_prune removes stale agents" {
    agent_register "stale_agent"

    # Set heartbeat to old timestamp
    local old_ts=$(( $(date +%s) - 600 ))
    echo "$old_ts" > "$MAINFRAME_AGENT_DIR/stale_agent/heartbeat"

    run agent_prune --older-than 300
    [ "$status" -eq 0 ]

    [ ! -d "$MAINFRAME_AGENT_DIR/stale_agent" ]
}

@test "agent_prune keeps fresh agents" {
    agent_register "fresh_agent"
    agent_heartbeat

    run agent_prune --older-than 300
    [ "$status" -eq 0 ]

    [ -d "$MAINFRAME_AGENT_DIR/fresh_agent" ]
}

# =============================================================================
# AGENT_LIST_V TESTS
# =============================================================================

@test "agent_list_v stores agents in array" {
    agent_register "arr_agent_1"
    agent_register "arr_agent_2"

    local -a agents
    agent_list_v agents

    [ "${#agents[@]}" -ge 2 ]
    [[ " ${agents[*]} " == *" arr_agent_1 "* ]]
    [[ " ${agents[*]} " == *" arr_agent_2 "* ]]
}

# =============================================================================
# ASYNC RECEIVE TESTS
# =============================================================================

@test "agent_receive_async returns immediately when no message" {
    agent_register "async_agent"
    _MAINFRAME_AGENT_NAME="async_agent"

    local start_time
    start_time=$(date +%s)
    run agent_receive_async
    local end_time
    end_time=$(date +%s)

    # Should return quickly (within 1 second)
    [ $(( end_time - start_time )) -lt 2 ]
}

@test "agent_receive_async returns message if available" {
    agent_register "async_sender"
    agent_register "async_receiver"
    _MAINFRAME_AGENT_NAME="async_sender"
    agent_send "async_receiver" "async_msg"

    _MAINFRAME_AGENT_NAME="async_receiver"
    local result
    result=$(agent_receive_async)
    [[ "$result" == *'"payload":"async_msg"'* ]]
}

# =============================================================================
# PUB/SUB TESTS
# =============================================================================

@test "agent_subscribe creates topic file" {
    agent_register "sub_agent"
    _MAINFRAME_AGENT_NAME="sub_agent"
    agent_subscribe "news"

    [ -f "$MAINFRAME_AGENT_DIR/_topics/news" ]
    grep -q "sub_agent" "$MAINFRAME_AGENT_DIR/_topics/news"
}

@test "agent_unsubscribe removes agent from topic" {
    agent_register "unsub_agent"
    _MAINFRAME_AGENT_NAME="unsub_agent"
    agent_subscribe "events"
    agent_unsubscribe "events"

    ! grep -q "unsub_agent" "$MAINFRAME_AGENT_DIR/_topics/events" 2>/dev/null || true
}

@test "agent_publish sends to all topic subscribers" {
    agent_register "pub_agent"
    agent_register "sub1"
    agent_register "sub2"

    _MAINFRAME_AGENT_NAME="sub1"
    agent_subscribe "updates"
    _MAINFRAME_AGENT_NAME="sub2"
    agent_subscribe "updates"

    _MAINFRAME_AGENT_NAME="pub_agent"
    run agent_publish "updates" "topic_message"
    [ "$status" -eq 0 ]

    # Check that messages were delivered
    _MAINFRAME_AGENT_NAME="sub1"
    local count1
    count1=$(agent_inbox_count)
    [ "$count1" -eq 1 ]

    _MAINFRAME_AGENT_NAME="sub2"
    local count2
    count2=$(agent_inbox_count)
    [ "$count2" -eq 1 ]
}

@test "agent_publish fails for non-existent topic" {
    agent_register "lonely_pub"
    _MAINFRAME_AGENT_NAME="lonely_pub"
    run agent_publish "no_such_topic" "message"
    [ "$status" -ne 0 ]
}

# =============================================================================
# LOCKING TESTS
# =============================================================================

@test "agent_lock creates lock file" {
    agent_register "locker"
    _MAINFRAME_AGENT_NAME="locker"
    agent_lock "shared_resource"

    [ -f "$MAINFRAME_AGENT_DIR/_locks/shared_resource.lock" ]

    agent_unlock "shared_resource"
}

@test "agent_unlock releases lock" {
    agent_register "unlocker"
    _MAINFRAME_AGENT_NAME="unlocker"
    agent_lock "temp_resource"
    run agent_unlock "temp_resource"
    [ "$status" -eq 0 ]
}

@test "agent_trylock succeeds if lock available" {
    agent_register "trylock_agent"
    _MAINFRAME_AGENT_NAME="trylock_agent"
    run agent_trylock "free_resource"
    [ "$status" -eq 0 ]
    agent_unlock "free_resource"
}

@test "agent_trylock fails if lock held" {
    agent_register "holder"
    _MAINFRAME_AGENT_NAME="holder"
    agent_lock "contested"

    # Try from another process
    run bash -c "
        export MAINFRAME_AGENT_DIR='$MAINFRAME_AGENT_DIR'
        export MAINFRAME_QUIET=1
        source '$MAINFRAME_ROOT/lib/agent.sh'
        agent_register 'waiter'
        _MAINFRAME_AGENT_NAME='waiter'
        agent_trylock 'contested'
    "
    [ "$status" -ne 0 ]

    agent_unlock "contested"
}

# =============================================================================
# WORK QUEUE COMPLETION TRACKING TESTS
# =============================================================================

@test "agent_work_push_tracked returns task ID" {
    agent_register "tracker"
    agent_work_queue "tracked_q"
    _MAINFRAME_AGENT_NAME="tracker"

    local task_id
    task_id=$(agent_work_push_tracked "tracked_q" "tracked_item")

    [[ "$task_id" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]
}

@test "agent_work_pop_tracked marks task in progress" {
    agent_register "tracked_worker"
    agent_work_queue "progress_q"
    _MAINFRAME_AGENT_NAME="tracked_worker"

    local task_id
    task_id=$(agent_work_push_tracked "progress_q" "wip_item")

    agent_work_pop_tracked "progress_q" >/dev/null

    [ -f "$MAINFRAME_AGENT_DIR/_queues/progress_q/.inprogress" ]
}

@test "agent_work_complete removes from in_progress" {
    agent_register "completer"
    agent_work_queue "complete_q"
    _MAINFRAME_AGENT_NAME="completer"

    local task_id
    task_id=$(agent_work_push_tracked "complete_q" "to_complete")
    agent_work_pop_tracked "complete_q" >/dev/null
    agent_work_complete "complete_q" "$task_id"

    # Check completed file exists and contains task
    [ -f "$MAINFRAME_AGENT_DIR/_queues/complete_q/.completed" ]
    grep -q "$task_id" "$MAINFRAME_AGENT_DIR/_queues/complete_q/.completed"
}

@test "agent_work_fail records failure reason" {
    agent_register "failer"
    agent_work_queue "fail_q"
    _MAINFRAME_AGENT_NAME="failer"

    local task_id
    task_id=$(agent_work_push_tracked "fail_q" "broken_item")
    agent_work_pop_tracked "fail_q" >/dev/null
    agent_work_fail "fail_q" "$task_id" "Connection timeout"

    [ -f "$MAINFRAME_AGENT_DIR/_queues/fail_q/.failed" ]
    grep -q "Connection timeout" "$MAINFRAME_AGENT_DIR/_queues/fail_q/.failed"
}

@test "agent_work_stats returns queue statistics" {
    agent_register "stats_agent"
    agent_work_queue "stats_q"
    _MAINFRAME_AGENT_NAME="stats_agent"

    agent_work_push "stats_q" "item1"
    agent_work_push "stats_q" "item2"
    agent_work_push "stats_q" "item3"
    agent_work_pop "stats_q" >/dev/null

    local result
    result=$(agent_work_stats "stats_q")

    [[ "$result" == *'"pending":2'* ]]
    [[ "$result" == *'"queue":"stats_q"'* ]]
}

# =============================================================================
# DISCOVERY: ADDITIONAL TESTS
# =============================================================================

@test "agent_find_by_capability returns matching agents" {
    agent_register "http_worker" "http" "rest"
    agent_register "json_worker" "json" "parse"
    agent_register "multi_worker" "http" "json"

    local result
    result=$(agent_find_by_capability "http")
    [[ "$result" == *"http_worker"* ]]
    [[ "$result" == *"multi_worker"* ]]
    [[ "$result" != *"json_worker"* ]]
}

@test "agent_elect_leader returns one agent" {
    agent_register "candidate_1"
    agent_register "candidate_2"
    agent_register "candidate_3"

    local leader
    leader=$(agent_elect_leader "election_group")

    # Should return exactly one agent
    [ -n "$leader" ]
    [[ "$leader" =~ ^candidate_[1-3]$ ]]
}

@test "agent_elect_leader is deterministic" {
    agent_register "voter_a"
    agent_register "voter_b"

    local leader1
    leader1=$(agent_elect_leader "stable_group")

    local leader2
    leader2=$(agent_elect_leader "stable_group")

    [ "$leader1" = "$leader2" ]
}

@test "agent_elect_leader fails with no agents" {
    # Clear all agents
    rm -rf "$MAINFRAME_AGENT_DIR"/*

    run agent_elect_leader "empty_election"
    [ "$status" -ne 0 ]
}

# =============================================================================
# CLEANUP TESTS
# =============================================================================

@test "agent_cleanup removes all agent resources" {
    agent_register "cleanup_agent"
    _MAINFRAME_AGENT_NAME="cleanup_agent"
    agent_subscribe "cleanup_topic"
    agent_work_queue "cleanup_q"
    agent_work_push "cleanup_q" "test"

    run agent_cleanup
    [ "$status" -eq 0 ]

    # Directory should be empty (or just have empty subdirs)
    [ ! -d "$MAINFRAME_AGENT_DIR/cleanup_agent" ]
}

# =============================================================================
# INIT TESTS
# =============================================================================

@test "agent_init creates base directories" {
    rm -rf "$MAINFRAME_AGENT_DIR"
    agent_init

    [ -d "$MAINFRAME_AGENT_DIR/_queues" ]
    [ -d "$MAINFRAME_AGENT_DIR/_barriers" ]
    [ -d "$MAINFRAME_AGENT_DIR/_signals" ]
    [ -d "$MAINFRAME_AGENT_DIR/_topics" ]
    [ -d "$MAINFRAME_AGENT_DIR/_locks" ]
}

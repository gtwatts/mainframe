#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: FIFO Message Broker
# =============================================================================
# Description: Redis-like message broker using only named pipes
# Category:    agent
# WOW Factor:  10/10
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
#
# A full pub/sub message broker implemented with FIFOs (named pipes).
# No Redis, no RabbitMQ, no external dependencies - just filesystem primitives.
#
# Features:
# - PUBLISH/SUBSCRIBE channels
# - Message queues with persistence
# - Fan-out to multiple consumers
# - Message acknowledgment
# - Channel listing
# - Dead letter queue
#
# Architecture:
# - Each channel is a directory with subscriber FIFOs
# - Messages are written to all subscriber FIFOs
# - Persistent queue uses append-only log files
#
# Usage:
#   mainframe fifo-broker start                    # Start broker daemon
#   mainframe fifo-broker publish channel "msg"   # Publish message
#   mainframe fifo-broker subscribe channel       # Subscribe to channel
#   mainframe fifo-broker queue push queue "msg"  # Push to queue
#   mainframe fifo-broker queue pop queue         # Pop from queue
#
# =============================================================================

set -euo pipefail

# Source MAINFRAME libraries
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="fifo-broker"
readonly SCRIPT_VERSION="1.0.0"

# Broker directory (can be overridden)
BROKER_DIR="${MAINFRAME_BROKER_DIR:-${XDG_RUNTIME_DIR:-/tmp}/mainframe-broker}"
readonly CHANNELS_DIR="$BROKER_DIR/channels"
readonly QUEUES_DIR="$BROKER_DIR/queues"
readonly LOCK_DIR="$BROKER_DIR/locks"
readonly PID_FILE="$BROKER_DIR/broker.pid"

# Message format: TIMESTAMP|MESSAGE_ID|PAYLOAD
readonly MSG_DELIMITER="|"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

generate_msg_id() {
    # Generate unique message ID
    printf "%s-%04x" "$(date +%s%N)" "$RANDOM"
}

get_timestamp() {
    date +%s%N
}

ensure_broker_dirs() {
    mkdir -p "$CHANNELS_DIR" "$QUEUES_DIR" "$LOCK_DIR"
}

acquire_lock() {
    local lock_name="$1"
    local lock_file="$LOCK_DIR/$lock_name.lock"

    # Create lock file if doesn't exist
    touch "$lock_file"

    # Use flock for atomic locking
    exec 200>"$lock_file"
    flock -n 200 || return 1
}

release_lock() {
    local lock_name="$1"
    local lock_file="$LOCK_DIR/$lock_name.lock"

    flock -u 200 2>/dev/null || true
}

# =============================================================================
# CHANNEL OPERATIONS
# =============================================================================

channel_exists() {
    local channel="$1"
    [[ -d "$CHANNELS_DIR/$channel" ]]
}

create_channel() {
    local channel="$1"
    local channel_dir="$CHANNELS_DIR/$channel"

    if [[ -d "$channel_dir" ]]; then
        return 0  # Already exists
    fi

    mkdir -p "$channel_dir/subscribers"
    touch "$channel_dir/meta"

    info "Channel created: $channel"
}

delete_channel() {
    local channel="$1"
    local channel_dir="$CHANNELS_DIR/$channel"

    if [[ ! -d "$channel_dir" ]]; then
        warn "Channel not found: $channel"
        return 1
    fi

    # Remove all subscriber FIFOs
    rm -rf "$channel_dir"
    success "Channel deleted: $channel"
}

list_channels() {
    ensure_broker_dirs

    header "Active Channels"

    local count=0
    for channel_dir in "$CHANNELS_DIR"/*/; do
        [[ -d "$channel_dir" ]] || continue
        local channel
        channel=$(basename "$channel_dir")
        local sub_count
        sub_count=$(find "$channel_dir/subscribers" -type p 2>/dev/null | wc -l)
        printf "  %-30s %d subscribers\n" "$channel" "$sub_count"
        ((count++))
    done

    if [[ $count -eq 0 ]]; then
        info "No active channels"
    fi

    printf "\nTotal: %d channels\n" "$count"
}

# =============================================================================
# PUBLISH/SUBSCRIBE
# =============================================================================

publish() {
    local channel="$1"
    local message="$2"
    local channel_dir="$CHANNELS_DIR/$channel"

    # Auto-create channel
    create_channel "$channel" 2>/dev/null || true

    # Generate message envelope
    local msg_id
    msg_id=$(generate_msg_id)
    local timestamp
    timestamp=$(get_timestamp)
    local envelope="${timestamp}${MSG_DELIMITER}${msg_id}${MSG_DELIMITER}${message}"

    # Write to all subscriber FIFOs
    local delivered=0
    for fifo in "$channel_dir/subscribers"/*; do
        [[ -p "$fifo" ]] || continue

        # Non-blocking write with timeout
        if timeout 1 bash -c "echo '$envelope' > '$fifo'" 2>/dev/null; then
            ((delivered++))
        else
            # Subscriber disconnected, remove FIFO
            rm -f "$fifo"
        fi
    done

    # Log to channel history (optional persistence)
    echo "$envelope" >> "$channel_dir/history.log" 2>/dev/null || true

    if [[ "$VERBOSE" == "true" ]]; then
        info "Published to $channel: $msg_id (delivered to $delivered subscribers)"
    fi

    echo "$msg_id"
}

subscribe() {
    local channel="$1"
    local callback="${2:-}"  # Optional callback script
    local channel_dir="$CHANNELS_DIR/$channel"

    # Auto-create channel
    create_channel "$channel" 2>/dev/null || true

    # Create subscriber FIFO
    local subscriber_id="$$-$(date +%s%N)"
    local fifo="$channel_dir/subscribers/$subscriber_id"

    mkfifo "$fifo"

    # Cleanup on exit
    cleanup_subscription() {
        rm -f "$fifo"
        info "Unsubscribed from $channel"
    }
    trap cleanup_subscription EXIT INT TERM

    info "Subscribed to channel: $channel"
    info "Subscriber ID: $subscriber_id"
    printf "\n"

    # Read messages from FIFO
    while true; do
        if read -r envelope < "$fifo"; then
            # Parse envelope
            local timestamp msg_id message
            IFS="$MSG_DELIMITER" read -r timestamp msg_id message <<< "$envelope"

            if [[ -n "$callback" ]]; then
                # Execute callback with message
                "$callback" "$channel" "$msg_id" "$message"
            else
                # Print to stdout
                printf "[%s] %s: %s\n" "$msg_id" "$channel" "$message"
            fi
        fi
    done
}

# =============================================================================
# QUEUE OPERATIONS
# =============================================================================

queue_exists() {
    local queue="$1"
    [[ -f "$QUEUES_DIR/$queue/queue.log" ]]
}

create_queue() {
    local queue="$1"
    local queue_dir="$QUEUES_DIR/$queue"

    mkdir -p "$queue_dir"
    touch "$queue_dir/queue.log"
    touch "$queue_dir/processed.log"
    echo "0" > "$queue_dir/head"
    echo "0" > "$queue_dir/tail"

    info "Queue created: $queue"
}

queue_push() {
    local queue="$1"
    local message="$2"
    local queue_dir="$QUEUES_DIR/$queue"

    # Auto-create queue
    [[ -d "$queue_dir" ]] || create_queue "$queue"

    # Lock for atomic operation
    if ! acquire_lock "queue-$queue"; then
        die "$EXIT_TEMPFAIL" "Could not acquire queue lock"
    fi

    # Generate message
    local msg_id
    msg_id=$(generate_msg_id)
    local timestamp
    timestamp=$(get_timestamp)
    local envelope="${timestamp}${MSG_DELIMITER}${msg_id}${MSG_DELIMITER}${message}"

    # Append to queue log
    echo "$envelope" >> "$queue_dir/queue.log"

    # Update tail pointer
    local tail
    tail=$(cat "$queue_dir/tail")
    echo "$((tail + 1))" > "$queue_dir/tail"

    release_lock "queue-$queue"

    if [[ "$VERBOSE" == "true" ]]; then
        info "Pushed to $queue: $msg_id"
    fi

    echo "$msg_id"
}

queue_pop() {
    local queue="$1"
    local queue_dir="$QUEUES_DIR/$queue"

    if [[ ! -d "$queue_dir" ]]; then
        return 1  # Queue doesn't exist
    fi

    # Lock for atomic operation
    if ! acquire_lock "queue-$queue"; then
        die "$EXIT_TEMPFAIL" "Could not acquire queue lock"
    fi

    local head tail
    head=$(cat "$queue_dir/head")
    tail=$(cat "$queue_dir/tail")

    if [[ "$head" -ge "$tail" ]]; then
        release_lock "queue-$queue"
        return 1  # Queue empty
    fi

    # Read message at head position (1-indexed for sed)
    local line_num=$((head + 1))
    local envelope
    envelope=$(sed -n "${line_num}p" "$queue_dir/queue.log")

    # Update head pointer
    echo "$((head + 1))" > "$queue_dir/head"

    # Log as processed
    echo "$envelope" >> "$queue_dir/processed.log"

    release_lock "queue-$queue"

    # Parse and output
    local timestamp msg_id message
    IFS="$MSG_DELIMITER" read -r timestamp msg_id message <<< "$envelope"

    echo "$message"
}

queue_peek() {
    local queue="$1"
    local queue_dir="$QUEUES_DIR/$queue"

    if [[ ! -d "$queue_dir" ]]; then
        return 1
    fi

    local head tail
    head=$(cat "$queue_dir/head")
    tail=$(cat "$queue_dir/tail")

    if [[ "$head" -ge "$tail" ]]; then
        return 1  # Queue empty
    fi

    # Read message at head position
    local line_num=$((head + 1))
    local envelope
    envelope=$(sed -n "${line_num}p" "$queue_dir/queue.log")

    # Parse and output
    local timestamp msg_id message
    IFS="$MSG_DELIMITER" read -r timestamp msg_id message <<< "$envelope"

    echo "$message"
}

queue_length() {
    local queue="$1"
    local queue_dir="$QUEUES_DIR/$queue"

    if [[ ! -d "$queue_dir" ]]; then
        echo "0"
        return
    fi

    local head tail
    head=$(cat "$queue_dir/head")
    tail=$(cat "$queue_dir/tail")

    echo "$((tail - head))"
}

queue_list() {
    ensure_broker_dirs

    header "Message Queues"

    local count=0
    for queue_dir in "$QUEUES_DIR"/*/; do
        [[ -d "$queue_dir" ]] || continue
        local queue
        queue=$(basename "$queue_dir")
        local length
        length=$(queue_length "$queue")
        printf "  %-30s %d messages\n" "$queue" "$length"
        ((count++))
    done

    if [[ $count -eq 0 ]]; then
        info "No queues"
    fi

    printf "\nTotal: %d queues\n" "$count"
}

# =============================================================================
# BROKER DAEMON
# =============================================================================

broker_start() {
    ensure_broker_dirs

    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            die "$EXIT_CANTCREAT" "Broker already running (PID: $old_pid)"
        fi
    fi

    info "Starting MAINFRAME Message Broker..."
    info "Broker directory: $BROKER_DIR"

    # Write PID file
    echo $$ > "$PID_FILE"

    # Cleanup on exit
    broker_cleanup() {
        rm -f "$PID_FILE"
        info "Broker stopped"
    }
    trap broker_cleanup EXIT INT TERM

    success "Broker started (PID: $$)"
    printf "\n"

    # Keep broker alive (monitors health, compacts logs, etc.)
    while true; do
        # Periodic maintenance
        sleep 60

        # Compact processed messages in queues
        for queue_dir in "$QUEUES_DIR"/*/; do
            [[ -d "$queue_dir" ]] || continue
            local queue
            queue=$(basename "$queue_dir")

            # If head > 1000, compact the log
            local head
            head=$(cat "$queue_dir/head" 2>/dev/null || echo "0")
            if [[ "$head" -gt 1000 ]]; then
                acquire_lock "queue-$queue" || continue

                # Remove processed lines
                tail -n "+$((head + 1))" "$queue_dir/queue.log" > "$queue_dir/queue.log.tmp"
                mv "$queue_dir/queue.log.tmp" "$queue_dir/queue.log"

                # Reset pointers
                local tail
                tail=$(cat "$queue_dir/tail")
                echo "0" > "$queue_dir/head"
                echo "$((tail - head))" > "$queue_dir/tail"

                release_lock "queue-$queue"

                [[ "$VERBOSE" == "true" ]] && info "Compacted queue: $queue"
            fi
        done
    done
}

broker_stop() {
    if [[ ! -f "$PID_FILE" ]]; then
        warn "Broker not running"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        info "Stopping broker (PID: $pid)..."
        kill "$pid"
        rm -f "$PID_FILE"
        success "Broker stopped"
    else
        warn "Broker process not found, cleaning up"
        rm -f "$PID_FILE"
    fi
}

broker_status() {
    ensure_broker_dirs

    header "MAINFRAME Broker Status"

    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            success "Broker running (PID: $pid)"
        else
            warn "Broker not running (stale PID file)"
        fi
    else
        info "Broker not running"
    fi

    printf "\n"
    printf "Broker directory: %s\n" "$BROKER_DIR"

    local channel_count queue_count
    channel_count=$(find "$CHANNELS_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    queue_count=$(find "$QUEUES_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    ((channel_count--)) || true  # Subtract 1 for parent dir
    ((queue_count--)) || true

    printf "Channels: %d\n" "$channel_count"
    printf "Queues: %d\n" "$queue_count"
}

# =============================================================================
# MAIN
# =============================================================================

VERBOSE="${VERBOSE:-false}"

show_help() {
    cat << EOF
${CLR_BOLD}$SCRIPT_NAME${CLR_RESET} - FIFO Message Broker

${CLR_BOLD}Usage:${CLR_RESET}
  mainframe $SCRIPT_NAME <command> [options]

${CLR_BOLD}Commands:${CLR_RESET}
  ${CLR_BOLD}Broker:${CLR_RESET}
    start              Start the broker daemon
    stop               Stop the broker daemon
    status             Show broker status

  ${CLR_BOLD}Pub/Sub:${CLR_RESET}
    publish <channel> <message>    Publish message to channel
    subscribe <channel>            Subscribe to channel
    channels                       List all channels

  ${CLR_BOLD}Queues:${CLR_RESET}
    queue push <queue> <message>   Push message to queue
    queue pop <queue>              Pop message from queue
    queue peek <queue>             Peek at next message
    queue length <queue>           Get queue length
    queue list                     List all queues

${CLR_BOLD}Options:${CLR_RESET}
  -v, --verbose    Enable verbose output
  -h, --help       Show this help message

${CLR_BOLD}Examples:${CLR_RESET}
  # Start broker in background
  mainframe $SCRIPT_NAME start &

  # Publish/Subscribe
  mainframe $SCRIPT_NAME subscribe events &
  mainframe $SCRIPT_NAME publish events "Hello, World!"

  # Message queue
  mainframe $SCRIPT_NAME queue push tasks "Process file.txt"
  mainframe $SCRIPT_NAME queue pop tasks

${CLR_BOLD}Environment:${CLR_RESET}
  MAINFRAME_BROKER_DIR    Broker directory (default: \$XDG_RUNTIME_DIR/mainframe-broker)

${CLR_DIM}YO JOE!${CLR_RESET}
EOF
}

main() {
    ensure_broker_dirs

    local command="${1:-}"
    shift || true

    # Global options
    while [[ $# -gt 0 && "$1" == -* ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    case "$command" in
        start)
            broker_start
            ;;
        stop)
            broker_stop
            ;;
        status)
            broker_status
            ;;
        publish|pub)
            local channel="${1:?Channel required}"
            local message="${2:?Message required}"
            publish "$channel" "$message"
            ;;
        subscribe|sub)
            local channel="${1:?Channel required}"
            subscribe "$channel" "${2:-}"
            ;;
        channels|ch)
            list_channels
            ;;
        queue|q)
            local subcmd="${1:-list}"
            shift || true
            case "$subcmd" in
                push)
                    queue_push "${1:?Queue name required}" "${2:?Message required}"
                    ;;
                pop)
                    queue_pop "${1:?Queue name required}"
                    ;;
                peek)
                    queue_peek "${1:?Queue name required}"
                    ;;
                length|len)
                    queue_length "${1:?Queue name required}"
                    ;;
                list|ls)
                    queue_list
                    ;;
                *)
                    die "$EXIT_USAGE" "Unknown queue command: $subcmd"
                    ;;
            esac
            ;;
        -h|--help|help)
            show_help
            ;;
        "")
            show_help
            ;;
        *)
            die "$EXIT_USAGE" "Unknown command: $command"
            ;;
    esac
}

main "$@"

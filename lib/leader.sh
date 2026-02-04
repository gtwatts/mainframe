#!/usr/bin/env bash
#
# Leader Election Module for Mainframe
# Provides distributed leader election with file-based and Redis-based backends
#
# Features:
#   - File-based leader election using flock for atomicity
#   - Redis-based leader election using SET NX EX for distributed lease
#   - TTL-based leadership with automatic expiration
#   - Leader renewal and graceful step-down
#
# Usage:
#   source "${MAINFRAME_ROOT}/lib/leader.sh"
#   leader_elect "my-group" "$(hostname)" 30
#

# =============================================================================
# MODULE GUARD
# =============================================================================

[[ -n "${_MAINFRAME_LEADER_LOADED:-}" ]] && return 0
_MAINFRAME_LEADER_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Leader state directory (defaults to orchestrate leaders dir)
: "${MAINFRAME_LEADER_DIR:=${ORCH_STATE_DIR:-${TMPDIR:-/tmp}/mainframe-${UID}/orchestrate}/leaders}"

# Default TTL for leader lease (seconds)
: "${MAINFRAME_LEADER_TTL:=30}"

# Renewal interval (should be < TTL/2)
: "${MAINFRAME_LEADER_RENEWAL_INTERVAL:=10}"

# Redis URL (optional, for distributed mode)
: "${MAINFRAME_LEADER_REDIS_URL:=${REDIS_URL:-}}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

declare -gA _LEADER_GROUPS=()  # group -> candidate mapping for this process
declare -gA _LEADER_RENEWAL_PIDS=()  # group -> renewal background PID

# =============================================================================
# LOGGING HELPERS
# =============================================================================

# Use orchestrate logging if available, otherwise fallback
_leader_log() {
    local level="$1" message="$2"
    if type -t _orch_log &>/dev/null; then
        _orch_log "$level" "$message"
    elif type -t mainframe_log &>/dev/null; then
        mainframe_log "$level" "$message"
    else
        printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >&2
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get epoch seconds
_leader_epoch() {
    date +%s
}

# Get leader file path for a group
_leader_file() {
    local group="${1:-default}"
    printf '%s/%s/leader' "$MAINFRAME_LEADER_DIR" "$group"
}

# Get lock file path for a group
_leader_lock_file() {
    local group="${1:-default}"
    printf '%s/%s/lock' "$MAINFRAME_LEADER_DIR" "$group"
}

# Initialize leader directory structure
_leader_init_dir() {
    local group="${1:-default}"
    local dir="$MAINFRAME_LEADER_DIR/$group"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null || {
            _leader_log error "Failed to create leader directory: $dir"
            return 1
        }
    fi
    return 0
}

# =============================================================================
# FILE-BASED LEADER ELECTION
# =============================================================================

##
# @brief Attempt to become leader using file-based locking
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @param $3 TTL in seconds (default: 30)
# @return 0 if elected, 1 if not elected, 2 on error
#
# Uses flock for atomic leader election. The leader file contains
# "candidate:timestamp" format. Leadership expires after TTL seconds.
##
leader_elect_file() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"
    local ttl="${3:-$MAINFRAME_LEADER_TTL}"

    _leader_init_dir "$group" || return 2

    local leader_file
    local lock_file
    leader_file=$(_leader_file "$group")
    lock_file=$(_leader_lock_file "$group")

    local elected=1
    local now
    now=$(_leader_epoch)

    # Use flock for atomic operation
    {
        flock -x 200 || return 2

        # Check if there's an existing valid leader
        if [[ -f "$leader_file" ]]; then
            local leader_data
            leader_data=$(cat "$leader_file" 2>/dev/null || echo "")
            if [[ -n "$leader_data" ]]; then
                local leader_time
                leader_time=$(printf '%s' "$leader_data" | cut -d: -f2)
                # Check if leader is still valid
                if [[ $((now - leader_time)) -lt ttl ]]; then
                    # Leader still valid
                    elected=1
                else
                    # Leader expired, try to take over
                    printf '%s:%d' "$candidate" "$now" > "$leader_file" 2>/dev/null
                    [[ $? -eq 0 ]] && elected=0
                fi
            else
                # Empty leader file, try to become leader
                printf '%s:%d' "$candidate" "$now" > "$leader_file" 2>/dev/null
                [[ $? -eq 0 ]] && elected=0
            fi
        else
            # No leader file, try to become leader
            printf '%s:%d' "$candidate" "$now" > "$leader_file" 2>/dev/null
            [[ $? -eq 0 ]] && elected=0
        fi

        flock -u 200
    } 200>"$lock_file"

    if [[ $elected -eq 0 ]]; then
        _LEADER_GROUPS["$group"]="$candidate"
        _leader_log info "Elected leader for group '$group': $candidate"
    fi

    return $elected
}

##
# @brief Get current leader for a group (file-based)
# @param $1 Group name (default: "default")
# @return Prints leader ID to stdout, empty if no leader
##
leader_get_file() {
    local group="${1:-default}"
    local leader_file
    leader_file=$(_leader_file "$group")

    if [[ -f "$leader_file" ]]; then
        local leader_data
        leader_data=$(cat "$leader_file" 2>/dev/null || echo "")
        if [[ -n "$leader_data" ]]; then
            printf '%s' "$leader_data" | cut -d: -f1
        fi
    fi
}

##
# @brief Check if leader is still valid (file-based)
# @param $1 Group name (default: "default")
# @param $2 TTL in seconds (default: 30)
# @return 0 if leader is valid, 1 if expired or no leader
##
leader_is_valid_file() {
    local group="${1:-default}"
    local ttl="${2:-$MAINFRAME_LEADER_TTL}"
    local leader_file
    leader_file=$(_leader_file "$group")

    if [[ -f "$leader_file" ]]; then
        local leader_data
        leader_data=$(cat "$leader_file" 2>/dev/null || echo "")
        if [[ -n "$leader_data" ]]; then
            local leader_time
            leader_time=$(printf '%s' "$leader_data" | cut -d: -f2)
            local now
            now=$(_leader_epoch)
            if [[ $((now - leader_time)) -lt ttl ]]; then
                return 0
            fi
        fi
    fi
    return 1
}

##
# @brief Renew leadership (file-based)
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @return 0 if renewed, 1 if not leader, 2 on error
#
# Must be called periodically (more frequently than TTL/2) to maintain leadership.
##
leader_renew_file() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"

    local leader_file
    local lock_file
    leader_file=$(_leader_file "$group")
    lock_file=$(_leader_lock_file "$group")

    local renewed=1
    local now
    now=$(_leader_epoch)

    {
        flock -x 200 || return 2

        # Verify we are still the leader
        if [[ -f "$leader_file" ]]; then
            local leader_data
            leader_data=$(cat "$leader_file" 2>/dev/null || echo "")
            local current_leader
            current_leader=$(printf '%s' "$leader_data" | cut -d: -f1)

            if [[ "$current_leader" == "$candidate" ]]; then
                # Renew our leadership
                printf '%s:%d' "$candidate" "$now" > "$leader_file" 2>/dev/null
                [[ $? -eq 0 ]] && renewed=0
            fi
        fi

        flock -u 200
    } 200>"$lock_file"

    return $renewed
}

##
# @brief Step down as leader (file-based)
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @return 0 on success, 1 if not leader, 2 on error
##
leader_step_down_file() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"

    local leader_file
    local lock_file
    leader_file=$(_leader_file "$group")
    lock_file=$(_leader_lock_file "$group")

    local stepped_down=1

    {
        flock -x 200 || return 2

        # Verify we are the leader before removing
        if [[ -f "$leader_file" ]]; then
            local leader_data
            leader_data=$(cat "$leader_file" 2>/dev/null || echo "")
            local current_leader
            current_leader=$(printf '%s' "$leader_data" | cut -d: -f1)

            if [[ "$current_leader" == "$candidate" ]]; then
                rm -f "$leader_file"
                stepped_down=0
                _leader_log info "Stepped down as leader for group '$group'"
            fi
        fi

        flock -u 200
    } 200>"$lock_file"

    # Clean up internal state
    unset "_LEADER_GROUPS[$group]"

    return $stepped_down
}

# =============================================================================
# REDIS-BASED LEADER ELECTION
# =============================================================================

##
# @brief Check if Redis is available for leader election
# @return 0 if Redis is available, 1 otherwise
##
leader_redis_available() {
    [[ -n "${MAINFRAME_LEADER_REDIS_URL:-}" ]] || return 1
    redis-cli -u "$MAINFRAME_LEADER_REDIS_URL" PING &>/dev/null
}

##
# @brief Attempt to become leader using Redis
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @param $3 TTL in seconds (default: 30)
# @return 0 if elected, 1 if not elected, 2 on error
#
# Uses Redis SET with NX (only if not exists) and EX (expiration) for atomic election.
##
leader_elect_redis() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"
    local ttl="${3:-$MAINFRAME_LEADER_TTL}"

    if ! leader_redis_available; then
        return 2
    fi

    local key="mainframe:leader:$group"
    local result

    # Try to set with NX (only if not exists) and EX (expiration)
    result=$(redis-cli -u "$MAINFRAME_LEADER_REDIS_URL" SET "$key" "$candidate" NX EX "$ttl" 2>/dev/null)

    if [[ "$result" == "OK" ]]; then
        _LEADER_GROUPS["$group"]="$candidate"
        _leader_log info "Elected leader via Redis for group '$group': $candidate"
        return 0
    else
        return 1
    fi
}

##
# @brief Get current leader for a group (Redis)
# @param $1 Group name (default: "default")
# @return Prints leader ID to stdout, empty if no leader
##
leader_get_redis() {
    local group="${1:-default}"

    if ! leader_redis_available; then
        return 1
    fi

    local key="mainframe:leader:$group"
    redis-cli -u "$MAINFRAME_LEADER_REDIS_URL" GET "$key" 2>/dev/null
}

##
# @brief Renew leadership (Redis)
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @param $3 TTL in seconds (default: 30)
# @return 0 if renewed, 1 if not leader, 2 on error
#
# Uses GET to verify ownership, then EXPIRE to renew TTL.
##
leader_renew_redis() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"
    local ttl="${3:-$MAINFRAME_LEADER_TTL}"

    if ! leader_redis_available; then
        return 2
    fi

    local key="mainframe:leader:$group"
    local current_leader

    current_leader=$(redis-cli -u "$MAINFRAME_LEADER_REDIS_URL" GET "$key" 2>/dev/null)

    if [[ "$current_leader" == "$candidate" ]]; then
        # We are still the leader, renew TTL
        redis-cli -u "$MAINFRAME_LEADER_REDIS_URL" EXPIRE "$key" "$ttl" &>/dev/null
        return 0
    else
        return 1
    fi
}

##
# @brief Step down as leader (Redis)
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @return 0 on success, 1 if not leader, 2 on error
##
leader_step_down_redis() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"

    if ! leader_redis_available; then
        return 2
    fi

    local key="mainframe:leader:$group"
    local current_leader

    current_leader=$(redis-cli -u "$MAINFRAME_LEADER_REDIS_URL" GET "$key" 2>/dev/null)

    if [[ "$current_leader" == "$candidate" ]]; then
        redis-cli -u "$MAINFRAME_LEADER_REDIS_URL" DEL "$key" &>/dev/null
        _leader_log info "Stepped down as Redis leader for group '$group'"
        unset "_LEADER_GROUPS[$group]"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# UNIFIED LEADER ELECTION API
# =============================================================================

##
# @brief Attempt to become leader (auto-detects backend)
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @param $3 TTL in seconds (default: 30)
# @return 0 if elected, 1 if not elected, 2 on error
#
# Tries Redis first if available, falls back to file-based.
##
leader_elect() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"
    local ttl="${3:-$MAINFRAME_LEADER_TTL}"

    # Try Redis first if available
    if leader_redis_available; then
        leader_elect_redis "$group" "$candidate" "$ttl"
        local result=$?
        [[ $result -eq 0 ]] && return 0
        # If Redis failed (not just "not elected"), fall back to file
        [[ $result -eq 2 ]] || return $result
    fi

    # Fall back to file-based
    leader_elect_file "$group" "$candidate" "$ttl"
}

##
# @brief Get current leader for a group (auto-detects backend)
# @param $1 Group name (default: "default")
# @return Prints leader ID to stdout, empty if no leader
##
leader_get() {
    local group="${1:-default}"

    # Try Redis first
    if leader_redis_available; then
        local leader
        leader=$(leader_get_redis "$group")
        if [[ -n "$leader" ]]; then
            printf '%s' "$leader"
            return 0
        fi
    fi

    # Fall back to file-based
    leader_get_file "$group"
}

##
# @brief Check if current process is the leader
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @return 0 if is leader, 1 otherwise
##
leader_am_i_leader() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"

    local current_leader
    current_leader=$(leader_get "$group")

    [[ "$current_leader" == "$candidate" ]]
}

##
# @brief Renew leadership (auto-detects backend)
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @param $3 TTL in seconds (default: 30)
# @return 0 if renewed, 1 if not leader, 2 on error
##
leader_renew() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"
    local ttl="${3:-$MAINFRAME_LEADER_TTL}"

    # Try Redis first if available
    if leader_redis_available; then
        leader_renew_redis "$group" "$candidate" "$ttl"
        local result=$?
        [[ $result -eq 0 ]] && return 0
        [[ $result -eq 2 ]] || return $result
    fi

    # Fall back to file-based
    leader_renew_file "$group" "$candidate"
}

##
# @brief Step down as leader (auto-detects backend)
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @return 0 on success, 1 if not leader, 2 on error
##
leader_step_down() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"

    # Try Redis first if available
    if leader_redis_available; then
        leader_step_down_redis "$group" "$candidate"
        local result=$?
        [[ $result -eq 0 ]] && return 0
        [[ $result -eq 2 ]] || return $result
    fi

    # Fall back to file-based
    leader_step_down_file "$group" "$candidate"
}

##
# @brief Start automatic leader renewal in background
# @param $1 Group name (default: "default")
# @param $2 Candidate ID (default: hostname)
# @param $3 TTL in seconds (default: 30)
# @return 0 on success, 1 on failure
#
# Starts a background process that periodically renews leadership.
# Store the PID to stop later with leader_stop_renewal().
##
leader_start_renewal() {
    local group="${1:-default}"
    local candidate="${2:-$(hostname)}"
    local ttl="${3:-$MAINFRAME_LEADER_TTL}"

    # Stop any existing renewal for this group
    leader_stop_renewal "$group" 2>/dev/null

    # Calculate renewal interval (TTL/3, minimum 5 seconds)
    local interval=$((ttl / 3))
    [[ $interval -lt 5 ]] && interval=5

    # Start renewal loop in background
    (
        while true; do
            sleep "$interval"
            leader_renew "$group" "$candidate" "$ttl" || exit 0
        done
    ) &

    local pid=$!
    _LEADER_RENEWAL_PIDS["$group"]="$pid"
    _leader_log info "Started leader renewal for group '$group' (PID: $pid, interval: ${interval}s)"

    return 0
}

##
# @brief Stop automatic leader renewal
# @param $1 Group name (default: "default")
# @return 0 on success, 1 if no renewal running
##
leader_stop_renewal() {
    local group="${1:-default}"

    local pid="${_LEADER_RENEWAL_PIDS[$group]:-}"
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null
        unset "_LEADER_RENEWAL_PIDS[$group]"
        _leader_log info "Stopped leader renewal for group '$group'"
        return 0
    fi
    return 1
}

##
# @brief Stop all leader renewals
# @return 0 on success
##
leader_stop_all_renewals() {
    local group
    for group in "${_!_LEADER_RENEWAL_PIDS[@]}"; do
        leader_stop_renewal "$group"
    done
    return 0
}

##
# @brief Wait for a leader to be elected
# @param $1 Group name (default: "default")
# @param $2 Timeout in seconds (default: 60)
# @return 0 if leader found, 1 on timeout
#
# Blocks until a leader is elected or timeout is reached.
##
leader_wait_for() {
    local group="${1:-default}"
    local timeout="${2:-60}"

    local deadline
    deadline=$(($(date +%s) + timeout))

    while [[ $(date +%s) -lt $deadline ]]; do
        local leader
        leader=$(leader_get "$group")
        if [[ -n "$leader" ]]; then
            printf '%s' "$leader"
            return 0
        fi
        sleep 1
    done

    return 1
}

##
# @brief List all known leader groups
# @return Prints group names to stdout, one per line
##
leader_list_groups() {
    if [[ -d "$MAINFRAME_LEADER_DIR" ]]; then
        find "$MAINFRAME_LEADER_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null
    fi
}

##
# @brief Get status of all leader groups
# @return Prints JSON array with group status
##
leader_status_all() {
    local groups=()
    local first=1

    printf '['
    while IFS= read -r group; do
        [[ -n "$group" ]] || continue
        [[ $first -eq 1 ]] || printf ','
        first=0

        local leader
        leader=$(leader_get "$group")
        printf '{"group":"%s","leader":"%s","has_leader":%s}' \
            "$group" \
            "${leader:-null}" \
            "$([[ -n "$leader" ]] && echo "true" || echo "false")"
    done < <(leader_list_groups)
    printf ']\n'
}

##
# @brief Cleanup leader resources on exit
# @return 0 on success
#
# Should be called on script exit to gracefully step down as leader.
##
leader_cleanup() {
    _leader_log info "Cleaning up leader election resources..."

    # Stop all renewals
    leader_stop_all_renewals

    # Step down from all groups we're leading
    local group candidate
    for group in "${!_LEADER_GROUPS[@]}"; do
        candidate="${_LEADER_GROUPS[$group]}"
        leader_step_down "$group" "$candidate" 2>/dev/null || true
    done

    return 0
}

# Register cleanup on exit if not already registered
trap 'leader_cleanup 2>/dev/null || true' EXIT 2>/dev/null || true

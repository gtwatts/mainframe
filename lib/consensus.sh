#!/usr/bin/env bash
#
# Consensus Primitives Module for Mainframe
# Provides simple consensus mechanisms for distributed agreement
#
# Features:
#   - Majority voting with yes/no/pending states
#   - Vote counting with configurable total voters
#   - File-based vote storage per topic
#   - Consensus result caching
#
# Usage:
#   source "${MAINFRAME_ROOT}/lib/consensus.sh"
#   consensus_vote "my-topic" "yes" "$(hostname)" 5
#

# =============================================================================
# MODULE GUARD
# =============================================================================

[[ -n "${_MAINFRAME_CONSENSUS_LOADED:-}" ]] && return 0
_MAINFRAME_CONSENSUS_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Consensus state directory
: "${MAINFRAME_CONSENSUS_DIR:=${ORCH_STATE_DIR:-${TMPDIR:-/tmp}/mainframe-${UID}/orchestrate}/consensus}"

# Default vote timeout in seconds
: "${MAINFRAME_CONSENSUS_TIMEOUT:=60}"

# Default quorum percentage (0-100)
: "${MAINFRAME_CONSENSUS_QUORUM:=51}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

declare -gA _CONSENSUS_TOPICS=()  # Track topics this process is participating in

# =============================================================================
# LOGGING HELPERS
# =============================================================================

# Use orchestrate logging if available, otherwise fallback
_consensus_log() {
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
_consensus_epoch() {
    date +%s
}

# Get vote directory for a topic
_consensus_vote_dir() {
    local topic="$1"
    printf '%s/%s' "$MAINFRAME_CONSENSUS_DIR" "$topic"
}

# Get vote file for a voter on a topic
_consensus_vote_file() {
    local topic="$1" voter="$2"
    printf '%s/%s/votes/%s' "$MAINFRAME_CONSENSUS_DIR" "$topic" "$voter"
}

# Get lock file for a topic
_consensus_lock_file() {
    local topic="$1"
    printf '%s/%s/lock' "$MAINFRAME_CONSENSUS_DIR" "$topic"
}

# Get metadata file for a topic
_consensus_meta_file() {
    local topic="$1"
    printf '%s/%s/meta' "$MAINFRAME_CONSENSUS_DIR" "$topic"
}

# Initialize consensus directory structure
_consensus_init_topic() {
    local topic="$1"
    local dir="$MAINFRAME_CONSENSUS_DIR/$topic"

    if [[ ! -d "$dir/votes" ]]; then
        mkdir -p "$dir/votes" 2>/dev/null || {
            _consensus_log error "Failed to create consensus directory: $dir"
            return 1
        }
    fi
    return 0
}

# =============================================================================
# CORE VOTING FUNCTIONS
# =============================================================================

##
# @brief Cast a vote on a topic
# @param $1 Topic name (required)
# @param $2 Vote value: "yes", "no", or "abstain" (required)
# @param $3 Voter ID (default: hostname)
# @param $4 Total number of voters (default: 3)
# @return 0 if consensus reached (yes), 1 if consensus reached (no), 2 if pending, 3 on error
#
# Casts a vote and immediately counts all votes to determine if consensus is reached.
# Consensus is reached when a majority (>50%) of total_voters cast the same vote.
#
# Output format on consensus: "consensus:yes" or "consensus:no"
# Output format on pending: "pending:<yes_count>:<no_count>:<abstain_count>:<total_cast>"
##
consensus_vote() {
    local topic="$1"
    local vote="$2"
    local voter="${3:-$(hostname)}"
    local total_voters="${4:-3}"

    # Validate inputs
    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_vote: topic is required"
        return 3
    fi

    if [[ -z "$vote" ]]; then
        _consensus_log error "consensus_vote: vote is required"
        return 3
    fi

    # Normalize vote
    case "$vote" in
        yes|YES|y|Y|true|1)
            vote="yes"
            ;;
        no|NO|n|N|false|0)
            vote="no"
            ;;
        abstain|ABSTAIN|skip|SKIP|abstention)
            vote="abstain"
            ;;
        *)
            _consensus_log error "consensus_vote: invalid vote '$vote', must be yes/no/abstain"
            return 3
            ;;
    esac

    # Initialize topic directory
    _consensus_init_topic "$topic" || return 3

    local lock_file
    lock_file=$(_consensus_lock_file "$topic")

    local result=2
    local yes_count=0
    local no_count=0
    local abstain_count=0

    # Atomic vote casting and counting
    {
        flock -x 200 || return 3

        # Record the vote
        printf '%s:%d' "$vote" "$(_consensus_epoch)" > "$(_consensus_vote_file "$topic" "$voter")"

        # Count all votes
        local vote_file vote_value
        for vote_file in "$MAINFRAME_CONSENSUS_DIR/$topic/votes"/*; do
            [[ -f "$vote_file" ]] || continue
            vote_value=$(head -c 20 "$vote_file" 2>/dev/null | cut -d: -f1)
            case "$vote_value" in
                yes) ((yes_count++)) ;;
                no) ((no_count++)) ;;
                abstain) ((abstain_count++)) ;;
            esac
        done

        # Calculate majority threshold
        local majority=$(( (total_voters / 2) + 1 ))
        local total_cast=$((yes_count + no_count + abstain_count))

        # Check for consensus
        if [[ $yes_count -ge $majority ]]; then
            result=0
            printf 'consensus:yes' > "$MAINFRAME_CONSENSUS_DIR/$topic/result"
            printf '%d' "$(_consensus_epoch)" >> "$MAINFRAME_CONSENSUS_DIR/$topic/result"
        elif [[ $no_count -ge $majority ]]; then
            result=1
            printf 'consensus:no' > "$MAINFRAME_CONSENSUS_DIR/$topic/result"
            printf ':%d' "$(_consensus_epoch)" >> "$MAINFRAME_CONSENSUS_DIR/$topic/result"
        else
            result=2
        fi

        flock -u 200
    } 200>"$lock_file"

    # Output result
    case $result in
        0)
            printf 'consensus:yes\n'
            _consensus_log info "Consensus reached on '$topic': YES ($yes_count/$total_voters)"
            ;;
        1)
            printf 'consensus:no\n'
            _consensus_log info "Consensus reached on '$topic': NO ($no_count/$total_voters)"
            ;;
        2)
            printf 'pending:%d:%d:%d:%d\n' "$yes_count" "$no_count" "$abstain_count" "$total_cast"
            _consensus_log debug "Vote cast on '$topic': $vote (yes:$yes_count no:$no_count abstain:$abstain_count)"
            ;;
    esac

    # Track participation
    _CONSENSUS_TOPICS["$topic"]=1

    return $result
}

##
# @brief Get current vote counts for a topic
# @param $1 Topic name (required)
# @return Prints "yes:N no:M abstain:P total:Q" to stdout
##
consensus_count() {
    local topic="$1"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_count: topic is required"
        return 1
    fi

    local vote_dir="$MAINFRAME_CONSENSUS_DIR/$topic/votes"
    if [[ ! -d "$vote_dir" ]]; then
        printf 'yes:0 no:0 abstain:0 total:0\n'
        return 0
    fi

    local yes_count=0
    local no_count=0
    local abstain_count=0
    local vote_file vote_value

    for vote_file in "$vote_dir"/*; do
        [[ -f "$vote_file" ]] || continue
        vote_value=$(head -c 20 "$vote_file" 2>/dev/null | cut -d: -f1)
        case "$vote_value" in
            yes) ((yes_count++)) ;;
            no) ((no_count++)) ;;
            abstain) ((abstain_count++)) ;;
        esac
    done

    local total=$((yes_count + no_count + abstain_count))
    printf 'yes:%d no:%d abstain:%d total:%d\n' "$yes_count" "$no_count" "$abstain_count" "$total"
}

##
# @brief Check if consensus has been reached
# @param $1 Topic name (required)
# @param $2 Total number of voters (default: 3)
# @return 0 if consensus yes, 1 if consensus no, 2 if pending, 3 if error
#
# Output format: "consensus:yes", "consensus:no", or "pending:yes:N:no:M"
##
consensus_check() {
    local topic="$1"
    local total_voters="${2:-3}"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_check: topic is required"
        return 3
    fi

    local vote_dir="$MAINFRAME_CONSENSUS_DIR/$topic/votes"
    if [[ ! -d "$vote_dir" ]]; then
        printf 'pending:yes:0:no:0\n'
        return 2
    fi

    # Check for cached result
    local result_file="$MAINFRAME_CONSENSUS_DIR/$topic/result"
    if [[ -f "$result_file" ]]; then
        local cached_result
        cached_result=$(head -c 20 "$result_file" 2>/dev/null)
        case "$cached_result" in
            consensus:yes)
                printf '%s\n' "$cached_result"
                return 0
                ;;
            consensus:no)
                printf '%s\n' "$cached_result"
                return 1
                ;;
        esac
    fi

    local yes_count=0
    local no_count=0
    local abstain_count=0
    local vote_file vote_value

    for vote_file in "$vote_dir"/*; do
        [[ -f "$vote_file" ]] || continue
        vote_value=$(head -c 20 "$vote_file" 2>/dev/null | cut -d: -f1)
        case "$vote_value" in
            yes) ((yes_count++)) ;;
            no) ((no_count++)) ;;
            abstain) ((abstain_count++)) ;;
        esac
    done

    local majority=$(( (total_voters / 2) + 1 ))

    if [[ $yes_count -ge $majority ]]; then
        printf 'consensus:yes\n'
        return 0
    elif [[ $no_count -ge $majority ]]; then
        printf 'consensus:no\n'
        return 1
    else
        printf 'pending:yes:%d:no:%d\n' "$yes_count" "$no_count"
        return 2
    fi
}

##
# @brief Wait for consensus to be reached
# @param $1 Topic name (required)
# @param $2 Timeout in seconds (default: 60)
# @param $3 Total number of voters (default: 3)
# @return 0 if consensus yes, 1 if consensus no, 2 on timeout, 3 on error
#
# Blocks until consensus is reached or timeout expires.
##
consensus_wait() {
    local topic="$1"
    local timeout="${2:-60}"
    local total_voters="${3:-3}"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_wait: topic is required"
        return 3
    fi

    local deadline
    deadline=$(($(date +%s) + timeout))

    while [[ $(date +%s) -lt $deadline ]]; do
        local result
        result=$(consensus_check "$topic" "$total_voters")
        local ret=$?

        if [[ $ret -eq 0 || $ret -eq 1 ]]; then
            printf '%s\n' "$result"
            return $ret
        fi

        sleep 1
    done

    _consensus_log warn "Timeout waiting for consensus on '$topic'"
    return 2
}

##
# @brief Get the vote cast by a specific voter
# @param $1 Topic name (required)
# @param $2 Voter ID (default: hostname)
# @return Prints vote value and timestamp, or empty if not voted
##
consensus_get_vote() {
    local topic="$1"
    local voter="${2:-$(hostname)}"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_get_vote: topic is required"
        return 1
    fi

    local vote_file
    vote_file=$(_consensus_vote_file "$topic" "$voter")

    if [[ -f "$vote_file" ]]; then
        cat "$vote_file" 2>/dev/null
        return 0
    fi

    return 1
}

##
# @brief Revoke a previously cast vote
# @param $1 Topic name (required)
# @param $2 Voter ID (default: hostname)
# @return 0 on success, 1 if no vote to revoke
##
consensus_revoke() {
    local topic="$1"
    local voter="${2:-$(hostname)}"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_revoke: topic is required"
        return 1
    fi

    local vote_file
    vote_file=$(_consensus_vote_file "$topic" "$voter")

    if [[ -f "$vote_file" ]]; then
        rm -f "$vote_file"
        _consensus_log info "Revoked vote on '$topic' for voter '$voter'"
        return 0
    fi

    return 1
}

##
# @brief Reset/clear all votes for a topic
# @param $1 Topic name (required)
# @param $2 Force reset even if consensus reached (yes/no, default: no)
# @return 0 on success, 1 on error
#
# Removes all votes and result cache for the topic.
##
consensus_reset() {
    local topic="$1"
    local force="${2:-no}"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_reset: topic is required"
        return 1
    fi

    local topic_dir="$MAINFRAME_CONSENSUS_DIR/$topic"
    if [[ ! -d "$topic_dir" ]]; then
        return 0
    fi

    # Check if consensus was reached
    if [[ "$force" != "yes" && -f "$topic_dir/result" ]]; then
        _consensus_log warn "Cannot reset '$topic': consensus already reached (use force=yes)"
        return 1
    fi

    rm -rf "$topic_dir"
    _consensus_log info "Reset consensus topic '$topic'"
    return 0
}

##
# @brief List all voters who have cast votes on a topic
# @param $1 Topic name (required)
# @return Prints voter IDs, one per line
##
consensus_list_voters() {
    local topic="$1"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_list_voters: topic is required"
        return 1
    fi

    local vote_dir="$MAINFRAME_CONSENSUS_DIR/$topic/votes"
    if [[ -d "$vote_dir" ]]; then
        find "$vote_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null
    fi
}

##
# @brief List all active consensus topics
# @return Prints topic names, one per line
##
consensus_list_topics() {
    if [[ -d "$MAINFRAME_CONSENSUS_DIR" ]]; then
        find "$MAINFRAME_CONSENSUS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null
    fi
}

##
# @brief Get detailed status of a topic
# @param $1 Topic name (required)
# @param $2 Total number of voters (default: 3)
# @return Prints JSON status object
##
consensus_status() {
    local topic="$1"
    local total_voters="${2:-3}"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_status: topic is required"
        return 1
    fi

    local counts
    counts=$(consensus_count "$topic")

    local yes_count no_count abstain_count total_cast
    yes_count=$(printf '%s' "$counts" | grep -o 'yes:[0-9]*' | cut -d: -f2)
    no_count=$(printf '%s' "$counts" | grep -o 'no:[0-9]*' | cut -d: -f2)
    abstain_count=$(printf '%s' "$counts" | grep -o 'abstain:[0-9]*' | cut -d: -f2)
    total_cast=$(printf '%s' "$counts" | grep -o 'total:[0-9]*' | cut -d: -f2)

    local majority=$(( (total_voters / 2) + 1 ))
    local status="pending"
    local winner="null"

    if [[ $yes_count -ge $majority ]]; then
        status="consensus"
        winner="yes"
    elif [[ $no_count -ge $majority ]]; then
        status="consensus"
        winner="no"
    fi

    printf '{"topic":"%s","status":"%s","winner":%s,"votes":{"yes":%d,"no":%d,"abstain":%d},"total_cast":%d,"required":%d,"total_voters":%d}\n' \
        "$topic" \
        "$status" \
        "$([[ "$winner" == "null" ]] && echo "null" || echo "\"$winner\"")" \
        "${yes_count:-0}" \
        "${no_count:-0}" \
        "${abstain_count:-0}" \
        "${total_cast:-0}" \
        "$majority" \
        "$total_voters"
}

##
# @brief Get status of all topics
# @return Prints JSON array of topic statuses
##
consensus_status_all() {
    local topics=()
    local first=1

    printf '['
    while IFS= read -r topic; do
        [[ -n "$topic" ]] || continue
        [[ $first -eq 1 ]] || printf ','
        first=0
        consensus_status "$topic"
    done < <(consensus_list_topics)
    printf ']\n'
}

##
# @brief Propose a value and wait for consensus
# @param $1 Topic name (required)
# @param $2 Proposed value (required)
# @param $3 Voter ID (default: hostname)
# @param $4 Total number of voters (default: 3)
# @param $5 Timeout in seconds (default: 60)
# @return 0 if proposal accepted, 1 if rejected, 2 on timeout, 3 on error
#
# Higher-level function that proposes a value and waits for consensus.
# The proposal is a "yes" vote for the given value.
##
consensus_propose() {
    local topic="$1"
    local value="$2"
    local voter="${3:-$(hostname)}"
    local total_voters="${4:-3}"
    local timeout="${5:-60}"

    if [[ -z "$topic" || -z "$value" ]]; then
        _consensus_log error "consensus_propose: topic and value are required"
        return 3
    fi

    # Store the proposal value
    _consensus_init_topic "$topic"
    printf '%s' "$value" > "$MAINFRAME_CONSENSUS_DIR/$topic/proposal"

    # Cast vote
    local result
    result=$(consensus_vote "$topic" "yes" "$voter" "$total_voters")
    local ret=$?

    if [[ $ret -eq 0 || $ret -eq 1 ]]; then
        printf '%s\n' "$result"
        return $ret
    fi

    # Wait for consensus
    consensus_wait "$topic" "$timeout" "$total_voters"
}

##
# @brief Get the winning proposal value
# @param $1 Topic name (required)
# @return Prints the proposal value if consensus reached, empty otherwise
##
consensus_get_proposal() {
    local topic="$1"

    if [[ -z "$topic" ]]; then
        _consensus_log error "consensus_get_proposal: topic is required"
        return 1
    fi

    local proposal_file="$MAINFRAME_CONSENSUS_DIR/$topic/proposal"
    if [[ -f "$proposal_file" ]]; then
        cat "$proposal_file" 2>/dev/null
        return 0
    fi

    return 1
}

##
# @brief Cleanup consensus resources
# @param $1 Topic name (optional, if omitted cleans all topics this process participated in)
# @return 0 on success
#
# Removes vote files for this process. Should be called on exit.
##
consensus_cleanup() {
    local topic="${1:-}"
    local voter
    voter=$(hostname)

    if [[ -n "$topic" ]]; then
        # Clean specific topic
        consensus_revoke "$topic" "$voter" 2>/dev/null || true
    else
        # Clean all topics this process participated in
        for topic in "${!_CONSENSUS_TOPICS[@]}"; do
            consensus_revoke "$topic" "$voter" 2>/dev/null || true
            unset "_CONSENSUS_TOPICS[$topic]"
        done
    fi

    return 0
}

# Register cleanup on exit
if declare -F _mainframe_add_exit_trap >/dev/null 2>&1; then
    _mainframe_add_exit_trap 'consensus_cleanup 2>/dev/null || true'
else
    trap 'consensus_cleanup 2>/dev/null || true' EXIT 2>/dev/null || true
fi

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/agent_teams.sh - Claude Code Agent Teams Bridge
# =============================================================================
# Description: Bridge between Mainframe's orchestration/AWM capabilities and
#              Claude Code's experimental Agent Teams feature. Provides:
#              - Agent Teams detection (env var + config dir)
#              - Shared AWM session rendezvous (leader creates, teammates join)
#              - Team config accessors
#
# Design Principle: Bridge, don't duplicate. Agent Teams owns team lifecycle,
#                   task assignment, and mailbox messaging. Mainframe provides
#                   persistent cross-agent memory (AWM), synchronization
#                   primitives (barriers, locks), and bash-level utilities.
#
# Version: 1.0.0
# Requires: Bash 4.0+, awm.sh, agent.sh
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_AGENT_TEAMS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_AGENT_TEAMS_LOADED=1

# Source dependencies
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${SCRIPT_DIR}/awm.sh"
source "${SCRIPT_DIR}/agent.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Agent Teams environment variable (set by Claude Code when teams are active)
_AGENT_TEAMS_ENV_VAR="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"

# Base directory where Agent Teams stores team configs
_AGENT_TEAMS_CONFIG_BASE="${HOME}/.claude/teams"

# Well-known file for AWM session rendezvous
_AGENT_TEAMS_AWM_SESSION_FILE=".awm_session"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_agent_teams_log() {
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "agent_teams" "$@"
    else
        local level="$1"; shift
        [[ "${MAINFRAME_QUIET:-}" != "1" ]] && printf '[agent_teams] %s: %s\n' "$level" "$*" >&2
        :
    fi
}

# =============================================================================
# DETECTION
# =============================================================================

# @desc Check if Claude Code Agent Teams is active
# @usage agent_teams_active
# @returns 0 if active, 1 if not
# @example if agent_teams_active; then echo "Teams mode"; fi
agent_teams_active() {
    # Check env var first (fastest path)
    if [[ "${!_AGENT_TEAMS_ENV_VAR:-}" == "1" ]]; then
        return 0
    fi

    # Check for team config directory existence as fallback
    if [[ -d "$_AGENT_TEAMS_CONFIG_BASE" ]]; then
        local team_dir
        for team_dir in "$_AGENT_TEAMS_CONFIG_BASE"/*/; do
            [[ -d "$team_dir" ]] && return 0
        done
    fi

    return 1
}

# @desc Get the current team name
# @usage team=$(agent_teams_team_name)
# @returns 0 and prints team name, 1 if not in a team
# @example team=$(agent_teams_team_name)
agent_teams_team_name() {
    # Check CLAUDE_AGENT_TEAM_NAME env var (set by Agent Teams runtime)
    if [[ -n "${CLAUDE_AGENT_TEAM_NAME:-}" ]]; then
        printf '%s' "$CLAUDE_AGENT_TEAM_NAME"
        return 0
    fi

    # Fallback: find the most recently modified team directory
    if [[ -d "$_AGENT_TEAMS_CONFIG_BASE" ]]; then
        local latest_dir=""
        local latest_time=0
        local team_dir

        for team_dir in "$_AGENT_TEAMS_CONFIG_BASE"/*/; do
            [[ -d "$team_dir" ]] || continue
            local mtime
            if [[ "$OSTYPE" == darwin* ]]; then
                mtime=$(stat -f%m "$team_dir" 2>/dev/null || echo 0)
            else
                mtime=$(stat -c%Y "$team_dir" 2>/dev/null || echo 0)
            fi
            if (( mtime > latest_time )); then
                latest_time=$mtime
                latest_dir="$team_dir"
            fi
        done

        if [[ -n "$latest_dir" ]]; then
            local name="${latest_dir%/}"
            name="${name##*/}"
            printf '%s' "$name"
            return 0
        fi
    fi

    _agent_teams_log warn "agent_teams_team_name: no team detected"
    return 1
}

# @desc Get team configuration as JSON
# @usage config=$(agent_teams_config)
# @returns 0 and prints JSON, 1 if no config found
# @example config=$(agent_teams_config)
agent_teams_config() {
    local team_name
    team_name=$(agent_teams_team_name) || return 1

    local config_dir="${_AGENT_TEAMS_CONFIG_BASE}/${team_name}"

    # Look for config files in priority order
    local config_file
    for config_file in "${config_dir}/config.json" "${config_dir}/team.json"; do
        if [[ -f "$config_file" ]]; then
            cat "$config_file"
            return 0
        fi
    done

    # Return minimal config if directory exists but no config file
    if [[ -d "$config_dir" ]]; then
        printf '{"team_name":"%s","config_dir":"%s"}' \
            "$team_name" "$config_dir"
        return 0
    fi

    _agent_teams_log warn "agent_teams_config: no config found for team '$team_name'"
    return 1
}

# =============================================================================
# AWM SESSION RENDEZVOUS
# =============================================================================
# The rendezvous problem: teammates need to find and join a shared AWM session.
# Solution: the team lead creates the session and writes the session ID to a
# well-known path. Teammates read the session ID from that path and join.
#
# Well-known path: ~/.claude/teams/{team_name}/.awm_session
# =============================================================================

# @desc Initialize a shared AWM session for the team (call from lead agent)
# @usage agent_teams_awm_init ["session_name"]
# @returns 0 and prints session_id, 1 on failure
# @note Sets _AWM_SESSION_ID and AWM namespace internally. If called in a
#       subshell (e.g., sid=$(agent_teams_awm_init)), you must also run
#       awm_team_namespace && awm_resume "$sid" in the parent shell.
#       Prefer calling without capture: agent_teams_awm_init "name"
#       then use agent_teams_awm_session_id to get the ID.
# @example agent_teams_awm_init "deploy-task"
# @example sid=$(agent_teams_awm_session_id)
agent_teams_awm_init() {
    local session_name="${1:-team-session}"
    local team_name

    team_name=$(agent_teams_team_name) || {
        _agent_teams_log error "agent_teams_awm_init: not in a team"
        return 1
    }

    # Set AWM namespace to team-{name} for isolation
    awm_team_namespace

    # Create AWM session
    local session_id
    session_id=$(awm_init "$session_name") || {
        _agent_teams_log error "agent_teams_awm_init: awm_init failed"
        return 1
    }

    # awm_init sets _AWM_SESSION_ID in its subshell; propagate here
    _AWM_SESSION_ID="$session_id"

    # Write session ID to well-known rendezvous path
    local team_dir="${_AGENT_TEAMS_CONFIG_BASE}/${team_name}"
    mkdir -p "$team_dir" 2>/dev/null

    local rendezvous_file="${team_dir}/${_AGENT_TEAMS_AWM_SESSION_FILE}"
    printf '%s' "$session_id" > "$rendezvous_file" || {
        _agent_teams_log error "agent_teams_awm_init: failed to write rendezvous file"
        return 1
    }

    _agent_teams_log info "created shared AWM session '$session_id' for team '$team_name'"
    printf '%s' "$session_id"
}

# @desc Join the team's shared AWM session (call from teammate agents)
# @usage agent_teams_awm_join
# @returns 0 on success, 1 if no session found
# @example agent_teams_awm_join && echo "joined"
agent_teams_awm_join() {
    local team_name

    team_name=$(agent_teams_team_name) || {
        _agent_teams_log error "agent_teams_awm_join: not in a team"
        return 1
    }

    local session_id
    session_id=$(agent_teams_awm_session_id) || {
        _agent_teams_log error "agent_teams_awm_join: no shared session found"
        return 1
    }

    # Set namespace to match the lead
    awm_team_namespace

    # Resume the shared session
    awm_resume "$session_id" || {
        _agent_teams_log error "agent_teams_awm_join: failed to resume session '$session_id'"
        return 1
    }

    _agent_teams_log info "joined shared AWM session '$session_id' for team '$team_name'"
    return 0
}

# @desc Get the team's shared AWM session ID
# @usage sid=$(agent_teams_awm_session_id)
# @returns 0 and prints session_id, 1 if none
# @example sid=$(agent_teams_awm_session_id)
agent_teams_awm_session_id() {
    local team_name

    team_name=$(agent_teams_team_name) || return 1

    local rendezvous_file="${_AGENT_TEAMS_CONFIG_BASE}/${team_name}/${_AGENT_TEAMS_AWM_SESSION_FILE}"

    if [[ -f "$rendezvous_file" ]]; then
        local sid
        sid=$(<"$rendezvous_file")
        if [[ -n "$sid" ]]; then
            printf '%s' "$sid"
            return 0
        fi
    fi

    return 1
}

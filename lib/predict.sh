#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/predict.sh - Command Execution Prediction Engine
# =============================================================================
# Description: Predicts resource usage, risk levels, success probability, and
#              execution duration for shell commands. Uses command profiling,
#              pattern analysis, and historical data from temporal.sh.
#
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PREDICT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PREDICT_LOADED=1

# =============================================================================
# DEPENDENCY LOADING
# =============================================================================

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"

# Source required libraries (if not already loaded)
[[ -z "${_MAINFRAME_JSON_LOADED:-}" ]] && source "${SCRIPT_DIR}/json.sh"
[[ -z "${_MAINFRAME_OUTPUT_LOADED:-}" ]] && source "${SCRIPT_DIR}/output.sh"
[[ -z "${_MAINFRAME_TEMPORAL_LOADED:-}" ]] && source "${SCRIPT_DIR}/temporal.sh"
[[ -z "${_MAINFRAME_RISK_LOADED:-}" ]] && source "${SCRIPT_DIR}/risk.sh"

# =============================================================================
# COMMAND PROFILES
# =============================================================================

# Built-in associative array of command profiles
# Format: time_seconds, memory_mb, cpu_percent, scalable, io_heavy, network_heavy
declare -gA _PREDICT_PROFILES
case "${BASH_VERSION:-}" in
    4.*|5.*)
        _PREDICT_PROFILES=(
            # Read-only / Informational (low resource usage)
            ["ls"]='{"time":0.01,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["cat"]='{"time":0.05,"memory":5,"cpu":10,"scalable":true,"io":"medium","network":false}'
            ["head"]='{"time":0.01,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["tail"]='{"time":0.01,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["grep"]='{"time":0.1,"memory":10,"cpu":30,"scalable":true,"io":"medium","network":false}'
            ["awk"]='{"time":0.1,"memory":5,"cpu":20,"scalable":true,"io":"medium","network":false}'
            ["sed"]='{"time":0.1,"memory":5,"cpu":20,"scalable":true,"io":"medium","network":false}'
            ["wc"]='{"time":0.05,"memory":1,"cpu":10,"scalable":true,"io":"low","network":false}'
            ["sort"]='{"time":0.5,"memory":50,"cpu":40,"scalable":true,"io":"high","network":false}'
            ["uniq"]='{"time":0.1,"memory":10,"cpu":20,"scalable":true,"io":"medium","network":false}'
            ["diff"]='{"time":0.1,"memory":10,"cpu":20,"scalable":true,"io":"medium","network":false}'
            ["file"]='{"time":0.05,"memory":2,"cpu":10,"scalable":false,"io":"low","network":false}'
            ["stat"]='{"time":0.01,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["echo"]='{"time":0.001,"memory":1,"cpu":1,"scalable":false,"io":"none","network":false}'
            ["printf"]='{"time":0.001,"memory":1,"cpu":1,"scalable":false,"io":"none","network":false}'
            ["pwd"]='{"time":0.001,"memory":1,"cpu":1,"scalable":false,"io":"none","network":false}'
            ["whoami"]='{"time":0.01,"memory":1,"cpu":5,"scalable":false,"io":"none","network":false}'
            ["date"]='{"time":0.01,"memory":1,"cpu":5,"scalable":false,"io":"none","network":false}'
            ["which"]='{"time":0.01,"memory":2,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["test"]='{"time":0.001,"memory":1,"cpu":1,"scalable":false,"io":"none","network":false}'
            ["true"]='{"time":0.001,"memory":1,"cpu":1,"scalable":false,"io":"none","network":false}'
            ["false"]='{"time":0.001,"memory":1,"cpu":1,"scalable":false,"io":"none","network":false}'

            # File operations (medium resource usage)
            ["cp"]='{"time":0.5,"memory":5,"cpu":15,"scalable":true,"io":"high","network":false}'
            ["mv"]='{"time":0.1,"memory":5,"cpu":10,"scalable":false,"io":"medium","network":false}'
            ["rm"]='{"time":0.1,"memory":1,"cpu":10,"scalable":true,"io":"medium","network":false}'
            ["mkdir"]='{"time":0.05,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["rmdir"]='{"time":0.05,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["touch"]='{"time":0.05,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["ln"]='{"time":0.05,"memory":1,"cpu":5,"scalable":false,"io":"low","network":false}'
            ["chmod"]='{"time":0.1,"memory":1,"cpu":10,"scalable":true,"io":"medium","network":false}'
            ["chown"]='{"time":0.1,"memory":1,"cpu":10,"scalable":true,"io":"medium","network":false}'
            ["dd"]='{"time":10.0,"memory":10,"cpu":30,"scalable":true,"io":"critical","network":false}'

            # Search and traversal (scalable with path size)
            ["find"]='{"time":1.0,"memory":20,"cpu":50,"scalable":true,"io":"high","network":false}'
            ["locate"]='{"time":0.1,"memory":5,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["updatedb"]='{"time":30.0,"memory":50,"cpu":60,"scalable":true,"io":"critical","network":false}'

            # Archive operations
            ["tar"]='{"time":5.0,"memory":20,"cpu":40,"scalable":true,"io":"critical","network":false}'
            ["gzip"]='{"time":2.0,"memory":10,"cpu":60,"scalable":true,"io":"high","network":false}'
            ["gunzip"]='{"time":1.0,"memory":10,"cpu":50,"scalable":true,"io":"high","network":false}'
            ["zip"]='{"time":3.0,"memory":20,"cpu":50,"scalable":true,"io":"high","network":false}'
            ["unzip"]='{"time":2.0,"memory":20,"cpu":40,"scalable":true,"io":"high","network":false}'
            ["bzip2"]='{"time":5.0,"memory":15,"cpu":80,"scalable":true,"io":"high","network":false}'
            ["xz"]='{"time":10.0,"memory":50,"cpu":90,"scalable":true,"io":"high","network":false}'

            # Version control
            ["git"]='{"time":0.5,"memory":30,"cpu":30,"scalable":true,"io":"medium","network":false}'
            ["git clone"]='{"time":30.0,"memory":50,"cpu":40,"scalable":true,"io":"medium","network":true}'
            ["git push"]='{"time":5.0,"memory":30,"cpu":30,"scalable":true,"io":"low","network":true}'
            ["git pull"]='{"time":10.0,"memory":30,"cpu":30,"scalable":true,"io":"low","network":true}'
            ["git fetch"]='{"time":5.0,"memory":30,"cpu":30,"scalable":true,"io":"low","network":true}'
            ["git status"]='{"time":0.5,"memory":20,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["git log"]='{"time":0.5,"memory":20,"cpu":20,"scalable":true,"io":"low","network":false}'
            ["svn"]='{"time":5.0,"memory":40,"cpu":30,"scalable":true,"io":"medium","network":true}'
            ["hg"]='{"time":5.0,"memory":40,"cpu":30,"scalable":true,"io":"medium","network":true}'

            # Build systems
            ["make"]='{"time":60.0,"memory":100,"cpu":80,"scalable":true,"io":"high","network":false}'
            ["cmake"]='{"time":10.0,"memory":100,"cpu":60,"scalable":true,"io":"medium","network":false}'
            ["ninja"]='{"time":30.0,"memory":100,"cpu":80,"scalable":true,"io":"high","network":false}'
            ["gcc"]='{"time":5.0,"memory":200,"cpu":80,"scalable":true,"io":"medium","network":false}'
            ["g++"]='{"time":10.0,"memory":300,"cpu":80,"scalable":true,"io":"medium","network":false}'
            ["clang"]='{"time":5.0,"memory":200,"cpu":80,"scalable":true,"io":"medium","network":false}'
            ["cargo"]='{"time":60.0,"memory":500,"cpu":80,"scalable":true,"io":"high","network":true}'
            ["cargo build"]='{"time":120.0,"memory":500,"cpu":80,"scalable":true,"io":"high","network":false}'
            ["cargo test"]='{"time":60.0,"memory":500,"cpu":80,"scalable":true,"io":"medium","network":false}'
            ["go"]='{"time":10.0,"memory":100,"cpu":60,"scalable":true,"io":"medium","network":true}'
            ["go build"]='{"time":15.0,"memory":150,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["go test"]='{"time":30.0,"memory":200,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["javac"]='{"time":5.0,"memory":300,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["java"]='{"time":2.0,"memory":256,"cpu":50,"scalable":false,"io":"low","network":false}'
            ["python"]='{"time":0.5,"memory":50,"cpu":30,"scalable":true,"io":"medium","network":false}'
            ["python3"]='{"time":0.5,"memory":50,"cpu":30,"scalable":true,"io":"medium","network":false}'
            ["node"]='{"time":0.5,"memory":100,"cpu":30,"scalable":true,"io":"medium","network":false}'
            ["npm"]='{"time":10.0,"memory":200,"cpu":50,"scalable":true,"io":"medium","network":true}'
            ["npm install"]='{"time":60.0,"memory":300,"cpu":60,"scalable":true,"io":"medium","network":true}'
            ["npm test"]='{"time":30.0,"memory":200,"cpu":80,"scalable":true,"io":"medium","network":false}'
            ["npm run build"]='{"time":45.0,"memory":300,"cpu":80,"scalable":true,"io":"medium","network":false}'
            ["yarn"]='{"time":15.0,"memory":200,"cpu":50,"scalable":true,"io":"medium","network":true}'
            ["pnpm"]='{"time":10.0,"memory":150,"cpu":50,"scalable":true,"io":"medium","network":true}'
            ["bun"]='{"time":5.0,"memory":100,"cpu":50,"scalable":true,"io":"medium","network":true}'
            ["pip"]='{"time":15.0,"memory":100,"cpu":40,"scalable":true,"io":"medium","network":true}'
            ["pip install"]='{"time":30.0,"memory":150,"cpu":50,"scalable":true,"io":"medium","network":true}'
            ["bundle"]='{"time":30.0,"memory":200,"cpu":60,"scalable":true,"io":"medium","network":true}'
            ["gem"]='{"time":15.0,"memory":100,"cpu":40,"scalable":true,"io":"medium","network":true}'
            ["gradle"]='{"time":120.0,"memory":512,"cpu":80,"scalable":true,"io":"high","network":true}'
            ["mvn"]='{"time":180.0,"memory":512,"cpu":80,"scalable":true,"io":"high","network":true}'
            ["ant"]='{"time":60.0,"memory":256,"cpu":70,"scalable":true,"io":"high","network":false}'
            ["sbt"]='{"time":120.0,"memory":1024,"cpu":80,"scalable":true,"io":"high","network":true}'

            # Container operations
            ["docker"]='{"time":5.0,"memory":50,"cpu":30,"scalable":true,"io":"medium","network":true}'
            ["docker build"]='{"time":60.0,"memory":200,"cpu":70,"scalable":true,"io":"high","network":true}'
            ["docker run"]='{"time":3.0,"memory":100,"cpu":40,"scalable":false,"io":"medium","network":true}'
            ["docker-compose"]='{"time":10.0,"memory":100,"cpu":40,"scalable":true,"io":"medium","network":true}'
            ["docker compose"]='{"time":10.0,"memory":100,"cpu":40,"scalable":true,"io":"medium","network":true}'
            ["kubectl"]='{"time":2.0,"memory":50,"cpu":30,"scalable":true,"io":"low","network":true}'
            ["helm"]='{"time":5.0,"memory":50,"cpu":30,"scalable":true,"io":"low","network":true}'
            ["podman"]='{"time":5.0,"memory":50,"cpu":30,"scalable":true,"io":"medium","network":true}'

            # System operations
            ["sudo"]='{"time":0.1,"memory":5,"cpu":10,"scalable":false,"io":"low","network":false}'
            ["su"]='{"time":0.5,"memory":10,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["ssh"]='{"time":2.0,"memory":20,"cpu":20,"scalable":false,"io":"low","network":true}'
            ["scp"]='{"time":10.0,"memory":20,"cpu":30,"scalable":true,"io":"medium","network":true}'
            ["rsync"]='{"time":30.0,"memory":50,"cpu":40,"scalable":true,"io":"high","network":true}'
            ["curl"]='{"time":5.0,"memory":20,"cpu":20,"scalable":true,"io":"low","network":true}'
            ["wget"]='{"time":10.0,"memory":20,"cpu":20,"scalable":true,"io":"low","network":true}'
            ["ping"]='{"time":5.0,"memory":5,"cpu":10,"scalable":false,"io":"none","network":true}'
            ["netstat"]='{"time":0.5,"memory":10,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["lsof"]='{"time":1.0,"memory":20,"cpu":30,"scalable":false,"io":"medium","network":false}'
            ["ps"]='{"time":0.1,"memory":5,"cpu":10,"scalable":false,"io":"low","network":false}'
            ["top"]='{"time":1.0,"memory":10,"cpu":20,"scalable":false,"io":"medium","network":false}'
            ["htop"]='{"time":1.0,"memory":20,"cpu":30,"scalable":false,"io":"medium","network":false}'
            ["kill"]='{"time":0.01,"memory":1,"cpu":5,"scalable":false,"io":"none","network":false}'
            ["killall"]='{"time":0.1,"memory":5,"cpu":10,"scalable":false,"io":"low","network":false}'
            ["systemctl"]='{"time":1.0,"memory":10,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["service"]='{"time":1.0,"memory":10,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["mount"]='{"time":0.5,"memory":5,"cpu":10,"scalable":false,"io":"medium","network":false}'
            ["umount"]='{"time":0.5,"memory":5,"cpu":10,"scalable":false,"io":"medium","network":false}'
            ["fdisk"]='{"time":1.0,"memory":5,"cpu":10,"scalable":false,"io":"medium","network":false}'
            ["mkfs"]='{"time":30.0,"memory":10,"cpu":30,"scalable":true,"io":"critical","network":false}'
            ["fsck"]='{"time":60.0,"memory":20,"cpu":40,"scalable":true,"io":"critical","network":false}'

            # Database operations
            ["mysql"]='{"time":1.0,"memory":50,"cpu":30,"scalable":true,"io":"medium","network":true}'
            ["mysqldump"]='{"time":30.0,"memory":100,"cpu":50,"scalable":true,"io":"high","network":true}'
            ["psql"]='{"time":1.0,"memory":40,"cpu":30,"scalable":true,"io":"medium","network":true}'
            ["pg_dump"]='{"time":30.0,"memory":100,"cpu":50,"scalable":true,"io":"high","network":true}'
            ["mongo"]='{"time":1.0,"memory":100,"cpu":30,"scalable":true,"io":"medium","network":true}'
            ["redis-cli"]='{"time":0.1,"memory":10,"cpu":10,"scalable":false,"io":"low","network":true}'
            ["sqlite3"]='{"time":0.5,"memory":20,"cpu":20,"scalable":true,"io":"medium","network":false}'

            # Test runners
            ["pytest"]='{"time":30.0,"memory":200,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["jest"]='{"time":30.0,"memory":300,"cpu":80,"scalable":true,"io":"medium","network":false}'
            ["mocha"]='{"time":30.0,"memory":250,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["ava"]='{"time":20.0,"memory":200,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["jasmine"]='{"time":25.0,"memory":200,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["vitest"]='{"time":15.0,"memory":200,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["tap"]='{"time":20.0,"memory":150,"cpu":60,"scalable":true,"io":"medium","network":false}'
            ["karma"]='{"time":60.0,"memory":300,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["cypress"]='{"time":120.0,"memory":500,"cpu":80,"scalable":true,"io":"high","network":true}'
            ["playwright"]='{"time":90.0,"memory":400,"cpu":80,"scalable":true,"io":"high","network":true}'
            ["selenium"]='{"time":60.0,"memory":400,"cpu":70,"scalable":true,"io":"high","network":true}'

            # Linting and formatting
            ["eslint"]='{"time":10.0,"memory":200,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["prettier"]='{"time":5.0,"memory":100,"cpu":60,"scalable":true,"io":"medium","network":false}'
            ["black"]='{"time":5.0,"memory":100,"cpu":60,"scalable":true,"io":"medium","network":false}'
            ["flake8"]='{"time":5.0,"memory":100,"cpu":60,"scalable":true,"io":"medium","network":false}'
            ["pylint"]='{"time":10.0,"memory":150,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["mypy"]='{"time":15.0,"memory":200,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["rubocop"]='{"time":15.0,"memory":150,"cpu":70,"scalable":true,"io":"medium","network":false}'
            ["shellcheck"]='{"time":5.0,"memory":50,"cpu":50,"scalable":true,"io":"medium","network":false}'
            ["hadolint"]='{"time":3.0,"memory":50,"cpu":40,"scalable":true,"io":"medium","network":false}'

            # Documentation
            ["man"]='{"time":0.5,"memory":10,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["info"]='{"time":0.5,"memory":10,"cpu":20,"scalable":false,"io":"low","network":false}'
            ["pandoc"]='{"time":5.0,"memory":100,"cpu":60,"scalable":true,"io":"medium","network":false}'

            # Editors
            ["vim"]='{"time":0.5,"memory":50,"cpu":20,"scalable":false,"io":"medium","network":false}'
            ["nvim"]='{"time":0.5,"memory":50,"cpu":20,"scalable":false,"io":"medium","network":false}'
            ["emacs"]='{"time":1.0,"memory":100,"cpu":30,"scalable":false,"io":"medium","network":false}'
            ["nano"]='{"time":0.5,"memory":20,"cpu":10,"scalable":false,"io":"medium","network":false}'
            ["code"]='{"time":2.0,"memory":300,"cpu":50,"scalable":false,"io":"high","network":false}'
        )
        ;;
esac

# =============================================================================
# RISK PATTERNS
# =============================================================================

# Patterns that indicate critical risk
declare -gA _PREDICT_CRITICAL_PATTERNS
declare -gA _PREDICT_HIGH_PATTERNS
declare -gA _PREDICT_MEDIUM_PATTERNS

case "${BASH_VERSION:-}" in
    4.*|5.*)
        _PREDICT_CRITICAL_PATTERNS=(
            ["rm -rf /"]='Destructive system wipe'
            ["rm -rf /*"]='Destructive system wipe'
            ["rm -rf ~"]='Home directory deletion'
            [":(){ :|:& };:"]='Fork bomb'
            ["mkfs"]='Filesystem format'
            ["dd if="]='Direct disk write'
            ["> /dev/sda"]='Direct disk overwrite'
            ["format"]='Disk format operation'
        )

        _PREDICT_HIGH_PATTERNS=(
            ["rm -rf"]='Recursive deletion'
            ["rm -r"]='Recursive deletion'
            ["mv *"]='Bulk move operation'
            ["chmod -R"]='Recursive permission change'
            ["chown -R"]='Recursive ownership change'
            ["sudo"]='Elevated privileges'
            ["su -"]='Switch user root'
            ["drop database"]='Database destruction'
            ["drop table"]='Table destruction'
            ["DELETE FROM"]='Data deletion'
            ["docker system prune"]='Docker cleanup'
            ["docker volume rm"]='Volume deletion'
            ["kubectl delete"]='Kubernetes resource deletion'
        )

        _PREDICT_MEDIUM_PATTERNS=(
            ["npm install"]='Package installation'
            ["pip install"]='Package installation'
            ["bundle install"]='Package installation'
            ["find"]='Filesystem traversal'
            ["xargs"]='Command batch execution'
            ["exec"]='Process replacement'
            ["eval"]='Dynamic code execution'
            ["source"]='Script sourcing'
            [". "]='Script sourcing'
            ["curl | bash"]='Remote code execution'
            ["wget | bash"]='Remote code execution'
        )
        ;;
esac

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging helper
_predict_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "predict" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" && "${MAINFRAME_DEBUG:-}" == "1" ]]; then
        printf '[predict] %s: %s\n' "$level" "$*" >&2
    fi
}

# Get base command from full command string
_predict_base_cmd() {
    local cmd="$1"
    # Remove leading whitespace
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    # Get first word
    printf '%s' "${cmd%% *}"
}

# Get first two words (for compound commands like "git clone")
_predict_compound_cmd() {
    local cmd="$1"
    # Remove leading whitespace
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    # Get first two words
    local first="${cmd%% *}"
    local rest="${cmd#* }"
    local second="${rest%% *}"
    if [[ "$first" != "$rest" && -n "$second" ]]; then
        printf '%s %s' "$first" "$second"
    else
        printf '%s' "$first"
    fi
}

# Check if command contains any pattern from an associative array
_predict_matches_pattern() {
    local cmd="$1"
    local -n patterns=$2
    local pattern
    for pattern in "${!patterns[@]}"; do
        # For critical destructive patterns targeting root filesystem
        if [[ "$pattern" == "rm -rf /" || "$pattern" == "rm -rf /*" ]]; then
            # Must be exact match or followed by space (to avoid matching /home, /tmp, etc)
            if [[ "$cmd" == "$pattern" || "$cmd" == "$pattern "* ]]; then
                printf '%s' "$pattern"
                return 0
            fi
        else
            # Regular substring match for other patterns
            if [[ "$cmd" == *"$pattern"* ]]; then
                printf '%s' "$pattern"
                return 0
            fi
        fi
    done
    return 1
}

# Get profile for a command (handles base command and compound commands)
_predict_get_profile() {
    local cmd="$1"
    local base_cmd=$(_predict_base_cmd "$cmd")
    local compound_cmd=$(_predict_compound_cmd "$cmd")
    local profile=""

    # Try compound command first (e.g., "git clone")
    if [[ -n "${_PREDICT_PROFILES[$compound_cmd]:-}" ]]; then
        profile="${_PREDICT_PROFILES[$compound_cmd]}"
    # Fall back to base command
    elif [[ -n "${_PREDICT_PROFILES[$base_cmd]:-}" ]]; then
        profile="${_PREDICT_PROFILES[$base_cmd]}"
    else
        # Unknown command - return default profile
        profile='{"time":1.0,"memory":50,"cpu":40,"scalable":false,"io":"medium","network":false}'
    fi

    printf '%s' "$profile"
}

# Adjust profile based on command arguments
_predict_adjust_profile() {
    local cmd="$1"
    local profile="$2"

    local time_val memory_val cpu_val scalable
    # Extract base values (simple parsing)
    if [[ "$profile" =~ \"time\":([0-9.]+) ]]; then
        time_val="${BASH_REMATCH[1]}"
    else
        time_val=1.0
    fi
    if [[ "$profile" =~ \"memory\":([0-9]+) ]]; then
        memory_val="${BASH_REMATCH[1]}"
    else
        memory_val=50
    fi
    if [[ "$profile" =~ \"cpu\":([0-9]+) ]]; then
        cpu_val="${BASH_REMATCH[1]}"
    else
        cpu_val=40
    fi
    if [[ "$profile" == *"\"scalable\":true"* ]]; then
        scalable="true"
    else
        scalable="false"
    fi

    # Adjust based on patterns
    local multiplier=1.0

    # Large directory traversal for find
    if [[ "$cmd" == "find"* ]]; then
        if [[ "$cmd" == *" /"* || "$cmd" == *" /home"* ]]; then
            multiplier="10.0"
        elif [[ "$cmd" == *" ."* || "$cmd" == *" ./"* ]]; then
            multiplier="1.0"
        elif [[ "$cmd" == *"/"* ]]; then
            multiplier="5.0"
        fi
        # Name search is faster than content search
        if [[ "$cmd" == *"-exec"* || "$cmd" == *"-ok"* ]]; then
            multiplier=$(echo "$multiplier * 3" | bc 2>/dev/null || printf '%s' "$multiplier")
        fi
    fi

    # Large file operations
    if [[ "$cmd" == "cat"* || "$cmd" == "sort"* || "$cmd" == "grep"* ]]; then
        if [[ "$cmd" == *".log"* || "$cmd" == *"*.txt"* ]]; then
            multiplier="2.0"
        fi
        if [[ "$cmd" == *"*"* ]]; then
            # Wildcard patterns
            multiplier=$(echo "$multiplier * 2" | bc 2>/dev/null || printf '%s' "$multiplier")
        fi
    fi

    # Recursive operations
    if [[ "$cmd" == *" -r "* || "$cmd" == *" -R "* || "$cmd" == *" --recursive"* ]]; then
        multiplier=$(echo "$multiplier * 5" | bc 2>/dev/null || printf '%s' "$multiplier")
    fi

    # Parallel operations
    if [[ "$cmd" == *" -P "* || "$cmd" == *" --parallel"* ]]; then
        # Parallel is faster but uses more CPU/memory
        time_val=$(echo "$time_val * 0.3" | bc 2>/dev/null || printf '%s' "$time_val")
        cpu_val=$((cpu_val * 3))
        [[ $cpu_val -gt 100 ]] && cpu_val=100
    fi

    # Calculate adjusted time
    local adjusted_time
    adjusted_time=$(echo "$time_val * $multiplier" | bc 2>/dev/null || printf '%s' "$time_val")

    # Format output
    printf '{"time":%.3f,"memory":%d,"cpu":%d,"scalable":%s}' "$adjusted_time" "$memory_val" "$cpu_val" "$scalable"
}

# Convert risk score to category
_predict_score_to_category() {
    local score="$1"
    if [[ $score -ge 8 ]]; then
        printf 'critical'
    elif [[ $score -ge 6 ]]; then
        printf 'high'
    elif [[ $score -ge 3 ]]; then
        printf 'medium'
    else
        printf 'low'
    fi
}

# Calculate disk usage estimate
_predict_disk_usage() {
    local cmd="$1"
    local base_cmd=$(_predict_base_cmd "$cmd")

    case "$base_cmd" in
        cp|mv|tar|zip|gzip)
            # High disk usage for archive/copy operations
            printf 'high'
            ;;
        npm|pip|yarn|pnpm|bundle)
            # Package managers download to disk
            printf 'medium'
            ;;
        docker)
            # Container operations
            printf 'medium'
            ;;
        find|grep|ls)
            # Read operations
            printf 'low'
            ;;
        rm)
            # Deletion frees space
            printf 'negative'
            ;;
        *)
            printf 'low'
            ;;
    esac
}

# =============================================================================
# PREDICTION FUNCTIONS
# =============================================================================

# Predict resource requirements for a command
# Usage: predict_resources "$command"
# Returns: USOP JSON with time_seconds, memory_mb, cpu_percent, disk_usage, confidence
predict_resources() {
    local cmd="$1"
    [[ -z "$cmd" ]] && {
        output_error "E_ARG_MISSING" "Command required for prediction"
        return 1
    }

    output_timer_start

    local base_cmd=$(_predict_base_cmd "$cmd")
    local profile=$(_predict_get_profile "$cmd")
    profile=$(_predict_adjust_profile "$cmd" "$profile")

    # Parse adjusted profile
    local time_val memory_val cpu_val scalable
    if [[ "$profile" =~ \"time\":([0-9.]+) ]]; then
        time_val="${BASH_REMATCH[1]}"
    else
        time_val=1.0
    fi
    if [[ "$profile" =~ \"memory\":([0-9]+) ]]; then
        memory_val="${BASH_REMATCH[1]}"
    else
        memory_val=50
    fi
    if [[ "$profile" =~ \"cpu\":([0-9]+) ]]; then
        cpu_val="${BASH_REMATCH[1]}"
    else
        cpu_val=40
    fi
    if [[ "$profile" == *"\"scalable\":true"* ]]; then
        scalable="true"
    else
        scalable="false"
    fi

    # Get historical data if available
    local historical_time=0
    local historical_count=0
    local confidence="medium"

    if [[ -n "${_MAINFRAME_TEMPORAL_LOADED:-}" ]]; then
        local hist_result
        hist_result=$(temporal_predict_duration "$cmd" 2>/dev/null)
        if [[ "$hist_result" == *'"predicted_ms"'* ]]; then
            if [[ "$hist_result" =~ \"predicted_ms\":([0-9]+) ]]; then
                historical_time=$(echo "${BASH_REMATCH[1]} / 1000" | bc 2>/dev/null || echo "0")
                historical_time=${historical_time%.*}
            fi
            if [[ "$hist_result" =~ \"based_on\":([0-9]+) ]]; then
                historical_count="${BASH_REMATCH[1]}"
            fi
        fi
    fi

    # Blend with historical data if available
    if [[ $historical_count -gt 3 ]]; then
        # Weighted average: 70% historical, 30% profile
        time_val=$(echo "scale=3; ($historical_time * 0.7) + ($time_val * 0.3)" | bc 2>/dev/null || printf '%s' "$time_val")
        if [[ $historical_count -ge 10 ]]; then
            confidence="high"
        fi
    else
        confidence="medium"
    fi

    # Check for unknown command
    if [[ -z "${_PREDICT_PROFILES[$base_cmd]:-}" ]]; then
        confidence="low"
    fi

    # Get disk usage estimate
    local disk_usage
    disk_usage=$(_predict_disk_usage "$cmd")

    # Build JSON response
    local json="{"
    json+="\"command\":\"$(printf '%s' "$cmd" | sed 's/"/\\"/g')\","
    json+="\"time_seconds\":$time_val,"
    json+="\"memory_mb\":$memory_val,"
    json+="\"cpu_percent\":$cpu_val,"
    json+="\"scalable\":$scalable,"
    json+="\"disk_usage\":\"$disk_usage\","
    json+="\"confidence\":\"$confidence\","
    json+="\"historical_samples\":$historical_count"
    json+="}"

    output_success "$json" "resource_prediction"
}

# Assess risk level for a command
# Usage: predict_risk "$command"
# Returns: USOP JSON with risk_category, risk_score, reasons
predict_risk() {
    local cmd="$1"
    [[ -z "$cmd" ]] && {
        output_error "E_ARG_MISSING" "Command required for risk assessment"
        return 1
    }

    output_timer_start

    local risk_score=0
    local -a reasons=()
    local matched_pattern=""

    # Check for critical patterns first (highest priority)
    matched_pattern=$(_predict_matches_pattern "$cmd" _PREDICT_CRITICAL_PATTERNS)
    if [[ -n "$matched_pattern" ]]; then
        risk_score=10
        reasons+=("Critical pattern detected: ${_PREDICT_CRITICAL_PATTERNS[$matched_pattern]}")
    else
        # Check for high patterns
        matched_pattern=$(_predict_matches_pattern "$cmd" _PREDICT_HIGH_PATTERNS)
        if [[ -n "$matched_pattern" ]]; then
            risk_score=6
            reasons+=("High risk pattern: ${_PREDICT_HIGH_PATTERNS[$matched_pattern]}")
        else
            # Check for medium patterns
            matched_pattern=$(_predict_matches_pattern "$cmd" _PREDICT_MEDIUM_PATTERNS)
            if [[ -n "$matched_pattern" ]]; then
                risk_score=3
                reasons+=("Medium risk pattern: ${_PREDICT_MEDIUM_PATTERNS[$matched_pattern]}")
            fi
        fi

        # Also check risk.sh if available (for unknown commands)
        if [[ -n "${_MAINFRAME_RISK_LOADED:-}" ]] && declare -F mainframe_risk_assess &>/dev/null && [[ $risk_score -eq 0 ]]; then
            local risk_result
            risk_result=$(mainframe_risk_assess "$cmd" 2>/dev/null)
            if [[ "$risk_result" =~ \"score\":([0-9]+) ]]; then
                local risk_sh_score="${BASH_REMATCH[1]}"
                # Use risk.sh score only if we have no pattern match
                if [[ $risk_sh_score -gt $risk_score ]]; then
                    risk_score=$risk_sh_score
                    reasons+=("Risk assessment module detected concerns")
                fi
            fi
        fi

        # Additional modifiers
            local base_cmd=$(_predict_base_cmd "$cmd")

            # Sudo/su escalation
            if [[ "$base_cmd" == "sudo" || "$base_cmd" == "su" ]]; then
                risk_score=$((risk_score + 2))
                reasons+=("Privilege escalation detected")
            fi

            # Network operations
            if [[ "$cmd" == *"curl"* || "$cmd" == *"wget"* || "$cmd" == *"scp"* ]]; then
                if [[ "$cmd" == *"http"* ]] && [[ "$cmd" != *"https"* ]]; then
                    risk_score=$((risk_score + 1))
                    reasons+=("Unencrypted network connection")
                fi
            fi

            # Wildcard operations
            if [[ "$cmd" == *" *"* || "$cmd" == *"* "* ]]; then
                risk_score=$((risk_score + 1))
                reasons+=("Wildcard pattern detected")
            fi

            # Force flag
            if [[ "$cmd" == *" -f "* || "$cmd" == *" --force"* ]]; then
                risk_score=$((risk_score + 1))
                reasons+=("Force flag detected")
            fi

        # Clamp to 0-10
        [[ $risk_score -lt 0 ]] && risk_score=0
        [[ $risk_score -gt 10 ]] && risk_score=10
    fi

    # Determine category
    local category
    category=$(_predict_score_to_category "$risk_score")

    # Build reasons array
    local reasons_json="["
    local first=true
    for reason in "${reasons[@]}"; do
        $first || reasons_json+=","
        first=false
        reasons_json+="\"$(printf '%s' "$reason" | sed 's/"/\\"/g')\""
    done
    reasons_json+="]"

    # Build JSON response
    local json="{"
    json+="\"command\":\"$(printf '%s' "$cmd" | sed 's/"/\\"/g')\","
    json+="\"risk_category\":\"$category\","
    json+="\"risk_score\":$risk_score,"
    json+="\"reasons\":$reasons_json,"
    json+="\"requires_confirmation\":$([[ $risk_score -ge ${MAINFRAME_RISK_CONFIRM_THRESHOLD:-5} ]] && printf 'true' || printf 'false'),"
    json+="\"blocked\":$([[ $risk_score -ge ${MAINFRAME_RISK_THRESHOLD:-6} ]] && printf 'true' || printf 'false')"
    json+="}"

    output_success "$json" "risk_assessment"
}

# Predict success probability for a command
# Usage: predict_success "$command"
# Returns: USOP JSON with probability (0-1), confidence, factors
predict_success() {
    local cmd="$1"
    [[ -z "$cmd" ]] && {
        output_error "E_ARG_MISSING" "Command required for success prediction"
        return 1
    }

    output_timer_start

    local base_cmd=$(_predict_base_cmd "$cmd")
    local probability=0.85  # Default optimistic probability
    local confidence="medium"
    local -a factors=("Base success rate for known commands")

    # Get historical success rate from temporal.sh
    local historical_prob=0
    local historical_count=0

    if [[ -n "${_MAINFRAME_TEMPORAL_LOADED:-}" ]]; then
        local hist_result
        hist_result=$(temporal_predict_success "$cmd" 2>/dev/null)
        if [[ "$hist_result" == *'"success_probability"'* ]]; then
            if [[ "$hist_result" =~ \"success_probability\":([0-9.]+) ]]; then
                historical_prob="${BASH_REMATCH[1]}"
            fi
            if [[ "$hist_result" =~ \"similar_past_commands\":([0-9]+) ]]; then
                historical_count="${BASH_REMATCH[1]}"
            fi
        fi
    fi

    # Adjust based on historical data
    if [[ $historical_count -gt 0 ]]; then
        if [[ $historical_count -ge 10 ]]; then
            # Strong historical data
            probability=$historical_prob
            confidence="high"
            factors=("Based on $historical_count similar past executions")
        else
            # Weak historical data - blend with base
            probability=$(echo "scale=4; ($historical_prob * 0.6) + (0.85 * 0.4)" | bc 2>/dev/null || echo "0.85")
            confidence="medium"
            factors+=("Limited historical data: $historical_count samples")
        fi
    fi

    # Adjust based on risk
    local risk_score=0
    if [[ -n "${_MAINFRAME_RISK_LOADED:-}" ]] && declare -F mainframe_risk_assess &>/dev/null; then
        local risk_result
        risk_result=$(mainframe_risk_assess "$cmd" 2>/dev/null)
        if [[ "$risk_result" =~ \"score\":([0-9]+) ]]; then
            risk_score="${BASH_REMATCH[1]}"
        fi
    else
        # Simple risk check
        if [[ "$cmd" == *"rm -rf"* ]]; then
            risk_score=6
        elif [[ "$cmd" == *"sudo"* ]]; then
            risk_score=4
        fi
    fi

    # Higher risk = lower probability
    if [[ $risk_score -ge 8 ]]; then
        probability=$(echo "scale=4; $probability * 0.5" | bc 2>/dev/null || echo "0.5")
        factors+=("Critical risk level detected")
    elif [[ $risk_score -ge 6 ]]; then
        probability=$(echo "scale=4; $probability * 0.7" | bc 2>/dev/null || echo "0.7")
        factors+=("High risk level detected")
    elif [[ $risk_score -ge 3 ]]; then
        probability=$(echo "scale=4; $probability * 0.9" | bc 2>/dev/null || echo "0.9")
        factors+=("Medium risk level detected")
    fi

    # Check for common error patterns
    if [[ "$cmd" == *"|"* && "$cmd" != *"|"*"|"* ]]; then
        # Single pipe - check for missing input
        if [[ "$cmd" == "|"* ]]; then
            probability="0.1"
            factors+=("Command starts with pipe - missing input")
        fi
    fi

    if [[ "$cmd" == *">"* && "$cmd" == *"<"* ]]; then
        # Complex redirection - higher chance of error
        probability=$(echo "scale=4; $probability * 0.95" | bc 2>/dev/null || echo "$probability")
        factors+=("Complex redirection detected")
    fi

    # Unknown commands have lower success probability
    if [[ -z "${_PREDICT_PROFILES[$base_cmd]:-}" ]]; then
        probability=$(echo "scale=4; $probability * 0.8" | bc 2>/dev/null || echo "$probability")
        confidence="low"
        factors+=("Unknown command: limited profiling data")
    fi

    # Clamp probability to 0-1
    if [[ $(echo "$probability > 1" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        probability="1.0"
    elif [[ $(echo "$probability < 0" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        probability="0.0"
    fi

    # Build factors array
    local factors_json="["
    local first=true
    for factor in "${factors[@]}"; do
        $first || factors_json+=","
        first=false
        factors_json+="\"$(printf '%s' "$factor" | sed 's/"/\\"/g')\""
    done
    factors_json+="]"

    # Build JSON response
    local json="{"
    json+="\"command\":\"$(printf '%s' "$cmd" | sed 's/"/\\"/g')\","
    json+="\"probability\":$probability,"
    json+="\"confidence\":\"$confidence\","
    json+="\"factors\":$factors_json,"
    json+="\"historical_samples\":$historical_count"
    json+="}"

    output_success "$json" "success_prediction"
}

# Predict execution duration for a command
# Usage: predict_duration "$command"
# Returns: USOP JSON with predicted_seconds, min_seconds, max_seconds, confidence
predict_duration() {
    local cmd="$1"
    [[ -z "$cmd" ]] && {
        output_error "E_ARG_MISSING" "Command required for duration prediction"
        return 1
    }

    output_timer_start

    local base_cmd=$(_predict_base_cmd "$cmd")
    local predicted=1.0
    local confidence="medium"
    local based_on=0

    # Get profile base time
    local profile=$(_predict_get_profile "$cmd")
    profile=$(_predict_adjust_profile "$cmd" "$profile")

    if [[ "$profile" =~ \"time\":([0-9.]+) ]]; then
        predicted="${BASH_REMATCH[1]}"
    fi

    # Get historical data
    if [[ -n "${_MAINFRAME_TEMPORAL_LOADED:-}" ]]; then
        local hist_result
        hist_result=$(temporal_predict_duration "$cmd" 2>/dev/null)
        if [[ "$hist_result" == *'"predicted_ms"'* ]]; then
            local hist_ms=0
            local hist_stddev=0
            local hist_count=0

            if [[ "$hist_result" =~ \"predicted_ms\":([0-9.]+) ]]; then
                hist_ms="${BASH_REMATCH[1]}"
            fi
            if [[ "$hist_result" =~ \"stddev_ms\":([0-9.]+) ]]; then
                hist_stddev="${BASH_REMATCH[1]}"
            fi
            if [[ "$hist_result" =~ \"based_on\":([0-9]+) ]]; then
                hist_count="${BASH_REMATCH[1]}"
            fi

            if [[ $hist_count -gt 0 ]]; then
                local hist_sec
                hist_sec=$(echo "scale=3; $hist_ms / 1000" | bc 2>/dev/null || echo "0")
                hist_sec=${hist_sec%.*}

                if [[ $hist_count -ge 10 ]]; then
                    # Strong historical data - use it primarily
                    predicted=$hist_sec
                    confidence="high"
                elif [[ $hist_count -ge 3 ]]; then
                    # Blend historical with profile
                    predicted=$(echo "scale=3; ($hist_sec * 0.7) + ($predicted * 0.3)" | bc 2>/dev/null || echo "$predicted")
                    confidence="medium"
                else
                    # Weak data - slight adjustment
                    predicted=$(echo "scale=3; ($hist_sec * 0.4) + ($predicted * 0.6)" | bc 2>/dev/null || echo "$predicted")
                    confidence="low"
                fi

                based_on=$hist_count
            fi
        fi
    fi

    # If no historical data and unknown command, lower confidence
    if [[ $based_on -eq 0 && -z "${_PREDICT_PROFILES[$base_cmd]:-}" ]]; then
        confidence="low"
    fi

    # Calculate min/max based on confidence
    local min_val max_val
    case "$confidence" in
        high)
            min_val=$(echo "scale=3; $predicted * 0.8" | bc 2>/dev/null || echo "$predicted")
            max_val=$(echo "scale=3; $predicted * 1.2" | bc 2>/dev/null || echo "$predicted")
            ;;
        medium)
            min_val=$(echo "scale=3; $predicted * 0.5" | bc 2>/dev/null || echo "$predicted")
            max_val=$(echo "scale=3; $predicted * 2.0" | bc 2>/dev/null || echo "$predicted")
            ;;
        low)
            min_val=$(echo "scale=3; $predicted * 0.2" | bc 2>/dev/null || echo "$predicted")
            max_val=$(echo "scale=3; $predicted * 5.0" | bc 2>/dev/null || echo "$predicted")
            ;;
    esac

    # Ensure we have valid numbers
    min_val=${min_val:-$predicted}
    max_val=${max_val:-$predicted}

    # Format nicely (remove trailing zeros)
    predicted=$(echo "$predicted" | sed 's/0*$//;s/\.$//')
    min_val=$(echo "$min_val" | sed 's/0*$//;s/\.$//')
    max_val=$(echo "$max_val" | sed 's/0*$//;s/\.$//')

    # Build JSON response
    local json="{"
    json+="\"command\":\"$(printf '%s' "$cmd" | sed 's/"/\\"/g')\","
    json+="\"predicted_seconds\":$predicted,"
    json+="\"min_seconds\":$min_val,"
    json+="\"max_seconds\":$max_val,"
    json+="\"confidence\":\"$confidence\","
    json+="\"historical_samples\":$based_on"
    json+="}"

    output_success "$json" "duration_prediction"
}

# Run all predictions for a command
# Usage: predict_all "$command"
# Returns: USOP JSON with resources, risk, success, and duration predictions
predict_all() {
    local cmd="$1"
    [[ -z "$cmd" ]] && {
        output_error "E_ARG_MISSING" "Command required for prediction"
        return 1
    }

    output_timer_start

    # Run all predictions with raw output to get JSON data
    local old_mode="${MAINFRAME_OUTPUT:-raw}"
    MAINFRAME_OUTPUT=raw
    
    local resources risk success duration
    resources=$(predict_resources "$cmd" 2>/dev/null)
    risk=$(predict_risk "$cmd" 2>/dev/null)
    success=$(predict_success "$cmd" 2>/dev/null)
    duration=$(predict_duration "$cmd" 2>/dev/null)
    
    # Restore output mode
    MAINFRAME_OUTPUT="$old_mode"

    # Build combined JSON response
    local json="{"
    json+="\"command\":\"$(printf '%s' "$cmd" | sed 's/"/\\"/g')\","
    json+="\"resources\":$resources,"
    json+="\"risk\":$risk,"
    json+="\"success\":$success,"
    json+="\"duration\":$duration"
    json+="}"

    output_success "$json" "complete_prediction"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# Functions are available when library is sourced via source predict.sh
# No explicit export needed for bash library usage
#
# predict_resources "$command"  - Predict resource requirements
# predict_risk "$command"       - Assess risk level
# predict_success "$command"    - Predict success probability
# predict_duration "$command"   - Predict execution duration
# predict_all "$command"        - Run all predictions

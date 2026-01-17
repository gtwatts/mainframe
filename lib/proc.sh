#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/proc.sh - Process Management Library
# =============================================================================
# Description: Process queries, monitoring, discovery, PID files, locks
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PROC_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PROC_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Detect OS for platform-specific implementations
_proc_is_linux() {
    [[ "$OSTYPE" == linux* ]]
}

_proc_is_macos() {
    [[ "$OSTYPE" == darwin* ]]
}

# =============================================================================
# PROCESS QUERIES
# =============================================================================

# Check if PID exists
# Usage: proc_exists "pid"
# Returns: 0 if exists, 1 if not
proc_exists() {
    local pid="$1"

    [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && return 1

    if _proc_is_linux && [[ -d "/proc/$pid" ]]; then
        return 0
    fi

    # Fallback: kill -0 works on all platforms
    kill -0 "$pid" 2>/dev/null
}

# Get process name
# Usage: proc_name "pid"
# Returns: process name (e.g., "bash")
proc_name() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/comm" ]]; then
        cat "/proc/$pid/comm" 2>/dev/null
    elif _proc_is_macos; then
        ps -p "$pid" -o comm= 2>/dev/null | sed 's:.*/::'
    else
        ps -p "$pid" -o comm= 2>/dev/null
    fi
}

# Get full command line
# Usage: proc_cmd "pid"
# Returns: full command with arguments
proc_cmd() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/cmdline" ]]; then
        # cmdline has NUL separators
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | sed 's/ $//'
    else
        ps -p "$pid" -o args= 2>/dev/null
    fi
}

# Get parent PID
# Usage: proc_parent "pid"
# Returns: parent PID
proc_parent() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/stat" ]]; then
        # Field 4 in stat is PPID
        local stat
        stat=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
        # Handle process names with spaces/parens by removing the (name) part
        stat="${stat#*) }"
        echo "${stat}" | cut -d' ' -f2
    else
        ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' '
    fi
}

# Get child PIDs
# Usage: proc_children "pid"
# Returns: space-separated list of child PIDs
proc_children() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/task/$pid/children" ]]; then
        cat "/proc/$pid/task/$pid/children" 2>/dev/null
    else
        # Fallback using ps
        ps -o pid= --ppid "$pid" 2>/dev/null | tr -d ' ' | tr '\n' ' ' | sed 's/ $//'
    fi
}

# Get full process tree (recursive children)
# Usage: proc_tree "pid"
# Returns: newline-separated list of all descendant PIDs (including the original)
proc_tree() {
    local pid="$1"
    local children child

    proc_exists "$pid" || return 1

    printf '%s\n' "$pid"

    children=$(proc_children "$pid")
    for child in $children; do
        proc_tree "$child"
    done
}

# Get process owner (username)
# Usage: proc_user "pid"
# Returns: username of process owner
proc_user() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/status" ]]; then
        local uid
        uid=$(grep -m1 '^Uid:' "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
        [[ -n "$uid" ]] && getent passwd "$uid" 2>/dev/null | cut -d: -f1
    else
        ps -p "$pid" -o user= 2>/dev/null | tr -d ' '
    fi
}

# Get process start time
# Usage: proc_start_time "pid"
# Returns: start time in seconds since epoch
proc_start_time() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/stat" ]]; then
        # Field 22 in stat is starttime (in clock ticks since boot)
        local stat starttime_ticks
        stat=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
        stat="${stat#*) }"
        starttime_ticks=$(echo "$stat" | cut -d' ' -f20)

        # Get boot time from /proc/stat
        local boot_time hz
        boot_time=$(awk '/^btime/ {print $2}' /proc/stat 2>/dev/null)
        hz=$(getconf CLK_TCK 2>/dev/null || echo 100)

        if [[ -n "$boot_time" && -n "$starttime_ticks" ]]; then
            echo $((boot_time + starttime_ticks / hz))
        else
            return 1
        fi
    elif _proc_is_macos; then
        # macOS: use ps with lstart format, convert to epoch
        local lstart
        lstart=$(ps -p "$pid" -o lstart= 2>/dev/null) || return 1
        date -j -f "%a %b %d %T %Y" "$lstart" "+%s" 2>/dev/null
    else
        # Fallback: try ps etime and subtract from now
        local etime now
        etime=$(proc_runtime "$pid") || return 1
        now=$(date +%s)
        echo $((now - etime))
    fi
}

# Get process runtime in seconds
# Usage: proc_runtime "pid"
# Returns: seconds since process started
proc_runtime() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/stat" ]]; then
        local start_time now
        start_time=$(proc_start_time "$pid") || return 1
        now=$(date +%s)
        echo $((now - start_time))
    else
        # Parse etime format: [[DD-]HH:]MM:SS
        local etime
        etime=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ') || return 1

        local days=0 hours=0 minutes=0 seconds=0

        if [[ "$etime" == *-* ]]; then
            days="${etime%%-*}"
            etime="${etime#*-}"
        fi

        IFS=':' read -ra parts <<< "$etime"
        case ${#parts[@]} in
            3) hours="${parts[0]}"; minutes="${parts[1]}"; seconds="${parts[2]}" ;;
            2) minutes="${parts[0]}"; seconds="${parts[1]}" ;;
            1) seconds="${parts[0]}" ;;
        esac

        # Remove leading zeros to prevent octal interpretation
        days=$((10#$days))
        hours=$((10#$hours))
        minutes=$((10#$minutes))
        seconds=$((10#$seconds))

        echo $((days * 86400 + hours * 3600 + minutes * 60 + seconds))
    fi
}

# =============================================================================
# RESOURCE MONITORING
# =============================================================================

# Get memory usage in KB
# Usage: proc_memory "pid"
# Returns: resident set size in KB
proc_memory() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/status" ]]; then
        grep -m1 '^VmRSS:' "/proc/$pid/status" 2>/dev/null | awk '{print $2}'
    else
        # ps reports in KB on most systems
        ps -p "$pid" -o rss= 2>/dev/null | tr -d ' '
    fi
}

# Get memory as percentage of total
# Usage: proc_memory_percent "pid"
# Returns: memory usage as percentage (e.g., "2.5")
proc_memory_percent() {
    local pid="$1"

    proc_exists "$pid" || return 1

    ps -p "$pid" -o %mem= 2>/dev/null | tr -d ' '
}

# Get CPU percentage (snapshot)
# Usage: proc_cpu "pid"
# Returns: CPU percentage (e.g., "5.2")
proc_cpu() {
    local pid="$1"

    proc_exists "$pid" || return 1

    ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' '
}

# Get thread count
# Usage: proc_threads "pid"
# Returns: number of threads
proc_threads() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -f "/proc/$pid/status" ]]; then
        grep -m1 '^Threads:' "/proc/$pid/status" 2>/dev/null | awk '{print $2}'
    elif _proc_is_linux && [[ -d "/proc/$pid/task" ]]; then
        ls -1 "/proc/$pid/task" 2>/dev/null | wc -l
    else
        ps -p "$pid" -o nlwp= 2>/dev/null | tr -d ' ' || echo 1
    fi
}

# Get count of open file descriptors
# Usage: proc_open_files "pid"
# Returns: count of open FDs
proc_open_files() {
    local pid="$1"

    proc_exists "$pid" || return 1

    if _proc_is_linux && [[ -d "/proc/$pid/fd" ]]; then
        ls -1 "/proc/$pid/fd" 2>/dev/null | wc -l
    elif _proc_is_macos; then
        lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' '
    else
        lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' '
    fi
}

# =============================================================================
# PROCESS DISCOVERY
# =============================================================================

# Find PIDs by process name
# Usage: proc_find_by_name "nginx"
# Returns: newline-separated list of PIDs
proc_find_by_name() {
    local name="$1"

    [[ -z "$name" ]] && return 1

    if _proc_is_linux; then
        pgrep -x "$name" 2>/dev/null || pgrep "$name" 2>/dev/null
    else
        pgrep "$name" 2>/dev/null
    fi
}

# Find PID listening on port
# Usage: proc_find_by_port "8080"
# Returns: PID listening on the port
proc_find_by_port() {
    local port="$1"

    [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]] && return 1

    if _proc_is_linux; then
        # Try ss first (faster), then netstat, then lsof
        if command -v ss &>/dev/null; then
            ss -tlnp "sport = :$port" 2>/dev/null | \
                grep -oP 'pid=\K[0-9]+' | head -1
        elif command -v netstat &>/dev/null; then
            netstat -tlnp 2>/dev/null | grep ":$port " | \
                awk '{print $7}' | cut -d/ -f1 | head -1
        else
            lsof -i ":$port" -t 2>/dev/null | head -1
        fi
    else
        # macOS and others: use lsof
        lsof -i ":$port" -t 2>/dev/null | head -1
    fi
}

# Find PIDs owned by user
# Usage: proc_find_by_user "www-data"
# Returns: newline-separated list of PIDs
proc_find_by_user() {
    local user="$1"

    [[ -z "$user" ]] && return 1

    if _proc_is_linux; then
        pgrep -u "$user" 2>/dev/null
    else
        ps -u "$user" -o pid= 2>/dev/null | tr -d ' '
    fi
}

# Find PIDs matching command pattern
# Usage: proc_find_by_cmd "python.*server"
# Returns: newline-separated list of PIDs
proc_find_by_cmd() {
    local pattern="$1"

    [[ -z "$pattern" ]] && return 1

    if _proc_is_linux; then
        pgrep -f "$pattern" 2>/dev/null
    else
        # macOS pgrep also supports -f
        pgrep -f "$pattern" 2>/dev/null
    fi
}

# =============================================================================
# PID FILE MANAGEMENT
# =============================================================================

# Create PID file with current process PID
# Usage: pidfile_create "/var/run/myapp.pid"
# Returns: 0 on success, 1 on failure
pidfile_create() {
    local pidfile="$1"
    local pid="${2:-$$}"

    [[ -z "$pidfile" ]] && return 1

    # Ensure directory exists
    local dir
    dir=$(dirname "$pidfile")
    [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || return 1

    # Write PID atomically
    printf '%d\n' "$pid" > "$pidfile"
}

# Read PID from file
# Usage: pidfile_read "/var/run/myapp.pid"
# Returns: PID from file
pidfile_read() {
    local pidfile="$1"

    [[ -f "$pidfile" ]] || return 1

    local pid
    pid=$(cat "$pidfile" 2>/dev/null) || return 1

    # Validate it looks like a PID
    [[ "$pid" =~ ^[0-9]+$ ]] && printf '%d\n' "$pid"
}

# Check if PID file process is running
# Usage: pidfile_check "/var/run/myapp.pid"
# Returns: 0 if running, 1 if not
pidfile_check() {
    local pidfile="$1"
    local pid

    pid=$(pidfile_read "$pidfile") || return 1
    proc_exists "$pid"
}

# Remove PID file
# Usage: pidfile_remove "/var/run/myapp.pid"
pidfile_remove() {
    local pidfile="$1"

    [[ -f "$pidfile" ]] && rm -f "$pidfile"
}

# Kill process from PID file
# Usage: pidfile_kill "/var/run/myapp.pid" [signal]
# Returns: 0 if killed, 1 if not found/already dead
pidfile_kill() {
    local pidfile="$1"
    local signal="${2:-TERM}"
    local pid

    pid=$(pidfile_read "$pidfile") || return 1

    if proc_exists "$pid"; then
        kill "-$signal" "$pid" 2>/dev/null
        local result=$?
        [[ $result -eq 0 ]] && pidfile_remove "$pidfile"
        return $result
    fi

    # Process already dead, clean up stale pidfile
    pidfile_remove "$pidfile"
    return 1
}

# =============================================================================
# LOCK FILES
# =============================================================================

# Acquire lock (with optional timeout)
# Usage: lockfile_acquire "/tmp/myapp.lock" [timeout_secs]
# Returns: 0 if acquired, 1 if timeout/failure
lockfile_acquire() {
    local lockfile="$1"
    local timeout="${2:-0}"
    local start elapsed

    [[ -z "$lockfile" ]] && return 1

    start=$(date +%s)

    # Try flock if available (Linux)
    if command -v flock &>/dev/null; then
        local fd
        exec {fd}>"$lockfile"

        if [[ "$timeout" -eq 0 ]]; then
            flock -n "$fd" 2>/dev/null
        else
            flock -w "$timeout" "$fd" 2>/dev/null
        fi
        local result=$?

        if [[ $result -eq 0 ]]; then
            # Store FD for later release
            printf '%d\n' "$$" > "$lockfile"
            eval "_LOCKFILE_FD_${fd}='$lockfile'"
            return 0
        fi
        exec {fd}>&-
        return 1
    fi

    # Fallback: mkdir trick (atomic on all POSIX systems)
    local lockdir="${lockfile}.d"

    while true; do
        if mkdir "$lockdir" 2>/dev/null; then
            printf '%d\n' "$$" > "$lockfile"
            return 0
        fi

        # Check if holder is still alive
        if [[ -f "$lockfile" ]]; then
            local holder_pid
            holder_pid=$(cat "$lockfile" 2>/dev/null)
            if [[ -n "$holder_pid" ]] && ! proc_exists "$holder_pid"; then
                # Stale lock, try to remove
                rmdir "$lockdir" 2>/dev/null
                rm -f "$lockfile" 2>/dev/null
                continue
            fi
        fi

        # Check timeout
        if [[ "$timeout" -gt 0 ]]; then
            elapsed=$(($(date +%s) - start))
            if [[ $elapsed -ge $timeout ]]; then
                return 1
            fi
            sleep 0.1
        else
            return 1
        fi
    done
}

# Release lock
# Usage: lockfile_release "/tmp/myapp.lock"
lockfile_release() {
    local lockfile="$1"

    [[ -z "$lockfile" ]] && return 1

    # Remove mkdir-based lock
    local lockdir="${lockfile}.d"
    rmdir "$lockdir" 2>/dev/null
    rm -f "$lockfile" 2>/dev/null

    return 0
}

# Check if locked (without acquiring)
# Usage: lockfile_check "/tmp/myapp.lock"
# Returns: 0 if locked, 1 if not
lockfile_check() {
    local lockfile="$1"
    local lockdir="${lockfile}.d"

    # Check mkdir-based lock
    if [[ -d "$lockdir" ]]; then
        # Verify holder is still alive
        if [[ -f "$lockfile" ]]; then
            local holder_pid
            holder_pid=$(cat "$lockfile" 2>/dev/null)
            if [[ -n "$holder_pid" ]] && proc_exists "$holder_pid"; then
                return 0
            fi
        fi
    fi

    return 1
}

# Run command with lock
# Usage: with_lock "/tmp/myapp.lock" "command args"
# Returns: exit code of command, or 1 if lock failed
with_lock() {
    local lockfile="$1"
    local command="$2"
    local timeout="${3:-0}"

    if lockfile_acquire "$lockfile" "$timeout"; then
        eval "$command"
        local result=$?
        lockfile_release "$lockfile"
        return $result
    fi

    return 1
}

# =============================================================================
# SIGNAL HANDLING
# =============================================================================

# Send signal to process
# Usage: proc_signal "pid" "TERM"
# Returns: 0 on success, 1 on failure
proc_signal() {
    local pid="$1"
    local signal="${2:-TERM}"

    proc_exists "$pid" || return 1

    kill "-$signal" "$pid" 2>/dev/null
}

# Kill process (SIGTERM)
# Usage: proc_kill "pid"
proc_kill() {
    local pid="$1"
    proc_signal "$pid" "TERM"
}

# Force kill process (SIGKILL)
# Usage: proc_kill_force "pid"
proc_kill_force() {
    local pid="$1"
    proc_signal "$pid" "KILL"
}

# Kill process and all children
# Usage: proc_kill_tree "pid" [signal]
proc_kill_tree() {
    local pid="$1"
    local signal="${2:-TERM}"
    local pids child

    proc_exists "$pid" || return 1

    # Get all descendants first (before we start killing)
    pids=$(proc_tree "$pid")

    # Kill in reverse order (children first)
    for child in $(echo "$pids" | tac 2>/dev/null || tail -r 2>/dev/null || echo "$pids"); do
        kill "-$signal" "$child" 2>/dev/null || true
    done
}

# =============================================================================
# WAITING
# =============================================================================

# Wait for process to exit
# Usage: proc_wait "pid"
# Returns: exit code of process
proc_wait() {
    local pid="$1"

    if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Use wait if it's a child process
    wait "$pid" 2>/dev/null && return $?

    # For non-child processes, poll
    while proc_exists "$pid"; do
        sleep 0.1
    done

    return 0
}

# Wait for process to exit with timeout
# Usage: proc_wait_timeout "pid" "secs"
# Returns: 0 if exited, 124 if timeout
proc_wait_timeout() {
    local pid="$1"
    local timeout="$2"
    local start elapsed

    [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && return 1
    [[ -z "$timeout" || ! "$timeout" =~ ^[0-9]+$ ]] && timeout=30

    start=$(date +%s)

    while proc_exists "$pid"; do
        elapsed=$(($(date +%s) - start))
        if [[ $elapsed -ge $timeout ]]; then
            return 124
        fi
        sleep 0.1
    done

    return 0
}

# Wait for process to start
# Usage: proc_wait_start "name" [timeout]
# Returns: PID if started, 1 if timeout
proc_wait_start() {
    local name="$1"
    local timeout="${2:-30}"
    local start elapsed pid

    [[ -z "$name" ]] && return 1

    start=$(date +%s)

    while true; do
        pid=$(proc_find_by_name "$name" | head -1)
        if [[ -n "$pid" ]]; then
            printf '%d\n' "$pid"
            return 0
        fi

        elapsed=$(($(date +%s) - start))
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi

        sleep 0.1
    done
}

# =============================================================================
# SYSTEM INFO
# =============================================================================

# Get total running process count
# Usage: proc_count
proc_count() {
    if _proc_is_linux && [[ -d /proc ]]; then
        # Count directories that are numbers (PIDs)
        find /proc -maxdepth 1 -type d -regex '/proc/[0-9]+' 2>/dev/null | wc -l
    else
        ps aux 2>/dev/null | wc -l | tr -d ' '
    fi
}

# Get system load average
# Usage: proc_load
# Returns: 1/5/15 minute load averages
proc_load() {
    if _proc_is_linux && [[ -f /proc/loadavg ]]; then
        cut -d' ' -f1-3 /proc/loadavg 2>/dev/null
    elif _proc_is_macos; then
        sysctl -n vm.loadavg 2>/dev/null | tr -d '{}'
    else
        uptime 2>/dev/null | grep -oE 'load average[s]?: [0-9., ]+' | \
            sed 's/load average[s]*: //'
    fi
}

# Get system uptime in seconds
# Usage: proc_uptime
proc_uptime() {
    if _proc_is_linux && [[ -f /proc/uptime ]]; then
        cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1
    elif _proc_is_macos; then
        local boot_time now
        boot_time=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
        now=$(date +%s)
        echo $((now - boot_time))
    else
        # Fallback: parse uptime command
        local up
        up=$(uptime 2>/dev/null)
        # This is a rough approximation
        if [[ "$up" =~ ([0-9]+)\ days? ]]; then
            echo $((${BASH_REMATCH[1]} * 86400))
        elif [[ "$up" =~ ([0-9]+):([0-9]+) ]]; then
            echo $((${BASH_REMATCH[1]} * 3600 + ${BASH_REMATCH[2]} * 60))
        else
            return 1
        fi
    fi
}

# Get human readable uptime
# Usage: proc_uptime_human
# Returns: "5 days, 3 hours, 42 minutes"
proc_uptime_human() {
    local secs days hours mins

    secs=$(proc_uptime) || return 1

    days=$((secs / 86400))
    secs=$((secs % 86400))
    hours=$((secs / 3600))
    secs=$((secs % 3600))
    mins=$((secs / 60))
    secs=$((secs % 60))

    local result=""
    [[ $days -gt 0 ]] && result="${days} day$( [[ $days -ne 1 ]] && echo s ), "
    [[ $hours -gt 0 ]] && result="${result}${hours} hour$( [[ $hours -ne 1 ]] && echo s ), "
    [[ $mins -gt 0 ]] && result="${result}${mins} minute$( [[ $mins -ne 1 ]] && echo s )"

    # Remove trailing comma/space
    result="${result%, }"

    [[ -z "$result" ]] && result="${secs} second$( [[ $secs -ne 1 ]] && echo s )"

    printf '%s\n' "$result"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_PROC_EXPORTS=(
    # Process queries
    proc_exists
    proc_name
    proc_cmd
    proc_parent
    proc_children
    proc_tree
    proc_user
    proc_start_time
    proc_runtime
    # Resource monitoring
    proc_memory
    proc_memory_percent
    proc_cpu
    proc_threads
    proc_open_files
    # Process discovery
    proc_find_by_name
    proc_find_by_port
    proc_find_by_user
    proc_find_by_cmd
    # PID file management
    pidfile_create
    pidfile_read
    pidfile_check
    pidfile_remove
    pidfile_kill
    # Lock files
    lockfile_acquire
    lockfile_release
    lockfile_check
    with_lock
    # Signal handling
    proc_signal
    proc_kill
    proc_kill_force
    proc_kill_tree
    # Waiting
    proc_wait
    proc_wait_timeout
    proc_wait_start
    # System info
    proc_count
    proc_load
    proc_uptime
    proc_uptime_human
)
